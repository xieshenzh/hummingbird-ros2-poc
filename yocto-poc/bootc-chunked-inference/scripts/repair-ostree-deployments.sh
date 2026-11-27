#!/usr/bin/env bash
# Repair the deployment-local mount points required by the Yocto initramfs.
#
# bootc 1.1.x can leave a fresh deployment with no `sysroot` entry (or with
# the absolute /sysroot symlink). The initramfs runs ostree-prepare-root
# before busybox switch_root, so the deployment must contain a real directory
# at this location. This helper is intended for the host-side Phase 5 disk
# conversion boundary, not for use inside the immutable guest.
#
# Usage:
#   sudo repair-ostree-deployments.sh [--check] <mounted-root>
set -euo pipefail

check_only=false
if [[ "${1:-}" == "--check" ]]; then
    check_only=true
    shift
fi

mount_root=${1:?usage: $0 [--check] <mounted-root>}
mount_root=$(readlink -f "$mount_root")

if ! mountpoint -q "$mount_root"; then
    printf 'error: %s is not a mounted filesystem\n' "$mount_root" >&2
    exit 2
fi

deploy_root="$mount_root/ostree/deploy/default/deploy"
if [[ ! -d "$deploy_root" ]]; then
    printf 'error: missing OSTree deployment root: %s\n' "$deploy_root" >&2
    exit 2
fi

shopt -s nullglob
deployments=("$deploy_root"/*.0)
if ((${#deployments[@]} == 0)); then
    printf 'error: no OSTree deployments found below %s\n' "$deploy_root" >&2
    exit 2
fi

for deployment in "${deployments[@]}"; do
    sysroot="$deployment/sysroot"
    if $check_only; then
        [[ -d "$sysroot" && ! -L "$sysroot" ]] || {
            printf 'error: deployment is missing a real sysroot directory: %s\n' "$sysroot" >&2
            exit 1
        }
        continue
    fi

    # OSTree deployments are immutable after installation. Only remove the
    # immutable bit on the exact deployment directory selected above.
    chattr -i "$deployment" 2>/dev/null || true
    rm -f "$sysroot"
    mkdir -p "$sysroot" "$deployment/dev" "$deployment/proc" \
        "$deployment/sys" "$deployment/boot"
done

"$0" --check "$mount_root"
printf 'OSTree deployment repair validated: %d deployment(s)\n' "${#deployments[@]}"
