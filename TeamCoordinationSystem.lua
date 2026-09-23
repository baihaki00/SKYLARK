--// TeamCoordinationSystem.lua
-- Phase 9: Dynamic Team Roles & Group Intelligence
-- Emergent role assignment: PackLeader, Follower, Wingman, Bodyguard, LoneWolf
-- In accordance with Skylark Isles Core Principles: Roles emerge dynamically from physical & tactical context.

local TeamCoordinationSystem = {}

-- Evaluates and updates the Quin's team role based on local allies, enemies, and personal attributes
function TeamCoordinationSystem.evaluateRole(quinModel, nearbyAllies, nearbyEnemies, tacticalContext)
	if not quinModel or not quinModel.Parent then return "LoneWolf" end

	local qType = quinModel:GetAttribute("QuinType") or "TypeA"
	local confidence = quinModel:GetAttribute("CurrentConfidence") or (quinModel:GetAttribute("Pers_Confidence") or 0.6)
	local protectiveness = quinModel:GetAttribute("Pers_Protectiveness") or 0.5
	local mobilityPref = quinModel:GetAttribute("Pers_MobilityPreference") or 0.5
	local currentRole = quinModel:GetAttribute("TeamRole") or "Solo"

	local allyCount = nearbyAllies and #nearbyAllies or 0
	local enemyCount = nearbyEnemies and #nearbyEnemies or 0

	-- 1. If completely alone (no allies nearby within perception radius), Quin is a Solo combatant or Lone Wolf
	if allyCount == 0 then
		local soloRole = (qType == "TypeC" or mobilityPref >= 0.75) and "LoneWolf" or "Solo"
		quinModel:SetAttribute("TeamRole", soloRole)
		quinModel:SetAttribute("AssignedLeader", "")
		quinModel:SetAttribute("GuardedAlly", "")
		return soloRole
	end

	-- 2. Check for LONE WOLF archetype: Assassin or low protectiveness + high mobility
	if (qType == "TypeC" and protectiveness <= 0.40) or (protectiveness <= 0.30 and mobilityPref >= 0.75) then
		quinModel:SetAttribute("TeamRole", "LoneWolf")
		quinModel:SetAttribute("AssignedLeader", "")
		quinModel:SetAttribute("GuardedAlly", "")
		return "LoneWolf"
	end

	-- 3. Check for BODYGUARD: Tanker or high protectiveness with a distressed ally nearby
	local distressedAlly = nil
	if tacticalContext and tacticalContext.DistressedAlly then
		distressedAlly = tacticalContext.DistressedAlly
	else
		for _, aEntry in ipairs(nearbyAllies) do
			if aEntry.healthRatio and aEntry.healthRatio <= 0.35 then
				distressedAlly = aEntry.model
				break
			end
		end
	end

	if distressedAlly and (qType == "TypeB" or protectiveness >= 0.60) then
		quinModel:SetAttribute("TeamRole", "Bodyguard")
		quinModel:SetAttribute("GuardedAlly", distressedAlly.Name)
		quinModel:SetAttribute("AssignedLeader", "")
		return "Bodyguard"
	end

	-- 4. Check for WINGMAN: An ally within 22 studs is locked in a 1v1 duel
	local duelAlly = nil
	for _, aEntry in ipairs(nearbyAllies) do
		if aEntry.distance and aEntry.distance <= 22.0 and aEntry.model then
			local aTarget = aEntry.model:GetAttribute("CurrentTarget")
			if aTarget and aTarget ~= "" then
				duelAlly = aEntry.model
				break
			end
		end
	end

	if duelAlly and protectiveness >= 0.45 and qType ~= "TypeB" and confidence >= 0.45 then
		quinModel:SetAttribute("TeamRole", "Wingman")
		quinModel:SetAttribute("GuardedAlly", duelAlly.Name)
		quinModel:SetAttribute("AssignedLeader", "")
		return "Wingman"
	end

	-- 5. Check for PACK LEADER vs FOLLOWER:
	-- The leader is the ally with the highest confidence in the cluster (or highest HP)
	local isLeader = true
	local foundLeaderModel = nil
	local highestAllyConfidence = -1

	for _, aEntry in ipairs(nearbyAllies) do
		local aModel = aEntry.model
		if aModel and aModel.Parent then
			local aConf = aModel:GetAttribute("CurrentConfidence") or (aModel:GetAttribute("Pers_Confidence") or 0.6)
			local aRole = aModel:GetAttribute("TeamRole")
			if aRole == "PackLeader" then
				isLeader = false
				foundLeaderModel = aModel
				break
			end
			if aConf > highestAllyConfidence then
				highestAllyConfidence = aConf
				foundLeaderModel = aModel
			end
		end
	end

	if isLeader and (confidence >= highestAllyConfidence or confidence >= 0.70) then
		quinModel:SetAttribute("TeamRole", "PackLeader")
		quinModel:SetAttribute("AssignedLeader", "")
		quinModel:SetAttribute("GuardedAlly", "")
		-- Broadcast current target as team focus
		local myTarget = quinModel:GetAttribute("CurrentTarget")
		if myTarget and myTarget ~= "" then
			quinModel:SetAttribute("TeamFocusTarget", myTarget)
		end
		return "PackLeader"
	else
		quinModel:SetAttribute("TeamRole", "Follower")
		quinModel:SetAttribute("AssignedLeader", foundLeaderModel and foundLeaderModel.Name or "")
		quinModel:SetAttribute("GuardedAlly", "")
		return "Follower"
	end
end

-- Get recommended focus target based on team role
function TeamCoordinationSystem.getTeamFocusTarget(quinModel)
	if not quinModel then return nil end
	local role = quinModel:GetAttribute("TeamRole")

	if role == "Follower" then
		local leaderName = quinModel:GetAttribute("AssignedLeader")
		if leaderName and leaderName ~= "" then
			local leaderModel = workspace:FindFirstChild(leaderName) or (workspace:FindFirstChild("QuinServer") and workspace.QuinServer:FindFirstChild(leaderName))
			if leaderModel and leaderModel.Parent then
				local focus = leaderModel:GetAttribute("TeamFocusTarget") or leaderModel:GetAttribute("CurrentTarget")
				if focus and focus ~= "" then
					return focus
				end
			end
		end
	elseif role == "Bodyguard" or role == "Wingman" then
		local guardedName = quinModel:GetAttribute("GuardedAlly")
		if guardedName and guardedName ~= "" then
			local guardedModel = workspace:FindFirstChild(guardedName) or (workspace:FindFirstChild("QuinServer") and workspace.QuinServer:FindFirstChild(guardedName))
			if guardedModel and guardedModel.Parent then
				-- Intercept the enemy targeting our guarded ally
				local enemyAttackingAlly = guardedModel:GetAttribute("LastAttacker") or guardedModel:GetAttribute("CurrentTarget")
				if enemyAttackingAlly and enemyAttackingAlly ~= "" then
					return enemyAttackingAlly
				end
			end
		end
	end

	return nil
end

return TeamCoordinationSystem
