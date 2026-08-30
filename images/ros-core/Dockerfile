# Hummingbird ROS 2 base image: ros-core
#
# This mirrors the osrf/docker_images `ros-core` image
# (generated from docker_images_ros2/create_ros_core_image.Dockerfile.em),
# but adapted to the Hummingbird model:
#
#   Reference (osrf)              This image
#   ---------------------------   ------------------------------------------
#   FROM ubuntu:noble             FROM quay.io/hummingbird-community/bootc-os
#   apt + packages.ros.org        dnf + tavie/ros2 COPR (FHS RPMs)
#   installs under /opt/ros       installs under /usr (FHS, immutable layer)
#   source /opt/ros/.../setup     source /usr/lib64/ros-jazzy/setup.bash
#
# Because the base is bootc-os, the result is itself a bootable container
# image: it inherits the kernel, systemd and `/sbin/init` from bootc-os, so it
# can be deployed to a machine as a "robot OS" with ROS 2 baked in, or run as a
# plain container for development.

FROM quay.io/hummingbird-community/bootc-os:latest

# ROS distribution shipped in this image. Jazzy is the current LTS and the
# distro packaged for Fedora 43 in the tavie/ros2 COPR.
ENV ROS_DISTRO=jazzy \
    ROS_VERSION=2 \
    ROS_PYTHON_VERSION=3

# ROS 2 requires a UTF-8 locale at runtime (matches the reference image, which
# sets LANG/LC_ALL to C.UTF-8).
ENV LANG=C.UTF-8 \
    LC_ALL=C.UTF-8

# ── Set up the ROS 2 package sources ──
# enable-repos.sh adds the stock Fedora repos that bootc-os omits (the tavie
# ROS RPMs need ordinary Fedora libraries) and drops the tavie/ros2 COPR repo
# with its baseurl pinned to the real Fedora release (bootc-os overrides dnf's
# $releasever to a snapshot id, which otherwise 404s the COPR). See the script
# header for the full rationale. This replaces the reference image's "add apt
# key + write sources.list" step.
COPY enable-repos.sh /tmp/enable-repos.sh
RUN bash /tmp/enable-repos.sh && rm -f /tmp/enable-repos.sh

# ── Install ros-core ──
# ros-core is the minimal ROS 2 metapackage: the client libraries (rclcpp,
# rclpy), the DDS middleware layer, ros2cli, and the common interface packages.
# ament-package ships the environment setup scripts that must be sourced.
RUN dnf -y install \
      "ros-${ROS_DISTRO}-ros-core" \
      "ros-${ROS_DISTRO}-ament-package" \
    && dnf clean all \
    && rm -rf /var/cache/* /var/log/dnf* /var/log/hawkey.log

# ── Environment setup ──
# tavie packages install their setup scripts under /usr/lib64/ros-${ROS_DISTRO}
# (not /opt/ros as in the Ubuntu reference). Auto-source them for interactive
# login shells, e.g. `podman run -it ... bash` or an SSH session on a booted
# robot OS.
COPY ros2-profile.sh /etc/profile.d/ros2.sh

# ros-entrypoint.sh sources the ROS environment then execs the given command.
# It mirrors the reference image's ros_entrypoint.sh and is used when running
# this image as a plain application container:
#   podman run --entrypoint /usr/bin/ros-entrypoint.sh <image> ros2 topic list
COPY ros-entrypoint.sh /usr/bin/ros-entrypoint.sh
RUN chmod +x /usr/bin/ros-entrypoint.sh

# ENTRYPOINT / CMD are intentionally NOT overridden. The image inherits
# CMD ["/sbin/init"] from bootc-os so it stays a valid, bootable bootc image.
# For container-style usage, override the entrypoint (see above) or run bash.
