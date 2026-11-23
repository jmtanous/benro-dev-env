#!/bin/bash
set -euo pipefail
export PATH=/usr/sbin:/usr/bin:/sbin:/bin
export DEBIAN_FRONTEND=noninteractive
trap 'echo BENRO_BOOTSTRAP_FAILED; /bin/busybox poweroff -f' ERR
mkdir -p /dev/pts /run /tmp
mount -t devpts devpts /dev/pts
mount -t tmpfs tmpfs /run
/bin/busybox modprobe virtio_net
/bin/busybox ifconfig eth0 10.0.2.15 netmask 255.255.255.0 up
# The initramfs has already installed the default route.
printf 'nameserver 10.0.2.3\n' > /etc/resolv.conf
printf '#!/bin/sh\nexit 101\n' > /usr/sbin/policy-rc.d
chmod +x /usr/sbin/policy-rc.d
apt-get update
xargs apt-get install -y --no-install-recommends < /benro-packages.txt
apt-get clean
rm /usr/sbin/policy-rc.d
/bin/busybox modprobe virtio_pci
/bin/busybox modprobe 9pnet_virtio
mount -t 9p -o trans=virtio,version=9p2000.L workspace /work
dpkg-query -W > /work/guest-packages.lock
chmod 644 /work/guest-packages.lock
rm /benro-bootstrap.pending
sync
echo BENRO_BOOTSTRAP_SUCCEEDED
/bin/busybox poweroff -f
