# The `simulation` image build — full process journal (2026-10-16)

> This is the **complete, chronological record** of building
> `images/simulation-rpms-rt` (ROS 2 Jazzy `simulation` variant, Gazebo
> Harmonic 8.15.0, PREEMPT_RT base, aarch64) from where the 2026-10-15
> session left off to a verified image in the host podman machine — every
> phase, command, failure, root cause, and fix. The condensed version lives
> in [`simulation-rpms.md`](simulation-rpms.md); this is the long form.
>
> **Result:** `simulation-rpms-rt:latest` — 3.43 GB, 219 ROS packages,
> `gz sim --version` → Gazebo Sim 8.15.0, bullet physics verified by
> free-fall (z: 10 → −481.5 in 10 s, theory −480), ROS 2 ↔ gz bridge
> round-trip verified over DDS.

---

## 0. Starting point (hand-off state, evening of 2026-10-15)

The previous session had:
- **Tier A**: 16 of 17 `gz_*_vendor` RPMs built (gz_cmake, utils, tools,
  math, plugin, msgs, common, transport, fuel_tools, ogre-next, rendering,
  physics (bullet+TPE, DART deferred), sensors, gui) + the icu78 Qt5 QML
  rebuilds + no-smb gdal + **no-smb ffmpeg** (`ffmpeg-8.1.3-1.hum1`).
- **The icu war won**: Qt5-qtdeclarative/qtquickcontrols2 rebuilt against
  icu78; gdal rebuilt `-DGDAL_USE_LIBSMBCLIENT=OFF`; ffmpeg rebuilt
  `--disable-libsmbclient` — the gdal→samba and ffmpeg→samba icu77 chains
  severed, `gz_gui` built.
- **Stopped at**: "rebuild gz_common **with av** (restore the
  ffmpeg-free-devel BR, now clean) → gz_sim (big compile) → Tier B
  (ros_gz) → the simulation image".

Build environment: the Lima `fedora` VM (aarch64, vz, 10 CPU / 24 GB /
80 GB disk), `~/hummingbird-rpms` clone (specs are authored there),
`~/ros-local-rpms` (the local RPM repo fed to mock via
`ci/build_rpms.sh --local-rpms-dir`), `scripts/sync-rpms-to-host.sh` for
VM→host spec syncing. Host repo:
`hummingbird-rpms` @ `add-ros2-jazzy-packages`, HEAD `1d0211e9`.

## 1. Phase 0 — state audit (before touching anything)

Verified in the VM:

- `~/ros-local-rpms`: **218 ros-jazzy RPMs** + the enablers
  (`ffmpeg-free-8.1.3-1.hum1` + `-devel`, `gdal-3.12.4-1.hum1` + libs,
  `qt5-qtdeclarative-5.15.18-1.hum1`, `qt5-qtquickcontrols2`) + the built
  gz vendors.
- **The VM's `ros-jazzy-gz-common-vendor` spec was the local "no av"
  variant**: Summary said "(no av)", no `ffmpeg-free-devel` BR, plus the
  DART/GUI-stripping seds. The committed HOST spec (HEAD) already carried
  the av BR — that was the rebuild target.
- Tarballs (`gz-common-5.9.0.tar.gz`, vendor 0.0.10) + `sources` present.
- `ci/build_rpms.sh` contract: builds via mock inside the pinned
  `rpm-build-pipeline` container, injects `--local-rpms-dir` as a
  high-priority repo, output to `builds/<pkg>/RPMS/`. Sources are fetched
  by `dist-git-client`, which **skips downloading when the file is already
  present with the matching SHA512** — that is why staging tarballs in the
  package dir works.

## 2. gz_common with av — clean, first try

```bash
cp <host-repo>/rpms/ros-jazzy-gz-common-vendor/ros-jazzy-gz-common-vendor.spec \
   ~/hummingbird-rpms/rpms/ros-jazzy-gz-common-vendor/
cd ~/hummingbird-rpms && ./ci/build_rpms.sh --local-rpms-dir ~/ros-local-rpms \
  ros-jazzy-gz-common-vendor
# → 1 min 26 s. Provides: libgz-common5-av.so.5 + events/geospatial/graphics/
#   io/profiler/testing; Requires libavcodec.so.62, libavformat.so.62, …
cp builds/ros-jazzy-gz-common-vendor/RPMS/*.rpm ~/ros-local-rpms/
```

