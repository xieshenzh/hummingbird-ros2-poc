# Hummingbird ROS 2 base image: ros-base (built from Hummingbird RPMs)
#
# Extends ros-core-rpms with the common robotics runtime, mirroring the
# osrf/docker_images `ros-base` variant (REP 2001): the ros_base metapackage =
# ros_core + rosbag2 + geometry2 (tf2) + kdl_parser + urdf + robot_state_publisher.
#
# Same package source as ros-core-rpms: our OWN ros-jazzy-* RPMs built the
# Hummingbird way (mock in a pinned container, official upstream sources) — NOT
# the tavie/ros2 COPR. This image only adds the ~40 new ros_base-closure RPMs
# on top of the ros-core layer; the 162 ros_core RPMs are already installed in
# the BASE_IMAGE.
#
# ── Populating the local RPMs (required before build) ──
# The new ros_base-closure ros-jazzy-* RPMs (plus the urdfdom system RPM) are
# NOT committed to git (see .gitignore). Stage the MATCHING arch into ./rpms/
# first (aarch64 → rpms/, x86_64 → rpms-x86_64/ — the Dockerfile COPYs rpms/).
# See ../../docs/ros-base-rpms.md for the build order and recipe.
#
# ── Base image ──
# Defaults to the plain Hummingbird ros-core image. Override BASE_IMAGE to layer
# ros-base onto the PREEMPT_RT ros-core for a real-time robot OS:
#   podman build \
#     --build-arg BASE_IMAGE=localhost/hummingbird-ros2-poc/ros-core-rpms-rt:latest \
#     -t hummingbird-ros2-poc/ros-base-rpms-rt:latest images/ros-base-rpms
ARG BASE_IMAGE=localhost/hummingbird-ros2-poc/ros-core-rpms:latest
FROM ${BASE_IMAGE}

# ROS_DISTRO, the locale, the Fedora + Hummingbird repos and the entrypoint /
# profile hooks are all inherited from ros-core-rpms, so this layer only adds
# the ros-base closure.

# ── Local repo of the new ros_base-closure RPMs ──
# The ros_base closure also binds system libraries that live in the stock Fedora
# / Hummingbird repos (enabled by ros-core-rpms' enable-repos.sh): orocos-kdl,
# bullet, eigen3-devel's headers, console-bridge, tinyxml2, yaml-cpp, sqlite,
# libzstd, lz4, graphviz, python3-numpy. ONE gap is handled by a local RPM:
# urdfdom was RETIRED in Fedora 44 (only the noarch urdfdom-headers survives),
# so a Hummingbird-built urdfdom (ros-jazzy-urdfdom or a plain urdfdom rebuild)
# is staged into rpms/ alongside the ros-jazzy-* packages.
COPY rpms/ /var/tmp/ros-base-rpms/
RUN dnf -y install --setopt=install_weak_deps=0 createrepo_c \
    && createrepo_c /var/tmp/ros-base-rpms \
    && printf '[ros-base-local]\nname=Hummingbird ROS 2 Jazzy ros-base (local)\nbaseurl=file:///var/tmp/ros-base-rpms\nenabled=1\ngpgcheck=0\n' \
         > /etc/yum.repos.d/ros-base-local.repo \
    && dnf -y install "ros-${ROS_DISTRO}-ros-base" \
    && dnf -y remove createrepo_c \
    && rm -rf /var/tmp/ros-base-rpms /etc/yum.repos.d/ros-base-local.repo \
    && dnf clean all \
    && rm -rf /var/cache/* /var/log/dnf* /var/log/hawkey.log /run/dnf /var/lib/dnf/repos

# ENTRYPOINT / CMD are intentionally NOT overridden — the image inherits
# CMD ["/sbin/init"] from bootc-os (through ros-core-rpms) so it stays a valid,
# bootable bootc image, and the /etc/profile.d + /usr/bin/ros-entrypoint.sh
# hooks are inherited from ros-core-rpms.
