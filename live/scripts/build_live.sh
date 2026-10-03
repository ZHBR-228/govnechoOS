#!/usr/bin/env bash
# govechoOS live — сборка полноценной live-системы (ISO) на базе Debian или Ubuntu
# с GNOME, фирменными компонентами govechoOS и установщиком.
# Автор: ZHBR-228 | Лицензия: MIT
#
# Требования (Debian/Ubuntu, root):
#   apt-get install -y debootstrap squashfs-tools xorriso isolinux syslinux-common \
#       grub-pc-bin grub-efi-amd64-bin grub-common mtools dosfstools fakeroot \
#       curl ca-certificates
#
# Использование:
#   sudo ./scripts/build_live.sh --base debian            # ISO на базе Debian 12
#   sudo ./scripts/build_live.sh --base ubuntu            # ISO на базе Ubuntu 24.04
#   sudo ./scripts/build_live.sh --skip-bootstrap         # переупаковать уже собранный chroot
set -euo pipefail

AUTHOR="ZHBR-228"; LICENSE="MIT"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
PROJECT_DIR="$(dirname "$ROOT_DIR")"          # корень репозитория govechoOS
BUILD_DIR="${GOVECHO_BUILD_DIR:-$PROJECT_DIR/build/live}"
CHROOT="$BUILD_DIR/chroot"
LIVE_DIR="$BUILD_DIR/image"
SQUASHFS="$BUILD_DIR/filesystem.squashfs"
EXPORT_DIR="$PROJECT_DIR/build/export"

BASE="debian"                 # debian | ubuntu
SKIP_BOOTSTRAP=0
DEBIAN_SUITE="bookworm"
UBUNTU_SUITE="noble"
IMAGE_LABEL="govechoos-1.0"
VERSION="$(cat "$ROOT_DIR/VERSION" 2>/dev/null || echo 1.0.0)"

log()  { echo -e "\e[1;34m[govechoOS-live]\e[0m $*"; }
warn() { echo -e "\e[1;33m[!] $*\e[0m"; }
die()  { echo -e "\e[1;31m[х] $*\e[0m" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    --base) BASE="$2"; shift 2 ;;
    --skip-bootstrap) SKIP_BOOTSTRAP=1; shift ;;
    --suite) DEBIAN_SUITE="$2"; UBUNTU_SUITE="$2"; shift 2 ;;
    *) die "неизвестный аргумент: $1" ;;
  esac
done

[ "$(id -u)" = 0 ] || die "нужны права root (debootstrap/mount)"
case "$BASE" in
  debian) SUITE="$DEBIAN_SUITE"; MIRROR="http://deb.debian.org/debian"; SRCFILE="$ROOT_DIR/config/sources.list.debian" ;;
  ubuntu) SUITE="$UBUNTU_SUITE"; MIRROR="http://archive.ubuntu.com/ubuntu"; SRCFILE="$ROOT_DIR/config/sources.list.ubuntu" ;;
  *) die "--base должен быть debian или ubuntu" ;;
esac

command -v debootstrap >/dev/null || die "не найден debootstrap — см. требования в шапке скрипта"
mkdir -p "$BUILD_DIR" "$EXPORT_DIR"

# ---------- 1. Базовая система ----------
if [ "$SKIP_BOOTSTRAP" = 0 ] || [ ! -d "$CHROOT/var/lib/dpkg" ]; then
  log "1/6 debootstrap базовой системы ($BASE/$SUITE) → $CHROOT"
  rm -rf "$CHROOT"; mkdir -p "$CHROOT"
  debootstrap --variant=minbase --include=sudo,dbus,locales,initramfs-tools,apt-utils \
              --arch=amd64 "$SUITE" "$CHROOT" "$MIRROR"
else
  log "1/6 пропуск bootstrap (chroot уже существует)"
fi

# ---------- 2. Настройка chroot / монтаж псевдо-ФС ----------
log "2/6 настройка chroot, монтаж /proc /sys /dev"
mount_pseudo() {
  mkdir -p "$CHROOT/proc" "$CHROOT/sys" "$CHROOT/dev/pts" "$CHROOT/run"
  mount -t proc     proc     "$CHROOT/proc"  2>/dev/null || true
  mount -t sysfs    sys      "$CHROOT/sys"   2>/dev/null || true
  mount --rbind     /dev     "$CHROOT/dev"   2>/dev/null || true
  mount --make-rslave "$CHROOT/dev"         2>/dev/null || true
}
umount_pseudo() {
  umount -R "$CHROOT/dev" 2>/dev/null || true
  umount "$CHROOT/proc" "$CHROOT/sys" 2>/dev/null || true
}
trap 'umount_pseudo' EXIT
mount_pseudo

