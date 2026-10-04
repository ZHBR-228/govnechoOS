@echo off
chcp 866 >nul 2>nul
rem GovechoOS Builder - двойной щелчок открывает окно с прогрессом сборки (ZHBR-228, MIT)
rem Консольный режим без окна: build_windows.bat -Console [...параметры билдера]
setlocal
cd /d "%~dp0"
if "%1"=="-Console" ( shift & goto console )
where pwsh >nul 2>nul && (pwsh -NoProfile -ExecutionPolicy Bypass -File scripts\build_gui.ps1 %*) || (powershell -NoProfile -ExecutionPolicy Bypass -File scripts\build_gui.ps1 %*)
if errorlevel 1 (
    echo.
    echo [govechoOS] Окно не открылось? Запустите вручную из PowerShell:
    echo     powershell -NoProfile -ExecutionPolicy Bypass -File scripts\build_gui.ps1
    pause
)
goto :eof
:console
where pwsh >nul 2>nul && (pwsh -NoProfile -ExecutionPolicy Bypass -File scripts\build_windows.ps1 %*) || (powershell -NoProfile -ExecutionPolicy Bypass -File scripts\build_windows.ps1 %*)
endlocal
