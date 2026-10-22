@echo off
title Quin body export (Blender -> Roblox FBX, versioned)
color 0A
echo =======================================================
echo   QUIN BODY EXPORT  (rigged .blend -^> versioned Roblox FBX)
echo =======================================================
echo Drag a rigged .blend onto this file. A name with "Female" in it
echo exports as QuinFemale_vN, anything else as QuinMale_vN
echo (QUIN_DESIGN\export\Female or \Male, N = next version).
echo.
if "%~1"=="" ( echo No .blend given: drag one onto this file. & pause & exit /b )
python "%~dp0scripts\export_versioned.py" "%~1"
echo.
pause
