#!/usr/bin/env bash
# Add the stock Fedora repos on bootc-os for the Hummingbird ROS 2 RPMs.
#
# Unlike images/ros-core/enable-repos.sh this does NOT add any COPR: the ROS 2
# packages come from the local repo of our own Hummingbird-built RPMs (see the
# Dockerfile), and the Hummingbird-built system libraries they link against
# (e.g. spdlog-1.17) come from the Hummingbird repo that bootc-os already
# enables (public-hummingbird-*-rpms). All that is missing is plain Fedora.
#
# bootc-os quirks handled here (same as the COPR image):
#   1. bootc-os ships ONLY the Hummingbird repo and does NOT enable the stock
#      Fedora repositories; our ROS RPMs still need ordinary Fedora libraries,
#      so add `fedora` + `updates` or nothing resolves.
#   2. bootc-os overrides dnf's $releasever to a snapshot id while `rpm -E
#      %fedora` still reports the real release. We bake the real release into
#      the baseurls rather than touching the global $releasever (which bootc's
#      own repo resolution relies on).
#
# NOTE ON ARCH/RELEASE: our RPMs are built for aarch64 against Fedora's current
# release in the Hummingbird build env. Build this image on a bootc-os base of
# the MATCHING Fedora release and arch, or system-library sonames may not line
# up. `rpm -E %fedora` below pins the Fedora repos to whatever the base reports.
set -euxo pipefail

FED="$(rpm -E %fedora)"
GPGKEY="https://src.fedoraproject.org/rpms/fedora-repos/raw/f${FED}/f/RPM-GPG-KEY-fedora-${FED}-primary"

# Release is hardcoded (not $releasever) so these resolve despite bootc-os's
# snapshot override; $basearch is left for dnf to expand at install time.
cat > /etc/yum.repos.d/fedora.repo <<EOF
[fedora]
name=Fedora ${FED} - \$basearch
metalink=https://mirrors.fedoraproject.org/metalink?repo=fedora-${FED}&arch=\$basearch
gpgcheck=1
gpgkey=${GPGKEY}
enabled=1

[updates]
name=Fedora ${FED} - updates - \$basearch
metalink=https://mirrors.fedoraproject.org/metalink?repo=updates-released-f${FED}&arch=\$basearch
gpgcheck=1
gpgkey=${GPGKEY}
enabled=1
EOF