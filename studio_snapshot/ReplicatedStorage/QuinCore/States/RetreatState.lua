--// RetreatState.lua
-- Phase 8 & 12 Redesign: Continuous Tactical Disengagement & Dynamic Escape State Machine
-- Features:
-- 1. Continuous per-frame locomotion (reusing proven ChaseState acceleration & arcTarget engine).
-- 2. Multi-candidate tactical evaluation via RetreatTacticsModule (Allies, High Ground, Cover, Distance).
-- 3. Dynamic transitions: Counterattack upon reaching allies, Vantage Hold upon securing high ground, LoS Break.
-- 4. Hysteresis commitment lock (prevents stop-and-go decision flapping).
-- 5. Full telemetry emission (RETREAT_STARTED, RETREAT_SURVIVED, RETREAT_COUNTERATTACK, RETREAT_TO_HIGH_GROUND).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")

local QuinCore = ReplicatedStorage:WaitForChild("QuinCore")
local CombatConfig = require(QuinCore:WaitForChild("CombatConfig"))
local AnimationModule = require(QuinCore:WaitForChild("Modules"):WaitForChild("AnimationModule"))
local KnockbackModule = require(QuinCore:WaitForChild("Modules"):WaitForChild("KnockbackModule"))
local SpatialModule = require(QuinCore:WaitForChild("Modules"):WaitForChild("SpatialModule"))
local RuntimeTracer = require(QuinCore:WaitForChild("Modules"):WaitForChild("RuntimeTracer"))
local BattleEventSystem = require(QuinCore:WaitForChild("Modules"):WaitForChild("BattleEventSystem"))
local RetreatTacticsModule = require(QuinCore:WaitForChild("Modules"):WaitForChild("RetreatTacticsModule"))
local LocomotionModule = require(QuinCore:WaitForChild("Modules"):WaitForChild("LocomotionModule"))
local GaitModule = require(QuinCore:WaitForChild("Modules"):WaitForChild("GaitModule"))
local TargetingModule = require(QuinCore:WaitForChild("Modules"):WaitForChild("TargetingModule"))
local Cognition = require(QuinCore:WaitForChild("Cognition"))
local PlatformCatalogue = require(QuinCore:WaitForChild("Modules"):WaitForChild("PlatformCatalogue"))
local TraversalModule = require(QuinCore:WaitForChild("Modules"):WaitForChild("TraversalModule"))

local RetreatState = { name = "Retreat" }
local retreatData = setmetatable({}, { __mode = "k" })

-- JumpHandler routed through authoritative LocomotionModule (Rule 4 & Rule 6)
local JumpHandler = LocomotionModule

local THREAT_RANGE = 160 -- studs within which a known enemy counts as a threat to get away from

local function gatherSides(fighter)
	local myTeam = fighter:GetAttribute("Team") or "None"
	local myHRP = fighter:FindFirstChild("HumanoidRootPart")
	local enemies, allies = {}, {}
	if not myHRP then return enemies, allies end
	local myPos = myHRP.Position
	for _, q in ipairs(CollectionService:GetTagged("Quin")) do
		if q ~= fighter and q.Parent and q:FindFirstChild("HumanoidRootPart") then
			local hum = q:FindFirstChildOfClass("Humanoid")
			if hum and hum.Health > 0 then
				local dist = (q.HumanoidRootPart.Position - myPos).Magnitude
				if myTeam ~= "None" and q:GetAttribute("Team") == myTeam then
					if dist <= 250 then
						table.insert(allies, q)
					end
				end
			end
		end
	end
	-- It runs from the enemies it knows about (seen, heard, remembered or reported)
	for _, contact in ipairs(Cognition.knownEnemies(fighter) or {}) do
		if contact.distance <= THREAT_RANGE and contact.model.Parent then
			table.insert(enemies, contact.model)
		end
	end
	return enemies, allies
end

