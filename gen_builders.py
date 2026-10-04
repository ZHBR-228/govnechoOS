#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Govecho builder generator (ZHBR-228, MIT).
Produces encoding-proof ASCII-only PowerShell scripts for BOTH repos:
  - govnechoOS : scripts/build_gui.ps1 + scripts/build_windows.ps1 (+ bat launcher)
  - GovechoBSD : scripts/build_gui_bsd.ps1 + scripts/build_bsd_windows.ps1 (+ bat launcher)

Root cause fixed here: previous GUI windows died with XAML parse errors because
here-strings / quotes got mangled on transfer. This generator writes every file
with pure-ASCII bytes + UTF-8 BOM + CRLF, and builds the WPF UI from a plain
XML string parsed via XmlDocument.LoadXml + XamlReader.Load (no here-strings at
all in .ps1 output).

New feature per user request: "Use already-downloaded ISO" picker; distro is
auto-detected from the ISO filename (ubuntu/debian/freebsd/unknown).
"""
import os, re, sys

WS = "/workspace"

def ascii_only(s: str) -> str:
    bad = [c for c in s if ord(c) > 126]
    assert not bad, f"non-ascii chars: {bad}"
    return s

def write_ps1(path: str, body: str):
    """UTF-8 BOM + pure ASCII + CRLF."""
    data = "\ufeff" + ascii_only(body.replace("\r\n", "\n"))
    raw = data.encode("utf-8")
    assert all(b < 128 for b in raw[3:]), "non-ascii byte leaked"
    with open(path, "wb") as f:
        f.write(raw.replace(b"\n", b"\r\n"))

def write_bat(path: str, body: str):
    raw = ascii_only(body.replace("\r\n", "\n")).encode("ascii")
    with open(path, "wb") as f:
        f.write(raw.replace(b"\n", b"\r\n"))

# ============================================================================
# Shared PS fragments
# ============================================================================

XAML_LINUX = '''$xamlText = '<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"' + [char]32 + 'xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"' + [char]34
'''

def xaml_ps(title: str, extra_row: bool) -> str:
    """Build the PowerShell statement that produces $xamlText safely.
    We embed the XAML as single-quoted PS strings line by line (no here-strings).
    The x namespace prefix MUST be declared (that was the exact user error:
    'prefix x is undeclared')."""
    lines = [
        '<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"',
        '        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"',
        f'        Title="{title}" Height="580" Width="780" WindowStartupLocation="CenterScreen">',
        '  <Grid Margin="14">',
        '    <Grid.RowDefinitions>',
        '      <RowDefinition Height="Auto"/>',
        '      <RowDefinition Height="Auto"/>',
        '      <RowDefinition Height="Auto"/>',
        '      <RowDefinition Height="Auto"/>',
        '      <RowDefinition Height="Auto"/>',
        '      <RowDefinition Height="*"/>',
        '      <RowDefinition Height="Auto"/>',
        '    </Grid.RowDefinitions>',
        '    <StackPanel Grid.Row="0">',
        f'      <TextBlock Text="{title}" FontSize="24" FontWeight="Bold"/>',
        '      <TextBlock x:Name="TxtSub" Foreground="Gray" Margin="0,2,0,10"/>',
        '    </StackPanel>',
        '    <StackPanel Grid.Row="1" Orientation="Horizontal" Margin="0,0,0,8">',
        '      <TextBlock x:Name="LblBase" VerticalAlignment="Center" Margin="0,0,6,0"/>',
        '      <ComboBox x:Name="CmbBase" Width="110" SelectedIndex="0">',
        '        <ComboBoxItem Content="ubuntu"/>',
        '        <ComboBoxItem Content="debian"/>',
        '      </ComboBox>',
        '      <Button x:Name="BtnPick" Margin="14,0,0,0" Padding="10,4"/>',
        '      <CheckBox x:Name="ChkAuto" Margin="16,0,0,0" VerticalAlignment="Center"/>',
        '    </StackPanel>',
        '    <TextBlock x:Name="TxtIso" Grid.Row="2" Foreground="DimGray" Margin="0,0,0,8" TextTrimming="CharacterEllipsis"/>',
        '    <DockPanel Grid.Row="3" Margin="0,0,0,6">',
        '      <TextBlock x:Name="TxtPct" DockPanel.Dock="Right" FontSize="30" FontWeight="Bold" Width="110" TextAlignment="Right"/>',
        '      <ProgressBar x:Name="Bar" Height="26" Minimum="0" Maximum="100" Value="0"/>',
        '    </DockPanel>',
        '    <TextBlock x:Name="TxtPhase" Grid.Row="4" FontSize="14" Margin="0,0,0,8" TextWrapping="Wrap"/>',
        '    <TextBox x:Name="TxtLog" Grid.Row="5" IsReadOnly="True" VerticalScrollBarVisibility="Auto"',
        '             FontFamily="Consolas" FontSize="12" AcceptsReturn="True" TextWrapping="NoWrap"/>',
        '    <StackPanel Grid.Row="6" Orientation="Horizontal" Margin="0,10,0,0">',
        '      <Button x:Name="BtnRun" Width="130" Height="34" FontWeight="Bold"/>',
        '      <Button x:Name="BtnCancel" Width="110" Height="34" Margin="10,0,0,0" IsEnabled="False"/>',
        '      <Button x:Name="BtnOpen" Width="170" Height="34" Margin="10,0,0,0"/>',
        '    </StackPanel>',
        '  </Grid>',
        '</Window>',
    ]
    parts = []
    for i, ln in enumerate(lines):
        esc = ln.replace("'", "''")   # PS single-quote escape
        sep = "`r`n" if i < len(lines) - 1 else ""
        parts.append(f"$xaml += '{esc}{sep}'")
    return "$xaml = ''\n" + "\n".join(parts)


def gui_ps(repo_title: str, sub: str, builder_name: str, iso_kind: str,
           base_combo: bool, freebsd_detect: bool) -> str:
    """Full build_gui*.ps1 content. iso_kind: 'live-installer' or 'disc1'.
    base_combo: show ubuntu/debian selector (Linux repo only)."""
    lbl_base_row = '''      <TextBlock x:Name="LblBase" .../>'''  # placeholder, unused
    xaml_block = xaml_ps(repo_title, base_combo)
    # If BSD: hide combo rows? Simpler: keep same XAML but set LblBase text to
    # "Baza:" hidden via Collapsed for BSD. We instead generate variant XAML:
    if not base_combo:
        xaml_block = xaml_block.replace(
            "$xaml += '      <ComboBox x:Name=\"\"CmbBase\" Width=\"110\" SelectedIndex=\"0\">'", "")
        # cleaner: rebuild without combo lines
        lines = []
    use = xaml_ps(repo_title, base_combo)
    if not base_combo:
        # drop the whole ComboBox element (open tag + 2 items + close tag)
        out_lines = []
        skip_next = 0
        for ln in use.splitlines():
            if "'      <ComboBox x:Name=\"CmbBase\"" in ln:
                skip_next = 3; continue
            if skip_next > 0:
                skip_next -= 1; continue
            out_lines.append(ln)
        use = "\n".join(out_lines)

    run_args = """
    $baseSel = if ($CmbBase) { [string]$CmbBase.SelectedItem.Content } else { '' }
    $bargs = @('-NoProfile','-ExecutionPolicy','Bypass','-File', $Builder, '-GuiProtocol')
    if ($script:IsoPath) {
        $bargs += @('-IsoPath', $script:IsoPath)
        if (-not $baseSel -and $script:DetectedBase) { $baseSel = $script:DetectedBase }
    }
    if ($baseSel) { $bargs += @('-Base', $baseSel) }
    if ($ChkAuto.IsChecked) { $bargs += '-AutoInstall' }
