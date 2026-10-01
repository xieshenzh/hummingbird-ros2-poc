# ROS 2 as Hummingbird-built RPMs (`images/ros-core-rpms`) — ros_core DONE, both arches

> Detail doc for [`../CLAUDE.md`](../CLAUDE.md). This is the **strategic**
> package source (vs. the tavie COPR documented in
> [`established-facts.md`](established-facts.md)).

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
  prefix as tavie. Takes `--build-arg BASE_IMAGE` so ROS 2 can layer onto
  `bootc-os-rt` (see [`realtime-kernel.md`](realtime-kernel.md)).
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
- **fc44 compatibility (verified 2026-10-01):** the existing fc43-built ROS 2
  RPMs install cleanly on the fc44 base (232-pkg closure resolves; python3.14 ABI
  unchanged; spdlog 1.17 from the Hummingbird repo). **No ROS rebuild needed for
  fc44** — only kernel-rt needs the fc44 rebuild. Rebuild ROS only if fc44 breaks
  an ABI: (a) the Python minor version (compiled RPMs target python3.14; 3.15 not
  expected until ~Oct 2026) or (b) a linked C++ soname (`boost` 1.90,
  `tinyxml2`/`console-bridge`/`spdlog-1.17`). Cheap pre-check:
  `dnf install --assumeno ros-jazzy-ros-core` on the fc44 base + confirm
  `python3 --version` and the compiled RPMs' `Requires` sonames.
- **NOT yet done as Hummingbird RPMs:** `ros-base`, `simulation`, `gazebo` (only
  the `ros_core` closure is built); and actually BOOTING the image
  (bootc-image-builder qcow2 + SSH login). These remain COPR-only / pending.
