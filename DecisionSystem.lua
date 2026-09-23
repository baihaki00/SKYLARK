--// DecisionSystem.lua
-- Single general Quin decision engine: evaluates candidate actions based on
-- situational usefulness + tactical battlefield state + individual personality preferences.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local QuinCore = ReplicatedStorage:WaitForChild("QuinCore")

local PersonalitySystem = require(QuinCore:WaitForChild("Modules"):WaitForChild("PersonalitySystem"))
local CombatConfig = require(QuinCore:WaitForChild("CombatConfig"))

local DecisionSystem = {}

-- Evaluates utilities for all candidate actions and selects the highest scoring action
function DecisionSystem.evaluateAction(quinModel, tacticalContext, distanceToTarget)
	if not tacticalContext then return "Attack", "ENGAGING", {} end

	-- Personality dimensions for this individual Quin
	local aggression         = quinModel:GetAttribute("Pers_Aggression") or 0.6
	local riskTolerance      = quinModel:GetAttribute("Pers_RiskTolerance") or 0.5
	local dashPreference     = quinModel:GetAttribute("Pers_DashPreference") or 0.6
	local retreatTendency    = quinModel:GetAttribute("Pers_RetreatTendency") or 0.3
	local targetPersistence  = quinModel:GetAttribute("Pers_TargetPersistence") or 0.7
	local protectiveness     = quinModel:GetAttribute("Pers_Protectiveness") or 0.4
	local mobilityPreference = quinModel:GetAttribute("Pers_MobilityPreference") or 0.6
	local specialPreference  = quinModel:GetAttribute("Pers_SpecialPreference") or 0.35
	local confidence         = tacticalContext.currentConfidence or 0.6

	local hpRatio        = tacticalContext.ownHealthRatio or (tacticalContext.SelfHealthPercent or 1.0)
	local energyRatio    = tacticalContext.ownEnergyRatio or (tacticalContext.SelfResourcePercent or 1.0)
	local advantageRatio = tacticalContext.localAdvantageRatio or (tacticalContext.LocalNumericalRatio or 1.0)
	local allyCount      = tacticalContext.nearbyAlliesCount or (tacticalContext.AllyCount or 0)
	local enemyCount     = tacticalContext.nearbyEnemiesCount or (tacticalContext.EnemyCount or 0)

	local isOutnumbered  = tacticalContext.Outnumbered or (enemyCount > allyCount + 1 and advantageRatio < 0.7)
	local isSurrounded   = tacticalContext.Surrounded or (enemyCount >= 3 and advantageRatio <= 0.35)
	local isTargetIso    = (tacticalContext.targetInfo and tacticalContext.targetInfo.isIsolated) or (tacticalContext.TargetIsolated or false)
	local targetHpRatio  = (tacticalContext.targetInfo and tacticalContext.targetInfo.healthRatio) or (tacticalContext.TargetHealthPercent or 1.0)
	local allyNeedsHelp  = tacticalContext.NearbyAllyNeedsHelp or false

	local dist = distanceToTarget or (tacticalContext.DistanceToTarget or 10)

	local scores = {}
	local decisionReasons = {}

	-- Phase 2 Awareness Attributes
	local isBullied     = tacticalContext.BeingBullied or false
	local isUnderRear   = tacticalContext.IsUnderRearThreat or false
	local rearDist      = tacticalContext.ClosestRearThreatDist or 100

	-- 1. ATTACK: Base combat engagement
	local attackBase = 50
	if dist <= 12 then attackBase = attackBase + 35 end
	if isTargetIso then attackBase = attackBase + 25 end -- Emergent convergence on lone target
	if targetHpRatio < 0.35 then attackBase = attackBase + 30 end -- Finishing instinct
	if isSurrounded then attackBase = attackBase - 25 end
	if isBullied and (confidence > 0.60 or aggression > 0.70) then
		attackBase = attackBase + 35 -- Cornered fighter counter-attack instinct
		table.insert(decisionReasons, "Bullied but aggressive: counter-striking")
	end
	scores["Attack"] = attackBase * (1 + (aggression - 0.5) * 1.0) * (1 + (confidence - 0.5) * 0.6)

	-- 2. DASH: Athletic gap closer from 10 up to 60 studs (with 8s cooldown)
	local dashBase = 20
	local lastDash = quinModel:GetAttribute("LastDashTime") or 0
	local isDashOnCooldown = (os.clock() - lastDash) < 8.0
	if not isDashOnCooldown and dist >= 10 and dist <= 60 and energyRatio > 0.35 then
		dashBase = dashBase + 45
		if isTargetIso then dashBase = dashBase + 20 end -- Gap close on isolated enemy
		if isSurrounded or isBullied then dashBase = dashBase + 30 end -- Breakout escape dash
	end
	if isDashOnCooldown or energyRatio < 0.25 or dist < 10 or dist > 60 then
		dashBase = 5 -- Ineligible or on cooldown
	end
	scores["Dash"] = dashBase * (1 + (dashPreference - 0.5) * 1.2) * (1 + (mobilityPreference - 0.5) * 0.8)

	-- 3. RETREAT / DISENGAGE: Back off when low on health, outnumbered, or exhausted
	local retreatBase = 15
	if hpRatio < 0.40 then
		retreatBase = retreatBase + 55
		table.insert(decisionReasons, "Health low")
	end
	if isOutnumbered then
		retreatBase = retreatBase + 40
		table.insert(decisionReasons, "Outnumbered by local enemies")
	end
	if isSurrounded then
		retreatBase = retreatBase + 50
		table.insert(decisionReasons, "Multi-quadrant surround detected")
	end
	if isBullied and (confidence < 0.55 or hpRatio < 0.45) then
		retreatBase = retreatBase + 45
		table.insert(decisionReasons, "Being focused by multiple enemies")
	end
	if energyRatio < 0.20 then
		retreatBase = retreatBase + 30
		table.insert(decisionReasons, "Energy depleted")
	end
	if confidence < 0.35 then
		retreatBase = retreatBase + 25
		table.insert(decisionReasons, "Confidence broken")
	end
	-- Phase 13: Tactical Escape Worth vs Last Stand Valuation
	local escapeFeasibility = tacticalContext.EscapeFeasibility or quinModel:GetAttribute("EscapeFeasibility") or 0.6
	local battleLifeValue = tacticalContext.BattleLifeValue or quinModel:GetAttribute("BattleLifeValue") or 1.0
	local isSoleSurvivor = tacticalContext.IsSoleSurvivor or quinModel:GetAttribute("IsSoleSurvivor") or false
	local isCornered = tacticalContext.IsCornered or quinModel:GetAttribute("IsCornered") or false
	local reinforcingAllyApproaching = tacticalContext.ReinforcingAllyApproaching or false

	-- Evaluate whether escape is realistically possible and tactically valuable
	local escapeFeasThreshold = CombatConfig.EscapeFeasibilityThreshold or 0.20
	local isLastStand = isCornered or (isSoleSurvivor and enemyCount >= 2 and hpRatio < 0.50) or (escapeFeasibility < escapeFeasThreshold and enemyCount >= 1)

	if isLastStand then
		-- REJECT RETREAT: Escape probability collapsed; turn and fight to the death
		scores["Retreat"] = 0
		quinModel:SetAttribute("LastStandMode", true)
		quinModel:SetAttribute("DesperateCounter", true)
		scores["Attack"] = (scores["Attack"] or 50) * (1.6 + aggression * 0.6)
		table.insert(decisionReasons, "Last Stand: escape futile, fighting to inflict maximum damage")
	elseif reinforcingAllyApproaching then
		-- DEFEND & DELAY: Reinforcing ally is rushing to help; guard/delay rather than fleeing away
		scores["Retreat"] = retreatBase * 0.15
		scores["Guard"] = (scores["Guard"] or 30) + 55
		scores["Circling"] = (scores["Circling"] or 20) + 45
		quinModel:SetAttribute("LastStandMode", false)
		table.insert(decisionReasons, "Reinforcing ally approaching: defending to buy time")
	else
		-- RETREAT EVALUATED: Escape is viable and tactically valuable
		quinModel:SetAttribute("LastStandMode", false)
		local rawRetreat = retreatBase * (1 + (retreatTendency - 0.5) * 1.5) * (1 - (riskTolerance - 0.5) * 0.8) * (1 - (confidence - 0.5) * 0.6)
		scores["Retreat"] = rawRetreat * math.clamp(escapeFeasibility * 1.4, 0.4, 1.4) * math.clamp(battleLifeValue * 1.2, 0.3, 1.2)
	end

	-- Sacred Showdown 1v1 Honor: Duelists never retreat inside the circle
	local showdownRole = quinModel:GetAttribute("LeaderShowdownRole")
	if showdownRole == "Duelist" then
		scores["Retreat"] = 0
		scores["Attack"] = (scores["Attack"] or 50) + 40
		table.insert(decisionReasons, "Sacred Showdown: Stand and fight (zero retreat)")
	end

	-- Hysteresis sticky bonus: if currently actively retreating and still viable, stick with it
	if quinModel:GetAttribute("CurrentState") == "Retreat" and not isLastStand then
		scores["Retreat"] = (scores["Retreat"] or 0) + 25
	end

	-- OB / Surroundings awareness (vertical navigation): leverage platforms tactically
	local isOnElevated = tacticalContext.IsOnElevatedPlatform or quinModel:GetAttribute("IsOnElevatedPlatform") or false
	local hasOverhead = tacticalContext.HasOverheadPlatform or quinModel:GetAttribute("HasOverheadPlatform") or false
	if isOnElevated then
		-- High-ground vantage: hold it (guard) and strike from above (attack); less need to retreat
		scores["Guard"] = (scores["Guard"] or 0) + 20
		scores["Attack"] = (scores["Attack"] or 0) + 10
		scores["Retreat"] = (scores["Retreat"] or 0) * 0.7
		table.insert(decisionReasons, "On high ground: holding vantage")
	elseif hasOverhead and (isOutnumbered or isBullied or hpRatio < 0.35) then
		-- Pressured with a climbable platform overhead: reposition up to it for safety
		scores["Reposition"] = (scores["Reposition"] or 0) + 30
		table.insert(decisionReasons, "Seeking overhead high ground")
	end

	-- 4. GUARD / DEFEND: Block incoming attacks or hold ground
	local guardBase = 25
	if isOutnumbered then guardBase = guardBase + 30 end
	if dist <= 12 and hpRatio < 0.5 then guardBase = guardBase + 25 end
	if isUnderRear and rearDist <= 12 then
		guardBase = guardBase + 35
		table.insert(decisionReasons, "Guarding against critical rear flanker")
	end
	scores["Guard"] = guardBase * (1 + (protectiveness - 0.5) * 0.9) * (1 - (aggression - 0.5) * 0.5)

	-- 5. PURSUE: Chase down enemy across the arena
	local pursueBase = 45
	if dist > 16 then pursueBase = pursueBase + 35 end
	if isTargetIso then pursueBase = pursueBase + 25 end
	if targetHpRatio < 0.4 then pursueBase = pursueBase + 25 end
	if isOutnumbered or energyRatio < 0.20 or hpRatio < 0.40 then pursueBase = pursueBase - 40 end -- Do not pursue into danger, exhaustion, or when wounded
	scores["Pursue"] = pursueBase * (1 + (targetPersistence - 0.5) * 1.2) * (1 + (aggression - 0.5) * 0.7)

	-- 6. PROTECT ALLY / RESCUE: Intercept threat approaching a low-health ally
	local protectBase = 10
	if allyNeedsHelp and allyCount > 0 then
		protectBase = protectBase + 75 -- Massive situational incentive to rescue distressed ally
		table.insert(decisionReasons, "Nearby ally in critical condition")
	elseif allyCount > 0 and not isOutnumbered then
		protectBase = protectBase + 20
	end
	scores["ProtectAlly"] = protectBase * (1 + (protectiveness - 0.5) * 1.8)

	-- 7. USE SPECIAL / SUPER: Execute powerful burst
	local specialBase = 20
	if dist <= 16 and energyRatio > 0.55 then specialBase = specialBase + 45 end
	if isTargetIso then specialBase = specialBase + 25 end

	-- Phase 12 Spectacle: Counter-fire clash instinct against active opposing specials
	local targetModel = tacticalContext.targetInfo and tacticalContext.targetInfo.model
	local targetSpecial = targetModel and targetModel:GetAttribute("CurrentSpecial")
	if targetSpecial and dist <= 30 and energyRatio >= 0.35 then
		specialBase = specialBase + 50
		table.insert(decisionReasons, "Opposing special detected: counter-fire clash instinct")
	end
	scores["UseSpecial"] = specialBase * (1 + (specialPreference - 0.5) * 1.3)

	-- 8. REPOSITION: Circle or strafe to flank, break out of blob
	local repoBase = 30
	if dist >= 10 and dist <= 26 then repoBase = repoBase + 25 end
	if isSurrounded then repoBase = repoBase + 35 end
	scores["Reposition"] = repoBase * (1 + (mobilityPreference - 0.5) * 1.1)

	-- 9. AURA FARM (Phase 12 Spectacle): Uncontested power charging & taunt
	local auraFarmBase = 0
	local minFarmDist = CombatConfig.AuraFarm_MinEnemyDist or 25
	local superMeter = quinModel:GetAttribute("SuperMeter") or 0
	if dist >= minFarmDist and (superMeter < 100 or energyRatio < 0.8) then
		auraFarmBase = 30
		if confidence > 0.65 then auraFarmBase = auraFarmBase + 25 end
		if quirky == "Showoff" then auraFarmBase = auraFarmBase + 40 end
		table.insert(decisionReasons, "Uncontested: charging elemental aura")
	end
	scores["AuraFarm"] = auraFarmBase * (1 + (confidence - 0.5) * 1.1)

	-- Global Taunt Response: Rush to interrupt target that is aura farming
	local targetIsAuraFarming = targetModel and (targetModel:GetAttribute("IsAuraFarming") == true)
	if targetIsAuraFarming then
		scores["Dash"] = (scores["Dash"] or 0) + 40
		scores["Pursue"] = (scores["Pursue"] or 0) + 35
		table.insert(decisionReasons, "Target aura farming: close distance to humble showoff")
	end

	-- Phase 10: Quirky Modulation
	local quirky = quinModel:GetAttribute("Quirky") or "Balanced"
	if quirky == "Charger" then
		scores["Attack"] = (scores["Attack"] or 0) + 25
		scores["Dash"] = (scores["Dash"] or 0) + 20
		scores["Guard"] = (scores["Guard"] or 0) * 0.6
		scores["Reposition"] = (scores["Reposition"] or 0) * 0.6
		table.insert(decisionReasons, "Quirky: Charger")
	elseif quirky == "Observer" then
		scores["Reposition"] = (scores["Reposition"] or 0) + 35
		scores["Guard"] = (scores["Guard"] or 0) + 20
		scores["Attack"] = (scores["Attack"] or 0) * 0.8
		table.insert(decisionReasons, "Quirky: Observer")
	elseif quirky == "Overconfident" then
		scores["Retreat"] = (scores["Retreat"] or 0) * 0.4
		scores["Attack"] = (scores["Attack"] or 0) * 1.3
		table.insert(decisionReasons, "Quirky: Overconfident")
	elseif quirky == "Low-Confidence" then
		if hpRatio < 0.50 then
			scores["Retreat"] = (scores["Retreat"] or 0) * 1.5
		end
		table.insert(decisionReasons, "Quirky: Low-Confidence")
	elseif quirky == "Revengeful" then
		local grudgeTarget = quinModel:GetAttribute("GrudgeTarget")
		if grudgeTarget and tacticalContext and tacticalContext.BestTarget and tacticalContext.BestTarget.Name == grudgeTarget then
			scores["Attack"] = (scores["Attack"] or 0) + 40
			scores["Pursue"] = (scores["Pursue"] or 0) + 30
			table.insert(decisionReasons, "Quirky: Revengeful")
		end
	end

	-- Select action with highest utility score
	local bestAction = "Attack"
	local bestScore = -math.huge
	for action, score in pairs(scores) do
		if score > bestScore then
			bestScore = score
			bestAction = action
		end
	end

	-- Survival instinct hard override: near-death Quins retreat ONLY if escape is feasible and NOT in Last Stand!
	if not isLastStand and escapeFeasibility >= (CombatConfig.EscapeFeasibilityThreshold or 0.20) then
		if hpRatio < (CombatConfig.RetreatCriticalHealth or 0.20) and confidence < (CombatConfig.RetreatConfidenceThreshold or 0.70) then
			bestAction = "Retreat"
			table.insert(decisionReasons, "Near death - survival instinct")
		end
	end

	-- Map action to high-level tactical state
	local tacticalState = "ENGAGING"
	if bestAction == "Retreat" then
		tacticalState = "RETREATING"
	elseif bestAction == "Pursue" then
		tacticalState = isTargetIso and "ISOLATING" or "PURSUING"
	elseif bestAction == "Dash" then
		tacticalState = (advantageRatio >= 2.0 and isTargetIso) and "SURROUNDING" or "PRESSING"
	elseif bestAction == "ProtectAlly" then
		tacticalState = "RESCUING"
	elseif bestAction == "Reposition" then
		tacticalState = "REPOSITIONING"
	elseif bestAction == "Attack" and targetHpRatio < 0.35 then
		tacticalState = "FINISHING"
	elseif bestAction == "AuraFarm" then
		tacticalState = "TAUNTING"
	end

	quinModel:SetAttribute("TacticalState", tacticalState)
	quinModel:SetAttribute("RecommendedAction", bestAction)

	-- Optional toggleable debug telemetry matching specification
	local debugEnabled = workspace:GetAttribute("TacticalDebugEnabled") or quinModel:GetAttribute("TacticalDebug")
	if debugEnabled then
		DecisionSystem.logTacticalTelemetry(quinModel, tacticalContext, bestAction, tacticalState, decisionReasons)
	end

	return bestAction, tacticalState, scores
