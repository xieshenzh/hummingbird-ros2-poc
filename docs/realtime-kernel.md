# Real-time (PREEMPT_RT) kernel — `images/bootc-os-rt`

> Detail doc for [`../CLAUDE.md`](../CLAUDE.md). Build/verify mechanics and the
> productization mapping live in
> [`../images/bootc-os-rt/README.md`](../images/bootc-os-rt/README.md); this doc
> is the status log.

Robotics/physical-AI needs bounded worst-case latency, so bootc-os needs a
PREEMPT_RT kernel option. **No custom kernel packaging is required**: the Fedora
kernel SRPM bootc-os pins ships the full RT flavor (the ark lineage that also
yields RHEL `kernel-rt` / AutoSD `kernel-automotive`). The RT kernel = rebuild
that SAME SRPM with the spec's own `--with rtonly` toggle
(`scripts/rt-kernel-build.sh`; `BUILDER` must match the SRPM's Fedora release,
`WITH_DEBUGINFO=1` for production).

## Status matrix

| Release | arch | kernel-rt built | image built | booted + RT confirmed | ROS-on-RT |
|---|---|---|---|---|---|
| fc43 | x86_64 | ✅ 2026-09-30 | ✅ 1.08 GB | ✅ TCG | ✅ 1.56 GB |
| fc43 | aarch64 | ✅ 2026-09-30 | ✅ 1.27 GB | ✅ TCG | ✅ 1.71 GB (rechunked 1.25) |
| fc44 | aarch64 | ✅ 2026-10-01 | ✅ 1.53 GB | ✅ TCG (full boot → login → `uname`) | ✅ 1.97 GB |
| fc44 | x86_64 | ✅ 2026-10-01 | ✅ 1.06 GB | ✅ TCG (banner + RT kargs) | ✅ 1.54 GB |

The authoritative live RT check is **`uname -v | grep PREEMPT_RT`** (printed only
when `CONFIG_PREEMPT_RT=y`). ⚠️ `/sys/kernel/realtime` is ABSENT on Fedora ark
`kernel-rt` (RHEL-only convenience patch) — do NOT use it here.

## fc43 — DONE & BOOTED on BOTH arches (2026-09-30)

- **kernel-rt (x86_64)** on a native `c7i`-class EC2 box (16 vCPU / 30 GB,
  AL2023, rootful podman + fedora:43), `rpmbuild --rebuild --with rtonly` — fast
  pass (`--without debuginfo`) ~29 min. Shipped config `CONFIG_PREEMPT_RT=y`;
  uname flavor `7.1.8-100.fc43.x86_64+rt`.
  - Subpackages: `kernel-rt` (meta), `kernel-rt-core` (19 MB),
    `kernel-rt-modules-core` (41 MB), `-modules`, `-modules-extra`,
    `-modules-internal`, `kernel-rt-devel` (48 MB), `-matched` stubs.
  - `Requires: realtime-setup` is on the `kernel-rt` META only — NOT on
    `kernel-rt-core`/`-modules-core`. So the minimal bootc install set =
    `kernel-rt-core` + `kernel-rt-modules-core` (~58 MB), needs no realtime-setup.
- **kernel-rt (aarch64)** NATIVELY on a Graviton EC2 box (no qemu), same SRPM +
  script → **16 `kernel-rt-*` RPMs** — the aarch64 SRPM emits TWO flavors, the
  standard 4k-page `aarch64+rt` AND a 64k-page `aarch64+rt-64k` (8 subpkgs each).
  The image install set is the **4k** `kernel-rt-core` + `kernel-rt-modules-core`.
