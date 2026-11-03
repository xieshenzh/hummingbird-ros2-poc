#!/bin/bash
# Install the registry-sourced hb-bootc container onto the prepared target
# disk via `bootc install to-filesystem`, then release the disk.
#
# Runs inside the Lima VM (rootful podman). Usage:
#   bootc-install-target.sh [tag] [disk-img]
#
# bootc v1.1.0's installer shells out to a set of host tools the minimal
# Yocto image doesn't carry; we bind-mount the VM host's binaries through
# loader-shim wrappers in /tmp/skopeo-wrap (see docs/journal.md). The
# bootupctl stub skips bootloader install — the PoC verifies via qemu
# direct-kernel boot; a productized image would ship grub-efi + bootupd.
set -euo pipefail

TAG="${1:-v1}"
DISK="${2:-/tmp/hb-disk.img}"
REG=localhost:5000/hb-bootc
WRAP=/tmp/skopeo-wrap
MNT=/mnt/hb-target

# wrappers for host binaries the installer needs (created once)
mkdir -p "$WRAP"
wrap() {
    printf '#!/bin/sh\nexec /host-lib/ld-linux-aarch64.so.1 --library-path /host-lib:/host-lib64 %s "$@"\n' "$2" \
        > "$WRAP/$1"
    chmod +x "$WRAP/$1"
}
for b in skopeo findmnt lsblk blkid fstrim fsfreeze sfdisk podman conmon crun; do
    [ -x "$WRAP/$b" ] || wrap "$b" "/usr/bin/$b.real"
done
[ -x "$WRAP/netavark" ] || wrap netavark /usr/libexec/podman/netavark
# PoC stub: skip bootloader install (qemu direct-kernel verification)
printf '#!/bin/sh\nexit 0\n' > "$WRAP/bootupctl"
chmod +x "$WRAP/bootupctl"

# permissive policy + insecure local registry for the install container
mkdir -p /tmp/containers-cfg
cat > /tmp/containers-cfg/policy.json <<'EOF'
{"default":[{"type":"insecureAcceptAnything"}]}
EOF
cat > /tmp/containers-cfg/registries.conf <<'EOF'
[registries.insecure]
registries = ["localhost:5000"]
EOF
cat > /tmp/containers-cfg/containers.conf <<'EOF'
[engine]
helper_binaries_dir = ["/usr/local/bin/skopeo-dir"]
EOF

# fresh GPT disk: ESP + root, loop-mounted at $MNT
sudo umount "$MNT/boot/efi" 2>/dev/null || true
sudo umount "$MNT" 2>/dev/null || true
sudo losetup -D
sudo rm -f "$DISK"
truncate -s 4G "$DISK"
sudo sfdisk "$DISK" <<'EOF'
label: gpt
name=esp, type=uefi, size=512M
name=root, type=linux
EOF
LOOP=$(sudo losetup -Pf --show "$DISK")
sudo mkfs.vfat -n ESP "${LOOP}p1" >/dev/null
sudo mkfs.ext4 -q -L root "${LOOP}p2"
sudo mount "${LOOP}p2" "$MNT"
sudo mkdir -p "$MNT/boot/efi"
sudo mount "${LOOP}p1" "$MNT/boot/efi"

sudo podman pull --tls-verify=false "$REG:$TAG" >/dev/null

R=""
for b in lsblk blkid findmnt fstrim fsfreeze sfdisk podman conmon crun; do
    R="$R -v /usr/bin/$b:/usr/bin/$b.real:ro"
done

sudo podman run --rm --privileged --pid=host --network=host \
    --security-opt label=disable \
    -v /var/lib/containers:/var/lib/containers \
    -v "$WRAP":/usr/local/bin/skopeo-dir:ro \
    -v /usr/bin/skopeo:/usr/bin/skopeo.real:ro \
    -v /usr/libexec/podman:/usr/libexec/podman:ro \
    $R \
    -v /lib:/host-lib:ro -v /lib64:/host-lib64:ro \
    -v /tmp/containers-cfg:/etc/containers:ro \
    -v /dev:/dev -v "$MNT":/target \
    -e PATH=/usr/local/bin/skopeo-dir:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    "$REG:$TAG" bootc install to-filesystem /target \
    --target-imgref "$REG:$TAG" --disable-selinux

# The deployment's `sysroot` must be a real directory, not the absolute
# `sysroot -> /sysroot` symlink the container-deploy path leaves: with a
# symlink, prepare-root binds the physical root at the *initramfs* /sysroot,
# which busybox switch_root then drops (var.mount ELOOP, bootc can't find
# the sysroot). With a dir, prepare-root binds it inside the deployment
# where it survives switch_root. bootc finalized the target read-only +
# immutable, so undo that first.
sudo mount -o remount,rw "$MNT"
for d in "$MNT"/ostree/deploy/default/deploy/*.0; do
    sudo chattr -i "$d" 2>/dev/null || true
    sudo rm -f "$d/sysroot" 2>/dev/null || true
    sudo mkdir -p "$d/sysroot"
    # chunked (derived-layer) imports drop empty dirs; ostree deployments
    # need the standard runtime mount points
    sudo mkdir -p "$d/dev" "$d/proc" "$d/sys" "$d/boot"
done

# export kernel + initrd for qemu direct-kernel boot, then release the disk
BLS=$(sudo ls "$MNT"/boot/loader.1/entries/ostree-*.conf | head -1)
KV=$(basename "$BLS" .conf) # unused; kernel lives in boot/ostree
BOOTDIR=$(sudo find "$MNT/boot/ostree" -maxdepth 1 -mindepth 1 -type d | head -1)
sudo cp "$BOOTDIR"/vmlinuz-* /tmp/hb-vmlinuz
sudo cp "$BOOTDIR"/initramfs-* /tmp/hb-initramfs.img
sudo grep ^options "$BLS" | sed 's/^options //' | sudo tee /tmp/hb-kargs

sudo umount "$MNT/boot/efi"
sudo umount "$MNT"
sudo losetup -d "$LOOP"
echo "installed: $DISK (kernel+initrd+kargs exported to /tmp/hb-*)"