The no-smb ffmpeg enabler was thereby proven end-to-end: av links
`ffmpeg-free` with no samba/icu77 pull. (Same-NVR content replacement —
the established convention in this repo; verified by checksum that all
three copies — VM local repo + both image staging dirs — matched the
fixed binary.)

## 3. Authoring `ros-jazzy-gz-sim-vendor`

**Version pinning, verified from source** (the docs said "confirm tags at
build"): fetched the jazzy-branch
`gazebo-release/gz_sim_vendor/CMakeLists.txt` —
`LIB_VER_MAJOR/MINOR/PATCH = 8/15/0`, `LIB_VCS_VER = gz-sim8_8.15.0`, and
the full vendor dependency list (14: gz_cmake/common/fuel_tools/gui/math/
msgs/physics/plugin/rendering/sensors/tools/transport/utils **+
sdformat_vendor**). Crucially: **no `gz_dartsim_vendor` reference** — the
DART deferral was already fully handled at the physics layer.

Generated the spec with the committed
`rpms/_rosidl_src/gen_gz_vendor.sh` (host-canonical copy pushed to the VM
first — the VM copy predated fixes), BR/REQ modeled on the gz_gui spec +
the Tier-A table:

- System BRs: `protobuf-devel tinyxml2-devel zeromq-devel cppzmq-devel
  qt5-qtbase-devel qt5-qtdeclarative-devel qt5-qtquickcontrols2-devel
  freeimage-devel glew-devel libwebsockets-devel elfutils-devel
  pybind11-devel`
- 14 vendor BRs, Qt5 trio at runtime.

Tarballs downloaded into the package dir (`gz-sim-8.15.0.tar.gz` 63 MB +
vendor 0.0.13), the 0.0.13 tag's CMakeLists re-verified to pin 8.15.0,
`sources` SHA512 written, changelog copied. The entire prep scripted in
`.poc-scratch/sim/prep-gz-sim.sh`.

## 4. The gz_sim build — four attempts, all packaging-layer

### Attempt 1 — compile clean, `%files` broken
10 min 46 s of flawless compilation ("Scanned 277 directories and 1413
files … 0 errors"), then:

```
error: File must begin with "/": joint
error: File must begin with "/": control.png
… 11 errors …
RPM build errors: File must begin with "/"
```

**Root cause:** gz-sim ships **6 files with spaces in their names**
(thumbnails + a tutorial image):

```
examples/worlds/thumbnails/OpenRobotics.NAO joint control.png
examples/worlds/thumbnails/OpenRobotics.Panda joint control world.png
examples/worlds/thumbnails/OpenRobotics.Prius on Sonoma Raceway.png
examples/worlds/thumbnails/OpenRobotics.Quadcopter teleop.png
examples/worlds/thumbnails/OpenRobotics.Tugbot in Warehouse.png
tutorials/files/underwater_vehicles/MBARI forces.png
```

rpm's `%files` list is whitespace-separated, so `Sonoma Raceway.png`
split into an orphan `Raceway.png` etc. **Fix:** the manifest
`find -printf` emits QUOTED paths (`"…"`), which rpm parses as single
entries. Patched the spec and the host generator
(`gen_gz_vendor.sh`, both `find -printf` lines).

### Attempt 2 — failed before building: stale workdir

```
find: cannot delete 'sources/local-rpms/ros-jazzy-…rpm': Permission denied
```

**Root cause:** the build container runs under rootless podman's user
namespace; files it leaves in `builds/<pkg>/` are owned by a mapped
**subuid** the VM user cannot delete. Only bites on *re*-builds (the
first run's cleanup found an empty dir). **Fix:** `sudo rm -rf
builds/<pkg>` before every rebuild (later baked into the Tier-B driver).

### Attempt 3 — my quoting fix was itself wrong

```
File must begin with "/":            ← ONE error, EMPTY name
```

The manifest now read:

```
"/usr/lib64/…/gz-sim8-all-config.cmake      ← quote, no closer
""/usr/lib64/…/config-version.cmake          ← TWO openers
…
"%dir "/usr/lib64/…/hook                     ← quote before %dir!
```

**Root cause:** I placed the closing quote **after** the `\n` in the
printf format: `'"…%%P\n"'`. find prints the format left-to-right —
`"` path `\n` `"` — so every entry's closing quote landed at the *start
of the next line*, and rpm's parser read the leading `""` as an **empty
quoted filename** (hence the blank-name error). **Fix:** the quote goes
BEFORE the newline: `-printf '"%{_libdir}/ros-jazzy/%%P"\n'` (and
`'%%%%dir "…"\n'` for the `%dir` find). Same fix applied to the
generator.

### Attempt 4 — SUCCESS

Full rebuild from a fresh workdir: **`ros-jazzy-gz-sim-vendor-0.0.13-1.
hum1.aarch64.rpm` (9.7 MB)**. Tier A complete: **17/17**.

> Notable: the docs' predicted gcc16/protobuf `string_view` source fixes
> (à la gz_gui's `TopicViewer.cc`) **never materialized** — gz-sim 8.15.0
> compiled clean against gcc 16 + protobuf 36 first try.

## 5. Tier B closure research — the table was wrong

Fetched the actual `package.xml`s from the pinned tags
(`gazebosim/ros_gz` 1.0.25, `ros-perception/image_common` 5.1.8,
`ros2/variants` 0.11.0) and cross-checked versions against the rosdistro
jazzy `distribution.yaml`. Findings:

- **`ros_gz_bridge` 1.0.25 requires 4 msg packages not in ros_base**:
  `actuator_msgs` (0.0.1, rudislabs), `gps_msgs` (3.1.1, gps_umd),
  `marine_acoustic_msgs` (2.1.0, marine_msgs), `vision_msgs` (4.1.1).
- **`ros_gz_sim` requires `simulation_interfaces`** (1.5.1,
  ros-simulation) — also not in ros_base.
- The docs' Tier B table (6 packages) was a **mapping gap**; the real
  Tier B is **11 packages**: the 5 above + `ros_gz_interfaces`,
  `image_transport`, `ros_gz_bridge`, `ros_gz_image`, `ros_gz_sim`, and
  the `simulation` metapackage.
- Full dep lists extracted per package (buildtool vs `<depend>`);
  `ros_gz_bridge` buildtools: `ament_cmake_python`, `pkg-config`,
  `rosidl_pycommon`; `ros_gz_sim` needs Fedora `cli11-devel` +
  `gflags-devel` (rosdep keys `cli11` / `libgflags-dev`).

## 6. `gen-tierb.sh` — the Tier B spec generator

Wrote `.poc-scratch/sim/gen-tierb.sh` (poc repo): one `emit()` function
generating all 11 specs from a shared template with
`@PLACEHOLDER@` substitution (avoids heredoc quoting hell), three kinds
(`msg` / `cmake` / `meta`) modeled verbatim on the committed
`rosbag2-interfaces` (msg), `tf2-ros` (cmake monorepo subpkg), and
`ros-base` (metapkg) specs. Per-package: tarball download (idempotent),
LICENSE detection (`%license` only when actually present), SHA512
`sources`, changelog.

**Generator bugs found and fixed during the run:**

1. `MSG_BR`/`MSG_REQ` defined as multi-line "BuildRequires:" blocks but
   consumed as space-separated lists by the `for` loop → doubled
   `BuildRequires:  BuildRequires:` lines. Fixed to plain package lists.
2. **sed replacement `\n` semantics**: `@BREXTRA@`/`@GZPATCH@` values
   containing literal `\n` were passed through `sed s|…|…|` replacements,
   where `\n` means *insert a newline* — the generated spec got real line
   breaks inside a sed expression (rpm re-emitted it as a `$'…'` string;
   "unterminated 's' command"). Fix: escape backslashes before
   substitution (`${var//\\/\\\\}`).

## 7. Tier B builds — the bridge's configure onion (6 layers)

Build order: 5 msg leaves → `ros_gz_interfaces` → `image_transport` →
`ros_gz_bridge` → `ros_gz_image` → `ros_gz_sim` → `simulation`.
Driver: `.poc-scratch/sim/build-tierb.sh` (sudo-rm workdir → build →
stage RPMs → **chmod 644**).

**The msg packages + `ros_gz_interfaces`: all built first pass.** Then:

### image_transport — missing system BR
```
Could NOT find OpenSSL (missing: OPENSSL_CRYPTO_LIBRARY …)
  ← message_filters → rclcpp → fastrtps-config.cmake → find_package(OpenSSL)
```
Fix: the `tf2-ros` spec's system-BR set added for all cmake-kind
packages: `openssl-devel asio-devel lttng-ust-devel tinyxml2-devel`.

### ros_gz_bridge — six configure failures in sequence

1. **`libuuid-devel` missing** — gz-transport's config needs
   `FindUUID.cmake` (gz-cmake3's module; resolved once installed).
2. **IMPORTED targets not found** — the vendored gz configs reference
   `protobuf::libprotobuf` and `CPPZMQ::CPPZMQ` without finding them
   (upstream gz's own CMakeLists does those finds internally;
   `ros_gz_bridge` doesn't). Fix: inject `find_package` calls into
   `ros_gz_bridge/CMakeLists.txt` before the first `find_package(gz_…)`.
3. **Injection sed ran at the monorepo root** (`CMakeLists.txt` vs
   `ros_gz_bridge/CMakeLists.txt`) — "can't read CMakeLists.txt".
4. **104-minute build burned by a transient network flake**: the S3
   mirror SSL failure ("Curl error (56) … unexpected eof") broke the
   builddep transaction downloading `python3-numpy-f2py`; the chroot
   silently lacked the new `-devel` packages, producing misleading
   downstream errors (`Could NOT find Protobuf`).
5. **`protobuf-devel`/`cppzmq-devel` genuinely absent** — I had assumed
   the vendor RPMs' runtime `Requires:` would pull them; **builddep does
   not install BR-packages' runtime Requires**. Added explicitly, with
   `zeromq-devel`.
6. **`FindCPPZMQ.cmake` found but its helpers weren't defined**
   (`_gz_cmake_parse_arguments` unknown): cherry-picking the find-module
   off the module path isn't enough — gz-cmake3's modules depend on each
   other. Fix: `find_package(gz-cmake3 REQUIRED)` first (its config does
   `include(GzCMake)` + appends the module path itself), with explicit
   `list(PREPEND CMAKE_PREFIX_PATH …/opt/gz_cmake_vendor)` so the config
   is found.
7. **Protobuf module/config-mode collision** — my injected
   `find_package(Protobuf REQUIRED)` (CMake module mode → 4 targets)
   collided with gz's `FindGzProtobuf` → config mode → 8 targets:
   ```
   Some (but not all) targets in this export set were already defined.
   ```
   **Fix: do NOT pre-find Protobuf at all** — let `FindGzProtobuf` do the
   single clean config-mode find, exactly like the vendor builds.

Final injected preamble (encoded in the generator for all ros_gz pkgs):

```cmake
list(APPEND CMAKE_MODULE_PATH "<vendor>/opt/gz_cmake_vendor/share/cmake/gz-cmake3/cmake3")
list(PREPEND CMAKE_PREFIX_PATH "<vendor>/opt/gz_cmake_vendor")
find_package(gz-cmake3 REQUIRED)
find_package(CPPZMQ REQUIRED)
find_package(gz_transport_vendor REQUIRED)   ← original first gz find
```

With that, the bridge configured, compiled, and installed — and
`ros_gz_image` then passed **first try** on the same patterns.

### The fmt-12 war (blocked `ros_gz_sim`'s builddep)

```
package ros-jazzy-gz-common-vendor requires libavdevice.so.62
  → libavdevice-free-8.1.3-1.hum1 requires libopenal.so.1
    → openal-soft-1.24.2-6.fc44 (Fedora) requires libfmt.so.11
      → spdlog-1.17 (Hummingbird, via rcl-logging-spdlog) requires libfmt.so.12
        → cannot install both fmt-11 and fmt-12
```

**Root cause:** the THIRD rawhide-cohort skew (after icu78 and samba) —
this time via openal-soft, dragged in by `libavdevice-free`'s hard
`libopenal` requirement. **Fix:** rebuild ffmpeg with
`--disable-openal` (and drop `pkgconfig(openal)` from the BR): gz's av
is video *encoding* only; the openal audio-*input* backend in
libavdevice is unused. Verified `libavdevice-free` no longer requires
`libopenal`; staged the full 8-piece `-free` set into both `~/ros-local-
rpms` and the image staging dir (the previously staged copies carried
the openal requirement and would have broken the image build the same
way).

`ros_gz_sim` then needed one more BR round (`qt5-qtbase-devel` etc. —
its config chain reaches `gz-gui8-config` → `find_package(Qt5 …)`), and
**built**, followed instantly by the `simulation` metapackage. **Tier B:
11/11.**

## 8. The image — `images/simulation-rpms/`

Dockerfile modeled on `ros-base-rpms` (ARG `BASE_IMAGE`, transient
local repo via `createrepo_c`, `dnf install ros-jazzy-simulation`,
cleanup incl. `/var/lib/dnf/repos`). The staging dir
`images/simulation-rpms/rpms/` carries the **full closure (257 RPMs)**:
Tier A 17 + Tier B 11 + ros_core/ros_base restage (harmless; also
satisfies uninstalled-in-base deps) + the enablers (icu78 Qt5 QML, no-smb
gdal, **no-smb+no-openal ffmpeg**, fiddle).

### Image-build failure 1 — the Ruby parallel-stream conflict

```
file …/specifications/default/yaml-0.4.0.gemspec conflicts between
  ruby4.0-default-gems-4.0.7-40.1.hum1 and ruby3.3-default-gems-…
  (and ruby3.4-default-gems)
```

Diagnosed with an `--assumeno` dry-run: with
`--setopt=install_weak_deps=0` the transaction **resolves cleanly (301
packages)** — the parallel ruby3.3/3.4 streams were arriving as **weak
dependencies**. Fix: `install_weak_deps=0` on the simulation install.

### Image-build failure 2/3 — the gz Ruby CLI's gems

- **`psych`**: `gz` (a Ruby script) requires `yaml` → psych, no longer a
  Ruby 4.0 default gem; normally a weak dep of ruby (now suppressed).
  `rubygem4.0-psych` exists in the Hummingbird repo → added explicitly.
- **`fiddle`**: the CLI's `SharedLibInterface` dlopens the gz command
  libraries via fiddle — **not a Ruby 4.0 default gem and not in the
  Hummingbird repo at all** (Ruby 4.0 externalized it from the source
  tree; verified `ext/fiddle` absent from the ruby-4.0.7 tarball).

**Built `rubygem4.0-fiddle` 1.1.8** from the rubygems.org gem, layout
mirroring `rubygem4.0-psych` (`.so` under `/usr/lib64/gems/ruby/fiddle-
1.1.8/` + a stdlib copy under `/usr/lib64/ruby/`, gem files under
`/usr/share/gems/`). Its own sub-saga:

1. `%setup -T -n …` without `-c` — the build dir was never created
   ("cd: fiddle-1.1.8: No such file or directory"). Fix: `-T -c`.
2. **`gcc` missing from the buildroot** — mkmf's "The compiler failed to
   generate an executable file" was literally *command not found*:
   reproduced by hand (`gcc: command not found` in the chroot). The
   hummingbird mock config does **not** preinstall the toolchain — every
   other spec in this repo carries `BuildRequires: gcc-c++`; this one
   needed `BuildRequires: gcc` (+ `make`). The mkmf.log didn't print the
   error, which cost a debugging round-trip.
3. **Build-time gemspec ≠ installed gemspec**: copying the gem's own
   `fiddle.gemspec` produced `Invalid gemspec … No such file or directory
   @ rb_sysopen - …/specifications/lib/fiddle/version.rb` — it evaluates
   `version.rb` relative to itself at load time. Rubygems then refused to
   activate the gem → `cannot load such file -- fiddle/import`. Fix:
   generate the installed form from the gem metadata:
   `gem spec %{SOURCE0} --ruby > …/fiddle-1.1.8.gemspec` (first attempt
   used the bare filename — `gem` needs the full `%{SOURCE0}` path).

Image rebuilt with `rubygem4.0-psych rubygem4.0-fiddle` in the install
list → **`simulation-rpms-rt:latest` (3.43 GB) BUILT**.

## 9. Verification (container on the Lima VM)

| Check | Result |
|---|---|
| `ros2 pkg list` | **219** (192 base + Tier B + vendors) |
| kernels | `kernel-rt-core-7.2.7-200.fc44.aarch64` only, stock absent |
| `bootc container lint` | pass (1 skip, 2 cosmetic warnings) |
| `gz sim --version` | **Gazebo Sim 8.15.0** (psych + fiddle working) |

### Headless physics — the plugin-path trap, again

First run: topics existed but

```
[Err] [SystemLoader.cc:92] Failed to load system plugin
  [gz-sim-physics-system] : Could not find shared library.
[Err] [ServerConfig.cc:1004] Failed to copy installed config
  [/builddir/build/BUILD/…BUILDROOT/usr/lib64/…/server.config] …
```

— the exact sim-bundle-era trap: only `GZ_CONFIG_PATH` is set by the
vendor hooks; `GZ_SIM_SYSTEM_PLUGIN_PATH`/`GZ_SIM_PHYSICS_ENGINE_PATH`
are not, and the vendored server bakes its **buildroot** into the default
config path. My first path globs also missed the real layout: systems
live in `…/opt/gz_sim_vendor/lib64/gz-sim-8/plugins/`, physics engines
directly in `…/opt/gz_physics_vendor/lib64/` **with versioned names**
(`libgz-physics7-bullet-plugin.so` — so the engine flag is
`gz-physics7-bullet-plugin`, not `gz-physics-bullet-plugin`).

With the paths exported (test script
`.poc-scratch/sim/physics-test.sh`, world
`.poc-scratch/sim/falling.sdf` — sphere at z=10 with explicit
Physics/UserCommands/SceneBroadcaster system plugins):

```
$ gz sim -s -r --physics-engine gz-physics7-bullet-plugin falling.sdf
$ gz topic -e -t /world/falling/pose/info -n 1
pose { name: "ball"  position { z: -481.54135131835938 } }
```

**z: 10 → −481.5 in 10 s of sim time; free-fall predicts −480. Bullet
physics verified, log error-free.** (DART remains deferred — fcl missing
in Fedora 44.)

### Bridge round-trip

`.poc-scratch/sim/bridge-test.sh`:

```
$ ros2 run ros_gz_bridge parameter_bridge \
    /clock@rosgraph_msgs/msg/Clock[gz.msgs.Clock
$ ros2 topic echo --once /clock
clock:
  sec: 14
  nanosec: 789000000
```

**gz sim → gz-transport → parameter_bridge → ROS 2 DDS → echo, at live
sim time. Round-trip verified.**

## 10. Copy to the host podman machine

- The Lima VM had **stopped itself** right before the first save
  (`limactl start fedora`; podman store intact — no loss).
- `podman save | gzip` streamed out over ssh →
  `artifacts/simulation-rpms-rt-fc44-aarch64.oci.tar.gz` (1.5 GB), then
  `podman load` into the macOS machine. ⚠️ Agent shells must export
  `XDG_CONFIG_HOME=~/.config XDG_DATA_HOME=~/.local/share` first or the
  podman CLI is blind to the machine + connections.
- Tagged `:fc44-aarch64`; verified natively on the Mac:
  `Gazebo Sim 8.15.0`, 219 pkgs, `kernel-rt-core-7.2.7-…+rt`.

## 11. Commits & artifacts

| Repo | Commit | Content |
|---|---|---|
| hummingbird-rpms | `8647926c` | Tier B (11 specs) + gz-sim-vendor + fixed gz-common + generator quoting fixes |
| hummingbird-rpms | `2e578ac9` | `rubygem4.0-fiddle` enabler + ffmpeg `--disable-openal` |
| hummingbird-ros2-poc | `8e47915` | `images/simulation-rpms/` (Dockerfile + .gitignore) + docs |
| hummingbird-ros2-poc | `6476fa5` | artifacts.md: archived + loaded into the macOS machine |

Artifacts: `artifacts/simulation-rpms-rt-fc44-aarch64.oci.tar.gz`
(1.5 GB). Harness scripts (gitignored scratch, referenced by the docs):
`.poc-scratch/sim/{prep-gz-sim.sh, gen-tierb.sh, build-tierb.sh,
fix-gzsim-quotes.py, rubygem4.0-fiddle.spec, physics-test.sh,
bridge-test.sh, falling.sdf, ruby-dryrun.sh, core-dryrun.sh}`.

## 12. Complete lessons table

| # | Challenge | Root cause | Fix (where it lives now) |
|---|---|---|---|
| 1 | `%files` rejects space-containing filenames | rpm's file list is whitespace-separated; gz-sim ships 6 such files | quote manifest paths — spec + `gen_gz_vendor.sh` |
| 2 | Quoting fix shifted quotes onto next lines | closing `"` placed after `\n` in `find -printf` | quote before `\n` — spec + generator |
| 3 | Rebuilds die in workdir cleanup | build container leaves subuid-owned files | `sudo rm -rf builds/<pkg>` first — build driver |
| 4 | Staged RPMs invisible to next build (`No match for argument`) | container-written RPMs are mode 640; `createrepo_c` silently skips unreadable files | `chmod 644` after staging — driver |
| 5 | 104-min build with misleading errors | transient S3-mirror SSL failure broke builddep; chroot silently degraded | nothing to fix — recognize the pattern |
| 6 | Tier B closure too small | docs' table missed 5 msg packages ros_gz 1.0.25 actually needs | map closures from `package.xml`s — `gen-tierb.sh` |
| 7 | `Could NOT find OpenSSL` (image_transport) | rclcpp→fastrtps cmake chain needs OpenSSL headers | system-BR set for cmake-kind packages |
| 8 | `Could NOT find UUID` (bridge) | gz-transport config's `FindUUID` | `libuuid-devel` BR |
| 9 | `protobuf::libprotobuf`/`CPPZMQ::CPPZMQ` targets not found | vendored gz configs reference IMPORTED targets without finding them | inject `find_package(CPPZMQ)` (+ gz-cmake3) before the gz finds — generator |
| 10 | `Some (but not all) targets already defined` | my module-mode Protobuf find vs gz's config-mode find | do NOT pre-find Protobuf |
| 11 | `_gz_cmake_parse_arguments` unknown | FindCPPZMQ depends on gz-cmake3's helpers | `find_package(gz-cmake3 REQUIRED)` + prefix/module-path hints |
| 12 | `Qt5Config.cmake` not found (ros_gz_sim) | its config chain reaches gz-gui8→find_package(Qt5) | Qt5 devel trio BR |
| 13 | fmt-11 vs fmt-12 conflict | openal-soft (via libavdevice-free←gz-common av) links fmt-11; spdlog 1.17 needs fmt-12 | ffmpeg `--disable-openal` — spec `2e578ac9` |
| 14 | ruby3.3/3.4/4.0 default-gems conflicts | parallel ruby streams pulled by weak deps | `install_weak_deps=0` — Dockerfile |
| 15 | gz CLI: `psych` missing | not a Ruby 4.0 default gem; weak-dep-suppressed | explicit `rubygem4.0-psych` |
| 16 | gz CLI: `fiddle` missing | externalized from Ruby 4.0; absent from the Hummingbird repo | **new enabler RPM `rubygem4.0-fiddle`** |
| 17 | mkmf "compiler failed" with no error shown | `gcc` not in mock buildroot (no toolchain preinstall) | every spec BRs its compiler |
| 18 | `Invalid gemspec … version.rb` | gem's own gemspec is build-time, not installed-form | `gem spec %{SOURCE0} --ruby` |
| 19 | Sim runs with no physics | `GZ_SIM_*` plugin paths unset (vendored RPMs bake no defaults; buildroot baked into server.config path) | export paths (runtime); **TODO: bake into image entrypoint** |
| 20 | Engine flag rejected | this build names engines `libgz-physics7-*-plugin.so` (versioned) | `--physics-engine gz-physics7-bullet-plugin` |
| 21 | Generator sed split expressions | `\n` in a sed *replacement* inserts a newline | backslash-doubling before substitution |
| 22 | Plain chain blocked | `bootc-os:latest` rolled; ros-core closure no longer resolves | OPEN — the RT chain is immune (digest-pinned base) |

## 13. What remains

- **Bake the `GZ_*` runtime paths** into the image (profile.d hook or
  entrypoint; `images/sim-bundle/sim-entrypoint.sh` is the reference).
- **Plain (non-RT) `simulation-rpms`**: diagnose the ros-core closure
  failure on the rolled `bootc-os:latest` (assumeno pre-check; likely
  another enabler rebuild or a base pin).
- **x86_64** of the whole stack (same specs; EC2 c6i-class builder).
- GUI runtime (QML modules + software GL) on the image; booting the sim
  image as a robot OS; pushing to quay (same convention as ros-base).
