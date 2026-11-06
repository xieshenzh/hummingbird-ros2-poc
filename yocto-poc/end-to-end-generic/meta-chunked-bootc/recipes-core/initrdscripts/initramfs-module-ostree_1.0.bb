SUMMARY = "initramfs-framework module that runs ostree prepare-root"
DESCRIPTION = "After the rootfs module mounts the physical root, run \
ostree-prepare-root so the ostree deployment is assembled before \
switch_root. Mirrors dracut's ostree module for Yocto's initramfs-framework."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "file://ostree"

S = "${WORKDIR}"

do_install() {
    install -d ${D}/init.d
    install -m 0755 ${WORKDIR}/ostree ${D}/init.d/91-ostree
}

FILES:${PN} = "/init.d/*"

RDEPENDS:${PN} = "initramfs-framework-base ostree"
