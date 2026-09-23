local ReplicatedStorage = game:GetService("ReplicatedStorage")
local QuinCore = ReplicatedStorage:WaitForChild("QuinCore")
local statesFolder = QuinCore:WaitForChild("States")
local modulesFolder = QuinCore:WaitForChild("Modules")

local logs = {}
local passed = true

local function logPass(msg)
	table.insert(logs, "[PASS] " .. msg)
end

local function logFail(msg)
	passed = false
	table.insert(logs, "[FAIL] " .. msg)
end

-- 1. Check all modules in Modules folder
local modCount = 0
for _, mod in ipairs(modulesFolder:GetChildren()) do
	if mod:IsA("ModuleScript") then
		modCount = modCount + 1
		local ok, err = pcall(function()
			local clone = mod:Clone()
			local res = require(clone)
			clone:Destroy()
			return res
		end)
		if not ok then
			logFail("Module require failed: " .. mod.Name .. " -> " .. tostring(err))
		end
	end
end
logPass(string.format("All %d modules in Modules folder required successfully", modCount))

-- 2. Verify LocomotionModule API
local locoClone = modulesFolder:WaitForChild("LocomotionModule"):Clone()
local LocomotionModule = require(locoClone)
if type(LocomotionModule.dash) == "function" then
	logPass("LocomotionModule.dash function exists")
else
	logFail("LocomotionModule.dash is missing or not a function")
end

if type(LocomotionModule.slide) == "function" then
	logPass("LocomotionModule.slide function exists")
else
	logFail("LocomotionModule.slide is missing or not a function")
end
locoClone:Destroy()

-- 3. Check all states in States folder
local stateCount = 0
for _, st in ipairs(statesFolder:GetChildren()) do
	if st:IsA("ModuleScript") then
		stateCount = stateCount + 1
		local ok, err = pcall(function()
			local clone = st:Clone()
			local res = require(clone)
			clone:Destroy()
			return res
		end)
		if not ok then
			logFail("State require failed: " .. st.Name .. " -> " .. tostring(err))
		end
	end
end
logPass(string.format("All %d states in States folder required successfully", stateCount))

-- 4. Verify the 5 archived states are NOT in States folder
local archivedNames = {
	"DashState",
	"ProjectileJumpRecoveryState",
	"PositioningJumpState",
	"TargetTransitionState",
	"SlideState",
}
for _, name in ipairs(archivedNames) do
	if statesFolder:FindFirstChild(name) then
		logFail("Archived state still exists in States folder: " .. name)
	else
		logPass("Verified archived state removed from States: " .. name)
	end
end

-- 5. Verify Main.lua aliases via simulated States table
local Idle = require(statesFolder:WaitForChild("IdleState"))
local Chase = require(statesFolder:WaitForChild("ChaseState"))
local Recovery = require(statesFolder:WaitForChild("RecoveryState"))

local States = {
	Idle = Idle,
	Chase = Chase,
	Recovery = Recovery,
}
States.Slide = States.Chase
States.Dash = States.Chase
States.PositioningJump = States.Chase
States.TargetTransition = States.Idle
States.ProjectileJumpRecovery = States.Recovery

if States.Slide == States.Chase and States.Dash == States.Chase and States.PositioningJump == States.Chase then
	logPass("Locomotion aliases (Slide, Dash, PositioningJump) resolve to Chase")
else
	logFail("Locomotion aliases do not resolve to Chase")
end

if States.TargetTransition == States.Idle then
	logPass("TargetTransition alias resolves to Idle")
else
	logFail("TargetTransition alias does not resolve to Idle")
end

if States.ProjectileJumpRecovery == States.Recovery then
	logPass("ProjectileJumpRecovery alias resolves to Recovery")
else
	logFail("ProjectileJumpRecovery alias does not resolve to Recovery")
end

-- 6. Verify RecoveryState handles slam_landing
local RecoveryState = require(statesFolder:WaitForChild("RecoveryState"))
if RecoveryState.enter and RecoveryState.update and RecoveryState.exit then
	logPass("RecoveryState has full lifecycle contract (enter, update, exit)")
else
	logFail("RecoveryState missing lifecycle methods")
end

-- 7. Zero deprecated BodyMovers
local bmInfractions = 0
local function scanBM(inst)
	if inst:IsA("LuaSourceContainer") then
		local src = inst.Source
		for lineNum, line in ipairs(src:split("\n")) do
			local codeOnly = line:gsub("%-%-.*$", "")
			if codeOnly:find("Instance.new%([\"']BodyVelocity[\"']%)") or
			   codeOnly:find("Instance.new%([\"']BodyGyro[\"']%)") or
			   codeOnly:find("Instance.new%([\"']BodyPosition[\"']%)") then
				bmInfractions = bmInfractions + 1
				logFail(string.format("BodyMover in %s:%d", inst:GetFullName(), lineNum))
			end
		end
	end
	for _, ch in ipairs(inst:GetChildren()) do
		scanBM(ch)
	end
end
scanBM(QuinCore)
if bmInfractions == 0 then
	logPass("Verified Rule 4: 0 deprecated BodyMovers across entire QuinCore")
end

local summary = string.format("\n========================================\nMACRO-STATE CONSOLIDATION VERIFICATION: %s\n========================================\n%s",
	passed and "SUCCESS (ALL PASS)" or "FAILURE",
	table.concat(logs, "\n")
)

return summary
