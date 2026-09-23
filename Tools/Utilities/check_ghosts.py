import sys
import os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from roblox_client import RobloxStudioClient

client = RobloxStudioClient()
code = """
local Workspace = game:GetService("Workspace")
local ghostFolder = Workspace:FindFirstChild("QuinGhost")
if not ghostFolder then return "No QuinGhost folder in Workspace" end
local ghosts = ghostFolder:GetChildren()
local lines = { "Ghost count: " .. #ghosts }
for _, g in ipairs(ghosts) do
    local hrp = g:FindFirstChild("HumanoidRootPart")
    local pos = hrp and string.format("%.1f, %.1f, %.1f", hrp.Position.X, hrp.Position.Y, hrp.Position.Z) or "No HRP"
    table.insert(lines, g.Name .. " at " .. pos)
end
return table.concat(lines, "\\n")
"""
res = client.execute_luau(code, datamodel_type="Client")
if res.get("isError"):
    print("ERROR:", res)
else:
    print(res.get("result", {}).get("content", [{}])[0].get("text", ""))
