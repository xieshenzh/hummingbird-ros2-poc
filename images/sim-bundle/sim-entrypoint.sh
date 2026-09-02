#!/usr/bin/env bash
# Run a command inside the bundled ROS/Gazebo sysroot.
#
# The stack is installed on stock fedora:43 (where the tavie RPMs resolve) into
# an isolated root that is copied into this bootc image at /usr/lib/ros-sysroot.
# It carries its OWN boost 1.83, ruby and ogre, which conflict irreconcilably
# with bootc-os's boost 1.90 / multi-stream ruby if merged into the base /usr.
# We chroot into the sysroot so its paths (/usr/lib64/ros-<distro>, its boost,
# its ruby) all resolve against the bundled tree and never touch the base.
#
# chroot needs CAP_SYS_CHROOT (default) plus CAP_SYS_ADMIN to bind-mount the
# kernel filesystems, so run with --cap-add=sys_admin (a booted bootc host runs
# this as root with full caps, so the mounts just work there):
#   podman run --cap-add=sys_admin --entrypoint /usr/bin/sim-entrypoint.sh \
#     <image> ros2 pkg list
#   podman run --cap-add=sys_admin --entrypoint /usr/bin/sim-entrypoint.sh \
#     <image> gz sim --version
#
# We tried bwrap first (unprivileged user namespaces, no caps) but the
# podman-machine VM blocks nested userns creation (EINVAL); chroot is the
# portable fallback. bwrap would be preferable where nested userns is allowed.
set -e

SYSROOT="${ROS_SYSROOT:-/usr/lib/ros-sysroot}"

# Bind the kernel filesystems into the sysroot. rbind /proc because a fresh proc
# mount is rejected read-only inside the container; rbind /dev and /sys so DDS
# shared memory, /dev/null, GPUs (/dev/dri), etc. are visible.
for fs in proc dev sys; do
    mountpoint -q "$SYSROOT/$fs" 2>/dev/null || mount --rbind "/$fs" "$SYSROOT/$fs"
done
# Carry DNS in for networked simulation.
cp -f /etc/resolv.conf "$SYSROOT/etc/resolv.conf" 2>/dev/null || true

# GUI support (gz sim -g / rviz): make the host display reachable inside the
# chroot. The sysroot has its own /tmp, so the X11 socket must be bound in.
# Provide a display at run time, e.g. (X11, host GPU):
#   xhost +local:
#   podman run --rm --platform linux/amd64 --cap-add=sys_admin \
#     --net=host --device /dev/dri -e DISPLAY -e XAUTHORITY \
#     -v /tmp/.X11-unix:/tmp/.X11-unix \
#     --entrypoint /usr/bin/sim-entrypoint.sh \
#     hummingbird-ros2-poc/sim-bundle:gazebo gz sim -g
# (drop --device /dev/dri and add -e LIBGL_ALWAYS_SOFTWARE=1 for software GL.)
# GUI is x86_64-native only: it will NOT work under amd64-on-arm64 qemu.
if [ -d /tmp/.X11-unix ]; then
    mkdir -p "$SYSROOT/tmp/.X11-unix"
    mountpoint -q "$SYSROOT/tmp/.X11-unix" 2>/dev/null || \
        mount --rbind /tmp/.X11-unix "$SYSROOT/tmp/.X11-unix"
fi
# Bind an X authority file through, if one is set and exists.
if [ -n "${XAUTHORITY:-}" ] && [ -f "$XAUTHORITY" ]; then
    mkdir -p "$SYSROOT$(dirname "$XAUTHORITY")"
    touch "$SYSROOT$XAUTHORITY"
    mountpoint -q "$SYSROOT$XAUTHORITY" 2>/dev/null || \
        mount --bind "$XAUTHORITY" "$SYSROOT$XAUTHORITY"
fi

