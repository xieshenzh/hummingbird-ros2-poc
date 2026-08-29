#!/usr/bin/env bash
# Source the environment that puts the Gazebo tools on PATH, then exec the
# given command (e.g. `gz sim`).
#
# The tavie RPMs ship Gazebo as ROS-namespaced "vendor" packages under the FHS
# prefix /usr/lib64/ros-<distro> (e.g. the `gz` CLI lives at
# /usr/lib64/ros-jazzy/opt/gz_tools_vendor/bin/gz). Sourcing the prefix-level
# setup.bash (from ros-<distro>-ament-package) adds those vendor bin dirs to
# PATH. This image contains NO ROS middleware (no rclcpp / ros-core) — only the
# Gazebo simulator and the setup plumbing needed to launch it.
set -e

# shellcheck disable=SC1090
source "/usr/lib64/ros-${ROS_DISTRO}/setup.bash"

exec "$@"