function RetreatState.enter(fighter, humanoid, rootPart)
	local now = tick()
	local maxSpeed = fighter:GetAttribute("Speed") or 40
	-- Preserve existing running velocity; do NOT reset to 0
	local initialSpeed = humanoid.WalkSpeed
	if initialSpeed < 18 or initialSpeed > (maxSpeed * 1.2) then
		initialSpeed = 18
	end
	humanoid.WalkSpeed = initialSpeed
	humanoid.AutoRotate = true

	local enemies, allies = gatherSides(fighter)
	local initialHopDone = false

	-- Immediate close melee disengage (< 12 studs): evasive backstep slide
	if #enemies > 0 then
		local nearestDist = math.huge
		local nearestPos = nil
		for _, e in ipairs(enemies) do
			local eHRP = e:FindFirstChild("HumanoidRootPart")
			if eHRP then
				local d = (eHRP.Position - rootPart.Position).Magnitude
				if d < nearestDist then
					nearestDist = d
					nearestPos = eHRP.Position
				end
			end
		end

		if nearestDist <= 12 and nearestPos then
			local awayFlat = Vector3.new(rootPart.Position.X - nearestPos.X, 0, rootPart.Position.Z - nearestPos.Z)
			local hopDir = (awayFlat.Magnitude > 0.1) and awayFlat.Unit or -rootPart.CFrame.LookVector
			AnimationModule.playConfig(humanoid, "Tactics.RetreatBackstep", 1.3, Enum.AnimationPriority.Action3, false)
			KnockbackModule.applySlide(fighter, hopDir, 34, 0.25)
			initialHopDone = true
		end
	end

	-- Running comes from the shared gait (playing the Run clip directly restarted the cycle)
	local initialAnim = (initialHopDone and CombatConfig.Chase_PushOffOverlay == true) and "Movement.StartSprint" or "Gait"
	if initialAnim ~= "Gait" then
		AnimationModule.playConfig(humanoid, initialAnim)
	else
		GaitModule.update(humanoid, rootPart, 1 / 60)
	end

	retreatData[fighter] = {
		enterTime = now,
		lastUpdateTime = now,
		currentSpeed = initialSpeed,
		currentAnim = initialAnim,
		isAccelerating = true,
		isDecelerating = false,
		initialHP = humanoid.Health,
		initialPos = rootPart.Position,
		startEnemyCount = #enemies,
	}

	fighter:SetAttribute("CurrentState", "Retreat")
	fighter:SetAttribute("RetreatStartTime", now)

	BattleEventSystem.emit("RETREAT_STARTED", {
		QuinId = fighter:GetAttribute("QuinId") or fighter.Name,
		Model = fighter,
		InitialHP = humanoid.Health,
		EnemyCount = #enemies,
		AllyCount = #allies,
	})

	RuntimeTracer.checkpoint(fighter, "Enter Retreat (tactical disengage)")
end

function RetreatState.exit(fighter, humanoid, rootPart)
	local data = retreatData[fighter]
	if data and data.currentAnim == "Gait" then
		-- Gait keeps running into the next state; the ground contract releases it if unused
	elseif data and data.currentAnim then
		AnimationModule.stopConfig(humanoid, data.currentAnim, 0.15)
	end

	retreatData[fighter] = nil
end

