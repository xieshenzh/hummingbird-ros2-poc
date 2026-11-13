# Generic target image: minimal + kernel + ostree + bootc.
# The image is intentionally free of application-specific content.
require recipes-core/images/core-image-minimal.bb

inherit chunked-bootc

IMAGE_INSTALL:append = " \
    ostree \
    bootc \
    kernel-modules \
    util-linux-mount \
    util-linux-umount \
    util-linux-unshare \
"

IMAGE_CLASSES += "chunked-bootc-oci chunked-bootc-chunkah"
IMAGE_FSTYPES += "oci"
CHUNKED_BOOTC_HYBRID ?= "1"
