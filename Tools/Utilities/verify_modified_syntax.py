import os
import sys
import json

sys.path.append(os.path.abspath("Tools/Utilities"))
from roblox_client import RobloxStudioClient

files_to_check = [
    "CombatConfig.lua",
    "LocomotionModule.lua",
    "ChaseState.lua",
    "RetreatState.lua",
    "FightState.lua",
    "IdleState.lua",
    "SlideState.lua",
    "DashState.lua",
    "GameModeManager.lua"
]

client = RobloxStudioClient()
all_ok = True

for fname in files_to_check:
    fpath = os.path.abspath(fname)
    if not os.path.exists(fpath):
        print(f"[MISSING] {fname}")
        all_ok = False
        continue
    with open(fpath, "r", encoding="utf-8") as f:
        src = f.read()

    # Pass src as JSON string
    payload = json.dumps(src)
    code = f"""
    local HttpService = game:GetService("HttpService")
    local src = HttpService:JSONDecode({json.dumps(payload)})
    local fn, err = loadstring(src)
    if not fn then
        return "SYNTAX ERROR: " .. tostring(err)
    else
        return "OK"
    end
    """
    res = client.execute_luau(code, datamodel_type="Edit")
    out = res.get("result", {}).get("content", [{}])[0].get("text", "")
    if out == "OK":
        print(f"[OK] {fname}")
    else:
        print(f"[FAIL] {fname}: {out}")
        all_ok = False

client.close()
if all_ok:
    print("\nALL MODIFIED FILES PASSED SYNTAX CHECK!")
else:
    print("\nSOME FILES FAILED SYNTAX CHECK!")
