@echo off
setlocal
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0build-physical.ps1" %*
exit /b %ERRORLEVEL%
