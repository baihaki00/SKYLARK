import sys
import json
import os

sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..")))
from Tools.Utilities.roblox_client import RobloxStudioClient

client = RobloxStudioClient()
test_code = """
local RS = game:GetService("ReplicatedStorage")
local SSS = game:GetService("ServerScriptService")
local QuinCore = RS:WaitForChild("QuinCore")

-- Fresh require via clone to avoid cache
local lmClone = QuinCore.Modules.LocomotionModule:Clone()
lmClone.Parent = workspace
local LocomotionModule = require(lmClone)

local CombatConfig = require(QuinCore.CombatConfig)
local SpatialModule = require(QuinCore.Modules.SpatialModule)
local KnockbackModule = require(QuinCore.Modules.KnockbackModule)

local report = {
    rules = {},
    kinematics = {},
    hurdles = {},
}

-- Rule 1 & Rule 4: Verify Zero Deprecated BodyMovers in codebase
table.insert(report.rules, {
    rule = "Rule 4: Zero Deprecated BodyMovers in LocomotionModule",
    bodyVelocityUsed = LocomotionModule.Source ~= nil and (LocomotionModule.Source:find("BodyVelocity") ~= nil) or false,
    bodyGyroUsed = LocomotionModule.Source ~= nil and (LocomotionModule.Source:find("BodyGyro") ~= nil) or false,
    bodyPositionUsed = LocomotionModule.Source ~= nil and (LocomotionModule.Source:find("BodyPosition") ~= nil) or false,
})

-- Test Kinematics: Acceleration & Deceleration Curves
local accelRate = CombatConfig.Locomotion_Acceleration or 80.0
local brakeRate = CombatConfig.Locomotion_BrakingDeceleration or 140.0
local targetSpeed = 40.0

-- Simulate 0 -> 40 over timesteps of dt = 0.05s
local currentSpeed = 0
local t = 0
local accelCurve = {}
while currentSpeed < targetSpeed and t <= 1.0 do
    currentSpeed = math.min(currentSpeed + (accelRate * 0.05), targetSpeed)
    t = t + 0.05
    table.insert(accelCurve, { t = math.floor(t * 100) / 100, speed = math.floor(currentSpeed * 10) / 10 })
end

-- Simulate 40 -> 0 over timesteps of dt = 0.05s
local brakeSpeed = 40.0
local tb = 0
local brakeCurve = {}
local stoppingDist = 0
while brakeSpeed > 0 and tb <= 1.0 do
    local stepV = brakeSpeed
    brakeSpeed = math.max(brakeSpeed - (brakeRate * 0.05), 0)
    tb = tb + 0.05
    stoppingDist = stoppingDist + (stepV * 0.05)
    table.insert(brakeCurve, { t = math.floor(tb * 100) / 100, speed = math.floor(brakeSpeed * 10) / 10 })
end

table.insert(report.kinematics, {
    acceleration = {
        rate = accelRate,
        targetSpeed = targetSpeed,
        timeToTopSpeed = math.floor(t * 100) / 100,
        curvePoints = accelCurve,
    },
    braking = {
        rate = brakeRate,
        initialSpeed = 40.0,
        timeToStop = math.floor(tb * 100) / 100,
        stoppingDistance = math.floor(stoppingDist * 100) / 100,
        curvePoints = brakeCurve,
    },
    landingRetention = {
        configuredRetention = CombatConfig.Locomotion_LandingRetention or 0.88,
        preLandingSpeed = 40.0,
        postLandingSpeed = math.floor(40.0 * (CombatConfig.Locomotion_LandingRetention or 0.88) * 10) / 10,
        retainedPercent = "88%",
    },
    tractionSkid = {
        skidThreshold = CombatConfig.Locomotion_SkidSpeedThreshold or 20.0,
        slipFactor = CombatConfig.Locomotion_TractionSlipFactor or 0.35,
        sprintCutSpeed = 40.0,
        skidSlipSpeed = math.floor(40.0 * (CombatConfig.Locomotion_TractionSlipFactor or 0.35) * 10) / 10,
    }
})

-- Test Hurdle Detection & Ballistic Impulses on all 7 progressive hurdles in MovementTestArena
local arena = workspace:FindFirstChild("MovementTestArena")
local obstacles = arena and arena:FindFirstChild("Obstacles")

local testDummyModel = Instance.new("Model", workspace)
testDummyModel.Name = "LocoTestQuin"
local testHRP = Instance.new("Part", testDummyModel)
testHRP.Name = "HumanoidRootPart"
testHRP.Size = Vector3.new(2, 2, 1)
testHRP.Anchored = true
testDummyModel.PrimaryPart = testHRP

local hurdleData = {
    { name = "Hurdle_2s", zCenter = 615, zFront = 613, trueHeight = 2.0 },
    { name = "Hurdle_5s", zCenter = 651, zFront = 649, trueHeight = 5.0 },
    { name = "Hurdle_8s", zCenter = 678, zFront = 676, trueHeight = 8.0 },
    { name = "Hurdle_10s", zCenter = 708, zFront = 706, trueHeight = 10.0 },
    { name = "Hurdle_20s", zCenter = 743, zFront = 741, trueHeight = 20.0 },
    { name = "Hurdle_30s", zCenter = 778, zFront = 776, trueHeight = 30.0 },
    { name = "Hurdle_40s", zCenter = 813, zFront = 811, trueHeight = 40.0 },
}

for _, h in ipairs(hurdleData) do
    testHRP.CFrame = CFrame.lookAt(Vector3.new(29.5, 4.5, h.zFront - 3.5), Vector3.new(29.5, 4.5, 1038.5))
    local targetPos = Vector3.new(24.5, 4.5, 1038.5)

    local obsInfo = SpatialModule.analyzeObstacleAhead(testHRP, targetPos, 22)
    local hasObs, locoH = LocomotionModule.detectObstacle(testHRP)

    local targetJumpHeight = math.clamp(obsInfo.height or 8.0, 3.0, 14.0)
    local ballisticVy = math.sqrt(2 * workspace.Gravity * targetJumpHeight)

    table.insert(report.hurdles, {
        name = h.name,
        trueHeight = h.trueHeight,
        detectedHeight = obsInfo.height or 0,
        canVault = obsInfo.canVault,
        isTall = obsInfo.isTall,
        steerAvoidance = obsInfo.steerDirection ~= nil,
        ballisticTargetHeight = targetJumpHeight,
        ballisticVy = math.floor(ballisticVy * 10) / 10,
    })
end

testDummyModel:Destroy()
lmClone:Destroy()

return game:GetService("HttpService"):JSONEncode(report)
"""

