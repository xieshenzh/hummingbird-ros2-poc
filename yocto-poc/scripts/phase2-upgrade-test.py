#!/usr/bin/env python3
"""Phase 2: bootc upgrade test on the deployed hb-bootc disk.

Flow:
  1. Boot the installed v2 disk under qemu TCG.
  2. Point the guest at the VM registry via the qemu user-net gateway
     (10.0.2.2:5000) and `bootc switch` to hb-bootc:v3 — a full
     pull + stage + deploy transaction.
  3. Power off; on the host, export the NEW deployment's kernel/initrd/kargs
     from the disk (we boot via qemu direct kernel, no bootloader).
  4. Boot again and assert: booted image is v3, rollback is v2,
     /etc/hb-version says v3, PREEMPT_RT still live.
  5. Print the ostree content diff between rollback and booted commits
     (the measured delta of the one-recipe bump).

Runs inside the Lima VM: /usr/bin/python3 (the kas venv lacks pexpect).
"""
import json
import os
import re
import subprocess
import sys
import pexpect

DISK = "/tmp/hb-disk.img"
REG_GUEST = "10.0.2.2:5000/hb-bootc"   # as seen from inside the guest
# usage: phase2-upgrade-test.py [from_tag] [to_tag]  (default v2 v3)
FROM_TAG = sys.argv[1] if len(sys.argv) > 1 else "v2"
NEW_TAG = sys.argv[2] if len(sys.argv) > 2 else "v3"

QEMU = (
    "qemu-system-aarch64 -M virt -cpu cortex-a57 -smp 2 -m 2048 "
    "-nographic -no-reboot -nodefaults -serial stdio -monitor none "
    "-kernel {k} -initrd {i} -append '{a}' "
    "-drive file={d},format=raw,if=virtio "
    "-device virtio-net-pci,netdev=n0 -netdev user,id=n0"
)

failures = []


def sh(cmd):
    return subprocess.run(cmd, shell=True, capture_output=True, text=True).stdout


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
    # child.before includes the echo of the `cat` command itself (which ends
    # with the literal "HB$?DONE"); drop everything up to and including it
    return child.before.split("HB$?DONE")[-1]


def export_boot_assets(prefix, want_tag=None):
    """Mount the disk on the host, export a deployment's kernel/initrd/kargs
    to /tmp/<prefix>-vmlinuz / -initramfs.img / -kargs.

    want_tag selects the deployment whose .origin references that image tag
    (e.g. "v2"/"v3"); None takes the first. Deploy-dir mtimes are NOT a
    usable selector — booting a deployment touches its dir.

    bootc switch writes a fresh boot layout (loader.0 — the Phase 1 install
    had used loader.1), which invalidates any previously exported kargs.
    Rather than trust dir names, resolve each BLS entry's
    ostree=/ostree/boot.N/default/<csum>/<idx> through the
    ostree/boot.N/default/<csum>/<idx> symlink to its deploy dir and match
    the adjacent .origin file.
    """
    sh("sudo umount /mnt/hb-target/boot/efi 2>/dev/null; sudo umount /mnt/hb-target 2>/dev/null; sudo losetup -D")
    loop = sh("sudo losetup -Pf --show %s" % DISK).strip()
    sh("sudo mount %sp2 /mnt/hb-target" % loop)
    # Phase 1 fixed the deployment `sysroot` entry at INSTALL time; bootc
    # switch creates fresh deployments with NO sysroot entry (or the absolute
    # /sysroot symlink), and prepare-root's physical-root bind then fails.
    # /sysroot is read-only in the running guest, so repair from the host
    # here, on the rw loop mount.
    fixed = sh("for d in /mnt/hb-target/ostree/deploy/default/deploy/*/; do "
               "sudo chattr -i $d 2>/dev/null; "
               "sudo rm -f $d/sysroot; sudo mkdir -p $d/sysroot; echo $d; done").split()
    print("sysroot repair on %d deployment(s)" % len(fixed))
    best = None  # (bls, opts)
    seen = set()
    for bls in sh("sudo ls /mnt/hb-target/boot/loader*/entries/ostree-*.conf").split():
        opts = sh("sudo grep ^options %s | sed 's/^options //'" % bls).strip()
        m = re.search(r"ostree=/ostree/boot\.(\w+)/[^/]+/[^/]+/(\d+)", opts)
        if not m:
            continue
        link = "/mnt/hb-target/ostree/boot.%s/default/*/%s" % (m.group(1), m.group(2))
        target = sh("sudo readlink -f %s" % link).strip()
        if not target or target in seen:
            continue
        seen.add(target)
        if want_tag:
            origin = sh("sudo cat %s.origin 2>/dev/null" % target)
            if ":%s" % want_tag not in origin:
                continue
        if best is None:
            best = (bls, opts)
            if not want_tag:
                break
    if best is None:
        raise RuntimeError("no BLS entry for want_tag=%r found on disk" % want_tag)
    bls, opts = best

    def boot_path(abs_or_rel):
        # BLS paths may be /boot-absolute or relative to the boot dir
        p = abs_or_rel.lstrip("/")
        if not p.startswith("boot/"):
            p = "boot/" + p
        return "/mnt/hb-target/" + p

    linux = boot_path(sh("sudo grep ^linux %s | sed 's/^linux //'" % bls).strip())
    initrd = boot_path(sh("sudo grep ^initrd %s | sed 's/^initrd //'" % bls).strip())
    if not os.path.exists(linux):
        # fall back to the newest kernel/initrd under /boot/ostree
        d = sh("sudo ls -td /mnt/hb-target/boot/ostree/*/ | head -1").strip()
        linux = sh("sudo ls %s/vmlinuz* | head -1" % d).strip()
        initrd = sh("sudo ls %s/initramfs* | head -1" % d).strip()
    sh("sudo cp %s /tmp/%s-vmlinuz" % (linux, prefix))
    sh("sudo cp %s /tmp/%s-initramfs.img" % (initrd, prefix))
    with open("/tmp/%s-kargs" % prefix, "w") as f:
        f.write(opts + " console=ttyAMA0\n")
    sh("sudo umount /mnt/hb-target")
    sh("sudo losetup -d %s" % loop)
    print("exported %r boot assets from %s:\n  kargs: %s" % (want_tag, os.path.basename(bls), opts))
    return "/tmp/%s-vmlinuz" % prefix, "/tmp/%s-initramfs.img" % prefix