- **The image** (`images/bootc-os-rt/Dockerfile`): `FROM bootc-os`, inject local
  kernel-rt RPMs, swap stock `kernel*` → `kernel-rt-core` +
  `kernel-rt-modules-core`, regen initramfs for the `+rt` kver, add RT kargs.d,
  `bootc container lint`. Stays bootable. No Fedora repos added (RT kernel shares
  the stock kernel's runtime deps). **lint 14/0 (x86_64), 14/1 (aarch64).**
- **BOOTED & RT confirmed live (both arches).** `bootc-image-builder` → qcow2
  (`--rootfs ext4`; bootc-os declares no default rootfs, and the bib image lacked
  `mkfs.xfs`), booted under **qemu TCG** (the build boxes had NO `/dev/kvm`; only
  `.metal` exposes it; AL2023 qemu also lacks user-mode SLIRP net, so login was
  driven over a serial unix socket by `scripts/rt-serial-verify.py`). Proof:
  - x86_64 banner `Linux version 7.1.8-100.fc43.x86_64+rt … #1 SMP PREEMPT_RT`;
    `uname -v` = `#1 SMP PREEMPT_RT`; kernel cmdline shows `preempt=full
    nowatchdog` (from `kargs.d/10-realtime.toml`).
  - aarch64 `uname -r` = `7.1.8-100.fc43.aarch64+rt`, `uname -v` =
    `#1 SMP PREEMPT_RT`, cmdline has the RT kargs, powered off cleanly.
    ⚠️ The transcript regex missed the markers (fc43 bash emits OSC-3008
    shell-integration escapes that pollute the marker lines) — read the raw
    transcript for the proof; a future `rt-serial-verify.py` tweak could strip
    `\x1b]...` OSC sequences before matching.
- **ROS 2 on the RT base.** `images/ros-core-rpms` takes `--build-arg
  BASE_IMAGE`, so ROS 2 Jazzy layers straight onto `bootc-os-rt`. Result ships
  BOTH the `+rt` kernel AND ros-core (150 pkgs, `ros2` CLI); aarch64 default Fast
  DDS pub/sub round-trips. lint 14/1.

## fc44 — kernel-rt + images BUILT on aarch64 (2026-10-01)

Done NATIVELY on a Graviton EC2 box. Rebuilt kernel-rt from
`kernel-7.2.7-200.fc44.src.rpm` (`--with rtonly`, `BUILDER=fedora:44`) → **18
`kernel-rt-*` RPMs** (4k `aarch64+rt` + 64k `aarch64+rt-64k`), `CONFIG_PREEMPT_RT=y`,
flavor `7.2.7-200.fc44.aarch64+rt`.

- `bootc-os-rt:fc44` — **1.53 GB**, lint 14/1.
- `ros-core-rpms-rt:fc44` — **1.97 GB** (155 ROS pkgs, `ros2` CLI, Fast DDS
  round-trips). Confirms the fc43-built ROS RPMs are fc44-compatible (no rebuild).
- **BOOTED & RT confirmed live (2026-10-01).** On a 2nd Graviton EC2 box the
  `bootc-os-rt:fc44` base qcow2 (918 MB, `--rootfs ext4`) was booted under **qemu
  aarch64 TCG** (no `/dev/kvm`). RT proven at **three** levels, all under TCG:
  1. **Kernel banner + cmdline** (`artifacts/serial-transcript-fc44-aarch64.txt`):
     banner `Linux version 7.2.7-200.fc44.aarch64+rt … #1 SMP PREEMPT_RT`
     (`CONFIG_PREEMPT_RT=y` — the authoritative RT check); kernel cmdline booted
     `vmlinuz-7.2.7-200.fc44.aarch64+rt` with the RT kargs applied at deploy
     (`preempt=full nowatchdog`, from `kargs.d/10-realtime.toml`).
  2. **Userspace-executed `uname`** (`artifacts/serial-transcript-fc44-aarch64-userspace.txt`)
     — `uname` run from a live userspace process on the booted RT kernel:
     `uname -r` = `7.2.7-200.fc44.aarch64+rt`, `uname -v` = `#1 SMP PREEMPT_RT …`.
  3. **Full clean boot → interactive getty login → `uname`**
     (`artifacts/serial-transcript-fc44-aarch64-login.txt`) — the complete
     **x86_64-parity** proof (same as fc43: boot to `login:` over serial, log in,
     run `uname`). Reached `multi-user.target`, `localhost login: rt` →
     `[rt@localhost ~]$`, then interactively:
     - `uname -r` = `7.2.7-200.fc44.aarch64+rt`
     - `uname -v` = `#1 SMP PREEMPT_RT Thu Oct  1 02:42:48 UTC 2026`
     - `/proc/cmdline` = `… preempt=full nowatchdog … console=ttyAMA0`
     - (`/sys/kernel/realtime` = MISSING — expected on Fedora ark kernel-rt.)
  - **No KVM/`.metal` was needed for any of these** (the earlier "retry on KVM"
    note was wrong). KVM/`.metal` is required ONLY for meaningful `cyclictest`
    latency (TCG timing is noise).
  - **The `/boot` → emergency-mode quirk and its fix (root cause, 2026-10-01):**
    before the fix, the bib qcow2 dropped to **emergency mode** under TCG —
    `boot.mount` (`/boot`)'s **device dependency timed out** (slow aarch64-TCG udev
    exceeds systemd's default 90 s device-timeout; the by-UUID device for `/boot`
    appears too late) → `local-fs.target` fails → `emergency.target` +
    `Press Enter to continue.`. x86_64 TCG is faster so it never hit this. **Not**
    an RT/arch/KVM defect and **not** a wrong fstab (the `/boot` UUID matched).
    **Fix:** make `/boot` non-fatal + patient — edit the deploy's `/etc/fstab` to
    `UUID=… /boot auto ro,nofail,x-systemd.device-timeout=10min 0 0`. With `nofail`
    the slow mount no longer fails `local-fs.target`, so the boot proceeds to
    `multi-user.target` and getty. (This is a TCG **verification aid only** —
    applied in-place to the throwaway test qcow2's deploy fstab, NOT baked into
    any image. On real hardware / KVM the device appears instantly and the stock
    fstab is fine. Per the base-consistency principle below it is deliberately
    kept out of `images/bootc-os-rt` and out of the ros2 images; it lives in the
    boot-verify harness/this doc.)
  - **The earlier no-login userspace proof** (level 2) was obtained *before* this
    fix by injecting an early oneshot unit (`DefaultDependencies=no`,
    `Before=sysinit.target`) that printed `uname` before the emergency cascade.
    Gotcha: a unit written into the ostree deploy via `qemu-nbd` must get the
    `system_u:object_r:systemd_unit_file_t:s0` SELinux label (`setfattr`), else
    systemd under enforcing can't load it and GCs the `*.wants` symlink.
