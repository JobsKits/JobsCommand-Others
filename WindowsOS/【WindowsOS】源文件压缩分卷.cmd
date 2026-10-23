@echo off
setlocal
chcp 65001 >nul
powershell.exe -NoLogo -NoProfile -File "%~dp0【WindowsOS】源文件压缩分卷.ps1" %*
set "jobs_exit=%errorlevel%"
if not "%jobs_exit%"=="0" echo Failed. Exit code: %jobs_exit%
if "%~1"=="" pause
exit /b %jobs_exit%
