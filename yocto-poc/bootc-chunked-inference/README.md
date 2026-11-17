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

The former `openshift/anomalynet-v2/` Deployment/Service/Route was an
intermediate smoke test only. The Phase 3 Kustomization now deploys the
OpenShift AI KServe `InferenceService/anomalynet-v3` and the immutable v3
release:

```bash
oc apply -k yocto-poc/bootc-chunked-inference
oc -n my-first-model get inferenceservice anomalynet-v3
```

KServe reports the predictor as Ready and Loaded. The custom dependency-free
adapter exposes KServe-compatible health paths and
`POST /v2/models/anomalynet-v3/infer`; the model ConfigMap is generated from
the committed `models/anomalynet-v3/` release and is not replaced with a
mutable training output.

This is a generic Yocto reference image, not a claim of a supported RHEL for
Edge or MicroShift host configuration. A production Red Hat deployment should
use the supported RHEL/Image Mode + MicroShift path while reusing the model
release and OCI validation concepts demonstrated here.

## Phase 3: OpenShift AI model workflow

Phase 3 keeps training outside BitBake and runs the reproducible fine-tuning
job with the OpenShift AI/Kubeflow Training Operator. The pinned inputs and
configuration are in `models/training/training-config-v3.json`; the submitted
single-worker CPU `PyTorchJob` is in `openshift/phase3-pytorchjob.yaml`.

The completed release is `models/anomalynet-v3/`. It contains the compact JSON
weights, an immutable manifest, and a checksum. The release was trained with:

- source model `eoinedge/AnomalyNet@bb9db962cebb0f506496dc51e824cfc15b8a7ab`
- dataset `eoinedge/heater-anomaly-windows@1d8bc1832883fec91792fedbdba11e79ee476636`
- seed `20261116`, 5 epochs, learning rate `0.0002`, batch size `128`
- evaluation threshold `0.99`; measured test accuracy `0.996749997138977`
- model SHA-256 `4451989831e5551be121a687cfdb6baafc5b456703c47d64eac74b4ed7554edb`

The release is mirrored under
`meta-chunked-bootc/recipes-inference/edge-inference-model/files/anomalynet-v3/`
so it can be selected by `BOOTC_MODEL_RELEASE=anomalynet-v3` without training
inside BitBake.

Phase 4 has a fixed KAS configuration for this approved release:

```bash
kas build kas/bootc-chunked-inference-qemuarm64-anomalynet-v3.yaml
```

The final OpenShift AI inference path is the KServe-managed
`InferenceService/anomalynet-v3` in `openshift/anomalynet-v3-inferenceservice.yaml`.
It uses the dependency-free JSON adapter in `openshift/kserve-anomalynet.py`,
with the immutable release mounted by ConfigMap. The previous generic v2
Deployment, Service, Route, and ConfigMaps are not part of the Phase 3
Kustomization and were removed from the namespace.

Validate the KServe workload from inside its managed predictor pod:

```bash
oc -n my-first-model get inferenceservice anomalynet-v3
oc -n my-first-model exec deploy/anomalynet-v3-predictor -- curl -sS http://localhost:8080/healthz
oc -n my-first-model exec deploy/anomalynet-v3-predictor -- curl -sS http://localhost:8080/version
```

The platform-level Model Registry component CR is not itself a registry
instance. The actual namespaced registry is defined separately in
`openshift/anomalynet-registry.yaml` and must be applied to
`rhoai-model-registries`:

```bash
oc apply -f openshift/anomalynet-registry.yaml
```

This creates the REST service and OAuth-protected route. The registration
metadata used for `anomalynet-v3` is recorded in
`openshift/model-registry-registration.json`; the live registry contains the
registered model, version, artifact, provenance fields, and SHA-256. Use the
current route as `MODEL_REGISTRY_URL` and pass the token only at runtime:

