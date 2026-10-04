#Requires -Version 5.0
# govshell.ps1 - universalnyj interfeys sborshchika Govecho (WinForms, BEZ XAML).
# Sluzhit obeim redaktsiyam: param -Edition linux|bsd. Vse stroki ASCII bez apostrofov.
# Zapusk: powershell -NoProfile -ExecutionPolicy Bypass -File govshell.ps1 -Edition linux
[CmdletBinding()]
param(
    [ValidateSet("linux","bsd")][string]$Edition = "linux",
    [string]$Engine = ""
)
$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$ScriptDir = Split-Path -Parent $PSCommandPath
if (-not $Engine) { $Engine = Join-Path $ScriptDir "govengine.ps1" }
if (-not (Test-Path $Engine)) {
    [System.Windows.Forms.MessageBox]::Show(("Dvizhok ne naiden: {0}" -f $Engine), "Govecho Builder") | Out-Null
    exit 1
}
$WorkDir = Join-Path $env:USERPROFILE ("govecho_build_{0}" -f $Edition)

# ---------------- okno ----------------
$frm = New-Object System.Windows.Forms.Form
$tag = "Linux"
if ($Edition -eq "bsd") { $tag = "BSD" }
$frm.Text = ("Govecho Builder [{0}] v2.0" -f $tag)
$frm.Width = 800; $frm.Height = 640
$frm.StartPosition = "CenterScreen"
$frm.Font = New-Object System.Drawing.Font("Segoe UI", 9)

$lblTitle = New-Object System.Windows.Forms.Label
$lblTitle.Text = "Govecho OS Builder"
$lblTitle.Font = New-Object System.Drawing.Font("Segoe UI", 14, [System.Drawing.FontStyle]::Bold)
$lblTitle.SetBounds(14, 10, 500, 30); $frm.Controls.Add($lblTitle)

$lblSub = New-Object System.Windows.Forms.Label
$lblSub.Text = "Dvizhok v2.0: vyberite uzhe skachannyj ISO - distributiv opredelitsya po imeni fayla."
$lblSub.ForeColor = [System.Drawing.Color]::Gray
$lblSub.SetBounds(16, 42, 740, 18); $frm.Controls.Add($lblSub)

$lblBase = New-Object System.Windows.Forms.Label
$lblBase.Text = "Baza:"
$lblBase.SetBounds(16, 74, 50, 22); $frm.Controls.Add($lblBase)

$cmb = New-Object System.Windows.Forms.ComboBox
$cmb.DropDownStyle = "DropDownList"
$cmb.SetBounds(70, 71, 130, 24); $frm.Controls.Add($cmb)
if ($Edition -eq "bsd") {
    [void]$cmb.Items.Add("freebsd"); $cmb.SelectedIndex = 0; $cmb.Enabled = $false
} else {
    [void]$cmb.Items.Add("auto")
    [void]$cmb.Items.Add("ubuntu")
    [void]$cmb.Items.Add("debian")
    $cmb.SelectedIndex = 0
}

$btnIso = New-Object System.Windows.Forms.Button
$btnIso.Text = "VYBRAT ISO..."
$btnIso.SetBounds(215, 70, 120, 26); $frm.Controls.Add($btnIso)

$txtIso = New-Object System.Windows.Forms.TextBox
$txtIso.ReadOnly = $true
$txtIso.SetBounds(345, 71, 330, 24); $txtIso.Anchor = "Top,Left,Right"; $frm.Controls.Add($txtIso)

$chkAuto = New-Object System.Windows.Forms.CheckBox
$chkAuto.Text = "Avto-ustanovka (snyato - rezhim kontrolya kazhdogo shaga)"
$chkAuto.SetBounds(16, 104, 460, 22); $frm.Controls.Add($chkAuto)

$bar = New-Object System.Windows.Forms.ProgressBar
$bar.Minimum = 0; $bar.Maximum = 1000
$bar.SetBounds(16, 134, 650, 26); $bar.Anchor = "Top,Left,Right"; $frm.Controls.Add($bar)

$lblPct = New-Object System.Windows.Forms.Label
$lblPct.Text = "0%"
$lblPct.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
$lblPct.TextAlign = [System.Drawing.ContentAlignment]::MiddleRight
$lblPct.SetBounds(676, 132, 70, 28); $lblPct.Anchor = "Top,Right"; $frm.Controls.Add($lblPct)

