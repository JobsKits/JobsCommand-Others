@echo off
setlocal DisableDelayedExpansion
chcp 65001 >nul
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0【WindowsOS】URL去乱码.ps1" %*
set "jobs_exit=%errorlevel%"
if not "%jobs_exit%"=="0" echo Failed. Exit code: %jobs_exit%
if "%~1"=="" pause
exit /b %jobs_exit%
