--// TacticalPerception.lua
-- The tactical context a Quin reasons with. It is produced by the Cognition pipeline
-- (QuinCore.Cognition: senses -> attention -> memory -> self / environment / situation);
-- this module is the name the rest of QuinCore calls it by.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local QuinCore = ReplicatedStorage:WaitForChild("QuinCore")
local Cognition = require(QuinCore:WaitForChild("Cognition"))

local TacticalPerception = {
	LOCAL_RADIUS = 45,       -- Radius for direct local combat encounter reasoning
	AWARENESS_RADIUS = 90,   -- Radius for incoming reinforcements
}

-- Evaluate the tactical situation of a Quin (optionally against a specific target)
function TacticalPerception.evaluate(quinModel, targetModel)
	return Cognition.update(quinModel, targetModel)
end

return TacticalPerception
