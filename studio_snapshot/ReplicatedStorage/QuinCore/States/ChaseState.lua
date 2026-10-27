--// ChaseState.lua
-- Intelligent pathfinding chase with obstacle jumping and smooth lean
-- Single Source of Truth: ReplicatedStorage.QuinCore.AnimationConfig

local DebugDraw = require(game:GetService("ReplicatedStorage"):WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("DebugDraw"))
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")
local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")
local QuinRoster = require(game:GetService("ReplicatedStorage"):WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("QuinRoster")) -- (GetTagged("Quin") once a frame, shared)

local TargetingModule = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("TargetingModule"))
local AnimationModule = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("AnimationModule"))
local CombatConfig = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("CombatConfig"))
local DebugReadouts = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("DebugReadouts")) -- (debug-only attributes)
local AnimationConfig = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("AnimationConfig"))
local SpatialModule = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("SpatialModule"))
local Cognition = require(game:GetService("ReplicatedStorage"):WaitForChild("QuinCore"):WaitForChild("Cognition"))
local PlatformCatalogue = require(game:GetService("ReplicatedStorage"):WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("PlatformCatalogue"))
local TraversalModule = require(game:GetService("ReplicatedStorage"):WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("TraversalModule"))
local AirInterceptModule = require(game:GetService("ReplicatedStorage"):WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("AirInterceptModule"))
local KnockbackModule = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("KnockbackModule"))
local BattleEventSystem = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("BattleEventSystem"))
local LocomotionModule = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("LocomotionModule"))
local GaitModule = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("GaitModule"))
local RuntimeTracer = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("RuntimeTracer"))
local NavigationModule = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("NavigationModule"))
local Reach = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("Reach"))
local Pace = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("Pace"))
local Pers = require(game:GetService("ReplicatedStorage"):WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("Pers")) -- (personality reads + defaults, one place)
local States = require(game:GetService("ReplicatedStorage"):WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("States")) -- (every state by name)
-- Its parts (child modules): climbing to a target up high, the obstacles on the way, how it runs
local Climb = require(script:WaitForChild("Climb"))
local Obstacles = require(script:WaitForChild("Obstacles"))
local Steer = require(script:WaitForChild("Steer"))

local function findModelByName(name)
	local m = QuinRoster.byName(name)
	return m and m:FindFirstChild("HumanoidRootPart") and m or nil
end

local ChaseState = { name = "Chase" }

-- JumpHandler routed through authoritative LocomotionModule (Rule 4 & Rule 6)
local JumpHandler = LocomotionModule
local chaseData = setmetatable({}, { __mode = "k" })

local function selectPacingStrategy(fighter)
	local mobility = Pers.get(fighter, "MobilityPreference")
	local aggression = Pers.get(fighter, "Aggression")
	local dashPref = Pers.get(fighter, "DashPreference")
	local confidence = Pers.get(fighter, "Confidence")
	
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
	local mobility = Pers.get(fighter, "MobilityPreference")
	local now = tick()
	
	local maxSpeed = fighter:GetAttribute("Speed") or 40
	local initialSpeed = math.clamp(humanoid.WalkSpeed, 0, maxSpeed)
	humanoid.WalkSpeed = initialSpeed
	humanoid.AutoRotate = true

	local initialAnim = "Movement.Run"
	local pushOffAnim = nil
	local planarVel = rootPart and rootPart.AssemblyLinearVelocity or Vector3.zero
	local actualPlanarSpeed = Vector3.new(planarVel.X, 0, planarVel.Z).Magnitude

	if strategy == "ConfidentWalk" or strategy == "WalkThenSprint" then
		initialAnim = "Movement.WalkConfident"
	elseif initialSpeed < 4 and actualPlanarSpeed < 4 and CombatConfig.Chase_PushOffOverlay == true then
		pushOffAnim = (mobility > 0.55 or math.random() > 0.5) and "Movement.IdleToRun1" or "Movement.IdleToRun2"
		initialAnim = pushOffAnim
	end

	chaseData[fighter] = {
		lastStepTime = 0,
		lastUpdateTime = now,
		lastSlideCheckTime = now,
		currentSpeed = initialSpeed,
		isAccelerating = true,
		isDecelerating = false,
		currentAnim = pushOffAnim or "Gait",
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
		nextPJCheckTime = now + (CombatConfig.ProjectileJump_ChaseFirstCheck or 2.0) * (0.7 + math.random() * 0.6),
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
		TargetName = fighter:GetAttribute("CurrentTarget") or "Unknown",
	})
	
	if pushOffAnim then
		AnimationModule.playConfig(humanoid, pushOffAnim)
	else
		-- Walk / run come from the shared gait. Playing the Run or Walk clip directly here
		-- stopped the other blend clips and restarted the cycle on every entry into Chase.
		GaitModule.update(humanoid, rootPart, 1 / 60)
	end
