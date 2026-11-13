# Chunked bootc inference image PoC

This is a standalone Yocto/BitBake example. It builds a small bootc/OSTree
edge image, packages an immutable model release into it, publishes the normal,
chunked, base, and hybrid OCI artifacts, and upgrades a running deployment
with `bootc switch`. The existing `yocto-poc/end-to-end-generic` PoC is not
modified.

## Build

The normal entry point is KAS:

```bash
cd yocto-poc/bootc-chunked-inference
BOOTC_MODEL_RELEASE=v1 kas build kas/bootc-chunked-inference-qemuarm64.yaml
```

The build consumes only the selected immutable files under `models/` mirrored
in the model recipe. Model training is intentionally outside BitBake:

```bash
python3 models/training/train-model.py
BOOTC_MODEL_RELEASE=v2 kas build kas/bootc-chunked-inference-qemuarm64.yaml
```

`BOOTC_MODEL_RELEASE` is a build input, not mutable state fetched by a rootfs
task. The model package validates its manifest digest and version before it is
installed at `/opt/edge-inference/model`.

For a release-specific build that cannot accidentally inherit a previous
shared-build value, use the fixed-v2 manifest:

```bash
kas build kas/bootc-chunked-inference-qemuarm64-v2.yaml
```

The KAS configuration explicitly passes `BOOTC_MODEL_RELEASE` into BitBake;
the rootfs task also declares the version stamp as a dependency so the
immutable release and `/etc/chunked-bootc-version` stay aligned.

## Image and update design

The image inherits the unchanged bootc/chunkah behavior from the generic PoC
and adds an optional inference profile. The service is deliberately tiny and
generic: `/healthz`, `/ready`, `/version`, `/metrics`, and `POST /infer`.
The model is an intentionally simple linear JSON model so the PoC is fast and
deterministic; a promoted ONNX or accelerator model can replace the package
without changing the image contract.

The model path is isolated from the OS and runtime. Compare two generated
chunked OCI layouts with:

```bash
python3 meta-chunked-bootc/scripts/compare-oci-layers.py OLD.oci NEW.oci \
  --max-changed 2 --report model-layer-diff.json
```

The report includes changed layer count, bytes, and paths. A release build can
set `BOOTC_LAYER_COMPARE_FROM` to make this check a BitBake task.

## Deployment validation

The generated `*-hybrid.oci` is the bootc-installable artifact. The validated
local-registry/QEMU run installed v1, checked the golden request (`2 -> 2.0`),
switched to v2, rebooted, and checked (`2 -> 2.5`). After reboot, bootc
reported v2 as booted and retained v1 as the rollback deployment; the
PREEMPT_RT kernel remained active. bootc 1.1.0 emits a nonfatal pruning
warning while staging in this PoC, but the stage and deployment transaction
completed successfully. Registry credentials and site policy are deployment
inputs and are never embedded in the image.

The final hybrid OCI comparison contained 26 layers in each image, with one
changed layer and 66,269,184 changed bytes. This is the measured chunk-level
delta for the deterministic model release update.

The copied, optional developer harnesses are:

```bash
scripts/deploy-inference-image.sh v1 /tmp/inference-disk.img localhost:5000/generic-inference-bootc
scripts/upgrade-inference-check.py v1 v2
```

They use the same direct-kernel QEMU approach as the generic reference PoC;
they are not part of normal artifact assembly. In CI, the equivalent boot,
upgrade, and interrupted-upgrade checks should be wired through
`oeqa/testimage`.

This is a generic Yocto reference image, not a claim of a supported RHEL for
Edge or MicroShift host configuration. A production Red Hat deployment should
use the supported RHEL/Image Mode + MicroShift path while reusing the model
release and OCI validation concepts demonstrated here.
