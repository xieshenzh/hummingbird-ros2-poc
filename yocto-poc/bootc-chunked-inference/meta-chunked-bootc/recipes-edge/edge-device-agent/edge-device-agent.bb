SUMMARY = "Simulated edge-device identity and temperature agent"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "file://edge-device-agent.py file://edge-device-agent.service"
S = "${WORKDIR}"

RDEPENDS:${PN} = "python3-core python3-json python3-netserver"
inherit systemd
SYSTEMD_SERVICE:${PN} = "edge-device-agent.service"
SYSTEMD_AUTO_ENABLE:${PN} = "enable"

do_install() {
    install -d ${D}${bindir} ${D}${systemd_system_unitdir}
    install -m 0755 ${WORKDIR}/edge-device-agent.py ${D}${bindir}/edge-device-agent
    install -m 0644 ${WORKDIR}/edge-device-agent.service ${D}${systemd_system_unitdir}/
}

FILES:${PN} += "${systemd_system_unitdir}/edge-device-agent.service"
