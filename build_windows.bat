@echo off
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
