# hb-bootc.bbclass — make an image recipe produce a bootc-bootable rootfs.
#
# Everything here runs at rootfs time (ROOTFS_POSTPROCESS_COMMAND), so the
# shape fixes apply to every artifact: tarball, plain container, chunked
# container, ext4.
#
# Bootc contract pieces:
#  - kernel image at /usr/lib/modules/$kver/vmlinuz + initramfs alongside
#  - BLS entry in /boot/loader/entries
#  - /usr/lib/ostree/prepare-root.conf enabling the ostree boot path
#  - /opt -> /usr/opt (bootc-standard usr layout; ostree-ext's
#    derived-layer tar filter drops non-usr/etc/var toplevels)
#  - no hardlink groups (chunkah may split a group across layers and
#    ostree's per-layer import then fails on the far-side link)
#  - /etc/hb-version stamp (the one-file delta between image versions)

ROOTFS_POSTPROCESS_COMMAND += "hb_bootc_layout; hb_bootc_usr_layout; hb_deref_hardlinks; hb_version_stamp; "

# Phase 2 upgrade marker. Bump per release; visible as /etc/hb-version
# on the deployed system. NOTE: changing this does not reliably
# invalidate do_rootfs (sstate stamp quirk) — iterate with
# `bitbake -C rootfs <image>`.
HB_VERSION ?= "v5"
hb_version_stamp() {
    echo "${HB_VERSION}" > ${IMAGE_ROOTFS}/etc/hb-version
}

hb_bootc_layout() {
    # KERNEL_VERSION is not expanded here — derive it from the modules the
    # kernel recipe already installed into the rootfs
    local kv="$(ls ${IMAGE_ROOTFS}/usr/lib/modules 2>/dev/null | grep -E '^[0-9]' | head -1)"
    [ -n "${kv}" ] || bbfatal "hb_bootc_layout: no kernel version dir in rootfs"
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

hb_bootc_usr_layout() {
    if [ -d ${IMAGE_ROOTFS}/opt ] && [ ! -L ${IMAGE_ROOTFS}/opt ]; then
        install -d ${IMAGE_ROOTFS}/usr
        mv ${IMAGE_ROOTFS}/opt ${IMAGE_ROOTFS}/usr/opt
        ln -s usr/opt ${IMAGE_ROOTFS}/opt
    fi
}

hb_deref_hardlinks() {
    find ${IMAGE_ROOTFS} -xdev -type f -links +1 | while read -r f; do
        cp -p "$f" "$f.hb-deref" && mv "$f.hb-deref" "$f"
    done
}
