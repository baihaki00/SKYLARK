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
local GaitModule = require(QuinCore:WaitForChild("Modules"):WaitForChild("GaitModule"))

local ReEntryState = { name = "ReEntry" }

local reEntryData = {}

function ReEntryState.enter(fighter, humanoid, rootPart)
	if not fighter or not humanoid or not rootPart then return end

	humanoid.WalkSpeed = 0
	humanoid.PlatformStand = false

	-- Horizontal direction to the real arena centre. The arena is not at the world origin:
	-- aiming at (0, 0) sent every re-entry leap toward a point outside the arena.
	local myPos = rootPart.Position
	local bounds = SpatialModule.getArenaBounds()
	local dirToCenter = Vector3.new(bounds.center.X - myPos.X, 0, bounds.center.Z - myPos.Z)
	-- Still standing on the arena floor (only pressed against its edge)?
	local insideFootprint = math.abs(myPos.X - bounds.center.X) <= bounds.halfX
		and math.abs(myPos.Z - bounds.center.Z) <= bounds.halfZ and myPos.Y > -5
	if dirToCenter.Magnitude > 0.001 then
		dirToCenter = dirToCenter.Unit
	else
		dirToCenter = Vector3.new(0, 0, -1)
	end

	-- Turn toward the centre through the humanoid's own rotation (no facing snap)
	humanoid.AutoRotate = true

	reEntryData[fighter] = {
		enterTime = tick(),
		phase = insideFootprint and "run_in" or "walk", -- jog back in, or walk -> run -> leap from outside
		phaseStartTime = tick(),
		dirToCenter = dirToCenter,
		hasLeaped = false,
		lastFootstepTime = 0,
	}

	-- Start Phase 1: approach stride (the shared gait matches the clip to the pace)
	humanoid.WalkSpeed = 14
	humanoid:Move(dirToCenter)

	print(string.format("[ReEntryState] %s entered Cinematic Re-Entry! Facing arena center from (%.1f, %.1f, %.1f)", 
		fighter.Name, myPos.X, myPos.Y, myPos.Z))
end

