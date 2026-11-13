# chunked-bootc-oci.bbclass — image type "oci": wrap the finished rootfs into a
# single-layer OCI image with buildah (daemonless; no Dockerfile, no
# docker daemon).
#
# Usage (image recipe or local.conf):
#   IMAGE_CLASSES += "chunked-bootc-oci"
#   IMAGE_FSTYPES += "oci"
# Result: ${IMGDEPLOYDIR}/${IMAGE_BASENAME}.oci (OCI layout directory)
# with the bootc labels set.
#
# Requires buildah on the build host PATH (CHUNKED_BOOTC_BUILDAH to override).

IMAGE_TYPES += "oci"
IMAGE_CMD:oci = "chunked_bootc_oci_build"
# bitbake disables networking (and drops the task into a single-mapping
# user namespace) for any task without a `network` flag — rootless
# buildah cannot create its own user namespace from inside that. The
# flag itself doesn't grant network access we don't use; it just keeps
# the task in the initial user namespace.
do_image_oci[network] = "1"

CHUNKED_BOOTC_BUILDAH ?= "buildah"
CHUNKED_BOOTC_OCI_LABELS ?= "ostree.bootable=1 containers.bootc=1"
# "oci" = OCI layout directory, "oci-archive" = single-file archive
CHUNKED_BOOTC_OUTPUT_TYPE ?= "oci"

chunked_bootc_oci_build() {
    set -euo pipefail
    command -v ${CHUNKED_BOOTC_BUILDAH} >/dev/null 2>&1 \
        || bbfatal "chunked-bootc-oci: ${CHUNKED_BOOTC_BUILDAH} not found in PATH (install buildah on the build host or set CHUNKED_BOOTC_BUILDAH)"

    local out="${IMGDEPLOYDIR}/${IMAGE_BASENAME}.${CHUNKED_BOOTC_OUTPUT_TYPE}"
    rm -rf "$out"
    if [ "${CHUNKED_BOOTC_OUTPUT_TYPE}" = "oci" ]; then
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
    local img="chunked-bootc-oci-${IMAGE_BASENAME}"
    local run="env -u LD_PRELOAD PATH=/usr/bin:/bin PSEUDO_DISABLED=1"
    local ctr="$($run ${CHUNKED_BOOTC_BUILDAH} from scratch)"
    $run ${CHUNKED_BOOTC_BUILDAH} add "$ctr" "${IMAGE_ROOTFS}"

    local lbl args=""
    for lbl in ${CHUNKED_BOOTC_OCI_LABELS}; do
        args="$args --label ${lbl}"
    done
    $run ${CHUNKED_BOOTC_BUILDAH} config $args "$ctr"
    # scratch containers can't be pushed directly — commit to an image
    $run ${CHUNKED_BOOTC_BUILDAH} commit "$ctr" "$img" >/dev/null
    $run ${CHUNKED_BOOTC_BUILDAH} push "$img" "$out"
    $run ${CHUNKED_BOOTC_BUILDAH} rm "$ctr" >/dev/null
    $run ${CHUNKED_BOOTC_BUILDAH} rmi "$img" >/dev/null
    echo "chunked-bootc-oci: wrote ${IMGDEPLOYDIR}/${IMAGE_BASENAME}.${CHUNKED_BOOTC_OUTPUT_TYPE}"
}
