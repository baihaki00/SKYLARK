--// Pers.lua
-- The one place a Quin's personality is read. Each Quin carries its habits as attributes
-- (Pers_Aggression ... Pers_Awareness: QuinInstance.attachToModel, drifted by Temperament); code
-- asks Pers.get(quin, "Aggression") instead of reading the attribute with its own fallback.
-- (Before: 100+ reads, and the fallbacks disagreed - aggression 0.5 / 0.6 / 0.7, awareness 0.6 /
-- 0.65 - so a rig without the attributes behaved differently file to file.)
--
-- Derived traits are worked out from the real ones, never stored:
--   DefensePreference  how readily it guards rather than trades: the opposite of its aggression and
--                      its appetite for risk. (Code read Pers_DefensePreference, which no Quin has:
--                      every Quin guarded at 0.5.)

local Pers = {}

-- What a Quin without the attribute (a test rig, a dummy) is taken to be: the middle of the ranges
Pers.DEFAULT = {
	Aggression = 0.6,
	RiskTolerance = 0.5,
	DashPreference = 0.6,
	RetreatTendency = 0.3,
	TargetPersistence = 0.7,
	Protectiveness = 0.5,
	MobilityPreference = 0.6,
	SpecialPreference = 0.35,
	Confidence = 0.6,
	Awareness = 0.65,
}

local DERIVED = {
	DefensePreference = function(quin)
		return math.clamp(1 - (Pers.get(quin, "Aggression") + Pers.get(quin, "RiskTolerance")) / 2, 0, 1)
	end,
}

function Pers.get(quin, dim)
	local value = quin and quin:GetAttribute("Pers_" .. dim)
	if value ~= nil then
		return value
	end
	local derive = DERIVED[dim]
	if derive then
		return derive(quin)
	end
	local default = Pers.DEFAULT[dim]
	if default == nil then
		warn("[Pers] no such personality trait: " .. tostring(dim))
		return 0.5
	end
	return default
end

return Pers
