#!/usr/bin/env bash
#
# gui-verify.sh — launch the Gazebo GUI (`gz sim`) from the sim-bundle image on a
# HEADLESS x86_64 host, rendered with SOFTWARE GL (Mesa, bundled in the image —
# no GPU needed) and served over VNC.
#
# It brings up a virtual X display (Xvfb), exposes it via x11vnc on localhost,
# then runs `gz sim <world>` (server + GUI in one process) so a real 3D scene
# renders. Connect from your workstation over an SSH tunnel:
#
#   ssh -i KEY -L 5900:localhost:5900 ec2-user@HOST      # on your laptop
#   # then point any VNC viewer at localhost:5900 (macOS: open vnc://localhost:5900)
#
# Prereqs on the host: podman + Xvfb + x11vnc (the script checks and tells you the
# dnf packages if missing). Software GL is CPU-bound and slow but proves the GUI
# stack end to end. For a smooth GUI use a GPU instance (g4dn) + NVIDIA driver
# injected into the chroot — a separate follow-up (see CLAUDE.md "Interactive GUI").
#
# >>> NATIVE x86_64 only. Usage:  ./scripts/gui-verify.sh   (KEEP running; Ctrl-C to stop)
# Env: IMG, DISP (:99), GEO (1600x900x24), VNC_PORT (5900), WORLD (auto demo).

set -uo pipefail

IMG="${IMG:-hummingbird-ros2-poc/sim-bundle:gazebo}"
PODMAN="${PODMAN:-sudo podman}"
DISP="${DISP:-:99}"
GEO="${GEO:-1600x900x24}"
VNC_PORT="${VNC_PORT:-5900}"
ENTRY="/usr/bin/sim-entrypoint.sh"

need() { command -v "$1" >/dev/null 2>&1 || { echo "!! missing '$1' — install with: sudo dnf install -y $2"; MISSING=1; }; }
MISSING=0
need Xvfb  xorg-x11-server-Xvfb
need x11vnc x11vnc
need xdpyinfo xorg-x11-utils
[ "$MISSING" = 1 ] && { echo "Install the packages above, then re-run."; exit 1; }

# 1. Virtual X display (‑ac disables access control — fine on a throwaway box).
if ! xdpyinfo -display "$DISP" >/dev/null 2>&1; then
  echo ">>> starting Xvfb on $DISP ($GEO)"
  Xvfb "$DISP" -screen 0 "$GEO" -ac >/tmp/xvfb.log 2>&1 &
  sleep 2
  xdpyinfo -display "$DISP" >/dev/null 2>&1 || { echo "Xvfb failed — see /tmp/xvfb.log"; exit 1; }
else
  echo ">>> reusing existing display $DISP"
fi

# 2. VNC server bound to localhost (reach it through the SSH tunnel above).
if ! pgrep -f "x11vnc.*$DISP" >/dev/null 2>&1; then
  echo ">>> starting x11vnc on localhost:$VNC_PORT (display $DISP)"
  x11vnc -display "$DISP" -localhost -rfbport "$VNC_PORT" -forever -shared -nopw -bg -o /tmp/x11vnc.log
  sleep 1
else
  echo ">>> reusing existing x11vnc on $DISP"
fi

# 3. A demo world with something to look at: sun + ground + a ball that falls.
WORLD="${WORLD:-/tmp/gui-world.sdf}"
if [ ! -f "$WORLD" ]; then
cat > "$WORLD" <<'SDF'
<?xml version="1.0"?>
<sdf version="1.8">
  <world name="demo">
    <plugin filename="gz-sim-physics-system" name="gz::sim::systems::Physics"/>
    <plugin filename="gz-sim-scene-broadcaster-system" name="gz::sim::systems::SceneBroadcaster"/>
    <plugin filename="gz-sim-user-commands-system" name="gz::sim::systems::UserCommands"/>
    <light type="directional" name="sun">
      <cast_shadows>true</cast_shadows><pose>0 0 10 0 0 0</pose>
      <diffuse>1 1 1 1</diffuse><specular>0.5 0.5 0.5 1</specular>
      <direction>-0.5 0.1 -0.9</direction>
    </light>
    <model name="ground"><static>true</static><link name="l">
      <collision name="c"><geometry><plane><normal>0 0 1</normal><size>50 50</size></plane></geometry></collision>
      <visual name="v"><geometry><plane><normal>0 0 1</normal><size>50 50</size></plane></geometry>
        <material><ambient>0.3 0.3 0.3 1</ambient><diffuse>0.5 0.5 0.5 1</diffuse></material></visual>
    </link></model>
    <model name="ball"><pose>0 0 5 0 0 0</pose><link name="l">
      <inertial><mass>1.0</mass><inertia><ixx>0.1</ixx><iyy>0.1</iyy><izz>0.1</izz><ixy>0</ixy><ixz>0</ixz><iyz>0</iyz></inertia></inertial>
      <collision name="c"><geometry><sphere><radius>0.5</radius></sphere></geometry></collision>
      <visual name="v"><geometry><sphere><radius>0.5</radius></sphere></geometry>
        <material><ambient>0.1 0.2 0.6 1</ambient><diffuse>0.2 0.4 0.9 1</diffuse></material></visual>
    </link></model>
  </world>
</sdf>
SDF
fi

echo "----------------------------------------------------------------"
echo ">>> launching 'gz sim' GUI under software GL"
echo "    On your laptop:  ssh -i KEY -L $VNC_PORT:localhost:$VNC_PORT ec2-user@<host>"
echo "    then open a VNC viewer at localhost:$VNC_PORT (macOS: open vnc://localhost:$VNC_PORT)"
echo "    You should see a ground plane and a blue ball falling. Ctrl-C to stop."
echo "----------------------------------------------------------------"

# sim-entrypoint.sh rbinds the container's /tmp/.X11-unix into the chroot and
# passes DISPLAY/LIBGL_ALWAYS_SOFTWARE through, so bind the host X socket in and
# hand it the world at /tmp/w.sdf. `gz sim <world>` (no -s/-g) runs server+GUI.
exec $PODMAN run --rm --cap-add=sys_admin \
  -e DISPLAY="$DISP" -e LIBGL_ALWAYS_SOFTWARE=1 -e GZ_IP=127.0.0.1 \
  -v /tmp/.X11-unix:/tmp/.X11-unix \
  -v "$WORLD:/usr/lib/ros-sysroot/tmp/w.sdf:ro" \
  --entrypoint "$ENTRY" "$IMG" \
  gz sim -v3 /tmp/w.sdf