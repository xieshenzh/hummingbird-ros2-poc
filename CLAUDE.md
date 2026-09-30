# hummingbird-ros2-poc — Project Context

This file is a handoff from the design session (run in the sibling
`hummingbird/containers` repo) that scaffolded this project. It captures the
decisions and facts needed to build and test the images here without re-deriving
them. Keep it updated as the POC evolves.

## Goal

Prove that ROS 2 base images (`ros-core`, `ros-base`) can be built on the
Hummingbird `bootc-os` image instead of Ubuntu — producing images that are
**both** ROS 2 dev containers **and** bootable "robot OS" images (bootc).

Modeled structurally on the auto-generated `osrf/docker_images` ROS 2
Dockerfiles (`create_ros_core_image.Dockerfile.em` → ros-core, then ros-base
`FROM ros-core`), translated from apt/Ubuntu to dnf/Fedora.

## TWO package sources — read this first

This POC now has **two independent ways** to get ROS 2 onto bootc-os. Most of
this file (Established facts, sim-bundle, Gazebo, Verification) documents the
FIRST; the SECOND is the strategic direction and is summarized in its own
section immediately below.

1. **tavie/ros2 COPR** (community, unofficial) — the original path. x86_64-only,
   Fedora-packaged Jazzy. Basis for `images/ros-core`, `images/ros-base`,
   `images/gazebo`, `images/sim-bundle`. Still the only source for the
   Gazebo/simulation images.
2. **Hummingbird-built RPMs** (`images/ros-core-rpms`) — ROS 2 Jazzy built the
   Hummingbird way from official upstream sources (no COPR). The `ros_core`
   closure is **COMPLETE on BOTH aarch64 and x86_64**. See next section.

## ROS 2 as Hummingbird-built RPMs (`images/ros-core-rpms`) — ros_core DONE, both arches

