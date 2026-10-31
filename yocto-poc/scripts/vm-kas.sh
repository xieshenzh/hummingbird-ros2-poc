#!/usr/bin/env bash
# Run kas inside the Lima VM against a manifest in ~/yocto-poc.
# Usage: vm-kas.sh build kas/phase0.yaml
set -euo pipefail
CMD="${1:?usage: vm-kas.sh <build|shell> <manifest>}"
MANIFEST="${2:-kas/phase0.yaml}"

limactl shell fedora -- bash -lc "
  source ~/venvs/kas/bin/activate
  cd ~/yocto-poc
  export KAS_WORK_DIR=\$HOME/yocto/kas-work
  mkdir -p \$KAS_WORK_DIR
  kas ${CMD} ${MANIFEST}
"
