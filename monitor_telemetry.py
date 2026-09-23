from Tools.Utilities.roblox_client import RobloxStudioClient
import time

c = RobloxStudioClient()
print("Monitoring 16v16 battle telemetry for 10 seconds...")

code = r"""
local ws = game:GetService("Workspace")
local qs = ws:FindFirstChild("QuinServer")
if not qs then return "No QuinServer folder found!" end

local states = {}
local awarenessEvents = {}
local feints = {}

for _, q in ipairs(qs:GetChildren()) do
    local st = q:GetAttribute("CurrentState") or "Unknown"
    states[st] = (states[st] or 0) + 1

    local aware = q:GetAttribute("ObstacleAwareness")
    if aware and aware ~= "Clear" then
        table.insert(awarenessEvents, q.Name .. ": " .. aware)
    end

    local feint = q:GetAttribute("TacticalFeint")
    if feint then
        table.insert(feints, q.Name)
    end
end

local stateStrs = {}
for st, cnt in pairs(states) do
    table.insert(stateStrs, st .. "=" .. tostring(cnt))
end

return string.format(
    "Active Fighters: %d\nStates: %s\nObstacle Events (%d): %s",
    #qs:GetChildren(),
    table.concat(stateStrs, ", "),
    #awarenessEvents,
    #awarenessEvents > 0 and table.concat(awarenessEvents, " | ") or "None"
)
"""

for i in range(3):
    res = c.execute_luau(code, "Server")
    print(f"--- Telemetry Snapshot {i+1} ---")
    print(res.get("result", {}).get("content", [{}])[0].get("text", ""))
    time.sleep(3)

c.close()
