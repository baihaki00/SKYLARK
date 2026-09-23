import sys
import os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from roblox_client import RobloxStudioClient

client = RobloxStudioClient()
code = """
local Workspace = game:GetService("Workspace")
local ghostFolder = Workspace:FindFirstChild("QuinGhost")
local g = ghostFolder and ghostFolder:FindFirstChild("QuinA_Runner_Visual")
if not g then return "No QuinA_Runner_Visual found" end

local info = {}
table.insert(info, "Name: " .. g.Name)
table.insert(info, "PrimaryPart: " .. tostring(g.PrimaryPart))
for _, p in ipairs(g:GetDescendants()) do
    if p:IsA("BasePart") then
        table.insert(info, string.format("Part %s | Size: (%.1f, %.1f, %.1f) | Trans: %.2f | CanCollide: %s | Anchored: %s | Pos: (%.1f, %.1f, %.1f)",
            p.Name, p.Size.X, p.Size.Y, p.Size.Z, p.Transparency, tostring(p.CanCollide), tostring(p.Anchored), p.Position.X, p.Position.Y, p.Position.Z))
    end
end
return table.concat(info, "\\n")
"""
res = client.execute_luau(code, datamodel_type="Client")
print(res.get("result", {}).get("content", [{}])[0].get("text", ""))