```bash
export MODEL_REGISTRY_URL=https://anomalynet-registry-rest.apps.ocp.8q22b.sandbox1882.opentlc.com
export MODEL_REGISTRY_TOKEN="$(oc whoami -t)"
curl -ksS -H "Authorization: Bearer $MODEL_REGISTRY_TOKEN" \
  "$MODEL_REGISTRY_URL/api/model_registry/v1alpha3/registered_models"
```

## Phase 4: production model-to-device promotion

The approved `anomalynet-v3` release is selected by the fixed
`kas/bootc-chunked-inference-qemuarm64-anomalynet-v3.yaml` configuration. Run
the build from a prepared Yocto/KAS environment:

```bash
cd yocto-poc/bootc-chunked-inference
kas build kas/bootc-chunked-inference-qemuarm64-anomalynet-v3.yaml
```

After the build, validate the generated bootc/OCI artifacts and run the
existing deployment checks for boot, inference, `bootc switch`, rollback, and
interrupted upgrade safety. The current macOS session has no `kas` or BitBake
installation, so the image build itself must run in the project Yocto build
environment or a prepared KAS container.

### OpenShift AI / OpenShift Pipelines execution

The Phase 4 build is intended to run in OpenShift, not on the developer
workstation. OpenShift AI owns the approved release PVC and Tekton/OpenShift
Pipelines executes the promotion. The pipeline copies the release from
`anomalynet-v3-release`, verifies the model and manifest SHA-256, overlays it
onto the checked-out source, runs KAS/BitBake, validates the generated
`generic-inference-bootc-image-hybrid.oci`, and optionally publishes it.

The manifests are intentionally opt-in because publication credentials must
never be committed:

```bash
oc apply -f openshift/phase4-build-pvc.yaml -n my-first-model
oc apply -f openshift/phase4-tekton-pipeline.yaml -n my-first-model
# Review the builder image and destination, then submit the run:
oc apply -f openshift/phase4-tekton-pipelinerun.yaml -n my-first-model
oc -n my-first-model get pipelinerun anomalynet-v3-yocto-bootc-promotion
oc -n my-first-model logs -f pipelinerun/anomalynet-v3-yocto-bootc-promotion
```

The `yocto-builder-image` parameter is a contract, not a claim that the
generic KAS image contains every host tool. Build and smoke-test the
cluster-approved builder image **before** creating the promotion PipelineRun,
then pin the resulting image by digest. It must contain `kas`, BitBake,
`buildah`, `chunkah`, `ostree`, `ostree-encap`, `skopeo`, and the static
`linux/arm64` Skopeo helper at
`/usr/local/libexec/chunked-bootc-skopeo-static`; the pipeline fails closed if
any tool is absent. The promotion run does not install packages, download
toolchains, or compile builder tools. Set
`publish-image`, `publish-username`, and `publish-password` only at runtime
(prefer a Secret-backed Tekton parameter or an internal registry service
account); no OpenShift token or registry password belongs in Git.
The Git revision used by the run must also contain the Phase 4 KAS file and
pipeline changes; push the reviewed commit before launching the run.

### Building the builder image in OpenShift

The builder image can be bootstrapped without local Docker or Podman using the
OpenShift binary build API:

```bash
oc apply -f openshift/phase4-builder-buildconfig.yaml -n my-first-model
oc start-build yocto-bootc-builder \
  --from-dir=openshift \
  --follow \
  -n my-first-model
oc -n my-first-model get istag yocto-bootc-builder:5.2
```

The binary build context contains `yocto-builder.Containerfile`. It uses
`ghcr.io/siemens/kas/kas:5.2-debian-bookworm` as its base. Named intermediate
Containerfile stages compile Chunkah, the `ostree-ext` CLI wrapper, and the
static ARM64 Skopeo helper; the final builder stage copies only those finished
runtime tools and contains no Go/Rust toolchain or source tree. Chunkah is
compiled against Debian Bookworm to avoid a glibc mismatch. The image exposes
an `ostree-encap` compatibility wrapper backed by the compiled `ostree-ext`
CLI. The Containerfile performs a tool smoke test before the image is
accepted. Rebuild this image and update the digest-pinned
`yocto-builder-image` parameter before submitting a new promotion run.
