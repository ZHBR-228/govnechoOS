#Requires -Version 5.0
<#
.SYNOPSIS
    GovechoOS — сборка модифицированного ISO (Ubuntu/Debian) на Windows 10/11.
.DESCRIPTION
    Качает официальный ISO базы, распаковывает его, "въедает" в него фирменные
    компоненты Govecho (баннер входа, профиль GNOME-чистоты, стартовые приложения),
    пересобирает гибридный ISO BIOS+UEFI (xorriso через WSL).

    РЕЖИМЫ УСТАНОВКИ (переключаются параметром):
      по умолчанию  — интерактивная установка: никаких preseed/autoinstall,
                      установщик задаёт все вопросы сам, пользователь следит
                      и настраивает каждый шаг;
      -AutoInstall  — старый режим без вопросов (preseed), для массовых
                      развёртываний, когда контроль не нужен.

    Скрипт НИКОГДА не записывает ISO на диск/флешку автоматически — он только
    собирает файл образа в WorkDir. Запись оставляйте проверенным инструментам
    (Rufus/Ventoy/balenaEtcher) или запускайте VirtualBox прямо на ISO.

    Требования: Windows 10/11 x64 + PowerShell 5+. Если WSL не настроен — скрипт
    сам предложит `wsl --install -d Ubuntu` (однократно). Конфигурация базовых ISO
    вынесена в govechoos.build.json — версии/URL можно менять без правки кода.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\scripts\build_windows.ps1
    powershell -ExecutionPolicy Bypass -File .\scripts\build_windows.ps1 -Base debian
    powershell -ExecutionPolicy Bypass -File .\scripts\build_windows.ps1 -AutoInstall
.NOTES
    Автор: ZHBR-228 · Лицензия: MIT · github.com/ZHBR-228/govnechoOS
#>
[CmdletBinding()]
param(
    [ValidateSet('ubuntu','debian')][string]$Base = '',   # пусто => из govechoos.build.json
    [string]$WorkDir = "$env:USERPROFILE\govecho_build",
    [switch]$SkipDownload,
    [switch]$AutoInstall,  # включить preseed-режим без вопросов (по умолчанию ВЫКЛ:
                           # установка интерактивная, чтобы можно было всё контролировать)
    [switch]$GuiProtocol   # режим для GUI (build_gui.ps1): пишет в stdout строки
                           # "PROGRESS|<0-100>|<фаза>" вместо Write-Host-оформления
)
$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'
$VER = '2.1.0'

# ---------- Протокол прогресса ----------
# В GUI-режиме каждая фаза дублируется машиночитаемой строкой PROGRESS|pct|phase,
# которую перехватывает мини-приложение build_gui.ps1 и показывает процент/этап.
function Report([double]$pct, [string]$phase) {
    if ($GuiProtocol) {
        [Console]::Out.WriteLine(("PROGRESS|{0}|{1}" -f [math]::Round($pct), $phase))
        [Console]::Out.Flush()
    } else {
        Write-Host ("[{0}%] {1}" -f [math]::Round($pct), $phase) -ForegroundColor Cyan
    }
}

# ---------- 0. Конфигурация: govechoos.build.json ----------
$cfgPath = Join-Path $PSScriptRoot '..\govechoos.build.json'
if (-not (Test-Path $cfgPath)) { throw "Не найден $cfgPath — список базовых ISO" }
$cfg = Get-Content $cfgPath -Raw | ConvertFrom-Json
if (-not $Base) { $Base = $cfg.defaultBase }
$b = $cfg.bases.$Base
if (-not $b) { throw "База '$Base' не описана в govechoos.build.json" }

$outIso  = Join-Path $WorkDir "govechoos-$VER-live-$Base.iso"
$origIso = Join-Path $WorkDir $b.file
New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null

Report 2 "Конфигурация загружена (база: $Base)"
Write-Host "== GovechoOS Windows Builder v$VER ($Base) ==" -ForegroundColor Cyan

# ---------- 1. WSL с инструментами упаковки (нужен для squashfs/xorriso) ----------
$wslOk = $false
try { wsl -l -q | Out-Null; $wslOk = $true } catch {}
if (-not $wslOk) {
    Write-Host @"
WSL не установлен. Выполните ОДНОКРАТНО в админ-PowerShell:
    wsl --install -d Ubuntu
затем перезагрузите ПК и запустите этот скрипт снова.
"@ -ForegroundColor Yellow
    Read-Host "Нажмите Enter после установки WSL (или Ctrl+C для выхода)"
}
# инструменты сборки внутри WSL-дистрибутива
Report 8 "Подготовка инструментов сборки (xorriso/squashfs в WSL)..."
wsl -u root -- bash -c "command -v xorriso >/dev/null || (apt-get update -qq && apt-get install -y -qq xorriso squashfs-tools isolinux syslinux-common)"

