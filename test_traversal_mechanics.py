import sys
import time
import os
import json

sys.stdout.reconfigure(encoding='utf-8')
sys.path.insert(0, r"C:\Users\User\.gemini\antigravity\scratch\Tools\Utilities")

from roblox_client import RobloxStudioClient
client = RobloxStudioClient()
print("Connected Studio ID:", client.studio_id)

test_code = """
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local QuinCore = ReplicatedStorage:WaitForChild("QuinCore")
local SpatialModule = require(QuinCore:WaitForChild("Modules"):WaitForChild("SpatialModule"))
local SlideState = require(QuinCore:WaitForChild("States"):WaitForChild("SlideState"))
local WallRunState = require(QuinCore:WaitForChild("States"):WaitForChild("WallRunState"))
local QuinSpawner = require(game.ServerScriptService:WaitForChild("QuinSpawner"))

local results = {}

-- 1. Create a temporary obstacle wall for testing
local testWall = Instance.new("Part")
testWall.Name = "OB_TestWall"
testWall.Size = Vector3.new(4, 15, 30)
testWall.Position = Vector3.new(0, 7.5, 0)
testWall.Anchored = true
testWall.CanCollide = true
testWall.Parent = Workspace

-- Spawn test Quin facing near the wall at an angle
local p1 = Vector3.new(-6, 2, -5)
local quin = QuinSpawner.spawn("TypeC", p1, "TeamAlpha", "Water", Vector3.new(0, 2, 10))
task.wait(0.2)

local rootPart = quin:FindFirstChild("HumanoidRootPart")
local hum = quin:FindFirstChildOfClass("Humanoid")

-- TEST 1: Wall-Run Detection & Enter
local wallInfo = SpatialModule.detectWallRunSurface(rootPart, 8.0)
results.wallDetected = (wallInfo ~= nil)
if wallInfo then
    results.wallSide = wallInfo.side
    results.wallTangent = tostring(wallInfo.tangent)
end

-- Enter WallRun
WallRunState.enter(quin, hum, rootPart)
results.stateAfterWallEnter = quin:GetAttribute("CurrentState")
local bv = rootPart:FindFirstChild("WallRun_Velocity")
results.hasWallVelocity = (bv ~= nil)

-- Let it run for 0.1s then dismount
task.wait(0.1)
local nextState = WallRunState.update(quin, hum, rootPart, false)
results.wallRunRunning = (nextState == WallRunState or nextState.name == "WallRun")

WallRunState.exit(quin, hum, rootPart)
results.wallVelocityCleaned = (rootPart:FindFirstChild("WallRun_Velocity") == nil)

-- TEST 2: Ground Slide Enter & Exit
SlideState.enter(quin, hum, rootPart)
results.stateAfterSlideEnter = quin:GetAttribute("CurrentState")
local slideBv = rootPart:FindFirstChild("Slide_Impulse")
results.hasSlideImpulse = (slideBv ~= nil)

task.wait(0.1)
local slideNext = SlideState.update(quin, hum, rootPart, false)
results.slideRunning = (slideNext == SlideState or slideNext.name == "Slide")

SlideState.exit(quin, hum, rootPart)
results.slideImpulseCleaned = (rootPart:FindFirstChild("Slide_Impulse") == nil)

-- Cleanup test fixtures
quin:Destroy()
testWall:Destroy()

return HttpService:JSONEncode(results)
"""

res = client.execute_luau(test_code, datamodel_type="Server")
raw = res.get("result", {}).get("content", [{}])[0].get("text", "")
print("Traversal unit test results:", raw)
client.close()
