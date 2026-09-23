from Tools.Utilities.roblox_client import RobloxStudioClient
import time

c = RobloxStudioClient()
print("Waiting 5s for spawn and countdown...")
time.sleep(5)

code = r"""
local ws = game:GetService("Workspace")
local qs = ws:FindFirstChild("QuinServer")
if not qs then return "No QuinServer folder found!" end

local quins = qs:GetChildren()
local alphaCount = 0
local betaCount = 0
local rings = 0
local highlights = 0
local states = {}
local awarenessList = {}

for _, q in ipairs(quins) do
    local team = q:GetAttribute("Team")
    if team == "TeamAlpha" then alphaCount = alphaCount + 1
    elseif team == "TeamBeta" then betaCount = betaCount + 1 end

    local r = q:FindFirstChild("TeamRing")
    if r and r:IsA("BasePart") then
        rings = rings + 1
    end

    local hl = q:FindFirstChild("ElementHighlight")
    if hl and hl:IsA("Highlight") and hl.OutlineTransparency >= 0.99 then
        highlights = highlights + 1
    end

    local st = q:GetAttribute("CurrentState") or "Unknown"
    states[st] = (states[st] or 0) + 1

    local aware = q:GetAttribute("ObstacleAwareness")
    if aware and aware ~= "Clear" then
        table.insert(awarenessList, q.Name .. ": " .. aware)
    end
end

local stateStrs = {}
for st, cnt in pairs(states) do
    table.insert(stateStrs, st .. "=" .. tostring(cnt))
end

return string.format(
    "Total Quins Spawned: %d (Alpha=%d, Beta=%d)\nActive TeamRings: %d/%d\nOutline-free Highlights: %d/%d\nStates: %s\nObstacle Awareness: %s",
    #quins, alphaCount, betaCount, rings, #quins, highlights, #quins,
    table.concat(stateStrs, ", "),
    #awarenessList > 0 and table.concat(awarenessList, " | ") or "None active yet"
)
"""
res = c.execute_luau(code, "Server")
print("16v16 Match Inspection:\n", res.get("result", {}).get("content", [{}])[0].get("text", ""))
c.close()
