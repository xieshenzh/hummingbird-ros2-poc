# Gaps: ROS 2 + Gazebo images on the Hummingbird base

What still stands in the way of producing clean ROS 2 (`ros-core`, `ros-base`)
and Gazebo images on the Hummingbird `bootc-os` base. Grouped by category.

Native-hardware validation is **done**: on 2026-08-31 all five images built and
the full suite passed on a native x86_64 EC2 instance — including default Fast
DDS, headless `gz sim -s`, and the two-container ROS 2 ↔ Gazebo integration (see
CLAUDE.md "Verification status"). The interactive **GUI** (`gz sim`) was the last
pending item and is now also **verified** (2026-09-02, native x86_64, headless
box + software GL over VNC) — so there are no verification-pending items left;
the gaps below are all structural, not untested-functionality gaps.

## Packaging & upstream dependency

> **Largely resolved for the ros-core path (2026-09).** We now build ROS 2 Jazzy
> ourselves the Hummingbird way (the `rpms` monorepo dev workflow, from official
> upstream sources) instead of relying on the COPR. The `ros_core` closure — 162
> `ros-jazzy-*` RPMs — is built and image-verified on **both aarch64 and x86_64**
> (see `images/ros-core-rpms` and CLAUDE.md "ROS 2 as Hummingbird-built RPMs").
> The two gaps below therefore no longer apply to `ros-core`; they still apply to
> the Gazebo/simulation images, which remain COPR-sourced.

### Architecture coverage — RESOLVED for ros-core, open for Gazebo/sim
The community `tavie/ros2` COPR builds for x86_64 only — no aarch64 build — so
any image sourced from it is x86_64-only (that is still true of
`gazebo`/`simulation`/`sim-bundle`). This is no longer a dead end for the base
stack: the Hummingbird-built `ros_core` RPMs exist for **both** arches, built
natively on each (aarch64 on Apple Silicon, x86_64 on EC2). Extending the in-house
build to `ros-base` (and eventually the Gazebo stack) would remove the COPR's
arch limit everywhere.

### Dependence on an unofficial upstream — RESOLVED for ros-core, open for Gazebo/sim
For `ros-core` the stack no longer rests on the community COPR: the packages are
Hummingbird-maintained specs built from official upstream release tarballs
(SHA512-pinned), under our control. The Gazebo/simulation images still depend on
the single community-maintained COPR, whose availability, versions, and continued
Fedora 43 / Jazzy support are outside our control.

### ros-base / Gazebo / simulation not yet built as Hummingbird RPMs
The in-house RPM effort so far covers only the `ros_core` closure. `ros-base`,
`simulation`, and `gazebo` are still COPR-only. Building `ros-base` as Hummingbird
RPMs is the natural next step (a superset of the ros_core closure); the Gazebo
stack additionally needs the boost/ogre-next fix noted below before it can be
packaged cleanly.

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
plugins, physics engine, GUI plugins, render engine, shader media, or Qt QML
modules — so out of the box the simulator starts but loads no physics (a body
wouldn't fall, even though the clock still advances, which made this easy to
miss) and the GUI opens a blank window. Our runtime entrypoint now discovers and
sets all of those paths so both the headless server and the interactive GUI work
from the image alone; the risk is that this wiring lives in our entrypoint, not
upstream, so a future package layout change could require updating it. (Same root
cause throughout: the RPMs bake their default paths into a nonexistent build root.)

## Image footprint

### Images are large
The ROS image is much bigger than the equivalent Ubuntu one, for two structural
reasons: the base is a full bootable OS (kernel, systemd, container tooling), and
the ROS packages pull in a full compiler toolchain even into the runtime image.
The Gazebo/simulation images are far larger still.
