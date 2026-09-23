import sys
import os
import base64
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from roblox_client import RobloxStudioClient

client = RobloxStudioClient()

# Hide HUD temporarily on client
hide_hud_code = """
local Players = game:GetService("Players")
local lp = Players.LocalPlayer
if lp and lp:FindFirstChild("PlayerGui") then
    for _, gui in ipairs(lp.PlayerGui:GetChildren()) do
        if gui:IsA("ScreenGui") and (gui.Name:find("HUD") or gui.Name:find("Spectator") or gui.Name:find("Quin")) then
            gui.Enabled = false
        end
    end
end
return "HUDs hidden"
"""
client.execute_luau(hide_hud_code, datamodel_type="Client")

# Get Quin position
pos_code = """
local Workspace = game:GetService("Workspace")
local ghostFolder = Workspace:FindFirstChild("QuinGhost")
local g = ghostFolder and ghostFolder:FindFirstChild("QuinA_Runner_Visual")
if g and g.PrimaryPart then
    local p = g.PrimaryPart.Position
    return string.format("%.1f,%.1f,%.1f", p.X, p.Y, p.Z)
end
return "none"
"""
res = client.execute_luau(pos_code, datamodel_type="Client")
pos_str = res.get("result", {}).get("content", [{}])[0].get("text", "")
print("Quin pos:", pos_str)

if pos_str != "none":
    x, y, z = [float(v) for v in pos_str.split(",")]
    # Frame camera directly looking horizontally at the Quin from 14 studs back
    cam = [x, y + 2, z - 14]
    look = [x, y + 1.5, z]
    res_cap = client.call_tool("screen_capture", {
        "studio_id": client.studio_id,
        "capture_id": "clean_quin_frame",
        "camera_position": cam,
        "look_at_position": look
    })
    for item in res_cap.get("result", {}).get("content", []):
        if item.get("type") == "image":
            out_path = r"C:\Users\User\.gemini\antigravity\brain\742ec506-bcb9-44da-93cc-dfae76d1bdaf\clean_quin_frame.png"
            with open(out_path, "wb") as f:
                f.write(base64.b64decode(item["data"]))
            print("Saved clean capture to:", out_path)

# Restore HUD
restore_hud_code = """
local Players = game:GetService("Players")
local lp = Players.LocalPlayer
if lp and lp:FindFirstChild("PlayerGui") then
    for _, gui in ipairs(lp.PlayerGui:GetChildren()) do
        if gui:IsA("ScreenGui") and (gui.Name:find("HUD") or gui.Name:find("Spectator") or gui.Name:find("Quin")) then
            gui.Enabled = true
        end
    end
end
return "HUDs restored"
"""
client.execute_luau(restore_hud_code, datamodel_type="Client")
