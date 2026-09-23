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
local LocomotionModule = require(QuinCore.Modules.LocomotionModule)
local SpatialModule = require(QuinCore.Modules.SpatialModule)
local CombatConfig = require(QuinCore.CombatConfig)

local arena = workspace:FindFirstChild("MovementTestArena")
if not arena then return "ERROR: MovementTestArena not found" end

-- Create dummy character model
local dummyModel = Instance.new("Model")
dummyModel.Name = "TestQuin"
local dummyHRP = Instance.new("Part")
dummyHRP.Name = "HumanoidRootPart"
dummyHRP.Size = Vector3.new(2, 2, 1)
dummyHRP.Anchored = true
dummyHRP.CanCollide = false
dummyHRP.Parent = dummyModel
dummyModel.PrimaryPart = dummyHRP
dummyModel.Parent = workspace

local testHurdles = {
    { name = "Hurdle_2s", zFront = 613, hurdleTop = 4.0, targetZ = 1038.5 },
    { name = "Hurdle_5s", zFront = 649, hurdleTop = 7.0, targetZ = 1038.5 },
    { name = "Hurdle_8s", zFront = 676, hurdleTop = 10.0, targetZ = 1038.5 },
    { name = "Hurdle_10s", zFront = 706, hurdleTop = 12.0, targetZ = 1038.5 },
}

local results = {}

for _, th in ipairs(testHurdles) do
    local testZ = th.zFront - 3.5
    dummyHRP.CFrame = CFrame.lookAt(Vector3.new(29.5, 4.5, testZ), Vector3.new(29.5, 4.5, th.targetZ))

    local targetPos = Vector3.new(24.5, 4.5, th.targetZ)
    local obsInfo = SpatialModule.analyzeObstacleAhead(dummyHRP, targetPos, 22)
    local hasObs, height = LocomotionModule.detectObstacle(dummyHRP)

    local targetJumpHeight = math.clamp(obsInfo.height or 8.0, 3.0, 14.0)
    local v_y = math.sqrt(2 * workspace.Gravity * targetJumpHeight)

    table.insert(results, {
        hurdle = th.name,
        zFront = th.zFront,
        testZ = testZ,
        hasObstacle = obsInfo.hasObstacle,
        heightAhead = obsInfo.height,
        canVault = obsInfo.canVault,
        isTall = obsInfo.isTall,
        locoDetect = hasObs,
        locoHeight = height,
        ballisticVy = math.floor(v_y * 10) / 10,
    })
end

dummyModel:Destroy()

return game:GetService("HttpService"):JSONEncode(results)
"""

res = client.execute_luau(test_code, datamodel_type="Edit")
out = res.get("result", {}).get("content", [{}])[0].get("text", "{}")
print("Hurdle Detection & Ballistic Calculations:")
try:
    parsed = json.loads(out)
    for item in parsed:
        print(f"  [{item['hurdle']}] At Z={item['testZ']:.1f} -> SpatialObs: {item['hasObstacle']} (canVault={item.get('canVault')}, isTall={item.get('isTall')}, height={item.get('heightAhead', 0):.1f}s) | LocoDetect: {item['locoDetect']} (height={item.get('locoHeight', 0):.1f}s) | Ballistic v_y = {item['ballisticVy']} st/s")
except Exception as e:
    print("Raw output:", out)
client.close()
