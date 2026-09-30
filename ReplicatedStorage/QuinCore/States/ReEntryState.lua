--// ReEntryState.lua
-- Dedicated cinematic out-of-bounds return state:
-- 1. Orient to arena center (0, Y, 0)
-- 2. Confident walk toward arena (0.8s)
-- 3. Accelerate into run/sprint (0.6s)
-- 4. Super Wall-Clearing Leap (Vy = 260, Vxz = 150) soaring over the 148-stud arena wall
-- 5. Crest the apex, descent, land on the arena floor into combat stance!

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local QuinCore = ReplicatedStorage:WaitForChild("QuinCore")
local AnimationModule = require(QuinCore:WaitForChild("Modules"):WaitForChild("AnimationModule"))
local AnimationIds = require(QuinCore:WaitForChild("AnimationIds"))
local AudioModule = require(QuinCore:WaitForChild("Modules"):WaitForChild("AudioModule"))
local SpatialModule = require(QuinCore:WaitForChild("Modules"):WaitForChild("SpatialModule"))

local ReEntryState = { name = "ReEntry" }

local reEntryData = {}

function ReEntryState.enter(fighter, humanoid, rootPart)
	if not fighter or not humanoid or not rootPart then return end

	humanoid.WalkSpeed = 0
	humanoid.PlatformStand = false

	-- Determine horizontal direction to arena center (0, Y, 0)
	local myPos = rootPart.Position
	local dirToCenter = Vector3.new(-myPos.X, 0, -myPos.Z)
	if dirToCenter.Magnitude > 0.001 then
		dirToCenter = dirToCenter.Unit
	else
		dirToCenter = Vector3.new(0, 0, -1)
	end

	-- Immediately snap/face arena center
	rootPart.CFrame = CFrame.lookAt(myPos, myPos + dirToCenter)

	reEntryData[fighter] = {
		enterTime = tick(),
		phase = "walk", -- Start with confident walk
		phaseStartTime = tick(),
		dirToCenter = dirToCenter,
		hasLeaped = false,
		lastFootstepTime = 0,
	}

	-- Start Phase 1: Confident Walk
	humanoid.WalkSpeed = 14
	AnimationModule.play(humanoid, AnimationIds.WalkConfident or AnimationIds.WalkThug, Enum.AnimationPriority.Action2, true, 1.0)
	humanoid:Move(dirToCenter)

	print(string.format("[ReEntryState] %s entered Cinematic Re-Entry! Facing arena center from (%.1f, %.1f, %.1f)", 
		fighter.Name, myPos.X, myPos.Y, myPos.Z))
end

function ReEntryState.exit(fighter, humanoid, rootPart)
	local data = reEntryData[fighter]
	if data then
		AnimationModule.stop(humanoid, AnimationIds.WalkConfident, 0.15)
		AnimationModule.stop(humanoid, AnimationIds.WalkThug, 0.15)
		AnimationModule.stop(humanoid, AnimationIds.Run, 0.15)
		AnimationModule.stop(humanoid, AnimationIds.Jump, 0.15)
		AnimationModule.stop(humanoid, AnimationIds.Fall, 0.15)
	end

	if humanoid then
		local defaultSpeed = fighter:GetAttribute("Speed") or 40
		humanoid.WalkSpeed = defaultSpeed
		humanoid.PlatformStand = false
	end

	if rootPart then
		local lv = rootPart:FindFirstChild("ReEntryVelocity")
		if lv then lv:Destroy() end
		local att = rootPart:FindFirstChild("ReEntryAtt")
		if att then att:Destroy() end
	end

	reEntryData[fighter] = nil
end

