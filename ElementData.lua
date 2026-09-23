--// ElementData.lua
-- Canonical static definitions for Quin Elements
-- Establishes elemental power identity independent from combat chassis (Type)
-- Clean extension point for color palettes, status identifiers, and plug-and-play FX

local ElementData = {
	ElementDataVersion = 1,

	Fire = {
		DisplayName = "Fire",
		Color = Color3.fromRGB(255, 85, 30),         -- Vibrant Flame Orange/Red
		BodyTint = Color3.fromRGB(215, 105, 70),
		ParticleColor = Color3.fromRGB(255, 140, 50),
		StatusEffect = "Burn",
		FX = {
			Attack = "FireAttack_Basic",
			Dash = "FireDash_Burst",
			Hit = "FireHit_Sparks",
			Block = "FireBlock_Shield",
			Special = "FireSpecial_Eruption",
			Super = "FireSuper_Inferno",
			Death = "FireDeath_Ashes",
			Spawn = "FireSpawn_Ignite",
		},
		Modifiers = {
			-- Clean extension point for future balance; keep empty or subtle now
			DamageMultiplier = 1.0,
		},
	},

	Water = {
		DisplayName = "Water",
		Color = Color3.fromRGB(30, 140, 255),        -- Deep Azure / Ocean Blue
		BodyTint = Color3.fromRGB(70, 145, 215),
		ParticleColor = Color3.fromRGB(100, 200, 255),
		StatusEffect = "Drench",
		FX = {
			Attack = "WaterAttack_Basic",
			Dash = "WaterDash_Surge",
			Hit = "WaterHit_Splash",
			Block = "WaterBlock_Barrier",
			Special = "WaterSpecial_Geyser",
			Super = "WaterSuper_Tsunami",
			Death = "WaterDeath_Vapor",
			Spawn = "WaterSpawn_Torrent",
		},
		Modifiers = {
			DamageMultiplier = 1.0,
		},
	},

	Stone = {
		DisplayName = "Stone",
		Color = Color3.fromRGB(160, 140, 120),       -- Granite / Slate Earth
		BodyTint = Color3.fromRGB(145, 135, 122),
		ParticleColor = Color3.fromRGB(180, 170, 155),
		StatusEffect = "Fortify",
		FX = {
			Attack = "StoneAttack_Basic",
			Dash = "StoneDash_Quake",
			Hit = "StoneHit_Rubble",
			Block = "StoneBlock_Bulwark",
			Special = "StoneSpecial_Boulder",
			Super = "StoneSuper_Cataclysm",
			Death = "StoneDeath_Crumble",
			Spawn = "StoneSpawn_Emerge",
		},
		Modifiers = {
			DamageMultiplier = 1.0,
		},
	},

	Lightning = {
		DisplayName = "Lightning",
		Color = Color3.fromRGB(255, 235, 60),       -- Pale Electric / Neon Yellow
		BodyTint = Color3.fromRGB(220, 205, 95),
		ParticleColor = Color3.fromRGB(255, 255, 160),
		StatusEffect = "Shock",
		FX = {
			Attack = "LightningAttack_Basic",
			Dash = "LightningDash_Volt",
			Hit = "LightningHit_Arc",
			Block = "LightningBlock_Discharge",
			Special = "LightningSpecial_Thunderclap",
			Super = "LightningSuper_Overcharge",
			Death = "LightningDeath_Disperse",
			Spawn = "LightningSpawn_Strike",
		},
		Modifiers = {
			DamageMultiplier = 1.0,
		},
	},

	Wind = {
		DisplayName = "Wind",
		Color = Color3.fromRGB(180, 255, 240),      -- Crisp Jade / Pale Cyan / White
		BodyTint = Color3.fromRGB(170, 215, 208),
		ParticleColor = Color3.fromRGB(220, 255, 250),
		StatusEffect = "Haste",
		FX = {
			Attack = "WindAttack_Basic",
			Dash = "WindDash_Gale",
			Hit = "WindHit_Slice",
			Block = "WindBlock_Vortex",
			Special = "WindSpecial_Cyclone",
			Super = "WindSuper_Tempest",
			Death = "WindDeath_Breeze",
			Spawn = "WindSpawn_Zephyr",
		},
		Modifiers = {
			DamageMultiplier = 1.0,
		},
	},
}

-- Aliases for element keys (Water is the core element, Ice is the crystalline byproduct)
ElementData.Ice = ElementData.Water
ElementData.Earth = ElementData.Stone
ElementData.Electric = ElementData.Lightning

-- List of all canonical element keys
local ELEMENT_LIST = { "Fire", "Water", "Stone", "Lightning", "Wind" }

-- Helper: Get element data safely with fallback to Fire and alias support
function ElementData.getElement(elementName)
	if elementName == "Ice" then elementName = "Water" end
	if elementName == "Earth" then elementName = "Stone" end
	if elementName == "Electric" then elementName = "Lightning" end

	local data = ElementData[elementName]
	if not data then
		warn("[ElementData] Unknown element: " .. tostring(elementName) .. ", falling back to Fire")
		data = ElementData.Fire
	end
	return data
end

-- Helper: Get random element
function ElementData.getRandomElement(rng)
	local rand = rng or math.random
	local idx = type(rand) == "userdata" and rand:NextInteger(1, #ELEMENT_LIST) or rand(1, #ELEMENT_LIST)
	return ELEMENT_LIST[idx]
end

-- Helper: Get all element names
function ElementData.getAllElements()
	local copy = {}
	for i, name in ipairs(ELEMENT_LIST) do
		copy[i] = name
	end
	return copy
end

return ElementData
