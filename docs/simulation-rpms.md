# ROS 2 `simulation` variant as Hummingbird RPMs — MAPPING / PLAN

> Detail doc for [`../CLAUDE.md`](../CLAUDE.md). The strategic (Hummingbird-RPM)
> path for the `simulation` variant, following
> [`ros-base-rpms.md`](ros-base-rpms.md). Supersedes the COPR/isolated-sysroot
> `sim-bundle` workaround ([`simulation-gazebo.md`](simulation-gazebo.md)) with a
> native, multi-arch, base-consistent build. **Status: mapped 2026-10-15; build
> of the leaf vendor in progress.**

## Target

Per REP 2001 (`ros2/variants/simulation`, jazzy):
```
simulation = ros_base + ros_gz_bridge + ros_gz_sim + ros_gz_image + ros_gz_interfaces
```
Branches directly off `ros_base` — **no** `perception`/`desktop` needed first.

The delta over the built `ros_base` = **Gazebo Harmonic built from source** (the
`gz_*_vendor` stack, since Fedora 44 / Hummingbird ship **no** `gz-*`/`sdformat`
and no ogre-next) + the `ros_gz` bridge. **~25 new packages**, two of which
(ogre-next, DART) and gz-sim are very large C++ compiles.

## Tier A — Gazebo Harmonic `gz_*_vendor` (17 pkgs, from source)

Vendor packages live at `github.com/gazebo-release/<name>`, **branch `jazzy`**
(⚠️ NOT `rolling` — rolling pins the dev Gazebo gz-sim11/Qt6; jazzy pins
**Harmonic**/Qt5). Each is an `ament_cmake_vendor_package` that `ament_vendor()`-
builds a pinned upstream from source. Build order (leaves first):

| # | vendor pkg (ver) | builds upstream @ tag | vendor deps | key Fedora -devel |
|---|---|---|---|---|
| 1 | gz_cmake_vendor 0.0.12 | gz-cmake `gz-cmake3_3.6.0` | — | (cmake, pkgconf) |
| 2 | gz_utils_vendor 0.0.5 | gz-utils `gz-utils2_2.2.1` | cmake | spdlog-devel (CLI11 in-tree) |
| 3 | gz_tools_vendor 0.0.8 | gz-tools `gz-tools2_2.0.4` | cmake | (ruby @ exec) |
| 4 | gz_math_vendor 0.0.11 | gz-math `gz-math7_7.7.0` | cmake, utils | eigen3-devel, pybind11-devel |
| 5 | gz_plugin_vendor 0.0.5 | gz-plugin `gz-plugin2_2.0.4` | cmake, tools, utils | — |
| 6 | gz_msgs_vendor 0.0.8 | gz-msgs `gz-msgs10_10.4.0` | cmake, math, tools | protobuf-devel+compiler, tinyxml2-devel |
| 7 | gz_common_vendor 0.0.10 | gz-common `gz-common5_5.9.0` | cmake, math, utils, **spdlog_vendor** | assimp, ffmpeg-free, gdal, libuuid, tinyxml2, google-benchmark -devel |
| 8 | sdformat_vendor 0.0.14 | sdformat `sdformat14_14.9.0` | cmake, math, utils, tools | tinyxml2, urdfdom, pybind11 -devel |
| 9 | gz_transport_vendor 0.0.9 | gz-transport `gz-transport13_13.6.0` | cmake, math, msgs, tools, utils | zeromq, cppzmq, sqlite, protobuf, libuuid -devel |
| 10 | gz_fuel_tools_vendor 0.0.6 | gz-fuel-tools `gz-fuel-tools9_9.1.1` | cmake, common, math, msgs, tools, utils | libcurl, gflags, jsoncpp, libyaml, libzip -devel |
| 11 | gz_ogre_next_vendor 0.0.5 | OGRECave/ogre-next (2.3.x) | cmake | freeimage, freetype, vulkan, mesa-GL, X11*, rapidjson, tbb, zziplib, (glslang/shaderc) -devel |
| 12 | gz_dartsim_vendor 0.0.3 | dartsim/dart `v6.13.2` | — | eigen3, libccd, fcl, fmt, bullet, ode, assimp, tinyxml2, urdfdom, octomap, **boost** -devel |
| 13 | gz_rendering_vendor 0.0.8 | gz-rendering `gz-rendering8_8.3.0` | ogre_next (+core) | freeglut, glew, vulkan, libXi/Xmu, mesa-GL -devel |
| 14 | gz_physics_vendor 0.0.9 | gz-physics `gz-physics7_7.8.0` | dartsim (+core) | bullet, eigen3, google-benchmark -devel |
| 15 | gz_sensors_vendor 0.0.6 | gz-sensors `gz-sensors8_8.2.2` | rendering (+core) | (opencv transitively) |
| 16 | gz_gui_vendor 0.0.5 | gz-gui `gz-gui8_8.4.0` | rendering (+core) | **Qt5** qtbase/qtdeclarative/qtquickcontrols2 + QML5 modules, protobuf, tinyxml2 |
| 17 | gz_sim_vendor 0.0.13 | gz-sim `gz-sim8_8.15.0` | physics, gui, sensors, rendering, fuel_tools (+core) | Qt5, freeimage, glew, libwebsockets, elfutils, protobuf, pybind11 -devel |

(Versions are the **jazzy-branch** `LIB_VER` as of 2026-10-15; confirm tags at build.)

## Tier B — `ros_gz` (6 pkgs, built the ros-base way)