# ---- boot 1: v2 -> switch to v3 ----
# export the CURRENT deployment's assets: a previous bootc switch may have
# rewritten the boot layout (boot.1 -> boot.0) and invalidated the
# install-time kargs
export_boot_assets("hb1", want_tag=FROM_TAG)
child = boot_and_login("/tmp/hb1-vmlinuz", "/tmp/hb1-initramfs.img",
                       open("/tmp/hb1-kargs").read().strip())

out = run(child, "bootc status --json")
before = json.loads(out[out.index("{"):])
booted_img = before["status"]["booted"]["image"]["image"]["image"]
print("\nbooted before switch: %s" % booted_img)
if FROM_TAG not in booted_img:
    failures.append("boot 1: expected %s booted, got %s" % (FROM_TAG, booted_img))

# the v2 image predates the 10.0.2.2 registries.conf entry — add it at
# runtime (deployment /etc is writable); bootc's pull also needs the
# containers storage dir to exist
run(child, "echo '[registries.insecure]' > /etc/containers/registries.conf; "
           "echo 'registries = [\"10.0.2.2:5000\"]' >> /etc/containers/registries.conf; "
           "mkdir -p /var/lib/containers")

out = run(child, "bootc switch %s:%s" % (REG_GUEST, NEW_TAG), timeout=600)
print("\n--- bootc switch ---\n%s" % out.strip())
# a non-fatal ERROR can appear in the pruning stage after successful
# staging ("Pruning: Listing images: ENOENT"); success is judged by the
# staged deployment below, not by absence of stderr

out = run(child, "bootc status --json")
after_switch = json.loads(out[out.index("{"):])
staged = after_switch["status"]["staged"]
print("staged after switch: %s" % (staged["image"]["image"]["image"] if staged else None))
if not staged or NEW_TAG not in staged["image"]["image"]["image"]:
    failures.append("no staged %s deployment after switch" % NEW_TAG)

child.sendline("poweroff")
child.expect(pexpect.EOF, timeout=120)

# ---- host: export the new deployment's boot assets ----
kernel, initrd = export_boot_assets("hb2", want_tag=NEW_TAG)

# ---- boot 2: verify v3 booted, v2 is rollback ----
child = boot_and_login(kernel, initrd, open("/tmp/hb2-kargs").read().strip())

out = run(child, "uname -v")
if "PREEMPT_RT" not in out:
    failures.append("kernel is not PREEMPT_RT after upgrade: %s" % out.strip())

out = run(child, "bootc status --json")
status = json.loads(out[out.index("{"):])
booted = status["status"]["booted"]
rollback = status["status"]["rollback"]
print("\nbooted after upgrade: %s" % booted["image"]["image"]["image"])
print("rollback:             %s" % (rollback["image"]["image"]["image"] if rollback else None))
if NEW_TAG not in booted["image"]["image"]["image"]:
    failures.append("booted image is not %s" % NEW_TAG)
if not rollback or FROM_TAG not in rollback["image"]["image"]["image"]:
    failures.append("rollback deployment is not %s" % FROM_TAG)

out = run(child, "cat /etc/hb-version")
print("/etc/hb-version: %s" % out.strip())
if out.strip() != NEW_TAG:
    failures.append("/etc/hb-version is %r, expected %r" % (out.strip(), NEW_TAG))

# measured delta: ostree content diff between rollback and booted commits
new_c = booted["ostree"]["checksum"]
old_c = rollback["ostree"]["checksum"] if rollback else None
if old_c:
    out = run(child, "ostree diff --repo=/sysroot/ostree/repo %s %s | head -n 40" % (old_c, new_c))
    print("\n--- ostree diff (rollback -> booted) ---\n%s" % out.strip())

child.sendline("poweroff")
child.expect(pexpect.EOF, timeout=120)

if failures:
    print("\nFAIL:", "; ".join(failures))
    sys.exit(1)
print("\nPASS: %s -> %s bootc switch upgraded transactionally; %s retained as rollback" % (FROM_TAG, NEW_TAG, FROM_TAG))
