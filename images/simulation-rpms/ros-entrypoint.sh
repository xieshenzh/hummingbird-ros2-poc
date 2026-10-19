#!/usr/bin/env bash
# Source the ROS 2 environment, then exec the given command.
#
# Synced copy of images/ros-core-rpms/ros-entrypoint.sh (keep the two in
# sync — same convention as enable-repos.sh). The simulation image installs
# this updated version over the one inherited from its base so that it also
# sources /etc/profile.d/gz.sh (the vendored gz RPMs bake broken default
# plugin paths; the hook exports the real ones — no-op on images without
# the gz vendors).
set -e

# shellcheck disable=SC1090
source "/usr/lib64/ros-${ROS_DISTRO}/setup.bash"

# gz runtime wiring (simulation images only; the file is absent elsewhere)
if [ -f /etc/profile.d/gz.sh ]; then
    # shellcheck disable=SC1091
    . /etc/profile.d/gz.sh
fi

exec "$@"
