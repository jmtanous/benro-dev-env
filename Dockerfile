FROM debian@sha256:734a72b3d6142a71993b4bc580ca01d8ca687f77a2c422d96a961d3376b179bc
ENV DEBIAN_FRONTEND=noninteractive
RUN dpkg --add-architecture armhf && dpkg --add-architecture armel && apt-get update && apt-get install -y --no-install-recommends \
    qemu-system-arm qemu-utils qemu-user-static proot e2fsprogs cpio kmod \
    openssh-client ca-certificates curl python3 file binutils rsync \
    gcc-arm-linux-gnueabi g++-arm-linux-gnueabi make cmake ninja-build \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /project
