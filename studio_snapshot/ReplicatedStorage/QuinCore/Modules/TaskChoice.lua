--// TaskChoice.lua
-- What a Quin sets out to do, one level above which enemy it hits (Lantern Siege design, brain
-- step 2; works in every mode). Each reasoning tick it weighs a few tasks from what it knows
-- (its own senses, memory and the team's callouts, never the whole arena):
--   Fight   deal with what is in front of it (TargetingModule then picks the enemy, as before)
--   Rescue  go to an ally further off who is in trouble, and take on whoever is hurting it
--   Hunt    nobody near: go after an enemy it believes is somewhere (seen, remembered, called)
-- And, when a mode puts objectives on the field (Modules/Objectives, Lantern Siege):
--   Carry     it has the Lantern: take it to the Shrine it believes is least defended
--   PickUp    the Lantern lies free: go and take it
--   Escort    walk with the ally carrying it
--   HoldPlant it burns in a Shrine: stand round it
--   Guard     (defending) watch a Shrine, spread across them
--   Retake    (defending) it burns: get to it and stamp it out, more urgent as time runs out
-- A task with a place to go returns point / speed / engage: the Quin walks there and turns to
-- fight only an enemy within `engage` (Main, IdleState).
-- Each task is scored on value, danger and distance, and temperament bends it. Leanings, never
-- rules: a protective Quin answers a hurt ally sooner; a timid one hunts less; nobody leaves a
-- fight it is pinned in. A task is kept for a moment unless another is clearly better.
-- Later tasks (guard a route, escort, scout, retake) slot in here once a mode has objectives.
-- Off switch: CombatConfig.Task_Enabled = false (Fight always, the old behaviour).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local QuinCore = ReplicatedStorage:WaitForChild("QuinCore")
local CombatConfig = require(QuinCore:WaitForChild("CombatConfig"))
local Blackboard = require(QuinCore:WaitForChild("Cognition"):WaitForChild("Blackboard"))
local FightMaths = require(QuinCore:WaitForChild("Modules"):WaitForChild("FightMaths"))
local Objectives = require(QuinCore:WaitForChild("Modules"):WaitForChild("Objectives"))

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
	-- the ally it is already going to: followed further, and through moments nobody is on it
	-- (thrown clear of its attacker) - it is still hurt
	local going = board.task and board.task.name == "Rescue" and board.task.ally
	for _, ally in ipairs(board.contacts.allies or {}) do
		local am, aRoot = ally.model, rootOf(ally.model)
		local hp = ally.healthRatio or 1
		local dist = aRoot and flat(aRoot.Position, myPos)
		local mine = going == am.Name
		local reach = cfg("Task_RescueRange", 140) * (mine and cfg("Task_RescueFollowFactor", 1.5) or 1)
		if aRoot and hp <= cfg("Task_RescueHealth", 0.45) and dist > cfg("Task_RescueMinRange", 45) and dist <= reach then
			-- who is hurting it: an enemy this Quin knows near it, else the one that hit it last.
			-- It keeps the one it went for while that one is still on the ally; else the one that
			-- is after the ally, then the nearest to it. (It took whichever came last in its list:
			-- in a brawl round the ally that changed every tick, and the rescuer swung between
			-- them - 121 of 280 target switches in a 16v16 were rescues, most straight back.)
			local kept = mine and board.task.enemy
			local attacker, danger, bestRank = nil, 0, math.huge
			for _, contact in ipairs(board.contacts.enemies or {}) do
				local d = flat(contact.position, aRoot.Position)
				if d <= cfg("Task_RescueDangerRadius", 30) then
					danger += 1
					local rank = (contact.model == kept and -1000 or 0)
						+ (contact.model:GetAttribute("CurrentTarget") == am.Name and -100 or 0) + d
					if rank < bestRank then attacker, bestRank = contact.model, rank end
				end
			end
			if not attacker then
				local last = am:GetAttribute("LastAttackerName")
				local lm = last and (workspace:FindFirstChild("QuinServer") or workspace):FindFirstChild(last)
				local lRoot = rootOf(lm)
				if lRoot and (mine or flat(lRoot.Position, aRoot.Position) <= cfg("Task_RescueDangerRadius", 30)) then
					attacker, danger = lm, 1
				end
			end
			if attacker then
				local s = (1 - hp) * cfg("Task_RescueValue", 170) * (0.4 + protect)
					- dist * cfg("Task_RescueDistanceCost", 0.25)
					- math.max(0, danger - 1) * cfg("Task_RescueDangerCost", 18) * (1.2 - risk)
					- rescuersOf(am.Name, quinModel) * cfg("Task_RescueTakenCost", 45)
					- (selfHp < 0.35 and 40 or 0)
					+ (mine and cfg("Task_RescueAllyKeep", 30) or 0) -- (the ally it is on its way to)
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
					- FightMaths.cost(quinModel, rootPart, contact.position, confidence)
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

	local view = Objectives.view(quinModel)
	if view then
		-- with a job on the field, wandering off after someone is a bigger step
		if tasks.Hunt.score > -math.huge then tasks.Hunt.score -= cfg("Objective_HuntCost", 30) end
		TaskChoice.objectiveTasks(tasks, quinModel, rootPart, view, board, aggression, protect)
	end
	return tasks
end

-- How many teammates already have this task at this spot (the team talks)
local function takenBy(task, spot, me)
	local n = 0
	for _, q in ipairs((workspace:FindFirstChild("QuinServer") or workspace):GetChildren()) do
		if q ~= me and q:GetAttribute("Team") == me:GetAttribute("Team") and q:GetAttribute("Task") == task
			and (spot == nil or q:GetAttribute("TaskSpot") == spot) then
			n += 1
		end
	end
	return n
end

-- Teammates on the same job at the same spot, with itself, in a fixed order: each takes its own
-- place there (guards spread round a Shrine instead of standing on one point)
local function slotAmong(task, spot, me)
	local names = { me.Name }
	for _, q in ipairs((workspace:FindFirstChild("QuinServer") or workspace):GetChildren()) do
		if q ~= me and q:GetAttribute("Team") == me:GetAttribute("Team") and q:GetAttribute("Task") == task
			and (spot == nil or q:GetAttribute("TaskSpot") == spot) then
			table.insert(names, q.Name)
		end
	end
	table.sort(names)
	for i, n in ipairs(names) do
		if n == me.Name then return i, #names end
	end
	return 1, #names
end

-- An enemy it believes is within `range` of a point
local function enemyNear(board, point, range)
	for _, contact in ipairs(board.contacts and board.contacts.enemies or {}) do
		if flat(contact.position, point) <= range then return contact end
	end
	return nil
end

-- Get clear of a planted orb that will go off before anything can be done about it (caught, a
-- Quin is knocked out and starts the next round shaken). Seconds it needs to run clear, at a run.
local function clearTime(view, myPos)
	local d = (myPos - view.planted.position).Magnitude
	return math.max(0, view.planted.blast + 6 - d) / 30 + 1
end

function TaskChoice.objectiveTasks(tasks, quinModel, rootPart, view, board, aggression, protect)
	local myPos = rootPart.Position
	if view.planted then
		local left = math.max(0, view.planted.endsAt - workspace:GetServerTimeNow())
		local inside = (myPos - view.planted.position).Magnitude <= view.planted.blast + 4
		-- (a defender still defusing stays: it may yet make it; the rest go when it is time)
		local defusing = view.planted.defuser == quinModel.Name
		local need = cfg("Objective_DefuseTime", 7) * (1 - view.planted.defuse)
		local hopeless = view.role == "Defend" and left < need
		if inside and (left < clearTime(view, myPos) + 1.5 or hopeless) and not (defusing and not hopeless) then
			local away = (myPos - view.planted.position) * Vector3.new(1, 0, 1)
			away = away.Magnitude > 0.1 and away.Unit or Vector3.xAxis
			tasks.Escape = {
				score = 400, point = view.planted.position + away * (view.planted.blast + 10), speed = 40, engage = 0,
				urgency = 1, paceWhy = "it is going off",
				why = hopeless and "no time to defuse, get clear" or string.format("get clear (%ds)", math.ceil(left)),
			}
			return
		end
	end
	local awareness = pers(quinModel, "Pers_Awareness", 0.65)
	local run = cfg("Objective_RunSpeed", 40)
	local engage = cfg("Objective_EngageRange", 16)
	-- the clock: with little of the round left the attackers stop being careful (0 .. 1)
	local hurry = view.roundLeft and math.clamp(1 - (view.roundLeft - 10) / cfg("Objective_HurryFrom", 35), 0, 1) or 0
	local clock = function(sec) return string.format("%d:%02d", math.floor(sec) // 60, math.floor(sec) % 60) end

	if view.role == "Attack" then
		if view.iCarry then
			-- the Shrine it believes is least defended (fight maths at each), kept unless another
			-- becomes clearly better
			local best, bestScore = nil, -math.huge
			for _, s in ipairs(view.shrines) do
				local _, enemies = FightMaths.sides(quinModel, rootPart, s.position)
				-- (short of time the nearer one wins over the safer one)
				local sc = -(enemies or 0) * cfg("Objective_ShrineEnemyCost", 40) * (1 - 0.6 * hurry) - flat(s.position, myPos) * (0.1 + 0.4 * hurry)
					+ (board.carryShrine == s.name and cfg("Objective_ShrineKeep", 30) or 0)
				if sc > bestScore then best, bestScore = s, sc end
			end
			if best then
				board.carryShrine = best.name
				-- (it walks it in while nobody is on it; chased, or with an open Shrine close, it runs)
				local chaser = enemyNear(board, myPos, cfg("Objective_CarryChasedRange", 35))
				local urgency, pace = 0.3, "carry it in"
				if chaser then
					urgency, pace = 0.95, "chased"
				elseif hurry > 0.3 then
					urgency, pace = 1, "time is short"
				elseif flat(best.position, myPos) < 50 and bestScore > -20 then
					urgency, pace = 0.75, "run it in"
				end
				-- (a hot-headed carrier may turn on one that is on it; a calm one keeps walking)
				tasks.Carry = {
					score = cfg("Objective_CarryValue", 150) + 60 * (1 - aggression), point = best.position, spot = best.name,
					speed = cfg("Objective_CarrySpeed", 22), engage = 0, urgency = urgency, paceWhy = pace,
					why = string.format("plant at %s (%s, %s left)", best.name, bestScore > -20 and "looks open" or "least bad", clock(view.roundLeft or 0)),
				}
			end
		elseif view.lantern.state == "Base" or view.lantern.state == "Dropped" then
			local pos = view.lantern.position
			tasks.PickUp = {
				score = cfg("Objective_PickUpValue", 140) - flat(pos, myPos) * 0.3 - takenBy("PickUp", nil, quinModel) * 70,
				point = pos, speed = run, engage = engage * 0.6, urgency = math.max(0.75, hurry), paceWhy = "get the orb",
				why = view.lantern.state == "Base" and "take the orb" or "the orb is down, grab it",
			}
		elseif view.lantern.state == "Carried" and view.carrier then
			local cRoot = view.carrier:FindFirstChild("HumanoidRootPart")
			if cRoot then
				-- walk a little ahead of the carrier, to one side (each escort its own side)
				-- toward the Shrine the carrier heads for (its facing turned with every step, the point
				-- swung and the escort flipped between run and walk chasing it)
				local toShrine = cRoot.CFrame.LookVector
				for _, s in ipairs(view.shrines) do
					if s.name == view.carrier:GetAttribute("TaskSpot") then
						local d = Vector3.new(s.position.X - cRoot.Position.X, 0, s.position.Z - cRoot.Position.Z)
						if d.Magnitude > 1 then toShrine = d.Unit end
					end
				end
				toShrine = Vector3.new(toShrine.X, 0, toShrine.Z).Unit
				local slot, count = slotAmong("Escort", nil, quinModel)
				local side = Vector3.new(-toShrine.Z, 0, toShrine.X) * ((slot % 2 == 0) and 1 or -1)
				local point = cRoot.Position + toShrine * (slot <= 2 and 8 or -4) + side * 7
				tasks.Escort = {
					score = cfg("Objective_EscortValue", 75) + 40 * protect - flat(cRoot.Position, myPos) * 0.15
						- math.max(0, takenBy("Escort", nil, quinModel) - 1) * 25,
					point = point, speed = run, engage = engage,
					urgency = flat(point, myPos) > 25 and 0.7 or 0.35, paceWhy = flat(point, myPos) > 25 and "catch up" or "walk with it",
					why = "walk with " .. view.carrier.Name,
				}
			end
		elseif view.planting or view.planted then
			-- round the Shrine it is being planted on / is planted on: keep the defenders off it
			local site = view.planted or view.planting
			local ring = site.position + (myPos - site.position) * Vector3.new(1, 0, 1)
			ring = (ring - site.position).Magnitude > 0.1 and site.position + (ring - site.position).Unit * 10 or site.position
			local defusing = view.planted and view.planted.defuser
			local left = view.planted and math.max(0, view.planted.endsAt - workspace:GetServerTimeNow()) or nil
			tasks.HoldPlant = {
				score = cfg("Objective_HoldValue", 110) + (defusing and 40 or 0) - flat(site.position, myPos) * 0.2,
				point = ring, speed = run, engage = engage * (defusing and 1.5 or 1), urgency = (defusing or view.planting) and 1 or 0.6,
				paceWhy = defusing and "they are defusing" or "hold the Shrine",
				why = view.planting and string.format("cover the plant at %s", tostring(site.shrine))
					or defusing and string.format("stop the defuse at %s (%s)", tostring(site.shrine), clock(left))
					or string.format("guard the orb at %s (%s)", tostring(site.shrine), clock(left)),
			}
		end
	else
		if view.planted then
			-- the less time on it, the more it matters; with one already kneeling on it, the
			-- others keep the attackers off rather than stand in line
			local left = math.max(0, view.planted.endsAt - workspace:GetServerTimeNow())
			local mine = view.planted.defuser == quinModel.Name
			local someone = view.planted.defuser and not mine
			local away = (myPos - view.planted.position) * Vector3.new(1, 0, 1)
			away = away.Magnitude > 0.1 and away.Unit or Vector3.xAxis
			-- the less time to spare, the less it lets itself be drawn into a fight on the way: at
			-- the end it walks past the guards and kneels (it brawled on top of the orb till too late)
			local slack = left - cfg("Objective_DefuseTime", 7) * (1 - view.planted.defuse)
			local commit = math.clamp(slack / cfg("Objective_DefuseCommit", 15), 0, 1) * (0.5 + 0.5 * aggression)
			tasks.Retake = {
				score = cfg("Objective_RetakeValue", 150) + (1 - left / cfg("Objective_DetonateTime", 40)) * 80 - flat(view.planted.position, myPos) * 0.2,
				point = someone and view.planted.position + away * 8 or view.planted.position,
				speed = run, engage = someone and engage * 1.5 or engage * 0.6 * commit, urgency = 1, paceWhy = "it will go off",
				why = someone and string.format("cover the defuse at %s (%s)", tostring(view.planted.shrine), clock(left))
					or string.format("defuse at %s (%s left)", tostring(view.planted.shrine), clock(left)),
			}
		elseif view.planting then
			-- one is kneeling on a Shrine: a blow stops it
			tasks.Retake = {
				score = cfg("Objective_RetakeValue", 150) + 40 - flat(view.planting.position, myPos) * 0.2,
				point = view.planting.position, speed = run, engage = engage * 1.5, urgency = 1, paceWhy = "they are planting",
				why = string.format("stop the plant at %s", tostring(view.planting.shrine)),
			}
		end
		-- watch a Shrine: the one fewest teammates watch, near the way the attackers come
		local best, bestScore = nil, -math.huge
		for _, s in ipairs(view.shrines) do
			local sc = -takenBy("Guard", s.name, quinModel) * cfg("Objective_GuardTakenCost", 35) - flat(s.position, myPos) * 0.1
				+ (board.task and board.task.spot == s.name and 20 or 0)
			if sc > bestScore then best, bestScore = s, sc end
		end
		if best then
			-- each guard of that Shrine its own post round it, facing a different way in
			local toward = view.lantern.position or best.position
			local dir = Vector3.new(toward.X - best.position.X, 0, toward.Z - best.position.Z)
			dir = dir.Magnitude > 1 and dir.Unit or Vector3.new(0, 0, 1)
			local slot, count = slotAmong("Guard", best.name, quinModel)
			local angle = math.rad(cfg("Objective_GuardSpread", 55)) * (slot - (count + 1) / 2)
			-- a restless guard, having looked all round from its post, walks over to look from the
			-- other side of it (a steady one holds its post)
			local restless = pers(quinModel, "Pers_MobilityPreference", 0.5)
			local cycles = board.gaze and board.gaze.scanCycles or 0
			if restless >= cfg("Objective_PatrolRestless", 0.55) and cycles % 2 == 1 then
				angle += math.rad(cfg("Objective_PatrolSwing", 30)) * ((slot % 2 == 0) and 1 or -1)
			end
			local postDir = CFrame.fromAxisAngle(Vector3.yAxis, angle):VectorToWorldSpace(dir)
			local point = best.position + postDir * (cfg("Objective_GuardPost", 12) + (slot % 2) * 5)
			local far = flat(point, myPos) > 70
			tasks.Guard = {
				score = cfg("Objective_GuardValue", 70) + 20 * awareness + bestScore * 0.5, point = point, spot = best.name,
				face = point + postDir * 40, urgency = far and 0.55 or 0.3, paceWhy = far and "get to my post" or "to my post",
				speed = run, engage = engage * (1 + 0.5 * aggression),
				why = "watch " .. best.name,
			}
		end
	end
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
	-- what it set out to do pulls a little: it finishes a rescue or a hunt unless something is
	-- clearly better (measured: without it, rescues gave up for an equal fight or hunt at 2.5 s)
	local held = board.task
	if held and tasks[held.name] and tasks[held.name].score > -math.huge and not (pinned and held.name ~= "Fight") then
		local keep = cfg("Task_KeepValue", 25)
		if held.name == "Rescue" then
			-- on its way to a hurt ally: a protective Quin runs past the enemies in its path; an
			-- aggressive one takes the first fight it passes (habits, so the temperament shows:
			-- Guardian and Friendly push through, Hothead and Jester take the bait)
			keep += cfg("Task_RescueDevotion", 70) * pers(quinModel, "Pers_Protectiveness", 0.5) - cfg("Task_RescueDistraction", 40) * pers(quinModel, "Pers_Aggression", 0.6)
		end
		tasks[held.name].score += keep
	end
	local bestName, best = "Fight", tasks.Fight
	for name, t in pairs(tasks) do
		if t.score > best.score then bestName, best = name, t end
	end

	-- Keep the task it has for a moment unless another is clearly better
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
	board.task.enemy, board.task.ally, board.task.why, board.task.spot = best.enemy, best.ally, best.why, best.spot
	if quinModel:GetAttribute("TaskSpot") ~= best.spot then quinModel:SetAttribute("TaskSpot", best.spot) end
	if quinModel:GetAttribute("Task") ~= bestName then quinModel:SetAttribute("Task", bestName) end
	if quinModel:GetAttribute("TaskWhy") ~= best.why then quinModel:SetAttribute("TaskWhy", best.why) end
	if quinModel:GetAttribute("TaskAlly") ~= (best.ally or "") then quinModel:SetAttribute("TaskAlly", best.ally or "") end
	return { name = bestName, enemy = best.enemy, ally = best.ally, why = best.why,
		point = best.point, speed = best.speed, engage = best.engage, face = best.face,
		urgency = best.urgency, paceWhy = best.paceWhy }
end

return TaskChoice
