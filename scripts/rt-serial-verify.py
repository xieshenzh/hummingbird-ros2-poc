#!/usr/bin/env python3
# Drive a booted bootc-os-rt VM over its qemu serial unix socket and capture the
# real-time proof — without SSH (AL2023's qemu lacks user-mode SLIRP net, and
# the login is scripted rather than interactive).
#
# WHY the serial socket: on a build box with no /dev/kvm (any non-.metal EC2)
# the VM boots under qemu TCG and there is no easy network in. Point qemu's
# serial at a unix socket and this script logs in + runs the checks over it:
#
#   qemu-system-x86_64 -accel tcg -m 4096 -smp 4 -machine q35 \
#     -drive if=pflash,format=raw,readonly=on,file=/usr/share/edk2/ovmf/OVMF_CODE.fd \
#     -drive if=pflash,format=raw,file=./OVMF_VARS.fd \
#     -drive file=disk.qcow2,format=qcow2,if=virtio \
#     -display none -monitor none \
#     -chardev socket,id=s0,path=/tmp/ttyS0.sock,server=on,wait=off -serial chardev:s0 &
#   sudo chmod 666 /tmp/ttyS0.sock
#   python3 rt-serial-verify.py /tmp/ttyS0.sock
#
# Uses the NON-secboot OVMF (our kernel-rt is unsigned). Credentials default to
# the demo user baked by bib-config.toml (rt / rtdemo123); override via env.
#
# Authoritative RT check = `uname -v` containing PREEMPT_RT (a kernel prints that
# only when CONFIG_PREEMPT_RT=y). NOTE: /sys/kernel/realtime is ABSENT on Fedora
# ark kernel-rt (it is a RHEL-kernel-rt-only sysfs patch) — do not rely on it.
import os, re, socket, sys, time

SOCK = sys.argv[1] if len(sys.argv) > 1 else "/tmp/ttyS0.sock"
RAW  = sys.argv[2] if len(sys.argv) > 2 else "serial-transcript.txt"
USER = os.environ.get("RT_USER", "rt")
PASS = os.environ.get("RT_PASS", "rtdemo123")
A, B = "RTPROOF_BEGIN", "RTPROOF_END"

s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
for _ in range(30):
    try: s.connect(SOCK); break
    except OSError: time.sleep(2)
else:
    print("could not connect to", SOCK); sys.exit(2)
s.setblocking(False)

buf = ""
def pump(t=1.0):
    global buf
    end = time.time() + t
    while time.time() < end:
        try:
            d = s.recv(4096)
            if d: buf += d.decode("utf-8", "replace")
            else: time.sleep(0.1)
        except (BlockingIOError, OSError): time.sleep(0.1)
def send(x): s.sendall(x.encode())
def wait_for(pat, timeout=180):
    end = time.time() + timeout
    while time.time() < end:
        pump(1.0)
        if re.search(pat, buf[-4000:]): return True
    return False

# clear any stray prompt, then reach a clean login prompt (TCG boot is slow)
send("\x03\n"); pump(2.0)
send("\n")
if not wait_for(r"login:", 240):
    open(RAW, "w").write(buf); print("NEVER SAW LOGIN"); print(buf[-600:]); sys.exit(3)
send(USER + "\n")
wait_for(r"[Pp]assword:", 30)
send(PASS + "\n")
time.sleep(4)

# run the proof; markers land ALONE on their own output lines
send("echo %s\n" % A)
send("uname -r; uname -v\n")
send("echo realtime_file=$(cat /sys/kernel/realtime 2>/dev/null || echo MISSING)\n")
send("cat /proc/cmdline\n")
send("echo %s\n" % B)
wait_for(r"(?m)^%s\r?$" % B, 40)
pump(2.0)
open(RAW, "w").write(buf)

# power off (the demo user is in wheel; feed the sudo password)
send("echo %s | sudo -S systemctl poweroff\n" % PASS)
pump(4.0)

m = re.search(r"(?m)^%s\r?\n(.*?)\r?\n%s\r?$" % (A, B), buf, re.S)
print("========== RT PROOF (from booted bootc-os-rt VM) ==========")
if m:
    for ln in m.group(1).splitlines():
        ln = ln.strip("\r\n ")
        if ln: print(ln)
    ok = "PREEMPT_RT" in m.group(1)
    print("--> %s" % ("PREEMPT_RT CONFIRMED" if ok else "PREEMPT_RT NOT FOUND"))
else:
    print("markers not found; see", RAW); print(buf[-1000:])
print("===========================================================")