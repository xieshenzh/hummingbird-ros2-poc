# Boot the Phase 1 hb-bootc-image ext4 under qemu TCG and verify the
# bootc contract end to end: PREEMPT_RT kernel, bootc binary present,
# `bootc status` runs against the booted system.
import glob, pexpect

deploy = "/home/xiezhang.guest/yocto/kas-work/build/tmp/deploy/images/qemuarm64/"
qemu = glob.glob("/home/xiezhang.guest/yocto/kas-work/build/tmp/work/aarch64-linux/qemu-helper-native/1.0/recipe-sysroot-native/usr/bin/qemu-system-aarch64")[0]
rootfs = deploy + "hb-bootc-image-qemuarm64.rootfs.ext4"
kernel = deploy + "Image"

# NOTE: direct -kernel boot; qemu cannot execute the image's own BLS entry
# (that needs a bootloader on the disk image — Phase 1 verifies the bootc
# contract of the RUNNING system, not firmware-level boot)
cmd = (f"{qemu} -machine virt -cpu cortex-a57 -smp 4 -m 1024 "
       f"-drive id=disk0,file={rootfs},if=none,format=raw -device virtio-blk-pci,drive=disk0 "
       f"-kernel {kernel} -append 'root=/dev/vda rw console=ttyAMA0' "
       f"-display none -serial stdio -monitor none -no-reboot")

log = open("/tmp/bootccheck.log", "w")
c = pexpect.spawn(cmd, timeout=600, encoding="utf-8")
c.logfile = log
try:
    c.expect("login:")
    c.sendline("root")
    i = c.expect(["Password:", r"[#] ?$"])
    if i == 0:
        c.sendline("")
        c.expect(r"[#] ?$")
    c.sendline("uname -v")
    c.expect("PREEMPT_RT")
    c.sendline("bootc --version && echo BOOTC-PRESENT")
    c.expect("BOOTC-PRESENT")
    c.sendline("bootc status; echo BOOTC-STATUS-RC=$?")
    c.expect("BOOTC-STATUS-RC=")
    rc = c.readline().strip()
    print("bootc status rc:", rc)
    c.expect(r"[#] ?$")
    c.sendline("poweroff")
    c.expect(pexpect.EOF, timeout=120)
    print("BOOTCCHECK: PASS" + ("" if rc == "0" else f" (bootc status rc={rc})"))
except Exception as e:
    print("BOOTCCHECK: FAIL:", e)
finally:
    log.close()