The strategic alternative to the COPR: build the ROS 2 Jazzy packages ourselves,
the Hummingbird way — the `rpms` monorepo dev workflow (`ci/build_rpms.sh`
running **mock** inside a pinned Fedora container, from **official upstream
sources**, SHA512-pinned in each package's `sources` file). Specs live in the
`hummingbird-rpms` monorepo on branch `add-ros2-jazzy-packages`. This removes
both COPR limitations: it is not third-party, and it is **not x86_64-only**.

- **Status: the `ros_core` closure = 162 `ros-jazzy-*` RPMs, built 1:1 (source
  → binary, no debuginfo).**
  - **aarch64** — DONE 2026-09-13, built NATIVELY on Apple Silicon (Fedora
    aarch64 Lima VM, no qemu). RPMs staged in `images/ros-core-rpms/rpms/`.
  - **x86_64** — DONE 2026-09-25, built NATIVELY on an AL2023 `c6i` EC2 box
    (rootful podman 5.6.1, no qemu, no `--platform`). Same specs/sources/tarballs
    as aarch64 — only `build_rpms.sh --arch x86_64` differs (mock's
    `legal_host_arches` requires an x86_64 HOST, hence a native x86_64 machine).
    RPMs staged in `images/ros-core-rpms/rpms-x86_64/` (105 noarch + 57 compiled
    x86_64; verified byte-exact on copy-down). Both dirs are gitignored (build
    artifacts; the specs are the tracked source in the monorepo).
- **The image** (`images/ros-core-rpms/Dockerfile`, arch-agnostic): `FROM
  bootc-os`; `enable-repos.sh` adds only the stock Fedora repos (NO COPR — the
  base already enables the Hummingbird repo, which provides the load-bearing
  `spdlog-1.17.0`, i.e. `libspdlog.so.1.17`, that plain Fedora lacks — Fedora has
  1.15); COPY the RPMs → `createrepo_c` a transient local repo under `/var/tmp` →
  `dnf install ros-jazzy-ros-core ros-jazzy-ament-package` → remove the
  repo/RPMs/createrepo_c. Reuses `images/ros-core`'s `ros-entrypoint.sh` +
  `ros2-profile.sh` verbatim — our RPMs use the SAME `/usr/lib64/ros-jazzy` FHS
  prefix as tavie.
- **Verified (both arches, NATIVE — no qemu):** closure resolves; `ros2` CLI
  works; login shell auto-sources ROS; FHS `setup.bash` at
  `/usr/lib64/ros-jazzy/`; **DEFAULT Fast DDS pub/sub WORKS** (the old Fast-DDS
  failure was purely amd64-on-arm64 emulation — gone on native hardware of either
  arch); `bootc container lint` passes (aarch64 13/0, x86_64 14 pass / 1 skip);
  `CMD [/sbin/init]` + kernel + `bootc` inherited (bootable). Image sizes:
  **aarch64 1.39 GB, x86_64 1.33 GB** — both smaller than the COPR `ros-core`
  (1.96 GB).
- **x86_64 build mechanics (2026-09-25):** driven by a multi-pass,
  failure-tolerant batch driver (scratch, lived only on the EC2 box). A
  build-order derived from **`BuildRequires:` only** misses runtime `Requires:`
  edges (e.g. building `ament-cmake` pulls `ament-cmake-export-dependencies`,
  which *Requires* `ament-cmake-libraries` — an edge the sort never saw), so a
  strict single pass stalls; retrying the unbuilt set pass-over-pass converged in
  **4 passes**. A full runtime-Requires-aware order would build all 162 in one
  pass, but a Kahn sort over that graph risks silently dropping cyclic nodes —
  the retry loop was the lower-risk choice. Those scratch scripts are NOT in the
  repo and are gone with the terminated instance; regenerate from the specs if a
  rebuild is needed.
- **⚠️ spdlog soname pin:** `rcl_logging_spdlog` links `libspdlog.so.1.17`,
  provided by the **Hummingbird** repo's `spdlog-1.17`, NOT Fedora's own 1.15. A
  closure dry-run WITHOUT the Hummingbird repo falsely reports "nothing provides
  libspdlog.so.1.17" — always include it. bootc-os is built from that same repo,
  so the target already has 1.17.
- **NOT yet done as Hummingbird RPMs:** `ros-base`, `simulation`, `gazebo` (only
  the `ros_core` closure is built); and actually BOOTING the image
  (bootc-image-builder qcow2 + SSH login). These remain COPR-only / pending.

## Real-time (PREEMPT_RT) kernel — `images/bootc-os-rt` (kernel-rt built, image drafted)

Robotics/physical-AI needs bounded worst-case latency, so bootc-os needs a
PREEMPT_RT kernel option. **No custom kernel packaging is required**: the Fedora
kernel SRPM bootc-os already pins (`kernel-7.1.8-100.fc43`) ships the full RT
flavor (the ark lineage that also yields RHEL `kernel-rt` / AutoSD
`kernel-automotive`). The RT kernel = rebuild that SAME SRPM with the spec's own
`--with rtonly` toggle.

- **kernel-rt BUILT & verified (x86_64, 2026-09-30)** on a native `c7i`-class
  EC2 box (16 vCPU / 30 GB, AL2023, rootful podman + fedora:43 container),
  `rpmbuild --rebuild --with rtonly` — fast pass (`--without debuginfo`) ~29 min.
  Build log `BUILDING A KERNEL FOR rt x86_64`; shipped config has
  **`CONFIG_PREEMPT_RT=y`** (genuine RT). Driver: `scripts/rt-kernel-build.sh`
  (`WITH_DEBUGINFO=1` for the production build).
  - Subpackages, uname flavor `7.1.8-100.fc43.x86_64+rt` (`+rt` suffix):
    `kernel-rt` (meta), `kernel-rt-core` (19 MB), `kernel-rt-modules-core`
    (41 MB), `kernel-rt-modules`, `-modules-extra`, `-modules-internal`,
    `kernel-rt-devel` (48 MB), `-matched` stubs.
  - `Requires: realtime-setup` is on the `kernel-rt` META only — NOT on
    `kernel-rt-core`/`-modules-core`. So the minimal bootc install set =
    `kernel-rt-core` + `kernel-rt-modules-core` (~58 MB) and needs no
    realtime-setup — closure de-risked.
- **The image** (`images/bootc-os-rt/Dockerfile`): `FROM bootc-os`, inject the
  local kernel-rt RPMs (mirrors `ros-core-rpms`, since the RT RPMs are not yet in
  the Hummingbird koji repo), swap stock `kernel*` → `kernel-rt-core` +
  `kernel-rt-modules-core`, regen initramfs for the `+rt` kver, add RT kargs.d,
  `bootc container lint`. Stays bootable (inherits `/sbin/init`, bootloader,
  bootc). No Fedora repos added: the RT kernel shares the stock kernel's runtime
  deps, already in the base.
- **Open:** Secure Boot signing (self-built kernel-rt unsigned by Fedora's key —
  boots only with SB off until signed); **aarch64** RT build (same SRPM + `--with
  rtonly` on a native arm64 box); actually BUILDING/BOOTING the image +
  `cyclictest` latency numbers. Productization = a `hummingbird/rt/` bootc-os
  variant in the containers monorepo (MAIN_PACKAGES kernel swap) once kernel-rt
  is published — see `images/bootc-os-rt/README.md`.

## Established facts (verified during design)

- **Base image:** `quay.io/hummingbird-community/bootc-os:latest`
  - Fedora 43 based; ships `dnf5`, `python3`, `systemd`, `curl`, `ca-certificates`.
  - It is a bootc image: `CMD ["/sbin/init"]`, `LABEL containers.bootc=1`, ships a kernel.
  - On a booted bootc system `/usr` is immutable/image-managed; `/opt`, `/home`,
    `/root`, `/usr/local` are symlinks into writable `/var` and are NOT in the OS image.
- **ROS packages:** `tavie/ros2` COPR (community, unofficial).
  - Supports Fedora 43, ROS 2 **Jazzy**. **x86_64 ONLY** — the COPR has no
    aarch64 build for fedora-43 (`fedora-43-aarch64/repodata/repomd.xml` => 404).
    All images here are x86_64-only. (Confirmed 2026-08-28.)
  - Fedora **FHS layout**: installs under `/usr`, NOT `/opt/ros`.
  - Package names (f42+) match the Ubuntu deb names: `ros-jazzy-ros-core`,
    `ros-jazzy-ros-base`, `ros-jazzy-ament-package` (needed for setup scripts).
  - Setup scripts live at **`/usr/lib64/ros-jazzy/setup.bash`** (and `.sh`) —
    prefix is **`ros-<distro>`** (hyphen), provided by `ros-jazzy-ament-package`.
    NOTE: an earlier draft said `ros2-jazzy` (with a "2") — that path does NOT
    exist; verified via `dnf repoquery --whatprovides`.
  - RPMs are built against the base Fedora's **system Python** — do not add a
    second `python3`.
  - Repo file: `enable-repos.sh` now **authors the `.repo` directly** against the
    COPR results backend (`download.copr.fedorainfracloud.org/results/tavie/ros2/
    fedora-$FED-$basearch/`, gpgkey `.../results/tavie/ros2/pubkey.gpg`) instead
    of `curl`-ing the frontend generator
    (`copr.fedorainfracloud.org/coprs/tavie/ros2/repo/...`). Reason (hit during
    the first real build, 2026-08-29): the frontend generator was returning
    **502 / connection-reset** while the results backend stayed **200** — the
    generated file just points at that backend anyway, so we skip the flaky
    round-trip. Release still pinned to `rpm -E %fedora`, not `$releasever`.

- **Two bootc-os quirks break the COPR install — both handled by
  `enable-repos.sh` (verified 2026-08-28):**
  1. **No stock Fedora repos.** bootc-os enables only
     `public-hummingbird-x86_64-rpms` (+ our COPR). The tavie ROS RPMs need
     ordinary Fedora libraries (`gflags`, `cli11`, `console-bridge`,
     `protobuf`, ...), so we must add the `fedora` + `updates` repos or nothing
     resolves — even `ros-core` fails without them.
  2. **`$releasever` override.** bootc-os sets dnf's `$releasever` to a snapshot
     id (e.g. `20251124-1.15.hum1`, from `VERSION_ID`) while `rpm -E %fedora`
     still reports `43`. The COPR baseurl is `fedora-$releasever-$basearch`, so
     it 404s. We bake the real release (`rpm -E %fedora`) into the baseurls
     rather than touching the global `$releasever` (which bootc's own repo
     resolution relies on).
  - Verified dry-run transaction sizes on fedora-43 x86_64: ros-core 373 pkgs,
    ros-base 558, simulation 1068, gazebo (gz-sim-vendor) 798.

- **Gazebo on Fedora:** there is NO standalone `gazebo` / `gz-sim` package in
  Fedora's repos. The only packaged Gazebo Harmonic comes from tavie as
  ROS-namespaced **vendor** RPMs: `ros-jazzy-gz-sim-vendor`,
  `ros-jazzy-gz-tools-vendor` (the `gz` CLI), `ros-jazzy-gz-rendering-vendor`,
  etc. They install under `/usr/lib64/ros-jazzy/opt/<pkg>/...`; the `gz` binary
  is NOT on PATH until the prefix `setup.bash` is sourced. ROS 2 Jazzy pairs
  with Gazebo **Harmonic** (gz-sim 8.x). The ROS<->Gazebo bridge is
  `ros-jazzy-ros-gz` (pulls `ros-gz-bridge` / `-sim` / `-interfaces` / `-image`).

## Why these choices

- **tavie COPR over RHEL ROS repo:** RHEL ROS installs to `/opt/ros`, which on a
  bootc system is a symlink into `/var` and would NOT survive `bootc upgrade`.
  tavie's `/usr` (FHS) layout lives in the immutable image layer — the whole
  point of building on bootc-os.
- **`.repo` file drop over `dnf copr enable`:** self-contained, no COPR plugin
  dependency, mirrors the reference Dockerfile's "write sources.list" step.
- **ENTRYPOINT/CMD left unset:** inherits `CMD ["/sbin/init"]` from bootc-os so
  the image stays bootable. Container use is served by `ros-entrypoint.sh`
  (`--entrypoint`) and `/etc/profile.d/ros2.sh` (interactive/login shells).

## Files

```
images/ros-core/Dockerfile        FROM bootc-os; runs enable-repos.sh; installs ros-core + ament-package
images/ros-core/enable-repos.sh   adds Fedora repos + release-pinned tavie COPR (see header for why)
images/ros-core/ros-entrypoint.sh sources /usr/lib64/ros-$ROS_DISTRO/setup.bash then exec "$@"
images/ros-core/ros2-profile.sh   /etc/profile.d hook, auto-source for interactive bash login shells
images/ros-base/Dockerfile        FROM ros-core (ARG BASE_IMAGE); adds ros-base
images/ros-core-rpms/Dockerfile   FROM bootc-os; ros-core from HUMMINGBIRD-BUILT RPMs (NO COPR). createrepo_c a local repo from rpms/ (or rpms-x86_64/) then dnf install ros-jazzy-ros-core. Arch-agnostic.
images/ros-core-rpms/enable-repos.sh  adds ONLY the stock Fedora repos (base already has the hummingbird repo → spdlog-1.17); no COPR
images/ros-core-rpms/rpms/         aarch64 ros-jazzy-* RPMs (162; gitignored build artifacts; specs live in the hummingbird-rpms monorepo)
images/ros-core-rpms/rpms-x86_64/  x86_64 ros-jazzy-* RPMs (162; gitignored; kept SEPARATE from aarch64 — never mix arches)
images/bootc-os-rt/Dockerfile     FROM bootc-os; swaps stock kernel -> kernel-rt (PREEMPT_RT) from local RPMs, regen initramfs, RT kargs.d. POC (mirrors ros-core-rpms).
images/bootc-os-rt/kargs.d/10-realtime.toml  RT boot args (preempt=full, nowatchdog; commented isolcpus/nohz_full/rcu_nocbs template)
images/bootc-os-rt/rpms-rt/        local kernel-rt-* RPMs (gitignored build artifacts; produce with scripts/rt-kernel-build.sh)
images/bootc-os-rt/README.md       build/verify + mapping to the productized containers-monorepo hummingbird/rt/ variant
images/simulation/Dockerfile      FROM ros-base (ARG BASE_IMAGE); adds ros-<distro>-simulation (osrf variant; incl. ros_gz bridge)
images/gazebo/Dockerfile          FROM bootc-os; standalone Gazebo Harmonic (gz-*-vendor, NO ROS middleware)
images/gazebo/enable-repos.sh     copy of ros-core's (separate build context; keep in sync)
images/gazebo/gz-entrypoint.sh    sources setup.bash (puts vendored `gz` on PATH) then exec "$@"
images/gazebo/gz-profile.sh       /etc/profile.d hook for interactive bash login shells
images/sim-bundle/Dockerfile      multi-stage: fedora:43 builder installs the gz stack into an isolated /sysroot, then COPY into bootc-os at /usr/lib/ros-sysroot (VARIANT=bridge|simulation|gazebo)
images/sim-bundle/tavie-ros2.repo COPR repo for the builder stage (fedora:43 already has fedora/updates repos+keys)
images/sim-bundle/sim-entrypoint.sh chroot into the sysroot (rbind /proc,/dev,/sys, + X11 socket for GUI) + source setup.bash + set GZ_SIM_SYSTEM_PLUGIN_PATH & GZ_SIM_PHYSICS_ENGINE_PATH (else no plugins/physics load — see below) then exec "$@"; needs --cap-add=sys_admin
scripts/rt-kernel-build.sh        builds kernel-rt from the pinned Fedora kernel SRPM via `--with rtonly` (rpmbuild in a fedora:43 container; native x86_64; WITH_DEBUGINFO=1 for production)
scripts/ec2-verify.sh             native x86_64 build+test of all 5 images (run on an EC2 instance; covers the qemu-blocked Fast-DDS + headless gz sim + integration checks)
scripts/gui-verify.sh             native x86_64 GUI launcher: Xvfb + x11vnc + `gz sim <world>` under software GL, reachable over an SSH tunnel (see "Interactive GUI"); verified 2026-09-02
scripts/gui-cmdvel-demo.sh        native x86_64 "ROS 2 drives the sim via the GUI": pod with gz-gui (diff-drive world, GUI) + ros-bridge (parameter_bridge); `ros2 topic pub /cmd_vel` moves the robot in the live GUI, odometry bridged back; leaves the pod running to drive over VNC; verified 2026-09-02
scripts/integration-rosgz.sh      two-container ROS 2 <-> Gazebo integration (podman pod: gazebo `gz topic` publisher -> ros_gz bridge -> ros2 echo); native x86_64 only
scripts/integration-rosgz-sim.sh  same, but with a REAL running `gz sim -s -r` world bridging /clock (sim time) into ROS 2; native x86_64 only
scripts/integration-ros2gz.sh     REVERSE direction (ROS 2 -> Gazebo): ros2 pub -> bridge (`] `) -> gz-transport subscriber; native x86_64 only
```

