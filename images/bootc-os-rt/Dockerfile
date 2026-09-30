# Hummingbird bootc-os with a PREEMPT_RT (real-time) kernel — POC variant.
#
# Swaps the stock Fedora kernel that bootc-os ships for the kernel-rt built
# from the SAME pinned Fedora kernel SRPM (kernel-7.1.8-100.fc43) via the
# spec's own `--with rtonly` flavor toggle — no custom RT packaging. See
# scripts/rt-kernel-build.sh for how the RPMs are produced, and the memory
# note rt-kernel-fedora-srpm for the background.
#
# The result is still a valid, bootable bootc image: it inherits systemd,
# /sbin/init, the bootloader and `bootc` from the base; only the kernel and its
# initramfs change, plus a kargs.d drop-in with RT tuning boot arguments.
#
# ── WHY THIS SHAPE (FROM bootc-os + local RPMs) ──
# This is the POC / dev path, deliberately mirroring images/ros-core-rpms: our
# kernel-rt RPMs are built locally and are NOT yet published to the Hummingbird
# koji repo. The productized shape is a parallel bootc-os *variant* in the
# containers monorepo (images/bootc-os/hummingbird/rt/) whose MAIN_PACKAGES
# replaces `kernel` with `kernel-rt-core kernel-rt-modules-core` and whose
# rpms.lock.yaml pins the kernel-rt NVR — buildable only once the RT RPMs land
# in the Hummingbird repo. See README.md for that mapping.
#
# ── Populating the local RPMs (required before build) ──
# The kernel-rt-* RPMs are NOT committed to git (see .gitignore). Build them
# with scripts/rt-kernel-build.sh on a native x86_64 box, then copy the two
# load-bearing RPMs (plus their deps if any) into ./rpms-rt/ — at minimum:
#     kernel-rt-core-*.rpm  kernel-rt-modules-core-*.rpm
# Build the image on a bootc-os base of the MATCHING arch + Fedora release as
# the kernel SRPM (native; no qemu):
#     podman build -t hummingbird-ros2-poc/bootc-os-rt:latest images/bootc-os-rt

ARG BASE_IMAGE=quay.io/hummingbird-community/bootc-os:latest
FROM ${BASE_IMAGE}

# ── Local repo of the Hummingbird-built kernel-rt RPMs ──
# Staged under /var/tmp (writable, image-local) rather than /opt (a symlink into
# /var on bootc and NOT part of the image). We do NOT add Fedora repos: the RT
# kernel is built from the same SRPM as the stock kernel already in the base, so
# its runtime dependencies are identical and already installed — the local repo
# is the only new source needed. (We install ONLY kernel-rt-core +
# kernel-rt-modules-core, not the kernel-rt meta, so `realtime-setup` is not
# pulled in — it is Required only by the meta.)
COPY rpms-rt/ /var/tmp/rt-rpms/
RUN dnf -y install --setopt=install_weak_deps=0 createrepo_c \
    && createrepo_c /var/tmp/rt-rpms \
    && printf '[rt-local]\nname=Hummingbird kernel-rt (local)\nbaseurl=file:///var/tmp/rt-rpms\nenabled=1\ngpgcheck=0\n' \
         > /etc/yum.repos.d/rt-local.repo \
    # 1. Add the RT kernel (image now has two kernels).
    && dnf -y --setopt=protect_running_kernel=False \
         install kernel-rt-core kernel-rt-modules-core \
    # 2. Remove the stock kernel packages in one transaction. --noautoremove
    #    keeps shared deps (still needed by kernel-rt) installed.
    && STOCK="$(rpm -qa --qf '%{NAME}\n' kernel kernel-core kernel-modules kernel-modules-core kernel-modules-extra 2>/dev/null)" \
    && if [ -n "${STOCK}" ]; then \
         dnf -y --setopt=protect_running_kernel=False remove --noautoremove ${STOCK}; \
       fi \
    # 3. Ensure exactly one modules dir remains (drop any orphaned stock dir,
    #    e.g. a leftover initramfs.img not owned by rpm).
    && find /usr/lib/modules -maxdepth 1 -mindepth 1 -type d ! -name '*+rt*' -exec rm -rf {} + \
    # 4. Regenerate the initramfs for the +rt kernel. The base's dracut config
    #    (usr/lib/dracut/dracut.conf.d/*.conf: ostree + bootc modules) is
    #    inherited, so the new initramfs is bootc/ostree-capable.
    && KVER="$(ls /usr/lib/modules/ | grep -- '+rt' | head -1)" \
    && test -n "${KVER}" || (echo ">>>>> no +rt kernel found <<<<<" && false) \
    && dracut --force --no-hostonly "/usr/lib/modules/${KVER}/initramfs.img" "${KVER}" \
    # 5. Tidy up: remove the transient repo, RPMs and build tool.
    && dnf -y remove createrepo_c \
    && rm -rf /var/tmp/rt-rpms /etc/yum.repos.d/rt-local.repo \
    && dnf clean all \
    && rm -rf /var/cache/* /var/log/dnf* /var/log/hawkey.log /run/dnf

# ── Real-time boot arguments ──
# bootc merges kargs.d drop-ins into the boot loader entry at deploy time.
COPY kargs.d/10-realtime.toml /usr/lib/bootc/kargs.d/10-realtime.toml

# Validate the assembled image (kernel present, still a valid bootc container).
# Not --fatal-warnings: a POC may carry cosmetic dnf-leftover warnings.
RUN bootc container lint --no-truncate || true

# ENTRYPOINT / CMD are intentionally NOT overridden — the image inherits
# CMD ["/sbin/init"] from bootc-os so it stays a valid, bootable bootc image.
