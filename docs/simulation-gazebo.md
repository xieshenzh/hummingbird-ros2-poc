# Simulation & Gazebo (sim-bundle, GUI, the boost blocker)

> Detail doc for [`../CLAUDE.md`](../CLAUDE.md). Covers the native-install blocker,
> the sim-bundle multi-stage workaround, and interactive GUI. ROS/Gazebo-on-Fedora
> packaging facts are in [`established-facts.md`](established-facts.md).

## ⚠️ The native blocker: Gazebo rendering vs bootc-os boost

(Found 2026-08-30; INVALIDATES the earlier "simulation 1068 / gazebo 798, no unmet
deps" dry-run, which must have run against a different base/repo state.)

The Gazebo dep chain is
`ros-jazzy-simulation → ros-gz-sim → gz-sim-vendor → gz-rendering-vendor →
libOgreMain.so.1.9.0`. The ONLY provider is Fedora's **`ogre-1:1.9.0-52.fc43`**,
built against **boost 1.83** (`libboost_thread.so.1.83.0` → `boost-system = 1.83`).
But bootc-os ships **boost 1.90**, whose `boost-filesystem-1.90`
**Obsoletes/Conflicts boost-system < 1.90** — so the old boost 1.83 the rendering
stack needs cannot coexist with the base's 1.90. `gz-sim-vendor` hard-requires
`gz-rendering-vendor` even headless, so this blocks BOTH `simulation` and `gazebo`;
there is no rendering-free subset. Not fixable by repo config (`--allowerasing`
would try to rip boost 1.90 out of the base OS and cascade). Real fixes need one
of: (a) tavie rebuilds `gz-rendering-vendor` against a boost-1.90-compatible ogre
(e.g. ogre-next) or vendors ogre; (b) a bootc-os base pinned to boost 1.83
(unlikely/regressive); (c) build the gz stack ourselves against boost 1.90.
ros-core/ros-base are unaffected (they don't touch ogre/boost-thread).

## sim-bundle: the multi-stage workaround (isolated sysroot)

Sidesteps the boost skew and multi-stream-ruby conflicts by installing the Gazebo
stack on **stock fedora:43** — where the tavie RPMs resolve cleanly — into an
isolated root, then copying that root into bootc-os at `/usr/lib/ros-sysroot` and
running it via `chroot`. The bundled boost/ruby/ogre live entirely inside the
sysroot and never merge with the base `/usr`, so nothing conflicts; the outer
image stays a bootable bootc image.

- **`bridge` variant ✅ built & tested 2026-08-30** (amd64 emulation): 2.17 GB,
  569 pkgs resolved on fedora:43. `ros2 pkg list` shows
  `ros_gz_bridge`/`ros_gz_image`/`ros_gz_interfaces`; `parameter_bridge` ELF loads
  with ALL libs resolved (`ldd` clean). Add
  `ros-<distro>-ros2cli-common-extensions` for the `ros2 pkg`/`run`/... sub-commands.
- **Activation needs `--cap-add=sys_admin`** (chroot bind-mounts /proc,/dev,/sys):
  ```bash
  podman run --rm --platform linux/amd64 --cap-add=sys_admin \
    --entrypoint /usr/bin/sim-entrypoint.sh \
    hummingbird-ros2-poc/sim-bundle:bridge ros2 pkg list
  ```
  chroot (not bwrap): the podman-machine VM blocks nested user namespaces
  (bwrap EINVAL); on a booted bootc host running as root the mounts just work.
- **`simulation` variant ✅ built & tested 2026-08-30** (amd64 emulation,
  `--build-arg VARIANT=simulation`): the full osrf `simulation` set — `ros_gz_*`
  plus the whole gz vendor stack (16 `gz_*` vendor pkgs). Verified:
  `gz sim --version` → **Gazebo Sim 8.11.0** (Harmonic); `ros2 pkg list` lists all
  ros_gz + gz_*_vendor; `ldd` clean on `ros_gz_sim/create` and
  `parameter_bridge`.
  - ⚠️ Headless `gz sim -s` server aborts under qemu (`std::__throw_out_of_range`
    → signal 6) — amd64-on-arm64 emulation artifact. Works on native x86_64.
- **`gazebo` variant ✅ built & tested 2026-08-30** (amd64 emulation,
  `--build-arg VARIANT=gazebo`): standalone Gazebo Harmonic (gz-sim-vendor +
  gz-tools-vendor, **no** ROS middleware). `gz sim --version` → 8.11.0; `gz` CLI
  at `/usr/lib64/ros-jazzy/opt/gz_tools_vendor/bin/gz`; gz-sim plugin `.so`s
  `ldd`-clean. Same qemu headless-server caveat.
- **sim-bundle image sizes** (amd64): bridge 2.19 GB, gazebo 4.5 GB,
  simulation 4.83 GB (base bootc-os 909 MB + the copied sysroot).

## Interactive GUI (gz sim -g) — supported, runtime-only concern (2026-08-30)

The **GUI stack is already fully bundled** in the `gazebo` and `simulation`
variants — no extra build/packaging needed. Verified present in the sysroot:
`gz_gui_vendor` (gz-gui-8 + plugins), `gz_ogre_next_vendor`, `gz_rendering_vendor`,
Qt5 xcb platform plugin, `libGL`/`libEGL`, and a COMPLETE Mesa (`/usr/lib64/dri`:
hardware drivers **and** software `swrast`/`kms_swrast`/`zink`). `gz sim -g` is a
supported mode.

- **✅ GUI VERIFIED on native x86_64 (headless EC2, software GL) 2026-09-02.** A
  plain `gz sim <world>` (server + GUI in one process, no overrides) renders the
  full standard Gazebo GUI from the image alone. Rendered on an AL2023 `c6i` box
  with NO GPU via bundled Mesa **software GL** (`swrast`/`llvmpipe`,
  `LIBGL_ALWAYS_SOFTWARE=1`) on `Xvfb :99` served over `x11vnc` through an SSH
  tunnel. Reproduce with `scripts/gui-verify.sh`.
- **✅ ROS 2 drives the sim THROUGH the GUI — verified 2026-09-02.**
  `scripts/gui-cmdvel-demo.sh` stands up a two-container co-sim pod (`gz-gui`
  diff-drive world + `ros_gz parameter_bridge`); `ros2 topic pub /cmd_vel` drove
  the robot visibly across the live GUI, odometry read back over ROS 2. The full
  `/cmd_vel` actuation + sensor-return loop. ⚠️ Software GL is CPU-bound: run only
  ONE gz GUI at a time.
- **Runtime plugin/QML wiring is baked into `sim-entrypoint.sh`.** The GUI needs
  more paths than the server: it exports `GZ_GUI_PLUGIN_PATH`,
  `GZ_RENDERING_PLUGIN_PATH`, `GZ_RENDERING_RESOURCE_PATH` (OGRE HLMS media — baked
  path is `ogre2/src/media`, real one is `ogre2/media`) and **`QML2_IMPORT_PATH`**
  (the gz-sim `gui/` dir with the `GzSim` QML module — without it Qt errors
  `module "GzSim" is not installed` and the whole GUI config fails to load). It
  also seeds the real default `gui.config` into `$HOME/.gz/sim/<v>/`. All globbed
  from the sysroot; no-ops on the `bridge` variant.

So a GUI Gazebo on bootc-os is proven feasible — the base image is NOT the blocker.
The only external requirement is a **runtime display** (GPU optional — software GL
works). `sim-entrypoint.sh` binds the host X11 socket + `XAUTHORITY` into the
chroot and passes `DISPLAY`/`XAUTHORITY`/`LIBGL_ALWAYS_SOFTWARE` through.

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
  `-e LIBGL_ALWAYS_SOFTWARE=1`.
- ⚠️ **GUI is x86_64-native only** — it will NOT run under amd64-on-arm64 qemu
  (no GPU passthrough; software GL under qemu is unusable and crashes like the
  headless physics engine). Run on a native x86_64 host, or on a booted bootc
  machine with its own compositor/GPU.

Two deployment shapes: (a) **Container GUI** on an x86_64 Linux workstation (run
recipe above; mirrors upstream `gazebosim/gz-sim` `Dockerfile.gz`); (b) **Booted
bootc robot/workstation** — the image boots and runs `gz sim -g` on the machine's
own display/GPU via a compositor (needs Weston/GNOME layered on — a follow-up).

## Architecture

`simulation` is a ROS image (the osrf variant incl. the ros_gz bridge, `FROM
ros-base`); `gazebo` is a separate simulator image (`FROM bootc-os`, no
rclcpp/ros-core). Run them together (same pod / shared network) to co-simulate —
the bridge relays between ROS 2 and the Gazebo simulator. (The `simulation`
variant also pulls the gz-*-vendor libs since ros_gz_sim links them, so it
overlaps `gazebo`; the standalone `gazebo` image remains the ROS-free simulator.)
