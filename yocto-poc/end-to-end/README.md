# End-to-end: Yocto builds the layered bootc image

Everything for the Phase 3/4 result — one `kas build` producing the
chunkah-layered, bootc-installable image — lives in this folder, kept
separate from the base PoC (phases 0-2, `meta-hb-bootc`).

```
kas/phase3.yaml           the single kas manifest (extends ../../kas/phase1-5b.yaml:
                           minimal bootc + ros_core, plus the classes below)
meta-hb-e2e/               classes-only OE layer (added to BBLAYERS by phase3.yaml)
  classes/hb-oci.bbclass     single-layer OCI image via buildah (IMAGE_FSTYPES oci)
  classes/hb-chunkah.bbclass chunkah re-split + the bootc-installable hybrid
                             (encapsulated base commit + chunks as derived layers)
  scripts/assemble-chunked-bootc.py  hybrid assembler (layer 0 + chunk layers)
scripts/
  build-encap-base.sh       standalone base-commit builder (used while developing
                            the format; the class now does this in-tree)
  patch-oci-final-diffid.py patch ostree.final-diffid into an image manifest
```

## Run it (Lima VM)

```bash
scripts/vm-sync.sh                                        # syncs both layers into kas-work
scripts/vm-kas.sh build end-to-end/kas/phase3.yaml        # ~2.5 h cold; artifacts in
                                                          # kas-work/build/tmp-glibc/deploy/images/qemuarm64/
# then the shared validation scripts (../scripts/):
skopeo copy oci:<hybrid.oci> docker://localhost:5000/hb-bootc:v7
bash ../scripts/bootc-install-target.sh v7
/usr/bin/python3 ../scripts/bootccheck-deployed.py        # TCG boot: PREEMPT_RT + ROS
/usr/bin/python3 ../scripts/phase2-upgrade-test.py v6 v7  # bootc switch + rollback
```

Build-host prerequisites (chunkah, buildah, ostree, ostree-encap, static
skopeo) and the full list of bitbake/pseudo gotchas: see
`../docs/journal.md`, "Phase 3 end-to-end". Bump `HB_VERSION` in
`kas/phase3.yaml` per release.
