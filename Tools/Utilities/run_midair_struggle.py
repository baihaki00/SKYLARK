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

-- 1. Clear arena for a clean mid-air 1v1 long-range power struggle
for _, child in ipairs(qFolder:GetChildren()) do
    if child:IsA("Model") and child:FindFirstChild("Humanoid") then
        child:Destroy()
    end
end

-- 2. Spawn two Quins 52 studs apart elevated in mid-air (Y = 28 studs, 45-80 studs threshold)
local posFire = Vector3.new(-26.0, 28.0, -38.0)
local posWater = Vector3.new(26.0, 28.0, -38.0)

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

-- Elevate explicitly to 28 studs in mid-air facing each other across the 52-stud span
fireHRP.CFrame = CFrame.lookAt(posFire, Vector3.new(posWater.X, posFire.Y, posWater.Z))
waterHRP.CFrame = CFrame.lookAt(posWater, Vector3.new(posFire.X, posWater.Y, posFire.Z))

-- 3. Trigger Power Struggle between the two combatants
fireQuin:SetAttribute("TargetQuin", waterQuin.Name)
fireQuin:SetAttribute("ForceState", "BeamStruggle")

waterQuin:SetAttribute("TargetQuin", fireQuin.Name)
waterQuin:SetAttribute("ForceState", "BeamStruggle")

-- 4. Long-range camera framing: pulled back to Z = 14 to capture the entire 52-stud beam span cleanly
Workspace:SetAttribute("HideSpectatorHUD", true)
Workspace:SetAttribute("CameraOverrideActive", true)
Workspace:SetAttribute("CamPosX", 0.0)
Workspace:SetAttribute("CamPosY", 32.0)
Workspace:SetAttribute("CamPosZ", 14.0)
Workspace:SetAttribute("CamLookX", 0.0)
Workspace:SetAttribute("CamLookY", 28.0)
Workspace:SetAttribute("CamLookZ", -38.0)

local dist = (fireHRP.Position - waterHRP.Position).Magnitude
return string.format("Spawned %s and %s in MID-AIR at Y=%.1f (%.1f studs apart). Long-range threshold and white sphere surge engaged.", fireQuin.Name, waterQuin.Name, posFire.Y, dist)
"""

res = client.execute_luau(spawn_code, datamodel_type="Server")
print("Spawn result:", res)

# Monitor progress across mid-air power up, ignition, tug-of-war, and breach
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

local clashNode = Workspace:FindFirstChild("BeamClashNode_Quin_FireStriker") or Workspace:FindFirstChild("BeamClashNode_Quin_WaterTanker")

local leader = (fire:GetAttribute("BeamStruggleRole") == "Leader" and fire) or (water:GetAttribute("BeamStruggleRole") == "Leader" and water) or fire
local offset = leader:GetAttribute("ClashNodeOffset") or 0.0
local subPhase = leader:GetAttribute("StruggleSubPhase") or fire:GetAttribute("StruggleSubPhase") or water:GetAttribute("StruggleSubPhase") or "Unknown"
local angle = leader:GetAttribute("ClashAngle") or 0.0

return string.format("Phase:%s | Ang:%.2frad | Off:%.2f | Fire:[%.1f,%.1f,%.1f] (E:%d) | Water:[%.1f,%.1f,%.1f] (E:%d) | Node:%s",
    subPhase,
    angle,
    offset,
    fireHRP and fireHRP.Position.X or 0, fireHRP and fireHRP.Position.Y or 0, fireHRP and fireHRP.Position.Z or 0,
    fire:GetAttribute("Energy") or 0,
    waterHRP and waterHRP.Position.X or 0, waterHRP and waterHRP.Position.Y or 0, waterHRP and waterHRP.Position.Z or 0,
    water:GetAttribute("Energy") or 0,
    clashNode and string.format("[%.1f,%.1f,%.1f]", clashNode.Position.X, clashNode.Position.Y, clashNode.Position.Z) or "None"
)
"""

