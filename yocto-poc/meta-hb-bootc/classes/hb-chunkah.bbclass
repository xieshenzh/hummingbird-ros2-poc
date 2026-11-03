# hb-chunkah.bbclass — re-split the image rootfs into content-based
# layers with chunkah, and (optionally) assemble the bootc-installable
# hybrid image (encapsulated base commit + chunks as derived layers).
#
# Usage (image recipe or local.conf):
#   IMAGE_CLASSES += "hb-chunkah"
#   # optional, needs ostree + ostree-encap on the build host:
#   HB_CHUNKED_HYBRID = "1"
# Results in ${IMGDEPLOYDIR}:
#   ${IMAGE_NAME}-chunked.oci   chunkah output (plain chunks)
#   ${IMAGE_NAME}-hybrid.oci    bootc-1.1.0-installable hybrid (if enabled)
#
# Requires chunkah on the build host PATH (HB_CHUNKAH to override; e.g.
# `podman run ... chunkah` wrapper). Runs after do_rootfs, before the
# image type commands, so it sees the final rootfs (all hb-bootc shape
# fixes applied). NOTE: this wiring has not yet been exercised by a full
# bake — the identical command sequence is what produced the tested
# v4k/v5k images via yocto-poc/scripts/.

HB_CHUNKAH ?= "chunkah"
HB_CHUNKED_MAX_LAYERS ?= "32"
HB_CHUNKED_HYBRID ?= "0"
HB_CHUNKED_LABELS ?= "ostree.bootable=1 containers.bootc=1"
# assembler ships with the layer (meta-hb-bootc/scripts/)
HB_CHUNKED_ASSEMBLE ?= "${@os.path.join(os.path.dirname(d.getVar('FILE')), '..', 'scripts', 'assemble-chunked-bootc.py')}"
HB_OSTREE ?= "ostree"
HB_OSTREE_ENCAP ?= "${HOME}/ostree-encap/target/release/ostree-encap"

addtask image_chunk after do_rootfs before do_image
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

    local out="${IMGDEPLOYDIR}/${IMAGE_NAME}-chunked.oci"
    rm -rf "$out"
    ${HB_CHUNKAH} build --rootfs "${IMAGE_ROOTFS}" \
        --max-layers ${HB_CHUNKED_MAX_LAYERS} \
        --config "$cfg" \
        -o "oci:${out}"

    if [ "${HB_CHUNKED_HYBRID}" = "1" ]; then
        command -v ${HB_OSTREE} >/dev/null 2>&1 || bbfatal "hb-chunkah: ostree not found"
        [ -x "${HB_OSTREE_ENCAP}" ] || bbfatal "hb-chunkah: ostree-encap not found at ${HB_OSTREE_ENCAP} (set HB_OSTREE_ENCAP)"

        # encapsulated near-empty base commit: compat symlinks + mountpoint
        # placeholders (see build-encap-base.sh / journal Phase 3)
        local tree="${WORKDIR}/hb-base-tree" repo="${WORKDIR}/hb-base-repo"
        local base="${IMGDEPLOYDIR}/${IMAGE_NAME}-base.oci"
        rm -rf "$tree" "$repo" "$base"
        mkdir -p "$tree"
        ln -sfn usr/bin "$tree/bin"
        ln -sfn usr/lib "$tree/lib"
        ln -sfn usr/sbin "$tree/sbin"
        ln -sfn usr/opt "$tree/opt"
        ln -sfn var/root "$tree/root"
        ln -sfn var/home "$tree/home"
        ln -sfn var/srv "$tree/srv"
        ln -sfn sysroot/ostree "$tree/ostree"
        local d
        for d in dev proc sys boot run tmp; do
            mkdir -p "$tree/$d"
            touch "$tree/$d/.hb-keep"
        done
        ${HB_OSTREE} init --repo="$repo" --mode=archive
        ${HB_OSTREE} commit --repo="$repo" --branch=hb/bootc/base --tree=dir="$tree" --quiet
        ${HB_OSTREE_ENCAP} "$repo" hb/bootc/base "oci:${base}:base"

        local hyb="${IMGDEPLOYDIR}/${IMAGE_NAME}-hybrid.oci"
        rm -rf "$hyb"
        python3 "${HB_CHUNKED_ASSEMBLE}" "$out" "" "$base" "$hyb" "${IMAGE_BASENAME}"
    fi
}