cp "$SRCFILE" "$CHROOT/etc/apt/sources.list"
cp "$ROOT_DIR/config/apt.conf" "$CHROOT/etc/apt/apt.conf.d/99govechoos"
echo "govechoos" > "$CHROOT/etc/hostname"
printf '127.0.0.1\tlocalhost govechoos\n::1\tlocalhost ip6-loopback\n' > "$CHROOT/etc/hosts"
cp "$ROOT_DIR/overlay/etc/os-release" "$CHROOT/etc/os-release" 2>/dev/null || true
cp "$ROOT_DIR/overlay/etc/issue"      "$CHROOT/etc/issue"      2>/dev/null || true
echo "ru_RU.UTF-8 UTF-8" > "$CHROOT/etc/locale.gen"
ln -sf /usr/share/zoneinfo/Europe/Moscow "$CHROOT/etc/localtime" 2>/dev/null || true

chroot_run() { chroot "$CHROOT" /bin/bash -c "$*"; }
chroot_run "apt-get update"

# ---------- 3. Пакеты (ядро + GNOME + стартовые приложения) ----------
log "3/6 установка пакетов системы ($BASE/$SUITE)"
mapfile -t PKGS < <(grep -vE '^\s*(#|$)' "$ROOT_DIR/config/packages.list" | while read -r line; do
  IFS='|' read -ra alts <<< "$line"
  for alt in "${alts[@]}"; do
    if chroot_run "apt-cache show $alt >/dev/null 2>&1"; then echo "$alt"; break; fi
  done
done)
log "устанавливается ${#PKGS[@]} пакетов: ${PKGS[*]}"
# ставим частями: устойчивее к одному недоступному пакету
CHUNK=(); failed=()
install_chunk() {
  [ ${#CHUNK[@]} -gt 0 ] || return 0
  if ! DEBIAN_FRONTEND=noninteractive chroot_run \
        "apt-get install -y --no-install-recommends ${CHUNK[*]}"; then
    warn "чанк не прошёл целиком, ставлю поштучно: ${CHUNK[*]}"
    for p in "${CHUNK[@]}"; do
      DEBIAN_FRONTEND=noninteractive chroot_run \
        "apt-get install -y --no-install-recommends $p" || failed+=("$p")
    done
  fi
  CHUNK=()
}
for p in "${PKGS[@]}"; do
  CHUNK+=("$p")
  [ ${#CHUNK[@]} -ge 8 ] && { install_chunk; }
done
install_chunk
[ ${#failed[@]} -gt 0 ] && warn "пропущены недоступные пакеты: ${failed[*]}"

# live-boot/initramfs для загрузки с ISO
chroot_run "update-initramfs -u -k all" || warn "initramfs не пересобран"

# ---------- 4. Фирменные компоненты govechoOS ----------
log "4/6 компиляция и установка govinit/govecho/govwelcome/govstartapps"
BIN="$PROJECT_DIR/build/bin"; mkdir -p "$BIN"
SRC="$PROJECT_DIR/src"
PKGROOT="$PROJECT_DIR/pkgroot"
gcc -O2 -static  -Wall -Wextra -o "$BIN/govinit"    "$SRC/govinit.c"
gcc -O2          -Wall -Wextra -o "$BIN/govecho"    "$SRC/govecho.c"
[ -f "$SRC/govwelcome.c" ] && gcc -O2 -Wall -Wextra -o "$BIN/govwelcome" "$SRC/govwelcome.c"
cp "$BIN/govinit" "$CHROOT/sbin/govinit"
cp "$BIN/govecho" "$CHROOT/usr/local/bin/govecho"
[ -f "$BIN/govwelcome" ] && cp "$BIN/govwelcome" "$CHROOT/usr/local/bin/govwelcome"
# govstartapps: из pkgroot (общий источник с .deb) или staging-артефакта сборки
for cand in "$PKGROOT/usr/local/bin/govstartapps" \
            "$PROJECT_DIR"/build/deb-stage*/govechoos-gnome/*/usr/local/bin/govstartapps; do
  if [ -f "$cand" ]; then
    cp "$cand" "$CHROOT/usr/local/bin/govstartapps"
    chmod +x "$CHROOT/usr/local/bin/govstartapps"
    break
  fi
done
chmod 755 "$CHROOT/sbin/govinit" "$CHROOT/usr/local/bin/"*


# overlay govechoOS (os-release, issue, gdm, юниты, skel)
cp -a "$ROOT_DIR/overlay/." "$CHROOT/"
# автозапуск systemd-user
mkdir -p "$CHROOT/etc/systemd/user/default.target.wants"
ln -sf ../govstartapps.service "$CHROOT/etc/systemd/user/default.target.wants/govstartapps.service" 2>/dev/null || true
# XDG autostart и ярлыки приложений ряда — из pkgroot (общий источник с .deb)
if [ -d "$PKGROOT/etc/xdg/autostart" ]; then
  mkdir -p "$CHROOT/etc/xdg/autostart"
  cp -a "$PKGROOT/etc/xdg/autostart/." "$CHROOT/etc/xdg/autostart/"
fi
if [ -d "$PKGROOT/usr/share/applications" ]; then
  mkdir -p "$CHROOT/usr/share/applications"
  cp -a "$PKGROOT/usr/share/applications/." "$CHROOT/usr/share/applications/"
fi
# dconf-баннер входа GNOME — из pkgroot
if [ -d "$PKGROOT/etc/dconf/db/local.d" ]; then
  mkdir -p "$CHROOT/etc/dconf/db/local.d" "$CHROOT/etc/dconf/profile"
  cp -a "$PKGROOT/etc/dconf/db/local.d/." "$CHROOT/etc/dconf/db/local.d/"
  cp -a "$PKGROOT/etc/dconf/profile/."    "$CHROOT/etc/dconf/profile/" 2>/dev/null || true
  chroot_run "command -v dconf >/dev/null && dconf update" || true
fi

# пользователь live + sudo без пароля
chroot_run "getent group sudo >/dev/null || addgroup --system sudo"
chroot_run "id govecho >/dev/null 2>&1 || useradd -m -G sudo,audio,video -s /bin/bash govecho"
echo 'govecho ALL=(ALL) NOPASSWD:ALL' > "$CHROOT/etc/sudoers.d/govecho-live"
chmod 440 "$CHROOT/etc/sudoers.d/govecho-live"
# пароль root для установленной системы
chroot_run "echo 'root:govecho' | chpasswd" || true

# ---------- 5. Установщик (govecho-installer) ----------
log "5/6 установка govecho-installer в образ"
if [ -f "$ROOT_DIR/scripts/govecho-installer.sh" ]; then
  cp "$ROOT_DIR/scripts/govecho-installer.sh" "$CHROOT/usr/local/bin/govecho-installer"
  chmod +x "$CHROOT/usr/local/bin/govecho-installer"
  cat > "$CHROOT/usr/share/applications/govecho-installer.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Установить govechoOS
Name[en]=Install govechoOS
Comment=Установка govechoOS 1.0 на локальный диск
Exec=gksudo govecho-installer
Icon=drive-harddisk
Terminal=true
Categories=System;Settings;
EOF
fi

# очистка кэша для уменьшения squashfs
chroot_run "apt-get clean; rm -rf /var/lib/apt/lists/*" || true

# ---------- 6. Squashfs + ISO ----------
log "6/6 упаковка squashfs и создание ISO"
umount_pseudo; trap - EXIT

mkdir -p "$LIVE_DIR/live"
mksquashfs "$CHROOT" "$SQUASHFS" -comp zstd -b 1M -noappend -e boot
cp "$SQUASHFS" "$LIVE_DIR/live/govechoos.squashfs"

# ядро и initrd из chroot
KERNDIR="$CHROOT/boot"
KVER="$(ls "$KERNDIR" | grep -oE 'vmlinuz-[0-9].*' | head -1 | sed 's/vmlinuz-//')" || die "в chroot нет ядра в /boot"
cp "$KERNDIR/vmlinuz-$KVER" "$LIVE_DIR/live/vmlinuz"
cp "$KERNDIR/initrd.img-$KVER" "$LIVE_DIR/live/initrd.img"

# EFI: grub.efi берётся с хоста (пакет grub-efi-amd64-bin/signed)

# isolinux для BIOS-загрузки
ISOLINUX_DIR="$LIVE_DIR/isolinux"; mkdir -p "$ISOLINUX_DIR"
BOOTCAT_ARGS=()
if [ -f /usr/lib/ISOLINUX/isolinux.bin ]; then
  cp /usr/lib/ISOLINUX/isolinux.bin "$ISOLINUX_DIR/"
  cp /usr/lib/syslinux/modules/bios/ldlinux.c32 "$ISOLINUX_DIR/" 2>/dev/null || true
  cp /usr/lib/ISOLINUX/vesamenu.c32 "$ISOLINUX_DIR/" 2>/dev/null || true
  cat > "$ISOLINUX_DIR/isolinux.cfg" <<EOF
DEFAULT vesamenu.c32
PROMPT 0
TIMEOUT 50
MENU TITLE govechoOS 1.0 Echo (GNOME Edition) — автор ZHBR-228
LABEL live
  MENU LABEL govechoOS 1.0 Echo (live, GNOME)
  KERNEL /live/vmlinuz
  APPEND initrd=/live/initrd.img boot=live username=govecho hostname=govechoos components quiet splash
LABEL failsafe
  MENU LABEL govechoOS 1.0 Echo (failsafe)
  KERNEL /live/vmlinuz
  APPEND initrd=/live/initrd.img boot=live username=govecho hostname=govechoos components noapic noacpi nomodeset
EOF
  BOOTCAT_ARGS=(-c isolinux/boot.cat -b isolinux/isolinux.bin -no-emul-boot -boot-load-size 4 -boot-info-table)
else
  warn "isolinux не найден — ISO будет EFI-only (grub)"
fi

# EFI: каталог EFI/BOOT прямо на ISO + grub.efi из пакета grub-efi-amd64-bin
GRUB_EFI="$(ls /usr/lib/grub/x86_64-efi-signed/grubnetx64.efi.signed 2>/dev/null \
            || ls /usr/lib/grub/x86_64-efi/grub.efi 2>/dev/null \
            || ls /boot/efi/EFI/*/grub*.efi 2>/dev/null | head -1 || true)"
[ -n "$GRUB_EFI" ] || die "не найден grub EFI-образ (пакет grub-efi-amd64-bin или grub-efi-amd64-signed)"
mkdir -p "$LIVE_DIR/EFI/BOOT" "$LIVE_DIR/EFI/govechoos" "$LIVE_DIR/boot/grub"
cp "$GRUB_EFI" "$LIVE_DIR/EFI/BOOT/BOOTX64.EFI"
cat > "$LIVE_DIR/EFI/BOOT/grub.cfg" <<EOF
set timeout=5
set default=0
menuentry "govechoOS 1.0 Echo (live, GNOME)" {
    search --set -f /live/vmlinuz
    linux /live/vmlinuz boot=live username=govecho hostname=govechoos components quiet splash
    initrd /live/initrd.img
}
menuentry "govechoOS 1.0 Echo (live failsafe)" {
    search --set -f /live/vmlinuz
    linux /live/vmlinuz boot=live username=govecho hostname=govechoos components noapic noacpi nomodeset
    initrd /live/initrd.img
}
EOF
cp "$LIVE_DIR/EFI/BOOT/grub.cfg" "$LIVE_DIR/boot/grub/grub.cfg"

# Сборка hybrid-ISO (BIOS via isolinux + EFI via kexec'd grub image)
XORRISO_EXTRA=()
if [ ${#BOOTCAT_ARGS[@]} -gt 0 ]; then
  XORRISO_EXTRA=(-isohybrid-mbr /usr/lib/ISOLINUX/isohdpfx.bin "${BOOTCAT_ARGS[@]}" -eltorito-alt-boot)
fi
xorriso -as mkisofs -r -V "$IMAGE_LABEL" \
  -J -joliet-long -l \
  "${XORRISO_EXTRA[@]}" \
  -e /EFI/BOOT/BOOTX64.EFI -no-emul-boot \
  -isohybrid-gpt-basdat \
  -o "$EXPORT_DIR/govechoOS-${VERSION}-live-${BASE}.iso" "$LIVE_DIR"

log "Готово! ISO: $(ls -lh "$EXPORT_DIR/govechoOS-${VERSION}-live-${BASE}.iso")"
log "Проверка: sudo virt-install --import ... или просто записать на флешку: dd if=...iso of=/dev/sdX bs=4M"