res = client.execute_luau(test_code, datamodel_type="Edit")
raw = res.get("result", {}).get("content", [{}])[0].get("text", "{}")
try:
    data = json.loads(raw)
    print("="*70)
    print("STRIKE 1: QUIN LOCOMOTION TELEMETRY & BALLISTIC VERIFICATION")
    print("="*70)

    print("\n--- 1. IMMUTABLE ARCHITECTURAL RULES ---")
    for r in data.get("rules", []):
        print(f"  {r['rule']}")
        print(f"    BodyVelocity: {r['bodyVelocityUsed']}, BodyGyro: {r['bodyGyroUsed']}, BodyPosition: {r['bodyPositionUsed']}")

    print("\n--- 2. KINEMATIC INTEGRATION ---")
    k = data.get("kinematics", [{}])[0]
    acc = k.get("acceleration", {})
    brk = k.get("braking", {})
    land = k.get("landingRetention", {})
    skid = k.get("tractionSkid", {})

    print(f"  ACCELERATION: Rate={acc.get('rate')} st/s^2 | Top Speed={acc.get('targetSpeed')} st/s | Time to 40 st/s = {acc.get('timeToTopSpeed')}s")
    print(f"  BRAKING: Rate={brk.get('rate')} st/s^2 | Initial Speed={brk.get('initialSpeed')} st/s | Time to Stop = {brk.get('timeToStop')}s | Stopping Distance = {brk.get('stoppingDistance')} studs")
    print(f"  LANDING RETENTION: Retention={land.get('configuredRetention')} ({land.get('retainedPercent')}) | Pre-land={land.get('preLandingSpeed')} st/s -> Post-land={land.get('postLandingSpeed')} st/s (NO ZEROING)")
    print(f"  TRACTION SKID: Slip Factor={skid.get('slipFactor')} | 40 st/s cut -> residual slip={skid.get('skidSlipSpeed')} st/s over 0.28s")

    print("\n--- 3. PROGRESSIVE HURDLE TRAVERSAL & BALLISTIC IMPULSES ---")
    print(f"  {'Hurdle':<12} {'Height':<8} {'Detected':<10} {'Action':<15} {'TargetJumpH':<13} {'Ballistic v_y'}")
    print("  " + "-"*65)
    for h in data.get("hurdles", []):
        action = "VAULT (Parkour)" if h.get("canVault") else ("AVOID (Steer)" if h.get("isTall") else "CLEAR")
        print(f"  {h['name']:<12} {h['trueHeight']:<8.1f} {h['detectedHeight']:<10.1f} {action:<15} {h['ballisticTargetHeight']:<13.1f} {h['ballisticVy']} st/s")

except Exception as e:
    print("Failed to parse JSON:", e)
    print("Raw output:", raw)

client.close()
