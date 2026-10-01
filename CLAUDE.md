# hummingbird-ros2-poc — Project Context

Handoff from the design session (run in the sibling `hummingbird/containers`
repo). This file is the lean index; the detailed, hard-won facts live in
[`docs/`](docs/) — **read the relevant doc before acting in that area.** Keep both
updated as the POC evolves.

## Goal

Prove that ROS 2 base images (`ros-core`, `ros-base`) can be built on the
Hummingbird `bootc-os` image instead of Ubuntu — producing images that are
**both** ROS 2 dev containers **and** bootable "robot OS" images (bootc) — plus a
**PREEMPT_RT** kernel option for real-time robotics. Modeled structurally on the
auto-generated `osrf/docker_images` ROS 2 Dockerfiles, translated apt/Ubuntu →
dnf/Fedora.

## TWO package sources — read this first

1. **tavie/ros2 COPR** (community, unofficial) — the original path. x86_64-only,
   Fedora-packaged Jazzy. Basis for `images/ros-core`, `ros-base`, `gazebo`,
   `sim-bundle`. Still the only source for the Gazebo/simulation images. Details:
   [`docs/established-facts.md`](docs/established-facts.md).
2. **Hummingbird-built RPMs** (`images/ros-core-rpms`) — ROS 2 Jazzy built the
   Hummingbird way from official upstream sources (no COPR). The `ros_core`
   closure (162 RPMs) is **COMPLETE on BOTH aarch64 and x86_64**. The strategic
   direction. Details: [`docs/ros-core-rpms.md`](docs/ros-core-rpms.md).

## Status snapshot

| Piece | aarch64 | x86_64 |
|---|---|---|
| `ros-core` / `ros-base` (COPR) | n/a (COPR x86_64-only) | ✅ built + tested |
| `ros-core-rpms` (Hummingbird RPMs) | ✅ built + verified | ✅ built + verified |
| `sim-bundle` bridge/simulation/gazebo | n/a (COPR) | ✅ built + tested (native) |
| native `simulation`/`gazebo` | ❌ boost skew | ❌ boost skew → use sim-bundle |
| `bootc-os-rt` (PREEMPT_RT) fc43 | ✅ built + BOOTED | ✅ built + BOOTED |
| `bootc-os-rt` fc44 | ✅ built + BOOTED + RT verified under TCG (full boot → login → `uname`) | ✅ built + BOOTED + RT verified under TCG (full boot → login → `uname`) |

- **Base moved fc43 → fc44 (2026-09-30):** `bootc-os:latest` stock kernel is now
  `7.2.7-200.fc44` (generic-only). fc44 RT rebuilt on **both** arches 2026-10-01 —
  a matched **7.2.7** pair pinned to the same base child digest (the base had since
  bumped to 7.2.8; both RT images pin 7.2.7 for internal consistency). The fc43 ROS
  RPMs are fc44-compatible (no rebuild). See
  [`docs/realtime-kernel.md`](docs/realtime-kernel.md).
- All built images + RT kernel RPMs are archived in `artifacts/` (gitignored) and
  loaded in local podman — inventory in [`docs/artifacts.md`](docs/artifacts.md).

## docs/ index

| Doc | Covers |
|---|---|
| [`established-facts.md`](docs/established-facts.md) | base image, tavie COPR, bootc-os quirks, Gazebo-on-Fedora, why-choices |
| [`ros-core-rpms.md`](docs/ros-core-rpms.md) | the Hummingbird-built ROS 2 RPM path (both arches) |
| [`realtime-kernel.md`](docs/realtime-kernel.md) | PREEMPT_RT kernel + `bootc-os-rt` status (fc43/fc44, both arches) |
| [`simulation-gazebo.md`](docs/simulation-gazebo.md) | boost blocker, sim-bundle workaround, interactive GUI |
| [`verification.md`](docs/verification.md) | verification status, test plan, image-size analysis |
| [`open-questions.md`](docs/open-questions.md) | open risks + provenance + upstream reference Dockerfiles |
| [`artifacts.md`](docs/artifacts.md) | archived artifacts + local podman image inventory |

Also: [`images/bootc-os-rt/README.md`](images/bootc-os-rt/README.md) (RT
build/verify mechanics + productization mapping).

## Files

