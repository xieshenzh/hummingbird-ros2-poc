# Yocto PoC journal

## 2026-10-30 — Phase 0 kickoff

### Environment
- Lima VM `fedora`: Fedora 43 (Cloud), aarch64, 10 vCPU, 24 GB RAM, 62 GB free
  on `/` (78G volume). Project dir is mounted **read-only** in the VM
  (virtiofs, nfs_t) → build in VM-native `$HOME` (same pattern as the
  hummingbird-rpms workflow).
- Decision: **poky `scarthgap` (4.0 LTS)** — support into 2028, well-tested
  `linux-yocto-rt` (6.6-rt, full PREEMPT_RT), natural pairing with meta-ros
  Jazzy for Phase 1.5. (Newest branch is walnascar 5.1, but scarthgap is the
  LTS; green/purple on the branch list are ancient 3.x, not releases.)

### Choices
- MACHINE=qemuarm64 — everything native arm64 (no emulation anywhere; the
  qemux86-64 alternative would force an emulated podman stage later).
- RT kernel = `linux-yocto-rt` (PREEMPT_RT patched series). Verification
  target: `uname -v` contains `PREEMPT_RT` (TCG proves RT-live; cyclictest
  numbers need real hardware/KVM, as with the Fedora RT images).
- kas for manifest-driven builds so the same tree builds in the Lima VM and
  later on EC2 (sstate shared via rsync).

### Steps
1. Host-deps in VM (dnf): gawk make git python3 python3-pip patch wget socat
   tar file xz gzip bzip2 zstd lz4 findutils hostname perl-FindBin
   perl-File-Compare perl-File-Copy perl-lib perl-IPC-Cmd ...
2. kas via venv (Fedora 43 is PEP 668): `python3 -m venv ~/venvs/kas`
   `pip install kas`
3. `kas build kas/phase0.yaml` (KAS_WORK_DIR=~/yocto/kas-work, native fs)
4. Verify: runqemu nographic, login root, `uname -v` → PREEMPT_RT

(Results appended below as they land.)

## 2026-10-30 — Phase 0 COMPLETE ✅

Build: `kas build kas/phase0.yaml` — cold build ~2.5 h (10 vCPU, all cores
saturated, task 4199/4199 clean). Artifacts: 75 MB ext4 rootfs +
`Image--6.6.151+git...` (linux-yocto-rt, the ONLY kernel recipe built).

Startup failures fixed (in order):
1. kas: missing parent for KAS_WORK_DIR/build → mkdir -p in vm-kas.sh
2. manifest listed `meta-yocto` — doesn't exist in scarthgap (qemuarm64
   lives in oe-core `meta`); dropped