end

function ChaseState.exit(fighter, humanoid, rootPart)
	local data = chaseData[fighter]
	if data then
		if data.currentAnim == "Gait" then
			-- The gait is left running: the next state keeps driving it (Fight, Retreat) or
			-- replaces it (Circling strafe), and the ground contract releases it if nobody does.
			-- Stopping it here made the legs drop out and restart on every Chase -> Fight.
		elseif data.currentAnim then
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
	
	-- WalkSpeed is left as it is: the next state accelerates or brakes from the current pace.
	-- Forcing it to full speed here made a walking Quin lurch to a sprint on the way out.

	chaseData[fighter] = nil
end

function ChaseState.update(fighter, humanoid, rootPart, DEBUG)
	-- Respect-custom spectators must never chase
	local showdownRole = fighter:GetAttribute("RespectRole")
	if require(game:GetService("ReplicatedStorage").QuinCore.Modules.SocialSystem).standsDown(fighter) then
		return States.Idle -- (spectators stand and watch)
	end
	-- A place it decided to walk to (a leader's regroup, a respect custom): it goes there first
	if require(game:GetService("ReplicatedStorage").QuinCore.Modules.SocialSystem).followMoveIntent(fighter, humanoid, rootPart, 0.1) then
		return ChaseState
	end

	-- Respect-custom duel: kept on the ceremony space, no jumping away
	local inShowdown = (showdownRole == "Duelist") -- (a respect-custom duel)
	if inShowdown then
		humanoid.UseJumpPower = true
		humanoid.JumpPower = 0
		humanoid.JumpHeight = 0
		require(game:GetService("ReplicatedStorage").QuinCore.Modules.SocialSystem).constrainToCeremony(rootPart)
	end

	local data = chaseData[fighter]
	if not data then return ChaseState end

	-- Prone / Cockroach protection: if tipped flat on ground, immediately recover
	local upY = rootPart.CFrame.UpVector.Y
	if upY < 0.6 and SpatialModule.isGrounded(rootPart) then
		fighter:SetAttribute("KnockbackType", "hard_ground")
		return States.Recovery
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
		return States.Idle
	end
	
	local targetHRP = target:FindFirstChild("HumanoidRootPart")
	local targetState = target:GetAttribute("CurrentState")

	-- In the air (a jump, the kick off a wall): a dash may get it somewhere (Modules/AirDash)
	if require(script.Parent.Parent:WaitForChild("Modules"):WaitForChild("AirDash")).consider(fighter, humanoid, rootPart, target) then
		return ChaseState
	end

	-- A slide in progress owns the body until it is through. (Handing over to Fight at striking
	-- range stopped the slide clip, which ends the glide: a tackle was cut off ~10 studs short.)
	if fighter:GetAttribute("LocomotionAction") == "Slide" then
		return ChaseState
	end

	-- Respect-custom standoff: once within the circling gap it circles, it does not close in
	local standoffGap = fighter:GetAttribute("SocialStandoff")
	if standoffGap and distance <= standoffGap + 12 then
		return States.Circling
	end

	-- === PURSUIT TERMINATION INVARIANTS (Section 5) ===
	-- 1. Target out of maximum chase range (> 800 studs)
	if distance > (CombatConfig.ChaseRange or 800) then
		return States.Idle
	end

	-- 2. Tactical decision override: disengage or rescue higher priority (disabled in Showdown)
	local recAction = fighter:GetAttribute("RecommendedAction")
	if not inShowdown and recAction == "Retreat" then
		-- Phase 3: Evaluate safe haven before committing to retreat
		local myTeam = fighter:GetAttribute("Team")
		local enemies = {}
		local allies = {}
		for _, quin in ipairs(QuinRoster.all()) do
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
		DebugReadouts.set(fighter, "RetreatScore", math.round(retreatResult.score * 100) / 100)
		fighter:SetAttribute("IsCornered", retreatResult.isCornered)

		if retreatResult.isCornered then
			local aggression = Pers.get(fighter, "Aggression")
			local meleeRange = (CombatConfig.CombatRange or 8.2) * 2.0
			if aggression >= (CombatConfig.CorneredCounterThreshold or 0.65) and distance <= meleeRange then
				-- Cornered aggressive fighter with enemy in melee proximity: desperate stand-and-fight instead of futile retreat
				fighter:SetAttribute("DesperateCounter", true)
				return States.Fight
			end
		end

		return States.Retreat
	elseif recAction == "ProtectAlly" then
		return States.Circling
	end

	-- A target up high: met in the air, climbed to, jumped on to (ChaseState/Climb)
	local climbed = Climb.update(fighter, humanoid, rootPart, data, target, targetHRP, inShowdown)
	if climbed then
		return climbed
	end

	-- 3. Dangerously low resources: do not pursue into exhaustion
	local energy = fighter:GetAttribute("Energy") or 100
	local hpRatio = humanoid.Health / humanoid.MaxHealth
	if energy < 15 and hpRatio < 0.35 then
		return States.Circling
	end
	
	local now = tick()

	-- === 4. Line-of-Sight (LoS) & Last Known Position (LKP) Tracking (Sections 41 & 44) ===
	local myEyePos = SpatialModule.getEyePosition(rootPart)
	local tgtEyePos = SpatialModule.getEyePosition(targetHRP)
	local hasLoS = SpatialModule.checkLineOfSight(myEyePos, tgtEyePos, { fighter, target })
	if hasLoS then
		data.targetLKP = targetHRP.Position
		data.lastLoSTime = now
		data.surveyingAtLKP = nil
		data.searchLeg = nil
		fighter:SetAttribute("LastSeenTargetPosition", targetHRP.Position)
		-- (TimeLastSeen is no longer an attribute: nothing read it, ~200 writes a second)
	else
		local savedLKP = fighter:GetAttribute("LastSeenTargetPosition")
		data.targetLKP = data.targetLKP or savedLKP or targetHRP.Position

		-- The hunt goes on from memory: head for where the target is believed to be, and from
		-- there search on along the way it was last moving, for as long as the track is worth
		-- following. A persistent hunter follows a fainter trail.
		local contact = Cognition.contactFor(fighter, target)
		local trailWorth = contact ~= nil and not contact.visible
			and contact.confidence >= (CombatConfig.Chase_TrailGiveUpConfidence or 0.6) - (Pers.get(fighter, "TargetPersistence")) * 0.5
		if trailWorth and not data.searchLeg then
			data.targetLKP = contact.position
		end

		-- Check if arrived at LKP without sighting target (target escaped behind obstacle)
		local distToLKP = (data.targetLKP - rootPart.Position).Magnitude
		if distToLKP <= 7.0 and trailWorth then
			local heading = Vector3.new(contact.velocity.X, 0, contact.velocity.Z)
			if heading.Magnitude < 1 then
				heading = Vector3.new(data.targetLKP.X - rootPart.Position.X, 0, data.targetLKP.Z - rootPart.Position.Z)
			end
			if heading.Magnitude > 0.1 then
				data.searchLeg = (data.searchLeg or 0) + 1
				local arena = SpatialModule.getArenaBounds()
				local nextPoint = data.targetLKP + heading.Unit * (CombatConfig.Chase_SearchLegDistance or 45)
				data.targetLKP = Vector3.new(
					math.clamp(nextPoint.X, arena.center.X - arena.halfX + 20, arena.center.X + arena.halfX - 20),
					nextPoint.Y,
					math.clamp(nextPoint.Z, arena.center.Z - arena.halfZ + 20, arena.center.Z + arena.halfZ - 20))
				fighter:SetAttribute("ObstacleAwareness", "Searching for " .. target.Name)
			end
		elseif distToLKP <= 7.0 then
			if not data.surveyingAtLKP then
				data.surveyingAtLKP = now
				-- Full-body clip: only once the body has slowed (it froze the legs of a Quin still
				-- arriving at the spot); otherwise the head looks around
				local v = rootPart.AssemblyLinearVelocity
				if Vector3.new(v.X, 0, v.Z).Magnitude < 4 then
					AnimationModule.playConfig(humanoid, "Idles.SurveyIdle", 1.2, Enum.AnimationPriority.Action2, false)
				else
					fighter:SetAttribute("GlanceBackUntil", workspace:GetServerTimeNow() + 0.8)
				end
			elseif (now - data.surveyingAtLKP) >= 0.9 then
				data.surveyingAtLKP = nil
				data.targetLKP = nil
				TargetingModule.clearTarget(fighter)
				return States.Idle
			end
		end
	end

	-- === 5. Chase Commitment & Pursuit Abandonment (Sections 9-11) ===
	local persistence = Pers.get(fighter, "TargetPersistence")
	local aggression = Pers.get(fighter, "Aggression")
	local confidence = fighter:GetAttribute("CurrentConfidence") or (Pers.get(fighter, "Confidence"))
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
	-- A hunter still committed to its target only turns on a passer-by that is itself after it.
	local looselyCommitted = commitment < (CombatConfig.Chase_DistractionCommitment or 0.6)
	if not inShowdown and persistence < 0.85 then
		local myTeam = fighter:GetAttribute("Team") or "None"
		local nearestDistraction = nil
		local nearestDistractionDist = 13.0
		for _, q in ipairs(QuinRoster.all()) do
			if q ~= fighter and q ~= target and q.Parent and q:FindFirstChild("HumanoidRootPart") then
				local qHum = q:FindFirstChildOfClass("Humanoid")
				if qHum and qHum.Health > 0 and q:GetAttribute("Team") ~= myTeam then
					local d = (q.HumanoidRootPart.Position - rootPart.Position).Magnitude
					local afterMe = (q:GetAttribute("CurrentTarget") or q:GetAttribute("TargetQuin")) == fighter.Name
					if d < nearestDistractionDist and (looselyCommitted or afterMe) then
						nearestDistractionDist = d
						nearestDistraction = q
					end
				end
			end
		end

		if nearestDistraction and TargetingModule.setTarget(fighter, nearestDistraction, "Distraction") then
			BattleEventSystem.emit("CHASE_ABANDONED", {
				QuinId = fighter:GetAttribute("QuinId") or fighter.Name,
				Model = fighter,
				TargetName = target.Name,
				Reason = "Distraction",
				NewTarget = nearestDistraction.Name,
			})
			RuntimeTracer.checkpoint(fighter, "Chase abandoned: distracted by " .. nearestDistraction.Name)
			return States.Fight
		end
	end

	-- Pursuit Abandonment: Target reached squad ambush (1v3+) and commitment is broken
	-- Only applies when actually closing in (distance <= 45 studs) and local allies are outnumbered!
	if not inShowdown and commitment < 0.30 and distance <= 45.0 then
		local targetTeam = target:GetAttribute("Team")
		local myTeam = fighter:GetAttribute("Team")
		local targetAllies = 0
		local myAllies = 0
		for _, q in ipairs(QuinRoster.all()) do
			if q.Parent and q:FindFirstChild("HumanoidRootPart") then
				local qHum = q:FindFirstChildOfClass("Humanoid")
				if qHum and qHum.Health > 0 then
					local qDist = (q.HumanoidRootPart.Position - targetHRP.Position).Magnitude
					if qDist <= 24 then
						if q:GetAttribute("Team") == targetTeam and q ~= target then
							targetAllies = targetAllies + 1
						elseif q:GetAttribute("Team") == myTeam and q ~= fighter then
							myAllies = myAllies + 1
						end
					end
				end
			end
		end

		if targetAllies >= 2 and myAllies < targetAllies then
			BattleEventSystem.emit("CHASE_ABANDONED", {
				QuinId = fighter:GetAttribute("QuinId") or fighter.Name,
				Model = fighter,
				TargetName = target.Name,
				Reason = "AmbushRisk",
				EnemyCount = targetAllies + 1,
			})
			RuntimeTracer.checkpoint(fighter, "Chase abandoned: target reached squad ambush (1v" .. (targetAllies+1) .. ")")
			return States.Circling
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
				-- FightState's facing gyro turns the body onto the new target. The pivot clip rotates
				-- the hips 177 degrees by itself: stacked on a root that is also turning it over-spins
				-- the mesh and snaps back when it ends, so it stays off unless explicitly enabled.
				if CombatConfig.Turn180PivotClipEnabled == true then
					AnimationModule.playConfig(humanoid, "Awareness.Turn180Pivot", 1.5, Enum.AnimationPriority.Action4, false)
				end
				
				TargetingModule.setTarget(fighter, rearModel, "RearThreat")
				fighter:SetAttribute("LastRearReactionTime", now)
				
				return States.Fight
			end
		-- 2. Over-The-Shoulder Backward Glance (Pursuer detected behind at distance <= 22 studs)
		elseif rearDist <= maxRearDetect then
			local lastGlance = data.lastRearGlanceTime or 0
			if (now - lastGlance) >= (2.8 / speedMult) then
				data.lastRearGlanceTime = now
				fighter:SetAttribute("LastRearGlanceTime", now)
				-- The glance clip is full-body: played at a run it froze the legs mid-stride.
				-- On the move only the head and shoulders look back (LookController).
				local v = rootPart.AssemblyLinearVelocity
				if Vector3.new(v.X, 0, v.Z).Magnitude > 6 then
					fighter:SetAttribute("GlanceBackUntil", workspace:GetServerTimeNow() + 0.8)
				else
					AnimationModule.playConfig(humanoid, "Awareness.RearThreatGlance", 1.3, Enum.AnimationPriority.Action2, false)
				end
			end
		end
	end

	-- Evaluate Pacing Strategy (WalkThenSprint, AlternatingPace, ConfidentWalk, ContinuousSprint)
	-- When energy drops below FatigueThreshold (25 mana), force walk/circle to regenerate mana
	-- paceReason records why this Quin is walking (PaceReason attribute, for the HUD):
	-- out of breath, strolling up to an opponent it has put on the ground, or stalking from range.
	local shouldWalk = false
	local paceReason = "Sprint"
	if energy < (CombatConfig.FatigueThreshold or 25) then
		shouldWalk = true
		paceReason = "Fatigue"
	elseif targetState == "Knockback" or targetState == "Airborne" or targetState == "Recovery" then
		shouldWalk = true
		paceReason = "TargetDown"
	else
		paceReason = "Stalk:" .. (data.pacingStrategy or "ContinuousSprint")
		local strat = data.pacingStrategy or "ContinuousSprint"
		if strat == "WalkThenSprint" then
			shouldWalk = (distance > 65)
		elseif strat == "ConfidentWalk" then
			shouldWalk = (distance > 45)
		elseif strat == "AlternatingPace" and not Pace.enabled() then
			-- (a timer that flipped walk and sprint every few seconds: with Pace on, the
			-- urgency of the chase decides the gear instead)
			if now >= (data.pacingSwitchTime or 0) then
				data.isPacingWalk = not data.isPacingWalk
				data.pacingSwitchTime = now + ((data.isPacingWalk and math.random(1.5, 2.5) or math.random(3.5, 6)) / speedMult)
			end
			shouldWalk = data.isPacingWalk and (distance > 40)
		end

		-- A stalking walk is a short read of the target, not the whole approach: from across the
		-- arena WalkThenSprint walked until 65 studs out (up to 18 s at walking pace, staring at
		-- the target the whole way). After Chase_StalkWalkMaxTime the Quin commits and runs.
		if shouldWalk and (strat == "ConfidentWalk" or strat == "WalkThenSprint") then
			data.stalkWalkSince = data.stalkWalkSince or now
			if now - data.stalkWalkSince > (CombatConfig.Chase_StalkWalkMaxTime or 2.5) / speedMult then
				data.pacingStrategy = "ContinuousSprint"
				shouldWalk = false
			end
		end

		-- Pacing Commitment Hysteresis: do not abort sprint pursuit within 2.0s of initiating sprint
		local sprintDwell = (now - (data.sprintStartTime or 0)) < (2.0 / speedMult)
		if sprintDwell and not data.wasWalking and distance > 10 then
			shouldWalk = false
		end
	end

	-- After a soft landing it walks on for a moment (unless someone is on it)
	if os.clock() < (fighter:GetAttribute("CasualUntil") or 0) and distance > 14
		and fighter:GetAttribute("IsUnderRearThreat") ~= true then
		shouldWalk = true
		paceReason = "CasualDrop"
	end

	-- Track walk -> sprint transition for cinematic pacing
	if data.wasWalking and not shouldWalk then
		data.wasWalking = false
		data.sprintStartTime = now
		data.justSwitchedToSprint = true
	elseif shouldWalk then
		data.wasWalking = true
	end
	fighter:SetAttribute("PaceReason", shouldWalk and paceReason or "Sprint")

	-- 4. Long Athletic Dash (Requires minimum 25 mana, cooldown 14-20s, never spammed)
	local lastDash = fighter:GetAttribute("LastDashTime") or 0
	local dashPref = Pers.get(fighter, "DashPreference")
	local minDashMana = CombatConfig.DashMinEnergy or 25
	local dashCooldown = math.max(4.0, ((dashPref > 0.7) and 12.0 or 18.0) / speedMult)
	local isDashOnCooldown = (now - lastDash) < dashCooldown
	
	if not isDashOnCooldown and energy >= minDashMana and distance >= 20 and distance <= 70 then
		local shouldCheckDash = now >= (data.nextDashCheckTime or 0)
		if shouldCheckDash then
			data.nextDashCheckTime = now + (((dashPref > 0.7 and math.random(10, 15) or math.random(15, 22))) / speedMult)
			if recAction == "Dash" or math.random() < (dashPref * 0.25) then
				TargetingModule.setTarget(fighter, target, "State")
				fighter:SetAttribute("JumpWhy", "dash to close the gap") -- (JumpLog, team step 5)
				LocomotionModule.dash(fighter, humanoid, rootPart, targetHRP.Position, distance)
				return ChaseState
			end
		end
	end

	-- 5. Projectile jump: the way to close on a distant target (energy cost, cooldown, and a
	-- chance per check that grows with aggression and mobility; CombatConfig.ProjectileJump_*)
	local pjEnabled = not inShowdown and (CombatConfig.EnableProjectileJump ~= false) and (fighter:GetAttribute("EnableProjectileJump") ~= false)
	local lastPJ = fighter:GetAttribute("LastProjectileJumpTime") or 0
	local aggression = Pers.get(fighter, "Aggression")
	local mobility = Pers.get(fighter, "MobilityPreference")
	local minPJMana = CombatConfig.ProjectileJumpMinEnergy or 40
	local pjCooldown = math.max(6.0, (CombatConfig.ProjectileJump_Cooldown or 14.0) * ((aggression > 0.7) and 0.75 or 1.0) / speedMult)
	local isPJOnCooldown = (now - lastPJ) < pjCooldown

	if pjEnabled and not isPJOnCooldown and energy >= minPJMana and distance >= 40 and distance <= (CombatConfig.ProjectileJumpMaxDistance or 800) then
		local triggerPJ = false
		if now >= (data.nextPJCheckTime or 0) then
			data.nextPJCheckTime = now + (CombatConfig.ProjectileJump_ChaseCheckInterval or 4.0) * (0.7 + math.random() * 0.6) / speedMult
			local pjChance = aggression * (CombatConfig.ProjectileJump_ChanceAggression or 0.30) + mobility * (CombatConfig.ProjectileJump_ChanceMobility or 0.20)
			if recAction == "ProjectileJump" or math.random() < pjChance then
				triggerPJ = true
			end
		end

		if triggerPJ then
			fighter:SetAttribute("LastProjectileJumpTime", now)
			data.nextPJCheckTime = now + pjCooldown

			-- Dynamic selection across all 7 projectile jump styles (Style 1 Parabolic Arc, Style 5 Bezier, etc.)
			local stylePool = { 1, 1, 2, 3, 4, 5, 5, 6, 7 }
			local chosenStyle = stylePool[math.random(1, #stylePool)]
			fighter:SetAttribute("JumpStyle", chosenStyle)
			TargetingModule.setTarget(fighter, target, "State")

			fighter:SetAttribute("JumpWhy", "rocket to close a far gap") -- (JumpLog, team step 5)
			return States.ProjectileJump
		end
	end
	
	-- Close only counts when it can be reached: a wall or a platform edge between them is not
	-- a fight (they used to stand facing each other through it for the rest of the match)
	local reachable = NavigationModule.isReachable(rootPart, targetHRP)
	-- A Quin going round keeps to its path until the straight line has stayed clear for
	-- Nav_ClearHoldTime: a line that opened for a moment while rounding a pillar flipped it
	-- between the path and the straight line, and it ran in circles next to its target.
	if not LocomotionModule.isOnGround(rootPart, humanoid) then
		-- Mid-jump the body's height says nothing about the way to the target (the top of a
		-- hurdle is 8 studs up: "too high to reach" sent it off on a path round, swerving)
		reachable = not data.detouring
	elseif reachable then
		if data.detouring then
			data.clearSince = data.clearSince or now
			if now - data.clearSince < (CombatConfig.Nav_ClearHoldTime or 0.5) then
				reachable = false
			else
				data.detouring = false
			end
		end
	else
		data.detouring = true
		data.clearSince = nil
	end

	-- Mirroring: If they are circling, we circle!
	if reachable and targetState == "Circling" and distance < (CombatConfig.CombatRange or 8.2) * 4.0 then
		if math.random() > 0.8 then
			return States.Circling
		end
	end
	
	-- In range to fight: by studs, or by time when Reach is on (a target running in is met sooner)
	local reachNow = Reach.enabled() and Reach.measure(fighter, rootPart, target) or nil
	if reachNow then Reach.publish(fighter, reachNow) end
	local inRange = distance <= (CombatConfig.CombatRange or 8.2) * 1.5
		or (reachNow ~= nil and reachNow.time <= (CombatConfig.Reach_FightEnterTime or 0.15) and distance <= (CombatConfig.CombatRange or 8.2) * 3)
	-- (a flanker still going round does not stop to fight at the side: it gets behind first,
	-- unless the enemy comes right at it; team coordination step 3)
	if inRange and fighter:GetAttribute("Flanking") and distance > (CombatConfig.CombatRange or 8.2) * (CombatConfig.Team_FlankCommitRange or 0.9) then
		inRange = false
	end
	if reachable and inRange then
		if math.random() > 0.7 then
			return States.Circling
		else
			return States.Fight
		end
	end
	
	-- What lies between it and the target, and the move for it (ChaseState/Obstacles)
	local nextState, obstacleSteer, platformDismountDir
	nextState, obstacleSteer, platformDismountDir, shouldWalk = Obstacles.update(fighter, humanoid, rootPart, data, target, targetHRP,
		targetState, distance, now, hpRatio, confidence, inShowdown, shouldWalk)
	if nextState then
		return nextState
	end

	-- How it runs there: pace, clip, lead, room for teammates, arcs, path, the steer (ChaseState/Steer)
	Steer.update(fighter, humanoid, rootPart, data, target, targetHRP, targetState, distance, now, speedMult, hasLoS,
		reachable, shouldWalk, inShowdown, obstacleSteer, platformDismountDir)

	return ChaseState
end

return ChaseState
