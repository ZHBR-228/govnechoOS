#!/usr/bin/env python3
"""Автор: ZHBR-228 | Лицензия: MIT (файл LICENSE)

Генерация файлов сессии govechoOS GNOME через Gio.Keyfile (GSettings-совместимо).

Создаёт:
  <out>/share/gnome/session/gnome.session.d/50_govechoos.conf  — имя "govechoOS GNOME"
  <out>/share/gnome/session/gnome.session                       — полная копия базовой
  <out>/share/wayland-sessions/govechoos-wayland.desktop        — сессия Wayland для GDM
Использует тот же механизм, что и gnome-session (GLib GKeyFile), поэтому
формат гарантированно корректный. Fallback на sed, если gi/GLib недоступны.
"""
import os
import sys

BASE_SESSION = "/usr/share/gnome/session/gnome.session"
WAYLAND_DESKTOP_SRC = "/usr/share/wayland-sessions/org.gnome.Shell.desktop"

def gio_method(out_root: str) -> bool:
    try:
        import gi
        gi.require_version("Gio", "2.0")
        from gi.repository import Gio
    except Exception as exc:
        print(f"gi/GLib недоступен: {exc}", file=sys.stderr)
        return False

    # --- gnome.session override: Name=govechoOS GNOME -------------------
    if not os.path.isfile(BASE_SESSION):
        print(f"Базовый {BASE_SESSION} не найден — пропускаю session override",
              file=sys.stderr)
        base_ok = False
    else:
        kf = Gio.Keyfile()
        kf.load(BASE_SESSION, Gio.KeyfileLoadType.NONE)
        kf.set_string("Session", "Name", "govechoOS GNOME")
        kf.set_string("Session", "Description",
                      "The govechoOS desktop experience powered by GNOME Shell")
        os.makedirs(os.path.join(out_root, "share/gnome/session"), exist_ok=True)
        with open(os.path.join(out_root, "share/gnome/session/gnome.session"),
                  "w", encoding="utf-8") as fh:
            fh.write(kf.to_string())
        conf_dir = os.path.join(out_root, "share/gnome/session",
                                "gnome.session.d")
        os.makedirs(conf_dir, exist_ok=True)
        delta = Gio.Keyfile()
        delta.set_string("Session", "Name", "govechoOS GNOME")
        with open(os.path.join(conf_dir, "50_govechoos.conf"),
                  "w", encoding="utf-8") as fh:
            fh.write(delta.to_string())
        base_ok = True

    # --- wayland .desktop для GDM: полная копия + смена имени -------------
    if not os.path.isfile(WAYLAND_DESKTOP_SRC) and \
       os.path.isfile(os.path.join(out_root, "share/wayland-sessions",
                                   "govechoos-wayland.desktop")):
        print("Локальный шаблон уже в pkgroot — Gio-генерация пропущена.",
              file=sys.stderr)
        return base_ok
    if os.path.isfile(WAYLAND_DESKTOP_SRC):
        kd = Gio.Keyfile()
        kd.load(WAYLAND_DESKTOP_SRC, Gio.KeyfileLoadType.NONE)
        for grp in kd.get_groups():
            for key in kd.get_keys(grp):
                pass  # load() уже сохранил все группы/ключи в to_string()
        kd.set_string("Desktop Entry", "Name", "govechoOS GNOME (Wayland)")
        if kd.has_key("Desktop Entry", "Comment"):
            kd.set_string("Desktop Entry", "Comment",
                          "This session logs you into govechoOS with GNOME Shell")
        wdir = os.path.join(out_root, "share/wayland-sessions")
        os.makedirs(wdir, exist_ok=True)
        with open(os.path.join(wdir, "govechoos-wayland.desktop"),
                  "w", encoding="utf-8") as fh:
            fh.write(kd.to_string())
    else:
        print(f"{WAYLAND_DESKTOP_SRC} не найден — пропуск", file=sys.stderr)
        return base_ok

    return base_ok


def sed_fallback(out_root: str) -> bool:
    """Запасной вариант: текстовая подстановка имени сессии.
    Если локальные шаблоны pkgroot уже скопированы в out_root — это успех."""
    ok = False
    tmpl_w = os.path.join(out_root, "share/wayland-sessions",
                          "govechoos-wayland.desktop")
    if os.path.isfile(tmpl_w):
        ok = True
    sess_d = os.path.join(out_root, "share/gnome/session", "gnome.session.d")
    if os.path.isdir(sess_d):
        ok = True
    if os.path.isfile(BASE_SESSION):
        d = os.path.join(out_root, "share/gnome/session")
        os.makedirs(d, exist_ok=True)
        txt = open(BASE_SESSION, encoding="utf-8").read()
        lines = []
        for line in txt.splitlines():
            if line.startswith("Name="):
                line = "Name=govechoOS GNOME"
            lines.append(line)
        if not any(l.startswith("Name=") for l in lines):
            lines.insert(1, "Name=govechoOS GNOME")
        open(os.path.join(d, "gnome.session"), "w", encoding="utf-8").write(
            "\n".join(lines) + "\n")
        ok = True
    if os.path.isfile(WAYLAND_DESKTOP_SRC):
        w = os.path.join(out_root, "share/wayland-sessions")
        os.makedirs(w, exist_ok=True)
        txt = open(WAYLAND_DESKTOP_SRC, encoding="utf-8").read()
        out = []
        replaced = False
        for line in txt.splitlines():
            if line.startswith("Name=") and not replaced:
                line = "Name=govechoOS GNOME (Wayland)"
                replaced = True
            out.append(line)
        if not replaced:
            out.insert(1, "Name=govechoOS GNOME (Wayland)")
        open(os.path.join(w, "govechoos-wayland.desktop"), "w",
             encoding="utf-8").write("\n".join(out) + "\n")
        ok = True
    return ok


if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else "."
    if not gio_method(out):
        if not sed_fallback(out):
            print("Не удалось создать файлы сессии.", file=sys.stderr)
            sys.exit(1)
    print("Файлы сессии govechoOS GNOME сгенерированы в:", out)
