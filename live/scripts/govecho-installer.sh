#!/usr/bin/env bash
# govecho-installer — установщик govechoOS 1.0 с live-сессии на локальный диск
# Автор: ZHBR-228 | Лицензия: MIT
#
# Делает: разметку диска (GPT: EFI + ext4 root), распаковку squashfs,
#         установку grub, создание пользователя, финализацию chroot-настройки.
# Запуск: sudo govecho-installer [/dev/sdX] [--auto]   (--auto = без вопросов)
set -euo pipefail

VERSION="$(cat /etc/govechoos-version 2>/dev/null || grep VERSION_ID /etc/os-release | cut -d'"' -f2)"
TARGET="${1:-/dev/sda}"
AUTO=0; [ "${2:-}" = "--auto" ] && AUTO=1

log() { echo "[govecho-installer] $*"; }
die() { echo "[govecho-installer][ОШИБКА] $*" >&2; exit 1; }

[ "$(id -u)" = 0 ] || die "запустите с sudo"
[ -b "$TARGET" ] || die "не найден целевой диск $TARGET (укажите, например /dev/sdb)"
SQUASH="/run/live/roots/rw.squash"
[ -f "$SQUASH" ] || SQUASH="$(find /run/live -name '*.squash*' 2>/dev/null | head -1)"
[ -n "$SQUASH" ] || die "live-файл squashfs не найден (/run/live)"

if [ "$AUTO" = 0 ]; then
  echo "ВНИМАНИЕ: диск $TARGET будет полностью перезаписан!"
  lsblk "$TARGET"
  read -r -p "Продолжить? Напишите 'GOVECHO' для подтверждения: " ans
  [ "$ans" = "GOVECHO" ] || die "установка отменена"
  read -r -p "Имя нового пользователя [govecho]: " NEWUSER; NEWUSER=${NEWUSER:-govecho}
  read -s -r -p "Пароль: " PASS1; echo
else
  NEWUSER="govecho"
  PASS1="govecho"
fi

MNT=/mnt/target; mkdir -p "$MNT"

log "1/6 Разметка $TARGET (GPT: 512M EFI + остальное ext4 root)"
wipefs -a "$TARGET" >/dev/null
parted -s "$TARGET" mklabel gpt
parted -s "$TARGET" mkpart ESP fat32 1MiB 513MiB
parted -s "$TARGET" set 1 esp on
parted -s "$TARGET" mkpart root ext4 513MiB 100%
ROOTP="${TARGET}2"; EFP="${TARGET}1"
# mmc/nvme нумерация
case "$TARGET" in *nvme*|*mmcblk*) ROOTP="${TARGET}p2"; EFP="${TARGET}p1" ;; esac
sleep 2; partprobe "$TARGET" || true
mkfs.ext4 -q -F "$ROOTP"
mkfs.vfat -F32 "$EFP" >/dev/null

log "2/6 Распаковка squashfs → $ROOTP"
mount "$ROOTP" "$MNT"
unsquashfs -d "$MNT" -f "$SQUASH" >/dev/null

log "3/6 Монтаж псевдо-ФС и подготовка fstab"
mount --bind /dev  "$MNT/dev"
mount --bind /proc "$MNT/proc"
mount --bind /sys  "$MNT/sys"
mkdir -p "$MNT/boot/efi"
UUID_ROOT="$(blkid -s UUID -o value "$ROOTP")"
UUID_EFI="$(blkid -s UUID -o value "$EFP" || true)"
{
  echo "UUID=$UUID_ROOT / ext4 errors=remount-ro 0 1"
  [ -n "$UUID_EFI" ] && echo "UUID=$UUID_EFI /boot/efi vfat umask=007,shortname=winnt 0 2"
} > "$MNT/etc/fstab"

log "4/6 Установка загрузчика GRUB"
chroot "$MNT" /bin/bash -c "
  apt-get update -qq || true
  DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends grub-pc grub-efi-amd64-bin efibootmgr || true
  mkdir -p /boot/efi
  mount /boot/efi 2>/dev/null || true
  grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=govechoOS --removable 2>/dev/null \
    || grub-install --target=i386-pc --boot-directory=/boot '$TARGET'
  update-grub || grub-mkconfig -o /boot/grub/grub.cfg
" || log "предупреждение: grub в chroot не прошёл полностью (проверьте загрузчик вручную)"

log "5/6 Финализация системы"
echo "govechoos" > "$MNT/etc/hostname"
printf '127.0.0.1\tlocalhost\n127.0.1.1\tgovechoos\n' > "$MNT/etc/hosts"
# live-юзера заменяем на реального
chroot "$MNT" /bin/bash -c "
  userdel -r govecho 2>/dev/null || true
  useradd -m -G sudo,audio,video -s /bin/bash '$NEWUSER'
  echo '$NEWUSER:$PASS1' | chpasswd
  echo 'root:$PASS1' | chpasswd
  rm -f /etc/sudoers.d/govecho-live
  passwd -d live 2>/dev/null || true
  systemctl set-default graphical.target
"
# убираем live-boot из initramfs установленной системы
rm -f "$MNT/etc/initramfs-tools/conf.d/casper-md5check" 2>/dev/null || true
chroot "$MNT" /bin/bash -c "update-initramfs -u -k all" || true

log "6/6 Отмотка монтирований"
umount -R "$MNT"

log "Готово! govechoOS $VERSION установлена на $TARGET."
log "Перезагрузитесь: sudo reboot (извлеките носитель live)"