print("\n--- Tracking 52-Stud Mid-Air Power Struggle & Impact Dynamics ---")
captured_struggle = False
captured_surge = False
captured_launch = False
surge_time = 0
start_track = time.time()

for i in range(25):
    t_res = client.execute_luau(telemetry_code, datamodel_type="Server")
    t_text = t_res.get("result", {}).get("content", [{}])[0].get("text", "")
    elapsed = time.time() - start_track
    print(f"[{elapsed:4.2f}s] {t_text}")

    # 1. Capture during peak active 52-stud long-range struggle
    if elapsed >= 1.8 and not captured_struggle and "TugOfWar" in t_text:
        captured_struggle = True
        print("--> Capturing active 52-Stud Long-Range Struggle screenshot...")
        cap_res = client.call_tool("screen_capture", {
            "studio_id": client.studio_id,
            "capture_id": "ScreenCapture_LongRange_Struggle"
        })
        artifact_path = r"C:\Users\User\.gemini\antigravity\brain\742ec506-bcb9-44da-93cc-dfae76d1bdaf\screen_capture_longrange_struggle.png"
        if cap_res and not cap_res.get("isError", False):
            content = cap_res.get("result", {}).get("content", [])
            for item in content:
                if item.get("type") == "image":
                    img_data = item.get("data", "")
                    with open(artifact_path, "wb") as f:
                        f.write(base64.b64decode(img_data))
                    print(f"[OK] Saved long-range struggle screenshot to {artifact_path} ({len(img_data)} bytes)")
                    break

    # Parse minimum energy to anticipate breach
    min_energy = 100
    if "(E:" in t_text:
        try:
            parts = t_text.split("(E:")
            e1 = int(parts[1].split(")")[0])
            e2 = int(parts[2].split(")")[0])
            min_energy = min(e1, e2)
        except Exception:
            pass

    # 2. Capture when Breach triggers: white sphere surging into loser's chest!
    if ("Breach" in t_text or min_energy <= 8 or elapsed >= 4.3) and captured_struggle and not captured_surge:
        captured_surge = True
        surge_time = elapsed
        print("--> Capturing White Clash Node Surge & Direct Impact screenshot...")
        cap_res = client.call_tool("screen_capture", {
            "studio_id": client.studio_id,
            "capture_id": "ScreenCapture_Breach_Impact_Surge"
        })
        artifact_path = r"C:\Users\User\.gemini\antigravity\brain\742ec506-bcb9-44da-93cc-dfae76d1bdaf\screen_capture_breach_impact_surge.png"
        if cap_res and not cap_res.get("isError", False):
            content = cap_res.get("result", {}).get("content", [])
            for item in content:
                if item.get("type") == "image":
                    img_data = item.get("data", "")
                    with open(artifact_path, "wb") as f:
                        f.write(base64.b64decode(img_data))
                    print(f"[OK] Saved breach impact surge screenshot to {artifact_path} ({len(img_data)} bytes)")
                    break

    # 3. Capture during sustained knockback launch (0.25s-0.35s after surge)
    if captured_surge and not captured_launch and (elapsed - surge_time >= 0.25):
        captured_launch = True
        print("--> Capturing Sustained Pierce & Airborne Knockback Launch screenshot...")
        cap_res = client.call_tool("screen_capture", {
            "studio_id": client.studio_id,
            "capture_id": "ScreenCapture_Sustained_Pierce_Launch"
        })
        artifact_path = r"C:\Users\User\.gemini\antigravity\brain\742ec506-bcb9-44da-93cc-dfae76d1bdaf\screen_capture_sustained_pierce_launch.png"
        if cap_res and not cap_res.get("isError", False):
            content = cap_res.get("result", {}).get("content", [])
            for item in content:
                if item.get("type") == "image":
                    img_data = item.get("data", "")
                    with open(artifact_path, "wb") as f:
                        f.write(base64.b64decode(img_data))
                    print(f"[OK] Saved sustained pierce launch screenshot to {artifact_path} ({len(img_data)} bytes)")
                    break

    time.sleep(0.25)

print("--- Timeline complete ---\n")
