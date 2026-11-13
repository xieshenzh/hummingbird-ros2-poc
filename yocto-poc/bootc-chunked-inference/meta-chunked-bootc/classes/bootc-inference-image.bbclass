# Optional inference profile for a chunked bootc image.  The underlying image
# remains a generic bootc/OSTree image; inference is just a selectable payload.

BOOTC_INFERENCE_RUNTIME ?= "edge-inference-runtime"
BOOTC_INFERENCE_SERVICE ?= "edge-inference-service"
BOOTC_INFERENCE_MODEL ?= "edge-inference-model"
BOOTC_INFERENCE_API_PORT ?= "8080"

IMAGE_INSTALL:append = " ${BOOTC_INFERENCE_RUNTIME} ${BOOTC_INFERENCE_SERVICE} ${BOOTC_INFERENCE_MODEL}"

IMAGE_FEATURES:append = " ${@bb.utils.contains('DISTRO_FEATURES', 'systemd', '', '', d)}"
CHUNKED_BOOTC_INFERENCE_MODEL ?= "${BOOTC_MODEL_RELEASE}"

python do_bootc_inference_validate() {
    import json, os
    rootfs = d.getVar('IMAGE_ROOTFS')
    path = os.path.join(rootfs, 'opt/edge-inference/model/model-manifest.json')
    if not os.path.exists(path):
        bb.fatal('inference model manifest missing: %s' % path)
    with open(path) as f:
        manifest = json.load(f)
    if manifest.get('version') != d.getVar('BOOTC_MODEL_RELEASE'):
        bb.fatal('installed model does not match BOOTC_MODEL_RELEASE')
    service = os.path.join(rootfs, d.getVar('systemd_system_unitdir').lstrip('/'), 'edge-inference.service')
    if not os.path.exists(service):
        bb.fatal('inference systemd service missing: %s' % service)
}
addtask bootc_inference_validate after do_rootfs before do_image

# Optional cross-build comparison.  Set BOOTC_LAYER_COMPARE_FROM to a previous
# chunked OCI layout to make the release build fail if too many layers change.
BOOTC_LAYER_COMPARE_FROM ?= ""
BOOTC_LAYER_COMPARE_MAX_CHANGED ?= "2"
python do_bootc_layer_validate() {
    import json, os
    previous = d.getVar('BOOTC_LAYER_COMPARE_FROM')
    if not previous:
        return
    current = os.path.join(d.getVar('IMGDEPLOYDIR'), d.getVar('IMAGE_BASENAME') + '-chunked.oci')
    tool = os.path.join(d.getVar('CHUNKED_BOOTC_LAYERDIR'), 'scripts', 'compare-oci-layers.py')
    import subprocess
    report = os.path.join(d.getVar('DEPLOY_DIR_IMAGE'), d.getVar('IMAGE_BASENAME') + '-layer-diff.json')
    subprocess.check_call(['python3', tool, previous, current, '--max-changed', d.getVar('BOOTC_LAYER_COMPARE_MAX_CHANGED'), '--report', report])
}
addtask bootc_layer_validate after do_chunked_bootc_chunk before do_chunked_bootc_hybrid
