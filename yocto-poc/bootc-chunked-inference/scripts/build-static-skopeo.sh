#!/bin/bash
# Build the static ARM64 Skopeo helper required by bootc's registry importer.
# The output is deliberately outside the source tree: it is a build input,
# not an application payload or a model release.
set -euo pipefail

OUT=${1:-/tmp/chunked-bootc-skopeo-static}
SRC=${2:-/tmp/chunked-bootc-skopeo-src}
REV=${SKOPEO_REV:-v1.24.1}

if [ ! -d "$SRC/.git" ]; then
    rm -rf "$SRC"
    git clone --depth 1 --branch "$REV" https://github.com/containers/skopeo "$SRC"
fi

cd "$SRC"
CGO_ENABLED=0 go build -tags containers_image_openpgp -trimpath -o "$OUT" ./cmd/skopeo
file "$OUT"
