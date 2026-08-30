#!/usr/bin/env bash
# Run a command inside the bundled ROS/Gazebo sysroot.
#
# The stack is installed on stock fedora:43 (where the tavie RPMs resolve) into
# an isolated root that is copied into this bootc image at /usr/lib/ros-sysroot.
# It carries its OWN boost 1.83, ruby and ogre, which conflict irreconcilably
# with bootc-os's boost 1.90 / multi-stream ruby if merged into the base /usr.
# We chroot into the sysroot so its paths (/usr/lib64/ros-<distro>, its boost,
# its ruby) all resolve against the bundled tree and never touch the base.
#
# chroot needs CAP_SYS_CHROOT (default) plus CAP_SYS_ADMIN to bind-mount the
# kernel filesystems, so run with --cap-add=sys_admin (a booted bootc host runs
# this as root with full caps, so the mounts just work there):
#   podman run --cap-add=sys_admin --entrypoint /usr/bin/sim-entrypoint.sh \
#     <image> ros2 pkg list
#   podman run --cap-add=sys_admin --entrypoint /usr/bin/sim-entrypoint.sh \
#     <image> gz sim --version
#
# We tried bwrap first (unprivileged user namespaces, no caps) but the
# podman-machine VM blocks nested userns creation (EINVAL); chroot is the
# portable fallback. bwrap would be preferable where nested userns is allowed.
set -e

SYSROOT="${ROS_SYSROOT:-/usr/lib/ros-sysroot}"

# Bind the kernel filesystems into the sysroot. rbind /proc because a fresh proc
# mount is rejected read-only inside the container; rbind /dev and /sys so DDS
# shared memory, /dev/null, GPUs, etc. are visible.
for fs in proc dev sys; do
    mountpoint -q "$SYSROOT/$fs" 2>/dev/null || mount --rbind "/$fs" "$SYSROOT/$fs"
done
# Carry DNS in for networked simulation.
cp -f /etc/resolv.conf "$SYSROOT/etc/resolv.conf" 2>/dev/null || true

# ROS_DISTRO / LANG / LC_ALL are image ENV and are inherited across chroot.
exec chroot "$SYSROOT" /bin/bash -c \
    'source "/usr/lib64/ros-${ROS_DISTRO:-jazzy}/setup.bash"; exec "$@"' bash "$@"