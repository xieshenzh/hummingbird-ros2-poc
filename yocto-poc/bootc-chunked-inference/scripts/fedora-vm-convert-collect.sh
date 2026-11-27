#!/usr/bin/env bash
# Run on the dedicated Fedora conversion VM.
set -euo pipefail

oci_dir=${1:?usage: $0 <oci-dir> <output-dir> [disk-size]}
output_dir=${2:?usage: $0 <oci-dir> <output-dir> [disk-size]}
test -f "$oci_dir/index.json"
command -v podman >/dev/null
command -v qemu-img >/dev/null

rm -rf "$output_dir"
mkdir -p "$output_dir/boot-assets"
sudo podman pull "oci:$oci_dir" >/dev/null
image_id=$(sudo podman images --no-trunc --format '{{.ID}}' | head -1)
test -n "$image_id"
image_ref="localhost/anomalynet-v3:tekton-$(date -u +%Y%m%d%H%M%S)"
sudo podman tag "$image_id" "$image_ref"

tmp_output=$(mktemp -d)
cleanup() { rm -rf "$tmp_output"; }
trap cleanup EXIT
builder_image=${BOOTC_IMAGE_BUILDER_IMAGE:-quay.io/centos-bootc/bootc-image-builder:latest}
sudo podman pull "$builder_image" >/dev/null
sudo podman run --rm --privileged --pid=host --network=host \
  --security-opt label=disable \
  -v /var/lib/containers:/var/lib/containers \
  -v /run/containers:/run/containers \
  -v /dev:/dev \
  -v "$tmp_output":/output \
  "$builder_image" --type raw --rootfs ext4 \
  --output /output "$image_ref"
raw=$(find "$tmp_output" -type f \( -name '*.raw' -o -name '*.img' \) -print -quit)
test -n "$raw"
cp "$raw" "$output_dir/disk.img"
printf '%s\n' anomalynet-v3 > "$output_dir/release"
printf '%s\n' "$image_ref" > "$output_dir/source-image"
(cd "$output_dir" && sha256sum disk.img > disk.img.sha256)
qemu-img info "$output_dir/disk.img" > "$output_dir/disk.img.qemu-info"

loop=$(sudo losetup --find --show --partscan "$output_dir/disk.img")
cleanup_loop() {
  sudo umount "$output_dir/mnt" 2>/dev/null || true
  sudo losetup -d "$loop" 2>/dev/null || true
}
trap cleanup_loop EXIT
mkdir -p "$output_dir/mnt"
sudo mount "${loop}p3" "$output_dir/mnt"
deploy=$(sudo find "$output_dir/mnt/boot/ostree" -mindepth 1 -maxdepth 1 -type d -print -quit)
test -n "$deploy"
sudo cp "$deploy"/vmlinuz-* "$output_dir/boot-assets/vmlinuz"
sudo cp "$deploy"/initramfs-* "$output_dir/boot-assets/initramfs.img"
sudo sha256sum "$output_dir/boot-assets"/* > "$output_dir/boot-assets/SHA256SUMS"
printf 'conversion=passed\nrelease=anomalynet-v3\n' > "$output_dir/CONVERSION-METADATA"
