#Requires -Version 5.0
<#
.SYNOPSIS
    GovechoOS - sborka modifitsirovannogo ISO (Ubuntu/Debian) na Windows 10/11.
.DESCRIPTION
    Dva rezhima istochnika:
      1) URL iz govechoos.build.json (ofitsialnyy ISO + proverka sha256);
      2) -IsoPath - UZHE SKHANNYY POL''ZOVATELEM ISO. Distro opredelyaetsya
         po imeni fayla (ubuntu*/debian*), lichi URL-baza ne ukazan yavno.
    Dalee odin i tot zhe konveyer: raspakovka -> naslayvanie Govecho-sloya ->
    gibridnyy BIOS+UEFI ISO cherez xorriso (WSL).
    Po umolchaniyu ustanovka INTERAKTIVNAYA (pol''zovatel kontroliruet kazhdyy
    shag); rezhim bez voprosov - flag -AutoInstall.
    Skript NIKOGDA ne zapisyvaet ISO na fleshku avtomaticheski.
.NOTES
    Avtor: ZHBR-228 | Litsenziya: MIT | github.com/ZHBR-228/govnechoOS
#>
[CmdletBinding()]
param(
    [ValidateSet('','ubuntu','debian')][string]$Base = '',
    [string]$IsoPath = '',          # uzhe skhannyy ISO (novoe!)
    [string]$WorkDir = "$env:USERPROFILE\govecho_build",
    [switch]$SkipDownload,
    [switch]$AutoInstall,
    [switch]$GuiProtocol
)
$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'
$VER = '2.2.0'

function Report([double]$pct, [string]$phase) {
    if ($GuiProtocol) {
        [Console]::Out.WriteLine(("PROGRESS|{0}|{1}" -f [math]::Round($pct), $phase))
        [Console]::Out.Flush()
    } else {
        Write-Progress -Activity 'GovechoOS Builder' -Status $phase -PercentComplete ([math]::Round($pct))
        Write-Host ("[{0}%] {1}" -f [math]::Round($pct), $phase) -ForegroundColor Cyan
    }
}

# ---------- 0. Konfiguratsiya ----------
$cfgPath = Join-Path $PSScriptRoot '..\govechoos.build.json'
$b = $null
if (Test-Path $cfgPath) {
    $cfg = Get-Content $cfgPath -Raw | ConvertFrom-Json
    if (-not $Base) { $Base = $cfg.defaultBase }
    $b = $cfg.bases.$Base
}
New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null

# ---------- 0b. Istochnik ISO: lokalnyy fayl ili URL ----------
$origIso = ''
if ($IsoPath) {
    if (-not (Test-Path $IsoPath)) { throw "Ukazannyj ISO ne nayden: $IsoPath" }
    $origIso = (Resolve-Path $IsoPath).Path
    $nm = [IO.Path]::GetFileName($origIso).ToLower()
    # AVTOOPREDELENIE distribyuta po imeni fayla:
    $detected = ''
    if ($nm -match 'ubuntu')                          { $detected = 'ubuntu' }
    elseif ($nm -match 'debian')                      { $detected = 'debian' }
    elseif ($nm -match 'linuxmint|mint-')             { $detected = 'ubuntu' }  # Mint = baza Ubuntu
    elseif ($nm -match 'pop-os|pop_os|zorin|elementary') { $detected = 'ubuntu' }
    elseif ($nm -match 'linux')                       { $detected = 'debian' }
    if ($Base -and $detected -and ($Base -ne $detected)) {
        Write-Host "! Imya ISO goworit pro '$detected', perekluchayu bazu" -ForegroundColor Yellow
    }
    if ($detected) { $Base = $detected }
    if (-not $Base -or -not $b) { $Base = 'ubuntu' }
    Report 5 ("Istochnik: lokalnyy ISO [" + $Base + "]: " + $origIso)
    Write-Host "== GovechoOS Windows Builder v$VER (baza: $Base, lokalnyy ISO) ==" -ForegroundColor Cyan
} else {
    if (-not $b) { throw "Net ni lokalnogo ISO, ni opisanija bazy v govechoos.build.json" }
    $origIso = Join-Path $WorkDir $b.file
    Report 5 "Konfiguratsiya zagruzhena (baza: $Base)"
    Write-Host "== GovechoOS Windows Builder v$VER ($Base) ==" -ForegroundColor Cyan
}
$outIso = Join-Path $WorkDir "govechoos-$VER-live-$Base.iso"

