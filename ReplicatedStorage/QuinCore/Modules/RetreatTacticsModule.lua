--// RetreatTacticsModule.lua
-- Multi-candidate tactical disengagement evaluator for Quins
-- Evaluates 4 distinct escape objectives:
-- 1. TO_ALLIES (Pulling enemies into an ally ambush / pair hunting)
-- 2. TO_HIGH_GROUND (Elevated platforms / rooftops for vertical escape)
-- 3. BREAK_LOS (Obstacle cover to break visual pursuit)
-- 4. OPEN_GROUND (Pure distance evasion away from threat centroid)
-- Biased by Personality, Class, Quirks, and Owner-Family Bonds (Master Project Plan Sections 28-31, 41, 51)

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local QuinCore = ReplicatedStorage:WaitForChild("QuinCore")
local CombatConfig = require(QuinCore:WaitForChild("CombatConfig"))
local SpatialModule = require(QuinCore:WaitForChild("Modules"):WaitForChild("SpatialModule"))

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
	local aggression = fighter:GetAttribute("Pers_Aggression") or 0.6
	local confidence = fighter:GetAttribute("CurrentConfidence") or (fighter:GetAttribute("Pers_Confidence") or 0.6)
	local mobility = fighter:GetAttribute("Pers_MobilityPreference") or 0.6
	local protectiveness = fighter:GetAttribute("Pers_Protectiveness") or 0.5
	local retreatTendency = fighter:GetAttribute("Pers_RetreatTendency") or 0.3
	local quirky = fighter:GetAttribute("Quirky") or "Balanced"
	local ownerId = fighter:GetAttribute("OwnerId") or "SERVER"
	local qType = fighter:GetAttribute("QuinType") or "TypeA"

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

						local rayL = Workspace:Raycast(myPos + Vector3.new(0, 1.5, 0), cutL * 15, rayParams)
						local rayR = Workspace:Raycast(myPos + Vector3.new(0, 1.5, 0), cutR * 15, rayParams)
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

	local candidateScores = {}

	-- ============================================================
	-- 1. CANDIDATE: TO_ALLIES (Ambush trap / Sibling bond regroup)
	-- ============================================================
	local allyScore = -100
	local bestAllyPos = nil
	if allies and #allies > 0 then
		local allyCentroid = Vector3.zero
		local validAllies = 0
		local hasSameOwnerAlly = false
		local nearestAllyDist = math.huge

		for _, ally in ipairs(allies) do
			local aHRP = getEntityHRP(ally)
			if aHRP then
				local aPos = aHRP.Position
				local aDist = (aPos - myPos).Magnitude
				if aDist < nearestAllyDist then nearestAllyDist = aDist end

				allyCentroid = allyCentroid + aPos
				validAllies = validAllies + 1

				-- Check same-owner sibling bond
				local aModel = typeof(ally) == "Instance" and ally or ally.model
				if aModel and aModel:GetAttribute("OwnerId") == ownerId and ownerId ~= "SERVER" then
					hasSameOwnerAlly = true
				end
			end
		end

		if validAllies > 0 then
			allyCentroid = allyCentroid / validAllies
			bestAllyPos = allyCentroid

			-- Base ally score: increases with ally count and healthy proximity (15 to 60 studs)
			local countBonus = math.min(validAllies * 18, 45)
			local distFactor = math.clamp(1.0 - (nearestAllyDist / 80), 0.1, 1.0) * 30
			allyScore = countBonus + distFactor + (protectiveness * 20)

			-- Quirky & Bond modulations
			if hasSameOwnerAlly then
				allyScore = allyScore + 35 -- Sibling bond: "Look at my two Quins working together!"
			end
			if quirky == "Follower" or quirky == "Wingman" then
				allyScore = allyScore + 30
			elseif quirky == "Bodyguard" or quirky == "Guardian" or quirky == "Safekeeper" then
				allyScore = allyScore + 25
			elseif quirky == "PackLeader" then
				allyScore = allyScore + 15
			elseif quirky == "LoneWolf" or quirky == "Egoist" then
				allyScore = allyScore - 30 -- Prefers solo escape
			end

			-- Tactical trap bonus: if pursuer is outnumbered when we reach allies
			if enemyCount == 1 and validAllies >= 2 then
				allyScore = allyScore + 20 -- 1v1 becomes 3v1 ambush
			end
		end
	end
	candidateScores["TO_ALLIES"] = allyScore

	-- ============================================================
	-- 2. CANDIDATE: TO_HIGH_GROUND (Elevated platform / rooftop)
	-- ============================================================
	local highGroundScore = -100
	local bestPlatformPos = nil
	local platforms = SpatialModule.findNearbyPlatforms(rootPart, 50, 4.0, 26.0)
	if platforms and #platforms > 0 then
		local bestPlat = nil
		local bestPlatVal = -math.huge
		for _, plat in ipairs(platforms) do
			local pDist = (plat.position - myPos).Magnitude
			local heightAdv = plat.heightDiff
			-- Prefer platforms between 6 and 18 studs high that are reachable within 12-40 studs
			local val = (heightAdv * 2.0) - (pDist * 0.8)
			if val > bestPlatVal then
				bestPlatVal = val
				bestPlat = plat
			end
		end

		if bestPlat then
			bestPlatformPos = bestPlat.position
			highGroundScore = 25 + (bestPlat.heightDiff * 1.8) + (mobility * 25)

			-- Quirky & Class modulations
			if quirky == "HighGround" or quirky == "Observer" or quirky == "Watcher" then
				highGroundScore = highGroundScore + 40
			elseif quirky == "Parkourist" or quirky == "Nuke" then
				highGroundScore = highGroundScore + 30
			elseif qType == "TypeC" then -- Assassin: loves vertical shortcuts
				highGroundScore = highGroundScore + 25
			elseif qType == "TypeB" then -- Tanker: heavy, less vertical
				highGroundScore = highGroundScore - 15
			end

			-- High ground is a lifesaver when heavily pressured or low HP
			local hpRatio = 1.0
			local hum = fighter:FindFirstChildOfClass("Humanoid")
			if hum then hpRatio = hum.Health / hum.MaxHealth end
			if hpRatio < 0.30 then
				highGroundScore = highGroundScore + 25
			end
		end
	end
	candidateScores["TO_HIGH_GROUND"] = highGroundScore

	-- ============================================================
	-- 3. CANDIDATE: BREAK_LOS (Obstacle cover / Corner break)
	-- ============================================================
	local coverScore = -100
	local bestCoverPos = nil
	local coverPositions = SpatialModule.findCoverPositions(rootPart, enemyCentroid, 35)
	if coverPositions and #coverPositions > 0 then
		local bestCov = nil
		local bestCovVal = -math.huge
		for _, cov in ipairs(coverPositions) do
			local cDist = (cov - myPos).Magnitude
			-- Reward close cover that is away from enemy centroid
			local awayFromEnemy = (cov - enemyCentroid).Magnitude
			local val = awayFromEnemy - (cDist * 0.6)
			if val > bestCovVal then
				bestCovVal = val
				bestCov = cov
			end
		end

		if bestCov then
			bestCoverPos = bestCov
			coverScore = 30 + (mobility * 20) + (1.0 - confidence) * 15

			-- Quirky modulations
			if quirky == "Ghost" or quirky == "Evasive" or quirky == "Ambusher" then
				coverScore = coverScore + 35
			elseif quirky == "Opportunist" or quirky == "Survivor" then
				coverScore = coverScore + 20
			end
		end
	end
	candidateScores["BREAK_LOS"] = coverScore

	-- ============================================================
	-- 4. CANDIDATE: OPEN_GROUND (Distance gain away from threat)
	-- ============================================================
	local openGroundResult = SpatialModule.getSafeRetreatDirection(rootPart, enemies, allies, CombatConfig)
	local openGroundScore = (openGroundResult.score or 0.5) * 45
	if openGroundResult.isCornered then
		openGroundScore = openGroundScore - 40
	end
	if quirky == "SpeedDemon" or quirky == "Momentum" then
		openGroundScore = openGroundScore + 20
	end
	candidateScores["OPEN_GROUND"] = openGroundScore

	-- ============================================================
	-- TACTICAL ARBITRATION: PICK HIGHEST-SCORING OBJECTIVE
	-- ============================================================
	local bestObj = "OPEN_GROUND"
	local bestVal = openGroundScore
	local targetPos = myPos + (openGroundResult.direction * 35)

	if highGroundScore > bestVal and bestPlatformPos then
		bestVal = highGroundScore
		bestObj = "TO_HIGH_GROUND"
		targetPos = bestPlatformPos
	end

	if allyScore > bestVal and bestAllyPos then
		bestVal = allyScore
		bestObj = "TO_ALLIES"
		targetPos = bestAllyPos
	end

	if coverScore > bestVal and bestCoverPos then
		bestVal = coverScore
		bestObj = "BREAK_LOS"
		targetPos = bestCoverPos
	end

	-- Compute steering direction towards targetPos
	local steerDir = (targetPos - myPos)
	local steerFlat = Vector3.new(steerDir.X, 0, steerDir.Z)
	if steerFlat.Magnitude > 0.1 then
		steerDir = steerFlat.Unit
	else
		steerDir = openGroundResult.direction
	end

	-- Check if completely cornered
	local isCornered = openGroundResult.isCornered or (bestVal < 10 and (not bestAllyPos) and (not bestPlatformPos) and (not bestCoverPos))

	-- If actively juking, steer toward the lateral juke vector
	local finalSteerDir = (isCurrentlyJuking and jukeDirection) and jukeDirection or steerDir

	return {
		objective = bestObj,
		targetPosition = targetPos,
		steerDirection = finalSteerDir,
		score = math.clamp(bestVal / 80.0, 0.05, 1.0),
		isCornered = isCornered,
		reason = isCornered and "CORNERED_DEAD_END" or bestObj,
		candidateScores = candidateScores,
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
