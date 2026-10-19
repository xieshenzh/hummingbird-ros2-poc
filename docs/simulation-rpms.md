# ROS 2 `simulation` variant as Hummingbird RPMs — MAPPING / PLAN

> Detail doc for [`../CLAUDE.md`](../CLAUDE.md). The strategic (Hummingbird-RPM)
> path for the `simulation` variant, following
> [`ros-base-rpms.md`](ros-base-rpms.md). Supersedes the COPR/isolated-sysroot
> `sim-bundle` workaround ([`simulation-gazebo.md`](simulation-gazebo.md)) with a
> native, multi-arch, base-consistent build. **Status: mapped 2026-10-15; build
> of the leaf vendor in progress.** For the complete, chronological record of
> the 2026-10-16 build-through (every failure and fix), see
> [`simulation-build-journal.md`](simulation-build-journal.md).

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

## Build results — aarch64 (2026-10-15)

Built natively on the (resized: 10 CPU / 24 GB) Lima VM, offline vendor recipe.
**16 of the 17 Tier-A vendors built** + the Qt5 QML stack rebuilt against icu78:

- **gz core (10):** gz_cmake 3.6.0, gz_utils 2.2.1, gz_tools 2.0.4, gz_math 7.7.0,
  gz_plugin 2.0.4, gz_msgs 10.4.0, gz_common 5.9.0 (needs **gts** for graphics),
  gz_transport 13.6.0, gz_fuel_tools 9.1.1, sdformat 14.9.0 (urdfdom optional → off).
- **render/sim (4):** gz_ogre_next 2.3.3 (+ the rolling **cxx20 STLAllocator patch**
  for gcc16), gz_rendering 8.3.0 (ogre2-only), gz_physics 7.8.0 (**bullet+TPE**),
  gz_sensors 8.2.2.
- **Qt5 for the GUI:** qt5-qtdeclarative + qt5-qtquickcontrols2 rebuilt `.hum1`
  against the base's **icu78** (Fedora ships them against icu77 → conflict).
- Commits: hummingbird-rpms `9d292db9` (gz_cmake), `904afef6` (13 more gz vendors +
  generator/driver), `80dc3820` (Qt5 icu78).

Recurring build gotchas handled (all in `gen_gz_vendor.sh`): `VCS_TYPE path` offline
rewire + pre-applied vendor patches (inline AND multiline PATCHES forms);
`QA_SKIP_BUILD_ROOT=1` (gz bakes CMAKE_INSTALL_PREFIX into .so); patchelf rpath
shrink; protobuf-devel + zeromq/cppzmq-devel BRs for the transitive imported targets
(`protobuf::libprotobuf`, `CPPZMQ::CPPZMQ`); drop Fedora `python3-protobuf` (old 3.19
vs hummingbird protobuf 36.2).

### Two deferrals / blockers found at build time

1. **DART deferred (gz_dartsim NOT built):** DART 6.13.2 needs **fcl** (Flexible
   Collision Library), which is **absent from Fedora 44** (only python bindings).
   → `gz_physics` built with **bullet + TPE** engines instead (dartsim is gz-sim's
   default, but bullet works; `--physics-engine gz-physics-bullet-plugin`). Enabling
   dartsim = package fcl (+ resolve urdfdom for DART) + DART's boost-1.90 compile.

2. **gz_gui + gz_sim BLOCKED on an icu conflict (the GUI gate):** gz-sim 8
   **hard-requires** gz-gui8 + Qt5 (no headless-only build). The Qt5 QML rebuild
   against icu78 is done, BUT **gz-rendering REQUIRES gz-common[geospatial] → gdal →
   samba-core-libs**, and gdal/samba are **Fedora-only, built against icu77**, which
   cannot coexist with the base's icu78 (needed by Qt5). See the GUI evaluation below.

## GUI evaluation (requested 2026-10-15)

