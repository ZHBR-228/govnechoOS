#Requires -Version 5.0
# Govecho Builder - WinForms fallback GUI (no XAML). Author: ZHBR-228 | MIT.
param([string]$Builder = '')
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
[System.Windows.Forms.Application]::EnableVisualStyles()
if (-not $Builder) { $Builder = Join-Path $PSScriptRoot 'build_windows.ps1' }
$WorkDir = Join-Path $env:USERPROFILE 'govecho_build'

$frm = New-Object Windows.Forms.Form
$frm.Text = 'Govecho Builder (compat mode)'
$frm.Width = 780; $frm.Height = 560; $frm.StartPosition = 'CenterScreen'

$pct = New-Object Windows.Forms.Label; $pct.Text = '0%'; $pct.Font = New-Object Drawing.Font('Segoe UI', 20, [Drawing.FontStyle]::Bold)
$pct.Location = '620,14'; $pct.AutoSize = $true; $frm.Controls.Add($pct)
$bar = New-Object Windows.Forms.ProgressBar; $bar.Location = '14,20'; $bar.Size = '590,26'; $bar.Maximum = 100; $frm.Controls.Add($bar)
$phase = New-Object Windows.Forms.Label; $phase.Text = 'Gotov k zapusku'; $phase.Location = '14,52'; $phase.Size = '740,20'; $frm.Controls.Add($phase)
$lblBase = New-Object Windows.Forms.Label; $lblBase.Text = 'Baza:'; $lblBase.Location = '14,58'; $lblBase.AutoSize = $true
$cmbBase = New-Object Windows.Forms.ComboBox; $cmbBase.Location = '70,55'; $cmbBase.Width = 110; $cmbBase.DropDownStyle = 'DropDownList'
[void]$cmbBase.Items.AddRange(@('ubuntu','debian')); $cmbBase.SelectedIndex = 0
$frm.Controls.Add($lblBase); $frm.Controls.Add($cmbBase)
$chkAuto = New-Object Windows.Forms.CheckBox; $chkAuto.Text = 'Rezhim AutoInstall'; $chkAuto.Location = '194,55'; $chkAuto.AutoSize = $true; $frm.Controls.Add($chkAuto)
$txtIso = New-Object Windows.Forms.Label; $txtIso.Text = 'ISO: net vybara - budem kachat ofitsialnyy obraz'; $txtIso.Location = '14,80'; $txtIso.Size = '740,20'; $frm.Controls.Add($txtIso)
$log = New-Object Windows.Forms.TextBox; $log.Multiline = $true; $log.ReadOnly = $true; $log.ScrollBars = 'Vertical'
$log.Location = '14,106'; $log.Size = '740,340'; $log.Font = New-Object Drawing.Font('Consolas', 9); $frm.Controls.Add($log)
$btnRun = New-Object Windows.Forms.Button; $btnRun.Text = 'SOBRAT'; $btnRun.Location = '14,456'; $btnRun.Size = '130,34'; $btnRun.Font = New-Object Drawing.Font('Segoe UI', 9, [Drawing.FontStyle]::Bold); $frm.Controls.Add($btnRun)
$btnCancel = New-Object Windows.Forms.Button; $btnCancel.Text = 'OTMENA'; $btnCancel.Location = '154,456'; $btnCancel.Size = '110,34'; $btnCancel.Enabled = $false; $frm.Controls.Add($btnCancel)
$btnOpen = New-Object Windows.Forms.Button; $btnOpen.Text = 'OTKRYT PAPKU'; $btnOpen.Location = '274,456'; $btnOpen.Size = '170,34'; $frm.Controls.Add($btnOpen)
$btnPick = New-Object Windows.Forms.Button; $btnPick.Text = 'VYBRAT ISO...'; $btnPick.Location = '454,456'; $btnPick.Size = '150,34'; $frm.Controls.Add($btnPick)

$script:IsoPath = ''
$script:DetectedBase = ''

