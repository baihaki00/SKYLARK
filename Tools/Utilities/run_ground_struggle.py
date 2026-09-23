import os
import sys
import time
import base64

current_dir = os.path.dirname(os.path.abspath(__file__))
if current_dir not in sys.path:
    sys.path.insert(0, current_dir)

from roblox_client import RobloxStudioClient

client = RobloxStudioClient()
print("Connected to Studio ID:", client.studio_id)

spawn_code = """
local Workspace = game:GetService("Workspace")
local ServerScriptService = game:GetService("ServerScriptService")
local QuinSpawner = require(ServerScriptService:WaitForChild("QuinSpawner"))

local qFolder = Workspace:FindFirstChild("QuinServer") or Workspace

-- 1. Clear arena for a clean 1v1 ground power struggle
for _, child in ipairs(qFolder:GetChildren()) do
    if child:IsA("Model") and child:FindFirstChild("Humanoid") then
        child:Destroy()
    end
end

-- 2. Spawn two Quins 32 studs apart on the arena ground (20-50 studs range)
local posFire = Vector3.new(-16.0, 6.35, -38.0)
local posWater = Vector3.new(16.0, 6.35, -38.0)

local fireQuin = QuinSpawner.spawn("TypeA", posFire, "TeamRed", "Fire")
fireQuin.Name = "Quin_FireStriker"
fireQuin:SetAttribute("Element", "Fire")
fireQuin:SetAttribute("Energy", 100)
fireQuin:SetAttribute("CurrentConfidence", 0.70)

local waterQuin = QuinSpawner.spawn("TypeD", posWater, "TeamBlue", "Water")
waterQuin.Name = "Quin_WaterTanker"
waterQuin:SetAttribute("Element", "Water")
waterQuin:SetAttribute("Energy", 100)
waterQuin:SetAttribute("CurrentConfidence", 0.70)

task.wait(0.25)

local fireHRP = fireQuin:FindFirstChild("HumanoidRootPart")
local waterHRP = waterQuin:FindFirstChild("HumanoidRootPart")

if not fireHRP or not waterHRP then
    return "Error: Missing root parts"
end

-- Face each other directly across the 32-stud gap
fireHRP.CFrame = CFrame.lookAt(fireHRP.Position, Vector3.new(waterHRP.Position.X, fireHRP.Position.Y, waterHRP.Position.Z))
waterHRP.CFrame = CFrame.lookAt(waterHRP.Position, Vector3.new(fireHRP.Position.X, waterHRP.Position.Y, fireHRP.Position.Z))

-- 3. Trigger Power Struggle between the two combatants
fireQuin:SetAttribute("TargetQuin", waterQuin.Name)
fireQuin:SetAttribute("ForceState", "BeamStruggle")

waterQuin:SetAttribute("TargetQuin", fireQuin.Name)
waterQuin:SetAttribute("ForceState", "BeamStruggle")

-- 4. Authoritative camera setup: framed 32 studs away looking at center
Workspace:SetAttribute("HideSpectatorHUD", true)
Workspace:SetAttribute("CameraOverrideActive", true)
Workspace:SetAttribute("CamPosX", 0.0)
Workspace:SetAttribute("CamPosY", 8.5)
Workspace:SetAttribute("CamPosZ", -6.0)
Workspace:SetAttribute("CamLookX", 0.0)
Workspace:SetAttribute("CamLookY", 5.5)
Workspace:SetAttribute("CamLookZ", -38.0)

local dist = (fireHRP.Position - waterHRP.Position).Magnitude
return string.format("Spawned %s and %s %.1f studs apart on ground. Multi-phase power struggle engaged.", fireQuin.Name, waterQuin.Name, dist)
"""

res = client.execute_luau(spawn_code, datamodel_type="Server")
print("Spawn result:", res)

# Monitor progress across power up, ignition, tug-of-war, and breach
telemetry_code = """
local Workspace = game:GetService("Workspace")
local qFolder = Workspace:FindFirstChild("QuinServer") or Workspace
local fire = qFolder:FindFirstChild("Quin_FireStriker")
local water = qFolder:FindFirstChild("Quin_WaterTanker")

if not fire or not water then return "Quins missing" end

local fireHRP = fire:FindFirstChild("HumanoidRootPart")
local waterHRP = water:FindFirstChild("HumanoidRootPart")
local fireHum = fire:FindFirstChildOfClass("Humanoid")
local waterHum = water:FindFirstChildOfClass("Humanoid")
local dist = fireHRP and waterHRP and (fireHRP.Position - waterHRP.Position).Magnitude or 0

local clashNode = Workspace:FindFirstChild("BeamClashNode_Quin_FireStriker") or Workspace:FindFirstChild("BeamClashNode_Quin_WaterTanker")

local leader = fire:GetAttribute("BeamStruggleRole") == "Leader" and fire or water
local offset = leader:GetAttribute("ClashNodeOffset") or 0.0
local subPhase = fire:GetAttribute("StruggleSubPhase") or "Unknown"

return string.format("Phase:%s | Off:%.2f | FireState:%s (HP:%d, Mana:%d) | WaterState:%s (HP:%d, Mana:%d) | Node:%s",
    subPhase,
    offset,
    tostring(fire:GetAttribute("CurrentState")),
    fireHum and fireHum.Health or 0,
    fire:GetAttribute("Energy") or 0,
    tostring(water:GetAttribute("CurrentState")),
    waterHum and waterHum.Health or 0,
    water:GetAttribute("Energy") or 0,
    clashNode and string.format("%.1f", clashNode.Position.X) or "None"
)
"""

print("\n--- Tracking Power Struggle Multi-Phase Timeline ---")
captured_active = False
start_track = time.time()

for i in range(16):
    t_res = client.execute_luau(telemetry_code, datamodel_type="Server")
    t_text = t_res.get("result", {}).get("content", [{}])[0].get("text", "")
    elapsed = time.time() - start_track
    print(f"[{elapsed:4.2f}s] {t_text}")

    # Capture at ~1.4s during peak dynamic tug-of-war
    if elapsed >= 1.3 and not captured_active and "TugOfWar" in t_text:
        captured_active = True
        print("--> Capturing active Tug-of-War oscillation screenshot...")
        cap_res = client.call_tool("screen_capture", {
            "studio_id": client.studio_id,
            "capture_id": "ScreenCapture_Active_TugOfWar"
        })
        artifact_path = r"C:\Users\User\.gemini\antigravity\brain\742ec506-bcb9-44da-93cc-dfae76d1bdaf\screen_capture_ground_power_struggle.png"
        if cap_res and not cap_res.get("isError", False):
            content = cap_res.get("result", {}).get("content", [])
            for item in content:
                if item.get("type") == "image":
                    img_data = item.get("data", "")
                    with open(artifact_path, "wb") as f:
                        f.write(base64.b64decode(img_data))
                    print(f"[OK] Saved active struggle screenshot to {artifact_path} ({len(img_data)} bytes)")
                    break

    time.sleep(0.25)

print("--- Timeline complete ---\n")
