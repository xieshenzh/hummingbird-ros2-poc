require recipes-core/images/core-image-minimal.bb

inherit chunked-bootc bootc-inference-image

IMAGE_INSTALL:append = " ostree bootc kernel-modules util-linux-mount util-linux-umount util-linux-unshare"
IMAGE_BASENAME = "generic-inference-bootc-image"
IMAGE_CLASSES += "chunked-bootc-oci chunked-bootc-chunkah"
IMAGE_FSTYPES += "oci"
CHUNKED_BOOTC_HYBRID ?= "1"
