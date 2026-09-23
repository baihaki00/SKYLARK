import sys
import os
import time
import base64
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from roblox_client import RobloxStudioClient

client = RobloxStudioClient()

# 1. Get Quin position and set camera override
code = """
local Workspace = game:GetService("Workspace")
local ghostFolder = Workspace:FindFirstChild("QuinGhost")
local g = ghostFolder and (ghostFolder:FindFirstChild("QuinA_Runner_Visual") or ghostFolder:GetChildren()[1])
if not g or not g.PrimaryPart then return "No ghost found" end

local p = g.PrimaryPart.Position
local camPos = Vector3.new(p.X, p.Y + 2.5, p.Z - 12)
local lookPos = Vector3.new(p.X, p.Y + 2.0, p.Z)

Workspace:SetAttribute("CamPosX", camPos.X)
Workspace:SetAttribute("CamPosY", camPos.Y)
Workspace:SetAttribute("CamPosZ", camPos.Z)
Workspace:SetAttribute("CamLookX", lookPos.X)
Workspace:SetAttribute("CamLookY", lookPos.Y)
Workspace:SetAttribute("CamLookZ", lookPos.Z)
Workspace:SetAttribute("CameraOverrideActive", true)

return string.format("Tracking %s at (%.1f, %.1f, %.1f)", g.Name, p.X, p.Y, p.Z)
"""

res = client.execute_luau(code, datamodel_type="Client")
print(res.get("result", {}).get("content", [{}])[0].get("text", ""))

# Wait a frame for client camera to update
time.sleep(0.3)

# Capture
res_cap = client.call_tool("screen_capture", {
    "studio_id": client.studio_id,
    "capture_id": "test_override_cam"
})

for item in res_cap.get("result", {}).get("content", []):
    if item.get("type") == "image":
        out_path = r"C:\Users\User\.gemini\antigravity\brain\742ec506-bcb9-44da-93cc-dfae76d1bdaf\test_override_cam.png"
        with open(out_path, "wb") as f:
            f.write(base64.b64decode(item["data"]))
        print("Captured override view to:", out_path)

# Reset camera override
reset_code = """
workspace:SetAttribute("CameraOverrideActive", false)
return "Camera override released"
"""
client.execute_luau(reset_code, datamodel_type="Client")
