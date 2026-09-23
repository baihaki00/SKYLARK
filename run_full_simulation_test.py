import sys
import time
import os
import json

sys.stdout.reconfigure(encoding='utf-8')
sys.path.insert(0, r"C:\Users\User\.gemini\antigravity\scratch\Tools\Utilities")

from roblox_client import RobloxStudioClient
client = RobloxStudioClient()
print("Connected Studio ID:", client.studio_id)

spawn_code = """
local HttpService = game:GetService("HttpService")
local QuinSpawner = require(game.ServerScriptService:WaitForChild("QuinSpawner"))

-- Clear previous Quins
for _, m in ipairs(workspace:GetDescendants()) do
    if m:IsA("Model") and game:GetService("CollectionService"):HasTag(m, "Quin") then
        m:Destroy()
    end
end
task.wait(0.5)

local teamA = QuinSpawner.spawnTeam("A", 16, Vector3.new(-80, 5, 0), 10)
local teamB = QuinSpawner.spawnTeam("B", 16, Vector3.new(80, 5, 0), 10)

task.wait(0.3)
-- Assign cross-team targets
local CS = game:GetService("CollectionService")
local allQuins = CS:GetTagged("Quin")
for _, q in ipairs(allQuins) do
    local myTeam = q:GetAttribute("Team")
    local enemies = {}
    for _, other in ipairs(allQuins) do
        if other:GetAttribute("Team") ~= myTeam and other.Parent then
            table.insert(enemies, other)
        end
    end
    if #enemies > 0 then
        local t = enemies[math.random(1, #enemies)]
        q:SetAttribute("CurrentTarget", t.Name)
        q:SetAttribute("TargetQuin", t.Name)
    end
end

return HttpService:JSONEncode({
    teamA = #teamA,
    teamB = #teamB,
    total = #teamA + #teamB
})
"""

res = client.execute_luau(spawn_code, datamodel_type="Server")
raw = res.get("result", {}).get("content", [{}])[0].get("text", "")
print("Spawn result:", raw)

print("\nRunning 16v16 simulation for 25 seconds...")
for i in range(5):
    time.sleep(5)
    sample_code = """
    local HttpService = game:GetService("HttpService")
    local CS = game:GetService("CollectionService")
    local quins = CS:GetTagged("Quin")
    local alive = 0
    local states = {}
    local decisions = {}
    local retreatingCount = 0
    local corneredCount = 0
    local recoveryCount = 0

    for _, q in ipairs(quins) do
        if q.Parent then
            local hum = q:FindFirstChildOfClass("Humanoid")
            if hum and hum.Health > 0 then
                alive = alive + 1
                local st = q:GetAttribute("CurrentState") or "None"
                states[st] = (states[st] or 0) + 1
                local dec = q:GetAttribute("RecommendedAction") or "None"
                decisions[dec] = (decisions[dec] or 0) + 1
                if st == "Retreat" then retreatingCount = retreatingCount + 1 end
                if st == "ProjectileJumpRecovery" then recoveryCount = recoveryCount + 1 end
                if q:GetAttribute("IsCornered") then corneredCount = corneredCount + 1 end
            end
        end
    end

    local logs = game:GetService("LogService"):GetLogHistory()
    local errCount = 0
    local errMsgs = {}
    for _, entry in ipairs(logs) do
        if entry.messageType == Enum.MessageType.MessageError then
            errCount = errCount + 1
            if #errMsgs < 3 then table.insert(errMsgs, entry.message:sub(1, 120)) end
        end
    end

    return HttpService:JSONEncode({
        alive = alive,
        total = #quins,
        states = states,
        decisions = decisions,
        retreating = retreatingCount,
        recovery = recoveryCount,
        cornered = corneredCount,
        errorCount = errCount,
        sampleErrors = errMsgs
    })
    """
    s_res = client.execute_luau(sample_code, datamodel_type="Server")
    s_raw = s_res.get("result", {}).get("content", [{}])[0].get("text", "")
    try:
        data = json.loads(s_raw)
        print(f"[{i*5+5:2d}s] Alive: {data['alive']}/{data['total']} | States: {data['states']} | Decisions: {data['decisions']} | Errors: {data['errorCount']}")
        if data['errorCount'] > 0 and data.get('sampleErrors'):
            print("     Errors:", data['sampleErrors'])
    except Exception as e:
        print(f"[{i*5+5:2d}s] Raw: {s_raw[:200]}")

print("\nSimulation test complete.")
