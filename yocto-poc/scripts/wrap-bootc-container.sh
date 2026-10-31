#!/bin/bash
# Wrap a Yocto hb-bootc-image rootfs tarball into an ostree-native bootc
# container image and push it to the local registry (localhost:5000).
#
# Runs inside the Lima VM. Usage:
#   wrap-bootc-container.sh [tarball] [tag]
#
# Every fix here was discovered the hard way (see docs/journal.md
# "Phase 1: deployment"):
#  - /etc -> /usr/etc  : ostree deployments carry /etc in /usr/etc; the tar
#    exporter maps /usr/etc back to /etc, so keeping both duplicates paths
#  - /var/tmp removed  : ostree-ext synthesizes var/tmp in the layer tar and
#    its "already present" check misses prefixed paths -> duplicate entry
#  - ca-certificates symlinks longer than 100 chars replaced with copies:
#    the tar exporter's link-name field overflows (set_link_name limit)
#  - /ostree -> sysroot/ostree symlink: bootc install reads /ostree/repo
#  - ostree.bootable + containers.bootc labels: required by bootc install's
#    fetch validation
set -euo pipefail

TAR="${1:-$HOME/yocto/kas-work/build/tmp/deploy/images/qemuarm64/hb-bootc-image-qemuarm64.rootfs.tar.bz2}"
TAG="${2:-v1}"
WORK=/tmp/oci-wrap
REPO=/tmp/ostree-repo
OCIDIR=/tmp/hb-oci
REG=localhost:5000/hb-bootc

sudo rm -rf "$WORK" && mkdir -p "$WORK"
sudo tar -xjf "$TAR" -C "$WORK"

# 1. replace symlinks whose target exceeds the tar link-name cap (~100).
#    MUST run before the /etc move: the ca-certificates symlinks are
#    relative and dangle once /etc becomes /usr/etc.
sudo find "$WORK" -type l | while read -r l; do
    t=$(readlink "$l")
    if [ ${#t} -gt 100 ]; then
        sudo cp -L "$l" "$l.tmp" && sudo rm "$l" && sudo mv "$l.tmp" "$l"
    fi
done

# 2. /etc -> /usr/etc (usrmerge layout, single copy)
sudo mkdir -p "$WORK/usr/etc"
sudo cp -a "$WORK/etc/." "$WORK/usr/etc/"
sudo rm -rf "$WORK/etc"

# 3. no /var/tmp in the commit (exporter synthesizes it)
sudo rm -rf "$WORK/var/tmp"

# 4. /ostree symlink for bootc install's /ostree/repo probe
sudo ln -sfn sysroot/ostree "$WORK/ostree"

# 5. container config: the install container pulls itself from the local
#    registry; bootc overlays /etc/containers with the image's own usr/etc
#    copy, so the insecure-registry config must ship in the image
sudo mkdir -p "$WORK/usr/etc/containers"
sudo tee "$WORK/usr/etc/containers/registries.conf" >/dev/null <<'EOF'
[registries.insecure]
registries = ["localhost:5000"]
EOF
sudo tee "$WORK/usr/etc/containers/policy.json" >/dev/null <<'EOF'
{"default":[{"type":"insecureAcceptAnything"}]}
EOF

# 5. commit + encapsulate
sudo ostree init --repo="$REPO" --mode=archive 2>/dev/null || true
sudo ostree commit --repo="$REPO" --branch hb/bootc/"$TAG" --tree=dir="$WORK" >/dev/null
sudo rm -rf "$OCIDIR"
sudo "$HOME/ostree-encap/target/release/ostree-encap" "$REPO" hb/bootc/"$TAG" "oci:$OCIDIR:$TAG"

# 6. into podman + local registry
sudo podman rmi -f "hb-bootc-ostree:$TAG" "$REG:$TAG" 2>/dev/null || true
sudo podman pull -q "oci:$OCIDIR:$TAG" >/dev/null
ID=$(sudo podman images --format "{{.ID}} {{.Repository}}" | awk -v t="$TAG" '$2 ~ /latest|oci/ {print $1; exit}')
sudo podman tag "$(sudo podman images -q | head -1)" "hb-bootc-ostree:$TAG"
sudo podman push --tls-verify=false "hb-bootc-ostree:$TAG" "$REG:$TAG" >/dev/null
echo "pushed $REG:$TAG"
sudo podman run --rm "hb-bootc-ostree:$TAG" bootc container lint
