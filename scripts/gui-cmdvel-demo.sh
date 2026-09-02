#!/usr/bin/env bash
#
# gui-cmdvel-demo.sh — "ROS 2 drives the sim, watched in the Gazebo GUI".
#
# Brings up the two-container co-simulation from the project architecture and
# wires a ROS 2 /cmd_vel command through to a diff-drive robot moving in the LIVE
# Gazebo GUI, on a HEADLESS x86_64 host (software GL, served over VNC):
#
#   [ ros-bridge container ]                    [ gz-gui container ]
#     ros2 topic pub /cmd_vel  --> parameter_bridge --> gz-transport --> DiffDrive
#     (geometry_msgs/Twist)        (ROS<->gz, shared pod)   plugin drives the robot
#                                                           |
#     ros2 topic echo  <-- parameter_bridge <-- gz-transport <-- odometry
#     (nav_msgs/Odometry)
#
# Both containers share ONE network namespace (a podman pod) so gz-transport and
# DDS discovery happen over the pod's loopback (GZ_IP=127.0.0.1). The GUI renders
# with bundled Mesa software GL (no GPU) on an Xvfb display exposed via x11vnc.
#
# Connect from your workstation over an SSH tunnel, then drive the robot:
#   ssh -i KEY -L 5900:localhost:5900 ec2-user@HOST     # on your laptop
#   open vnc://localhost:5900                            # macOS VNC viewer
#   # then, on the host, drive it (robot moves in the GUI):
#   sudo podman exec ros-bridge /usr/bin/sim-entrypoint.sh bash -c \
#     "ros2 topic pub /cmd_vel geometry_msgs/msg/Twist \
#        '{linear: {x: 1.0}, angular: {z: 0.3}}'"
#
# The script sets everything up, does ONE short auto-drive to prove motion, then
# LEAVES THE POD RUNNING so you can connect and drive it yourself. Re-run to reset.
# Tear down with:  sudo podman pod rm -f gzcmdvel
#
# >>> NATIVE x86_64 only (gz-transport aborts under amd64-on-arm64 qemu; see
#     CLAUDE.md). Prereqs: podman + Xvfb + x11vnc + ImageMagick (for the proof
#     screenshot). Run only ONE gz GUI at a time — software GL is CPU-heavy and a
#     second concurrent GUI starves llvmpipe and paints nothing.
#
# Usage:  ./scripts/gui-cmdvel-demo.sh
# Env: GZ_IMG, ROS_IMG, DISP (:99), GEO, VNC_PORT (5900), POD (gzcmdvel), NODRIVE=1.

set -uo pipefail

GZ_IMG="${GZ_IMG:-hummingbird-ros2-poc/sim-bundle:gazebo}"     # simulator + GUI
ROS_IMG="${ROS_IMG:-hummingbird-ros2-poc/sim-bundle:bridge}"   # ros_gz bridge + ros2
PODMAN="${PODMAN:-sudo podman}"
POD="${POD:-gzcmdvel}"
DISP="${DISP:-:99}"
GEO="${GEO:-1600x900x24}"
VNC_PORT="${VNC_PORT:-5900}"
ENTRY="/usr/bin/sim-entrypoint.sh"
WORLD="${WORLD:-/tmp/vehicle.sdf}"

need() { command -v "$1" >/dev/null 2>&1 || { echo "!! missing '$1' — sudo dnf install -y $2"; MISSING=1; }; }
MISSING=0
need Xvfb  xorg-x11-server-Xvfb
need x11vnc x11vnc
need xdpyinfo xorg-x11-utils
need import ImageMagick
[ "$MISSING" = 1 ] && { echo "Install the packages above, then re-run."; exit 1; }

# ── 1. Virtual X display + VNC (localhost; reach it through the SSH tunnel) ─────
if ! xdpyinfo -display "$DISP" >/dev/null 2>&1; then
  echo ">>> starting Xvfb on $DISP ($GEO)"
  Xvfb "$DISP" -screen 0 "$GEO" -ac >/tmp/xvfb.log 2>&1 &
  sleep 2
  xdpyinfo -display "$DISP" >/dev/null 2>&1 || { echo "Xvfb failed — see /tmp/xvfb.log"; exit 1; }
else
  echo ">>> reusing existing display $DISP"
fi
if ! pgrep -f "x11vnc.*$DISP" >/dev/null 2>&1; then
  echo ">>> starting x11vnc on localhost:$VNC_PORT (display $DISP)"
  x11vnc -display "$DISP" -localhost -rfbport "$VNC_PORT" -forever -shared -nopw -bg -o /tmp/x11vnc.log
  sleep 1
fi

