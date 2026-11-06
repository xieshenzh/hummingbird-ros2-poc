# libostree + ostree CLI — no OE recipe exists upstream (meta-updater is
# stale since 2023), so this is the Phase-1 graft. bootc needs:
#   - libostree (storage backend for bootc)
#   - ostree CLI
#   - ostree-prepare-root (runs from the initramfs to assemble the root)
# Pinned to upstream release v2026.6. Upstream build system is AUTOTOOLS
# (autogen.sh + configure.ac), not meson.
LICENSE = "LGPL-2.0-or-later"
LIC_FILES_CHKSUM = "file://COPYING;md5=5f30f0716dfdd0d91eb439ebec522ec2"

SRC_URI = "gitsm://github.com/ostreedev/ostree;protocol=https;branch=main"
SRCREV = "b8e8afe3e5e57d4c003204fcdc9c3517a464878e"
PV = "2026.6"
S = "${WORKDIR}/git"

inherit autotools-brokensep pkgconfig

DEPENDS = "glib-2.0 glib-2.0-native libarchive curl e2fsprogs openssl xz zlib systemd bison-native"

# PoC flags (verified against configure.ac AC_ARG_* list): curl fetch
# backend only (libsoup is meta-oe), no gpg, no composefs (Phase 1 = plain
# ostree backend), no dracut/mkinitcpio/avahi, systemd journal on.
EXTRA_OECONF = "\
    --with-curl \
    --without-soup \
    --without-soup3 \
    --without-gpgme \
    --without-composefs \
    --without-dracut \
    --without-mkinitcpio \
    --without-avahi \
    --with-libsystemd \
    --disable-rofiles-fuse \
    --disable-man \
    --disable-man-html \
"

# ostree's bootstrap (generates libglnx/Makefile-libglnx.am.inc etc.) lives
# in autogen.sh — but its internal autoreconf fights the OE cross env, so we
# replicate only the file-generation bits and let the class autoreconf
do_configure:prepend() {
    cd ${S}
    mkdir -p m4
    printf 'EXTRA_DIST =\nCLEANFILES =\n' > gtk-doc.make
    sed -e 's,$(libglnx_srcpath),libglnx,g' < libglnx/Makefile-libglnx.am > libglnx/Makefile-libglnx.am.inc
    sed -e 's,$(libbsdiff_srcpath),bsdiff,g' < bsdiff/Makefile-bsdiff.am > bsdiff/Makefile-bsdiff.am.inc
    ln -sf ../libglnx/libglnx.m4 buildutil/libglnx.m4
}

# The static prepare-root binary must land where the initramfs expects it
FILES:${PN} += "\
    ${nonarch_base_libdir}/ostree/prepare-root \
    ${libdir}/tmpfiles.d \
    ${libdir}/systemd/system \
    ${libdir}/systemd/system-generators \
    ${datadir}/bash-completion \
"
