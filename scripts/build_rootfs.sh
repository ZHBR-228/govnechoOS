#!/usr/bin/env bash
# build_rootfs.sh — собирает корневую ФС govechoOS в ext4-образ.
# Автор: ZHBR-228 | Лицензия: MIT (LICENSE)
#
# Этапы:
#   1. Компиляция govinit (PID 1) и govecho (фирменный echo) из src/
#   2. Подготовка дерева rootfs: стандартная иерархия FHS + overlay/
#   3. Busybox как /bin/sh и набор утилит (если доступен; иначе fallback)
#   4. Упаковка в ext4-образ build/govechoos-rootfs.img
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$HERE")"
source "$ROOT/config/build.conf"

BUILD="$ROOT/build"
STAGE="$BUILD/rootfs-stage"
IMG="$BUILD/govechoos-rootfs-${DISTRO_VERSION}.img"

log() { printf '\e[1;36m[govechoOS]\e[0m %s\n' "$*"; }
die() { printf '\e[1;31m[govechoOS] ERROR:\e[0m %s\n' "$*" >&2; exit 1; }

# ---------- 1. компиляция собственных компонентов ----------------------
log "компилирую govinit и govecho (${ARCH})..."
CC="${CROSS_COMPILE}gcc"
command -v "$CC" >/dev/null || die "не найден компилятор $CC"
mkdir -p "$BUILD/bin"
CFLAGS="-O2 -Wall -Wextra -static"
# -static предпочтительна; если статической libc нет, соберём динамически
if ! $CC $CFLAGS -o "$BUILD/bin/govinit" "$ROOT/src/govinit.c" 2>/dev/null; then
    log "статическая сборка не удалась, пробую динамическую..."
    CFLAGS="-O2 -Wall -Wextra"
    $CC $CFLAGS -o "$BUILD/bin/govinit" "$ROOT/src/govinit.c" \
        || die "сборка govinit завершилась ошибкой"
fi
if ! $CC $CFLAGS -o "$BUILD/bin/govecho" "$ROOT/src/govecho.c" 2>/dev/null; then
    $CC -O2 -Wall -Wextra -o "$BUILD/bin/govecho" "$ROOT/src/govecho.c" \
        || die "сборка govecho завершилась ошибкой"
fi

# ---------- 2. дерево rootfs -------------------------------------------
log "готовлю дерево rootfs в $STAGE ..."
rm -rf "$STAGE"
mkdir -p "$STAGE"/{bin,sbin,usr/{bin,sbin,lib},lib,lib64,etc,dev,proc,sys,\
run,tmp,mnt,root,home,var/{log,lib},opt}
chmod 1777 "$STAGE/tmp"
cp -a "$ROOT/overlay/." "$STAGE/"
install -m 0755 "$BUILD/bin/govinit" "$STAGE/sbin/govinit"
install -m 0755 "$BUILD/bin/govecho" "$STAGE/bin/govecho"
ln -sf govecho "$STAGE/bin/echo"     # эхо дистрибутива — каноническое
echo "$DISTRO_VERSION" > "$STAGE/etc/govechoos-version"

# ---------- 3. busybox --------------------------------------------------
BB=""
if command -v busybox >/dev/null; then
    BB="$(command -v busybox)"
elif [ -x "$BUILD/busybox" ]; then
    BB="$BUILD/busybox"
else
    log "busybox не найден на хосте — rootfs будет только с govinit/govecho/sh из хоста"
fi

if [ -n "$BB" ]; then
    log "устанавливаю busybox ($BB) как /bin/sh и утилиты..."
    install -m 0755 "$BB" "$STAGE/bin/busybox"
    for app in sh ls cat cp mv rm mkdir rmdir ln mount umount ps kill grep sed awk \
               head tail wc du df free uptime dmesg hostname ifconfig ip ping sleep \
               true false echo printf test tar gzip bunzip2 more less vi clear id whoami; do
        ln -sf busybox "$STAGE/bin/$app" 2>/dev/null || true
    done
    for app in init reboot poweroff halt shutdown switch_root mdev insmod; do
        ln -sf ../bin/busybox "$STAGE/sbin/$app" 2>/dev/null || true
    done
    # фирменный govecho важнее busybox-echo: симлинк bin/echo уже указывает на него
    ln -sf govecho "$STAGE/bin/echo"
else
    # fallback: копируем статический шелл с хоста, если возможно
    for b in /bin/sh /bin/busybox; do
        [ -x "$b" ] && { install -m 0755 "$b" "$STAGE/bin/sh"; break; }
    done
