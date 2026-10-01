# bootc-os-rt — bootc-os with a PREEMPT_RT kernel (POC)

A [`bootc-os`](https://gitlab.com/redhat/hummingbird/containers) image whose
stock Fedora kernel is swapped for a **PREEMPT_RT** (real-time) kernel, built
from the *same* pinned Fedora kernel SRPM the base already uses
(`kernel-7.1.8-100.fc43`) via the kernel spec's own `--with rtonly` flavor
toggle. No custom kernel packaging: the RT flavor is Fedora's own (the ark
lineage that also produces RHEL `kernel-rt` and AutoSD `kernel-automotive`).

The image stays a valid, bootable bootc image — it inherits `systemd`,
`/sbin/init`, the bootloader and `bootc` from the base; only the kernel, its
initramfs, and a `kargs.d` drop-in change.

**Status (BOTH arches, 2026-09-30): BUILT, lint-clean & BOOTED.** Built natively
(rootful podman, no qemu) — x86_64 on a `c7i`-class EC2 box, aarch64 on a
Graviton box. `bootc container lint` = 14 checks / 0 warnings; exactly one modules
dir (`7.1.8-100.fc43.<arch>+rt`) with `CONFIG_PREEMPT_RT=y`, initramfs regenerated
under `/usr/lib/modules`, `/boot` empty, RT kargs applied, stock kernel fully
removed. **Image size: x86_64 1.08 GB, aarch64 1.27 GB** (base + RT kernel).
**Booted** to a qcow2 under qemu TCG (x86_64 and aarch64) and confirmed the
running kernel is genuine PREEMPT_RT (see Verify → Boot). Note the aarch64 SRPM
emits TWO RT flavors (4k-page `aarch64+rt` + 64k-page `aarch64+rt-64k`, 16 RPMs);
the image installs the 4k `kernel-rt-core`+`kernel-rt-modules-core`.

⚠️ **Base version skew (2026-09-30):** these RT kernels are from the fc43 SRPM,
but `bootc-os:latest` has since moved to **fc44** (`7.2.7-200.fc44`, generic-only,
no RT) on both arches — so `bootc-os-rt` currently regresses the base kernel.
**Deferred to 2026-10-01:** rebuild kernel-rt from `kernel-7.2.7-200.fc44.src.rpm`
(`--with rtonly`) on both arches; see CLAUDE.md for the ROS-2-rebuild-only-if-ABI
analysis.
ROS 2 layers cleanly on top — `images/ros-core-rpms` with `--build-arg
BASE_IMAGE=…/bootc-os-rt:latest` yields `ros-core-rpms-rt` (RT kernel + ros-core,
1.56 GB), a real-time robot OS with ROS 2 in the immutable `/usr`.

## Why real-time?

Physical-AI / robotics workloads (motor control, sensor fusion, ROS 2 control
loops) need *bounded worst-case latency*, not just throughput. A PREEMPT_RT
kernel makes almost all kernel code preemptible, threads IRQ handlers, and uses
priority-inheriting mutexes so a high-priority control thread is not blocked
unboundedly by the kernel. This pairs directly with the ROS 2 images in this
repo (`ros-core-rpms`, etc.).

## Build

The `kernel-rt-*` RPMs are **not committed** (build artifacts — see
`.gitignore`). Produce and stage them first:

```bash
# 1. Build kernel-rt on a native x86_64 box (see repo scripts/rt-kernel-build.sh).
#    WITH_DEBUGINFO=1 for a production build; omit for a fast pass.
WITH_DEBUGINFO=1 ./scripts/rt-kernel-build.sh

# 2. Stage the two load-bearing RPMs (plus any deps) into ./rpms-rt/:
#    kernel-rt-core-*.rpm  kernel-rt-modules-core-*.rpm

# 3. Build the image on a MATCHING arch + Fedora release (native, no qemu):
podman build -t hummingbird-ros2-poc/bootc-os-rt:latest images/bootc-os-rt
```

Only `kernel-rt-core` + `kernel-rt-modules-core` are installed (the minimal set,
~58 MB, mirroring stock `kernel-core`+`kernel-modules-core`). The `kernel-rt`
*meta* package is intentionally NOT used — it is the only thing that
`Requires: realtime-setup`, which we don't need for the swap.

## What the Dockerfile does