# ROS_DISTRO / LANG / LC_ALL are image ENV and are inherited across chroot.
#
# The vendored setup.bash only sets GZ_CONFIG_PATH — NOT the several paths gz-sim
# needs to actually run a simulation OR open its GUI. Every gz-*-vendor RPM bakes
# its default plugin/media paths into the nonexistent RPM build root
# (/builddir/.../BUILDROOT/...), so out of the box:
#   - the SERVER starts but loads no system plugin ("Failed to load system plugin
#     [gz-sim-physics-system]") and finds no physics engine ("Failed to find
#     plugin [gz-physics-dartsim-plugin]") — nothing is simulated even though
#     /clock still advances; and
#   - the GUI opens an empty window: its gz-sim/gz-gui plugins, the ogre2 render
#     engine, and OGRE's shader media all resolve to the missing BUILDROOT path.
# We rediscover each by glob (versioned dirs: gz-sim-8, gz-physics-7,
# gz-rendering-8 today — the globs survive version bumps) and export the right
# GZ_* var. On the bridge variant none of these dirs exist, so every line is a
# no-op there. Verified on native x86_64: headless physics computes (a body
# falls) and `gz sim <world>` renders the standard GUI under software GL.
exec chroot "$SYSROOT" /bin/bash -c '
    source "/usr/lib64/ros-${ROS_DISTRO:-jazzy}/setup.bash"
    _pfx="/usr/lib64/ros-${ROS_DISTRO:-jazzy}/opt"

    # Headless simulation: gz-sim system plugins + physics (dartsim) engine.
    for d in "$_pfx"/gz_sim_vendor/lib64/gz-sim-*/plugins; do
        [ -d "$d" ] && export GZ_SIM_SYSTEM_PLUGIN_PATH="$d${GZ_SIM_SYSTEM_PLUGIN_PATH:+:$GZ_SIM_SYSTEM_PLUGIN_PATH}"
    done
    for d in "$_pfx"/gz_physics_vendor/lib64/gz-physics-*/engine-plugins; do
        [ -d "$d" ] && export GZ_SIM_PHYSICS_ENGINE_PATH="$d${GZ_SIM_PHYSICS_ENGINE_PATH:+:$GZ_SIM_PHYSICS_ENGINE_PATH}"
    done

    # GUI: gz-gui + gz-sim GUI plugins, the ogre2 render engine, and its media.
    for d in "$_pfx"/gz_gui_vendor/lib64/gz-gui-*/plugins \
             "$_pfx"/gz_sim_vendor/lib64/gz-sim-*/plugins/gui; do
        [ -d "$d" ] && export GZ_GUI_PLUGIN_PATH="$d${GZ_GUI_PLUGIN_PATH:+:$GZ_GUI_PLUGIN_PATH}"
    done
    for d in "$_pfx"/gz_rendering_vendor/lib64/gz-rendering-*/engine-plugins; do
        [ -d "$d" ] && export GZ_RENDERING_PLUGIN_PATH="$d${GZ_RENDERING_PLUGIN_PATH:+:$GZ_RENDERING_PLUGIN_PATH}"
    done
    for d in "$_pfx"/gz_rendering_vendor/share/gz/gz-rendering*; do
        [ -d "$d" ] && export GZ_RENDERING_RESOURCE_PATH="$d${GZ_RENDERING_RESOURCE_PATH:+:$GZ_RENDERING_RESOURCE_PATH}"
    done
    # Qt needs the gz-sim GUI QML modules (e.g. "GzSim") on its import path, or
    # panels like ComponentInspector/EntityTree fail ("module GzSim is not
    # installed") and gz then fails to load the whole GUI config -> blank window.
    for d in "$_pfx"/gz_sim_vendor/lib64/gz-sim-*/plugins/gui; do
        [ -d "$d" ] && export QML2_IMPORT_PATH="$d${QML2_IMPORT_PATH:+:$QML2_IMPORT_PATH}"
    done
    # gz sim cannot find its default GUI config (same baked-BUILDROOT path), so
    # seed the real one into $HOME — then plain "gz sim <world>" opens the normal
    # GUI without needing --gui-config.
    for cfg in "$_pfx"/gz_sim_vendor/share/gz/gz-sim*/gui/gui.config; do
        [ -f "$cfg" ] || continue
        _b="${cfg%/gui/gui.config}"; _v="${_b##*/gz-sim}"
        _dest="${HOME:-/root}/.gz/sim/$_v/gui.config"
        [ -f "$_dest" ] || { mkdir -p "${_dest%/*}" && cp "$cfg" "$_dest"; }
    done

    exec "$@"' bash "$@"