### sim-bundle: the multi-stage workaround (isolated sysroot)

Sidesteps the boost-1.83-vs-1.90 and multi-stream-ruby conflicts (see Open
questions) by installing the Gazebo stack on **stock fedora:43** — where the
tavie RPMs resolve cleanly — into an isolated root, then copying that root into
bootc-os at `/usr/lib/ros-sysroot` and running it via `chroot`. The bundled
boost/ruby/ogre live entirely inside the sysroot and never merge with the base
`/usr`, so nothing conflicts; the outer image stays a bootable bootc image.

- **`bridge` variant ✅ built & tested 2026-08-30** (amd64 emulation): 2.17 GB,
  569 pkgs resolved on fedora:43. `ros2 pkg list` shows `ros_gz_bridge`/
  `ros_gz_image`/`ros_gz_interfaces`; `parameter_bridge` ELF loads with ALL libs
  resolved (`ldd` clean). Add `ros-<distro>-ros2cli-common-extensions` for the
  `ros2 pkg`/`run`/... sub-commands (bare `ros2cli` has none).
- **Activation needs `--cap-add=sys_admin`** (chroot bind-mounts /proc,/dev,/sys):
  ```bash
  podman run --rm --platform linux/amd64 --cap-add=sys_admin \
    --entrypoint /usr/bin/sim-entrypoint.sh \
    hummingbird-ros2-poc/sim-bundle:bridge ros2 pkg list
  ```
  chroot (not bwrap): the podman-machine VM blocks nested user namespaces
  (bwrap EINVAL); on a booted bootc host running as root the mounts just work.
