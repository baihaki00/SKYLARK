--// CirclingState.lua
-- The Standoff. Tension builds before a massive strike.
--
-- Locomotion contract: the legs always match the motion.
--   * Strafe form  - the Quin faces its target and moves along the circle. Strafe clips only
--     travel straight sideways, so the body is turned (by at most Circling_MaxFacingBias) until
--     the real motion is exactly sideways, and the pace is the clip's own ground speed. The
--     clip's play rate follows the measured sideways speed; a Quin that is not moving shows idle.
--   * Travel form  - when the intended direction is not along the circle (retreating, rescuing,
--     leaving an edge) the body faces where it is going and the shared gait carries it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local QuinCore = ReplicatedStorage:WaitForChild("QuinCore")
local TargetingModule = require(QuinCore:WaitForChild("Modules"):WaitForChild("TargetingModule"))
local AnimationModule = require(QuinCore:WaitForChild("Modules"):WaitForChild("AnimationModule"))
local AnimationIds = require(QuinCore:WaitForChild("AnimationIds"))
local CombatConfig = require(QuinCore:WaitForChild("CombatConfig"))
local SpatialModule = require(QuinCore:WaitForChild("Modules"):WaitForChild("SpatialModule"))
local LocomotionModule = require(QuinCore:WaitForChild("Modules"):WaitForChild("LocomotionModule"))
local GaitModule = require(QuinCore:WaitForChild("Modules"):WaitForChild("GaitModule"))
local RuntimeTracer = require(QuinCore:WaitForChild("Modules"):WaitForChild("RuntimeTracer"))
local BattleEventSystem = require(QuinCore:WaitForChild("Modules"):WaitForChild("BattleEventSystem"))

local CirclingState = { name = "Circling" }

local TEST_MODE_ACTIVE = false -- true keeps them circling forever (animation debugging)
local DEFAULT_RADIUS = 30.0

-- Strafe clip per tension. `speed` is the clip's ground speed at 1.0x, measured on the rig
-- (CombatConfig.Strafe_*AuthoredSpeed overrides it); the Quin strafes at `pace` times that.
-- A tired Quin walks its strafe slowly: the StrafeTired clips drag both feet (3.5 studs of
-- foot travel per cycle for under 1 stud of ground), so they slide at any pace.
local STRAFE_CLIPS = {
	tired = { left = "StrafeLeftWalk", right = "StrafeRightWalk", speedKey = "Strafe_WalkAuthoredSpeed", speed = 6.5, paceKey = "Strafe_TiredPace", pace = 0.65 },
	walk = { left = "StrafeLeftWalk", right = "StrafeRightWalk", speedKey = "Strafe_WalkAuthoredSpeed", speed = 6.5 },
	run = { left = "StrafeLeftRun", right = "StrafeRightRun", speedKey = "Strafe_RunAuthoredSpeed", speed = 18.5 },
}

-- A different strafe clip must stay wanted this long, and clips switch at most this often
local CLIP_SWITCH_CONFIRM = 0.3
local CLIP_SWITCH_INTERVAL = 0.6
-- Below this fraction of the clip's ground speed the Quin is treated as standing
local STANDING_SPEED_RATIO = 0.25
-- A Quin that arrives faster than its strafe clip can step (carried sprint, a shove) runs the
-- momentum off facing its travel; it squares up to strafe once it has slowed. Ratios are of the
-- clip's fastest ground speed.
local CARRY_ENTER_RATIO = 1.5
local CARRY_EXIT_RATIO = 1.1

local GYRO_NAME = "CirclingGyro"

local circlingData = {}

local function flatUnit(v, fallback)
	local flat = Vector3.new(v.X, 0, v.Z)
	return flat.Magnitude > 0.01 and flat.Unit or fallback
end

local function ensureGyro(rootPart)
	local gyro = rootPart:FindFirstChild(GYRO_NAME)
	if not gyro then
		gyro = Instance.new("AlignOrientation")
		gyro.Name = GYRO_NAME
		gyro.Mode = Enum.OrientationAlignmentMode.OneAttachment
		local att = rootPart:FindFirstChild("RootAttachment") or Instance.new("Attachment", rootPart)
		att.Name = "RootAttachment"
		gyro.Attachment0 = att
		gyro.RigidityEnabled = false
		gyro.Responsiveness = 25
		gyro.MaxTorque = 100000
		gyro.CFrame = rootPart.CFrame
		gyro.Parent = rootPart
	end
	return gyro
end

local function stopStrafeClip(humanoid, data, fade)
	if data.currentAnim then
		AnimationModule.stop(humanoid, data.currentAnim, fade)
		data.currentAnim = nil
	end
