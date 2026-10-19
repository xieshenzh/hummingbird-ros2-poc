# ROS 2 `ros-base` as Hummingbird-built RPMs (`images/ros-base-rpms`)

> Detail doc for [`../CLAUDE.md`](../CLAUDE.md). Extends the strategic
> Hummingbird-RPM path ([`ros-core-rpms.md`](ros-core-rpms.md)) from `ros_core`
> up to `ros_base`. **Status: all 41 RPMs BUILT on aarch64 (2026-10-15); image
> built + verified on the latest Hummingbird base. x86_64 pending.**

## What `ros_base` adds over `ros_core`

`ros_base` is the next REP-2001 variant. Its metapackage (`ros2/variants`,
jazzy) is exactly `ros_core` + **5 roots**:

```
ros_base  =  ros_core  +  rosbag2  +  geometry2  +  kdl_parser  +  urdf  +  robot_state_publisher
```

The 162-package `ros_core` closure is **already built on both arches**
(`images/ros-core-rpms/rpms{,-x86_64}/`). This effort is the **delta**: the
transitive closure of those 5 roots that is not already in `ros_core`.

## The delta closure — 40 new `ros-jazzy-*` RPMs + 1 system RPM

Mapped from the actual jazzy-branch `package.xml` files (BUILD_TESTING=OFF →
`test_depend` skipped). Two independent subtrees:

### A. geometry2 / urdf / kdl / robot_state_publisher — 21 packages

Build order (leaves first). All `ament_cmake` unless noted.

| # | package | repo | ver | type | new-pkg deps | system -devel |
|---|---|---|---|---|---|---|
| 1 | eigen3_cmake_module | ros2/eigen3_cmake_module | 0.3.1 | noarch cmake-module | — | (finds eigen3) |
| 2 | tf2 | ros2/geometry2 | 0.36.23 | C++ | — | — |
| 3 | tf2_msgs | ros2/geometry2 | 0.36.23 | msgs (arch) | — | — |
| 4 | message_filters | ros2/message_filters | 4.11.17 | C++ | — | — |
| 5 | urdf_parser_plugin | ros2/urdf | 2.10.1 | C++ (headers) | — | urdfdom-headers |
| 6 | orocos_kdl_vendor | ros2/orocos_kdl_vendor | 0.5.2 | vendor (arch) | eigen3_cmake_module | eigen3-devel, **orocos-kdl-devel** |
| 7 | tf2_py | ros2/geometry2 | 0.36.23 | C-ext (arch) | tf2 | — |
| 8 | urdf | ros2/urdf | 2.10.1 | C++ | urdf_parser_plugin | **urdfdom-devel**, urdfdom-headers |
| 9 | tf2_ros | ros2/geometry2 | 0.36.23 | C++ | message_filters, tf2, tf2_msgs | — |
| 10 | python_orocos_kdl_vendor | ros2/orocos_kdl_vendor | 0.5.2 | vendor (arch) | orocos_kdl_vendor | **python3-pykdl** |
| 11 | tf2_ros_py | ros2/geometry2 | 0.36.23 | ament_python (noarch) | tf2_msgs, tf2_py | — |
| 12 | tf2_eigen | ros2/geometry2 | 0.36.23 | C++ (header) | tf2, tf2_ros | eigen3-devel |
| 13 | tf2_bullet | ros2/geometry2 | 0.36.23 | C++ (header) | tf2, tf2_ros | **bullet-devel** |
| 14 | tf2_eigen_kdl | ros2/geometry2 | 0.36.23 | C++ | tf2, orocos_kdl_vendor | eigen3-devel |
| 15 | kdl_parser | ros/kdl_parser | 2.11.0 | C++ | orocos_kdl_vendor, urdf | urdfdom-headers |
| 16 | tf2_sensor_msgs | ros2/geometry2 | 0.36.23 | C++/py | tf2, tf2_ros, tf2_ros_py, eigen3_cmake_module | eigen3-devel |
| 17 | tf2_geometry_msgs | ros2/geometry2 | 0.36.23 | C++/py | tf2, tf2_ros, tf2_ros_py, orocos_kdl_vendor | — |
| 18 | tf2_kdl | ros2/geometry2 | 0.36.23 | C++ | tf2, tf2_ros, orocos_kdl_vendor, python_orocos_kdl_vendor, tf2_ros_py | — |
| 19 | tf2_tools | ros2/geometry2 | 0.36.23 | ament_python (noarch) | tf2_msgs, tf2_py, tf2_ros_py | (exec: graphviz, python3-yaml) |
| 20 | robot_state_publisher | ros/robot_state_publisher | 3.3.4 | C++ | kdl_parser, orocos_kdl_vendor, urdf, tf2_ros | — |
| 21 | geometry2 | ros2/geometry2 | 0.36.23 | noarch metapackage | all tf2_* above | — |

