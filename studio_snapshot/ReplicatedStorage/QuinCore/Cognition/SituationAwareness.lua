--// Cognition.SituationAwareness
-- What is happening around the Quin and what it means for it: the local balance of numbers,
-- where the threats stand relative to its facing, who is hunting it, whether it could get
-- away, how its team is doing. Built only from what the Quin knows (its contacts), its own
-- condition and its surroundings - never from the world directly.
-- Returns the tactical context consumed by TargetingModule, DecisionSystem and the states.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local QuinCore = ReplicatedStorage:WaitForChild("QuinCore")
local CombatConfig = require(QuinCore:WaitForChild("CombatConfig"))
local PersonalitySystem = require(QuinCore:WaitForChild("Modules"):WaitForChild("PersonalitySystem"))
local TeamCoordinationSystem = require(QuinCore:WaitForChild("Modules"):WaitForChild("TeamCoordinationSystem"))

local SituationAwareness = {
	LOCAL_RADIUS = 45, -- direct local combat encounter
}

local CLOSE_PRESENCE = 10.0 -- an enemy this close counts as a threat even without line of sight

-- Contacts inside the local combat radius
function SituationAwareness.nearby(contacts)
	local allies, enemies = {}, {}
	for _, contact in ipairs(contacts.allies) do
		if contact.distance <= SituationAwareness.LOCAL_RADIUS then table.insert(allies, contact) end
	end
	for _, contact in ipairs(contacts.enemies) do
		if contact.distance <= SituationAwareness.LOCAL_RADIUS then table.insert(enemies, contact) end
	end
	return allies, enemies
end

local function nearest(list)
	local best = nil
	for _, contact in ipairs(list) do
		if not best or contact.distance < best.distance then best = contact end
	end
	return best
end

-- Where each active threat stands relative to the Quin's facing
local function quadrants(rootPart, myPos, nearbyEnemies)
	local front, flank, flankLeft, flankRight, rear = {}, {}, {}, {}, {}
	local lookVec = rootPart.CFrame.LookVector
	local rightVec = rootPart.CFrame.RightVector
	for _, entry in ipairs(nearbyEnemies) do
		-- Occlusion awareness: enemies behind solid walls do not count as a directional threat
		if entry.hasLineOfSight or entry.distance <= CLOSE_PRESENCE then
			local diff = Vector3.new(entry.position.X - myPos.X, 0, entry.position.Z - myPos.Z)
			local dir = diff.Magnitude > 0.01 and diff.Unit or lookVec
			entry.dotForward = lookVec:Dot(dir)
			entry.dotRight = rightVec:Dot(dir)
			if entry.dotForward >= 0.5 then
				entry.quadrant = "Front"
				table.insert(front, entry)
			elseif entry.dotForward <= -0.45 then
				entry.quadrant = "Rear"
				table.insert(rear, entry)
			else
				entry.quadrant = entry.dotRight > 0 and "FlankRight" or "FlankLeft"
				table.insert(entry.dotRight > 0 and flankRight or flankLeft, entry)
				table.insert(flank, entry)
			end
		end
	end
	return front, flank, flankLeft, flankRight, rear
end

