# Phase 5 — OpenShift-managed edge-device simulation

Phase 5 validates a bootable bootc device as an OpenShift Virtualization VM.
The first milestone is one VM (`edge-device-001`) before introducing fleet
waves or rollback automation.

## Repository is the source of truth

All build inputs and execution contracts must remain in this repository. The
OpenShift cluster is disposable execution infrastructure, not the canonical
location for source code or pipeline logic. In particular, keep the KAS
configurations, Yocto layer, model manifests/checksums, Tekton Pipeline and
PipelineRun parameters, and validation scripts checked in here. A cluster may
contain only a checked-out workspace and generated artifacts.

The Phase 4 pipeline clones this repository at a pinned revision. It must not
silently patch the cloned layer to correct architecture or shell behavior;
those fixes belong in the tracked layer and KAS files.

## Current boundary

The Phase 4 artifact is an OCI layout, not a KubeVirt disk image. It cannot be
placed directly in `containerDisk`. Before applying `edge-device-vm.yaml`, the
approved hybrid OCI artifact must be installed into a raw or qcow2 disk and
imported into a CDI PVC named `phase4-bootc-disk-anomalynet-v3` (or the VM
manifest must be changed to the actual PVC). This conversion is a separate
 image-preparation step; it is not a Tekton promotion task.

The first direct Tekton conversion attempt is recorded in
`tekton-direct-image-builder.yaml`. The OCI publication step succeeded, but
the raw-image TaskRun was rejected at pod admission because the `pipeline`
service account is not allowed to use a privileged SCC (and its requested
`fsGroup: 1001` is not allowed). Do not modify a shared SCC to bypass this
boundary. The checked-in conversion contract therefore requires either an
approved, dedicated privileged worker or an external installer VM.

Tekton can orchestrate an installer VM by invoking a pre-provisioned VM over a
controlled worker/SSH or an approved cloud API. It cannot provide that VM by
itself. This cluster currently has no usable KubeVirt/CDI API for creating the
VM or importing its disk, so the next safe path is a dedicated Fedora/bootc
installer VM with the validated OCI artifact and a separate output transfer.

## External-VM Tekton orchestration

`tekton-external-vm-pipelines.yaml` defines the two-job handoff without using
KubeVirt:

1. `anomalynet-v3-convert-collect-vm` transfers the validated OCI layout to a
   dedicated Fedora conversion VM over SSH, runs
   `scripts/fedora-vm-convert-collect.sh`, and copies the generated
   `disk.img`, kernel, initramfs, checksums, and metadata back into the owned
   `phase5-anomalynet-v3-artifacts-32830c0` PVC.
2. `anomalynet-v3-deploy-qemu-vm` transfers that PVC content to the separate
   deployment VM, runs `scripts/fedora-qemu-deploy-verify.sh`, and performs
   the guarded target-disk write plus QEMU/serial validation there.

The deployment VM is the Fedora host that launches the QEMU guest; Tekton does
not SSH into the guest before it boots. The VM must provide the tested
`serial-console-exec` driver, QEMU, and the host disk utilities. Both jobs use
the namespace-local `anomalynet-vm-ssh` Secret with `privateKey` and
`knownHosts`; no credential is checked into the repository. Replace the two
example hostnames in the PipelineRuns before creating them.

After a host-side raw conversion, run the checked-in deployment repair and
validation helper while the root partition is mounted, before exporting boot
assets or starting QEMU:

```bash
sudo yocto-poc/bootc-chunked-inference/scripts/repair-ostree-deployments.sh \
  /var/tmp/anomalynet/native-output-4f62798/mnt
```

The helper addresses a bootc 1.1.x installation quirk: a fresh deployment may
have no deployment-local `sysroot` entry, or an absolute `sysroot -> /sysroot`
symlink. The Yocto initramfs needs a real deployment-local directory so
`ostree-prepare-root` survives `switch_root`. This is a host-side repair of
the generated disk, not a change to the OCI image and not a substitute for
the raw-image and QEMU checks below.

OpenShift Virtualization is being activated in the connected cluster, so this
manifest is a checked-in contract. The operator and
`phase5/hyperconverged.yaml` have now been applied; the KubeVirt/CDI operands
must report ready before the VM manifest can be applied.

## Guest contract

The image now includes `edge-device-agent`, alongside the AnomalyNet service.
It exposes:

- `http://<guest>:8080`: inference service;
- `http://<guest>:8090/healthz` and `/status`: device identity and simulated
  temperature;
- `/run/edge-device/status.json`: local health-check state.

The agent accepts `edge.device-id=` and `edge.temperature=` kernel parameters,
with deterministic defaults. It also reads the JSON identity and sensor files
provided by the VM's NoCloud config disk. The VM manifest therefore keeps
identity and sensor values in the VM definition rather than in the immutable
OS image.

## First-device validation sequence

1. Install the OpenShift Virtualization operator and apply
   `hyperconverged.yaml`; verify KubeVirt/CDI are available.
2. Convert the approved architecture-matched hybrid OCI artifact into a bootable disk and
   import it as `phase4-bootc-disk-anomalynet-v3`.
3. Apply `edge-device-vm.yaml`.
4. Verify the VM reaches `Running`, then verify bootc status and the two guest
   services through the VM network.
5. Record the booted release, device identity, temperature, and inference
   result before attempting a staged `bootc switch` plus explicit VM reboot.

Do not create a fleet until this single-device boot, health, identity, and
rollback contract passes.