# ---------- 1. WSL instrumenty upakovki ----------
$wslOk = $false
try { wsl -l -q | Out-Null; $wslOk = $true } catch {}
if (-not $wslOk) {
    Write-Host @"
WSL ne ustanovlen. Vypolnite ODNOKRATNO v admin-PowerShell:
    wsl --install -d Ubuntu
perezagruzite PK i zapustite etot skript snova.
"@ -ForegroundColor Yellow
    Read-Host "Nazhmite Enter posle ustanovki WSL (ili Ctrl+C dlya vyhoda)"
}
Report 8 "Podgotovka instrumentov sborki (xorriso/squashfs v WSL)..."
wsl -u root -- bash -c "command -v xorriso >/dev/null || (apt-get update -qq && apt-get install -y -qq xorriso squashfs-tools isolinux syslinux-common)"

# ---------- 2. Zagruzka ISO (tolko esli net lokalnogo) ----------
if (-not $IsoPath -and -not $SkipDownload -and -not (Test-Path $origIso)) {
    Report 10 "Skachivayu bazovyy ISO: $($b.url)"
    $wc = New-Object System.Net.WebClient
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $dlArgs = {
        param($s, $e)
        if ($e.ProgressPercentage -ge 0) {
            $overall = 10 + ($e.ProgressPercentage * 0.30)
            $mbps = if ($sw.Elapsed.TotalSeconds -gt 1) { [math]::Round($e.BytesReceived/1MB/$sw.Elapsed.TotalSeconds,1) } else { 0 }
            [Console]::Out.WriteLine(("PROGRESS|{0}|Download ISO... {1} MB/s" -f [math]::Round($overall), $mbps))
            [Console]::Out.Flush()
        }
    }
    Register-ObjectEvent $wc DownloadProgressChanged -SourceIdentifier dlprog -Action $dlArgs | Out-Null
    $wc.DownloadFile($b.url, "$origIso.part")
    Unregister-Event -SourceIdentifier dlprog -EA SilentlyContinue
    $wc.Dispose()
    Move-Item "$origIso.part" $origIso -Force
}
if ($b -and $b.sha256 -and (Test-Path $origIso)) {
    Report 42 "Proveryayu kontrolnuyu summu sha256..."
    $actual = (Get-FileHash $origIso -Algorithm SHA256).Hash.ToLower()
    if ($actual -ne $b.sha256.ToLower()) { throw "sha256 ne sovpal: zhdali $($b.sha256), poluchili $actual" }
    Write-Host "sha256 OK" -ForegroundColor Green
}
if (-not (Test-Path $origIso)) { throw "Bazovyy ISO ne nayden: $origIso" }

# ---------- 3. Raspakovka ISO sredstvami Windows ----------
$safeName = ($origIso -replace '[^\w\.]', '_')
$src = Join-Path $WorkDir ("extracted_" + [IO.Path]::GetFileNameWithoutExtension($safeName))
if (-not (Test-Path $src)) {
    Report 46 "Raspakovyvayu soderzhimoe ISO na disk sborki..."
    $img = Mount-DiskImage -ImagePath $origIso -PassThru
    $drv = ($img | Get-Volume).DriveLetter
    robocopy "${drv}:\" $src /E /NFL /NDL /NJH /NJS | Out-Null
    Dismount-DiskImage -ImagePath $origIso | Out-Null
}

