@echo off
title Cascadeur to Quin Converter
color 0A
echo =======================================================
echo      CASCADEUR FBX TO QUIN CONVERTER (Roblox, 0.044)
echo =======================================================
echo.
echo Drop Cascadeur FBX files in this folder, then run this.
echo Each one gets a ^<Name^>_CascadeurQuin folder: _Quin, _Quin_InPlace,
echo and the mirrored (left ^<-^> right) _Quin_Mirror, _Quin_Mirror_InPlace.
echo Import with Rest Pose Source: Imported Rig.
echo.

python "%~dp0_converter\cascadeur_to_quin.py" %*

echo.
pause
