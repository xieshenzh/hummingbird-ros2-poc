#!/usr/bin/env bash
# Run on the separate Fedora host that launches the deployment QEMU VM.
set -euo pipefail

artifact_dir=${1:?usage: $0 <artifact-dir> [target-disk]}
target=${2:-/dev/nvme1n1}
raw="$artifact_dir/disk.img"
kernel="$artifact_dir/boot-assets/vmlinuz"
initrd="$artifact_dir/boot-assets/initramfs.img"
test -s "$raw"; test -s "$kernel"; test -s "$initrd"

root_source=$(findmnt -rn -o SOURCE /)
case "$root_source" in
  /dev/nvme0n1p3*) ;;
  *) echo "refusing host root $root_source" >&2; exit 2;;
esac
test -b "$target"
test -z "$(findmnt -rn -S "$target" -o TARGET || true)"
for part in "${target}p1" "${target}p2" "${target}p3"; do
  test -z "$(findmnt -rn -S "$part" -o TARGET || true)"
done

sudo dd if="$raw" of="$target" bs=16M conv=fsync status=progress
sudo blockdev --rereadpt "$target" 2>/dev/null || true
sudo sgdisk -e "$target" >/dev/null
sudo sgdisk --verify "$target" >/dev/null
sudo udevadm settle
echo "deployment_write=passed target=$target"

# The deployment VM supplies this driver because its QEMU console setup is
# environment-specific. It must execute stdin as root in the guest and return
# the guest command's exit status.
driver=${SERIAL_DRIVER:-/usr/local/sbin/serial-console-exec}
test -x "$driver"
"$driver" --disk "$target" --kernel "$kernel" --initrd "$initrd" <<'GUEST'
set -e
cat /etc/chunked-bootc-version
uname -a | grep -q PREEMPT_RT
wget -qO- http://127.0.0.1:8080/healthz
wget -qO- http://127.0.0.1:8090/healthz
wget -qO- http://127.0.0.1:8090/status
wget -qO- http://127.0.0.1:8080/version
normal=$(wget -qO- --header='Content-Type: application/json' --post-data='{"samples":[50,50,50,50,50,50,50,50,50,50,50,50,50,50,50,50,50,50,50,50,50,50,50,50,50,50,50,50,50,50,50,50]}' http://127.0.0.1:8080/infer)
anomaly=$(wget -qO- --header='Content-Type: application/json' --post-data='{"samples":[50,50,50,50,50,50,50,50,50,50,50,50,110,110,110,110,110,110,110,110,110,110,110,110,110,110,110,110,110,110,110,110]}' http://127.0.0.1:8080/infer)
printf '%s\n' "$normal" | grep -q '"classification":"normal"'
printf '%s\n' "$anomaly" | grep -q '"classification":"anomaly"'
GUEST
