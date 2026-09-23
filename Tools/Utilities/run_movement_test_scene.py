import sys
import json
import os
import base64
import time

sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..")))
from Tools.Utilities.roblox_client import RobloxStudioClient

ARTIFACT_DIR = r"C:\Users\User\.gemini\antigravity\brain\742ec506-bcb9-44da-93cc-dfae76d1bdaf"

client = RobloxStudioClient()
print("Connected to Studio ID:", client.studio_id)

setup_code = """
local Workspace = game:GetService("Workspace")
local ServerScriptService = game:GetService("ServerScriptService")
local QuinSpawner = require(ServerScriptService.QuinSpawner)

-- Clean existing
QuinSpawner.cleanAll()
Workspace:SetAttribute("CurrentMode", "MovementTestArena")

-- Position at runandjumpcheckpoint1: (30.5, 2.02, 568.5)
-- Hurdle track goes towards runandjumpcheckpoint2: (24.5, 2.02, 1038.5)
local p1 = Vector3.new(30.5, 4.5, 568.5)
local p2 = Vector3.new(24.5, 4.5, 1038.5)

local runner = QuinSpawner.spawn("TypeA", p1, "TeamAlpha", "Fire", p2)
runner.Name = "QuinRunner_Strike1"

local target = QuinSpawner.spawn("TypeB", p2, "TeamBeta", "Earth", p1)
target.Name = "QuinTarget_Strike1"

local humB = target:FindFirstChildOfClass("Humanoid")
if humB then
    humB.WalkSpeed = 0
    humB.Health = 99999
end

runner:SetAttribute("CurrentTarget", target.Name)
runner:SetAttribute("TargetQuin", target.Name)
runner:SetAttribute("InitialPacingOverride", "ContinuousSprint")
runner:SetAttribute("EnableProjectileJump", false)

local hrpA = runner:FindFirstChild("HumanoidRootPart")
local hrpB = target:FindFirstChild("HumanoidRootPart")

return string.format("Spawned %s at %s, %s at %s", runner.Name, tostring(hrpA and hrpA.Position), target.Name, tostring(hrpB and hrpB.Position))
"""

res = client.execute_luau(setup_code, datamodel_type="Edit")
print("Setup result:", res.get("result", {}).get("content", [{}])[0].get("text", ""))

# Take screenshot looking down the hurdle track from behind the runner at checkpoint 1
time.sleep(0.5)
cam_pos = [30.5, 12.0, 550.0] # 18 studs behind runner, slightly elevated
look_at = [29.5, 6.0, 650.0]  # Looking forward along hurdle track

cap_res = client.call_tool("screen_capture", {
    "studio_id": client.studio_id,
    "capture_id": "movement_test_arena_track",
    "camera_position": cam_pos,
    "look_at_position": look_at
})

if cap_res and not cap_res.get("isError", False):
    items = cap_res.get("result", {}).get("content", [])
    for it in items:
        if it.get("type") == "image":
            data = it.get("data", "")
            fpath = os.path.join(ARTIFACT_DIR, "screen_capture_movement_test_arena.png")
            with open(fpath, "wb") as f:
                f.write(base64.b64decode(data))
            print(f"[OK] Saved track screenshot to {fpath} ({len(data)} bytes)")
            break

client.close()
