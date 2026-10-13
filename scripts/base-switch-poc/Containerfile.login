FROM localhost/hummingbird-ros2-poc/ros-core-rpms-rt:fedora44-aarch64
RUN dnf -y install realtime-tests >/dev/null 2>&1 && dnf clean all && rm -rf /var/cache/* /var/lib/dnf/repos;     command -v cyclictest;     useradd -m -G wheel rt 2>/dev/null || true;     echo "rt:rtdemo123" | chpasswd; echo "root:rtdemo123" | chpasswd
