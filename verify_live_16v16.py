from Tools.Utilities.roblox_client import RobloxStudioClient
import time
import json

c = RobloxStudioClient()
print("Connected to Studio in Play mode. Studio ID:", c.studio_id)

# 1. Test SpatialModule analyzeObstacleAhead in Server datamodel
test_obs_code = r"""
local rs = game:GetService("ReplicatedStorage")
local SpatialModule = require(rs.QuinCore.Modules.SpatialModule)

local part = Instance.new("Part")
part.Size = Vector3.new(2, 2, 1)
part.CFrame = CFrame.new(-124, 4.5, 15)
part.Parent = workspace

local targetPos = Vector3.new(-124, 4.5, 35)
local info = SpatialModule.analyzeObstacleAhead(part, targetPos, 22)
part:Destroy()

local res = {}
for k, v in pairs(info) do
    table.insert(res, k .. "=" .. tostring(v))
end
return "analyzeObstacleAhead result: " .. table.concat(res, ", ")
"""

res_obs = c.execute_luau(test_obs_code, "Server")
print("Obstacle Analysis Verification:")
print(res_obs.get("result", {}).get("content", [{}])[0].get("text", ""))

# 2. Trigger 16v16 Team Battle
start_match_code = r"""
local gmm = _G.GameModeManager or shared.GameModeManager
if gmm and gmm.startTeamBattle then
    task.spawn(function()
        gmm.startTeamBattle(16)
    end)
    return "Triggered startTeamBattle(16)"
else
    return "GameModeManager not found"
end
"""
res_start = c.execute_luau(start_match_code, "Server")
print("Match Start Result:", res_start.get("result", {}).get("content", [{}])[0].get("text", ""))

# 3. Wait 5 seconds to observe countdown and spawn
time.sleep(5)

# 4. Check spawned Quins: counts, team rings, highlights, colors, states
inspect_match_code = r"""
local ws = game:GetService("Workspace")
local qs = ws:FindFirstChild("QuinServer")
if not qs then return "No QuinServer found" end

local quins = qs:GetChildren()
local alphaCount = 0
local betaCount = 0
local ringCount = 0
local hlCount = 0
local states = {}
local awarenessList = {}

for _, q in ipairs(quins) do
    local team = q:GetAttribute("Team")
    if team == "TeamAlpha" then alphaCount = alphaCount + 1
    elseif team == "TeamBeta" then betaCount = betaCount + 1 end
    
    local ring = q:FindFirstChild("TeamRing")
    if ring and ring.Transparency < 0.5 then
        ringCount = ringCount + 1
    end
    
    local hl = q:FindFirstChild("ElementHighlight")
    if hl and hl.OutlineTransparency >= 0.99 then
        hlCount = hlCount + 1
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
    "Total Quins: %d (Alpha=%d, Beta=%d)\nActive TeamRings: %d/%d\nOutline-free Highlights: %d/%d\nState Breakdown: %s\nActive Obstacle Awareness: %s",
    #quins, alphaCount, betaCount, ringCount, #quins, hlCount, #quins,
    table.concat(stateStrs, ", "),
    #awarenessList > 0 and table.concat(awarenessList, " | ") or "None active yet"
)
"""
res_inspect = c.execute_luau(inspect_match_code, "Server")
print("Initial 16v16 Inspection:\n", res_inspect.get("result", {}).get("content", [{}])[0].get("text", ""))

c.close()
