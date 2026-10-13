# Base-switch PoC — ROS 2 + PREEMPT_RT on `fedora/fedora-bootc:44`

> Detail doc for [`../CLAUDE.md`](../CLAUDE.md). Goal: prove the ROS 2 + RT stack
> builds and boots on a **non-Hummingbird** bootc base, to de-risk the dependency
> on Hummingbird. Target chosen: **`quay.io/fedora/fedora-bootc:44`** (full parity
> scope: `ros-core-rpms` + `bootc-os-rt` + `ros-core-rpms-rt`, both arches).

## Why fedora-bootc:44 (vs rawhide / RHEL / UBI)

Hummingbird is NOT a Fedora point release — it is a **rolling, rawhide-sourced
userspace** (95%+ from Fedora Rawhide via Konflux: e.g. `gcc 16.2.1`,
`spdlog 1.17.0`, shipped as `.hum1`) on a **Fedora-supplied kernel** (`.fc44`,
from `fedora-44-updates`; ARK/CKI not wired in yet). So no single Fedora release
matches it. For a *base-switch* PoC the aim is to change the fewest variables:

- **fedora-bootc:44** keeps **python 3.14** → ROS RPMs reused, **no rebuild** —
  isolates the experiment to "the base", not a mass rebuild.
- Its kernel is **7.2.8-200.fc44**, the *same NVR* as the current Hummingbird
  base → the RT recipe is identical.
- The only real gap vs Hummingbird is **spdlog-1.17** (fedora-bootc has 1.15),
  which is exactly the "can we drop the Hummingbird repo?" question this PoC
  should answer.

rawhide would match the libs (spdlog 1.17, gcc 16) but moves python to **3.15**
(full compiled-ROS rebuild) and is unpinnable. RHEL (`rhel-bootc:10`) is a bigger,
separate track: subscription, python 3.12 (ROS rebuild), EPEL deps, and aarch64
`kernel-rt` is only **Technology Preview**. UBI is not a bootc base at all.

## Verified facts about the target (2026-10-07)

`quay.io/fedora/fedora-bootc:44` (inspected live):

| | fedora-bootc:44 | vs current Hummingbird base |
|---|---|---|
| `VERSION_ID` / `rpm -E %fedora` | 44 / **44** (correct) | HB: fc44 userspace but `%fedora` pinned to **43** (stale-macro bug) |
| `python3` | **3.14.8-1.fc44** | HB: 3.14.8-1.1.hum1 — **same ABI**, ROS RPMs reusable |
| `kernel` | **7.2.8-200.fc44** | HB: **7.2.8-200.fc44** — identical NVR |
| stock Fedora repos | **ship built-in** (+ GPG keys) | HB: absent (only `hummingbird.repo`) |
| `spdlog` | **1.15.3-4.fc44** (`libspdlog.so.1.15`) | HB repo: **1.17.0-3.hum1** (`libspdlog.so.1.17`) — the gap |
| `bootc` | 1.16.13-1.fc44 present | HB: present |

Pin (manifest-list / index digest; podman selects the arch):
```
quay.io/fedora/fedora-bootc@sha256:10ead291e5531900951775c75b12fd3b08bc6bc1667cdb7b66803e31f871c78d
```
For strict per-arch child-digest pinning, extract from `skopeo inspect --raw
docker://quay.io/fedora/fedora-bootc:44`. Note `:44` floats on fc44 updates —
re-pin before each reproducible run.

## The real dependency gap — NOT "just stage spdlog-1.17" (disproven 2026-10-13)

The original plan (stage a rebuilt `spdlog-1.17` into the local repo) is **wrong**,
and finding that out is the core PoC result. `spdlog-1.17` is not a lone package —
it is part of a **rawhide library cohort**:

```
rcl_logging_spdlog  →needs→  libspdlog.so.1.17  →needs→  libfmt.so.12   (rawhide: spdlog 1.17 + fmt 12)
fedora-bootc:44 has:         spdlog 1.15.3              fmt 11.2.0
and fmt 11 is load-bearing:  dnf5 / libdnf5 / PackageKit all link libfmt.so.11
```

So you **cannot** bring `spdlog-1.17` down to fc44: it dynamically links
`libfmt.so.12`, and upgrading `fmt` 11 → 12 would break `dnf5`/`libdnf5` (the
package manager itself links `libfmt.so.11`). Verified live on the fc44 base.