3. host tools missing: `chrpath diffstat which` (dnf)
4. bitbake sanity: perl `Thread::Queue` missing → `perl(Thread::Queue)`
5. bitbake sanity: perl `open` pragma missing — hummingbird-built perl 5.42
   (fc43 rawhide-ish userspace) doesn't package `open.pm`; `dnf install
   perl-open` (Fedora repo) fixes it. **VM quirk to remember.**
6. runqemu nographic quoting via `kas shell -c` mangled → drive qemu directly
7. `-nographic` muxes serial+monitor on stdio → use
   `-display none -serial stdio -monitor none` (input previously went to
   monitor, not guest)
8. root login rejected: `core-image-minimal` without `debug-tweaks` locks
   root (empty password refused) → add `debug-tweaks` to
   EXTRA_IMAGE_FEATURES; rebuild is minutes (everything else cached)

Verification (scripts/rtcheck.py, pexpect-driven qemu in VM):
```
Linux qemuarm64 6.6.151-rt31-yocto-preempt-rt #1 SMP PREEMPT_RT ... aarch64
```
Full boot → serial login → uname → poweroff, all scripted. RT-live proven
under TCG (same standard as the Fedora bootc-os-rt images; latency numbers
need real hardware).

## 2026-10-30 — Phase 1 kickoff (scaffolding, not yet building)

Recipe-availability findings (blocker #1/#2 confirmed by search):
- **ostree: NO recipe anywhere indexed** (layer index: zero hits; poky: none).
  Only prior art = `advancedtelematic/meta-updater` — last pushed 2023-06,
  stale vs scarthgap. Decision: write our own recipe in meta-hb-bootc.
- **bootc: zero recipes** (as before). Repo MOVED: containers/bootc →
  **bootc-dev/bootc** (active daily). Latest release v1.17.3.

Scaffolded in meta-hb-bootc:
- `recipes-extended/ostree/ostree_git.bb` — pinned v2026.6
  (b8e8afe), meson, gpg/ro-fuse/selinux off. EXPECTS ITERATION: meson
  option names, prepare-root static build + initramfs placement.
- `recipes-containers/bootc/bootc_git.bb` — pinned v1.17.3 (ffde873e),
  cargo + cargo-update-recipe-crates (bootc-crates.inc generated on first
  build, then committed), systemd units/preset.
- `recipes-core/images/hb-bootc-image.bb` — core-image-minimal + ostree +
  bootc + rt-tests; ROOTFS_POSTPROCESS_COMMAND lays out the bootc contract
  (kernel Image → /usr/lib/modules/$kver/vmlinuz, initramfs alongside, BLS
  entry, prepare-root.conf).
- `kas/phase1.yaml` — poky scarthgap + meta-hb-bootc, target hb-bootc-image.

Next session: `kas build kas/phase1.yaml` and iterate (expect ostree meson
option fixes first, then bootc crate fetch, then image layout, then
`bootc container lint` on the podman-wrapped tarball, then TCG boot with
`bootc status`. The initramfs must run ostree-prepare-root — real graft).

## 2026-10-30/31 — Phase 1 iteration log (in progress)

Fixed in sequence (each verified by a rebuild):
1. kas local-layer path resolves against KAS_WORK_DIR → vm-sync now also
   rsyncs meta-hb-bootc into ~/yocto/kas-work/
2. LICENSE fields missing (parse halt) → added to both recipes
3. `MIT OR Apache-2.0` invalid in OE → `MIT | Apache-2.0`
4. libsoup-3 not in poky → ostree curl fetch backend (`--with-curl`)
5. ostree is AUTOTOOLS, not meson (upstream v2026.6 has no meson.build!)
   → rewrote recipe as autotools-brokensep
6. submodules (libglnx, bsdiff) not fetched → `gitsm://` fetcher
7. autogen.sh's own autoreconf fights OE cross env (macro paths) →
   replicate only its sed/gtk-doc.make bits in do_configure:prepend, let
   the class autoreconf
8. bison needed at build time → bison-native
9. gpgme auto-required → flags verified against configure.ac AC_ARG_*
   (--without-gpgme --without-soup --without-soup3 --without-composefs
   --without-dracut --without-mkinitcpio --without-avahi --disable-
   rofiles-fuse --with-libsystemd)
10. `Nothing PROVIDES systemd` → poky defaults to sysvinit; bootc needs
    systemd pid1 → INIT_MANAGER = "systemd" (sstate hit, expected)
11. glib-mkenums missing at build → glib-2.0-native
12. unshipped files (systemd units, tmpfiles, generator, completions) →
    FILES: mappings. NOTE: ostree-prepare-root.service + system generator
    now packaged — exactly the boot-path pieces we need.

STATUS: ostree 2026.6 BUILDS + PACKAGES on qemuarm64/scarthgap. ✅

### Strategic findings (2026-10-31)
- **poky master is an empty umbrella repo** (README + .gitignore only) —
  the Yocto project restructured poky into components in 2026. Release
  branches (scarthgap/walnascar) still work as before. There is no
  post-walnascar release branch on the poky repo.
- **Rust skew:** scarthgap cargo = 1.75; walnascar cargo = 1.84. bootc
  v1.1.7+ workspace uses edition2024 (needs cargo >= 1.85) → **bootc
  pinned to v1.1.6** (2025-03-03; edition2021, Cargo.lock v3, no
  edition2024 deps — verified by inspection). bootc repo moved
  containers/bootc → bootc-dev/bootc.
- Consequence to remember: on newer OE releases with rust >= 1.85,
  re-pin bootc to current.

NEXT: bootc cargo build (crate fetch + cross-compile), then image
assembly, podman wrap, bootc lint, TCG boot.