GUI is **feasible but gated by a second icu77/icu78 fault line**. The Qt5 half is
solved (qtdeclarative/qtquickcontrols2 rebuilt against icu78). The remaining blocker:
the rendering path drags in `gdal`→`samba` (icu77), which clashes with icu78. To
finish gz_gui + gz_sim + the GUI, pick ONE of:

- **A — rebuild gdal against icu78 with the SMB driver off** (~1 package): breaks the
  samba→icu77 chain while keeping geospatial for gz-rendering. Smallest IF gdal has no
  other icu77-tied deps (unverified — gdal is driver-heavy). Then gz_gui → gz_sim.
- **B — strip geospatial** from gz_common + gz_rendering (patch 2 vendors, rebuild the
  rendering subtree): avoids gdal/samba entirely; **loses DEM/heightmap terrain** and
  risks gz-rendering source patches (it uses geospatial for heightmaps).
- **C — rebuild samba against icu78** (clean but **large**: samba is a big multi-pkg
  build).

After the chosen fix: build **gz_gui** (Qt5 icu78, ready) → **gz_sim** (big compile) →
Tier B (ros_gz) → the `simulation` image. Runtime GUI also needs the icu78 QML runtime
modules (qtquickcontrols2, qtgraphicaleffects) + software GL in the image (proven on
x86_64 in [`simulation-gazebo.md`](simulation-gazebo.md)). Rough effort: **A** is the
fastest to a GUI sim (~a few hours incl. the gz_sim compile); **B** medium + lossy;
**C** largest.

## GUI build-through (2026-10-15) — icu/samba conflict SOLVED; gz_gui BUILT

