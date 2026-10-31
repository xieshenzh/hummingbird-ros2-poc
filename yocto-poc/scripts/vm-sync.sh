#!/usr/bin/env bash
# Sync the yocto-poc tree (kas manifests + our layer) into the Lima VM.
# Build artifacts stay VM-local (native fs); this tree is source-of-truth.
set -euo pipefail
cd "$(dirname "$0")/../.."

limactl cp -r yocto-poc fedora:yocto-poc-sync 2>/dev/null || {
  limactl shell fedora -- rm -rf ~/yocto-poc-sync
  limactl cp -r yocto-poc fedora:yocto-poc-sync
}
limactl shell fedora -- sh -c 'rsync -a --delete ~/yocto-poc-sync/ ~/yocto-poc/ 2>/dev/null || { mkdir -p ~/yocto-poc && cp -r ~/yocto-poc-sync/. ~/yocto-poc/; }; rm -rf ~/yocto-poc-sync'
# kas resolves local layer paths against KAS_WORK_DIR — place our layer there
limactl shell fedora -- sh -c 'mkdir -p ~/yocto/kas-work && rsync -a --delete ~/yocto-poc/meta-hb-bootc/ ~/yocto/kas-work/meta-hb-bootc/'
echo "synced -> fedora:~/yocto-poc + kas-work/meta-hb-bootc"
