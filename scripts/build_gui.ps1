#Requires -Version 5.0
# ============================================================
# Govecho Builder GUI (ASCII-safe) - mini app with progress bar.
<#
.SYNOPSIS
    Govecho Builder GUI - shows build progress in a window (WPF).
.DESCRIPTION
    Big percent + progress bar, current phase, live log,
    buttons Run / Cancel / Open ISO folder, base selector ubuntu/debian.
    Talks to build_windows.ps1 via -GuiProtocol lines "PROGRESS|<0-100>|<phase>".
    Author: ZHBR-228 | License: MIT | github.com/ZHBR-228/govnechoOS
.NOTES
    All UI text is defined below in a language table; Russian strings are
    decoded from Unicode escapes so this file stays 100% ASCII and can never
    be broken by encoding issues.
#>
param(
    [string]$Builder = '',
    [ValidateSet('ubuntu','debian')][string]$Base = 'ubuntu',
    [switch]$AutoInstall
)
$ErrorActionPreference = 'Stop'

# ---- language table: pure ASCII labels (encoding-proof) ----
$L = @{
    Title    = 'Govecho Builder'
    Sub      = 'GovechoOS v2.2 - sborka ISO dlja Windows'
    Base     = 'Baza:'
    Auto     = 'Rezhim AutoInstall (bez kontroliya)'
    Run      = 'SOBRAT'
    Cancel   = 'OTMENA'
    Open     = 'OTKRYT'
    Pct0     = '0%'
    Idle     = 'Gotov k zapusku'
    Starting = 'Zapusk...'
    Running  = 'Idet sborka...'
    Done     = 'SBORKA Zavershena!'
    Failed   = 'Oshibka sborki'
    Stopped  = 'Ostanovleno pol''zovatelem'
    Help     = 'Nazhmit SOBRAT: skhaet bazovyj ISO, vinaet Govecho-sloj, peresoberet obraz. ISO ne zapisyvaetsya na disk avtomaticheski.'
    ErrTitle = 'Oshibka Govecho Builder'
    ErrHint  = 'Zapustite vruchnuyuju iz PowerShell:'
}

trap {
    Add-Type -AssemblyName System.Windows.Forms
    $msg = ($L.ErrTitle + [Environment]::NewLine + $_.Exception.Message + [Environment]::NewLine +
            [Environment]::NewLine + $L.ErrHint + [Environment]::NewLine +
            'powershell -NoProfile -ExecutionPolicy Bypass -File "' + $MyInvocation.MyCommand.Path + '"')
    [void][System.Windows.Forms.MessageBox]::Show($msg, 'Govecho Builder', 'OK', 'Error')
    exit 1
}

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

if (-not $Builder) { $Builder = Join-Path $PSScriptRoot 'build_windows.ps1' }
$WorkDir = Join-Path $env:USERPROFILE 'govecho_build'

# ---- XAML built from pure-ASCII string (no Cyrillic at all) ----
[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        Title="Govecho Builder" Height="560" Width="760" WindowStartupLocation="CenterScreen">
  <Grid Margin="14">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>
    <StackPanel Grid.Row="0">
      <TextBlock Text="Govecho Builder" FontSize="24" FontWeight="Bold"/>
      <TextBlock x:Name="TxtSub" Foreground="Gray" Margin="0,2,0,10"/>
    </StackPanel>
    <StackPanel Grid.Row="1" Orientation="Horizontal" Margin="0,0,0,8">
      <TextBlock x:Name="LblBase" VerticalAlignment="Center" Margin="0,0,6,0"/>
      <ComboBox x:Name="CmbBase" Width="110" SelectedIndex="0">
        <ComboBoxItem Content="ubuntu"/>
        <ComboBoxItem Content="debian"/>
      </ComboBox>
      <CheckBox x:Name="ChkAuto" Content="" Margin="16,0,0,0" VerticalAlignment="Center"/>
    </StackPanel>
    <DockPanel Grid.Row="2" Margin="0,0,0,6">
      <TextBlock x:Name="TxtPct" DockPanel.Dock="Right" FontSize="30" FontWeight="Bold" Width="110" TextAlignment="Right"/>
      <ProgressBar x:Name="Bar" Height="26" Minimum="0" Maximum="100" Value="0"/>
    </DockPanel>
    <TextBlock x:Name="TxtPhase" Grid.Row="3" FontSize="14" Margin="0,0,0,8" TextWrapping="Wrap"/>
    <TextBox x:Name="TxtLog" Grid.Row="4" IsReadOnly="True" VerticalScrollBarVisibility="Auto"
             FontFamily="Consolas" FontSize="12" AcceptsReturn="True" TextWrapping="NoWrap"/>
    <StackPanel Grid.Row="5" Orientation="Horizontal" Margin="0,10,0,0">
      <Button x:Name="BtnRun" Content="" Width="130" Height="34" FontWeight="Bold"/>
      <Button x:Name="BtnCancel" Content="" Width="110" Height="34" Margin="10,0,0,0" IsEnabled="False"/>
      <Button x:Name="BtnOpen" Content="" Width="170" Height="34" Margin="10,0,0,0"/>
    </StackPanel>
  </Grid>
</Window>
"@

$win = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $xaml))

