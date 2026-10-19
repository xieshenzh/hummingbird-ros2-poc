# Hummingbird ROS 2 simulation image: the `simulation` variant (REP 2001)
#
# Extends ros-base-rpms with the Gazebo-Harmonic-based simulation stack:
#   simulation = ros_base + ros_gz_bridge + ros_gz_sim + ros_gz_image
#              + ros_gz_interfaces
#
# Package source (all OUR Hummingbird-built RPMs, no COPR):
#   * Tier B: image_transport, the 5 extra msg packages ros_gz 1.0.25 needs
#     (actuator/gps/marine-acoustic/vision/simulation-interfaces),
#     ros_gz_{interfaces,bridge,image,sim}, the simulation metapackage.
#   * Tier A: the 17 gz_*_vendor RPMs (Gazebo Harmonic 8.15.0 built from
#     source via the offline-vendor recipe) — including gz_sim_vendor and
#     the av-enabled gz_common_vendor rebuild.
#   * Enablers: the icu78 Qt5 QML + no-smb gdal/ffmpeg `.hum1` rebuilds
#     (must be staged so dnf prefers them over Fedora's icu77-linked ones —
#     `1.hum1` > `1.fc44` in RPM EVR).
#
# Physics note: DART is deferred (fcl missing in Fedora 44) — gz-physics
# ships bullet + TPE. Run sims with:
#   gz sim --physics-engine gz-physics-bullet-plugin ...
#
# GUI (no workarounds): `podman run -d -p 5900:5900 <image> gz-ui` —
# Xvnc + software GL + the gz wiring; view with any VNC client (macOS:
# `open vnc://localhost:5900`, password "hummingbird"). See gz-ui.sh.
#
# ── Populating the local RPMs (required before build) ──
# Stage the sim closure from the build VM (aarch64) into ./rpms/ — from the
# repo root (ALL non-debug RPMs of ~/ros-local-rpms; the ros_core/ros_base
# RPMs already in the base are harmless restage, and the closure's uninstalled
# deps e.g. sensor_msgs_py resolve from it):
#   limactl shell fedora -- bash -lc \
#     'cd ~/ros-local-rpms && ls *.rpm | grep -vE "debuginfo|debugsource" \
#        | tar cf - -T -' | tar xf - -C images/simulation-rpms/rpms
# then build natively (aarch64):
#   podman build -t hummingbird-ros2-poc/simulation-rpms:latest images/simulation-rpms
# or on the RT ros-base for the full RT robot-OS chain:
#   podman build \
#     --build-arg BASE_IMAGE=localhost/hummingbird-ros2-poc/ros-base-rpms-rt:latest \
#     -t hummingbird-ros2-poc/simulation-rpms-rt:latest images/simulation-rpms
ARG BASE_IMAGE=localhost/hummingbird-ros2-poc/ros-base-rpms:latest
FROM ${BASE_IMAGE}

# ROS_DISTRO, locale, Fedora + Hummingbird repos and the entrypoint / profile
# hooks are all inherited from ros-core-rpms via ros-base-rpms, so this layer
# only adds the simulation closure.