### B. rosbag2 — 18 packages

All from `ros2/rosbag2` jazzy (version **0.26.11**) except `yaml_cpp_vendor`
(ros2/yaml_cpp_vendor, 9.0.1) and `keyboard_handler` (ros-tooling/keyboard_handler,
0.3.2). Build order (leaves first):

| # | package | ver | type | new-pkg deps | system -devel |
|---|---|---|---|---|---|
| 1 | keyboard_handler | 0.3.2 | C++ | — | — |
| 2 | yaml_cpp_vendor | 9.0.1 | vendor | — | yaml-cpp-devel |
| 3 | zstd_vendor | 0.26.11 | vendor | — | libzstd-devel (≥1.5.1) |
| 4 | liblz4_vendor | 0.26.11 | vendor | — | lz4-devel |
| 5 | sqlite3_vendor | 0.26.11 | vendor | — | sqlite-devel |
| 6 | rosbag2_interfaces | 0.26.11 | msgs (arch) | — | — |
| 7 | mcap_vendor | 0.26.11 | vendor (compiled) | liblz4_vendor, zstd_vendor | (lz4, zstd) **⚠ always downloads mcap** |
| 8 | rosbag2_storage | 0.26.11 | C++ | yaml_cpp_vendor | — |
| 9 | rosbag2_cpp | 0.26.11 | C++ | rosbag2_storage | — |
| 10 | rosbag2_storage_mcap | 0.26.11 | C++ plugin | mcap_vendor, rosbag2_storage, yaml_cpp_vendor | — |
| 11 | rosbag2_storage_sqlite3 | 0.26.11 | C++ plugin | sqlite3_vendor, rosbag2_storage, yaml_cpp_vendor | — |
| 12 | rosbag2_compression | 0.26.11 | C++ | rosbag2_cpp, rosbag2_storage | — |
| 13 | rosbag2_storage_default_plugins | 0.26.11 | noarch metapackage | rosbag2_storage_mcap, rosbag2_storage_sqlite3 | — |
| 14 | rosbag2_compression_zstd | 0.26.11 | C++ plugin | rosbag2_compression, zstd_vendor | — |
| 15 | rosbag2_transport | 0.26.11 | C++ | rosbag2_compression, rosbag2_cpp, rosbag2_interfaces, rosbag2_storage, yaml_cpp_vendor, keyboard_handler | — |
| 16 | rosbag2_py | 0.26.11 | pybind11 (arch) | rosbag2_compression, rosbag2_cpp, rosbag2_storage, rosbag2_transport | python3-devel |
| 17 | ros2bag | 0.26.11 | ament_python (noarch) | rosbag2_py, rosbag2_storage_default_plugins | (exec: python3-pyyaml) |
| 18 | rosbag2 | 0.26.11 | noarch metapackage | ros2bag + all rosbag2_* | — |

**NOT in the jazzy closure** (do not build): `shared_queues_vendor` (orphaned —
no package.xml depends on it in jazzy), `urdf_parser_py`/`urdfdom_py`, and all
`*_test*`/benchmark/example packages.

### C. The metapackage + the urdfdom gap

- **`ros-base`** metapackage (`ros2/variants`, 0.11.0) — the 40th ros-jazzy RPM;
  its install pulls A + B.
