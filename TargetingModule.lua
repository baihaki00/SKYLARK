--// TargetingModule.lua
-- Finds, evaluates, and selects optimal targets for Quin combat
-- Implements explainable utility-based target selection biased by personality & local battlefield state

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CombatConfig = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("CombatConfig"))

local TargetingModule = {}

-- Utility-based target evaluation and selection
function TargetingModule.selectTarget(quinModel, localState)
	if not quinModel or not quinModel.Parent then return nil, 0, "No model" end
	local rootPart = quinModel:FindFirstChild("HumanoidRootPart")
	if not rootPart then return nil, 0, "No root part" end

	-- Normalize localState in case caller passes rootPart or nil
	if typeof(localState) ~= "table" then
		localState = nil
	end

	-- SACRED SHOWDOWN TRADITION (Respect & Anti-Bullying)
	local showdownRole = quinModel:GetAttribute("LeaderShowdownRole")
	if showdownRole == "PerimeterGuard" or showdownRole == "Transition" then
		quinModel:SetAttribute("CurrentTarget", "")
		quinModel:SetAttribute("TargetReason", "Perimeter Spectator (Respect & Tradition)")
		return nil, 0, "Perimeter Spectator (Respect & Tradition)"
	end

	if showdownRole == "Duelist" then
		local oppName = quinModel:GetAttribute("TargetQuin")
		if oppName and oppName ~= "" then
			local serverFolder = workspace:FindFirstChild("QuinServer") or workspace
			local opp = serverFolder:FindFirstChild(oppName) or workspace:FindFirstChild(oppName)
			if opp and opp:FindFirstChild("HumanoidRootPart") and opp:GetAttribute("LeaderShowdownRole") == "Duelist" then
				local d = (opp.HumanoidRootPart.Position - rootPart.Position).Magnitude
				quinModel:SetAttribute("CurrentTarget", opp.Name)
				quinModel:SetAttribute("LastTargetName", opp.Name)
				quinModel:SetAttribute("TargetReason", "Sacred Showdown 1v1 Duelist")
				return opp, 2000, "Sacred Showdown 1v1 Duelist"
			end
		end
		return nil, 0, "Waiting for Showdown Opponent"
	end

	-- If explicit override is requested by server/game-mode, respect it
	local explicitTargetName = quinModel:GetAttribute("ExplicitTarget") or quinModel:GetAttribute("TargetOverride")
	if not explicitTargetName and quinModel:GetAttribute("ForceExplicitTarget") then
		explicitTargetName = quinModel:GetAttribute("TargetQuin")
	end
	if explicitTargetName and explicitTargetName ~= "" then
		local serverFolder = workspace:FindFirstChild("QuinServer") or workspace
		local explicit = serverFolder:FindFirstChild(explicitTargetName) or workspace:FindFirstChild(explicitTargetName)
		if explicit and TargetingModule.isValid(explicit) then
			local d = (explicit.HumanoidRootPart.Position - rootPart.Position).Magnitude
			return explicit, 1000, "Explicit target override: " .. explicitTargetName
		end
	end

	-- Personality & runtime attributes
	local aggression        = quinModel:GetAttribute("Pers_Aggression") or 0.6
	local targetPersistence = quinModel:GetAttribute("Pers_TargetPersistence") or 0.7
	local confidence        = (localState and localState.currentConfidence) or (quinModel:GetAttribute("CurrentConfidence") or 0.6)
	local selfHp            = (localState and localState.SelfHealthPercent) or 1.0

	local currentTargetName = quinModel:GetAttribute("CurrentTarget") or quinModel:GetAttribute("LastTargetName")

	local candidates = localState and localState.NearbyEnemies or {}
	if #candidates == 0 then
		-- Fallback to global scan if no enemies are in direct local radius
		local nearest, nearestDist = TargetingModule.getNearest(rootPart, 500)
		if nearest then
			local fallbackReason = string.format("Nearest enemy fallback (%.1f studs)", nearestDist)
			quinModel:SetAttribute("CurrentTarget", nearest.Name)
			quinModel:SetAttribute("LastTargetName", nearest.Name)
			quinModel:SetAttribute("TargetReason", fallbackReason)
			return nearest, 50, fallbackReason
		end
		return nil, 0, "No targets available"
	end

	local bestCandidate = nil
	local bestUtility = -math.huge
	local bestReason = "None"

	for _, cand in ipairs(candidates) do
		local model = cand.model
		if model and model.Parent and TargetingModule.isValid(model) then
			local dist = cand.distance or (model.HumanoidRootPart.Position - rootPart.Position).Magnitude
			local targetHp = cand.healthRatio or 1.0
			local isIsolated = cand.isIsolated or false

			-- 1. Distance Score: exponential decay with distance (closer = higher utility)
			local distScore = 100 * math.exp(-dist / 35)

			-- 2. Vulnerability Score: finishing instinct on wounded enemies
			local vulnScore = (1.0 - targetHp) * 55 * (1 + (aggression - 0.5) * 0.8)

			-- 3. Isolation Score: emergent convergence / bully incentive on lone targets
			local isoScore = isIsolated and (45 * (1 + (aggression - 0.5) * 0.6)) or 0

			-- 4. Persistence Bias: prevent rapid tick flipping; reward staying engaged
			local isCurrent = (currentTargetName == model.Name or quinModel:GetAttribute("LastTargetName") == model.Name)
			local persistBias = isCurrent and (35 * (targetPersistence / 0.5)) or 0

			-- 5. Risk Score: penalty if target is protected by multiple allies while self is low HP
			local riskScore = 0
			if not isIsolated and ((localState and localState.Outnumbered) or selfHp < 0.4) then
				riskScore = 35 * (1 - (aggression - 0.5) * 0.5)
			end

			-- 6. Threat Score: high-threat proximity when low HP
			local threatScore = 0
			if selfHp < 0.35 and dist < 14 and targetHp > 0.6 then
				threatScore = 30 * (1 - (confidence - 0.5) * 0.8)
			end

			-- 7. Directional Awareness Score (Phase 2): priority response to immediate rear flanker
			local rearThreatScore = 0
			if localState and localState.IsUnderRearThreat and localState.ClosestRearThreat == model then
				local awareness = quinModel:GetAttribute("Pers_Awareness") or 0.65
				if dist <= (CombatConfig.RearThreatCriticalRange or 10.0) then
					rearThreatScore = 45 * awareness
				end
			end

			-- 8. Team Coordination Score (Phase 9): bias toward team focus target
			local teamRoleScore = 0
			local teamRole = localState and localState.TeamRole or quinModel:GetAttribute("TeamRole")
			local teamFocus = localState and localState.TeamFocusTarget or quinModel:GetAttribute("TeamFocusTarget")
			if teamFocus and teamFocus == model.Name then
				if teamRole == "Follower" then
					teamRoleScore = 35 -- Supporting leader's focus target
				elseif teamRole == "Bodyguard" or teamRole == "Wingman" then
					teamRoleScore = 45 -- Intercepting threat to guarded ally
				end
			end
			if teamRole == "LoneWolf" and isIsolated then
				teamRoleScore = teamRoleScore + 40 -- Lone wolf hunting isolated prey
			end

			-- 9. Quirky: Revengeful Grudge Targeting (Phase 10)
			local grudgeScore = 0
			local grudgeTarget = quinModel:GetAttribute("GrudgeTarget")
			if grudgeTarget and grudgeTarget == model.Name then
				grudgeScore = 55 -- Prioritize retribution against grudge target
			end

			-- 10. Historical Rivalry Focus (Phase 11 Persistence)
			local rivalryScore = 0
			local primaryRivalId = quinModel:GetAttribute("PrimaryRivalId")
			local modelQuinId = model:GetAttribute("QuinId")
			if primaryRivalId and modelQuinId and primaryRivalId == modelQuinId then
				rivalryScore = 40 -- Focus historical rival in combat
			end

			-- 11. Phase 12 Spectacle: Global Taunt Response ("Humble the showoff")
			local tauntScore = 0
			local isAuraFarming = cand.isAuraFarming or (model:GetAttribute("IsAuraFarming") == true)
			if isAuraFarming then
				tauntScore = 60 * (1 + (aggression - 0.5) * 0.8)
			end

			local utility = distScore + vulnScore + isoScore + persistBias - riskScore - threatScore + rearThreatScore + teamRoleScore + grudgeScore + rivalryScore + tauntScore

			if utility > bestUtility then
				bestUtility = utility
				bestCandidate = model

				-- Build explainable debug reason
				local reasons = {}
				if tauntScore > 0 then table.insert(reasons, "Humble the showoff (aura farming)") end
				if rivalryScore > 0 then table.insert(reasons, "Historical Rivalry") end
				if grudgeScore > 0 then table.insert(reasons, "Revengeful grudge") end
				if teamRoleScore > 20 then table.insert(reasons, string.format("Team role (%s)", tostring(teamRole))) end
				if isIsolated then table.insert(reasons, "Target isolated") end
				if targetHp < 0.45 then table.insert(reasons, string.format("Target HP %.0f%%", targetHp * 100)) end
				if isCurrent then table.insert(reasons, "Target persistence") end
				if dist <= 15 then table.insert(reasons, string.format("Close range (%.1f studs)", dist)) end
				if rearThreatScore > 15 then table.insert(reasons, "Immediate rear threat") end
				if riskScore > 15 then table.insert(reasons, "High risk penalty") end
				if threatScore > 15 then table.insert(reasons, "High counter-threat") end
				if #reasons == 0 then table.insert(reasons, "Optimal utility score") end

				bestReason = table.concat(reasons, ", ")
			end
		end
	end

	if bestCandidate then
		quinModel:SetAttribute("CurrentTarget", bestCandidate.Name)
		quinModel:SetAttribute("LastTargetName", bestCandidate.Name)
		quinModel:SetAttribute("TargetReason", bestReason)
	end

	return bestCandidate, bestUtility, bestReason
