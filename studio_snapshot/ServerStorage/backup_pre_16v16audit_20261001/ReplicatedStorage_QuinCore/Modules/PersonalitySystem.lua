--// PersonalitySystem.lua
-- Canonical 9-dimension personality evaluation and Type-constrained generation
-- Personality represents individual behavioral bias and preference, NOT hard command logic

local PersonalitySystem = {
	PersonalityVersion = 1,
}

-- The 9 canonical personality dimensions
PersonalitySystem.DIMENSIONS = {
	"Aggression",
	"RiskTolerance",
	"DashPreference",
	"RetreatTendency",
	"TargetPersistence",
	"Protectiveness",
	"MobilityPreference",
	"SpecialPreference",
	"Confidence", -- BaseConfidence
	"Awareness", -- Directional & 360 Spatial Threat Detection
}

-- Baseline generation bounds by combat chassis (Type)
-- Ensures two Quins of the same Type vary, but adhere to believable archetype tendencies
local TYPE_BOUNDS = {
	TypeA = { -- Striker (Balanced Offensive)
		Aggression         = { min = 0.55, max = 0.85 },
		RiskTolerance      = { min = 0.40, max = 0.70 },
		DashPreference     = { min = 0.50, max = 0.80 },
		RetreatTendency    = { min = 0.20, max = 0.50 },
		TargetPersistence  = { min = 0.50, max = 0.75 },
		Protectiveness     = { min = 0.30, max = 0.60 },
		MobilityPreference = { min = 0.50, max = 0.80 },
		SpecialPreference  = { min = 0.20, max = 0.50 },
		Confidence         = { min = 0.50, max = 0.80 },
		Awareness          = { min = 0.55, max = 0.85 },
	},

	TypeB = { -- Tank (Protector, Anchor, Tenacious)
		Aggression         = { min = 0.30, max = 0.60 },
		RiskTolerance      = { min = 0.60, max = 0.90 },
		DashPreference     = { min = 0.30, max = 0.60 },
		RetreatTendency    = { min = 0.10, max = 0.35 },
		TargetPersistence  = { min = 0.60, max = 0.85 },
		Protectiveness     = { min = 0.70, max = 0.95 },
		MobilityPreference = { min = 0.20, max = 0.50 },
		SpecialPreference  = { min = 0.15, max = 0.40 },
		Confidence         = { min = 0.60, max = 0.85 },
		Awareness          = { min = 0.40, max = 0.70 },
	},

	TypeC = { -- Assassin (High Mobility, Hit-and-Run, Opportunity Seeker)
		Aggression         = { min = 0.75, max = 0.98 },
		RiskTolerance      = { min = 0.50, max = 0.80 },
		DashPreference     = { min = 0.75, max = 0.98 },
		RetreatTendency    = { min = 0.30, max = 0.65 },
		TargetPersistence  = { min = 0.65, max = 0.90 },
		Protectiveness     = { min = 0.10, max = 0.35 },
		MobilityPreference = { min = 0.80, max = 1.00 },
		SpecialPreference  = { min = 0.40, max = 0.75 },
		Confidence         = { min = 0.55, max = 0.85 },
		Awareness          = { min = 0.75, max = 0.98 },
	},

	TypeD = { -- Brawler (Relentless Pressure, High Risk Tolerance)
		Aggression         = { min = 0.65, max = 0.90 },
		RiskTolerance      = { min = 0.65, max = 0.95 },
		DashPreference     = { min = 0.60, max = 0.85 },
		RetreatTendency    = { min = 0.15, max = 0.40 },
		TargetPersistence  = { min = 0.70, max = 0.95 },
		Protectiveness     = { min = 0.30, max = 0.60 },
		MobilityPreference = { min = 0.40, max = 0.70 },
		SpecialPreference  = { min = 0.30, max = 0.60 },
		Confidence         = { min = 0.65, max = 0.90 },
		Awareness          = { min = 0.35, max = 0.65 },
	},
}