- **`urdfdom` — the one real system gap.** `urdf` / `kdl_parser` /
  `robot_state_publisher` bind `liburdfdom*`. **Verified live 2026-10-15:**
  Fedora **44 retired `urdfdom`** (compiled lib) — repoquery over
  `fedora`+`updates`+`public-hummingbird` returns MISSING; only the **noarch
  `urdfdom-headers-devel` 1.1.2** survives (carried from fc43). So `urdfdom-devel`
  does **not** resolve on the current base and must be supplied by us.
  - **Recommended:** build `ros-jazzy-urdfdom` (ros/urdfdom **4.0.2**, build_type
    `cmake`; BR urdfdom-headers + console-bridge-devel + tinyxml2-devel) and keep
    `urdfdom_headers` from the Fedora noarch (present). Then override the `urdfdom`
    rosdep key → the ros-jazzy name in the `urdf`/`kdl_parser` specs.
  - **Alternative:** revive the retired Fedora `urdfdom` spec and rebuild it
    `.hum1` for fc44 (gives stock `urdfdom`/`urdfdom-devel`). More faithful to the
    system-package model but resurrects an orphaned spec.
  - (Optionally also build `ros-jazzy-urdfdom-headers` 1.1.3 for self-consistency;
    not required while the Fedora noarch is present.)

**Total new to build: 40 `ros-jazzy-*` RPMs + 1 `urdfdom` RPM = 41.** (All
noarch RPMs are arch-agnostic; the compiled ones must be built once per arch,
same as `ros_core`.)

## Compatibility with the LATEST Hummingbird bootc-os (the user's explicit ask)

Context: the `ros_core` RPMs were built ~2 weeks ago; the base rolls ~daily. The
question is whether `ros_base`, built now, co-installs with the 2-week-old
`ros_core` RPMs on **today's** base. Verified live against
`quay.io/hummingbird-community/bootc-os:latest` + the live
`public-hummingbird` + Fedora 44 repos (2026-10-15):

| Axis | Finding | Verdict |
|---|---|---|
| **Python** | base = **3.14.8** (`python3-3.14.8-1.1.hum1`); the ros_core compiled RPMs target 3.14 | ✅ ABI unchanged — no rebuild |
| **ros_core still resolves** | `dnf install --assumeno ros-jazzy-ros-core` against {staged ros_core RPMs + Fedora44 + hummingbird} → **clean, no missing/conflict** (108 MiB) | ✅ 2-week-old RPMs still good |
| **spdlog (the one rawhide soname ros_core binds)** | hummingbird repo still ships `spdlog-1.17.0-3.1.hum1` → `libspdlog.so.1.17` | ✅ satisfied |
| **ros_base system libs** | orocos-kdl **1.5.3**, bullet **3.08**, console-bridge **1.0.2**, tinyxml2 **11.0.0**, yaml-cpp **0.8.0**, eigen3 **5.0.1** — all from **stable Fedora** (not the rolling rawhide cohort); sqlite/zstd/lz4 present (hummingbird + Fedora, stable sonames) | ✅ low skew risk |
| **urdfdom** | retired in Fedora 44 — see §C | ⚠ we supply it |
| kernel | base bumped to **7.2.10-200.fc44** (was 7.2.7/7.2.8) | irrelevant to userspace ROS |

**Conclusion — how to stay compatible:** build the `ros_base` RPMs in the **same
build env the base is cut from** (fedora:44 mock + the current `public-hummingbird`
repo), feeding the existing 162 `ros_core` RPMs via `--local-rpms-dir`. Because
(a) Python stays 3.14, (b) `ros_core` still resolves on today's base, and (c) the
`ros_base` C++ libs come from *stable* Fedora rather than the volatile rawhide
cohort, the freshly-built `ros_base` RPMs will co-install with the 2-week-old
`ros_core` RPMs on the latest base. **No `ros_core` rebuild is required.** Run the
`--assumeno ros-jazzy-ros-base` pre-check on the live base before each image build
to catch any future base bump that moves one of the shared sonames.

Unlike `simulation`/`gazebo`, **nothing in this closure links boost** → no
boost-skew blocker here.

## How to build (recipe)

Same Hummingbird dev workflow as `ros_core` ([[ros2-packaging-approach]],
[[ros2-build-env-lima]]): author one spec per package (rosfed as the reference,
adapted to HB conventions — SPDX license, `%autochangelog`, SHA512 `sources`),
then `./ci/build_rpms.sh --build-dir /tmp/rpm-build --local-rpms-dir ~/ros-local-rpms <pkg>`
in topological order, copying each result back into `~/ros-local-rpms/` so later
packages resolve. Reuse `rpms/_rosidl_src/gen_tier2.sh` / `build_one.sh` to
generate specs from the per-package BR/Requires table.

