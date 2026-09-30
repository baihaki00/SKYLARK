--// QuinData.lua
-- Stat templates for each Quin type
-- Add new types or tweak stats here to customize each fighter
-- Each Quin model gets these values applied as Attributes at spawn

local QuinData = {
	QuinDataVersion = 1,

	TypeA = {
		DisplayName = "Striker",
		-- Base Stats
		Health = 1000,
		Damage = 12,
		Speed = 60,

		-- Combat Stats
		AttackSpeed = 1.0,
		KnockbackResist = 0.0,
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
		ComboRecovery = 0.3,
		BlockChance = 0.05,
		DodgeChance = 0.08,

		-- Super
		SuperMeterMax = 100,
		SuperGainPerHit = 5,
		SuperGainOnTakeDamage = 8,

		-- AI Personality Defaults (for backward compatibility)
		Aggression = 0.7,
		SpecialPreference = 0.3,
	},

	TypeB = {
		DisplayName = "Tanker",
		Health = 1400,
		Damage = 10,
		Speed = 60,

		AttackSpeed = 0.8,
		KnockbackResist = 0.35,
		ComboMax = 4,
		SpecialCooldown = 10,
		Defense = 8,
		JumpPower = 40,
		DashSpeed = 60,
		CriticalHitChance = 0.05,
		StunResist = 0.25,

		Weight = 1.5,
		LaunchPower = 0.7,
		SlamPower = 1.3,
		AerialDamageBonus = 0.05,

		ComboRecovery = 0.5,
		BlockChance = 0.20,
		DodgeChance = 0.03,

		SuperMeterMax = 100,
		SuperGainPerHit = 3,
		SuperGainOnTakeDamage = 12,

		Aggression = 0.4,
		SpecialPreference = 0.2,
	},

	TypeC = {
		DisplayName = "Assassin",
		Health = 700,
		Damage = 15,
		Speed = 55,

		AttackSpeed = 1.4,
		KnockbackResist = 0.0,
		ComboMax = 7,
		SpecialCooldown = 5,
		Defense = 0,
		JumpPower = 65,
		DashSpeed = 110,
		CriticalHitChance = 0.25,
		StunResist = 0.0,

		Weight = 0.7,
		LaunchPower = 1.2,
		SlamPower = 0.8,
		AerialDamageBonus = 0.25,

		ComboRecovery = 0.15,
		BlockChance = 0.02,
		DodgeChance = 0.25,

		SuperMeterMax = 100,
		SuperGainPerHit = 7,
		SuperGainOnTakeDamage = 5,

		Aggression = 0.9,
		SpecialPreference = 0.5,
	},

	TypeD = {
		DisplayName = "Brawler",
		Health = 1100,
		Damage = 14,
		Speed = 38,

		AttackSpeed = 1.1,
		KnockbackResist = 0.15,
		ComboMax = 6,
		SpecialCooldown = 7,
		Defense = 3,
		JumpPower = 55,
		DashSpeed = 85,
		CriticalHitChance = 0.12,
		StunResist = 0.1,

		Weight = 1.1,
		LaunchPower = 1.1,
		SlamPower = 1.1,
		AerialDamageBonus = 0.18,

		ComboRecovery = 0.25,
		BlockChance = 0.10,
		DodgeChance = 0.10,

		SuperMeterMax = 100,
		SuperGainPerHit = 6,
		SuperGainOnTakeDamage = 8,

		Aggression = 0.65,
		SpecialPreference = 0.4,
	},
}

-- Helper: get stats for a type with safe defaults
function QuinData.getStats(typeName)
	local stats = QuinData[typeName]
	if not stats then
		warn("[QuinData] Unknown type: " .. tostring(typeName) .. ", falling back to TypeA")
		stats = QuinData.TypeA
	end
	return stats
end

return QuinData
