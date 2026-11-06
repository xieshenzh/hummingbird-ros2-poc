# bootc — no OE recipe exists upstream (verified: zero layer-index hits).
# Rust binary driving OCI-image-based OS updates; links libostree.
# Pinned to v1.1.0 — the newest release that builds on scarthgap's rust
# 1.75 (workspace rust-version = 1.75, edition2021, lock has ZERO git deps
# and predates the c-string-literal/edition2024 drift: v1.1.6+ pulls the
# composefs-rs git dep; v1.1.7+ needs cargo >= 1.85). Verified clean
# `cargo check` with scarthgap's native cargo. Repo: containers/bootc
# moved to bootc-dev/bootc.
LICENSE = "MIT | Apache-2.0"
LIC_FILES_CHKSUM = "file://LICENSE-MIT;md5=b377b220f43d747efdec40d69fcaa69d \
                    file://LICENSE-APACHE;md5=fa818a259cbed7ce8bc2a22d35a464fc"

SRC_URI = "git://github.com/bootc-dev/bootc;protocol=https;branch=main"
SRCREV = "49dbe70ce6b304e5afb995bd09fcc50c1ca58f9b"
PV = "1.1.0"
S = "${WORKDIR}/git"

# crates are resolved from Cargo.lock on the first do_update_crates run;
# the generated bootc-crates.inc gets committed once stable.
inherit cargo cargo-update-recipe-crates pkgconfig
include bootc-crates.inc

# -sys crates probe the target sysroot via pkg-config
DEPENDS = "ostree glib-2.0 openssl"

# build only the CLI package — the workspace's dev tools (xtask etc.) hit
# OE's panic=abort + thin-LTO rustc quirk and are not needed on target
CARGO_BUILD_FLAGS += "--package bootc"

# OE's rust-cross can't link panic=abort binaries (panic_abort strategy
# mismatch) — drop it from the release profile; plain unwind is fine here
do_configure:append() {
    sed -i '/^panic = "abort"$/d' ${S}/Cargo.toml
}
RDEPENDS:${PN} = "ostree"

FILES:${PN} += "${systemd_unitdir}/system ${systemd_unitdir}/system-preset"

do_install:append() {
    install -d ${D}${systemd_unitdir}/system
    install -m 0644 ${S}/systemd/*.service ${S}/systemd/*.timer \
        ${D}${systemd_unitdir}/system/ 2>/dev/null || true
    install -d ${D}${systemd_unitdir}/system-preset
    echo 'enable bootc-fetch-apply-updates.timer' > \
        ${D}${systemd_unitdir}/system-preset/90-bootc.preset
}
