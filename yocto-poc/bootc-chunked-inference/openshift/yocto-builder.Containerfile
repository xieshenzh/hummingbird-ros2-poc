# Phase 4 OpenShift builder image.
# The image deliberately derives from the official KAS image instead of a
# generic distro image so the BitBake host dependency set stays aligned with
# the KAS release.
FROM ghcr.io/siemens/kas/kas:5.2-debian-bookworm

USER root

RUN apt-get update && apt-get install -y --no-install-recommends \
        buildah \
        ca-certificates \
        curl \
        git \
        libssl-dev \
        ostree \
        pkg-config \
        skopeo \
        zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

# Chunkah v0.7.1 uses Rust edition 2024, which is newer than Debian
# Bookworm's packaged Cargo. Install a current stable toolchain in the image
# so the compiled binary remains ABI-compatible with this Debian base.
ENV PATH=/root/.cargo/bin:$PATH
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | \
    sh -s -- -y --profile minimal --default-toolchain stable

# Build Chunkah against this image's glibc. The published Fedora-based
# Chunkah image cannot be copied directly into Debian Bookworm because its
# binary requires a newer GLIBC than the KAS base provides.
ARG CHUNKAH_TAG=v0.7.1
RUN git clone --depth 1 --branch "$CHUNKAH_TAG" https://github.com/coreos/chunkah.git /tmp/chunkah && \
    cd /tmp/chunkah && \
    cargo build --release --locked && \
    install -m 0755 target/release/chunkah /usr/bin/chunkah && \
    rm -rf /tmp/chunkah /root/.cargo/registry /root/.cargo/git

# The project class historically called a small helper named ostree-encap.
# Keep that stable interface, but use the upstream OSTree implementation in
# the builder image. The class passes: REPO REF DESTINATION.
RUN cat > /usr/bin/ostree-encap <<'EOF' && chmod 0755 /usr/bin/ostree-encap
#!/bin/sh
set -eu
if [ "$#" -eq 1 ] && [ "$1" = "--help" ]; then
    echo 'usage: ostree-encap REPO REF DESTINATION'
    exit 0
fi
test "$#" -eq 3
exec ostree container encapsulate --repo="$1" "$2" "$3"
EOF

RUN set -eux; \
    kas --version; \
    buildah --version; \
    chunkah --help >/dev/null; \
    ostree --version; \
    ostree-encap --help >/dev/null; \
    skopeo --version

WORKDIR /workspace
