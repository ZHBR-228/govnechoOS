#!/usr/bin/env bash
# govclean.sh — «чистота GNOME» для govechoOS
# Применяет/откатывает профиль чистого рабочего стола:
#   * пустой десктоп (без иконок), без «корзины» на столе
#   * только Activities + часы в верхней панели, никаких доков на столе
#   * единая тема Adwaita(-dark), тёмный стиль, без анимаций-мишуры
#   * файловый менеджер: компактный вид, скрытые файлы по требованию
#   * отключены не нужные вgovechoOS расширения-дубликаты
#
# Использование:
#   govclean apply            применить профиль (нужен dconf/gsettings в GNOME)
#   govclean revert           вернуть системные значения по умолчанию
#   govclean show             показать применяемые ключи
#   govclean export <file>    выгрузить текущие настройки GNOME в файл
#   govclean import <file>    загрузить настройки из файла
#
# Автор: ZHBR-228
# Лицензия: MIT (см. файл LICENSE)
set -euo pipefail

PROFILE="/usr/share/govechoos/gnome-clean.dconf"

have() { command -v "$1" >/dev/null 2>&1; }

apply_keys() {
    # schema key value — только если схема существует в системе
    local schema="$1" key="$2" val="$3"
    if have gsettings && gsettings list-schemas 2>/dev/null | grep -qx "$schema"; then
        gsettings set "$schema" "$key" "$val" 2>/dev/null \
            || echo "  пропущено: $schema $key (недоступно)"
        echo "  ✓ $schema $key = $val"
    fi
}

cmd_show() {
    cat <<'EOF'
Профиль чистоты GNOME govechoOS (ключи):
  org.gnome.desktop.background show-desktop-icons        false
  org.gnome.desktop.interface   enable-animations        false
  org.gnome.desktop.interface   gtk-theme                Adwaita-dark
  org.gnome.desktop.interface   color-scheme             prefer-dark
  org.gnome.desktop.wm.preferences button-layout         appmenu:
  org.gnome.shell               always-show-log-out      true
  org.gnome.nautilus.preferences default-folder-viewer   'list-view'
  org.gnome.nautilus.preferences show-hidden-files       false
  org.gnome.desktop.screensaver lock-enabled            true
EOF
}

cmd_apply() {
    echo "goveclean: применение профиля чистоты GNOME…"
    apply_keys org.gnome.desktop.background     show-desktop-icons       "false"
    apply_keys org.gnome.desktop.interface      enable-animations        "false"
    apply_keys org.gnome.desktop.interface      gtk-theme                "Adwaita-dark"
    apply_keys org.gnome.desktop.interface      color-scheme             "prefer-dark"
    apply_keys org.gnome.desktop.wm.preferences button-layout            "appmenu:"
    apply_keys org.gnome.shell                  always-show-log-out      "true"
    apply_keys org.gnome.nautilus.preferences   default-folder-viewer    "'list-view'"
    apply_keys org.gnome.nautilus.preferences   show-hidden-files        "false"
    apply_keys org.gnome.desktop.screensaver    lock-enabled             "true"

    # отключить типовые дубликаты-расширения, если они есть
    if have gnome-extensions; then
        for ext in apps-menu@gnome-shell-extensions.gcampax.github.com \
                   places-status-button@gnome-shell-extensions.gcampax.github.com; do
            gnome-extensions disable "$ext" 2>/dev/null || true
        done
        echo "  ✓ лишние расширения отключены (если присутствовали)"
    fi

    # экспорт canonical-профиля в домашний dconf через load, если доступен
    if [ -f "$PROFILE" ] && have dconf; then
        dconf load / < "$PROFILE" 2>/dev/null || true
        echo "  ✓ загружен канонический профиль $PROFILE"
    fi
    echo "Готово: GNOME приведён к чистому виду govechoOS."
}

cmd_revert() {
    echo "goveclean: возврат настроек GNOME к значениям по умолчанию…"
    for pair in \
        "org.gnome.desktop.background show-desktop-icons" \
        "org.gnome.desktop.interface enable-animations" \
        "org.gnome.desktop.interface gtk-theme" \
        "org.gnome.desktop.interface color-scheme" \
        "org.gnome.desktop.wm.preferences button-layout" \
        "org.gnome.nautilus.preferences default-folder-viewer" \
        "org.gnome.nautilus.preferences show-hidden-files"; do
        set -- $pair
        if have gsettings && gsettings list-schemas 2>/dev/null | grep -qx "$1"; then
            gsettings reset "$1" "$2" 2>/dev/null || true
            echo "  ↺ $1 $2"
        fi
    done
    echo "Готово."
}

cmd_export() {
    local out="${1:?нужен файл назначения}"
    have dconf || { echo "dconf недоступен"; exit 1; }
    dconf dump / > "$out"
    echo "Экспортировано в $out ($(wc -l < "$out") строк)"
}

cmd_import() {
    local in="${1:?нужен файл источника}"
    have dconf || { echo "dconf недоступен"; exit 1; }
    [ -f "$in" ] || { echo "нет файла $in"; exit 1; }
    dconf load / < "$in"
    echo "Импортировано из $in"
}

case "${1:-show}" in
    apply)   cmd_apply ;;
    revert)  cmd_revert ;;
    show)    cmd_show ;;
    export)  cmd_export "${2:-}" ;;
    import)  cmd_import "${2:-}" ;;
    *) echo "Использование: govclean {apply|revert|show|export <f>|import <f>}"; exit 2 ;;
esac
