# base-switch PoC — EC2 aarch64 boot/verify helpers

Scripts used on an EC2 `c7g.metal` (Graviton, `/dev/kvm`) to boot and verify the
`fedora-bootc:44` ROS 2 + PREEMPT_RT image. See `docs/base-switch-poc.md`.

Why these exist: `quay.io/centos-bootc/bootc-image-builder:latest` is **amd64-only**
(no arm64 manifest), so bib can't run on a Graviton host. Instead the image installs
itself with `bootc install to-disk --via-loopback`, then qemu+KVM boots the raw disk
and a Python driver drives the serial console (no SSH into the guest).

Flow (run on the EC2 box, as ec2-user with rootful podman):
1. `podman load` the transferred `ros-core-rpms-rt:fedora44-aarch64` OCI archive.
2. Build `Containerfile.login` overlay (adds serial-login `rt`/root users + `realtime-tests`).
3. `bootc install to-disk --via-loopback --filesystem ext4 --generic-image --karg console=ttyAMA0 disk.raw`
4. Prep edk2 flash: `cp /usr/share/edk2/aarch64/QEMU_EFI.fd /tmp/code.fd; truncate -s 64M /tmp/code.fd /tmp/varstore.img`
5. Boot + verify:
   - `boot-verify.sh`  — boot under KVM, assert PREEMPT_RT (uses the repo's `rt-serial-verify.py`)
   - `boot-cyclic.sh`  + `cyclictest-serial.py`   — cyclictest latency
   - `boot-pubsub.sh`  + `ros2-pubsub-serial.py`  — ROS 2 Fast-DDS pub/sub round-trip
   - `ros2-verify-serial.py` — ros2 CLI introspection (pkg/topic list, logging)

Serial-driver gotchas: throttle per-char sends (getty duplicates chars on fast writes);
each `ros2` CLI call cold-starts Python (~2-3s) so use one continuous publisher;
pre-create `~/.ros/log`; pick end-markers that differ from the typed command (the shell
echoes the command, so `echo FOO` matches instantly — use `echo F""OO`).
