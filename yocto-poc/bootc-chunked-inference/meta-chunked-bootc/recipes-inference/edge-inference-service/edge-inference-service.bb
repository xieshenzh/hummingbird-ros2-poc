SUMMARY = "Small generic inference service"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "file://edge-inference.py file://edge-inference.service"
S = "${WORKDIR}"
RDEPENDS:${PN} = "python3-core python3-io python3-json python3-email python3-html python3-mime python3-netclient python3-netserver"
inherit systemd useradd
SYSTEMD_SERVICE:${PN} = "edge-inference.service"
SYSTEMD_AUTO_ENABLE:${PN} = "enable"
USERADD_PACKAGES = "${PN}"
USERADD_PARAM:${PN} = "--system --no-create-home --shell /bin/false edge-inference"

do_install() {
    install -d ${D}${bindir} ${D}${systemd_system_unitdir}
    install -m 0755 ${WORKDIR}/edge-inference.py ${D}${bindir}/edge-inference
    install -m 0644 ${WORKDIR}/edge-inference.service ${D}${systemd_system_unitdir}/
}
FILES:${PN} += "${systemd_system_unitdir}/edge-inference.service"