$lblPhase = New-Object System.Windows.Forms.Label
$lblPhase.Text = "Fazy: ozhidanie zapuska"
$lblPhase.SetBounds(16, 166, 740, 20); $lblPhase.Anchor = "Top,Left,Right"; $frm.Controls.Add($lblPhase)

$txtLog = New-Object System.Windows.Forms.TextBox
$txtLog.Multiline = $true; $txtLog.ReadOnly = $true
$txtLog.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical
$txtLog.Font = New-Object System.Drawing.Font("Consolas", 9)
$txtLog.SetBounds(16, 192, 750, 330); $txtLog.Anchor = "Top,Bottom,Left,Right"; $frm.Controls.Add($txtLog)

$btnRun = New-Object System.Windows.Forms.Button
$btnRun.Text = "SOBRAT"
$btnRun.SetBounds(16, 534, 130, 34); $btnRun.Anchor = "Bottom,Left"; $frm.Controls.Add($btnRun)

$btnCancel = New-Object System.Windows.Forms.Button
$btnCancel.Text = "OSTANOVIT"
$btnCancel.SetBounds(156, 534, 110, 34); $btnCancel.Anchor = "Bottom,Left"
$btnCancel.Enabled = $false; $frm.Controls.Add($btnCancel)

$btnOpen = New-Object System.Windows.Forms.Button
$btnOpen.Text = "OTKRYT PAPKU SBORKI"
$btnOpen.SetBounds(276, 534, 180, 34); $btnOpen.Anchor = "Bottom,Left"; $frm.Controls.Add($btnOpen)

$script:selIso = ""
$script:proc = $null

function Add-Log([string]$s) {
    if ($s) { $txtLog.AppendText($s + "`r`n") }
}
function Set-Progress([double]$pct, [string]$phase) {
    if ($pct -lt 0) { $pct = 0 }
    if ($pct -gt 100) { $pct = 100 }
    $bar.Value = [int]($pct * 10)
    $lblPct.Text = ("{0}%" -f [math]::Round($pct))
    if ($phase) { $lblPhase.Text = $phase }
    [System.Windows.Forms.Application]::DoEvents()
}

# ---------------- vybor lokalnogo ISO + avto-opredelenie ----------------
$btnIso.Add_Click({
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Filter = "ISO-obrazy (*.iso)|*.iso|Vse fayly (*.*)|*.*"
    $dlg.Title = "Vyberite uzhe skachannyj obraz Ubuntu / Debian / FreeBSD"
    if ($dlg.ShowDialog($frm) -eq [System.Windows.Forms.DialogResult]::OK) {
        $script:selIso = $dlg.FileName
        $txtIso.Text = [IO.Path]::GetFileName($selIso)
        $name = $txtIso.Text.ToLower()
        $detected = "ne izvestno"
        if     ($name -match "freebsd|ghostbsd") { $detected = "FreeBSD" }
        elseif ($name -match "linuxmint|zorin|pop-os|popos|ubuntu") { $detected = "Ubuntu-baza" }
        elseif ($name -match "debian|devuan") { $detected = "Debian-baza" }
        elseif ($name -match "fedora") { $detected = "Fedora" }
        if ($Edition -eq "linux") {
            if     ($name -match "debian|devuan") { $cmb.SelectedItem = "debian" }
            elseif ($name -match "ubuntu|mint|zorin|pop") { $cmb.SelectedItem = "ubuntu" }
        }
        Add-Log ("Vybran obraz: {0} -> opredeleno: {1}" -f $txtIso.Text, $detected)
    }
})

$btnOpen.Add_Click({
    if (-not (Test-Path $WorkDir)) { New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null }
    Start-Process explorer.exe $WorkDir
})

# ---------------- protokoly dvizhka: chitaem v tike ----------------
$script:bufOut = ""
$script:bufErr = ""

