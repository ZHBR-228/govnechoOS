#!/usr/bin/env bash
# run_qemu.sh — запуск govechoOS в QEMU.
# Автор: ZHBR-228 | Лицензия: MIT (LICENSE)
# Требуется: qemu-system-x86_64 и ядро (vmlinuz). rootfs передаётся как ext4-диск,
# init=/sbin/govinit задаётся через append.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$HERE")"
source "$ROOT/config/build.conf"

IMG="$ROOT/build/govechoos-rootfs-${DISTRO_VERSION}.img"
[ -f "$IMG" ] || { echo "Образ не найден: $IMG — сначала выполните ./scripts/build_rootfs.sh" >&2; exit 1; }

# Найти ядро: KERNEL_PATH из конфига, затем типичные пути
KERNEL=""
for k in "$KERNEL_PATH" "/boot/vmlinuz-$(uname -r)" /boot/vmlinuz \
         "$ROOT/build/bzImage" "$ROOT/build/linux-6.1/arch/x86/boot/bzImage"; do
    [ -f "$k" ] && { KERNEL="$k"; break; }
done
[ -n "$KERNEL" ] || { echo "Не найдено ядро. Укажите KERNEL_PATH в config/build.conf" >&2; exit 1; }

command -v qemu-system-$QEMU_ARCH >/dev/null || { echo "qemu-system-$QEMU_ARCH не установлен" >&2; exit 1; }

echo "[govechoOS] kernel=$KERNEL rootfs=$IMG"
exec qemu-system-$QEMU_ARCH \
    -kernel "$KERNEL" \
    -drive file="$IMG",format=raw,id=hd0,if=none \
    -device virtio-blk-pci,drive=hd0 \
    -append "root=/dev/vda rw init=/sbin/govinit console=ttyS0 net.ifnames=0 panic=-1" \
    -nographic -no-reboot \
    -m 512 -smp 2
