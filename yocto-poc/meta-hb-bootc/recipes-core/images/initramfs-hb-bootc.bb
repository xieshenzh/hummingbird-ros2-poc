# Initramfs for the hb-bootc image: initramfs-framework + udev + rootfs
# mount + ostree prepare-root. bootc deployments are assembled by
# prepare-root before switch_root into the deployed root.
DESCRIPTION = "Minimal initramfs with ostree support for hb-bootc"

PACKAGE_INSTALL = "initramfs-framework-base initramfs-module-udev \
    initramfs-module-e2fs initramfs-module-rootfs initramfs-module-ostree \
    ${VIRTUAL-RUNTIME_base-utils} udev base-passwd ${ROOTFS_BOOTSTRAP_INSTALL}"

# Do not pollute the initrd image with rootfs features
IMAGE_FEATURES = ""

# Don't allow the initramfs to contain a kernel
PACKAGE_EXCLUDE = "kernel-image-*"

IMAGE_NAME_SUFFIX ?= ""
IMAGE_LINGUAS = ""

LICENSE = "MIT"

IMAGE_FSTYPES = "${INITRAMFS_FSTYPES}"
inherit core-image

IMAGE_ROOTFS_SIZE = "8192"
IMAGE_ROOTFS_EXTRA_SPACE = "0"
