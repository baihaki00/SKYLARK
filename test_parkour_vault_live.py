from Tools.Utilities.roblox_client import RobloxStudioClient
import time

c = RobloxStudioClient()
print("Running targeted Parkour Vault Live Verification...")

code = r"""
local ws = game:GetService("Workspace")
local sss = game:GetService("ServerScriptService")
local QuinSpawner = require(sss:WaitForChild("QuinSpawner"))

-- Clean existing to run isolated hurdle test
QuinSpawner.cleanAll()
task.wait(0.2)

ws:SetAttribute("MatchStarted", true)

-- Spawn Quin directly facing the hurdle at (-124, 3, 31)
-- Ground is Y=2.05, spawn at (-124, 2.05, 10) facing (0, 0, 1)
local p1 = Vector3.new(-124, 2.05, 8)
local p2 = Vector3.new(-124, 2.05, 50) -- Target behind the hurdle!

local quin = QuinSpawner.spawn("TypeA", p1, "TeamAlpha", "Fire", p2)
local enemy = QuinSpawner.spawn("TypeB", p2, "TeamBeta", "Water", p1)

task.wait(0.1)

quin:SetAttribute("CurrentTarget", enemy.Name)
quin:SetAttribute("TargetQuin", enemy.Name)
enemy:SetAttribute("CurrentTarget", quin.Name)
enemy:SetAttribute("TargetQuin", quin.Name)

-- Force chase state
quin:SetAttribute("ForceState", "Chase")

return string.format("Spawned %s at %s facing enemy at %s across hurdle", quin.Name, tostring(p1), tostring(p2))
"""

res = c.execute_luau(code, "Server")
print("Setup:", res.get("result", {}).get("content", [{}])[0].get("text", ""))

# Monitor for 4 seconds as the Quin runs towards the obstacle and leaps
monitor_code = r"""
local ws = game:GetService("Workspace")
local qs = ws:FindFirstChild("QuinServer")
if not qs then return "No QuinServer" end

local quin = qs:FindFirstChild("Quin_TypeA", true)
if not quin then
    for _, ch in ipairs(qs:GetChildren()) do
        if ch.Name:find("TypeA") then quin = ch break end
    end
end
if not quin then return "Quin not found" end

local hrp = quin:FindFirstChild("HumanoidRootPart")
local hum = quin:FindFirstChildOfClass("Humanoid")
local aware = quin:GetAttribute("ObstacleAwareness")
local st = quin:GetAttribute("CurrentState")

local vel = hrp and hrp.AssemblyLinearVelocity or Vector3.zero
local yPos = hrp and hrp.Position.Y or 0
local zPos = hrp and hrp.Position.Z or 0

return string.format("Pos=(Z:%.1f, Y:%.1f) | Vel=(Z:%.1f, Y:%.1f) | State=%s | Awareness=%s | Jump=%s",
    zPos, yPos, vel.Z, vel.Y, tostring(st), tostring(aware), tostring(hum and hum.Jump))
"""

for i in range(8):
    m_res = c.execute_luau(monitor_code, "Server")
    print(f"t={i*0.4:.1f}s: {m_res.get('result', {}).get('content', [{}])[0].get('text', '')}")
    time.sleep(0.4)

c.close()