# ── Local repo of the simulation-closure RPMs ──
COPY rpms/ /var/tmp/ros-sim-rpms/
# rubygem4.0-psych + rubygem4.0-fiddle: the gz Ruby CLI (gz-tools) requires
# 'yaml'/psych and 'fiddle', neither of which is a Ruby 4.0 default gem (and
# the Hummingbird repo lacks fiddle — built as an enabler in this repo) —
# and install_weak_deps=0 (needed: weak deps would pull the conflicting
# ruby3.3/3.4 parallel streams) drops ruby's Recommends that bring psych.
# qt5-qtquickcontrols: provides the QtQuick.Dialogs QML module that gz-gui's
# Main.qml hard-imports ("import QtQuick.Dialogs 1.0") — a runtime dep the
# gz_gui_vendor spec does not capture (Controls-1 package, easily missed
# next to qtquickcontrols2).
# qt5-qtsvg: Qt's SVG image-format plugin — gz-gui's toolbar/panel icons are
# SVGs; without it the GUI renders but every icon fails to decode.
# tigervnc-server: Xvnc (X server + VNC server in one) for the baked gz-ui
# launcher — view the GUI from any VNC client, no GPU or host X needed.
RUN dnf -y install --setopt=install_weak_deps=0 createrepo_c \
    && createrepo_c /var/tmp/ros-sim-rpms \
    && printf '[ros-sim-local]\nname=Hummingbird ROS 2 Jazzy simulation (local)\nbaseurl=file:///var/tmp/ros-sim-rpms\nenabled=1\ngpgcheck=0\n' \
         > /etc/yum.repos.d/ros-sim-local.repo \
    && dnf -y install --setopt=install_weak_deps=0 "ros-${ROS_DISTRO}-simulation" \
         rubygem4.0-psych rubygem4.0-fiddle \
         qt5-qtquickcontrols \
         qt5-qtsvg \
         tigervnc-server \
    && dnf -y remove createrepo_c \
    && rm -rf /var/tmp/ros-sim-rpms /etc/yum.repos.d/ros-sim-local.repo \
    && dnf clean all \
    && rm -rf /var/cache/* /var/log/dnf* /var/log/hawkey.log /run/dnf /var/lib/dnf/repos \
              /run/selinux-policy /run/setrans

# ── gz runtime wiring ──
# The vendored gz RPMs bake broken default plugin paths (the RPM BUILD root);
# gz.sh discovers and exports the real ones (system plugins, physics engines,
# GUI plugins, the ogre2 engine + media, the GzSim QML modules) and seeds the
# default gui.config. Sourced by interactive shells (/etc/bashrc) and by the
# updated entrypoint below. No-op on images without the gz vendors.
COPY gz.sh /etc/profile.d/gz.sh
# Updated entrypoint (synced copy of images/ros-core-rpms/ros-entrypoint.sh)
# that sources the gz hook — installed over the one inherited from the base.
COPY ros-entrypoint.sh /usr/bin/ros-entrypoint.sh

# ── ogre2 media layout fix ──
# Ogre2RenderEngine looks for $GZ_RENDERING_RESOURCE_PATH/ogre2/src/media/Hlms/…
# but the vendored gz_rendering RPM installs the media at ogre2/media (no
# src/). Without this symlink the 3D viewport dies at startup with
#   OGRE EXCEPTION(6:FileNotFoundException): Data folder provided contains
#   no valid template shader files.
RUN for d in /usr/lib64/ros-${ROS_DISTRO}/opt/gz_rendering_vendor/share/gz/gz-rendering*; do \
      if [ -d "$d/ogre2/media" ] && [ ! -e "$d/ogre2/src/media" ]; then \
        mkdir -p "$d/ogre2/src" && ln -s ../media "$d/ogre2/src/media"; \
      fi; \
    done

# ── One-command GUI launch ──
#   podman run -d -p 5900:5900 <image> gz-ui [gz-sim args | world.sdf]
# Xvnc + software GL + the wiring above; view with any VNC client
# (macOS: open vnc://localhost:5900, password "hummingbird" — see gz-ui.sh).
COPY gz-ui.sh /usr/bin/gz-ui
COPY demo-world.sdf /usr/share/hummingbird/demo-world.sdf
RUN chmod +x /usr/bin/ros-entrypoint.sh /etc/profile.d/gz.sh /usr/bin/gz-ui

# ── bootc-clean /var and /run ──
# `bootc container lint` requires every item under /var to be declared in
# systemd tmpfiles.d (var-tmpfiles check) and /run to be empty (the
# nonempty-run-tmp check). Two sources of content:
#  * the gz default-config symlinks (what gz.sh seeds into $HOME at runtime;
#    baked here for the default root home — $HOME=/root → /var/roothome),
#  * empty dirs the sim closure's RPM scriptlets leave behind
#    (/var/kerberos from the krb5 deps — declared below; /run/selinux-policy
#    and /run/setrans from the selinux packages — removed in the dnf cleanup
#    above).
# The entries are generated with a glob so gz-sim version bumps survive.
RUN tf=/usr/lib/tmpfiles.d/hummingbird-gz.conf \
    && printf 'd /var/roothome/.gz 0755 root root - -\nd /var/roothome/.gz/sim 0755 root root - -\nd /var/kerberos 0755 root root - -\nd /var/kerberos/krb5 0755 root root - -\nd /var/kerberos/krb5/user 0755 root root - -\n' > "$tf" \
    && for v in /usr/lib64/ros-${ROS_DISTRO}/opt/gz_sim_vendor/share/gz/gz-sim*; do \
         n="${v##*/gz-sim}"; \
         printf 'd /var/roothome/.gz/sim/%s 0755 root root - -\n' "$n" >> "$tf"; \
         printf 'L /var/roothome/.gz/sim/%s/gui.config - - - - %s/gui/gui.config\n' "$n" "$v" >> "$tf"; \
         printf 'L /var/roothome/.gz/sim/%s/server.config - - - - %s/server.config\n' "$n" "$v" >> "$tf"; \
         mkdir -p "/var/roothome/.gz/sim/$n"; \
         ln -sfn "$v/gui/gui.config" "/var/roothome/.gz/sim/$n/gui.config"; \
         ln -sfn "$v/server.config" "/var/roothome/.gz/sim/$n/server.config"; \
       done

# ── Official-image parity ──
# Like ros:jazzy-simulation's ENTRYPOINT ["/ros_entrypoint.sh"]: every
# `podman run <image> <cmd>` goes through the entrypoint (sources the ROS
# env + gz wiring) so `gz sim`, `ros2 …`, `bash` etc. all just work.
# CMD stays ["/sbin/init"]: bootc boots the OS natively and ignores
# ENTRYPOINT/CMD, and the init CMD keeps `bootc container lint` happy —
# for an interactive shell use `podman run -it <image> bash` (one word
# more than the official image, which trades away bootc boot validity).
ENTRYPOINT ["/usr/bin/ros-entrypoint.sh"]
# Compat: the official images' entrypoint path.
RUN ln -s /usr/bin/ros-entrypoint.sh /ros_entrypoint.sh

# CMD is intentionally NOT overridden — the image inherits CMD ["/sbin/init"]
# from bootc-os (through ros-core-rpms) so it stays a valid, bootable bootc
# image; see the parity note above for the full story.
