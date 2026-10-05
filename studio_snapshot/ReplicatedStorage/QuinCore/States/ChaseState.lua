--// ChaseState.lua
-- Intelligent pathfinding chase with obstacle jumping and smooth lean
-- Single Source of Truth: ReplicatedStorage.QuinCore.AnimationConfig

local DebugDraw = require(game:GetService("ReplicatedStorage"):WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("DebugDraw"))
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")
local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")

local TargetingModule = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("TargetingModule"))
local AnimationModule = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("AnimationModule"))
local CombatConfig = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("CombatConfig"))
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
local chaseData = setmetatable({}, { __mode = "k" })

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
		return require(script.Parent:WaitForChild("IdleState")) -- (spectators stand and watch)
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
		return require(script.Parent:WaitForChild("CirclingState"))
	end

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

	-- Vertical gap awareness: target is perched on high ground
	local verticalGap = targetHRP.Position.Y - rootPart.Position.Y
	local lastPJ = fighter:GetAttribute("LastPositioningJumpTime") or 0 -- tick() timestamp
	local flatDistToTgt = Vector3.new(targetHRP.Position.X - rootPart.Position.X, 0, targetHRP.Position.Z - rootPart.Position.Z).Magnitude

	-- An enemy it has seen high in the air may be met up there
	if not inShowdown and not humanoid.Jump and humanoid:GetState() ~= Enum.HumanoidStateType.Freefall then
		local jumper = AirInterceptModule.consider(fighter, rootPart)
		if jumper then
			AirInterceptModule.commit(fighter, jumper)
			RuntimeTracer.checkpoint(fighter, "Chase: going up after a jumper")
			return require(script.Parent:WaitForChild("ProjectileJumpState"))
		end
	end

	-- Perched means standing on something up there. A target that is merely in the air (jumping,
	-- knocked up) comes back down by itself; treating it as high ground sent a projectile jump
	-- after every jumper.
	local targetHumanoid = target:FindFirstChildOfClass("Humanoid")
	local targetPerched = targetHumanoid ~= nil and targetHumanoid.FloorMaterial ~= Enum.Material.Air
		and not targetHumanoid.PlatformStand

	-- Climb to a target above through stepping stones (NavigationModule.nextStone): a precise
	-- hop onto the next surface that brings it closer, then the next from there. Running jumps
	-- onto small tops carried their speed straight off the far side, so these are spot jumps.
	-- (a smaller climb too when it cannot simply walk up: the last 7 studs from one high stone to
	-- the target's ran it straight off the stone)
	-- A top within a jump's reach is jumped on to (the run-up and jump further down); the
	-- stones are for what is higher, or when that jump has not come off for
	-- HighGround_ClimbPatience seconds. (The stones came first for any climb of 8 studs or more,
	-- so the jump was never taken for those: 67 spot hops to 4 jumps up in a 96 s match.)
	local jumpable = targetPerched and verticalGap >= (CombatConfig.HighGround_InterceptJumpMinReach or 8.0)
		and verticalGap <= (CombatConfig.Jump_MaxReach or 25.0)
	data.jumpClimbSince = jumpable and (data.jumpClimbSince or tick()) or nil
	local jumpFirst = jumpable and tick() - data.jumpClimbSince < (CombatConfig.HighGround_ClimbPatience or 5)
	local stoneClimb = not jumpFirst and (verticalGap >= (CombatConfig.Nav_StoneMinClimb or 8)
		or (verticalGap >= 2 and not NavigationModule.isReachable(rootPart, targetHRP)))
	if not inShowdown and stoneClimb and LocomotionModule.isOnGround(rootPart, humanoid) and not LocomotionModule.isSliding(fighter) then
		local stone = NavigationModule.nextStone(fighter, rootPart, targetHRP, 2)
		if stone then
			fighter:SetAttribute("ObstacleAwareness", string.format("Stepping stone: %.0f up, %.0f across", stone.rise, stone.hop))
			if tick() - (fighter:GetAttribute("LastStoneHopTime") or 0) >= 0.6 then
				fighter:SetAttribute("LastStoneHopTime", tick())
				-- A stone it is facing, within a jump's reach and range, and wide enough to land
				-- a running jump on, is simply jumped on to; the spot hop (a projectile arc) is
				-- for the rest: too high, too far, a small top, or not lined up.
				local toStone = Vector3.new(stone.point.X - rootPart.Position.X, 0, stone.point.Z - rootPart.Position.Z)
				local wideTop = math.min(stone.part.Size.X, stone.part.Size.Z) >= (CombatConfig.Nav_StoneJumpMinWidth or 10)
				local lined = toStone.Magnitude > 0.1 and rootPart.CFrame.LookVector:Dot(toStone.Unit) > 0.85
				local jumpTo = wideTop and lined
					and TraversalModule.solveJumpOnto(stone.rise, math.max(stone.hop - 3, 1), CombatConfig.Jump_MaxReach or 25.0, 3)
				if jumpTo and LocomotionModule.jump(fighter, humanoid, rootPart, jumpTo.height, jumpTo.speed, "jump") then
					fighter:SetAttribute("ObstacleAwareness", string.format("Jump to a stone: %.0f up, %.0f across", stone.rise, stone.hop))
					fighter:SetAttribute("StoneJumps", (fighter:GetAttribute("StoneJumps") or 0) + 1) -- (probes)
					require(script.Parent.Parent:WaitForChild("Modules"):WaitForChild("AirDash")).noteJump(fighter, stone.point)
					return ChaseState
				end
				fighter:SetAttribute("LastProjectileJumpTime", tick())
				local ProjectileJumpState = require(script.Parent:WaitForChild("ProjectileJumpState"))
				ProjectileJumpState.aimAtPoint(fighter, stone.point)
				return ProjectileJumpState
			end
			LocomotionModule.brake(fighter, humanoid, rootPart, 0.1)
			return ChaseState
		end
	end

	if not inShowdown and targetPerched and verticalGap >= (CombatConfig.HighGround_InterceptJumpMinReach or 8.0) then
		local energy = fighter:GetAttribute("Energy") or 100
		local climbEnergyCost = CombatConfig.HighGround_InterceptJumpEnergyCost or 20

		local canLeave = not humanoid.Jump and humanoid:GetState() ~= Enum.HumanoidStateType.Freefall
		if verticalGap <= (CombatConfig.Jump_MaxReach or 25.0) then
			-- Within a jump's reach. The jump is solved for the platform's edge: it needs a
			-- run-up (too close and the feet hit the lip, too far and they fall short), so the
			-- Quin backs off or closes in until the jump works, then takes it.
			local platform = PlatformCatalogue.under(targetHRP.Position)
			local edge = platform and PlatformCatalogue.nearestTopPoint(platform, rootPart.Position, 0) or targetHRP.Position
			local toEdge = Vector3.new(edge.X - rootPart.Position.X, 0, edge.Z - rootPart.Position.Z)
			local depth = platform and PlatformCatalogue.landingDepth(platform, edge, rootPart.Position) or nil
			local solution, problem = TraversalModule.solveJumpOnto(verticalGap, toEdge.Magnitude, CombatConfig.Jump_MaxReach or 25.0, depth)
			if problem == "TooClose" and toEdge.Magnitude > 0.1 then
				fighter:SetAttribute("ObstacleAwareness", "Backing off for a run-up")
				LocomotionModule.steer(fighter, humanoid, rootPart, rootPart.Position - toEdge.Unit * 14, 24.0, 0.05)
				GaitModule.update(humanoid, rootPart, 0.1)
				return ChaseState
			end
			local facingEdge = toEdge.Magnitude > 0.1 and rootPart.CFrame.LookVector:Dot(toEdge.Unit) > 0.85
			if solution and facingEdge and energy >= climbEnergyCost and (tick() - lastPJ) >= 2.0 and canLeave then
				fighter:SetAttribute("ObstacleAwareness", "High-Ground Intercept Jump")
				if LocomotionModule.jump(fighter, humanoid, rootPart, solution.height, solution.speed, "jump") then
					-- (where it means to land, so a jump coming down short can dash on to it)
					require(script.Parent.Parent:WaitForChild("Modules"):WaitForChild("AirDash")).noteJump(fighter, edge + toEdge.Unit * (depth or 4))
					fighter:SetAttribute("LastPositioningJumpTime", tick())
					fighter:SetAttribute("Energy", energy - climbEnergyCost)
					return ChaseState
				end
			end
			-- A jump that works from here but is not lined up yet (it has just backed off, or
			-- the last jump was a moment ago): it runs at the edge, and goes when it is. (It
			-- fell through to the vantage rule below, which walked it away from the platform:
			-- 21 run-ups and no jump in a 97 s match.)
			if solution and jumpFirst and energy >= climbEnergyCost and canLeave then
				fighter:SetAttribute("ObstacleAwareness", "Run-up for a jump")
				LocomotionModule.steer(fighter, humanoid, rootPart, edge, math.max(solution.speed, 24.0), 0.05)
				GaitModule.update(humanoid, rootPart, 0.1)
				return ChaseState
			end
		elseif canLeave then
			-- Higher than any jump: the projectile jump is the way up to a target on a platform
			local lastProjectileJump = fighter:GetAttribute("LastProjectileJumpTime") or 0
			local cooldown = (CombatConfig.ProjectileJump_Cooldown or 14.0) / (workspace:GetAttribute("GameSpeedMultiplier") or 1.0)
			if CombatConfig.EnableProjectileJump ~= false and fighter:GetAttribute("EnableProjectileJump") ~= false
				and energy >= (CombatConfig.ProjectileJumpMinEnergy or 40)
				and (tick() - lastProjectileJump) >= cooldown
				and flatDistToTgt <= (CombatConfig.ProjectileJumpMaxDistance or 800) then
				fighter:SetAttribute("LastProjectileJumpTime", tick())
				fighter:SetAttribute("ObstacleAwareness", "Projectile jump to target on high ground")
				local stylePool = { 1, 1, 2, 3, 4, 5, 5, 6, 7 }
				fighter:SetAttribute("JumpStyle", stylePool[math.random(1, #stylePool)])
				TargetingModule.setTarget(fighter, target, "State")
				return require(script.Parent:WaitForChild("ProjectileJumpState"))
			end
		end

		-- If standing directly underneath the platform (< 16 studs flat), back up to maintain vantage LoS
		-- Back away from the platform to a spot straight out from the target (fixed while it moves
		-- out along that line). It used to be set from the body's own facing every tick (22 behind,
		-- 8 right), so turning towards it moved it: Quins under a perched target ran in circles
		-- on the spot. Out there it watches, creeping in, until a way up opens.
		local vantage = CombatConfig.HighGround_VantageDistance or 24
		local outOfJumpReach = verticalGap > (CombatConfig.Jump_MaxReach or 25.0)
		-- (not while it is working at the jump up: the jump's run-up starts closer than this)
		if (flatDistToTgt < 16.0 and not jumpFirst) or (outOfJumpReach and flatDistToTgt < vantage) then
			local away = Vector3.new(rootPart.Position.X - targetHRP.Position.X, 0, rootPart.Position.Z - targetHRP.Position.Z)
			if away.Magnitude < 1 then
				local saved = fighter:GetAttribute("VantageDir")
				if typeof(saved) ~= "Vector3" then
					local a = math.random() * math.pi * 2
					saved = Vector3.new(math.cos(a), 0, math.sin(a))
					fighter:SetAttribute("VantageDir", saved)
				end
				away = saved
			end
			fighter:SetAttribute("ObstacleAwareness", "Positioning for High-Ground Vantage")
			if flatDistToTgt < 16.0 then
				local vantageTarget = Vector3.new(targetHRP.Position.X, rootPart.Position.Y, targetHRP.Position.Z) + away.Unit * vantage
				LocomotionModule.steer(fighter, humanoid, rootPart, vantageTarget, 20.0, 0.05)
			else
				-- (a slow creep towards it keeps the body turned to the target)
				LocomotionModule.steer(fighter, humanoid, rootPart, Vector3.new(targetHRP.Position.X, rootPart.Position.Y, targetHRP.Position.Z), 2.0, 0.05)
			end
			return ChaseState
		end
	end

	-- 3. Dangerously low resources: do not pursue into exhaustion
	local energy = fighter:GetAttribute("Energy") or 100
	local hpRatio = humanoid.Health / humanoid.MaxHealth
	if energy < 15 and hpRatio < 0.35 then
		return require(script.Parent:WaitForChild("CirclingState"))
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
		fighter:SetAttribute("TimeLastSeen", now)
	else
		local savedLKP = fighter:GetAttribute("LastSeenTargetPosition")
		data.targetLKP = data.targetLKP or savedLKP or targetHRP.Position

		-- The hunt goes on from memory: head for where the target is believed to be, and from
		-- there search on along the way it was last moving, for as long as the track is worth
		-- following. A persistent hunter follows a fainter trail.
		local contact = Cognition.contactFor(fighter, target)
		local trailWorth = contact ~= nil and not contact.visible
			and contact.confidence >= (CombatConfig.Chase_TrailGiveUpConfidence or 0.6) - (fighter:GetAttribute("Pers_TargetPersistence") or 0.6) * 0.5
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
				return require(script.Parent:WaitForChild("IdleState"))
			end
		end
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
	-- A hunter still committed to its target only turns on a passer-by that is itself after it.
	local looselyCommitted = commitment < (CombatConfig.Chase_DistractionCommitment or 0.6)
	if not inShowdown and persistence < 0.85 then
		local myTeam = fighter:GetAttribute("Team") or "None"
		local nearestDistraction = nil
		local nearestDistractionDist = 13.0
		for _, q in ipairs(CollectionService:GetTagged("Quin")) do
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
			return require(script.Parent:WaitForChild("FightState"))
		end
	end

	-- Pursuit Abandonment: Target reached squad ambush (1v3+) and commitment is broken
	-- Only applies when actually closing in (distance <= 45 studs) and local allies are outnumbered!
	if not inShowdown and commitment < 0.30 and distance <= 45.0 then
		local targetTeam = target:GetAttribute("Team")
		local myTeam = fighter:GetAttribute("Team")
		local targetAllies = 0
		local myAllies = 0
		for _, q in ipairs(CollectionService:GetTagged("Quin")) do
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
				-- FightState's facing gyro turns the body onto the new target. The pivot clip rotates
				-- the hips 177 degrees by itself: stacked on a root that is also turning it over-spins
				-- the mesh and snaps back when it ends, so it stays off unless explicitly enabled.
				if CombatConfig.Turn180PivotClipEnabled == true then
					AnimationModule.playConfig(humanoid, "Awareness.Turn180Pivot", 1.5, Enum.AnimationPriority.Action4, false)
				end
				
				TargetingModule.setTarget(fighter, rearModel, "RearThreat")
				fighter:SetAttribute("LastRearReactionTime", now)
				
				return require(script.Parent:WaitForChild("FightState"))
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
		elseif strat == "AlternatingPace" then
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
	local dashPref = fighter:GetAttribute("Pers_DashPreference") or 0.6
	local minDashMana = CombatConfig.DashMinEnergy or 25
	local dashCooldown = math.max(4.0, ((dashPref > 0.7) and 12.0 or 18.0) / speedMult)
	local isDashOnCooldown = (now - lastDash) < dashCooldown
	
	if not isDashOnCooldown and energy >= minDashMana and distance >= 20 and distance <= 70 then
		local shouldCheckDash = now >= (data.nextDashCheckTime or 0)
		if shouldCheckDash then
			data.nextDashCheckTime = now + (((dashPref > 0.7 and math.random(10, 15) or math.random(15, 22))) / speedMult)
			if recAction == "Dash" or math.random() < (dashPref * 0.25) then
				TargetingModule.setTarget(fighter, target, "State")
				LocomotionModule.dash(fighter, humanoid, rootPart, targetHRP.Position, distance)
				return ChaseState
			end
		end
	end

	-- 5. Projectile jump: the way to close on a distant target (energy cost, cooldown, and a
	-- chance per check that grows with aggression and mobility; CombatConfig.ProjectileJump_*)
	local pjEnabled = not inShowdown and (CombatConfig.EnableProjectileJump ~= false) and (fighter:GetAttribute("EnableProjectileJump") ~= false)
	local lastPJ = fighter:GetAttribute("LastProjectileJumpTime") or 0
	local aggression = fighter:GetAttribute("Pers_Aggression") or 0.6
	local mobility = fighter:GetAttribute("Pers_MobilityPreference") or 0.6
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

			return require(script.Parent:WaitForChild("ProjectileJumpState"))
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
	if reachable and targetState == "Circling" and distance < (CombatConfig.CombatRange or 7) * 4.0 then
		if math.random() > 0.8 then
			return require(script.Parent:WaitForChild("CirclingState"))
		end
	end
	
	if reachable and distance <= (CombatConfig.CombatRange or 7) * 1.5 then
		if math.random() > 0.7 then
			return require(script.Parent:WaitForChild("CirclingState"))
		else
			return require(script.Parent:WaitForChild("FightState"))
		end
	end
	
	-- === Comprehensive OB & Obstacle Situational Awareness ===
	local obsInfo = SpatialModule.analyzeObstacleAhead(rootPart, targetHRP.Position, 22)
	local obstacleSteer = nil
	-- A lip lower than a step is walked over (it used to be "avoided": the Quin swerved,
	-- which on a narrow raised lane meant off the edge)
	if obsInfo.hasObstacle and (obsInfo.height or 99) < (CombatConfig.Locomotion_StepHeight or 1.5) then
		obsInfo = { hasObstacle = false }
	end
	if obsInfo.hasObstacle and not inShowdown then
		local isJumpSuppressed = LocomotionModule.isJumpSuppressed(fighter, humanoid)
		-- Takeoff timing: a runner leaves the ground so the top of its arc is over the obstacle,
		-- i.e. speed x time-to-apex before it (about 7 studs for a 2-stud hurdle at 40 studs/s,
		-- 12 for an 8-stud one). It used to jump as soon as the 22-stud look-ahead saw anything:
		-- a 2-stud hurdle from 19 studs out, and a taller one was refused until the Quin ran
		-- into it, stopped dead and hopped up from a standstill.
		local flatVelNow = Vector3.new(rootPart.AssemblyLinearVelocity.X, 0, rootPart.AssemblyLinearVelocity.Z)
		local speedNow = flatVelNow.Magnitude
		local faceDistance = obsInfo.hitPosition and Vector3.new(obsInfo.hitPosition.X - rootPart.Position.X, 0, obsInfo.hitPosition.Z - rootPart.Position.Z).Magnitude or 0
		local clearRise = math.clamp((obsInfo.height or 0) + 0.8, 3, 14)
		local timeToApex = math.sqrt(2 * clearRise / Workspace.Gravity)
		local takeoffDistance = math.max(2.5, speedNow * timeToApex)
		-- Thin (a hurdle, a low wall) or deep (a box, a platform): probe the top beyond the face
		local isThin = false
		if obsInfo.hitPosition and obsInfo.topSurfaceY then
			local dirFlat = (targetHRP.Position - rootPart.Position) * Vector3.new(1, 0, 1)
			dirFlat = dirFlat.Magnitude > 0.1 and dirFlat.Unit or Vector3.new(rootPart.CFrame.LookVector.X, 0, rootPart.CFrame.LookVector.Z).Unit
			local probeParams = RaycastParams.new()
			probeParams.FilterType = Enum.RaycastFilterType.Exclude
			probeParams.FilterDescendantsInstances = { fighter, Workspace:FindFirstChild("QuinServer") }
			local beyond = obsInfo.hitPosition + dirFlat * 7 + Vector3.new(0, 1, 0)
			local down = Workspace:Raycast(Vector3.new(beyond.X, obsInfo.topSurfaceY + 3, beyond.Z), Vector3.new(0, -(obsInfo.topSurfaceY + 3 - rootPart.Position.Y + 8), 0), probeParams)
			isThin = not down or down.Position.Y < obsInfo.topSurfaceY - 1.5
		end
		-- Skid-over: a low obstacle (up to SkidOver_MaxRise) is crossed in one speed vault, a
		-- hand on top, whatever its length up to SkidOver_MaxLength. The flight is sized to the
		-- length (apex over the middle, landing a stride past the far edge) and the clip is
		-- fitted to that flight (LocomotionModule "skidover").
		-- Thin obstacles too tall to skid (up to Hurdle_MaxRise high, 7 deep) are hurdled with the
		-- same solve and a little more clearance: the old hurdle peaked over the near edge and
		-- came down on top of a 3-deep, 7-tall bar.
		local skidRise, skidTakeoff, crossType, skidLength, crossHeight, crossSpeed = nil, nil, nil, nil, nil, nil
		-- Skid-over only between SkidOver_MinRise and SkidOver_MaxRise (3-5: below that the hand
		-- on top reads wrong, above it the vault is too high); everything else is a jump
		local lowEnoughToSkid = (obsInfo.height or 99) <= (CombatConfig.SkidOver_MaxRise or 5)
			and (obsInfo.height or 0) >= (CombatConfig.SkidOver_MinRise or 3)
		if obsInfo.hitPosition and obsInfo.topSurfaceY and (obsInfo.height or 99) <= (CombatConfig.Hurdle_MaxRise or 11) and speedNow >= 14 then
			local dirFlat = Vector3.new(flatVelNow.X, 0, flatVelNow.Z).Unit
			local probeParams = RaycastParams.new()
			probeParams.FilterType = Enum.RaycastFilterType.Exclude
			probeParams.FilterDescendantsInstances = { fighter, Workspace:FindFirstChild("QuinServer") }
			local length = nil
			for d = 1, lowEnoughToSkid and (CombatConfig.SkidOver_MaxLength or 16) or 7, 1.5 do
				local p = obsInfo.hitPosition + dirFlat * d
				local top = Workspace:Raycast(Vector3.new(p.X, obsInfo.topSurfaceY + 2, p.Z), Vector3.new(0, -4, 0), probeParams)
				if not top or top.Position.Y < obsInfo.topSurfaceY - 1 then
					length = d
					break
				end
			end
			skidLength = length
			if length then
				-- Apex over the middle; the arc must clear the obstacle's height (+0.8) at both
				-- edges: g/8 * (T^2 - (L/v)^2) >= h + 0.8. Takeoff and landing are each
				-- (v*T - L)/2 from the edges.
				local g = Workspace.Gravity
				local clearance = (lowEnoughToSkid or obsInfo.height < 3) and 0.8 or 1.2
				local flight = math.sqrt((length / speedNow) ^ 2 + 8 * (obsInfo.height + clearance) / g)
				local rise = g * flight * flight / 8
				if rise <= (lowEnoughToSkid and (CombatConfig.SkidOver_MaxFlightRise or 9) or 14) then
					skidRise = rise
					skidTakeoff = math.max(2, (speedNow * flight - length) / 2)
					crossType = lowEnoughToSkid and "skidover" or "hurdle"
					crossHeight = obsInfo.height + clearance

					-- Pace for the next one. A crossing lands as far past this obstacle as it took off
					-- before it, and both grow with speed; with the next obstacle close behind, a full
					-- sprint landed with no run-up left for it (0.9 studs from a 7-stud bar: a dead stop
					-- and a standing jump). A runner shortens up on the ground, before taking off: the
					-- approach speed is capped so this landing plus the next takeoff fit in the gap,
					--   v <= (2 (gap - 1) + L1 + L2) / (T1 + T2),  T = sqrt(8 (h + c) / g)
					local farEdge = obsInfo.hitPosition + dirFlat * length
					local floorY = obsInfo.topSurfaceY - obsInfo.height
					local ahead = Workspace:Raycast(Vector3.new(farEdge.X, floorY + 1.0, farEdge.Z) + dirFlat * 0.5, dirFlat * 26, probeParams)
					if data and ahead and ahead.Normal.Y < 0.3 then
						local inside = ahead.Position - Vector3.new(ahead.Normal.X, 0, ahead.Normal.Z) * 0.4
						local nextTop = Workspace:Raycast(inside + Vector3.new(0, 20, 0), Vector3.new(0, -24, 0), probeParams)
						local nextH = nextTop and (nextTop.Position.Y - floorY) or 0
						if nextH >= (CombatConfig.Locomotion_StepHeight or 1.5) and nextH <= (CombatConfig.Hurdle_MaxRise or 11) then
							local gap = (ahead.Position - farEdge):Dot(dirFlat)
							local T1 = math.sqrt(8 * (obsInfo.height + clearance) / g)
							local T2 = math.sqrt(8 * (nextH + 1.0) / g)
							local paceCap = (2 * (gap - 1) + length + 3) / (T1 + T2)
							if paceCap < speedNow + 2 then
								data.obstaclePace = math.max(paceCap, 16)
								data.obstaclePaceUntil = now + 0.6
								fighter:SetAttribute("ObstaclePace", math.floor(data.obstaclePace))
							end
						end
					end
				end
			end
		end
		local readyToJump = isThin and faceDistance <= takeoffDistance + 1
			or (not isThin and faceDistance <= 4 + speedNow * 0.16)
		-- This state updates at 10 Hz: at 40 studs/s that is 4 studs a tick, about the whole
		-- takeoff window, so the takeoff is timed to the moment (task.delay) once it falls
		-- before the next tick
		local skidLead = speedNow * 0.15
		if skidRise then
			readyToJump = faceDistance <= skidTakeoff + skidLead
		end
		if skidRise and readyToJump and not isJumpSuppressed and not humanoid.Jump and humanoid:GetState() ~= Enum.HumanoidStateType.Freefall then
			if tick() >= (fighter:GetAttribute("SkidPendingUntil") or 0) then
				local wait = math.max(0, (faceDistance - skidTakeoff) / math.max(speedNow, 1))
				fighter:SetAttribute("SkidPendingUntil", tick() + wait + 0.3)
				fighter:SetAttribute("SkidPlan", string.format("%s face %.1f takeoff %.1f wait %.2f length %.1f rise %.1f v %.0f%s",
					crossType, faceDistance, skidTakeoff, wait, skidLength or -1, skidRise, speedNow,
					crossSpeed and string.format(" (setting up the next: v %.0f)", crossSpeed) or ""))
				fighter:SetAttribute("ObstacleAwareness", crossType == "skidover" and "Skidding over" or "Hurdling")
				local facePos = obsInfo.hitPosition
				local crossDir = Vector3.new(flatVelNow.X, 0, flatVelNow.Z).Unit
				local plannedRise, plannedTakeoff, plannedLength, plannedHeight, plannedSpeed = skidRise, skidTakeoff, skidLength, crossHeight, crossSpeed
				task.delay(wait, function()
					-- Just off a landing the body can still read as airborne for a few frames; the
					-- jump would be refused and it ran into the obstacle. Wait for the ground (briefly).
					local function inAir()
						return not LocomotionModule.isOnGround(rootPart, humanoid)
					end
					local deadline = os.clock() + 0.35
					while inAir() and os.clock() < deadline do
						task.wait()
					end
					if fighter.Parent and humanoid.Health > 0 and fighter:GetAttribute("CurrentState") == "Chase"
						and not inAir() then
						local v = rootPart.AssemblyLinearVelocity
						local speed = plannedSpeed or Vector3.new(v.X, 0, v.Z).Magnitude
						local rise = plannedRise
						-- Where it really is now: a crossing planned on a landing, or a tick late,
						-- can be closer than the ideal takeoff. Then it jumps from here instead of
						-- refusing: the lowest arc that still clears both edges, found over the
						-- horizontal speeds it can shed (a shortened, steeper jump).
						local d = (facePos - rootPart.Position):Dot(crossDir)
						if d < plannedTakeoff - 0.75 then
							local g = Workspace.Gravity
							local H = plannedHeight
							local L = plannedLength or 3
							local best = nil
							if d > 0.3 then
								for hv = math.max(speed, 10), 8, -2 do
									local vy = math.max(H * hv / d + g * d / (2 * hv), H * hv / (d + L) + g * (d + L) / (2 * hv))
									if not best or vy < best.vy * 0.93 then
										best = { hv = hv, vy = vy }
									end
								end
							end
							if not best or best.vy * best.vy / (2 * g) > 14 then
								fighter:SetAttribute("SkidPlan", (fighter:GetAttribute("SkidPlan") or "") .. string.format(" TOO CLOSE d %.1f", d))
								return
							end
							rise = best.vy * best.vy / (2 * g)
							speed = best.hv
							fighter:SetAttribute("SkidPlan", (fighter:GetAttribute("SkidPlan") or "") .. string.format(" SHORT d %.1f -> v %.0f rise %.1f", d, speed, rise))
						end
						if crossType == "skidover" then
							fighter:SetAttribute("SkidObstacleHeight", plannedHeight - 0.8)
						end
						local ok = JumpHandler.performJump(humanoid, rootPart, rise, speed, crossType)
						if ok == false then
							fighter:SetAttribute("SkidPlan", (fighter:GetAttribute("SkidPlan") or "") .. " REFUSED " .. tostring(fighter:GetAttribute("JumpRejected")))
						end
					end
				end)
			end
		elseif obsInfo.canVault and not readyToJump then
			fighter:SetAttribute("ObstacleAwareness", "Approaching Obstacle")
		elseif obsInfo.canVault and isThin and not isJumpSuppressed and not humanoid.Jump and humanoid:GetState() ~= Enum.HumanoidStateType.Freefall then
			fighter:SetAttribute("ObstacleAwareness", "Hurdling")
			JumpHandler.performJump(humanoid, rootPart, clearRise, speedNow, "hurdle")
		elseif obsInfo.canVault and not isJumpSuppressed and not humanoid.Jump and humanoid:GetState() ~= Enum.HumanoidStateType.Freefall then
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
	local slideGap = SpatialModule.detectLowOverheadGap(rootPart, 18)
	local energy = fighter:GetAttribute("Energy") or 100
	local quirky = fighter:GetAttribute("Quirky") or "Balanced"
	local lastSlide = fighter:GetAttribute("LastSlideTime") or 0
	local slideCooldown = (quirky == "Charger") and 5.0 or (CombatConfig.SlideCooldown or 8.0)
	local canSlide = (now - lastSlide) >= slideCooldown and energy >= (CombatConfig.SlideMinEnergy or 12)
		and not humanoid.Jump and humanoid:GetState() ~= Enum.HumanoidStateType.Freefall

	-- Sliding under a gap is forced by the course, not a choice: no cooldown or energy gate.
	-- The clip is low from about 0.1 s to 0.9 s, so it starts when the bar is ~0.3 s away.
	if slideGap and not inShowdown and not LocomotionModule.isSliding(fighter) then
		local flatSpeed = Vector3.new(rootPart.AssemblyLinearVelocity.X, 0, rootPart.AssemblyLinearVelocity.Z).Magnitude
		if slideGap.faceDistance <= flatSpeed * 0.3 + 1.5 then
			fighter:SetAttribute("ObstacleAwareness", string.format("Sliding under a %.0f-stud gap", slideGap.gapHeight))
			fighter:SetAttribute("LastSlideTime", now)
			LocomotionModule.slide(fighter, humanoid, rootPart, nil, nil, { underGap = true })
			return ChaseState
		end
		fighter:SetAttribute("ObstacleAwareness", "Approaching a low gap")
	end

	-- Tactical Gap-Close Slide: one decision per approach, taken as the Quin comes into slide
	-- range at running speed, so the slide ends in striking distance. (It used to be re-rolled
	-- every 1.5s, and the range is crossed in under half a second, so it almost never fired.)
	if distance > 45 then
		data.slideDecided = false
	end
	-- (a tackle has to reach: the glide covers ~17 studs at a run, plus the legs' reach)
	local tackling = CombatConfig.SlideTackle_Enabled ~= false
	local slideMin = tackling and (CombatConfig.SlideTackle_StartMin or 8) or 18
	local slideMax = tackling and (CombatConfig.SlideTackle_StartMax or 19) or 35
	if canSlide and distance >= slideMin and distance <= slideMax and (data.currentSpeed or 30) >= 24 and not inShowdown then
		if not data.slideDecided then
			data.slideDecided = true
			local mobilityPref = fighter:GetAttribute("Pers_MobilityPreference") or 0.6
			local slideChance = (quirky == "Charger") and 0.6 or math.clamp(0.10 + 0.5 * mobilityPref, 0.10, 0.45)
			if workspace:GetAttribute("SlideTackleAlways") and game:GetService("RunService"):IsStudio() then slideChance = 1 end -- (test switch)
			data.slideWanted = math.random() < slideChance
		end
		-- Decided to slide in: it goes as soon as its run lines up with the target (a tackle slide
		-- refuses a target too far off its line; the chase curves in, so that comes a moment later)
		if data.slideWanted then
			-- (a slide in on the target takes the legs of whoever stands in its lane: Modules/SlideTackle)
			if require(script.Parent.Parent:WaitForChild("Modules"):WaitForChild("SlideTackle")).slide(fighter, humanoid, rootPart, target) > 0 then
				data.slideWanted = false
				fighter:SetAttribute("ObstacleAwareness", "Tactical Slide Gap-Close")
				fighter:SetAttribute("LastSlideTime", now)
				return ChaseState
			end
		end
	end

	-- Dynamic Wall-Running (Phase 6 Parkour): angled vertical wall traversal
	local lastWallRun = fighter:GetAttribute("LastWallRunTime") or 0
	local wallRunCooldown = (quirky == "WallTapper") and 2.5 or (CombatConfig.WallRunCooldown or 5.0)
	-- (a target that takes to a wall is followed onto it: no waiting out the cooldown)
	local followingOntoWall = targetState == "WallRun"
	local canWallRun = ((now - lastWallRun) >= wallRunCooldown or followingOntoWall) and energy >= (CombatConfig.WallRunMinEnergy or 15)
		and (data.currentSpeed or 30) >= (CombatConfig.WallRunMinSpeed or 18)
		and not humanoid.Jump and humanoid:GetState() ~= Enum.HumanoidStateType.Freefall

	-- Not worth mounting a wall with the target already this close: the run would end at once
	if canWallRun and not inShowdown and distance > 22 then
		local wallSurface = SpatialModule.detectWallRunSurface(rootPart, CombatConfig.WallRunRayDistance or 5.2, CombatConfig.WallRunMinRunway or 24)
		local WallRunState = require(script.Parent:WaitForChild("WallRunState"))
		if wallSurface and WallRunState.fastEnough(rootPart, wallSurface) then
			fighter:SetAttribute("ObstacleAwareness", "Wall-Running " .. wallSurface.side)
			return WallRunState
		end
	end

	-- High-Ground Seeking: climb to a reachable overhead platform when it grants an
	-- advantage — target is above, being pressured/bullied, or critically hurt.
	local overheadPlatform = SpatialModule.findReachableOverheadPlatform(rootPart, (CombatConfig.Jump_MaxReach or 25) + 2)
	if overheadPlatform and not inShowdown and not humanoid.Jump and humanoid:GetState() ~= Enum.HumanoidStateType.Freefall then
		local lastHighGround = data.lastHighGroundJump or 0
		local targetAbove = targetHRP.Position.Y > rootPart.Position.Y + 5
		local recAction = fighter:GetAttribute("RecommendedAction")
		local beingBullied = fighter:GetAttribute("BeingBullied")
		local wantHighGround = targetAbove or recAction == "Retreat" or beingBullied or hpRatio < 0.35
		if wantHighGround and (now - lastHighGround) > 6 then
			-- The top is reached from outside its footprint, by the jump solved for its rim. (It
			-- used to jump straight up from wherever it stood: when that was under the platform
			-- it hit the underside, and tried again every 6 s.) It gives the climb a few seconds:
			-- out from under, a run-up, the jump; then it lets it be for a while.
			data.highGroundSince = data.highGroundSince or now
			local platform = PlatformCatalogue.under(overheadPlatform.position + Vector3.new(0, 0.5, 0), 2)
			local feetY = rootPart.Position.Y - (humanoid.HipHeight + rootPart.Size.Y / 2)
			local rise = overheadPlatform.topY - feetY
			local edge = platform and PlatformCatalogue.nearestTopPoint(platform, rootPart.Position, 0)
			local toEdge = edge and Vector3.new(edge.X - rootPart.Position.X, 0, edge.Z - rootPart.Position.Z)
			if not platform or now - data.highGroundSince > (CombatConfig.HighGround_ClimbPatience or 5) then
				data.lastHighGroundJump, data.highGroundSince = now, nil
			elseif toEdge.Magnitude < 1.0 then
				-- Under it: out the nearest way, with room for a run-up
				local outward = Vector3.new(rootPart.Position.X - platform.center.X, 0, rootPart.Position.Z - platform.center.Z)
				outward = outward.Magnitude > 0.5 and outward.Unit or rootPart.CFrame.LookVector
				local rim = PlatformCatalogue.nearestTopPoint(platform, platform.center + outward * 1000, 0)
				fighter:SetAttribute("ObstacleAwareness", "Under the platform: stepping out to jump")
				LocomotionModule.steer(fighter, humanoid, rootPart, Vector3.new(rim.X, rootPart.Position.Y, rim.Z) + outward * 14, 24.0, 0.05)
				GaitModule.update(humanoid, rootPart, 0.1)
				return ChaseState
			else
				local depth = PlatformCatalogue.landingDepth(platform, edge, rootPart.Position)
				local solution, problem = TraversalModule.solveJumpOnto(rise, toEdge.Magnitude, CombatConfig.Jump_MaxReach or 25.0, depth)
				if solution and rootPart.CFrame.LookVector:Dot(toEdge.Unit) > 0.85 then
					fighter:SetAttribute("ObstacleAwareness", "Climbing High Ground")
					if LocomotionModule.jump(fighter, humanoid, rootPart, solution.height, solution.speed, "jump") then
						require(script.Parent.Parent:WaitForChild("Modules"):WaitForChild("AirDash")).noteJump(fighter, edge + toEdge.Unit * (depth or 4))
						data.lastHighGroundJump, data.highGroundSince = now, nil
						return ChaseState
					end
				elseif problem == "TooHigh" then
					data.lastHighGroundJump, data.highGroundSince = now, nil
				else
					-- too close for the jump: back off for the run-up; otherwise up to the rim, facing it
					local away = problem == "TooClose" and -14 or 14
					fighter:SetAttribute("ObstacleAwareness", problem == "TooClose" and "Backing off for a run-up" or "Lining up the climb")
					LocomotionModule.steer(fighter, humanoid, rootPart, rootPart.Position + toEdge.Unit * away, 24.0, 0.05)
					GaitModule.update(humanoid, rootPart, 0.1)
					return ChaseState
				end
			end
		else
			data.highGroundSince = nil
		end
	end

	-- Self Platform Dismount (Phase 4): if THIS Quin is perched on an elevated platform,
	-- walk toward the nearest ledge biased toward the target rather than milling around.
	local platformDismountDir = nil
	local ledgeDist = 999
	local allowPlatformDrop = false
	local targetBelow = (targetHRP.Position.Y < rootPart.Position.Y - 5.0)

	local isOnPlatform, platformInfo = SpatialModule.isOnElevatedPlatform(rootPart, CombatConfig.HighGround_PerchDetectThreshold or 5.0)
	if isOnPlatform then
		data.wasOnPlatform = true
		if targetBelow then
			allowPlatformDrop = true
			platformDismountDir, ledgeDist = SpatialModule.getPlatformDismountDirection(rootPart, targetHRP.Position)
			fighter:SetAttribute("ObstacleAwareness", "Approaching Platform Ledge")

			-- Check if close enough to ledge and facing target to execute Dive-Down Leap!
			local flatDist = Vector3.new(targetHRP.Position.X - rootPart.Position.X, 0, targetHRP.Position.Z - rootPart.Position.Z).Magnitude
			local lookVec = rootPart.CFrame.LookVector
			local isFacingTarget = lookVec:Dot(platformDismountDir) > 0.15
			-- How it leaves. In a hurry it dives off at its target (below). With time on its side
			-- (sure of itself, in good health, nobody pressing it, the target well away) it walks
			-- to the ledge and steps off: a straight drop, the soft landing, and it walks on.
			local casual = confidence >= (CombatConfig.Dismount_CasualConfidence or 0.7)
				and hpRatio > 0.5
				and flatDist >= (CombatConfig.Dismount_CasualMinDistance or 18)
				and (fighter:GetAttribute("SocialUrgency") or 0) < 0.5
				and not fighter:GetAttribute("SocialHunt")
				and fighter:GetAttribute("IsUnderRearThreat") ~= true
			-- (no jump: it keeps walking and the edge does the rest; the touchdown is the ground
			-- contract's, GaitModule, which gives a walked-off straight drop the soft landing)
			if casual then
				shouldWalk = true
				fighter:SetAttribute("ObstacleAwareness", "Walking off the ledge")
			end

			-- The leap has to carry past the ledge. It used to be taken whenever the target was
			-- within 28 studs, however far the ledge was: from the middle of a wide top a 2-stud
			-- hop of 8-15 studs came down on the same top, played its landing, and was taken
			-- again (several hops and landings before the Quin finally left).
			local leapHeight = 2.0
			local forwardSpeed = math.clamp(flatDist * 1.3, 28.0, 52.0)
			local leapReach = forwardSpeed * 2 * math.sqrt(2 * leapHeight / workspace.Gravity)
			local canDive = (CombatConfig.HighGround_DiveDropEnabled ~= false)
				and not humanoid.Jump
				and humanoid:GetState() ~= Enum.HumanoidStateType.Freefall
				and ledgeDist + (CombatConfig.HighGround_DiveLedgeMargin or 2.5) <= leapReach
				and isFacingTarget
				and not casual

			if canDive then
				fighter:SetAttribute("ObstacleAwareness", "Ledge Dive Down")
				data.isDismountFalling = true
				data.wasOnPlatform = false
				LocomotionModule.jump(fighter, humanoid, rootPart, leapHeight, forwardSpeed, "leap_down")
				return ChaseState
			end
		end
	end

	-- Vertical Obstacle Unstick (Phase 4): detect zero-progress against a vertical face
	-- and force a vertical hop instead of grinding endlessly into the wall.
	data.stuckCheckPos = data.stuckCheckPos or rootPart.Position
	data.stuckCheckTime = data.stuckCheckTime or now
	if (now - data.stuckCheckTime) >= 1.2 then
		local progress = (rootPart.Position - data.stuckCheckPos).Magnitude
		if progress < (CombatConfig.VerticalStuckThreshold or 0.8) and distance > 15 and not humanoid.Jump and humanoid:GetState() ~= Enum.HumanoidStateType.Freefall and not allowPlatformDrop then
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
	-- Walking is the Walk clip's own pace. It used to be 16 studs/s, which is a hard jog: the
	-- legs were over-cranked and it never read as a walk.
	local targetSpeed = (shouldWalk and (CombatConfig.Player_WalkSpeed or 7.5) or speed) * speedMult
	-- Brake into the engagement: cap the pace by what the braking rate can shed over the
	-- remaining gap. At a full sprint the stopping distance (~13 studs) is longer than the
	-- hand-over range to Fight, so a sprinting Quin ran through its target and was shoved back.
	local arriveGap = math.max(distance - (CombatConfig.CombatRange or 8), 0.5)
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
			local mobility = fighter:GetAttribute("Pers_MobilityPreference") or 0.6
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
	
	return ChaseState
end

return ChaseState
