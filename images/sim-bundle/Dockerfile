# Hummingbird ROS 2 / Gazebo bundle: multi-stage (fedora:43 builder → bootc-os)
#
# WHY THIS EXISTS
# The Gazebo-adjacent stack (ros-jazzy-simulation, gz-sim-vendor, the ros_gz
# bridge) cannot be installed natively onto bootc-os: it needs boost 1.83 (via
# Fedora's ogre 1.9) and a single ruby (the `gz` CLI is ruby), while bootc-os
# ships boost 1.90 (whose boost-filesystem Obsoletes boost-system < 1.90) and
# three colliding ruby streams. Both are hard, irreconcilable dnf conflicts.
#
# This image sidesteps both by installing the stack on STOCK fedora:43 — where
# the tavie RPMs resolve cleanly (boost 1.83, one ruby) — into an isolated root,
# then copying that root into the bootc image and running it under chroot. The
# bundled boost/ruby/ogre live entirely inside the sysroot and never merge with
# the base /usr, so nothing conflicts. The outer image stays a bootable bootc
# image (inherits CMD ["/sbin/init"]).
#
# This is the "for now" bridge to the durable fix (ROS/Gazebo built against
# boost 1.90 in Hummingbird's own repos, or tracked from Fedora rawhide).
#
# Pick the payload with --build-arg VARIANT=<bridge|simulation|gazebo>:
#   bridge      ros_gz message bridge only (no simulator/renderer) — smallest
#   simulation  the osrf `simulation` variant (bridge + ROS sim tooling + gz)
#   gazebo      standalone Gazebo Harmonic (gz-sim + gz CLI, no ROS middleware)
#
# NOTE: x86_64 only (tavie has no aarch64 build). Build with --platform linux/amd64
# on arm64 hosts.

ARG ROS_DISTRO=jazzy
ARG VARIANT=bridge

# ── Builder: stock fedora:43 (tavie RPMs resolve here) ──
FROM registry.fedoraproject.org/fedora:43 AS builder
ARG ROS_DISTRO
ARG VARIANT

# tavie/ros2 COPR (fedora + updates repos and GPG keys already ship in fedora:43).
# baseurl points at the COPR results backend (see ../ros-core/enable-repos.sh for
# why we avoid the frontend generator).
COPY tavie-ros2.repo /etc/yum.repos.d/tavie-ros2.repo

# Resolve VARIANT -> package set and install into an isolated sysroot. ros2cli +
# ros2cli-common-extensions give a fully-featured `ros2` (the extensions provide
# the `pkg`/`run`/`topic`/... sub-commands; bare ros2cli has none); ament-package
# provides setup.bash; bash + coreutils give the chroot entrypoint a shell.
RUN set -eux; \
    case "${VARIANT}" in \
      bridge)     PKGS="ros-${ROS_DISTRO}-ros-gz-bridge ros-${ROS_DISTRO}-ros-gz-interfaces ros-${ROS_DISTRO}-ros-gz-image ros-${ROS_DISTRO}-ros2cli ros-${ROS_DISTRO}-ros2cli-common-extensions";; \
      simulation) PKGS="ros-${ROS_DISTRO}-simulation ros-${ROS_DISTRO}-ros2cli ros-${ROS_DISTRO}-ros2cli-common-extensions";; \
      gazebo)     PKGS="ros-${ROS_DISTRO}-gz-sim-vendor ros-${ROS_DISTRO}-gz-tools-vendor";; \
      *)          PKGS="${VARIANT}";; \
    esac; \
    mkdir -p /sysroot; \
    dnf -y --installroot=/sysroot --releasever=43 \
        --setopt=reposdir=/etc/yum.repos.d \
        install bash coreutils ${PKGS} "ros-${ROS_DISTRO}-ament-package"; \
    dnf -y --installroot=/sysroot clean all; \
    rm -rf /sysroot/var/cache/* /sysroot/var/log/* /sysroot/tmp/*

# ── Runtime: bootc-os (bootable robot OS) ──
FROM quay.io/hummingbird-community/bootc-os:latest
ARG ROS_DISTRO
ENV ROS_DISTRO=${ROS_DISTRO} \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8

# The self-contained stack. /usr is in the immutable image layer (survives bootc
# upgrade); /opt would be a symlink into /var and would NOT be in the image.
COPY --from=builder /sysroot /usr/lib/ros-sysroot

# chroot wrapper that enters the sysroot and sources the ROS/Gazebo env. Needs
# --cap-add=sys_admin at run time to bind-mount /proc,/dev,/sys into the sysroot.
COPY sim-entrypoint.sh /usr/bin/sim-entrypoint.sh
RUN chmod +x /usr/bin/sim-entrypoint.sh

# ENTRYPOINT / CMD intentionally NOT overridden: inherits CMD ["/sbin/init"]
# from bootc-os so the image stays a valid, bootable bootc image. For container
# usage override the entrypoint:
#   podman run --entrypoint /usr/bin/sim-entrypoint.sh <image> ros2 pkg list