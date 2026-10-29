--// ChaseState/Steer.lua
-- How a chaser runs, once it knows where it is going: its pace (Modules/Pace), the clip and
-- push-off, the lead on a moving target, room for teammates on the same one (tandem, spread,
-- flank), carved arcs and cuts, a path round when the straight line is blocked, then the one
-- steer of the frame (LocomotionModule) and the fall/landing tidy-up.
-- (Cut out of ChaseState.update as it was: QuinCore audit 2026-10-27, step 7.)

local DebugDraw = require(game:GetService("ReplicatedStorage"):WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("DebugDraw"))
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local QuinRoster = require(game:GetService("ReplicatedStorage"):WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("QuinRoster")) -- (GetTagged("Quin") once a frame, shared)
local AnimationModule = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("AnimationModule"))
local CombatConfig = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("CombatConfig"))
local SpatialModule = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("SpatialModule"))
local LocomotionModule = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("LocomotionModule"))
local GaitModule = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("GaitModule"))
local NavigationModule = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("NavigationModule"))
local Pace = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("Pace"))
local Pers = require(game:GetService("ReplicatedStorage"):WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("Pers")) -- (personality reads + defaults, one place)

local Steer = {}

-- How urgent this chase is (Modules/Pace turns it into walk / jog / run): a long approach with
-- nothing at stake is a jog; closing in, a target on an ally, one coming at it, one hurt or getting
-- away, a rescue - each makes it hurry. Read from what it knows, so two Quins in the same chase can
-- be in different gears.
local function chaseUrgency(fighter, target, distance, targetState)
	local u = CombatConfig.Pace_ChaseBase or 0.5
	local why = "approach"
	if distance < (CombatConfig.Pace_ChaseCloseRange or 90) then u += 0.35 why = "closing in" end
	local tTarget = target:GetAttribute("CurrentTarget")
	if tTarget == fighter.Name then
		u += 0.25 why = "it is coming for me"
	elseif tTarget and tTarget ~= "" then
		local folder = workspace:FindFirstChild("QuinServer")
		local victim = folder and folder:FindFirstChild(tTarget)
		if victim and victim:GetAttribute("Team") == fighter:GetAttribute("Team") then u += 0.25 why = "it is on " .. tTarget end
	end
	local hum = target:FindFirstChildOfClass("Humanoid")
	if hum and hum.MaxHealth > 0 and hum.Health / hum.MaxHealth < 0.35 then u += 0.2 why = "it is hurt" end
	if targetState == "Retreat" then u += 0.2 why = "it is getting away" end
	if fighter:GetAttribute("TacticalState") == "RESCUING" or fighter:GetAttribute("Task") == "Rescue" then u += 0.3 why = "rescue" end
	if distance > (CombatConfig.Pace_ChaseFarRange or 160) then u -= 0.1 end
	return u, why
end

