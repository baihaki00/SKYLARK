--// ChaseState.lua
-- Intelligent pathfinding chase with obstacle jumping and smooth lean
-- Single Source of Truth: ReplicatedStorage.QuinCore.AnimationConfig

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")
local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")

local TargetingModule = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("TargetingModule"))
local AnimationModule = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("AnimationModule"))
local CombatConfig = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("CombatConfig"))
local SpatialModule = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("SpatialModule"))
local KnockbackModule = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("KnockbackModule"))
local BattleEventSystem = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("BattleEventSystem"))
local LocomotionModule = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("LocomotionModule"))
local RuntimeTracer = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("RuntimeTracer"))

local function findModelByName(name)
	if not name or name == "" then return nil end
	local quinServer = workspace:FindFirstChild("QuinServer") or workspace
	local m = quinServer:FindFirstChild(name) or workspace:FindFirstChild(name)
	if m and m:IsA("Model") and m:FindFirstChild("HumanoidRootPart") then
		return m
	end
	for _, tag in ipairs(CollectionService:GetTagged("Quin")) do
		if tag.Name == name and tag:FindFirstChild("HumanoidRootPart") then
			return tag
		end
	end
	return nil
end

local ChaseState = { name = "Chase" }

-- JumpHandler routed through authoritative LocomotionModule (Rule 4 & Rule 6)
local JumpHandler = LocomotionModule

local chaseData = {}

local function selectPacingStrategy(fighter)
	local mobility = fighter:GetAttribute("Pers_MobilityPreference") or 0.6
	local aggression = fighter:GetAttribute("Pers_Aggression") or 0.6
	local dashPref = fighter:GetAttribute("Pers_DashPreference") or 0.6
	local confidence = fighter:GetAttribute("Pers_Confidence") or 0.6
	
	local rand = math.random()
	
	if mobility > 0.75 or aggression > 0.75 then
		-- High mobility / aggressive: sprint with athletic jumps or alternating pace
		if rand < 0.40 then
			return "ContinuousSprint"
		elseif rand < 0.75 then
			return "AlternatingPace"
		else
			return "WalkThenSprint"
		end
	elseif aggression < 0.45 or confidence < 0.45 then
		-- Cautious / tactical style: stalk/walk first to conserve stamina
		if rand < 0.45 then
			return "ConfidentWalk"
		elseif rand < 0.80 then
			return "WalkThenSprint"
		else
			return "AlternatingPace"
		end
	else
		-- Balanced chassis: diverse natural mix
		if rand < 0.30 then
			return "AlternatingPace"
		elseif rand < 0.60 then
			return "WalkThenSprint"
		elseif rand < 0.80 then
			return "ContinuousSprint"
		else
			return "ConfidentWalk"
		end
	end
end

function ChaseState.enter(fighter, humanoid, rootPart)
	local strategy = selectPacingStrategy(fighter)
	local pacingOverride = fighter:GetAttribute("InitialPacingOverride")
	if pacingOverride then
		strategy = pacingOverride
		fighter:SetAttribute("InitialPacingOverride", nil)
	end
	local mobility = fighter:GetAttribute("Pers_MobilityPreference") or 0.6
	local now = tick()
	
	local initialSpeed = humanoid.WalkSpeed
	-- If coming from stationary (0) or walking, preserve it so acceleration builds smoothly
	if initialSpeed < 4 or initialSpeed > 40 then
		initialSpeed = 0
	end
	humanoid.WalkSpeed = initialSpeed
	humanoid.AutoRotate = true

	local initialAnim = "Movement.Run"
	local pushOffAnim = nil
	if strategy == "ConfidentWalk" or strategy == "WalkThenSprint" then
		initialAnim = "Movement.WalkConfident"
	elseif initialSpeed < 10 then
		pushOffAnim = (mobility > 0.55 or math.random() > 0.5) and "Movement.IdleToRun1" or "Movement.IdleToRun2"
		initialAnim = pushOffAnim
	end

	chaseData[fighter] = {
		lastStepTime = 0,
		lastUpdateTime = now,
		currentSpeed = initialSpeed,
		isAccelerating = true,
		isDecelerating = false,
		currentAnim = initialAnim,
		pushOffAnim = pushOffAnim,
		lastTurnTime = 0,
		turnActiveUntil = 0,
		turnAnim = nil,
		turnTargetHeading = nil,
		lastArcTime = 0,
		arcActiveUntil = 0,
		arcAnim = nil,
		arcOffset = (math.random() > 0.5 and 1 or -1) * math.random(3, 8),
		arcChangeTime = now + math.random(2, 5),
		nextJumpTime = now + (8 - mobility * 4) + math.random(1, 3),
		nextDashCheckTime = now + math.random(5, 9),
		nextPJCheckTime = now + math.random(6, 12),
		pacingStrategy = strategy,
		isPacingWalk = (strategy == "ConfidentWalk" or strategy == "WalkThenSprint"),
		enterTime = now,
		targetLKP = nil,
		lastLoSTime = now,
		sprintStartTime = now,
		pacingSwitchTime = now + math.random(3, 6),
	}

	BattleEventSystem.emit("CHASE_STARTED", {
		QuinId = fighter:GetAttribute("QuinId") or fighter.Name,
		Model = fighter,
		TargetName = target and target.Name or "Unknown",
	})
	
	AnimationModule.playConfig(humanoid, initialAnim)