# ---------- 2. Скачивание базового ISO + проверка sha256 ----------
if (-not $SkipDownload -and -not (Test-Path $origIso)) {
    Report 10 "Скачиваю базовый ISO: $($b.url)"
    Write-Host "Скачиваю: $($b.url)" -ForegroundColor Cyan
    # качаем через WebClient с событийным прогрессом => GUI видит реальные % скачивания
    $wc = New-Object System.Net.WebClient
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $dlArgs = {
        param($s, $e)
        if ($e.ProgressPercentage -ge 0) {
            $overall = 10 + ($e.ProgressPercentage * 0.30)   # скачивание = коридор 10..40%
            $mbps = if ($sw.Elapsed.TotalSeconds -gt 1) { [math]::Round($e.BytesReceived/1MB/$sw.Elapsed.TotalSeconds,1) } else { 0 }
            [Console]::Out.WriteLine(("PROGRESS|{0}|Скачивание ISO... {1} МБ/с" -f [math]::Round($overall), $mbps))
            [Console]::Out.Flush()
        }
    }
    Register-ObjectEvent $wc DownloadProgressChanged -SourceIdentifier dlprog -Action $dlArgs | Out-Null
    $wc.DownloadFile($b.url, "$origIso.part")
    Unregister-Event -SourceIdentifier dlprog -EA SilentlyContinue
    $wc.Dispose()
    if ($b.sha256) {
        Report 42 "Проверяю контрольную сумму sha256..."
        $actual = (Get-FileHash "$origIso.part" -Algorithm SHA256).Hash.ToLower()
        if ($actual -ne $b.sha256) { Remove-Item "$origIso.part"; throw "sha256 не совпал: ждали $($b.sha256), получили $actual" }
        Write-Host "sha256 ✓" -ForegroundColor Green
    }
    Move-Item "$origIso.part" $origIso -Force
}
if (-not (Test-Path $origIso)) { throw "Базовый ISO не найден: $origIso" }

# ---------- 3. Распаковка ISO средствами Windows ----------
$src = Join-Path $WorkDir 'extracted'
if (-not (Test-Path $src)) {
    Report 46 "Распаковываю содержимое ISO на диск сборки..."
    Write-Host "Монтирую ISO -> robocopy..." -ForegroundColor Cyan
    $img = Mount-DiskImage -ImagePath $origIso -PassThru
    $drv = ($img | Get-Volume).DriveLetter
    robocopy "${drv}:\" $src /E /NFL /NDL /NJH /NJS | Out-Null
    Dismount-DiskImage -ImagePath $origIso | Out-Null
}

# ---------- 4. Фирменный слой Govecho поверх дерева ISO ----------
Report 58 "Наслаиваю фирменный слой Govecho (компоненты, меню загрузчика)..."
Write-Host "Наслаиваю фирменные компоненты Govecho..." -ForegroundColor Cyan
# 4a. каталог /govecho с нашим DEB-пакетом и списком стартовых приложений
$gv = Join-Path $src 'govecho'
New-Item -ItemType Directory -Force -Path $gv | Out-Null
Copy-Item (Join-Path $PSScriptRoot '..\Release\govechoos-gnome_2.1.0_amd64.deb') $gv -Force -EA SilentlyContinue
@"
# Ряд стартовых программ GovechoOS (ставятся при автоустановке)
gnome-shell gdm3 firefox htop vim gnome-calculator nautilus gnome-terminal
"@ | Set-Content (Join-Path $gv 'startapps.list') -Encoding ASCII

