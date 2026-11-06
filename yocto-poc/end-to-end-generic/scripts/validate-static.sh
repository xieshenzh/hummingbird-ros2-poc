#!/usr/bin/env bash
# Static validation for the standalone Yocto layer. No build artifacts are
# modified and no external project files are required.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

python3 -m py_compile meta-chunked-bootc/scripts/assemble-chunked-bootc.py
for f in meta-chunked-bootc/classes/*.bbclass; do
    grep -q 'CHUNKED_BOOTC_' "$f"
done
grep -q 'meta-chunked-bootc' kas/chunked-bootc-qemuarm64.yaml
grep -q 'generic-chunked-bootc-image' kas/chunked-bootc-qemuarm64.yaml
grep -q 'IMAGE_CLASSES.*chunked-bootc' meta-chunked-bootc/recipes-core/images/generic-chunked-bootc-image.bb

if grep -RInE '/home/[^/]+|hb-bootc|HB_[A-Z_]+|meta-hb|HB_E2E' \
    --exclude=README.md --exclude=validate-static.sh --exclude-dir=.git .; then
    echo "generic setup contains project-specific references" >&2
    exit 1
fi

echo "standalone static validation: PASS"
