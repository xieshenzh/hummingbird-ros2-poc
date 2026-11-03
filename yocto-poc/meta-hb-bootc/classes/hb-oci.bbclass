# hb-oci.bbclass — image type "oci": wrap the finished rootfs into a
# single-layer OCI image with buildah (daemonless; no Dockerfile, no
# docker daemon), modeled on meta-virtualization's docker image class.
#
# Usage (image recipe or local.conf):
#   IMAGE_CLASSES += "hb-oci"
#   IMAGE_FSTYPES += "oci"
# Result: ${IMGDEPLOYDIR}/${IMAGE_NAME}.oci (OCI layout directory)
# with the bootc labels set.
#
# Requires buildah on the build host PATH (HB_OCI_BUILDAH to override).
# NOTE: runs inside the image task's fakeroot environment; if the
# pseudo/buildah interaction misbehaves on your host, set
# HB_OCI_FAKEROOT = "" and arrange privileges accordingly. This wiring
# has not yet been exercised by a full bake — the equivalent flow
# (rootfs tar -> podman import) is what produced the tested images.

IMAGE_TYPES += "oci"
IMAGE_CMD:oci = "hb_oci_build"

HB_OCI_BUILDAH ?= "buildah"
HB_OCI_LABELS ?= "ostree.bootable=1 containers.bootc=1"

hb_oci_build() {
    set -euo pipefail
    command -v ${HB_OCI_BUILDAH} >/dev/null 2>&1 \
        || bbfatal "hb-oci: ${HB_OCI_BUILDAH} not found in PATH (install buildah on the build host or set HB_OCI_BUILDAH)"

    local out="${IMGDEPLOYDIR}/${IMAGE_NAME}.oci"
    rm -rf "$out"

    local ctr="$(${HB_OCI_BUILDAH} from scratch)"
    local mnt="$(${HB_OCI_BUILDAH} mount "$ctr")"
    cp -a "${IMAGE_ROOTFS}/." "$mnt/"
    ${HB_OCI_BUILDAH} unmount "$ctr"

    local lbl args=""
    for lbl in ${HB_OCI_LABELS}; do
        args="$args --label ${lbl}"
    done
    ${HB_OCI_BUILDAH} config $args "$ctr"
    # oci: transport writes an OCI layout directory
    ${HB_OCI_BUILDAH} push "$ctr" "oci:${out}:${IMAGE_BASENAME}"
    ${HB_OCI_BUILDAH} rm "$ctr"
    echo "hb-oci: wrote $out"
}
