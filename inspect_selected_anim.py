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

local info = {}
for _, desc in ipairs(anim_ui:GetDescendants()) do
    if desc:IsA("TextBox") then
        table.insert(info, {class="TextBox", name=desc.Name, text=desc.Text, placeholder=desc.PlaceholderText})
    elseif desc:IsA("TextLabel") and string.find(desc.Text, "Selected:") then
        table.insert(info, {class="TextLabel", name=desc.Name, text=desc.Text})
    end
end

local HttpService = game:GetService("HttpService")
return HttpService:JSONEncode(info)
"""

res = client.execute_luau(code, datamodel_type="Client")
print(res)
