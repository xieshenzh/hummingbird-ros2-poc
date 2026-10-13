#!/usr/bin/env bash
# Run ROS 2 system test suites (test_rclcpp, test_communication) against the
# INSTALLED Hummingbird ROS RPMs on a fedora-bootc:44 base. Run inside the
# ros-test-dev container with a persistent /ws workspace. See docs/base-switch-poc.md.
#
#   podman run --rm -v $PWD/ws:/ws:z -w /ws ros-test-dev bash run-test-suites.sh
set -uo pipefail
source /usr/lib64/ros-jazzy/setup.bash
mkdir -p /ws/src && cd /ws

# 1. Import only the repos we need (jazzy branch) from the ROS 2 manifest.
[ -f ros2.repos ] || curl -fsSL https://raw.githubusercontent.com/ros2/ros2/jazzy/ros2.repos -o ros2.repos
{ echo "repositories:"; for k in ros2/rcl_interfaces ros2/mimick_vendor ros2/performance_test_fixture \
    osrf/osrf_testing_tools_cpp ros2/test_interface_files ros2/system_tests; do
    grep -A3 "^  ${k}:$" ros2.repos; done; } > need.repos
vcs import src < need.repos
git clone -q -b jazzy https://github.com/ros2/python_cmake_module src/python_cmake_module 2>/dev/null || true
git clone -q -b jazzy https://github.com/ament/ament_cmake.git /tmp/ac 2>/dev/null || true
cp -rn /tmp/ac/ament_cmake_vendor_package src/ 2>/dev/null || true
cp -rn /tmp/ac/ament_cmake_google_benchmark src/ 2>/dev/null || true
cp -rn src/ros2/rcl_interfaces/test_msgs src/ 2>/dev/null || true
rm -rf src/ros2/rcl_interfaces   # keep only test_msgs; rest comes from installed RPMs

# 2. Build cmake-support pkgs FIRST (undeclared transitive deps -> ordering race).
colcon build --merge-install --packages-select python_cmake_module ament_cmake_vendor_package ament_cmake_google_benchmark
# 3. Build the remaining test-support deps missing from ros_core.
colcon build --merge-install --packages-select test_interface_files mimick_vendor \
  osrf_testing_tools_cpp performance_test_fixture test_msgs --cmake-args -DCMAKE_BUILD_TYPE=Release
# 4. Build + run the system test suites against the INSTALLED RPMs.
source install/setup.bash
colcon build --merge-install --packages-select test_rclcpp test_communication --cmake-args -DCMAKE_BUILD_TYPE=Release
export HOME=/tmp; mkdir -p /tmp/.ros/log
colcon test --merge-install --packages-select test_rclcpp test_communication --event-handlers console_direct-
colcon test-result --all | tail -30
