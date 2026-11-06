#!/usr/bin/env bash
# Validate the generated artifact set and optionally run the VM runtime checks.
# Artifact construction itself remains a BitBake responsibility.
set -euo pipefail

DEPLOY_DIR=${1:?usage: validate-e2e.sh <deploy-dir> [tag] [registry]}
TAG=${2:-v1}
REGISTRY=${3:-localhost:5000/generic-chunked-bootc}
IMAGE=generic-chunked-bootc-image

for artifact in \
    "$DEPLOY_DIR/${IMAGE}.oci" \
    "$DEPLOY_DIR/${IMAGE}-chunked.oci" \
    "$DEPLOY_DIR/${IMAGE}-base.oci" \
    "$DEPLOY_DIR/${IMAGE}-hybrid.oci"; do
    [ -d "$artifact" ] || { echo "missing OCI artifact: $artifact" >&2; exit 1; }
done

command -v skopeo >/dev/null 2>&1 || {
    echo "skopeo is required to publish the hybrid artifact" >&2
    exit 1
}
skopeo copy "oci:${DEPLOY_DIR}/${IMAGE}-hybrid.oci" \
    "docker://${REGISTRY}:${TAG}"

echo "artifact validation: PASS"
echo "published: ${REGISTRY}:${TAG}"
echo "next: install-bootc-image.sh ${TAG} /tmp/chunked-bootc-disk.img ${REGISTRY}"