function ReEntryState.update(fighter, humanoid, rootPart, DEBUG)
	local data = reEntryData[fighter]
	if not data or not rootPart or not humanoid or humanoid.Health <= 0 then
		return require(script.Parent:WaitForChild("IdleState"))
	end

	local now = tick()
	local totalElapsed = now - data.enterTime
	local phaseElapsed = now - data.phaseStartTime

	-- Global Safety Timeout (7 seconds): Emergency teleport inside if anything stalled
	if totalElapsed > 7.0 then
		print(string.format("[ReEntryState] %s timed out during re-entry. Emergency placing at center.", fighter.Name))
		fighter:PivotTo(CFrame.new(0, 7.5, 0))
		rootPart.AssemblyLinearVelocity = Vector3.zero
		return require(script.Parent:WaitForChild("FightState"))
	end

	-- Recompute live horizontal direction to arena center
	local currentPos = rootPart.Position
	local dirToCenter = Vector3.new(-currentPos.X, 0, -currentPos.Z)
	if dirToCenter.Magnitude > 0.001 then
		dirToCenter = dirToCenter.Unit
		data.dirToCenter = dirToCenter
	end

	-- PHASE 1: Confident Walk (0.8 seconds)
	if data.phase == "walk" then
		humanoid.WalkSpeed = 14
		humanoid:Move(data.dirToCenter)
		rootPart.CFrame = CFrame.lookAt(currentPos, currentPos + data.dirToCenter)

		if now - data.lastFootstepTime > 0.4 then
			data.lastFootstepTime = now
			AudioModule.playFootstep(fighter, 0.4)
		end

		if phaseElapsed >= 0.8 then
			-- Transition to Phase 2: Run Acceleration
			data.phase = "run"
			data.phaseStartTime = now
			AnimationModule.stop(humanoid, AnimationIds.WalkConfident, 0.1)
			AnimationModule.stop(humanoid, AnimationIds.WalkThug, 0.1)
			AnimationModule.play(humanoid, AnimationIds.Run, Enum.AnimationPriority.Action2, true, 1.3)
			humanoid.WalkSpeed = 38
			print(string.format("[ReEntryState] %s accelerating into run sprint toward wall!", fighter.Name))
		end

		return ReEntryState

	-- PHASE 2: Run Acceleration (0.6 seconds)
	elseif data.phase == "run" then
		humanoid.WalkSpeed = 38
		humanoid:Move(data.dirToCenter)
		rootPart.CFrame = CFrame.lookAt(currentPos, currentPos + data.dirToCenter)

		if now - data.lastFootstepTime > 0.25 then
			data.lastFootstepTime = now
			AudioModule.playFootstep(fighter, 0.6)
		end

		if phaseElapsed >= 0.6 then
			-- Transition to Phase 3: The Super Wall-Clearing Leap!
			data.phase = "leap"
			data.phaseStartTime = now
			data.hasLeaped = true

			AnimationModule.stop(humanoid, AnimationIds.Run, 0.1)
			AnimationModule.play(humanoid, AnimationIds.Jump or AnimationIds.Uppercut, Enum.AnimationPriority.Action3, false, 1.2)

			-- Sound & Audio
			AudioModule.playJumpUp(currentPos)
			AudioModule.playSonicBoom(currentPos)

			-- Lift out of ground friction plane and set Freefall state
			humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
			rootPart.CFrame = rootPart.CFrame + Vector3.new(0, 1.5, 0)

			-- Super Velocity: Vy = 260 reaches apex Y ≈ 175-180 studs (clearing 148-stud wall easily)
			-- Vxz = 150 covers 250+ studs horizontally during the 2.6s parabolic flight
			local horizVelocity = data.dirToCenter * 150
			local vertVelocity = Vector3.new(0, 260, 0)
			local totalVelocity = horizVelocity + vertVelocity

			local att = Instance.new("Attachment")
			att.Name = "ReEntryAtt"
			att.Parent = rootPart

			local lv = Instance.new("LinearVelocity")
			lv.Name = "ReEntryVelocity"
			lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
			lv.MaxForce = 1e6
			lv.VectorVelocity = totalVelocity
			lv.Attachment0 = att
			lv.Parent = rootPart
			game:GetService("Debris"):AddItem(lv, 0.35)
			game:GetService("Debris"):AddItem(att, 0.35)

			rootPart.AssemblyLinearVelocity = totalVelocity

			print(string.format("[ReEntryState] %s UNLEASHED SUPER WALL-CLEARING LEAP! Vy=260, Vxz=150 toward arena center!", fighter.Name))
		end

		return ReEntryState

	-- PHASE 3: Mid-Air Flight & Landing
	elseif data.phase == "leap" then
		local yVel = rootPart.AssemblyLinearVelocity.Y

		-- Maintain horizontal heading toward center while airborne
		rootPart.CFrame = CFrame.lookAt(currentPos, currentPos + data.dirToCenter)

		-- Once vertical velocity becomes negative (descending after apex), switch to Fall animation
		if yVel < -10 and not data.isFallingAnimPlaying then
			data.isFallingAnimPlaying = true
			AnimationModule.play(humanoid, AnimationIds.Fall, Enum.AnimationPriority.Action3, true, 1.0)
		end

		-- Check touchdown: Must have spent at least 1.2s in the air (to reach apex and begin descending)
		if phaseElapsed > 1.2 then
			local isGrounded = SpatialModule.isGrounded(rootPart)
			local distFromCenter = Vector3.new(currentPos.X, 0, currentPos.Z).Magnitude

			-- If grounded or very close to the floor inside the arena
			if isGrounded or (currentPos.Y <= 8.5 and distFromCenter < 280) then
				print(string.format("[ReEntryState] %s LANDED SAFELY INSIDE ARENA at (%.1f, %.1f, %.1f)! Dist=%.1f", 
					fighter.Name, currentPos.X, currentPos.Y, currentPos.Z, distFromCenter))

				-- Impact sound
				AudioModule.playFallOnGround(currentPos)
				AudioModule.playDash(currentPos)

				-- Stabilize velocity
				rootPart.AssemblyLinearVelocity = Vector3.zero

				-- Transition to combat or idle
				local isCombatActive = Workspace:GetAttribute("NormalCombatActive") or Workspace:GetAttribute("MatchStarted")
				if isCombatActive then
					return require(script.Parent:WaitForChild("FightState"))
				else
					return require(script.Parent:WaitForChild("CirclingState"))
				end
			end
		end

		return ReEntryState
	end

	return ReEntryState
end

return ReEntryState