**Correct approach: rebuild the ROS consumer against the base's native libs** (the
ROS layer adapts to the base — the portable direction). For the whole `ros-core`
closure the *only* rawhide-skew soname is spdlog, consumed by exactly one package,
`ros-jazzy-rcl-logging-spdlog`. Its spec BuildRequires/Requires `spdlog-devel`
**unversioned**, so a plain fc44 rebuild links against the base's `spdlog-1.15`
and the result requires `libspdlog.so.1.15` (which the base has). Rebuild recipe
(native per arch, from the monorepo spec — verified aarch64):

```bash
# in a fedora:44 container, with the local ROS repo (rpms/) + fedora repos:
#   curl github.com/ros2/rcl_logging tag 3.1.1 -> SOURCES
#   dnf builddep <spec>  (pulls ament/colcon/rcutils/spdlog-vendor from local+fedora)
#   rpmbuild -bb ros-jazzy-rcl-logging-spdlog.spec
# -> ros-jazzy-rcl-logging-spdlog-3.1.1-1.fc44.<arch>.rpm (requires libspdlog.so.1.15)
```
Spec source: `hummingbird-rpms/rpms/ros-jazzy-rcl-logging-spdlog/`. Swap this
fc44-built RPM in place of the `.hum1` one when staging `rpms/` for a fedora-bootc
build. **Broader lesson: the ROS layer must be rebuilt per base**, not merely
restaged — Hummingbird's value was the coherent rawhide cohort the RPMs were built
against. (For `ros-core` only 1 package needed it; richer variants — `ros-base`,
sim — likely bind more rawhide sonames and need more rebuilds.)

Pre-check that confirms the above on the pinned base: `dnf install --assumeno
ros-jazzy-ros-core` with the (unmodified `.hum1`) local repo shows
`libspdlog.so.1.17` as the ONLY unmet soname — everything else resolves on fc44.

## Code changes already landed (base-agnostic; safe on both bases)

- **`images/ros-core-rpms/enable-repos.sh`** — now (1) no-ops when stock Fedora
  repos are already enabled (fedora-bootc — verified: it no-ops), and (2) when it
  must add them (Hummingbird), derives the release from the real package disttag
  (`fcNN`) instead of `rpm -E %fedora` — fixing the pinned-`%fedora=43`-on-fc44 bug.
- **`images/ros-core-rpms/Dockerfile` + `images/bootc-os-rt/Dockerfile`** — cleanup
  now also removes `/var/lib/dnf/repos`. **Base-specific delta found 2026-10-13:**
  fedora-bootc's dnf leaves `/var/lib/dnf/repos/*/countme` files (and the empty
  dir) in `/var`, which fails `bootc container lint --fatal-warnings`
  (`var-tmpfiles`). The Hummingbird base did not. Removing the dir fixes lint on
  both bases.
- **`scripts/rt-kernel-build.sh`** — defaults bumped to `kernel-7.2.8-200.fc44` /
  `BUILDER=fedora:44` (fc43 7.1.8 superseded). Still env-overridable.
- **`images/ros-core-rpms/Dockerfile`** — comment updated for the two-base case.

The base swap itself is driven entirely by `--build-arg BASE_IMAGE=`; the image
defaults still point at Hummingbird so existing builds are unchanged.

## Results — aarch64 PROVEN locally & natively (2026-10-13)

Built on this Apple Silicon host (native aarch64 podman; no emulation), reusing the
existing 7.2.7-200.fc44 kernel-rt RPMs from `artifacts/`:

- **`ros-core` on `fedora-bootc:44`**: 155 ROS pkgs install; base-native
  `spdlog-1.15.3-4.fc44`; `ros2` CLI works; **default Fast-DDS pub/sub round-trip
  PASS** (received `RTFEDORA44OK`).
- **`bootc-os-rt` on `fedora-bootc:44`**: builds; `bootc container lint` **14/0**;
  image carries ONLY `7.2.7-200.fc44.aarch64+rt`, stock kernel removed; RT kargs.d
  applied. → RT base swap works on a non-Hummingbird base.
- **`ros-core-rpms-rt` (ROS on the RT fedora base)**: builds; lint **14/0**; ships
  the `+rt` kernel + 155 ROS pkgs + `ros2` CLI + `bootc`.
- **Image size tradeoff:** fedora-bootc variants are bigger than the Hummingbird
  minimal/distroless base — `bootc-os-rt` **2.4 GB** (vs HB 1.53 GB) and
  `ros-core-rpms-rt` **2.83 GB** (vs HB 1.97 GB), ~0.9 GB heavier.