function Process-Line([string]$line) {
    if (-not $line) { return }
    if ($line.StartsWith("PROGRESS|")) {
        $p = $line.Split("|")
        $v = 0.0
        if ([double]::TryParse($p[1], [ref]$v)) { Set-Progress $v $p[2] }
    } elseif ($line.StartsWith("PHASE|")) {
        $p = $line.Split("|")
        Add-Log ("--- Faza {0}: {1} ---" -f $p[1], $p[2])
    } elseif ($line.StartsWith("LOG|")) {
        Add-Log $line.Substring(4)
    } elseif ($line.StartsWith("DONE|")) {
        $iso = $line.Substring(5)
        Add-Log ""
        Add-Log ("SBORKA Zavershena: {0}" -f $iso)
        Set-Progress 100 "Gotovo!"
        $btnRun.Enabled = $true; $btnCancel.Enabled = $false
        [System.Windows.Forms.MessageBox]::Show(("Obraz gotov:{0}{1}" -f "`r`n", $iso), "Govecho Builder") | Out-Null
    } elseif ($line.StartsWith("ERR|")) {
        $p = $line.Split("|", 3)
        Add-Log ("OSHIBKA: " + $p[2])
        Set-Progress 0 "Oshibka sborki"
        $btnRun.Enabled = $true; $btnCancel.Enabled = $false
    } else {
        Add-Log $line
    }
}

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 120
$timer.Add_Tick({
    if (-not $script:proc) { return }
    $moreOut = $script:proc.StandardOutput.ReadToEnd()
    # cchitat' popotoczno: ReadToEnd blokiruet do EOF - ispolzuem BaseStream chtenie
})
# vmesto timer-na-ReadToEnd: prosteje blokiruyushchee chtenie s DoEvents mezhdu strokami
$pollDel = [System.Action]{
    while ($script:proc -and -not $script:proc.StandardOutput.EndOfStream) {
        $line = $script:proc.StandardOutput.ReadLine()
        $frm.BeginInvoke([Action]{ Process-Line $line }) | Out-Null
        [System.Windows.Forms.Application]::DoEvents()
    }
    $code = -1
    try { $script:proc.WaitForExit(); $code = $script:proc.ExitCode } catch {}
    $frm.BeginInvoke([Action]{
        if ($code -ne 0) {
            Add-Log ("Dvizhok zavershen s kodom {0}." -f $code)
            $btnRun.Enabled = $true; $btnCancel.Enabled = $false
        }
        $script:proc = $null
    }) | Out-Null
}

$btnRun.Add_Click({
    if ($script:proc) { return }
    $txtLog.Clear(); Set-Progress 1 "Zapusk dvizhka..."
    $btnRun.Enabled = $false; $btnCancel.Enabled = $true
    $a = "-NoProfile -ExecutionPolicy Bypass -File `"{0}`" -WorkDir `"{1}`" -Edition {2} -Base {3}" -f $Engine, $WorkDir, $Edition, $cmb.SelectedItem
    if ($script:selIso) { $a += (" -IsoPath `"{0}`"" -f $script:selIso) }
    if ($chkAuto.IsChecked) { $a += " -AutoInstall" }
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "powershell.exe"
    $psi.Arguments = $a
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $false
    $psi.CreateNoWindow = $true
    $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    $script:proc = [System.Diagnostics.Process]::Start($psi)
    Add-Log ("Dvizhok zapushchen (PID {0})." -f $script:proc.Id)
    $pollDel.BeginInvoke($null, $null)
})

$btnCancel.Add_Click({
    if ($script:proc -and -not $script:proc.HasExited) {
        try { $script:proc.Kill($true) } catch { try { $script:proc.Kill() } catch {} }
        Add-Log "Protsess ostanovlen polzovatelem."
    }
    $btnRun.Enabled = $true; $btnCancel.Enabled = $false
    Set-Progress 0 "Ostanovleno"
})

$frm.Add_FormClosing({
    if ($script:proc -and -not $script:proc.HasExited) {
        $r = [System.Windows.Forms.MessageBox]::Show("Sborka idet. Zakryt? Dvizhok budet ostanovlen.", "Govecho", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Warning)
        if ($r -ne [System.Windows.Forms.DialogResult]::Yes) { $EventArgs.Cancel = $true; return }
        try { $script:proc.Kill($true) } catch {}
    }
})

Set-Progress 0 "Nazhmite SOBRAT. Mozhno vybrat uzhe skachannyj ISO - distributiv opredelitsya sam."
[void]$frm.ShowDialog()
