# hb-oci.bbclass — image type "oci": wrap the finished rootfs into a
# single-layer OCI image with buildah (daemonless; no Dockerfile, no
# docker daemon).
#
# Usage (image recipe or local.conf):
#   IMAGE_CLASSES += "hb-oci"
#   IMAGE_FSTYPES += "oci"
# Result: ${IMGDEPLOYDIR}/${IMAGE_BASENAME}.oci (OCI layout directory)
# with the bootc labels set.
#
# Requires buildah on the build host PATH (HB_OCI_BUILDAH to override).

IMAGE_TYPES += "oci"
IMAGE_CMD:oci = "hb_oci_build"
# bitbake disables networking (and drops the task into a single-mapping
# user namespace) for any task without a `network` flag — rootless
# buildah cannot create its own user namespace from inside that. The
# flag itself doesn't grant network access we don't use; it just keeps
# the task in the initial user namespace.
do_image_oci[network] = "1"

HB_OCI_BUILDAH ?= "buildah"
HB_OCI_LABELS ?= "ostree.bootable=1 containers.bootc=1"
# "oci" = OCI layout directory, "oci-archive" = single-file archive
HB_OCI_OUTPUT_TYPE ?= "oci"

hb_oci_build() {
    set -euo pipefail
    command -v ${HB_OCI_BUILDAH} >/dev/null 2>&1 \
        || bbfatal "hb-oci: ${HB_OCI_BUILDAH} not found in PATH (install buildah on the build host or set HB_OCI_BUILDAH)"

    local out="${IMGDEPLOYDIR}/${IMAGE_BASENAME}.${HB_OCI_OUTPUT_TYPE}"
    rm -rf "$out"
    if [ "${HB_OCI_OUTPUT_TYPE}" = "oci" ]; then
        out="oci:${out}:${IMAGE_BASENAME}"
    else
        out="oci-archive:${out}:${IMAGE_BASENAME}"
    fi

    # buildah must run outside the fakeroot context: pseudo's
    # LD_PRELOAD breaks buildah's user-namespace reexec, its fake passwd
    # (PSEUDO_PASSWD) breaks user lookup, and recipe-sysroot-native's
    # non-setuid newuidmap breaks the uid mapping. A clean PATH and no
    # LD_PRELOAD gives rootless buildah its normal behavior; rootless
    # buildah maps the build user's files to container root, and
    # `buildah add <dir>` copies the directory's CONTENTS into / (docker
    # COPY semantics).
    local img="hb-oci-${IMAGE_BASENAME}"
    local run="env -u LD_PRELOAD PATH=/usr/bin:/bin PSEUDO_DISABLED=1"
    local ctr="$($run ${HB_OCI_BUILDAH} from scratch)"
    $run ${HB_OCI_BUILDAH} add "$ctr" "${IMAGE_ROOTFS}"

    local lbl args=""
    for lbl in ${HB_OCI_LABELS}; do
        args="$args --label ${lbl}"
    done
    $run ${HB_OCI_BUILDAH} config $args "$ctr"
    # scratch containers can't be pushed directly — commit to an image
    $run ${HB_OCI_BUILDAH} commit "$ctr" "$img" >/dev/null
    $run ${HB_OCI_BUILDAH} push "$img" "$out"
    $run ${HB_OCI_BUILDAH} rm "$ctr" >/dev/null
    $run ${HB_OCI_BUILDAH} rmi "$img" >/dev/null
    echo "hb-oci: wrote ${IMGDEPLOYDIR}/${IMAGE_BASENAME}.${HB_OCI_OUTPUT_TYPE}"
}
