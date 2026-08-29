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
  - Repo file: `https://copr.fedorainfracloud.org/coprs/tavie/ros2/repo/fedora-$(rpm -E %fedora)/tavie-ros2-fedora-$(rpm -E %fedora).repo`
    (brings the COPR signing key + `gpgcheck=1`).

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
```

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
podman build -t hummingbird-ros2-poc/simulation:latest images/simulation
podman build -t hummingbird-ros2-poc/gazebo:latest     images/gazebo
```

## Test plan (this is what to run/verify here)

1. **Build succeeds.** The repo/dep issues that used to block this are handled
   by `enable-repos.sh` (Fedora repos + release-pinned COPR). If the tavie repo
   fetch is ever blocked (COPR bot protection), swap it for
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
   or `ros2 topic pub` + `ros2 topic echo`.
6. **(Stretch) bootability:** convert ros-base to a qcow2 with
   `quay.io/centos-bootc/bootc-image-builder` and boot it; confirm ROS sources
   in an SSH login shell.

## Open questions / risks

- **Dep resolution CONFIRMED** for ros-core/ros-base/simulation/gazebo on
  fedora-43 x86_64 (dry-run). Still need a full `podman build` + runtime smoke
  test (the dry-run doesn't download/GPG-verify or run anything).
- **Image size:** simulation resolves to 1068 pkgs and gazebo to 798 — both huge
  on top of an already-full OS image. Measure built size; this likely motivates
  a slimmer non-bootc variant, or keeping gazebo/simulation off the bootable
  images.
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
