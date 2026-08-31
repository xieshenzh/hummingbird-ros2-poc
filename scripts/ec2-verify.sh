#!/usr/bin/env bash
#
# ec2-verify.sh — authoritative NATIVE x86_64 build + test of the Hummingbird
# ROS 2 / Gazebo POC images. Run this on a fresh x86_64 Linux EC2 instance
# (Fedora 43, Amazon Linux 2023, or Ubuntu — anything with podman + network).
#
# It builds all buildable images natively (NO qemu, so no --platform) and runs
# the full test suite, INCLUDING the checks that cannot run under amd64-on-arm64
# emulation on the dev laptop:
#   - default Fast DDS pub/sub (shared-memory transport fails under qemu)
#   - headless `gz sim -s` physics stepping (aborts under qemu)
#
# GUI (`gz sim -g`) is intentionally NOT covered here — it needs a display and
# ideally a GPU (g4dn/g5 instance + X/Wayland). See CLAUDE.md "Interactive GUI".
#
# Usage:
#   sudo dnf -y install podman git    # or apt/yum equivalent
#   git clone <this repo> && cd hummingbird-ros2-poc
#   ./scripts/ec2-verify.sh
#
# Exit non-zero if any build or hard check fails. DDS/sim runtime checks are
# reported but treated as soft (network/instance-dependent) unless STRICT=1.

set -uo pipefail
cd "$(dirname "$0")/.."

STRICT="${STRICT:-0}"
PODMAN="${PODMAN:-podman}"
PREFIX="hummingbird-ros2-poc"
fail=0
soft_fail=0

hr()   { printf '\n============ %s ============\n' "$*"; }
pass() { printf '  [PASS] %s\n' "$*"; }
bad()  { printf '  [FAIL] %s\n' "$*"; fail=1; }
soft() { printf '  [WARN] %s\n' "$*"; soft_fail=1; [ "$STRICT" = 1 ] && fail=1; return 0; }

# ── Build (native; no --platform) ────────────────────────────────────────────
hr "BUILD"
build() { # <tag> <context> [--build-arg ...]
  local tag="$1"; shift; local ctx="$1"; shift
  echo ">>> building $PREFIX/$tag"
  if $PODMAN build -t "$PREFIX/$tag" "$@" "$ctx"; then pass "build $tag"
  else bad "build $tag"; fi
}
build ros-core:latest        images/ros-core
# ros-base's default BASE_IMAGE is localhost/hummingbird-ros2-poc/ros-core:latest
# (built above), so no --build-arg needed.
build ros-base:latest        images/ros-base
build sim-bundle:bridge      images/sim-bundle --build-arg VARIANT=bridge
build sim-bundle:simulation  images/sim-bundle --build-arg VARIANT=simulation
build sim-bundle:gazebo      images/sim-bundle --build-arg VARIANT=gazebo

# Helper runners
ros()  { $PODMAN run --rm --entrypoint /usr/bin/ros-entrypoint.sh "$@"; }
simr() { $PODMAN run --rm --cap-add=sys_admin --entrypoint /usr/bin/sim-entrypoint.sh "$@"; }

# ── ros-core ─────────────────────────────────────────────────────────────────
hr "ros-core"
ros "$PREFIX/ros-core:latest" bash -c 'command -v ros2 >/dev/null' \
  && pass "ros2 CLI present" || bad "ros2 CLI missing"

