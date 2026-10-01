--// RetreatTacticsModule.lua
-- Where a Quin that has decided to get away runs to.
-- It makes an escape plan - one objective and one destination - and commits to it; it only
-- plans again when the destination is reached, the pursuer has cut the route, it is stuck, or
-- the plan has gone stale. Distances scale with the arena, so an escape is a run across the
-- field and not a loop around the fight.
-- Objectives, scored by the Quin's condition and personality:
--   BREAK_LOS       get behind something the pursuer cannot see through
--   TO_HIGH_GROUND  get onto a platform
--   TO_ALLIES       reach friends who are not already in this fight
--   OPEN_GROUND     put distance between it and the threat
-- A destination that means running at the pursuer is never chosen.

local DebugDraw = require(game:GetService("ReplicatedStorage"):WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("DebugDraw"))
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local QuinCore = ReplicatedStorage:WaitForChild("QuinCore")
local CombatConfig = require(QuinCore:WaitForChild("CombatConfig"))
local SpatialModule = require(QuinCore:WaitForChild("Modules"):WaitForChild("SpatialModule"))
local PlatformCatalogue = require(game:GetService("ReplicatedStorage"):WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("PlatformCatalogue"))

local RetreatTacticsModule = {}

-- Extract HRP helper for either Models or tables
local function getEntityHRP(entity)
	if not entity then return nil end
	if typeof(entity) == "Instance" then
		if entity:IsA("Model") then
			return entity:FindFirstChild("HumanoidRootPart")
		elseif entity:IsA("BasePart") and entity.Name == "HumanoidRootPart" then
			return entity
		end
	elseif typeof(entity) == "table" then
		if entity.model and typeof(entity.model) == "Instance" then
			return entity.model:FindFirstChild("HumanoidRootPart")
		elseif entity.HRP and typeof(entity.HRP) == "Instance" then
			return entity.HRP
		elseif entity.rootPart and typeof(entity.rootPart) == "Instance" then
			return entity.rootPart
		end
	end
	return nil
end

