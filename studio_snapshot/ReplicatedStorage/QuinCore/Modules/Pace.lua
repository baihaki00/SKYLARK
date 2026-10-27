--// Pace.lua
-- How fast a Quin goes, for every Quin in every mode (owner 2026-10-27: "most of them jog... the
-- pacing between idle run jog strafe needs to feel natural... run 0.5s then walk 0.5s looks
-- hesitant or stupid"). A state says how urgent its goal is (0 calm .. 1 now); Pace turns that
-- into a gear - Walk, Jog or Run - and holds it:
--   * habits tilt it: an aggressive Quin hurries where a calm one jogs (the same situation, two
--     different Quins, two different gears - no random timers)
--   * it shifts up at once when the urgency rises (something happened: be decisive) and down only
--     once the urgency has stayed low a moment (a persistent Quin holds its pace longer). A small
--     wobble in the urgency never flips the gait.
--   * arriving at a spot it eases off over the last stretch, so it comes in walking instead of
--     sprinting to the spot and braking (the stop-run plant all of them did at once)
-- Off: CombatConfig.Pace_Enabled = false, or Workspace attribute PaceOff = true (live A/B).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local QuinCore = ReplicatedStorage:WaitForChild("QuinCore")
local CombatConfig = require(QuinCore:WaitForChild("CombatConfig"))

local Pace = {}

local GEARS = { "Walk", "Jog", "Run" }
local RANK = { Walk = 1, Jog = 2, Run = 3 }

local state = setmetatable({}, { __mode = "k" })

local function cfg(key, default)
	local v = CombatConfig[key]
	if v == nil then return default end
	return v
end

function Pace.enabled()
	return cfg("Pace_Enabled", true) ~= false and workspace:GetAttribute("PaceOff") ~= true
end

function Pace.speedOf(fighter, gear)
	if gear == "Walk" then return cfg("Player_WalkSpeed", 7.5) end
	if gear == "Jog" then return cfg("Pace_JogSpeed", 13) end
	return fighter:GetAttribute("Speed") or 40
end

-- The urgency as this Quin feels it: hot heads hurry, the tired save their legs
function Pace.felt(fighter, urgency)
	local aggression = fighter:GetAttribute("Pers_Aggression") or 0.5
	local felt = urgency + (aggression - 0.5) * cfg("Pace_AggressionTilt", 0.3)
	local energy, maxEnergy = fighter:GetAttribute("Energy"), fighter:GetAttribute("MaxEnergy") or 100
	if energy and maxEnergy > 0 and energy / maxEnergy < cfg("Pace_TiredShare", 0.3) then
		felt -= cfg("Pace_TiredCost", 0.25)
	end
	return math.clamp(felt, 0, 1)
end

local function wanted(felt)
	if felt >= cfg("Pace_RunAt", 0.62) then return "Run" end
	if felt >= cfg("Pace_JogAt", 0.28) then return "Jog" end
	return "Walk"
end

-- The gear (and its speed) for an urgency, held with commitment. why: shown on the debug HUD.
function Pace.gear(fighter, urgency, why)
	local now = os.clock()
	local s = state[fighter]
	if not s then
		s = { gear = nil, lowSince = nil }
		state[fighter] = s
	end
	local felt = Pace.felt(fighter, urgency)
	local want = wanted(felt)
	if not s.gear or RANK[want] > RANK[s.gear] then
		s.gear, s.lowSince = want, nil
	elseif RANK[want] < RANK[s.gear] then
		-- down only when clearly below this gear's threshold, and for a moment
		local floor = s.gear == "Run" and cfg("Pace_RunAt", 0.62) or cfg("Pace_JogAt", 0.28)
		if felt < floor - cfg("Pace_Hysteresis", 0.08) then
			s.lowSince = s.lowSince or now
			local persistence = fighter:GetAttribute("Pers_TargetPersistence") or 0.5
			if now - s.lowSince >= cfg("Pace_DownshiftHold", 0.6) + cfg("Pace_PersistenceHold", 0.9) * persistence then
				s.gear, s.lowSince = GEARS[RANK[s.gear] - 1], nil
			end
		else
			s.lowSince = nil
		end
	else
		s.lowSince = nil
	end
	if fighter:GetAttribute("PaceGear") ~= s.gear then fighter:SetAttribute("PaceGear", s.gear) end
	if why and fighter:GetAttribute("PaceWhy") ~= why then fighter:SetAttribute("PaceWhy", why) end
	return Pace.speedOf(fighter, s.gear), s.gear
end

-- Ease off over the last stretch to a spot (not to an enemy: Chase has its own brake into a fight)
function Pace.arrive(speed, distanceLeft)
	local d = math.max(distanceLeft, 0)
	return math.min(speed, math.sqrt(2 * cfg("Pace_ArriveDecel", 28) * d) + cfg("Pace_ArriveFloor", 3))
end

-- How long it takes this Quin to take in something new before acting on it (alert Quins are
-- quick). The same news reaches a team at once; they do not all move on the same frame.
function Pace.reaction(fighter)
	local awareness = fighter:GetAttribute("Pers_Awareness") or 0.6
	return cfg("Pace_ReactionMin", 0.15) + cfg("Pace_ReactionSpan", 0.65) * (1 - awareness)
end

function Pace.reset(fighter)
	state[fighter] = nil
end

return Pace
