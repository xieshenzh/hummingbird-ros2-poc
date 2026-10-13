#!/usr/bin/env bash
set -uo pipefail
DISK=$HOME/disk.raw
rm -f /tmp/ttyS0.sock
truncate -s 64M /tmp/varstore.img
echo ">>> launching qemu (aarch64, KVM) headless"
sudo qemu-system-aarch64 \
  -machine virt,accel=kvm,gic-version=max -cpu host -smp 4 -m 4096 \
  -drive if=pflash,format=raw,readonly=on,file=/tmp/code.fd \
  -drive if=pflash,format=raw,file=/tmp/varstore.img \
  -drive if=virtio,format=raw,file=$DISK \
  -display none -nic none \
  -chardev socket,id=ser0,path=/tmp/ttyS0.sock,server=on,wait=off \
  -serial chardev:ser0 &
QPID=$!
# wait for socket, then make it accessible to this user
for i in $(seq 1 30); do [ -S /tmp/ttyS0.sock ] && break; sleep 1; done
sudo chmod 666 /tmp/ttyS0.sock 2>/dev/null || true
echo ">>> driving serial (login as rt, assert PREEMPT_RT)"
RT_LOGIN_TIMEOUT=300 python3 ~/rt-serial-verify.py /tmp/ttyS0.sock ~/serial-fedora44-aarch64.txt
RC=$?
echo ">>> verify rc=$RC"
sudo kill $QPID 2>/dev/null || true
exit $RC
