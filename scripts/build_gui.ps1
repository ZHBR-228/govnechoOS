#Requires -Version 5.0
# ============================================================
# Govecho Builder GUI builder (auto-generated, pure ASCII, encoding-proof).
# Author: ZHBR-228 | License: MIT
# Talks to build_windows.ps1 via PROGRESS|<0-100>|<phase> stdout lines.
# New: "Use local ISO" button - pick an already downloaded image; the
#      distribution is auto-detected from its file name.
# ============================================================
param(
    [string]$Builder = '',
    [switch]$SelfTest
)
$ErrorActionPreference = 'Stop'

$L = @{
    Title    = 'Govecho Builder'
    Sub      = 'GovechoOS v2.2 - sborka ISO dlja Windows (Ubuntu/Debian)'
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
    IsoSel   = 'ISO: {0}  [opredeleno: {1}]'
    Unknown  = 'ne izvestno - ukazite bazu v spiske'
    ErrTitle = 'Oshibka Govecho Builder'
    ErrHint  = 'Zapustite vruchnuyuju iz PowerShell:'
}

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms

if ($SelfTest) { Write-Host 'SELFTEST-OK'; exit 0 }

# ---- locate builder script next to this file ----
if (-not $Builder) { $Builder = Join-Path $PSScriptRoot 'build_windows.ps1' }
if (-not (Test-Path $Builder)) {
    Add-Type -AssemblyName System.Windows.Forms
    [void][System.Windows.Forms.MessageBox]::Show(('Ne nayden fail sborschika: ' + $Builder), $L.ErrTitle, 'OK', 'Error')
    exit 1
}
$WorkDir = Join-Path $env:USERPROFILE 'govecho_build'

# ---- XAML built line-by-line from single-quoted strings (no here-strings,
#      no way for transfer tools to break quoting; xmlns:x IS declared) ----
$xaml = ''
$xaml += '<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"`r`n'
$xaml += '        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"`r`n'
$xaml += '        Title="Govecho Builder" Height="580" Width="780" WindowStartupLocation="CenterScreen">`r`n'
$xaml += '  <Grid Margin="14">`r`n'
$xaml += '    <Grid.RowDefinitions>`r`n'
$xaml += '      <RowDefinition Height="Auto"/>`r`n'
$xaml += '      <RowDefinition Height="Auto"/>`r`n'
$xaml += '      <RowDefinition Height="Auto"/>`r`n'
$xaml += '      <RowDefinition Height="Auto"/>`r`n'
$xaml += '      <RowDefinition Height="Auto"/>`r`n'
$xaml += '      <RowDefinition Height="*"/>`r`n'
$xaml += '      <RowDefinition Height="Auto"/>`r`n'
$xaml += '    </Grid.RowDefinitions>`r`n'
$xaml += '    <StackPanel Grid.Row="0">`r`n'
$xaml += '      <TextBlock Text="Govecho Builder" FontSize="24" FontWeight="Bold"/>`r`n'
$xaml += '      <TextBlock x:Name="TxtSub" Foreground="Gray" Margin="0,2,0,10"/>`r`n'
$xaml += '    </StackPanel>`r`n'
$xaml += '    <StackPanel Grid.Row="1" Orientation="Horizontal" Margin="0,0,0,8">`r`n'
$xaml += '      <TextBlock x:Name="LblBase" VerticalAlignment="Center" Margin="0,0,6,0"/>`r`n'
$xaml += '      <ComboBox x:Name="CmbBase" Width="110" SelectedIndex="0">`r`n'
$xaml += '        <ComboBoxItem Content="ubuntu"/>`r`n'
$xaml += '        <ComboBoxItem Content="debian"/>`r`n'
$xaml += '      </ComboBox>`r`n'
$xaml += '      <Button x:Name="BtnPick" Margin="14,0,0,0" Padding="10,4"/>`r`n'
$xaml += '      <CheckBox x:Name="ChkAuto" Margin="16,0,0,0" VerticalAlignment="Center"/>`r`n'
$xaml += '    </StackPanel>`r`n'
$xaml += '    <TextBlock x:Name="TxtIso" Grid.Row="2" Foreground="DimGray" Margin="0,0,0,8" TextTrimming="CharacterEllipsis"/>`r`n'
$xaml += '    <DockPanel Grid.Row="3" Margin="0,0,0,6">`r`n'
$xaml += '      <TextBlock x:Name="TxtPct" DockPanel.Dock="Right" FontSize="30" FontWeight="Bold" Width="110" TextAlignment="Right"/>`r`n'
$xaml += '      <ProgressBar x:Name="Bar" Height="26" Minimum="0" Maximum="100" Value="0"/>`r`n'
$xaml += '    </DockPanel>`r`n'
$xaml += '    <TextBlock x:Name="TxtPhase" Grid.Row="4" FontSize="14" Margin="0,0,0,8" TextWrapping="Wrap"/>`r`n'
$xaml += '    <TextBox x:Name="TxtLog" Grid.Row="5" IsReadOnly="True" VerticalScrollBarVisibility="Auto"`r`n'
$xaml += '             FontFamily="Consolas" FontSize="12" AcceptsReturn="True" TextWrapping="NoWrap"/>`r`n'
$xaml += '    <StackPanel Grid.Row="6" Orientation="Horizontal" Margin="0,10,0,0">`r`n'
$xaml += '      <Button x:Name="BtnRun" Width="130" Height="34" FontWeight="Bold"/>`r`n'
$xaml += '      <Button x:Name="BtnCancel" Width="110" Height="34" Margin="10,0,0,0" IsEnabled="False"/>`r`n'
$xaml += '      <Button x:Name="BtnOpen" Width="170" Height="34" Margin="10,0,0,0"/>`r`n'
$xaml += '    </StackPanel>`r`n'
$xaml += '  </Grid>`r`n'
$xaml += '</Window>'