# 4b. preseed: ТОЛЬКО при -AutoInstall. По умолчанию образ интерактивный —
#     установщик сам задаёт все вопросы, пользователь контролирует каждый шаг.
if ($AutoInstall) {
    New-Item -ItemType Directory -Force -Path (Join-Path $src 'preseed') | Out-Null
@"
d-i auto-install/enable boolean true
d-i pkgsel/include string $( (Get-Content (Join-Path $gv 'startapps.list') | Where-Object {$_ -notmatch '^#'}) -join ' ')
d-i pkgsel/default-desktop-environment string ubuntu-desktop
d-i finish-install/reboot_in_progress note
d-i preseed/late_command string in-target apt-get install -y /cdrom/govecho/*.deb || true; \
  in-target bash -lc 'command -v govclean >/dev/null && govclean apply --all-users || true'
"@ | Set-Content (Join-Path $src 'preseed\govechoos.seed') -Encoding ASCII
}

# 4c. Пункты меню загрузчиков (BIOS-isolinux и EFI-grub), если они есть в базе.
#     Основной пункт — ИНТЕРАКТИВНЫЙ (без automatic-ubiquity/quiet splash):
#     видно каждый шаг установки, можно настроить язык, разделы, пользователей.
$bootAppend = 'boot=casper ---'                                   # интерактив
$autoAppend = 'file=/cdrom/preseed/govechoos.seed boot=casper automatic-ubiquity quiet splash ---'
$txt = Join-Path $src 'isolinux\txt.cfg'
if (Test-Path $txt) {
    Add-Content $txt @"

label govecho
  menu label ^GovechoOS $VER (GNOME Edition - interactive install)
  kernel /casper/vmlinuz
  append  $bootAppend
  initrd /casper/initrd
"@
    if ($AutoInstall) {
        Add-Content $txt @"

label govecho-auto
  menu label GovechoOS $VER (^Auto-install, no questions)
  kernel /casper/vmlinuz
  append  $autoAppend
  initrd /casper/initrd
"@
    }
}
foreach ($gc in @((Join-Path $src 'boot\grub\grub.cfg'), (Join-Path $src 'EFI\ubuntu\grub.cfg'))) {
    if (Test-Path $gc) {
        Add-Content $gc @"

menuentry 'GovechoOS $VER (GNOME Edition - interactive install)' {
  linux /casper/vmlinuz $bootAppend
  initrd /casper/initrd
}
"@
        if ($AutoInstall) {
            Add-Content $gc @"

menuentry 'GovechoOS $VER (Auto-install, no questions)' {
  linux /casper/vmlinuz $autoAppend
  initrd /casper/initrd
}
"@
        }
    }
}

# ---------- 5. Пересборка hybrid-ISO (xorriso в WSL) ----------
Report 72 "Пересобираю гибридный ISO (BIOS + UEFI)... это самый долгий шаг"
Write-Host "Пересобираю гибридный ISO (BIOS + UEFI)..." -ForegroundColor Cyan
function ToWslPath([string]$p) { ($p -replace '^([A-Za-z]):', '/mnt/$1').ToLower().Replace('\','/') }
$wSrc = ToWslPath $src; $wOut = ToWslPath $outIso
# берём загрузочные артефакты того, что дала база (ubuntu: casper+EFI; debian: install.amd+EFI)
$bootArgs = '-isohybrid-mbr isohdpfx.bin -b isolinux/isolinux.bin -c isolinux/boot.cat -no-emul-boot -boot-load-size 4 -boot-info-table -eltorito-alt-boot -e boot/grub/efi.img -no-emul-boot -isohybrid-gpt-basdat'
if ($Base -eq 'debian') { $bootArgs = '-isohybrid-mbr isohdpfx.bin -b isolinux/isolinux.bin -c isolinux/boot.cat -no-emul-boot -boot-load-size 4 -boot-info-table -eltorito-alt-boot -e images/efi/boot.img -no-emul-boot -isohybrid-gpt-basdat' }
# isolinux hybrid MBR template кладём в корень дерева
Copy-Item (Join-Path $src 'isolinux\isohdpfx.bin') (Join-Path $src 'isohdpfx.bin') -Force -EA SilentlyContinue
wsl -u root -- bash -c "set -e; cd '$wSrc'; xorriso -as mkisofs -r -J -joliet-long -cache-inodes -V 'GOVECHOOS_$($Base.ToUpper())' $bootArgs -o '$wOut' ."
if (-not (Test-Path $outIso)) { throw "Не удалось собрать ISO" }
$szMB = [math]::Round((Get-Item $outIso).Length/1MB,1)
Report 95 "Проверяю готовый образ..."
if (-not (Get-Item $outIso).Length) { throw "ISO пустой?" }
Report 100 "Готово: govechoos-$VER-live-$Base.iso ($szMB МБ)"
Write-Host "✓ Готово: $outIso ($szMB MB)" -ForegroundColor Green

# ---------- 6. Готово ----------
# ВНИМАТЕЛЬНОЕ РЕШЕНИЕ: скрипт НЕ пишет ISO ни на какие диски/флешки.
# Запись образа — опасная операция (стирает диск), а кроме того многим нужно
# самому выбирать способ загрузки и следить за установкой. Поэтому builder
# останавливается на файле ISO в WorkDir.
Write-Host @"

✓ Сборка завершена. Файл образа: $outIso ($szMB MB)

Что дальше (запись образа вы делаете сами, как вам удобнее):
  • Тест без записи: VirtualBox/VMware -> новая ВМ -> носитель = этот ISO;
  • Флешка: Rufus / Ventoy / balenaEtcher (выберите файл образа вручную);
  • При загрузке с флешки откроется меню GovechoOS — установка ИНТЕРАКТИВНАЯ:
    установщик задаёт все вопросы (язык, разделы, пользователь), вы всё
    видите и настраиваете. Режим «без вопросов» включается пересборкой
    с флагом -AutoInstall (в меню появится отдельный пункт).
"@ -ForegroundColor Green
