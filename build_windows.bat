@echo off
rem Govecho Builder (Linux-editsiya) - otkryvaet GUI s progressom.
set "PS=powershell.exe"
%PS% -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\govshell.ps1" -Edition linux
if errorlevel 1 (
  echo.
  echo Ne udalos zapustit GUI. Ruchnoy variant:
  echo   %PS% -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\govshell.ps1" -Edition linux
  pause
)
