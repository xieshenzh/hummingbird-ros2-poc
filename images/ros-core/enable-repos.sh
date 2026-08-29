#!/usr/bin/env bash
# Configure dnf package sources for the ROS 2 / Gazebo RPMs on bootc-os.
#
# Two bootc-os quirks make this necessary (both verified against the live
# image and the tavie/ros2 COPR):
#
#   1. bootc-os ships ONLY the Hummingbird repo (public-hummingbird-*-rpms) and
#      does NOT enable the stock Fedora repositories. The tavie ROS RPMs depend
#      on ordinary Fedora libraries (gflags, cli11, console-bridge, protobuf,
#      ...), so we add `fedora` + `updates` here or nothing resolves.
#
#   2. bootc-os overrides dnf's $releasever to a snapshot id (e.g.
#      "20251124-1.15.hum1", derived from VERSION_ID) while `rpm -E %fedora`
#      still reports the real release (43). The tavie .repo baseurl is
#      `.../fedora-$releasever-$basearch/`, so with the snapshot id it 404s.
#      We bake the real Fedora release into the baseurls instead of touching
#      the global $releasever, leaving bootc's own repo resolution untouched.
#
# NOTE: tavie/ros2 only publishes x86_64 for fedora-43 (aarch64 => 404), so
# these images are x86_64-only.
set -euxo pipefail

FED="$(rpm -E %fedora)"
GPGKEY="https://src.fedoraproject.org/rpms/fedora-repos/raw/f${FED}/f/RPM-GPG-KEY-fedora-${FED}-primary"

# ── Stock Fedora repos (omitted by bootc-os) ──
# Release is hardcoded (not $releasever) so these resolve despite the snapshot
# override; $basearch is left for dnf to expand at install time.
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

# ── tavie/ros2 COPR (FHS ROS 2 RPMs) ──
# The .repo carries the COPR signing key + gpgcheck=1; we only rewrite the
# broken $releasever in its baseurl to the real Fedora release.
curl -fsSL -o /tmp/tavie-ros2.repo \
  "https://copr.fedorainfracloud.org/coprs/tavie/ros2/repo/fedora-${FED}/tavie-ros2-fedora-${FED}.repo"
sed "s/\$releasever/${FED}/g" /tmp/tavie-ros2.repo > /etc/yum.repos.d/tavie-ros2.repo
rm -f /tmp/tavie-ros2.repo