- **`rt-serial-verify.py` fixes landed this session** (both validated against the
  fc44 aarch64 boot): (1) `\r` bursts through the login wait to dismiss the
  fresh-vars edk2 boot-device menu + poke getty (old `\n` did nothing);
  (2) `strip_esc()` strips OSC-3008/ANSI escapes before regex matching;
  (3) a **banner fallback** — if login never comes, it scans the full transcript
  for `PREEMPT_RT` (exit 0 on a banner hit), which is exactly what salvaged this
  proof.

## fc44 — kernel-rt + images BUILT & BOOTED on x86_64 (2026-10-01)

Done NATIVELY on a fresh `c7i.4xlarge` EC2 box (16 vCPU / 32 GB, AL2023, rootful
podman + fedora:44). Closes the last matrix cell → **both arches are now a matched
7.2.7 pair.**

- **Version-skew decision (Strategy A):** while building, the box's freshly-pulled
  `bootc-os:latest` had already bumped `7.2.7-200.fc44` → `7.2.8-200.fc44` (a new
  base pushed 2026-10-01 05:54 UTC — the exact "check the live base NVR" trap). To
  deliver an internally-consistent, reproducible **matched pair** with the fc44
  aarch64 work (also 7.2.7), we **pinned the base to the 7.2.7 child digest** and
  reused the already-built 7.2.7+rt kernel — rebuilding only the x86_64 image, no
  kernel recompile. Pin:
  `quay.io/hummingbird-community/bootc-os@sha256:1eec04befdd1d30370fe7adf1dce1d38d66ee329680827c35cd817b6c0f40ce4`
  (kernel `7.2.7-200.fc44`), passed as `--build-arg BASE_IMAGE=`.
- **kernel-rt (x86_64)** from `kernel-7.2.7-200.fc44.src.rpm` (`--with rtonly`,
  `BUILDER=fedora:44`), `CONFIG_PREEMPT_RT=y`, flavor `7.2.7-200.fc44.x86_64+rt`.
- `bootc-os-rt:fc44` — **1.06 GB**, lint 14/1, removed kernel = the 7.2.7 match.
- `ros-core-rpms-rt:fc44` — **1.54 GB** (155 ROS pkgs, `ros2` CLI, default Fast
  DDS pub/sub round-trip PASS — received `RTFC44OK`). Again confirms the
  fc43-built ROS RPMs are fc44-compatible (no rebuild).
- **BOOTED & RT confirmed live (2026-10-01).** `bootc-image-builder` → qcow2
  (669 MB, `--rootfs ext4`), booted under **qemu x86_64 TCG** (no `/dev/kvm`),
  capture-only serial. Banner proof
  (`artifacts/serial-transcript-fc44-x86_64.txt`):
  `Linux version 7.2.7-200.fc44.x86_64+rt … #1 SMP PREEMPT_RT` (the authoritative
  `CONFIG_PREEMPT_RT=y` check); kernel cmdline booted
  `vmlinuz-7.2.7-200.fc44.x86_64+rt` with the RT kargs applied at deploy
  (`preempt=full nowatchdog`). x86_64 TCG is fast and (unlike aarch64) never hits
  the `/boot` device-timeout, so no fstab aid was needed.