# ── 2. Diff-drive world: a blue vehicle driven over gz topic /cmd_vel ──────────
# The DiffDrive system subscribes /cmd_vel (gz.msgs.Twist) and publishes
# odometry; the bridge maps those to/from ROS 2 types.
if [ ! -f "$WORLD" ]; then
cat > "$WORLD" <<'SDF'
<?xml version="1.0"?>
<sdf version="1.8">
  <world name="demo">
    <physics name="1ms" type="ignored"><max_step_size>0.001</max_step_size><real_time_factor>1.0</real_time_factor></physics>
    <plugin filename="gz-sim-physics-system" name="gz::sim::systems::Physics"/>
    <plugin filename="gz-sim-scene-broadcaster-system" name="gz::sim::systems::SceneBroadcaster"/>
    <plugin filename="gz-sim-user-commands-system" name="gz::sim::systems::UserCommands"/>
    <light type="directional" name="sun"><cast_shadows>true</cast_shadows><pose>0 0 10 0 0 0</pose>
      <diffuse>1 1 1 1</diffuse><specular>0.5 0.5 0.5 1</specular><direction>-0.5 0.1 -0.9</direction></light>
    <model name="ground"><static>true</static><link name="l">
      <collision name="c"><geometry><plane><normal>0 0 1</normal><size>100 100</size></plane></geometry></collision>
      <visual name="v"><geometry><plane><normal>0 0 1</normal><size>100 100</size></plane></geometry>
        <material><ambient>0.3 0.3 0.3 1</ambient><diffuse>0.5 0.5 0.5 1</diffuse></material></visual></link></model>
    <model name="vehicle_blue" canonical_link="chassis">
      <pose>0 0 0 0 0 0</pose>
      <link name="chassis"><pose relative_to="__model__">0.5 0 0.4 0 0 0</pose>
        <inertial><mass>1.14395</mass><inertia><ixx>0.126164</ixx><ixy>0</ixy><ixz>0</ixz><iyy>0.416519</iyy><iyz>0</iyz><izz>0.481014</izz></inertia></inertial>
        <visual name="visual"><geometry><box><size>2.0 1.0 0.5</size></box></geometry>
          <material><ambient>0 0 1 1</ambient><diffuse>0 0 1 1</diffuse><specular>0 0 1 1</specular></material></visual>
        <collision name="collision"><geometry><box><size>2.0 1.0 0.5</size></box></geometry></collision></link>
      <link name="left_wheel"><pose relative_to="chassis">-0.5 0.6 0 -1.5707 0 0</pose>
        <inertial><mass>1</mass><inertia><ixx>0.043333</ixx><ixy>0</ixy><ixz>0</ixz><iyy>0.043333</iyy><iyz>0</iyz><izz>0.08</izz></inertia></inertial>
        <visual name="visual"><geometry><cylinder><radius>0.4</radius><length>0.2</length></cylinder></geometry>
          <material><ambient>1 0 0 1</ambient><diffuse>1 0 0 1</diffuse></material></visual>
        <collision name="collision"><geometry><cylinder><radius>0.4</radius><length>0.2</length></cylinder></geometry></collision></link>
      <link name="right_wheel"><pose relative_to="chassis">-0.5 -0.6 0 -1.5707 0 0</pose>
        <inertial><mass>1</mass><inertia><ixx>0.043333</ixx><ixy>0</ixy><ixz>0</ixz><iyy>0.043333</iyy><iyz>0</iyz><izz>0.08</izz></inertia></inertial>
        <visual name="visual"><geometry><cylinder><radius>0.4</radius><length>0.2</length></cylinder></geometry>
          <material><ambient>1 0 0 1</ambient><diffuse>1 0 0 1</diffuse></material></visual>
        <collision name="collision"><geometry><cylinder><radius>0.4</radius><length>0.2</length></cylinder></geometry></collision></link>
      <link name="caster"><pose relative_to="chassis">0.8 0 -0.2 0 0 0</pose>
        <inertial><mass>1</mass><inertia><ixx>0.016</ixx><ixy>0</ixy><ixz>0</ixz><iyy>0.016</iyy><iyz>0</iyz><izz>0.016</izz></inertia></inertial>
        <visual name="visual"><geometry><sphere><radius>0.2</radius></sphere></geometry>
          <material><ambient>0.2 0.2 0.2 1</ambient><diffuse>0.2 0.2 0.2 1</diffuse></material></visual>
        <collision name="collision"><geometry><sphere><radius>0.2</radius></sphere></geometry></collision></link>
      <joint name="left_wheel_joint" type="revolute"><parent>chassis</parent><child>left_wheel</child>
        <axis><xyz expressed_in="__model__">0 1 0</xyz><limit><lower>-1.79769e+308</lower><upper>1.79769e+308</upper></limit></axis></joint>
      <joint name="right_wheel_joint" type="revolute"><parent>chassis</parent><child>right_wheel</child>
        <axis><xyz expressed_in="__model__">0 1 0</xyz><limit><lower>-1.79769e+308</lower><upper>1.79769e+308</upper></limit></axis></joint>
      <joint name="caster_wheel" type="ball"><parent>chassis</parent><child>caster</child></joint>
      <plugin filename="gz-sim-diff-drive-system" name="gz::sim::systems::DiffDrive">
        <left_joint>left_wheel_joint</left_joint><right_joint>right_wheel_joint</right_joint>
        <wheel_separation>1.2</wheel_separation><wheel_radius>0.4</wheel_radius>
        <odom_publish_frequency>5</odom_publish_frequency>
        <topic>/cmd_vel</topic><odom_topic>/model/vehicle_blue/odometry</odom_topic></plugin>
    </model>
  </world>
