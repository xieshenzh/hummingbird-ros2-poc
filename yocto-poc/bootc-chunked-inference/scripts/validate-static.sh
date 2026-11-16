#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
python3 -m py_compile models/training/train-model.py \
  models/training/finetune-anomalynet.py \
  meta-chunked-bootc/scripts/compare-oci-layers.py \
  meta-chunked-bootc/recipes-inference/edge-inference-service/files/edge-inference.py
python3 - <<'PY'
import hashlib, json
from pathlib import Path
for version in ('v1', 'v2', 'anomalynet-v1', 'anomalynet-v2'):
    root = Path('models') / version
    manifest = json.loads((root / 'model-manifest.json').read_text())
    assert manifest['version'] == version
    assert manifest['sha256'] == hashlib.sha256((root / 'model.json').read_bytes()).hexdigest()
print('model release validation: PASS')
PY
grep -q 'generic-inference-bootc-image' kas/bootc-chunked-inference-qemuarm64.yaml
grep -q 'chunked-bootc-chunkah' meta-chunked-bootc/recipes-core/images/generic-inference-bootc-image.bb
echo 'static validation: PASS'
