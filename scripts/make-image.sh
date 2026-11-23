#!/bin/bash
set -euo pipefail
cd /project
root=/project/artifacts/rootfs
mkdir -p artifacts/kernel-download artifacts/kernel
if [ ! -f artifacts/kernel/vmlinuz ]; then
    apt-get update
    cd artifacts/kernel-download
    pkg=$(apt-cache depends linux-image-armmp:armhf | awk '/Depends: linux-image-[0-9]/{print $2; exit}')
    test -n "$pkg"
    apt-get download "${pkg%:armhf}:armhf"
    dpkg-deb -x ./linux-image-*.deb /project/artifacts/kernel
    cd /project
    cp artifacts/kernel/boot/vmlinuz-* artifacts/kernel/vmlinuz
fi
version=$(basename "$(find artifacts/kernel/lib/modules -mindepth 1 -maxdepth 1 -type d | head -1)")
cp -a artifacts/kernel/lib/modules "$root/lib/"
depmod -b "$root" "$version"
printf '%s\n' "$version" > artifacts/kernel/version
printf 'benro-dev\n' > "$root/etc/hostname"
printf '127.0.0.1 localhost\n127.0.1.1 benro-dev\n' > "$root/etc/hosts"
printf 'nameserver 10.0.2.3\n' > "$root/etc/resolv.conf"
printf '/dev/vda / ext4 defaults 0 1\nworkspace /work 9p trans=virtio,version=9p2000.L,msize=262144,nofail 0 0\n' > "$root/etc/fstab"
mkdir -p "$root/etc/systemd/network" "$root/etc/systemd/system/multi-user.target.wants" "$root/work" "$root/home/dev/.ssh" "$root/etc/sudoers.d" "$root/etc/ssh/sshd_config.d" "$root/app/sd"
cp config/20-wired.network "$root/etc/systemd/network/20-wired.network"
touch "$root/etc/benro-dev-network-configured"
for service in systemd-networkd dbus ssh; do
    ln -sf "/lib/systemd/system/$service.service" "$root/etc/systemd/system/multi-user.target.wants/$service.service"
done
ln -sf /lib/systemd/system/multi-user.target "$root/etc/systemd/system/default.target"
if ! grep -q '^dev:' "$root/etc/passwd"; then
    printf 'dev:x:1000:1000:Developer:/home/dev:/bin/bash\n' >> "$root/etc/passwd"
    printf 'dev:x:1000:\n' >> "$root/etc/group"
    printf 'dev:!:20000:0:99999:7:::\n' >> "$root/etc/shadow"
fi
cp state/id_ed25519.pub "$root/home/dev/.ssh/authorized_keys"
chmod 700 "$root/home/dev/.ssh"
chmod 600 "$root/home/dev/.ssh/authorized_keys"
chown -R 1000:1000 "$root/home/dev"
printf 'dev ALL=(ALL) NOPASSWD: ALL\n' > "$root/etc/sudoers.d/dev"
chmod 440 "$root/etc/sudoers.d/dev"
printf 'PasswordAuthentication no\nKbdInteractiveAuthentication no\nPermitRootLogin no\n' > "$root/etc/ssh/sshd_config.d/10-development.conf"
# Guest host keys are generated in the build environment; each rebuild gets fresh keys.
for type in ed25519 rsa; do
    key="$root/etc/ssh/ssh_host_${type}_key"
    if [ ! -f "$key" ]; then ssh-keygen -q -t "$type" -N '' -f "$key"; fi
done
rm -f "$root/usr/sbin/policy-rc.d" "$root/etc/machine-id"
touch "$root/etc/machine-id"
mkdir -p "$root/var/lib/dbus"
ln -sf /etc/machine-id "$root/var/lib/dbus/machine-id"
cp /project/config/guest-motd.txt "$root/etc/motd"
mkdir -p "$root/etc/systemd/system"
if [ -f /project/config/benro-simulator.service ]; then
    cp /project/config/benro-simulator.service "$root/etc/systemd/system/"
    ln -sf /etc/systemd/system/benro-simulator.service "$root/etc/systemd/system/multi-user.target.wants/benro-simulator.service"
fi

# A small ARM initramfs loads the virtual disk driver before switching to Debian.
init=/project/artifacts/initramfs
mkdir -p "$init"/{bin,sbin,dev,proc,sys,newroot,lib/modules}
cp "$root/bin/busybox" "$init/bin/busybox"
for app in sh cp touch ifconfig route mount sleep switch_root modprobe; do ln -sf busybox "$init/bin/$app"; done
ln -sf /bin/busybox "$init/sbin/modprobe"
cp /benro-dev-env/scripts/guest-bootstrap.sh "$init/bootstrap.sh"
cp config/guest-packages.txt "$init/packages.txt"
cp config/20-wired.network "$init/network.conf"
cp -a "artifacts/kernel/lib/modules/$version" "$init/lib/modules/"
depmod -b "$init" "$version"
cat > "$init/init" <<EOF
#!/bin/sh
export PATH=/bin:/sbin
mount -t devtmpfs devtmpfs /dev
mount -t proc proc /proc
mount -t sysfs sysfs /sys
modprobe virtio_mmio
modprobe virtio_blk
modprobe virtio_net
modprobe virtio_pci
modprobe 9pnet_virtio
ifconfig eth0 10.0.2.15 netmask 255.255.255.0 up
route add default gw 10.0.2.2
ifconfig eth0
modprobe crc32c_generic
modprobe ext4
for attempt in 1 2 3 4 5 6 7 8 9 10; do
    [ -b /dev/vda ] && break
    sleep 1
done
mount -t ext4 /dev/vda /newroot || exec sh
if [ ! -e /newroot/etc/benro-dev-network-configured ]; then
    cp /network.conf /newroot/etc/systemd/network/20-wired.network
    touch /newroot/etc/benro-dev-network-configured
fi
mount --move /dev /newroot/dev
mount --move /proc /newroot/proc
mount --move /sys /newroot/sys
if [ -f /newroot/benro-bootstrap.pending ]; then
    cp /bootstrap.sh /newroot/benro-bootstrap.sh
    cp /packages.txt /newroot/benro-packages.txt
    exec switch_root /newroot /benro-bootstrap.sh
fi
exec switch_root /newroot /sbin/init
EOF
chmod +x "$init/init"
(cd "$init" && find . -print0 | cpio --null -o --format=newc 2>/dev/null | gzip -1) > artifacts/kernel/initramfs.gz
truncate -s 12G artifacts/root.raw
mkfs.ext4 -q -F -L benro-dev -d "$root" artifacts/root.raw
qemu-img convert -f raw -O qcow2 artifacts/root.raw artifacts/base.qcow2
rm artifacts/root.raw
sha256sum artifacts/kernel/vmlinuz artifacts/kernel/initramfs.gz artifacts/base.qcow2 > artifacts/SHA256SUMS
chown -R "$(stat -c %u /project):$(stat -c %g /project)" artifacts/kernel artifacts/base.qcow2 artifacts/SHA256SUMS
