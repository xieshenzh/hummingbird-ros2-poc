# ros-core-rpms — ros-core from Hummingbird-built RPMs

A `ros-core` image built from **our own** ROS 2 Jazzy RPMs (built the
Hummingbird way in the `hummingbird-rpms` monorepo, from official upstream
sources) on top of `bootc-os` — instead of the third-party `tavie/ros2` COPR
used by `../ros-core`.

Because the RPMs are native **aarch64**, this builds and runs natively on
Apple Silicon — no `--platform linux/amd64` / qemu (unlike the x86_64-only
COPR images).

## 1. Populate `./rpms/` from the build VM

The RPMs are not committed (see `.gitignore`). Copy the full set out of the
Lima build VM's `~/ros-local-rpms/` into `./rpms/` (run from the repo root):

```bash
mkdir -p images/ros-core-rpms/rpms
limactl shell fedora -- bash -lc 'tar cf - -C ~/ros-local-rpms .' \
  | tar xf - -C images/ros-core-rpms/rpms
ls images/ros-core-rpms/rpms/*.rpm | wc -l   # expect ~162
```

## 2. Build

Build on a bootc-os base whose Fedora release + arch match what the RPMs were
built against (aarch64; see the note in `enable-repos.sh`):

```bash
podman build -t hummingbird-ros2-poc/ros-core-rpms:latest images/ros-core-rpms
```

The Dockerfile stages the RPMs into a transient `createrepo_c` repo, adds the
stock Fedora repos (bootc-os omits them; the Hummingbird repo it already
enables provides the Hummingbird-built system libs such as `spdlog-1.17`),
`dnf install`s `ros-jazzy-ros-core`, then removes the staged repo, the RPMs and
`createrepo_c` so nothing extraneous lands in the image.

## 3. Smoke test

```bash
# ros2 CLI + env sources cleanly
podman run --rm --entrypoint /usr/bin/ros-entrypoint.sh \
  hummingbird-ros2-poc/ros-core-rpms:latest ros2 pkg list | grep -c ros

# interactive login shell auto-sources ROS
podman run --rm -it hummingbird-ros2-poc/ros-core-rpms:latest bash
#   ros2 topic list

# pub/sub (Cyclone DDS is reliable; Fast DDS needs native x86_64 hardware)
podman run --rm -e RMW_IMPLEMENTATION=rmw_cyclonedds_cpp \
  --entrypoint /usr/bin/ros-entrypoint.sh \
  hummingbird-ros2-poc/ros-core-rpms:latest bash -c \
  'ros2 topic pub -r5 /chatter std_msgs/msg/String "{data: hi}" & \
   sleep 6; ros2 topic echo --once /chatter std_msgs/msg/String'
```

## 4. (Stretch) bootability

Like `../ros-core`, this keeps `CMD ["/sbin/init"]`, the kernel and the
`bootc` binary from the base, so it should remain a valid bootc image:

```bash
bootc container lint   # inside the built image
```