| pkg (ver) | deps beyond ros_base |
|---|---|
| image_transport 5.1.8 (ros-perception/image_common) | ros_base only (message_filters ✓, pluginlib, rclcpp, sensor_msgs) |
| ros_gz_interfaces 1.0.25 | ros_core/base msgs only (leaf) |
| ros_gz_bridge 1.0.25 | ros_gz_interfaces + gz_msgs_vendor + gz_transport_vendor |
| ros_gz_image 1.0.25 | image_transport + ros_gz_bridge + gz_msgs/transport_vendor |
| ros_gz_sim 1.0.25 | gz_{math,msgs,sim,transport}_vendor + ros_gz_interfaces |
| **simulation** metapackage (variants 0.11.0) | ros_base + the 4 ros_gz_* |

## The offline-vendor mechanism (the load-bearing technique)

`ament_vendor()` defaults to `VCS_TYPE git` → runs `vcs import` (live git clone)
at build time → **fails in mock (no network)**. `ament_vendor.cmake` supports
**`VCS_TYPE path`** → ExternalProject `SOURCE_DIR ${VCS_URL}`, no download. It
*forbids* the `PATCHES`/`SOURCE_SUBDIR` args, so each vendor's in-repo patches
must be **pre-applied** to the staged source. Per-vendor spec recipe (generalises
the `mcap_vendor` pattern):

1. `Source0` = the `gz_*_vendor` package (gazebo-release, tag = vendor version).
2. `Source1` = the pinned upstream tarball (`gazebosim/<lib>` or OGRECave/dartsim).
3. `%prep`: extract Source1; `patch -p1` the vendor's `patches/*.patch` onto it;
   `sed` the vendor `CMakeLists.txt` to `VCS_TYPE path` + `VCS_URL <extracted dir>`
   and delete the `PATCHES patches` line.
4. Build with colcon; `SATISFIED ${<lib>_FOUND}` is FALSE (no system gz) → it
   builds the local source. Leave `GZ_BUILD_FROM_SOURCE` unset (so the vendored
   `gz-*` system dep stays inactive).
- No upstream uses git submodules at these tags (verified for ogre-next/DART and
  the gz-* libs) → a plain tag tarball is complete.

## Blocker assessment (the user's gate: "if no blockers, build")

**No hard blocker.** The historically-cited boost/ogre blocker is **resolved**:
`gz_ogre_next_vendor` builds ogre-next from source, where **boost is optional and
OFF by default** (add `-DOGRE_SKIP_BOOST_SEARCHING=TRUE`), and `gz-rendering8`
builds the **ogre2-only** engine when Fedora's ogre1 is absent (do NOT install
`ogre-devel`). Remaining items are **risks to manage during the build, not gates**:

- **Offline-vendor rewire** (all 17) — the `VCS_TYPE path` technique above; the
  biggest mechanical task + the first thing to prove (leaf `gz_cmake_vendor`).
- **DART ↔ boost 1.90** — `gz_dartsim_vendor` (DART 6.13.2) genuinely links system
  boost (regex/system); must compile DART against the base's boost 1.90. Real risk
  (API drift) — unknown until built.
- **protobuf/abseil ABI** — gz-msgs/gz-transport generate protobuf; Fedora 44's
  protobuf must match. Classic Gazebo-on-Fedora breakage point.
- **Qt5 breadth** — gz-gui8/gz-sim8 need Qt5 qtbase/qtdeclarative + many QML
  modules (present on fc44; tedious rosdep→Fedora mapping).
- **ffmpeg** — gz-common AV wants libav*; Fedora main has only `ffmpeg-free-devel`
  (reduced). Verify it satisfies the find_package, else disable gz-common AV.
- **spdlog consistency** — `gz_utils_vendor` uses system spdlog; `gz_common_vendor`
  uses the ROS `spdlog_vendor`. Keep one spdlog ABI across the stack.
- **Scale/compute** — ogre-next + DART + gz-sim are large compiles. aarch64 needs
  the Lima VM **resized** (~24 GB RAM / 10 CPU / ~180 GB disk, within this 32 GB
  Mac); x86_64 needs a `c7i.4xlarge`-class EC2 (mock needs a native x86 host).

## Build order (full)

Tier A 1→17 (topological, above) → Tier B (image_transport, ros_gz_interfaces →
ros_gz_bridge → ros_gz_image, ros_gz_sim) → `simulation` metapackage → the
`simulation` image (`FROM ros-base` + `dnf install ros-jazzy-simulation`).

## Status

| Step | aarch64 | x86_64 |
|---|---|---|
| closure mapped (Tier A 17 + Tier B 6) | ✅ 2026-10-15 | ✅ (same specs) |
| offline-vendor pattern proven (gz_cmake_vendor 0.0.12 → gz-cmake 3.6.0) | ✅ built, mock/offline, lint n/a | ❌ |
| Tier A remaining (16 vendors incl. ogre-next, DART, gz-sim) | ❌ needs VM resize + per-pkg specs | ❌ |
| Tier B (ros_gz) + simulation image | ❌ | ❌ |

**POC result (2026-10-15):** `gz_cmake_vendor` built clean in mock with no network
(hummingbird-rpms `9d292db9`), proving the `VCS_TYPE path` offline-vendor recipe.
The remaining 16 Tier-A vendors follow the same per-package recipe; the heavies
(ogre-next, DART, gz-sim) additionally need the VM resized and carry the risks in
the blocker section (DART↔boost 1.90, protobuf, Qt5).
