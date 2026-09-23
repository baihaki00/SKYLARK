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

local RetreatState = { name = "Retreat" }
local retreatData = {}

-- JumpHandler routed through authoritative LocomotionModule (Rule 4 & Rule 6)
local JumpHandler = LocomotionModule

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
				if (q.HumanoidRootPart.Position - myPos).Magnitude <= 80 then
					if myTeam ~= "None" and q:GetAttribute("Team") == myTeam then
						table.insert(allies, q)
					else
						table.insert(enemies, q)
					end
				end
			end
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

	local initialAnim = initialHopDone and "Movement.StartSprint" or "Movement.Run"
	AnimationModule.playConfig(humanoid, initialAnim)

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
	if data and data.currentAnim then
		AnimationModule.stopConfig(humanoid, data.currentAnim, 0.15)
	end

	if data and data.rootJoint then
		local origC0 = data.rootJoint:GetAttribute("OriginalC0")
		if origC0 then
			data.rootJoint.C0 = origC0
		end
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
	local result = RetreatTacticsModule.evaluate(fighter, enemies, allies)
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
	if isLastStand or (escapeFeas < (CombatConfig.EscapeFeasibilityThreshold or 0.20) and elapsed >= 0.20) then
		BattleEventSystem.emit("LAST_STAND_TRIGGERED", {
			QuinId = fighter:GetAttribute("QuinId") or fighter.Name,
			Model = fighter,
			EnemyCount = #enemies,
			Reason = "EscapeSuicidal",
		})
		fighter:SetAttribute("LastStandMode", true)
		fighter:SetAttribute("DesperateCounter", true)
		fighter:SetAttribute("CurrentTarget", nearestThreat and nearestThreat.Name or "")
		fighter:SetAttribute("TargetQuin", nearestThreat and nearestThreat.Name or "")
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

	if nearestAllyDist > 16 and fighter:GetAttribute("ReinforcingAllyApproaching") == true and nearestThreatDist <= (CombatConfig.DefendDelayDistance or 35.0) and elapsed >= 0.20 then
		fighter:SetAttribute("IsGuarding", true)
		RuntimeTracer.checkpoint(fighter, "Ally reinforcing -> Defend & Delay stance")
		return require(script.Parent:WaitForChild("CirclingState"))
	end

	-- TRANSITION 3: PURSUER OVEREXTENSION / WHIFF COUNTERATTACK
	-- If pursuer swung and missed, or overshot past runner within 10 studs, seize initiative!
	if nearestThreat and nearestThreatDist <= (CombatConfig.PursuerOverextendWhiffDistance or 10.0) and elapsed >= 0.30 then
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
			fighter:SetAttribute("CurrentTarget", nearestThreat.Name)
			fighter:SetAttribute("TargetQuin", nearestThreat.Name)
			RuntimeTracer.checkpoint(fighter, "Pursuer overextended -> Turn and Counterattack!")
			return require(script.Parent:WaitForChild("FightState"))
		end
	end

	-- Outcome A: Safe Haven Reached (threat dropped or out of pursuit range)
	if #enemies == 0 or nearestThreatDist >= 40 then
		if elapsed >= 0.8 then
			BattleEventSystem.emit("RETREAT_SURVIVED", {
				QuinId = fighter:GetAttribute("QuinId") or fighter.Name,
				Model = fighter,
				FinalHP = humanoid.Health,
				DistanceGained = (rootPart.Position - data.initialPos).Magnitude,
				Objective = result.objective,
			})
			RuntimeTracer.checkpoint(fighter, "Retreat reached safety")
			return require(script.Parent:WaitForChild("IdleState"))
		end
	end

	-- Outcome B: Reached Allies -> Turn and COUNTERATTACK! (Immediate as soon as squad reached)
	if result.objective == "TO_ALLIES" and #allies >= 1 and elapsed >= 0.25 then
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
			fighter:SetAttribute("CurrentTarget", nearestThreat and nearestThreat.Name or "")
			fighter:SetAttribute("TargetQuin", nearestThreat and nearestThreat.Name or "")
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
		local recAction = fighter:GetAttribute("RecommendedAction")
		if recAction and recAction ~= "Retreat" and nearestThreatDist > 20 then
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
		local wallSurface = SpatialModule.detectWallRunSurface(rootPart, CombatConfig.WallRunRayDistance or 5.2)
		if wallSurface then
			fighter:SetAttribute("LastWallRunTime", now)
			RuntimeTracer.checkpoint(fighter, "Retreat wall-running away from threat")
			return require(script.Parent:WaitForChild("WallRunState"))
		end
	end

	-- High-Ground vertical jump if approaching elevated platform
	if result.objective == "TO_HIGH_GROUND" and not humanoid.Jump and humanoid:GetState() ~= Enum.HumanoidStateType.Freefall then
		local distToPlat = (result.targetPosition - rootPart.Position).Magnitude
		local verticalDelta = result.targetPosition.Y - rootPart.Position.Y
		if distToPlat <= 18 and verticalDelta >= 4.0 and verticalDelta <= 20.0 then
			JumpHandler.performJump(humanoid, rootPart, verticalDelta + 3.0, 48, "jump")
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

	local accelRate = (CombatConfig.LocomotionAcceleration or 70) * speedMult
	local currentSpeed = data.currentSpeed or humanoid.WalkSpeed
	if currentSpeed < maxSpeed then
		currentSpeed = math.min(maxSpeed, currentSpeed + accelRate * dt)
		data.isAccelerating = true
	else
		data.isAccelerating = false
	end
	data.currentSpeed = currentSpeed
	humanoid.WalkSpeed = currentSpeed

	-- Animation track selection with push-off awareness
	local desiredAnim
	if data.isAccelerating and currentSpeed < (maxSpeed * 0.55) then
		desiredAnim = "Movement.StartSprint"
	else
		desiredAnim = "Movement.Run"
	end
	if data.currentAnim ~= desiredAnim then
		data.currentAnim = desiredAnim
		AnimationModule.playConfig(humanoid, desiredAnim)
	else
		local isFreefall = (humanoid:GetState() == Enum.HumanoidStateType.Freefall)
		if not isFreefall and not AnimationModule.isPlaying(humanoid, data.currentAnim) then
			AnimationModule.playConfig(humanoid, data.currentAnim)
		end
	end

	-- Compute dynamic arcTarget on every single tick
	local arcTarget = result.targetPosition
	if result.isJuking and result.steerDirection then
		-- Sharp lateral juke cut target
		arcTarget = rootPart.Position + result.steerDirection * 18
		if currentSpeed >= 14 and (now >= (data.jukeAnimUntil or 0)) and (now - (data.lastJukeAnim or 0) >= 1.2) then
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
	LocomotionModule.steer(fighter, humanoid, rootPart, arcTarget, currentSpeed, 0.1)

	-- Dynamic forward torso lean & banking (rootJoint.C0)
	local rootJoint = data.rootJoint
	if not rootJoint then
		for _, child in pairs(fighter:GetDescendants()) do
			if child:IsA("Motor6D") and child.Part0 == rootPart then
				rootJoint = child
				data.rootJoint = rootJoint
				if not rootJoint:GetAttribute("OriginalC0") then
					rootJoint:SetAttribute("OriginalC0", rootJoint.C0)
				end
				break
			end
		end
	end
	if rootJoint then
		local origC0 = rootJoint:GetAttribute("OriginalC0")
		if origC0 then
			local leanAngle = data.isAccelerating and math.rad(-20) or math.rad(-14)
			local maxRollDeg = CombatConfig.TorsoBankingMaxRoll or 12.0
			local targetBankRoll = 0
			if result.isJuking and result.steerDirection then
				-- Dynamic banking into the lateral cut (roll around Z)
				local isRight = (result.steerDirection:Dot(rootPart.CFrame.RightVector) > 0)
				targetBankRoll = isRight and -math.rad(maxRollDeg * 1.25) or math.rad(maxRollDeg * 1.25)
			else
				local angVelY = rootPart.AssemblyAngularVelocity.Y
				local strideBase = CombatConfig.RunStrideBase or 38.0
				local speedRatio = math.clamp(currentSpeed / strideBase, 0.2, 1.4)
				targetBankRoll = -math.clamp(angVelY * speedRatio * math.rad(maxRollDeg * 0.12), -math.rad(maxRollDeg), math.rad(maxRollDeg))
			end
			data.currentBankRoll = (data.currentBankRoll or 0) + (targetBankRoll - (data.currentBankRoll or 0)) * 0.16
			rootJoint.C0 = rootJoint.C0:Lerp(origC0 * CFrame.Angles(leanAngle, 0, data.currentBankRoll), 0.14)
		end
	end

	return RetreatState
end

function RetreatState.exit(fighter, humanoid, rootPart)
	local data = retreatData[fighter]
	if data and data.rootJoint then
		local origC0 = data.rootJoint:GetAttribute("OriginalC0")
		if origC0 then
			data.rootJoint.C0 = origC0
		end
	end
	retreatData[fighter] = nil
end

return RetreatState