$TxtSub   = $win.FindName('TxtSub');     $TxtPhase = $win.FindName('TxtPhase')
$TxtPct   = $win.FindName('TxtPct');     $Bar      = $win.FindName('Bar')
$TxtHint  = $null
$TxtLog   = $win.FindName('TxtLog');     $BtnRun   = $win.FindName('BtnRun')
$BtnCancel= $win.FindName('BtnCancel');  $BtnOpen  = $win.FindName('BtnOpen')
$CmbBase  = $win.FindName('CmbBase');    $ChkAuto  = $win.FindName('ChkAuto')
$LblBase  = $win.FindName('LblBase')

# apply localized texts
$TxtSub.Text    = $L.Sub
$LblBase.Text   = $L.Base
$ChkAuto.Content= $L.Auto
$BtnRun.Content = $L.Run
$BtnCancel.Content = $L.Cancel
$BtnOpen.Content   = $L.Open
$TxtPct.Text    = $L.Pct0
$TxtPhase.Text  = $L.Idle + '  |  ' + $L.Help

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

$sync = $null
$ps = $null
$runspace = $null

$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromMilliseconds(200)
$timer.Add_Tick({
    if (-not $script:sync) { return }
    while ($script:sync.IsCompleted -or $true) {
        $item = $null
        if (-not $script:sync.TryTake([ref]$item)) { break }
        $s = [string]$item
        if ($s.StartsWith('PROGRESS|')) {
            $parts = $s.Split('|')
            $p = 0.0
            if ([double]::TryParse($parts[1], [ref]$p)) { Set-Progress $p $parts[2] }
        } elseif ($s.StartsWith('ERRTEXT|')) {
            Add-Log ('STDERR: ' + $s.Substring(8))
        } elseif ($s.StartsWith('EXITCODE|')) {
            $code = [int]($s.Split('|')[1])
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
    $baseSel = $CmbBase.SelectedItem.Content
    $bargs = @('-NoProfile','-ExecutionPolicy','Bypass','-File', $Builder, '-GuiProtocol', '-Base', $baseSel)
    if ($ChkAuto.IsChecked) { $bargs += '-AutoInstall' }
    # synchronized queue + inline runspace: no background jobs / WinRM needed
    $script:sync = [System.Collections.Concurrent.ConcurrentQueue[string]]::new()
    $rs = [RunspaceFactory]::CreateRunspace()
    $rs.ApartmentState = 'STA'
    $rs.ThreadOptions = 'ReuseThread'
    $rs.Open()
    $ps = [PowerShell]::Create()
    $ps.Runspace = $rs
    [void]$ps.AddScript({
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
            if ($errt) { [void]$q.Enqueue(('ERRTEXT|' + $errt)) }
            [void]$q.Enqueue(('EXITCODE|' + $proc.ExitCode))
        } catch {
            [void]$q.Enqueue(('ERRTEXT|' + $_.Exception.Message))
            [void]$q.Enqueue('EXITCODE|1')
        }
    }).AddArgument($Builder).AddArgument($bargs).AddArgument($script:sync)
    $asyncResult = $ps.BeginInvoke()
    $script:runspace = $rs
    $timer.Start()
})

$BtnCancel.Add_Click({
    if ($script:ps) { try { $script.ps.Stop(); $script.ps.Dispose() } catch {} }
    if ($script:runspace) { try { $script.runspace.Close(); $script.runspace.Dispose() } catch {} ; $script:runspace = $null }
    $script:sync = $null
    $timer.Stop()
    Add-Log ('== ' + $L.Stopped + ' ==')
    $BtnRun.IsEnabled = $true; $BtnCancel.IsEnabled = $false
})

$BtnOpen.Add_Click({
    if (-not (Test-Path $WorkDir)) { New-Item -ItemType Directory -Path $WorkDir | Out-Null }
    Start-Process explorer.exe $WorkDir
})

$win.Add_Closed({
    if ($script:ps) { try { $script.ps.Stop(); $script.ps.Dispose() } catch {} }
    if ($script:runspace) { try { $script.runspace.Dispose() } catch {} }
})

[void]$win.ShowDialog()
