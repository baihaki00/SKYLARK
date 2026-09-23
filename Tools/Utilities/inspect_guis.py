import sys
import os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from roblox_client import RobloxStudioClient

client = RobloxStudioClient()
code = """
local Players = game:GetService("Players")
local lp = Players.LocalPlayer
if not lp then return "No LocalPlayer" end
local pg = lp:FindFirstChild("PlayerGui")
if not pg then return "No PlayerGui" end

local lines = {}
for _, gui in ipairs(pg:GetChildren()) do
    if gui:IsA("ScreenGui") then
        table.insert(lines, string.format("ScreenGui: %s | Enabled: %s", gui.Name, tostring(gui.Enabled)))
        for _, desc in ipairs(gui:GetDescendants()) do
            if desc:IsA("TextLabel") and desc.Text:find("QUIN MANAGER") then
                table.insert(lines, "  -> Found Quin Manager TextLabel in " .. desc:GetFullName())
            end
        end
    end
end
return table.concat(lines, "\\n")
"""
res = client.execute_luau(code, datamodel_type="Client")
print(res.get("result", {}).get("content", [{}])[0].get("text", ""))
