# gz runtime environment — profile hook for the simulation images.
#
# The vendored gz RPMs bake their default plugin/media paths into the RPM
# BUILD root (nonexistent at runtime), so discover and export the real ones
# by glob (versioned dirs: gz-sim-8, gz-gui-8, gz-physics-7, gz-rendering-8
# today — the globs survive version bumps). No-op on images without the
# vendors (ros-core/ros-base). Same wiring as images/sim-bundle's
# sim-entrypoint.sh, which documents the failure modes without it:
#   - the SERVER starts but loads no system plugin (no physics);
#   - the GUI opens an empty window (its plugins, the ogre2 render engine
#     and OGRE's media all resolve to the baked BUILDROOT path);
#   - Qt errors "module GzSim is not installed" -> the whole GUI config
#     fails to load.
# Sourced by /etc/bashrc (interactive shells) and by ros-entrypoint.sh.

# Idempotency guard — REQUIRED: the exports below PREPEND to their vars, so
# sourcing this hook twice (entrypoint + login shell, or entrypoint + a user
# script) doubles every path. A doubled GZ_RENDERING_RESOURCE_PATH kills the
# ogre2 engine outright: Ogre treats "path:path" (its Hlms folder suffix
# appended once) as ONE nonexistent folder —
#   OGRE EXCEPTION(6:FileNotFoundException): Data folder provided contains
#   no valid template shader files.
# The guard var is exported so child shells skip the wiring too.
if [ -n "${GZ_VENDOR_WIRED:-}" ]; then
    return 0 2>/dev/null || exit 0
fi
export GZ_VENDOR_WIRED=1

_pfx="/usr/lib64/ros-${ROS_DISTRO:-jazzy}/opt"

# Headless simulation: gz-sim system plugins + the physics engines.
for _d in "$_pfx"/gz_sim_vendor/lib64/gz-sim-*/plugins; do
    [ -d "$_d" ] && export GZ_SIM_SYSTEM_PLUGIN_PATH="$_d${GZ_SIM_SYSTEM_PLUGIN_PATH:+:$GZ_SIM_SYSTEM_PLUGIN_PATH}"
done
for _d in "$_pfx"/gz_physics_vendor/lib64/gz-physics-*/engine-plugins; do
    [ -d "$_d" ] && export GZ_SIM_PHYSICS_ENGINE_PATH="$_d${GZ_SIM_PHYSICS_ENGINE_PATH:+:$GZ_SIM_PHYSICS_ENGINE_PATH}"
done

# GUI: gz-gui + gz-sim GUI plugins, the ogre2 render engine, and its media.
for _d in "$_pfx"/gz_gui_vendor/lib64/gz-gui-*/plugins \
          "$_pfx"/gz_sim_vendor/lib64/gz-sim-*/plugins/gui; do
    [ -d "$_d" ] && export GZ_GUI_PLUGIN_PATH="$_d${GZ_GUI_PLUGIN_PATH:+:$GZ_GUI_PLUGIN_PATH}"
done
for _d in "$_pfx"/gz_rendering_vendor/lib64/gz-rendering-*/engine-plugins; do
    [ -d "$_d" ] && export GZ_RENDERING_PLUGIN_PATH="$_d${GZ_RENDERING_PLUGIN_PATH:+:$GZ_RENDERING_PLUGIN_PATH}"
done
for _d in "$_pfx"/gz_rendering_vendor/share/gz/gz-rendering*; do
    [ -d "$_d" ] && export GZ_RENDERING_RESOURCE_PATH="$_d${GZ_RENDERING_RESOURCE_PATH:+:$GZ_RENDERING_RESOURCE_PATH}"
done
# Qt needs the gz-sim GUI QML modules (e.g. "GzSim") on its import path.
for _d in "$_pfx"/gz_sim_vendor/lib64/gz-sim-*/plugins/gui; do
    [ -d "$_d" ] && export QML2_IMPORT_PATH="$_d${QML2_IMPORT_PATH:+:$QML2_IMPORT_PATH}"
done

# Worlds by NAME (official-image parity: `gz sim shapes.sdf`) — gz-sim
# resolves world files against GZ_SIM_RESOURCE_PATH, and the vendored RPM
# bakes no usable default (BUILDROOT paths), so export the shipped worlds.
for _d in "$_pfx"/gz_sim_vendor/share/gz/gz-sim*/worlds; do
    [ -d "$_d" ] && export GZ_SIM_RESOURCE_PATH="$_d${GZ_SIM_RESOURCE_PATH:+:$GZ_SIM_RESOURCE_PATH}"
done

# Seed the default gui.config into $HOME — the baked default path is broken,
# so without this a plain "gz sim <world>" cannot load its GUI config.
# Symlink (not copy): bootc container lint only allows directories and
# symlinks under /var — real files there trigger warnings (and $HOME=/root
# symlinks to /var/roothome on bootc-os).
for _cfg in "$_pfx"/gz_sim_vendor/share/gz/gz-sim*/gui/gui.config; do
    [ -f "$_cfg" ] || continue
    _b="${_cfg%/gui/gui.config}"; _v="${_b##*/gz-sim}"
    _dest="${HOME:-/root}/.gz/sim/$_v/gui.config"
    [ -e "$_dest" ] || { mkdir -p "${_dest%/*}" && ln -s "$_cfg" "$_dest"; }
done

# Seed the default server.config too — gz-sim copies it from the baked
# BUILDROOT path on first run and fails with
#   [Err] [ServerConfig.cc] Failed to copy installed config [...BUILDROOT...]
# (same disease, same cure as gui.config — symlink, see above).
for _cfg in "$_pfx"/gz_sim_vendor/share/gz/gz-sim*/server.config; do
    [ -f "$_cfg" ] || continue
    _b="${_cfg%/server.config}"; _v="${_b##*/gz-sim}"
    _dest="${HOME:-/root}/.gz/sim/$_v/server.config"
    [ -e "$_dest" ] || { mkdir -p "${_dest%/*}" && ln -s "$_cfg" "$_dest"; }
done

unset _pfx _d _cfg _b _v _dest
