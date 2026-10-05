--// TargetingModule.lua
-- Finds, evaluates, and selects optimal targets for Quin combat
-- Implements explainable utility-based target selection biased by personality & local battlefield state

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CombatConfig = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("CombatConfig"))
local SpatialModule = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("SpatialModule"))
local Cognition = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Cognition"))

local SocialSystem = require(game:GetService("ReplicatedStorage"):WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("SocialSystem"))
local TargetingModule = {}

-- Utility-based target evaluation and selection
-- Commitment. A target is held: the utility scores below move with every tick (who is nearest,
-- who is hunting whom, who stands behind), and taken at face value they changed a Quin's target
-- every 2 s, 46% of the time straight back to the one it had just dropped (held 0.8 s on
-- average). In a fight each change stopped it to look round: a quick turn away and back.
-- So a Quin stays on its target for at least Targeting_MinHold (longer the more persistent it
-- is) and leaves it only for one that is clearly better (Targeting_SwitchMargin); only a far
-- better one (Targeting_UrgentMargin: something hitting it from behind) cuts the hold short.
-- committed[quin] = { name, since }: also notices a target set from elsewhere (a state's own
-- choice starts a hold of its own).
local committed = setmetatable({}, { __mode = "k" })

-- Every change of target is written here, with who asked for it: TargetChangedBy says why a
-- Quin turned to someone else ("Select" the utility choice, "Nearest" a state's nearest-enemy
-- look-up, "Distraction", "RearThreat", "Dive", "Intercept", "Duel"). The mind panel and probes
-- read it.
local function heldFor(quinModel, targetName, now)
	local record = committed[quinModel]
	if not record or record.name ~= targetName then
		record = { name = targetName, since = now }
		committed[quinModel] = record
	end
	return now - record.since
end

-- Still inside the minimum time it stays on the target it has?
local function isHolding(quinModel)
	local name = quinModel:GetAttribute("CurrentTarget")
	if not name or name == "" then return false end
	local persistence = quinModel:GetAttribute("Pers_TargetPersistence") or 0.7
	return heldFor(quinModel, name, os.clock()) < (CombatConfig.Targeting_MinHold or 2.0) * (0.5 + persistence)
end

local function assign(fighter, name, reason)
	if fighter:GetAttribute("CurrentTarget") ~= name then
		fighter:SetAttribute("TargetChangedBy", reason)
	end
	fighter:SetAttribute("CurrentTarget", name)
	heldFor(fighter, name, os.clock()) -- (a new target starts a new hold)
end

