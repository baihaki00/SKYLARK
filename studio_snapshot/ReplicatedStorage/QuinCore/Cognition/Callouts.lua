--// Cognition.Callouts
-- Shared team knowledge, out loud (Lantern Siege design, brain step 1; works in every mode).
-- A Quin that spots an enemy the team has not had eyes on for a while may call it out. Allies
-- within earshot of the shout take it as a second-hand belief (a "report" track that fades like
-- any memory) and may glance where it was called. Nothing is telepathy: a call has a place, a
-- time and a range; a Quin too far away never hears it.
-- Who calls is a leaning: aware Quins call more, nobody calls every time, and an enemy a teammate
-- called a moment ago is not called again.
-- Neutral (layer off): nobody calls and nobody hears; Memory's quiet sharing between Quins
-- standing close together still works.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local QuinCore = ReplicatedStorage:WaitForChild("QuinCore")
local CombatConfig = require(QuinCore:WaitForChild("CombatConfig"))

local Callouts = {}

local QUIET_STATES = { Knockback = true, Recovery = true, Death = true }

local calls = {} -- team -> { { id, caller, enemy, position, velocity, from, at } }, newest last
local nextId = 0

local function cfg(key, default)
	local v = CombatConfig.Cognition[key]
	if v == nil then return default end
	return v
end

local function teamList(team)
	local list = calls[team]
	if not list then
		list = {}
		calls[team] = list
	end
	return list
end

local function prune(list, now)
	local keep = cfg("CalloutKeep", 3)
	while list[1] and now - list[1].at > keep do
		table.remove(list, 1)
	end
end

-- Did a teammate call this enemy a moment ago?
local function recentlyCalled(list, enemy, now)
	for i = #list, 1, -1 do
		local call = list[i]
		if now - call.at > cfg("CalloutTeamRepeat", 4) then break end
		if call.enemy == enemy then return true end
	end
	return false
end

-- fresh: { percept } the enemies this Quin sees itself that the team has not had eyes on for a
-- while (Memory decides). Calls at most one, the nearest, now and then.
function Callouts.maybeCall(board, quinModel, rootPart, fresh, now)
	if #fresh == 0 or now < (board.nextCallout or 0) then return end
	if QUIET_STATES[quinModel:GetAttribute("CurrentState") or ""] then return end
	local team = quinModel:GetAttribute("Team") or "None"
	local list = teamList(team)
	prune(list, now)

	table.sort(fresh, function(a, b) return a.distance < b.distance end)
	for _, percept in ipairs(fresh) do
		if not recentlyCalled(list, percept.model, now) then
			local awareness = quinModel:GetAttribute("Pers_Awareness") or 0.65
			local chance = cfg("CalloutChanceBase", 0.35) + cfg("CalloutChanceAwareness", 0.5) * awareness
			board.nextCallout = now + cfg("CalloutCooldown", 2.5)
			if math.random() >= chance then return end
			nextId += 1
			table.insert(list, {
				id = nextId, caller = quinModel, enemy = percept.model, position = percept.position,
				velocity = percept.velocity, healthRatio = percept.healthRatio, energyRatio = percept.energyRatio,
				from = rootPart.Position, at = now,
			})
			board.called = { enemy = percept.model, at = now }
			quinModel:SetAttribute("CalloutOf", percept.model.Name)
			quinModel:SetAttribute("CalloutAt", workspace:GetServerTimeNow())
			return
		end
	end
end

-- Take in every call from this Quin's team made since it last listened, within earshot of where
-- it was shouted. learn(call) stores it as a belief; returns the newest call heard, or nil.
function Callouts.listen(board, quinModel, rootPart, now, learn)
	local team = quinModel:GetAttribute("Team") or "None"
	local list = calls[team]
	if not list then return nil end
	local lastId = board.lastCallId or 0
	local range = cfg("CalloutRange", 110)
	local heard = nil
	for _, call in ipairs(list) do
		if call.id > lastId then
			lastId = call.id
			if call.caller ~= quinModel and call.enemy.Parent and (call.from - rootPart.Position).Magnitude <= range then
				if learn(call) then heard = call end
			end
		end
	end
	board.lastCallId = lastId
	if heard then
		board.heard = { from = heard.caller, enemy = heard.enemy, at = now }
		quinModel:SetAttribute("HeardCalloutOf", heard.enemy.Name)
		quinModel:SetAttribute("HeardCalloutFrom", heard.caller.Name)
		quinModel:SetAttribute("HeardCalloutAt", workspace:GetServerTimeNow())
	end
	return heard
end

return Callouts
