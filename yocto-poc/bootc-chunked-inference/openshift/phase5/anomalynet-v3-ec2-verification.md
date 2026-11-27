# AnomalyNet v3 AMD64 EC2 verification

## Artifact

The owned Tekton rebuild completed with `yocto-bootc-builder-2` and the
target-aware static Skopeo helper. The reassembled hybrid OCI was validated as
AMD64 and contains a runnable `skopeo 1.24.1` plus the bootc labels:

```text
containers.bootc=1
ostree.bootable=1
ostree.final-diffid=sha256:aee1e8dcf1f585c71055e798154b0db602bf5fa2fc837c1385a2aa1a3f21536b
```

The original OCI layouts remain preserved. The rebuilt layout is archived
locally under `artifacts/anomalynet-v3-amd64/rebuilt/` (the artifacts directory
is intentionally not committed).

## EC2 result

Host: `ec2-3-137-215-16.us-east-2.compute.amazonaws.com`.

Safety checks confirmed `/dev/nvme0n1p1` is the mounted root filesystem and
`/dev/nvme1n1` is the dedicated 80 GiB target. All failed bootc attempts left
the root disk untouched. The target disk was prepared with a GPT ESP and ext4
root partition for the install attempt.

The image itself passes `bootc --version` and the embedded AMD64 Skopeo helper
executes successfully. Installation is currently blocked because bootc 1.1.0
re-execs into the EC2 host PID 1 mount namespace, where this non-bootc host does
not expose the container-mounted `/dev/nvme1n1` or the temporary target mount.
The host has no native bootc installation. Explicit local-storage references
also require the host bootc/container-store integration and do not bypass this
mount-namespace boundary. No further disk write should be attempted until the
host provides a supported bootc installer environment (or a dedicated bootc
image-builder/VM path).

## Reproduction boundary

The safe command shape used for all attempts was rootful Podman with
`--privileged --pid=host`, and every command asserted that `/dev/nvme1n1` was
unmounted and `/dev/nvme0n1p1` was `/` before invoking bootc. The blocker is
therefore recorded as an EC2 host capability limitation, not an OCI build or
architecture failure.

## OpenShift raw-image attempt

The validated OCI layout was published from the Phase 4 workspace to the owned
namespace registry successfully. A direct `bootc-image-builder` TaskRun was
then submitted, intentionally avoiding the earlier nested-Podman and manual
loop-device approach. It did not start: OpenShift rejected the pod because
the `pipeline` service account is not permitted to use a privileged SCC, and
the requested supplemental group was also outside the namespace's allowed
range. No SCC or cluster-scoped security configuration was changed.

This means Tekton can still orchestrate the workflow, but the current cluster
cannot execute the conversion. Use a pre-provisioned dedicated installer VM
or an approved privileged build worker, then copy the resulting raw/QCOW2
artifact back to the owned workspace. KubeVirt/CDI would be another option,
but its APIs are not installed on this cluster.
