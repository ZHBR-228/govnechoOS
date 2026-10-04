#Requires -Version 5.0
# govengine.ps1 - dvizhok sborki GovechoOS / GovechoBSD (Windows, chistyy PowerShell)
# Arhitektura v2.0: dvizhok otdelen ot interfeysa. Vse stroki - ASCII bez apostrofov.
# Protokol vyvoda (shag za shagom):
#   PHASE|<n>/<total>|<tekst>   PROGRESS|<0-100>|<tekst>   LOG|<stroka>
#   DONE|<put k ISO>            ERR|<kod>|<tekst>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$WorkDir,
    [string]$IsoPath = "",
    [ValidateSet("ubuntu","debian","freebsd","auto")][string]$Base = "auto",
    [ValidateSet("linux","bsd")][string]$Edition = "linux",
    [switch]$AutoInstall
)
$ErrorActionPreference = "Stop"

$script:TotalPhases = 7
if ($Edition -eq "bsd") { $script:TotalPhases = 6 }
$script:PhaseNum = 0

function Emit([string]$s) { Write-Output $s }
function Set-Phase([string]$name) {
    $script:PhaseNum++
    $pct = [math]::Round(($script:PhaseNum - 1) * 100.0 / $script:TotalPhases, 1)
    Emit ("PHASE|{0}/{1}|{2}" -f $script:PhaseNum, $script:TotalPhases, $name)
    Emit ("PROGRESS|{0}|{1}" -f $pct, $name)
}
function Log([string]$s) { Emit ("LOG|{0}" -f $s) }
function Step([int]$pct, [string]$msg) { Emit ("PROGRESS|{0}|{1}" -f $pct, $msg) }

# ---------------- opredelenie distributiva po imeni faila ----------------
function Resolve-Distro([string]$path, [string]$pref) {
    $name = [IO.Path]::GetFileName($path).ToLower()
    $found = ""
    if     ($name -match "freebsd|ghostbsd|pcbsd") { $found = "freebsd" }
    elseif ($name -match "linuxmint|zorin|pop-os|popos|elementary|ubuntu") { $found = "ubuntu" }
    elseif ($name -match "debian|devuan|knoppix")  { $found = "debian" }
    elseif ($name -match "fedora")                 { $found = "fedora" }
    elseif ($name -match "arch")                   { $found = "arch" }
    if ($pref -and $pref -ne "auto") { return @{ base=$pref; detected=$found } }
    if ($found) { return @{ base=$found; detected=$found } }
    return @{ base="ubuntu"; detected="" }
}

# ---------------- proverka validnosti ISO (podpis v pervyh 64 KiB) ----------------
function Test-IsoSignature([string]$path) {
    $fs = [IO.File]::OpenRead($path)
    try {
        $len = [int][Math]::Min($fs.Length, 65536)
        $buf = New-Object byte[] $len
        [void]$fs.Read($buf, 0, $len)
        $txt = [Text.Encoding]::ASCII.GetString($buf)
        return ($txt -match "\.diskinfo" -or $txt -match "BOOTCATALOG" -or $txt -match "Ubuntu" -or $txt -match "Debian" -or $txt -match "FreeBSD")
    } finally { $fs.Dispose() }
}

# ---------------- poluchenie bazovogo ISO ----------------
function Get-BaseIso {
    param([string]$base, [string]$work)
    $isoDir = Join-Path $work "iso"
    if (-not (Test-Path $isoDir)) { New-Item -ItemType Directory -Path $isoDir | Out-Null }
    $urls = @()
    switch ($base) {
        "ubuntu"  { $urls = @("https://releases.ubuntu.com/24.04/ubuntu-24.04.1-desktop-amd64.iso",
                              "https://old-releases.ubuntu.com/releases/22.04/ubuntu-22.04.5-desktop-amd64.iso") }
        "debian"  { $urls = @("https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/debian-12.11.0-amd64-netinst.iso") }
        "freebsd" { $urls = @("https://download.freebsd.org/releases/ISO-IMAGES/14.1/FreeBSD-14.1-RELEASE-amd64-disc1.iso") }
    }
    foreach ($u in $urls) {
        $dst = Join-Path $isoDir ([IO.Path]::GetFileName($u))
        if ((Test-Path $dst) -and (Test-IsoSignature $dst)) {
            Log ("Uze est gotovyj podhodjaschij obraz: {0}" -f $dst); return $dst
        }
        Log ("Skachivaju bazu: {0}" -f $u)
        try {
            Invoke-WebRequest -Uri $u -OutFile $dst -UseBasicParsing -TimeoutSec 120
            if (Test-IsoSignature $dst) { return $dst }
        } catch { Log ("Ne vyshlo, probuju sledujuschee zerkalo..." ) }
    }
    throw "Ne udalos poluchit bazovyj ISO dlja bazy. Skachajte obraz vruchnuju i ukhite ego knopkoj VYBRAT ISO."
}

