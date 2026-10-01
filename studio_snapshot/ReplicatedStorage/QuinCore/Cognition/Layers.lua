--// Cognition.Layers
-- Switches for the cognition layers that can be taken out to see what they contribute.
-- A layer that is off returns its neutral result (documented in the layer's own module), so the
-- rest of the pipeline keeps working and the difference is that layer alone.
--   default : CombatConfig.Cognition.<Name>
--   live    : workspace attribute Cognition_<Name> (set from the Spectator HUD)

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local QuinCore = ReplicatedStorage:WaitForChild("QuinCore")
local CombatConfig = require(QuinCore:WaitForChild("CombatConfig"))

local Layers = {}

-- Layers with a switch, in pipeline order
Layers.Switchable = {
	{ id = "Senses", label = "Senses (vision cone, hearing)" },
	{ id = "Attention", label = "Attention (limited focus)" },
	{ id = "Memory", label = "Memory (remember, forget, share)" },
}

local function attributeName(id)
	return "Cognition_" .. id
end

function Layers.isEnabled(id)
	local live = workspace:GetAttribute(attributeName(id))
	if live ~= nil then return live == true end
	return CombatConfig.Cognition[id] ~= false
end

if RunService:IsServer() then
	-- Publish the defaults so clients can show them, and take live changes from the HUD
	for _, layer in ipairs(Layers.Switchable) do
		if workspace:GetAttribute(attributeName(layer.id)) == nil then
			workspace:SetAttribute(attributeName(layer.id), CombatConfig.Cognition[layer.id] ~= false)
		end
	end
	QuinCore:WaitForChild("CognitionToggleEvent").OnServerEvent:Connect(function(_, id, value)
		for _, layer in ipairs(Layers.Switchable) do
			if layer.id == id then
				workspace:SetAttribute(attributeName(id), value == true)
			end
		end
	end)
else
	-- Client: ask the server to switch a layer
	function Layers.request(id, value)
		QuinCore:WaitForChild("CognitionToggleEvent"):FireServer(id, value == true)
	end
end

return Layers