- **`enable-repos.sh` robustness fix (surfaced here):** the old gpgkey pointed at
  `src.fedoraproject.org` dist-git raw, which dnf5 fetches once with no retry at
  transaction time — a single 503 (seen live) fails the build. Now the per-release
  Fedora key is derived LOCALLY from the stable combined keyring
  (`fedoraproject.org/fedora.gpg`) into an armored file, with the dist-git URL only
  as a retrying fallback. Generic fix; benefits every `ros-core-rpms` build.

**Base pinning (productization takeaway):** `bootc-os:latest` moves ~1×/day
(irregular, CI-driven) and bumps the kernel whenever Fedora does. Always **pin the
base to a specific per-arch child digest** and build kernel-rt from *that exact*
kernel SRPM — otherwise the RT image's kernel NVR silently diverges from the base
(the skew above). The fc44 matched pair is pinned to the 7.2.7 digest on both arches.

**All fc44 + fc43 artifacts are archived** in `artifacts/` (gitignored) and
loaded into local podman — see [`artifacts.md`](artifacts.md).

## Where robot customization goes (base-consistency principle, 2026-10-01)

The base bootc image must stay **consistent with Hummingbird's upstream
`bootc-os`** — no ad-hoc, non-standard tweaks. Any customization *for robots*
goes into the **ros2 image layer**, not the base. Concretely:

| Belongs in the RT **base** (`images/bootc-os-rt`) | Belongs in the **ros2/robot** image layer |
|---|---|
| The kernel swap `kernel` → `kernel-rt-core`+`kernel-rt-modules-core` (an OS/bootc-layer op; mirrors the productized `hummingbird/rt/` bootc-os variant, MAIN_PACKAGES) | Robot-**workload**-specific CPU isolation kargs (`isolcpus` / `nohz_full` / `rcu_nocbs` / `irqaffinity` — the ranges depend on the robot's cores) |
| Generic RT tuning kargs that are intrinsic to running an RT kernel (`preempt=full`, `nowatchdog`) | ROS 2 packages, `rt-tests`/`cyclictest`, app config, demo users |

What this explicitly **excludes from the base**: the `/boot` `nofail`
fstab edit — it is a TCG boot-verification aid, not a robot feature, and is kept
in the verify harness only (see the fc44 section). The RT base is NOT forked or
patched beyond the kernel swap + intrinsic RT kargs.

## Base version skew (2026-09-30)

While the RT work ran, `quay.io/hummingbird-community/bootc-os:latest` was rebuilt
and bumped its stock generic kernel `7.1.8-100.fc43` → `7.2.7-200.fc44` on BOTH
arches (still generic-only, no RT). The fc43 `bootc-os-rt` therefore regresses the
base's kernel; the fc44 rebuilds (above) close that gap on **both** arches. Both
fc44 RT stacks are the matched **7.2.7** pair pinned to the same base child digest
(the base had since moved on to 7.2.8 — see the Strategy-A note above).

## Open items

- **Secure Boot signing** — self-built kernel-rt is unsigned by Fedora's key;
  boots only with SB off until signed (verified booting with SB off via
  non-secboot OVMF on x86_64 and non-secboot aarch64 pflash).
- ~~fc44 x86_64 kernel-rt + image stack~~ **DONE 2026-10-01** — kernel-rt +
  `bootc-os-rt:fc44` (1.06 GB) + `ros-core-rpms-rt:fc44` (1.54 GB), booted under
  TCG with the `PREEMPT_RT` banner + RT kargs
  (`artifacts/serial-transcript-fc44-x86_64.txt`). Both arches now the matched
  7.2.7 pair.
- ~~fc44 aarch64 interactive getty login~~ **DONE 2026-10-01** — full clean boot →
  serial `login:` → interactive `uname` = `#1 SMP PREEMPT_RT`
  (`artifacts/serial-transcript-fc44-aarch64-login.txt`), after the `/boot`
  `nofail` fstab fix. Complete x86_64 parity.
- **`cyclictest` latency numbers** on a KVM/`.metal` host (both arches — TCG
  timing is meaningless; `rt-tests` must be baked into the image).
- Productization = a `hummingbird/rt/` bootc-os variant in the containers
  monorepo (MAIN_PACKAGES kernel swap) once kernel-rt is published — see
  [`../images/bootc-os-rt/README.md`](../images/bootc-os-rt/README.md).