fi

# dynamic-сборка требует libc внутри образа
if ldd "$STAGE/sbin/govinit" 2>/dev/null | grep -q 'not a dynamic'; then
    log "govinit статический — зависимости в образ не копируются"
elif ldd "$STAGE/sbin/govinit" >/dev/null 2>&1; then
    log "копирую зависимости libc в образ (динамическая сборка)..."
    ldd "$STAGE/sbin/govinit" "$STAGE/bin/govecho" 2>/dev/null | \
      awk '/=> \// {print $3} /^\/(lib|ld)/ {print $1}' | sort -u | while read -r lib; do
        [ -f "$lib" ] || continue
        dest="$STAGE/lib$(dirname "$lib" | sed 's|^/||;s|lib.*||')$(basename "$lib")"
        mkdir -p "$(dirname "$dest")"
        cp -n "$lib" "$dest" 2>/dev/null || true
    done
    LDCONF=$(ldd "$STAGE/sbin/govinit" | awk '/ld-linux/{print $3}' | head -1)
    [ -n "$LDCONF" ] && { mkdir -p "$STAGE/lib64"; cp -n "$LDCONF" "$STAGE/lib64/" 2>/dev/null || true; }
fi

# ---------- 4. упаковка ext4 --------------------------------------------
log "упаковываю ext4-образ (${ROOTFS_SIZE_MB} МБ)..."
mkfs_cmd="$(command -v mkfs.ext4 || command -v mke2fs || true)"
[ -n "$mkfs_cmd" ] || die "не найден mkfs.ext4/mke2fs (пакет e2fsprogs)"
rm -f "$IMG"
dd if=/dev/zero of="$IMG" bs=1M count="$ROOTFS_SIZE_MB" status=progress
$mkfs_cmd -q -L GOVECHOOS -N 8192 -I 256 -m 0 "$IMG"

if command -s debugfs >/dev/null 2>&1 || command -v debugfs >/dev/null 2>&1; then
    # debugfs пишет дерево без прав root/loop-устройств
    log "записываю дерево через debugfs (без root)..."
    python3 - "$IMG" "$STAGE" <<'PYEOF'
import os, stat as S, subprocess, sys
img, stage = sys.argv[1], sys.argv[2]
cmds = []

def ensure_dir(rel):
    """гарантировать существование каталога в образе (идемпотентно)"""
    if rel in ("", "."):
        return
    cmds.append(f'mkdir {rel} 755')

def walk(base, rel=""):
    d = os.path.join(base, rel) if rel else base
    for name in sorted(os.listdir(d)):
        p = os.path.join(d, name)
        rp = rel + "/" + name
        st = os.lstat(p)
        if S.S_ISLNK(st.st_mode):
            target = os.readlink(p)
            # битые симлинки пропускаем (в staging они могут указывать на /proc и т.п.)
            if not os.path.exists(p):
                continue
            ensure_dir(os.path.dirname(rp))
            cmds.append(f'symlink {rp} {target}')
        elif S.S_ISDIR(st.st_mode):
            cmds.append(f'mkdir {rp} {(st.st_mode & 0o7777):o}')
            walk(base, rp)
        elif S.S_ISREG(st.st_mode):
            mode = (st.st_mode & 0o7777) or 0o644
            ensure_dir(os.path.dirname(rp))
            cmds.append(f'write {p} {rp}')
            cmds.append(f'setmode {rp} {mode:o}')
        # спец-устройства (fifo/socket/device) в debugfs не пишем

walk(stage)
# обязательные точки монтирования даже если остались пустыми
for extra in ("/dev", "/proc", "/sys", "/run", "/tmp", "/mnt", "/root"):
    cmds.insert(0, f'mkdir {extra} 755')
with open("/tmp/debugfs.script", "w") as f:
    f.write("\n".join(cmds) + "\n")
subprocess.run(["debugfs", "-w", "-f", "/tmp/debugfs.script", img], check=True)
PYEOF
else
    # классический путь: loop-mount (нужен root)
    log "монтирую образ через loop (требуются права root)..."
    MNT="$BUILD/mnt"
    mkdir -p "$MNT"
    sudo mount -o loop "$IMG" "$MNT"
    sudo cp -a "$STAGE/." "$MNT/"
    sudo umount "$MNT"
fi

log "готово: $IMG"
ls -lh "$IMG"
