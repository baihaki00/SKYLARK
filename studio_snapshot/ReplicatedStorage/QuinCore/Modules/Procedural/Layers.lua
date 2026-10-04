--// Layers.lua
-- The switchable body layers: every procedural rule that shapes a Quin's body on top of its
-- clips, with one way to ask "is it on for this Quin" so any of them can be taken out while a
-- match runs and judged against the same match without it (ablation).
--
-- A layer is decided, first match wins, by:
--   1. the Quin's own attribute  Layer_<Name>          (one Quin on or off)
--   2. Workspace LayerSplit = "odd": every other Quin goes without the added layers
--   3. the Workspace attribute named in the list below  (all Quins)
--   4. its default from CombatConfig
-- Client presentation only: the switches are read where the body is posed.

local Workspace = game:GetService("Workspace")
local QuinCore = script.Parent.Parent.Parent
local CombatConfig = require(QuinCore:WaitForChild("CombatConfig"))

local Layers = {}

-- `added`: not in the arena before the lane D port (PROCEDURAL_PORT_PLAN.md). "Legacy" and a
-- split leave these off; the rest are what the arena has always had.
Layers.List = {
	{ name = "BodyTilt", label = "body tilt", attribute = "BodyTilt", default = function() return CombatConfig.BodyTilt_Enabled ~= false end },
	{ name = "FootPlant", label = "foot planting", attribute = "FootPlant", default = function() return CombatConfig.FootIK_Plant ~= false end },
	{ name = "PlantWhenStill", label = "plant when still", attribute = "PlantWhenStill", default = function() return CombatConfig.FootIK_PlantWhenStill ~= false end },
	{ name = "PivotPin", label = "pivot pin", attribute = "PivotPin", default = function() return CombatConfig.FootIK_PivotPin ~= false end },
	{ name = "SecondaryMotion", label = "arm follow-through", attribute = "SecondaryMotion", default = function() return CombatConfig.SecondaryMotion_Enabled ~= false end },
	{ name = "HipTwist", label = "hip twist with sideways travel", attribute = "Layer_HipTwist", default = function() return true end },
	{ name = "ProceduralStyle", label = "per-Quin style (experiment)", attribute = "ProceduralStyle", default = function() return CombatConfig.ProceduralStyle_Enabled == true end },
	{ name = "SquareUp", label = "chest squared in a strafe", attribute = "Layer_SquareUp", added = true, default = function() return CombatConfig.ProceduralLayers.SquareUp.Enabled ~= false end },
	{ name = "StrafeUpright", label = "strafe clip carries the body (no tilt, no hip twist)", attribute = "Layer_StrafeUpright", added = true, default = function() return CombatConfig.ProceduralLayers.StrafeUpright.Enabled ~= false end },
	{ name = "KneeOverToe", label = "knee over toe", attribute = "Layer_KneeOverToe", added = true, default = function() return CombatConfig.ProceduralLayers.KneeOverToe.Enabled ~= false end },
	{ name = "SoftElbows", label = "soft elbows", attribute = "Layer_SoftElbows", added = true, default = function() return CombatConfig.ProceduralLayers.SoftElbows.Enabled ~= false end },
	{ name = "ArmClear", label = "arms out of the trunk", attribute = "Layer_ArmClear", added = true, default = function() return CombatConfig.ProceduralLayers.ArmClear.Enabled ~= false end },
	{ name = "LooseWrists", label = "loose wrists", attribute = "Layer_LooseWrists", added = true, default = function() return CombatConfig.ProceduralLayers.LooseWrists.Enabled ~= false end },
	{ name = "Breath", label = "breathing (harder when spent)", attribute = "Layer_Breath", added = true, default = function() return CombatConfig.ProceduralLayers.Breath.Enabled ~= false end },
	{ name = "Footfall", label = "weight on each footfall", attribute = "Layer_Footfall", added = true, default = function() return CombatConfig.ProceduralLayers.Footfall.Enabled ~= false end },
}

local byName = {}
for _, layer in ipairs(Layers.List) do
	byName[layer.name] = layer
end

local splitGroup = setmetatable({}, { __mode = "k" }) -- Quin -> true if a split leaves it without the added layers

-- Every other Quin, the same ones every match: by the letters of its name
local function inLegacyHalf(quin: Instance): boolean
	local known = splitGroup[quin]
	if known == nil then
		local sum = 0
		for i = 1, #quin.Name do
			sum += string.byte(quin.Name, i)
		end
		known = sum % 2 == 1
		splitGroup[quin] = known
	end
	return known
end

-- True if a split is on and this Quin is in the half that goes without the added layers
function Layers.isLegacyHalf(quin: Instance?): boolean
	return quin ~= nil and Workspace:GetAttribute("LayerSplit") == "odd" and inLegacyHalf(quin)
end

function Layers.isOn(name: string, quin: Instance?): boolean
	local layer = byName[name]
	if quin then
		local own = quin:GetAttribute("Layer_" .. name)
		if own ~= nil then
			return own == true
		end
		if layer.added and Layers.isLegacyHalf(quin) then
			return false
		end
	end
	local switch = Workspace:GetAttribute(layer.attribute)
	if switch ~= nil then
		return switch == true
	end
	return layer.default()
end

-- Switch a layer for all Quins (nil: back to its default)
function Layers.set(name: string, on: boolean?)
	Workspace:SetAttribute(byName[name].attribute, on)
end

-- "Default": every switch cleared. "All" / "None": every layer on / off.
-- "Legacy": the added layers off, the rest at their defaults.
function Layers.preset(which: string)
	for _, layer in ipairs(Layers.List) do
		local value = nil
		if which == "All" then
			value = true
		elseif which == "None" then
			value = false
		elseif which == "Legacy" and layer.added then
			value = false
		end
		Workspace:SetAttribute(layer.attribute, value)
	end
end

return Layers