-- Generate a persistent personality for a genuinely new Quin
function PersonalitySystem.generate(typeName, customOverrides, rng)
	local bounds = TYPE_BOUNDS[typeName] or TYPE_BOUNDS.TypeA
	local personality = {}

	local randomFloat = function(min, max)
		local r
		if rng and type(rng) == "userdata" then
			r = rng:NextNumber()
		else
			r = math.random()
		end
		-- 2 decimal precision (e.g., 0.75)
		local val = min + r * (max - min)
		return math.round(val * 100) / 100
	end

	for _, dim in ipairs(PersonalitySystem.DIMENSIONS) do
		local b = bounds[dim] or { min = 0.35, max = 0.65 }
		personality[dim] = randomFloat(b.min, b.max)
	end

	-- Apply any explicit overrides (e.g. for deterministic testing or preset benchmarks)
	if customOverrides and type(customOverrides) == "table" then
		for k, v in pairs(customOverrides) do
			if personality[k] ~= nil and type(v) == "number" then
				personality[k] = math.clamp(math.round(v * 100) / 100, 0, 1)
			end
		end
	end

	return personality
end

-- Validate and normalize a personality table
function PersonalitySystem.validate(personality)
	if type(personality) ~= "table" then
		return false, "Personality must be a table"
	end
	for _, dim in ipairs(PersonalitySystem.DIMENSIONS) do
		local val = personality[dim]
		if type(val) ~= "number" or val < 0 or val > 1 then
			return false, string.format("Dimension %s must be a number between 0 and 1 (got %s)", dim, tostring(val))
		end
	end
	return true
end

-- Safely retrieve a dimension value (clamped between 0 and 1, defaults to 0.5)
function PersonalitySystem.getWeight(personality, dimension)
	if not personality or type(personality) ~= "table" then
		return 0.5
	end
	local val = personality[dimension]
	if type(val) ~= "number" then
		return 0.5
	end
	return math.clamp(val, 0, 1)
end

-- Compute dynamic runtime confidence based on BaseConfidence, health ratio, and local numerical advantage
function PersonalitySystem.computeEffectiveConfidence(baseConfidence, healthRatio, localAdvantageRatio)
	local base = math.clamp(baseConfidence or 0.5, 0.1, 1.0)
	local hp = math.clamp(healthRatio or 1.0, 0.0, 1.0)
	local adv = math.clamp(localAdvantageRatio or 1.0, 0.2, 5.0)

	-- Health influence (-0.25 to +0.10)
	local hpDelta = (hp - 0.5) * 0.35
	-- Advantage influence (-0.20 to +0.20)
	local advDelta = math.clamp((adv - 1.0) * 0.15, -0.25, 0.25)

	local currentConfidence = math.clamp(base + hpDelta + advDelta, 0.05, 0.98)
	return math.round(currentConfidence * 100) / 100
end

-- Adjust runtime confidence dynamically based on in-combat events
function PersonalitySystem.applyEventToConfidence(quinModel, eventType, magnitude)
	if not quinModel or not quinModel.Parent then return end
	local cur = quinModel:GetAttribute("CurrentConfidence") or (quinModel:GetAttribute("Pers_Confidence") or 0.6)
	local mag = magnitude or 1.0
	local delta = 0

	if eventType == "HitLanded" then
		delta = 0.04 * mag
	elseif eventType == "TargetKilled" then
		delta = 0.20 * mag
		PersonalitySystem.recordCombatOutcome(quinModel, "Kill", {})
	elseif eventType == "DamageTaken" then
		delta = -0.08 * mag
	elseif eventType == "Interrupted" then
		delta = -0.06 * mag
	elseif eventType == "Surrounded" then
		delta = -0.15 * mag
	elseif eventType == "Decay" then
		-- Passive decay back towards BaseConfidence
		local base = quinModel:GetAttribute("Pers_Confidence") or 0.6
		delta = (base - cur) * 0.1 * mag
	end

	local updated = math.clamp(cur + delta, 0.05, 0.98)
	quinModel:SetAttribute("CurrentConfidence", math.round(updated * 100) / 100)
	return updated