$btnPick.Add_Click({
    $dlg = New-Object Windows.Forms.OpenFileDialog
    $dlg.Filter = 'ISO obrazy (*.iso)|*.iso|Vse fayly (*.*)|*.*'
    if ($dlg.ShowDialog() -eq 'OK') {
        $script:IsoPath = $dlg.FileName
        $nm = [IO.Path]::GetFileName($dlg.FileName).ToLower()
        $det = 'unknown'
        if ($nm -match 'freebsd') { $det = 'freebsd' }
        elseif ($nm -match 'ubuntu') { $det = 'ubuntu' }
        elseif ($nm -match 'debian') { $det = 'debian' }
        $script:DetectedBase = if ($det -eq 'unknown') { '' } else { $det }
        if ($cmbBase -and ($det -eq 'ubuntu' -or $det -eq 'debian')) {
            $cmbBase.SelectedIndex = if ($det -eq 'ubuntu') { 0 } else { 1 }
        }
        $txtIso.Text = 'ISO: ' + [IO.Path]::GetFileName($dlg.FileName) + '  [opredeleno: ' + $det + ']'
        $log.AppendText('ISO vybran: ' + $dlg.FileName + ' => ' + $det + "`r`n")
    }
})

$sync = $null; $psInstance = $null; $runspace = $null
$timer = New-Object System.Windows.Forms.Timer; $timer.Interval = 200
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
            if ([double]::TryParse($parts[1], [ref]$p)) {
                if ($p -lt 0) { $p = 0 }; if ($p -gt 100) { $p = 100 }
                $bar.Value = [int]$p
                $pct.Text = ([math]::Round($p)).ToString() + '%'
                if ($parts.Length -gt 2) { $phase.Text = $parts[2] }
            }
        } elseif ($s.StartsWith('ERRTEXT' + $pipe)) {
            $log.AppendText('STDERR: ' + $s.Substring(8) + "`r`n")
        } elseif ($s.StartsWith('EXITCODE' + $pipe)) {
            $code = [int]($s.Split($pipe)[1])
            if ($code -eq 0) { $bar.Value = 100; $pct.Text = '100%'; $phase.Text = 'SBORKA ZAVERSHENA!' }
            else { $phase.Text = 'Oshibka sborki (code ' + $code + ')' }
            $timer.Stop(); $btnRun.Enabled = $true; $btnCancel.Enabled = $false
            if ($script:runspace) { $script:runspace.Dispose(); $script:runspace = $null }
            $script:sync = $null
        } else {
            $log.AppendText($s + "`r`n")
        }
    }
})

$btnRun.Add_Click({
    if ($script:sync) { return }
    $phase.Text = 'Zapusk...'
    $btnRun.Enabled = $false; $btnCancel.Enabled = $true
    $baseSel = if ($cmbBase) { [string]$cmbBase.SelectedItem } else { '' }
    $bargs = @('-NoProfile','-ExecutionPolicy','Bypass','-File', $Builder, '-GuiProtocol')
    if ($script:IsoPath) {
        $bargs += @('-IsoPath', $script:IsoPath)
        if (-not $baseSel -and $script:DetectedBase) { $baseSel = $script:DetectedBase }
    }
    if ($baseSel) { $bargs += @('-Base', $baseSel) }
    if ($chkAuto.Checked) { $bargs += '-AutoInstall' }
    $script:sync = [System.Collections.Concurrent.ConcurrentQueue[string]]::new()
    $rs = [RunspaceFactory]::CreateRunspace()
    $rs.ApartmentState = 'STA'; $rs.ThreadOptions = 'ReuseThread'; $rs.Open()
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

$btnCancel.Add_Click({
    if ($script:psInstance) { try { $script:psInstance.Stop(); $script:psInstance.Dispose() } catch {} }
    if ($script:runspace) { try { $script:runspace.Close(); $script:runspace.Dispose() } catch {}; $script:runspace = $null }
    $script:sync = $null
    $timer.Stop()
    $log.AppendText('== Ostanovleno pol''zovatelem ==' + "`r`n")
    $btnRun.Enabled = $true; $btnCancel.Enabled = $false
})

$btnOpen.Add_Click({
    if (-not (Test-Path $WorkDir)) { New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null }
    Start-Process explorer.exe $WorkDir
})

$frm.Add_FormClosed({
    if ($script:psInstance) { try { $script:psInstance.Stop(); $script:psInstance.Dispose() } catch {} }
    if ($script:runspace) { try { $script:runspace.Dispose() } catch {} }
})

[void]$frm.ShowDialog()