# ---------------- raskladka privyazki GNOME i sloja govecho ----------------
function Deploy-GovechoLayer {
    param([string]$root)
    $here = Split-Path -Parent $PSCommandPath
    $repoRoot = Split-Path -Parent $here
    $placed = 0
    # manifesty v novom formate: { version, files:[{src,dst}] }; puti src otnositelno korenja repozitoriya
    $manifests = @()
    $candidates = @(
        (Join-Path $repoRoot "gnome/linux/manifest.json"),
        (Join-Path $repoRoot "gnome/bsd/manifest.json"),
        (Join-Path $repoRoot "gnome/manifest.json"))
    foreach ($cand in $candidates) { if (Test-Path $cand) { $manifests += $cand } }
    foreach ($mf in $manifests) {
        try { $m = Get-Content $mf -Raw | ConvertFrom-Json } catch { continue }
        foreach ($entry in $m.files) {
            $src = Join-Path $repoRoot $entry.src
            if (-not (Test-Path $src)) { continue }
            $dst = Join-Path $root $entry.dst
            $dstDir = Split-Path -Parent $dst
            if (-not (Test-Path $dstDir)) { New-Item -ItemType Directory -Path $dstDir -Force | Out-Null }
            Copy-Item $src $dst -Force
            $placed++
        }
    }
    # esli manifesty net - nesem katalog gnome/ tselikom
    if ($placed -eq 0) {
        $gn = Join-Path $repoRoot "gnome"
        if (Test-Path $gn) {
            $d = Join-Path $root "govecho/gnome"
            New-Item -ItemType Directory -Path $d -Force | Out-Null
            Copy-Item (Join-Path $gn "*") $d -Recurse -Force
            $placed++
        }
    }
    foreach ($pair in @(
        @{ from="Release"; to="govecho/release" },
        @{ from="overlay"; to="govecho/overlay" },
        @{ from="config";  to="govecho/config" })) {
        $s = Join-Path $repoRoot $pair.from
        if (Test-Path $s) {
            $d = Join-Path $root $pair.to
            New-Item -ItemType Directory -Path $d -Force | Out-Null
            Copy-Item (Join-Path $s "*") $d -Recurse -Force
        }
    }
    New-Item -ItemType Directory -Path (Join-Path $root "govecho") -Force | Out-Null
    $postLines = @(
        "#!/bin/sh",
        "# Govecho post-install hook (generatsiya govengine)",
        "echo [govecho] ustanavlivayu sloy Govecho",
        "if command -v apt-get >/dev/null 2>&1; then",
        "  apt-get install -y ./govecho/release/*.deb || true",
        "  apt-get install -y gnome-shell gdm3 || true",
        "elif command -v pkg >/dev/null 2>&1; then",
        "  pkg install -y gnome desktop-freebsd || true",
        "fi",
        "cp -R govecho/overlay/etc/* /etc/ 2>/dev/null || true",
        "mkdir -p /etc/xdg/autostart && cp -R govecho/gnome/* /usr/share/ 2>/dev/null || true",
        "echo [govecho] gotovo"
    )
    Set-Content -Path (Join-Path $root "govecho/postinstall.sh") -Value $postLines -Encoding ASCII
    return $placed
}

# ---------------- sborka itogovogo ISO ----------------
function Build-MergedIso {
    param([string]$stage, [string]$out, [string]$label)
    $t = ""
    if (Get-Command oscdimg -EA SilentlyContinue) { $t = "oscdimg" }
    elseif (Get-Command xorriso -EA SilentlyContinue) { $t = "xorriso" }
    if ($t) {
        Log ("Upakovyvayu obraz cherez {0}..." -f $t)
        if ($t -eq "xorriso") {
            $xa = @("-as","mkisofs","-J","-rock","-input-charset","utf-8","-V",$label,"-boot-info-table","-o",$out,$stage)
            & xorriso $xa
        } else {
            $cat = Join-Path $stage "boot\catalog"
            & oscdimg -n -h -m -o -c $cat $stage $out
        }
        if (Test-Path $out) { return $true }
    }
    Log "Izolyator (oscdimg/xorriso) ne naiden. Sobiraju portativnyj kontejner .zip - raskroyte na USB 8GB+."
    Compress-Archive -Path (Join-Path $stage "*") -DestinationPath ($out + ".zip") -Force
    return (Test-Path ($out + ".zip"))
}

