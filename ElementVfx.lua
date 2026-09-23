--// ElementVfx.lua
-- Placeholder elemental VFX palette + behavior config.
--
-- Every dash/air-dash trail, launch burst, shockwave, debris and impact reads its
-- colors/textures/material from this single table. To tweak an element's look just
-- edit its entry below (no gameplay code touches these values).
--
-- impactStyle picks the flavor of the impact burst:
--   "embers"  -> fire embers
--   "splash"  -> water droplets (gravity)
--   "rocks"   -> physical rock debris chunks
--   "arc"     -> sharp electric sparks (lightning)
--   "gust"    -> pale wind streaks

local ElementVfx = {
	Fire = {
		trailColor      = Color3.fromRGB(255, 150, 50),
		trailCore       = Color3.fromRGB(255, 225, 120),
		trailTexture    = "rbxassetid://1185246",      -- ember/spark
		trailEmission   = 0.6,
		burstColor      = Color3.fromRGB(255, 170, 70),
		burstCore       = Color3.fromRGB(255, 230, 130),
		impactPrimary   = Color3.fromRGB(255, 170, 60),
		impactSecondary = Color3.fromRGB(255, 90, 20),
		sparkTexture    = "rbxassetid://6763809313",
		debrisColor     = Color3.fromRGB(150, 110, 70),
		debrisMaterial  = Enum.Material.Slate,
		shockwaveColor  = Color3.fromRGB(255, 180, 90),
		impactStyle     = "embers",
	},

	Water = {
		trailColor      = Color3.fromRGB(80, 180, 255),
		trailCore       = Color3.fromRGB(180, 235, 255),
		trailTexture    = "rbxassetid://2415893330",   -- soft droplet/ring
		trailEmission   = 0.4,
		burstColor      = Color3.fromRGB(90, 190, 255),
		burstCore       = Color3.fromRGB(190, 240, 255),
		impactPrimary   = Color3.fromRGB(120, 210, 255),
		impactSecondary = Color3.fromRGB(40, 130, 220),
		sparkTexture    = "rbxassetid://2415893330",
		debrisColor     = Color3.fromRGB(120, 190, 255),
		debrisMaterial  = Enum.Material.Ice,
		shockwaveColor  = Color3.fromRGB(130, 210, 255),
		impactStyle     = "splash",
	},

	Stone = {
		trailColor      = Color3.fromRGB(170, 150, 125),
		trailCore       = Color3.fromRGB(200, 185, 160),
		trailTexture    = "rbxassetid://2415893330",   -- dust
		trailEmission   = 0.15,
		burstColor      = Color3.fromRGB(180, 160, 140),
		burstCore       = Color3.fromRGB(210, 195, 175),
		impactPrimary   = Color3.fromRGB(190, 170, 145),
		impactSecondary = Color3.fromRGB(120, 105, 90),
		sparkTexture    = "rbxassetid://2415893330",
		debrisColor     = Color3.fromRGB(150, 135, 115),
		debrisMaterial  = Enum.Material.Slate,
		shockwaveColor  = Color3.fromRGB(200, 180, 160),
		impactStyle     = "rocks",
	},

	Lightning = {
		trailColor      = Color3.fromRGB(255, 235, 90),
		trailCore       = Color3.fromRGB(255, 255, 190),
		trailTexture    = "rbxassetid://6763809313",   -- electric spark
		trailEmission   = 0.9,
		burstColor      = Color3.fromRGB(255, 240, 120),
		burstCore       = Color3.fromRGB(255, 255, 220),
		impactPrimary   = Color3.fromRGB(255, 255, 180),
		impactSecondary = Color3.fromRGB(160, 220, 255),
		sparkTexture    = "rbxassetid://6763809313",
		debrisColor     = Color3.fromRGB(255, 250, 200),
		debrisMaterial  = Enum.Material.Neon,
		shockwaveColor  = Color3.fromRGB(255, 245, 150),
		impactStyle     = "arc",
	},

	Wind = {
		trailColor      = Color3.fromRGB(190, 255, 245),
		trailCore       = Color3.fromRGB(230, 255, 250),
		trailTexture    = "rbxassetid://2415893330",   -- soft ring
		trailEmission   = 0.35,
		burstColor      = Color3.fromRGB(200, 255, 245),
		burstCore       = Color3.fromRGB(235, 255, 252),
		impactPrimary   = Color3.fromRGB(210, 255, 248),
		impactSecondary = Color3.fromRGB(150, 235, 220),
		sparkTexture    = "rbxassetid://2415893330",
		debrisColor     = Color3.fromRGB(210, 255, 248),
		debrisMaterial  = Enum.Material.Neon,
		shockwaveColor  = Color3.fromRGB(210, 255, 248),
		impactStyle     = "gust",
	},
}

-- Canonical aliases (Water is the core element; Ice is its phase-change byproduct)
ElementVfx.Ice = ElementVfx.Water
ElementVfx.Earth = ElementVfx.Stone
ElementVfx.Electric = ElementVfx.Lightning

-- Safe getter with Fire fallback (never returns nil)
function ElementVfx.get(elementName)
	return ElementVfx[elementName] or ElementVfx.Fire
end

return ElementVfx
