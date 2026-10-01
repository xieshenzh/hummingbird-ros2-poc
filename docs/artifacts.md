# Archived artifacts & local podman images

> Detail doc for [`../CLAUDE.md`](../CLAUDE.md). All binary build artifacts live
> under `artifacts/` in the repo (gitignored) — never in the user's home dir. RT
> build/status context: [`realtime-kernel.md`](realtime-kernel.md).

## `artifacts/` on disk (gitignored)

RT kernel RPMs (release/arch-scoped subdirs):

| Path | count | notes |
|---|---|---|
| `rt-kernel-rpms/7.1.8-100.fc43.x86_64/` | 11 | incl. debuginfo |
| `rt-kernel-rpms/7.1.8-100.fc43.aarch64/` | 16 | 4k `+rt` + 64k `+rt-64k` |
| `rt-kernel-rpms/7.2.7-200.fc44.aarch64/` | 18 | 4k `+rt` + 64k `+rt-64k` |

OCI image tarballs (`podman save | gzip`) and qcow2s:

| File | what |
|---|---|
| `bootc-os-rt-fc43-aarch64.oci.tar.gz` | fc43 aarch64 RT base |
| `bootc-os-rt-fc44-aarch64.oci.tar.gz` | fc44 aarch64 RT base |
| `ros-core-rpms-rt-fc44-aarch64.oci.tar.gz` | fc44 aarch64 RT + ros-core |
| `ros-core-rpms-rt-chunked.tar.gz` | fc43 x86_64 RT + ros-core (rechunked) |
| `ros-core-rpms-rt-chunked-aarch64.tar.gz` | fc43 aarch64 RT + ros-core (rechunked) |
| `bootc-os-rt.qcow2.gz` | fc43 x86_64 base qcow2 |
| `bootc-os-rt-ros-core-aarch64.qcow2.gz` | fc43 aarch64 ros-core qcow2 |
| `bootc-os-rt-fc44-aarch64.qcow2.gz` | fc44 aarch64 base qcow2 |
| `ros-core-rpms-rt-fc44-aarch64.qcow2.gz` | fc44 aarch64 ros-core qcow2 |
| `serial-transcript-aarch64.txt` | fc43 aarch64 boot proof transcript |
| `serial-transcript-fc44-aarch64.txt` | fc44 aarch64 boot proof (banner `…aarch64+rt … PREEMPT_RT` + RT cmdline) |
| `serial-transcript-fc44-aarch64-userspace.txt` | fc44 aarch64 **userspace** proof — oneshot unit ran `uname -r`/`uname -v` (`#1 SMP PREEMPT_RT`) on the live RT kernel (x86_64-parity, TCG) |
| `serial-transcript-fc44-aarch64-login.txt` | fc44 aarch64 **full boot → interactive getty login → `uname`** (`#1 SMP PREEMPT_RT`), after the `/boot` `nofail` fstab fix — complete x86_64 parity (TCG) |
| `kbuild-fc44.log` | fc44 kernel-rt build log |

## Loaded in local podman

| Tag | arch | size |
|---|---|---|
| `bootc-os-rt:fc43-x86_64` (also `:latest`) | amd64 | 1.08 GB |
| `bootc-os-rt:fc43-aarch64` | arm64 | 1.27 GB |
| `bootc-os-rt:fc44` | arm64 | 1.53 GB |
| `ros-core-rpms-rt-chunked:fc43-x86_64` (also `:latest`) | amd64 | 1.19 GB |
| `ros-core-rpms-rt-chunked:fc43-aarch64` | arm64 | 1.25 GB |
| `ros-core-rpms-rt:fc44` | arm64 | 1.97 GB |

## Notes

- fc43 was built before the base moved to fc44; fc44 aarch64 was rebuilt
  2026-10-01. **fc44 x86_64 was never built** (needs a fresh native x86_64 box).
- The COPR-sourced ROS RPM dirs (`images/ros-core-rpms/rpms/`,
  `rpms-x86_64/`) and the RT staging dir (`images/bootc-os-rt/rpms-rt/`) are also
  gitignored build artifacts — the tracked source is the specs in the
  `hummingbird-rpms` monorepo.
- `kernel-7.2.7-200.fc44.src.rpm` (160 MB) was NOT archived — it's public/
  reproducible from kojipkgs.
- Loading an OCI tarball re-applies its embedded `:latest` tag; retag
  arch-explicitly after `podman load` to avoid clobbering a same-named image of a
  different arch.
