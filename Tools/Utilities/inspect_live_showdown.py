import sys
import os
sys.path.append(os.path.abspath("Tools/Utilities"))
from roblox_client import RobloxStudioClient

client = RobloxStudioClient()
script = """
local CS = game:GetService("CollectionService")
local quins = CS:GetTagged("Quin")
local out = {}
for _, q in ipairs(quins) do
    local hrp = q:FindFirstChild("HumanoidRootPart")
    local hum = q:FindFirstChildOfClass("Humanoid")
    local pos = hrp and hrp.Position or Vector3.zero
    local dist = (Vector3.new(pos.X, 0, pos.Z) - Vector3.new(0, 0, -38)).Magnitude
    table.insert(out, string.format("%s | Role: %s | State: %s | Pos: (%.1f, %.1f, %.1f) | Dist: %.1f | HP: %.0f",
        q.Name, tostring(q:GetAttribute("LeaderShowdownRole")), tostring(q:GetAttribute("CurrentState")),
        pos.X, pos.Y, pos.Z, dist, hum and hum.Health or 0))
end
local dais = workspace:FindFirstChild("LeaderShowdownDais")
table.insert(out, "Dais: " .. tostring(dais ~= nil) .. " | Active: " .. tostring(workspace:GetAttribute("LeaderShowdownActive")))
return table.concat(out, "\\n")
"""
res = client.execute_luau(script, datamodel_type="Server")
print(res.get("result", {}).get("content", [{}])[0].get("text", ""))
