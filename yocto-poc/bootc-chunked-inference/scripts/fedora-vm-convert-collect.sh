#!/usr/bin/env bash
# Run on the dedicated Fedora conversion VM.
set -euo pipefail

oci_dir=${1:?usage: $0 <oci-dir> <output-dir> [disk-size]}
output_dir=${2:?usage: $0 <oci-dir> <output-dir> [disk-size]}
test -f "$oci_dir/index.json"
command -v podman >/dev/null
for tool in podman qemu-img sfdisk mkfs.vfat mkfs.ext4 losetup mount umount find; do
  command -v "$tool" >/dev/null
done

rm -rf "$output_dir"
mkdir -p "$output_dir/boot-assets"
sudo podman pull "oci:$oci_dir" >/dev/null
image_id=$(sudo podman images --no-trunc --format '{{.ID}}' | head -1)
test -n "$image_id"
image_ref="localhost/anomalynet-v3:tekton-$(date -u +%Y%m%d%H%M%S)"
sudo podman tag "$image_id" "$image_ref"

disk_size=${3:-4G}
truncate -s "$disk_size" "$output_dir/disk.img"
mkdir -p "$output_dir/mnt"
sfdisk "$output_dir/disk.img" <<'EOF'
label: gpt
start=2048,size=2048,type=21686148-6449-6E6F-744E-656564454649,name=bios
size=524288,type=uefi,name=esp
type=linux,name=root
EOF

loop=$(sudo losetup --find --show --partscan "$output_dir/disk.img")
cleanup_loop() {
  sudo umount "$output_dir/mnt/boot/efi" 2>/dev/null || true
  sudo umount "$output_dir/mnt" 2>/dev/null || true
  sudo losetup -d "$loop" 2>/dev/null || true
}
trap cleanup_loop EXIT
sudo mkfs.vfat -n ESP "${loop}p2" >/dev/null
sudo mkfs.ext4 -q -L root "${loop}p3"
sudo mount "${loop}p3" "$output_dir/mnt"
sudo mkdir -p "$output_dir/mnt/boot/efi"
sudo mount "${loop}p2" "$output_dir/mnt/boot/efi"

# Use the native bootc installer path proven on the Fedora conversion VM. The
# generic bootc-image-builder does not recognize this chunked bootc image even
# though bootc container lint accepts it.
sudo podman run --rm --privileged --pid=host --network=host \
  --security-opt label=disable \
  -v /var/lib/containers/storage:/var/lib/containers/storage \
  -v /run/containers/storage:/run/containers/storage \
  -v /dev:/dev \
  -v "$output_dir/mnt":/target \
  --entrypoint bootc "$image_ref" install to-filesystem /target \
  --target-imgref "$image_ref" --disable-selinux

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