function RetreatState.update(fighter, humanoid, rootPart, DEBUG)
	-- Sacred Showdown: Duelists stand and fight; spectators watch
	local showdownRole = fighter:GetAttribute("LeaderShowdownRole")
	if showdownRole == "Duelist" then
		return require(script.Parent:WaitForChild("FightState"))
	elseif showdownRole == "PerimeterGuard" or showdownRole == "Transition" then
		return require(script.Parent:WaitForChild("LeaderShowdownState"))
	end

	local data = retreatData[fighter]
	if not data then return require(script.Parent:WaitForChild("IdleState")) end

	-- Prone / Cockroach protection: if flat on ground, immediately recover
	local upY = rootPart.CFrame.UpVector.Y
	if upY < 0.6 and SpatialModule.isGrounded(rootPart) then
		fighter:SetAttribute("KnockbackType", "hard_ground")
		return require(script.Parent:WaitForChild("RecoveryState"))
	end

	local now = tick()
	local elapsed = now - data.enterTime
	local enemies, allies = gatherSides(fighter)

	-- ============================================================
	-- 1. TACTICAL EVALUATION VIA RETREAT TACTICS MODULE
	-- ============================================================
	local board = Cognition.Blackboard.peek(fighter)
	local standHeight = humanoid.HipHeight + rootPart.Size.Y / 2
	local canProjectileJump = CombatConfig.EnableProjectileJump ~= false and fighter:GetAttribute("EnableProjectileJump") ~= false
		and (fighter:GetAttribute("Energy") or 100) >= (CombatConfig.ProjectileJumpMinEnergy or 40)
		and (now - (fighter:GetAttribute("LastProjectileJumpTime") or 0)) >= (CombatConfig.ProjectileJump_Cooldown or 14.0)
	local result = RetreatTacticsModule.evaluate(fighter, enemies, allies, {
		plan = data.plan,
		standHeight = standHeight,
		canProjectileJump = canProjectileJump,
		stalled = board ~= nil and board.self ~= nil and board.self.stalledFor > 0.6,
	})
	data.plan = result.plan
	fighter:SetAttribute("RetreatObjective", result.objective)
	fighter:SetAttribute("RetreatScore", math.round(result.score * 100) / 100)
	fighter:SetAttribute("IsCornered", result.isCornered)
	fighter:SetAttribute("DistanceThreatPhase", result.distanceThreatPhase or "SAFE_LEAD")
	fighter:SetAttribute("ClosingSpeed", math.round((result.closingSpeed or 0) * 10) / 10)
	fighter:SetAttribute("FleeManeuver", result.maneuver or "CONTINUOUS_RUN")
	fighter:SetAttribute("IsJuking", result.isJuking == true)

	-- Format candidate scores for HUD
	local cScores = result.candidateScores or {}
	fighter:SetAttribute("RetreatScoresHUD", string.format("Allies:%.0f | High:%.0f | LoS:%.0f | Open:%.0f",
		cScores["TO_ALLIES"] or 0,
		cScores["TO_HIGH_GROUND"] or 0,
		cScores["BREAK_LOS"] or 0,
		cScores["OPEN_GROUND"] or 0
	))

	-- ============================================================
	-- 2. DYNAMIC STATE TRANSITIONS & HYSTERESIS COMMITMENT
	-- ============================================================
	local minCommitDuration = CombatConfig.RetreatMinDuration or 1.2

	-- Nearest threat distance
	local nearestThreatDist = result.nearestEnemyDist or math.huge
	local nearestThreat = result.primaryPursuer
	if not nearestThreat and #enemies > 0 then
		for _, e in ipairs(enemies) do
			local eHRP = e:FindFirstChild("HumanoidRootPart")
			if eHRP then
				local d = (eHRP.Position - rootPart.Position).Magnitude
				if d < nearestThreatDist then
					nearestThreatDist = d
					nearestThreat = e
				end
			end
		end
	end

	-- TRANSITION 1: LAST STAND / SUICIDAL ESCAPE HANDOFF
	-- If escape feasibility collapsed or fighter was set to LastStandMode, turn and make enemies pay!
	local isLastStand = fighter:GetAttribute("LastStandMode")
	local escapeFeas = fighter:GetAttribute("EscapeFeasibility") or 1.0
	if isLastStand or (escapeFeas < (CombatConfig.EscapeFeasibilityThreshold or 0.20) and elapsed >= minCommitDuration) then
		BattleEventSystem.emit("LAST_STAND_TRIGGERED", {
			QuinId = fighter:GetAttribute("QuinId") or fighter.Name,
			Model = fighter,
			EnemyCount = #enemies,
			Reason = "EscapeSuicidal",
		})
		fighter:SetAttribute("LastStandMode", true)
		fighter:SetAttribute("DesperateCounter", true)
		TargetingModule.setTarget(fighter, nearestThreat)
		RuntimeTracer.checkpoint(fighter, "Escape suicidal -> Turn to Last Stand fight!")
		return require(script.Parent:WaitForChild("FightState"))
	end

	-- TRANSITION 2: DEFEND & DELAY (Reinforcing Ally Approaching)
	-- If an ally is closing in (<= 35 studs), do not flee past them; hold ground and delay pursuer.
	-- If already within squad cluster (<= 16 studs), fall through to Outcome B (squad counterattack) instead.
	local nearestAllyDist = math.huge
	for _, ally in ipairs(allies) do
		local aHRP = ally:FindFirstChild("HumanoidRootPart")
		if aHRP then
			local d = (aHRP.Position - rootPart.Position).Magnitude
			if d < nearestAllyDist then nearestAllyDist = d end
		end
	end

	if nearestAllyDist > 16 and fighter:GetAttribute("ReinforcingAllyApproaching") == true and nearestThreatDist <= (CombatConfig.DefendDelayDistance or 35.0) and elapsed >= minCommitDuration then
		fighter:SetAttribute("IsGuarding", true)
		RuntimeTracer.checkpoint(fighter, "Ally reinforcing -> Defend & Delay stance")
		return require(script.Parent:WaitForChild("CirclingState"))
	end

	-- TRANSITION 3: PURSUER OVEREXTENSION / WHIFF COUNTERATTACK
	-- If pursuer swung and missed, or overshot past runner within 10 studs, seize initiative!
	-- Only a Quin with fight left in it turns round; one running for its life keeps running
	local canTurnAndFight = humanoid.Health / humanoid.MaxHealth > (CombatConfig.RetreatCriticalHealth or 0.20)
	if canTurnAndFight and nearestThreat and nearestThreatDist <= (CombatConfig.PursuerOverextendWhiffDistance or 10.0) and elapsed >= minCommitDuration then
		local threatAttacking = nearestThreat:GetAttribute("Attacking")
		local threatWindupUntil = nearestThreat:GetAttribute("AttackWindupUntil") or 0
		local hasWhiffed = threatAttacking and (now > threatWindupUntil)
		local hasOvershot = false
		local eHRP = nearestThreat:FindFirstChild("HumanoidRootPart")
		if eHRP then
			local toThreat = (eHRP.Position - rootPart.Position).Unit
			local runnerLook = rootPart.CFrame.LookVector
			if toThreat:Dot(runnerLook) > 0.40 then
				hasOvershot = true
			end
		end

		if hasWhiffed or hasOvershot then
			BattleEventSystem.emit("RETREAT_COUNTERATTACK", {
				QuinId = fighter:GetAttribute("QuinId") or fighter.Name,
				Model = fighter,
				TargetName = nearestThreat.Name,
				Reason = hasWhiffed and "PursuerWhiff" or "PursuerOvershot",
			})
			fighter:SetAttribute("RetreatCounterattacked", true)
			TargetingModule.setTarget(fighter, nearestThreat)
			RuntimeTracer.checkpoint(fighter, "Pursuer overextended -> Turn and Counterattack!")
			return require(script.Parent:WaitForChild("FightState"))
		end
	end

	-- Outcome A: got away. Either far enough across the arena, or the pursuer has not had a
	-- line of sight for a while (it lost them).
	local safeDist = math.max(CombatConfig.RetreatSafeDistance or 85.0, SpatialModule.getArenaBounds().radius * (CombatConfig.Retreat_SafeDistanceRatio or 0.4))
	local minRetreatDur = CombatConfig.RetreatMinDuration or 2.5
	local threatRoot = nearestThreat and nearestThreat:FindFirstChild("HumanoidRootPart")
	if threatRoot and not SpatialModule.checkLineOfSight(SpatialModule.getEyePosition(threatRoot), SpatialModule.getEyePosition(rootPart), { fighter, nearestThreat }) then
		data.unseenSince = data.unseenSince or now
	else
		data.unseenSince = nil
	end
	local lostThem = data.unseenSince ~= nil and (now - data.unseenSince) >= (CombatConfig.Retreat_LostSightTime or 2.5)
		and nearestThreatDist >= (CombatConfig.Retreat_LostSightMinDistance or 40)
	fighter:SetAttribute("RetreatUnseen", data.unseenSince ~= nil)
	if #enemies == 0 or nearestThreatDist >= safeDist or lostThem then
		if elapsed >= minRetreatDur then
			BattleEventSystem.emit("RETREAT_SURVIVED", {
				QuinId = fighter:GetAttribute("QuinId") or fighter.Name,
				Model = fighter,
				FinalHP = humanoid.Health,
				DistanceGained = (rootPart.Position - data.initialPos).Magnitude,
				Objective = result.objective,
			})
			RuntimeTracer.checkpoint(fighter, lostThem and "Retreat: lost the pursuer" or "Retreat reached safety")
			-- Regroup & hold defensive standoff with energy recovery; do NOT dead-stop into IdleState
			return require(script.Parent:WaitForChild("CirclingState"))
		end
	end

	-- Outcome B: Reached Allies -> Turn and COUNTERATTACK! (Guaranteed commitment fulfilled)
	if canTurnAndFight and result.objective == "TO_ALLIES" and #allies >= 1 and elapsed >= minCommitDuration then
		local allyDist = (result.targetPosition - rootPart.Position).Magnitude
		if allyDist <= 16 then
			-- We successfully pulled pursuer to allies! Turn and strike!
			BattleEventSystem.emit("RETREAT_TO_ALLIES", {
				QuinId = fighter:GetAttribute("QuinId") or fighter.Name,
				Model = fighter,
				AllyCount = #allies,
			})
			BattleEventSystem.emit("RETREAT_COUNTERATTACK", {
				QuinId = fighter:GetAttribute("QuinId") or fighter.Name,
				Model = fighter,
				TargetName = nearestThreat and nearestThreat.Name or "Unknown",
			})
			fighter:SetAttribute("RetreatCounterattacked", true)
			TargetingModule.setTarget(fighter, nearestThreat)
			RuntimeTracer.checkpoint(fighter, "Retreat reached allies -> COUNTERATTACK!")
			return require(script.Parent:WaitForChild("FightState"))
		end
	end

	-- After minimum commitment duration, evaluate remaining tactical exits
	if elapsed >= minCommitDuration then

		-- Outcome C: Reached High Ground -> Secure vantage point
		if result.objective == "TO_HIGH_GROUND" then
			local heightDiff = rootPart.Position.Y - data.initialPos.Y
			if heightDiff >= 4.5 and SpatialModule.isGrounded(rootPart) then
				BattleEventSystem.emit("RETREAT_TO_HIGH_GROUND", {
					QuinId = fighter:GetAttribute("QuinId") or fighter.Name,
					Model = fighter,
					ElevationGained = heightDiff,
				})
				RuntimeTracer.checkpoint(fighter, "Retreat secured high ground -> Holding vantage")
				local OverwatchState = require(script.Parent:WaitForChild("OverwatchState"))
				if OverwatchState.canHold(fighter, rootPart) then
					return OverwatchState
				end
				return require(script.Parent:WaitForChild("CirclingState"))
			end
		end

		-- Outcome D: Cornered Trap -> Desperate Counter Stand
		if result.isCornered then
			BattleEventSystem.emit("RETREAT_FAILED", {
				QuinId = fighter:GetAttribute("QuinId") or fighter.Name,
				Model = fighter,
				Reason = "Cornered",
			})
			fighter:SetAttribute("LastStandMode", true)
			fighter:SetAttribute("DesperateCounter", true)
			RuntimeTracer.checkpoint(fighter, "Retreat cornered -> Desperate Stand")
			return require(script.Parent:WaitForChild("FightState"))
		end

		-- Decision changed by player command or external system
		-- The run is finished before the Quin reconsiders. Leaving the fight is what makes the
		-- reason to leave go away (no longer outnumbered once it is out of the crowd), so
		-- reconsidering mid-run turned every retreat into a 2.5 s out-and-back.
		local runFinished = (result.targetPosition - rootPart.Position).Magnitude <= (CombatConfig.Retreat_ArriveDistance or 10) + 8
			or elapsed >= (CombatConfig.Retreat_PlanHold or 4.0)
		local recAction = fighter:GetAttribute("RecommendedAction")
		if recAction and recAction ~= "Retreat" and nearestThreatDist > 20 and runFinished then
			RuntimeTracer.checkpoint(fighter, "Retreat complete -> " .. recAction)
			return require(script.Parent:WaitForChild("CirclingState"))
		end
	end

	-- ============================================================
	-- 3. PARKOUR OBSTACLE & EVASION LOGIC (Matching ChaseState)
	-- ============================================================
	local obsInfo = SpatialModule.analyzeObstacleAhead(rootPart, result.targetPosition, 20)
	local obstacleSteer = nil
	if obsInfo.hasObstacle then
		if obsInfo.canVault and not humanoid.Jump and humanoid:GetState() ~= Enum.HumanoidStateType.Freefall then
			fighter:SetAttribute("ObstacleAwareness", "Retreat Vaulting Obstacle")
			JumpHandler.performJump(humanoid, rootPart, obsInfo.height, nil, "vault")
		elseif obsInfo.isTall then
			obstacleSteer = obsInfo.steerDirection
		end
	end

	-- Evasive Low-Gap Slide (Phase 6): slide under low obstacles to break pursuit
	local slideGap = SpatialModule.detectLowOverheadGap(rootPart, 8)
	local energy = fighter:GetAttribute("Energy") or 100
	local lastSlide = fighter:GetAttribute("LastSlideTime") or 0
	local canSlide = (now - lastSlide) >= (CombatConfig.SlideCooldown or 2.5) and energy >= (CombatConfig.SlideMinEnergy or 12)
		and not humanoid.Jump and humanoid:GetState() ~= Enum.HumanoidStateType.Freefall
	if slideGap and canSlide then
		RuntimeTracer.checkpoint(fighter, "Retreat sliding under obstacle gap")
		LocomotionModule.slide(fighter, humanoid, rootPart)
		return RetreatState
	end

	-- Evasive Wall-Run (Phase 6): wall-run along arena boundaries
	local lastWallRun = fighter:GetAttribute("LastWallRunTime") or 0
	local canWallRun = (now - lastWallRun) >= (CombatConfig.WallRunCooldown or 5.0) and energy >= (CombatConfig.WallRunMinEnergy or 15)
		and (data.currentSpeed or 30) >= 20 and not humanoid.Jump and humanoid:GetState() ~= Enum.HumanoidStateType.Freefall
	if canWallRun then
		local wallSurface = SpatialModule.detectWallRunSurface(rootPart, CombatConfig.WallRunRayDistance or 5.2, CombatConfig.WallRunMinRunway or 24)
		if wallSurface then
			fighter:SetAttribute("LastWallRunTime", now)
			RuntimeTracer.checkpoint(fighter, "Retreat wall-running away from threat")
			return require(script.Parent:WaitForChild("WallRunState"))
		end
	end

	-- High ground: get onto the platform the escape plan chose. A high one takes a projectile
	-- jump to the spot; one within a jump's reach is jumped onto once the run-up fits.
	local planPlatform = result.plan and result.plan.platform
	if result.objective == "TO_HIGH_GROUND" and planPlatform and not humanoid.Jump and humanoid:GetState() ~= Enum.HumanoidStateType.Freefall then
		if result.plan.access == PlatformCatalogue.Access.ProjectileJump then
			if canProjectileJump then
				fighter:SetAttribute("ObstacleAwareness", "Projectile jump to high ground")
				RuntimeTracer.checkpoint(fighter, "Retreat: projectile jump onto a platform")
				local ProjectileJumpState = require(script.Parent:WaitForChild("ProjectileJumpState"))
				ProjectileJumpState.aimAtPoint(fighter, result.targetPosition)
				return ProjectileJumpState
			end
		else
			local edge = PlatformCatalogue.nearestTopPoint(planPlatform, rootPart.Position, 0)
			local toEdge = Vector3.new(edge.X - rootPart.Position.X, 0, edge.Z - rootPart.Position.Z)
			local rise = planPlatform.topY - (rootPart.Position.Y - standHeight)
			if rise > TraversalModule.Config.StepHeight and toEdge.Magnitude > 0.1 then
				local solution = TraversalModule.solveJumpOnto(rise, toEdge.Magnitude, CombatConfig.Jump_MaxReach or 12.0)
				if solution and rootPart.CFrame.LookVector:Dot(toEdge.Unit) > 0.85 then
					fighter:SetAttribute("ObstacleAwareness", "Jumping to high ground")
					JumpHandler.performJump(humanoid, rootPart, solution.height, solution.speed, "jump")
				end
			end
		end
	end

	-- ============================================================
	-- 4. CONTINUOUS PER-FRAME LOCOMOTION & STEERING (ChaseState Engine)
	-- ============================================================
	local speedMult = workspace:GetAttribute("GameSpeedMultiplier") or 1.0
	local maxSpeed = (fighter:GetAttribute("Speed") or 40) * speedMult
	local lastUpdate = data.lastUpdateTime or (now - 0.05)
	local dt = math.clamp(now - lastUpdate, 0.016, 0.25)
	data.lastUpdateTime = now

	local currentSpeed = humanoid.WalkSpeed
	data.isAccelerating = (currentSpeed < maxSpeed - 2.0)
	data.currentSpeed = currentSpeed

	-- Animation track selection with push-off awareness
	local desiredAnim
	if CombatConfig.Chase_PushOffOverlay == true and data.isAccelerating and currentSpeed < (maxSpeed * 0.55) then
		desiredAnim = "Movement.StartSprint"
	else
		desiredAnim = "Movement.Run"
	end
	local isFreefall = (humanoid:GetState() == Enum.HumanoidStateType.Freefall)
	if desiredAnim == "Movement.Run" then
		-- Base gait: shared stride-matched Walk/Run blend driven by real ground speed
		-- (the start overlay hands over here instead of playing out over the sprint)
		if data.currentAnim and data.currentAnim ~= "Gait" then
			AnimationModule.stopConfig(humanoid, data.currentAnim, 0.2)
		end
		data.currentAnim = "Gait"
		if not isFreefall then
			GaitModule.update(humanoid, rootPart, dt)
		end
	elseif data.currentAnim ~= desiredAnim then
		data.currentAnim = desiredAnim
		AnimationModule.playConfig(humanoid, desiredAnim)
	elseif not isFreefall and not AnimationModule.isPlaying(humanoid, data.currentAnim) then
		AnimationModule.playConfig(humanoid, data.currentAnim)
	end

	-- Compute dynamic arcTarget on every single tick
	local arcTarget = result.targetPosition
	if result.isJuking and result.steerDirection then
		-- Sharp lateral juke cut target
		arcTarget = rootPart.Position + result.steerDirection * 18
		if CombatConfig.Chase_TurnCutOverlayEnabled == true and currentSpeed >= 14 and (now >= (data.jukeAnimUntil or 0)) and (now - (data.lastJukeAnim or 0) >= 1.2) then
			data.jukeAnimUntil = now + 0.38
			data.lastJukeAnim = now
			local isRight = (result.steerDirection:Dot(rootPart.CFrame.RightVector) > 0)
			local turnAnim = isRight and "Movement.RunTurn90Right" or "Movement.RunTurn90Left"
			AnimationModule.playConfig(humanoid, turnAnim, 1.65, Enum.AnimationPriority.Action, false)
		end
	else
		local dirToTarget = (arcTarget - rootPart.Position).Unit

		local nearEdge, awayDir = SpatialModule.isNearArenaEdge(rootPart, 6)
		if nearEdge then
			arcTarget = rootPart.Position + awayDir * 12 + dirToTarget * 4
		end

		local centerPull = SpatialModule.getArenaCenterPull(rootPart)
		if centerPull.Magnitude > 0.1 then
			arcTarget = arcTarget + centerPull * 12
		end

		if obstacleSteer then
			arcTarget = rootPart.Position + obstacleSteer * 16
		else
			local hasObstacleAhead = SpatialModule.raycastForward(rootPart, 5)
			if hasObstacleAhead then
				local safeDir = SpatialModule.getObstacleAvoidanceDirection(rootPart, 5)
				arcTarget = rootPart.Position + safeDir * 10
			end
		end
	end

	-- Continuous per-frame target steering with dynamic traction skid
	LocomotionModule.steer(fighter, humanoid, rootPart, arcTarget, maxSpeed, dt)

	return RetreatState
end

return RetreatState