end

-- Find nearest enemy Quin (not on same team, not dead) - Preserved for backward compatibility
function TargetingModule.getNearest(rootPart, maxRange)
	maxRange = maxRange or 1000
	local myModel = rootPart.Parent
	local myTeam = myModel:GetAttribute("Team") or "None"
	
	-- Sacred Showdown respect filter
	local myShowdownRole = myModel:GetAttribute("LeaderShowdownRole")
	if myShowdownRole == "PerimeterGuard" or myShowdownRole == "Transition" then
		return nil, math.huge
	end

	-- Explicit target override (set by game modes or lab server only: TargetQuin)
	local targetName = myModel:GetAttribute("TargetQuin")
	if targetName and targetName ~= "" then
		local quinServer = workspace:FindFirstChild("QuinServer") or workspace
		local explicitTarget = quinServer:FindFirstChild(targetName) or workspace:FindFirstChild(targetName)
		if explicitTarget and explicitTarget:FindFirstChild("HumanoidRootPart") then
			local eHum = explicitTarget:FindFirstChildOfClass("Humanoid")
			if eHum and eHum.Health > 0 then
				local eRole = explicitTarget:GetAttribute("LeaderShowdownRole")
				local forbidden = false
				if eRole == "PerimeterGuard" or eRole == "Transition" then
					forbidden = true
				elseif myShowdownRole == "Duelist" and eRole ~= "Duelist" then
					forbidden = true
				end

				if not forbidden then
					local d = (explicitTarget.HumanoidRootPart.Position - rootPart.Position).Magnitude
					if d <= maxRange then
						return explicitTarget, d
					end
				else
					-- Clear forbidden spectator target so fighter does not lock onto spectators
					myModel:SetAttribute("TargetQuin", nil)
				end
			end
		end
	end
	
	local enemies = CollectionService:GetTagged("Quin")
	if #enemies == 0 then
		local quinServer = workspace:FindFirstChild("QuinServer") or workspace
		for _, child in ipairs(quinServer:GetChildren()) do
			if child:IsA("Model") and child ~= myModel and child:FindFirstChild("HumanoidRootPart") and child:FindFirstChildOfClass("Humanoid") then
				table.insert(enemies, child)
			end
		end
	end
	local nearest, nearestDist = nil, math.huge
	
	for _, enemy in ipairs(enemies) do
		if enemy ~= myModel and enemy.Parent then
			local eHum = enemy:FindFirstChildOfClass("Humanoid")
			local eRoot = enemy:FindFirstChild("HumanoidRootPart")
			if eRoot and eHum and eHum.Health > 0 then
				local enemyTeam = enemy:GetAttribute("Team") or "None"
				local isAlly = (myTeam ~= "None" and myTeam == enemyTeam)
				if not isAlly then
					local enemyShowdownRole = enemy:GetAttribute("LeaderShowdownRole")
					local isShowdownForbidden = false
					if enemyShowdownRole == "PerimeterGuard" or enemyShowdownRole == "Transition" then
						isShowdownForbidden = true
					elseif myShowdownRole == "Duelist" and enemyShowdownRole ~= "Duelist" then
						isShowdownForbidden = true
					elseif myShowdownRole ~= "Duelist" and enemyShowdownRole == "Duelist" then
						isShowdownForbidden = true
					end

					if not isShowdownForbidden then
						local d = (eRoot.Position - rootPart.Position).Magnitude
						if d < nearestDist and d <= maxRange then
							nearest = enemy
							nearestDist = d
						end
					end
				end
			end
		end
	end
	
	return nearest, nearestDist
end

-- Get all enemies within range
function TargetingModule.getEnemiesInRange(rootPart, range)
	range = range or 50
	local myModel = rootPart.Parent
	local myTeam = myModel:GetAttribute("Team") or "None"
	local results = {}
	
	for _, enemy in ipairs(CollectionService:GetTagged("Quin")) do
		if enemy ~= myModel and enemy.Parent then
			local eHum = enemy:FindFirstChildOfClass("Humanoid")
			local eRoot = enemy:FindFirstChild("HumanoidRootPart")
			if eRoot and eHum and eHum.Health > 0 then
				local enemyTeam = enemy:GetAttribute("Team") or "None"
				if myTeam == "None" or myTeam ~= enemyTeam then
					local d = (eRoot.Position - rootPart.Position).Magnitude
					if d <= range then
						table.insert(results, {model = enemy, distance = d})
					end
				end
			end
		end
	end
	
	table.sort(results, function(a, b) return a.distance < b.distance end)
	return results
end

-- Check if target is still valid
function TargetingModule.isValid(target)
	if not target or not target.Parent then return false end
	local hum = target:FindFirstChildOfClass("Humanoid")
	return hum and hum.Health > 0
end

return TargetingModule
