import time
import json
import os
import sys
import base64

sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..")))
from Tools.Utilities.roblox_client import RobloxStudioClient

def main():
    client = RobloxStudioClient()
    print("Connected to Studio ID:", client.studio_id)

    # 1. Setup Beam Struggle Scene
    setup_beam = """
    local Workspace = game:GetService("Workspace")
    local ServerScriptService = game:GetService("ServerScriptService")
    local QuinSpawner = require(ServerScriptService:WaitForChild("QuinSpawner"))

    local qFolder = Workspace:FindFirstChild("QuinServer") or Workspace
    for _, child in ipairs(qFolder:GetChildren()) do
        if child.Name:find("SpectacleCap_") then
            child:Destroy()
        end
    end

    -- Spawn Fire vs Water Quins elevated at Y = 22 studs, 22 studs apart
    local fireQ = QuinSpawner.spawn("TypeA", Vector3.new(-11, 22, -38), "BeamTeamA", "Fire")
    fireQ.Name = "SpectacleCap_FireFighter"
    fireQ:SetAttribute("Element", "Fire")
    fireQ:SetAttribute("Energy", 90)

    local waterQ = QuinSpawner.spawn("TypeD", Vector3.new(11, 22, -38), "BeamTeamB", "Water")
    waterQ.Name = "SpectacleCap_WaterFighter"
    waterQ.PrimaryPart.CFrame = CFrame.lookAt(waterQ.PrimaryPart.Position, fireQ.PrimaryPart.Position)
    waterQ.Name = "SpectacleCap_WaterFighter"
    waterQ:SetAttribute("Element", "Water")
    waterQ:SetAttribute("Energy", 90)

    task.wait(0.2)

    fireQ.PrimaryPart.CFrame = CFrame.lookAt(fireQ.PrimaryPart.Position, waterQ.PrimaryPart.Position)
    waterQ.PrimaryPart.CFrame = CFrame.lookAt(waterQ.PrimaryPart.Position, fireQ.PrimaryPart.Position)

    -- Trigger Beam Struggle
    fireQ:SetAttribute("TargetQuin", waterQ.Name)
    fireQ:SetAttribute("ForceState", "BeamStruggle")
    waterQ:SetAttribute("TargetQuin", fireQ.Name)
    waterQ:SetAttribute("ForceState", "BeamStruggle")

    return "Beam Struggle Scene Active"
    """

    res1 = client.execute_luau(setup_beam, datamodel_type="Server")
    print("Beam setup:", res1)
    time.sleep(0.8) # Wait for beams, particles, and clash node to emerge

    # Capture Beam Struggle Screen
    print("Capturing Beam Struggle screenshot...")
    cam_pos_beam = [0, 24, -12] # Looking south towards center (0, 22, -38)
    look_pos_beam = [0, 22, -38]

    cap_res1 = client.call_tool("screen_capture", {
        "studio_id": client.studio_id,
        "capture_id": "ScreenCapture_Beam_Struggle",
        "camera_position": cam_pos_beam,
        "look_at_position": look_pos_beam
    })

    artifact_beam = r"C:\Users\User\.gemini\antigravity\brain\742ec506-bcb9-44da-93cc-dfae76d1bdaf\screen_capture_beam_struggle.png"
    if cap_res1 and not cap_res1.get("isError", False):
        content = cap_res1.get("result", {}).get("content", [])
        for item in content:
            if item.get("type") == "image":
                img_data = item.get("data", "")
                with open(artifact_beam, "wb") as f:
                    f.write(base64.b64decode(img_data))
                print(f"[OK] Saved Beam Struggle screenshot to {artifact_beam} ({len(img_data)} bytes)")
                break

    # 2. Cleanup and Setup Aura Farm Scene
    setup_aura = """
    local Workspace = game:GetService("Workspace")
    local ServerScriptService = game:GetService("ServerScriptService")
    local QuinSpawner = require(ServerScriptService:WaitForChild("QuinSpawner"))

    local qFolder = Workspace:FindFirstChild("QuinServer") or Workspace
    for _, child in ipairs(qFolder:GetChildren()) do
        if child.Name:find("SpectacleCap_") then
            child:Destroy()
        end
    end

    -- Spawn Showoff Fire Quin flaring elemental aura on ground
    local showoffQ = QuinSpawner.spawn("TypeB", Vector3.new(0, 6.5, -38), "AuraTeam", "Fire")
    showoffQ.Name = "SpectacleCap_AuraShowoff"
    showoffQ:SetAttribute("Quirky", "Showoff")
    showoffQ:SetAttribute("Pers_Confidence", 0.95)
    showoffQ:SetAttribute("ForceState", "AuraFarm")

    return "Aura Farm Scene Active"
    """

    res2 = client.execute_luau(setup_aura, datamodel_type="Server")
    print("Aura setup:", res2)
    time.sleep(0.8)

    # Capture Aura Farm Screen
    print("Capturing Aura Farm screenshot...")
    cam_pos_aura = [6, 9.5, -28] # Close 3/4 angle looking at Quin
    look_pos_aura = [0, 8.0, -38]

    cap_res2 = client.call_tool("screen_capture", {
        "studio_id": client.studio_id,
        "capture_id": "ScreenCapture_Aura_Farm",
        "camera_position": cam_pos_aura,
        "look_at_position": look_pos_aura
    })

    artifact_aura = r"C:\Users\User\.gemini\antigravity\brain\742ec506-bcb9-44da-93cc-dfae76d1bdaf\screen_capture_aura_farming.png"
    if cap_res2 and not cap_res2.get("isError", False):
        content = cap_res2.get("result", {}).get("content", [])
        for item in content:
            if item.get("type") == "image":
                img_data = item.get("data", "")
                with open(artifact_aura, "wb") as f:
                    f.write(base64.b64decode(img_data))
                print(f"[OK] Saved Aura Farm screenshot to {artifact_aura} ({len(img_data)} bytes)")
                break

    # Final cleanup of test quins
    cleanup_code = """
    local Workspace = game:GetService("Workspace")
    local qFolder = Workspace:FindFirstChild("QuinServer") or Workspace
    for _, child in ipairs(qFolder:GetChildren()) do
        if child.Name:find("SpectacleCap_") then
            child:Destroy()
        end
    end
    """
    client.execute_luau(cleanup_code, datamodel_type="Server")
    client.close()

if __name__ == "__main__":
    main()
