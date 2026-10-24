--// Temperament.lua
-- Who a Quin is, and how what happens to it reshapes how it fights (owner, 2026-10-24;
-- QUIN_TEMPERAMENT.md). Three layers:
--   * Mood: seconds to minutes inside a match (CurrentConfidence, PersonalitySystem). Fades.
--   * Habits: the 10 PersonalitySystem dimensions. Small steps after every match, up AND down,
--     from what happened in it, from training and from plans. Saved on the Quin; never slide back
--     on their own while it sits.
--   * Temperament: a name (Friendly, Hothead, ...) that never changes. It is a leaning, not a
--     rule: it tilts the habits a Quin is born with, and decides what comes easily (toward its
--     nature) and what takes work (away from it). Every Quin uses the same brain.
-- Rules for the habit steps (applyMatch):
--   * Links: some habits pull on each other (more Aggression, a bit less Awareness ...).
--   * Away from its nature (outside the home range) a step gets harder the further it goes.
--   * Against what the owner is training (TrainingFocus), a step counts a third (1:3), so one bad
--     session can't undo days of work. Untrained habits move freely both ways.
--   * One session moves a habit at most SESSION_CAP.
--   * Under stress (a losing streak) habits far from its nature ease back a little. Only from hard
--     fights, never from time.

local Temperament = {}

local STRONG, NORMAL, GENTLE = 0.22, 0.14, 0.07

Temperament.SESSION_CAP = 0.015 -- (habits are 0..1: 1.5 points on a 100 scale)
Temperament.AGAINST_TRAINING = 1 / 3
Temperament.HOME_RANGE = 0.15 -- (either side of its nature's centre: inside it, steps are free)
Temperament.FAR_RANGE = 0.30 -- (by here, a step away from its nature counts AWAY_FROM_NATURE)
Temperament.AWAY_FROM_NATURE = 0.1
Temperament.LINK_PULL = 0.4
Temperament.STRESS_STREAK = 3
Temperament.STRESS_PULL = 0.003

-- How each temperament tilts a newborn's habits (added on top of its Type's roll)
Temperament.LEANINGS = {
	Hothead = { Aggression = STRONG, TargetPersistence = NORMAL, RiskTolerance = NORMAL, Awareness = -NORMAL, RetreatTendency = -NORMAL },
	Jester = { DashPreference = NORMAL, MobilityPreference = NORMAL, SpecialPreference = NORMAL, TargetPersistence = -NORMAL, Protectiveness = -GENTLE },
	Egoist = { Confidence = STRONG, SpecialPreference = NORMAL, Protectiveness = -NORMAL },
	Stoic = { Confidence = NORMAL, Awareness = NORMAL, DashPreference = -NORMAL, RiskTolerance = -NORMAL },
	Wary = { RetreatTendency = STRONG, Awareness = NORMAL, MobilityPreference = NORMAL, RiskTolerance = -NORMAL, Confidence = -NORMAL },
	Hunter = { TargetPersistence = STRONG, Awareness = NORMAL, Protectiveness = -NORMAL },
	Guardian = { Protectiveness = STRONG, Confidence = NORMAL, MobilityPreference = -NORMAL },
	FreeSpirit = { MobilityPreference = STRONG, RiskTolerance = NORMAL, TargetPersistence = -NORMAL, SpecialPreference = -NORMAL, Protectiveness = -NORMAL },
	Friendly = { Protectiveness = NORMAL, Awareness = NORMAL, Aggression = -NORMAL, TargetPersistence = -NORMAL },
	Gambler = { RiskTolerance = STRONG, SpecialPreference = NORMAL, DashPreference = NORMAL, RetreatTendency = -NORMAL },
	Opportunist = { Awareness = STRONG, MobilityPreference = NORMAL, Aggression = -NORMAL, Protectiveness = -NORMAL },
}

Temperament.NAMES = {}
for name in pairs(Temperament.LEANINGS) do
	table.insert(Temperament.NAMES, name)
end
table.sort(Temperament.NAMES)

Temperament.DISPLAY = { FreeSpirit = "Free Spirit" }

-- Habits that pull on each other: a step in one moves its partner the other way
Temperament.LINKS = {
	Aggression = "Awareness",
	Awareness = "Aggression",
	RetreatTendency = "Confidence",
	Confidence = "RetreatTendency",
	Protectiveness = "TargetPersistence",
	TargetPersistence = "Protectiveness",
}

function Temperament.isValid(name)
	return Temperament.LEANINGS[name] ~= nil
end

