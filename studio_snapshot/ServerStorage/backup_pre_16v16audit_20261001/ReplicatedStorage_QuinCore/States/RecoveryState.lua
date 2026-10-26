--// RecoveryState.lua
-- Dedicated state for getting back up from a stun, knockdown, or prone tumble
-- Restores physical upright orientation, engages GettingUp humanoid state, and plays get-up animation

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local AnimationModule = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("AnimationModule"))
local AnimationIds = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("AnimationIds"))
local RuntimeTracer = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("RuntimeTracer"))
local LocomotionModule = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("LocomotionModule"))

local RecoveryState = { name = "Recovery" }

local recoveryData = {}

function RecoveryState.enter(fighter, humanoid, rootPart)
	local kbType = fighter:GetAttribute("KnockbackType") or "ground"
	
	LocomotionModule.brake(fighter, humanoid, rootPart, 0.05)
	humanoid.WalkSpeed = 0
	humanoid.PlatformStand = false

	-- Physical Upright Alignment & Floor Clearance
	local upY = rootPart.CFrame.UpVector.Y
	if upY < 0.85 then
		-- Prone tumble recovery: lift +1.2 studs to clear floor collision mesh so HipHeight raycast engages cleanly
		local lookFlat = Vector3.new(rootPart.CFrame.LookVector.X, 0, rootPart.CFrame.LookVector.Z)
		if lookFlat.Magnitude < 0.05 then
			lookFlat = Vector3.new(-rootPart.CFrame.UpVector.X, 0, -rootPart.CFrame.UpVector.Z)
			if lookFlat.Magnitude < 0.05 then
				lookFlat = Vector3.new(0, 0, -1)
			end
		end
		lookFlat = lookFlat.Unit
		local currentPos = rootPart.Position
		rootPart.CFrame = CFrame.lookAt(currentPos + Vector3.new(0, 1.2, 0), currentPos + Vector3.new(0, 1.2, 0) + lookFlat, Vector3.new(0, 1, 0))
	end

	rootPart.AssemblyLinearVelocity = Vector3.zero
	rootPart.AssemblyAngularVelocity = Vector3.zero
	humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)

	-- Pick animation: prioritize GetUpGround / GetUpAir
	local animId = AnimationIds.GetUpGround or AnimationIds.GetUpAir
	local duration = 1.2

	-- Fast recovery for light ground flinches where Quin is already upright
	if kbType == "ground" and upY >= 0.85 then
		animId = nil
		duration = 0.2
	elseif kbType == "slam_landing" then
		animId = nil
		duration = 0.35
		AnimationModule.playConfig(humanoid, "Attacks.Specials.SlamImpact", 1.0, Enum.AnimationPriority.Action4, false)
	end

	recoveryData[fighter] = {
		enterTime = tick(),
		animId = animId,
		duration = duration
	}
	
	RuntimeTracer.checkpoint(fighter, string.format("Enter Recovery (Type=%s, ProneUpY=%.2f)", kbType, upY))
	
	if animId then
		AnimationModule.play(humanoid, animId, Enum.AnimationPriority.Action4, false, 1.0, 0.15)
	end
end

function RecoveryState.exit(fighter, humanoid, rootPart)
	RuntimeTracer.checkpoint(fighter, "Recovery Complete → Return to Combat")
	local data = recoveryData[fighter]
	if data and data.animId then
		AnimationModule.stop(humanoid, data.animId, 0.2)
	end
	
	-- Purge residual reaction tracks
	AnimationModule.stopConfig(humanoid, "Attacks.Specials.SlamImpact", 0.15)
	AnimationModule.stop(humanoid, AnimationIds.FallAirKnockback, 0.1)
	AnimationModule.stop(humanoid, AnimationIds.Knockback, 0.1)
	AnimationModule.stop(humanoid, AnimationIds.KnockbackExtreme, 0.1)
	
	humanoid.PlatformStand = false
	rootPart.AssemblyAngularVelocity = Vector3.zero
	
	fighter:SetAttribute("KnockbackType", nil)
	recoveryData[fighter] = nil
end

function RecoveryState.update(fighter, humanoid, rootPart, DEBUG)
	local showdownRole = fighter:GetAttribute("LeaderShowdownRole")
	if showdownRole == "Duelist" then
		local LeaderShowdownSystem = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("LeaderShowdownSystem"))
		LeaderShowdownSystem.constrainToRing(rootPart)
	end

	local data = recoveryData[fighter]
	if not data then return require(script.Parent:WaitForChild("IdleState")) end
	
	local elapsed = tick() - data.enterTime
	
	if elapsed >= data.duration then
		return require(script.Parent:WaitForChild("CirclingState"))
	end
	
	-- Keep them grounded, upright, and still during get-up
	humanoid.WalkSpeed = 0
	humanoid:MoveTo(rootPart.Position)
	
	return RecoveryState
end

return RecoveryState