end

local function livingSides(fighter)
	local myTeam = fighter:GetAttribute("Team")
	local enemies, allies = {}, {}
	for _, quin in ipairs(CollectionService:GetTagged("Quin")) do
		if quin ~= fighter and quin.Parent and quin:FindFirstChild("HumanoidRootPart") then
			local hum = quin:FindFirstChildOfClass("Humanoid")
			if hum and hum.Health > 0 then
				table.insert(quin:GetAttribute("Team") ~= myTeam and enemies or allies, quin)
			end
		end
	end
	return enemies, allies
end

function CirclingState.enter(fighter, humanoid, rootPart)
	local aggression = fighter:GetAttribute("Pers_Aggression") or 0.6
	local confidence = fighter:GetAttribute("Pers_Confidence") or 0.6
	local mobility = fighter:GetAttribute("Pers_MobilityPreference") or 0.6

	-- The pace of the standoff says how the Quin is doing: spent Quins drag, eager or nimble
	-- ones prowl fast, the rest walk it.
	local energyRatio = (fighter:GetAttribute("Energy") or 100) / (CombatConfig.MaxEnergy or 100)
	local tension = "walk"
	if energyRatio < (CombatConfig.Circling_TiredEnergyRatio or 0.35) then
		tension = "tired"
	elseif math.max(aggression, mobility) >= (CombatConfig.Circling_ProwlThreshold or 0.6) then
		tension = "run"
	end

	-- Personality-driven duration and radius
	local duration, idealRadius
	if aggression > 0.70 then
		idealRadius = 16.0 + math.random() * 6.0 -- Tight circle (16 - 22)
		duration = 1.4 + math.random() * 1.2 -- Quick snap (1.4 - 2.6s)
	elseif aggression < 0.45 or confidence < 0.45 then
		idealRadius = 28.0 + math.random() * 8.0 -- Wide standoff (28 - 36)
		duration = 3.5 + math.random() * 2.0 -- Long standoff (3.5 - 5.5s)
	else
		idealRadius = 22.0 + math.random() * 8.0
		duration = 2.2 + math.random() * 1.8
	end

	local now = tick()
	circlingData[fighter] = {
		enterTime = now,
		lastUpdateTime = now,
		duration = duration * (CombatConfig.Circling_DurationScale or 0.7),
		direction = math.random() > 0.5 and 1 or -1,
		tension = tension,
		currentAnim = nil,
		idealRadius = idealRadius,
		nextFeintTime = now + (1.2 + math.random() * 1.6),
	}

	RuntimeTracer.checkpoint(fighter, string.format("Enter Circling (Tension=%s)", tension))

	AnimationModule.stop(humanoid, AnimationIds.Jump, 0.15)
	AnimationModule.stop(humanoid, AnimationIds.Fall, 0.15)
	AnimationModule.stopCategory(humanoid, "Attacks", 0.1)

	-- The gyro owns facing for the whole state (update picks the facing and the leg clip)
	fighter:SetAttribute("IsStrafing", true)
	humanoid.AutoRotate = false
	ensureGyro(rootPart)
end

function CirclingState.exit(fighter, humanoid, rootPart)
	RuntimeTracer.checkpoint(fighter, "Exit Circling")
	fighter:SetAttribute("IsStrafing", false)
	local data = circlingData[fighter]
	if data then
		stopStrafeClip(humanoid, data, 0.15)
	end
	humanoid.AutoRotate = true
	local gyro = rootPart:FindFirstChild(GYRO_NAME)
	if gyro then
		gyro:Destroy()
	end
	circlingData[fighter] = nil
end

