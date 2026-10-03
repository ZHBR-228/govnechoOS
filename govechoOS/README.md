# govechoOS

> **Автор:** ZHBR-228 · **Лицензия:** MIT

**govechoOS** — учебный минималистичный Linux-дистрибутив из исходников
(LFS-подобная сборка). Система состоит из:

- собственного init (PID 1) на C — `/sbin/govinit`
- фирменной утилиты `echo` под названием `govecho` (отсюда и имя дистрибутива)
- busybox-окружения (/bin/sh, утилиты)
- образа rootfs в формате ext4, загружаемого напрямую ядром через `init=/sbin/govinit`

## Структура репозитория

```
govechoOS/
├── README.md            этот файл
├── VERSION              версия дистрибутива
├── config/build.conf    параметры сборки (архитектура, размер образа, зеркала)
├── scripts/
│   ├── build_rootfs.sh  сборка корневой ФС (ext4-образ)
│   └── run_qemu.sh      запуск собранного образа в QEMU
├── src/
│   ├── govinit.c        собственный init (PID 1)
│   └── govecho.c        фирменная команда echo
└── overlay/             файлы, копируемые в rootfs как есть
    └── etc/passwd, group, issue ...
```


## GNOME Edition — экспорт и установка

govechoOS поставляется с **GNOME Edition**: DEB-пакет `govechoos-gnome`,
который можно экспортировать на любую Debian/Ubuntu-систему (или в rootfs
govechoOS) и установить как обычный пакет.

### Что делает пакет
- добавляет сеанс входа **"govechoOS GNOME"** в GDM (Wayland + X11);
- устанавливает фирменные компоненты: `/sbin/govinit`, `/usr/local/bin/govecho`;
- применяет конфигурацию GNOME через dconf (`/etc/dconf/db/local.d/30-govechoos`):
  баннер экрана входа, тёмная тема Adwaita-dark, фон рабочего стола;
- регистрирует пользовательские systemd-юниты сессии
  (`/usr/share/gnome/govsession/*.service`);
- добавляет приложение "About govechoOS";
- **ряд стартовых программ** (XDG Autostart): при входе в сессию автоматически
  запускаются приветствие `govwelcome` и `govstartapps`, который открывает
  Файлы (nautilus), Терминал, Текстовый редактор, Калькулятор, Системный
  монитор и браузер (firefox-esr/firefox/epiphany). Каждая программа
  пропускается, если не установлена — сессия не ломается. Ярлыки автозапуска
  прописываются в `/etc/xdg/autostart`, всем существующим пользователям и
  в `/etc/skel`; пункты меню: "govechoOS Starter Apps", "govechoOS Welcome".

### Сборка и экспорт пакета
```bash
make deb            # или ./scripts/build_deb.sh
# артефакт: build/export/govechoos-gnome_1.0.0_amd64.deb
ls -lh build/export/*.deb   # готово к экспорту (scp/флешка/репозиторий)
```

### Установка на целевую систему
```bash
sudo dpkg -i govechoos-gnome_1.0.0_amd64.deb
sudo apt-get -f install -y      # подтянет gnome-shell, gdm3, mutter и т.д.
# или одной командой из исходного дерева:
./scripts/install_gnome.sh
```
После установки: перезагрузитесь → на экране GDM нажмите на значок пользователя →
выберите сеанс **"govechoOS GNOME"** → войдите.

### Удаление
```bash
sudo apt remove govechoos-gnome
```
(prerm снимет фирменные юниты сессии и fragment dconf.)

### Как это устроено (pkgroot/)
```
pkgroot/
├── DEBIAN/control, postinst, prerm     — meta-файлы пакета
├── sbin/govinit                        — init (собирается из src/)
├── usr/local/bin/govecho               — фирменный echo (собирается из src/)
├── etc/dconf/db/local.d/30-govechoos   — настройки GNOME (баннер логина, темы)
├── etc/dconf/profile/user              — подключение local-базы dconf
├── usr/share/gnome/govsession/*.service— юниты сессии govechoOS
├── usr/share/gnome/session/gnome.session.d/50_govechoos.conf — имя сессии
├── usr/share/wayland-sessions/govechoos-wayland.desktop      — запись для GDM
└── usr/share/applications/govechoos-about.desktop            — пункт меню
```
Скрипт `scripts/gen_session.py` при сборке дополнительно перегенерирует файлы
сессии через GLib `Gio.Keyfile` (тот же парсер, что использует gnome-session),
если на хосте доступны базовые файлы GNOME; иначе используются статические
шаблоны из `pkgroot`.

## Требования для сборки

На хост-системе (Debian/Ubuntu):

```bash
sudo apt install gcc make curl wget tar m4 bison flex \
    util-linux e2fsprogs qemu-system-x86 linux-image-amd64
```

Сборка **полностью автономна** (без интернета) использует stage1 —
статический busybox + gcc. Для «настоящей» LFS-сборки раскомментируйте
этапы в `scripts/build_rootfs.sh`.

## Сборка

```bash
cd govechoOS
./scripts/build_rootfs.sh          # -> build/govechoos-rootfs.img
./scripts/run_qemu.sh              # загрузка в QEMU с init=/sbin/govinit
```

## Запуск без QEMU (через текущее ядро)

```bash
sudo mount -o loop build/govechoos-rootfs.img /mnt/govecho
sudo chroot /mnt/govecho /sbin/govinit   # или просто /bin/sh
```

## Манифест дистрибутива

| Компонент   | Поставщик                 | Версия |
|-------------|---------------------------|--------|
| Ядро        | пакет дистрибутива / QEMU-kernel | ≥ 6.1 |
| libc        | glibc (или musl в slim-режиме)| 2.39   |
| Coreutils   | busybox (multi-call)       | 1.37   |
| Init        | govinit (собственный)      | 1.0    |
| Shell       | busybox sh (ash)           | 1.37   |
| echo        | govecho (собственная)      | 1.0    |

## Лицензия и автор

- **Автор:** ZHBR-228
- **Лицензия:** MIT (полный текст — в файле [LICENSE](LICENSE))
- Формат авторских прав для Debian-пакета: `DEBIAN/copyright` (machine-readable, DEP-5)

© 2026 ZHBR-228. Лицензия: MIT.
