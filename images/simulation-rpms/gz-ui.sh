#!/usr/bin/env bash
# Launch the Gazebo GUI straight from the simulation image — one command,
# no workarounds:
#
#   podman run -d -p 5900:5900 <this-image> gz-ui [gz-sim args | world.sdf]
#
# * No DISPLAY in the container (the usual case) → starts Xvnc (X server +
#   VNC server in one process) and the GUI becomes viewable from any VNC
#   client, e.g. on macOS:   open vnc://localhost:5900
#   (VNC password: "hummingbird" — override with -e GZ_UI_VNC_PASSWORD=…;
#    geometry/port: GZ_UI_GEOMETRY / GZ_UI_VNC_PORT)
# * DISPLAY already set (e.g. X11 forwarding) → uses it directly.
# * Software GL (Mesa llvmpipe) — no GPU required.
# * No arguments → the baked demo world (a ball dropping onto a ground
#   plane); arguments are passed through to `gz sim`.
set -e
export LIBGL_ALWAYS_SOFTWARE=1

# Defensive: also works via `podman exec` (fresh session, nothing sourced
# yet). No-ops when already set up — the dsv hooks prepend-non-duplicate,
# and gz.sh is guarded (see /etc/profile.d/gz.sh).
. "/usr/lib64/ros-${ROS_DISTRO:-jazzy}/setup.bash" 2>/dev/null || true
. /etc/profile.d/gz.sh 2>/dev/null || true

if [ -z "${DISPLAY:-}" ]; then
    PWFILE=/tmp/.gz-ui-vncpass
    printf '%s\n' "${GZ_UI_VNC_PASSWORD:-hummingbird}" | vncpasswd -f > "$PWFILE" 2>/dev/null
    chmod 600 "$PWFILE"
    Xvnc :99 -geometry "${GZ_UI_GEOMETRY:-1280x1024}" -depth 24 -ac \
          -rfbport "${GZ_UI_VNC_PORT:-5900}" -PasswordFile "$PWFILE" \
          >/tmp/gz-ui-xvnc.log 2>&1 &
    for _ in $(seq 1 25); do [ -S /tmp/.X11-unix/X99 ] && break; sleep 0.2; done
    [ -S /tmp/.X11-unix/X99 ] || {
        echo "gz-ui: Xvnc failed to start:" >&2
        tail -5 /tmp/gz-ui-xvnc.log >&2
        exit 1
    }
    export DISPLAY=:99
    echo "gz-ui: GUI is live — connect a VNC client to port ${GZ_UI_VNC_PORT:-5900} (password: ${GZ_UI_VNC_PASSWORD:-hummingbird})"
fi

if [ $# -gt 0 ]; then
    exec gz sim -v -r --physics-engine gz-physics7-bullet-plugin "$@"
else
    exec gz sim -v -r --physics-engine gz-physics7-bullet-plugin \
        /usr/share/hummingbird/demo-world.sdf
fi
