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
        golang-go \
        libssl-dev \
        libostree-dev \
        libzstd-dev \
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

# Debian Bookworm's libostree predates the native-container CLI. Build the
# ostree-ext CLI from the published crate so hybrid assembly can encapsulate
# the OSTree commit without requiring a privileged container.
RUN mkdir -p /tmp/ostree-ext-cli/src
RUN cat > /tmp/ostree-ext-cli/Cargo.toml <<'EOF'
[package]
name = "ostree-ext-cli-wrapper"
version = "0.1.0"
edition = "2021"

[dependencies]
anyhow = "1"
ostree-ext = "=0.15.2"
tokio = { version = "1", features = ["rt-multi-thread", "macros"] }
EOF
RUN cat > /tmp/ostree-ext-cli/src/main.rs <<'EOF'
#[tokio::main]
async fn main() -> anyhow::Result<()> {
    ostree_ext::cli::run_from_iter(std::env::args()).await
}
EOF
RUN cd /tmp/ostree-ext-cli && cargo build --release && install -m 0755 target/release/ostree-ext-cli-wrapper /usr/bin/ostree-ext-cli && rm -rf /tmp/ostree-ext-cli /root/.cargo/registry /root/.cargo/git

RUN set -eux; \
    kas --version; \
    buildah --version; \
    chunkah --help >/dev/null; \
    ostree --version; \
    ostree-encap --help >/dev/null; \
    skopeo --version

RUN mkdir -p /workspace && chmod 0777 /workspace

WORKDIR /workspace

# BitBake refuses to run as root. OpenShift may replace this UID with the
# namespace-assigned non-root UID under its SCC, which is also supported.
USER 1001