try {
    $xd = New-Object System.Xml.XmlDocument
    $xd.LoadXml($xaml)
    $win = [System.Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $xd))
} catch {
    Add-Type -AssemblyName System.Windows.Forms
    [void][System.Windows.Forms.MessageBox]::Show(('XAML parse: ' + $_.Exception.Message + [Environment]::NewLine + $L.ErrHint + [Environment]::NewLine + 'powershell -NoProfile -ExecutionPolicy Bypass -File "' + $MyInvocation.MyCommand.Path + '"'), $L.ErrTitle, 'OK', 'Error')
    exit 1
}

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
if ($LblBase) { $LblBase.Text = $L.Base }
$TxtPhase.Text   = $L.Idle

$script:IsoPath = ''
$script:DetectedBase = ''

function Set-Progress([double]$pct, [string]$phase) {
    if ($pct -lt 0) { $pct = 0 }; if ($pct -gt 100) { $pct = 100 }
    $Bar.Value = $pct
    $TxtPct.Text = ([math]::Round($pct)).ToString() + '%'
    if ($phase) { $TxtPhase.Text = $phase }
}
function Add-Log([string]$s) {
    if ($null -eq $s -or $s -eq '') { return }
    $TxtLog.AppendText($s + "`r`n")
    $TxtLog.ScrollToEnd()
}

# ---- local ISO picker + distro detection by file name ----
$BtnPick.Add_Click({
    $dlg = New-Object Microsoft.Win32.OpenFileDialog
    $dlg.Filter = 'ISO obrazy (*.iso)|*.iso|Vse fayly (*.*)|*.*'
    $dlg.Title = 'Vyberite uzhe skhannyy Ubuntu/Debian live-installer ISO'
    if ($dlg.ShowDialog()) {
        $script:IsoPath = $dlg.FileName
        $nm = [IO.Path]::GetFileName($dlg.FileName).ToLower()
        $det = 'unknown'
        if ($nm -match 'ubuntu') { $det = 'ubuntu' }
        elseif ($nm -match 'debian') { $det = 'debian' }
        $script:DetectedBase = if ($det -eq 'unknown') { '' } else { $det }
        if ($CmbBase -and ($det -eq 'ubuntu' -or $det -eq 'debian')) {
            $CmbBase.SelectedIndex = if ($det -eq 'ubuntu') { 0 } else { 1 }
        }
        $shown = if ($det -eq 'unknown') { $L.Unknown } else { $det }
        $TxtIso.Text = [string]::Format($L.IsoSel, [IO.Path]::GetFileName($dlg.FileName), $shown)
        Add-Log ('ISO vybran: ' + $dlg.FileName + ' => ' + $shown)
    }
})

# ---- progress pump: runspace + ConcurrentQueue (no WinRM/jobs needed) ----
$sync = $null
$psInstance = $null
$runspace = $null

