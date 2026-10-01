--// Cognition.Attention
-- What matters most right now. Every noticed enemy gets a salience score; only the top few
-- (the Quin's capacity) are attended. Unattended enemies are still in front of the Quin, but it
-- is not keeping track of them: Memory only refreshes what Attention holds.
-- Capacity comes from awareness, and narrows while the Quin is locked in a fight (aggressive
-- Quins tunnel the most).
-- Neutral (layer off): everything noticed is attended.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local QuinCore = ReplicatedStorage:WaitForChild("QuinCore")
local CombatConfig = require(QuinCore:WaitForChild("CombatConfig"))

local Attention = {}

local ENGAGED_STATES = { Fight = true, Special = true, BeamStruggle = true }

function Attention.capacity(quinModel)
	local cfg = CombatConfig.Cognition
	local awareness = quinModel:GetAttribute("Pers_Awareness") or 0.65
	local capacity = cfg.AttentionCapacityMin + awareness * (cfg.AttentionCapacityMax - cfg.AttentionCapacityMin)
	if ENGAGED_STATES[quinModel:GetAttribute("CurrentState") or ""] then
		capacity -= (quinModel:GetAttribute("Pers_Aggression") or 0.6) * cfg.AttentionEngagedPenalty
	end
	return math.clamp(math.round(capacity), 1, cfg.AttentionCapacityMax)
end

local function salience(quinModel, percept, targetName, aggression)
	local other = percept.model
	local score = 100 * math.exp(-percept.distance / 40) -- nearer is louder
	local reasons = {}
	if other.Name == targetName then
		score += 60
		table.insert(reasons, "my target")
	end
	local otherTarget = other:GetAttribute("CurrentTarget") or other:GetAttribute("TargetQuin")
	if otherTarget == quinModel.Name then
		score += 50
		table.insert(reasons, "after me")
		if other:GetAttribute("Attacking") == true then
			score += 40
			table.insert(reasons, "swinging at me")
		end
	end
	if percept.channel == "touch" then
		score += 80
		table.insert(reasons, "in my face")
	end
	if other:GetAttribute("CurrentState") == "ProjectileJump" then
		score += 20
		table.insert(reasons, "incoming jump")
	end
	if percept.healthRatio < 0.5 then
		score += 30 * (1 - percept.healthRatio) * (0.5 + aggression)
		table.insert(reasons, "wounded")
	end
	return score, reasons
end

function Attention.rank(quinModel, percepts, enabled)
	local targetName = quinModel:GetAttribute("CurrentTarget") or quinModel:GetAttribute("TargetQuin")
	local aggression = quinModel:GetAttribute("Pers_Aggression") or 0.6

	local ranked = {}
	for _, percept in ipairs(percepts) do
		if not percept.isAlly and percept.channel then
			percept.salience, percept.salienceReasons = salience(quinModel, percept, targetName, aggression)
			table.insert(ranked, percept)
		end
	end
	table.sort(ranked, function(a, b) return a.salience > b.salience end)

	local capacity = enabled and Attention.capacity(quinModel) or #ranked
	for index, percept in ipairs(ranked) do
		percept.attended = index <= capacity
	end
	return { ranked = ranked, capacity = capacity }
end

return Attention