## 2026-10-31 — Phase 1 deployment: Yocto rootfs → ostree-native bootc container → installed + booted

Build side was done (hb-bootc-image: RT kernel + ostree + bootc v1.1.0 +
bootc layout). This section is the deployment half — every hard-won fact.

### bootc-image-builder: ABANDONED
`bwrap: execvp /run/osbuild/runner/org.osbuild.linux: No such file or
directory` — BIB's osbuild pipeline uses a distro-specific runner; unknown
distros (poky) get the generic `org.osbuild.linux` runner which fails in the
image pipeline. Spoofing os-release to centos would risk Fedora-specific
bootloader stages. Pivoted to bootc v1.1.0's own installer + an
**ostree-native container** (what upstream bootc CI does).

### ostree-native container from a Yocto rootfs
No packaged tool exists anymore: `ostree container commit` CLI is gone,
`ostree-ext-cli` is not packaged and its repo moved/disappeared in the 2026
restructure (github.com/ostreedev/ostree-ext → 404/auth prompt). Wrote
**~/ostree-encap** (VM): ~30-line Rust bin calling
`ostree_ext::container::encapsulate` (ostree-ext 0.15.2 from crates.io,
built with poky's native cargo via ~/cargo-bin symlinks — do NOT put poky's
native bin dir on PATH wholesale, its `rpm` breaks Fedora's multilib
pkg-config wrapper, exit 127).

Tree fixes required before `ostree commit` + encapsulate succeed
(all scripted in scripts/wrap-bootc-container.sh):
1. symlinks with target >100 chars (ca-certificates) → replace with copies;
   the tar exporter's link-name field overflows. MUST run before the /etc
   move — the symlinks are relative and dangle under /usr/etc.
2. `/etc` → `/usr/etc` (ostree convention; exporter maps it back, so
   keeping both duplicates every path).
3. no `/var/tmp` in the commit — ostree-ext synthesizes one and its
   "already present" check compares unprefixed paths, so a Yocto-style
   populated /var/tmp duplicates.
4. `/ostree -> sysroot/ostree` symlink (bootc install reads /ostree/repo).
5. labels `ostree.bootable=true` + `containers.bootc=1` (encapsulate Config).

Result: `podman pull oci:...` works, `bootc container lint` → "Checks
passed: 3". Pushed to a local registry:2 (localhost:5000) — needed for
Phase 2 anyway.

