# chunked-bootc.bbclass — make any image recipe produce a bootc-bootable rootfs.
#
# Runs entirely at rootfs time (ROOTFS_POSTPROCESS_COMMAND), so the shape
# applies to every artifact: tarball, plain container, chunked container,
# ext4. Inheritable by any image (minimal, ros, custom).
#
# What it guarantees (the bootc/ostree container contract):
#  - kernel + initramfs at /usr/lib/modules/$kver/{vmlinuz,initramfs.img}
#  - BLS entry in /boot/loader/entries
#  - /usr/lib/ostree/prepare-root.conf (ostree boot path)
#  - /opt -> /usr/opt (ostree-ext's derived-layer tar filter drops
#    non-usr/etc/var toplevels; see journal Phase 3)
#  - no hardlink groups (chunkers split groups across layers; ostree's
#    per-layer import then fails on the far-side link)
#  - /etc/${CHUNKED_BOOTC_VERSION_FILE} stamp for version deltas
#
# Tunables (all have working defaults):
#   CHUNKED_BOOTC_VERSION               version stamp written to the configured file
#   CHUNKED_BOOTC_TITLE           BLS entry title
#   CHUNKED_BOOTC_KARGS      kernel args in the BLS entry
#   CHUNKED_BOOTC_LSINITRD_SHIM install the bootc-image-builder shim (default 1)
#
# Kernel image and initramfs are discovered from the deploy dir: the
# machine's KERNEL_IMAGETYPE for the kernel, and ${INITRAMFS_IMAGE}
# (if set) for the initramfs — no machine names hardcoded.

ROOTFS_POSTPROCESS_COMMAND += "chunked_bootc_layout; chunked_bootc_usr_layout; chunked_bootc_deref_hardlinks; chunked_bootc_container_cfg; chunked_bootc_version_stamp; "

# These values change the generated rootfs and must invalidate do_rootfs. This
# is important for version-only upgrade images: serving the previous rootfs
# from sstate would make the upgrade test vacuous.
do_rootfs[vardeps] += "CHUNKED_BOOTC_VERSION CHUNKED_BOOTC_VERSION_FILE CHUNKED_BOOTC_TITLE CHUNKED_BOOTC_KARGS CHUNKED_BOOTC_CONTAINER_CFG CHUNKED_BOOTC_INSECURE_REGISTRIES CHUNKED_BOOTC_SKOPEO_STATIC"

CHUNKED_BOOTC_TITLE ?= "Generic bootc"
CHUNKED_BOOTC_KARGS ?= "root=/dev/vda rw"
CHUNKED_BOOTC_LSINITRD_SHIM ?= "1"
CHUNKED_BOOTC_VERSION_FILE ?= "chunked-bootc-version"
# container-runtime config baked into the image (bootc overlays
# /etc/containers at install time; the guest needs permissive policy +
# the build/test registries preconfigured to pull updates)
CHUNKED_BOOTC_CONTAINER_CFG ?= "1"
CHUNKED_BOOTC_INSECURE_REGISTRIES ?= "localhost:5000 10.0.2.2:5000"
# optional static skopeo copied into the image for bootc's pull path
CHUNKED_BOOTC_SKOPEO_STATIC ?= ""

# NOTE: changing CHUNKED_BOOTC_VERSION does not reliably invalidate do_rootfs
# (sstate stamp quirk) — iterate with `bitbake -C rootfs <image>`.
CHUNKED_BOOTC_VERSION ?= "v1"

chunked_bootc_version_stamp() {
    echo "${CHUNKED_BOOTC_VERSION}" > ${IMAGE_ROOTFS}/etc/${CHUNKED_BOOTC_VERSION_FILE}
}