1. `createrepo_c` a transient local repo from `rpms-rt/` (no Fedora repos: the
   RT kernel shares the stock kernel's runtime deps, already in the base).
2. `dnf install kernel-rt-core kernel-rt-modules-core` (image now has 2 kernels).
3. Remove the stock `kernel*` packages in one transaction (`--noautoremove`).
4. Drop any orphaned stock modules dir so exactly one `<ver>+rt` remains.
5. `dracut` a fresh initramfs for the `+rt` kver (inheriting the base's
   ostree + bootc dracut modules).
6. Remove the transient repo / RPMs / `createrepo_c`, clean caches.
7. Copy `kargs.d/10-realtime.toml` (RT boot args) and `bootc container lint`.

## Verify (after build)

```bash
# kernel is +rt and PREEMPT_RT
podman run --rm hummingbird-ros2-poc/bootc-os-rt:latest \
  bash -c 'ls /usr/lib/modules; grep CONFIG_PREEMPT_RT= /usr/lib/modules/*/config'
# still a valid bootc image (kernel, /sbin/init, bootc, kargs)
podman run --rm hummingbird-ros2-poc/bootc-os-rt:latest bootc container lint --no-truncate
```

### Boot (verified 2026-09-30, x86_64)

```bash
# 1. qcow2 (bootc-os declares no default rootfs, so pass --rootfs; the bib image
#    shipped mkfs.ext4 but not mkfs.xfs, hence ext4):
sudo podman run --rm --privileged --security-opt label=type:unconfined_t \
  -v /var/lib/containers/storage:/var/lib/containers/storage \
  -v $PWD/bib-out:/output -v $PWD/bib-config.toml:/config.toml:ro \
  quay.io/centos-bootc/bootc-image-builder:latest \
  --type qcow2 --rootfs ext4 localhost/hummingbird-ros2-poc/bootc-os-rt:latest

# 2. Boot under qemu. Our kernel-rt is UNSIGNED, so use the NON-secboot firmware.
#    x86_64:
qemu-system-x86_64 -accel kvm -m 4096 -smp 4 -machine q35 \
  -drive if=pflash,format=raw,readonly=on,file=/usr/share/edk2/ovmf/OVMF_CODE.fd \
  -drive if=pflash,format=raw,file=./OVMF_VARS.fd \
  -drive file=bib-out/qcow2/disk.qcow2,format=qcow2,if=virtio -nographic

#    aarch64 (no KVM off .metal → -accel tcg; aarch64 UEFI pflash, writable vars copy):
cp /usr/share/edk2/aarch64/vars-template-pflash.raw ./QEMU_VARS-rw.raw
qemu-system-aarch64 -machine virt -accel tcg -cpu max -m 4096 -smp 4 \
  -drive if=pflash,format=raw,readonly=on,file=/usr/share/edk2/aarch64/QEMU_EFI-pflash.raw \
  -drive if=pflash,format=raw,file=./QEMU_VARS-rw.raw \
  -drive file=bib-out/qcow2/disk.qcow2,format=qcow2,if=virtio -display none -monitor none \
  -chardev socket,id=s0,path=/tmp/ttyS0.sock,server=on,wait=off -serial chardev:s0
# then: python3 ../../scripts/rt-serial-verify.py /tmp/ttyS0.sock  (login over serial, no net)
```

In the booted VM the authoritative RT check is the kernel version string:

```bash
uname -v            # => #1 SMP PREEMPT_RT ...   (printed ONLY when CONFIG_PREEMPT_RT=y)
uname -r            # => 7.1.8-100.fc43.x86_64+rt
cat /proc/cmdline   # shows the RT kargs: preempt=full nowatchdog
```

⚠️ **Do NOT rely on `/sys/kernel/realtime`** — it is ABSENT on this Fedora ark
`kernel-rt` (that sysfs file is a RHEL-`kernel-rt`-only convenience patch, not
part of mainline/Fedora PREEMPT_RT). `uname -v` / the boot banner is the check.

For worst-case latency, `cyclictest -m -p95 -i200 -d0 -l100000` (from `rt-tests`,
which must be baked into the image) on a host with **KVM** (bare metal or an EC2
`.metal` instance). It was verified booted only under **qemu TCG** (this build
box had no `/dev/kvm`), which proves RT is live but gives no meaningful latency.

## Open items

- **Secure Boot:** this locally-built `kernel-rt` is **unsigned** by Fedora's
  key. It boots with Secure Boot disabled (verified via the non-secboot OVMF
  firmware); production needs signing (MOK enrollment or a Hummingbird signing
  key).
- **aarch64:** ✅ DONE 2026-09-30 — same SRPM + `--with rtonly`, built natively on
  a Graviton box, image built + BOOTED under qemu-system-aarch64 TCG, PREEMPT_RT
  confirmed live (`7.1.8-100.fc43.aarch64+rt`). Full parity with x86_64.
- **fc44 rebuild:** base moved fc43 → `7.2.7-200.fc44` mid-build (generic-only);
  rebuild kernel-rt from the fc44 SRPM on both arches (deferred 2026-10-01).
- **cyclictest latency:** boot was proven under qemu TCG (no KVM on the build
  box); real worst-case-latency numbers need a KVM/`.metal` host + `rt-tests`
  baked into the image.

## Productization: the `hummingbird/rt/` bootc-os variant

This POC injects local RPMs because the `kernel-rt` build is not yet in the
Hummingbird koji repo. Once it is published, the clean shape is a parallel
**variant** in the `containers` monorepo, alongside `hummingbird/default/`:

```
images/bootc-os/hummingbird/rt/
  Containerfile          # copy of default/, with the kernel swap below
  rpms/rpms.in.yaml      # + kernel-rt-core, kernel-rt-modules-core
  rpms/rpms.lock.yaml    # pins the kernel-rt NVR (via `pins`/regen)
  rootfs/usr/lib/bootc/kargs.d/10-realtime.toml
  TAGS / VERSION
```

The only functional change vs. `default/` is the `MAIN_PACKAGES` kernel entry:

```dockerfile
# default:  ... kernel ...
# rt:       ... kernel-rt-core kernel-rt-modules-core ...
ARG MAIN_PACKAGES="bootc bootupd ... kernel-rt-core kernel-rt-modules-core systemd dracut ..."
```

Everything else in `default/Containerfile` already generalizes: the dracut step
derives the kver from `ls ${NEWROOT}/usr/lib/modules/`, and `chunkah` isolates
the kernel into its own layer so an RT variant dedups cleanly against `default`.
The `rt/` variant would set `io.hummingbird-project.variant=rt` in its labels.