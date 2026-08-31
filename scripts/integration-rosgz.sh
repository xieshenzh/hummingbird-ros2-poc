#!/usr/bin/env bash
#
# integration-rosgz.sh — two-container ROS 2 <-> Gazebo integration test.
#
# Proves the full cross-container path end to end:
#   [ gazebo container ]  gz-transport  -->  [ ros container ]
#     gz topic publisher    (ZeroMQ/UDP)       ros_gz parameter_bridge --> DDS --> ros2 topic echo
#
# The two containers share ONE network namespace (a podman pod), so gz-transport
# multicast discovery and ROS 2 DDS discovery both happen over the pod's loopback.
# This mirrors the intended deployment ("run them together in the same pod /
# shared network — the bridge relays between ROS 2 and the Gazebo simulator").
#
# >>> MUST run on a NATIVE x86_64 host (EC2). It does NOT work under amd64-on-arm64
#     qemu emulation: gz-transport aborts (multicast socket setup fails under
#     qemu-user). See CLAUDE.md "gz-transport under qemu".
#
# Usage:  ./scripts/integration-rosgz.sh
# Env:    GZ_IMG / ROS_IMG to override image tags; KEEP=1 to skip cleanup.

set -uo pipefail

GZ_IMG="${GZ_IMG:-hummingbird-ros2-poc/sim-bundle:gazebo}"       # simulator side
ROS_IMG="${ROS_IMG:-hummingbird-ros2-poc/sim-bundle:bridge}"     # bridge + ros2 side
POD="rosgz-integration"
TOPIC="/chatter"
PAYLOAD="from_gazebo"
PODMAN="${PODMAN:-podman}"
ENTRY="/usr/bin/sim-entrypoint.sh"

cleanup() { [ "${KEEP:-0}" = 1 ] || $PODMAN pod rm -f "$POD" >/dev/null 2>&1; }
trap cleanup EXIT

echo ">>> (re)creating pod $POD (shared net namespace = shared localhost)"
$PODMAN pod rm -f "$POD" >/dev/null 2>&1
$PODMAN pod create --name "$POD" >/dev/null

# ── Gazebo container: continuous gz-transport publisher on $TOPIC ─────────────
# Stands in for a running simulator emitting messages on the Gazebo side. Uses a
# loop because `gz topic -p` sends one message per call. GZ_IP=127.0.0.1 keeps
# discovery on loopback within the pod.
echo ">>> starting gazebo publisher container"
$PODMAN run -d --pod "$POD" --name rosgz-sim --cap-add=sys_admin \
  -e GZ_IP=127.0.0.1 \
  --entrypoint "$ENTRY" "$GZ_IMG" \
  bash -c "for i in \$(seq 1 120); do
             gz topic -t $TOPIC -m gz.msgs.StringMsg -p 'data:\"$PAYLOAD\"' >/dev/null 2>&1
             sleep 0.5
           done" >/dev/null

# ── ROS container: bridge $TOPIC (gz -> ROS) then echo it ─────────────────────
# parameter_bridge mapping "TOPIC@<ros_type>[<gz_type>" : the '[' means gz->ROS.
# ROS_LOCALHOST_ONLY=1 makes DDS discover over loopback (bridge + echo are in the
# same container / pod). Prints the first message received on the ROS side.
echo ">>> starting bridge + ros2 echo (waits up to ~40s for a message)"
set +e
OUT=$($PODMAN run --rm --pod "$POD" --name rosgz-ros --cap-add=sys_admin \
  -e GZ_IP=127.0.0.1 -e ROS_LOCALHOST_ONLY=1 \
  --entrypoint "$ENTRY" "$ROS_IMG" \
  bash -c "
    ros2 run ros_gz_bridge parameter_bridge \
      '$TOPIC@std_msgs/msg/String[gz.msgs.StringMsg' >/tmp/bridge.log 2>&1 &
    sleep 8
    timeout 40 ros2 topic echo --once $TOPIC std_msgs/msg/String 2>/dev/null
    echo \"echo_rc=\$?\"
    echo '--- bridge.log tail ---'; tail -5 /tmp/bridge.log")
rc=$?
set -e

echo "----------------------------------------------------------------"
echo "$OUT"
echo "----------------------------------------------------------------"

if echo "$OUT" | grep -q "$PAYLOAD"; then
  echo "RESULT: PASS — ROS 2 received a message that originated in the Gazebo container."
  exit 0
else
  echo "RESULT: FAIL — no bridged message received."
  echo "  If you see 'Aborted (core dumped)' / qemu signal 6, you are running under"
  echo "  emulation; run this on a native x86_64 host. Otherwise check /tmp/bridge.log,"
  echo "  confirm the pod's lo is up, and that both images share the pod (podman pod ps)."
  exit 1
fi
