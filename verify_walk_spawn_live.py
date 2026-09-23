import sys
import json
import time
sys.path.append(r"C:\Users\User\.gemini\antigravity\scratch\Tools\Utilities")
from roblox_client import RobloxStudioClient

client = RobloxStudioClient()

# 1. Verify Walk animation ID in Client datamodel
verify_walk_code = """
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local QuinCore = ReplicatedStorage:WaitForChild("QuinCore")
local AnimationConfig = require(QuinCore:WaitForChild("AnimationConfig"))
local HttpService = game:GetService("HttpService")

return HttpService:JSONEncode({
    WalkConfident = AnimationConfig.get("Movement.WalkConfident"),
    WalkThug = AnimationConfig.get("Movement.WalkThug"),
})
"""

print("1. Checking Walk Animation IDs in Client datamodel:")
res1 = client.execute_luau(verify_walk_code, datamodel_type="Client")
print(res1.get("result", {}).get("content", [{}])[0].get("text", ""))

# 2. Launch a 4v4 match and check facing & scatter
launch_code = """
local labEvent = game:GetService("ReplicatedStorage"):WaitForChild("QuinCore"):WaitForChild("Events"):WaitForChild("AnimationLabEvent")
labEvent:FireServer("SetGameMode", { mode = "team", count = 4 })
return "Launched 4v4"
"""

client.execute_luau(launch_code, datamodel_type="Client")
time.sleep(2.0)

# Check positions, LookVectors, and teammate spacing
check_spawn_code = """
local Workspace = game:GetService("Workspace")
local quinServer = Workspace:FindFirstChild("QuinServer") or Workspace
local HttpService = game:GetService("HttpService")

local teams = { TeamAlpha = {}, TeamBeta = {} }
for _, model in ipairs(quinServer:GetDescendants()) do
    if model:IsA("Model") and model:FindFirstChildOfClass("Humanoid") and model.Name:find("Quin") then
        local hrp = model:FindFirstChild("HumanoidRootPart")
        local team = model:GetAttribute("Team") or "None"
        if teams[team] and hrp then
            table.insert(teams[team], {
                name = model.Name,
                pos = hrp.Position,
                lookVector = string.format("(%.2f, %.2f, %.2f)", hrp.CFrame.LookVector.X, hrp.CFrame.LookVector.Y, hrp.CFrame.LookVector.Z),
                obAwareness = model:GetAttribute("ObstacleAwareness") or "Clear"
            })
        end
    end
end

-- Calculate inter-teammate distances
local teamAlphaDistances = {}
for i = 1, #teams.TeamAlpha do
    for j = i + 1, #teams.TeamAlpha do
        local d = (teams.TeamAlpha[i].pos - teams.TeamAlpha[j].pos).Magnitude
        table.insert(teamAlphaDistances, math.round(d * 10) / 10)
    end
end

local teamBetaDistances = {}
for i = 1, #teams.TeamBeta do
    for j = i + 1, #teams.TeamBeta do
        local d = (teams.TeamBeta[i].pos - teams.TeamBeta[j].pos).Magnitude
        table.insert(teamBetaDistances, math.round(d * 10) / 10)
    end
end

-- Check dot product of lookVectors between teams (should be ~ -1.0, meaning facing opposite toward each other!)
local dotProd = nil
if #teams.TeamAlpha > 0 and #teams.TeamBeta > 0 then
    local dirA = (teams.TeamBeta[1].pos - teams.TeamAlpha[1].pos).Unit
    local lookA = Vector3.new(teams.TeamAlpha[1].pos.X, 0, teams.TeamAlpha[1].pos.Z) -- placeholder
end

return HttpService:JSONEncode({
    alphaCount = #teams.TeamAlpha,
    betaCount = #teams.TeamBeta,
    alphaLookVectors = (function() local r={}; for _, q in ipairs(teams.TeamAlpha) do table.insert(r, q.lookVector) end; return r end)(),
    betaLookVectors = (function() local r={}; for _, q in ipairs(teams.TeamBeta) do table.insert(r, q.lookVector) end; return r end)(),
    alphaTeammateDistances = teamAlphaDistances,
    betaTeammateDistances = teamBetaDistances,
    sampleAlpha = teams.TeamAlpha[1],
    sampleBeta = teams.TeamBeta[1],
})
"""

print("\n2. Checking Team Spawning, Facing & Scatter:")
res2 = client.execute_luau(check_spawn_code, datamodel_type="Server")
print(res2.get("result", {}).get("content", [{}])[0].get("text", ""))
