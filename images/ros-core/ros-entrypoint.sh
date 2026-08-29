#!/usr/bin/env bash
# Source the ROS 2 environment, then exec the given command.
#
# Adapted from osrf/docker_images ros_entrypoint.sh. The only difference is the
# setup path: tavie/ros2 RPMs use the FHS layout under /usr/lib64/ros-<distro>
# instead of the Ubuntu /opt/ros/<distro> layout.
set -e

# shellcheck disable=SC1090
source "/usr/lib64/ros-${ROS_DISTRO}/setup.bash"

exec "$@"