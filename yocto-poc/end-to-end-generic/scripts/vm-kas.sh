#!/usr/bin/env bash
# Run KAS for this standalone setup inside the prepared Lima VM.
set -euo pipefail

CMD=${1:?usage: vm-kas.sh <build|shell> [manifest]}
MANIFEST=${2:-end-to-end-generic/kas/chunked-bootc-qemuarm64.yaml}

limactl shell fedora -- bash -lc "
    source ~/venvs/kas/bin/activate
    cd ~/yocto-poc
    export KAS_WORK_DIR=\${CHUNKED_KAS_WORK_DIR:-\$HOME/yocto/kas-work-generic}
    mkdir -p \"\$KAS_WORK_DIR\"
    kas ${CMD} ${MANIFEST}
"