-- census: { totalLivingAllies, totalLivingEnemies } (the team always knows the score)
function SituationAwareness.assess(quinModel, rootPart, self, contacts, nearbyAllies, nearbyEnemies, environment, census, targetModel)
	local myPos = rootPart.Position
	local myTeam = quinModel:GetAttribute("Team") or "None"

	local allyCount = #nearbyAllies
	local enemyCount = #nearbyEnemies
	local nearestAlly = nearest(contacts.allies)
	local nearestEnemy = nearest(contacts.enemies)
	local nearestAllyDist = nearestAlly and nearestAlly.distance or math.huge
	local nearestEnemyDist = nearestEnemy and nearestEnemy.distance or math.huge

	-- An ally in trouble close by
	local distressedAlly = nil
	for _, ally in ipairs(nearbyAllies) do
		if ally.healthRatio <= 0.35 then
			distressedAlly = ally.model
			break
		end
	end

	-- Local numerical ratio: (allies + self) / active threats (seen, or point-blank)
	local activeEnemyCount = 0
	for _, enemy in ipairs(nearbyEnemies) do
		if enemy.hasLineOfSight or enemy.distance <= CLOSE_PRESENCE then
			activeEnemyCount += 1
		end
	end
	local localAdvantageRatio = (allyCount + 1) / math.max(1, activeEnemyCount)

	-- Directional threat breakdown; a true surround needs three occupied sectors
	local frontEnemies, flankEnemies, flankLeftEnemies, flankRightEnemies, rearEnemies = quadrants(rootPart, myPos, nearbyEnemies)
	local occupiedQuadrants = (#frontEnemies > 0 and 1 or 0) + (#flankLeftEnemies > 0 and 1 or 0)
		+ (#flankRightEnemies > 0 and 1 or 0) + (#rearEnemies > 0 and 1 or 0)
	local isSurrounded = enemyCount >= 3 and occupiedQuadrants >= (CombatConfig.SurroundedQuadrantThreshold or 3)

	-- Rear threat, within a range set by the Quin's awareness
	local awareness = quinModel:GetAttribute("Pers_Awareness") or 0.65
	local maxRearRange = CombatConfig.RearThreatDetectionRange or 22.0
	local rearDetectDist = 8.0 + awareness * (maxRearRange - 8.0)
	local closestRearThreat, closestRearThreatDist = nil, math.huge
	for _, entry in ipairs(rearEnemies) do
		if entry.distance <= rearDetectDist and entry.distance < closestRearThreatDist then
			closestRearThreatDist = entry.distance
			closestRearThreat = entry.model
		end
	end
	local isUnderRearThreat = closestRearThreat ~= nil

	-- Focus: known enemies within 40 studs that are targeting this Quin
	local enemiesFocusingMe = {}
	for _, enemy in ipairs(contacts.enemies) do
		local theirTarget = enemy.model:GetAttribute("CurrentTarget") or enemy.model:GetAttribute("TargetQuin")
		if theirTarget == quinModel.Name and enemy.distance <= 40 then
			table.insert(enemiesFocusingMe, enemy.model)
		end
	end
	local isBeingBullied = #enemiesFocusingMe >= (CombatConfig.BulliedFocusThreshold or 2)

	local threatZone = "Front"
	if nearestEnemy and nearestEnemy.quadrant then
		threatZone = (nearestEnemy.quadrant == "FlankLeft" or nearestEnemy.quadrant == "FlankRight") and "Flank" or nearestEnemy.quadrant
	end

	local isSelfIsolated = (allyCount == 0 and enemyCount >= 1) or (nearestAllyDist > 65 and enemyCount >= 1)
	local isOutnumbered = (enemyCount > allyCount + 1) or (localAdvantageRatio < 0.65)

	-- The target's own situation, as far as this Quin knows it
	local targetInfo = nil
	local isTargetIsolated = false
	local targetHealthRatio = 1.0
	local activeTarget = targetModel or (nearestEnemy and nearestEnemy.model)
	if activeTarget and activeTarget.Parent then
		local targetRoot = activeTarget:FindFirstChild("HumanoidRootPart")
		local targetHum = activeTarget:FindFirstChildOfClass("Humanoid")
		if targetRoot and targetHum and targetHum.Health > 0 then
			local targetPos = targetRoot.Position
			local targetAlliesCount = 0
			for _, enemy in ipairs(contacts.enemies) do
				if enemy.model ~= activeTarget and (enemy.position - targetPos).Magnitude <= SituationAwareness.LOCAL_RADIUS then
					targetAlliesCount += 1
				end
			end
			isTargetIsolated = targetAlliesCount == 0
			targetHealthRatio = targetHum.Health / targetHum.MaxHealth
			targetInfo = {
				model = activeTarget,
				distance = (targetPos - myPos).Magnitude,
				healthRatio = targetHealthRatio,
				isIsolated = isTargetIsolated,
				alliesCount = targetAlliesCount,
			}
		end
	end

	local baseConfidence = quinModel:GetAttribute("Pers_Confidence") or 0.6
	local currentConfidence = PersonalitySystem.computeEffectiveConfidence(baseConfidence, self.healthRatio, localAdvantageRatio)

	local threatLevel = math.clamp((enemyCount * 25) + ((1 - self.healthRatio) * 35) + (isSelfIsolated and 25 or 0) - (allyCount * 15), 0, 100)

	-- Team battle state
	local totalLivingAllies = census.totalLivingAllies
	local totalLivingEnemies = census.totalLivingEnemies
	local isSoleSurvivor = myTeam ~= "None" and totalLivingAllies == 0
	local teamSurvivalRatio = (totalLivingAllies + 1) / math.max(1, totalLivingAllies + totalLivingEnemies + 1)

	-- Who is closing in, and how fast
	local primaryPursuer, primaryPursuerDist, closingSpeed = nil, math.huge, 0
	for _, entry in ipairs(nearbyEnemies) do
		local toMe = myPos - entry.position
		local dist = toMe.Magnitude
		local closing = dist > 0.1 and (entry.velocity - self.velocity):Dot(toMe.Unit) or 0
		local isTargetingMe = entry.model:GetAttribute("TargetQuin") == quinModel.Name or entry.model:GetAttribute("CurrentTarget") == quinModel.Name
		if (closing > 0 or isTargetingMe) and dist < primaryPursuerDist then
			primaryPursuerDist = dist
			closingSpeed = math.max(0, closing)
			primaryPursuer = entry.model
		end
	end

	-- Is an ally on its way to help?
	local reinforcingAllyApproaching = false
	if nearestAlly and nearestAllyDist <= (CombatConfig.DefendDelayDistance or 35.0) then
		local toMe = myPos - nearestAlly.position
		if toMe.Magnitude > 0.1 and nearestAlly.velocity:Dot(toMe.Unit) > 3.0 then
			reinforcingAllyApproaching = true
		end
	end

	-- Escape feasibility (0.05 .. 1.0)
	local myMaxSpeed = quinModel:GetAttribute("Speed") or 40
	local chaserMaxSpeed = (primaryPursuer and (primaryPursuer:GetAttribute("Speed") or 40)) or 40
	local speedRatio = math.clamp(myMaxSpeed / math.max(15, chaserMaxSpeed), 0.5, 1.5)
	local energyFactor = math.clamp(self.energyRatio, 0.1, 1.0)

	local havenScore = 0.5
	if nearestAllyDist <= 60 then
		havenScore += 0.35
	elseif nearestAllyDist <= 120 then
		havenScore += 0.15
	elseif nearestAllyDist > 180 or isSoleSurvivor then
		havenScore -= 0.35
	end
	if environment.overheadPlatform or environment.isOnElevatedPlatform then
		havenScore += 0.20
	end

	local escapeFeasibility = (speedRatio * 0.35) + (energyFactor * 0.25) + (havenScore * 0.40)
	if isSurrounded then
		escapeFeasibility -= 0.30
	end
	if isSoleSurvivor then
		escapeFeasibility -= (totalLivingEnemies >= 2 and 0.45 or 0.25)
		if self.healthRatio < 0.40 then
			escapeFeasibility -= 0.20
		end
	end
	if self.healthRatio < 0.25 and primaryPursuerDist < 14 and closingSpeed > 4 then
		escapeFeasibility -= 0.35
	end
	if environment.isCornered then
		escapeFeasibility = 0.05
	end
	escapeFeasibility = math.clamp(escapeFeasibility, 0.05, 1.0)

	-- How much staying alive is worth to the team right now (0 .. 1)
	local battleLifeValue
	if isSoleSurvivor and totalLivingEnemies >= 2 then
		battleLifeValue = 0.15 -- alone against a team: fleeing gains little
	elseif totalLivingAllies >= 2 then
		battleLifeValue = 0.90 -- team is strong: staying alive to regroup matters
	elseif totalLivingAllies == 1 then
		battleLifeValue = 0.65
	else
		battleLifeValue = 0.45
	end

	-- Published for the HUD, the states and other Quins
	quinModel:SetAttribute("IsUnderRearThreat", isUnderRearThreat)
	quinModel:SetAttribute("ClosestRearThreat", closestRearThreat and closestRearThreat.Name or "")
	quinModel:SetAttribute("ClosestRearThreatDist", isUnderRearThreat and closestRearThreatDist or 0)
	quinModel:SetAttribute("BeingBullied", isBeingBullied)
	quinModel:SetAttribute("FocusCount", #enemiesFocusingMe)
	quinModel:SetAttribute("OccupiedQuadrants", occupiedQuadrants)
	quinModel:SetAttribute("AwarenessLevel", awareness)
	quinModel:SetAttribute("ThreatZone", threatZone)
	quinModel:SetAttribute("CurrentConfidence", currentConfidence)
	quinModel:SetAttribute("EscapeFeasibility", math.round(escapeFeasibility * 100) / 100)
	quinModel:SetAttribute("BattleLifeValue", math.round(battleLifeValue * 100) / 100)
	quinModel:SetAttribute("IsSoleSurvivor", isSoleSurvivor)
	quinModel:SetAttribute("TotalLivingAllies", totalLivingAllies)
	quinModel:SetAttribute("TotalLivingEnemies", totalLivingEnemies)
	quinModel:SetAttribute("NearestGlobalAllyDist", nearestAllyDist < math.huge and math.round(nearestAllyDist * 10) / 10 or 999)
	quinModel:SetAttribute("ReinforcingAllyApproaching", reinforcingAllyApproaching)

	return {
		NearbyAllies = nearbyAllies,
		NearbyEnemies = nearbyEnemies,
		AllyCount = allyCount,
		EnemyCount = enemyCount,
		LocalNumericalRatio = localAdvantageRatio,
		NearestEnemy = nearestEnemy and nearestEnemy.model,
		BestTarget = activeTarget,
		SelfHealthPercent = self.healthRatio,
		SelfResourcePercent = self.energyRatio,
		TargetHealthPercent = targetHealthRatio,
		Isolated = isSelfIsolated,
		TargetIsolated = isTargetIsolated,
		Outnumbered = isOutnumbered,
		Surrounded = isSurrounded,
		NearbyAllyNeedsHelp = distressedAlly ~= nil,
		DistressedAlly = distressedAlly,
		ThreatLevel = threatLevel,

		-- Team battle state and survival
		TotalLivingAllies = totalLivingAllies,
		TotalLivingEnemies = totalLivingEnemies,
		IsSoleSurvivor = isSoleSurvivor,
		TeamSurvivalRatio = teamSurvivalRatio,
		NearestGlobalAllyDist = nearestAllyDist,
		ReinforcingAllyApproaching = reinforcingAllyApproaching,
		PrimaryPursuer = primaryPursuer,
		ClosingSpeed = closingSpeed,
		EscapeFeasibility = escapeFeasibility,
		BattleLifeValue = battleLifeValue,

		-- Directional threats
		FrontEnemies = frontEnemies,
		FlankEnemies = flankEnemies,
		RearEnemies = rearEnemies,
		FlankLeftEnemies = flankLeftEnemies,
		FlankRightEnemies = flankRightEnemies,
		OccupiedQuadrants = occupiedQuadrants,
		IsUnderRearThreat = isUnderRearThreat,
		ClosestRearThreat = closestRearThreat,
		ClosestRearThreatDist = isUnderRearThreat and closestRearThreatDist or 0,
		BeingBullied = isBeingBullied,
		FocusCount = #enemiesFocusingMe,
		EnemiesFocusingMe = enemiesFocusingMe,

		-- Room to retreat and platforms (EnvironmentAwareness)
		SafeRetreatDirection = environment.retreatDirection,
		SafeRetreatScore = environment.retreatScore,
		IsCornered = environment.isCornered,
		HasOverheadPlatform = environment.overheadPlatform ~= nil,
		OverheadPlatformTopY = environment.overheadPlatform and environment.overheadPlatform.topY or 0,
		IsOnElevatedPlatform = environment.isOnElevatedPlatform,

		-- Team roles
		TeamRole = TeamCoordinationSystem.evaluateRole(quinModel, nearbyAllies, nearbyEnemies, { DistressedAlly = distressedAlly }),
		TeamFocusTarget = TeamCoordinationSystem.getTeamFocusTarget(quinModel),

		-- Names kept for older readers of this table
		myModel = quinModel,
		myPosition = myPos,
		ownHealthRatio = self.healthRatio,
		ownEnergyRatio = self.energyRatio,
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
end

return SituationAwareness
