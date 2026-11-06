# chunked-bootc-chunkah.bbclass — re-split an image rootfs into content-based OCI
# layers with chunkah, and optionally assemble the bootc-installable
# hybrid (encapsulated base commit + chunks as derived layers).
#
# Usage (image recipe or local.conf):
#   IMAGE_CLASSES += "chunked-bootc-chunkah"
#   CHUNKED_BOOTC_HYBRID = "1"     # also build the bootc hybrid
# Results in ${IMGDEPLOYDIR}:
#   ${IMAGE_BASENAME}-chunked.oci   chunkah output (plain chunks)
#   ${IMAGE_BASENAME}-base.oci      encapsulated base layer (hybrid only)
#   ${IMAGE_BASENAME}-hybrid.oci    bootc-installable image (hybrid only)
#
# Tunables:
#   CHUNKED_BOOTC_CHUNKAH                 chunkah command (default "chunkah"; wrap a
#                              containerized run here if needed)
#   CHUNKED_BOOTC_MAX_LAYERS      chunk count cap (default 32)
#   CHUNKED_BOOTC_LABELS          labels carried into the chunked image
#   CHUNKED_BOOTC_BASE_SYMLINKS    compat symlinks baked into the base commit
#                              ("name:target" pairs; defaults cover both
#                              usrmerge depths, incl. lib64)
#   CHUNKED_BOOTC_BASE_MOUNTPOINTS dirs ensured in the base commit (ostree
#                              cannot store empty dirs -> placeholder files
#                              placeholders, shadowed by runtime mounts)
#
# Requires chunkah on the build host PATH; the hybrid additionally needs
# ostree and ostree-encap. Validated end-to-end by the v6/v7 builds
# (kas/phase3.yaml in this folder) — see ../../docs/journal.md
# "Phase 3 end-to-end".

CHUNKED_BOOTC_CHUNKAH ?= "chunkah"
CHUNKED_BOOTC_MAX_LAYERS ?= "32"
CHUNKED_BOOTC_HYBRID ?= "0"
CHUNKED_BOOTC_LABELS ?= "ostree.bootable=1 containers.bootc=1"
CHUNKED_BOOTC_BASE_SYMLINKS ?= "bin:usr/bin sbin:usr/sbin lib:usr/lib lib64:usr/lib64 opt:usr/opt root:var/root home:var/home srv:var/srv ostree:sysroot/ostree"
CHUNKED_BOOTC_BASE_MOUNTPOINTS ?= "dev proc sys boot run tmp"
CHUNKED_BOOTC_BASE_REF ?= "chunked-bootc/base"
CHUNKED_BOOTC_OSTREE ?= "ostree"
CHUNKED_BOOTC_OSTREE_ENCAP ?= "ostree-encap"
# assembler ships with this layer. ${FILE} would
# resolve to the inheriting recipe — the layerdir capture in this layer's
# conf/layer.conf is the class's own location.
CHUNKED_BOOTC_ASSEMBLE ?= "${CHUNKED_BOOTC_LAYERDIR}/scripts/assemble-chunked-bootc.py"

addtask chunked_bootc_chunk after do_rootfs before do_image
# chunkah reads the pseudo-owned rootfs and must record root:root in the
# layer tars — run it under fakeroot
do_chunked_bootc_chunk[fakeroot] = "1"
do_chunked_bootc_chunk[dirs] = "${IMGDEPLOYDIR}"
do_chunked_bootc_chunk[vardeps] += "CHUNKED_BOOTC_CHUNKAH CHUNKED_BOOTC_MAX_LAYERS CHUNKED_BOOTC_LABELS"
do_chunked_bootc_chunk() {
    set -euo pipefail
    command -v ${CHUNKED_BOOTC_CHUNKAH} >/dev/null 2>&1 \
        || bbfatal "chunked-bootc: ${CHUNKED_BOOTC_CHUNKAH} not found in PATH (install chunkah on the build host or set CHUNKED_BOOTC_CHUNKAH)"

    # chunkah --config expects the .Config element of a podman inspect
    local cfg="${WORKDIR}/chunked-bootc-chunkah-config.json"
    python3 - "$cfg" "${CHUNKED_BOOTC_LABELS}" <<'PY'
import json, sys
labels = dict(l.split("=", 1) for l in sys.argv[2].split())
json.dump({"Labels": labels, "Env": []}, open(sys.argv[1], "w"))
PY

    local out="${IMGDEPLOYDIR}/${IMAGE_BASENAME}-chunked.oci"
    rm -rf "$out"
    ${CHUNKED_BOOTC_CHUNKAH} build --rootfs "${IMAGE_ROOTFS}" \
        --max-layers ${CHUNKED_BOOTC_MAX_LAYERS} \
        --config "$cfg" \
        -o "oci:${out}"
}

