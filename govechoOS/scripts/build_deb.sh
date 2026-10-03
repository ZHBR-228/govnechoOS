#!/usr/bin/env bash
# govechoOS — сборка DEB-пакета govechoos-gnome (GNOME Edition)
# Автор: ZHBR-228 | Лицензия: MIT (LICENSE)
# Результат: build/export/govechoos-gnome_<version>_amd64.deb
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/config/build.conf"

VERSION="$DISTRO_VERSION"
PKG="govechoos-gnome"
ARCH="amd64"
STAGE="$ROOT/build/deb-stage-$PKG"
EXPORT_DIR="$ROOT/build/export"

echo "[1/5] Очистка staging..."
rm -rf "$STAGE"
mkdir -p "$STAGE"

echo "[2/5] Копирование дерева пакета..."
cp -a "$ROOT/pkgroot/." "$STAGE/"

# Бинарные компоненты, собранные из исходников govechoOS
if [[ -x "$ROOT/build/bin/govinit" ]]; then
    install -m 0755 "$ROOT/build/bin/govinit" "$STAGE/sbin/govinit"
fi
if [[ -x "$ROOT/build/bin/govecho" ]]; then
    install -m 0755 "$ROOT/build/bin/govecho" "$STAGE/usr/local/bin/govecho"
fi
# govwelcome — приветствие стартовой сессии (собирается на месте, если ещё нет)
if [[ ! -x "$ROOT/build/bin/govwelcome" ]]; then
    mkdir -p "$ROOT/build/bin"
    gcc -O2 -Wall -Wextra -o "$ROOT/build/bin/govwelcome" "$ROOT/src/govwelcome.c"
fi
install -m 0755 "$ROOT/build/bin/govwelcome" "$STAGE/usr/local/bin/govwelcome"
# govstartapps — ряд стартовых программ (скрипт уже в pkgroot)
chmod 0755 "$STAGE/usr/local/bin/govstartapps"

# Фирменные юниты сессии в /usr/share/gnome/govsession (уже в pkgroot)

echo "[3/5] Генерация файлов сессии GNOME (Gio.Keyfile)..."
if ! python3 "$ROOT/scripts/gen_session.py" "$STAGE/usr"; then
    echo "ВНИМАНИЕ: Gio-генерация недоступна; используются статические шаблоны pkgroot." >&2
fi


echo "[4/5] Настройка прав и meta-файлов DEBIAN..."
chmod 0755 "$STAGE/DEBIAN/postinst" "$STAGE/DEBIAN/prerm" "$STAGE/DEBIAN/config" 2>/dev/null || true
# control: подставить актуальную версию
sed -i "s/^Version: .*/Version: ${VERSION}/" "$STAGE/DEBIAN/control"
find "$STAGE" -type d -exec chmod 0755 {} +
find "$STAGE" -type f ! -path "*/DEBIAN/*" ! -name copyright -exec chmod 0644 {} +
find "$STAGE" -type f -name copyright -exec chmod 0644 {} + 2>/dev/null || true
chmod 0755 "$STAGE/usr/local/bin/govecho" "$STAGE/sbin/govinit" \
    "$STAGE/usr/local/bin/govwelcome" "$STAGE/usr/local/bin/govstartapps" 2>/dev/null || true

echo "[5/5] dpkg-deb --build..."
mkdir -p "$EXPORT_DIR"
DEB="$EXPORT_DIR/${PKG}_${VERSION}_${ARCH}.deb"
dpkg-deb --root-owner-group --build "$STAGE" "$DEB"

echo "Готово: $DEB"
dpkg-deb -I "$DEB" | sed -n '1,30p'
dpkg-deb -c "$DEB" | awk '{print $6}' | sed 1d | head -20
