#Requires -Version 5.0
# ============================================================
# САМОДЕКОДИРУЮЩИЙСЯ ЗАПУСКЧИК (fixes "окно открывается на миллисекунды"):
# Если .ps1 сохранён без BOM и содержит кириллицу в комментариях/строках,
# Windows PowerShell 5.1 читает его как ANSI(cp1251), код ломается и скрипт
# мгновенно завершается с ошибкой парсинга. Поэтому при первом запуске этот
# файл сам перезаписывает себя с UTF-8 BOM и перезапускается.
if ($args[0] -ne '-Relaunched') {
    $f = $MyInvocation.MyCommand.Path
    if (-not $f) { $f = (Resolve-Path '.\build_gui.ps1').Path }
    $bytes = [IO.File]::ReadAllBytes($f)
    if (-not ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)) {
        $text = [Text.Encoding]::UTF8.GetString($bytes)
        [IO.File]::WriteAllBytes($f, [byte[]](0xEF,0xBB,0xBF) + [Text.Encoding]::UTF8.GetBytes($text))
        $exe = if (Get-Command pwsh -EA SilentlyContinue) { 'pwsh' } else { 'powershell' }
        Start-Process -FilePath $exe -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File', "`"$f`"", '-Relaunched') -WindowStyle Hidden
        exit 0
    }
}
<#
.SYNOPSIS
    Govecho Builder GUI — мини-приложение с интерфейсом, показывающим прогресс сборки.
.DESCRIPTION
    Окно (WPF, встроен в PowerShell — без внешних зависимостей):
      • большой процент выполнения + прогресс-бар;
      • текущая фаза и живой лог внизу окна;
      • кнопки «Собрать», «Отмена», «Открыть папку с ISO»;
      • выбор базы ubuntu/debian и режима AutoInstall.
    Работает с build_windows.ps1: тот в режиме -GuiProtocol пишет в stdout
    машиночитаемые строки "PROGRESS|<0-100>|<фаза>", GUI их перехватывает.

    Автор: ZHBR-228 · Лицензия: MIT · github.com/ZHBR-228/govnechoOS
#>
param(
    [string]$Relaunched = '',       # служебный: метка перезапуска после самодекодирования
    [string]$Builder = '',          # путь к build_windows.ps1 (по умолчанию рядом)
    [ValidateSet('ubuntu','debian')][string]$Base = 'ubuntu',
    [switch]$AutoInstall
)
$ErrorActionPreference = 'Stop'
# Страховка: любая ошибка покажет диалог с текстом причины, а не закроет окно молча
trap {
    Add-Type -AssemblyName System.Windows.Forms
    $msg = 'Ошибка запуска Govecho Builder:' + [Environment]::NewLine + $_.Exception.Message +
           [Environment]::NewLine + [Environment]::NewLine + 'Запустите вручную из PowerShell:' +
           [Environment]::NewLine + 'powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\build_gui.ps1
    [void][System.Windows.Forms.MessageBox]::Show($msg, 'Govecho Builder', 'OK', 'Error')
    exit 1
}

# ---------- WPF ----------
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

# ---------- Консольный режим (для тестов/серверов без GUI) ----------
if ($env:GOVECHO_GUI -eq 'console') {
    & $Builder -GuiProtocol -Base $(if($Base){$Base}else{'ubuntu'}) $(if($AutoInstall){'-AutoInstall'}else{})
    exit $LASTEXITCODE
}

