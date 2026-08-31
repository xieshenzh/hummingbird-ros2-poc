#!/usr/bin/env bash
#
# integration-rosgz-sim.sh — two-container integration with a REAL running
# Gazebo world (not a `gz topic` stand-in).
#
#   [ gazebo container ]                         [ ros container ]
#     gz sim -s -r <world>  --gz-transport-->  ros_gz parameter_bridge --DDS--> ros2 topic echo
#     (physics running,        (/clock,           (/clock: gz.msgs.Clock            (/clock:
#      publishes /clock)        protobuf)          -> rosgraph_msgs/msg/Clock)       sim time)
#
# Proves that a running simulator's data (here: simulation time on /clock, which
# a stepping server publishes) crosses gz-transport -> bridge -> DDS into ROS 2.
#
# >>> NATIVE x86_64 only (gz-transport aborts under amd64-on-arm64 qemu).
# Usage:  [sudo] ./scripts/integration-rosgz-sim.sh     (sudo if images are in root storage)
# Env:    GZ_IMG / ROS_IMG override tags; KEEP=1 keeps the pod for inspection.

set -uo pipefail

GZ_IMG="${GZ_IMG:-hummingbird-ros2-poc/sim-bundle:gazebo}"
ROS_IMG="${ROS_IMG:-hummingbird-ros2-poc/sim-bundle:bridge}"
POD="rosgz-sim-integration"
PODMAN="${PODMAN:-podman}"
ENTRY="/usr/bin/sim-entrypoint.sh"

cleanup() { [ "${KEEP:-0}" = 1 ] || $PODMAN pod rm -f "$POD" >/dev/null 2>&1; }
trap cleanup EXIT

echo ">>> (re)creating pod $POD"
$PODMAN pod rm -f "$POD" >/dev/null 2>&1
$PODMAN pod create --name "$POD" >/dev/null

# ── Gazebo container: run an actual world with physics stepping (-r) ───────────
# A minimal world (physics + scene broadcaster) is enough — a stepping server
# publishes /clock. The world is written inside the chroot's /tmp.
echo ">>> starting 'gz sim -s -r' (real simulator, physics running)"
$PODMAN run -d --pod "$POD" --name rosgz-sim --cap-add=sys_admin \
  -e GZ_IP=127.0.0.1 \
  --entrypoint "$ENTRY" "$GZ_IMG" \
  bash -c 'cat > /tmp/w.sdf <<SDF
<?xml version="1.0"?>
<sdf version="1.8"><world name="demo">
  <plugin filename="gz-sim-physics-system" name="gz::sim::systems::Physics"/>
  <plugin filename="gz-sim-scene-broadcaster-system" name="gz::sim::systems::SceneBroadcaster"/>
</world></sdf>
SDF
exec gz sim -s -r -v1 /tmp/w.sdf' >/dev/null

sleep 8
echo ">>> topics the running simulator advertises on gz-transport:"
$PODMAN run --rm --pod "$POD" --cap-add=sys_admin -e GZ_IP=127.0.0.1 \
  --entrypoint "$ENTRY" "$GZ_IMG" gz topic -l 2>/dev/null | sed 's/^/    /'

# ── ROS container: bridge /clock (gz -> ROS) and echo simulation time ─────────
echo ">>> bridging /clock (gz.msgs.Clock -> rosgraph_msgs/msg/Clock) and echoing"
set +e
OUT=$($PODMAN run --rm --pod "$POD" --name rosgz-ros --cap-add=sys_admin \
  -e GZ_IP=127.0.0.1 -e ROS_LOCALHOST_ONLY=1 \
  --entrypoint "$ENTRY" "$ROS_IMG" \
  bash -c '
    ros2 run ros_gz_bridge parameter_bridge \
      "/clock@rosgraph_msgs/msg/Clock[gz.msgs.Clock" >/tmp/bridge.log 2>&1 &
    sleep 8
    echo "--- ROS topics ---"; ros2 topic list 2>/dev/null
    echo "--- /clock (once) ---"
    timeout 30 ros2 topic echo --once /clock rosgraph_msgs/msg/Clock 2>/dev/null
    echo "echo_rc=$?"
    echo "--- bridge.log tail ---"; tail -6 /tmp/bridge.log')
set -e

echo "----------------------------------------------------------------"
echo "$OUT"
echo "----------------------------------------------------------------"

# A message on /clock with a non-empty sec/nanosec field == sim time reached ROS.
if echo "$OUT" | grep -qE "sec:|nanosec:"; then
  echo "RESULT: PASS — the running Gazebo simulator's /clock reached ROS 2."
  exit 0
else
  echo "RESULT: FAIL — no /clock message bridged. If the topic list above shows a"
  echo "  different clock topic name (e.g. /world/demo/clock), rerun bridging that."
  exit 1
fi