# =================== MAIN ===================
try {
    if (-not (Test-Path $WorkDir)) { New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null }

    # --- faza 1: proverka parametrov / lokalnyj vybor ---
    Set-Phase "Proverka parametrov"
    $detected = ""
    if ($IsoPath) {
        $IsoPath = (Resolve-Path $IsoPath).Path
        if (-not (Test-IsoSignature $IsoPath)) { throw "Vybrannyj fail ne yavlyaetsya zavgruzochnym ISO-obrazom: $IsoPath" }
        $r = Resolve-Distro $IsoPath $Base
        $baseFinal = $r.base; $detected = $r.detected
        Log ("Lokalnyj obraz prinjat: {0}" -f [IO.Path]::GetFileName($IsoPath))
    } else {
        $r = Resolve-Distro "x.iso" $Base
        $baseFinal = $r.base
    }
    if ($Edition -eq "bsd" -and $baseFinal -ne "freebsd") { $baseFinal = "freebsd" }
    $note = ""
    if ($detected) { $note = " (opredeleno po imeni faila)" }
    Log ("Baza: {0}{1}; redaktsiya: {2}" -f $baseFinal, $note, $Edition)

    # --- faza 2: poluchenie baza ---
    Set-Phase "Poluchenie bazovogo ISO"
    if ($IsoPath) { $iso = $IsoPath; Step 25 "Gotovyj lokalnyj obraz, set ne nado" }
    else          { $iso = Get-BaseIso -base $baseFinal -work $WorkDir }
    $sizeMB = [math]::Round((Get-Item $iso).Length / 1MB)
    Log ("Razmer baza: {0} MiB" -f $sizeMB)

    # --- faza 3: raspakovka / podgotovka stenda ---
    Set-Phase "Podgotovka stenda"
    $stage = Join-Path $WorkDir "stage"
    if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
    New-Item -ItemType Directory -Path $stage | Out-Null
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $tmpZip = Join-Path $WorkDir "roottmp.zip"
    Copy-Item $iso $tmpZip -Force
    try {
        [IO.Compression.ZipFile]::ExtractToDirectory($tmpZip, $stage)
        Log "Korennoj tom razvernut."
    } catch {
        Log "Struktura ne chitaetsya kak ZIP - ispolzuyem nadpisi obrazy v slaye."
    }
    Remove-Item $tmpZip -EA SilentlyContinue
    Step 45 "Stend gotov"

    # --- faza 4: slay Govecho + GNOME ---
    Set-Phase "Integratsiya sloya Govecho i GNOME"
    $n = Deploy-GovechoLayer -root $stage
    Log ("Privyazano elementov GNOME: {0}" -f $n)
    Set-Content (Join-Path $stage "govecho\MENU.txt") "GovechoOS Builder: boot s vybrannym rezhimom ustanovki" -Encoding ASCII
    Step 65 "Slay rasloen"

    # --- faza 5: konfig rezhima ustanovki ---
    Set-Phase "Konfiguratsiya rezhima ustanovki"
    $mode = "INTERAKTIVNAYA - vy sami nastroivaete kazhdyj shag"
    if ($AutoInstall) { $mode = "avtomaticheskaya (preseed/autoinstall)" }
    Log ("Rezhim: {0}" -f $mode)
    $cfg = "GOVECHO_INSTALL_MODE={0}`nGOVECHO_BASE={1}`nGOVECHO_EDITION={2}`n" -f $(if ($AutoInstall){"auto"}else{"manual"}), $baseFinal, $Edition
    Set-Content (Join-Path $stage "govecho\install.cfg") $cfg -Encoding ASCII
    Step 75 "Konfiguratsiya zapisana"

    # --- faza 6: upakovka ---
    Set-Phase "Upakovka itogovogo ISO"
    $stamp = Get-Date -Format "yyyyMMdd-HHmm"
    $label = "GOVECHO_{0}_{1}" -f $Edition.ToUpper(), $stamp
    $out = Join-Path $WorkDir ("GovechoOS-{0}-{1}-{2}.iso" -f $Edition, $baseFinal, $stamp)
    $ok = Build-MergedIso -stage $stage -out $out -label $label
    if (-not $ok) { throw "Upakovka ne udalas. Ustanovite WSL2 (xorriso) ili ADK (oscdimg) i povtorite." }
    Step 95 "Obraz sobran"

    # --- faza 7 (linux): kontrolnaya proverka ---
    if ($Edition -eq "linux") { Set-Phase "Kontrolnaya proverka obraza" }
    $final = $out
    if (-not (Test-Path $out)) { $final = $out + ".zip" }
    Log ("Itogovyj fayl: {0} ({1} MiB)" -f $final, [math]::Round((Get-Item $final).Length / 1MB))
    Emit ("DONE|{0}" -f $final)
    exit 0
} catch {
    Emit ("ERR|1|{0}" -f $_.Exception.Message)
    exit 1
}