function RetreatTacticsModule.evaluate(fighter, enemies, allies, context)
	local rootPart = fighter:FindFirstChild("HumanoidRootPart")
	if not rootPart then
		return {
			objective = "OPEN_GROUND",
			targetPosition = Vector3.zero,
			steerDirection = Vector3.new(0, 0, -1),
			score = 0,
			isCornered = true,
			candidateScores = {},
		}
	end

	context = context or {}
	local myPos = rootPart.Position
	local myPosFlat = Vector3.new(myPos.X, 0, myPos.Z)

	-- Personality & Trait attributes
	local confidence = fighter:GetAttribute("CurrentConfidence") or (fighter:GetAttribute("Pers_Confidence") or 0.6)
	local mobility = fighter:GetAttribute("Pers_MobilityPreference") or 0.6
	local protectiveness = fighter:GetAttribute("Pers_Protectiveness") or 0.5
	local quirky = fighter:GetAttribute("Quirky") or "Balanced"
	local ownerId = fighter:GetAttribute("OwnerId") or "SERVER"

	-- Threat centroid (flat XZ)
	local enemyCentroid = Vector3.zero
	local enemyPositions = {}
	local enemyCount = 0
	if enemies and #enemies > 0 then
		for _, enemy in ipairs(enemies) do
			local eHRP = getEntityHRP(enemy)
			if eHRP then
				local ePos = Vector3.new(eHRP.Position.X, 0, eHRP.Position.Z)
				table.insert(enemyPositions, ePos)
				enemyCentroid = enemyCentroid + ePos
				enemyCount = enemyCount + 1
			end
		end
		if enemyCount > 0 then
			enemyCentroid = enemyCentroid / enemyCount
		end
	end

	-- Distance to nearest threat and closing speed
	local nearestEnemyDist = math.huge
	local primaryPursuer = nil
	local primaryPursuerHRP = nil
	if enemies and #enemies > 0 then
		for _, enemy in ipairs(enemies) do
			local eHRP = getEntityHRP(enemy)
			if eHRP then
				local d = (eHRP.Position - myPos).Magnitude
				if d < nearestEnemyDist then
					nearestEnemyDist = d
					primaryPursuer = enemy
					primaryPursuerHRP = eHRP
				end
			end
		end
	end

	-- Calculate closing speed of primary pursuer
	local closingSpeed = 0
	if primaryPursuerHRP then
		local disp = (myPos - primaryPursuerHRP.Position)
		local dispFlat = Vector3.new(disp.X, 0, disp.Z)
		if dispFlat.Magnitude > 0.1 then
			local dispDir = dispFlat.Unit
			local runnerVel = rootPart.AssemblyLinearVelocity
			local chaserVel = primaryPursuerHRP.AssemblyLinearVelocity
			local runnerForwardSpeed = runnerVel:Dot(dispDir)
			local chaserForwardSpeed = chaserVel:Dot(dispDir)
			closingSpeed = math.max(0, chaserForwardSpeed - runnerForwardSpeed)
		end
	end

	-- Distance-threat continuum phase classification
	local distanceThreatPhase = "SAFE_LEAD"
	if nearestEnemyDist <= 6.0 then
		distanceThreatPhase = "IMMINENT_ATTACK"
	elseif nearestEnemyDist <= 14.0 then
		distanceThreatPhase = "DANGER"
	elseif nearestEnemyDist <= 28.0 then
		distanceThreatPhase = "PURSUER_CLOSING"
	else
		distanceThreatPhase = "SAFE_LEAD"
	end

	-- Geometric Juke Cut: sharp lateral cut vector when pursuer is closing rapidly behind
	local now = tick()
	local lastJukeTime = fighter:GetAttribute("LastJukeTime") or 0
	local jukeDuration = CombatConfig.JukeDuration or 0.35
	local jukeCooldown = CombatConfig.JukeCooldown or 2.0
	local isCurrentlyJuking = (now - lastJukeTime) < jukeDuration
	local jukeDirection = nil

	if isCurrentlyJuking then
		local jx = fighter:GetAttribute("JukeDirX") or 0
		local jz = fighter:GetAttribute("JukeDirZ") or 0
		if math.abs(jx) > 0.01 or math.abs(jz) > 0.01 then
			jukeDirection = Vector3.new(jx, 0, jz).Unit
		end
	elseif (now - lastJukeTime) >= jukeCooldown and primaryPursuerHRP then
		local jukeDist = CombatConfig.JukeTriggerDistance or 14.0
		local jukeSpeedThresh = CombatConfig.JukeClosingSpeedThreshold or 5.0
		if nearestEnemyDist <= jukeDist and closingSpeed >= jukeSpeedThresh then
			local runnerLook = rootPart.CFrame.LookVector
			local runnerLookFlat = Vector3.new(runnerLook.X, 0, runnerLook.Z)
			if runnerLookFlat.Magnitude > 0.1 then
				runnerLookFlat = runnerLookFlat.Unit
				local disp = (myPos - primaryPursuerHRP.Position)
				local dispFlat = Vector3.new(disp.X, 0, disp.Z)
				if dispFlat.Magnitude > 0.1 then
					dispFlat = dispFlat.Unit
					-- Check if pursuer is chasing directly behind us
					if dispFlat:Dot(runnerLookFlat) > 0.60 then
						-- Evaluate left and right perpendicular vectors (90° lateral cuts)
						local cutL = Vector3.new(-runnerLookFlat.Z, 0, runnerLookFlat.X).Unit
						local cutR = Vector3.new(runnerLookFlat.Z, 0, -runnerLookFlat.X).Unit

						local rayParams = RaycastParams.new()
						rayParams.FilterDescendantsInstances = { fighter, primaryPursuerHRP.Parent }
						rayParams.FilterType = Enum.RaycastFilterType.Exclude

						local rayL = DebugDraw.raycast(fighter, myPos + Vector3.new(0, 1.5, 0), cutL * 15, rayParams)
						local rayR = DebugDraw.raycast(fighter, myPos + Vector3.new(0, 1.5, 0), cutR * 15, rayParams)
						local distL = rayL and (rayL.Position - myPos).Magnitude or 15
						local distR = rayR and (rayR.Position - myPos).Magnitude or 15

						-- Choose side with greater clearance
						local chosenCut = (distL >= distR) and cutL or cutR
						if math.max(distL, distR) >= 6.0 then
							isCurrentlyJuking = true
							jukeDirection = chosenCut
							fighter:SetAttribute("LastJukeTime", now)
							fighter:SetAttribute("JukeDirX", chosenCut.X)
							fighter:SetAttribute("JukeDirZ", chosenCut.Z)
							fighter:SetAttribute("JukeType", (distL >= distR) and "Left" or "Right")
						end
					end
				end
			end
		end
	end

	-- ============================================================
	-- ESCAPE PLAN
	-- ============================================================
	local arena = SpatialModule.getArenaBounds()
	local escapeDistance = math.clamp(arena.radius * (CombatConfig.Retreat_EscapeDistanceRatio or 0.5), 60, 220)
	local searchRange = math.clamp(arena.radius * (CombatConfig.Retreat_SearchRangeRatio or 0.4), 40, 160)
	local pursuerPos = primaryPursuerHRP and primaryPursuerHRP.Position or (enemyCount > 0 and Vector3.new(enemyCentroid.X, myPos.Y, enemyCentroid.Z) or nil)

	-- Keep destinations on the arena floor area
	local function insideArena(position)
		local margin = 20
		return Vector3.new(
			math.clamp(position.X, arena.center.X - arena.halfX + margin, arena.center.X + arena.halfX - margin),
			position.Y,
			math.clamp(position.Z, arena.center.Z - arena.halfZ + margin, arena.center.Z + arena.halfZ - margin))
	end

	-- Running there must not mean running at the pursuer
	local function leadsAway(position)
		if not pursuerPos then return true end
		local toPlace = Vector3.new(position.X - myPos.X, 0, position.Z - myPos.Z)
		local toPursuer = Vector3.new(pursuerPos.X - myPos.X, 0, pursuerPos.Z - myPos.Z)
		if toPlace.Magnitude < 1 or toPursuer.Magnitude < 1 then return true end
		return toPlace.Unit:Dot(toPursuer.Unit) < 0.3
	end

	local openGroundResult = SpatialModule.getSafeRetreatDirection(rootPart, enemies, allies,
		setmetatable({ RetreatSearchRadius = CombatConfig.Retreat_OpenGroundProbe or 60 }, { __index = CombatConfig }))

	local plan = context.plan
	local planExpired = true
	if plan then
		local toGoal = Vector3.new(plan.position.X - myPos.X, 0, plan.position.Z - myPos.Z)
		local cut = false
		if pursuerPos and toGoal.Magnitude > 1 then
			local toPursuer = Vector3.new(pursuerPos.X - myPos.X, 0, pursuerPos.Z - myPos.Z)
			cut = toPursuer.Magnitude < toGoal.Magnitude and toPursuer.Magnitude > 1 and toGoal.Unit:Dot(toPursuer.Unit) > 0.5
		end
		planExpired = toGoal.Magnitude <= (CombatConfig.Retreat_ArriveDistance or 10)
			or cut or context.stalled == true
			or (now - plan.time) >= (CombatConfig.Retreat_PlanHold or 4.0)
	end

	local candidateScores = plan and plan.scores or {}
	if planExpired then
		candidateScores = {}
		local options = {}

		-- BREAK_LOS: the nearest spot in each direction that hides it from the pursuer
		if pursuerPos then
			local best, bestValue = nil, -math.huge
			for _, cover in ipairs(SpatialModule.findCoverPositions(rootPart, pursuerPos, searchRange)) do
				if leadsAway(cover) then
					local value = (cover - pursuerPos).Magnitude - (cover - myPos).Magnitude * 0.6
					if value > bestValue then best, bestValue = cover, value end
				end
			end
			if best then
				local score = 45 + (mobility * 20) + (1.0 - confidence) * 15
				if quirky == "Ghost" or quirky == "Evasive" or quirky == "Ambusher" then
					score += 35
				elseif quirky == "Opportunist" or quirky == "Survivor" then
					score += 20
				end
				table.insert(options, { objective = "BREAK_LOS", position = best, score = score })
			end
		end

		-- TO_HIGH_GROUND: a platform to get onto. One within a jump's reach is run to and jumped
		-- onto; a higher one takes a projectile jump, so it is only an option with the energy for it.
		do
			local floorY = myPos.Y - (context.standHeight or 5.4)
			local canProjectileJump = context.canProjectileJump == true
			local best, bestValue = nil, -math.huge
			for _, found in ipairs(PlatformCatalogue.near(myPos, canProjectileJump and escapeDistance or searchRange)) do
				local access = PlatformCatalogue.accessFrom(found.platform, floorY)
				local rise = found.platform.topY - floorY
				local usable = access == PlatformCatalogue.Access.Jump or access == PlatformCatalogue.Access.Vault
					or (access == PlatformCatalogue.Access.ProjectileJump and canProjectileJump)
				if usable and leadsAway(found.point) then
					local value = math.min(rise, 30) * 2.0 - found.distance * 0.4
					if value > bestValue then
						best, bestValue = { platform = found.platform, access = access, rise = rise, distance = found.distance }, value
					end
				end
			end
			if best then
				local score = 25 + (math.min(best.rise, 20) * 1.8) + (mobility * 25)
				if quirky == "HighGround" or quirky == "Observer" or quirky == "Watcher" then
					score += 40
				elseif quirky == "Parkourist" or quirky == "Nuke" then
					score += 30
				end
				local humanoid = fighter:FindFirstChildOfClass("Humanoid")
				if humanoid and humanoid.Health / humanoid.MaxHealth < 0.30 then
					score += 25 -- high ground is a lifesaver when nearly down
				end
				table.insert(options, {
					objective = "TO_HIGH_GROUND",
					position = PlatformCatalogue.nearestTopPoint(best.platform, myPos, 4),
					score = score,
					platform = best.platform,
					access = best.access,
				})
			end
		end

		-- TO_ALLIES: friends who are somewhere else. Allies standing in this same fight are not
		-- an escape (running to them was a lap around the brawl).
		do
			local minDistance = CombatConfig.Retreat_AllyMinDistance or 40
			local nearestFar, nearestFarDist = nil, math.huge
			for _, ally in ipairs(allies or {}) do
				local allyRoot = getEntityHRP(ally)
				if allyRoot then
					local distance = (allyRoot.Position - myPos).Magnitude
					if distance >= minDistance and distance < nearestFarDist and leadsAway(allyRoot.Position) then
						nearestFar, nearestFarDist = allyRoot, distance
					end
				end
			end
			if nearestFar then
				local group = 0
				local hasSameOwnerAlly = false
				for _, ally in ipairs(allies) do
					local allyRoot = getEntityHRP(ally)
					if allyRoot and (allyRoot.Position - nearestFar.Position).Magnitude <= 30 then
						group += 1
						local allyModel = typeof(ally) == "Instance" and ally or ally.model
						if allyModel and allyModel:GetAttribute("OwnerId") == ownerId and ownerId ~= "SERVER" then
							hasSameOwnerAlly = true
						end
					end
				end
				local score = math.min(group * 18, 45) + math.clamp(1.0 - (nearestFarDist / 220), 0.15, 1.0) * 35 + (protectiveness * 20)
				if hasSameOwnerAlly then score += 35 end
				if quirky == "Follower" or quirky == "Wingman" then
					score += 30
				elseif quirky == "Bodyguard" or quirky == "Guardian" or quirky == "Safekeeper" then
					score += 25
				elseif quirky == "PackLeader" then
					score += 15
				elseif quirky == "LoneWolf" or quirky == "Egoist" then
					score -= 30 -- prefers to get away alone
				end
				if enemyCount == 1 and group >= 2 then
					score += 20 -- the pursuer runs into three
				end
				table.insert(options, { objective = "TO_ALLIES", position = nearestFar.Position, score = score })
			end
		end

		-- OPEN_GROUND: straight distance along the safest direction
		do
			local score = (openGroundResult.score or 0.5) * 45
			if openGroundResult.isCornered then score -= 40 end
			if quirky == "SpeedDemon" or quirky == "Momentum" then score += 20 end
			table.insert(options, { objective = "OPEN_GROUND", position = myPos + openGroundResult.direction * escapeDistance, score = score })
		end

		local best = nil
		for _, option in ipairs(options) do
			if not option.platform then
				option.position = insideArena(option.position)
			end
			candidateScores[option.objective] = option.score
			if not best or option.score > best.score then best = option end
		end
		plan = { objective = best.objective, position = best.position, score = best.score, scores = candidateScores, options = options, time = now,
			platform = best.platform, access = best.access }
	end

	local toGoal = Vector3.new(plan.position.X - myPos.X, 0, plan.position.Z - myPos.Z)
	local steerDir = toGoal.Magnitude > 0.1 and toGoal.Unit or openGroundResult.direction
	local isCornered = openGroundResult.isCornered and plan.objective == "OPEN_GROUND"

	-- Debug: every escape option of the current plan with its score; the chosen one in green
	if DebugDraw.isActive("Retreat", fighter) then
		for _, option in ipairs(plan.options) do
			local color = option.objective == plan.objective and Color3.fromRGB(80, 255, 140) or Color3.fromRGB(255, 190, 80)
			DebugDraw.line("Retreat", fighter, myPos, option.position, color)
			DebugDraw.sphere("Retreat", fighter, option.position, 1.2, color)
			DebugDraw.text("Retreat", fighter, option.position + Vector3.new(0, 2.5, 0), string.format("%s %.0f", option.objective, option.score), color)
		end
	end

	return {
		objective = plan.objective,
		targetPosition = plan.position,
		steerDirection = (isCurrentlyJuking and jukeDirection) and jukeDirection or steerDir,
		score = math.clamp(plan.score / 80.0, 0.05, 1.0),
		isCornered = isCornered,
		reason = isCornered and "CORNERED_DEAD_END" or plan.objective,
		candidateScores = candidateScores,
		plan = plan,
		distanceThreatPhase = distanceThreatPhase,
		closingSpeed = closingSpeed,
		nearestEnemyDist = nearestEnemyDist,
		primaryPursuer = primaryPursuer,
		isJuking = isCurrentlyJuking,
		jukeDirection = jukeDirection,
		maneuver = isCurrentlyJuking and "JUKE_CUT" or "CONTINUOUS_RUN",
	}
end

return RetreatTacticsModule
