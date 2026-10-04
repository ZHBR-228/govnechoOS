#!/usr/bin/env bash
# Тестовая сборка live-образа govechoOS (без GNOME, быстрый smoke-тест)
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${1:-$ROOT/build/live-test}"
CHROOT="$OUT/chroot"; IMGDIR="$OUT/image"

echo "[test] debootstrap minbase bookworm -> $CHROOT (нужен root + сеть)"
[ "$(id -u)" = 0 ] || { echo "run as root"; exit 1; }
rm -rf "$OUT"; mkdir -p "$OUT"
debootstrap --variant=minbase --include=sudo,locales bookworm "$CHROOT" http://deb.debian.org/debian

cp "$ROOT/config/sources.list.debian" "$CHROOT/etc/apt/sources.list"
mount -t proc proc "$CHROOT/proc"; mount -t sysfs sys "$CHROOT/sys"
mount --rbind /dev "$CHROOT/dev"; mount --make-rslave "$CHROOT/dev"
trap 'umount -R "$CHROOT/dev" 2>/dev/null; umount "$CHROOT/proc" "$CHROOT/sys" 2>/dev/null' EXIT

chroot "$CHROOT" apt-get update
chroot "$CHROOT" apt-get install -y --no-install-recommends linux-image-amd64 initramfs-tools live-boot live-config live-config-systemd

BIN="$ROOT/../build/bin"; mkdir -p "$BIN"
gcc -O2 -static -Wall -Wextra -o "$BIN/govinit"    "$ROOT/../src/govinit.c"
gcc -O2         -Wall -Wextra -o "$BIN/govecho"    "$ROOT/../src/govecho.c"
cp "$BIN/govinit" "$CHROOT/sbin/"; cp "$BIN/govecho" "$CHROOT/usr/local/bin/"
chmod 755 "$CHROOT/sbin/govinit" "$CHROOT/usr/local/bin/govecho"
cp "$ROOT/overlay/etc/os-release" "$CHROOT/etc/os-release"
cp "$ROOT/overlay/etc/issue" "$CHROOT/etc/issue"
chroot "$CHROOT" useradd -m -G sudo -s /bin/bash govecho
echo 'govecho ALL=(ALL) NOPASSWD:ALL' > "$CHROOT/etc/sudoers.d/gg"
chroot "$CHROOT" update-initramfs -u -k all
chroot "$CHROOT" apt-get clean

mkdir -p "$IMGDIR/live"
mksquashfs "$CHROOT" "$IMGDIR/live/govechoos.squashfs" -comp zstd -b 1M -noappend -e boot >/dev/null
KVER="$(ls "$CHROOT/boot" | grep -oE 'vmlinuz-.*' | head -1 | sed 's/vmlinuz-//')"
cp "$CHROOT/boot/vmlinuz-$KVER" "$IMGDIR/live/vmlinuz"
cp "$CHROOT/boot/initrd.img-$KVER" "$IMGDIR/live/initrd.img"

mkdir -p "$IMGDIR/isolinux" "$IMGDIR/EFI/BOOT"
cp /usr/lib/ISOLINUX/isolinux.bin "$IMGDIR/isolinux/" 2>/dev/null || true
cp /usr/lib/syslinux/modules/bios/ldlinux.c32 "$IMGDIR/isolinux/" 2>/dev/null || true
cat > "$IMGDIR/isolinux/isolinux.cfg" <<EOF
DEFAULT local
LABEL local
  KERNEL /live/vmlinuz
  APPEND initrd=/live/initrd.img boot=live username=govecho hostname=govechoos components
EOF
GRUB_EFI="$(ls /usr/lib/grub/x86_64-efi-signed/grubnetx64.efi.signed 2>/dev/null || ls /usr/lib/grub/x86_64-efi/grub.efi 2>/dev/null || true)"
if [ -n "$GRUB_EFI" ]; then
  cp "$GRUB_EFI" "$IMGDIR/EFI/BOOT/BOOTX64.EFI"
  cat > "$IMGDIR/EFI/BOOT/grub.cfg" <<EOF
set timeout=3
menuentry "govechoOS live test" {
    search --set -f /live/vmlinuz
    linux /live/vmlinuz boot=live username=govecho hostname=govechoos components
    initrd /live/initrd.img
}
EOF
fi
ISO="$OUT/govechoOS-live-test.iso"
ARGS=(-isohybrid-mbr /usr/lib/ISOLINUX/isohdpfx.bin -c isolinux/boot.cat -b isolinux/isolinux.bin -no-emul-boot -boot-load-size 4 -boot-info-table -eltorito-alt-boot)
[ -f "$IMGDIR/EFI/BOOT/BOOTX64.EFI" ] && ARGS+=(-e /EFI/BOOT/BOOTX64.EFI -no-emul-boot -isohybrid-gpt-basdat)
xorriso -as mkisofs -r -V GOVECHOOS-TEST -J -joliet-long -l "${ARGS[@]}" -o "$ISO" "$IMGDIR" >/dev/null
echo "[test] ISO готово: $ISO ($(du -h "$ISO" | cut -f1))"
