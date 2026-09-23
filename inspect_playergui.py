import sys
import json
sys.path.append(r"C:\Users\User\.gemini\antigravity\scratch\Tools\Utilities")
from roblox_client import RobloxStudioClient

client = RobloxStudioClient()

code = """
local Players = game:GetService("Players")
local lp = Players.LocalPlayer
if not lp then return "No LocalPlayer" end
local pg = lp:FindFirstChild("PlayerGui")
if not pg then return "No PlayerGui" end

local gui_info = {}
for _, child in ipairs(pg:GetChildren()) do
    table.insert(gui_info, {
        name = child.Name,
        className = child.ClassName,
        enabled = child:IsA("ScreenGui") and child.Enabled or nil
    })
end

local anim_lab = pg:FindFirstChild("AnimationLabGui")
local details = {}
if anim_lab then
    for _, desc in ipairs(anim_lab:GetDescendants()) do
        if desc:IsA("TextBox") or desc:IsA("TextLabel") then
            if desc.Text ~= "" and string.len(desc.Text) < 100 then
                table.insert(details, {
                    name = desc.Name,
                    parent = desc.Parent and desc.Parent.Name,
                    text = desc.Text
                })
            end
        end
    end
end

local HttpService = game:GetService("HttpService")
return HttpService:JSONEncode({guis = gui_info, details = details})
"""

res = client.execute_luau(code, datamodel_type="Client")
print(res)