- **`simulation` variant ✅ built & tested 2026-08-30** (amd64 emulation):
  `--build-arg VARIANT=simulation`. Installs the full osrf `simulation` set —
  `ros_gz_bridge`/`_image`/`_interfaces`/`_sim` plus the whole gz vendor stack
  (`gz_sim_vendor`, `gz_rendering_vendor`, `gz_ogre_next_vendor`,
  `gz_physics_vendor`, `gz_dartsim_vendor`, ... — 16 gz_* vendor pkgs). The
  boost-1.83/ogre/ruby stack that blocks a native bootc-os install resolves
  cleanly in the isolated fedora:43 sysroot. Verified:
  - `gz sim --version` → **Gazebo Sim 8.11.0** (Harmonic); the ruby `gz` CLI runs.
  - `ros2 pkg list` lists all ros_gz + gz_*_vendor packages.
  - `ldd` clean on `ros_gz_sim/create` and `ros_gz_bridge/parameter_bridge`
    (ALL LIBS RESOLVED).
  - ⚠️ **Headless `gz sim -s` server aborts under qemu** (`std::__throw_out_of_range`
    → `qemu: uncaught target signal 6`, core dumped) — same amd64-on-arm64
    emulation artifact as Fast DDS / parameter_bridge. Re-test full sim
    execution on **native x86_64** before assuming a runtime bug.
- **`gazebo` sim-bundle variant ✅ built & tested 2026-08-30** (amd64 emulation):
  `--build-arg VARIANT=gazebo` — standalone Gazebo Harmonic (gz-sim-vendor +
  gz-tools-vendor, **no** ROS middleware). `gz sim --version` → Gazebo Sim
  8.11.0; the `gz` CLI resolves to
  `/usr/lib64/ros-jazzy/opt/gz_tools_vendor/bin/gz`; gz-sim plugin `.so`s are
  `ldd`-clean. Same qemu headless-server caveat as the simulation variant.
- **sim-bundle image sizes** (amd64): bridge 2.19 GB, gazebo 4.5 GB,
  simulation 4.83 GB (base bootc-os 909 MB + the copied sysroot).

### Interactive GUI (gz sim -g) — supported, runtime-only concern (2026-08-30)

The **GUI stack is already fully bundled** in the `gazebo` and `simulation`
variants — no extra build/packaging needed. Verified present in the sysroot:
`gz_gui_vendor` (gz-gui-8 + its plugins: MinimalScene, Grid3D, Camera*, ...),
`gz_ogre_next_vendor`, `gz_rendering_vendor`, Qt5 xcb platform plugin
(`/usr/lib64/qt5/plugins/platforms/libqxcb.so`), `libGL`/`libEGL`, and a
COMPLETE Mesa (`/usr/lib64/dri`: hardware drivers `iris`/`radeonsi`/`nouveau`/
`virtio_gpu` **and** software `swrast_dri.so`/`kms_swrast_dri.so`/`zink_dri.so`).
`gz sim -g` ("Run only the GUI") is a supported mode.

**✅ GUI VERIFIED on native x86_64 (headless EC2, software GL) 2026-09-02.** A
plain `gz sim <world>` (server + GUI in one process, NO `--gui-config`, NO env
overrides) renders the full standard Gazebo GUI from the image alone: 3D
viewport (ground grid, a falling ball + its shadow), the shape/transform
toolbars, the Component Inspector (Physics Engine Plugin
`gz-physics-dartsim-plugin`, Solver `DantzigBoxedLcpSolver`, Collision Detector
`ode`) and the Entity Tree (default/ground/ball/sun). Rendered on an AL2023
`c6i` box with **no GPU** via bundled Mesa **software GL** (`swrast`/`llvmpipe`,
`LIBGL_ALWAYS_SOFTWARE=1`), on an `Xvfb :99` virtual display served over
`x11vnc` (localhost) through an SSH tunnel. Screenshot color count 11.8k
(vs 1 for a blank window); zero config/QML/rendering errors in the `-v3` log.
Reproduce with **`scripts/gui-verify.sh`** (see below).

