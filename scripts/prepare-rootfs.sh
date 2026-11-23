#!/bin/bash
set -euo pipefail
cd /project
root=/project/artifacts/rootfs
mkdir -p "$root" artifacts/busybox-download
if [ ! -e "$root/etc/debian_version" ]; then
    tar --numeric-owner -xf artifacts/debian-armel.tar -C "$root"
fi
apt-get update
cd artifacts/busybox-download
apt-get download busybox-static:armel
dpkg-deb -x ./busybox-static*.deb /project/artifacts/busybox-extracted
cp /project/artifacts/busybox-extracted/bin/busybox "$root/usr/bin/busybox"
cd /project
cp config/guest-packages.txt "$root/benro-packages.txt"
cp /benro-dev-env/scripts/guest-bootstrap.sh "$root/benro-bootstrap.sh"
chmod +x "$root/benro-bootstrap.sh"
touch "$root/benro-bootstrap.pending"
