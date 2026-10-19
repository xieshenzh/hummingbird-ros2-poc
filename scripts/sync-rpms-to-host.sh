#!/usr/bin/env bash
# Sync ROS 2 Jazzy package dirs (spec + changelog + sources) from the Lima VM
# clone to the host hummingbird-rpms repo and commit. Tarballs stay gitignored.
# Usage: sync-rpms-to-host.sh "commit message"
set -euo pipefail
MSG="${1:?commit message required}"
HOST_REPO=/Users/xiezhang/IdeaProjects/hummingbird/hummingbird-rpms

# 1) (Re)generate sources files in the VM for every package that has a tarball.
limactl shell fedora -- bash -lc '
cd ~/hummingbird-rpms/rpms
for d in ros-jazzy-*/; do
  d=${d%/}; spec="$d/$d.spec"; [ -f "$spec" ] || continue
  base=$(grep -m1 "^Source0:" "$spec" | sed -E "s/.*#\///")
  [ -n "$base" ] && [ -f "$d/$base" ] || continue
  h=$(sha512sum "$d/$base" | cut -d" " -f1)
  printf "SHA512 (%s) = %s\n" "$base" "$h" > "$d/sources"
done
'

# 2) Stream spec/changelog/sources into the host repo.
cd "$HOST_REPO"
limactl shell fedora -- bash -lc \
  'cd ~/hummingbird-rpms && tar cf - rpms/ros-jazzy-*/*.spec rpms/ros-jazzy-*/changelog rpms/ros-jazzy-*/sources 2>/dev/null' \
  | tar xf -

# 3) Clean macOS AppleDouble/junk, stage, commit (no push).
# Optional attribution trailer for the commit — e.g. when an AI assistant
# drives the sync:
#   SYNC_TRAILER="Assisted-by: <who> <noreply@example.com>" \
#     ./sync-rpms-to-host.sh "commit message"
# Default: NO extra trailer. (This script previously hardcoded a
# "Co-Authored-By: Claude" trailer onto every commit regardless of which
# assistant — or human — ran it, mis-attributing the work; keep attribution
# with whoever actually drives the sync.)
find rpms/ros-jazzy-* -name '._*' -delete 2>/dev/null || true
find rpms -name '.DS_Store' -delete 2>/dev/null || true
git add rpms/ros-jazzy-*
if git diff --cached --quiet; then
  echo "nothing to commit"
else
  if [ -n "${SYNC_TRAILER:-}" ]; then
    git commit -q -m "$MSG" -m "$SYNC_TRAILER"
  else
    git commit -q -m "$MSG"
  fi
  git log --oneline -1
fi