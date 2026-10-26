--// TaskChoice.lua
-- What a Quin sets out to do, one level above which enemy it hits (Lantern Siege design, brain
-- step 2; works in every mode). Each reasoning tick it weighs a few tasks from what it knows
-- (its own senses, memory and the team's callouts, never the whole arena):
--   Fight   deal with what is in front of it (TargetingModule then picks the enemy, as before)
--   Rescue  go to an ally further off who is in trouble, and take on whoever is hurting it
--   Hunt    nobody near: go after an enemy it believes is somewhere (seen, remembered, called)
-- Each task is scored on value, danger and distance, and temperament bends it. Leanings, never
-- rules: a protective Quin answers a hurt ally sooner; a timid one hunts less; nobody leaves a
-- fight it is pinned in. A task is kept for a moment unless another is clearly better.
-- Later tasks (guard a route, escort, scout, retake) slot in here once a mode has objectives.
-- Off switch: CombatConfig.Task_Enabled = false (Fight always, the old behaviour).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local QuinCore = ReplicatedStorage:WaitForChild("QuinCore")
local CombatConfig = require(QuinCore:WaitForChild("CombatConfig"))
local Blackboard = require(QuinCore:WaitForChild("Cognition"):WaitForChild("Blackboard"))

local TaskChoice = {}

local function cfg(key, default)
	local v = CombatConfig[key]
	if v == nil then return default end
	return v
end

local function flat(a, b)
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

local function pers(quinModel, key, default)
	return quinModel:GetAttribute(key) or default
end

local function rootOf(model)
	return model and model.Parent and model:FindFirstChild("HumanoidRootPart")
end

-- Allies already going to this ally's rescue (the team talks: each says what it is doing)
local function rescuersOf(allyName, me)
	local n = 0
	for _, q in ipairs((workspace:FindFirstChild("QuinServer") or workspace):GetChildren()) do
		if q ~= me and q:GetAttribute("Task") == "Rescue" and q:GetAttribute("TaskAlly") == allyName then
			n += 1
		end
	end
	return n
end

-- Scores for every task this tick. Returns { name = { score, enemy, ally, why } }
local function score(quinModel, rootPart, context, board)
	local myPos = rootPart.Position
	local confidence = context.currentConfidence or pers(quinModel, "CurrentConfidence", 0.6)
	local aggression = pers(quinModel, "Pers_Aggression", 0.6)
	local protect = pers(quinModel, "Pers_Protectiveness", 0.5)
	local risk = pers(quinModel, "Pers_RiskTolerance", 0.5)
	local selfHp = context.SelfHealthPercent or 1
	local tasks = {}

	-- Fight: what is in front of it. Pinned (an enemy on it, close) is hard to leave.
	local near = context.NearbyEnemies or {}
	if #near > 0 then
		local pinned = false
		for _, e in ipairs(near) do
			if e.model and e.model:GetAttribute("CurrentTarget") == quinModel.Name and (e.distance or 99) <= cfg("Task_PinnedRange", 20) then
				pinned = true
			end
		end
		tasks.pinned = pinned
		tasks.Fight = {
			score = cfg("Task_FightBase", 60) + (pinned and cfg("Task_PinnedBonus", 60) or 0) + 20 * (aggression - 0.5),
			why = pinned and "one is on me" or "enemies right here",
		}
	else
		tasks.Fight = { score = 0, why = "nobody near" }
	end

	-- Rescue: an ally beyond its own fight radius in trouble. Allies are always known (team).
	local bestRescue = nil
	for _, ally in ipairs(board.contacts.allies or {}) do
		local am, aRoot = ally.model, rootOf(ally.model)
		local hp = ally.healthRatio or 1
		local dist = aRoot and flat(aRoot.Position, myPos)
		if aRoot and hp <= cfg("Task_RescueHealth", 0.45) and dist > cfg("Task_RescueMinRange", 45) and dist <= cfg("Task_RescueRange", 140) then
			-- who is hurting it: an enemy this Quin knows near it, else the one that hit it last
			local attacker, danger = nil, 0
			for _, contact in ipairs(board.contacts.enemies or {}) do
				local d = flat(contact.position, aRoot.Position)
				if d <= cfg("Task_RescueDangerRadius", 30) then
					danger += 1
					if contact.model:GetAttribute("CurrentTarget") == am.Name or not attacker then attacker = contact.model end
				end
			end
			if not attacker then
				local last = am:GetAttribute("LastAttackerName")
				local lm = last and (workspace:FindFirstChild("QuinServer") or workspace):FindFirstChild(last)
				local lRoot = rootOf(lm)
				if lRoot and flat(lRoot.Position, aRoot.Position) <= cfg("Task_RescueDangerRadius", 30) then
					attacker, danger = lm, 1
				end
			end
			if attacker then
				local s = (1 - hp) * cfg("Task_RescueValue", 170) * (0.4 + protect)
					- dist * cfg("Task_RescueDistanceCost", 0.25)
					- math.max(0, danger - 1) * cfg("Task_RescueDangerCost", 18) * (1.2 - risk)
					- rescuersOf(am.Name, quinModel) * cfg("Task_RescueTakenCost", 45)
					- (selfHp < 0.35 and 40 or 0)
				if not bestRescue or s > bestRescue.score then
					bestRescue = { score = s, enemy = attacker, ally = am.Name, why = string.format("%s is hurt (%d%%), %s is on it", am.Name, hp * 100, attacker.Name) }
				end
			end
		end
	end
	tasks.Rescue = bestRescue or { score = -math.huge, why = "nobody to save" }

	-- Hunt: nobody near. Go after the best enemy it believes is somewhere.
	local bestHunt = nil
	if #near == 0 then
		for _, contact in ipairs(board.contacts.enemies or {}) do
			if rootOf(contact.model) then
				local dist = flat(contact.position, myPos)
				local s = cfg("Task_HuntBase", 50) * (0.5 + aggression) * (0.5 + confidence)
					+ (1 - (contact.healthRatio or 1)) * cfg("Task_HuntWeakValue", 30)
					+ (contact.heardFrom and cfg("Task_HuntCalledValue", 15) or 0)
					+ (contact.confidence or 1) * 20
					+ (contact.model.Name == quinModel:GetAttribute("CurrentTarget") and cfg("Task_HuntKeepValue", 25) or 0)
					- dist * cfg("Task_HuntDistanceCost", 0.15)
					- (selfHp < 0.35 and 30 or 0)
				if not bestHunt or s > bestHunt.score then
					local how = contact.visible and "I see it"
						or contact.heardFrom and (contact.heardFrom .. " called it")
						or contact.channel == "rumour" and "somewhere that way"
						or "I saw it there"
					bestHunt = { score = s, enemy = contact.model, why = string.format("go after %s (%s)", contact.model.Name, how) }
				end
			end
		end
	end
	tasks.Hunt = bestHunt or { score = -math.huge, why = "nobody known" }
	return tasks
end

-- The task this Quin takes now: { name, enemy, ally, why }. Published as Task / TaskWhy /
-- TaskAlly / TaskAt for the HUD, the mind panel and teammates.
function TaskChoice.choose(quinModel, rootPart, context)
	if cfg("Task_Enabled", true) == false or not context then return nil end
	local board = Blackboard.peek(quinModel)
	if not board or not board.contacts then return nil end
	local now = os.clock()

	local tasks = score(quinModel, rootPart, context, board)
	local pinned = tasks.pinned
	tasks.pinned = nil
	local bestName, best = "Fight", tasks.Fight
	for name, t in pairs(tasks) do
		if t.score > best.score then bestName, best = name, t end
	end

	-- Keep the task it has for a moment unless another is clearly better
	local held = board.task
	-- (an enemy on it, close, ends any hold: nobody walks off with one hitting its back)
	if held and held.name ~= bestName and not (pinned and bestName == "Fight") and tasks[held.name] and tasks[held.name].score > -math.huge then
		local heldScore = tasks[held.name].score
		if now - held.since < cfg("Task_MinHold", 2.5) or best.score - heldScore < cfg("Task_SwitchMargin", 20) then
			bestName, best = held.name, tasks[held.name]
		end
	end

	if not held or held.name ~= bestName then
		board.task = { name = bestName, since = now }
		quinModel:SetAttribute("TaskAt", tick())
	end
	board.task.enemy, board.task.ally, board.task.why = best.enemy, best.ally, best.why
	if quinModel:GetAttribute("Task") ~= bestName then quinModel:SetAttribute("Task", bestName) end
	if quinModel:GetAttribute("TaskWhy") ~= best.why then quinModel:SetAttribute("TaskWhy", best.why) end
	if quinModel:GetAttribute("TaskAlly") ~= (best.ally or "") then quinModel:SetAttribute("TaskAlly", best.ally or "") end
	return { name = bestName, enemy = best.enemy, ally = best.ally, why = best.why }
end

return TaskChoice