</sdf>
SDF
fi

# ── 3. Pod + two containers ───────────────────────────────────────────────────
echo ">>> (re)creating pod $POD"
$PODMAN pod rm -f "$POD" >/dev/null 2>&1
$PODMAN pod create --name "$POD" >/dev/null

echo ">>> starting gz-gui (server + GUI + physics + DiffDrive, running)"
$PODMAN run -d --pod "$POD" --name gz-gui --cap-add=sys_admin \
  -e GZ_IP=127.0.0.1 -e DISPLAY="$DISP" -e LIBGL_ALWAYS_SOFTWARE=1 \
  -v /tmp/.X11-unix:/tmp/.X11-unix \
  -v "$WORLD:/usr/lib/ros-sysroot/tmp/vehicle.sdf:ro" \
  --entrypoint "$ENTRY" "$GZ_IMG" \
  gz sim -v3 -r /tmp/vehicle.sdf >/dev/null

echo ">>> starting ros-bridge (parameter_bridge /cmd_vel + odometry)"
$PODMAN run -d --pod "$POD" --name ros-bridge --cap-add=sys_admin \
  -e GZ_IP=127.0.0.1 -e ROS_LOCALHOST_ONLY=1 \
  --entrypoint "$ENTRY" "$ROS_IMG" \
  bash -c "ros2 run ros_gz_bridge parameter_bridge \
      '/cmd_vel@geometry_msgs/msg/Twist]gz.msgs.Twist' \
      '/model/vehicle_blue/odometry@nav_msgs/msg/Odometry[gz.msgs.Odometry' \
      2>&1 | tee /tmp/bridge.log" >/dev/null

echo ">>> waiting ~40s for the GUI to render (software GL) and discovery to settle"
sleep 40

# ── 4. Prove ROS 2 drives the sim: read odom, publish /cmd_vel, read odom again ─
odom() { $PODMAN exec ros-bridge "$ENTRY" bash -c \
  "timeout 15 ros2 topic echo --once --field pose.pose.position /model/vehicle_blue/odometry 2>/dev/null"; }

echo ">>> odometry BEFORE:"; odom
if [ "${NODRIVE:-0}" != 1 ]; then
  echo ">>> DRIVE: ros2 topic pub /cmd_vel {linear.x=1.0, angular.z=0.4} for ~6s"
  $PODMAN exec ros-bridge "$ENTRY" bash -c \
    "timeout 8 ros2 topic pub -r 10 /cmd_vel geometry_msgs/msg/Twist \
       '{linear: {x: 1.0}, angular: {z: 0.4}}' >/dev/null 2>&1; true"
  sleep 2
  echo ">>> odometry AFTER (position should have changed):"; odom
  if command -v import >/dev/null 2>&1; then
    import -display "$DISP" -window root /tmp/cmdvel-after.png 2>/dev/null && \
      echo ">>> proof screenshot: /tmp/cmdvel-after.png (colors=$(convert /tmp/cmdvel-after.png -format '%k' info: 2>/dev/null))"
  fi
fi

cat <<EOF
----------------------------------------------------------------
Pod '$POD' is RUNNING (gz-gui + ros-bridge). Drive it yourself:

  On your laptop:
    ssh -i KEY -L $VNC_PORT:localhost:$VNC_PORT ec2-user@<host>
    open vnc://localhost:$VNC_PORT          # any VNC viewer -> localhost:$VNC_PORT

  On this host, publish velocity (robot moves in the GUI):
    $PODMAN exec ros-bridge $ENTRY bash -c \\
      "ros2 topic pub /cmd_vel geometry_msgs/msg/Twist \\
         '{linear: {x: 1.0}, angular: {z: 0.3}}'"
    # Ctrl-C to stop publishing (robot coasts to a halt).

  Read the robot's odometry back over ROS 2:
    $PODMAN exec ros-bridge $ENTRY bash -c \\
      "ros2 topic echo /model/vehicle_blue/odometry"

Tear down:  $PODMAN pod rm -f $POD
----------------------------------------------------------------
EOF
