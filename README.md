# govechoOS

> **Автор:** ZHBR-228 · **Лицензия:** MIT

**govechoOS** — учебный Linux-дистрибутив с оболочкой GNOME. Два варианта поставки:

1. **Live ISO (v2.0)** — полноценная загрузочная система на базе **Debian 12 или Ubuntu 24.04**
   с GNOME, фирменными компонентами и установщиком на диск (`live/`).
2. **GNOME Edition DEB + минимальный rootfs (v1.0)** — надстройка над существующей
   Debian/Ubuntu и LFS-подобная сборка с собственным init.

Фирменные компоненты: собственный init `/sbin/govinit` (PID 1), утилита `govecho`
(фирменный echo — отсюда имя дистрибутива), приветствие `govwelcome` и ряд стартовых
программ `govstartapps`.

## Структура репозитория

```
govechoOS/
├── README.md / LICENSE / VERSION / Makefile
├── src/                     исходники C: govinit.c, govecho.c, govwelcome.c, govctl.c
├── config/build.conf        параметры сборки rootfs
├── scripts/                 build_deb.sh, build_rootfs.sh, install_gnome.sh,
│                            run_qemu.sh, gen_session.py, build_windows.ps1 (сборка ISO на Windows)
├── pkgroot/                 содержимое DEB-пакета (файлы сессии GNOME, dconf,
│                            автозапуск, собранные бинарники)
├── overlay/                 файлы минимального rootfs (etc/passwd, issue ...)
└── live/                    LIVE-СИСТЕМА v2.0 (полноценный дистрибутив):
    ├── config/              sources.list.debian, sources.list.ubuntu,
    │                        packages.list (состав системы), apt.conf
    ├── overlay/             os-release, баннер, gdm3-конфиг, systemd-user юнит,
    │                        skel с XDG autostart
    └── scripts/
        ├── build_live.sh    сборка hybrid ISO (BIOS+EFI): debootstrap →
        │                    пакеты → squashfs(zstd) → grub/isolinux
        ├── govecho-installer.sh  установка на диск (GPT, EFI, grub, пользователь)
        └── test_live_build.sh    smoke-тест сборки
```

## Live ISO — сборка и установка (v2.0)

Требования: Debian/Ubuntu, root, `debootstrap xorriso squashfs-tools grub-* isolinux`.

```bash
# Сборка ISO на базе Debian 12 (bookworm) или Ubuntu 24.04 (noble):
sudo ./live/scripts/build_live.sh --base debian
sudo ./live/scripts/build_live.sh --base ubuntu
# Результат: build/export/govechoOS-1.0.0-live-{debian|ubuntu}.iso

# Запись на флешку:
sudo dd if=govechoOS-1.0.0-live-debian.iso of=/dev/sdX bs=4M status=progress

# Установка на диск — из live-сессии ярлык «Установить govechoOS» в меню GNOME,
# либо вручную:
sudo ./govecho-installer.sh /dev/sdX
```

В системе доступны сеанс **«govechoOS GNOME»** (GDM), фирменный баннер входа,
ряд стартовых приложений (файлы, терминал, редактор, калькулятор, системный
монитор, браузер) и утилиты `govecho` / `govwelcome`.


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

### Команды govechoOS (`govctl`) и чистота GNOME (`govclean`)

**`govctl`** — центральная консоль управления дистрибутивом (исходник `src/govctl.c`):

| Команда | Действие |
|---|---|
| `govctl status` | состояние системы: версия, база (debian/ubuntu), все компоненты [+] |
| `govctl info` | о выпуске, авторе (ZHBR-228), отличиях от Debian/Ubuntu |
| `govctl gnome tidy` | применить профиль «чистоты GNOME» (делает govclean apply) |
| `govctl apps list` | показать ряд стартовых программ пользователя |
| `govctl apps add <app>` / `remove <app>` | добавить/убрать приложение из ряда автозапуска |
| `govctl license` / `author` | MIT-лицензия и данные автора |
| `govctl echo …` | быстрый доступ к фирменному `govecho` |
| `govctl version` | версия и база системы |

Алиасы из `/etc/profile.d/govechoos.sh`: `gov`, `gstat`, `gapps`, `gtidy`, `gecho`.
Пункт меню **«govctl — консоль govechoOS»** открывает статус в терминале.

**`govclean`** — утилита чистоты рабочего стола GNOME (`scripts/govclean.sh`):
```bash
govclean apply    # пустой десктоп без иконок, панель только Activities+часы,
                  # тема Adwaita-dark, тёмный стиль, анимации выключены,
                  # nautilus: список без скрытых файлов, блокировка экрана,
                  # лишние расширения gnome-shell отключаются
govclean revert   # вернуть всё к значениям по умолчанию GNOME
govclean show     # перечень применяемых ключей gsettings
govclean export f / import f   # резервная копия / восстановление профиля
```
Канонический dconf-профиль хранится в `/usr/share/govechoos/gnome-clean.dconf`;
при установке пакета `.deb` профиль автоматически применяется ко всем
пользователям (postinst), при удалении — откатывается (prerm).

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


## 🪟 Сборка ISO прямо из Windows (v2.1+)

Двойной щелчок по **`build_windows.bat`** (или `powershell -File scripts/build_windows.ps1`) —
скрипт сам скачает официальный ISO Ubuntu 24.04 или Debian 12 (URL/версии — в `govechoos.build.json`),
распакует его средствами Windows, «въест» фирменный слой Govecho (DEB-пакет, ряд стартовых
приложений, GNOME-чистота `govclean`, пункты меню isolinux/GRUB) и пересоберёт гибридный
BIOS+UEFI образ через xorriso (WSL однократно: `wsl --install -d Ubuntu`).

⚠️ **Важно про установку:** скрипт **никогда не записывает ISO на диски/флешки** — он только
собирает файл образа в папке сборки. Загрузочный пункт меню по умолчанию запускает
**интерактивную установку**: установщик задаёт все вопросы (язык, разделы, пользователь),
вы видите и настраиваете каждый шаг. Режим «без вопросов» включается явно:
`build_windows.ps1 -AutoInstall` (в меню появится отдельный пункт). Для теста образа
рекомендуется VirtualBox напрямую по ISO; для флешки — Rufus/Ventoy/balenaEtcher вручную.

Для BSD-редакции — аналог `GovechoBSD/scripts/build_bsd_windows.ps1`: там ядро уже внутри
FreeBSD ISO, скрипт только наслаивает конфигурацию (ZFS root + GNOME) и пересобирает образ,
не трогая носители.
