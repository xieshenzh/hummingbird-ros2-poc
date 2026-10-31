import glob, pexpect, sys

deploy = glob.glob("/home/xiezhang.guest/yocto/kas-work/build/tmp/deploy/images/qemuarm64/")[0]
qemu = glob.glob("/home/xiezhang.guest/yocto/kas-work/build/tmp/work/aarch64-linux/qemu-helper-native/1.0/recipe-sysroot-native/usr/bin/qemu-system-aarch64")[0]
kernel = deploy + "Image"
rootfs = deploy + "core-image-minimal-qemuarm64.rootfs.ext4"

cmd = (f"{qemu} -machine virt -cpu cortex-a57 -smp 4 -m 512 "
       f"-drive id=disk0,file={rootfs},if=none,format=raw -device virtio-blk-pci,drive=disk0 "
       f"-kernel {kernel} -append 'root=/dev/vda rw console=ttyAMA0' "
       f"-display none -serial stdio -monitor none -no-reboot")

log = open("/tmp/rtcheck.log", "w")
c = pexpect.spawn(cmd, timeout=300, encoding="utf-8")
c.logfile = log
try:
    c.expect("login:")
    c.sendline("root")
    i = c.expect(["Password:", r"[#] ?$"])
    if i == 0:
        c.sendline("")  # empty password
        c.expect(r"[#] ?$")
    c.sendline("uname -a && uname -v && echo RTCHECK-DONE")
    c.expect("RTCHECK-DONE")
    c.expect(r"[#] ?$")
    c.sendline("poweroff")
    c.expect(pexpect.EOF, timeout=120)
    print("RTCHECK: PASS")
except Exception as e:
    print("RTCHECK: FAIL:", e)
finally:
    log.close()