**✅ ROS 2 drives the sim THROUGH the GUI — verified 2026-09-02** (same box).
`scripts/gui-cmdvel-demo.sh` stands up the two-container co-sim in one pod:
`gz-gui` (a diff-drive `vehicle_blue` world, GUI + physics, running) +
`ros-bridge` (`ros_gz parameter_bridge` mapping `/cmd_vel` ROS→gz and
`/model/vehicle_blue/odometry` gz→ROS). `ros2 topic pub /cmd_vel
geometry_msgs/msg/Twist '{linear:{x:1.0},angular:{z:0.4}}'` → bridge →
gz-transport (shared pod netns, `GZ_IP=127.0.0.1`) → the DiffDrive plugin drove
the robot visibly across the live GUI; odometry read back over ROS 2 went from
x≈0,y≈0 to x≈0.1,y≈5.0. This is the full ROS `/cmd_vel` actuation + sensor-return
loop with the GUI attached. ⚠️ Software GL is CPU-bound: run only ONE gz GUI at a
time — two concurrent GUIs starve llvmpipe and paint nothing (colors=1).

- **Runtime plugin/QML wiring needed — now baked into `sim-entrypoint.sh`.**
  Same baked-BUILDROOT-path defect as the headless physics engine, but the GUI
  needs *more* paths than the server: `sim-entrypoint.sh` now also exports
  `GZ_GUI_PLUGIN_PATH` (gz-gui + gz-sim GUI plugins), `GZ_RENDERING_PLUGIN_PATH`
  (ogre2 engine), `GZ_RENDERING_RESOURCE_PATH` (OGRE HLMS shader media — the
  baked path is `ogre2/src/media`, the real one is `ogre2/media`) and
  **`QML2_IMPORT_PATH`** (the gz-sim `gui/` dir holding the `GzSim` QML module —
  without it Qt errors `module "GzSim" is not installed` and gz then fails to
  load the whole GUI config, leaving a blank window). It also seeds the real
  default `gui.config` into `$HOME/.gz/sim/<v>/` since gz looks for it at the
  missing BUILDROOT path. All globbed from the sysroot; no-ops on the `bridge`
  variant. This was the last missing piece — with it, plain `gz sim <world>`
  "just works" from the image.

So a GUI Gazebo on bootc-os is proven feasible — the base image is NOT the
blocker. The only external requirement is a **runtime display** (GPU optional —
software GL works):
- `sim-entrypoint.sh` binds the host X11 socket (`/tmp/.X11-unix`) and an
  `XAUTHORITY` file into the chroot; `DISPLAY`/`XAUTHORITY`/`LIBGL_ALWAYS_SOFTWARE`
  pass through chroot as env. Headless behaviour is unchanged.
- Headless-box recipe (Xvfb + VNC, software GL, no GPU) — **verified**, use
  `scripts/gui-verify.sh`; connect with
  `ssh -i KEY -L 5900:localhost:5900 ec2-user@HOST` then `open vnc://localhost:5900`.
- Run recipe (X11 host + GPU):
  ```bash
  xhost +local:
  podman run --rm --platform linux/amd64 --cap-add=sys_admin \
    --net=host --device /dev/dri -e DISPLAY -e XAUTHORITY \
    -v /tmp/.X11-unix:/tmp/.X11-unix \
    --entrypoint /usr/bin/sim-entrypoint.sh \
    hummingbird-ros2-poc/sim-bundle:gazebo gz sim -g
  ```
  Software-GL fallback (no GPU): drop `--device /dev/dri`, add
  `-e LIBGL_ALWAYS_SOFTWARE=1` (Mesa swrast/zink are bundled — works, slow).
- ⚠️ **GUI is x86_64-native only** — it will NOT run under amd64-on-arm64 qemu
  (no GPU passthrough; software GL under qemu is unusable and crashes like the
  headless physics engine did). Run on a native x86_64 host (software GL is
  fine), or on a booted bootc machine with its own compositor/GPU.

Two deployment shapes for GUI use:
  (a) **Container GUI** on an x86_64 Linux workstation — the run recipe above
      (mirrors upstream `gazebosim/gz-sim` `Dockerfile.gz`, which is itself a
      GPU/GUI workstation image `FROM nvidia/opengl`).
  (b) **Booted bootc robot/workstation** — the image boots (inherits
      `/sbin/init`) and runs `gz sim -g` on the machine's own display/GPU via a
      compositor; the cleanest fit for GPU (no container display gymnastics),
      and the one bootc is actually designed for. Would need a compositor
      (Weston/GNOME) layered onto the base — a follow-up.

Architecture: `simulation` is a ROS image (the osrf variant incl. the ros_gz
bridge, `FROM ros-base`); `gazebo` is a separate simulator image (`FROM
bootc-os`, no rclcpp/ros-core). Run them together (same pod / shared network) to
co-simulate — the bridge relays between ROS 2 and the Gazebo simulator. (The
`simulation` variant also pulls the Gazebo gz-*-vendor libs since ros_gz_sim
links them, so it overlaps `gazebo`; the standalone `gazebo` image remains the
ROS-free simulator.) `enable-repos.sh` is duplicated in the two
`FROM bootc-os` contexts (ros-core, gazebo); a future cleanup could share it via
a common build context or a thin repos-only base image.

## Build

All images are **x86_64-only** (tavie has no aarch64 build). On an arm64 host
(e.g. Apple Silicon) add `--platform linux/amd64` to build/run under emulation.

