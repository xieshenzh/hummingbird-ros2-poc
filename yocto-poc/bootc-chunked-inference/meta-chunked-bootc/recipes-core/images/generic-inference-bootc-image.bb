require recipes-core/images/core-image-minimal.bb

inherit chunked-bootc bootc-inference-image

# Keep the target self-contained for native bootc installation. These are
# runtime components of the image contract; the raw-image step must not copy
# host/Fedora binaries or install ad-hoc compatibility stubs.
IMAGE_INSTALL:append = " \
    ostree \
    bootc \
    kernel-modules \
    util-linux-mount \
    util-linux-umount \
    util-linux-unshare \
    util-linux-sfdisk \
    e2fsprogs \
    dosfstools \
"
IMAGE_BASENAME = "generic-inference-bootc-image"
IMAGE_CLASSES += "chunked-bootc-oci chunked-bootc-chunkah"
IMAGE_FSTYPES += "oci"
CHUNKED_BOOTC_HYBRID ?= "1"
