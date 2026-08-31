# Gaps: ROS 2 + Gazebo images on the Hummingbird base

What still stands in the way of producing clean ROS 2 (`ros-core`, `ros-base`)
and Gazebo images on the Hummingbird `bootc-os` base. Grouped by category.

Native-hardware validation is **done**: on 2026-08-31 all five images built and
the full suite passed on a native x86_64 EC2 instance — including default Fast
DDS, headless `gz sim -s`, and the two-container ROS 2 ↔ Gazebo integration (see
CLAUDE.md "Verification status"). The interactive **GUI** (`gz sim -g`, needs a
display + GPU) remains the one verification-pending item and is omitted here.

## Packaging & upstream dependency

### Architecture coverage
The only package source we have (the community `tavie/ros2` COPR) builds for
x86_64 only — there is no aarch64 build. If target robots are arm64, this
package source is a dead end and the RPMs would have to come from elsewhere or
be built in-house.

### Dependence on an unofficial upstream
The whole stack rests on a single community-maintained package repository. It
is not official, and its availability, versions, and continued Fedora 43 / Jazzy
support are outside our control.

## Base image compatibility

### Gazebo can't be installed the normal way
Installing the Gazebo stack directly onto the base fails on an irreconcilable
library conflict (the base ships a newer Boost than Fedora's Ogre-based rendering
stack allows). This is a build-time failure independent of hardware, so it also
fails on native x86_64. It is why Gazebo currently exists only via a workaround.

### Gazebo relies on a workaround, not a clean image
To ship Gazebo at all, we install it into an isolated Fedora sysroot copied into
the image and run it via chroot (requiring an elevated capability at runtime).
It works, but it is a bridge, not a durable solution — the clean fix is
rebuilding the Gazebo stack against the base's own libraries in Hummingbird's
repos.

### Base image is missing pieces the packages assume
The base ships none of the stock Fedora repositories or signing keys the ROS
packages need, so we add them ourselves; it also reports a version string the
package URLs do not expect. These are handled by a setup script today, but they
are fragile — an upstream URL or layout change would break installs.

### Gazebo needs runtime plugin paths the packages don't set (handled)
The vendored Gazebo environment script points at its config but not at its system
plugins or physics engine, so out of the box the simulator starts but loads no
physics — a body wouldn't fall, even though the clock still advances (which made
this easy to miss). Our runtime entrypoint now discovers and sets those paths so
physics actually runs; the risk is that this wiring lives in our entrypoint, not
upstream, so a future package layout change could require updating it.

## Image footprint

### Images are large
The ROS image is much bigger than the equivalent Ubuntu one, for two structural
reasons: the base is a full bootable OS (kernel, systemd, container tooling), and
the ROS packages pull in a full compiler toolchain even into the runtime image.
The Gazebo/simulation images are far larger still.