# The hybrid assembly runs ostree/ostree-encap on scratch dirs and the
# chunkah output — no pseudo needed, and ostree aborts under pseudo — so
# it is a separate, non-fakeroot task.
addtask chunked_bootc_hybrid after do_chunked_bootc_chunk before do_image
do_chunked_bootc_hybrid[dirs] = "${IMGDEPLOYDIR}"
do_chunked_bootc_hybrid[vardeps] += "CHUNKED_BOOTC_HYBRID CHUNKED_BOOTC_BASE_REF CHUNKED_BOOTC_BASE_SYMLINKS CHUNKED_BOOTC_BASE_MOUNTPOINTS CHUNKED_BOOTC_OSTREE CHUNKED_BOOTC_OSTREE_ENCAP CHUNKED_BOOTC_ASSEMBLE"
do_chunked_bootc_hybrid() {
    set -euo pipefail
    [ "${CHUNKED_BOOTC_HYBRID}" = "1" ] || return 0

    command -v ${CHUNKED_BOOTC_OSTREE} >/dev/null 2>&1 || bbfatal "chunked-bootc: ostree not found"
    command -v ${CHUNKED_BOOTC_OSTREE_ENCAP} >/dev/null 2>&1 || bbfatal "chunked-bootc: ${CHUNKED_BOOTC_OSTREE_ENCAP} not found in PATH"
    [ -d "${IMGDEPLOYDIR}/${IMAGE_BASENAME}-chunked.oci" ] || bbfatal "chunked-bootc: chunked output missing (did do_chunked_bootc_chunk run?)"

    # encapsulated near-empty base commit carrying exactly what the
    # derived-layer import drops (see journal Phase 3 for the why)
    local tree="${WORKDIR}/chunked-bootc-base-tree" repo="${WORKDIR}/chunked-bootc-base-repo"
    local base="${IMGDEPLOYDIR}/${IMAGE_BASENAME}-base.oci"
    rm -rf "$tree" "$repo" "$base"
    mkdir -p "$tree"
    local pair name target
    for pair in ${CHUNKED_BOOTC_BASE_SYMLINKS}; do
        name="${pair%%:*}"
        target="${pair#*:}"
        ln -sfn "$target" "$tree/$name"
    done
    local d
    for d in ${CHUNKED_BOOTC_BASE_MOUNTPOINTS}; do
        mkdir -p "$tree/$d"
        touch "$tree/$d/.chunked-bootc-keep"
    done
    ${CHUNKED_BOOTC_OSTREE} init --repo="$repo" --mode=archive
    ${CHUNKED_BOOTC_OSTREE} commit --repo="$repo" --branch=${CHUNKED_BOOTC_BASE_REF} --tree=dir="$tree"
    ${CHUNKED_BOOTC_OSTREE_ENCAP} "$repo" ${CHUNKED_BOOTC_BASE_REF} "oci:${base}:base"

    local hyb="${IMGDEPLOYDIR}/${IMAGE_BASENAME}-hybrid.oci"
    rm -rf "$hyb"
    python3 "${CHUNKED_BOOTC_ASSEMBLE}" "${IMGDEPLOYDIR}/${IMAGE_BASENAME}-chunked.oci" "" "$base" "$hyb" "${IMAGE_BASENAME}"
}
