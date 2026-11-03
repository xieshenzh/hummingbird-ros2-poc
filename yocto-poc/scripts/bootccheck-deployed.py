#!/usr/bin/env python3
"""Boot the bootc-installed hb-disk.img under qemu TCG and verify the
deployment: PREEMPT_RT live + `bootc status` reports a real bootc deployment
(not "not deployed via bootc").

Runs inside the Lima VM (qemu-system-aarch64). Kernel/initrd are passed
directly (qemu cannot execute BLS entries); kargs mirror the installed
ostree-1.conf (exported to /tmp/hb-kargs by bootc-install-target.sh).
"""
import sys
import pexpect

DISK = sys.argv[1] if len(sys.argv) > 1 else "/tmp/hb-disk.img"
KERNEL = sys.argv[2] if len(sys.argv) > 2 else "/tmp/hb-vmlinuz"
INITRD = sys.argv[3] if len(sys.argv) > 3 else "/tmp/hb-initramfs.img"
KARGS = (
    sys.argv[4] if len(sys.argv) > 4
    else open("/tmp/hb-kargs").read().strip() + " console=ttyAMA0"
)

cmd = (
    "qemu-system-aarch64 -M virt -cpu cortex-a57 -smp 2 -m 2048 "
    "-nographic -no-reboot -nodefaults "
    "-serial stdio -monitor none "
    "-kernel {k} -initrd {i} -append '{a}' "
    "-drive file={d},format=raw,if=virtio "
    "-device virtio-net-pci,netdev=n0 -netdev user,id=n0"
).format(k=KERNEL, i=INITRD, a=KARGS, d=DISK)

failures = []
child = pexpect.spawn("bash", ["-c", cmd], timeout=420, encoding="utf-8")
child.logfile_read = sys.stdout


def run(cmdline, timeout=120):
    """Run a command at the shell prompt; return its output.

    Output goes to a file and is catted back before a sentinel that the
    tty echo can't fake: the echoed line shows `HB$?DONE` literally, only
    the executed marker matches HB<digits>DONE.
    """
    child.sendline("(%s) > /tmp/hbout 2>&1; echo HB$?DONE" % cmdline)
    child.expect(r"HB\d+DONE", timeout=timeout)
    child.sendline("cat /tmp/hbout; echo HB$?DONE")
    child.expect(r"HB\d+DONE", timeout=timeout)
    return child.before


try:
    child.expect(r"login:", timeout=420)
    child.sendline("root")
    child.expect(r"root@.*#")

    out = run("uname -v")
    if "PREEMPT_RT" not in out:
        failures.append("kernel is not PREEMPT_RT: %s" % out.strip())

    out = run("ls /run/ostree-booted && cat /proc/cmdline")
    print("--- ostree-booted marker ---\n%s" % out.strip())

    out = run("bootc status")
    if "not deployed via bootc" in out:
        failures.append("bootc status: still 'not deployed via bootc'")
    if "type: bootcHost" not in out:
        failures.append("bootc status: type is not bootcHost")
    print("\n--- bootc status ---\n%s\n--------------------" % out.strip())

    out = run("bootc status --json")
    if '"booted":' not in out.replace(" ", ""):
        failures.append("bootc status --json: no booted deployment")
    if '"type":"bootcHost"' not in out.replace(" ", ""):
        failures.append("bootc status --json: type is not bootcHost")
    print("--- bootc status --json ---\n%s" % out.strip())
    # ROS closure (Phase 1.5b images): source the workspace and run the CLI.
    # Skipped for the pre-ROS minimal image.
    out = run("test -d /opt/ros/jazzy && echo HB-HAS-ROS || true")
    if "HB-HAS-ROS" in out:
        out = run(". /opt/ros/jazzy/setup.sh && ros2 --help >/dev/null && "
                  "echo HB-ROS2-OK; ros2 pkg list | wc -l", timeout=180)
        if "HB-ROS2-OK" not in out:
            failures.append("ros2 CLI failed under /opt/ros/jazzy: %s" % out.strip())
        else:
            print("\n--- ros2 ---\n%s" % out.strip())
    else:
        print("\n(no /opt/ros/jazzy — minimal image, ROS checks skipped)")

finally:
    child.close()

if failures:
    print("FAIL:", "; ".join(failures))
    sys.exit(1)
print("PASS: deployed bootc image booted, PREEMPT_RT live, bootc reports deployment")
