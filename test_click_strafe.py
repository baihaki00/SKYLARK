import sys
import json
sys.path.append(r"C:\Users\User\.gemini\antigravity\scratch\Tools\Utilities")
from roblox_client import RobloxStudioClient

client = RobloxStudioClient()

code = """
local Players = game:GetService("Players")
local lp = Players.LocalPlayer
local pg = lp:FindFirstChild("PlayerGui")
local anim_ui = pg:FindFirstChild("AnimationLabUI")
if not anim_ui then return "No AnimationLabUI" end

-- Find Strafe category button
local strafe_cat_btn = nil
for _, desc in ipairs(anim_ui:GetDescendants()) do
    if desc:IsA("TextButton") and desc.Text == "Strafe" then
        strafe_cat_btn = desc
        break
    end
end

if not strafe_cat_btn then return "Strafe button not found" end

-- Fire category button click
-- In Roblox, GuiService or virtual click, but TextButton has Activated event / MouseButton1Click
-- Or we can inspect what the button does
return "Found Strafe button: " .. strafe_cat_btn:GetFullName()
"""

res = client.execute_luau(code, datamodel_type="Client")
print(res)