- **BOOTED + PREEMPT_RT confirmed live on EC2 (aarch64, 2026-10-13):** on a
  **`c7g.metal`** (64 vCPU / 125 GB, AL2023, `/dev/kvm`), the verified
  `ros-core-rpms-rt:fedora44-aarch64` OCI was transferred (sha256-checked),
  installed to a raw disk with the image's own **`bootc install to-disk
  --via-loopback`** (see bib note below), and booted under **qemu + KVM**
  (`-cpu host -machine virt,accel=kvm`). Full clean boot → serial getty login as
  `rt` → RT asserted:
  - banner `Linux version 7.2.7-200.fc44.aarch64+rt … gcc 16.2.1 … #1 SMP PREEMPT_RT`
  - `uname -r` = `7.2.7-200.fc44.aarch64+rt`; `uname -v` = `#1 SMP PREEMPT_RT`
  - `scripts/rt-serial-verify.py` → **PREEMPT_RT CONFIRMED (rc=0)**.
    Transcript: `artifacts/serial-fedora44-aarch64.txt`.
  - **ROS 2 functional on the booted RT VM (not just installed):** over the serial
    console — `ros2 pkg list` = 150, `ros2 topic list` = 3, the rebuilt
    `rcl_logging_spdlog` backend wrote a log file (`/root/.ros/log/python3_*.log`),
    and a **default Fast-DDS pub/sub round-trip PASSED** (subscriber received
    `data: ROS2_ON_RT_OK`). This is a `ros-core` **smoke test** (node graph, topic
    pub/sub, DDS discovery+transport+serialization, logging) — NOT a full
    conformance suite (services/actions/params/QoS/lifecycle/multi-host untested).
    Gotchas hit driving ros2 over serial: fast sends to the getty duplicate chars
    (throttle per-char), each `ros2` CLI call cold-starts Python (~2–3 s, so use
    one continuous publisher), and `~/.ros/log` must pre-exist.
  - **cyclictest** (`-D 20 -m -Sp99 -i 200`, KVM): typical **single-digit µs**
    (Min 2, Avg 2–11 µs; most threads Max ≤ 32 µs), with **one 90 ms outlier** —
    expected in an **untuned VM** (no `isolcpus`/vCPU pinning; audit/NetworkManager
    activity coincided). Kernel is RT-functional; a tuned run (host `isolcpus` +
    vCPU pinning + `taskset`) is needed for publishable latency figures.
- **bib gotcha (found 2026-10-13):** `quay.io/centos-bootc/bootc-image-builder:latest`
  is **amd64-only** (no arm64 manifest; the Fedora bib path is gone), so bib cannot
  run on an aarch64 host. Workaround used: **`bootc install to-disk`** from the
  target image itself (fully native, no external builder) + a thin overlay that
  adds a serial-login user (and `realtime-tests` for cyclictest — note the package
  is `realtime-tests`, NOT `rt-tests`, which is Request Tracker).
## Results — x86_64 PROVEN on EC2 (2026-10-13)

Done natively on an EC2 **`c6i.2xlarge`** (8 vCPU / 15 GB, AL2023, no `/dev/kvm`).
Base `fedora-bootc:44` x86_64 verified: python 3.14.8, spdlog 1.15.3, stock kernel
had drifted to `7.2.9-201.fc44` (our kernel-rt 7.2.7 still swaps in fine).

- **`rcl-logging-spdlog` rebuilt natively on fc44 x86** → requires
  `libspdlog.so.1.15` (same one-package fix as aarch64).
- **`ros-core-rpms` on fedora-bootc:44**: builds; 150 pkgs; base `spdlog-1.15`;
  **native-container Fast-DDS pub/sub round-trip PASS** (received `X86_FASTDDS_OK`)
  — run as a native container (real x86 CPU), the strongest ROS runtime proof.
- **`bootc-os-rt` + `ros-core-rpms-rt`**: build; lint **14/0**; only
  `7.2.7-200.fc44.x86_64+rt` kernel, stock removed; 155 ROS pkgs.
- **BOOTED + PREEMPT_RT confirmed**: `bootc install to-disk` → raw disk → booted
  under **qemu x86_64 TCG** (no KVM on c6i.2xlarge) → serial getty login as `rt` →
  banner `7.2.7-200.fc44.x86_64+rt … #1 SMP PREEMPT_RT`, `uname -r/-v` match,
  rt-serial-verify rc=0. Transcript: `artifacts/serial-fedora44-x86_64.txt`.
