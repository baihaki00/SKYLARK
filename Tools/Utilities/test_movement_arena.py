import sys
import os
import time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from roblox_client import RobloxStudioClient

client = RobloxStudioClient()

# Fire movement_test
trigger_code = """
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local cmd = ReplicatedStorage:WaitForChild("GameCommand", 5)
if not cmd then return "GameCommand RemoteEvent not found" end
cmd:FireServer("movement_test")
return "Fired movement_test command from client"
"""
res = client.execute_luau(trigger_code, datamodel_type="Client")
print(res.get("result", {}).get("content", [{}])[0].get("text", ""))

print("Waiting 4 seconds for movement test arena to initialize...")
time.sleep(4)

# Poll runner
poll_code = """
local CollectionService = game:GetService("CollectionService")
local runner = workspace:FindFirstChild("QuinA_Runner") or workspace:FindFirstChild("QuinServer") and workspace.QuinServer:FindFirstChild("QuinA_Runner")
if not runner then
    for _, q in ipairs(CollectionService:GetTagged("Quin")) do
        if q.Name == "QuinA_Runner" then runner = q break end
    end
end
if not runner then return "Runner not found" end

local hrp = runner:FindFirstChild("HumanoidRootPart")
local hum = runner:FindFirstChildOfClass("Humanoid")
local state = runner:GetAttribute("CurrentState") or "nil"
local vel = hrp and hrp.AssemblyLinearVelocity or Vector3.zero
local pos = hrp and hrp.Position or Vector3.zero

return string.format("QuinA_Runner | State: %s | Pos: (%.1f, %.1f, %.1f) | Vel: (%.1f, %.1f, %.1f) Mag=%.1f",
    state, pos.X, pos.Y, pos.Z, vel.X, vel.Y, vel.Z, vel.Magnitude)
"""

for i in range(4):
    res_poll = client.execute_luau(poll_code, datamodel_type="Server")
    print(f"Step {i+1}:", res_poll.get("result", {}).get("content", [{}])[0].get("text", ""))
    time.sleep(1.5)
