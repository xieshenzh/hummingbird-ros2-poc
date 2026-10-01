# Established facts (verified during design)

> Detail doc for [`../CLAUDE.md`](../CLAUDE.md). Covers the base image, the tavie
> COPR, the two bootc-os quirks, Gazebo-on-Fedora, and the rationale for the key
> choices. For the *Hummingbird-built RPM* path see
> [`ros-core-rpms.md`](ros-core-rpms.md).

- **Base image:** `quay.io/hummingbird-community/bootc-os:latest`
  - Fedora 43 based; ships `dnf5`, `python3`, `systemd`, `curl`, `ca-certificates`.
  - It is a bootc image: `CMD ["/sbin/init"]`, `LABEL containers.bootc=1`, ships a kernel.
  - On a booted bootc system `/usr` is immutable/image-managed; `/opt`, `/home`,
    `/root`, `/usr/local` are symlinks into writable `/var` and are NOT in the OS image.
  - ⚠️ **Base moved fc43 → fc44 (2026-09-30):** `:latest` now ships stock kernel
    `7.2.7-200.fc44` (generic-only, no RT) on both arches. python3 stays 3.14.
- **ROS packages:** `tavie/ros2` COPR (community, unofficial).
  - Supports Fedora 43, ROS 2 **Jazzy**. **x86_64 ONLY** — the COPR has no
    aarch64 build for fedora-43 (`fedora-43-aarch64/repodata/repomd.xml` => 404).
    All COPR-sourced images here are x86_64-only. (Confirmed 2026-08-28.)
  - Fedora **FHS layout**: installs under `/usr`, NOT `/opt/ros`.
  - Package names (f42+) match the Ubuntu deb names: `ros-jazzy-ros-core`,
    `ros-jazzy-ros-base`, `ros-jazzy-ament-package` (needed for setup scripts).
  - Setup scripts live at **`/usr/lib64/ros-jazzy/setup.bash`** (and `.sh`) —
    prefix is **`ros-<distro>`** (hyphen), provided by `ros-jazzy-ament-package`.
    NOTE: an earlier draft said `ros2-jazzy` (with a "2") — that path does NOT
    exist; verified via `dnf repoquery --whatprovides`.
  - RPMs are built against the base Fedora's **system Python** — do not add a
    second `python3`.
  - Repo file: `enable-repos.sh` now **authors the `.repo` directly** against the
    COPR results backend (`download.copr.fedorainfracloud.org/results/tavie/ros2/
    fedora-$FED-$basearch/`, gpgkey `.../results/tavie/ros2/pubkey.gpg`) instead
    of `curl`-ing the frontend generator
    (`copr.fedorainfracloud.org/coprs/tavie/ros2/repo/...`). Reason (hit during
    the first real build, 2026-08-29): the frontend generator was returning
    **502 / connection-reset** while the results backend stayed **200** — the
    generated file just points at that backend anyway, so we skip the flaky
    round-trip. Release still pinned to `rpm -E %fedora`, not `$releasever`.

## Two bootc-os quirks break the COPR install

Both handled by `enable-repos.sh` (verified 2026-08-28):

1. **No stock Fedora repos.** bootc-os enables only
   `public-hummingbird-x86_64-rpms` (+ our COPR). The tavie ROS RPMs need
   ordinary Fedora libraries (`gflags`, `cli11`, `console-bridge`,
   `protobuf`, ...), so we must add the `fedora` + `updates` repos or nothing
   resolves — even `ros-core` fails without them.
2. **`$releasever` override.** bootc-os sets dnf's `$releasever` to a snapshot
   id (e.g. `20251124-1.15.hum1`, from `VERSION_ID`) while `rpm -E %fedora`
   still reports `43`. The COPR baseurl is `fedora-$releasever-$basearch`, so
   it 404s. We bake the real release (`rpm -E %fedora`) into the baseurls
   rather than touching the global `$releasever` (which bootc's own repo
   resolution relies on).

Verified dry-run transaction sizes on fedora-43 x86_64: ros-core 373 pkgs,
ros-base 558, simulation 1068, gazebo (gz-sim-vendor) 798.

## Gazebo on Fedora

There is NO standalone `gazebo` / `gz-sim` package in Fedora's repos. The only
packaged Gazebo Harmonic comes from tavie as ROS-namespaced **vendor** RPMs:
`ros-jazzy-gz-sim-vendor`, `ros-jazzy-gz-tools-vendor` (the `gz` CLI),
`ros-jazzy-gz-rendering-vendor`, etc. They install under
`/usr/lib64/ros-jazzy/opt/<pkg>/...`; the `gz` binary is NOT on PATH until the
prefix `setup.bash` is sourced. ROS 2 Jazzy pairs with Gazebo **Harmonic**
(gz-sim 8.x). The ROS<->Gazebo bridge is `ros-jazzy-ros-gz` (pulls
`ros-gz-bridge` / `-sim` / `-interfaces` / `-image`). See
[`simulation-gazebo.md`](simulation-gazebo.md) for the boost blocker and the
sim-bundle workaround.

## Why these choices

- **tavie COPR over RHEL ROS repo:** RHEL ROS installs to `/opt/ros`, which on a
  bootc system is a symlink into `/var` and would NOT survive `bootc upgrade`.
  tavie's `/usr` (FHS) layout lives in the immutable image layer — the whole
  point of building on bootc-os.
- **`.repo` file drop over `dnf copr enable`:** self-contained, no COPR plugin
  dependency, mirrors the reference Dockerfile's "write sources.list" step.
- **ENTRYPOINT/CMD left unset:** inherits `CMD ["/sbin/init"]` from bootc-os so
  the image stays bootable. Container use is served by `ros-entrypoint.sh`
  (`--entrypoint`) and `/etc/profile.d/ros2.sh` (interactive/login shells).

## Repo/key caveats

- **Fedora GPG keys:** bootc-os ships none, so `enable-repos.sh` points the
  `fedora`/`updates` repos at the online Fedora key
  (`src.fedoraproject.org/.../RPM-GPG-KEY-fedora-<rel>-primary`); dnf imports it
  at install. If that URL/layout changes, the key import breaks.
- **Python version coupling:** bootc-os system python must match what the COPR
  RPMs were built against (Fedora 43 system python3; RPMs seen under python3.14).
- `enable-repos.sh` is duplicated across the two `FROM bootc-os` contexts
  (ros-core, gazebo) — keep the copies in sync (or refactor to a shared base).
