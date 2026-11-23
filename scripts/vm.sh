#!/bin/bash
set -euo pipefail
cd "${BENRO_PROJECT_DIR:?Set BENRO_PROJECT_DIR}"
shared_dir=$(cd "$(dirname "$0")/.." && pwd)
image=benro-dev-tools:bookworm
name=${BENRO_VM_NAME:?Set BENRO_VM_NAME}
running() { [ "$(docker inspect -f '{{.State.Running}}' "$name" 2>/dev/null || true)" = true ]; }
tool() { docker run --rm --user "$(id -u):$(id -g)" -v "$PWD:/project" "$image" "$@"; }
stop_vm() {
    if ! running; then echo 'VM is stopped.'; return; fi
    # SSH asks PID 1 directly; this also works without a desktop/login manager
    # listening to the virtual power button. QMP is a fallback during boot.
    if ! ssh -F /dev/null -p "$BENRO_SSH_PORT" -i "$PWD/state/id_ed25519" \
        -o BatchMode=yes -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new \
        -o UserKnownHostsFile="$PWD/state/known_hosts" -o ConnectTimeout=5 \
        dev@127.0.0.1 sudo /sbin/poweroff; then
        if running; then python3 "$shared_dir/scripts/qmp.py" state/qmp.sock system_powerdown; fi
    fi
    for attempt in $(seq 1 60); do
        if ! running; then echo 'VM shut down cleanly.'; return; fi
        sleep 1
    done
    echo 'Guest has not shut down; leaving it running. Inspect ./vm logs.' >&2
    return 1
}
case "${1:-help}" in
    build) exec bash "$shared_dir/scripts/provision.sh" "$PWD" ;;
    start)
        if running; then echo 'VM already running. Use ./vm ssh'; exit 0; fi
        test -f artifacts/build-complete || { echo 'Run ./vm build first.' >&2; exit 1; }
        if [ ! -f state/disk.qcow2 ]; then
            tool qemu-img create -f qcow2 -F qcow2 -b /project/artifacts/base.qcow2 /project/state/disk.qcow2
        fi
        docker rm "$name" >/dev/null 2>&1 || true
        rm -f state/qmp.sock
        docker run -d --name "$name" --read-only --tmpfs /tmp \
            --cap-drop ALL --security-opt no-new-privileges \
            --user "$(id -u):$(id -g)" \
            -p 127.0.0.1:$BENRO_SSH_PORT:2222 -p 127.0.0.1:$BENRO_WEB_PORT:8081 \
            -p 127.0.0.1:$BENRO_API_PORT:5555 -p 127.0.0.1:$BENRO_WS_PORT:5556 \
            -v "$PWD:/project" "$image" \
            qemu-system-arm -machine virt,highmem=off -cpu cortex-a7 -smp 2 -m 1536 \
            -accel tcg,thread=multi -nographic -no-reboot \
            -kernel /project/artifacts/kernel/vmlinuz \
            -initrd /project/artifacts/kernel/initramfs.gz \
            -append 'console=ttyAMA0 root=/dev/vda rw net.ifnames=0 systemd.unit=multi-user.target' \
            -drive file=/project/state/disk.qcow2,if=none,format=qcow2,id=rootdisk \
            -device virtio-blk-device,drive=rootdisk \
            -netdev 'user,id=net0,restrict=on,hostfwd=tcp:0.0.0.0:2222-:22,hostfwd=tcp:0.0.0.0:8081-:8081,hostfwd=tcp:0.0.0.0:5555-:5555,hostfwd=tcp:0.0.0.0:5556-:5556' \
            -device virtio-net-device,netdev=net0 \
            -virtfs local,path=/project/workspace,mount_tag=workspace,security_model=mapped-xattr,id=work \
            -qmp unix:/project/state/qmp.sock,server=on,wait=off
        echo 'Booting. Run ./vm logs or ./vm ssh.'
        ;;
    ssh)
        mkdir -p workspace/build
        cp VERSION workspace/build/VERSION
        shift
        exec ssh -F /dev/null -p "$BENRO_SSH_PORT" -i "$PWD/state/id_ed25519" \
            -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new \
            -o UserKnownHostsFile="$PWD/state/known_hosts" -o ConnectTimeout=8 dev@127.0.0.1 "$@"
        ;;
    stop) stop_vm ;;
    logs) exec docker logs --tail 100 "$name" ;;
    status) docker inspect -f '{{.State.Status}}' "$name" ;;
    snapshot)
        label=${2:?Usage: ./vm snapshot NAME}
        [[ "$label" =~ ^[a-zA-Z0-9_-]+$ ]] || { echo 'Use letters, digits, _ or -.' >&2; exit 1; }
        test ! -e "state/snapshot-$label.qcow2" || { echo 'Snapshot already exists.' >&2; exit 1; }
        stop_vm
        tool qemu-img convert -f qcow2 -O qcow2 /project/state/disk.qcow2 "/project/state/snapshot-$label.qcow2"
        echo "Saved state/snapshot-$label.qcow2. VM is stopped; ./vm start resumes it."
        ;;
    restore)
        label=${2:?Usage: ./vm restore NAME}
        [[ "$label" =~ ^[a-zA-Z0-9_-]+$ ]] || exit 1
        test -f "state/snapshot-$label.qcow2"
        stop_vm
        # Preserve the current disk instead of discarding work.
        mv state/disk.qcow2 "state/before-restore-$(date +%s).qcow2"
        tool qemu-img create -f qcow2 -F qcow2 -b "/project/state/snapshot-$label.qcow2" /project/state/disk.qcow2
        echo 'Restored. Run ./vm start. Shared source files are not part of disk snapshots.'
        ;;
    cross-cpp)
        tool cmake -S /project/workspace/cpp -B /project/workspace/build/cross \
            -DCMAKE_TOOLCHAIN_FILE=/project/config/benro-armel.cmake
        tool cmake --build /project/workspace/build/cross -j2
        ;;
    *) echo 'Usage: ./vm {build|start|ssh [command]|stop|logs|status|snapshot NAME|restore NAME|cross-cpp}' ;;
esac