function Temperament.random(rng)
	local i = rng and rng:NextInteger(1, #Temperament.NAMES) or math.random(1, #Temperament.NAMES)
	return Temperament.NAMES[i]
end

function Temperament.displayName(name)
	return Temperament.DISPLAY[name] or name
end

-- A newborn's habits: its Type's roll, tilted by the temperament
function Temperament.tilt(personality, name)
	local leaning = Temperament.LEANINGS[name]
	if not leaning then
		return personality
	end
	for habit, shift in pairs(leaning) do
		if type(personality[habit]) == "number" then
			personality[habit] = math.round(math.clamp(personality[habit] + shift, 0.02, 0.98) * 100) / 100
		end
	end
	return personality
end

-- Its nature's centre for a habit: the middle of its Type's range, tilted
function Temperament.homeCentre(typeBounds, name, habit)
	local b = typeBounds and typeBounds[habit]
	local mid = b and (b.min + b.max) / 2 or 0.5
	local leaning = Temperament.LEANINGS[name]
	return math.clamp(mid + (leaning and leaning[habit] or 0), 0.02, 0.98)
end

-- What a match did to the habits, before the rules. Each count is judged against the match's
-- average (`average`: the same counts over every fighter), so across a match the steps cancel
-- out: no habit creeps one way for every Quin, yet each reacts to its own good and bad fights.
function Temperament.matchDeltas(counts, outcome, average)
	average = average or {}
	local d = {}
	local function add(habit, amount)
		d[habit] = (d[habit] or 0) + amount
	end
	-- (relative to the average: 3 more knockbacks than an average of 13 is a small step, one
	-- more KO than an average of 0.7 a big one)
	local function vsAverage(key)
		local avg = average[key] or 0
		return math.clamp(((counts[key] or 0) - avg) / math.max(1, avg) * 2, -2, 2)
	end
	local kills = vsAverage("Kills") -- (more KOs than most: bolder)
	local downs = vsAverage("KnockedDown") -- (knocked down more than most: warier)
	local surrounds = vsAverage("SurroundsSurvived") -- (came through more gang-ups: more watchful)
	add("Confidence", 0.003 * kills - 0.003 * downs)
	add("Aggression", 0.002 * kills - 0.002 * downs)
	add("RetreatTendency", 0.003 * downs)
	add("Awareness", 0.004 * surrounds)
	if outcome == "Win" then
		add("Confidence", 0.004)
	elseif outcome == "Loss" then
		add("Confidence", -0.004)
	end
	return d
end

-- Apply one session's habit steps to a saved Quin (QuinInstance). typeBounds: its Type's ranges.
-- cap: the most one habit may move (default SESSION_CAP; a Trainer session passes its own).
-- Returns { [habit] = applied step } for what moved.
function Temperament.applyMatch(instance, rawDeltas, typeBounds, cap)
	cap = cap or Temperament.SESSION_CAP
	local habits = instance.Personality
	if not habits then
		return {}
	end
	local name = instance.Temperament
	local focus = instance.TrainingFocus or {}

	-- links
	local deltas = {}
	for habit, amount in pairs(rawDeltas) do
		deltas[habit] = (deltas[habit] or 0) + amount
	end
	for habit, amount in pairs(rawDeltas) do
		local partner = Temperament.LINKS[habit]
		if partner then
			deltas[partner] = (deltas[partner] or 0) - amount * Temperament.LINK_PULL
		end
	end

	-- stress: a losing streak eases habits far from its nature back toward it
	local streak = instance.BattleRecord and instance.BattleRecord.LossStreak or 0
	if streak >= Temperament.STRESS_STREAK then
		for habit, value in pairs(habits) do
			local centre = Temperament.homeCentre(typeBounds, name, habit)
			if math.abs(value - centre) > Temperament.HOME_RANGE then
				deltas[habit] = (deltas[habit] or 0) + (centre > value and 1 or -1) * Temperament.STRESS_PULL
			end
		end
	end

	local applied = {}
	instance.HabitTrend = instance.HabitTrend or {}
	for habit, step in pairs(deltas) do
		local value = habits[habit]
		if type(value) == "number" and step ~= 0 then
			local wanted = focus[habit]
			if wanted and wanted ~= 0 and (step > 0) ~= (wanted > 0) then
				step *= Temperament.AGAINST_TRAINING
			end
			local centre = Temperament.homeCentre(typeBounds, name, habit)
			local distance = math.abs(value - centre)
			local away = (value > centre) == (step > 0)
			if away and distance > Temperament.HOME_RANGE then
				local t = math.clamp((distance - Temperament.HOME_RANGE) / (Temperament.FAR_RANGE - Temperament.HOME_RANGE), 0, 1)
				step *= 1 - t * (1 - Temperament.AWAY_FROM_NATURE)
			end
			step = math.clamp(step, -cap, cap)
			local new = math.round(math.clamp(value + step, 0.02, 0.98) * 1000) / 1000
			if new ~= value then
				habits[habit] = new
				applied[habit] = new - value
				instance.HabitTrend[habit] = math.round(((instance.HabitTrend[habit] or 0) * 0.7 + (new - value)) * 1000) / 1000
			end
		end
	end
	return applied
end

-- Every two temperaments must clearly differ on at least `need` habits. Returns the pairs that don't.
function Temperament.checkUnique(need, gap)
	need, gap = need or 3, gap or 0.12
	local clashes = {}
	for i, a in ipairs(Temperament.NAMES) do
		for j = i + 1, #Temperament.NAMES do
			local b = Temperament.NAMES[j]
			local la, lb = Temperament.LEANINGS[a], Temperament.LEANINGS[b]
			local differ, seen = 0, {}
			for habit in pairs(la) do seen[habit] = true end
			for habit in pairs(lb) do seen[habit] = true end
			for habit in pairs(seen) do
				if math.abs((la[habit] or 0) - (lb[habit] or 0)) >= gap then
					differ += 1
				end
			end
			if differ < need then
				table.insert(clashes, string.format("%s/%s (%d)", a, b, differ))
			end
		end
	end
	return clashes
end

return Temperament
