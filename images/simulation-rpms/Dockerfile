# Hummingbird ROS 2 simulation image: the `simulation` variant (REP 2001)
#
# Extends ros-base-rpms with the Gazebo-Harmonic-based simulation stack:
#   simulation = ros_base + ros_gz_bridge + ros_gz_sim + ros_gz_image
#              + ros_gz_interfaces
#
# Package source (all OUR Hummingbird-built RPMs, no COPR):
#   * Tier B: image_transport, the 5 extra msg packages ros_gz 1.0.25 needs
#     (actuator/gps/marine-acoustic/vision/simulation-interfaces),
#     ros_gz_{interfaces,bridge,image,sim}, the simulation metapackage.
#   * Tier A: the 17 gz_*_vendor RPMs (Gazebo Harmonic 8.15.0 built from
#     source via the offline-vendor recipe) — including gz_sim_vendor and
#     the av-enabled gz_common_vendor rebuild.
#   * Enablers: the icu78 Qt5 QML + no-smb gdal/ffmpeg `.hum1` rebuilds
#     (must be staged so dnf prefers them over Fedora's icu77-linked ones —
#     `1.hum1` > `1.fc44` in RPM EVR).
#
# Physics note: DART is deferred (fcl missing in Fedora 44) — gz-physics
# ships bullet + TPE. Run sims with:
#   gz sim --physics-engine gz-physics-bullet-plugin ...
#
# ── Populating the local RPMs (required before build) ──
# Stage the sim closure from the build VM (aarch64) into ./rpms/ — from the
# repo root (ALL non-debug RPMs of ~/ros-local-rpms; the ros_core/ros_base
# RPMs already in the base are harmless restage, and the closure's uninstalled
# deps e.g. sensor_msgs_py resolve from it):
#   limactl shell fedora -- bash -lc \
#     'cd ~/ros-local-rpms && ls *.rpm | grep -vE "debuginfo|debugsource" \
#        | tar cf - -T -' | tar xf - -C images/simulation-rpms/rpms
# then build natively (aarch64):
#   podman build -t hummingbird-ros2-poc/simulation-rpms:latest images/simulation-rpms
# or on the RT ros-base for the full RT robot-OS chain:
#   podman build \
#     --build-arg BASE_IMAGE=localhost/hummingbird-ros2-poc/ros-base-rpms-rt:latest \
#     -t hummingbird-ros2-poc/simulation-rpms-rt:latest images/simulation-rpms
ARG BASE_IMAGE=localhost/hummingbird-ros2-poc/ros-base-rpms:latest
FROM ${BASE_IMAGE}

# ROS_DISTRO, locale, Fedora + Hummingbird repos and the entrypoint / profile
# hooks are all inherited from ros-core-rpms via ros-base-rpms, so this layer
# only adds the simulation closure.

# ── Local repo of the simulation-closure RPMs ──
COPY rpms/ /var/tmp/ros-sim-rpms/
# rubygem4.0-psych + rubygem4.0-fiddle: the gz Ruby CLI (gz-tools) requires
# 'yaml'/psych and 'fiddle', neither of which is a Ruby 4.0 default gem (and
# the Hummingbird repo lacks fiddle — built as an enabler in this repo) —
# and install_weak_deps=0 (needed: weak deps would pull the conflicting
# ruby3.3/3.4 parallel streams) drops ruby's Recommends that bring psych.
RUN dnf -y install --setopt=install_weak_deps=0 createrepo_c \
    && createrepo_c /var/tmp/ros-sim-rpms \
    && printf '[ros-sim-local]\nname=Hummingbird ROS 2 Jazzy simulation (local)\nbaseurl=file:///var/tmp/ros-sim-rpms\nenabled=1\ngpgcheck=0\n' \
         > /etc/yum.repos.d/ros-sim-local.repo \
    && dnf -y install --setopt=install_weak_deps=0 "ros-${ROS_DISTRO}-simulation" \
         rubygem4.0-psych rubygem4.0-fiddle \
    && dnf -y remove createrepo_c \
    && rm -rf /var/tmp/ros-sim-rpms /etc/yum.repos.d/ros-sim-local.repo \
    && dnf clean all \
    && rm -rf /var/cache/* /var/log/dnf* /var/log/hawkey.log /run/dnf /var/lib/dnf/repos

# ENTRYPOINT / CMD are intentionally NOT overridden — the image inherits
# CMD ["/sbin/init"] from bootc-os (through ros-core-rpms) so it stays a
# valid, bootable bootc image, and the /etc/profile.d + /usr/bin/ros-entrypoint.sh
# hooks are inherited from ros-core-rpms.
