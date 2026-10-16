#!/usr/bin/env bash
# Ensure the stock Fedora repos are available for the Hummingbird ROS 2 RPMs.
#
# This image is base-agnostic (ARG BASE_IMAGE). It supports BOTH:
#   * Hummingbird bootc-os  — ships ONLY the Hummingbird repo, NOT the stock
#     Fedora repos, so they must be added here or the ROS closure's ordinary
#     Fedora libraries (gflags, cli11, console-bridge, protobuf, ...) will not
#     resolve. (It also provides spdlog-1.17 via the Hummingbird repo.)
#   * Fedora fedora-bootc  — already ships fedora/updates with GPG keys, so
#     there is nothing to add; this script is then a no-op. (spdlog there is
#     1.15, so the base-switch PoC stages spdlog-1.17 into the local ROS repo —
#     see docs/base-switch-poc.md.)
#
# Two bootc quirks this handles on the Hummingbird base:
#   1. No stock Fedora repos (added below).
#   2. The Fedora RELEASE must be detected from the actual package disttag, NOT
#      from `rpm -E %fedora`: on the current Hummingbird base the %fedora macro
#      is pinned to 43 while the userspace/kernel are fc44 (verified 2026-10-07),
#      so %fedora would author fedora-43 repos onto an fc44 system. We derive the
#      release from an installed stock package's disttag instead.
set -euxo pipefail

# If the stock Fedora repos are already present and enabled (fedora-bootc),
# there is nothing to do.
if dnf -q repolist --enabled 2>/dev/null | grep -qiE '^(fedora|updates)[[:space:]]'; then
  echo "enable-repos: stock Fedora repos already enabled — nothing to add."
  exit 0
fi

# Detect the real Fedora release from a stock package's disttag (fcNN), falling
# back to %fedora only if that fails. Query BOTH kernel flavors: on the
# PREEMPT_RT base the stock kernel is swapped for kernel-rt-core, so
# kernel-core is ABSENT — its failed query also killed this script under
# pipefail before the fallback could run (found building ros-core-rpms-rt,
# 2026-10-16). rpm prints the "not installed" line to stdout, but it contains
# no fcNN so the grep below still only matches the real disttag.
FED="$(rpm -q --qf '%{release}\n' kernel-core kernel-rt-core 2>/dev/null \
        | grep -oE 'fc[0-9]+' | head -1 | tr -dc '0-9' || true)"
if [ -z "${FED}" ]; then
  FED="$(rpm -qa --qf '%{release}\n' 2>/dev/null \
          | grep -oE 'fc[0-9]+' | sort | uniq -c | sort -rn | head -1 \
          | grep -oE 'fc[0-9]+' | tr -dc '0-9' || true)"
fi
if [ -z "${FED}" ]; then
  FED="$(rpm -E %fedora)"
fi

# Ensure the Fedora release GPG key is available LOCALLY before writing the repos.
# dnf fetches a repo's gpgkey URL once, with no retry, at transaction time — and
# the canonical per-release key on src.fedoraproject.org (dist-git raw) is
# frequently 503, so a single blip fails the whole build. Derive the key from the
# stable combined keyring (fedoraproject.org/fedora.gpg) into an armored
# per-release file, and only fall back to the dist-git URL if that fails.
LOCALKEY="/etc/pki/rpm-gpg/RPM-GPG-KEY-fedora-${FED}-primary"
if [ ! -s "$LOCALKEY" ]; then
  tmpk="$(mktemp)"
  if curl -fsSL --retry 3 https://fedoraproject.org/fedora.gpg -o "$tmpk"; then
    export GNUPGHOME="$(mktemp -d)"
    gpg --import "$tmpk" 2>/dev/null || true
    gpg --armor --export "fedora-${FED}-primary@fedoraproject.org" > "$LOCALKEY" 2>/dev/null || true
  fi
  if [ ! -s "$LOCALKEY" ]; then
    curl -fsSL --retry 6 --retry-all-errors --retry-delay 3 \
      "https://src.fedoraproject.org/rpms/fedora-repos/raw/f${FED}/f/RPM-GPG-KEY-fedora-${FED}-primary" \
      -o "$LOCALKEY"
  fi
  # Clean the transient keyring/temp files so nothing is left in /tmp — bootc
  # container lint (nonempty-run-tmp) fails on leftover content in /run and /tmp.
  rm -rf "${tmpk:-}" "${GNUPGHOME:-}"
  unset GNUPGHOME
fi
GPGKEY="file://${LOCALKEY}"

# Release is the detected disttag (not $releasever) so these resolve despite the
# Hummingbird base's snapshot $releasever override; $basearch is left for dnf.
cat > /etc/yum.repos.d/fedora.repo <<EOF
[fedora]
name=Fedora ${FED} - \$basearch
metalink=https://mirrors.fedoraproject.org/metalink?repo=fedora-${FED}&arch=\$basearch
gpgcheck=1
gpgkey=${GPGKEY}
enabled=1

[updates]
name=Fedora ${FED} - updates - \$basearch
metalink=https://mirrors.fedoraproject.org/metalink?repo=updates-released-f${FED}&arch=\$basearch
gpgcheck=1
gpgkey=${GPGKEY}
enabled=1
EOF
