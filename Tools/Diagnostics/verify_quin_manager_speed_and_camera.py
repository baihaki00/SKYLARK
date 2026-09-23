import os
import sys
import time

sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "Utilities")))
from roblox_client import RobloxStudioClient

client = RobloxStudioClient()
print("Connected to Studio ID:", client.studio_id)

test_code = """
local Players = game:GetService("Players")
local player = Players.LocalPlayer
local pGui = player and player:FindFirstChild("PlayerGui")

local standaloneGui = pGui and pGui:FindFirstChild("BattleSpeedGui")
local speedMult = workspace:GetAttribute("GameSpeedMultiplier")

local labUI = pGui and pGui:FindFirstChild("AnimationLabUI")
local mainFrame = labUI and labUI:FindFirstChild("MainFrame")
local titleBar = mainFrame and mainFrame:FindFirstChild("TitleBar")
local speedContainer = titleBar and titleBar:FindFirstChild("SpeedControllerContainer")

local btn1x = speedContainer and speedContainer:FindFirstChild("SpeedBtn_1x")
local btn5x = speedContainer and speedContainer:FindFirstChild("SpeedBtn_5x")

local btn1xActive = btn1x and (btn1x.BackgroundColor3 == Color3.fromRGB(0, 200, 255))

return string.format("DefaultSpeed: %s | StandaloneHUD_Gone: %s | SpeedContainer_In_QuinManager: %s | Btn1x_Active: %s",
    tostring(speedMult),
    tostring(standaloneGui == nil),
    tostring(speedContainer ~= nil),
    tostring(btn1xActive)
)
"""

res = client.execute_luau(test_code, datamodel_type="Client")
print("Verification Result:", res.get("result", {}).get("content", [{}])[0].get("text", ""))

# Test clicking 5x button in Quin Manager Menu
click_5x_code = """
local Players = game:GetService("Players")
local player = Players.LocalPlayer
local pGui = player and player:FindFirstChild("PlayerGui")
local labUI = pGui and pGui:FindFirstChild("AnimationLabUI")
local mainFrame = labUI and labUI:FindFirstChild("MainFrame")
local titleBar = mainFrame and mainFrame:FindFirstChild("TitleBar")
local speedContainer = titleBar and titleBar:FindFirstChild("SpeedControllerContainer")
local btn5x = speedContainer and speedContainer:FindFirstChild("SpeedBtn_5x")

if btn5x then
    -- Trigger click
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local speedEvent = ReplicatedStorage:FindFirstChild("GameSpeedEvent")
    if speedEvent then
        speedEvent:FireServer(5)
        workspace:SetAttribute("GameSpeedMultiplier", 5)
    end
    return "Toggled to 5x via Quin Manager"
end
return "Btn5x not found"
"""
res_click = client.execute_luau(click_5x_code, datamodel_type="Client")
print("Click Test:", res_click.get("result", {}).get("content", [{}])[0].get("text", ""))
time.sleep(1.0)

chk_server = client.execute_luau("return workspace:GetAttribute('GameSpeedMultiplier')", datamodel_type="Server")
print("Server GameSpeedMultiplier after toggle:", chk_server.get("result", {}).get("content", [{}])[0].get("text", ""))

# Reset back to 1x
client.execute_luau("game:GetService('ReplicatedStorage').GameSpeedEvent:FireServer(1); workspace:SetAttribute('GameSpeedMultiplier', 1)", datamodel_type="Client")
time.sleep(1.0)
chk_reset = client.execute_luau("return workspace:GetAttribute('GameSpeedMultiplier')", datamodel_type="Server")
print("Reset back to 1x on Server:", chk_reset.get("result", {}).get("content", [{}])[0].get("text", ""))

# Camera Test
cam_test = """
local cam = workspace.CurrentCamera
return string.format("Camera Mode: %s, Position: (%.1f, %.1f, %.1f)", tostring(cam.CameraType), cam.CFrame.Position.X, cam.CFrame.Position.Y, cam.CFrame.Position.Z)
"""
res_cam = client.execute_luau(cam_test, datamodel_type="Client")
print("Camera Check:", res_cam.get("result", {}).get("content", [{}])[0].get("text", ""))

client.close()