```
images/ros-core/        FROM bootc-os; enable-repos.sh + install ros-core + ament-package (COPR)
  enable-repos.sh       Fedora repos + release-pinned tavie COPR
  ros-entrypoint.sh     sources /usr/lib64/ros-$ROS_DISTRO/setup.bash then exec "$@"
  ros2-profile.sh       /etc/profile.d hook, auto-source for interactive bash login shells
images/ros-base/        FROM ros-core (ARG BASE_IMAGE); adds ros-base
images/ros-core-rpms/   FROM bootc-os; ros-core from HUMMINGBIRD-BUILT RPMs (NO COPR). ARG BASE_IMAGE.
  enable-repos.sh       stock Fedora repos only (base already has the hummingbird repo → spdlog-1.17)
  rpms/                 aarch64 ros-jazzy-* RPMs (162; gitignored; specs in hummingbird-rpms monorepo)
  rpms-x86_64/          x86_64 ros-jazzy-* RPMs (162; gitignored; NEVER mix arches)
images/bootc-os-rt/     FROM bootc-os; swaps stock kernel -> kernel-rt (PREEMPT_RT), initramfs, RT kargs.d
  kargs.d/10-realtime.toml   RT boot args (preempt=full, nowatchdog; isolcpus/... template)
  rpms-rt/              local kernel-rt-* RPMs (gitignored; produce with scripts/rt-kernel-build.sh)
  bib-config.toml      bootc-image-builder customization (DEMO user; replace before real use)
images/simulation/      FROM ros-base (ARG BASE_IMAGE); adds ros-<distro>-simulation (osrf; incl. ros_gz)
images/gazebo/          FROM bootc-os; standalone Gazebo Harmonic (gz-*-vendor, NO ROS middleware)
  enable-repos.sh / gz-entrypoint.sh / gz-profile.sh
images/sim-bundle/      multi-stage: fedora:43 builder -> isolated /sysroot -> COPY into bootc-os (VARIANT=bridge|simulation|gazebo)
  tavie-ros2.repo / sim-entrypoint.sh (chroot + source setup.bash + GZ_* paths; needs --cap-add=sys_admin)

scripts/rt-kernel-build.sh   kernel-rt from the pinned Fedora kernel SRPM via --with rtonly (BUILDER matches SRPM release; WITH_DEBUGINFO=1 for prod)
scripts/rechunk-image.sh     rechunk an OCI image into content-based layers (chunkah; one layer per RPM)
scripts/rt-serial-verify.py  drive a booted bootc-os-rt qcow2 over its qemu serial socket (no SSH); assert PREEMPT_RT
scripts/ec2-verify.sh        native x86_64 build+test of all 5 images (Fast-DDS + headless gz sim + integration)
scripts/gui-verify.sh        native x86_64 GUI launcher (Xvfb + x11vnc + gz sim, software GL)
scripts/gui-cmdvel-demo.sh   native x86_64 "ROS 2 drives the sim via the GUI" (cmd_vel -> bridge -> DiffDrive)
scripts/integration-rosgz.sh / -rosgz-sim.sh / -ros2gz.sh   two-container ROS 2 <-> Gazebo integration (native x86_64)
```

## Build

COPR-sourced images are **x86_64-only** (tavie has no aarch64). On arm64 add
`--platform linux/amd64`. The Hummingbird-RPM and RT images build **natively per
arch, no emulation** (build on a matching-arch machine).

```bash
podman build -t hummingbird-ros2-poc/ros-core:latest images/ros-core
podman build -t hummingbird-ros2-poc/ros-base:latest images/ros-base
# ros-core from Hummingbird RPMs: stage the MATCHING arch into ./rpms/ first
# (aarch64 rpms/, x86_64 rpms-x86_64/ — the Dockerfile COPYs rpms/).
podman build -t hummingbird-ros2-poc/ros-core-rpms:latest images/ros-core-rpms
# bootc-os + PREEMPT_RT: stage kernel-rt RPMs into images/bootc-os-rt/rpms-rt/ first
# (build them with scripts/rt-kernel-build.sh).
podman build -t hummingbird-ros2-poc/bootc-os-rt:latest images/bootc-os-rt
# ROS 2 on the RT base:
podman build --build-arg BASE_IMAGE=localhost/hummingbird-ros2-poc/bootc-os-rt:latest \
  -t hummingbird-ros2-poc/ros-core-rpms-rt:latest images/ros-core-rpms
# native simulation/gazebo are BLOCKED (boost skew) — use sim-bundle:
podman build --build-arg VARIANT=bridge     -t hummingbird-ros2-poc/sim-bundle:bridge     images/sim-bundle
podman build --build-arg VARIANT=simulation -t hummingbird-ros2-poc/sim-bundle:simulation images/sim-bundle
podman build --build-arg VARIANT=gazebo     -t hummingbird-ros2-poc/sim-bundle:gazebo     images/sim-bundle
```

### EC2 for native builds

- **kernel-rt build:** ≥16 vCPU / ≥30 GB — `c7i.4xlarge` (x86_64) /
  `c7g.4xlarge`|`c8g.4xlarge` (aarch64). ~80 GB gp3 root.
- **ROS 2 RPM build:** lighter — `c6i.2xlarge` (x86_64) sufficed.
- **Boot + cyclictest latency (needs `/dev/kvm`):** a **`.metal`** instance
  (`c7i.metal-*` / `c7g.metal`). Non-metal boxes only have qemu TCG (RT boots and
  proves live, but no meaningful latency).
- Gotchas: AL2023 AMIs ship `docker`/`buildah` but **not `podman`** (install it);
  use **rootful** podman (`sudo`); build natively (no `--platform`).
