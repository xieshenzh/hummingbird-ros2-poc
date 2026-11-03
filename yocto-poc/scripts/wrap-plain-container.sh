#!/bin/bash
# Wrap a Yocto hb-bootc-image rootfs tarball into a PLAIN-layer bootc
# container (podman import) and push it to the local registry.
#
# Companion to wrap-bootc-container.sh (which makes the ostree-encap
# "ostree-native" image). This variant produces an ordinary
# Docker-style image: one plain rootfs layer + bootc labels. ostree-ext
# synthesizes the deployment commit at pull time. That layer shape is
# what chunkah can safely re-split (the ostree-encap layer is an ostree
# object store; chunking it breaks ostree-ext's import with
# "Missing xattrs reference").
#
# Runs inside the Lima VM. Usage:
#   wrap-plain-container.sh [tarball] [tag]
# Rootfs fixes are identical to wrap-bootc-container.sh — see the
# commentary there and docs/journal.md "Phase 1: deployment".
set -euo pipefail

TAR="${1:-$HOME/yocto/kas-work/build/tmp/deploy/images/qemuarm64/hb-bootc-image-qemuarm64.rootfs.tar.bz2}"
TAG="${2:-v1}"
WORK=/tmp/oci-plain
REG=localhost:5000/hb-bootc

sudo rm -rf "$WORK" && mkdir -p "$WORK"
sudo tar -xjf "$TAR" -C "$WORK"

# 1. long symlinks -> copies (tar link-name field cap) — before /etc move
sudo find "$WORK" -type l | while read -r l; do
    t=$(readlink "$l")
    if [ ${#t} -gt 100 ]; then
        sudo cp -L "$l" "$l.tmp" && sudo rm "$l" && sudo mv "$l.tmp" "$l"
    fi
done

# 2. /etc -> /usr/etc
sudo mkdir -p "$WORK/usr/etc"
sudo cp -a "$WORK/etc/." "$WORK/usr/etc/"
sudo rm -rf "$WORK/etc"

# 3. no /var/tmp in the layer
sudo rm -rf "$WORK/var/tmp"

# 4. /ostree symlink for bootc install's /ostree/repo probe
sudo ln -sfn sysroot/ostree "$WORK/ostree"

# 4b. strip any embedded ostree repo (only present when reusing the
#     rootfs of an ostree-encap image; a fresh Yocto tarball has none).
#     A repo carried in the chunks makes bootc install fail with
#     "Multiple commit objects found" — the chunked image's repo comes
#     from the assembled encapsulated base layer.
sudo rm -rf "$WORK/sysroot/ostree"
# NOTE: /opt -> usr/opt and hardlink dereference are done by the image
# recipe (hb-bootc-image.bb hb_bootc_usr_layout / hb_deref_hardlinks);
# only pre-recipe rootfs trees need them applied by hand.

# 5. container config baked into the image (bootc overlays /etc/containers)
sudo mkdir -p "$WORK/usr/etc/containers"
sudo tee "$WORK/usr/etc/containers/registries.conf" >/dev/null <<'EOF'
[registries.insecure]
# localhost: the VM-side install/registry; 10.0.2.2: qemu user-net gateway
registries = ["localhost:5000", "10.0.2.2:5000"]
EOF
sudo tee "$WORK/usr/etc/containers/policy.json" >/dev/null <<'EOF'
{"default":[{"type":"insecureAcceptAnything"}]}
EOF

# 6. static skopeo for bootc's pull path
if [ -x /tmp/skopeo-static ]; then
    sudo install -m 0755 /tmp/skopeo-static "$WORK/usr/bin/skopeo"
else
    echo "WARNING: /tmp/skopeo-static missing — image won't be able to pull" >&2
fi

# 7. plain-layer image: single uncompressed-ish layer via podman import,
#    with the labels bootc requires (what a Dockerfile-built bootc image has)
sudo tar -C "$WORK" -c . | sudo podman import --change 'LABEL ostree.bootable=1' \
    --change 'LABEL containers.bootc=1' \
    - "hb-bootc-plain:$TAG" >/dev/null

sudo podman rmi -f "$REG:$TAG" 2>/dev/null || true
sudo podman push --tls-verify=false "hb-bootc-plain:$TAG" "$REG:$TAG" >/dev/null
echo "pushed $REG:$TAG (plain-layer)"
sudo podman run --rm "hb-bootc-plain:$TAG" bootc container lint