### bootc install to-filesystem: the toolchain gap
bootc v1.1.0's installer shells out to tools the minimal Yocto image
doesn't ship. Solved by bind-mounting the VM host's binaries through
loader-shim wrappers (/tmp/skopeo-wrap, scripts/bootc-install-target.sh):
skopeo, findmnt, lsblk, blkid, fstrim, fsfreeze, sfdisk, podman, conmon,
crun, netavark (host /lib+/lib64 mounted read-only; wrapper execs the host
ld-linux directly). Also required:
- GPT target with an ESP (plain filesystem image → sfdisk "no partition
  table" failure) — script creates 4G disk, 512M ESP + root, loop-mounts
- `--disable-selinux` (Yocto files picked up Fedora SELinux xattrs during
  extraction on the VM, which flips bootc's target-SELinux detection)
- permissive policy.json + insecure localhost:5000 registries.conf
  (baked into usr/etc/containers in the image: bootc overlays
  /etc/containers from the image's own copy)
- bootupctl stubbed out (no bootupd/grub in the image — qemu
  direct-kernel verification doesn't need a bootloader; productization
  would ship grub-efi + bootupd)
- `--pid=host --network=host --privileged`, /var/lib/containers + /dev
  bind mounts

"Installation complete!" — real ostree deployment on target: BLS entry
ostree-1.conf, kernel+initramfs under /boot/ostree/<stateroot-hash>/,
kargs `root=UUID=... ostree=/ostree/boot.1/default/<hash>/0`.

### Booting the deployment (qemu TCG, direct kernel)
- ostree v2026.6 renamed the binary: `ostree-prepare-root`, not
  `prepare-root` (initramfs module now tries both).
- initramfs-framework quirks vs dracut's ostree module:
  - initramfs must have /sysroot dir (prepare-root bind-mounts the
    physical root onto <deploy>/sysroot → symlink → /sysroot)
  - the deployment must carry a `sysroot -> /sysroot` symlink; libostree's
    admin-deploy path creates it, the container-deploy path does NOT.
    Added post-install (remount rw + chattr -i first — bootc finalized
    the target read-only/immutable)
- Bitbake gotcha (again): editing the initramfs module alone does NOT
  re-run hb-bootc-image do_rootfs (sstate) — the rootfs tarball kept the
  old initramfs.img; needs `bitbake -c rootfs -f hb-bootc-image`.

Scripts (all run in the Lima VM, synced from the repo):
- scripts/wrap-bootc-container.sh — tarball → fixed tree → ostree commit →
  encapsulate → podman + localhost:5000 (ends with `bootc container lint`)
- scripts/bootc-install-target.sh — fresh GPT disk → bootc install
  to-filesystem (all host-binary shims) → post-fixes → export
  kernel/initrd/kargs → release disk
- scripts/bootccheck-deployed.py — pexpect TCG boot of the installed disk
  with the BLS kargs; asserts PREEMPT_RT + `bootc status` deployment

## 2026-10-31 — Phase 1 COMPLETE: bootc recognizes the deployment

After the disk booted but `bootc status` said "System is not deployed via
bootc", the fix chain (each step exposed the next gap):

1. **`/run/ostree-booted` lost at switch_root.** bootc/libostree recognize
   an ostree boot via that marker, stamped by prepare-root into the
   initramfs /run tmpfs. initramfs-framework's finish.sh moves /dev,
   /proc, /sys onto the new root but NOT /run — busybox switch_root
   discards it. Fix: the ostree initramfs module now ends with
   `mount --move /run $ROOTFS_DIR/run`.

2. **That exposed the missing `/sysroot` mount (var.mount ELOOP →
   emergency mode).** With /run surviving, ostree's systemd generator
   output (var.mount) also survived — and failed: the deployment's
   `sysroot -> /sysroot` symlink made prepare-root bind the physical root
   at the *initramfs* /sysroot, which busybox switch_root drops (systemd's
   switch-root keeps it — that's the flow prepare-root is designed for).
   Result: /sysroot in the real root is a self-referential symlink.
   Fix: at install time, replace the deployment's sysroot symlink with a
   real directory — then prepare-root binds the physical root *inside*
   the deployment at <deploy>/sysroot, where it travels through
   switch_root. (First attempted in the initramfs module with
   rm-symlink + `mount --move`; that persisted on the rw deployment and
   broke the *second* boot — install-time is the right, idempotent place.)

3. **`bootc status` → "Reexec self: No such file or directory".** bootc
   re-execs itself through `unshare -m` to get a private mount namespace;
   the minimal image didn't ship unshare. Fix: `util-linux-unshare`
   added to hb-bootc-image.

Final state: `bootc status --json` reports
`"type":"bootcHost"`, booted image `localhost:5000/hb-bootc:v2`
(transport registry, imageDigest sha256:4b1ea969…, store ostreeContainer),
PREEMPT_RT live, clean multi-user boot — verified on TWO consecutive
boots of the same disk (idempotent).

Bitbake gotcha #2 (ordering): `bitbake -c rootfs -f initramfs-hb-bootc`
does NOT run do_image, so a following `rootfs -f hb-bootc-image` bakes the
OLD deploy cpio.gz into the rootfs; the final `bitbake hb-bootc-image`
regenerates the cpio.gz but only re-tars the stale rootfs. Correct order:
`bitbake -c rootfs -f initramfs-hb-bootc && bitbake initramfs-hb-bootc &&
bitbake -c rootfs -f hb-bootc-image && bitbake hb-bootc-image`. Always
verify the tarball's initramfs.img content before wrapping.

bootccheck-deployed.py: serial-console pexpect is echo-heavy — the echoed
command line contains the prompt pattern and literal `$?` markers. Output
is captured via `cmd > /tmp/hbout` + `cat` with a `HB$?DONE` sentinel that
only the executed line (HB<rc>DONE) can match.

## Phase 2: bootc upgrade + interrupted-upgrade (2026-11-02, DONE)

v2 → v3 via `bootc switch` on the booted disk, verified end to end
(`scripts/phase2-upgrade-test.py`), plus a SIGKILL-mid-upgrade test
(`scripts/phase2-interrupt-test.py`). Both PASS.

### What was built

- **v3 image**: one-recipe bump only — `HB_VERSION` in hb-bootc-image.bb
  stamps `/etc/hb-version`. Wrap+push to the local registry as before.
  Caught mid-test: the first "v2" rebuild already carried the v3 stamp
  (both commits said v3, `ostree diff` empty) — the version assertion was
  vacuous. Rebuilt a true v2 (stamp `v2`) and re-ran everything clean.
- **static skopeo baked into the image**: bootc's pull path
  (ostree-ext ImageProxy → containers-image-proxy) shells out to a
  `skopeo` binary the minimal image doesn't have — `bootc switch` died
  with "Creating importer: i/o error: No such file or directory".
  Built skopeo v1.16.1 static (CGO_ENABLED=0, build tag
  `containers_image_openpgp` to drop gpgme) and the wrap script bakes it
  at /usr/bin/skopeo. Productization gap: use a proper OE recipe
  (meta-virtualization has skopeo) instead of /tmp/skopeo-static.
- Registry reachability: guest reaches the VM registry via the qemu
  user-net gateway 10.0.2.2:5000 (guest's own localhost:5000 is
  unreachable). The image's registries.conf ships both.

### Hard-won facts

1. **bootc switch rewrites the boot layout** (loader.1 → loader.0, and a
   mirror at boot/loader). Any previously exported kargs are stale —
   "ostree-prepare-root: Couldn't find specified OSTree root .../boot.1/...".
   The test exports boot assets from the disk before every boot,
   selecting the deployment by its `.origin`
   (container-image-reference=...:vN) — NOT by dir name, BLS mtime, or
   deploy-dir mtime (booting a deployment touches its dir).
2. **bootc-switch-created deployments have NO `sysroot` entry** (the
   Phase 1 install-time fix replaced a symlink; switch deployments have
   nothing at all) → prepare-root's physical-root bind
   (mount(root, /sysroot.tmp/sysroot), ostree-prepare-root.c:427) fails
   ENOENT. Fix: repair from the HOST on the rw loop mount (chattr -i, rm
   -f, mkdir) — /sysroot is read-only in the running guest, so a
   guest-side fix silently fails. Deployments are created at serial
   subindices (.0, .1, .2...), so glob `deploy/*/`.
3. **A backgrounded `bootc switch` fails on its own** with "invalid
   reference format" from the image proxy (foreground to the same
   reference works). To kill mid-transaction, run the switch in the
   foreground and arm a background watcher:
   `(sleep 5; kill -9 $(pgrep -f 'bootc switch')) & bootc switch ...`.
4. **Guest-side TOML writes are a quoting minefield**: writing
   registries.conf via `echo "registries = [\"10.0.2.2:5000\"]"` loses
   the inner quotes at some layer → unquoted `10.0.2.2:5000` → TOML
   "Invalid float value" (or a confusing "invalid reference format" from
   the pull path). Use `printf '%s\n' '...' '...'` with single-quoted
   args and cat the file back to verify.
5. **Non-fatal bootc error**: switch/upgrade prints `ERROR Switching:
   Staging: Pruning: Listing images: No such file or directory` (prune
   stage, after successful staging) — judge success by the staged
   deployment in `bootc status --json`, not by absence of stderr.
6. BusyBox `head` doesn't take `-40` (use `head -n 40`).

### Measured delta (one-recipe bump v2 → v3)

- `ostree diff` rollback→booted: exactly one modified file,
  `/usr/etc/hb-version` (v2\n → v3\n).
- Registry images: 197 MB each (v1 without skopeo: 160 MB; the static
  skopeo costs ~19 MB uncompressed). Layer delta between v2 and v3 is
  just the stamp file.

### Interrupted upgrade (kill -9 mid-pull)

Switch to v1 (never pulled by this disk → real 61 MB fetch over qemu
user-net), SIGKILL 5 s in — bootc dies mid-"Fetched layers". After: the
booted deployment is untouched (`bootc status` unchanged), and a reboot
comes up cleanly on the same deployment with PREEMPT_RT. Transactional
safety holds: the staged/partial state never affects the running system.

Also observed: an interrupted switch can leave a partial deployment as
the boot default — the interrupt test re-runs the host-side sysroot
repair + asset export before every boot, which is also what a real
bootloader rollback path (booting the previous BLS entry) exercises.

## Phase 1.5a: meta-ros Jazzy ros_core closure (2026-11-02, IN PROGRESS)

Goal: build `ros-image-core` (meta-ros, scarthgap + Jazzy) for qemuarm64,
standalone first, then fold into hb-bootc-image (1.5b).

### Build host: EC2 c8i? — actually `ubuntu@ec2-3-128-87-0.us-east-2.compute.amazonaws.com`

- x86_64, 16 vCPU, 30 GB RAM, 145 GB gp3 root, **Ubuntu 24.04.5** (picked
  over AL2023 for first-class Yocto build-host docs; deps via the standard
  apt list).
- Sync: `rsync -az yocto-poc/ …:yocto-poc/` (commit e1c33b6 is not pushed —
  never push without being asked).
- kas venv: `apt install python3.12-venv` first (Ubuntu 24.04 images lack
  it), then `python3 -m venv ~/venvs/kas && pip install kas` (kas 5.5).
- `KAS_WORK_DIR=$HOME/yocto/kas-work` — **mkdir -p it first**: kas's
  `os.mkdir(ctx.build_dir)` does not create parents (first run died with
  FileNotFoundError).

### Ubuntu 24.04 AppArmor vs BitBake user namespaces

BitBake sanity check fails: "User namespaces are not usable by BitBake,
possibly due to AppArmor" (Ubuntu 24.04 restricts unprivileged userns).
The documented per-binary AppArmor profile (`profile bitbake
/home/ubuntu/venvs/kas/bin/python3.12 flags=(unconfined) { userns, }`
+ `apparmor_parser -r`) did NOT fix it (kas re-execs via bin/bitbake
shebang; the exec path never matched). Working fix — global sysctl:

```
echo kernel.apparmor_restrict_unprivileged_userns=0 | \
  sudo tee /etc/sysctl.d/99-bitbake.conf && sudo sysctl -p ...
```

(Instance-scoped PoC build; acceptable. On a hardened host, revisit the
profile matching the actual exec path.)

### kas/phase1-5.yaml

Replicates meta-ros's reference `kas/oeros-scarthgap-jazzy` combo with the
exact pins from their `build` branch: OE-core `70dc1594`, bitbake `cff3be6f`
(2.8), meta-openembedded `b5874ea0`, meta-ros `c93b6b4` (scarthgap); layers
meta-ros-common + meta-ros2 + meta-ros2-jazzy, distro `ros2`. Deviations:
- `machine: qemuarm64` (our pipeline target)
- optional clang / clang-revival / lts-mixins / qt fragments DROPPED — add
  back only if the closure build demands them
- `INIT_MANAGER = "systemd"` from the start (hb-bootc needs pid1 systemd;
  avoids rebuilding the closure in 1.5b)
- `INHERIT += "rm_work"` (disk headroom), `WARN_QA:remove = "license-exists"`

Build: `nohup kas build kas/phase1-5.yaml > ~/logs/phase1-5-build.log 2>&1`
— ~7726 tasks; running as of 17:38 UTC 2026-11-02 (task 2046 at the 5-min
mark).

### Phase 1.5b: hb-bootc-image + ros_core (2026-11-03, BUILT)

- `kas/phase1-5b.yaml` = the 1.5 layer stack + `meta-hb-bootc`, target
  `hb-bootc-image`, RT kernel + initramfs + systemd as in phase1.yaml.
- `hb-bootc-image.bb`: `IMAGE_INSTALL:append:ros2 = " ros-core"` — the
  distro-name override fires only under meta-ros's ros2 distro; the poky
  phase1 build is untouched. (Checked meta-ros's ros-image-core.bb: the
  `ros_distro_*` / `*_image` class inherits only affect package recipes
  and the image basename — an image that just installs the built closure
  doesn't need them.)
- **kas path-repo gotcha (EC2):** kas resolved `path: meta-hb-bootc`
  against `KAS_WORK_DIR` (`${TOPDIR}/../meta-hb-bootc` in bblayers.conf),
  not the manifest's own tree. Fix: `ln -s ~/yocto-poc/meta-hb-bootc
  ~/yocto/kas-work/meta-hb-bootc`. Also git-init the rsynced tree so kas
  can compute the manifest repo root.
- Result (7 min, 7654/7904 from sstate, 0 errors):
  `hb-bootc-image-qemuarm64.rootfs.tar.bz2` **100 MB** (491 MB ext4;
  pre-ROS image was 71 MB tar / 160 MB container). Verified inside the
  tarball: `opt/ros/jazzy/bin/ros2`, `usr/bin/bootc`,
  `usr/lib/modules/6.6.147-rt31-yocto-preempt-rt/vmlinuz`,
  `etc/hb-version`. Kernel = linux-yocto-rt 6.6.147-rt31.
- Next: pull tarball + kernel + initramfs to the Lima VM, re-run the
  wrap → bootc install → TCG boot pipeline unchanged.

### Phase 1.5b verification + v4→v5 upgrade (2026-11-03, DONE)

- **Deployed-boot check** (`bootccheck-deployed.py`, extended): the
  installed v4 disk boots under TCG with PREEMPT_RT, `bootc status
  --json` reports `type: bootcHost` / booted `localhost:5000/hb-bootc:v4`
  (digest be12382e…), and — new assertion — `. /opt/ros/jazzy/setup.sh
  && ros2 --help` works, `ros2 pkg list` = **124 packages**. The ROS
  check self-skips on images without /opt/ros.
- **Image-size quirk:** changing `HB_VERSION ?=` in the recipe did NOT
  invalidate `do_rootfs` (sstate kept serving the old stamp; `bitbake -e`
  showed the new value but the dry-run said up-to-date). Fix for PoC
  iteration: `kas shell … -c "bitbake -C rootfs hb-bootc-image"`.
- `phase2-upgrade-test.py` parameterized: `argv [from_tag] [to_tag]`
  (defaults v2 v3 — the original run is unchanged).
- **v4 → v5 `bootc switch`** on the ROS-bearing disk (100 MB tarball /
  491 MB ext4 per version): PASS — new deployment booted, v4 retained as
  rollback, `/etc/hb-version` = v5, PREEMPT_RT live. Transactional
  upgrade semantics hold with the full ROS closure in the image; the
  one-file delta model still applies (only the stamp changed).

Phase 1.5 status: **DONE** — Yocto source-built ros_core + RT kernel +
ostree/bootc in one image, booted, ROS-verified, and transactionally
upgradable.

### Phase 3: chunkah rechunking + chunked upgrade test (2026-11-03, DONE)

Goal: rechunk the Yocto bootc images with chunkah (content-based layers,
like the Fedora stack) and prove install + boot + transactional upgrade
on the chunked images under bootc 1.1.0.

**The format problem.** bootc 1.1.0 (newest buildable on scarthgap's
rust 1.75) uses ostree-ext's *encapsulated* image contract
(`container/store.rs parse_manifest_layout`): layer 0 must be an
ostree-repo tar ("ostree layer"), the `ostree.final-diffid` label names
the target layer, layers before/after map to object-store chunks /
derived plain-tar layers. Three dead ends, each mapped to that code:

1. chunkah-rechunked ostree-encap image: the chunked layer 0 is no
   longer a valid repo tar → "Missing xattrs reference".
2. plain single-layer image (podman import) with the label patched to
   the last layer: a plain tar cannot be unencapsulated → "Commit
   object not found".
3. hybrid with a *populated* base commit: chunk layers re-delivered the
   rootfs's embedded `/sysroot/ostree/repo` objects → `ostree
   rev-parse --single` (bootc install's source-info probe) saw >1
   commit → "Multiple commit objects found".

**The working hybrid format** (`assemble-chunked-bootc.py`):
- layer 0 = ostree-encap'd *near-empty* base commit, built from a tree
  of just symlinks + placeholder files:
  - usrmerge/ostree compat symlinks: `bin lib sbin -> usr/…`,
    `opt -> usr/opt`, `root home srv -> var/…`, `ostree ->
    sysroot/ostree` (bootc's runtime sysroot probe needs the last one)
  - `dev proc sys boot run tmp/.hb-keep` — ostree cannot store empty
    dirs, but the initramfs switch_root and systemd need these
    mountpoints; `.hb-keep` files are shadowed by the runtime mounts
- layers 1..N = chunkah chunks (max-layers 32), imported through
  ostree-ext's **derived-layer** path
- config: one history entry per layer (`layers_with_history()` demands
  it — "Truncated history"), `ostree.final-diffid` → the base layer's
  uncompressed diffID

**Rootfs prep that makes chunks importable** (wrap-plain-container.sh,
steps 4b-4d): strip `sysroot/ostree` (the repo comes from layer 0);
move `opt → usr/opt` — ostree-ext's tar filter keeps only
`usr`/`etc`/`var` content, everything else at top level (including
compat symlinks) is silently dropped; `tar --hard-dereference`
round-trip to break hardlink groups (1067 in the ROS rootfs — the
identical ament `.dsv` env files) that chunkah splits across layers
("Failed to find object").

`bootc-install-target.sh` still creates `sysroot` as a real dir in each
deployment (unchanged); it also mkdirs `dev/proc/sys/boot` for installs
where the base layer predates the placeholder fix.

**Results (v4k/v5k, 33 layers each, 132 MB):**
- install: PASS — `bootc install to-filesystem` unencapsulates the
  empty base + imports 32 chunks as derived layers
- boot: PASS — PREEMPT_RT, `bootc status` type bootcHost, ROS 2 works
  (`ros2 pkg list` = 124) via `/usr/opt`
- `bootc switch` v4k→v5k: PASS — **"layers already present: 32; layers
  needed: 1 (54.0 MB)"**; booted v5k, v4k rollback, `/etc/hb-version`
  v5. ostree content diff between the two commits: exactly one file,
  `M /usr/etc/hb-version`.
- Known wart: `bootc switch` exits 1 at `Pruning: Listing images` —
  bootc's prune shells out to `podman` (imgstorage.rs `new_image_cmd`),
  which the minimal Yocto image doesn't carry. Harmless: the new
  deployment is fully staged. A productized image would add podman or a
  later bootc would use the image-proxy API.
- The 54 MB "one layer" is chunkah's bigfile split (kernel/initramfs
  land in one chunk); the *shared* 32 layers are the compressed content
  — this is the same shape as the Fedora stack's rechunked images.

Phase 3 status: **DONE** — chunkah-rechunked Yocto bootc images are
installable, bootable, and transactionally upgradable under bootc
1.1.0, with 32/33 layers shared across image versions.

### Phase 3 refactor: rootfs fixes moved into the build (2026-11-03)

Follow-up to the chunking work: two of the end-of-pipeline patches were
really rootfs *shape* problems, so they now run at image build time and
apply to every artifact (tarball, plain image, chunked image):

- `hb_bootc_usr_layout` (hb-bootc-image.bb): /opt → /usr/opt + compat
  symlink. Was a manual step in wrap-plain-container.sh.
- `hb_deref_hardlinks`: breaks bitbake/sstate hardlink groups (cp -p
  round-trip per file). Was a `tar --hard-dereference` round-trip.

Validated standalone against the pristine v4 rootfs: 1067 hardlinks →
0, opt symlink resolves, `/opt/ros/jazzy/bin/ros2` intact. The recipe
wiring itself gets proven at the next bitbake image build.

What deliberately stays at the assembly stage (they are properties of
the *ostree image format*, not of the rootfs):
- the encapsulated base commit (now codified in
  `scripts/build-encap-base.sh` instead of ad-hoc commands; reproduces
  the exact working base payload — verified entry-for-entry)
- history entries / `ostree.final-diffid` (assemble-chunked-bootc.py)
- `bootc-install-target.sh`'s deployment fixups (sysroot dir, runtime
  mountpoint mkdirs — the latter redundant since the base commit gained
  `.hb-keep` placeholders, kept for pre-placeholder installs)
