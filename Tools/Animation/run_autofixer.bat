@echo off
title Mixamo FBX Auto-Fixer for Roblox
color 0A
echo =======================================================
echo         MIXAMO FBX AUTO-FIXER FOR ROBLOX (0.044)
echo =======================================================
echo.
echo Scanning folder for FBX files...
echo.

python "%~dp0autofixer.py"

echo.
echo =======================================================
echo Done! Output folders have been created.
echo =======================================================
echo.
pause
