@echo off
rem Uninstall shunti IME (asks for administrator permission via UAC)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1" -Uninstall
echo.
pause
