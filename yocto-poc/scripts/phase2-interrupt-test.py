#!/usr/bin/env python3
"""Phase 2b: interrupted-upgrade test.

Boot the (already v3-booted) disk, start `bootc switch` back to v2, kill -9
the bootc process mid-transaction, and assert the system is unaffected:
poweroff, reboot, and the previously-booted v3 deployment must still come up
cleanly with PREEMPT_RT and a consistent bootc status.

Runs inside the Lima VM: /usr/bin/python3 (the kas venv lacks pexpect).
Assumes /tmp/hb2-* boot assets (the v3 deployment's) exported by
phase2-upgrade-test.py.
"""
import json
import os
import re
import subprocess
import sys
import pexpect

DISK = "/tmp/hb-disk.img"
REG_GUEST = "10.0.2.2:5000/hb-bootc"


def sh(cmd):
    return subprocess.run(cmd, shell=True, capture_output=True, text=True).stdout


def host_prepare(want_tag):
    """Loop-mount the disk rw, repair every deployment's `sysroot` entry
    (bootc-created deployments lack it; prepare-root then fails its
    physical-root bind — see phase2-upgrade-test.py), and export the
    want_tag deployment's kernel/initrd/kargs to /tmp/hb2-*.

    Must run before EVERY boot: an interrupted switch can leave a partial
    deployment as the boot default, and the boot layout may have been
    rewritten, invalidating previously exported kargs.
    """
    sh("sudo umount /mnt/hb-target/boot/efi 2>/dev/null; sudo umount /mnt/hb-target 2>/dev/null; sudo losetup -D")
    loop = sh("sudo losetup -Pf --show %s" % DISK).strip()
    sh("sudo mount %sp2 /mnt/hb-target" % loop)
    sh("for d in /mnt/hb-target/ostree/deploy/default/deploy/*/; do "
       "sudo chattr -i $d 2>/dev/null; "
       "sudo rm -f $d/sysroot; sudo mkdir -p $d/sysroot; done")
    best = None
    seen = set()
    for bls in sh("sudo ls /mnt/hb-target/boot/loader*/entries/ostree-*.conf").split():
        opts = sh("sudo grep ^options %s | sed 's/^options //'" % bls).strip()
        m = re.search(r"ostree=/ostree/boot\.(\w+)/[^/]+/[^/]+/(\d+)", opts)
        if not m:
            continue
        target = sh("sudo readlink -f /mnt/hb-target/ostree/boot.%s/default/*/%s"
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
        return "/mnt/hb-target/" + p

    linux = boot_path(sh("sudo grep ^linux %s | sed 's/^linux //'" % bls).strip())
    initrd = boot_path(sh("sudo grep ^initrd %s | sed 's/^initrd //'" % bls).strip())
    if not os.path.exists(linux):
        d = sh("sudo ls -td /mnt/hb-target/boot/ostree/*/ | head -1").strip()
        linux = sh("sudo ls %s/vmlinuz* | head -1" % d).strip()
        initrd = sh("sudo ls %s/initramfs* | head -1" % d).strip()
    sh("sudo cp %s /tmp/hb2-vmlinuz" % linux)
    sh("sudo cp %s /tmp/hb2-initramfs.img" % initrd)
    with open("/tmp/hb2-kargs", "w") as f:
        f.write(opts + " console=ttyAMA0\n")
    sh("sudo umount /mnt/hb-target")
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


# ---- boot 1: v3, interrupt a switch to v2 ----
host_prepare("v3")
child = boot_and_login("/tmp/hb2-vmlinuz", "/tmp/hb2-initramfs.img",
                       open("/tmp/hb2-kargs").read().strip())

out = run(child, "bootc status --json")
status = json.loads(out[out.index("{"):])
booted = status["status"]["booted"]["image"]["image"]["image"]
print("\nbooted before interrupt test: %s" % booted)
if "v3" not in booted:
    failures.append("expected v3 booted, got %s" % booted)

# point at the guest-reachable registry.
# printf with single-quoted args: no quoting layer can strip the inner
# double quotes (a broken TOML here surfaces later as a confusing
# "invalid reference format" from the pull path)
out = run(child, "printf '%s\\n' '[registries.insecure]' "
                 "'registries = [\"10.0.2.2:5000\"]' > /etc/containers/registries.conf; "
                 "mkdir -p /var/lib/containers; cat /etc/containers/registries.conf")
print("\nregistries.conf:\n%s" % out.strip())

# run the switch in the FOREGROUND (a backgrounded `bootc switch` fails on
# its own with "invalid reference format" from the image proxy) and arm a
# background watcher that SIGKILLs it 5 s in. Switch to v1 — an image this
# disk has never pulled, so bootc must do a real ~80 MB fetch over qemu
# user-net (~9 s under TCG) and the kill lands mid-pull, not after a fast
# "No changes" staging
out = run(child, "(sleep 5; kill -9 $(pgrep -f 'bootc switch') 2>/dev/null; "
                 "echo WATCHER-FIRED) & "
                 "bootc switch %s:v1" % REG_GUEST, timeout=180)
print("\n--- interrupted switch ---\n%s" % out.strip())

# the booted deployment must be untouched
out = run(child, "bootc status --json")
status = json.loads(out[out.index("{"):])
booted = status["status"]["booted"]["image"]["image"]["image"]
print("booted after kill: %s" % booted)
if "v3" not in booted:
    failures.append("booted deployment changed after kill -9: %s" % booted)

child.sendline("poweroff")
child.expect(pexpect.EOF, timeout=120)

# ---- boot 2: same deployment must still boot cleanly ----
host_prepare("v3")
child = boot_and_login("/tmp/hb2-vmlinuz", "/tmp/hb2-initramfs.img",
                       open("/tmp/hb2-kargs").read().strip())

out = run(child, "uname -v")
if "PREEMPT_RT" not in out:
    failures.append("kernel is not PREEMPT_RT after interrupted upgrade: %s" % out.strip())

out = run(child, "bootc status --json")
status = json.loads(out[out.index("{"):])
booted = status["status"]["booted"]["image"]["image"]["image"]
print("booted after reboot: %s" % booted)
if "v3" not in booted:
    failures.append("reboot after kill -9 did not boot v3: %s" % booted)

child.sendline("poweroff")
child.expect(pexpect.EOF, timeout=120)

if failures:
    print("\nFAIL:", "; ".join(failures))
    sys.exit(1)
print("\nPASS: kill -9 mid-bootc-switch left the booted deployment intact; reboot is clean")
