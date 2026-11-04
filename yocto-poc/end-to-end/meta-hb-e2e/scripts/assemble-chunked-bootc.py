#!/usr/bin/env python3
"""Assemble a bootc-1.1.0-installable chunked OCI image.

bootc 1.1.0's ostree-ext accepts exactly this layout (see
ostree-rs-ext container/store.rs parse_manifest_layout):
  - the layer named by the ostree.final-diffid label ("target") is
    unencapsulated as the base ostree commit — it must be an
    ostree-repo tar, NOT a plain rootfs tar
  - layers BEFORE the target (other than layer 0) are imported as
    ostree object-store chunks
  - layers AFTER the target are imported as DERIVED plain-tar layers
    (the Docker-compatible path)

So a chunkah output (plain-rootfs chunks) is turned installable by
prepending a tiny encapsulated EMPTY ostree commit as layer 0 and
pointing the label at it: chunkah's chunks then all land in the
derived-layer path and reconstruct the rootfs on top of the empty base.

Usage: assemble-chunked-bootc.py <chunked-oci-dir> <chunked-tag> <base-oci-dir> <out-oci-dir> <out-tag>
  <chunked-oci-dir>/<tag>: chunkah-built OCI (plain chunks)
  <base-oci-dir>: OCI containing the empty-commit encapsulated layer
"""
import hashlib
import json
import shutil
import sys
from pathlib import Path


def load_blob(blobs, digest):
    return json.loads((blobs / digest.split(":", 1)[1]).read_bytes())


def raw_blob(blobs, digest):
    return (blobs / digest.split(":", 1)[1]).read_bytes()


def write_blob(blobs, data):
    digest = "sha256:" + hashlib.sha256(data).hexdigest()
    (blobs / digest.split(":", 1)[1]).write_bytes(data)
    return digest, len(data)


def manifest_of(oci, tag_suffix):
    index = json.loads((oci / "index.json").read_bytes())
    for entry in index["manifests"]:
        ref = entry.get("annotations", {}).get("org.opencontainers.image.ref.name", "")
        if ref.endswith(":" + tag_suffix) or ref == tag_suffix:
            return load_blob(oci / "blobs" / "sha256", entry["digest"]), entry
    if len(index["manifests"]) == 1:
        return load_blob(oci / "blobs" / "sha256", index["manifests"][0]["digest"]), index["manifests"][0]
    sys.exit(f"tag {tag_suffix!r} not found in {oci}/index.json")


chunked_dir, chunked_tag, base_dir, out_dir, out_tag = sys.argv[1:6]
chunked_dir, base_dir, out_dir = Path(chunked_dir), Path(base_dir), Path(out_dir)

c_manifest, _ = manifest_of(chunked_dir, chunked_tag)
c_blobs = chunked_dir / "blobs" / "sha256"
c_config = load_blob(c_blobs, c_manifest["config"]["digest"])

b_manifest, _ = manifest_of(base_dir, "base")
b_blobs = base_dir / "blobs" / "sha256"

# layer 0 = the encapsulated empty-commit base layer
base_layer = b_manifest["layers"][0]
base_blob = raw_blob(b_blobs, base_layer["digest"])
base_uncompressed = base_blob
if "gzip" in base_layer.get("mediaType", ""):
    import gzip
    base_uncompressed = gzip.decompress(base_blob)
base_diffid = "sha256:" + hashlib.sha256(base_uncompressed).hexdigest()

# sanity: the base OCI's config should agree on the diffid
b_config = load_blob(b_blobs, b_manifest["config"]["digest"])
assert b_config["rootfs"]["diff_ids"] == [base_diffid], "base diffid mismatch"

# assemble: base layer first, then all chunkah chunks (derived path)
layers = [dict(base_layer)] + [dict(l) for l in c_manifest["layers"]]
diff_ids = [base_diffid] + list(c_config["rootfs"]["diff_ids"])

config = dict(c_config)
config["rootfs"]["diff_ids"] = diff_ids
# layers_with_history() requires one history entry per layer
config.setdefault("history", []).insert(
    0, {"created_by": "encapsulated empty ostree base commit"})
labels = config["config"].setdefault("Labels", {})
labels["ostree.final-diffid"] = base_diffid
labels["ostree.bootable"] = "1"
labels["containers.bootc"] = "1"

if out_dir.exists():
    shutil.rmtree(out_dir)
shutil.copytree(chunked_dir, out_dir, dirs_exist_ok=True)
out_blobs = out_dir / "blobs" / "sha256"

# copy the base layer blob in
base_digest = base_layer["digest"]
(out_blobs / base_digest.split(":", 1)[1]).write_bytes(base_blob)

cd, cs = write_blob(out_blobs, json.dumps(config, separators=(",", ":")).encode())
manifest = dict(c_manifest)
manifest["layers"] = layers
manifest["config"] = {"digest": cd, "size": cs,
                      "mediaType": c_manifest["config"].get(
                          "mediaType", "application/vnd.oci.image.config.v1+json")}
manifest.setdefault("mediaType", "application/vnd.oci.image.manifest.v1+json")
manifest.setdefault("schemaVersion", 2)
md, ms = write_blob(out_blobs, json.dumps(manifest, separators=(",", ":")).encode())

index = {"schemaVersion": 2,
         "mediaType": "application/vnd.oci.image.index.v1+json",
         "manifests": [{"mediaType": manifest["mediaType"], "digest": md, "size": ms,
                        "annotations": {"org.opencontainers.image.ref.name": out_tag}}]}
(out_dir / "index.json").write_bytes(json.dumps(index).encode())
print(f"assembled {out_dir} tag {out_tag}: 1 base + {len(layers)-1} chunk layers")
print(f"ostree.final-diffid -> {base_diffid} (empty-commit base)")
