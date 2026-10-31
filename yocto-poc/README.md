# Yocto → bootc PoC

**Goal:** prove that Yocto builds a Hummingbird-*shaped* bootc image from source
(a thin base: kernel + systemd + ostree + bootc), delivered via podman + chunka,
with the SWUpdate-derived upgrade test (delta size + rollback) on top.
Modeled on the classic SWUpdate zchunk-delta + bootcount-rollback example.

**It is NOT** a rebuild of the actual Hummingbird image (rawhide userspace +
ROS RPM closure). ROS 2 arrives later via meta-ros (source-built), never as
Fedora RPMs layered on poky (ABI-incompatible).

## Architecture

```
Lima VM (fedora, aarch64, 10 CPU / 24 GB) — everything native
  Yocto (kas, scarthgap LTS, MACHINE=qemuarm64)
    PREFERRED_PROVIDER_virtual/kernel = linux-yocto-rt   # full PREEMPT_RT
    → rootfs + kernel + initramfs
  podman: FROM scratch + ADD rootfs → bootc image → bootc container lint
  → local registry (registry:2) → chunka
  → qemu TCG boot → bootc upgrade v1→v2 → measure delta + rollback
```

Stack-vs-stack: this is the *source-built* sibling of the existing
`images/ros-*-rpms` (Fedora-binary) stack in this repo — see root CLAUDE.md.

## Phases

| Phase | Scope | Status |
|---|---|---|
| 0 | `core-image-minimal` + `linux-yocto-rt` for qemuarm64, boots under runqemu, `uname -v` shows PREEMPT_RT | ✅ done 2026-10-30 (`6.6.151-rt31 ... SMP PREEMPT_RT`) |
| 1 | bootc graft: ostree + bootc recipes, kernel at `/usr/lib/modules/$kver`, ostree-prepare-root in initramfs, BLS bootloader, podman wrap, `bootc container lint`, TCG boot | ✅ done 2026-10-31 — deployed disk boots under TCG, PREEMPT_RT live, `bootc status --json` reports `type: bootcHost` with the booted image (verified over two consecutive boots) |
| 1.5 | meta-ros Jazzy `ros_core` closure baked in (first full build on EC2 c8g) | ⬜ |
| 2 | upgrade test: v1/v2 via one-recipe bump, chunka both, local registry, predicted-vs-measured delta, `kill -9` mid-upgrade → assert rollback | ⬜ |

Phase 1 is the experimental frontier: no OE recipe exists for bootc (verified —
zero layer-index hits), and ostree-under-poky must be bridged via
`meta-updater`-era recipes. Expect the real effort here.

## Layout

```
kas/            kas manifests (phase0.yaml = minimal + RT kernel)
meta-hb-bootc/  our OE layer (Phase 1 recipes: bootc, ostree wiring, image)
scripts/
  vm-sync.sh    rsync this tree → fedora:~/yocto-poc (source of truth is here)
  vm-kas.sh     run kas inside the VM (build/tree in ~/yocto, VM-native fs)
docs/journal.md build journal — every phase, failure, root cause + fix
```

## Build (Phase 0)

```bash
scripts/vm-sync.sh                       # sync manifests to VM
scripts/vm-kas.sh build kas/phase0.yaml  # kas build (cold: ~1-2 h in VM)
# boot + verify RT:
limactl shell fedora -- bash -lc 'source ~/venvs/kas/bin/activate; \
  export KAS_WORK_DIR=$HOME/yocto/kas-work; cd ~/yocto-poc; \
  kas shell kas/phase0.yaml -c "runqemu qemuarm64 nographic"'
# login (root, no password) → uname -v   # expect ... PREEMPT_RT ...
```

Host-dep setup in the VM (once): see docs/journal.md.

## Phase 1 pipeline (Yocto → bootc container → installed system)

```bash
scripts/vm-sync.sh
scripts/vm-kas.sh build kas/phase1.yaml          # hb-bootc-image (RT + ostree + bootc)
# in the VM:
bash ~/yocto-poc/scripts/wrap-bootc-container.sh       # tarball → ostree-native OCI → localhost:5000
bash ~/yocto-poc/scripts/bootc-install-target.sh v1    # fresh GPT disk → bootc install to-filesystem
/usr/bin/python3 ~/yocto-poc/scripts/bootccheck-deployed.py  # qemu TCG boot, PREEMPT_RT + bootc status
                                            # (system python — the kas venv lacks pexpect)
```

The wrap and install scripts encode every bridge the minimal Yocto image
needs (usr/etc layout, /var/tmp, long-symlink, /ostree symlink, bootable
labels; host skopeo/podman/util-linux shims; bootupctl stub) — full
rationale in docs/journal.md.
