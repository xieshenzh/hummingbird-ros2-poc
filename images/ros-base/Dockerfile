# Hummingbird ROS 2 base image: ros-base
#
# Mirrors the osrf/docker_images `ros-base` image
# (generated from docker_images_ros2/create_ros_image.Dockerfile.em with
# base_image=ros-core). It extends ros-core with the common robotics runtime:
# tf2 / geometry2, urdf, kdl_parser, robot_state_publisher and rosbag2.
#
# BASE_IMAGE points at the ros-core image built from ../ros-core/Dockerfile.
# Override it to pull ros-core from a registry instead of the local build.

ARG BASE_IMAGE=localhost/hummingbird-ros2-poc/ros-core:latest
FROM ${BASE_IMAGE}

# ── Install ros-base ──
# ROS_DISTRO, the locale, the tavie/ros2 repo and the setup scripts are all
# inherited from ros-core, so this layer only adds the ros-base metapackage.
RUN dnf -y install \
      "ros-${ROS_DISTRO}-ros-base" \
    && dnf clean all \
    && rm -rf /var/cache/* /var/log/dnf* /var/log/hawkey.log