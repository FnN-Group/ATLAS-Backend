@echo off
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File ".\installer\build_installer.ps1" %*
endlocal