$XAML = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="GovechoOS Builder" Height="560" Width="760" MinHeight="420" MinWidth="600"
        Background="#1e1e2a" WindowStartupLocation="CenterScreen">
  <Grid Margin="14">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>
    <!-- Шапка -->
    <StackPanel Grid.Row="0" Orientation="Horizontal">
      <TextBlock Text="GOVECHO" FontSize="30" FontWeight="Bold" Foreground="#7aa2ff"/>
      <TextBlock Text="OS Builder" FontSize="30" Foreground="#dddddd" Margin="8,0,0,0"/>
      <TextBlock x:Name="TxtVer" Text="v2.1" FontSize="14" Foreground="#888888"
                 VerticalAlignment="Bottom" Margin="10,0,0,6"/>
    </StackPanel>
    <!-- Прогресс -->
    <Border Grid.Row="1" Background="#26263a" CornerRadius="8" Padding="12" Margin="0,12,0,0">
      <StackPanel>
        <DockPanel>
          <TextBlock x:Name="TxtPhase" DockPanel.Dock="Left" Text="Готов к сборке"
                     FontSize="16" Foreground="#ffffff"/>
          <TextBlock x:Name="TxtPct" DockPanel.Dock="Right" Text="0%"
                     FontSize="26" FontWeight="Bold" Foreground="#7aa2ff"/>
        </DockPanel>
        <ProgressBar x:Name="Bar" Height="16" Minimum="0" Maximum="100" Value="0"
                     Foreground="#5b8def" Background="#3a3a52" BorderThickness="0" Margin="0,8,0,0"/>
        <TextBlock x:Name="TxtHint" Text="" Foreground="#9a9ab0" FontSize="12" Margin="0,6,0,0"
                   TextWrapping="Wrap"/>
      </StackPanel>
    </Border>
    <!-- Выбор -->
    <StackPanel Grid.Row="2" Orientation="Horizontal" Margin="0,10,0,0">
      <TextBlock Text="База:" Foreground="#cccccc" VerticalAlignment="Center"/>
      <ComboBox x:Name="CmbBase" Width="120" Margin="8,0,16,0" SelectedIndex="0">
        <ComboBoxItem Content="ubuntu"/>
        <ComboBoxItem Content="debian"/>
      </ComboBox>
      <CheckBox x:Name="ChkAuto" Content="Режим автоустановки (без вопросов)"
                Foreground="#cccccc" VerticalAlignment="Center"/>
    </StackPanel>
    <!-- Лог -->
    <Border Grid.Row="3" Background="#14141d" CornerRadius="8" Padding="6" Margin="0,10,0,0">
      <TextBox x:Name="TxtLog" IsReadOnly="True" Background="Transparent" Foreground="#b8e0b8"
               FontFamily="Consolas" FontSize="12" BorderThickness="0"
               VerticalScrollBarVisibility="Auto" TextWrapping="Wrap"/>
    </Border>
    <!-- Кнопки -->
    <StackPanel Grid.Row="4" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,10,0,0">
      <Button x:Name="BtnOpen" Content="📂 Папка сборки" Width="130" Height="30" Margin="0,0,8,0"
              Background="#3a3a52" Foreground="#eeeeee" BorderThickness="0"/>
      <Button x:Name="BtnCancel" Content="✖ Отмена" Width="100" Height="30" Margin="0,0,8,0"
              Background="#6e3434" Foreground="#ffffff" BorderThickness="0" IsEnabled="False"/>
      <Button x:Name="BtnRun" Content="▶ Собрать" Width="120" Height="30"
              Background="#5b8def" Foreground="#ffffff" FontWeight="Bold" BorderThickness="0"/>
    </StackPanel>
  </Grid>
</Window>
'@
$reader = New-Object System.Xml.XmlNodeReader ([xml]$XAML)
$win = [Windows.Markup.XamlReader]::Load($reader)
$TxtPhase = $win.FindName('TxtPhase'); $TxtPct = $win.FindName('TxtPct')
$Bar = $win.FindName('Bar');           $TxtHint = $win.FindName('TxtHint')
$TxtLog = $win.FindName('TxtLog');     $BtnRun = $win.FindName('BtnRun')
$BtnCancel = $win.FindName('BtnCancel'); $BtnOpen = $win.FindName('BtnOpen')
$CmbBase = $win.FindName('CmbBase');   $ChkAuto = $win.FindName('ChkAuto')

$WorkDir = Join-Path $env:USERPROFILE 'govecho_build'
if (-not $Builder) { $Builder = Join-Path $PSScriptRoot 'build_windows.ps1' }

function Set-Progress([double]$pct, [string]$phase) {
    if ($pct -lt 0) { $pct = 0 }; if ($pct -gt 100) { $pct = 100 }
    $Bar.Value = $pct
    $TxtPct.Text = "$([math]::Round($pct))%"
    if ($phase) { $TxtPhase.Text = $phase }
}
function Add-Log([string]$s) {
    if (-not $s) { return }
    $TxtLog.AppendText($s + "`r`n")
    $TxtLog.ScrollToEnd()
}

