#!/bin/bash
# Build the encapsulated near-empty ostree base commit (layer 0) for the
# chunked bootc image format — see assemble-chunked-bootc.py.
#
# The base commit carries ONLY what ostree-ext's derived-layer import
# drops and what the deployed system needs before systemd mounts things:
#   - usrmerge/ostree compat symlinks (bin/lib/sbin -> usr/..., opt ->
#     usr/opt, root/home/srv -> var/..., ostree -> sysroot/ostree for
#     bootc's runtime sysroot probe)
#   - runtime mountpoints (dev/proc/sys/boot/run/tmp). ostree cannot
#     store empty directories, so each gets a .hb-keep placeholder that
#     the runtime mounts shadow.
#
# Runs inside the Lima VM. Usage:
#   build-encap-base.sh [out-oci-dir]   (default /tmp/base-oci, tag "base")
# Requires ostree-encap at ~/ostree-encap/target/release/ostree-encap.
set -euo pipefail

OUT="${1:-/tmp/base-oci}"
TREE=/tmp/base-tree
REPO=/tmp/base-repo
ENCAP="$HOME/ostree-encap/target/release/ostree-encap"
[ -x "$ENCAP" ] || { echo "ostree-encap not found at $ENCAP" >&2; exit 1; }

sudo rm -rf "$TREE" "$REPO" "$OUT"
sudo mkdir -p "$TREE"
cd "$TREE"
sudo ln -sfn usr/bin bin
sudo ln -sfn usr/lib lib
sudo ln -sfn usr/sbin sbin
sudo ln -sfn usr/opt opt
sudo ln -sfn var/root root
sudo ln -sfn var/home home
sudo ln -sfn var/srv srv
sudo ln -sfn sysroot/ostree ostree
for d in dev proc sys boot run tmp; do
    sudo mkdir -p "$d"
    sudo touch "$d/.hb-keep"
done

sudo ostree init --repo="$REPO" --mode=archive
sudo ostree commit --repo="$REPO" --branch=hb/bootc/base --tree=dir="$TREE"
sudo "$ENCAP" "$REPO" hb/bootc/base "oci:$OUT:base"
echo "base layer written to $OUT (tag base)"
