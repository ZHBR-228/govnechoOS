-#Requires -Version 5.0
<#
.SYNOPSIS
    GovechoOS - sborka modifitsirovannogo ISO (Ubuntu/Debian) na Windows 10/11.
.DESCRIPTION
    Kachaet ofitsialnyy ISO bazy, raspakovyvaet ego, "vedaet" v nego firmennye
    komponenty Govecho (banner vhoda, profil GNOME-chistoty, startovye prilozheniya),
    peresobiraet gibridnyy ISO BIOS+UEFI (xorriso cherez WSL).

    REZHIMY USTANOVKI (pereklyuchayutsya parametrom):
      po umolchaniyu  - interaktivnaya ustanovka: nikakih preseed/autoinstall,
                      ustanovschik zadaet vse voprosy sam, polzovatel sledit
                      i nastraivaet kazhdyy shag;
      -AutoInstall  - staryy rezhim bez voprosov (preseed), dlya massovyh
                      razvertyvaniy, kogda kontrol ne nuzhen.

    Skript NIKOGDA ne zapisyvaet ISO na disk/fleshku avtomaticheski - on tolko
    sobiraet fayl obraza v WorkDir. Zapis ostavlyayte proverennym instrumentam
    (Rufus/Ventoy/balenaEtcher) ili zapuskayte VirtualBox pryamo na ISO.

    Trebovaniya: Windows 10/11 x64 + PowerShell 5+. Esli WSL ne nastroen - skript
    sam predlozhit `wsl --install -d Ubuntu` (odnokratno). Konfiguratsiya bazovyh ISO
    vynesena v govechoos.build.json - versii/URL mozhno menyat bez pravki koda.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\scripts\build_windows.ps1
    powershell -ExecutionPolicy Bypass -File .\scripts\build_windows.ps1 -Base debian
    powershell -ExecutionPolicy Bypass -File .\scripts\build_windows.ps1 -AutoInstall
.NOTES
    Avtor: ZHBR-228 - Litsenziya: MIT - github.com/ZHBR-228/govnechoOS
#>
[CmdletBinding()]
param(
    [ValidateSet('ubuntu','debian')][string]$Base = '',   # pusto => iz govechoos.build.json
    [string]$WorkDir = "$env:USERPROFILE\govecho_build",
    [switch]$SkipDownload,
    [switch]$AutoInstall,  # vklyuchit preseed-rezhim bez voprosov (po umolchaniyu VYKL:
                           # ustanovka interaktivnaya, chtoby mozhno bylo vse kontrolirovat)
    [switch]$GuiProtocol   # rezhim dlya GUI (build_gui.ps1): pishet v stdout stroki
                           # "PROGRESS|<0-100>|<faza>" vmesto Write-Host-oformleniya
)
$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'
$VER = '2.1.0'

# ---------- Protokol progressa ----------
# V GUI-rezhime kazhdaya faza dubliruetsya mashinochitaemoy strokoy PROGRESS|pct|phase,
# kotoruyu perehvatyvaet mini-prilozhenie build_gui.ps1 i pokazyvaet protsent/etap.
function Report([double]$pct, [string]$phase) {
    if ($GuiProtocol) {
        [Console]::Out.WriteLine(("PROGRESS|{0}|{1}" -f [math]::Round($pct), $phase))
        [Console]::Out.Flush()
    } else {
        Write-Progress -Activity 'GovechoOS Builder' -Status $phase -PercentComplete ([math]::Round($pct))
        Write-Host ("[{0}%] {1}" -f [math]::Round($pct), $phase) -ForegroundColor Cyan
    }
}

# ---------- 0. Konfiguratsiya: govechoos.build.json ----------
$cfgPath = Join-Path $PSScriptRoot '..\govechoos.build.json'
if (-not (Test-Path $cfgPath)) { throw "Ne nayden $cfgPath - spisok bazovyh ISO" }
$cfg = Get-Content $cfgPath -Raw | ConvertFrom-Json
if (-not $Base) { $Base = $cfg.defaultBase }
$b = $cfg.bases.$Base
if (-not $b) { throw "Baza '$Base' ne opisana v govechoos.build.json" }

$outIso  = Join-Path $WorkDir "govechoos-$VER-live-$Base.iso"
$origIso = Join-Path $WorkDir $b.file
New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null

Report 2 "Konfiguratsiya zagruzhena (baza: $Base)"
Write-Host "== GovechoOS Windows Builder v$VER ($Base) ==" -ForegroundColor Cyan

