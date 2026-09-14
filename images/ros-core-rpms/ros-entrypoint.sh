#!/usr/bin/env bash
# Source the ROS 2 environment, then exec the given command.
#
# Adapted from osrf/docker_images ros_entrypoint.sh. The setup path uses the
# FHS layout under /usr/lib64/ros-<distro> (as produced by the Hummingbird ROS
# RPMs) instead of the Ubuntu /opt/ros/<distro> layout.
set -e

# shellcheck disable=SC1090
source "/usr/lib64/ros-${ROS_DISTRO}/setup.bash"

exec "$@"