The GUI gate (Qt5 needs icu78; rendering's geospatial pulled icu77 libs) was broken
through. Resolution (committed): rebuild the icu77-linked libs clean, NOT samba
(option C dead-ended on a Hummingbird gpgme repo bug).
- **Qt5 QML** (qtdeclarative, qtquickcontrols2) rebuilt against **icu78** (`80dc3820`).
- **gdal 3.12.4-1.hum1** rebuilt with `-DGDAL_USE_LIBSMBCLIENT=OFF` + mingw/java off
  + optional scientific drivers off → minimal, **no samba**, keeps libgdal.so.38 for
  geospatial (`d3d93926`). This removed the gdal→samba→icu77 chain.
- **gz_gui 8.4.0 BUILT** against the icu78 Qt5 + clean gdal — the icu conflict is gone.
  Needed a gcc16/protobuf-36 fix (wrap `string_view` descriptor accessors in
  `TopicViewer.cc`).

### gz-common `av` → ffmpeg → samba — SOLVED (ffmpeg rebuilt no-smb)
gz-sim **hard-requires gz-common's `av` component** (video recording). `av` links
Fedora `ffmpeg-free`, whose `libavformat` links **`libsmbclient` → samba (icu77)** —
the *same* pattern as gdal, a second source of the icu77 pull. Fix (done): rebuild
ffmpeg with **`--disable-libsmbclient`** + drop the `pkgconfig(smbclient)` BR, exactly
like the gdal no-smb rebuild. **Built + verified on aarch64** (`ffmpeg-8.1.3-1.hum1`;
hummingbird-rpms `1d0211e9`) — `libavformat-free` no longer requires libsmbclient, so
the icu77 chain is fully severed. Note: Fedora's `ffmpeg-free` is built from a source
RPM named plain **`ffmpeg`** (that's why `ffmpeg-free` koji/SRPM lookups 404); fetch
the f44 SRPM via a `fedora:44` container (`dnf download --source ffmpeg`), since the
Lima host is f43.

**Remaining path:** ~~rebuild gz_common with av → gz_sim → Tier B → the image~~
**ALL DONE 2026-10-16** — see "Build-through COMPLETE" below.

## Build-through COMPLETE (2026-10-16, aarch64) — the simulation image EXISTS

All remaining pieces landed natively on the Lima VM. **`simulation-rpms-rt:latest`
(3.43 GB) — RT kernel + ros-base + Gazebo Harmonic simulation, 100% Hummingbird-built
RPMs — BUILT and VERIFIED.** Specs committed: `c2a914b4` (Tier B + gz-sim vendor +
gz-common av), `c77240b5` (fiddle + ffmpeg no-openal).

### gz_common + av (the "remaining path", step 1)
Rebuilt from the committed spec (the ffmpeg-free-devel BR restored — the VM's local
"no av" variant is superseded). Provides `libgz-common5-av.so.5` + all components,
linking the clean no-smb ffmpeg.

### gz_sim_vendor 0.0.13 — Tier A closes at 17/17
gz-sim **8.15.0** (jazzy-branch pin verified from the vendor tag's CMakeLists). The
compile was CLEAN first try — the predicted gcc16/protobuf `string_view` fixes never
materialized. The iterations were all packaging-layer:
- **6 upstream files with SPACES in names** (`OpenRobotics.Prius on Sonoma
  Raceway.png` etc. in examples/worlds/thumbnails) break rpm's space-separated
  `%files` — the manifest `find -printf` now emits QUOTED paths (generator fixed).
  Gotcha within the gotcha: the closing quote goes BEFORE `\n` in the printf format.
- **Rebuilds need `sudo rm -rf builds/<pkg>`** first — the build container (rootless
  podman userns) leaves subuid-owned files the user cannot delete.
- **Staged RPMs must be `chmod 644`** — container-written RPMs come out mode 640,
  which the NEXT build's container cannot read → createrepo_c silently skips them →
  builddep "No match for argument".

### Tier B — the closure was BIGGER than the table above
`ros_gz` 1.0.25's actual `package.xml`s require **5 packages beyond this doc's
6-package Tier B**: `actuator_msgs` 0.0.1, `gps_msgs` 3.1.1 (gps_umd),
`marine_acoustic_msgs` 2.1.0 (marine_msgs), `vision_msgs` 4.1.1,
`simulation_interfaces` 1.5.1 — none in ros_base. Tier B is **11 packages** total;
all built (specs generated by `.poc-scratch/sim/gen-tierb.sh` in the poc repo,
patterns copied from rosbag2-interfaces/tf2-ros/ros-base).

The bridge needed three CMake-integration fixes (now encoded in the generator):
1. **System BR set** for rclcpp consumers: `openssl-devel asio-devel lttng-ust-devel
   tinyxml2-devel` (+ `libuuid-devel` — gz-transport's config needs FindUUID).
2. **`protobuf-devel cppzmq-devel zeromq-devel` + Qt5 devel trio** for ros_gz
   packages (builddep does NOT install BR-packages' runtime Requires).
3. **A `%prep` sed injecting, before the first `find_package(gz_`**: the gz-cmake3
   module path + prefix, `find_package(gz-cmake3 REQUIRED)` (loads the Gz* helpers),
   and `find_package(CPPZMQ REQUIRED)` — the vendored gz configs reference IMPORTED
   targets (`protobuf::libprotobuf`, `CPPZMQ::CPPZMQ`) without finding them, and
   Fedora's cppzmq ships no CMake config. Do NOT pre-find Protobuf: the module-mode
   find collides with gz's own config-mode `FindGzProtobuf` ("some but not all
   targets already defined").

### The fmt-12 war (openal)
`gz-common[av] → libavdevice-free → libopenal → openal-soft (fmt-11)` conflicts with
the base's `fmt-12` (spdlog 1.17 via the rcl stack). Fix: **ffmpeg rebuilt with
`--disable-openal`** — gz's av is video encoding only; the openal audio-input backend
is unused (`c77240b5`).

### The Ruby 4.0 gem war (the gz CLI)
The `gz` CLI (gz-tools) is Ruby: `yaml`/psych ✓ (weak dep, added explicitly) but
**`fiddle`** is neither a Ruby 4.0 default gem nor in the Hummingbird repo. Built
**`rubygem4.0-fiddle` 1.1.8** from the rubygems.org gem (layout mirroring
rubygem4.0-psych; installed-form gemspec via `gem spec --ruby` — the gem's own
fiddle.gemspec is a build-time spec rubygems rejects). The image also needs
`install_weak_deps=0`: weak deps would pull the **ruby3.3/3.4 parallel streams**
whose default-gems conflict with ruby4.0's.

### The image — `images/simulation-rpms/` (aarch64)
`FROM ros-base-rpms(-rt)` + a local repo of the FULL closure (257 RPMs: Tier A 17 +
Tier B 11 + ros_core/ros_base restage + the icu/fmt enablers: icu78 Qt5 QML, no-smb
gdal, no-smb+no-openal ffmpeg, fiddle). 3.43 GB on the RT base.

### VERIFIED (aarch64, container on the Lima VM)
- `gz sim --version` → **Gazebo Sim 8.15.0** (psych+fiddle working).
- `ros2 pkg list` = **219**; RT kernel `7.2.7-200.fc44.aarch64+rt` only; lint OK
  (1 skip, 2 cosmetic warnings).
- **Headless physics (bullet)**: free body fell z=10 → **z=-481.5** in 10 s sim time
  (free-fall predicts -480), log error-free, via
  `gz sim -s -r --physics-engine gz-physics7-bullet-plugin`.
- **ROS 2 ↔ Gazebo bridge round-trip**: `parameter_bridge /clock` →
  `ros2 topic echo /clock` received sim time over DDS.
- ⚠️ **Runtime GZ_* plugin paths must be exported** (same trap as the sim-bundle
  era — the vendored RPMs bake no working defaults):
  `GZ_SIM_SYSTEM_PLUGIN_PATH=<...>/opt/gz_sim_vendor/lib64/gz-sim-8/plugins`,
  `GZ_SIM_PHYSICS_ENGINE_PATH=<...>/opt/gz_physics_vendor/lib64`; the engine name is
  **`gz-physics7-bullet-plugin`** (versioned .so name in this build). Bake these
  into the image's profile/entrypoint before shipping (sim-bundle's
  `sim-entrypoint.sh` is the reference).
- Server-config quirk: gz-sim bakes its BUILDROOT into the default server.config
  path (harmless warning when the world names its systems explicitly).

### Not done
- The plain (non-RT) `simulation-rpms` chain: `ros-core-rpms` on the CURRENT
  `bootc-os:latest` fails closure resolution (the base rolled since 2026-10-15 —
  diagnose with the `--assumeno` pre-check; the RT chain is immune, pinned base).
- x86_64 everything; the GUI runtime (QML/ogl) on the image; booting the sim image.

## Status

| Step | aarch64 | x86_64 |
|---|---|---|
| closure mapped (Tier A 17 + Tier B **11**) | ✅ 2026-10-16 (Tier B corrected) | ✅ (same specs) |
| Tier A core + render/sensors/physics (16 vendors) | ✅ built | ❌ |
| Qt5 QML rebuilt against icu78 | ✅ built | ❌ |
| clean gdal (no-smb) | ✅ built | ❌ |
| gz_gui (icu78 Qt5) | ✅ built | ❌ |
| gz_dartsim (DART) | ⚠️ deferred (fcl missing → bullet/TPE physics) | — |
| clean ffmpeg (no-smb **+ no-openal**) | ✅ built (`ffmpeg-8.1.3-1.hum1`) | ❌ |
| gz_common+av | ✅ 2026-10-16 | ❌ |
| gz_sim_vendor (last Tier-A vendor) | ✅ 2026-10-16 (gz-sim 8.15.0) | ❌ |
| rubygem4.0-fiddle (gz CLI) | ✅ 2026-10-16 | ❌ |
| Tier B (11 pkgs incl. 5 extra msg pkgs) | ✅ 2026-10-16 | ❌ |
| `simulation-rpms-rt` image | ✅ BUILT 3.43 GB + VERIFIED (physics + bridge) | ❌ |
| plain `simulation-rpms` image | ❌ (blocked: ros-core closure on rolled base) | ❌ |