# ---------- 1. WSL s instrumentami upakovki (nuzhen dlya squashfs/xorriso) ----------
$wslOk = $false
try { wsl -l -q | Out-Null; $wslOk = $true } catch {}
if (-not $wslOk) {
    Write-Host @"
WSL ne ustanovlen. Vypolnite ODNOKRATNO v admin-PowerShell:
    wsl --install -d Ubuntu
zatem perezagruzite PK i zapustite etot skript snova.
"@ -ForegroundColor Yellow
    Read-Host "Nazhmite Enter posle ustanovki WSL (ili Ctrl+C dlya vyhoda)"
}
# instrumenty sborki vnutri WSL-distributiva
Report 8 "Podgotovka instrumentov sborki (xorriso/squashfs v WSL)..."
wsl -u root -- bash -c "command -v xorriso >/dev/null || (apt-get update -qq && apt-get install -y -qq xorriso squashfs-tools isolinux syslinux-common)"

# ---------- 2. Skachivanie bazovogo ISO + proverka sha256 ----------
if (-not $SkipDownload -and -not (Test-Path $origIso)) {
    Report 10 "Skachivayu bazovyy ISO: $($b.url)"
    Write-Host "Skachivayu: $($b.url)" -ForegroundColor Cyan
    # kachaem cherez WebClient s sobytiynym progressom => GUI vidit realnye % skachivaniya
    $wc = New-Object System.Net.WebClient
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $dlArgs = {
        param($s, $e)
        if ($e.ProgressPercentage -ge 0) {
            $overall = 10 + ($e.ProgressPercentage * 0.30)   # skachivanie = koridor 10..40%
            $mbps = if ($sw.Elapsed.TotalSeconds -gt 1) { [math]::Round($e.BytesReceived/1MB/$sw.Elapsed.TotalSeconds,1) } else { 0 }
            [Console]::Out.WriteLine(("PROGRESS|{0}|Download ISO... {1} MB/s" -f [math]::Round($overall), $mbps))
            [Console]::Out.Flush()
        }
    }
    Register-ObjectEvent $wc DownloadProgressChanged -SourceIdentifier dlprog -Action $dlArgs | Out-Null
    $wc.DownloadFile($b.url, "$origIso.part")
    Unregister-Event -SourceIdentifier dlprog -EA SilentlyContinue
    $wc.Dispose()
    if ($b.sha256) {
        Report 42 "Proveryayu kontrolnuyu summu sha256..."
        $actual = (Get-FileHash "$origIso.part" -Algorithm SHA256).Hash.ToLower()
        if ($actual -ne $b.sha256) { Remove-Item "$origIso.part"; throw "sha256 ne sovpal: zhdali $($b.sha256), poluchili $actual" }
        Write-Host "sha256 -" -ForegroundColor Green
    }
    Move-Item "$origIso.part" $origIso -Force
}
if (-not (Test-Path $origIso)) { throw "Bazovyy ISO ne nayden: $origIso" }

# ---------- 3. Raspakovka ISO sredstvami Windows ----------
$src = Join-Path $WorkDir 'extracted'
if (-not (Test-Path $src)) {
    Report 46 "Raspakovyvayu soderzhimoe ISO na disk sborki..."
    Write-Host "Montiruyu ISO -> robocopy..." -ForegroundColor Cyan
    $img = Mount-DiskImage -ImagePath $origIso -PassThru
    $drv = ($img | Get-Volume).DriveLetter
    robocopy "${drv}:\" $src /E /NFL /NDL /NJH /NJS | Out-Null
    Dismount-DiskImage -ImagePath $origIso | Out-Null
}

# ---------- 4. Firmennyy sloy Govecho poverh dereva ISO ----------
Report 58 "Naslaivayu firmennyy sloy Govecho (komponenty, menyu zagruzchika)..."
Write-Host "Naslaivayu firmennye komponenty Govecho..." -ForegroundColor Cyan
# 4a. katalog /govecho s nashim DEB-paketom i spiskom startovyh prilozheniy
$gv = Join-Path $src 'govecho'
New-Item -ItemType Directory -Force -Path $gv | Out-Null
Copy-Item (Join-Path $PSScriptRoot '..\Release\govechoos-gnome_2.1.0_amd64.deb') $gv -Force -EA SilentlyContinue
@"
# Ryad startovyh programm GovechoOS (stavyatsya pri avtoustanovke)
gnome-shell gdm3 firefox htop vim gnome-calculator nautilus gnome-terminal
"@ | Set-Content (Join-Path $gv 'startapps.list') -Encoding ASCII

