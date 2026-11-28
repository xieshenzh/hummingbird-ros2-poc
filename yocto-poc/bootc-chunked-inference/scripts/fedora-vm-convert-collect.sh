#!/usr/bin/env bash
# Run on the dedicated Fedora conversion VM.
set -euo pipefail

oci_dir=${1:?usage: $0 <oci-dir> <output-dir> [disk-size]}
output_dir=${2:?usage: $0 <oci-dir> <output-dir> [disk-size]}
output_dir=$(readlink -f "$output_dir")
target_path=/target/anomalynet-v3
test -f "$oci_dir/index.json"
command -v podman >/dev/null
for tool in podman qemu-img sfdisk mkfs.vfat mkfs.ext4 losetup mount umount mountpoint nsenter find python3; do
  command -v "$tool" >/dev/null
done
if ! command -v skopeo >/dev/null; then
  command -v dnf >/dev/null
  sudo dnf install -y skopeo >/dev/null
fi
if ! command -v bootc >/dev/null; then
  command -v dnf >/dev/null
  sudo dnf install -y bootc >/dev/null
fi

# bootc probes prepare-root.conf in the encapsulated base layer before it
# imports later derived layers. Patch the transferred OCI layout directly,
# matching assemble-chunked-bootc.py, rather than adding an ignored image layer.
python3 - "$oci_dir" <<'PY'
import gzip, hashlib, io, json, sys, tarfile
from pathlib import Path

oci = Path(sys.argv[1])
blobs = oci / "blobs" / "sha256"
index_path = oci / "index.json"
index = json.loads(index_path.read_text())
entry = index["manifests"][0]
manifest_path = blobs / entry["digest"].split(":", 1)[1]
manifest = json.loads(manifest_path.read_text())
layer = manifest["layers"][0]
layer_path = blobs / layer["digest"].split(":", 1)[1]
raw = layer_path.read_bytes()
plain = gzip.decompress(raw) if "gzip" in layer.get("mediaType", "") else raw
probe = "usr/lib/ostree/prepare-root.conf"
with tarfile.open(fileobj=io.BytesIO(plain), mode="r:") as archive:
    members = archive.getmembers()
    if probe not in {m.name.rstrip("/") for m in members}:
        rebuilt = io.BytesIO()
        with tarfile.open(fileobj=rebuilt, mode="w") as output:
            for member in members:
                payload = archive.extractfile(member) if member.isfile() else None
                output.addfile(member, payload)
            names = {m.name.rstrip("/") for m in members}
            for directory in ("usr", "usr/lib", "usr/lib/ostree"):
                if directory not in names:
                    output.addfile(tarfile.TarInfo(directory + "/"))
            content = b"[composefs]\nenabled = false\n[sysroot]\nreadonly = true\n"
            info = tarfile.TarInfo(probe)
            info.mode, info.size = 0o644, len(content)
            output.addfile(info, io.BytesIO(content))
        plain = rebuilt.getvalue()
        compressed = gzip.compress(plain, mtime=0) if "gzip" in layer.get("mediaType", "") else plain
        new_layer_digest = "sha256:" + hashlib.sha256(compressed).hexdigest()
        (blobs / new_layer_digest.split(":", 1)[1]).write_bytes(compressed)
        layer.update(digest=new_layer_digest, size=len(compressed))
        config_path = blobs / manifest["config"]["digest"].split(":", 1)[1]
        config = json.loads(config_path.read_text())
        config["rootfs"]["diff_ids"][0] = "sha256:" + hashlib.sha256(plain).hexdigest()
        config_bytes = json.dumps(config, separators=(",", ":")).encode()
        config_digest = "sha256:" + hashlib.sha256(config_bytes).hexdigest()
        (blobs / config_digest.split(":", 1)[1]).write_bytes(config_bytes)
        manifest["config"].update(digest=config_digest, size=len(config_bytes))
        manifest_bytes = json.dumps(manifest, separators=(",", ":")).encode()
        manifest_digest = "sha256:" + hashlib.sha256(manifest_bytes).hexdigest()
        (blobs / manifest_digest.split(":", 1)[1]).write_bytes(manifest_bytes)
        entry.update(digest=manifest_digest, size=len(manifest_bytes))
        index_path.write_text(json.dumps(index, indent=2) + "\n")
PY

unmount_stale_target() {
  sudo umount -R -l "$target_path" 2>/dev/null || true
  sudo nsenter -t 1 -m -- umount -R -l "$target_path" 2>/dev/null || true
  sudo umount -R -l "$output_dir/mnt" 2>/dev/null || true
  sudo nsenter -t 1 -m -- umount -R -l "$output_dir/mnt" 2>/dev/null || true
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
# bootc re-execs in the VM's init mount namespace. Mount there explicitly so
# the target remains visible after that re-exec rather than only in the SSH
# session's mount namespace.
sudo mkdir -p "$target_path"
sudo nsenter -t 1 -m -- mkdir -p "$target_path"
if ! sudo mountpoint -q "$output_dir/mnt"; then
  sudo mount "${loop}p3" "$output_dir/mnt"
fi
sudo mkdir -p "$output_dir/mnt/boot/efi"
if ! sudo mountpoint -q "$output_dir/mnt/boot/efi"; then
  sudo mount "${loop}p2" "$output_dir/mnt/boot/efi"
fi
if ! sudo mountpoint -q "$target_path"; then
  sudo mount --bind "$output_dir/mnt" "$target_path"
fi
sudo nsenter -t 1 -m -- mkdir -p "$target_path"
sudo nsenter -t 1 -m -- sh -c 'mountpoint -q "$1" || mount "$2" "$1"' sh \
  "$output_dir/mnt" "${loop}p3"
sudo nsenter -t 1 -m -- mkdir -p "$output_dir/mnt/boot/efi"
sudo nsenter -t 1 -m -- sh -c 'mountpoint -q "$1" || mount "$2" "$1"' sh \
  "$output_dir/mnt/boot/efi" "${loop}p2"
sudo nsenter -t 1 -m -- sh -c 'mountpoint -q "$1" || mount --bind "$2" "$1"' sh \
  "$target_path" "$output_dir/mnt"

# Run bootc directly on the Fedora conversion VM. The host process already
# owns the mounted target, avoiding the container-to-host mount namespace gap.
sudo bootc install to-filesystem "$output_dir/mnt" \
  --source-imgref "containers-storage:$image_ref" \
  --target-transport containers-storage --target-imgref "$image_ref" \
  --disable-selinux

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
