# hummingbird-ros2-poc

> **Experimental proof of concept.** These images are for evaluation only and
> are not suitable for production use. They depend on a community (unofficial)
> ROS 2 package source and on the experimental Hummingbird `bootc-os` image.

This project builds ROS 2 base images (`ros-core` and `ros-base`) on top of the
Hummingbird [`bootc-os`](https://gitlab.com/redhat/hummingbird/containers)
image instead of the usual Ubuntu base.

Because the base is a bootable container (bootc) image, each result is *both*:

- a **development container** for ROS 2 (run it, get a ROS 2 environment), and
- a **bootable "robot OS"** — the kernel, systemd and `/sbin/init` are inherited
  from `bootc-os`, so the image can be installed to a machine with ROS 2 baked
  into the immutable OS layer and updated atomically on reboot.

## How this differs from the upstream ROS Dockerfiles

These files are modeled on the auto-generated `osrf/docker_images` ROS 2
Dockerfiles (`ros-core`, `ros-base`), adapted to the Hummingbird / Fedora world.

| Aspect            | Upstream `osrf/docker_images`        | This project                                       |
|-------------------|--------------------------------------|----------------------------------------------------|
| Base image        | `ubuntu:noble`                       | `quay.io/hummingbird-community/bootc-os:latest`     |
| Package manager   | `apt`                                | `dnf`                                               |
| Package source    | `packages.ros.org` (apt)             | `tavie/ros2` COPR (RPM, GPG-verified)              |
| Install prefix    | `/opt/ros/<distro>` (self-contained) | `/usr` (FHS-compliant, immutable image layer)      |
| Setup script      | `/opt/ros/<distro>/setup.bash`       | `/usr/lib64/ros2-<distro>/setup.bash`              |
| Result            | Plain container                      | Bootable bootc image *and* container               |

The `/usr` (FHS) layout is what makes the tavie packages a good fit for bootc:
`/usr` is part of the immutable, image-managed layer and survives atomic
updates, whereas `/opt` on a bootc system is a symlink into writable `/var` and
is not part of the OS image.

## ROS distribution

- **ROS 2 Jazzy** (current LTS), the distro packaged for Fedora 43 in
  [`tavie/ros2`](https://copr.fedorainfracloud.org/coprs/tavie/ros2/).

## Layout

```
images/
  ros-core/
    Dockerfile          # FROM bootc-os; installs ros-<distro>-ros-core
    ros-entrypoint.sh   # sources the ROS env then execs the command
    ros2-profile.sh     # auto-sources the ROS env in interactive login shells
  ros-base/
    Dockerfile          # FROM ros-core; adds ros-<distro>-ros-base
```

## Build

```bash
# Build ros-core
podman build -t hummingbird-ros2-poc/ros-core:latest images/ros-core

# Build ros-base on top of the local ros-core
podman build -t hummingbird-ros2-poc/ros-base:latest images/ros-base

# To build ros-base against a ros-core pulled from a registry instead:
podman build \
  --build-arg BASE_IMAGE=quay.io/my-org/ros-core:latest \
  -t hummingbird-ros2-poc/ros-base:latest images/ros-base
```

## Usage

### As a development container

The ROS 2 environment is sourced automatically for interactive shells:

```bash
podman run --rm -it hummingbird-ros2-poc/ros-base:latest bash
# inside the container:
ros2 topic list
```

For a non-interactive command, use the entrypoint helper (mirrors the upstream
`ros_entrypoint.sh`), which sources the environment before running the command:

```bash
podman run --rm \
  --entrypoint /usr/bin/ros-entrypoint.sh \
  hummingbird-ros2-poc/ros-base:latest \
  ros2 doctor
```

> The images do **not** override `ENTRYPOINT`/`CMD`; they inherit
> `CMD ["/sbin/init"]` from `bootc-os` so they remain bootable. That is why the
> entrypoint must be set explicitly for one-shot container commands.

### As a bootable robot OS

Convert the image to a disk image with
[bootc-image-builder](https://github.com/osbuild/bootc-image-builder), the same
way as the base `bootc-os` image:

```bash
podman run --rm --privileged \
  --volume /var/lib/containers/storage:/var/lib/containers/storage \
  --volume "$(pwd)/output":/output \
  quay.io/centos-bootc/bootc-image-builder:latest \
  --type qcow2 \
  localhost/hummingbird-ros2-poc/ros-base:latest
```

On a booted system the ROS 2 environment is sourced for login shells via
`/etc/profile.d/ros2.sh`. ROS 2 nodes intended to run as system services should
source `/usr/lib64/ros2-jazzy/setup.bash` from their unit (for example via an
`EnvironmentFile` or by sourcing it in `ExecStart`).

## Caveats

- **Community package source.** `tavie/ros2` is an unofficial COPR, provided
  as-is. Pin package versions for anything beyond a POC.
- **Python coupling.** The COPR RPMs are built against the base Fedora's system
  Python. Do not introduce a second `python3` into the image.
- **Experimental base.** `bootc-os` is itself a proof of concept; its package
  set and configuration may change without notice.