#!/usr/bin/env python3
"""Deterministic toy fine-tuning step; replace this with a promoted model job."""
import hashlib, json, pathlib, sys
root=pathlib.Path(__file__).resolve().parents[1]
source=json.loads((root/'v1/model.json').read_text())
source['weight']=source['weight'] + 0.25
out=root/'v2'; out.mkdir(exist_ok=True)
(out/'model.json').write_text(json.dumps(source,separators=(',',':'))+'\n')
digest=hashlib.sha256((out/'model.json').read_bytes()).hexdigest()
(out/'model-manifest.json').write_text(json.dumps({'model':'edge-linear','version':'v2','format':'json-linear','architecture':'aarch64','source_model':'v1','sha256':digest},sort_keys=True,indent=2)+'\n')
(out/'checksums.txt').write_text('%s  model.json\n' % digest)
print('wrote', out, digest)
