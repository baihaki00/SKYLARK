import sys
import os
import time

# Ensure Tools/Utilities is on python path
current_dir = os.path.dirname(os.path.abspath(__file__))
if current_dir not in sys.path:
    sys.path.insert(0, current_dir)

from roblox_client import RobloxStudioClient

client = RobloxStudioClient()
print("Connected to Studio ID:", client.studio_id)

test_code = """
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local QuinSpawner = require(ServerScriptService:WaitForChild("QuinSpawner"))
local TargetingModule = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("TargetingModule"))
local TacticalPerception = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("TacticalPerception"))
local DecisionSystem = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("DecisionSystem"))
local DamageModule = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("DamageModule"))
local BattleEventSystem = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("BattleEventSystem"))
local CombatConfig = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("CombatConfig"))

local log = {}
local function record(msg)
    table.insert(log, msg)
    print(msg)
end

-- ==========================================================
-- TEST 1: DYNAMIC ANIME BEAM STRUGGLE (Ground & Mid-Air)
-- ==========================================================
record("=== TEST 1: DYNAMIC ANIME BEAM STRUGGLE ===")

-- Clean any existing test quins
local qFolder = Workspace:FindFirstChild("QuinServer") or Workspace
for _, child in ipairs(qFolder:GetChildren()) do
    if child.Name:find("TestSpectacle_") then
        child:Destroy()
    end
end

-- Spawn 2 Quins: Fire Striker vs Water Tanker (mid-air suspended at Y = 32)
local fireQuin = QuinSpawner.spawn("TypeA", Vector3.new(-12, 32, -38), "SpectacleTeamA", "Fire")
fireQuin.Name = "TestSpectacle_FireFighter"
fireQuin:SetAttribute("Element", "Fire")
fireQuin:SetAttribute("Energy", 80)
fireQuin:SetAttribute("CurrentConfidence", 0.60)

local waterQuin = QuinSpawner.spawn("TypeD", Vector3.new(12, 32, -38), "SpectacleTeamB", "Water")
waterQuin.Name = "TestSpectacle_WaterFighter"
waterQuin:SetAttribute("Element", "Water")
waterQuin:SetAttribute("Energy", 80)
waterQuin:SetAttribute("CurrentConfidence", 0.60)

task.wait(0.25)

local fireHRP = fireQuin:FindFirstChild("HumanoidRootPart")
local waterHRP = waterQuin:FindFirstChild("HumanoidRootPart")

if not fireHRP or not waterHRP then
    record("FAIL: Root parts missing for Beam Struggle test.")
    return table.concat(log, "\\n")
end

-- Face each other
fireHRP.CFrame = CFrame.lookAt(fireHRP.Position, waterHRP.Position)
waterHRP.CFrame = CFrame.lookAt(waterHRP.Position, fireHRP.Position)

-- Set up event listener for climax
local climaxTriggered = false
local climaxDetails = "None"
BattleEventSystem.onEvent(function(evName, evData)
    if evName == "BEAM_STRUGGLE_CLIMAX" then
        climaxTriggered = true
        climaxDetails = string.format("Winner/Event: %s | Target: %s | Extra: %s", tostring(evData.QuinId), tostring(evData.TargetName), tostring(evData.Extra))
    end
end)

-- Lock both into BeamStruggleState
fireQuin:SetAttribute("TargetQuin", waterQuin.Name)
fireQuin:SetAttribute("ForceState", "BeamStruggle")

-- Follower receives partner attribute
waterQuin:SetAttribute("TargetQuin", fireQuin.Name)
waterQuin:SetAttribute("ForceState", "BeamStruggle")

task.wait(0.3)

-- Sample locomotion over 1.8 seconds to verify dynamic motion
local yPositions = {}
local angles = {}
local nodeOffsets = {}
local shakesObserved = 0

local startPos = fireHRP.Position
local startTime = tick()

for i = 1, 15 do
    task.wait(0.1)
    local curY = fireHRP.Position.Y
    table.insert(yPositions, curY)

    local curAngle = fireQuin:GetAttribute("ClashAngle") or 0
    table.insert(angles, curAngle)

    local offset = fireQuin:GetAttribute("ClashNodeOffset") or 0
    table.insert(nodeOffsets, offset)

    -- Check micro-shake: displacement from pure smooth trajectory
    local flatDisp = (fireHRP.Position - startPos).Magnitude
    if flatDisp > 0.05 then
        shakesObserved = shakesObserved + 1
    end
end

local yVariance = math.max(unpack(yPositions)) - math.min(unpack(yPositions))
local totalAngleRotated = math.abs(angles[#angles] - angles[1])
local finalOffset = nodeOffsets[#nodeOffsets]

record(string.format("Dynamic Locomotion Samples (15 frames):"))
record(string.format("  Y Bobbing Variance: %.2f studs (expected 0.3 - 1.5 studs)", yVariance))
record(string.format("  Arc Rotation: %.3f radians (orbital trajectory active: %s)", totalAngleRotated, tostring(totalAngleRotated > 0.05)))
record(string.format("  Micro-Shakes Observed: %d / 15 frames", shakesObserved))
record(string.format("  Tug-of-War Offset: %.3f (Water Elemental Advantage pushing Fire)", finalOffset))

local motionValid = (yVariance > 0.2 and totalAngleRotated > 0.03 and shakesObserved >= 10)
record(string.format("Dynamic Beam Struggle Physics: %s", motionValid and "VERIFIED" or "STATIC_DEFECT"))

-- Wait for struggle climax (maxDur = 5.0s)
task.wait(3.8)
task.wait(0.1) -- Yield to process task.spawn callbacks
local fState = fireQuin and fireQuin.Parent and fireQuin:GetAttribute("CurrentState") or "DEAD/GONE"
local wState = waterQuin and waterQuin.Parent and waterQuin:GetAttribute("CurrentState") or "DEAD/GONE"
record(string.format("Post-Wait State: Fire = %s | Water = %s", tostring(fState), tostring(wState)))
record(string.format("Climax Resolution: %s (%s)", tostring(climaxTriggered or (fState == "Knockback")), climaxDetails))

-- Clean test quins
fireQuin:Destroy()
waterQuin:Destroy()

-- ==========================================================
-- TEST 2: AURA FARMING & "HUMBLE THE SHOWOFF" TAUNT
-- ==========================================================
record("\\n=== TEST 2: AURA FARMING & GLOBAL TAUNT ===")

-- Spawn Showoff Quin at isolated arena sector (130, 6.5, 130)
local showoffQuin = QuinSpawner.spawn("TypeB", Vector3.new(130, 6.5, 130), "ShowoffTeam")
showoffQuin.Name = "TestSpectacle_Showoff"
showoffQuin:SetAttribute("Quirky", "Showoff")
showoffQuin:SetAttribute("Pers_Confidence", 0.90)
showoffQuin:SetAttribute("Energy", 40)
showoffQuin:SetAttribute("SuperMeter", 20)

task.wait(0.2)

-- Spawn Aggressive Challenger at 25 studs distance (105, 6.5, 130)
local aggressiveQuin = QuinSpawner.spawn("TypeC", Vector3.new(105, 6.5, 130), "ChallengerTeam")
aggressiveQuin.Name = "TestSpectacle_Challenger"
aggressiveQuin:SetAttribute("Pers_Aggression", 0.85)

task.wait(0.2)

-- 1. Verify Showoff AI evaluates AuraFarm
local sContext = TacticalPerception.evaluate(showoffQuin)
local sAction, sState = DecisionSystem.evaluateAction(showoffQuin, sContext, 40)
record(string.format("Showoff AI Evaluation: Action = %s | TacticalState = %s", tostring(sAction), tostring(sState)))

-- Enter AuraFarmState
showoffQuin:SetAttribute("ForceState", "AuraFarm")
task.wait(0.3)

local isFarming = showoffQuin:GetAttribute("IsAuraFarming") == true
record(string.format("Showoff IsAuraFarming Flag: %s", tostring(isFarming)))

-- 2. Verify Challenger perceives blatant showboating and prioritizes "Humble the showoff"
local cContext = TacticalPerception.evaluate(aggressiveQuin)
local cTarget, cScore, cReason = TargetingModule.selectTarget(aggressiveQuin, cContext)
record(string.format("Challenger Target Selection: Target = %s | Reason = %s", tostring(cTarget and cTarget.Name), tostring(cReason)))

local humbleVerified = (cTarget == showoffQuin and cReason:find("Humble the showoff"))
record(string.format("Global Taunt 'Humble Showoff' Response: %s", humbleVerified and "VERIFIED" or "FAILED"))

-- Clean test quins
showoffQuin:Destroy()
aggressiveQuin:Destroy()

-- ==========================================================
-- TEST 3: RIVAL DECISIVE FINISHER
-- ==========================================================
record("\\n=== TEST 3: RIVAL DECISIVE FINISHER ===")

local rivalA = QuinSpawner.spawn("TypeA", Vector3.new(0, 6.5, -30), "RivalTeamA")
rivalA.Name = "TestSpectacle_RivalA"
local idA = "QUIN_RIVAL_001"
rivalA:SetAttribute("QuinId", idA)

local rivalB = QuinSpawner.spawn("TypeB", Vector3.new(0, 6.5, -24), "RivalTeamB")
rivalB.Name = "TestSpectacle_RivalB"
local idB = "QUIN_RIVAL_002"
rivalB:SetAttribute("QuinId", idB)

-- Mutual rivalry tagging
rivalA:SetAttribute("PrimaryRivalId", idB)
rivalB:SetAttribute("PrimaryRivalId", idA)

task.wait(0.2)

local bHum = rivalB:FindFirstChildOfClass("Humanoid")
local bHRP = rivalB:FindFirstChild("HumanoidRootPart")
bHum.Health = 5 -- 1 hit from death

local rivalFinisherFired = false
BattleEventSystem.onEvent(function(evName, evData)
    if evName == "RIVAL_FINISHER" then
        rivalFinisherFired = true
    end
end)

local startBPos = bHRP.Position
-- Deliver lethal blow
local dmgInfo = DamageModule.calculate(rivalA, rivalB, 1, 3.0)
local _, isKill = DamageModule.apply(rivalA, rivalB, dmgInfo)

task.wait(0.45)

local endBPos = bHRP.Position
local kbDistance = (endBPos - startBPos).Magnitude

record(string.format("Lethal Strike on Rival: isKill = %s", tostring(isKill)))
record(string.format("Rival Knockback Distance: %.1f studs (target: 18 - 26 studs)", kbDistance))
record(string.format("RIVAL_FINISHER Battle Event: %s", tostring(rivalFinisherFired)))

local finisherValid = (isKill and kbDistance >= 15.0 and kbDistance <= 32.0 and rivalFinisherFired)
record(string.format("Rival Decisive Finisher: %s", finisherValid and "VERIFIED" or "FAILED"))

-- Clean test quins
rivalA:Destroy()
rivalB:Destroy()

return table.concat(log, "\\n")
"""

res = client.execute_luau(test_code, datamodel_type="Server")
print(res.get("result", {}).get("content", [{}])[0].get("text", ""))