"""

    detect_branch = """
        if ($nm -match 'freebsd') { $det = 'freebsd' }
        elseif ($nm -match 'ubuntu') { $det = 'ubuntu' }
        elseif ($nm -match 'debian') { $det = 'debian' }
""" if freebsd_detect else """
        if ($nm -match 'ubuntu') { $det = 'ubuntu' }
        elseif ($nm -match 'debian') { $det = 'debian' }
"""

    base_setter = """
        if ($CmbBase -and ($det -eq 'ubuntu' -or $det -eq 'debian')) {
            $CmbBase.SelectedIndex = if ($det -eq 'ubuntu') { 0 } else { 1 }
        }
"""

    return f'''#Requires -Version 5.0
# ============================================================
# {repo_title} GUI builder (auto-generated, pure ASCII, encoding-proof).
# Author: ZHBR-228 | License: MIT
# Talks to {builder_name} via PROGRESS|<0-100>|<phase> stdout lines.
# New: "Use local ISO" button - pick an already downloaded image; the
#      distribution is auto-detected from its file name.
# ============================================================
param(
    [string]$Builder = '',
    [switch]$SelfTest
)
$ErrorActionPreference = 'Stop'

$L = @{{
    Title    = '{repo_title}'
    Sub      = '{sub}'
    Base     = 'Baza:'
    Auto     = 'Rezhim AutoInstall (bez voprosov ustanovschika)'
    Run      = 'SOBRAT'
    Cancel   = 'OTMENA'
    Open     = 'OTKRYT PAPKU'
    Pick     = 'VYBRAT ISO...'
    Pct0     = '0%'
    Idle     = 'Gotov k zapusku'
    Starting = 'Zapusk...'
    Running  = 'Idet sborka...'
    Done     = 'SBORKA ZAVERSHENA!'
    Failed   = 'Oshibka sborki'
    Stopped  = 'Ostanovleno pol''zovatelem'
    IsoNone  = 'ISO: net vybara - budem kachat ofitsialnyy obraz'
    IsoSel   = 'ISO: {{0}}  [opredeleno: {{1}}]'
    Unknown  = 'ne izvestno - ukazite bazu v spiske'
    ErrTitle = 'Oshibka {repo_title}'
    ErrHint  = 'Zapustite vruchnuyuju iz PowerShell:'
}}

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms

if ($SelfTest) {{ Write-Host 'SELFTEST-OK'; exit 0 }}

# ---- locate builder script next to this file ----
if (-not $Builder) {{ $Builder = Join-Path $PSScriptRoot '{builder_name}' }}
if (-not (Test-Path $Builder)) {{
    Add-Type -AssemblyName System.Windows.Forms
    [void][System.Windows.Forms.MessageBox]::Show(('Ne nayden fail sborschika: ' + $Builder), $L.ErrTitle, 'OK', 'Error')
    exit 1
}}
$WorkDir = Join-Path $env:USERPROFILE 'govecho_build'

# ---- XAML built line-by-line from single-quoted strings (no here-strings,
#      no way for transfer tools to break quoting; xmlns:x IS declared) ----
{use}

try {{
    $xd = New-Object System.Xml.XmlDocument
    $xd.LoadXml($xaml)
    $win = [System.Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $xd))
}} catch {{
    Add-Type -AssemblyName System.Windows.Forms
    [void][System.Windows.Forms.MessageBox]::Show(('XAML parse: ' + $_.Exception.Message + [Environment]::NewLine + $L.ErrHint + [Environment]::NewLine + 'powershell -NoProfile -ExecutionPolicy Bypass -File "' + $MyInvocation.MyCommand.Path + '"'), $L.ErrTitle, 'OK', 'Error')
    exit 1
}}

$TxtSub    = $win.FindName('TxtSub');     $TxtPhase = $win.FindName('TxtPhase')
$TxtPct    = $win.FindName('TxtPct');     $Bar      = $win.FindName('Bar')
$TxtLog    = $win.FindName('TxtLog');     $BtnRun   = $win.FindName('BtnRun')
$BtnCancel = $win.FindName('BtnCancel');  $BtnOpen  = $win.FindName('BtnOpen')
$BtnPick   = $win.FindName('BtnPick');    $ChkAuto  = $win.FindName('ChkAuto')
$TxtIso    = $win.FindName('TxtIso')
$CmbBase   = $win.FindName('CmbBase');    $LblBase  = $win.FindName('LblBase')

$TxtSub.Text     = $L.Sub
$ChkAuto.Content = $L.Auto
$BtnRun.Content  = $L.Run
$BtnCancel.Content = $L.Cancel
$BtnOpen.Content   = $L.Open
$BtnPick.Content   = $L.Pick
$TxtPct.Text     = $L.Pct0
$TxtIso.Text     = $L.IsoNone
if ($LblBase) {{ $LblBase.Text = $L.Base }}
$TxtPhase.Text   = $L.Idle

$script:IsoPath = ''
$script:DetectedBase = ''

function Set-Progress([double]$pct, [string]$phase) {{
    if ($pct -lt 0) {{ $pct = 0 }}; if ($pct -gt 100) {{ $pct = 100 }}
    $Bar.Value = $pct
    $TxtPct.Text = ([math]::Round($pct)).ToString() + '%'
    if ($phase) {{ $TxtPhase.Text = $phase }}
}}
function Add-Log([string]$s) {{
    if ($null -eq $s -or $s -eq '') {{ return }}
    $TxtLog.AppendText($s + "`r`n")
    $TxtLog.ScrollToEnd()
}}

# ---- local ISO picker + distro detection by file name ----
$BtnPick.Add_Click({{
    $dlg = New-Object Microsoft.Win32.OpenFileDialog
    $dlg.Filter = 'ISO obrazy (*.iso)|*.iso|Vse fayly (*.*)|*.*'
    $dlg.Title = 'Vyberite uzhe skhannyy {iso_kind} ISO'
    if ($dlg.ShowDialog()) {{
        $script:IsoPath = $dlg.FileName
        $nm = [IO.Path]::GetFileName($dlg.FileName).ToLower()
        $det = 'unknown'{detect_branch.rstrip()}
        $script:DetectedBase = if ($det -eq 'unknown') {{ '' }} else {{ $det }}{base_setter.rstrip()}
        $shown = if ($det -eq 'unknown') {{ $L.Unknown }} else {{ $det }}
        $TxtIso.Text = [string]::Format($L.IsoSel, [IO.Path]::GetFileName($dlg.FileName), $shown)
        Add-Log ('ISO vybran: ' + $dlg.FileName + ' => ' + $shown)
    }}
}})

# ---- progress pump: runspace + ConcurrentQueue (no WinRM/jobs needed) ----
$sync = $null
$psInstance = $null
$runspace = $null

$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromMilliseconds(200)
$timer.Add_Tick({{
    if (-not $script:sync) {{ return }}
    while ($true) {{
        $item = $null
        if (-not $script:sync.TryTake([ref]$item)) {{ break }}
        $s = [string]$item
        $pipe = [string][char]124
        if ($s.StartsWith('PROGRESS' + $pipe)) {{
            $parts = $s.Split($pipe)
            $p = 0.0
            if ([double]::TryParse($parts[1], [ref]$p)) {{ Set-Progress $p $parts[2] }}
        }} elseif ($s.StartsWith('ERRTEXT' + $pipe)) {{
            Add-Log ('STDERR: ' + $s.Substring(8))
        }} elseif ($s.StartsWith('EXITCODE' + $pipe)) {{
            $code = [int]($s.Split($pipe)[1])
            if ($code -eq 0) {{ Set-Progress 100 $L.Done; Add-Log ('== ' + $L.Done + ' ==') }}
            else {{ Set-Progress 0 $L.Failed; Add-Log ('== ' + $L.Failed + ' (code ' + $code + ') ==') }}
            $timer.Stop(); $BtnRun.IsEnabled = $true; $BtnCancel.IsEnabled = $false
            if ($script:runspace) {{ $script:runspace.Dispose(); $script:runspace = $null }}
            $script:sync = $null
        }} else {{
            Add-Log $s
        }}
    }}
}})

$BtnRun.Add_Click({{
    if ($script:sync) {{ return }}
    Add-Log ('== ' + $L.Running + ' ==')
    Set-Progress 1 $L.Starting
    $BtnRun.IsEnabled = $false; $BtnCancel.IsEnabled = $true
{run_args.rstrip()}
    $script:sync = [System.Collections.Concurrent.ConcurrentQueue[string]]::new()
    $rs = [RunspaceFactory]::CreateRunspace()
    $rs.ApartmentState = 'STA'
    $rs.ThreadOptions = 'ReuseThread'
    $rs.Open()
    $psInstance = [PowerShell]::Create()
    $psInstance.Runspace = $rs
    $script:psInstance = $psInstance
    [void]$psInstance.AddScript({{
        param($b, $a, $q)
        try {{
            $exe = if (Get-Command pwsh -EA SilentlyContinue) {{ 'pwsh' }} else {{ 'powershell' }}
            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName = $exe
            $psi.Arguments = (($a | ForEach-Object {{ if ($_ -match '\\s') {{ '"' + $_ + '"' }} else {{ $_ }} }}) -join ' ')
            $psi.RedirectStandardOutput = $true
            $psi.RedirectStandardError = $true
            $psi.UseShellExecute = $false
            $psi.WorkingDirectory = Split-Path $b
            $proc = [System.Diagnostics.Process]::Start($psi)
            while ($null -ne ($line = $proc.StandardOutput.ReadLine())) {{ [void]$q.Enqueue($line) }}
            $errt = $proc.StandardError.ReadToEnd()
            $proc.WaitForExit()
            if ($errt) {{ [void]$q.Enqueue(('ERRTEXT' + [char]124 + $errt)) }}
            [void]$q.Enqueue(('EXITCODE' + [char]124 + $proc.ExitCode))
        }} catch {{
            [void]$q.Enqueue(('ERRTEXT' + [char]124 + $_.Exception.Message))
            [void]$q.Enqueue('EXITCODE' + [char]124 + '1')
        }}
    }}).AddArgument($Builder).AddArgument($bargs).AddArgument($script:sync)
    [void]$psInstance.BeginInvoke()
    $script:runspace = $rs
    $timer.Start()
}})

$BtnCancel.Add_Click({{
    if ($script:psInstance) {{ try {{ $script:psInstance.Stop(); $script:psInstance.Dispose() }} catch {{}} }}
    if ($script:runspace) {{ try {{ $script:runspace.Close(); $script:runspace.Dispose() }} catch {{}}; $script:runspace = $null }}
    $script:sync = $null
    $timer.Stop()
    Add-Log ('== ' + $L.Stopped + ' ==')
    $BtnRun.IsEnabled = $true; $BtnCancel.IsEnabled = $false
}})

$BtnOpen.Add_Click({{
    if (-not (Test-Path $WorkDir)) {{ New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null }}
    Start-Process explorer.exe $WorkDir
}})

$win.Add_Closed({{
    if ($script:psInstance) {{ try {{ $script:psInstance.Stop(); $script:psInstance.Dispose() }} catch {{}} }}
    if ($script:runspace) {{ try {{ $script:runspace.Dispose() }} catch {{}} }}
}})

[void]$win.ShowDialog()
'''

# ============================================================================
# Linux builder core (build_windows.ps1) — regenerated clean, adds -IsoPath
# ============================================================================

def linux_builder_ps1() -> str:
    return r'''#Requires -Version 5.0
<#
.SYNOPSIS
    GovechoOS - sborka modifitsirovannogo ISO (Ubuntu/Debian) na Windows 10/11.
.DESCRIPTION
    Dva rezhima istochnika:
      1) URL iz govechoos.build.json (ofitsialnyy ISO + proverka sha256);
      2) -IsoPath <put> - UZHE SKHANNYY POL''ZOVATELEM ISO. Distro opredelyaetsya
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
Report 58 "Naslaivayu firmennyy sloy Govecho (komponenty, menyu zagruzchika)..."
$gv = Join-Path $src 'govecho'
New-Item -ItemType Directory -Force -Path $gv | Out-Null
$deb = Get-ChildItem (Join-Path $PSScriptRoot '..\Release') -Filter '*.deb' -EA SilentlyContinue | Select-Object -First 1
if ($deb) { Copy-Item $deb.FullName $gv -Force }
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
'''

# ============================================================================
# BSD builder core (build_bsd_windows.ps1) — dedup Report, add -IsoPath
# ============================================================================

def bsd_builder_ps1() -> str:
    return r'''#Requires -Version 5.0
<#
.SYNOPSIS
    GovechoBSD - sborka FreeBSD+GNOME ISO na Windows.
.DESCRIPTION
    Iznachalno kachaet FreeBSD disc1 (yadro uzhe est'!). Novoe: -IsoPath -
    uzhe skhannyy pol''zovatelem FreeBSD-ISO; tip opredelyaetsya po imeni
    fayla (FreeBSD*/boothui*/disc1*). Slayvanie: loader.conf/rc.conf/GNOME
    manifest -> newfs/mkhybrid (cherez WSL) -> govechobsd ISO.
    Skript NE zapisyvaet obraz na nositeli.
.NOTES
    Avtor: ZHBR-228 | Litsenziya: MIT | github.com/ZHBR-228/GovechoBSD
#>
[CmdletBinding()]
param(
    [string]$IsoPath = '',
    [string]$WorkDir = "$env:USERPROFILE\govecho_bsd_build",
    [switch]$SkipDownload,
    [switch]$GuiProtocol
)
$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'

function Report([double]$pct, [string]$phase) {
    if ($GuiProtocol) {
        [Console]::Out.WriteLine(("PROGRESS|{0}|{1}" -f [math]::Round($pct), $phase))
        [Console]::Out.Flush()
    } else {
        Write-Progress -Activity 'GovechoBSD Builder' -Status $phase -PercentComplete ([math]::Round($pct))
        Write-Host ("[{0}%] {1}" -f [math]::Round($pct), $phase) -ForegroundColor Cyan
    }
}

$VER = (Get-Content (Join-Path $PSScriptRoot '..\VERSION') -EA SilentlyContinue); if (-not $VER) { $VER='1.0' }
$REL = '14.1-RELEASE'
$IsoUrl  = "https://download.freebsd.org/releases/amd64/amd64/ISO-IMAGES/14.1/FreeBSD-${REL}-disc1-amd64.iso"
$IsoName = "FreeBSD-${REL}-disc1-amd64.iso"
New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null

# ---------- 0. Istochnik: lokalnyy FreeBSD-ISO ili URL ----------
$origIso = ''
if ($IsoPath) {
    if (-not (Test-Path $IsoPath)) { throw "Ukazannyj ISO ne nayden: $IsoPath" }
    $origIso = (Resolve-Path $IsoPath).Path
    $nm = [IO.Path]::GetFileName($origIso).ToLower()
    $ok = ($nm -match 'freebsd') -or ($nm -match 'disc1') -or ($nm -match 'bootonly') -or ($nm -match 'dvd1')
    if (-not $ok) { throw "Fayl ne pakhodit na FreeBSD-ISO (imya: $nm). Ozhidalsya FreeBSD*disc1/dvd1/bootonly." }
    Report 5 ("Istochnik: lokalnyy FreeBSD ISO: " + $origIso)
} else {
    $origIso = Join-Path $WorkDir $IsoName
    Report 5 "Konfiguratsiya zagruzhen (baza: FreeBSD $REL)"
}
Write-Host "== GovechoBSD Windows Builder v$VER ==" -ForegroundColor Cyan
$outIso = Join-Path $WorkDir "govechobsd-$VER-gnome.iso"

# ---------- 1. Zagruzka FreeBSD-ISO (yadro i base uze vnutri!) ----------
if (-not $IsoPath -and -not $SkipDownload -and -not (Test-Path $origIso)) {
    Report 10 "Skachivayu FreeBSD ISO: $IsoUrl"
    $wc = New-Object System.Net.WebClient
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $dlArgs = {
        param($s, $e)
        if ($e.ProgressPercentage -ge 0) {
            $overall = 10 + ($e.ProgressPercentage * 0.35)
            $mbps = if ($sw.Elapsed.TotalSeconds -gt 1) { [math]::Round($e.BytesReceived/1MB/$sw.Elapsed.TotalSeconds,1) } else { 0 }
            [Console]::Out.WriteLine(("PROGRESS|{0}|Download FreeBSD ISO... {1} MB/s" -f [math]::Round($overall), $mbps))
            [Console]::Out.Flush()
        }
    }
    Register-ObjectEvent $wc DownloadProgressChanged -SourceIdentifier dlprog -Action $dlArgs | Out-Null
    $wc.DownloadFile($IsoUrl, "$origIso.part")
    Unregister-Event -SourceIdentifier dlprog -EA SilentlyContinue
    $wc.Dispose()
    Move-Item "$origIso.part" $origIso -Force
}
if (-not (Test-Path $origIso)) { throw "FreeBSD ISO ne nayden: $origIso" }

# ---------- 2. Raspakovka ----------
$src = Join-Path $WorkDir 'extracted'
if (-not (Test-Path $src)) {
    Report 48 "Raspakovyvayu FreeBSD ISO..."
    $img = Mount-DiskImage -ImagePath $origIso -PassThru
    $drv = ($img | Get-Volume).DriveLetter
    robocopy "${drv}:\" $src /E /NFL /NDL /NJH /NJS | Out-Null
    Dismount-DiskImage -ImagePath $origIso | Out-Null
}

# ---------- 3. Naslayvanie Govecho-sloya ----------
Report 62 "Naslaivayu konfiguratsiyu GovechoBSD (loader/rc/GNOME manifest)..."
$gv = Join-Path $src 'govecho'
New-Item -ItemType Directory -Force -Path $gv | Out-Null
foreach ($f in @('bsd/loader.conf','bsd/rc.conf','bsd/sysctl.conf','config/packages.freebsd.list')) {
    $host_f = Join-Path $PSScriptRoot ('..\..' + '\' + ($f -replace '/','\'))
    $alt    = Join-Path (Split-Path $PSScriptRoot) ('..' + '\' + ($f -replace '/','\'))
    foreach ($cand in @($host_f, $alt)) {
        if (Test-Path $cand) { Copy-Item $cand $gv -Force; break }
    }
}
@"
#!/bin/sh
# GovechoBSD post-install hook: GNOME + start apps + zfs boot environment
pkg install -y gnome shell-mate-desktop-lite firefox-esr 2>/dev/null || pkg install -y gnome firefox
sysrc gnome_enable="YES" gdm_enable="YES" dbus_enable="YES" zfs_enable="YES"
echo 'GovechoBSD: GNOME established. Pereklyuchite sessiyu GovechoBSD na ekrane GDM.'
"@ | Set-Content (Join-Path $gv 'postinstall.sh') -Encoding ASCII

# ---------- 4. Peresborka ISO (mkisofs/newfs cherez WSL) ----------
Report 75 "Peresobirayu bootable FreeBSD ISO..."
function ToWslPath([string]$p) { ($p -replace '^([A-Za-z]):', '/mnt/$1').ToLower().Replace('\','/') }
$wSrc = ToWslPath $src; $wOut = ToWslPath $outIso
wsl -u root -- bash -c "command -v mkisofs >/dev/null || (apt-get update -qq && apt-get install -y -qq genisoimage)"
# FreeBSD boot catalog: perebiraem s sohraneniem boot-fragments (boot.catalog/efi)
wsl -u root -- bash -c "set -e; cd '$wSrc'; mkisofs -r -J -joliet-long -V GOVECHOBSD -allow-leading-dots -relaxed-filenames -b boot/cd1/boot.catalog -c bootinfo -no-emul-boot -boot-load-size 4 -boot-info-table -o '$wOut' ."
if (-not (Test-Path $outIso)) { throw "Ne udalos sobrat BSD-ISO" }
$szMB = [math]::Round((Get-Item $outIso).Length/1MB,1)
Report 100 "DONE: govechobsd-$VER-gnome.iso ($szMB MB)"
Write-Host "- DONE: $outIso ($szMB MB)" -ForegroundColor Green
Write-Host @"

- Sborka zavershena. Fayl: $outIso ($szMB MB)
  Zapis na fleshku - vruchnuyu (Rufus/Ventoy/Etcher). Ustanovka interaktivnaya
  (bsdinstall), postinstall.sh dodast GNOME i Govecho-nastroyki.
"@ -ForegroundColor Green
'''

# ============================================================================
# BAT launchers (ASCII, CRLF)
# ============================================================================

BAT_LINUX = r'''@echo off
rem GovechoOS Builder launcher (ZHBR-228, MIT)
rem Double-click -> GUI window with live progress. Or: build_windows.bat -Console [args]
setlocal
cd /d "%~dp0"
if "%1"=="-Console" ( shift & goto console )
where pwsh >nul 2>nul && (pwsh -NoProfile -ExecutionPolicy Bypass -File scripts\build_gui.ps1 %*) || (powershell -NoProfile -ExecutionPolicy Bypass -File scripts\build_gui.ps1 %*)
if errorlevel 1 (
    echo.
    echo [govechoOS] GUI failed to start. Run manually from PowerShell:
    echo     powershell -NoProfile -ExecutionPolicy Bypass -File scripts\build_gui.ps1
    pause
)
goto :eof
:console
where pwsh >nul 2>nul && (pwsh -NoProfile -ExecutionPolicy Bypass -File scripts\build_windows.ps1 %*) || (powershell -NoProfile -ExecutionPolicy Bypass -File scripts\build_windows.ps1 %*)
endlocal
'''

BAT_BSD = r'''@echo off
rem GovechoBSD Builder launcher (ZHBR-228, MIT)
setlocal
cd /d "%~dp0"
if "%1"=="-Console" ( shift & goto console )
where pwsh >nul 2>nul && (pwsh -NoProfile -ExecutionPolicy Bypass -File scripts\build_gui_bsd.ps1 %*) || (powershell -NoProfile -ExecutionPolicy Bypass -File scripts\build_gui_bsd.ps1 %*)
if errorlevel 1 (
    echo.
    echo [GovechoBSD] GUI failed to start. Run manually from PowerShell:
    echo     powershell -NoProfile -ExecutionPolicy Bypass -File scripts\build_gui_bsd.ps1
    pause
)
goto :eof
:console
where pwsh >nul 2>nul && (pwsh -NoProfile -ExecutionPolicy Bypass -File scripts\build_bsd_windows.ps1 %*) || (powershell -NoProfile -ExecutionPolicy Bypass -File scripts\build_bsd_windows.ps1 %*)
endlocal
'''

# ============================================================================
# Emit files
# ============================================================================

gui_linux = gui_ps('Govecho Builder', 'GovechoOS v2.2 - sborka ISO dlja Windows (Ubuntu/Debian)',
                   'build_windows.ps1', 'Ubuntu/Debian live-installer', True, False)
gui_bsd   = gui_ps('GovechoBSD Builder', 'GovechoBSD v1.1 - sborka FreeBSD+GNOME ISO',
                   'build_bsd_windows.ps1', 'FreeBSD disc1/dvd1', False, True)

files = [
    (os.path.join(WS, "scripts/build_gui.ps1"), gui_linux, 'ps1'),
    (os.path.join(WS, "scripts/build_windows.ps1"), linux_builder_ps1(), 'ps1'),
    (os.path.join(WS, "build_windows.bat"), BAT_LINUX, 'bat'),
    (os.path.join(WS, "GovechoBSD/scripts/build_gui_bsd.ps1"), gui_bsd, 'ps1'),
    (os.path.join(WS, "GovechoBSD/scripts/build_bsd_windows.ps1"), bsd_builder_ps1(), 'ps1'),
    (os.path.join(WS, "GovechoBSD/build_bsd_windows.bat"), BAT_BSD, 'bat'),
]

for path, content, kind in files:
    if kind == 'ps1':
        write_ps1(path, content)
    else:
        write_bat(path, content)
    print(f"WROTE {path} ({os.path.getsize(path)} bytes)")

print("ALL PURE ASCII + BOM(ps1) + CRLF - OK")
