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
images/simulation/Dockerfile      FROM ros-base (ARG BASE_IMAGE); adds ros-<distro>-simulation (osrf variant; incl. ros_gz bridge)
images/gazebo/Dockerfile          FROM bootc-os; standalone Gazebo Harmonic (gz-*-vendor, NO ROS middleware)
images/gazebo/enable-repos.sh     copy of ros-core's (separate build context; keep in sync)
images/gazebo/gz-entrypoint.sh    sources setup.bash (puts vendored `gz` on PATH) then exec "$@"
images/gazebo/gz-profile.sh       /etc/profile.d hook for interactive bash login shells
images/sim-bundle/Dockerfile      multi-stage: fedora:43 builder installs the gz stack into an isolated /sysroot, then COPY into bootc-os at /usr/lib/ros-sysroot (VARIANT=bridge|simulation|gazebo)
images/sim-bundle/tavie-ros2.repo COPR repo for the builder stage (fedora:43 already has fedora/updates repos+keys)
images/sim-bundle/sim-entrypoint.sh chroot into the sysroot (rbind /proc,/dev,/sys, + X11 socket for GUI) + source setup.bash then exec "$@"; needs --cap-add=sys_admin
scripts/ec2-verify.sh             native x86_64 build+test of all 5 images (run on an EC2 instance; covers the qemu-blocked Fast-DDS + headless gz sim + integration checks)
scripts/integration-rosgz.sh      two-container ROS 2 <-> Gazebo integration (podman pod: gazebo publisher -> ros_gz bridge -> ros2 echo); native x86_64 only
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

So a GUI Gazebo on bootc-os is entirely feasible — the base image is NOT the
blocker. The only requirements are **runtime display + GPU access**:
- `sim-entrypoint.sh` now binds the host X11 socket (`/tmp/.X11-unix`) and an
  `XAUTHORITY` file into the chroot; `DISPLAY`/`XAUTHORITY`/`LIBGL_ALWAYS_SOFTWARE`
  pass through chroot as env. Headless behaviour is unchanged.
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
  headless physics engine did). Must be tested on a native x86_64 host with a
  display, or on a booted bootc machine with its own compositor/GPU. NOT YET
  tested — no native x86_64 host available in this POC.

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
  - **headless `gz sim -s` physics stepping (200 iters) ✅** (the abort was an
    emulation artifact, NOT an image bug).
  - **two-container ROS 2 ↔ Gazebo integration ✅** (`scripts/integration-rosgz.sh`)
    — a Gazebo-container message crossed gz-transport → parameter_bridge → DDS →
    `ros2 topic echo`, confirming the gz-transport multicast crash was purely
    qemu-user.
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
- **arm64:** tavie is x86_64-only. If target robots are arm64, this whole
  package source is a dead end — would need another ROS-on-Fedora source or to
  build the RPMs ourselves. (POC scoped to x86_64.)
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
