#!/usr/bin/env bash
# Run on the dedicated Fedora conversion VM.
set -euo pipefail

oci_dir=${1:?usage: $0 <oci-dir> <output-dir> [disk-size]}
output_dir=${2:?usage: $0 <oci-dir> <output-dir> [disk-size]}
output_dir=$(readlink -f "$output_dir")
test -f "$oci_dir/index.json"
command -v podman >/dev/null
for tool in podman qemu-img sfdisk mkfs.vfat mkfs.ext4 losetup mount umount mountpoint find; do
  command -v "$tool" >/dev/null
done
if ! command -v skopeo >/dev/null; then
  command -v dnf >/dev/null
  sudo dnf install -y skopeo >/dev/null
fi
wrap_dir=/var/tmp/anomalynet-bootc-wrap
containers_cfg=/var/tmp/anomalynet-bootc-containers-cfg
host_loader=/host-lib64/ld-linux-x86-64.so.2
mkdir -p "$wrap_dir" "$containers_cfg"
wrap_host_tool() {
  printf '#!/bin/sh\nexec %s --library-path /host-lib:/host-lib64 %s "$@"\n' \
    "$host_loader" "$2" > "$wrap_dir/$1"
  chmod +x "$wrap_dir/$1"
}
for tool in skopeo findmnt lsblk blkid fstrim fsfreeze sfdisk podman conmon crun; do
  wrap_host_tool "$tool" "/usr/bin/$tool.real"
done
wrap_host_tool netavark /usr/libexec/podman/netavark
printf '#!/bin/sh\nexit 0\n' > "$wrap_dir/bootupctl"
chmod +x "$wrap_dir/bootupctl"
cat > "$containers_cfg/policy.json" <<'EOF'
{"default":[{"type":"insecureAcceptAnything"}]}
EOF
cat > "$containers_cfg/registries.conf" <<'EOF'
[[registry]]
location = "localhost:5000"
insecure = true
EOF
cat > "$containers_cfg/containers.conf" <<'EOF'
[engine]
helper_binaries_dir = ["/usr/local/bin/skopeo-dir"]
EOF

unmount_stale_target() {
  sudo umount -R -l "$output_dir/mnt" 2>/dev/null || true
}
unmount_stale_target
if ! sudo rm -rf "$output_dir" 2>/dev/null; then
  stale_dir="${output_dir}.stale-$(date -u +%Y%m%d%H%M%S)"
  sudo mv "$output_dir" "$stale_dir"
fi
sudo rm -rf "$output_dir"
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
  unmount_stale_target
  sudo losetup -d "$loop" 2>/dev/null || true
}
trap cleanup_loop EXIT
sudo mkfs.vfat -n ESP "${loop}p2" >/dev/null
sudo mkfs.ext4 -q -L root "${loop}p3"
sudo mount "${loop}p3" "$output_dir/mnt"
sudo mkdir -p "$output_dir/mnt/boot/efi"
sudo mount "${loop}p2" "$output_dir/mnt/boot/efi"

host_tools=""
for tool in lsblk blkid findmnt fstrim fsfreeze sfdisk podman conmon crun; do
  host_tools="$host_tools -v /usr/bin/$tool:/usr/bin/$tool.real:ro"
done
sudo podman run --rm --privileged --pid=host --network=host \
  --security-opt label=disable \
  -v /var/lib/containers:/var/lib/containers \
  -v "$wrap_dir":/usr/local/bin/skopeo-dir:ro \
  -v /usr/bin/skopeo:/usr/bin/skopeo.real:ro \
  -v /usr/libexec/podman:/usr/libexec/podman:ro \
  $host_tools \
  -v /lib:/host-lib:ro -v /lib64:/host-lib64:ro \
  -v "$containers_cfg":/etc/containers:ro \
  -v /dev:/dev -v "$output_dir/mnt":/target \
  -e PATH=/usr/local/bin/skopeo-dir:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
  "$image_ref" bootc install to-filesystem /target \
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
