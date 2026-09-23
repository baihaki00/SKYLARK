import sys
sys.path.append(r"C:\Users\User\.gemini\antigravity\scratch\Tools\Utilities")
from roblox_client import RobloxStudioClient

client = RobloxStudioClient()

code = """
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local states = ReplicatedStorage.QuinCore.States

-- 1. Fix AnticipateState
local ant = states:FindFirstChild("AnticipateState")
if ant then
    ant.Source = [[
--// AnticipateState.lua (Active Match Safe)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local AnticipateState = { name = "Anticipate" }

function AnticipateState.enter(fighter, humanoid, rootPart)
    humanoid.WalkSpeed = 0
end

function AnticipateState.exit(fighter, humanoid, rootPart)
end

function AnticipateState.update(fighter, humanoid, rootPart, DEBUG)
    return require(script.Parent:WaitForChild("ChaseState"))
end

return AnticipateState
]]
end

-- 2. Fix TestEndState
local te = states:FindFirstChild("TestEndState")
if te then
    te.Source = [[
--// TestEndState.lua (Active Match Safe)
local Workspace = game:GetService("Workspace")
local TestEndState = { name = "TestEnd" }

function TestEndState.enter(fighter, humanoid, rootPart)
    humanoid.WalkSpeed = 0
end

function TestEndState.exit(fighter, humanoid, rootPart)
end

function TestEndState.update(fighter, humanoid, rootPart, DEBUG)
    local matchStarted = Workspace:GetAttribute("MatchStarted")
    if matchStarted ~= false then
        return require(script.Parent:WaitForChild("ChaseState"))
    end
    humanoid.WalkSpeed = 0
    return TestEndState
end

return TestEndState
]]
end

return "Successfully updated AnticipateState and TestEndState in Studio!"
"""

print("Updating AnticipateState and TestEndState in Studio...")
res = client.execute_luau(code, datamodel_type="Edit")
print("Result:", res.get("result", {}).get("content", [{}])[0].get("text", ""))