```bash
podman build -t hummingbird-ros2-poc/ros-core:latest images/ros-core
podman build -t hummingbird-ros2-poc/ros-base:latest images/ros-base
# ros-core from Hummingbird-built RPMs (no COPR). Build on the MATCHING arch —
# aarch64 uses rpms/, x86_64 uses rpms-x86_64/ (stage the right set into ./rpms/
# first, since the Dockerfile COPYs rpms/). Native per arch; no emulation.
podman build -t hummingbird-ros2-poc/ros-core-rpms:latest images/ros-core-rpms
# bootc-os with a PREEMPT_RT kernel. Stage kernel-rt RPMs into images/bootc-os-rt/rpms-rt/
# first (build them with scripts/rt-kernel-build.sh). Native per arch; no emulation.
podman build -t hummingbird-ros2-poc/bootc-os-rt:latest images/bootc-os-rt
# native simulation/gazebo are BLOCKED (boost skew) — use sim-bundle instead:
podman build --build-arg VARIANT=bridge     -t hummingbird-ros2-poc/sim-bundle:bridge     images/sim-bundle
podman build --build-arg VARIANT=simulation -t hummingbird-ros2-poc/sim-bundle:simulation images/sim-bundle
podman build --build-arg VARIANT=gazebo     -t hummingbird-ros2-poc/sim-bundle:gazebo     images/sim-bundle
```

## Verification status & how to test

- **Local (this laptop, arm64 + amd64 qemu) — DONE 2026-08-30.** All five
  buildable images build and pass everything testable under emulation:
  ros-core (`ros2` + pub/sub), ros-base (tf2/rosbag2/...), sim-bundle
  bridge/simulation/gazebo (`gz sim --version`, `ros_gz` pkgs, `ldd`-clean).
  - **DDS-in-container note:** cyclonedds pub/sub needs `ROS_LOCALHOST_ONLY=1`
    to discover under qemu (multicast is flaky in the podman-machine VM);
    loopback works. Default Fast DDS still doesn't discover under qemu.