# ---------- 4. Firmennyy sloy Govecho ----------
Report 58 "Naslaivayu firmennyy sloy Govecho (GNOME-fayly, komponenty, menyu)..."
$gv = Join-Path $src 'govecho'
New-Item -ItemType Directory -Force -Path $gv | Out-Null
$deb = Get-ChildItem (Join-Path $PSScriptRoot '..\Release') -Filter '*.deb' -EA SilentlyContinue | Select-Object -First 1
if ($deb) { Copy-Item $deb.FullName $gv -Force }

# --- GNOME-privyazki: raskladyvaem faily iz gnome/linux po katalogam ISO ---
# manifest.json: spiskovye pary src->dst; pri otsutstvii manifesta - prostoje kopirovanie
$gdir = Join-Path $PSScriptRoot '..\gnome\linux'
$mpath = Join-Path $gdir 'manifest.json'
if (Test-Path $mpath) {
    $man = Get-Content $mpath -Raw | ConvertFrom-Json
    foreach ($e in $man.files) {
        $sF = Join-Path $PSScriptRoot ('..' + '\' + ($e.src -replace '/','\'))
        if (Test-Path $sF) {
            $dD = Join-Path $src ($e.dst -replace '/','\')
            New-Item -ItemType Directory -Force -Path (Split-Path $dD) | Out-Null
            Copy-Item $sF $dD -Force
        }
    }
    Report 60 ("GNOME: razlozheno faizlov: " + @($man.files).Count)
} elseif (Test-Path $gdir) {
    Get-ChildItem $gdir -File | Where-Object Name -ne 'manifest.json' | ForEach-Object {
        Copy-Item $_.FullName (Join-Path $gv $_.Name) -Force }
}

@"
# Ryad startovyh programm GovechoOS
gnome-shell gdm3 firefox htop vim gnome-calculator nautilus gnome-terminal
"@ | Set-Content (Join-Path $gv 'startapps.list') -Encoding ASCII

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

$bootAppend = 'boot=casper ---'
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
Report 72 "Peresobirayu gibridnyy ISO (BIOS + UEFI)... samyy dolgiy shag"
function ToWslPath([string]$p) { ($p -replace '^([A-Za-z]):', '/mnt/$1').ToLower().Replace('\','/') }
$wSrc = ToWslPath $src; $wOut = ToWslPath $outIso
$bootArgs = '-isohybrid-mbr isohdpfx.bin -b isolinux/isolinux.bin -c isolinux/boot.cat -no-emul-boot -boot-load-size 4 -boot-info-table -eltorito-alt-boot -e boot/grub/efi.img -no-emul-boot -isohybrid-gpt-basdat'
if ($Base -eq 'debian') { $bootArgs = '-isohybrid-mbr isohdpfx.bin -b isolinux/isolinux.bin -c isolinux/boot.cat -no-emul-boot -boot-load-size 4 -boot-info-table -eltorito-alt-boot -e images/efi/boot.img -no-emul-boot -isohybrid-gpt-basdat' }
Copy-Item (Join-Path $src 'isolinux\isohdpfx.bin') (Join-Path $src 'isohdpfx.bin') -Force -EA SilentlyContinue
wsl -u root -- bash -c "set -e; cd '$wSrc'; xorriso -as mkisofs -r -J -joliet-long -cache-inodes -V 'GOVECHOOS_$($Base.ToUpper())' $bootArgs -o '$wOut' ."
if (-not (Test-Path $outIso)) { throw "Ne udalos sobrat ISO" }
$szMB = [math]::Round((Get-Item $outIso).Length/1MB,1)
Report 95 "Proveryayu gotovyy obraz..."
if (-not (Get-Item $outIso).Length) { throw "ISO pustoy" }
Report 100 "DONE: govechoos-$VER-live-$Base.iso ($szMB MB)"
Write-Host "- DONE: $outIso ($szMB MB)" -ForegroundColor Green
Write-Host @"

- Sborka zavershena. Fayl obraza: $outIso ($szMB MB)
  Zapis na fleshku - tolko vruchnuyu (Rufus/Ventoy/balenaEtcher) ili test v VirtualBox.
  Ustanovka v obraze INTERAKTIVNAYA: vy kontroliruete kazhdyy shag.
"@ -ForegroundColor Green
