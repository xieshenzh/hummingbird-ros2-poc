#!/usr/bin/env bash
#
# integration-ros2gz.sh — REVERSE-direction integration: ROS 2 -> Gazebo.
#
#   [ ros container ]                                  [ gazebo container ]
#     ros2 topic pub  --DDS-->  parameter_bridge  --gz-transport-->  gz topic -e
#     (std_msgs/String)          (ROS IDL -> proto,                   (gz.msgs.StringMsg
#                                 '] ' = ROS->gz)                      subscriber prints it)
#
# Complements integration-rosgz{,-sim}.sh (which prove gz -> ROS). This is the
# path a robot's commands take, e.g. ROS /cmd_vel -> bridge -> Gazebo actuates.
#
# >>> NATIVE x86_64 only (gz-transport aborts under amd64-on-arm64 qemu).
# Usage:  [sudo] ./scripts/integration-ros2gz.sh
# Env:    GZ_IMG / ROS_IMG override tags; KEEP=1 keeps the pod.

set -uo pipefail

GZ_IMG="${GZ_IMG:-hummingbird-ros2-poc/sim-bundle:gazebo}"    # gz-transport subscriber side
ROS_IMG="${ROS_IMG:-hummingbird-ros2-poc/sim-bundle:bridge}"  # ROS publisher + bridge side
POD="ros2gz-integration"
TOPIC="/from_ros"
PAYLOAD="hello_gazebo_from_ros2"
PODMAN="${PODMAN:-podman}"
ENTRY="/usr/bin/sim-entrypoint.sh"

cleanup() { [ "${KEEP:-0}" = 1 ] || $PODMAN pod rm -f "$POD" >/dev/null 2>&1; }
trap cleanup EXIT

echo ">>> (re)creating pod $POD"
$PODMAN pod rm -f "$POD" >/dev/null 2>&1
$PODMAN pod create --name "$POD" >/dev/null

# ── Gazebo container: gz-transport subscriber that prints what it receives ────
echo ">>> starting gz-transport subscriber (gz topic -e -t $TOPIC)"
$PODMAN run -d --pod "$POD" --name ros2gz-sub --cap-add=sys_admin \
  -e GZ_IP=127.0.0.1 \
  --entrypoint "$ENTRY" "$GZ_IMG" \
  bash -c "exec gz topic -e -t $TOPIC" >/dev/null
sleep 5

# ── ROS container: bridge ROS->gz ('] ') then publish on the ROS topic ────────
echo ">>> bridging ($TOPIC ROS->gz) and publishing from ROS 2"
set +e
$PODMAN run --rm --pod "$POD" --name ros2gz-pub --cap-add=sys_admin \
  -e GZ_IP=127.0.0.1 -e ROS_LOCALHOST_ONLY=1 \
  --entrypoint "$ENTRY" "$ROS_IMG" \
  bash -c "
    ros2 run ros_gz_bridge parameter_bridge \
      '$TOPIC@std_msgs/msg/String]gz.msgs.StringMsg' >/tmp/bridge.log 2>&1 &
    sleep 8
    timeout 10 ros2 topic pub -r 5 $TOPIC std_msgs/msg/String '{data: $PAYLOAD}' >/dev/null 2>&1
    echo '--- bridge.log tail ---'; tail -4 /tmp/bridge.log"
set -e

sleep 1
echo "----------------------------------------------------------------"
echo ">>> what the Gazebo-side gz-transport subscriber received:"
GZOUT=$($PODMAN logs ros2gz-sub 2>&1)
echo "$GZOUT" | sed 's/^/    /'
echo "----------------------------------------------------------------"

if echo "$GZOUT" | grep -q "$PAYLOAD"; then
  echo "RESULT: PASS — a ROS 2 message reached the Gazebo (gz-transport) side."
  exit 0
else
  echo "RESULT: FAIL — the gz subscriber never received the ROS message."
  exit 1
fi