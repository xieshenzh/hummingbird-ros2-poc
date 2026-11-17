# Phase 5 — OpenShift-managed edge-device simulation

Phase 5 validates a bootable bootc device as an OpenShift Virtualization VM.
The first milestone is one VM (`edge-device-001`) before introducing fleet
waves or rollback automation.

## Current boundary

The Phase 4 artifact is an OCI layout, not a KubeVirt disk image. It cannot be
placed directly in `containerDisk`. Before applying `edge-device-vm.yaml`, the
approved hybrid OCI artifact must be installed into a raw or qcow2 disk and
imported into a CDI PVC named `phase4-bootc-disk-anomalynet-v3` (or the VM
manifest must be changed to the actual PVC). This conversion is a separate
image-preparation step; it is not a Tekton promotion task.

OpenShift Virtualization is not currently installed in the connected cluster,
so this manifest is a checked-in contract and has not been applied.

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

1. Install the OpenShift Virtualization operator and verify KubeVirt/CDI are
   available.
2. Convert the approved ARM64 hybrid OCI artifact into a bootable disk and
   import it as `phase4-bootc-disk-anomalynet-v3`.
3. Apply `edge-device-vm.yaml`.
4. Verify the VM reaches `Running`, then verify bootc status and the two guest
   services through the VM network.
5. Record the booted release, device identity, temperature, and inference
   result before attempting a staged `bootc switch` plus explicit VM reboot.

Do not create a fleet until this single-device boot, health, identity, and
rollback contract passes.
