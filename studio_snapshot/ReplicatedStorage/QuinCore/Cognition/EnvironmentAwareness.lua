--// Cognition.EnvironmentAwareness
-- What is around the Quin physically: how much room it has to give ground and in which
-- direction, and the platforms within reach. (Spatial queries live in SpatialModule; this layer
-- decides which ones a Quin keeps in mind and publishes the result.)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local QuinCore = ReplicatedStorage:WaitForChild("QuinCore")
local CombatConfig = require(QuinCore:WaitForChild("CombatConfig"))
local SpatialModule = require(QuinCore:WaitForChild("Modules"):WaitForChild("SpatialModule"))

local EnvironmentAwareness = {}

function EnvironmentAwareness.survey(quinModel, rootPart, nearbyEnemies, nearbyAllies)
	local retreat = SpatialModule.getSafeRetreatDirection(rootPart, nearbyEnemies, nearbyAllies, CombatConfig)
	local overheadPlatform = SpatialModule.findReachableOverheadPlatform(rootPart, CombatConfig.HighGroundJumpReach or 14)
	local isOnElevatedPlatform = SpatialModule.isOnElevatedPlatform(rootPart, CombatConfig.ElevatedPlatformThreshold or 6.0)

	quinModel:SetAttribute("RetreatScore", math.round(retreat.score * 100) / 100)
	quinModel:SetAttribute("IsCornered", retreat.isCornered)
	quinModel:SetAttribute("HasOverheadPlatform", overheadPlatform ~= nil)
	quinModel:SetAttribute("IsOnElevatedPlatform", isOnElevatedPlatform)

	return {
		retreatDirection = retreat.direction,
		retreatScore = retreat.score,
		isCornered = retreat.isCornered,
		overheadPlatform = overheadPlatform,
		isOnElevatedPlatform = isOnElevatedPlatform,
	}
end

return EnvironmentAwareness
