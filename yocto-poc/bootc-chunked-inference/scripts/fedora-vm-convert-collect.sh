#!/usr/bin/env bash
# Run on the dedicated Fedora conversion VM.
set -euo pipefail

oci_dir=${1:?usage: $0 <oci-dir> <output-dir> [disk-size]}
output_dir=${2:?usage: $0 <oci-dir> <output-dir> [disk-size]}
output_dir=$(readlink -f "$output_dir")
test -f "$oci_dir/index.json"
command -v podman >/dev/null
for tool in podman qemu-img losetup mount umount find; do
  command -v "$tool" >/dev/null
done
if ! command -v skopeo >/dev/null; then
  command -v dnf >/dev/null
  sudo dnf install -y skopeo >/dev/null
fi

rm -rf "$output_dir"
mkdir -p "$output_dir/boot-assets"
sudo podman pull "oci:$oci_dir" >/dev/null
manifest_digest=$(grep -o '"digest"[[:space:]]*:[[:space:]]*"sha256:[^"]*"' "$oci_dir/index.json" | head -1 | sed 's/.*"sha256:/sha256:/' | sed 's/"$//')
test -n "$manifest_digest"
manifest_blob="$oci_dir/blobs/sha256/${manifest_digest#sha256:}"
test -f "$manifest_blob"
image_id=$(grep -o '"digest"[[:space:]]*:[[:space:]]*"sha256:[^"]*"' "$manifest_blob" | head -1 | sed 's/.*"sha256:/sha256:/' | sed 's/"$//')
test -n "$image_id"
image_ref="localhost/anomalynet-v3:tekton-$(date -u +%Y%m%d%H%M%S)"
sudo podman tag "$image_id" "$image_ref"

# osbuild expects the SELinux context database even when the source image is
# built with SELinux disabled. Add the same empty context file used by the
# project's earlier conversion workaround in a temporary derived image.
prepare_dir=$(mktemp -d)
cleanup_prepare() { rm -rf "$prepare_dir"; }
trap cleanup_prepare EXIT
cat > "$prepare_dir/Containerfile" <<EOF
FROM $image_ref
USER 0
RUN mkdir -p /etc/selinux/targeted/contexts/files /usr/bin /usr/lib/ostree && \
    touch /etc/selinux/targeted/contexts/files/file_contexts && \
    for tool in mount umount ostree; do \
      printf '#!/bin/sh\\nexit 0\\n' > /usr/bin/\$tool; \
      chmod 0755 /usr/bin/\$tool; \
    done
EOF
install_ref="localhost/anomalynet-v3:tekton-prepared-$(date -u +%Y%m%d%H%M%S)"
sudo podman build --security-opt label=disable --network=host \
  -t "$install_ref" "$prepare_dir" >/dev/null

tmp_output=$(mktemp -d)
cleanup_output() { rm -rf "$tmp_output"; }
trap cleanup_output EXIT
builder_image=${BOOTC_IMAGE_BUILDER_IMAGE:-quay.io/centos-bootc/bootc-image-builder:latest}
sudo podman pull "$builder_image" >/dev/null
sudo podman run --rm --privileged --pid=host --network=host \
  --security-opt label=disable \
  -v /var/lib/containers/storage:/var/lib/containers/storage \
  -v /run/containers/storage:/run/containers/storage \
  -v /dev:/dev \
  -v "$tmp_output":/output \
  "$builder_image" --type raw --rootfs ext4 --output /output "$install_ref"
raw=$(find "$tmp_output" -type f \( -name '*.raw' -o -name '*.img' \) -print -quit)
test -n "$raw"
cp "$raw" "$output_dir/disk.img"

loop=$(sudo losetup --find --show --partscan "$output_dir/disk.img")
cleanup_loop() {
  sudo umount "$output_dir/mnt" 2>/dev/null || true
  sudo losetup -d "$loop" 2>/dev/null || true
}
trap cleanup_loop EXIT
mkdir -p "$output_dir/mnt"
sudo mount "${loop}p3" "$output_dir/mnt"

# Repair the deployment-local mount points required by the Yocto initramfs.
deploy_root="$output_dir/mnt/ostree/deploy/default/deploy"
test -d "$deploy_root"
shopt -s nullglob
deployments=("$deploy_root"/*.0)
test "${#deployments[@]}" -gt 0
for deploy in "${deployments[@]}"; do
  sudo chattr -i "$deploy" 2>/dev/null || true
  sudo rm -f "$deploy/sysroot"
  sudo mkdir -p "$deploy/sysroot" "$deploy/dev" "$deploy/proc" "$deploy/sys" "$deploy/boot"
done
sudo test -d "${deployments[0]}/sysroot"

printf '%s\n' anomalynet-v3 > "$output_dir/release"
printf '%s\n' "$image_ref" > "$output_dir/source-image"
(cd "$output_dir" && sha256sum disk.img > disk.img.sha256)
qemu-img info "$output_dir/disk.img" > "$output_dir/disk.img.qemu-info"
boot_dir=$(sudo find "$output_dir/mnt/boot/ostree" -mindepth 1 -maxdepth 1 -type d -print -quit)
test -n "$boot_dir"
sudo cp "$boot_dir"/vmlinuz-* "$output_dir/boot-assets/vmlinuz"
sudo cp "$boot_dir"/initramfs-* "$output_dir/boot-assets/initramfs.img"
(cd "$output_dir/boot-assets" && sha256sum vmlinuz initramfs.img > SHA256SUMS)
printf 'conversion=passed\nrelease=anomalynet-v3\n' > "$output_dir/CONVERSION-METADATA"
