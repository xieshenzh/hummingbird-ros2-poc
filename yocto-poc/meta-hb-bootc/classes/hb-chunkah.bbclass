# hb-chunkah.bbclass — re-split an image rootfs into content-based OCI
# layers with chunkah, and optionally assemble the bootc-installable
# hybrid (encapsulated base commit + chunks as derived layers).
#
# Usage (image recipe or local.conf):
#   IMAGE_CLASSES += "hb-chunkah"
#   HB_CHUNKED_HYBRID = "1"     # also build the bootc hybrid
# Results in ${IMGDEPLOYDIR}:
#   ${IMAGE_BASENAME}-chunked.oci   chunkah output (plain chunks)
#   ${IMAGE_BASENAME}-base.oci      encapsulated base layer (hybrid only)
#   ${IMAGE_BASENAME}-hybrid.oci    bootc-installable image (hybrid only)
#
# Tunables:
#   HB_CHUNKAH                 chunkah command (default "chunkah"; wrap a
#                              containerized run here if needed)
#   HB_CHUNKED_MAX_LAYERS      chunk count cap (default 32)
#   HB_CHUNKED_LABELS          labels carried into the chunked image
#   HB_HYBRID_BASE_SYMLINKS    compat symlinks baked into the base commit
#                              ("name:target" pairs; defaults cover both
#                              usrmerge depths, incl. lib64)
#   HB_HYBRID_BASE_MOUNTPOINTS dirs ensured in the base commit (ostree
#                              cannot store empty dirs -> .hb-keep
#                              placeholders, shadowed by runtime mounts)
#
# Requires chunkah on the build host PATH; the hybrid additionally needs
# ostree and ostree-encap. NOT yet exercised by a full bake — the
# identical command sequence produced the tested v4k/v5k images.

HB_CHUNKAH ?= "chunkah"
HB_CHUNKED_MAX_LAYERS ?= "32"
HB_CHUNKED_HYBRID ?= "0"
HB_CHUNKED_LABELS ?= "ostree.bootable=1 containers.bootc=1"
HB_HYBRID_BASE_SYMLINKS ?= "bin:usr/bin sbin:usr/sbin lib:usr/lib lib64:usr/lib64 opt:usr/opt root:var/root home:var/home srv:var/srv ostree:sysroot/ostree"
HB_HYBRID_BASE_MOUNTPOINTS ?= "dev proc sys boot run tmp"
HB_HYBRID_BASE_REF ?= "hb/bootc/base"
HB_OSTREE ?= "ostree"
HB_OSTREE_ENCAP ?= "${HOME}/ostree-encap/target/release/ostree-encap"
# assembler ships with the layer (meta-hb-bootc/scripts/). ${FILE} would
# resolve to the inheriting recipe — LAYERDIR is the class's own layer.
HB_CHUNKED_ASSEMBLE ?= "${HB_LAYERDIR}/scripts/assemble-chunked-bootc.py"

addtask image_chunk after do_rootfs before do_image
# chunkah reads the pseudo-owned rootfs and must record root:root in the
# layer tars — run it under fakeroot
do_image_chunk[fakeroot] = "1"
do_image_chunk[dirs] = "${IMGDEPLOYDIR}"
do_image_chunk() {
    set -euo pipefail
    command -v ${HB_CHUNKAH} >/dev/null 2>&1 \
        || bbfatal "hb-chunkah: ${HB_CHUNKAH} not found in PATH (install chunkah on the build host or set HB_CHUNKAH)"

    # chunkah --config expects the .Config element of a podman inspect
    local cfg="${WORKDIR}/hb-chunkah-config.json"
    python3 - "$cfg" "${HB_CHUNKED_LABELS}" <<'PY'
import json, sys
labels = dict(l.split("=", 1) for l in sys.argv[2].split())
json.dump({"Labels": labels, "Env": []}, open(sys.argv[1], "w"))
PY

    local out="${IMGDEPLOYDIR}/${IMAGE_BASENAME}-chunked.oci"
    rm -rf "$out"
    ${HB_CHUNKAH} build --rootfs "${IMAGE_ROOTFS}" \
        --max-layers ${HB_CHUNKED_MAX_LAYERS} \
        --config "$cfg" \
        -o "oci:${out}"
}

# The hybrid assembly runs ostree/ostree-encap on scratch dirs and the
# chunkah output — no pseudo needed, and ostree aborts under pseudo — so
# it is a separate, non-fakeroot task.
addtask image_hybrid after do_image_chunk before do_image
do_image_hybrid[dirs] = "${IMGDEPLOYDIR}"
do_image_hybrid() {
    set -euo pipefail
    [ "${HB_CHUNKED_HYBRID}" = "1" ] || return 0

    command -v ${HB_OSTREE} >/dev/null 2>&1 || bbfatal "hb-chunkah: ostree not found"
    [ -x "${HB_OSTREE_ENCAP}" ] || bbfatal "hb-chunkah: ostree-encap not found at ${HB_OSTREE_ENCAP} (set HB_OSTREE_ENCAP)"
    [ -d "${IMGDEPLOYDIR}/${IMAGE_BASENAME}-chunked.oci" ] || bbfatal "hb-chunkah: chunked output missing (did do_image_chunk run?)"

    # encapsulated near-empty base commit carrying exactly what the
    # derived-layer import drops (see journal Phase 3 for the why)
    local tree="${WORKDIR}/hb-base-tree" repo="${WORKDIR}/hb-base-repo"
    local base="${IMGDEPLOYDIR}/${IMAGE_BASENAME}-base.oci"
    rm -rf "$tree" "$repo" "$base"
    mkdir -p "$tree"
    local pair name target
    for pair in ${HB_HYBRID_BASE_SYMLINKS}; do
        name="${pair%%:*}"
        target="${pair#*:}"
        ln -sfn "$target" "$tree/$name"
    done
    local d
    for d in ${HB_HYBRID_BASE_MOUNTPOINTS}; do
        mkdir -p "$tree/$d"
        touch "$tree/$d/.hb-keep"
    done
    ${HB_OSTREE} init --repo="$repo" --mode=archive
    ${HB_OSTREE} commit --repo="$repo" --branch=${HB_HYBRID_BASE_REF} --tree=dir="$tree"
    ${HB_OSTREE_ENCAP} "$repo" ${HB_HYBRID_BASE_REF} "oci:${base}:base"

    local hyb="${IMGDEPLOYDIR}/${IMAGE_BASENAME}-hybrid.oci"
    rm -rf "$hyb"
    python3 "${HB_CHUNKED_ASSEMBLE}" "${IMGDEPLOYDIR}/${IMAGE_BASENAME}-chunked.oci" "" "$base" "$hyb" "${IMAGE_BASENAME}"
}
