--// FightMaths.lua
-- Count before committing (Lantern Siege design, brain step 3; works in every mode). Around a spot
-- (an enemy it may take on), how many of each side does this Quin believe are there? Only what it
-- knows - its own eyes, memory and the team's callouts - never the whole arena. Each Quin counts
-- by its health, so two wounded enemies weigh like one fresh one.
-- The cost is a leaning, read from habits (so the temperament shows through them): a risk-taking,
-- confident Quin walks into a 1v2; a cautious one looks for better. Only bad odds cost: good odds
-- earn nothing (TargetingModule already keeps allies from piling onto one enemy).
-- Off: CombatConfig.FightMaths_Enabled = false, or Workspace attribute FightMathsOff = true (live A/B).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local QuinCore = ReplicatedStorage:WaitForChild("QuinCore")
local CombatConfig = require(QuinCore:WaitForChild("CombatConfig"))
local Blackboard = require(QuinCore:WaitForChild("Cognition"):WaitForChild("Blackboard"))

local FightMaths = {}

local function cfg(key, default)
	local v = CombatConfig[key]
	if v == nil then return default end
	return v
end

function FightMaths.enabled()
	return cfg("FightMaths_Enabled", true) ~= false and workspace:GetAttribute("FightMathsOff") ~= true
end

-- Believed sides around a spot: allies (with itself) and enemies, each weighted 0.4..1 by health
function FightMaths.sides(quinModel, rootPart, spot)
	local board = Blackboard.peek(quinModel)
	if not board or not board.contacts then return nil end
	local radius = cfg("FightMaths_Radius", 25)
	local function weight(hp) return 0.4 + 0.6 * math.clamp(hp or 1, 0, 1) end
	local flatSpot = Vector3.new(spot.X, 0, spot.Z)
	local function near(pos) return (Vector3.new(pos.X, 0, pos.Z) - flatSpot).Magnitude <= radius end

	local humanoid = quinModel:FindFirstChildOfClass("Humanoid")
	local allies = weight(humanoid and humanoid.Health / math.max(1, humanoid.MaxHealth) or 1)
	local enemies, nEnemies, nAllies = 0, 0, 1
	for _, contact in ipairs(board.contacts.allies or {}) do
		if near(contact.position) then
			allies += weight(contact.healthRatio)
			nAllies += 1
		end
	end
	for _, contact in ipairs(board.contacts.enemies or {}) do
		if near(contact.position) then
			-- a belief it holds loosely counts loosely
			enemies += weight(contact.healthRatio) * math.clamp(contact.confidence or 1, 0.3, 1)
			nEnemies += 1
		end
	end
	return allies, enemies, nAllies, nEnemies
end

-- Utility off for taking on an enemy at `spot` (0 when the odds are even or better), and a
-- reason such as "bad odds there (1 v 3)"
function FightMaths.cost(quinModel, rootPart, spot, confidence)
	if not FightMaths.enabled() then return 0 end
	local allies, enemies, nAllies, nEnemies = FightMaths.sides(quinModel, rootPart, spot)
	if not allies then return 0 end
	local deficit = enemies - allies
	if deficit <= cfg("FightMaths_Slack", 0.25) then return 0 end
	local risk = quinModel:GetAttribute("Pers_RiskTolerance") or 0.5
	confidence = confidence or quinModel:GetAttribute("CurrentConfidence") or 0.6
	local caution = math.clamp(1.3 - risk * 0.8 - confidence * 0.5, 0.15, 1.2)
	return math.min(deficit, 3) * cfg("FightMaths_Weight", 40) * caution, string.format("bad odds there (%d v %d)", nAllies, nEnemies)
end

return FightMaths
