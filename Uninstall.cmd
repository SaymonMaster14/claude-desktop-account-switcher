@echo off
rem Double-click to uninstall. Your saved accounts are kept (see README to delete them too).
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0uninstall.ps1"
echo.
pause
