import os
import sys
import time
import base64

sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..")))
from Tools.Utilities.roblox_client import RobloxStudioClient

ARTIFACT_DIR = r"C:\Users\User\.gemini\antigravity\brain\742ec506-bcb9-44da-93cc-dfae76d1bdaf"

client = RobloxStudioClient()
cleanup_code = """
local SSS = game:GetService("ServerScriptService")
require(SSS.QuinSpawner).cleanAll()
"""
client.execute_luau(cleanup_code, datamodel_type="Server")
time.sleep(0.3)

spawn_code = """
local SSS = game:GetService("ServerScriptService")
local QS = require(SSS.QuinSpawner)
local q1 = QS.spawn("TypeA", Vector3.new(-10, 2.05, 0), "TeamAlpha")
local q2 = QS.spawn("TypeC", Vector3.new(10, 2.05, 0), "TeamBeta")
local q3 = QS.spawn("TypeB", Vector3.new(-5, 2.05, 12), "TeamAlpha")
local q4 = QS.spawn("TypeD", Vector3.new(5, 2.05, 12), "TeamBeta")
workspace:SetAttribute("MatchStarted", true)
return "Spawned"
"""
client.execute_luau(spawn_code, datamodel_type="Server")
time.sleep(1.5)

res = client.call_tool("screen_capture", {
    "studio_id": client.studio_id,
    "capture_id": "screen_capture_live_survival_combat",
    "camera_position": [0, 8, -22],
    "look_at_position": [0, 3, 6]
})
print("Res keys:", res.keys())
content = res.get("result", {}).get("content", [])
print("Content count:", len(content))
for item in content:
    print("Item type:", item.get("type"))
    if item.get("type") == "image":
        fpath = os.path.join(ARTIFACT_DIR, "screen_capture_live_survival_combat.png")
        with open(fpath, "wb") as f:
            f.write(base64.b64decode(item["data"]))
        print("Captured combat action to", fpath)
