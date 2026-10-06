--// Rhythm.lua
-- The tempo of a fight (QUIN_CREATURE_DESIGN.md 5.6): a burst, a breath, a stare-down, an
-- explosion. Each fighter senses the exchange it is in (its own strikes and its opponent's) and
-- nudges the tempo, never the move:
--   breath    after a burst (BurstStrikes or more strikes between the two within BurstWindow),
--             once the strikes stop: a few seconds of sizing each other up (FightState waits
--             longer between strikes and may circle)
--   explode   engaged and nothing thrown for LullTime: the next action comes at once and hard
--             (a dash in, or a heavy strike)
-- Strikes are noted where they start (FightState.throwStrike, for AI and player alike).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CombatConfig = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("CombatConfig"))

local Rhythm = {}

local recent = setmetatable({}, { __mode = "k" }) -- quin -> { times of strikes it threw }
local breathUntil = setmetatable({}, { __mode = "k" })

local function cfg(key, default)
	local v = CombatConfig["Rhythm_" .. key]
	if v == nil then return default end
	return v
end

function Rhythm.enabled()
	-- (Studio: Workspace attribute Ablate_Rhythm switches it off live, for A/B by eye or probe)
	if workspace:GetAttribute("Ablate_Rhythm") and game:GetService("RunService"):IsStudio() then return false end
	return CombatConfig.Rhythm_Enabled ~= false
end

function Rhythm.noteStrike(quin)
	local list = recent[quin]
	if not list then
		list = {}
		recent[quin] = list
	end
	table.insert(list, os.clock())
	while #list > 12 do table.remove(list, 1) end
end

local function countSince(quin, since)
	local n, last = 0, 0
	for _, t in ipairs(recent[quin] or {}) do
		if t >= since then n += 1 end
		last = math.max(last, t)
	end
	return n, last
end

-- The tempo for `quin` fighting `opponent` now: "breath", "explode" or nil
function Rhythm.tempo(quin, opponent, engaged)
	if not Rhythm.enabled() or not opponent then return nil end
	local now = os.clock()
	-- a stand-off broken from circling (CirclingState): the first action comes hard
	if quin:GetAttribute("ExplodeNext") then
		quin:SetAttribute("ExplodeNext", nil)
		quin:SetAttribute("Tempo", "explode")
		return "explode"
	end
	if (breathUntil[quin] or 0) > now then return "breath" end
	local window = now - cfg("BurstWindow", 3)
	local mine, myLast = countSince(quin, window)
	local theirs, theirLast = countSince(opponent, window)
	local last = math.max(myLast, theirLast)
	-- a burst that has just stopped: breathe
	if mine + theirs >= cfg("BurstStrikes", 5) and now - last >= cfg("BurstEndGap", 0.6) then
		local breath = cfg("BreathMin", 1.2) + math.random() * (cfg("BreathMax", 2.5) - cfg("BreathMin", 1.2))
		breathUntil[quin] = now + breath
		recent[quin] = {} -- (the burst is spent)
		quin:SetAttribute("Tempo", "breath")
		return "breath"
	end
	-- a long lull while engaged: explode
	if engaged then
		local _, myAny = countSince(quin, 0)
		local _, theirAny = countSince(opponent, 0)
		local quiet = now - math.max(myAny, theirAny, quin:GetAttribute("EngagedSince") or now)
		if quiet >= cfg("LullTime", 4) then
			quin:SetAttribute("Tempo", "explode")
			return "explode"
		end
	end
	if quin:GetAttribute("Tempo") ~= nil then quin:SetAttribute("Tempo", nil) end
	return nil
end

return Rhythm