function Steer.update(fighter, humanoid, rootPart, data, target, targetHRP, targetState, distance, now, speedMult, hasLoS, reachable, shouldWalk, inShowdown, obstacleSteer, platformDismountDir)
	-- Jumps are now INTENTIONAL ONLY: they fire for a genuine reason (obstacle vault,
	-- elevated-target intercept, vertical unstick) rather than random athletic hops.
	-- This keeps locomotion grounded and makes every jump read as deliberate.
	
	local speed = fighter:GetAttribute("Speed") or 40
	-- Walking is the Walk clip's own pace. It used to be 16 studs/s, which is a hard jog: the
	-- legs were over-cranked and it never read as a walk.
	-- (a chase holds its run: no Jog gear far out, no shift down as the urgency drops; ChaseState)
	local holdSpeed = CombatConfig.Chase_HoldSpeed ~= false and workspace:GetAttribute("ChaseHoldSpeedOff") ~= true
	if not shouldWalk and Pace.enabled() and not holdSpeed then
		local urgency, why = chaseUrgency(fighter, target, distance, targetState)
		speed = math.min(speed, (Pace.gear(fighter, urgency, why)))
	end
	local targetSpeed = (shouldWalk and (CombatConfig.Player_WalkSpeed or 7.5) or speed) * speedMult
	-- Brake into the engagement: cap the pace by what the braking rate can shed over the
	-- remaining gap. At a full sprint the stopping distance (~13 studs) is longer than the
	-- hand-over range to Fight, so a sprinting Quin ran through its target and was shoved back.
	local arriveGap = math.max(distance - (CombatConfig.CombatRange or 8.2), 0.5)
	local arriveSpeed = math.sqrt(2 * (CombatConfig.Locomotion_BrakingDeceleration or 95) * arriveGap) + 6
	targetSpeed = math.min(targetSpeed, arriveSpeed)
	-- Pacing through a run of obstacles (set where the crossing is planned)
	if data.obstaclePace and now < (data.obstaclePaceUntil or 0) then
		targetSpeed = math.min(targetSpeed, data.obstaclePace * speedMult)
	end

	-- Locomotion Timing & Continuity: delegate acceleration & braking to LocomotionModule
	local lastUpdate = data.lastUpdateTime or (now - 0.05)
	local dt = math.clamp(now - lastUpdate, 0.016, 0.25)
	data.lastUpdateTime = now

	local currentSpeed = humanoid.WalkSpeed
	data.isAccelerating = (currentSpeed < targetSpeed - 2.0)
	data.isDecelerating = (currentSpeed > targetSpeed + 2.0)
	data.currentSpeed = currentSpeed
	data.targetSpeed = targetSpeed
	data.dt = dt

	-- Clean up expired turn or arc overlays so they never hold bone transforms frozen
	if data.turnAnim and now >= (data.turnActiveUntil or 0) then
		AnimationModule.stopConfig(humanoid, data.turnAnim, 0.12)
		data.turnAnim = nil
	end
	if data.arcAnim and now >= (data.arcActiveUntil or 0) then
		AnimationModule.stopConfig(humanoid, data.arcAnim, 0.12)
		data.arcAnim = nil
	end

	-- A new push-off becomes available once the body has actually come to rest
	local restVel = rootPart.AssemblyLinearVelocity
	if Vector3.new(restVel.X, 0, restVel.Z).Magnitude < 3 and not data.pushOffAnim then
		data.pushOffSpent = false
	end

	-- Animation track selection with push-off awareness (velocity-driven so the leg
	-- cycle matches actual movement speed and avoids "sprint at walk pace" shuffling)
	local desiredAnim
	if shouldWalk then
		desiredAnim = "Movement.WalkConfident"
		data.pushOffAnim = nil
	elseif data.turnAnim and now < (data.turnActiveUntil or 0) then
		desiredAnim = data.turnAnim
	elseif data.arcAnim and now < (data.arcActiveUntil or 0) then
		desiredAnim = data.arcAnim
	elseif CombatConfig.Chase_PushOffOverlay == true and data.isAccelerating and currentSpeed < (targetSpeed * 0.55) and (data.pushOffAnim or not data.pushOffSpent) then
		-- Push-off is a start-from-rest overlay: chosen once per start, never replayed while
		-- the Quin stays slow (the gait base layer runs underneath it)
		if not data.pushOffAnim then
			local mobility = Pers.get(fighter, "MobilityPreference")
			data.pushOffAnim = (mobility > 0.55 or math.random() > 0.5) and "Movement.IdleToRun1" or "Movement.IdleToRun2"
			data.pushOffSpent = true
		end
		desiredAnim = data.pushOffAnim
		if data.currentAnim == data.pushOffAnim and not AnimationModule.isPlaying(humanoid, data.pushOffAnim) then
			-- Push-off finished: hand over to the gait instead of replaying it
			data.pushOffAnim = nil
			desiredAnim = "Movement.Run"
		end
	else
		desiredAnim = "Movement.Run"
		data.pushOffAnim = nil
	end

	local isFreefall = (humanoid:GetState() == Enum.HumanoidStateType.Freefall)
	-- Airborne for overlay purposes (was read below as an undefined name, so the ground
	-- cut / arc overlays could start in mid-air)
	local isFreefallState = isFreefall or humanoid:GetState() == Enum.HumanoidStateType.Jumping
	if desiredAnim == "Movement.Run" or desiredAnim == "Movement.WalkConfident" then
		-- Base gait: shared stride-matched Walk/Run blend driven by real ground speed.
		-- A start overlay hands over here: left to play out, it covered the legs for its full
		-- length while the body was already at a sprint.
		if data.currentAnim and data.currentAnim ~= "Gait" then
			AnimationModule.stopConfig(humanoid, data.currentAnim, 0.2)
		end
		data.currentAnim = "Gait"
		if not isFreefall then
			GaitModule.update(humanoid, rootPart, dt)
		end
	elseif data.currentAnim ~= desiredAnim then
		data.currentAnim = desiredAnim
		AnimationModule.playConfig(humanoid, data.currentAnim)
	elseif not isFreefall and not AnimationModule.isPlaying(humanoid, data.currentAnim) then
		-- Locomotion overlay was interrupted (hit reaction / reaction overlay);
		-- re-assert it so the Quin does not glide like a statue while still translating.
		AnimationModule.playConfig(humanoid, data.currentAnim)
	end
	
	-- (running costs mana and slowing down gives it back in the body, whatever the state: BodyStamina)
	
	-- Predictive Lead Interception (Angle cutting rather than tail chasing)
	local interceptPos = targetHRP.Position
	if hasLoS then
		local targetVel = targetHRP.AssemblyLinearVelocity
		local targetVelFlat = Vector3.new(targetVel.X, 0, targetVel.Z)
		if targetVelFlat.Magnitude > 3.0 and currentSpeed > 5.0 then
			local maxLead = CombatConfig.PredictiveLeadMaxTime or 1.2
			local leadTime = math.clamp(distance / currentSpeed, 0, maxLead)
			local testIntercept = targetHRP.Position + targetVelFlat * leadTime

			local leadRayParams = RaycastParams.new()
			leadRayParams.FilterDescendantsInstances = { fighter, target }
			leadRayParams.FilterType = Enum.RaycastFilterType.Exclude

			local leadRay = DebugDraw.raycast(rootPart, rootPart.Position + Vector3.new(0, 1.5, 0), (testIntercept - rootPart.Position), leadRayParams)
			if not leadRay then
				interceptPos = testIntercept
				fighter:SetAttribute("InterceptionLeadTime", math.round(leadTime * 100) / 100)
			else
				fighter:SetAttribute("InterceptionLeadTime", 0)
			end
		else
			fighter:SetAttribute("InterceptionLeadTime", 0)
		end
	else
		fighter:SetAttribute("InterceptionLeadTime", 0)
	end

	local arcTarget = (not hasLoS and data.targetLKP) and data.targetLKP or interceptPos
	local dirToTarget = (arcTarget - rootPart.Position).Unit

	-- Emergent Multi-Chaser Formations (Tandem vs Dispersion based on bonds & quirks)
	local myOwner = fighter:GetAttribute("OwnerId") or "SERVER"
	local protectHabit = Pers.get(fighter, "Protectiveness")
	local sameTargetTeammates = {}
	for _, q in ipairs(QuinRoster.all()) do
		if q ~= fighter and q.Parent and q:FindFirstChild("HumanoidRootPart") then
			if q:GetAttribute("Team") == fighter:GetAttribute("Team") and q:GetAttribute("TargetQuin") == target.Name then
				table.insert(sameTargetTeammates, q)
			end
		end
	end

	-- Carved running (owner 2026-10-27: arcs and the whole-body tilt into them were rarely seen; the
	-- chase ran straight lines). On a long sprint the Quin swings out to one side of the line to
	-- its target and now and then carves across to the other, like a skier: the run curves and
	-- the body leans into it (the tilt reads the curve). Wider swings for a mobile Quin; none up
	-- close, while walking, detouring or out of sight.
	local arcCfg = CombatConfig.Chase_CarveDegrees or 32
	if arcCfg > 0 and hasLoS and not shouldWalk and not inShowdown and reachable and distance > 14 then
		if now >= (data.carveFlipAt or 0) then
			data.carveSide = (data.carveSide or (math.random() < 0.5 and 1 or -1)) * -1
			data.carveFlipAt = now + (CombatConfig.Chase_CarveSwitchMin or 1.6) + math.random() * (CombatConfig.Chase_CarveSwitchSpread or 1.6)
		end
		local mob = Pers.get(fighter, "MobilityPreference")
		local fade = math.clamp((distance - 14) / 30, 0, 1)
		local angle = math.rad(arcCfg * (0.6 + mob * 0.8) * fade) * data.carveSide
		local to = arcTarget - rootPart.Position
		local flatTo = Vector3.new(to.X, 0, to.Z)
		if flatTo.Magnitude > 1 then
			local c, sn = math.cos(angle), math.sin(angle)
			local turned = Vector3.new(flatTo.X * c - flatTo.Z * sn, 0, flatTo.X * sn + flatTo.Z * c)
			arcTarget = rootPart.Position + turned + Vector3.new(0, to.Y, 0)
		end
	end

	-- Team coordination step 3: a flanker goes round to the far side of the enemy from the ally
	-- already on it (TargetingModule PackIntent), not in through the same side. It aims at a point
	-- between where it is and the enemy's back, so the run curves round; once behind, it goes in.
	local flanking = false
	if hasLoS and fighter:GetAttribute("PackIntent") == "Flanker" and CombatConfig.Team_Flank ~= false then
		local ally = QuinRoster.byName(fighter:GetAttribute("PackIntentAlly"))
		local aRoot = ally and ally:FindFirstChild("HumanoidRootPart")
		local tPos = targetHRP.Position
		if aRoot and (aRoot.Position - tPos).Magnitude <= (CombatConfig.Targeting_CrowdRadius or 45) then
			local back = Vector3.new(tPos.X - aRoot.Position.X, 0, tPos.Z - aRoot.Position.Z)
			local mine = Vector3.new(rootPart.Position.X - tPos.X, 0, rootPart.Position.Z - tPos.Z)
			if back.Magnitude > 0.5 and mine.Magnitude > 0.5 then
				back, mine = back.Unit, mine.Unit
				if mine:Dot(back) < (CombatConfig.Team_FlankBehindDot or 0.55) then
					local way = mine + back
					if way.Magnitude < 0.3 then -- (straight through the enemy: go round one side)
						way = Vector3.new(-back.Z, 0, back.X)
					end
					arcTarget = tPos + way.Unit * (CombatConfig.Team_FlankRadius or 12)
					flanking = true
					fighter:SetAttribute("Flanking", true)
				end
			end
		end
	end
	if not flanking and fighter:GetAttribute("Flanking") then
		fighter:SetAttribute("Flanking", nil)
	end

	if #sameTargetTeammates > 0 and hasLoS and not flanking then
		local isTandemPair = false
		for _, mate in ipairs(sameTargetTeammates) do
			if (mate:GetAttribute("OwnerId") == myOwner and myOwner ~= "SERVER") or protectHabit >= 0.7 then -- (the protective pair up)
				isTandemPair = true
				break
			end
		end

		local rightVec = rootPart.CFrame.RightVector
		if isTandemPair then
			-- Tandem pair hunting: close support spacing (6 studs lateral)
			arcTarget = arcTarget + rightVec * 6.0
		else
			-- Route dispersion: flank around to cut off exit (16 studs lateral)
			local sign = (fighter.Name < sameTargetTeammates[1].Name) and 1 or -1
			arcTarget = arcTarget + rightVec * (sign * 16.0)
		end
	end

	-- Only the arena's true void here; ledges of raised ground are kept to by keepOnSurface
	-- below (on an 8-wide lane both sides read as ledges and this steered it off one of them)
	local nearEdge, awayDir = SpatialModule.isNearArenaEdge(rootPart, 6, true)
	if nearEdge then
		arcTarget = rootPart.Position + awayDir * 10 + dirToTarget * 5
	end
	
	local centerPull = SpatialModule.getArenaCenterPull(rootPart)
	if centerPull.Magnitude > 0.1 then
		arcTarget = arcTarget + centerPull * 15
	end
	
	if obstacleSteer then
		arcTarget = rootPart.Position + obstacleSteer * 16
	else
		local hasObstacleAhead = SpatialModule.raycastForward(rootPart, 5)
		if hasObstacleAhead then
			local safeDir = SpatialModule.getObstacleAvoidanceDirection(rootPart, 5)
			arcTarget = rootPart.Position + safeDir * 8
		end
	end

	-- Phase 4: If dismounting an elevated platform, walk toward the chosen ledge
	if platformDismountDir then
		arcTarget = rootPart.Position + platformDismountDir * (CombatConfig.PlatformDismountRayRange or 12)
	end
	
	-- Debug: where the target is expected to be (magenta) and where this Quin is actually heading (white)
	if DebugDraw.isActive("Pursuit", fighter) then
		local origin = rootPart.Position
		DebugDraw.line("Pursuit", fighter, origin, interceptPos, Color3.fromRGB(255, 80, 220))
		DebugDraw.sphere("Pursuit", fighter, interceptPos, 0.8, Color3.fromRGB(255, 80, 220))
		DebugDraw.line("Pursuit", fighter, origin, arcTarget, Color3.fromRGB(235, 235, 255))
		DebugDraw.text("Pursuit", fighter, arcTarget + Vector3.new(0, 2, 0),
			string.format("%s%s", tostring(fighter:GetAttribute("PaceReason") or "chase"), hasLoS and "" or " | no sight: going to last seen"),
			Color3.fromRGB(235, 235, 255))
	end

	-- Determine flat direction to the actual target/heading
	local steerDiff = arcTarget - rootPart.Position
	if steerDiff.Magnitude > 0.1 then
		dirToTarget = steerDiff.Unit
	end

	local flatLook = Vector3.new(rootPart.CFrame.LookVector.X, 0, rootPart.CFrame.LookVector.Z)
	flatLook = (flatLook.Magnitude > 0.01) and flatLook.Unit or Vector3.new(0, 0, -1)
	local flatTargetDir = Vector3.new(dirToTarget.X, 0, dirToTarget.Z)
	flatTargetDir = (flatTargetDir.Magnitude > 0.01) and flatTargetDir.Unit or flatLook

	local dotToTarget = flatLook:Dot(flatTargetDir)
	local localDir = rootPart.CFrame:VectorToObjectSpace(flatTargetDir)

	-- 1. Direction reversals are handled 100% procedurally by LocomotionModule & ProceduralCombatReactionController

	-- 2. Athletic 90-Degree Plant Cut (Mirrored Left / Right)
	local canTurn90 = (CombatConfig.Chase_TurnCutOverlayEnabled == true)
		and not inShowdown
		and not shouldWalk
		and currentSpeed >= 14
		and (now >= (data.turnActiveUntil or 0))
		and (now - (data.lastTurnTime or 0) >= 1.4)
		and not humanoid.Jump
		and not isFreefallState
		and (dotToTarget >= -0.20 and dotToTarget <= 0.50) -- Sharp 60 to 105 deg lateral cut

	if canTurn90 then
		local turn90Anim = (localDir.X < 0) and "Movement.RunTurn90Left" or "Movement.RunTurn90Right"
		data.turnAnim = turn90Anim
		data.turnActiveUntil = now + 0.38
		data.lastTurnTime = now
		data.turnTargetHeading = flatTargetDir
		data.currentAnim = turn90Anim

		AnimationModule.playConfig(humanoid, turn90Anim, 1.65, Enum.AnimationPriority.Action, false)
	end

	-- 3. Curved Pursuit / Arc Run 30 Degree Rear (Mirrored Left / Right)
	local canArcRun = (CombatConfig.Chase_ArcRunOverlayEnabled == true)
		and not inShowdown
		and not shouldWalk
		and currentSpeed >= 16
		and (now >= (data.turnActiveUntil or 0))
		and (now >= (data.arcActiveUntil or 0))
		and (now - (data.lastArcTime or 0) >= 2.2)
		and not humanoid.Jump
		and not isFreefallState
		and (dotToTarget >= 0.58 and dotToTarget <= 0.94) -- 20 to 55 deg curved pursuit

	if canArcRun then
		local arcAnim = (localDir.X < 0) and "Movement.ArcRun30RearLeft" or "Movement.ArcRun30RearRight"
		data.arcAnim = arcAnim
		data.arcActiveUntil = now + 0.50
		data.lastArcTime = now
		data.currentAnim = arcAnim
		
		AnimationModule.playConfig(humanoid, arcAnim, 1.20, Enum.AnimationPriority.Action, false)
	end

	-- Not reachable in a straight line: follow a path round (PathfindingService)
	if not reachable and not inShowdown then
		local waypoint = NavigationModule.detourWaypoint(fighter, rootPart, targetHRP.Position)
		if waypoint then
			arcTarget = waypoint
			fighter:SetAttribute("ObstacleAwareness", "Going round")
		end
	end

	-- Authoritative single-driver steering & speed modulation
	if workspace:GetAttribute("LocoDebug") then fighter:SetAttribute("SteerTick", os.clock()) end -- (probes: Chase steered)
	LocomotionModule.steer(fighter, humanoid, rootPart, arcTarget, targetSpeed, dt)
	
	-- Fall cover and touchdown belong to the ground contract (GaitModule.bindGroundContract).
	-- This state used to play and stop the same Fall track on its own 10 Hz rule (stopping it
	-- on the way up and at the apex), so the two owners restarted the pose several times per
	-- jump. Only the dismount bookkeeping and the vault clip cleanup remain here.
	local isGrounded = SpatialModule.isGrounded(rootPart)
	if isFreefallState and not isGrounded then
		if data.wasOnPlatform then
			data.isDismountFalling = true
		end
	elseif isGrounded then
		if data.isDismountFalling then
			data.isDismountFalling = false
			data.wasOnPlatform = false
		end
		if math.abs(rootPart.AssemblyLinearVelocity.Y) < 3 and AnimationModule.isPlaying(humanoid, "Parkour.VaultObstacle") then
			AnimationModule.stopConfig(humanoid, "Parkour.VaultObstacle", 0.15)
		end
	end

end

return Steer
