# Verification status & test plan

> Detail doc for [`../CLAUDE.md`](../CLAUDE.md).

## Verification status

- **Local (laptop, arm64 + amd64 qemu) — DONE 2026-08-30.** All five buildable
  images build and pass everything testable under emulation: ros-core (`ros2` +
  pub/sub), ros-base (tf2/rosbag2/...), sim-bundle bridge/simulation/gazebo
  (`gz sim --version`, `ros_gz` pkgs, `ldd`-clean).
  - **DDS-in-container note:** cyclonedds pub/sub needs `ROS_LOCALHOST_ONLY=1` to
    discover under qemu (multicast is flaky in the podman-machine VM); loopback
    works. Default Fast DDS still doesn't discover under qemu.
- **Native x86_64 (EC2) — ✅ DONE 2026-08-31. ALL CHECKS PASSED.** Ran
  `scripts/ec2-verify.sh` on an AL2023 `c6i.2xlarge` (8 vCPU / 15 GB / 80 GB gp3),
  rootful **podman 5.6.1**. Rebuilt all five natively (no `--platform`); every
  check passed — crucially the three that CANNOT run under qemu:
  - **default Fast DDS pub/sub ✅** (the qemu shared-memory-transport failure was
    emulation-only).
  - **headless `gz sim -s` physics ✅ — and a real gap found + fixed here.** The
    server runs natively, but raw logs exposed it started WITHOUT physics:
    `Failed to load system plugin [gz-sim-physics-system]` then `Failed to find
    plugin [gz-physics-dartsim-plugin] ... GZ_SIM_PHYSICS_ENGINE_PATH`. Root
    cause: the vendored `setup.bash` sets only `GZ_CONFIG_PATH`, not
    `GZ_SIM_SYSTEM_PLUGIN_PATH` / `GZ_SIM_PHYSICS_ENGINE_PATH`. **Fix:**
    `sim-entrypoint.sh` now globs the sysroot for the gz-sim plugins + gz-physics
    engine-plugins and exports both paths. Re-verified from the image alone: a
    free body falls under gravity — Z drops from 10 to ≈-65 in ~3 s, log
    error-free. `ec2-verify.sh` now asserts min Z < 9 instead of just rc=0.
  - **two-container ROS 2 ↔ Gazebo integration ✅** (`scripts/integration-rosgz.sh`)
    — a Gazebo-container message crossed gz-transport → parameter_bridge → DDS →
    `ros2 topic echo`. Also verified with a **real running simulator**
    (`scripts/integration-rosgz-sim.sh`): a live `gz sim -s -r` world published
    `/clock`, the bridge relayed it, `ros2 topic echo` printed advancing sim time.
    The **reverse direction** is verified too (`scripts/integration-ros2gz.sh`, the
    bridge's `]` mode): ROS 2 publisher → gz-transport subscriber. Bridge
    confirmed **bidirectional** (the ROS `/cmd_vel` → sim actuation path).
  Also green: ros-core (ros2 CLI, Cyclone DDS, `bootc container lint`), ros-base
  (tf2/tf2_ros/robot_state_publisher/geometry_msgs/rosbag2), bridge, simulation &
  gazebo. Sizes: ros-core 1.96, bridge 2.19, gazebo 4.5, simulation 4.83 GB.
  - NOTE: this AL2023 "kernel-6.18" AMI shipped `docker`/`buildah` but NOT
    `podman` — install podman manually before the run.
  - Reproduce: fresh x86_64 instance (Fedora / AL2023 / Ubuntu) + `podman`, then
    `./scripts/ec2-verify.sh`. GUI (`gz sim -g`) needs a display + GPU
    (`g4dn`/`g5`) and remains deferred (see [`simulation-gazebo.md`](simulation-gazebo.md)).

### Why gz-transport can't be tested under qemu

EVERY gz-transport op (`gz sim -s`, `gz topic -l/-p/-e`, `parameter_bridge`)
reproducibly crashes under amd64-on-arm64 qemu-user: `Error setting socket option
(IP_MULTICAST_IF)` → `[<ip>] seems an invalid local IP address` →
`std::out_of_range: vector::_M_range_check (0 >= 0)` → signal 6. NOT fixed by
`GZ_IP=127.0.0.1`, `--net=host`, or a pod. The failure is in gz-transport's
**multicast socket setup** under qemu — NOT getifaddrs (a ctypes probe confirmed
getifaddrs works under qemu). The ROS-only side works here (cyclonedds +
`ROS_LOCALHOST_ONLY=1`); only the Gazebo/gz-transport leg is blocked. Emulation
artifact — validate on native x86_64.

## Test plan (what to run/verify here)

1. **Build succeeds.** ✅ ros-core built & tested 2026-08-29 (amd64 emulation):
   `podman build --platform linux/amd64 -t hummingbird-ros2-poc/ros-core:latest
   images/ros-core` → 377 pkgs, GPG-verified, 1.96 GB. If the tavie backend is
   unreachable, fall back to `dnf -y copr enable tavie/ros2` (may need
   `dnf5-plugins`).
2. **Packages resolve.** Verified via `--assumeno` dry-run on fedora-43 x86_64
   (ros-core 373, ros-base 558). Re-confirm after any base/COPR bump.
   ```bash
   # Gazebo smoke test
   podman run --rm --platform linux/amd64 --entrypoint /usr/bin/gz-entrypoint.sh \
     hummingbird-ros2-poc/gazebo:latest gz sim --version
   # ROS<->Gazebo bridge (simulation image)
   podman run --rm --platform linux/amd64 --entrypoint /usr/bin/ros-entrypoint.sh \
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
5. **Smoke test pub/sub.** ✅ verified on ros-core 2026-08-29 — but only with
   **Cyclone DDS**:
   ```bash
   podman run --rm --platform linux/amd64 \
     -e RMW_IMPLEMENTATION=rmw_cyclonedds_cpp \
     --entrypoint /usr/bin/ros-entrypoint.sh \
     hummingbird-ros2-poc/ros-core:latest bash -c \
     'ros2 topic pub -r5 /chatter std_msgs/msg/String "{data: hi}" & \
      sleep 6; ros2 topic echo --once /chatter std_msgs/msg/String'
   ```
   ⚠️ The *default* Fast DDS pub/sub does NOT work under amd64-on-arm64 emulation
   (shared-memory transport fails) — emulation artifact, works on native x86_64.
6. **(Stretch) bootability:** ✅ ros-core confirmed bootc-valid 2026-08-29 — keeps
   `CMD ["/sbin/init"]`, `LABEL containers.bootc=1`, a kernel, and `bootc`;
   `bootc container lint` passes (2 cosmetic warnings). To actually boot, convert
   to a qcow2 with `quay.io/centos-bootc/bootc-image-builder` and confirm ROS
   sources in an SSH login shell (not yet done for the COPR images; RT images
   booted — see [`realtime-kernel.md`](realtime-kernel.md)).

## Build-status snapshot (real `podman build`, amd64 emulation 2026-08-29/30)

- `ros-core` ✅ built (1.96 GB) + smoke-tested (env, pub/sub, bootc-valid).
- `ros-base` ✅ built (2.29 GB) + smoke-tested (199 pkgs; tf2, tf2_ros,
  robot_state_publisher, rosbag2, geometry_msgs).
- `simulation` / `gazebo` ❌ **BLOCKED natively — boost version skew** (see
  [`simulation-gazebo.md`](simulation-gazebo.md)); use sim-bundle instead.

## Image size — why ros-core (1.96 GB) dwarfs osrf's Ubuntu ~0.7 GB

1. **The base is a full bootable OS, not a minimal userland.** bootc-os ships a
   kernel (~273 MB), systemd, dnf, *and* container tooling (podman 49 MB,
   containernetworking-plugins 71 MB, skopeo 26 MB, bootc). osrf is `FROM
   ubuntu:noble` (~78 MB, no kernel, no init).
2. **The tavie RPMs pull a full C/C++ toolchain into ros-core** that the Ubuntu
   runtime image omits: `boost-devel` 143 MB, `gcc` 122 MB, `cpp` 43 MB,
   `libstdc++-devel` 41 MB, `cmake` 40 MB, `binutils` 28 MB, plus `git-core`,
   `python3-pytest`, etc. The Fedora ROS RPMs `Require:` the `-devel` packages
   directly, so they land even in ros-core.

Motivates either a slimmer non-bootc variant, keeping gazebo/simulation off the
bootable images, or (if tavie's packaging allows) excluding the `-devel` Requires
from the runtime image.