echo "--- pub/sub: DEFAULT Fast DDS (the qemu-blocked one) ---"
out=$(ros "$PREFIX/ros-core:latest" bash -c '
  ros2 topic pub -r5 /chatter std_msgs/msg/String "{data: fastdds_ok}" >/dev/null 2>&1 &
  sleep 8; timeout 15 ros2 topic echo --once /chatter std_msgs/msg/String 2>/dev/null')
echo "$out" | grep -q fastdds_ok && pass "Fast DDS pub/sub" || soft "Fast DDS pub/sub (no message; check networking)"

echo "--- pub/sub: Cyclone DDS ---"
out=$(ros "$PREFIX/ros-core:latest" bash -c '
  export RMW_IMPLEMENTATION=rmw_cyclonedds_cpp
  ros2 topic pub -r5 /chatter std_msgs/msg/String "{data: cyclone_ok}" >/dev/null 2>&1 &
  sleep 8; timeout 15 ros2 topic echo --once /chatter std_msgs/msg/String 2>/dev/null')
echo "$out" | grep -q cyclone_ok && pass "Cyclone DDS pub/sub" || soft "Cyclone DDS pub/sub (try ROS_LOCALHOST_ONLY=1)"

echo "--- bootc validity ---"
$PODMAN run --rm "$PREFIX/ros-core:latest" bootc container lint >/tmp/lint.log 2>&1 \
  && pass "bootc container lint" || soft "bootc container lint (see /tmp/lint.log)"

# ── ros-base ─────────────────────────────────────────────────────────────────
hr "ros-base"
for p in tf2 tf2_ros robot_state_publisher geometry_msgs rosbag2; do
  ros "$PREFIX/ros-base:latest" bash -c "ros2 pkg prefix $p >/dev/null 2>&1" \
    && pass "$p" || bad "$p missing"
done

# ── sim-bundle:bridge ────────────────────────────────────────────────────────
hr "sim-bundle:bridge"
n=$(simr "$PREFIX/sim-bundle:bridge" bash -c 'ros2 pkg list 2>/dev/null | grep -c ros_gz')
[ "${n:-0}" -ge 3 ] && pass "ros_gz packages ($n)" || bad "ros_gz packages ($n)"
m=$(simr "$PREFIX/sim-bundle:bridge" bash -c 'ldd /usr/lib64/ros-jazzy/lib/ros_gz_bridge/parameter_bridge 2>&1 | grep -c "not found"')
[ "${m:-1}" -eq 0 ] && pass "parameter_bridge libs resolved" || bad "parameter_bridge has $m missing libs"

# ── sim-bundle:simulation ────────────────────────────────────────────────────
hr "sim-bundle:simulation"
simr "$PREFIX/sim-bundle:simulation" gz sim --version 2>&1 | grep -q "Gazebo Sim" \
  && pass "gz sim --version" || bad "gz sim --version"
m=$(simr "$PREFIX/sim-bundle:simulation" bash -c 'ldd /usr/lib64/ros-jazzy/lib/ros_gz_sim/create 2>&1 | grep -c "not found"')
[ "${m:-1}" -eq 0 ] && pass "ros_gz_sim/create libs resolved" || bad "create has $m missing libs"

echo "--- headless gz sim -s physics stepping (the qemu-blocked one) ---"
out=$(simr "$PREFIX/sim-bundle:simulation" bash -c '
  cat > /tmp/w.sdf <<EOF
<?xml version="1.0"?>
<sdf version="1.8"><world name="w">
  <plugin filename="gz-sim-physics-system" name="gz::sim::systems::Physics"/>
</world></sdf>
EOF
  timeout 40 gz sim -s -r --iterations 200 /tmp/w.sdf 2>&1; echo "rc=$?"')
echo "$out" | grep -q "rc=0" && ! echo "$out" | grep -qi "abort\|core dump" \
  && pass "headless gz sim -s stepped 200 iters" \
  || soft "headless gz sim -s (see output above; native x86_64 should pass)"
echo "$out" | tail -3

# ── sim-bundle:gazebo ────────────────────────────────────────────────────────
hr "sim-bundle:gazebo"
simr "$PREFIX/sim-bundle:gazebo" gz sim --version 2>&1 | grep -q "Gazebo Sim" \
  && pass "gz sim --version" || bad "gz sim --version"
simr "$PREFIX/sim-bundle:gazebo" bash -c 'command -v ros2 >/dev/null 2>&1' \
  && bad "ros2 unexpectedly present (should be ROS-free)" || pass "ros2 absent (ROS-free, correct)"

# ── Summary ──────────────────────────────────────────────────────────────────
hr "SUMMARY"
$PODMAN images --format '{{.Repository}}:{{.Tag}} {{.Size}}' | grep "$PREFIX" | sort
echo
if [ "$fail" -ne 0 ]; then
  echo "RESULT: FAILURES present."; exit 1
elif [ "$soft_fail" -ne 0 ]; then
  echo "RESULT: all hard checks passed; some soft (DDS/sim) warnings — review above."; exit 0
else
  echo "RESULT: ALL CHECKS PASSED."; exit 0
fi
