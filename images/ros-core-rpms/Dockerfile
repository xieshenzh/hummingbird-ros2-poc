# Hummingbird ROS 2 base image: ros-core (built from Hummingbird RPMs)
#
# Same goal as images/ros-core, but the ROS 2 packages come from our OWN
# RPMs — ROS 2 Jazzy built the Hummingbird way (the `rpms` monorepo dev
# workflow: mock in a pinned container, official upstream sources) — instead
# of the third-party tavie/ros2 COPR.
#
#   images/ros-core (COPR)         this image (Hummingbird RPMs)
#   ---------------------------    ------------------------------------------
#   tavie/ros2 COPR (x86_64)       local repo of our ros-jazzy-* RPMs (aarch64)
#   emulated on Apple Silicon      NATIVE aarch64 (no qemu)
#   Fedora repos + COPR .repo      Fedora repos + hummingbird repo + local repo
#
# Both install FHS packages under /usr/lib64/ros-jazzy (setup.bash provided by
# ros-jazzy-ament-package), so the entrypoint / profile hooks are identical.
#
# Because the base is bootc-os the result is itself a bootable container image:
# it inherits the kernel, systemd and /sbin/init from bootc-os, so it can be
# deployed as a "robot OS" with ROS 2 baked into the immutable /usr layer, or
# run as a plain dev container.
#
# ── Populating the local RPMs (required before build) ──
# The 162 ros-jazzy-* RPMs are NOT committed to git (see .gitignore). Copy them
# from the build VM into ./rpms/ first — e.g. from the repo root:
#     limactl shell fedora -- bash -lc 'tar cf - -C ~/ros-local-rpms .' \
#       | tar xf - -C images/ros-core-rpms/rpms
# then build for the matching arch (native on Apple Silicon = aarch64):
#     podman build -t hummingbird-ros2-poc/ros-core-rpms:latest images/ros-core-rpms

FROM quay.io/hummingbird-community/bootc-os:latest

# ROS distribution shipped in this image. Jazzy is the current LTS.
ENV ROS_DISTRO=jazzy \
    ROS_VERSION=2 \
    ROS_PYTHON_VERSION=3

# ROS 2 requires a UTF-8 locale at runtime.
ENV LANG=C.UTF-8 \
    LC_ALL=C.UTF-8

# ── Package sources ──
# bootc-os already enables the Hummingbird repo (public-hummingbird-*-rpms),
# which provides the Hummingbird-built system libraries our ROS RPMs link
# against (notably spdlog-1.17, which plain Fedora does not ship — Fedora has
# 1.15). enable-repos.sh adds the stock Fedora repos that bootc-os omits (our
# ROS RPMs still need ordinary Fedora libraries). No COPR is used here.
COPY enable-repos.sh /tmp/enable-repos.sh
RUN bash /tmp/enable-repos.sh && rm -f /tmp/enable-repos.sh

# ── Local repo of the Hummingbird-built ROS 2 Jazzy RPMs ──
# Staged under /var/tmp (writable, image-local) rather than /opt (a symlink
# into /var on bootc and NOT part of the image). createrepo_c turns the copied
# RPMs into a dnf repo so the solver can resolve the whole ros-core closure;
# the repo, the RPMs and createrepo_c are all removed afterwards so nothing
# extraneous lands in the immutable layer.
COPY rpms/ /var/tmp/ros-local-rpms/
RUN dnf -y install --setopt=install_weak_deps=0 createrepo_c \
    && createrepo_c /var/tmp/ros-local-rpms \
    && printf '[ros-local]\nname=Hummingbird ROS 2 Jazzy (local)\nbaseurl=file:///var/tmp/ros-local-rpms\nenabled=1\ngpgcheck=0\n' \
         > /etc/yum.repos.d/ros-local.repo \
    && dnf -y install \
         "ros-${ROS_DISTRO}-ros-core" \
         "ros-${ROS_DISTRO}-ament-package" \
    && dnf -y remove createrepo_c \
    && rm -rf /var/tmp/ros-local-rpms /etc/yum.repos.d/ros-local.repo \
    && dnf clean all \
    && rm -rf /var/cache/* /var/log/dnf* /var/log/hawkey.log

# ── Environment setup ──
# Our RPMs install setup scripts under /usr/lib64/ros-${ROS_DISTRO} (same FHS
# layout as tavie), so these hooks are shared verbatim with images/ros-core.
# Auto-source for interactive login shells (`podman run -it ... bash` or an SSH
# session on a booted robot OS):
COPY ros2-profile.sh /etc/profile.d/ros2.sh

# ros-entrypoint.sh sources the ROS environment then execs the given command,
# for plain application-container use:
#   podman run --entrypoint /usr/bin/ros-entrypoint.sh <image> ros2 topic list
COPY ros-entrypoint.sh /usr/bin/ros-entrypoint.sh
RUN chmod +x /usr/bin/ros-entrypoint.sh

# ENTRYPOINT / CMD are intentionally NOT overridden. The image inherits
# CMD ["/sbin/init"] from bootc-os so it stays a valid, bootable bootc image.