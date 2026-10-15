# `ros-base-rpms` — ROS 2 `ros_base` from Hummingbird-built RPMs

Extends [`../ros-core-rpms`](../ros-core-rpms) up to the REP-2001 `ros_base`
variant, using our OWN `ros-jazzy-*` RPMs (built the Hummingbird way) — not the
tavie COPR. Full research, the package closure, the `urdfdom` gap, the
latest-base compatibility analysis and the build recipe are in
[`../../docs/ros-base-rpms.md`](../../docs/ros-base-rpms.md).

`ros_base = ros_core + rosbag2 + geometry2 + kdl_parser + urdf +
robot_state_publisher`. The delta over `ros_core` is **41 new RPMs** (40
`ros-jazzy-*` + 1 `urdfdom`, which Fedora 44 retired).

**Status: scaffolded, RPMs NOT yet built.** The Dockerfile is thin (install
`ros-jazzy-ros-base` from a local repo of the new RPMs on top of the ros-core
layer); building it requires staging those 41 RPMs into `rpms/` (aarch64) /
`rpms-x86_64/` (x86_64) first.

## Build

```bash
# stage the MATCHING arch into ./rpms/ first (see docs/ros-base-rpms.md)
podman build -t hummingbird-ros2-poc/ros-base-rpms:latest images/ros-base-rpms

# on the PREEMPT_RT ros-core (the real-time robot-OS chain):
podman build \
  --build-arg BASE_IMAGE=localhost/hummingbird-ros2-poc/ros-core-rpms-rt:latest \
  -t hummingbird-ros2-poc/ros-base-rpms-rt:latest images/ros-base-rpms
```
