#!/bin/bash
set -euo pipefail
project_dir=${1:?Pass project directory}
shared_dir=$(cd "$(dirname "$0")/.." && pwd)
cd "$project_dir"
mkdir -p artifacts state workspace
if [ -e artifacts/build-complete ]; then
    echo 'Completed base disk already exists. Use ./vm start; move the base and completion marker aside explicitly to rebuild.'
    exit 0
fi
docker image inspect benro-dev-tools:bookworm >/dev/null 2>&1 || docker build -t benro-dev-tools:bookworm "$shared_dir"
base='arm32v5/debian@sha256:cf9397e3198b2c002eb360586d341ba89154634198a26c578eb096b533b212cd'
if [ ! -f artifacts/debian-armel.tar ]; then
    docker pull --platform linux/arm/v5 "$base"
    seed=$(docker create --platform linux/arm/v5 "$base" /bin/true)
    trap 'docker rm "$seed" >/dev/null 2>&1 || true' EXIT
    docker export "$seed" > artifacts/debian-armel.tar
    docker rm "$seed" >/dev/null
    trap - EXIT
fi
if [ ! -f state/id_ed25519 ]; then
    ssh-keygen -q -t ed25519 -N '' -C benro-development -f state/id_ed25519
fi
if [ ! -e artifacts/base.qcow2 ]; then
docker run --rm \
    -v "$PWD:/project" -v "$shared_dir:/benro-dev-env:ro" benro-dev-tools:bookworm bash /benro-dev-env/scripts/prepare-rootfs.sh
docker run --rm -v "$PWD:/project" -v "$shared_dir:/benro-dev-env:ro" benro-dev-tools:bookworm bash /benro-dev-env/scripts/make-image.sh
fi
docker run --rm -v "$PWD:/project" -v "$shared_dir:/benro-dev-env:ro" benro-dev-tools:bookworm \
    qemu-system-arm -machine virt,highmem=off -cpu cortex-a7 -smp 2 -m 1536 \
    -accel tcg,thread=multi -nographic -no-reboot \
    -kernel /project/artifacts/kernel/vmlinuz \
    -initrd /project/artifacts/kernel/initramfs.gz \
    -append 'console=ttyAMA0 root=/dev/vda rw net.ifnames=0' \
    -drive file=/project/artifacts/base.qcow2,if=none,format=qcow2,id=rootdisk \
    -device virtio-blk-device,drive=rootdisk \
    -netdev user,id=net0 -device virtio-net-device,netdev=net0 \
    -virtfs local,path=/project/workspace,mount_tag=workspace,security_model=mapped-xattr,id=work \
    | tee artifacts/guest-bootstrap.log
grep -q BENRO_BOOTSTRAP_SUCCEEDED artifacts/guest-bootstrap.log
sha256sum artifacts/kernel/vmlinuz artifacts/kernel/initramfs.gz artifacts/base.qcow2 > artifacts/SHA256SUMS
touch artifacts/build-complete
echo 'Build complete. Run ./vm start'
