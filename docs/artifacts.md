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
| `rt-kernel-rpms/7.2.7-200.fc44.x86_64/` | 8 | `+rt` (built on c7i.4xlarge; same 7.2.7 SRPM as aarch64) |

OCI image tarballs (`podman save | gzip`) and qcow2s:

| File | what |
|---|---|
| `bootc-os-rt-fc43-aarch64.oci.tar.gz` | fc43 aarch64 RT base |
| `bootc-os-rt-fc44-aarch64.oci.tar.gz` | fc44 aarch64 RT base |
| `bootc-os-rt-fc44-x86_64.oci.tar.gz` | fc44 x86_64 RT base (1.06 GB image; base pinned to 7.2.7 digest `sha256:1eec04be…`) |
| `ros-core-rpms-rt-fc44-aarch64.oci.tar.gz` | fc44 aarch64 RT + ros-core |
| `ros-base-rpms-rt-fc44-aarch64.oci.tar.gz` | fc44 aarch64 RT + ros-base (2.52 GB image; fresh 2026-10-16 build, fixed spdlog; booted + RT-verified + suites 184/0/0) |
| `ros-base-rpms-rt-chunked-fc44-aarch64.tar.gz` | fc44 aarch64 RT + ros-base (rechunked 2.52→1.73 GB; kernel in its own 175 MB layer) |
| `simulation-rpms-rt-fc44-aarch64.oci.tar.gz` | fc44 aarch64 RT + ros-base + Gazebo simulation — the 2026-10-16 build (3.43 GB; physics + bridge verified; **superseded** by the 2026-10-19 row below) |
| `simulation-rpms-rt-chunked-fc44-aarch64.tar.gz` | **fc44 aarch64 RT + ros-base + Gazebo simulation — 2026-10-19 GUI-runtime + official-parity rebuild** (rechunked 3.52→2.49 GB, kernel in its own 175 MB layer; gz-ui/Xvnc GUI, ENTRYPOINT parity, `bootc container lint` 14/1/0; verified + loaded in the macOS podman machine) |
| `ros-core-rpms-rt-fc44-x86_64.oci.tar.gz` | fc44 x86_64 RT + ros-core (1.54 GB image) |
| `ros-core-rpms-rt-chunked.tar.gz` | fc43 x86_64 RT + ros-core (rechunked) |
| `ros-core-rpms-rt-chunked-aarch64.tar.gz` | fc43 aarch64 RT + ros-core (rechunked) |
| `ros-core-rpms-rt-chunked-fc44-x86_64.tar.gz` | fc44 x86_64 RT + ros-core (rechunked 1.54→1.18 GB; kernel in its own 75.3 MB layer) |
| `ros-core-rpms-rt-chunked-fc44-aarch64.tar.gz` | fc44 aarch64 RT + ros-core (rechunked 1.97→1.25 GB; kernel in its own 175 MB layer; done natively on local arm64 podman) |
| `bootc-os-rt.qcow2.gz` | fc43 x86_64 base qcow2 |
| `bootc-os-rt-ros-core-aarch64.qcow2.gz` | fc43 aarch64 ros-core qcow2 |
| `bootc-os-rt-fc44-aarch64.qcow2.gz` | fc44 aarch64 base qcow2 |
| `ros-core-rpms-rt-fc44-aarch64.qcow2.gz` | fc44 aarch64 ros-core qcow2 |
| `bootc-os-rt-fc44-x86_64.qcow2.gz` | fc44 x86_64 base qcow2 (the one booted for the login RT proof) |
| `serial-transcript-aarch64.txt` | fc43 aarch64 boot proof transcript |
| `serial-transcript-fc44-aarch64.txt` | fc44 aarch64 boot proof (banner `…aarch64+rt … PREEMPT_RT` + RT cmdline) |
| `serial-transcript-fc44-aarch64-userspace.txt` | fc44 aarch64 **userspace** proof — oneshot unit ran `uname -r`/`uname -v` (`#1 SMP PREEMPT_RT`) on the live RT kernel (x86_64-parity, TCG) |
| `serial-transcript-fc44-aarch64-login.txt` | fc44 aarch64 **full boot → interactive getty login → `uname`** (`#1 SMP PREEMPT_RT`), after the `/boot` `nofail` fstab fix — complete x86_64 parity (TCG) |
| `serial-transcript-fc44-x86_64.txt` | fc44 x86_64 boot proof (banner `…x86_64+rt … #1 SMP PREEMPT_RT` + RT cmdline `preempt=full nowatchdog`, TCG) |
| `serial-transcript-fc44-x86_64-login.txt` | fc44 x86_64 **full boot → interactive getty login → `uname`** (`#1 SMP PREEMPT_RT`, verify exit 0) — complete parity, TCG |
| `serial-rosbase-rt-aarch64.txt` | **ros-base-rpms-rt** boot proof (2026-10-16, TCG): banner `…aarch64+rt … #1 SMP PREEMPT_RT` + getty login + live `uname` + `preempt=full nowatchdog` cmdline (rt-serial-verify rc=0) |
| `serial-rosbase-rt-ros-aarch64.txt` | ros_base on the **booted RT VM** over serial (2026-10-16): `ros2 pkg list` = 192 + Fast-DDS pub/sub round-trip PASS; the rosbag2 leg hit a 400 s harness timeout mid-cold-start (TCG artifact — rosbag2 passes in-container on the same image) |
| `kbuild-fc44.log` | fc44 kernel-rt build log |

