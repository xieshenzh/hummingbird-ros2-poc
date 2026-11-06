#!/usr/bin/env bash
# Synchronize only this standalone setup into the prepared Lima VM.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
REMOTE_SYNC=~/yocto-poc/end-to-end-generic-sync

limactl cp -r "$ROOT" "fedora:${REMOTE_SYNC#~/}" 2>/dev/null || {
    limactl shell fedora -- rm -rf "$REMOTE_SYNC"
    limactl cp -r "$ROOT" "fedora:${REMOTE_SYNC#~/}"
}
limactl shell fedora -- bash -lc '
    mkdir -p ~/yocto-poc/end-to-end-generic ~/yocto/kas-work-generic
    rsync -a --delete ~/yocto-poc/end-to-end-generic-sync/ ~/yocto-poc/end-to-end-generic/
    rsync -a --delete ~/yocto-poc/end-to-end-generic/meta-chunked-bootc/ ~/yocto/kas-work-generic/meta-chunked-bootc/
    rm -rf ~/yocto-poc/end-to-end-generic-sync
'
echo "synced -> fedora:~/yocto-poc/end-to-end-generic + kas-work-generic/meta-chunked-bootc"