- **aarch64:** native on the Lima Fedora VM (no qemu).
- **x86_64:** native on an EC2 `c6i.2xlarge` (mock `legal_host_arches` needs an
  x86_64 host). Same specs/sources, `build_rpms.sh --arch x86_64`.
- **Build order:** A (1→21) and B (1→18) are independent; `urdfdom` before `urdf`
  (#8 in A). A single strict pass may stall on undeclared runtime `Requires:`
  edges — use the ros_core multi-pass retry driver.

**Gotchas to carry over / new:**
- **Vendor packages must link the SYSTEM lib, not download.** `orocos_kdl_vendor`,
  `python_orocos_kdl_vendor`, `yaml_cpp_vendor`, `zstd_vendor`, `liblz4_vendor`,
  `sqlite3_vendor` all probe for the system lib and fall back to a network
  download if absent. BuildRequires the matching `-devel` (orocos-kdl-devel,
  python3-pykdl, yaml-cpp-devel, libzstd-devel, lz4-devel, sqlite-devel) so they
  take the system path — mock has no network.
- **⚠ `mcap_vendor` ALWAYS FetchContent-downloads** foxglove/mcap v1.3.1 (+ in-tree
  patches); there is no system-satisfied path. Pre-vendor the mcap tarball into
  `sources` (SHA512-pinned) for a hermetic mock build, or `rosbag2_storage_mcap`
  cannot build offline. (mcap is the newer default bag format; sqlite3 is the
  legacy one — both are pulled by `rosbag2_storage_default_plugins`.)
- `eigen3_cmake_module` is the only missing *buildtool* — build it first; every
  eigen-consuming tf2 package find_package()s it.

## How to build the IMAGE

Scaffolded at `images/ros-base-rpms/` (Dockerfile + .gitignore). It is thin:
`FROM ros-core-rpms` (inherits repos + entrypoint/profile), COPY the 41 new RPMs
→ `createrepo_c` a transient `/var/tmp` repo → `dnf install ros-jazzy-ros-base`
→ clean up. Stage the matching arch into `rpms/` first (gitignored).

```bash
# plain:
podman build -t hummingbird-ros2-poc/ros-base-rpms:latest images/ros-base-rpms
# on the RT ros-core (hummingbird base + PREEMPT_RT kernel — the user's target):
podman build \
  --build-arg BASE_IMAGE=localhost/hummingbird-ros2-poc/ros-core-rpms-rt:latest \
  -t hummingbird-ros2-poc/ros-base-rpms-rt:latest images/ros-base-rpms
```

The full RT robot-OS chain: `bootc-os` → `bootc-os-rt` (PREEMPT_RT kernel swap,
[[rt-kernel-fedora-srpm]]) → `ros-core-rpms-rt` → **`ros-base-rpms-rt`**.

## Verify (planned, per arch)

- Closure resolves; `ros2 pkg list` grows by the ros_base set; `ros2 run
  tf2_ros tf2_echo`, `ros2 bag record/play` smoke tests; a URDF →
  `robot_state_publisher` → tf2 round-trip.
- `bootc container lint --no-truncate` passes; `CMD [/sbin/init]` + kernel + bootc
  inherited (bootable).
- For RT: layer on `ros-core-rpms-rt`, confirm the `+rt` kernel survives and
  Fast-DDS round-trips (as in [`realtime-kernel.md`](realtime-kernel.md)).

## Results — aarch64 BUILT & VERIFIED (2026-10-15)

All 41 RPMs built natively on the Lima aarch64 VM (no qemu), Hummingbird mock
workflow, fed the 162 `ros_core` RPMs via `--local-rpms-dir`. Specs committed to
`hummingbird-rpms` (`add-ros2-jazzy-packages`, commit `6bbb756a`).

- **Closure resolves on the LATEST base cohort:** `dnf install --assumeno
  ros-jazzy-ros-base` against {41 new + 162 ros_core + Fedora 44 +
  `public-hummingbird`} = **465 packages, no missing/conflicts**. Real install
  also clean.
- **Image `ros-base-rpms:latest` — 1.96 GB** on `bootc-os:latest` (via
  `ros-core-rpms:latest`); `ros2 pkg list` = 192; `bootc container lint` **14/0**
  (after the `enable-repos.sh` `/tmp` cleanup fix below).
- **Functional on the Hummingbird base (gcc 16 runtime):**
  - `ros2 run tf2_ros tf2_echo` loads + spins (proper "waiting for transform").
  - `robot_state_publisher` loads + parses args.
  - **`ros2 bag record` → mcap** (Jazzy default storage): recorded `/chatter`,
    `ros2 bag info` = Storage id `mcap`, 48 msgs, `std_msgs/String` cdr —
    proves `mcap_vendor` + the mcap storage plugin work end-to-end.
- **`ros-base-rpms-rt:latest` — 2.51 GB** built on the existing RT ros-core base
  (`ros-core-rpms-rt:fc44-aarch64`) — proves the RT robot-OS chain carries
  ros_base. (The RT *kernel* there is the 7.2.7 build; a 7.2.10 kernel-rt rebuild
  for the current base is the standard follow-up per [`realtime-kernel.md`](realtime-kernel.md).)

### RT image: rebuilt fresh, rechunked, booted + RT-verified, suites re-run (2026-10-16)

The full ros-core→ros-base RT chain was rebuilt from scratch on the Lima aarch64
VM (the images from the Oct 15 session only existed in a since-deleted macOS
podman machine; the RPM staging + archived RT base were intact):

- **Bug found + fixed on the way:** `images/ros-core-rpms/enable-repos.sh`
  crashed on the RT base — the disttag detection (2026-10-13) queried
  `kernel-core`, which bootc-os-rt does not ship (stock kernel is swapped for
  `kernel-rt-core`), and the failed query killed the script under `pipefail`
  before the `rpm -qa` fallback. Fix (commit `aaa31cb`): query both kernel
  flavors + make detection pipefail-tolerant. The RT build path had been broken
  since the disttag fix landed (the Oct 1 RT image predated it).
- **`ros-core-rpms-rt:fc44-aarch64`** rebuilt from the archived
  `bootc-os-rt:fc44-aarch64` (kernel swap unchanged) with the CURRENT
  Dockerfile/enable-repos.sh and the **fixed `rcl_logging_spdlog`** RPM staged
  (same NVR as the pre-fix build — content-verified by checksum). 1.98 GB,
  lint 14/1.
- **`ros-base-rpms-rt:latest` — 2.52 GB**; `ros2 pkg list` = 192; lint 14/1;
  kernel-rt 7.2.7 only (stock kernel absent).
- **Rechunked** (chunkah): **2.52 → 1.73 GB**, kernel in its own 175 MB layer
  (`ros-base-rpms-rt-chunked:latest` / `:fc44-aarch64`).
- **Container tests, BOTH plain + chunked:** the functional set (tf2_echo
  spins, robot_state_publisher loads, rosbag2 mcap record→info→**play
  round-trip**, default Fast-DDS pub/sub) all PASS; lint 14/1.
- **Full suites on the RT image:** `test_tf2` + `rosbag2_tests` via
  `Containerfile.test-dev` on `ros-base-rpms-rt:latest` — **184 tests, 0
  errors, 0 failures, 9 skipped (cppcheck)** — identical profile to the non-RT
  image; `play_end_to_end` 14/14 re-proves the spdlog shutdown fix on the RT
  stack.
- **BOOTED + PREEMPT_RT confirmed live (TCG, 2026-10-16):** aarch64 path from
  the base-switch PoC — thin serial-login overlay → `bootc install to-disk
  --via-loopback` → qemu TCG (Lima VM, no KVM) → `rt-serial-verify.py` rc=0:
  banner `7.2.7-200.fc44.aarch64+rt … #1 SMP PREEMPT_RT`, getty login, live
  `uname -r`/`-v`, cmdline `preempt=full nowatchdog`. Transcripts:
  `artifacts/serial-rosbase-rt-aarch64.txt` (+ ros-over-serial below).
  - Layout note: bootc 1.17 installs with **/boot INSIDE root** (2 partitions:
    ESP + root) and an empty deploy fstab — the historical aarch64-TCG `/boot`
    device-timeout emergency-mode issue does not apply; no fstab aid needed.
  - **ros_base on the booted RT VM (over serial):** `ros2 pkg list` = **192**
    and a **default Fast-DDS pub/sub round-trip PASS** (`ROS2_ON_RT_OK`) —
    the same class of on-boot proof as the base-switch PoC. The rosbag2 leg
    produced no result: `ros2 bag record` was killed by its 400 s harness
    timeout mid-cold-start (TCG makes every CLI cold-start multi-minute;
    bag.out holds only the startup warning). Test-harness artifact, NOT a
    functional failure — the same rosbag2 mcap stack passes in-container on
    this image (smoke round-trip + suites 184/0/0). Transcript:
    `artifacts/serial-rosbase-rt-ros-aarch64.txt`.
  - Harness: `.poc-scratch/rosbase-rt/` (login overlay, install-disk, two-boot
    verify, serial ROS drivers). Two driver lessons encoded there: serial
    sends MUST interleave reads (the first driver deadlocked — qemu applies
    backpressure once its chardev buffer fills, and the naive per-char
    `sendall` from the base-switch scripts only survived under KVM), and
    TCG-timeout budgets must assume multi-minute `ros2` cold starts.
- **Archived:** `artifacts/ros-base-rpms-rt-fc44-aarch64.oci.tar.gz` (1.18 GB)
  + `artifacts/ros-base-rpms-rt-chunked-fc44-aarch64.tar.gz` (598 MB).
- ⚠️ **Not a valid test on stock Fedora:** these C++ RPMs are built against the
  Hummingbird rawhide cohort (gcc 16 libstdc++); running them in plain `fedora:44`
  segfaults (gcc 14 runtime). Always runtime-test on the Hummingbird bootc-os base
  — same rule as `ros_core`.

### ROS 2 test suites — aarch64 (2026-10-15)

Ran the upstream ros_base test packages against the **installed** RPMs (dedicated
test packages built on the shipped-RPM underlay — tests what we ship, same method
as ros_core's `test_rclcpp`/`test_communication` in [`base-switch-poc.md`](base-switch-poc.md)).
Runner: `scripts/run-test-suites-rosbase.sh` + the `base-switch-poc/Containerfile.test-dev`
overlay on `ros-base-rpms:latest`.

- **`test_tf2` (geometry2) — 100% pass:** buffer_core_test 15/0, test_convert 6/0,
  test_message_filter 9/0, test_tf2_bullet 2/0, test_utils 2/0,
  test_buffer_client_tester 2/0, test_static_publisher 2/0 — the full tf2
  transform/buffer/listener/conversion/message-filter surface.
- **`rosbag2_tests` — 100% pass after the spdlog fix below:** record_end_to_end
  32/0, info_end_to_end 26/0, **play_end_to_end 14/14**, cpp_api 2/0,
  get_service_info 6/0, test_converter, test_reindex, storage_api 2/0, + all
  cpplint/cppcheck/uncrustify/copyright/xmllint. **Full suite: 184 tests, 0 errors,
  0 failures, 9 skipped (cppcheck).** Before the fix, the lone failure was
  `play_fails_gracefully_if_needed_converter_plugin_does_not_exist` (exited
  `11`/`134`/`139` instead of `1` — see root cause + fix below).

#### Root cause of the negative case (investigated 2026-10-15) — a ros_core spdlog-shutdown crash, NOT an mcap/ros_base bug

The missing-converter path makes `ros2 bag play` (a C++ process) `exit()` **without**
a clean `rclcpp::shutdown()`, so logging is torn down from the libc `exit()` atexit
path. That crashes **nondeterministically** (SIGSEGV 139 / SIGABRT 134 / occasionally
clean) — memory corruption. gdb backtrace:

```
#0 spdlog::details::registry::drop(...)   /lib64/libspdlog.so.1.17
#1 rcl_logging_external_shutdown()        librcl_logging_spdlog.so
#2 rclcpp::Context::shutdown(...)         librclcpp.so
#3 rclcpp::Context::~Context()
#4 _Sp_counted_base::_M_release_last_use_cold()
#5 __run_exit_handlers / exit()           libc
```

- **Not mcap/ros_base:** both storage backends crash (sqlite3 too — the passing run
  just got the occasional clean exit); the error message
  (`Could not find converter for format wrong_format`) prints correctly first.
- **ros_core layer, exercised via rosbag2:** the root call is
  `rcl_logging_external_shutdown()` → `spdlog::drop("root")`, which dereferences
  spdlog's global `registry` singleton. On the no-clean-shutdown exit path that call
  runs from the Context destructor **after** the registry singleton's own static
  destructor has already run → use-after-free. **Pre-existing + latent in ros_core**,
  not introduced by ros_base: the ros_core suites (`test_rclcpp`/`test_communication`)
  `init`/`shutdown` cleanly so never hit it; a clean rclpy `init→shutdown→exit` loop
  is 20/20 clean. Both storage backends crash (sqlite3 too); the error message prints
  correctly first. Upstream `rcl_logging` (incl. `rolling`) has the **identical**
  shutdown — the bug only *manifests* on Hummingbird's spdlog 1.17 / gcc 16.
- **What did NOT fix it (ruled out):** (a) linking spdlog **header-only**
  (`spdlog::spdlog_header_only`) — still crashed, so it is not a shared-vs-static
  cross-DSO issue; (b) disabling the `flush_every` periodic thread
  (`RCL_LOGGING_SPDLOG_EXPERIMENTAL_OLD_FLUSHING_BEHAVIOR=1`) — still crashed, so it
  is not the flush worker. The crash is squarely the registry deref in `drop()`.
- **FIX (landed — `hummingbird-rpms` `186f4d40`):** patch `rcl_logging_spdlog.cpp` in
  the spec `%prep` to **never use spdlog's global registry**: drop
  `spdlog::register_logger(g_root_logger)`, replace `spdlog::drop("root")` with
  `g_root_logger->flush()`, and drop the registry-global `flush_every()` (it no longer
  reaches the unregistered logger; `flush_on(err)` + the shutdown flush cover it). The
  root logger lives only in the file-static `g_root_logger`, so shutdown touches no
  registry at any exit order. Also removes the duplicate-`"root"` throw on re-init.
  **Verified aarch64:** missing-converter path now exits `1` cleanly on both mcap +
  sqlite3 (20/20 each); logging to file still works; **`rosbag2_tests` full suite
  184/0/0** (9 cppcheck skips). ⚠️ **x86_64 TODO:** rebuild `rcl_logging_spdlog` with
  the committed spec (the `rpms-x86_64/` copy still has the pre-fix binary).
- **Not run:** the per-library internal unit suites (would rebuild the libs from
  source, not test the RPM binary) — same scoping as the ros_core suites.

### `enable-repos.sh` fix landed here
The gpg-keyring derivation left its `mktemp`/`GNUPGHOME` dirs in `/tmp`, tripping
`bootc container lint` `nonempty-run-tmp` (inherited by every image built on
`ros-core-rpms`). `images/ros-core-rpms/enable-repos.sh` now `rm -rf`s them →
lint 14/0. Generic fix; benefits `ros-core-rpms` too.

## Status

| Step | aarch64 | x86_64 |
|---|---|---|
| closure researched (41 new RPMs) | ✅ 2026-10-15 | ✅ (same specs) |
| specs authored + committed | ✅ `6bbb756a` | ✅ (same specs) |
| RPMs built | ✅ 2026-10-15 (native Lima) | ❌ (build on EC2 c6i, `--arch x86_64`) |
| `ros-base-rpms` image built + verified | ✅ 1.96 GB, lint 14/0, tf2+rsp+rosbag2(mcap) | ❌ |
| `ros-base-rpms-rt` (RT) built | ✅ 2.52 GB (fresh 2026-10-16, fixed spdlog; first build 2026-10-15) | ❌ |
| `ros-base-rpms-rt-chunked` | ✅ 1.73 GB (2026-10-16) | ❌ |
| RT image booted + PREEMPT_RT verified | ✅ 2026-10-16 (qemu TCG, serial login + `uname`) | ❌ |
| test suites on the RT image | ✅ 184/0/0 (2026-10-16) | ❌ |