$job = $null
$lastPct = 0.0

$BtnRun.Add_Click({
    if ($job) { return }
    $TxtLog.Clear(); Set-Progress 1 'Запуск...'
    $BtnRun.IsEnabled = $false; $BtnCancel.IsEnabled = $true
    $baseSel = $CmbBase.SelectedItem.Content
    $args = @('-NoProfile','-ExecutionPolicy','Bypass','-File', $Builder,
              '-GuiProtocol', '-Base', $baseSel)
    if ($ChkAuto.IsChecked) { $args += '-AutoInstall' }
    $job = Start-Job -ScriptBlock {
        param($b, $a)
        # внутри фонового задания: запускаем билдер и строчим stdout построчно
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $exe = if (Get-Command pwsh -EA SilentlyContinue) { 'pwsh' } else { 'powershell' }
        $psi.FileName = $exe
        $psi.Arguments = ($a | ForEach-Object { if ($_ -match '\s') { "'$_'" } else { $_ } }) -join ' '
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError  = $true
        $psi.UseShellExecute = $false
        $p = [System.Diagnostics.Process]::Start($psi)
        while (-not $p.StandardOutput.EndOfStream) {
            Write-Output $p.StandardOutput.ReadLine()
        }
        while (-not $p.StandardError.EndOfStream) {
            Write-Output ("ERR|" + $p.StandardError.ReadLine())
        }
        $p.WaitForExit()
        Write-Output ("EXIT|" + $p.ExitCode)
    } -ArgumentList $Builder, $args
    Add-Log "Сборка запущена (база: $baseSel)."
})

$BtnCancel.Add_Click({
    if ($job) { Stop-Job $job; Add-Log 'Отменено пользователем.'; Set-Progress 0 'Отменено' }
})
$BtnOpen.Add_Click({
    if (-not (Test-Path $WorkDir)) { New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null }
    Start-Process explorer.exe $WorkDir
})

# ---------- таймер опроса задания ----------
$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromMilliseconds(400)
$timer.Add_Tick({
    if (-not $job) { return }
    $out = Receive-Job $job
    foreach ($line in @($out)) {
        $s = "$line"
        if ($s -like 'PROGRESS|*') {
            $parts = $s.Split('|')
            $pct = 0.0; [double]::TryParse($parts[1], [ref]$pct) | Out-Null
            $phase = if ($parts.Length -gt 2) { $parts[2] } else { '' }
            # плавная анимация к новому значению
            Set-Progress $pct $phase; $lastPct = $pct
            Add-Log "[$([math]::Round($pct))%] $phase"
        } elseif ($s -like 'ERR|*') {
            Add-Log ('⚠ ' + $s.Substring(4))
        } elseif ($s -like 'EXIT|*') {
            $code = [int]($s.Split('|')[1])
            $timer.Stop()
            $BtnRun.IsEnabled = $true; $BtnCancel.IsEnabled = $false
            if ($code -eq 0) {
                Set-Progress 100 '✓ Сборка завершена!'
                $TxtHint.Text = "ISO готов в папке: $WorkDir"
                Add-Log '=== ГОТОВО. Запись на флешку — на ваш выбор (Rufus/Ventoy/balenaEtcher). ==='
                try { Start-Process explorer.exe ("'/select," + (Join-Path $WorkDir ((Get-ChildItem $WorkDir -Filter '*.iso' -EA SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1).FullName)) + "'") } catch {}
            } else {
                Set-Progress $lastPct '✖ Сборка завершилась с ошибкой (код ' + $code + ')'
                Add-Log "Ошибка. Код выхода: $code"
            }
            Remove-Job $job -Force -EA SilentlyContinue; $job = $null
        } elseif ($s) {
            Add-Log $s
        }
    }
    if ($job -and $job.State -in 'Failed','Stopped' -and $null -eq $job) { }
})
$win.Add_Closed({ if ($script:job) { Stop-Job $script:job -EA SilentlyContinue } })
$TxtHint.Text = 'Подсказка: сборка скачивает базовый ISO Ubuntu/Debian (~3-5 ГБ), интегрирует слой Govecho и пересобирает образ. ISO никуда не записывается автоматически.'
$timer.Start()
$win.ShowDialog() | Out-Null
