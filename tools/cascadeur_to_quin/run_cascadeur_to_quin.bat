@echo off
title Cascadeur to Quin Converter
color 0A
echo =======================================================
echo      CASCADEUR FBX TO QUIN CONVERTER (Roblox, 0.044)
echo =======================================================
echo.
echo Drop Cascadeur FBX files in this folder, then run this.
echo Each one gets a ^<Name^>_Quin[x0.044].fbx to import into Roblox.
echo.

python "%~dp0_converter\cascadeur_to_quin.py" %*

echo.
pause
