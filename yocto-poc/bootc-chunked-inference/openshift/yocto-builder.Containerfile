### Build-only stages
#
# Keep compilers, headers, source trees, and package-manager state out of the
# final KAS/BitBake builder.  The resulting image is a ready-to-run build
# dependency, not a toolchain image that compiles itself at PipelineRun time.
FROM ghcr.io/siemens/kas/kas:5.2-debian-bookworm AS go-tool-builder

USER root
ARG GO_VERSION=1.25.7
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates curl git \
    && rm -rf /var/lib/apt/lists/* \
    && curl --fail --location --retry 3 \
        "https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz" \
        | tar -C /usr/local -xz
ENV PATH=/usr/local/go/bin:$PATH
RUN git clone --depth 1 --branch v1.24.1 \
        https://github.com/containers/skopeo /tmp/skopeo && \
    cd /tmp/skopeo && \
    CGO_ENABLED=0 GOOS=linux GOARCH=arm64 \
        go build -tags containers_image_openpgp -trimpath \
        -o /usr/local/libexec/chunked-bootc-skopeo-static ./cmd/skopeo

FROM ghcr.io/siemens/kas/kas:5.2-debian-bookworm AS rust-tool-builder

USER root
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates curl git libssl-dev libostree-dev libzstd-dev \
        pkg-config zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*
ENV PATH=/root/.cargo/bin:$PATH
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | \
    sh -s -- -y --profile minimal --default-toolchain stable

# Chunkah is compiled against this image's glibc. The published Fedora-based
# binary cannot be copied directly into Debian Bookworm because it requires a
# newer GLIBC than the KAS base provides.
ARG CHUNKAH_TAG=v0.7.1
RUN git clone --depth 1 --branch "$CHUNKAH_TAG" https://github.com/coreos/chunkah.git /tmp/chunkah && \
    cd /tmp/chunkah && \
    cargo build --release --locked && \
    install -D -m 0755 target/release/chunkah /out/usr/bin/chunkah

# Build the ostree-ext CLI wrapper in the build-only stage as well.
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
RUN cd /tmp/ostree-ext-cli && cargo build --release && \
    install -D -m 0755 target/release/ostree-ext-cli-wrapper \
      /out/usr/bin/ostree-ext-cli

### Final, ready-to-use builder stage
# The image is built and digest-pinned before a promotion PipelineRun starts.
FROM ghcr.io/siemens/kas/kas:5.2-debian-bookworm

USER root
RUN apt-get update && apt-get install -y --no-install-recommends \
        buildah \
        ca-certificates \
        git \
        libostree-dev \
        libzstd-dev \
        ostree \
        pkg-config \
        skopeo \
        zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

COPY --from=go-tool-builder /usr/local/libexec/chunked-bootc-skopeo-static \
    /usr/local/libexec/chunked-bootc-skopeo-static
COPY --from=rust-tool-builder /out/usr/bin/chunkah /usr/bin/chunkah
COPY --from=rust-tool-builder /out/usr/bin/ostree-ext-cli /usr/bin/ostree-ext-cli

# The project class historically called a small helper named ostree-encap.
# Keep that stable interface, but use the compiled ostree-ext implementation.
RUN cat > /usr/bin/ostree-encap <<'EOF' && chmod 0755 /usr/bin/ostree-encap
#!/bin/sh
set -eu
if [ "$#" -eq 1 ] && [ "$1" = "--help" ]; then
    echo 'usage: ostree-encap REPO REF DESTINATION'
    exit 0
fi
test "$#" -eq 3
exec /usr/bin/ostree-ext-cli container encapsulate --repo "$1" "$2" "$3"
EOF

RUN set -eux; \
    kas --version; \
    buildah --version; \
    chunkah --help >/dev/null; \
    ostree --version; \
    ostree-encap --help >/dev/null; \
    skopeo --version; \
    test -x /usr/local/libexec/chunked-bootc-skopeo-static

RUN mkdir -p /workspace && chmod 0777 /workspace

WORKDIR /workspace

# BitBake refuses to run as root. OpenShift may replace this UID with the
# namespace-assigned non-root UID under its SCC, which is also supported.
USER 1001