- **Native x86_64 (EC2) — ✅ DONE 2026-08-31. ALL CHECKS PASSED.** Ran
  **`scripts/ec2-verify.sh`** on an AL2023 `c6i.2xlarge` (8 vCPU / 15 GB / 80 GB
  gp3), rootful **podman 5.6.1**. Rebuilt all five natively (no `--platform`) and
  every check passed — crucially the three that CANNOT run under qemu:
  - **default Fast DDS pub/sub ✅** (the qemu shared-memory-transport failure was
    emulation-only).
  - **headless `gz sim -s` physics ✅ — and a real gap found + fixed here.** The
    server runs natively (the qemu abort was emulation-only). BUT the raw logs
    exposed that it started WITHOUT physics: `Failed to load system plugin
    [gz-sim-physics-system]` then `Failed to find plugin [gz-physics-dartsim-plugin]
    ... GZ_SIM_PHYSICS_ENGINE_PATH`. Root cause: the vendored `setup.bash` sets
    only `GZ_CONFIG_PATH`, not `GZ_SIM_SYSTEM_PLUGIN_PATH` /
    `GZ_SIM_PHYSICS_ENGINE_PATH`, so no system plugin and no physics engine
    loaded — yet `/clock` still advanced and the process exited 0, so a bare
    rc/iteration check (the old ec2-verify check) passed anyway. **Fix:**
    `sim-entrypoint.sh` now globs the sysroot for
    `gz_sim_vendor/lib64/gz-sim-*/plugins` and
    `gz_physics_vendor/lib64/gz-physics-*/engine-plugins` and exports both paths.
    Re-verified from the image alone (no `-e` overrides): a free body falls under
    gravity — Z drops from 10 to ≈-65 in ~3 s, and the sim log is error-free.
    `ec2-verify.sh` now asserts this (min Z < 9) instead of just rc=0.
  - **two-container ROS 2 ↔ Gazebo integration ✅** (`scripts/integration-rosgz.sh`)
    — a Gazebo-container message crossed gz-transport → parameter_bridge → DDS →
    `ros2 topic echo`, confirming the gz-transport multicast crash was purely
    qemu-user. Also verified with a **real running simulator**
    (`scripts/integration-rosgz-sim.sh`): a live `gz sim -s -r` world published
    `/clock`, the bridge relayed it (gz.msgs.Clock → rosgraph_msgs/msg/Clock),
    and `ros2 topic echo` printed advancing simulation time (`sec: 18`). The
    **reverse direction (ROS 2 → Gazebo)** is also verified
    (`scripts/integration-ros2gz.sh`, the bridge's `] ` mode): a ROS 2 publisher
    reached a gz-transport subscriber in the Gazebo container — the bridge is
    confirmed **bidirectional** (this is the ROS `/cmd_vel` → sim actuation path).
  Also green: ros-core (ros2 CLI, Cyclone DDS, `bootc container lint`), ros-base
  (tf2/tf2_ros/robot_state_publisher/geometry_msgs/rosbag2), bridge (ros_gz pkgs +
  `ldd`-clean parameter_bridge), simulation & gazebo (`gz sim --version`, gazebo
  ROS-free). Sizes: ros-core 1.96, bridge 2.19, gazebo 4.5, simulation 4.83 GB.
  - NOTE: this AL2023 "kernel-6.18" AMI shipped `docker`/`buildah` but NOT
    `podman` in its repo snapshot — podman was installed manually before the run.
  - To reproduce: fresh x86_64 instance (Fedora / AL2023 / Ubuntu) + `podman`,
    then `./scripts/ec2-verify.sh`. GUI (`gz sim -g`) still needs a display + GPU
    (`g4dn`/`g5`) and remains deferred (see "Interactive GUI" above).
- **Two-container integration (`scripts/integration-rosgz.sh`) — ✅ PASSED on
  native x86_64 (EC2) 2026-08-31; cannot run on this laptop.** Creates a podman
  **pod** (shared net ns) with
  a `sim-bundle:gazebo` container publishing on the gz side and a
  `sim-bundle:bridge` container running `ros_gz parameter_bridge` + `ros2 topic
  echo`, and asserts the message crosses gz-transport → bridge → DDS. It is wired
  into `ec2-verify.sh` as the final (soft) check.
  - ⚠️ **Why not on the laptop: gz-transport aborts under amd64-on-arm64
    qemu-user.** EVERY gz-transport operation (`gz sim -s`, `gz topic -l/-p/-e`,
    `parameter_bridge`) reproducibly crashes: `Error setting socket option
    (IP_MULTICAST_IF)` → `[<ip>] seems an invalid local IP address` →
    `std::out_of_range: vector::_M_range_check (0 >= 0)` → `qemu: uncaught target
    signal 6 (Aborted)`. NOT fixed by `GZ_IP=127.0.0.1`, `--net=host`, or a pod.
    There is no gz-transport equivalent of `ROS_LOCALHOST_ONLY` to force unicast.
    The failure is in gz-transport's **multicast socket setup** under qemu — NOT
    getifaddrs (a ctypes probe confirmed `getifaddrs` works under qemu: rc=0, 6
    valid entries for lo/eth0; an earlier "empty getifaddrs" hypothesis was
    DISPROVEN). The ROS-only side works here (cyclonedds + `ROS_LOCALHOST_ONLY=1`);
    only the Gazebo/gz-transport leg is blocked. Emulation artifact, not an image
    bug — must be validated on native x86_64.

## Test plan (this is what to run/verify here)

1. **Build succeeds.** ✅ **ros-core built & tested 2026-08-29** (amd64 emulation
   on an arm64 host): `podman build --platform linux/amd64 -t
   hummingbird-ros2-poc/ros-core:latest images/ros-core` → 377 pkgs, GPG-verified,
   **1.96 GB**. The repo/dep issues that used to block this are handled by
   `enable-repos.sh` (Fedora repos + backend-pinned COPR, see Established facts).
   If the tavie backend is ever unreachable, fall back to
   `dnf -y copr enable tavie/ros2` (may require `dnf5-plugins`).
2. **Packages resolve.** Already verified via `--assumeno` dry-run on
   fedora-43 x86_64 (ros-core 373, ros-base 558, simulation 1068, gazebo 798
   pkgs, no unmet deps). Re-confirm after any base-image or COPR bump.
   Gazebo smoke test:
   ```bash
   podman run --rm --platform linux/amd64 \
     --entrypoint /usr/bin/gz-entrypoint.sh \
     hummingbird-ros2-poc/gazebo:latest gz sim --version
   ```
   ROS<->Gazebo bridge (in the simulation image):
   ```bash
   podman run --rm --platform linux/amd64 \
     --entrypoint /usr/bin/ros-entrypoint.sh \
     hummingbird-ros2-poc/simulation:latest ros2 pkg list | grep ros_gz
   ```
3. **Env sources cleanly:**
   ```bash
   podman run --rm --entrypoint /usr/bin/ros-entrypoint.sh \
     hummingbird-ros2-poc/ros-base:latest ros2 doctor
   ```
4. **Interactive shell auto-sources ROS:**
   ```bash
   podman run --rm -it hummingbird-ros2-poc/ros-base:latest bash
   #   ros2 topic list   # should work without manual sourcing
   ```
5. **Smoke test pub/sub** (talker/listener) using `demo_nodes_cpp` if pulled in,
   or `ros2 topic pub` + `ros2 topic echo`. ✅ **verified on ros-core 2026-08-29**
   — but only with **Cyclone DDS**:
   ```bash
   podman run --rm --platform linux/amd64 \
     -e RMW_IMPLEMENTATION=rmw_cyclonedds_cpp \
     --entrypoint /usr/bin/ros-entrypoint.sh \
     hummingbird-ros2-poc/ros-core:latest bash -c \
     'ros2 topic pub -r5 /chatter std_msgs/msg/String "{data: hi}" & \
      sleep 6; ros2 topic echo --once /chatter std_msgs/msg/String'
   ```
   ⚠️ **DDS-under-qemu caveat:** the *default* Fast DDS (`rmw_fastrtps_cpp`)
   pub/sub does NOT work under amd64-on-arm64 emulation — the topic is never
   discovered (its shared-memory transport fails under qemu). This is an
   **emulation artifact**, not an image bug; Fast DDS should work on a native
   x86_64 host. Both middlewares are packaged. Re-test the default on real
   x86_64 hardware before assuming it's fine there.
6. **(Stretch) bootability:** ✅ **ros-core confirmed bootc-valid 2026-08-29** —
   it keeps `CMD ["/sbin/init"]`, `LABEL containers.bootc=1`, a kernel
   (`/usr/lib/modules/*/vmlinuz`) and the `bootc` binary from the base;
   `bootc container lint` passes 11 checks (2 cosmetic warnings: leftover
   `/run/dnf` and a `/var/lib/dnf` tmpfiles entry — harmless, tidy the Dockerfile
   cleanup if desired). To actually boot it, convert to a qcow2 with
   `quay.io/centos-bootc/bootc-image-builder` and confirm ROS sources in an SSH
   login shell (not yet done).

## Open questions / risks

- **Build status (real `podman build`, 2026-08-29/30, amd64 emulation):**
  - `ros-core` ✅ built (1.96 GB) + smoke-tested (env, pub/sub, bootc-valid).
  - `ros-base` ✅ built (2.29 GB) + smoke-tested (199 pkgs; tf2, tf2_ros,
    robot_state_publisher, rosbag2, geometry_msgs all present).
  - `simulation` ❌ **BLOCKED — boost version skew.** `gazebo` ❌ blocked by the
    **same** chain (both pull the gz rendering stack). See next bullet.
- **⚠️ Gazebo rendering vs bootc-os boost — a real, unresolved blocker (found
  2026-08-30; INVALIDATES the earlier "simulation 1068 / gazebo 798, no unmet
  deps" dry-run, which must have run against a different base/repo state):**
  The Gazebo dep chain is
  `ros-jazzy-simulation → ros-gz-sim → gz-sim-vendor → gz-rendering-vendor →
  libOgreMain.so.1.9.0`. The ONLY provider is Fedora's **`ogre-1:1.9.0-52.fc43`**,
  which is built against **boost 1.83** (`libboost_thread.so.1.83.0` →
  `boost-system = 1.83`). But bootc-os ships **boost 1.90**, and its
  `boost-filesystem-1.90` **Obsoletes/Conflicts boost-system < 1.90** — so the
  old boost 1.83 the rendering stack needs cannot be installed alongside the
  base's boost 1.90. `gz-sim-vendor` hard-requires `gz-rendering-vendor` even
  headless, so this blocks BOTH `simulation` and `gazebo`; there is no
  rendering-free subset. Not fixable by repo config (`--allowerasing` would try
  to rip boost 1.90 out of the base OS and cascade). Real fixes need one of:
  (a) tavie rebuilds `gz-rendering-vendor` against a boost-1.90-compatible ogre
  (e.g. ogre-next) or vendors ogre; (b) a bootc-os base pinned to boost 1.83
  (unlikely / regressive); (c) build the gz stack ourselves against boost 1.90.
  ros-core/ros-base are unaffected (they don't touch ogre/boost-thread).
- **Image size:** measured ros-core = **1.96 GB** (base bootc-os = 909 MB; the
  ROS install layer adds ~1.05 GB). Two structural reasons it dwarfs osrf's
  Ubuntu `ros:jazzy-ros-core` (~0.7 GB):
  1. **The base is a full bootable OS, not a minimal userland.** bootc-os ships a
     kernel (`kernel-core`+`kernel-modules` ≈ 273 MB), systemd, dnf, *and*
     container tooling (podman 49 MB, containernetworking-plugins 71 MB, skopeo
     26 MB, bootc). osrf is `FROM ubuntu:noble` (~78 MB, no kernel, no init).
  2. **The tavie RPMs pull a full C/C++ build toolchain into ros-core** that the
     Ubuntu runtime image omits: `boost-devel` 143 MB, `gcc` 122 MB, `cpp` 43 MB,
     `libstdc++-devel` 41 MB, `cmake` 40 MB, `binutils` 28 MB, plus `git-core`,
     `python3-pytest`, etc. On Ubuntu these live in the *dev*/`ros-base` image,
     not runtime `ros-core`. The Fedora ROS RPMs `Require:` the `-devel` packages
     directly, so they land even in ros-core.
  simulation (1068 pkgs) and gazebo (798 pkgs) will be far larger still. This
  motivates either a slimmer non-bootc variant, keeping gazebo/simulation off the
  bootable images, or (if tavie's packaging allows) excluding the `-devel`
  Requires from the runtime image.
- **Gazebo rendering:** gz-sim's GUI/sensors need OpenGL/GPU (ogre-next). Headless
  server (`gz sim -s`) should work in a container; the GUI needs GPU/display
  passthrough. Verify what the POC actually requires.
- **arm64:** tavie is x86_64-only, so the COPR-sourced images
  (`gazebo`/`simulation`/`sim-bundle`) stay x86_64-only. RESOLVED for the base
  stack, though: we built the `ros_core` RPMs ourselves for aarch64 too (see "ROS
  2 as Hummingbird-built RPMs" above) — `images/ros-core-rpms` runs natively on
  arm64. Extending that to `ros-base`/Gazebo would lift the arch limit everywhere.
- **Fedora GPG keys:** bootc-os ships none, so `enable-repos.sh` points the
  `fedora`/`updates` repos at the online Fedora key
  (`src.fedoraproject.org/.../RPM-GPG-KEY-fedora-<rel>-primary`); dnf imports it
  at install. If that URL/layout changes, the key import breaks.
- Python version coupling: bootc-os system python must match what the COPR RPMs
  were built against (Fedora 43 system python3; RPMs seen under python3.14).
- `enable-repos.sh` is duplicated across the two `FROM bootc-os` contexts — keep
  the copies in sync (or refactor to a shared base).

## Provenance

Design conversation ran in `../containers` (the Hummingbird containers repo).
Reference upstream: `osrf/docker_images` (generated Dockerfiles) and
`osrf/docker_templates` (the `.em` empy templates). ROS 2 base metapackages are
defined in `ros2/variants` (`ros_core`, `ros_base` `package.xml`) and turned
into packages via bloom — the Dockerfiles only reference the metapackage name.

### Upstream reference Dockerfiles — where each variant actually lives (verified 2026-08-30)

- **ROS 2 variants** (`osrf/docker_images`, path
  `ros/jazzy/ubuntu/noble/<variant>/Dockerfile`): SIX variants are *defined* —
  `ros-core`, `ros-base`, `perception`, `simulation`, `desktop`, `desktop-full`
  (= REP 2001). But the **official Docker Library (`library/ros`) only publishes
  `ros-core`, `ros-base`, `perception`** as pullable tags. `simulation`/`desktop`/
  `desktop-full` are defined + buildable-from-source but NOT published (GUI/size).
  So "the upstream simulation variant" = the *Dockerfile* + the `ros-jazzy-simulation`
  metapackage, there is NO `ros:jazzy-simulation` tag to pull. Our sim-bundle
  `simulation` reproduces that Dockerfile (`FROM ros-base` + `ros-jazzy-simulation`);
  it contains the Gazebo runtime because the metapackage deps (`ros_gz` → the sim)
  pull it — same as upstream.
- **Gazebo Classic (v4–11)**: `osrf/docker_images` under `gazebo/<ver>/...`
  (Ubuntu/Debian, apt from `packages.osrfoundation.org`). Entrypoint convention:
  `source setup.sh; exec "$@"`, `ENTRYPOINT ["/gzserver_entrypoint.sh"]`,
  `CMD ["gzserver"]`, `EXPOSE 11345` (Classic master port — N/A to modern gz,
  which uses gz-transport UDP multicast discovery).
- **Modern Gazebo (gz-sim, Harmonic)**: NOT in `osrf/docker_images`. Lives in
  **`gazebosim/gz-sim/docker/`** — `Dockerfile.base`, `Dockerfile.gz` (main),
  `Dockerfile.nightly`. `Dockerfile.gz` is a **GPU/GUI workstation** image:
  `FROM nvidia/opengl:1.2-glvnd-devel-ubuntu20.04`, apt-installs `${gz_distribution}`
  from the OSRF repo, creates a non-root `developer` user + sudo, `ENTRYPOINT
  ["gz sim"]`. It sets NO `GZ_*`/`GAZEBO_*` env (relies on the install's default
  paths). It is explicitly GPU-oriented — not a minimal/bootable server image.
  (`gazebo-tooling/release-tools/bloom/ros_gz/Dockerfile` covers ros_gz bridge
  packaging.)
