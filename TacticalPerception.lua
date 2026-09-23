--// TacticalPerception.lua
-- Computes compact local battlefield awareness and situational state for AI decision making
-- All evaluation is bounded strictly within local sensory radius (45 studs)

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local QuinCore = ReplicatedStorage:WaitForChild("QuinCore")
local PersonalitySystem = require(QuinCore:WaitForChild("Modules"):WaitForChild("PersonalitySystem"))
local CombatConfig = require(QuinCore:WaitForChild("CombatConfig"))

local TacticalPerception = {
	LOCAL_RADIUS = 45,       -- Radius for direct local combat encounter reasoning
	AWARENESS_RADIUS = 90,   -- Radius for incoming reinforcements
}

-- Evaluate complete local tactical situation for a given Quin and optional target
function TacticalPerception.evaluate(quinModel, targetModel)
	if not quinModel or not quinModel.Parent then return nil end
	local myHRP = quinModel:FindFirstChild("HumanoidRootPart")
	local myHum = quinModel:FindFirstChildOfClass("Humanoid")
	if not myHRP or not myHum or myHum.Health <= 0 then return nil end

	local myPos = myHRP.Position
	local myTeam = quinModel:GetAttribute("Team") or "None"

	local nearbyAllies = {}
	local nearbyEnemies = {}
	local nearestAllyDist = math.huge
	local nearestEnemyDist = math.huge
	local nearestEnemyModel = nil
	local nearestAllyModel = nil

	local totalLivingAllies = 0
	local totalLivingEnemies = 0
	local nearestGlobalAllyDist = math.huge
	local nearestGlobalAllyModel = nil

	local distressedAlly = nil
	local nearbyAllyNeedsHelp = false

	-- Scan all living Quins in the arena
	local allQuins = CollectionService:GetTagged("Quin")
	if #allQuins == 0 then
		local serverFolder = workspace:FindFirstChild("QuinServer") or workspace
		allQuins = serverFolder:GetChildren()
	end

	for _, other in ipairs(allQuins) do
		if other:IsA("Model") and other ~= quinModel and other.Parent then
			local oHum = other:FindFirstChildOfClass("Humanoid")
			local oHRP = other:FindFirstChild("HumanoidRootPart")
			if oHum and oHum.Health > 0 and oHRP then
				local oTeam = other:GetAttribute("Team") or "None"
				local isAlly = (myTeam ~= "None" and myTeam == oTeam)

				-- Sacred Showdown Filter (Tradition & Anti-Bully)
				local myRole = quinModel:GetAttribute("LeaderShowdownRole")
				local oRole = other:GetAttribute("LeaderShowdownRole")
				if myRole == "Duelist" and oRole ~= "Duelist" then
					-- Spectators and transitions are neutral observers, not combatants or threats
					continue
				elseif oRole == "PerimeterGuard" or oRole == "Transition" then
					continue
				end

				local dist = (oHRP.Position - myPos).Magnitude
				local oHpRatio = oHum.Health / oHum.MaxHealth
				local oEnergy = other:GetAttribute("Energy") or 100
				local oMaxEnergy = other:GetAttribute("MaxEnergy") or 100
				local oEnergyRatio = math.clamp(oEnergy / oMaxEnergy, 0, 1)

				if isAlly then
					totalLivingAllies = totalLivingAllies + 1
					if dist < nearestGlobalAllyDist then
						nearestGlobalAllyDist = dist
						nearestGlobalAllyModel = other
					end

					if dist < nearestAllyDist then
						nearestAllyDist = dist
						nearestAllyModel = other
					end
					if dist <= TacticalPerception.LOCAL_RADIUS then
						local entry = {
							model = other,
							distance = dist,
							healthRatio = oHpRatio,
							energyRatio = oEnergyRatio,
						}
						table.insert(nearbyAllies, entry)

						-- Detect if this ally is in distress / needs rescue
						if oHpRatio <= 0.35 and not distressedAlly then
							distressedAlly = other
							nearbyAllyNeedsHelp = true
						end
					end
				else
					totalLivingEnemies = totalLivingEnemies + 1
					if dist < nearestEnemyDist then
						nearestEnemyDist = dist
						nearestEnemyModel = other
					end
					if dist <= TacticalPerception.LOCAL_RADIUS then
						table.insert(nearbyEnemies, {
							model = other,
							distance = dist,
							healthRatio = oHpRatio,
							energyRatio = oEnergyRatio,
							isAuraFarming = (other:GetAttribute("IsAuraFarming") == true),
						})
					end
				end
			end
		end
	end

	local allyCount = #nearbyAllies
	local enemyCount = #nearbyEnemies

	-- Local Numerical Ratio: (allies + self) / max(1, enemies)
	local localAdvantageRatio = (allyCount + 1) / math.max(1, enemyCount)

	-- Directional Threat Breakdown & Quadrant Analysis (Phase 2)
	local frontEnemies = {}
	local flankEnemies = {}
	local flankLeftEnemies = {}
	local flankRightEnemies = {}
	local rearEnemies = {}

	local lookVec = myHRP.CFrame.LookVector
	local rightVec = myHRP.CFrame.RightVector

	for _, entry in ipairs(nearbyEnemies) do
		local eModel = entry.model
		local eHRP = eModel:FindFirstChild("HumanoidRootPart")
		if eHRP then
			local diff = Vector3.new(eHRP.Position.X - myPos.X, 0, eHRP.Position.Z - myPos.Z)
			local d = diff.Magnitude
			local dir = (d > 0.01) and (diff / d) or lookVec
			
			local dotForward = lookVec:Dot(dir)
			local dotRight = rightVec:Dot(dir)
			
			entry.dotForward = dotForward
			entry.dotRight = dotRight

			if dotForward >= 0.5 then
				entry.quadrant = "Front"
				table.insert(frontEnemies, entry)
			elseif dotForward <= -0.45 then
				entry.quadrant = "Rear"
				table.insert(rearEnemies, entry)
			else
				if dotRight > 0 then
					entry.quadrant = "FlankRight"
					table.insert(flankRightEnemies, entry)
				else
					entry.quadrant = "FlankLeft"
					table.insert(flankLeftEnemies, entry)
				end
				table.insert(flankEnemies, entry)
			end
		end
	end

	-- Multi-Quadrant Surrounded Evaluation (True 360 surround requires >= 3 occupied sectors)
	local occupiedQuadrants = 0
	if #frontEnemies > 0 then occupiedQuadrants = occupiedQuadrants + 1 end
	if #flankLeftEnemies > 0 then occupiedQuadrants = occupiedQuadrants + 1 end
	if #flankRightEnemies > 0 then occupiedQuadrants = occupiedQuadrants + 1 end
	if #rearEnemies > 0 then occupiedQuadrants = occupiedQuadrants + 1 end

	local surroundThreshold = CombatConfig.SurroundedQuadrantThreshold or 3
	local isSurrounded = (enemyCount >= 3 and occupiedQuadrants >= surroundThreshold)

	-- Personality-Driven Rear Threat Detection
	local awareness = quinModel:GetAttribute("Pers_Awareness") or 0.65
	local maxRearRange = CombatConfig.RearThreatDetectionRange or 22.0
	local rearDetectDist = 8.0 + (awareness * (maxRearRange - 8.0))

	local isUnderRearThreat = false
	local closestRearThreat = nil
	local closestRearThreatDist = math.huge

	for _, entry in ipairs(rearEnemies) do
		if entry.distance <= rearDetectDist then
			isUnderRearThreat = true
			if entry.distance < closestRearThreatDist then
				closestRearThreatDist = entry.distance
				closestRearThreat = entry.model
			end
		end
	end

	-- Focus & Bullying Detection: How many enemies are actively targeting ME?
	local enemiesFocusingMe = {}
	for _, other in ipairs(allQuins) do
		if other:IsA("Model") and other ~= quinModel and other.Parent then
			local oTeam = other:GetAttribute("Team") or "None"
			if myTeam == "None" or myTeam ~= oTeam then
				local oTarget = other:GetAttribute("CurrentTarget") or other:GetAttribute("TargetQuin")
				if oTarget == quinModel.Name then
					local oHRP = other:FindFirstChild("HumanoidRootPart")
					local dist = oHRP and (oHRP.Position - myPos).Magnitude or 50
					if dist <= 40 then
						table.insert(enemiesFocusingMe, other)
					end
				end
			end
		end
	end
	local isBeingBullied = (#enemiesFocusingMe >= (CombatConfig.BulliedFocusThreshold or 2))

	quinModel:SetAttribute("IsUnderRearThreat", isUnderRearThreat)
	quinModel:SetAttribute("ClosestRearThreat", closestRearThreat and closestRearThreat.Name or "")
	quinModel:SetAttribute("ClosestRearThreatDist", closestRearThreatDist < math.huge and closestRearThreatDist or 0)
	quinModel:SetAttribute("BeingBullied", isBeingBullied)
	quinModel:SetAttribute("FocusCount", #enemiesFocusingMe)
	quinModel:SetAttribute("OccupiedQuadrants", occupiedQuadrants)

	-- Phase 6: Telemetry — AwarenessLevel & ThreatZone (Front/Flank/Rear)
	quinModel:SetAttribute("AwarenessLevel", awareness)
	local threatZone = "Front"
	if nearestEnemyModel then
		for _, e in ipairs(nearbyEnemies) do
			if e.model == nearestEnemyModel and e.quadrant then
				if e.quadrant == "FlankLeft" or e.quadrant == "FlankRight" then
					threatZone = "Flank"
				else
					threatZone = e.quadrant
				end
				break
			end
		end
	end
	quinModel:SetAttribute("ThreatZone", threatZone)

	-- Phase 3: Safe Haven Radial Evaluation
	local SpatialModule = require(QuinCore:WaitForChild("Modules"):WaitForChild("SpatialModule"))
	local retreatResult = SpatialModule.getSafeRetreatDirection(myHRP, nearbyEnemies, nearbyAllies, CombatConfig)
	quinModel:SetAttribute("RetreatScore", math.round(retreatResult.score * 100) / 100)
	quinModel:SetAttribute("IsCornered", retreatResult.isCornered)

	-- OB / Surroundings awareness (vertical navigation)
	local overheadPlatform = SpatialModule.findReachableOverheadPlatform(myHRP, CombatConfig.HighGroundJumpReach or 14)
	local isOnElevatedPlatform, _ = SpatialModule.isOnElevatedPlatform(myHRP, CombatConfig.ElevatedPlatformThreshold or 6.0)
	quinModel:SetAttribute("HasOverheadPlatform", overheadPlatform ~= nil)
	quinModel:SetAttribute("IsOnElevatedPlatform", isOnElevatedPlatform)

	-- Self Isolation: no allies nearby while enemies present or ally too far (> 60 studs)
	local isSelfIsolated = (allyCount == 0 and enemyCount >= 1) or (nearestAllyDist > 65 and enemyCount >= 1)
	local isOutnumbered = (enemyCount > allyCount + 1) or (localAdvantageRatio < 0.65)

	-- Target situation evaluation
	local targetInfo = nil
	local isTargetIsolated = false
	local targetHealthRatio = 1.0
	local distanceToTarget = 0

	local activeTarget = targetModel or nearestEnemyModel
	if activeTarget and activeTarget.Parent then
		local tHRP = activeTarget:FindFirstChild("HumanoidRootPart")
		local tHum = activeTarget:FindFirstChildOfClass("Humanoid")
		if tHRP and tHum and tHum.Health > 0 then
			local tPos = tHRP.Position
			local tTeam = activeTarget:GetAttribute("Team") or "None"
			local targetAlliesCount = 0

			for _, other in ipairs(allQuins) do
				if other:IsA("Model") and other ~= activeTarget and other.Parent then
					local oHum = other:FindFirstChildOfClass("Humanoid")
					local oHRP = other:FindFirstChild("HumanoidRootPart")
					if oHum and oHum.Health > 0 and oHRP then
						local dist = (oHRP.Position - tPos).Magnitude
						local oTeam = other:GetAttribute("Team") or "None"
						if oTeam ~= "None" and oTeam == tTeam and dist <= TacticalPerception.LOCAL_RADIUS then
							targetAlliesCount = targetAlliesCount + 1
						end
					end
				end
			end

			isTargetIsolated = (targetAlliesCount == 0)
			targetHealthRatio = tHum.Health / tHum.MaxHealth
			distanceToTarget = (tHRP.Position - myPos).Magnitude

			targetInfo = {
				model = activeTarget,
				distance = distanceToTarget,
				healthRatio = targetHealthRatio,
				isIsolated = isTargetIsolated,
				alliesCount = targetAlliesCount,
			}
		end
	end

	-- Resource Ratios
	local ownHealthRatio = myHum.Health / myHum.MaxHealth
	local energy = quinModel:GetAttribute("Energy") or 100
	local maxEnergy = quinModel:GetAttribute("MaxEnergy") or 100
	local ownEnergyRatio = math.clamp(energy / maxEnergy, 0, 1)

	-- Dynamic Confidence evaluation
	local baseConfidence = quinModel:GetAttribute("Pers_Confidence") or 0.6
	local currentConfidence = PersonalitySystem.computeEffectiveConfidence(baseConfidence, ownHealthRatio, localAdvantageRatio)
	quinModel:SetAttribute("CurrentConfidence", currentConfidence)

	-- Threat Level evaluation: 0 to 100
	local threatLevel = math.clamp((enemyCount * 25) + ((1 - ownHealthRatio) * 35) + (isSelfIsolated and 25 or 0) - (allyCount * 15), 0, 100)

	-- Phase 13: Global Team Battle State & Survival Dynamics
	local isSoleSurvivor = (myTeam ~= "None" and totalLivingAllies == 0)
	local totalCombatants = totalLivingAllies + totalLivingEnemies + 1
	local teamSurvivalRatio = (totalLivingAllies + 1) / math.max(1, totalCombatants)

	-- Identify Primary Pursuer and Closing Speed
	local primaryPursuer = nil
	local highestClosingSpeed = 0
	local primaryPursuerDist = math.huge
	local myVel = myHRP.AssemblyLinearVelocity

	for _, entry in ipairs(nearbyEnemies) do
		local eModel = entry.model
		local eHRP = eModel:FindFirstChild("HumanoidRootPart")
		if eHRP then
			local toMe = (myPos - eHRP.Position)
			local dist = toMe.Magnitude
			local eVel = eHRP.AssemblyLinearVelocity
			local closingVel = 0
			if dist > 0.1 then
				closingVel = (eVel - myVel):Dot(toMe.Unit)
			end
			local isTargetingMe = (eModel:GetAttribute("TargetQuin") == quinModel.Name or eModel:GetAttribute("CurrentTarget") == quinModel.Name)
			if (closingVel > 0 or isTargetingMe) and dist < primaryPursuerDist then
				primaryPursuerDist = dist
				highestClosingSpeed = math.max(0, closingVel)
				primaryPursuer = eModel
			end
		end
	end

	-- Check if a reinforcing ally is approaching to defend/rescue
	local reinforcingAllyApproaching = false
	if nearestGlobalAllyDist <= (CombatConfig.DefendDelayDistance or 35.0) and nearestGlobalAllyModel then
		local aHRP = nearestGlobalAllyModel:FindFirstChild("HumanoidRootPart")
		if aHRP then
			local toMe = (myPos - aHRP.Position)
			if toMe.Magnitude > 0.1 and aHRP.AssemblyLinearVelocity:Dot(toMe.Unit) > 3.0 then
				reinforcingAllyApproaching = true
			end
		end
	end

	-- Escape Feasibility (0.05 to 1.0)
	local myMaxSpeed = quinModel:GetAttribute("Speed") or 40
	local chaserMaxSpeed = (primaryPursuer and (primaryPursuer:GetAttribute("Speed") or 40)) or 40
	local speedRatio = math.clamp(myMaxSpeed / math.max(15, chaserMaxSpeed), 0.5, 1.5)
	local energyFactor = math.clamp(ownEnergyRatio, 0.1, 1.0)

	local havenScore = 0.5
	if nearestGlobalAllyDist <= 60 then
		havenScore = havenScore + 0.35
	elseif nearestGlobalAllyDist <= 120 then
		havenScore = havenScore + 0.15
	elseif nearestGlobalAllyDist > 180 or isSoleSurvivor then
		havenScore = havenScore - 0.35
	end

	if overheadPlatform or isOnElevatedPlatform then
		havenScore = havenScore + 0.20
	end

	local escapeFeasibility = (speedRatio * 0.35) + (energyFactor * 0.25) + (havenScore * 0.40)
	if isSurrounded then
		escapeFeasibility = escapeFeasibility - 0.30
	end
	if isSoleSurvivor then
		escapeFeasibility = escapeFeasibility - (totalLivingEnemies >= 2 and 0.45 or 0.25)
		if ownHealthRatio < 0.40 then
			escapeFeasibility = escapeFeasibility - 0.20
		end
	end
	if ownHealthRatio < 0.25 and primaryPursuerDist < 14 and highestClosingSpeed > 4 then
		escapeFeasibility = escapeFeasibility - 0.35
	end
	if retreatResult.isCornered then
		escapeFeasibility = 0.05
	end
	escapeFeasibility = math.clamp(escapeFeasibility, 0.05, 1.0)

	-- Battle Life Value (0.0 to 1.0)
	local battleLifeValue = 1.0
	if isSoleSurvivor and totalLivingEnemies >= 2 then
		battleLifeValue = 0.15 -- Sole survivor fighting overwhelming team: value of fleeing is minimal
	elseif totalLivingAllies >= 2 then
		battleLifeValue = 0.90 -- Team is strong: staying alive to regroup is critical
	elseif totalLivingAllies == 1 then
		battleLifeValue = 0.65
	else
		battleLifeValue = 0.45
	end

	quinModel:SetAttribute("EscapeFeasibility", math.round(escapeFeasibility * 100) / 100)
	quinModel:SetAttribute("BattleLifeValue", math.round(battleLifeValue * 100) / 100)
	quinModel:SetAttribute("IsSoleSurvivor", isSoleSurvivor)
	quinModel:SetAttribute("TotalLivingAllies", totalLivingAllies)
	quinModel:SetAttribute("TotalLivingEnemies", totalLivingEnemies)
	quinModel:SetAttribute("NearestGlobalAllyDist", nearestGlobalAllyDist < math.huge and math.round(nearestGlobalAllyDist*10)/10 or 999)
	quinModel:SetAttribute("ReinforcingAllyApproaching", reinforcingAllyApproaching)

	-- Structured canonical state matching specification
	local state = {
		-- Canonical Specification Fields
		NearbyAllies = nearbyAllies,
		NearbyEnemies = nearbyEnemies,
		AllyCount = allyCount,
		EnemyCount = enemyCount,
		LocalNumericalRatio = localAdvantageRatio,
		NearestEnemy = nearestEnemyModel,
		BestTarget = activeTarget,
		SelfHealthPercent = ownHealthRatio,
		SelfResourcePercent = ownEnergyRatio,
		TargetHealthPercent = targetHealthRatio,
		Isolated = isSelfIsolated,
		TargetIsolated = isTargetIsolated,
		Outnumbered = isOutnumbered,
		Surrounded = isSurrounded,
		NearbyAllyNeedsHelp = nearbyAllyNeedsHelp,
		DistressedAlly = distressedAlly,
		ThreatLevel = threatLevel,

		-- Phase 13 Survival Decision & Battle Census Fields
		TotalLivingAllies = totalLivingAllies,
		TotalLivingEnemies = totalLivingEnemies,
		IsSoleSurvivor = isSoleSurvivor,
		TeamSurvivalRatio = teamSurvivalRatio,
		NearestGlobalAllyDist = nearestGlobalAllyDist,
		ReinforcingAllyApproaching = reinforcingAllyApproaching,
		PrimaryPursuer = primaryPursuer,
		ClosingSpeed = highestClosingSpeed,
		EscapeFeasibility = escapeFeasibility,
		BattleLifeValue = battleLifeValue,

		-- Directional & 360 Awareness Fields (Phase 2)
		FrontEnemies = frontEnemies,
		FlankEnemies = flankEnemies,
		RearEnemies = rearEnemies,
		FlankLeftEnemies = flankLeftEnemies,
		FlankRightEnemies = flankRightEnemies,
		OccupiedQuadrants = occupiedQuadrants,
		IsUnderRearThreat = isUnderRearThreat,
		ClosestRearThreat = closestRearThreat,
		ClosestRearThreatDist = closestRearThreatDist < math.huge and closestRearThreatDist or 0,
		BeingBullied = isBeingBullied,
		FocusCount = #enemiesFocusingMe,
		EnemiesFocusingMe = enemiesFocusingMe,

		-- Safe Haven & Retreat Quality (Phase 3)
		SafeRetreatDirection = retreatResult.direction,
		SafeRetreatScore = retreatResult.score,
		IsCornered = retreatResult.isCornered,

		-- OB / Surroundings awareness (vertical navigation)
		HasOverheadPlatform = (overheadPlatform ~= nil),
		OverheadPlatformTopY = overheadPlatform and overheadPlatform.topY or 0,
		IsOnElevatedPlatform = isOnElevatedPlatform,

		-- Phase 9: Dynamic Team Roles & Coordination
		TeamRole = (function()
			local tcs = require(QuinCore:WaitForChild("Modules"):WaitForChild("TeamCoordinationSystem"))
			local r = tcs.evaluateRole(quinModel, nearbyAllies, nearbyEnemies, { DistressedAlly = distressedAlly })
			return r
		end)(),
		TeamFocusTarget = (function()
			local tcs = require(QuinCore:WaitForChild("Modules"):WaitForChild("TeamCoordinationSystem"))
			return tcs.getTeamFocusTarget(quinModel)
		end)(),

		-- Backward-compatibility aliases for existing modules/tests
		myModel = quinModel,
		myPosition = myPos,
		ownHealthRatio = ownHealthRatio,
		ownEnergyRatio = ownEnergyRatio,
		baseConfidence = baseConfidence,
		currentConfidence = currentConfidence,
		nearbyAlliesCount = allyCount,
		nearbyEnemiesCount = enemyCount,
		localAdvantageRatio = localAdvantageRatio,
		isSelfIsolated = isSelfIsolated,
		nearestAllyDist = nearestAllyDist,
		nearestEnemyDist = nearestEnemyDist,
		targetInfo = targetInfo,
	}

	return state
end

return TacticalPerception
