# Open questions / risks & provenance

> Detail doc for [`../CLAUDE.md`](../CLAUDE.md).

## Open questions / risks

- **Native `simulation`/`gazebo` BLOCKED by the boost 1.83-vs-1.90 skew** — the
  main unresolved blocker; full analysis + the sim-bundle workaround in
  [`simulation-gazebo.md`](simulation-gazebo.md).
- **Image size:** ros-core = 1.96 GB (base 909 MB + ~1.05 GB ROS layer);
  simulation/gazebo far larger. Breakdown + mitigations in
  [`verification.md`](verification.md).
- **Gazebo rendering:** gz-sim's GUI/sensors need OpenGL/GPU (ogre-next). Headless
  server (`gz sim -s`) works in a container; the GUI needs GPU/display passthrough
  (software GL works on native x86_64 — see [`simulation-gazebo.md`](simulation-gazebo.md)).
- **arm64:** tavie is x86_64-only, so the COPR-sourced images
  (`gazebo`/`simulation`/`sim-bundle`) stay x86_64-only. RESOLVED for the base
  stack: we built the `ros_core` RPMs ourselves for aarch64 too
  ([`ros-core-rpms.md`](ros-core-rpms.md)) — `images/ros-core-rpms` runs natively
  on arm64. Extending that to `ros-base`/Gazebo would lift the arch limit.
- **Fedora GPG keys / Python coupling / duplicated `enable-repos.sh`** — see
  [`established-facts.md`](established-facts.md).
- **RT open items** (Secure Boot signing, fc44 x86_64, cyclictest on KVM) — see
  [`realtime-kernel.md`](realtime-kernel.md).

## Provenance

Design conversation ran in `../containers` (the Hummingbird containers repo).
Reference upstream: `osrf/docker_images` (generated Dockerfiles) and
`osrf/docker_templates` (the `.em` empy templates). ROS 2 base metapackages are
defined in `ros2/variants` (`ros_core`, `ros_base` `package.xml`) and turned into
packages via bloom — the Dockerfiles only reference the metapackage name.

### Upstream reference Dockerfiles — where each variant lives (verified 2026-08-30)

- **ROS 2 variants** (`osrf/docker_images`, path
  `ros/jazzy/ubuntu/noble/<variant>/Dockerfile`): SIX variants are *defined* —
  `ros-core`, `ros-base`, `perception`, `simulation`, `desktop`, `desktop-full`
  (= REP 2001). But the **official Docker Library (`library/ros`) only publishes
  `ros-core`, `ros-base`, `perception`** as pullable tags.
  `simulation`/`desktop`/`desktop-full` are defined + buildable-from-source but NOT
  published (GUI/size). So "the upstream simulation variant" = the *Dockerfile* +
  the `ros-jazzy-simulation` metapackage; there is NO `ros:jazzy-simulation` tag.
  Our sim-bundle `simulation` reproduces that Dockerfile (`FROM ros-base` +
  `ros-jazzy-simulation`); it contains the Gazebo runtime because the metapackage
  deps (`ros_gz` → the sim) pull it — same as upstream.
- **Gazebo Classic (v4–11)**: `osrf/docker_images` under `gazebo/<ver>/...`
  (Ubuntu/Debian, apt from `packages.osrfoundation.org`). Entrypoint convention:
  `source setup.sh; exec "$@"`, `ENTRYPOINT ["/gzserver_entrypoint.sh"]`,
  `CMD ["gzserver"]`, `EXPOSE 11345` (Classic master port — N/A to modern gz,
  which uses gz-transport UDP multicast discovery).
- **Modern Gazebo (gz-sim, Harmonic)**: NOT in `osrf/docker_images`. Lives in
  **`gazebosim/gz-sim/docker/`** — `Dockerfile.base`, `Dockerfile.gz` (main),
  `Dockerfile.nightly`. `Dockerfile.gz` is a **GPU/GUI workstation** image:
  `FROM nvidia/opengl:1.2-glvnd-devel-ubuntu20.04`, apt-installs
  `${gz_distribution}` from the OSRF repo, creates a non-root `developer` user +
  sudo, `ENTRYPOINT ["gz sim"]`. It sets NO `GZ_*`/`GAZEBO_*` env (relies on the
  install's default paths). Explicitly GPU-oriented — not a minimal/bootable server
  image. (`gazebo-tooling/release-tools/bloom/ros_gz/Dockerfile` covers ros_gz
  bridge packaging.)
