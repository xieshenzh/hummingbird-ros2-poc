#!/usr/bin/env bash
set -uo pipefail
rm -f /tmp/ttyS0.sock; truncate -s 64M /tmp/varstore.img
sudo qemu-system-aarch64 -machine virt,accel=kvm,gic-version=max -cpu host -smp 4 -m 4096 \
  -drive if=pflash,format=raw,readonly=on,file=/tmp/code.fd \
  -drive if=pflash,format=raw,file=/tmp/varstore.img \
  -drive if=virtio,format=raw,file=$HOME/disk.raw \
  -display none -nic none \
  -chardev socket,id=ser0,path=/tmp/ttyS0.sock,server=on,wait=off -serial chardev:ser0 &
QPID=$!
for i in $(seq 1 30); do [ -S /tmp/ttyS0.sock ] && break; sleep 1; done
sudo chmod 666 /tmp/ttyS0.sock 2>/dev/null || true
python3 ~/ros2-pubsub-serial.py
sudo kill $QPID 2>/dev/null || true
