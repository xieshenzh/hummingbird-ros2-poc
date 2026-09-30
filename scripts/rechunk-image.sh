#!/usr/bin/env bash
# Rechunk an existing OCI image into content-based layers with the standalone
# Hummingbird `chunkah` image — one layer per RPM (or small RPM group), the
# kernel isolated into its own layer so a kernel swap (e.g. stock -> kernel-rt)
# dedups cleanly against the base. This is the standalone stand-in for the
# in-build chunkah step used by the containers monorepo (see that repo's
# CHUNKAH-NOTES.md); it needs only podman, no buildah.
#
# Usage:
#   scripts/rechunk-image.sh <src-image> [dst-image]
# Example (as used for the real-time ROS 2 image, native x86_64):
#   sudo scripts/rechunk-image.sh \
#     localhost/hummingbird-ros2-poc/ros-core-rpms-rt:latest \
#     localhost/hummingbird-ros2-poc/ros-core-rpms-rt-chunked:latest
#
# Run with the same podman you built the image with (rootful `sudo podman` on
# the EC2 builders here). Verified 2026-09-30: ros-core-rpms-rt 1.56 GB / 43
# build-step layers -> chunked 1.19 GB / 64 content-based layers, `rpm/kernel`
# in its own 84.5 MB layer; ros2 + RT kernel + `bootc container lint` all intact.
set -euxo pipefail

SRC="${1:?usage: rechunk-image.sh <src-image> [dst-image]}"
DST="${2:-${SRC%:*}-chunked:latest}"

podman pull quay.io/hummingbird-community/chunkah:latest

# chunkah reads the source image's config (env, cmd, labels, ...) from this env
# var so the rechunked image keeps them.
export CHUNKAH_CONFIG_STR="$(podman inspect "$SRC")"

# --cap-add=DAC_READ_SEARCH + label=disable let the non-root chunkah (UID 65532)
# read restrictive files (e.g. /etc/gshadow mode 0000).
podman run --rm \
  --cap-add=DAC_READ_SEARCH \
  --security-opt=label=disable \
  --mount=type=image,src="$SRC",dest=/chunkah \
  -e CHUNKAH_CONFIG_STR \
  quay.io/hummingbird-community/chunkah:latest build -t "$DST" | podman load

echo "=== $SRC -> $DST ==="
podman history "$DST" | head -30