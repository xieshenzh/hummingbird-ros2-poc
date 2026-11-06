#!/usr/bin/env python3
"""Interrupted-upgrade test.

Boot the disk at the current tag, start `bootc switch` to another tag, kill -9
the bootc process mid-transaction, and assert the system is unaffected:
power off, reboot, and the previously booted deployment must still come up
cleanly with PREEMPT_RT and a consistent bootc status.

Runs inside the Lima VM: /usr/bin/python3 (the kas venv lacks pexpect).
The helper exports the selected deployment's boot assets before each boot.
"""
import json
import os
import re
import subprocess
import sys
import pexpect

DISK = os.environ.get("CHUNKED_BOOTC_DISK", "/tmp/chunked-bootc-disk.img")
REG_GUEST = os.environ.get("CHUNKED_BOOTC_REGISTRY", "10.0.2.2:5000/generic-chunked-bootc")
CURRENT_TAG = sys.argv[1] if len(sys.argv) > 1 else "v2"
INTERRUPT_TAG = sys.argv[2] if len(sys.argv) > 2 else "v1"
INTERRUPT_DELAY = os.environ.get("CHUNKED_BOOTC_INTERRUPT_DELAY", "5")


def sh(cmd):
    return subprocess.run(cmd, shell=True, capture_output=True, text=True).stdout


def host_prepare(want_tag):
    """Loop-mount the disk rw, repair every deployment's `sysroot` entry
    (bootc-created deployments lack it; prepare-root then fails its
    physical-root bind), and export the
    want_tag deployment's kernel/initrd/kargs to /tmp/chunked-bootc-b-*.

    Must run before EVERY boot: an interrupted switch can leave a partial
    deployment as the boot default, and the boot layout may have been
    rewritten, invalidating previously exported kargs.
    """
    sh("sudo umount /mnt/chunked-bootc-target/boot/efi 2>/dev/null; sudo umount /mnt/chunked-bootc-target 2>/dev/null; sudo losetup -D")
    loop = sh("sudo losetup -Pf --show %s" % DISK).strip()
    sh("sudo mount %sp2 /mnt/chunked-bootc-target" % loop)
    sh("for d in /mnt/chunked-bootc-target/ostree/deploy/default/deploy/*/; do "
       "sudo chattr -i $d 2>/dev/null; "
       "sudo rm -f $d/sysroot; sudo mkdir -p $d/sysroot; done")
    best = None
    seen = set()
    for bls in sh("sudo ls /mnt/chunked-bootc-target/boot/loader*/entries/ostree-*.conf").split():
        opts = sh("sudo grep ^options %s | sed 's/^options //'" % bls).strip()
        m = re.search(r"ostree=/ostree/boot\.(\w+)/[^/]+/[^/]+/(\d+)", opts)
        if not m:
            continue
        target = sh("sudo readlink -f /mnt/chunked-bootc-target/ostree/boot.%s/default/*/%s"
                    % (m.group(1), m.group(2))).strip()
        if not target or target in seen:
            continue
        seen.add(target)
        origin = sh("sudo cat %s.origin 2>/dev/null" % target)
        if ":%s" % want_tag in origin:
            best = (bls, opts)
            break
    if best is None:
        raise RuntimeError("no deployment for %r found on disk" % want_tag)
    bls, opts = best

    def boot_path(p):
        p = p.lstrip("/")
        if not p.startswith("boot/"):
            p = "boot/" + p
        return "/mnt/chunked-bootc-target/" + p

    linux = boot_path(sh("sudo grep ^linux %s | sed 's/^linux //'" % bls).strip())
    initrd = boot_path(sh("sudo grep ^initrd %s | sed 's/^initrd //'" % bls).strip())
    if not os.path.exists(linux):
        d = sh("sudo ls -td /mnt/chunked-bootc-target/boot/ostree/*/ | head -1").strip()
        linux = sh("sudo ls %s/vmlinuz* | head -1" % d).strip()
        initrd = sh("sudo ls %s/initramfs* | head -1" % d).strip()
    sh("sudo cp %s /tmp/chunked-bootc-b-vmlinuz" % linux)
    sh("sudo cp %s /tmp/chunked-bootc-b-initramfs.img" % initrd)
    with open("/tmp/chunked-bootc-b-kargs", "w") as f:
        f.write(opts + " console=ttyAMA0\n")
    sh("sudo umount /mnt/chunked-bootc-target")
    sh("sudo losetup -d %s" % loop)
    print("prepared '%s' boot assets from %s" % (want_tag, os.path.basename(bls)))

