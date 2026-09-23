import sys
import os
import time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from roblox_client import RobloxStudioClient

client = RobloxStudioClient()

# 1. Fire GameCommand from Client
trigger_code = """
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local cmd = ReplicatedStorage:WaitForChild("GameCommand", 5)
if not cmd then return "GameCommand RemoteEvent not found" end
cmd:FireServer("team", 4)
return "Fired team 4 battle command from client"
"""
res = client.execute_luau(trigger_code, datamodel_type="Client")
print("Client command fire:", res.get("result", {}).get("content", [{}])[0].get("text", ""))

print("Waiting 6 seconds for 8 Quins to spawn and begin battle...")
time.sleep(6)

# 2. Check Server Quin count & states
poll_code = """
local CollectionService = game:GetService("CollectionService")
local quins = CollectionService:GetTagged("Quin")
local lines = {}
table.insert(lines, "Alive Quins count: " .. #quins)

local stateCounts = {}
for _, q in ipairs(quins) do
    local state = q:GetAttribute("CurrentState") or "nil"
    local hum = q:FindFirstChildOfClass("Humanoid")
    local hp = hum and hum.Health or 0
    local hrp = q:FindFirstChild("HumanoidRootPart")
    local vel = hrp and hrp.AssemblyLinearVelocity.Magnitude or 0
    stateCounts[state] = (stateCounts[state] or 0) + 1
    table.insert(lines, string.format("  [%s] State: %-12s | HP: %4.0f | Vel: %4.1f", q.Name, state, hp, vel))
end

local breakdown = {}
for st, cnt in pairs(stateCounts) do
    table.insert(breakdown, st .. ": " .. cnt)
end
table.insert(lines, "Breakdown: " .. table.concat(breakdown, ", "))
return table.concat(lines, "\\n")
"""
res_poll = client.execute_luau(poll_code, datamodel_type="Server")
print("\n=== Live 4v4 Quins Telemetry ===\n" + res_poll.get("result", {}).get("content", [{}])[0].get("text", ""))

# 3. Check for errors
error_code = """
local LogService = game:GetService("LogService")
local history = LogService:GetLogHistory()
local errors = {}
for _, entry in ipairs(history) do
    if entry.messageType == Enum.MessageType.MessageError then
        table.insert(errors, entry.message)
    end
end
if #errors == 0 then
    return "ZERO_ERRORS"
else
    return "ERRORS:\\n" .. table.concat(errors, "\\n")
end
"""
res_err = client.execute_luau(error_code, datamodel_type="Server")
print("\n=== Error Check ===\n" + res_err.get("result", {}).get("content", [{}])[0].get("text", ""))
