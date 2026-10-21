@echo off
title Quin body export (Blender -> Roblox FBX)
color 0A
echo =======================================================
echo      QUIN BODY EXPORT  (rigged .blend -^> Roblox FBX)
echo =======================================================
echo Drag a rigged .blend (e.g. BASE2_rigged_body_v3.blend) onto this file,
echo or run it to export the newest *_rigged*.blend in this folder.
echo.
set "BLEND=%~1"
if "%BLEND%"=="" for /f "delims=" %%F in ('dir /b /o-d "%~dp0*rigged*.blend" 2^>nul') do if not defined BLEND set "BLEND=%~dp0%%F"
if "%BLEND%"=="" ( echo No rigged .blend found. & pause & exit /b )
for %%F in ("%BLEND%") do set "NAME=%%~nF"
set "OUT=D:\SKYLARK\QUIN_DESIGN\export\%NAME%.fbx"
set "BLENDER=C:\Program Files\Blender Foundation\Blender 5.1\blender.exe"
echo Exporting %BLEND%
echo        to %OUT%
"%BLENDER%" -b --python "%~dp0scripts\export_quin.py" -- "%BLEND%" "%OUT%" | findstr /r "^MESH EXPORTED Error"
echo.
echo Next: Studio - 3D Importer - %NAME%.fbx (Rig Type Custom, Rest Pose Imported Rig),
echo then ask Claude to run build_quin_template.lua on it (QuinMale / QuinFemale).
pause
