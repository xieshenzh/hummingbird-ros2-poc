# Auto-source the Gazebo environment for interactive bash login shells.
#
# Installed to /etc/profile.d/gz.sh. The BASH_VERSION guard avoids sourcing the
# bash-specific setup script from a plain POSIX sh login shell. ROS_DISTRO is
# set as an image ENV; the default keeps this working on a booted bootc system
# where the container ENV is not applied to system login shells. Sourcing puts
# the vendored `gz` CLI (under /usr/lib64/ros-<distro>) on PATH.
if [ -n "${BASH_VERSION:-}" ] && [ -f "/usr/lib64/ros-${ROS_DISTRO:-jazzy}/setup.bash" ]; then
    . "/usr/lib64/ros-${ROS_DISTRO:-jazzy}/setup.bash"
fi