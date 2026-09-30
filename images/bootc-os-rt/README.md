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

**Status (x86_64, 2026-09-30): BUILT & verified natively** on a `c7i`-class EC2
box (rootful podman, no qemu). `bootc container lint` = 14 checks / 0 warnings;
exactly one modules dir (`7.1.8-100.fc43.x86_64+rt`) with `CONFIG_PREEMPT_RT=y`,
initramfs regenerated under `/usr/lib/modules`, `/boot` empty, RT kargs applied,
stock kernel fully removed. **Image size 1.08 GB** (base bootc-os 909 MB + the
RT kernel ~170 MB). Not yet booted (see Open items).

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

To actually boot it and measure latency: convert to qcow2 with
`quay.io/centos-bootc/bootc-image-builder`, boot the VM, then
`uname -v` (should show `PREEMPT_RT`) and `cyclictest -m -p95 -i200 -d0 -l100000`
(from `rt-tests`) for the worst-case latency figure.

## Open items

- **Secure Boot:** this locally-built `kernel-rt` is **unsigned** by Fedora's
  key. It boots with Secure Boot disabled; production needs signing (MOK
  enrollment or a Hummingbird signing key).
- **aarch64:** same SRPM + `--with rtonly` on a native arm64 box; not yet built.

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