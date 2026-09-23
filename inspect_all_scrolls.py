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

local scrolls = {}
for _, desc in ipairs(anim_ui:GetDescendants()) do
    if desc:IsA("ScrollingFrame") then
        local children = {}
        for _, c in ipairs(desc:GetChildren()) do
            if c:IsA("TextButton") then
                table.insert(children, c.Text)
            end
        end
        table.insert(scrolls, {
            name = desc.Name,
            parent = desc.Parent.Name,
            path = desc:GetFullName(),
            btnCount = #children,
            firstFew = {children[1], children[2], children[3]}
        })
    end
end

local HttpService = game:GetService("HttpService")
return HttpService:JSONEncode(scrolls)
"""

res = client.execute_luau(code, datamodel_type="Client")
print(res)
