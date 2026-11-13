# Packaging policy for an immutable, externally-produced model release.
# Training never runs as part of do_rootfs; BitBake only consumes and verifies
# the selected release.

BOOTC_MODEL_RELEASE ?= "v1"
BOOTC_MODEL_FORMAT ?= "json-linear"
BOOTC_MODEL_INSTALL_PATH ?= "/opt/edge-inference/model"
BOOTC_MODEL_RECIPE ?= "edge-inference-model"

do_install:append() {
    install -d ${D}${BOOTC_MODEL_INSTALL_PATH}
    install -m 0644 ${WORKDIR}/${BOOTC_MODEL_RELEASE}/model.json ${D}${BOOTC_MODEL_INSTALL_PATH}/model.json
    install -m 0644 ${WORKDIR}/${BOOTC_MODEL_RELEASE}/model-manifest.json ${D}${BOOTC_MODEL_INSTALL_PATH}/model-manifest.json
}

python do_model_validate() {
    import hashlib, json, os
    model = d.expand('${WORKDIR}/${BOOTC_MODEL_RELEASE}/model.json')
    manifest = d.expand('${WORKDIR}/${BOOTC_MODEL_RELEASE}/model-manifest.json')
    with open(model, 'rb') as f:
        digest = hashlib.sha256(f.read()).hexdigest()
    with open(manifest) as f:
        data = json.load(f)
    expected = data.get('sha256')
    if expected != digest:
        bb.fatal('model manifest sha256 %s does not match %s' % (expected, digest))
    if data.get('version') != d.getVar('BOOTC_MODEL_RELEASE'):
        bb.fatal('model release and manifest version disagree')
    if data.get('format') != d.getVar('BOOTC_MODEL_FORMAT'):
        bb.fatal('unsupported or unexpected model format')
}
addtask model_validate after do_unpack before do_install