# 4b. preseed: TOLKO pri -AutoInstall. Po umolchaniyu obraz interaktivnyy -
#     ustanovschik sam zadaet vse voprosy, polzovatel kontroliruet kazhdyy shag.
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

# 4c. Punkty menyu zagruzchikov (BIOS-isolinux i EFI-grub), esli oni est v baze.
#     Osnovnoy punkt - INTERAKTIVNYY (bez automatic-ubiquity/quiet splash):
#     vidno kazhdyy shag ustanovki, mozhno nastroit yazyk, razdely, polzovateley.
$bootAppend = 'boot=casper ---'                                   # interaktiv
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

# ---------- 5. Peresborka hybrid-ISO (xorriso v WSL) ----------
Report 72 "Peresobirayu gibridnyy ISO (BIOS + UEFI)... eto samyy dolgiy shag"
Write-Host "Peresobirayu gibridnyy ISO (BIOS + UEFI)..." -ForegroundColor Cyan
function ToWslPath([string]$p) { ($p -replace '^([A-Za-z]):', '/mnt/$1').ToLower().Replace('\','/') }
$wSrc = ToWslPath $src; $wOut = ToWslPath $outIso
# berem zagruzochnye artefakty togo, chto dala baza (ubuntu: casper+EFI; debian: install.amd+EFI)
$bootArgs = '-isohybrid-mbr isohdpfx.bin -b isolinux/isolinux.bin -c isolinux/boot.cat -no-emul-boot -boot-load-size 4 -boot-info-table -eltorito-alt-boot -e boot/grub/efi.img -no-emul-boot -isohybrid-gpt-basdat'
if ($Base -eq 'debian') { $bootArgs = '-isohybrid-mbr isohdpfx.bin -b isolinux/isolinux.bin -c isolinux/boot.cat -no-emul-boot -boot-load-size 4 -boot-info-table -eltorito-alt-boot -e images/efi/boot.img -no-emul-boot -isohybrid-gpt-basdat' }
# isolinux hybrid MBR template kladem v koren dereva
Copy-Item (Join-Path $src 'isolinux\isohdpfx.bin') (Join-Path $src 'isohdpfx.bin') -Force -EA SilentlyContinue
wsl -u root -- bash -c "set -e; cd '$wSrc'; xorriso -as mkisofs -r -J -joliet-long -cache-inodes -V 'GOVECHOOS_$($Base.ToUpper())' $bootArgs -o '$wOut' ."
if (-not (Test-Path $outIso)) { throw "Ne udalos sobrat ISO" }
$szMB = [math]::Round((Get-Item $outIso).Length/1MB,1)
Report 95 "Proveryayu gotovyy obraz..."
if (-not (Get-Item $outIso).Length) { throw "ISO pustoy-" }
Report 100 "DONE: govechoos-$VER-live-$Base.iso ($szMB MB)"
Write-Host "- DONE: $outIso ($szMB MB)" -ForegroundColor Green

# ---------- 6. DONE ----------
# VNIMATELNOE RESHENIE: skript NE pishet ISO ni na kakie diski/fleshki.
# Zapis obraza - opasnaya operatsiya (stiraet disk), a krome togo mnogim nuzhno
# samomu vybirat sposob zagruzki i sledit za ustanovkoy. Poetomu builder
# ostanavlivaetsya na fayle ISO v WorkDir.
Write-Host @"

- Sborka zavershena. Fayl obraza: $outIso ($szMB MB)

CHto dalshe (zapis obraza vy delaete sami, kak vam udobnee):
  - Test bez zapisi: VirtualBox/VMware -> novaya VM -> nositel = etot ISO;
  - Fleshka: Rufus / Ventoy / balenaEtcher (vyberite fayl obraza vruchnuyu);
  - Pri zagruzke s fleshki otkroetsya menyu GovechoOS - ustanovka INTERAKTIVNAYA:
    ustanovschik zadaet vse voprosy (yazyk, razdely, polzovatel), vy vse
    vidite i nastraivaete. Rezhim -bez voprosov- vklyuchaetsya peresborkoy
    s flagom -AutoInstall (v menyu poyavitsya otdelnyy punkt).
"@ -ForegroundColor Green