- **Not done on x86:** cyclictest (c6i.2xlarge has no KVM → TCG timing is noise;
  use a `*.metal` if latency numbers are needed).

**Both arches now prove the base switch end-to-end.** The ROS 2 + PREEMPT_RT stack
builds, installs, runs (Fast-DDS), and boots as a bootc image on plain
`fedora/fedora-bootc:44`, with exactly one ROS package rebuilt per base
(`rcl-logging-spdlog` → base-native spdlog 1.15).

## Runbook

Set the pin once:
```bash
BASE=quay.io/fedora/fedora-bootc@sha256:10ead291e5531900951775c75b12fd3b08bc6bc1667cdb7b66803e31f871c78d
```

### Per arch, on a matching-arch box (EC2 x86_64 c6i+ / Graviton; or Lima aarch64)

1. **spdlog-1.17** (mock/rpmbuild on fedora:44 from the rawhide SRPM); copy the
   binary RPM into `images/ros-core-rpms/rpms{,-x86_64}/` alongside the 162 ROS RPMs.

2. **ros-core-rpms** (userspace proof):
   ```bash
   podman build --build-arg BASE_IMAGE=$BASE \
     -t hummingbird-ros2-poc/ros-core-rpms:fedora44 images/ros-core-rpms
   ```

3. **kernel-rt** from the fc44 SRPM:
   ```bash
   SRPM=kernel-7.2.8-200.fc44.src.rpm BUILDER=fedora:44 \
     WITH_DEBUGINFO=1 scripts/rt-kernel-build.sh
   # stage kernel-rt-core + kernel-rt-modules-core into images/bootc-os-rt/rpms-rt/
   ```

4. **bootc-os-rt** on the fedora base (kernel-swap Dockerfile is base-agnostic):
   ```bash
   podman build --build-arg BASE_IMAGE=$BASE \
     -t hummingbird-ros2-poc/bootc-os-rt:fedora44 images/bootc-os-rt
   ```

5. **ros-core-rpms-rt** (ROS 2 on the RT fedora base):
   ```bash
   podman build --build-arg BASE_IMAGE=localhost/hummingbird-ros2-poc/bootc-os-rt:fedora44 \
     -t hummingbird-ros2-poc/ros-core-rpms-rt:fedora44 images/ros-core-rpms
   ```

### Verify (both arches)

- Closure resolves; `ros2` CLI runs; default Fast-DDS pub/sub round-trips.
- `bootc container lint --no-truncate` passes.
- `bootc-image-builder` → qcow2 (`--rootfs ext4`) → boot under qemu TCG →
  `uname -v | grep PREEMPT_RT` (authoritative RT check; `/sys/kernel/realtime` is
  absent on Fedora ark kernel-rt). Use `scripts/rt-serial-verify.py` for the
  getty-login proof. See [`realtime-kernel.md`](realtime-kernel.md) for the
  aarch64 `/boot` `nofail` TCG aid.

## Status

| Step | aarch64 | x86_64 |
|---|---|---|
| rcl-logging-spdlog rebuilt on fc44 (→ libspdlog.so.1.15) | ✅ | ✅ (native on EC2 c6i.2xlarge) |
| ros-core-rpms on fedora-bootc:44 (install + ros2 + Fast-DDS) | ✅ | ✅ (native-container Fast-DDS) |
| kernel-rt for RT base | ✅ reused 7.2.7 fc44 RPMs | ✅ reused 7.2.7 fc44 RPMs |
| bootc-os-rt:fedora44 built + lint 14/0 | ✅ | ✅ |
| ros-core-rpms-rt:fedora44 built + lint 14/0 | ✅ | ✅ |
| booted + PREEMPT_RT confirmed | ✅ EC2 c7g.metal (KVM) + cyclictest | ✅ EC2 c6i.2xlarge (TCG) |

## Expected deltas / watch-items

- **spdlog is the whole ballgame.** If the rawhide spdlog-1.17 rebuild on fc44 is
  clean and the closure resolves, the base swap works with zero ROS rebuild.
- **Secure Boot** unchanged — self-built kernel-rt is unsigned (boot with SB off).
- **No Hummingbird repo** means anything *else* the ROS closure pulled from it
  (besides spdlog) would surface here. Expectation per `ros-core-rpms.md`: spdlog
  was the only Hummingbird-specific soname — confirm with the `--assumeno`
  pre-check before building.
- This PoC does **not** change the strategic default; it proves portability. If
  it passes, the ROS stack is shown base-independent within the Fedora family.
