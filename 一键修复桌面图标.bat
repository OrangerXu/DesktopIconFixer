@echo off
chcp 65001 >nul
title 一键修复桌面图标
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Fix-DesktopIcons.ps1" %*
echo.
pause
