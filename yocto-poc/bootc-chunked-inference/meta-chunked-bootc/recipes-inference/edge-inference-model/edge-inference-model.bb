SUMMARY = "Immutable model release for the bootc inference PoC"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit bootc-inference-model

FILESEXTRAPATHS:prepend := "${THISDIR}/files:"
SRC_URI = "file://${BOOTC_MODEL_RELEASE}/model.json \
           file://${BOOTC_MODEL_RELEASE}/model-manifest.json"
FILES:${PN} += "/opt/edge-inference/model"