end

-- Structured telemetry log matching Section 15 specification
function DecisionSystem.logTacticalTelemetry(quinModel, context, decision, tacticalState, reasons)
	local qId = quinModel:GetAttribute("QuinId") or quinModel.Name
	local targetName = quinModel:GetAttribute("LastTargetName") or "None"
	local allyCount = context.nearbyAlliesCount or (context.AllyCount or 0)
	local enemyCount = context.nearbyEnemiesCount or (context.EnemyCount or 0)
	local hpPct = math.round((context.ownHealthRatio or context.SelfHealthPercent or 1.0) * 100)
	local resPct = math.round((context.ownEnergyRatio or context.SelfResourcePercent or 1.0) * 100)
	local tgtHpPct = math.round((context.TargetHealthPercent or 1.0) * 100)
	local ratio = context.localAdvantageRatio or context.LocalNumericalRatio or 1.0

	local lines = {
		"================== [TACTICAL] ==================",
		string.format("Quin: %s", tostring(qId)),
		string.format("State: %s", tostring(tacticalState)),
		string.format("Target: %s", tostring(targetName)),
		string.format("Nearby: Allies = %d, Enemies = %d", allyCount, enemyCount),
		string.format("Self HP = %d%%, Resource = %d%%", hpPct, resPct),
		string.format("Target HP = %d%%", tgtHpPct),
		string.format("Local Ratio = %.2f", ratio),
		string.format("Decision: %s", tostring(decision)),
		"Reason:",
	}
	if #reasons == 0 then
		table.insert(lines, "- Optimal candidate utility score")
	else
		for _, r in ipairs(reasons) do
			table.insert(lines, "- " .. r)
		end
	end
	table.insert(lines, "================================================")
	print(table.concat(lines, "\n"))
end

return DecisionSystem
