#!/usr/bin/env bash
# govechoOS GNOME Edition — установка DEB-пакета на целевую систему (Debian/Ubuntu/govechoOS)
# Автор: ZHBR-228 | Лицензия: MIT (LICENSE)
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEB="$ROOT/build/export/govechoos-gnome_$(cat "$ROOT/VERSION")_amd64.deb"
[[ -f "$DEB" ]] || { echo "Пакет не найден: $DEB — сначала выполните ./scripts/build_deb.sh"; exit 1; }
echo "[govechoOS] Установка GNOME-пакета: $DEB"
sudo dpkg -i "$DEB"
echo "[govechoOS] Дотягивание зависимостей (gnome-shell, gdm3 и т.д.)..."
sudo apt-get -f install -y
echo "[govechoOS] Готово! Перезагрузитесь и выберите сеанс \"govechoOS GNOME\" в GDM."