function ReEntryState.exit(fighter, humanoid, rootPart)
	local data = reEntryData[fighter]
	if data then
		GaitModule.stop(humanoid, 0.15)
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
	local locoDt = math.clamp(now - (data.lastLocoTime or (now - 0.05)), 1 / 60, 0.25)
	data.lastLocoTime = now

	-- Global Safety Timeout (7 seconds): Emergency teleport inside if anything stalled
	if totalElapsed > 7.0 then
		print(string.format("[ReEntryState] %s timed out during re-entry. Emergency placing at center.", fighter.Name))
		local timeoutBounds = SpatialModule.getArenaBounds()
		fighter:PivotTo(CFrame.new(timeoutBounds.center.X, 7.5, timeoutBounds.center.Z))
		rootPart.AssemblyLinearVelocity = Vector3.zero
		return require(script.Parent:WaitForChild("FightState"))
	end

	-- Recompute live horizontal direction to arena center
	local currentPos = rootPart.Position
	local bounds = SpatialModule.getArenaBounds()
	local dirToCenter = Vector3.new(bounds.center.X - currentPos.X, 0, bounds.center.Z - currentPos.Z)
	local centerDist = dirToCenter.Magnitude
	if centerDist > 0.001 then
		dirToCenter = dirToCenter.Unit
		data.dirToCenter = dirToCenter
	end

	-- PHASE 0: on the arena floor but hugging its edge -> jog back inside. The wall-clearing
	-- leap is reserved for Quins that are actually outside.
	if data.phase == "run_in" then
		humanoid.AutoRotate = true
		humanoid.WalkSpeed = math.min(math.max(humanoid.WalkSpeed, 12) + 8, 34)
		humanoid:Move(data.dirToCenter)
		GaitModule.update(humanoid, rootPart, locoDt)

		if not SpatialModule.isOutOfBounds(rootPart, 30) then
			return require(script.Parent:WaitForChild("ChaseState"))
		end
		if phaseElapsed > 2.5 then
			-- Blocked on the way in: fall back to the run-up and leap
			data.phase = "run"
			data.phaseStartTime = now
		end
		return ReEntryState
	end

	-- PHASE 1: Confident Walk (0.8 seconds)
	if data.phase == "walk" then
		humanoid.WalkSpeed = 14
		humanoid:Move(data.dirToCenter)
		rootPart.CFrame = CFrame.lookAt(currentPos, currentPos + data.dirToCenter)
		GaitModule.update(humanoid, rootPart, locoDt)

		if now - data.lastFootstepTime > 0.4 then
			data.lastFootstepTime = now
			AudioModule.playFootstep(fighter, 0.4)
		end

		if phaseElapsed >= 0.8 then
			-- Transition to Phase 2: Run Acceleration
			data.phase = "run"
			data.phaseStartTime = now
			humanoid.WalkSpeed = 38
			print(string.format("[ReEntryState] %s accelerating into run sprint toward wall!", fighter.Name))
		end

		return ReEntryState

	-- PHASE 2: Run Acceleration (0.6 seconds)
	elseif data.phase == "run" then
		humanoid.WalkSpeed = 38
		humanoid:Move(data.dirToCenter)
		rootPart.CFrame = CFrame.lookAt(currentPos, currentPos + data.dirToCenter)
		GaitModule.update(humanoid, rootPart, locoDt)

		if now - data.lastFootstepTime > 0.25 then
			data.lastFootstepTime = now
			AudioModule.playFootstep(fighter, 0.6)
		end

		if phaseElapsed >= 0.6 then
			-- Transition to Phase 3: The Super Wall-Clearing Leap!
			data.phase = "leap"
			data.phaseStartTime = now
			data.hasLeaped = true

			GaitModule.stop(humanoid, 0.1)
			AnimationModule.play(humanoid, AnimationIds.Jump or AnimationIds.Uppercut, Enum.AnimationPriority.Action3, false, 1.2)

			-- Sound & Audio
			AudioModule.playJumpUp(currentPos)
			AudioModule.playSonicBoom(currentPos)

			-- Lift out of ground friction plane and set Freefall state
			humanoid:ChangeState(Enum.HumanoidStateType.Freefall)

			-- Super Velocity: Vy = 260 reaches apex Y ≈ 175-180 studs (clearing 148-stud wall easily)
			-- Vxz = 150 covers 250+ studs horizontally during the 2.6s parabolic flight
			-- Horizontal speed sized to land well inside the arena (roughly 45% of its radius
			-- from the centre) instead of a fixed 150 that overshot from close range. Flight is
			-- ~3.3s: 0.35s under the launch constraint plus the ballistic arc.
			local travel = math.clamp(centerDist - bounds.radius * 0.45, 80, 400)
			local horizVelocity = data.dirToCenter * math.clamp(travel / 3.3, 25, 150)
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
			local distFromCenter = centerDist

			-- If grounded or very close to the floor inside the arena
			if isGrounded or (currentPos.Y <= 8.5 and distFromCenter < 280) then
				print(string.format("[ReEntryState] %s LANDED SAFELY INSIDE ARENA at (%.1f, %.1f, %.1f)! Dist=%.1f", 
					fighter.Name, currentPos.X, currentPos.Y, currentPos.Z, distFromCenter))

				-- Impact sound
				AudioModule.playFallOnGround(currentPos)
				AudioModule.playDash(currentPos)

				-- Stabilize velocity and absorb the drop with the landing clip (the touchdown
				-- used to go straight from a 200 studs/s fall to the combat idle)
				rootPart.AssemblyLinearVelocity = Vector3.zero
				AnimationModule.stop(humanoid, AnimationIds.Fall, 0.1)
				AnimationModule.playConfig(humanoid, "Parkour.LandingSuperHero", 1.0, Enum.AnimationPriority.Action3, true)

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
