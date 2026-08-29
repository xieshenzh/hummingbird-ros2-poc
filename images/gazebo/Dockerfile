# Hummingbird image: gazebo (standalone Gazebo Harmonic simulator)
#
# A self-contained Gazebo Harmonic simulator built directly on bootc-os, with
# NO ROS 2 middleware (no rclcpp / ros-core). It is deliberately a separate
# image from the ROS 2 stack: the simulator's large dependency tree stays out
# of the ROS images, and this image can be deployed / booted on its own as a
# simulation host, or run as a plain container. The ROS side connects to it via
# the separate `simulation` image (../simulation, which carries the ros_gz
# bridge) at runtime.
#
# Because the base is bootc-os, the result is itself a bootable container image
# (it inherits the kernel, systemd and CMD ["/sbin/init"] from bootc-os).
#
# Gazebo packaging note: on Fedora there is no standalone `gazebo` / `gz-sim`
# package. The only packaged Gazebo Harmonic comes from the tavie/ros2 COPR as
# ROS-namespaced "vendor" RPMs (ros-<distro>-gz-*-vendor), installed under the
# FHS prefix /usr/lib64/ros-<distro>. This image installs those vendor packages
# only (plus ament-package for the setup scripts) — not the ROS client libs.
#
# NOTE: x86_64 only (the tavie/ros2 COPR has no aarch64 build for fedora-43).

FROM quay.io/hummingbird-community/bootc-os:latest

# Gazebo Harmonic is the version paired with ROS 2 Jazzy; ROS_DISTRO selects the
# tavie package namespace and the /usr/lib64/ros-<distro> setup prefix.
ENV ROS_DISTRO=jazzy \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8

# ── Set up the package sources ──
# Same setup as the ROS images: add the stock Fedora repos bootc-os omits and
# drop the tavie/ros2 COPR repo with a release-pinned baseurl. See the script
# header for the full rationale.
COPY enable-repos.sh /tmp/enable-repos.sh
RUN bash /tmp/enable-repos.sh && rm -f /tmp/enable-repos.sh

# ── Install Gazebo Harmonic (vendored, no ROS middleware) ──
# gz-sim-vendor is the simulator; gz-tools-vendor provides the `gz` CLI;
# ament-package ships the prefix-level setup.bash that puts the vendored gz
# binaries on PATH. This pulls the Gazebo/rendering dep tree but NOT rclcpp.
RUN dnf -y install \
      "ros-${ROS_DISTRO}-gz-sim-vendor" \
      "ros-${ROS_DISTRO}-gz-tools-vendor" \
      "ros-${ROS_DISTRO}-ament-package" \
    && dnf clean all \
    && rm -rf /var/cache/* /var/log/dnf* /var/log/hawkey.log

# ── Environment setup ──
# Auto-source for interactive login shells (podman run -it ... bash, or SSH on a
# booted sim host); gz-entrypoint.sh sources then execs for container usage:
#   podman run --entrypoint /usr/bin/gz-entrypoint.sh <image> gz sim --version
COPY gz-profile.sh /etc/profile.d/gz.sh
COPY gz-entrypoint.sh /usr/bin/gz-entrypoint.sh
RUN chmod +x /usr/bin/gz-entrypoint.sh

# ENTRYPOINT / CMD intentionally NOT overridden: the image inherits
# CMD ["/sbin/init"] from bootc-os so it stays a valid, bootable bootc image.