function CirclingState.update(fighter, humanoid, rootPart, DEBUG)
	-- Showdown perimeter spectators must never circle
	local showdownRole = fighter:GetAttribute("LeaderShowdownRole")
	if showdownRole == "PerimeterGuard" or showdownRole == "Transition" then
		return require(script.Parent:WaitForChild("LeaderShowdownState"))
	end

	-- Showdown Ring Containment & Jump Suppression
	local inShowdown = (workspace:GetAttribute("LeaderShowdownActive") == true) or (showdownRole ~= nil)
	if inShowdown then
		humanoid.UseJumpPower = true
		humanoid.JumpPower = 0
		humanoid.JumpHeight = 0
		local LeaderShowdownSystem = require(QuinCore:WaitForChild("Modules"):WaitForChild("LeaderShowdownSystem"))
		LeaderShowdownSystem.constrainToRing(rootPart)
	end

	local data = circlingData[fighter]
	if not data then return require(script.Parent:WaitForChild("FightState")) end

	-- Prone / Cockroach protection: if flat on ground, immediately recover
	if rootPart.CFrame.UpVector.Y < 0.6 and SpatialModule.isGrounded(rootPart) then
		fighter:SetAttribute("KnockbackType", "hard_ground")
		return require(script.Parent:WaitForChild("RecoveryState"))
	end

	-- Mana / Energy recovery while pacing & circling (two terms, as before: one scales with game speed)
	local speedMult = workspace:GetAttribute("GameSpeedMultiplier") or 1.0
	local recoveryRate = CombatConfig.EnergyRecovery_Walk or 15
	local energy = fighter:GetAttribute("Energy") or 100
	fighter:SetAttribute("Energy", math.min(CombatConfig.MaxEnergy or 100, energy + recoveryRate * 0.1 * speedMult + recoveryRate * 0.1))

	local target, distance = TargetingModule.getCommittedTarget(fighter, rootPart, (CombatConfig.ChaseRange or 60) * 1.5)
	if not target then
		target, distance = TargetingModule.getNearest(rootPart, CombatConfig.ChaseRange)
		if target then
			TargetingModule.setTarget(fighter, target)
		else
			TargetingModule.clearTarget(fighter)
			return require(script.Parent:WaitForChild("IdleState"))
		end
	end

	local targetHRP = target:FindFirstChild("HumanoidRootPart")
	local targetState = target:GetAttribute("CurrentState")

	-- Snap condition 0: Opponent broke the standoff to fight!
	if targetState == "Fight" or targetState == "Dash" or targetState == "Special" then
		if DEBUG then print("[Circling] Opponent attacked! FIGHT!") end
		return require(script.Parent:WaitForChild("FightState"))
	end

	-- Snap condition 1: Time's up (tension snap)
	-- Snap condition 2: Enemy got too close (below minimum circling range) -> FightState
	-- Snap condition 3: Enemy moved too far away (above max circling range) -> ChaseState
	local minCircleRange = (CombatConfig.CombatRange or 8) * 0.7
	local maxCircleRange = (CombatConfig.CombatRange or 8) * 4.5
	local isTargetDown = (targetState == "Knockback" or targetState == "Airborne" or targetState == "Recovery" or target:GetAttribute("GetUpProtection") == true)

	local now = tick()
	if not TEST_MODE_ACTIVE and not isTargetDown then
		if now - data.enterTime >= data.duration or distance < minCircleRange then
			-- Tension snapped at close quarters: dash/attack into FightState!
			local dashMin = CombatConfig.DashMinDistance or 10
			local dashMax = CombatConfig.DashMaxDistance or 28
			if math.random() > 0.5 and distance >= dashMin and distance <= dashMax and targetHRP then
				LocomotionModule.dash(fighter, humanoid, rootPart, targetHRP.Position, distance)
			end
			return require(script.Parent:WaitForChild("FightState"))
		elseif distance > maxCircleRange then
			return require(script.Parent:WaitForChild("ChaseState"))
		end
	end

	-- An opening ends the standoff early: the target has turned its back (it is busy with
	-- someone else, or walking away) and is within a dash. Aggressive Quins take it sooner.
	if not TEST_MODE_ACTIVE and not isTargetDown and (now - data.enterTime) >= (CombatConfig.Circling_OpeningMinTime or 0.5) then
		local toMe = flatUnit(rootPart.Position - targetHRP.Position, nil)
		local targetFacing = flatUnit(targetHRP.CFrame.LookVector, nil)
		local aggression = fighter:GetAttribute("Pers_Aggression") or 0.6
		if toMe and targetFacing and targetFacing:Dot(toMe) < -0.2 and distance <= (CombatConfig.DashMaxDistance or 28)
			and math.random() < aggression * (CombatConfig.Circling_OpeningChancePerTick or 0.35) then
			fighter:SetAttribute("ObstacleAwareness", "Opening: target's back is turned")
			if distance >= (CombatConfig.DashMinDistance or 10) then
				LocomotionModule.dash(fighter, humanoid, rootPart, targetHRP.Position, distance)
			end
			return require(script.Parent:WaitForChild("FightState"))
		end
	end

	-- Strafe reversals / feints (agile fighters change direction)
	if data.nextFeintTime and now >= data.nextFeintTime and not isTargetDown then
		local mobility = fighter:GetAttribute("Pers_MobilityPreference") or 0.6
		if mobility > 0.58 and math.random() < 0.65 then
			data.direction = -data.direction
			data.nextFeintTime = now + (1.6 + math.random() * 2.2)
			BattleEventSystem.emit("FeintStrafe", { Model = fighter, TargetName = target.Name })
		else
			data.nextFeintTime = now + (2.0 + math.random() * 2.0)
		end
	end

	-- === Intended direction ===
	local fallbackLook = flatUnit(rootPart.CFrame.LookVector, Vector3.new(0, 0, -1))
	local targetDir = flatUnit(targetHRP.Position - rootPart.Position, fallbackLook)
	local bodyRightFacingTarget = targetDir:Cross(Vector3.yAxis) -- the Quin's right when it faces the target
	local tangent = bodyRightFacingTarget * data.direction

	-- Orbit: along the circle, corrected toward the ideal radius
	local idealDistance = isTargetDown and 25.0 or (data.idealRadius or DEFAULT_RADIUS)
	local distanceError = math.clamp((distance - idealDistance) * 0.05, -0.20, 0.20)
	local moveDirection = (tangent + targetDir * distanceError).Unit

	-- Tactical Flanking (Pincer Maneuver): if an ally is already engaging the target in front, flank around
	local myTeam = fighter:GetAttribute("Team")
	if myTeam then
		local targetLook = targetHRP.CFrame.LookVector
		local toMe = flatUnit(rootPart.Position - targetHRP.Position, -targetDir)
		if targetLook:Dot(toMe) > 0.2 then
			local allyInFront = false
			for _, other in ipairs(CollectionService:GetTagged("Quin")) do
				if other ~= fighter and other:GetAttribute("Team") == myTeam and other.Parent then
					local oHRP = other:FindFirstChild("HumanoidRootPart")
					if oHRP and (oHRP.Position - targetHRP.Position).Magnitude < 20
						and targetLook:Dot((oHRP.Position - targetHRP.Position).Unit) > 0.2 then
						allyInFront = true
						break
					end
				end
			end
			if allyInFront then
				local flankOffset = tangent * 1.5 - targetLook * 0.8
				moveDirection = (moveDirection + flankOffset.Unit * 0.85).Unit
			end
		end
	end

	local centerPull = SpatialModule.getArenaCenterPull(rootPart)

	-- Tactical state modulation (Disengagement / Rescue / Reposition)
	local tacticalState = fighter:GetAttribute("TacticalState")
	if tacticalState == "RETREATING" then
		-- Intelligent Safe Haven Retreat using radial evaluation
		local enemies, allies = livingSides(fighter)
		local retreatResult = SpatialModule.getSafeRetreatDirection(rootPart, enemies, allies, CombatConfig)
		fighter:SetAttribute("RetreatScore", math.round(retreatResult.score * 100) / 100)
		fighter:SetAttribute("IsCornered", retreatResult.isCornered)

		if retreatResult.isCornered then
			-- Cornered beast: an aggressive fighter with the enemy in reach counter-strikes instead
			local aggression = fighter:GetAttribute("Pers_Aggression") or 0.6
			local meleeRange = (CombatConfig.CombatRange or 8) * 2.0
			if aggression >= (CombatConfig.CorneredCounterThreshold or 0.65) and distance <= meleeRange then
				fighter:SetAttribute("DesperateCounter", true)
				return require(script.Parent:WaitForChild("FightState"))
			end
		end

		moveDirection = (retreatResult.direction * 1.5 + (centerPull.Magnitude > 0.1 and centerPull.Unit or Vector3.zero) * 0.3).Unit
	elseif tacticalState == "RESCUING" then
		local allyName = fighter:GetAttribute("DistressedAllyName")
		if allyName and allyName ~= "" then
			local ally = workspace:FindFirstChild(allyName) or (workspace:FindFirstChild("QuinServer") and workspace.QuinServer:FindFirstChild(allyName))
			local allyHRP = ally and ally:FindFirstChild("HumanoidRootPart")
			if allyHRP then
				moveDirection = ((allyHRP.Position - rootPart.Position).Unit * 1.4 + tangent * 0.4).Unit
			end
		end
	end

	-- Edge detection & Center Bias
	local nearEdge, awayDir = SpatialModule.isNearArenaEdge(rootPart, 15)
	if nearEdge then
		moveDirection = (moveDirection + awayDir * 1.5).Unit
	end
	if centerPull.Magnitude > 0.1 then
		moveDirection = (moveDirection + centerPull.Unit * 0.6).Unit
	end
	moveDirection = flatUnit(moveDirection, tangent)

	-- === Locomotion form ===
	-- side > 0: the motion is toward the Quin's right while it faces the target. The strafe
	-- form applies while the motion is within Circling_MaxFacingBias of straight sideways.
	local side = moveDirection:Dot(bodyRightFacingTarget)
	local maxBias = math.rad(CombatConfig.Circling_MaxFacingBias or 35)
	local clipSet = STRAFE_CLIPS[data.tension] or STRAFE_CLIPS.walk
	local clipSpeed = CombatConfig[clipSet.speedKey] or clipSet.speed

	local velocity = rootPart.AssemblyLinearVelocity
	local planar = Vector3.new(velocity.X, 0, velocity.Z)
	local strafeTopSpeed = clipSpeed * (CombatConfig.Strafe_MaxPlayRate or 1.35) * speedMult
	if planar.Magnitude > strafeTopSpeed * CARRY_ENTER_RATIO then
		data.carryingMomentum = true
	elseif planar.Magnitude < strafeTopSpeed * CARRY_EXIT_RATIO then
		data.carryingMomentum = false
	end
	-- Momentum that is not yet along the intended path (arriving head-on at the target) is run
	-- off the same way: the strafe clips cannot step forward
	local offPath = planar.Magnitude > clipSpeed * 0.5 and planar.Unit:Dot(moveDirection) < 0.5
	local drifting = data.carryingMomentum or offPath
	local strafing = math.abs(side) >= math.cos(maxBias) and not drifting
	local travelSpeed = (data.tension == "run") and (CombatConfig.Player_JogSpeed or 12.0) or (CombatConfig.Player_WalkSpeed or 7.5)
	local strafePace = clipSpeed * ((clipSet.paceKey and CombatConfig[clipSet.paceKey]) or clipSet.pace or 1)
	local targetSpeed = (strafing and strafePace or travelSpeed) * speedMult

	local dt = math.clamp(now - (data.lastUpdateTime or (now - 0.05)), 0.016, 0.25)
	data.lastUpdateTime = now
	LocomotionModule.steer(fighter, humanoid, rootPart, rootPart.Position + moveDirection * 15, targetSpeed, dt)

	-- Facing follows the real motion once the body is moving, so the legs match what the body
	-- is actually doing rather than what was asked of it a moment ago
	local motion = moveDirection
	if planar.Magnitude > 2.0 and (drifting or planar.Unit:Dot(moveDirection) > 0.5) then
		motion = planar.Unit
	end

	local look
	if strafing then
		-- Turn the body so that the motion is exactly along its right (or left) axis
		look = side > 0 and Vector3.new(motion.Z, 0, -motion.X) or Vector3.new(-motion.Z, 0, motion.X)
	else
		look = motion
	end
	ensureGyro(rootPart).CFrame = CFrame.lookAt(Vector3.zero, look)

	-- === Legs ===
	if strafing then
		if GaitModule.isActive(humanoid) then
			GaitModule.stop(humanoid, 0.2)
		end

		local desiredAnim = AnimationIds[side > 0 and clipSet.right or clipSet.left]
		local lateralSpeed = math.abs(planar:Dot(rootPart.CFrame.RightVector))

		if lateralSpeed < clipSpeed * STANDING_SPEED_RATIO then
			-- Not actually moving (blocked, turning around): no stepping in place
			stopStrafeClip(humanoid, data, 0.2)
			data.pendingAnim = nil
			AnimationModule.ensureBaseIdle(humanoid)
		else
			if data.currentAnim and desiredAnim ~= data.currentAnim then
				-- Hold: the other clip has to stay wanted briefly before the legs switch
				if data.pendingAnim ~= desiredAnim then
					data.pendingAnim = desiredAnim
					data.pendingSince = now
				end
				local confirmed = (now - data.pendingSince) >= CLIP_SWITCH_CONFIRM
					and (now - (data.lastAnimSwitch or 0)) >= CLIP_SWITCH_INTERVAL
				if confirmed then
					stopStrafeClip(humanoid, data, 0.25)
				end
			else
				data.pendingAnim = nil
			end

			if not data.currentAnim then
				data.currentAnim = desiredAnim
				data.lastAnimSwitch = now
			end
			local rate = math.clamp(lateralSpeed / clipSpeed, CombatConfig.Strafe_MinPlayRate or 0.6, CombatConfig.Strafe_MaxPlayRate or 1.35)
			AnimationModule.play(humanoid, data.currentAnim, Enum.AnimationPriority.Movement, true, rate / speedMult, 0.25)
		end
	else
		stopStrafeClip(humanoid, data, 0.2)
		data.pendingAnim = nil
		GaitModule.update(humanoid, rootPart, dt)
	end

	return CirclingState
end

return CirclingState
