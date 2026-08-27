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
  - Supports Fedora 43, ROS 2 **Jazzy**.
  - Fedora **FHS layout**: installs under `/usr`, NOT `/opt/ros`.
  - Package names (f42+) match the Ubuntu deb names: `ros-jazzy-ros-core`,
    `ros-jazzy-ros-base`, `ros-jazzy-ament-package` (needed for setup scripts).
  - Setup scripts live at **`/usr/lib64/ros2-jazzy/setup.bash`** (and `.sh`).
  - RPMs are built against the base Fedora's **system Python** — do not add a
    second `python3`.
  - Repo file: `https://copr.fedorainfracloud.org/coprs/tavie/ros2/repo/fedora-$(rpm -E %fedora)/tavie-ros2-fedora-$(rpm -E %fedora).repo`
    (brings the COPR signing key + `gpgcheck=1`).

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
images/ros-core/Dockerfile        FROM bootc-os; adds tavie repo; installs ros-core + ament-package
images/ros-core/ros-entrypoint.sh sources /usr/lib64/ros2-$ROS_DISTRO/setup.bash then exec "$@"
images/ros-core/ros2-profile.sh   /etc/profile.d hook, auto-source for interactive bash login shells
images/ros-base/Dockerfile        FROM ros-core (ARG BASE_IMAGE); adds ros-base
```

## Build

```bash
podman build -t hummingbird-ros2-poc/ros-core:latest images/ros-core
podman build -t hummingbird-ros2-poc/ros-base:latest images/ros-base
```

## Test plan (this is what to run/verify here)

1. **Build succeeds.** Watch for the tavie repo fetch — if `copr.fedorainfracloud.org`
   blocks the `curl` (bot protection), swap that line for `dnf -y copr enable tavie/ros2`
   (may require `dnf5-plugins`). This is the single most likely failure point.
2. **Packages resolve.** Confirm `ros-jazzy-ros-core` / `ros-jazzy-ros-base`
   exist for `fedora-43` in the COPR and that dnf can satisfy deps against the
   bootc-os package set (Fedora 43 + Hummingbird repos).
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

- Does `ros-jazzy-ros-base` (and its dep closure) actually build/resolve on
  fedora-43 in tavie? Verify in the COPR before trusting the ros-base layer.
- Python version coupling: bootc-os system python must match what the COPR RPMs
  were built against (Fedora 43 system python3).
- Image size: ros-base pulls a large dep tree onto an already-full OS image —
  measure it; it may motivate a slimmer, non-bootc variant later.

## Provenance

Design conversation ran in `../containers` (the Hummingbird containers repo).
Reference upstream: `osrf/docker_images` (generated Dockerfiles) and
`osrf/docker_templates` (the `.em` empy templates). ROS 2 base metapackages are
defined in `ros2/variants` (`ros_core`, `ros_base` `package.xml`) and turned
into packages via bloom — the Dockerfiles only reference the metapackage name.