QEMU = (
    "qemu-system-aarch64 -M virt -cpu cortex-a57 -smp 2 -m 2048 "
    "-nographic -no-reboot -nodefaults -serial stdio -monitor none "
    "-kernel {k} -initrd {i} -append '{a}' "
    "-drive file={d},format=raw,if=virtio "
    "-device virtio-net-pci,netdev=n0 -netdev user,id=n0"
)

failures = []


def boot_and_login(kernel, initrd, kargs):
    cmd = QEMU.format(k=kernel, i=initrd, a=kargs, d=DISK)
    child = pexpect.spawn("bash", ["-c", cmd], timeout=420, encoding="utf-8")
    child.logfile_read = sys.stdout
    child.expect(r"login:", timeout=420)
    child.sendline("root")
    child.expect(r"root@.*#")
    return child


def run(child, cmdline, timeout=180):
    """Run a command; return its output (file-backed, echo-proof sentinel)."""
    child.sendline("(%s) > /tmp/hbout 2>&1; echo HB$?DONE" % cmdline)
    child.expect(r"HB\d+DONE", timeout=timeout)
    child.sendline("cat /tmp/hbout; echo HB$?DONE")
    child.expect(r"HB\d+DONE", timeout=timeout)
    return child.before.split("HB$?DONE")[-1]


# ---- boot 1: interrupt a switch away from the current deployment ----
host_prepare(CURRENT_TAG)
child = boot_and_login("/tmp/chunked-bootc-b-vmlinuz", "/tmp/chunked-bootc-b-initramfs.img",
                       open("/tmp/chunked-bootc-b-kargs").read().strip())

out = run(child, "bootc status --json")
status = json.loads(out[out.index("{"):])
booted = status["status"]["booted"]["image"]["image"]["image"]
print("\nbooted before interrupt test: %s" % booted)
if CURRENT_TAG not in booted:
    failures.append("expected %s booted, got %s" % (CURRENT_TAG, booted))

# point at the guest-reachable registry.
# printf with single-quoted args: no quoting layer can strip the inner
# double quotes (a broken TOML here surfaces later as a confusing
# "invalid reference format" from the pull path)
out = run(child, "printf '%s\\n' '[registries.insecure]' "
                 "'registries = [\"10.0.2.2:5000\"]' > /etc/containers/registries.conf; "
                 "mkdir -p /var/lib/containers; cat /etc/containers/registries.conf")
print("\nregistries.conf:\n%s" % out.strip())

# Run the switch in the foreground and arm a background watcher that SIGKILLs
# it after INTERRUPT_DELAY seconds. Keeping the switch in the foreground is
# important: a backgrounded bootc switch can be interpreted as an invalid
# image-proxy invocation by the guest shell.
out = run(child, "(sleep %s; kill -9 $(pgrep -f 'bootc switch') 2>/dev/null; " % INTERRUPT_DELAY +
                  "echo WATCHER-FIRED) & "
                  "bootc switch %s:%s" % (REG_GUEST, INTERRUPT_TAG), timeout=180)
print("\n--- interrupted switch ---\n%s" % out.strip())

# the booted deployment must be untouched
out = run(child, "bootc status --json")
status = json.loads(out[out.index("{"):])
booted = status["status"]["booted"]["image"]["image"]["image"]
print("booted after kill: %s" % booted)
if CURRENT_TAG not in booted:
    failures.append("booted deployment changed after kill -9: %s" % booted)

child.sendline("systemctl poweroff || busybox poweroff")
child.expect(pexpect.EOF, timeout=120)

# ---- boot 2: same deployment must still boot cleanly ----
host_prepare(CURRENT_TAG)
child = boot_and_login("/tmp/chunked-bootc-b-vmlinuz", "/tmp/chunked-bootc-b-initramfs.img",
                       open("/tmp/chunked-bootc-b-kargs").read().strip())

out = run(child, "uname -v")
if "PREEMPT_RT" not in out:
    failures.append("kernel is not PREEMPT_RT after interrupted upgrade: %s" % out.strip())

out = run(child, "bootc status --json")
status = json.loads(out[out.index("{"):])
booted = status["status"]["booted"]["image"]["image"]["image"]
print("booted after reboot: %s" % booted)
if CURRENT_TAG not in booted:
    failures.append("reboot after kill -9 did not boot %s: %s" % (CURRENT_TAG, booted))

child.sendline("systemctl poweroff || busybox poweroff")
child.expect(pexpect.EOF, timeout=120)

if failures:
    print("\nFAIL:", "; ".join(failures))
    sys.exit(1)
print("\nPASS: kill -9 mid-bootc-switch left the booted deployment intact; reboot is clean")