chunked_bootc_layout() {
    local kv="$(ls ${IMAGE_ROOTFS}/usr/lib/modules 2>/dev/null | grep -E '^[0-9]' | head -1)"
    [ -n "${kv}" ] || bbfatal "chunked_bootc_layout: no kernel version dir in rootfs"

    # kernel image: the machine's KERNEL_IMAGETYPE, versioned or bare
    local kimg="${DEPLOY_DIR_IMAGE}/${KERNEL_IMAGETYPE}-${kv}"
    [ -e "${kimg}" ] || kimg="${DEPLOY_DIR_IMAGE}/${KERNEL_IMAGETYPE}"
    [ -e "${kimg}" ] || bbfatal "chunked_bootc_layout: no ${KERNEL_IMAGETYPE} in ${DEPLOY_DIR_IMAGE}"

    # initramfs: from INITRAMFS_IMAGE if the image sets one
    local initrd=""
    if [ -n "${INITRAMFS_IMAGE}" ]; then
        initrd="$(ls ${DEPLOY_DIR_IMAGE}/${INITRAMFS_IMAGE}-*${MACHINE}*.cpio.gz 2>/dev/null | head -1)"
        [ -n "${initrd}" ] || initrd="$(ls ${DEPLOY_DIR_IMAGE}/${INITRAMFS_IMAGE}*.cpio.gz 2>/dev/null | head -1)"
    fi

    local moddir="${IMAGE_ROOTFS}/usr/lib/modules/${kv}"
    install -d "${moddir}"
    install -m 0644 "${kimg}" "${moddir}/vmlinuz"
    [ -n "${initrd}" ] && install -m 0644 "${initrd}" "${moddir}/initramfs.img"

    install -d "${IMAGE_ROOTFS}/boot/loader/entries"
    {
        echo "title ${CHUNKED_BOOTC_TITLE}"
        echo "version ${kv}"
        echo "linux /usr/lib/modules/${kv}/vmlinuz"
        [ -n "${initrd}" ] && echo "initrd /usr/lib/modules/${kv}/initramfs.img"
        echo "options ${CHUNKED_BOOTC_KARGS}"
    } > "${IMAGE_ROOTFS}/boot/loader/entries/chunked-bootc-${kv}.conf"

    if [ "${CHUNKED_BOOTC_LSINITRD_SHIM}" = "1" ]; then
        # bootc-image-builder inspects the initramfs with `lsinitrd
        # --mod ...`; initramfs-framework images aren't dracut, so
        # report the kernel's builtin modules instead
        install -d "${IMAGE_ROOTFS}/usr/bin"
        cat > "${IMAGE_ROOTFS}/usr/bin/lsinitrd" <<'EOS'
#!/bin/sh
KV=""
while [ $# -gt 0 ]; do
    case "$1" in
        --kver) KV="$2"; shift 2 ;;
        *) shift ;;
    esac
done
if [ -n "$KV" ] && [ -f "/usr/lib/modules/$KV/modules.builtin" ]; then
    cat "/usr/lib/modules/$KV/modules.builtin"
fi
exit 0
EOS
        chmod 0755 "${IMAGE_ROOTFS}/usr/bin/lsinitrd"
    fi

    install -d "${IMAGE_ROOTFS}/usr/lib/ostree"
    cat > "${IMAGE_ROOTFS}/usr/lib/ostree/prepare-root.conf" <<EOF
[composefs]
enabled = false
[sysroot]
readonly = true
EOF
}

chunked_bootc_usr_layout() {
    if [ -d ${IMAGE_ROOTFS}/opt ] && [ ! -L ${IMAGE_ROOTFS}/opt ]; then
        install -d ${IMAGE_ROOTFS}/usr
        mv ${IMAGE_ROOTFS}/opt ${IMAGE_ROOTFS}/usr/opt
        ln -s usr/opt ${IMAGE_ROOTFS}/opt
    fi
}

chunked_bootc_deref_hardlinks() {
    find ${IMAGE_ROOTFS} -xdev -type f -links +1 | while read -r f; do
        cp -p "$f" "$f.chunked-bootc-deref" && mv "$f.chunked-bootc-deref" "$f"
    done
}

chunked_bootc_container_cfg() {
    [ "${CHUNKED_BOOTC_CONTAINER_CFG}" = "1" ] || return 0

    # no /var/tmp in the layer (ostree deployment provides it)
    rm -rf ${IMAGE_ROOTFS}/var/tmp

    install -d ${IMAGE_ROOTFS}/etc/containers
    # v2 format; the v1 [registries.insecure] form is rejected by
    # bootc/skopeo when the image's own config is read at install time
    : > ${IMAGE_ROOTFS}/etc/containers/registries.conf
    local r
    for r in ${CHUNKED_BOOTC_INSECURE_REGISTRIES}; do
        printf '[[registry]]\nlocation = "%s"\ninsecure = true\n\n' "$r" \
            >> ${IMAGE_ROOTFS}/etc/containers/registries.conf
    done
    cat > ${IMAGE_ROOTFS}/etc/containers/policy.json <<'EOF'
{"default":[{"type":"insecureAcceptAnything"}]}
EOF

    if [ -n "${CHUNKED_BOOTC_SKOPEO_STATIC}" ]; then
        [ -e "${CHUNKED_BOOTC_SKOPEO_STATIC}" ] || bbfatal "chunked_bootc_container_cfg: CHUNKED_BOOTC_SKOPEO_STATIC=${CHUNKED_BOOTC_SKOPEO_STATIC} not found"
        install -D -m 0755 "${CHUNKED_BOOTC_SKOPEO_STATIC}" ${IMAGE_ROOTFS}/usr/bin/skopeo
    fi
}
