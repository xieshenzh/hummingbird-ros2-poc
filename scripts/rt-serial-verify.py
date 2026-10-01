#!/usr/bin/env python3
# Drive a booted bootc-os-rt VM over its qemu serial unix socket and capture the
# real-time proof — without SSH (AL2023's qemu lacks user-mode SLIRP net, and
# the login is scripted rather than interactive).
#
# WHY the serial socket: on a build box with no /dev/kvm (any non-.metal EC2)
# the VM boots under qemu TCG and there is no easy network in. Point qemu's
# serial at a unix socket and this script logs in + runs the checks over it.
#
#   # x86_64:
#   qemu-system-x86_64 -accel tcg -m 4096 -smp 4 -machine q35 \
#     -drive if=pflash,format=raw,readonly=on,file=/usr/share/edk2/ovmf/OVMF_CODE.fd \
#     -drive if=pflash,format=raw,file=./OVMF_VARS.fd \
#     -drive file=disk.qcow2,format=qcow2,if=virtio \
#     -display none -monitor none \
#     -chardev socket,id=s0,path=/tmp/ttyS0.sock,server=on,wait=off -serial chardev:s0 &
#   # aarch64 (TCG, non-secboot pflash, writable vars copy):
#   cp /usr/share/edk2/aarch64/vars-template-pflash.raw ./QEMU_VARS-rw.raw
#   qemu-system-aarch64 -machine virt -accel tcg,thread=multi -cpu max -m 4096 -smp 4 \
#     -drive if=pflash,format=raw,readonly=on,file=/usr/share/edk2/aarch64/QEMU_EFI-pflash.raw \
#     -drive if=pflash,format=raw,file=./QEMU_VARS-rw.raw \
#     -drive file=disk.qcow2,format=qcow2,if=virtio -display none -monitor none \
#     -chardev socket,id=s0,path=/tmp/ttyS0.sock,server=on,wait=off -serial chardev:s0 &
#   sudo chmod 666 /tmp/ttyS0.sock
#   python3 rt-serial-verify.py /tmp/ttyS0.sock
#
# Uses the NON-secboot firmware (our kernel-rt is unsigned). Credentials default
# to the demo user baked by bib-config.toml (rt / rtdemo123); override via env.
#
# Authoritative RT check = `uname -v` / the boot banner containing PREEMPT_RT (a
# kernel prints that only when CONFIG_PREEMPT_RT=y). NOTE: /sys/kernel/realtime is
# ABSENT on Fedora ark kernel-rt (a RHEL-kernel-rt-only sysfs patch) — do not use.
#
# Fixes over the first version (both hit on the fc44 aarch64 boot, 2026-10-01):
#  1. FRESH UEFI vars land at the edk2 boot-device menu, which needs Enter (\r,
#     NOT \n) to boot. We now send \r bursts throughout the login wait — this both
#     dismisses the menu and re-triggers getty's `login:` prompt.
#  2. fc43/fc44 bash emits OSC-3008 shell-integration escapes that pollute the
#     marker lines, so the PREEMPT_RT regex missed them. We now strip ANSI/OSC
#     escape sequences before matching.
import os, re, socket, sys, time

SOCK = sys.argv[1] if len(sys.argv) > 1 else "/tmp/ttyS0.sock"
RAW  = sys.argv[2] if len(sys.argv) > 2 else "serial-transcript.txt"
USER = os.environ.get("RT_USER", "rt")
PASS = os.environ.get("RT_PASS", "rtdemo123")
LOGIN_TIMEOUT = int(os.environ.get("RT_LOGIN_TIMEOUT", "900"))  # TCG is slow
A, B = "RTPROOF_BEGIN", "RTPROOF_END"

# OSC (ESC ] ... BEL/ST), CSI (ESC [ ...), and other 2-char escape sequences.
_ESC = re.compile(r"\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)|\x1b\[[0-9;?]*[ -/]*[@-~]|\x1b[@-Z\\-_]")
def strip_esc(x): return _ESC.sub("", x)

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
        if re.search(pat, strip_esc(buf[-4000:])): return True
    return False

# Phase 1: get past the (possibly fresh-vars) UEFI boot menu and reach `login:`.
# Send \r periodically: boots the highlighted edk2 entry AND pokes getty.
send("\x03"); pump(1.0)
deadline = time.time() + LOGIN_TIMEOUT
last_poke = 0.0
last_flush = 0.0
seen_login = False
while time.time() < deadline:
    pump(2.0)
    if re.search(r"login:", strip_esc(buf[-4000:])):
        seen_login = True; break
    if time.time() - last_poke > 12:
        send("\r"); last_poke = time.time()
    # flush the transcript periodically so the boot can be monitored live
    # (the socket is single-client, so this file is the only progress window)
    if time.time() - last_flush > 15:
        try: open(RAW, "w").write(buf)
        except OSError: pass
        last_flush = time.time()
if not seen_login:
    open(RAW, "w").write(buf)
    # the kernel banner may still prove RT even if login never came up
    banner = "PREEMPT_RT" in strip_esc(buf)
    print("NEVER SAW LOGIN (banner PREEMPT_RT=%s); see %s" % (banner, RAW))
    print(strip_esc(buf)[-800:]); sys.exit(0 if banner else 3)

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
wait_for(r"(?m)^%s\r?$" % B, 60)
pump(2.0)
open(RAW, "w").write(buf)

# power off (the demo user is in wheel; feed the sudo password)
send("echo %s | sudo -S systemctl poweroff\n" % PASS)
pump(4.0)

clean = strip_esc(buf)
m = re.search(r"(?m)^%s\r?\n(.*?)\r?\n%s\r?$" % (A, B), clean, re.S)
print("========== RT PROOF (from booted bootc-os-rt VM) ==========")
if m:
    for ln in m.group(1).splitlines():
        ln = ln.strip("\r\n ")
        if ln: print(ln)
    ok = "PREEMPT_RT" in m.group(1)
else:
    # markers lost to escapes/line-wrapping — fall back to the whole transcript
    ok = "PREEMPT_RT" in clean
    print("(markers not cleanly matched; scanned full transcript, see %s)" % RAW)
    for ln in clean.splitlines():
        if "PREEMPT_RT" in ln or ln.strip().startswith("7.") or "cmdline" in ln.lower():
            print(ln.strip())
print("--> %s" % ("PREEMPT_RT CONFIRMED" if ok else "PREEMPT_RT NOT FOUND"))
print("===========================================================")
sys.exit(0 if ok else 4)
