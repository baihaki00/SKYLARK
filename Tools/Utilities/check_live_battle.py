import sys
import os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from roblox_client import RobloxStudioClient

client = RobloxStudioClient()
code = """
local CollectionService = game:GetService("CollectionService")
local quins = CollectionService:GetTagged("Quin")
local report = {}

table.insert(report, "Active Quins count: " .. #quins)
for _, q in ipairs(quins) do
    local hrp = q:FindFirstChild("HumanoidRootPart")
    local hum = q:FindFirstChildOfClass("Humanoid")
    local state = q:GetAttribute("CurrentState") or "nil"
    local tgt = q:GetAttribute("CurrentTarget") or "none"
    local energy = q:GetAttribute("Energy") or -1
    local hp = hum and hum.Health or -1
    local speed = hrp and hrp.AssemblyLinearVelocity.Magnitude or 0
    table.insert(report, string.format("Quin %s | State: %s | Tgt: %s | HP: %.0f | Energy: %.0f | Vel: %.1f", q.Name, state, tgt, hp, energy, speed))
end

return table.concat(report, "\\n")
"""
res = client.execute_luau(code, datamodel_type="Server")
if res.get("isError"):
    print("ERROR:", res)
else:
    print(res.get("result", {}).get("content", [{}])[0].get("text", ""))
