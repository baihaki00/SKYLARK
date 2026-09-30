--// QuinData.lua
-- Authoritative Base Stats Configuration for All Quins
-- Unified fair attributes for Male and Female Quins

local QuinData = {
	QuinDataVersion = 2,

	Standard = {
		DisplayName = "Standard Quin",
		-- Base Stats
		Health = 1000,
		Damage = 12,
		Speed = 50,

		-- Combat Stats
		AttackSpeed = 1.0,
		KnockbackResist = 0.05,
		ComboMax = 5,
		SpecialCooldown = 8,
		Defense = 0,
		JumpPower = 50,
		DashSpeed = 80,
		CriticalHitChance = 0.10,
		StunResist = 0.0,

		-- Physics
		Weight = 1.0,
		LaunchPower = 1.0,
		SlamPower = 1.0,
		AerialDamageBonus = 0.15,

		-- Recovery
		ComboRecovery = 0.25,
		BlockChance = 0.08,
		DodgeChance = 0.08,

		-- Super
		SuperMeterMax = 100,
		SuperGainPerHit = 5,
		SuperGainOnTakeDamage = 8,

		-- AI Personality Defaults
		Aggression = 0.65,
		SpecialPreference = 0.35,
	},
}

-- Aliases: all models and legacy types receive the identical, fair base stats
QuinData.Male = QuinData.Standard
QuinData.Female = QuinData.Standard
QuinData.Base = QuinData.Standard
QuinData.TypeA = QuinData.Standard
QuinData.TypeB = QuinData.Standard
QuinData.TypeC = QuinData.Standard
QuinData.TypeD = QuinData.Standard

-- Helper: get stats for a type/gender with safe defaults (all return fair base stats)
function QuinData.getStats(typeName)
	if typeName and QuinData[typeName] then
		return QuinData[typeName]
	end
	return QuinData.Standard
end

function QuinData.getBaseStats()
	return QuinData.Standard
end

return QuinData