-- Reasons a state may give that do not break the hold: a passer-by is no cause to drop a target
-- it has only just turned to. (Measured: 41 % of "Distraction" switches went straight back, two
-- enemies inside 13 studs each being the other's distraction in turn.)
local HOLD_RESPECTING = { Distraction = true }

function TargetingModule.selectTarget(quinModel, localState)
	if not quinModel or not quinModel.Parent then return nil, 0, "No model" end
	local rootPart = quinModel:FindFirstChild("HumanoidRootPart")
	if not rootPart then return nil, 0, "No root part" end

	-- Normalize localState in case caller passes rootPart or nil
	if typeof(localState) ~= "table" then
		localState = nil
	end

	-- RESPECT CUSTOM (Respect & Anti-Bullying)
	local showdownRole = quinModel:GetAttribute("RespectRole")
	if SocialSystem.standsDown(quinModel) then
		quinModel:SetAttribute("CurrentTarget", "")
		quinModel:SetAttribute("TargetReason", "Perimeter Spectator (Respect & Tradition)")
		return nil, 0, "Perimeter Spectator (Respect & Tradition)"
	end

	if showdownRole == "Duelist" then
		local oppName = quinModel:GetAttribute("TargetQuin")
		if oppName and oppName ~= "" then
			local serverFolder = workspace:FindFirstChild("QuinServer") or workspace
			local opp = serverFolder:FindFirstChild(oppName) or workspace:FindFirstChild(oppName)
			if opp and opp:FindFirstChild("HumanoidRootPart") and opp:GetAttribute("RespectRole") == "Duelist" then
				local d = (opp.HumanoidRootPart.Position - rootPart.Position).Magnitude
				assign(quinModel, opp.Name, "Duel")
				quinModel:SetAttribute("LastTargetName", opp.Name)
				quinModel:SetAttribute("TargetReason", "Respect custom 1v1 Duelist")
				return opp, 2000, "Respect custom 1v1 Duelist"
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
		-- (nobody close by, as in the middle of a jump: it keeps the target it has)
		local kept = currentTargetName and currentTargetName ~= ""
			and ((workspace:FindFirstChild("QuinServer") or workspace):FindFirstChild(currentTargetName))
		if kept and TargetingModule.isValid(kept) then
			return kept, 50, "Committed to its target (nobody near)"
		end
		local nearest, nearestDist = TargetingModule.getNearest(rootPart, 500)
		if nearest then
			local fallbackReason = string.format("Nearest enemy fallback (%.1f studs)", nearestDist)
			assign(quinModel, nearest.Name, "Nearest")
			quinModel:SetAttribute("LastTargetName", nearest.Name)
			quinModel:SetAttribute("TargetReason", fallbackReason)
			return nearest, 50, fallbackReason
		end
		return nil, 0, "No targets available"
	end

	local bestCandidate = nil
	local bestUtility = -math.huge
	local bestReason = "None"
	local heldName = quinModel:GetAttribute("CurrentTarget")
	local heldCandidate, heldUtility = nil, -math.huge

	for _, cand in ipairs(candidates) do
		local model = cand.model
		if model and model.Parent and TargetingModule.isValid(model) then
			local dist = cand.distance or (model.HumanoidRootPart.Position - rootPart.Position).Magnitude
			local targetHp = cand.healthRatio or 1.0
			local isIsolated = cand.isIsolated or false

			-- 0. Line of Sight / 8-Stud Quin Occlusion Score:
			-- Quins stand 8 studs tall; they cannot see through solid geometry.
			-- Occluded enemies receive a major penalty unless in close proximity (<= 12 studs) where audio/vibration reveals them.
			local hasLoS = cand.hasLineOfSight
			if hasLoS == nil then
				local myEye = SpatialModule.getEyePosition(rootPart)
				local oEye = SpatialModule.getEyePosition(model.HumanoidRootPart)
				hasLoS = SpatialModule.checkLineOfSight(myEye, oEye, { quinModel, model })
				cand.hasLineOfSight = hasLoS
			end
			local losScore = hasLoS and 25 or (dist <= 12 and -15 or -60)

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

			-- 12. Being hunted: the enemy that is closing on this Quin and has it as its target is
			-- worth turning on, the more so the more aware the Quin is. (Without it A chased B
			-- while B chased C while C chased A, round and round on the same spot.)
			local huntedScore = 0
			if localState and localState.PrimaryPursuer == model and not isCurrent then
				huntedScore = (CombatConfig.Targeting_HuntedScore or 60) * (quinModel:GetAttribute("Pers_Awareness") or 0.65)
			end

			-- 13. Social layer (SocialSystem): a leader's attack signal this Quin chose to follow, an
			-- enemy going for the leader it trusts, a Quin it holds off (respect custom)
			local socialScore = SocialSystem.targetScore(quinModel, model)

			local utility = distScore + vulnScore + isoScore + persistBias - riskScore - threatScore + rearThreatScore + teamRoleScore + grudgeScore + rivalryScore + tauntScore + losScore + huntedScore + socialScore

			if model.Name == heldName then
				heldCandidate, heldUtility = model, utility
			end
			if utility > bestUtility then
				bestUtility = utility
				bestCandidate = model

				-- Build explainable debug reason
				local reasons = {}
				if socialScore > 20 then table.insert(reasons, "Leader's signal / guarding the leader") end
				if tauntScore > 0 then table.insert(reasons, "Humble the showoff (aura farming)") end
				if rivalryScore > 0 then table.insert(reasons, "Historical Rivalry") end
				if grudgeScore > 0 then table.insert(reasons, "Revengeful grudge") end
				if teamRoleScore > 20 then table.insert(reasons, string.format("Team role (%s)", tostring(teamRole))) end
				if isIsolated then table.insert(reasons, "Target isolated") end
				if targetHp < 0.45 then table.insert(reasons, string.format("Target HP %.0f%%", targetHp * 100)) end
				if not hasLoS then table.insert(reasons, "Occluded (broken LoS)") end
				if isCurrent then table.insert(reasons, "Target persistence") end
				if dist <= 15 then table.insert(reasons, string.format("Close range (%.1f studs)", dist)) end
				if rearThreatScore > 15 then table.insert(reasons, "Immediate rear threat") end
				if huntedScore > 0 then table.insert(reasons, "It is hunting me") end
				if riskScore > 15 then table.insert(reasons, "High risk penalty") end
				if threatScore > 15 then table.insert(reasons, "High counter-threat") end
				if #reasons == 0 then table.insert(reasons, "Optimal utility score") end

				bestReason = table.concat(reasons, ", ")
			end
		end
	end

	-- Commitment (see above): the target it has is kept unless the best is clearly better
	if heldCandidate and bestCandidate and bestCandidate ~= heldCandidate then
		local lead = bestUtility - heldUtility
		local holding = isHolding(quinModel)
		if lead < (CombatConfig.Targeting_UrgentMargin or 80)
			and (holding or lead < (CombatConfig.Targeting_SwitchMargin or 30)) then
			bestCandidate, bestUtility = heldCandidate, heldUtility
			bestReason = holding and "Committed to its target" or "Committed (nothing clearly better)"
		end
	end
	-- A target that has left its near view (thrown clear, gone round a corner) is still its target
	-- while the hold lasts: it does not turn to whoever happens to be near in that moment
	if not heldCandidate and bestCandidate and isHolding(quinModel) then
		local held = (workspace:FindFirstChild("QuinServer") or workspace):FindFirstChild(heldName)
		if held and TargetingModule.isValid(held) then
			return held, 50, "Committed to its target (out of view)"
		end
	end

	if bestCandidate then
		local bestHasLoS = false
		for _, c in ipairs(candidates) do
			if c.model == bestCandidate then
				bestHasLoS = (c.hasLineOfSight == true)
				break
			end
		end

		-- (a new target it cannot see has no "last seen" place yet: the old target's is dropped)
		if quinModel:GetAttribute("CurrentTarget") ~= bestCandidate.Name and not bestHasLoS then
			quinModel:SetAttribute("LastSeenTargetPosition", nil)
		end
		assign(quinModel, bestCandidate.Name, "Select")
		quinModel:SetAttribute("LastTargetName", bestCandidate.Name)
		quinModel:SetAttribute("TargetReason", bestReason)
		if bestHasLoS then
			quinModel:SetAttribute("LastSeenTargetPosition", bestCandidate.HumanoidRootPart.Position)
			quinModel:SetAttribute("TimeLastSeen", os.clock())
		end
	end

	return bestCandidate, bestUtility, bestReason
end

-- A state turns the Quin onto a target of its own choosing; `reason` names the rule that did.
-- Returns false when the Quin stays on the target it has (see HOLD_RESPECTING): the caller then
-- carries on as it was.
function TargetingModule.setTarget(fighter, targetModel, reason)
	if not fighter then return false end
	if targetModel and targetModel.Parent then
		local tName = targetModel.Name
		if HOLD_RESPECTING[reason] and fighter:GetAttribute("CurrentTarget") ~= tName and isHolding(fighter) then
			return false
		end
		assign(fighter, tName, reason or "State")
		fighter:SetAttribute("TargetQuin", tName)
		fighter:SetAttribute("LastTargetName", tName)
	else
		fighter:SetAttribute("CurrentTarget", nil)
		fighter:SetAttribute("TargetQuin", nil)
	end
	return true
end

function TargetingModule.clearTarget(fighter)
	if not fighter then return end
	fighter:SetAttribute("CurrentTarget", nil)
	fighter:SetAttribute("TargetQuin", nil)
end

function TargetingModule.getCommittedTarget(fighter, rootPart, maxRange)
	maxRange = maxRange or 1000
	local targetName = fighter:GetAttribute("CurrentTarget") or fighter:GetAttribute("TargetQuin")
	if not targetName or targetName == "" then return nil, math.huge end

	local quinServer = workspace:FindFirstChild("QuinServer") or workspace
	local targetModel = quinServer:FindFirstChild(targetName) or workspace:FindFirstChild(targetName)
	if not targetModel or not targetModel.Parent then
		TargetingModule.clearTarget(fighter)
		return nil, math.huge
	end

	local hum = targetModel:FindFirstChildOfClass("Humanoid")
	local tHRP = targetModel:FindFirstChild("HumanoidRootPart")
	if not hum or hum.Health <= 0 or not tHRP then
		TargetingModule.clearTarget(fighter)
		return nil, math.huge
	end

	local myShowdownRole = fighter:GetAttribute("RespectRole")
	local eRole = targetModel:GetAttribute("RespectRole")
	if eRole == "Spectator" or eRole == "Watching" or (myShowdownRole == "Duelist" and eRole ~= "Duelist") then
		TargetingModule.clearTarget(fighter)
		return nil, math.huge
	end

	local dist = (tHRP.Position - rootPart.Position).Magnitude
	if dist > maxRange then
		return nil, dist
	end

	-- Synchronize attributes so CurrentTarget and TargetQuin never disagree
	fighter:SetAttribute("CurrentTarget", targetName)
	fighter:SetAttribute("TargetQuin", targetName)
	return targetModel, dist
end

-- Find the nearest enemy this Quin knows about (its Cognition contacts: seen, heard, remembered
-- or reported). Before its first cognition tick it falls back to every living Quin.
function TargetingModule.getNearest(rootPart, maxRange)
	maxRange = maxRange or 1000
	local myModel = rootPart.Parent
	local myTeam = myModel:GetAttribute("Team") or "None"
	
	-- Respect custom respect filter
	local myShowdownRole = myModel:GetAttribute("RespectRole")
	if myShowdownRole == "Spectator" or myShowdownRole == "Watching" then
		return nil, math.huge
	end

	-- Check committed target first
	local committedModel, committedDist = TargetingModule.getCommittedTarget(myModel, rootPart, maxRange)
	
	local enemies
	local known = Cognition.knownEnemies(myModel)
	if known then
		enemies = {}
		for _, contact in ipairs(known) do
			table.insert(enemies, contact.model)
		end
	else
		enemies = CollectionService:GetTagged("Quin")
	end
	if not known and #enemies == 0 then
		local quinServer = workspace:FindFirstChild("QuinServer") or workspace
		for _, child in ipairs(quinServer:GetChildren()) do
			if child:IsA("Model") and child ~= myModel and child:FindFirstChild("HumanoidRootPart") and child:FindFirstChildOfClass("Humanoid") then
				table.insert(enemies, child)
			end
		end
	end
	local nearestVisible, nearestVisibleDist = nil, math.huge
	local nearestAny, nearestAnyDist = nil, math.huge
	local myEyePos = SpatialModule.getEyePosition(rootPart)
	local committedHasLoS = false
	
	if committedModel and committedModel:FindFirstChild("HumanoidRootPart") then
		local cEyePos = SpatialModule.getEyePosition(committedModel.HumanoidRootPart)
		committedHasLoS = SpatialModule.checkLineOfSight(myEyePos, cEyePos, { myModel, committedModel })
	end

	for _, enemy in ipairs(enemies) do
		if enemy ~= myModel and enemy.Parent then
			local eHum = enemy:FindFirstChildOfClass("Humanoid")
			local eRoot = enemy:FindFirstChild("HumanoidRootPart")
			if eRoot and eHum and eHum.Health > 0 then
				local enemyTeam = enemy:GetAttribute("Team") or "None"
				local isAlly = (myTeam ~= "None" and myTeam == enemyTeam)
				if not isAlly then
					local enemyShowdownRole = enemy:GetAttribute("RespectRole")
					local isShowdownForbidden = false
					if enemyShowdownRole == "Spectator" or enemyShowdownRole == "Watching" then
						isShowdownForbidden = true
					elseif myShowdownRole == "Duelist" and enemyShowdownRole ~= "Duelist" then
						isShowdownForbidden = true
					elseif myShowdownRole ~= "Duelist" and enemyShowdownRole == "Duelist" then
						isShowdownForbidden = true
					end

					if not isShowdownForbidden then
						local d = (eRoot.Position - rootPart.Position).Magnitude
						if d <= maxRange then
							if d < nearestAnyDist then
								nearestAny = enemy
								nearestAnyDist = d
							end
							local eEyePos = SpatialModule.getEyePosition(eRoot)
							if SpatialModule.checkLineOfSight(myEyePos, eEyePos, { myModel, enemy }) then
								if d < nearestVisibleDist then
									nearestVisible = enemy
									nearestVisibleDist = d
								end
							end
						end
					end
				end
			end
		end
	end
	
	local chosenTarget, chosenDist = nil, math.huge
	if nearestVisible then
		chosenTarget = nearestVisible
		chosenDist = nearestVisibleDist
	elseif nearestAny then
		chosenTarget = nearestAny
		chosenDist = nearestAnyDist
	end

	-- Target commitment hysteresis: If committed target is still alive and in range,
	-- do NOT switch unless the new candidate is significantly closer (>= 30% closer)
	-- or the candidate is visible while the committed target is completely occluded.
	if committedModel and chosenTarget and chosenTarget ~= committedModel then
		local shouldSwitch = false
		if not committedHasLoS and (nearestVisible and chosenTarget == nearestVisible) then
			-- Committed target lost LoS, candidate has visible LoS
			if chosenDist < committedDist * 0.90 then
				shouldSwitch = true
			end
		elseif chosenDist < committedDist * 0.70 then
			-- Candidate is at least 30% closer
			shouldSwitch = true
		end

		if not shouldSwitch then
			chosenTarget = committedModel
			chosenDist = committedDist
		end
	elseif committedModel and not chosenTarget then
		chosenTarget = committedModel
		chosenDist = committedDist
	end

	if chosenTarget then
		assign(myModel, chosenTarget.Name, "Nearest")
		myModel:SetAttribute("TargetQuin", chosenTarget.Name)
		return chosenTarget, chosenDist
	else
		TargetingModule.clearTarget(myModel)
		return nil, math.huge
	end
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
