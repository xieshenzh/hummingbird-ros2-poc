# Phase 1 target image: minimal + RT kernel + ostree + bootc.
# The bootc rootfs layout (kernel placement, BLS entry, usr layout,
# hardlink deref, version stamp) lives in hb-bootc.bbclass so other
# images can inherit it.
require recipes-core/images/core-image-minimal.bb

inherit hb-bootc

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

# Optional container outputs (require buildah/chunkah on the build host):
#   IMAGE_CLASSES += "hb-oci"     + IMAGE_FSTYPES += "oci"
#   IMAGE_CLASSES += "hb-chunkah" (+ HB_CHUNKED_HYBRID = "1" for the
#                                   bootc-installable hybrid image)