end

function ChaseState.exit(fighter, humanoid, rootPart)
	local data = chaseData[fighter]
	if data then
		if data.currentAnim then
			AnimationModule.stop(humanoid, data.currentAnim, 0.3)
		end
		if data.turnAnim then
			AnimationModule.stop(humanoid, data.turnAnim, 0.15)
		end
		if data.arcAnim then
			AnimationModule.stop(humanoid, data.arcAnim, 0.15)
		end
	end
	
	AnimationModule.stopLocomotionOverlays(humanoid, 0.15)
	
	local speed = fighter:GetAttribute("Speed") or 40
	humanoid.WalkSpeed = speed
	
	if data and data.rootJoint then
		local origC0 = data.rootJoint:GetAttribute("OriginalC0")
		if origC0 then
			data.rootJoint.C0 = origC0
		end
	end
	
	chaseData[fighter] = nil
end

function ChaseState.update(fighter, humanoid, rootPart, DEBUG)
	-- Showdown perimeter spectators must never chase
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
		local LeaderShowdownSystem = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("LeaderShowdownSystem"))
		LeaderShowdownSystem.constrainToRing(rootPart)
	end

	local data = chaseData[fighter]
	if not data then return ChaseState end

	-- Prone / Cockroach protection: if tipped flat on ground, immediately recover
	local upY = rootPart.CFrame.UpVector.Y
	if upY < 0.6 and SpatialModule.isGrounded(rootPart) then
		fighter:SetAttribute("KnockbackType", "hard_ground")
		return require(script.Parent:WaitForChild("RecoveryState"))
	end
	
	local target, distance
	local designatedTargetName = fighter:GetAttribute("TargetQuin") or fighter:GetAttribute("CurrentTarget")
	if designatedTargetName and designatedTargetName ~= "" then
		local candidate = findModelByName(designatedTargetName)
		if candidate and candidate:FindFirstChild("HumanoidRootPart") then
			local candHum = candidate:FindFirstChildOfClass("Humanoid")
			if candHum and candHum.Health > 0 then
				target = candidate
				distance = (candidate.HumanoidRootPart.Position - rootPart.Position).Magnitude
			end
		end
	end

	if not target then
		target, distance = TargetingModule.getNearest(rootPart, CombatConfig.ChaseRange)
	end
	
	if not target or not target:FindFirstChild("HumanoidRootPart") then
		return require(script.Parent:WaitForChild("IdleState"))
	end
	
	local targetHRP = target:FindFirstChild("HumanoidRootPart")
	local targetState = target:GetAttribute("CurrentState")

	-- === PURSUIT TERMINATION INVARIANTS (Section 5) ===
	-- 1. Target out of maximum chase range (> 800 studs)
	if distance > (CombatConfig.ChaseRange or 800) then
		return require(script.Parent:WaitForChild("IdleState"))
	end

	-- 2. Tactical decision override: disengage or rescue higher priority (disabled in Showdown)
	local recAction = fighter:GetAttribute("RecommendedAction")
	if not inShowdown and recAction == "Retreat" then
		-- Phase 3: Evaluate safe haven before committing to retreat
		local myTeam = fighter:GetAttribute("Team")
		local enemies = {}
		local allies = {}
		for _, quin in ipairs(CollectionService:GetTagged("Quin")) do
			if quin ~= fighter and quin.Parent and quin:FindFirstChild("HumanoidRootPart") then
				local qTeam = quin:GetAttribute("Team")
				local qHum = quin:FindFirstChildOfClass("Humanoid")
				if qHum and qHum.Health > 0 then
					if qTeam ~= myTeam then
						table.insert(enemies, quin)
					else
						table.insert(allies, quin)
					end
				end
			end
		end

		local retreatResult = SpatialModule.getSafeRetreatDirection(rootPart, enemies, allies, CombatConfig)
		fighter:SetAttribute("RetreatScore", math.round(retreatResult.score * 100) / 100)
		fighter:SetAttribute("IsCornered", retreatResult.isCornered)

		if retreatResult.isCornered then
			local aggression = fighter:GetAttribute("Pers_Aggression") or 0.6
			local meleeRange = (CombatConfig.CombatRange or 8) * 2.0
			if aggression >= (CombatConfig.CorneredCounterThreshold or 0.65) and distance <= meleeRange then
				-- Cornered aggressive fighter with enemy in melee proximity: desperate stand-and-fight instead of futile retreat
				fighter:SetAttribute("DesperateCounter", true)
				return require(script.Parent:WaitForChild("FightState"))
			end
		end

		return require(script.Parent:WaitForChild("RetreatState"))
	elseif recAction == "ProtectAlly" then
		return require(script.Parent:WaitForChild("CirclingState"))
	end

	-- Vertical gap awareness: target is far above → vault toward high ground via LocomotionModule
	local verticalGap = targetHRP.Position.Y - rootPart.Position.Y
	local lastPJ = fighter:GetAttribute("LastPositioningJumpTime") or 0
	if not inShowdown and verticalGap > (CombatConfig.HighGroundJumpReach or 14)
		and (fighter:GetAttribute("Energy") or 100) >= (CombatConfig.ProjectileJumpMinEnergy or 40)
		and (os.clock() - lastPJ) >= (CombatConfig.PositioningJumpCooldown or 10) then
		fighter:SetAttribute("LastPositioningJumpTime", os.clock())
		LocomotionModule.jump(fighter, humanoid, rootPart, verticalGap + 2, 45, "jump")
		return ChaseState
	end

	-- 3. Dangerously low resources: do not pursue into exhaustion
	local energy = fighter:GetAttribute("Energy") or 100
	local hpRatio = humanoid.Health / humanoid.MaxHealth
	if energy < 15 and hpRatio < 0.35 then
		return require(script.Parent:WaitForChild("CirclingState"))
	end
	
	local now = tick()

	-- === 4. Line-of-Sight (LoS) & Last Known Position (LKP) Tracking (Sections 41 & 44) ===
	local hasLoS = SpatialModule.checkLineOfSight(rootPart.Position + Vector3.new(0, 2.5, 0), targetHRP.Position + Vector3.new(0, 2.5, 0), { fighter, target })
	if hasLoS then
		data.targetLKP = targetHRP.Position
		data.lastLoSTime = now
		fighter:SetAttribute("TargetHasLoS", true)
	else
		fighter:SetAttribute("TargetHasLoS", false)
		data.targetLKP = data.targetLKP or targetHRP.Position
	end

	-- === 5. Chase Commitment & Pursuit Abandonment (Sections 9-11) ===
	local persistence = fighter:GetAttribute("Pers_TargetPersistence") or 0.6
	local aggression = fighter:GetAttribute("Pers_Aggression") or 0.6
	local confidence = fighter:GetAttribute("CurrentConfidence") or (fighter:GetAttribute("Pers_Confidence") or 0.6)
	local targetHum = target:FindFirstChildOfClass("Humanoid")
	local targetHpRatio = targetHum and (targetHum.Health / targetHum.MaxHealth) or 1.0

	local distPenalty = math.clamp((distance - 20) / 70, 0, 0.45)
	local chaseDuration = now - (data.enterTime or now)
	local fatiguePenalty = math.clamp(chaseDuration / 14.0, 0, 0.35)
	local weaknessBonus = (1.0 - targetHpRatio) * 0.35
	local persistBonus = (persistence - 0.5) * 0.40
	local confBonus = (confidence - 0.5) * 0.30

	local commitment = math.clamp(0.55 + weaknessBonus + persistBonus + confBonus - distPenalty - fatiguePenalty, 0.05, 1.0)
	fighter:SetAttribute("ChaseCommitment", math.round(commitment * 100) / 100)

	-- Opportunistic Distraction: If another enemy crosses within close melee (<= 13 studs), brawl with them!
	-- "MY QUIN GAVE UP CHASING THAT GUY, BECAUSE HE GOT CAUGHT UP IN ANOTHER FIGHT!"
	if not inShowdown and persistence < 0.85 then
		local myTeam = fighter:GetAttribute("Team") or "None"
		local nearestDistraction = nil
		local nearestDistractionDist = 13.0
		for _, q in ipairs(CollectionService:GetTagged("Quin")) do
			if q ~= fighter and q ~= target and q.Parent and q:FindFirstChild("HumanoidRootPart") then
				local qHum = q:FindFirstChildOfClass("Humanoid")
				if qHum and qHum.Health > 0 and q:GetAttribute("Team") ~= myTeam then
					local d = (q.HumanoidRootPart.Position - rootPart.Position).Magnitude
					if d < nearestDistractionDist then
						nearestDistractionDist = d
						nearestDistraction = q
					end
				end
			end
		end

		if nearestDistraction then
			fighter:SetAttribute("CurrentTarget", nearestDistraction.Name)
			fighter:SetAttribute("TargetQuin", nearestDistraction.Name)
			BattleEventSystem.emit("CHASE_ABANDONED", {
				QuinId = fighter:GetAttribute("QuinId") or fighter.Name,
				Model = fighter,
				TargetName = target.Name,
				Reason = "Distraction",
				NewTarget = nearestDistraction.Name,
			})
			RuntimeTracer.checkpoint(fighter, "Chase abandoned: distracted by " .. nearestDistraction.Name)
			return require(script.Parent:WaitForChild("FightState"))
		end
	end

	-- Pursuit Abandonment: Target reached squad ambush (1v3+) and commitment is broken
	if not inShowdown and commitment < 0.30 then
		local targetTeam = target:GetAttribute("Team")
		local targetAllies = 0
		for _, q in ipairs(CollectionService:GetTagged("Quin")) do
			if q ~= target and q.Parent and q:FindFirstChild("HumanoidRootPart") then
				local qHum = q:FindFirstChildOfClass("Humanoid")
				if qHum and qHum.Health > 0 and q:GetAttribute("Team") == targetTeam then
					if (q.HumanoidRootPart.Position - targetHRP.Position).Magnitude <= 24 then
						targetAllies = targetAllies + 1
					end
				end
			end
		end

		if targetAllies >= 2 then
			BattleEventSystem.emit("CHASE_ABANDONED", {
				QuinId = fighter:GetAttribute("QuinId") or fighter.Name,
				Model = fighter,
				TargetName = target.Name,
				Reason = "AmbushRisk",
				EnemyCount = targetAllies + 1,
			})
			RuntimeTracer.checkpoint(fighter, "Chase abandoned: target reached squad ambush (1v" .. (targetAllies+1) .. ")")
			return require(script.Parent:WaitForChild("CirclingState"))
		end
	end

	local speedMult = workspace:GetAttribute("GameSpeedMultiplier") or 1.0

	-- === 360° Directional Awareness & Rear Threat Interception (Phase 2) ===
	local isUnderRearThreat = fighter:GetAttribute("IsUnderRearThreat")
	local rearDist = fighter:GetAttribute("ClosestRearThreatDist") or 999
	local rearThreatName = fighter:GetAttribute("ClosestRearThreat")
	
	if isUnderRearThreat and rearDist > 0 then
		local maxRearDetect = CombatConfig.RearThreatDetectionRange or 22.0
		local critRearDist = CombatConfig.RearThreatCriticalRange or 10.0
		
		-- 1. Rear Intercept (Pursuer is right behind us in critical striking distance <= 8.5 studs)
		if rearDist <= (critRearDist - 1.5) then
			local rearModel = findModelByName(rearThreatName)
			if rearModel and rearModel:FindFirstChild("HumanoidRootPart") then
				local rHRP = rearModel.HumanoidRootPart
				local snapLook = CFrame.lookAt(rootPart.Position, Vector3.new(rHRP.Position.X, rootPart.Position.Y, rHRP.Position.Z))
				rootPart.CFrame = rootPart.CFrame:Lerp(snapLook, 0.35)
				AnimationModule.playConfig(humanoid, "Awareness.Turn180Pivot", 1.5, Enum.AnimationPriority.Action4, false)
				
				fighter:SetAttribute("CurrentTarget", rearModel.Name)
				fighter:SetAttribute("TargetQuin", rearModel.Name)
				fighter:SetAttribute("LastRearReactionTime", now)
				
				return require(script.Parent:WaitForChild("FightState"))
			end
		-- 2. Over-The-Shoulder Backward Glance (Pursuer detected behind at distance <= 22 studs)
		elseif rearDist <= maxRearDetect then
			local lastGlance = data.lastRearGlanceTime or 0
			if (now - lastGlance) >= (2.8 / speedMult) then
				data.lastRearGlanceTime = now
				fighter:SetAttribute("LastRearGlanceTime", now)
				AnimationModule.playConfig(humanoid, "Awareness.RearThreatGlance", 1.3, Enum.AnimationPriority.Action2, false)
			end
		end
	end

	-- Evaluate Pacing Strategy (WalkThenSprint, AlternatingPace, ConfidentWalk, ContinuousSprint)
	-- When energy drops below FatigueThreshold (25 mana), force walk/circle to regenerate mana
	local shouldWalk = false
	if energy < (CombatConfig.FatigueThreshold or 25) then
		shouldWalk = true
	elseif targetState == "Knockback" or targetState == "Airborne" then
		shouldWalk = true
	else
		local strat = data.pacingStrategy or "ContinuousSprint"
		if strat == "WalkThenSprint" then
			shouldWalk = (distance > 65)
		elseif strat == "ConfidentWalk" then
			shouldWalk = (distance > 45)
		elseif strat == "AlternatingPace" then
			if now >= (data.pacingSwitchTime or 0) then
				data.isPacingWalk = not data.isPacingWalk
				data.pacingSwitchTime = now + ((data.isPacingWalk and math.random(1.5, 2.5) or math.random(3.5, 6)) / speedMult)
			end
			shouldWalk = data.isPacingWalk and (distance > 40)
		end

		-- Pacing Commitment Hysteresis: do not abort sprint pursuit within 2.0s of initiating sprint
		local sprintDwell = (now - (data.sprintStartTime or 0)) < (2.0 / speedMult)
		if sprintDwell and not data.wasWalking and distance > 10 then
			shouldWalk = false
		end
	end

	-- Track walk -> sprint transition for cinematic pacing
	if data.wasWalking and not shouldWalk then
		data.wasWalking = false
		data.sprintStartTime = now
		data.justSwitchedToSprint = true
	elseif shouldWalk then
		data.wasWalking = true
	end

	-- 4. Long Athletic Dash (Requires minimum 25 mana, cooldown 14-20s, never spammed)
	local lastDash = fighter:GetAttribute("LastDashTime") or 0
	local dashPref = fighter:GetAttribute("Pers_DashPreference") or 0.6
	local minDashMana = CombatConfig.DashMinEnergy or 25
	local dashCooldown = math.max(4.0, ((dashPref > 0.7) and 12.0 or 18.0) / speedMult)
	local isDashOnCooldown = (now - lastDash) < dashCooldown
	
	if not isDashOnCooldown and energy >= minDashMana and distance >= 20 and distance <= 70 then
		local shouldCheckDash = now >= (data.nextDashCheckTime or 0)
		if shouldCheckDash then
			data.nextDashCheckTime = now + (((dashPref > 0.7 and math.random(10, 15) or math.random(15, 22))) / speedMult)
			if recAction == "Dash" or math.random() < (dashPref * 0.25) then
				fighter:SetAttribute("CurrentTarget", target.Name)
				fighter:SetAttribute("TargetQuin", target.Name)
				LocomotionModule.dash(fighter, humanoid, rootPart, targetHRP.Position, distance)
				return ChaseState
			end
		end
	end

	-- 5. Dynamic Projectile Jump (Requires 40 mana, cooldown 20-30s, rare impactful tactical commitment)
	local pjEnabled = not inShowdown and (CombatConfig.EnableProjectileJump ~= false) and (fighter:GetAttribute("EnableProjectileJump") ~= false)
	local lastPJ = fighter:GetAttribute("LastProjectileJumpTime") or 0
	local aggression = fighter:GetAttribute("Pers_Aggression") or 0.6
	local mobility = fighter:GetAttribute("Pers_MobilityPreference") or 0.6
	local minPJMana = CombatConfig.ProjectileJumpMinEnergy or 40
	local pjCooldown = math.max(6.0, ((aggression > 0.7) and 20.0 or 30.0) / speedMult)
	local isPJOnCooldown = (now - lastPJ) < pjCooldown

	if pjEnabled and not isPJOnCooldown and energy >= minPJMana and distance >= 40 and distance <= (CombatConfig.ProjectileJumpMaxDistance or 800) then
		local triggerPJ = false
		if now >= (data.nextPJCheckTime or 0) then
			data.nextPJCheckTime = now + (((aggression > 0.7 and math.random(16, 24) or math.random(24, 35))) / speedMult)
			local pjChance = (aggression * 0.12) + (mobility * 0.08)
			if recAction == "ProjectileJump" or math.random() < pjChance then
				triggerPJ = true
			end
		end

		if triggerPJ then
			fighter:SetAttribute("LastProjectileJumpTime", now)
			data.nextPJCheckTime = now + (((aggression > 0.7 and math.random(18, 25) or math.random(25, 38))) / speedMult)

			-- Dynamic selection across all 7 projectile jump styles (Style 1 Parabolic Arc, Style 5 Bezier, etc.)
			local stylePool = { 1, 1, 2, 3, 4, 5, 5, 6, 7 }
			local chosenStyle = stylePool[math.random(1, #stylePool)]
			fighter:SetAttribute("JumpStyle", chosenStyle)
			fighter:SetAttribute("CurrentTarget", target.Name)
			fighter:SetAttribute("TargetQuin", target.Name)

			return require(script.Parent:WaitForChild("ProjectileJumpState"))
		end
	end
	
	-- Mirroring: If they are circling, we circle!
	if targetState == "Circling" and distance < (CombatConfig.CombatRange or 7) * 4.0 then
		if math.random() > 0.8 then
			return require(script.Parent:WaitForChild("CirclingState"))
		end
	end
	
	if distance <= (CombatConfig.CombatRange or 7) * 1.5 then
		if math.random() > 0.7 then
			return require(script.Parent:WaitForChild("CirclingState"))
		else
			return require(script.Parent:WaitForChild("FightState"))
		end
	end
	
	-- === Comprehensive OB & Obstacle Situational Awareness ===
	local obsInfo = SpatialModule.analyzeObstacleAhead(rootPart, targetHRP.Position, 22)
	local obstacleSteer = nil
	if obsInfo.hasObstacle and not inShowdown then
		local isJumpSuppressed = LocomotionModule.isJumpSuppressed(fighter, humanoid)
		if obsInfo.canVault and not isJumpSuppressed and not humanoid.Jump and humanoid:GetState() ~= Enum.HumanoidStateType.Freefall then
			local soundPart = fighter:FindFirstChild("Sounds")
			if soundPart then
				local jumpSound = soundPart:FindFirstChild("jump")
				if jumpSound then
					jumpSound.Volume = 0.08
					jumpSound.PlaybackSpeed = math.random(2.1, 2.4)
					jumpSound:Play()
				end
			end
			fighter:SetAttribute("ObstacleAwareness", obsInfo.isOB and "Parkour Vaulting OB" or "Parkour Vaulting Obstacle")
			JumpHandler.performJump(humanoid, rootPart, obsInfo.height, nil, "vault")
		else
			-- Ground pathfinding fallback: tall barrier or jumps suppressed -> steer along tangent around obstacle
			fighter:SetAttribute("ObstacleAwareness", obsInfo.isOB and "Navigating OB" or "Avoiding Obstacle")
			obstacleSteer = obsInfo.steerDirection
		end
	else
		fighter:SetAttribute("ObstacleAwareness", "Clear")
	end

	-- Slide-under: low-overhead gap ahead -> athletic SlideState
	local slideGap = SpatialModule.detectLowOverheadGap(rootPart, 8)
	local energy = fighter:GetAttribute("Energy") or 100
	local lastSlide = fighter:GetAttribute("LastSlideTime") or 0
	local slideCooldown = CombatConfig.SlideCooldown or 2.5
	local canSlide = (now - lastSlide) >= slideCooldown and energy >= (CombatConfig.SlideMinEnergy or 12)
		and not humanoid.Jump and humanoid:GetState() ~= Enum.HumanoidStateType.Freefall

	if slideGap and canSlide and not inShowdown then
		fighter:SetAttribute("ObstacleAwareness", "Sliding Under Gap")
		LocomotionModule.slide(fighter, humanoid, rootPart)
		return ChaseState
	end

	-- Tactical Gap-Close Slide (Phase 6): high mobility, Charger quirky, or close-range flank
	local quirky = fighter:GetAttribute("Quirky") or "Balanced"
	local qType = fighter:GetAttribute("QuinType") or "TypeA"
	local isHighMobility = (qType == "TypeC" or quirky == "Charger")
	if canSlide and distance >= 18 and distance <= 35 and (data.currentSpeed or 30) >= 24 and not inShowdown then
		local slideChance = isHighMobility and 0.45 or 0.18
		if math.random() < slideChance then
			fighter:SetAttribute("ObstacleAwareness", "Tactical Slide Gap-Close")
			LocomotionModule.slide(fighter, humanoid, rootPart)
			return ChaseState
		end
	end

	-- Dynamic Wall-Running (Phase 6 Parkour): angled vertical wall traversal
	local lastWallRun = fighter:GetAttribute("LastWallRunTime") or 0
	local wallRunCooldown = (quirky == "WallTapper") and 2.5 or (CombatConfig.WallRunCooldown or 5.0)
	local canWallRun = (now - lastWallRun) >= wallRunCooldown and energy >= (CombatConfig.WallRunMinEnergy or 15)
		and (data.currentSpeed or 30) >= (CombatConfig.WallRunMinSpeed or 18)
		and not humanoid.Jump and humanoid:GetState() ~= Enum.HumanoidStateType.Freefall

	if canWallRun and not inShowdown then
		local wallSurface = SpatialModule.detectWallRunSurface(rootPart, CombatConfig.WallRunRayDistance or 5.2)
		if wallSurface then
			fighter:SetAttribute("ObstacleAwareness", "Wall-Running " .. wallSurface.side)
			return require(script.Parent:WaitForChild("WallRunState"))
		end
	end

	-- Elevated Platform Awareness (Target standing on high OB floating platform)
	local elevInfo = SpatialModule.detectElevatedPlatform(rootPart, targetHRP.Position)
	if elevInfo.isElevated and not inShowdown then
		local flatDist = Vector3.new(targetHRP.Position.X - rootPart.Position.X, 0, targetHRP.Position.Z - rootPart.Position.Z).Magnitude
		if flatDist < 25 and not humanoid.Jump and humanoid:GetState() ~= Enum.HumanoidStateType.Freefall then
			fighter:SetAttribute("ObstacleAwareness", "Intercepting Elevated OB")
			JumpHandler.performJump(humanoid, rootPart, math.clamp(elevInfo.heightDiff, 15, 35), nil, "jump")
		end
	end

	-- High-Ground Seeking: climb to a reachable overhead platform when it grants an
	-- advantage — target is above, being pressured/bullied, or critically hurt.
	local overheadPlatform = SpatialModule.findReachableOverheadPlatform(rootPart, 14)
	if overheadPlatform and not inShowdown and not humanoid.Jump and humanoid:GetState() ~= Enum.HumanoidStateType.Freefall then
		local lastHighGround = data.lastHighGroundJump or 0
		local targetAbove = targetHRP.Position.Y > rootPart.Position.Y + 5
		local recAction = fighter:GetAttribute("RecommendedAction")
		local beingBullied = fighter:GetAttribute("BeingBullied")
		local wantHighGround = targetAbove or recAction == "Retreat" or beingBullied or hpRatio < 0.35
		if wantHighGround and (now - lastHighGround) > 6 then
			data.lastHighGroundJump = now
			fighter:SetAttribute("ObstacleAwareness", "Climbing High Ground")
			local climbHeight = math.clamp(overheadPlatform.topY - rootPart.Position.Y, 5, 14)
			JumpHandler.performJump(humanoid, rootPart, climbHeight, 22, "vault")
		end
	end

	-- Positioning Projectile-Jump: launch up to a HIGH platform (beyond normal jump reach)
	local highPlatform = SpatialModule.findReachableOverheadPlatform(rootPart, CombatConfig.PositioningJumpMaxReach or 80, 15)
	if highPlatform and not humanoid.Jump and humanoid:GetState() ~= Enum.HumanoidStateType.Freefall then
		local lastPosJump = fighter:GetAttribute("LastPositioningJumpTime") or 0
		local energy = fighter:GetAttribute("Energy") or 100
		local recAction = fighter:GetAttribute("RecommendedAction")
		local beingBullied = fighter:GetAttribute("BeingBullied")
		local wantPosition = (recAction == "Retreat" or beingBullied or hpRatio < 0.35)
		if wantPosition and energy >= (CombatConfig.ProjectileJumpMinEnergy or 40) and (now - lastPosJump) > (CombatConfig.PositioningJumpCooldown or 10) then
			fighter:SetAttribute("LastPositioningJumpTime", now)
			fighter:SetAttribute("ObstacleAwareness", "Positioning Jump to High Ground")
			local topPos = highPlatform.position + Vector3.new(0, 5, 0)
			local jumpHeight = math.max(8, (topPos.Y - rootPart.Position.Y) + 2)
			LocomotionModule.jump(fighter, humanoid, rootPart, jumpHeight, 45, "jump")
			return ChaseState
		end
	end
	
	-- Self Platform Dismount (Phase 4): if THIS Quin is perched on an elevated OB platform,
	-- walk toward the nearest ledge biased toward the target rather than milling around.
	local platformDismountDir = nil
	local isOnPlatform, _ = SpatialModule.isOnElevatedPlatform(rootPart, CombatConfig.ElevatedPlatformThreshold or 6.0)
	if isOnPlatform then
		data.wasOnPlatform = true
		platformDismountDir = SpatialModule.getPlatformDismountDirection(rootPart, targetHRP.Position)
		fighter:SetAttribute("ObstacleAwareness", "Dismounting Elevated Platform")
	end

	-- Vertical Obstacle Unstick (Phase 4): detect zero-progress against a vertical face
	-- and force a vertical hop instead of grinding endlessly into the wall.
	data.stuckCheckPos = data.stuckCheckPos or rootPart.Position
	data.stuckCheckTime = data.stuckCheckTime or now
	if (now - data.stuckCheckTime) >= 1.2 then
		local progress = (rootPart.Position - data.stuckCheckPos).Magnitude
		if progress < (CombatConfig.VerticalStuckThreshold or 0.8) and distance > 15 and not humanoid.Jump and humanoid:GetState() ~= Enum.HumanoidStateType.Freefall then
			fighter:SetAttribute("ObstacleAwareness", "Unsticking Vertical Barrier")
			JumpHandler.performJump(humanoid, rootPart, CombatConfig.VerticalUnstickJumpHeight or 9.0, 10, "jump")
		end
		data.stuckCheckPos = rootPart.Position
		data.stuckCheckTime = now
	end

	-- Jumps are now INTENTIONAL ONLY: they fire for a genuine reason (obstacle vault,
	-- elevated-target intercept, vertical unstick) rather than random athletic hops.
	-- This keeps locomotion grounded and makes every jump read as deliberate.
	
	local speed = fighter:GetAttribute("Speed") or 40
	local targetSpeed = (shouldWalk and 16 or speed) * speedMult

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
	elseif data.isAccelerating and currentSpeed < (targetSpeed * 0.55) then
		if not data.pushOffAnim then
			local mobility = fighter:GetAttribute("Pers_MobilityPreference") or 0.6
			data.pushOffAnim = (mobility > 0.55 or math.random() > 0.5) and "Movement.IdleToRun1" or "Movement.IdleToRun2"
		end
		desiredAnim = data.pushOffAnim
	else
		desiredAnim = "Movement.Run"
		data.pushOffAnim = nil
	end

	if data.currentAnim ~= desiredAnim then
		data.currentAnim = desiredAnim
		AnimationModule.playConfig(humanoid, data.currentAnim)
	else
		local isFreefall = (humanoid:GetState() == Enum.HumanoidStateType.Freefall)
		if not isFreefall and not AnimationModule.isPlaying(humanoid, data.currentAnim) then
			-- Locomotion track was interrupted (hit reaction / reaction overlay);
			-- re-assert it so the Quin does not glide like a statue while still translating.
			AnimationModule.playConfig(humanoid, data.currentAnim)
		end
	end

	-- Dynamic Foot-Sync: Scale playback speed proportional to actual ground velocity
	-- Stride reference: WalkConfident calibrated at ~16 studs/s, Run calibrated at ~38 studs/s
	if (desiredAnim == "Movement.Run" or desiredAnim == "Movement.WalkConfident") and AnimationModule.isPlaying(humanoid, desiredAnim) then
		local strideBase = (desiredAnim == "Movement.WalkConfident") and 16.0 or 38.0
		local ratio = math.clamp(currentSpeed / strideBase, 0.65, 1.45)
		local baseCfgSpeed = (desiredAnim == "Movement.Run") and 1.15 or 1.00
		AnimationModule.adjustSpeed(humanoid, desiredAnim, baseCfgSpeed * ratio)
	end
	
	-- Energy drain and recovery scaled with speedMult
	if not shouldWalk then
		local drain = (CombatConfig.EnergyDrain_Sprint or 1) * 0.1 * speedMult
		fighter:SetAttribute("Energy", math.max(0, energy - drain))
	else
		local recovery = (CombatConfig.EnergyRecovery_Walk or 15) * 0.1 * speedMult
		fighter:SetAttribute("Energy", math.min(CombatConfig.MaxEnergy or 100, energy + recovery))
	end
	
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

			local leadRay = Workspace:Raycast(rootPart.Position + Vector3.new(0, 1.5, 0), (testIntercept - rootPart.Position), leadRayParams)
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
	local quirky = fighter:GetAttribute("Quirky") or "Balanced"
	local sameTargetTeammates = {}
	for _, q in ipairs(CollectionService:GetTagged("Quin")) do
		if q ~= fighter and q.Parent and q:FindFirstChild("HumanoidRootPart") then
			if q:GetAttribute("Team") == fighter:GetAttribute("Team") and q:GetAttribute("TargetQuin") == target.Name then
				table.insert(sameTargetTeammates, q)
			end
		end
	end

	if #sameTargetTeammates > 0 and hasLoS then
		local isTandemPair = false
		for _, mate in ipairs(sameTargetTeammates) do
			if (mate:GetAttribute("OwnerId") == myOwner and myOwner ~= "SERVER") or (quirky == "Follower" or quirky == "Wingman") then
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

	local nearEdge, awayDir = SpatialModule.isNearArenaEdge(rootPart, 6)
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

	-- 1. High-Speed 180 Direction Reversal (Mirrored Left / Right)
	local isFreefallState = (humanoid:GetState() == Enum.HumanoidStateType.Freefall)
	local canTurn180 = not inShowdown 
		and not shouldWalk 
		and currentSpeed >= 12
		and (now >= (data.turnActiveUntil or 0))
		and (now - (data.lastTurnTime or 0) >= 1.6)
		and not humanoid.Jump
		and not isFreefallState
		and (dotToTarget < -0.65) -- Sharp reversal: target is in rear hemisphere (> 130 deg)

	if canTurn180 then
		local turnAnim = (localDir.X < 0) and "Movement.RunTurn180Left" or "Movement.RunTurn180Right"
		data.turnAnim = turnAnim
		data.turnActiveUntil = now + 0.45
		data.lastTurnTime = now
		data.turnTargetHeading = flatTargetDir
		data.currentAnim = turnAnim
		
		AnimationModule.playConfig(humanoid, turnAnim, 1.35, Enum.AnimationPriority.Action, false)
	end

	-- 2. Athletic 90-Degree Plant Cut (Mirrored Left / Right)
	local canTurn90 = not inShowdown
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
	local canArcRun = not inShowdown
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
		
		AnimationModule.playConfig(humanoid, arcAnim, 1.20, Enum.AnimationPriority.Movement, false)
	end

	-- Authoritative single-driver steering & speed modulation
	LocomotionModule.steer(fighter, humanoid, rootPart, arcTarget, targetSpeed, dt)
	
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
			local leanAngle
			if data.isAccelerating and currentSpeed < targetSpeed * 0.85 then
				-- Heavy forward torso tilt on push-off acceleration (~20 deg)
				leanAngle = math.rad(-20)
			elseif data.isDecelerating and currentSpeed > targetSpeed + 4 then
				-- Kinetic braking drag lean back (~8 deg)
				leanAngle = math.rad(8)
			elseif shouldWalk then
				leanAngle = math.rad(-5)
			else
				leanAngle = math.rad(-14)
			end

			-- Centripetal roll banking into turns
			local maxRollDeg = CombatConfig.TorsoBankingMaxRoll or 12.0
			local angVelY = rootPart.AssemblyAngularVelocity.Y
			local strideBase = CombatConfig.RunStrideBase or 38.0
			local speedRatio = math.clamp(currentSpeed / strideBase, 0.2, 1.4)
			local targetBankRoll = -math.clamp(angVelY * speedRatio * math.rad(maxRollDeg * 0.12), -math.rad(maxRollDeg), math.rad(maxRollDeg))

			if data.arcAnim then
				local isLeftArc = string.find(data.arcAnim, "Left") ~= nil
				targetBankRoll = isLeftArc and math.rad(maxRollDeg) or -math.rad(maxRollDeg)
			end

			data.currentBankRoll = (data.currentBankRoll or 0) + (targetBankRoll - (data.currentBankRoll or 0)) * 0.15
			local rollAngle = data.currentBankRoll

			rootJoint.C0 = rootJoint.C0:Lerp(origC0 * CFrame.Angles(leanAngle, 0, rollAngle), 0.14)
		end
	end
	
	-- Fall & landing animation
	local isFreefall = (humanoid:GetState() == Enum.HumanoidStateType.Freefall)
	local isGrounded = SpatialModule.isGrounded(rootPart)
	if rootPart.AssemblyLinearVelocity.Y < -5 and isFreefall and not isGrounded then
		if data.wasOnPlatform then
			data.isDismountFalling = true
		end
		if not AnimationModule.isPlaying(humanoid, "Movement.Fall") then
			AnimationModule.playConfig(humanoid, "Movement.Fall", 1.0, Enum.AnimationPriority.Action)
		end
	else
		if AnimationModule.isPlaying(humanoid, "Movement.Fall") then
			AnimationModule.stopConfig(humanoid, "Movement.Fall")
			if data.isDismountFalling then
				data.isDismountFalling = false
				data.wasOnPlatform = false
				AnimationModule.playConfig(humanoid, "Parkour.LedgeDropLanding", 1.4, Enum.AnimationPriority.Action3, false)
			end
			if data.currentAnim then
				AnimationModule.playConfig(humanoid, data.currentAnim)
			end
		end
		if isGrounded and math.abs(rootPart.AssemblyLinearVelocity.Y) < 3 then
			if AnimationModule.isPlaying(humanoid, "Parkour.VaultObstacle") then
				AnimationModule.stopConfig(humanoid, "Parkour.VaultObstacle")
			end
		end
	end
	
	return ChaseState
end

return ChaseState
