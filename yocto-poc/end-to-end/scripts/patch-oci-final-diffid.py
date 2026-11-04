#!/usr/bin/env python3
"""Patch an OCI layout's ostree.final-diffid label to match its last layer.

chunkah rewrites an image into content-based layers but keeps the source
config verbatim — including the ostree.final-diffid label an
ostree-encap-wrapped bootc image carries. That label names the original
single layer's diffID, which no longer exists in the chunked layer stack,
and bootc's fetch validation then rejects the image ("Missing
ostree.final-diffid sha256:...").

Fix: set the label to config.rootfs.diff_ids[-1] (the last layer), which
is what bootc's check compares against, and rewrite config + manifest
digests. Usage: patch-oci-final-diffid.py <oci-dir> <tag>
"""
import hashlib
import json
import sys
from pathlib import Path

oci = Path(sys.argv[1])
tag = sys.argv[2]
blobs = oci / "blobs" / "sha256"


def blob(digest):
    return json.loads((blobs / digest).read_bytes())


def write_blob(obj):
    data = json.dumps(obj, separators=(",", ":")).encode()
    digest = hashlib.sha256(data).hexdigest()
    (blobs / digest).write_bytes(data)
    return digest, len(data)


index = json.loads((oci / "index.json").read_bytes())
for entry in index["manifests"]:
    if entry.get("annotations", {}).get("org.opencontainers.image.ref.name", "").endswith(":" + tag):
        break
else:
    sys.exit(f"tag {tag!r} not found in index.json")

manifest = blob(entry["digest"].split(":", 1)[1])
config = blob(manifest["config"]["digest"].split(":", 1)[1])

final = config["rootfs"]["diff_ids"][-1]
labels = config["config"].setdefault("Labels", {})
old = labels.get("ostree.final-diffid")
labels["ostree.final-diffid"] = final

cd, cs = write_blob(config)
manifest["config"]["digest"] = "sha256:" + cd
manifest["config"]["size"] = cs
md, ms = write_blob(manifest)
entry["digest"] = "sha256:" + md
entry["size"] = ms
(oci / "index.json").write_bytes(json.dumps(index).encode())
print(f"ostree.final-diffid: {old} -> {final}")
