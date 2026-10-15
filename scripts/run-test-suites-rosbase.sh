#!/usr/bin/env bash
# Run ROS 2 ros_base test suites (test_tf2 from geometry2, rosbag2_tests) against
# the INSTALLED Hummingbird ros-base RPMs. Mirrors run-test-suites.sh (which
# covers ros_core: test_rclcpp/test_communication). The dedicated test packages
# link/exercise the installed libs, so this tests what we SHIP, not a source
# rebuild of the libs. See docs/ros-base-rpms.md.
#
#   # overlay built on the ros-base image:
#   podman build --build-arg BASE=localhost/hummingbird-ros2-poc/ros-base-rpms:latest \
#     -t ros-base-test-dev -f scripts/base-switch-poc/Containerfile.test-dev scripts/base-switch-poc
#   podman run --rm -v $PWD/ws-rosbase:/ws:z -w /ws ros-base-test-dev \
#     bash /scripts/run-test-suites-rosbase.sh
set -o pipefail   # NOT -u: ROS setup.bash references unbound vars
source /usr/lib64/ros-jazzy/setup.bash
mkdir -p /ws/src && cd /ws

# 1. Clone the jazzy test sources OUTSIDE /ws (so colcon only scans src/).
C=/tmp/clones; mkdir -p "$C"
[ -d "$C/geometry2" ]            || git clone -q -b 0.36.23 https://github.com/ros2/geometry2            "$C/geometry2"
[ -d "$C/rosbag2" ]              || git clone -q -b 0.26.11 https://github.com/ros2/rosbag2              "$C/rosbag2"
[ -d "$C/rcl_interfaces" ]       || git clone -q -b jazzy   https://github.com/ros2/rcl_interfaces       "$C/rcl_interfaces"
[ -d "$C/test_interface_files" ] || git clone -q -b jazzy   https://github.com/ros2/test_interface_files "$C/test_interface_files"
# python_cmake_module is a buildtool NOT installed in the runtime image (same
# class as sensor_msgs_py) — the message-gen (rosidl_generator_py) needs it.
[ -d "$C/python_cmake_module" ]  || git clone -q -b jazzy   https://github.com/ros2/python_cmake_module  "$C/python_cmake_module"

# 2. Stage ONLY the test + test-support packages; everything else comes from the
#    installed RPMs.
rm -rf src/*
cp -rn "$C/geometry2/test_tf2" src/
cp -rn "$C/rosbag2/rosbag2_tests" "$C/rosbag2/rosbag2_test_common" "$C/rosbag2/rosbag2_test_msgdefs" src/
cp -rn "$C/rcl_interfaces/test_msgs" src/
cp -rn "$C/test_interface_files" src/
cp -rn "$C/python_cmake_module" src/

# 3a. Build the cmake/buildtool support FIRST (undeclared transitive dep order).
colcon build --merge-install --packages-select python_cmake_module test_interface_files \
  --cmake-args -DCMAKE_BUILD_TYPE=Release || { echo "BUILDTOOL BUILD FAILED"; exit 1; }
source install/setup.bash
# 3b. Build the remaining test-support packages missing from ros_base.
colcon build --merge-install --packages-select \
  test_msgs rosbag2_test_msgdefs rosbag2_test_common \
  --cmake-args -DCMAKE_BUILD_TYPE=Release || { echo "SUPPORT BUILD FAILED"; exit 1; }
source install/setup.bash

# 4. Build the test suites against the INSTALLED ros_base RPMs.
colcon build --merge-install --packages-select test_tf2 rosbag2_tests \
  --cmake-args -DCMAKE_BUILD_TYPE=Release || { echo "TEST BUILD FAILED"; exit 1; }

# 5. Run them.
export HOME=/tmp; mkdir -p /tmp/.ros/log
colcon test --merge-install --packages-select test_tf2 rosbag2_tests \
  --event-handlers console_direct-
echo "================ TEST RESULT SUMMARY ================"
colcon test-result --all --verbose | tail -40
