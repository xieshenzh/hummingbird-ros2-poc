#!/usr/bin/env bash
# Build a PREEMPT_RT kernel from the pinned Fedora kernel SRPM used by
# Hummingbird bootc-os, via `--with rtonly` (builds ONLY kernel-rt*).
#
# Runs rpmbuild inside a rootful fedora:43 podman container so the host distro
# (AL2023) is irrelevant. Native x86_64 only (no qemu). Intended to run on a
# >=16 vCPU / >=30 GB box.
#
# Env:
#   WITH_DEBUGINFO=1  build the debuginfo subpackages too (production build;
#                     slower, more RAM/disk). Default: omit for a fast pass.
#   SRPM=...          override the SRPM filename (must sit in $WORK).
set -euo pipefail

WORK="${WORK:-$HOME/rtbuild}"
SRPM="${SRPM:-kernel-7.1.8-100.fc43.src.rpm}"
WITH_DEBUGINFO="${WITH_DEBUGINFO:-0}"
if [ "$WITH_DEBUGINFO" = "1" ]; then
  DBG_FLAG=""            # let the spec build debuginfo (default)
else
  DBG_FLAG="--without debuginfo"
fi
cd "$WORK"

echo "=== $(date -u) rt-kernel-build start (SRPM=$SRPM WITH_DEBUGINFO=$WITH_DEBUGINFO) ==="

sudo podman run --rm -v "$WORK":/work:z -w /work fedora:43 bash -euxo pipefail -c '
  SRPM="'"$SRPM"'"
  DBG_FLAG="'"$DBG_FLAG"'"
  dnf -y install rpm-build dnf-plugins-core rpmdevtools cpio >/dev/null

  echo "### spec sanity: RT switches present? (non-fatal)"
  { rpm2cpio "$SRPM" | cpio -i --quiet --to-stdout "kernel.spec" > /tmp/kernel.spec; } || true
  grep -nE "with_rtonly|with_realtime|include_rt" /tmp/kernel.spec | head -20 || true

  echo "### installing build deps"
  dnf -y builddep --define "_with_rtonly 1" "$SRPM"

  echo "### rpmbuild --with rtonly $DBG_FLAG"
  rpmbuild --rebuild --with rtonly $DBG_FLAG \
    --define "_topdir /work/rpmbuild" "$SRPM"

  echo "### RESULTING RPMS:"
  ls -la /work/rpmbuild/RPMS/*/ 2>/dev/null || true
'

echo "=== $(date -u) rt-kernel-build DONE ==="