## Loaded in local podman

> The host's macOS podman machine (`podman-machine-default`, applehv, 6 CPU /
> 16 GB / 186 GB, rootful, managed via Podman Desktop) holds the image set.
> ⚠️ Agent/sandboxed shells: `XDG_CONFIG_HOME` may be redirected, which makes
> the podman CLI blind to the machine + connections — export
> `XDG_CONFIG_HOME=~/.config XDG_DATA_HOME=~/.local/share` first.

| Tag | arch | size |
|---|---|---|
| `bootc-os-rt:fc43-x86_64` (also `:latest`) | amd64 | 1.08 GB |
| `bootc-os-rt:fc43-aarch64` | arm64 | 1.27 GB |
| `bootc-os-rt:fc44-aarch64` | arm64 | 1.53 GB |
| `bootc-os-rt:fc44-x86_64` | amd64 | 1.06 GB |
| `ros-core-rpms-rt-chunked:fc43-x86_64` (also `:latest`) | amd64 | 1.19 GB |
| `ros-core-rpms-rt-chunked:fc43-aarch64` | arm64 | 1.25 GB |
| `ros-core-rpms-rt-chunked:fc44-x86_64` | amd64 | 1.18 GB |
| `ros-core-rpms-rt-chunked:fc44-aarch64` | arm64 | 1.25 GB |
| `ros-core-rpms-rt:fc44-aarch64` | arm64 | 1.97 GB |
| `ros-core-rpms-rt:fc44-x86_64` | amd64 | 1.54 GB |

Loaded in the **macOS podman machine** (as of 2026-10-19; the earlier
base-switch/ros-base images from Oct 13–15 are still there too):

| Tag | arch | size |
|---|---|---|
| `ros-base-rpms-rt:fc44-aarch64` (fresh 2026-10-16 rebuild, fixed spdlog) | arm64 | 2.52 GB |
| `ros-base-rpms-rt-chunked:fc44-aarch64` | arm64 | 1.73 GB |
| `simulation-rpms-rt:fc44-aarch64` / `-chunked:fc44-aarch64` / `-chunked:latest` (2026-10-19 GUI-runtime + parity rebuild, chunked 2.49 GB, native smoke-test) | arm64 | 2.49 GB |

The Lima `fedora` VM's rootless podman also carries both fresh ros-base tags plus
`simulation-rpms-rt:latest` and `simulation-rpms-rt-chunked:latest` (where they
were built). The older pre-spdlog-fix `ros-base-rpms-rt:latest` (2.51 GB,
2026-10-15) is still in the macOS machine's store, as is the superseded
2026-10-16 `simulation-rpms-rt:latest` (3.43 GB, untagged from `:fc44-aarch64`).

## Notes

- fc43 was built before the base moved to fc44; fc44 was rebuilt on **both** arches
  2026-10-01 → a matched **7.2.7** pair pinned to base child digest
  `sha256:1eec04befdd1d30370fe7adf1dce1d38d66ee329680827c35cd817b6c0f40ce4` (the
  live base had since bumped to 7.2.8 — see `realtime-kernel.md` Strategy A).
- The COPR-sourced ROS RPM dirs (`images/ros-core-rpms/rpms/`,
  `rpms-x86_64/`) and the RT staging dir (`images/bootc-os-rt/rpms-rt/`) are also
  gitignored build artifacts — the tracked source is the specs in the
  `hummingbird-rpms` monorepo.
- `kernel-7.2.7-200.fc44.src.rpm` (160 MB) was NOT archived — it's public/
  reproducible from kojipkgs.
- Loading an OCI tarball re-applies its embedded `:latest` tag; retag
  arch-explicitly after `podman load` to avoid clobbering a same-named image of a
  different arch.