end

-- ============================================================
-- Phase 10: Quirkies & Behavioral Identity Evolution
-- ============================================================

-- Evaluates and assigns an initial Quirky based on personality vectors
function PersonalitySystem.assignInitialQuirky(quinModel, typeName, personality)
	if not quinModel then return "Balanced" end
	personality = personality or {}

	local aggression = personality.Aggression or (quinModel:GetAttribute("Pers_Aggression") or 0.6)
	local dashPref = personality.DashPreference or (quinModel:GetAttribute("Pers_DashPreference") or 0.6)
	local awareness = personality.Awareness or (quinModel:GetAttribute("Pers_Awareness") or 0.6)
	local mobility = personality.MobilityPreference or (quinModel:GetAttribute("Pers_MobilityPreference") or 0.6)
	local confidence = personality.Confidence or (quinModel:GetAttribute("Pers_Confidence") or 0.6)
	local retreatTendency = personality.RetreatTendency or (quinModel:GetAttribute("Pers_RetreatTendency") or 0.3)
	local riskTolerance = personality.RiskTolerance or (quinModel:GetAttribute("Pers_RiskTolerance") or 0.5)

	local quirky = "Balanced"

	if aggression >= 0.80 and dashPref >= 0.75 then
		quirky = "Charger"
	elseif awareness >= 0.80 and mobility >= 0.75 then
		quirky = "Observer"
	elseif confidence >= 0.80 and riskTolerance >= 0.75 then
		quirky = "Showoff"
	elseif confidence <= 0.40 or retreatTendency >= 0.55 then
		quirky = "Low-Confidence"
	elseif confidence >= 0.85 and retreatTendency <= 0.20 then
		quirky = "Overconfident"
	elseif mobility >= 0.80 and riskTolerance >= 0.70 then
		quirky = "WallTapper"
	end

	quinModel:SetAttribute("Quirky", quirky)
	return quirky
end

-- Tracks combat outcomes to dynamically evolve Quirkies and grudges
function PersonalitySystem.recordCombatOutcome(quinModel, eventType, context)
	if not quinModel or not quinModel.Parent then return end
	context = context or {}

	if eventType == "DamageReceived" then
		local attackerName = context.AttackerName
		local damage = context.Damage or 0
		if attackerName and attackerName ~= "" and damage >= 20 then
			local grudgeCount = (quinModel:GetAttribute("GrudgeHits_" .. attackerName) or 0) + 1
			quinModel:SetAttribute("GrudgeHits_" .. attackerName, grudgeCount)
			if grudgeCount >= 2 then
				quinModel:SetAttribute("Quirky", "Revengeful")
				quinModel:SetAttribute("GrudgeTarget", attackerName)
			end
		end

	elseif eventType == "Kill" then
		local streak = (quinModel:GetAttribute("CombatKillStreak") or 0) + 1
		quinModel:SetAttribute("CombatKillStreak", streak)
		local currentQuirky = quinModel:GetAttribute("Quirky") or "Balanced"
		if streak >= 2 and currentQuirky ~= "Revengeful" then
			quinModel:SetAttribute("Quirky", "Showoff")
		end
		-- Clear grudge if we killed our grudge target
		local grudge = quinModel:GetAttribute("GrudgeTarget")
		if grudge and context.TargetName == grudge then
			quinModel:SetAttribute("GrudgeTarget", nil)
			quinModel:SetAttribute("Quirky", "Balanced")
		end

	elseif eventType == "SurroundSurvived" then
		-- Escaped a 1v3+ surround with low HP -> develops Observer caution
		quinModel:SetAttribute("Quirky", "Observer")

	elseif eventType == "KnockedDown" then
		local currentQuirky = quinModel:GetAttribute("Quirky") or "Balanced"
		if currentQuirky == "Showoff" or currentQuirky == "Overconfident" then
			-- Humbled: lose arrogant quirky
			quinModel:SetAttribute("Quirky", "Balanced")
		end
	end
end

return PersonalitySystem