$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromMilliseconds(200)
$timer.Add_Tick({
    if (-not $script:sync) { return }
    while ($true) {
        $item = $null
        if (-not $script:sync.TryTake([ref]$item)) { break }
        $s = [string]$item
        $pipe = [string][char]124
        if ($s.StartsWith('PROGRESS' + $pipe)) {
            $parts = $s.Split($pipe)
            $p = 0.0
            if ([double]::TryParse($parts[1], [ref]$p)) { Set-Progress $p $parts[2] }
        } elseif ($s.StartsWith('ERRTEXT' + $pipe)) {
            Add-Log ('STDERR: ' + $s.Substring(8))
        } elseif ($s.StartsWith('EXITCODE' + $pipe)) {
            $code = [int]($s.Split($pipe)[1])
            if ($code -eq 0) { Set-Progress 100 $L.Done; Add-Log ('== ' + $L.Done + ' ==') }
            else { Set-Progress 0 $L.Failed; Add-Log ('== ' + $L.Failed + ' (code ' + $code + ') ==') }
            $timer.Stop(); $BtnRun.IsEnabled = $true; $BtnCancel.IsEnabled = $false
            if ($script:runspace) { $script:runspace.Dispose(); $script:runspace = $null }
            $script:sync = $null
        } else {
            Add-Log $s
        }
    }
})

$BtnRun.Add_Click({
    if ($script:sync) { return }
    Add-Log ('== ' + $L.Running + ' ==')
    Set-Progress 1 $L.Starting
    $BtnRun.IsEnabled = $false; $BtnCancel.IsEnabled = $true

    $baseSel = if ($CmbBase) { [string]$CmbBase.SelectedItem.Content } else { '' }
    $bargs = @('-NoProfile','-ExecutionPolicy','Bypass','-File', $Builder, '-GuiProtocol')
    if ($script:IsoPath) {
        $bargs += @('-IsoPath', $script:IsoPath)
        if (-not $baseSel -and $script:DetectedBase) { $baseSel = $script:DetectedBase }
    }
    if ($baseSel) { $bargs += @('-Base', $baseSel) }
    if ($ChkAuto.IsChecked) { $bargs += '-AutoInstall' }
    $script:sync = [System.Collections.Concurrent.ConcurrentQueue[string]]::new()
    $rs = [RunspaceFactory]::CreateRunspace()
    $rs.ApartmentState = 'STA'
    $rs.ThreadOptions = 'ReuseThread'
    $rs.Open()
    $psInstance = [PowerShell]::Create()
    $psInstance.Runspace = $rs
    $script:psInstance = $psInstance
    [void]$psInstance.AddScript({
        param($b, $a, $q)
        try {
            $exe = if (Get-Command pwsh -EA SilentlyContinue) { 'pwsh' } else { 'powershell' }
            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName = $exe
            $psi.Arguments = (($a | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }) -join ' ')
            $psi.RedirectStandardOutput = $true
            $psi.RedirectStandardError = $true
            $psi.UseShellExecute = $false
            $psi.WorkingDirectory = Split-Path $b
            $proc = [System.Diagnostics.Process]::Start($psi)
            while ($null -ne ($line = $proc.StandardOutput.ReadLine())) { [void]$q.Enqueue($line) }
            $errt = $proc.StandardError.ReadToEnd()
            $proc.WaitForExit()
            if ($errt) { [void]$q.Enqueue(('ERRTEXT' + [char]124 + $errt)) }
            [void]$q.Enqueue(('EXITCODE' + [char]124 + $proc.ExitCode))
        } catch {
            [void]$q.Enqueue(('ERRTEXT' + [char]124 + $_.Exception.Message))
            [void]$q.Enqueue('EXITCODE' + [char]124 + '1')
        }
    }).AddArgument($Builder).AddArgument($bargs).AddArgument($script:sync)
    [void]$psInstance.BeginInvoke()
    $script:runspace = $rs
    $timer.Start()
})

$BtnCancel.Add_Click({
    if ($script:psInstance) { try { $script:psInstance.Stop(); $script:psInstance.Dispose() } catch {} }
    if ($script:runspace) { try { $script:runspace.Close(); $script:runspace.Dispose() } catch {}; $script:runspace = $null }
    $script:sync = $null
    $timer.Stop()
    Add-Log ('== ' + $L.Stopped + ' ==')
    $BtnRun.IsEnabled = $true; $BtnCancel.IsEnabled = $false
})

$BtnOpen.Add_Click({
    if (-not (Test-Path $WorkDir)) { New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null }
    Start-Process explorer.exe $WorkDir
})

$win.Add_Closed({
    if ($script:psInstance) { try { $script:psInstance.Stop(); $script:psInstance.Dispose() } catch {} }
    if ($script:runspace) { try { $script:runspace.Dispose() } catch {} }
})

[void]$win.ShowDialog()
