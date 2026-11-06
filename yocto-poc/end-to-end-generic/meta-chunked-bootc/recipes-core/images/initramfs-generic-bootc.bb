# Initramfs for the generic bootc image: initramfs-framework + udev + rootfs
# mount + ostree prepare-root. bootc deployments are assembled by
# prepare-root before switch_root into the deployed root.
DESCRIPTION = "Minimal initramfs with ostree support for generic bootc"

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

# container artifact classes don't apply to the initramfs.
IMAGE_CLASSES:remove = "chunked-bootc-oci chunked-bootc-chunkah"

IMAGE_ROOTFS_SIZE = "8192"
IMAGE_ROOTFS_EXTRA_SPACE = "0"
