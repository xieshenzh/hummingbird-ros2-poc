# Hummingbird ROS 2 image: simulation
#
# The official osrf/docker_images `simulation` variant: `FROM ros-base` plus the
# ros-<distro>-simulation metapackage. It adds the ROS-side simulation stack,
# including the ros_gz integration (the ROS 2 <-> Gazebo bridge: ros-gz-bridge,
# ros-gz-sim, ros-gz-interfaces, ros-gz-image).
#
# It is a ROS image, not a Gazebo image. Because ros_gz_sim links the Gazebo
# libraries, this variant also pulls the Gazebo (gz-*-vendor) client/runtime
# libs. The standalone simulator lives in the separate `gazebo` image
# (../gazebo, no ROS middleware); run them together (same pod / shared network)
# to co-simulate, with the bridge here relaying between ROS 2 and Gazebo.
#
# ROS_DISTRO, the locale, the package sources (Fedora + tavie repos) and the
# setup scripts are all inherited from ros-core via ros-base.
#
# NOTE: x86_64 only (the tavie/ros2 COPR has no aarch64 build for fedora-43).

ARG BASE_IMAGE=localhost/hummingbird-ros2-poc/ros-base:latest
FROM ${BASE_IMAGE}

# ── Install the simulation variant ──
# ros-<distro>-simulation is the osrf variant metapackage; it pulls the ros_gz
# bridge and the rest of the ROS simulation tooling. Verified to resolve on
# fedora-43 (dry-run: ~1068 packages, includes ros-gz-*).
RUN dnf -y install \
      "ros-${ROS_DISTRO}-simulation" \
    && dnf clean all \
    && rm -rf /var/cache/* /var/log/dnf* /var/log/hawkey.log