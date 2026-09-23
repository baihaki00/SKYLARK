import sys
import os
import time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from roblox_client import RobloxStudioClient

client = RobloxStudioClient()

# 1. Trigger 4v4 Team Battle
start_code = """
local GMM = _G.GameModeManager or shared.GameModeManager
if not GMM then
    return "FAIL: GameModeManager not found in _G/shared"
end
GMM.startTeamBattle(4)
return "STARTED: 4v4 TeamBattle triggered"
"""

res_start = client.execute_luau(start_code, datamodel_type="Server")
start_text = res_start.get("result", {}).get("content", [{}])[0].get("text", "")
print("Start result:", start_text)

# 2. Wait for countdown (3-4 seconds) and let Quins engage
print("Waiting 5 seconds for Quins to spawn and clash...")
time.sleep(5)

# 3. Poll Quins telemetry
poll_code = """
local CollectionService = game:GetService("CollectionService")
local quins = CollectionService:GetTagged("Quin")
local states = {}
local lines = {}
table.insert(lines, "Alive Quins: " .. #quins)

for _, q in ipairs(quins) do
    local state = q:GetAttribute("CurrentState") or "None"
    local team = q:GetAttribute("Team") or "None"
    local hum = q:FindFirstChildOfClass("Humanoid")
    local hp = hum and hum.Health or 0
    local hrp = q:FindFirstChild("HumanoidRootPart")
    local vel = hrp and hrp.AssemblyLinearVelocity.Magnitude or 0
    states[state] = (states[state] or 0) + 1
    table.insert(lines, string.format("  [%s] %s | State: %-12s | HP: %4.0f | Vel: %4.1f", team, q.Name, state, hp, vel))
end

local stateBreakdown = {}
for st, cnt in pairs(states) do
    table.insert(stateBreakdown, st .. ": " .. cnt)
end
table.insert(lines, "States distribution: " .. table.concat(stateBreakdown, ", "))

return table.concat(lines, "\\n")
"""

res_poll = client.execute_luau(poll_code, datamodel_type="Server")
poll_text = res_poll.get("result", {}).get("content", [{}])[0].get("text", "")
print("\n=== Live 4v4 Telemetry ===\n" + poll_text)

# 4. Check for console errors
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
    return "0_ERRORS: Clean execution in 4v4 battle"
else
    return "ERRORS_FOUND:\\n" .. table.concat(errors, "\\n")
end
"""
res_err = client.execute_luau(error_code, datamodel_type="Server")
err_text = res_err.get("result", {}).get("content", [{}])[0].get("text", "")
print("\n=== Console Error Check ===\n" + err_text)
