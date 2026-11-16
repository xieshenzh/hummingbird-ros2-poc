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

### Real edge model (local Phase 1)

The local real-model path uses the Apache-2.0 `eoinedge/AnomalyNet` model. It
is an 842-parameter temperature-window classifier with 32 inputs and two
outputs (`normal`, `anomaly`). Its published training data is the
`eoinedge/heater-anomaly-windows` dataset: 20,000 training rows, 4,000
validation rows, and 4,000 test rows. The dataset contains synthetic heater
telemetry with spikes, dropouts, runaway ramps, and noise bursts.

Install host-side training dependencies and create an immutable model release
outside BitBake:

```bash
python3 -m venv .venv-model
. .venv-model/bin/activate
pip install torch datasets
python3 models/training/finetune-anomalynet.py \
  --version anomalynet-v1 \
  --output models/anomalynet-v1
```

The script downloads the original state dict, loads the published dataset,
fine-tunes the model, and writes the actual trained weights as a compact JSON
artifact. It also writes the manifest and checksum used by the BitBake model
recipe. The target service executes the same two-layer MLP with its embedded
weights and does not require PyTorch on the image.

Build the real-model image with the dedicated manifest:

```bash
kas build kas/bootc-chunked-inference-qemuarm64-anomalynet.yaml
```

This first phase uses the published synthetic dataset to reproduce the edge
workflow. A later release should replace it with device-specific telemetry
while retaining the same 32-sample input contract and manifest provenance.

### Phase 2: v2 fine-tuning and bootc upgrade

The Phase 2 release is fine-tuned with a fixed seed and records its training
configuration in the model manifest:

```bash
python3 models/training/finetune-anomalynet.py \
  --version anomalynet-v2 \
  --output models/anomalynet-v2 \
  --epochs 5 \
  --lr 0.0002 \
  --batch-size 128 \
  --seed 20261116
```

Build the v2 bootc image with:

```bash
kas build kas/bootc-chunked-inference-qemuarm64-anomalynet-v2.yaml
```

The next validation step compares the v1 and v2 hybrid OCI artifacts, then
uses `bootc switch` and reboot to verify v2 boot selection, v1 rollback
retention, and inference behavior after the upgrade.

## Deployment validation

The generated `*-hybrid.oci` is the bootc-installable artifact. The validated
local-registry/QEMU run installed v1, classified a steady 32-sample window as
`normal`, switched to v2, rebooted, and classified both the steady window as
`normal` and a high-temperature excursion as `anomaly`. After reboot, bootc
reported v2 as booted and retained v1 as the rollback deployment; the
PREEMPT_RT kernel remained active. bootc 1.1.0 emits a nonfatal pruning
warning while staging in this PoC, but the stage and deployment transaction
completed successfully. Registry credentials and site policy are deployment
inputs and are never embedded in the image.

The final hybrid OCI comparison contained 27 layers in each image, with one
changed layer and 66,287,104 changed bytes. This is the measured chunk-level
delta for the deterministic model release update.

The follow-up safety checks also passed. Killing `bootc switch` with `SIGKILL`
after it entered the registry pull/stage path left v2 booted and rebootable,
with PREEMPT_RT intact. A real `bootc rollback` from v2 then rebooted into v1;
v2 was retained as the rollback deployment, `/version` and
`/etc/chunked-bootc-version` reported `anomalynet-v1`, and both normal and
anomaly inference classifications passed.

The copied, optional developer harnesses are:

```bash
scripts/deploy-inference-image.sh v1 /tmp/inference-disk.img localhost:5000/generic-inference-bootc
scripts/upgrade-inference-check.py v1 v2
```

They use the same direct-kernel QEMU approach as the generic reference PoC;
they are not part of normal artifact assembly. In CI, the equivalent boot,
upgrade, and interrupted-upgrade checks should be wired through
`oeqa/testimage`.

## OpenShift deployment

An optional Phase 3 application deployment is provided in
`openshift/anomalynet-v2/`. The top-level Kustomization keeps the model and
service source tied to the immutable v2 release while deploying the
dependency-free HTTP service in a non-root UBI Python container:

```bash
oc apply -k yocto-poc/bootc-chunked-inference
oc -n my-first-model rollout status deployment/anomalynet-v2
oc -n my-first-model get route anomalynet-v2
```

The deployment exposes `/healthz`, `/ready`, `/version`, `/metrics`, and
`/infer` through an edge-terminated OpenShift Route. The model ConfigMap is
generated from `models/anomalynet-v2/` and should not be replaced with a
mutable training output.

This is a generic Yocto reference image, not a claim of a supported RHEL for
Edge or MicroShift host configuration. A production Red Hat deployment should
use the supported RHEL/Image Mode + MicroShift path while reusing the model
release and OCI validation concepts demonstrated here.
