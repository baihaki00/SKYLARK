from Tools.Utilities.roblox_client import RobloxStudioClient
import time

client = RobloxStudioClient()

# Monitor Quins for 6 seconds and log animation track triggers
code_monitor = """
local CollectionService = game:GetService("CollectionService")
local AnimationModule = require(game:GetService("ReplicatedStorage").QuinCore.Modules.AnimationModule)

local quins = CollectionService:GetTagged("Quin")
local status = {}
for _, q in ipairs(quins) do
    local hum = q:FindFirstChildOfClass("Humanoid")
    local hrp = q:FindFirstChild("HumanoidRootPart")
    local state = q:GetAttribute("CurrentState") or "None"
    local activeAnims = {}
    if hum then
        for _, t in ipairs(hum:GetPlayingAnimationTracks()) do
            if t.WeightCurrent > 0.05 then
                local id = t.Animation and t.Animation.AnimationId or "unknown"
                table.insert(activeAnims, string.format("%s (w=%.2f, spd=%.2f)", id, t.WeightCurrent, t.Speed))
            end
        end
    end
    local vel = hrp and hrp.AssemblyLinearVelocity.Magnitude or 0
    table.insert(status, string.format("[%s] State: %s | Spd: %.1f | Tracks: %s", 
        q.Name, state, vel, (#activeAnims > 0 and table.concat(activeAnims, "; ") or "None")))
end
return table.concat(status, "\\n")
"""

print("--- Snapshot 1 ---")
res1 = client.execute_luau(code_monitor, "Server")
print(res1.get("result", {}).get("content", [{}])[0].get("text", ""))

time.sleep(3.0)

print("\n--- Snapshot 2 (3s later) ---")
res2 = client.execute_luau(code_monitor, "Server")
print(res2.get("result", {}).get("content", [{}])[0].get("text", ""))

client.close()
