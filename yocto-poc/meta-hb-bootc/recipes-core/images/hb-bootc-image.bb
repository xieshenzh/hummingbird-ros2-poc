# Phase 1 target image: minimal + RT kernel + ostree + bootc, with the
# kernel laid out the bootc way (image + initramfs under
# /usr/lib/modules/$kver, BLS entry) instead of Yocto's /boot default.
require recipes-core/images/core-image-minimal.bb

IMAGE_INSTALL:append = " \
    ostree \
    bootc \
    rt-tests \
    kernel-modules \
    util-linux-mount \
    util-linux-umount \
    util-linux-unshare \
"

# Phase 1.5b: under the meta-ros "ros2" distro, bake in the Jazzy ros_core
# closure (same package set ros-image-core installs). Under poky (phase1)
# the override never fires and the image stays the minimal bootc base.
IMAGE_INSTALL:append:ros2 = " ros-core"

# bootc contract pieces assembled at rootfs time:
#  - kernel image at /usr/lib/modules/${KERNEL_VERSION}/vmlinuz
#  - initramfs alongside it
#  - BLS entry in /boot/loader/entries
#  - /usr/lib/ostree/prepare-root.conf enabling the ostree boot path
ROOTFS_POSTPROCESS_COMMAND += "hb_bootc_layout; hb_version_stamp; "

# Phase 2 upgrade marker: the one-file delta between image versions.
# Bump per release; visible as /etc/hb-version on the deployed system.
HB_VERSION ?= "v5"
hb_version_stamp() {
    echo "${HB_VERSION}" > ${IMAGE_ROOTFS}/etc/hb-version
}

hb_bootc_layout() {
    # KERNEL_VERSION is not expanded here — derive it from the modules the
    # kernel recipe already installed into the rootfs
    local kv="$(ls ${IMAGE_ROOTFS}/usr/lib/modules 2>/dev/null | grep -E '^[0-9]' | head -1)"
    [ -n "${kv}" ] || bbfatal "hb_bootc_layout: no kernel version dir in rootfs"
    [ -n "${kv}" ] || bbfatal "no kernel modules dir in rootfs"
    local moddir="${IMAGE_ROOTFS}/usr/lib/modules/${kv}"
    install -d "${moddir}"
    install -m 0644 "${DEPLOY_DIR_IMAGE}/Image-${kv}" "${moddir}/vmlinuz" \
        || install -m 0644 "${DEPLOY_DIR_IMAGE}/Image" "${moddir}/vmlinuz"
    if [ -e "${DEPLOY_DIR_IMAGE}/initramfs-hb-bootc-qemuarm64.cpio.gz" ]; then
        install -m 0644 "${DEPLOY_DIR_IMAGE}/initramfs-hb-bootc-qemuarm64.cpio.gz" \
            "${moddir}/initramfs.img"
    fi
    install -d "${IMAGE_ROOTFS}/boot/loader/entries"
    cat > "${IMAGE_ROOTFS}/boot/loader/entries/hb-bootc-${kv}.conf" <<EOF
title Hummingbird Yocto bootc (linux-yocto-rt)
version ${kv}
linux /usr/lib/modules/${kv}/vmlinuz
initrd /usr/lib/modules/${kv}/initramfs.img
options root=/dev/vda rw console=ttyAMA0
EOF

    # minimal lsinitrd shim: bootc-image-builder inspects the initramfs
    # module list with `lsinitrd --mod ...`; our initramfs is initramfs-
    # framework (not dracut), so report the kernel's builtin modules
    install -d "${IMAGE_ROOTFS}/usr/bin"
    cat > "${IMAGE_ROOTFS}/usr/bin/lsinitrd" <<'EOS'
#!/bin/sh
# PoC shim for bootc-image-builder's initramfs inspection
KV=""
FILE=""
while [ $# -gt 0 ]; do
    case "$1" in
        --kver) KV="$2"; shift 2 ;;
        --mod) shift ;;
        *) FILE="$1"; shift ;;
    esac
done
if [ -n "$KV" ] && [ -f "/usr/lib/modules/$KV/modules.builtin" ]; then
    cat "/usr/lib/modules/$KV/modules.builtin"
fi
exit 0
EOS
    chmod 0755 "${IMAGE_ROOTFS}/usr/bin/lsinitrd"
    install -d "${IMAGE_ROOTFS}/usr/lib/ostree"
    cat > "${IMAGE_ROOTFS}/usr/lib/ostree/prepare-root.conf" <<EOF
[composefs]
enabled = false
[sysroot]
readonly = true
EOF
}
