--// AirInterceptModule.lua
-- Going up after an enemy that is high in the air.
-- A Quin that sees an enemy well above it and off the ground (a projectile jumper, a Quin
-- thrown up) may launch straight at it (jump style 8); the two meet in the air and
-- ProjectileJumpState turns that into a mid-air clash. It has to have seen it (so it was looking up: Cognition.Gaze), have a
-- projectile jump available, and want to - by chance, more for aggressive Quins. Each sighting
-- is weighed once.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local QuinCore = ReplicatedStorage:WaitForChild("QuinCore")
local CombatConfig = require(QuinCore:WaitForChild("CombatConfig"))
local Cognition = require(QuinCore:WaitForChild("Cognition"))

local AirInterceptModule = {}

local function canProjectileJump(fighter)
	return CombatConfig.EnableProjectileJump ~= false and fighter:GetAttribute("EnableProjectileJump") ~= false
		and (fighter:GetAttribute("Energy") or 100) >= (CombatConfig.ProjectileJumpMinEnergy or 40)
		and (tick() - (fighter:GetAttribute("LastProjectileJumpTime") or 0)) >= (CombatConfig.ProjectileJump_Cooldown or 14.0)
end

-- The airborne enemy this Quin decides to go up after right now, or nil
function AirInterceptModule.consider(fighter, rootPart)
	local board = Cognition.Blackboard.peek(fighter)
	if not board or not canProjectileJump(fighter) then return nil end

	local minHeight = CombatConfig.Intercept_MinHeight or 40
	local maxRange = CombatConfig.Intercept_MaxRange or 300
	local nearest, nearestDistance = nil, maxRange
	for _, contact in ipairs(board.contacts.enemies) do
		if contact.visible and contact.channel == "sight" and contact.distance <= nearestDistance then
			local humanoid = contact.model:FindFirstChildOfClass("Humanoid")
			local root = contact.model:FindFirstChild("HumanoidRootPart")
			local offGround = humanoid and (humanoid.PlatformStand or humanoid.FloorMaterial == Enum.Material.Air)
			-- One interceptor per jumper, and none into a clash already going on up there
			-- (two or three Quins went up after the same one and ended in three-way clashes)
			local claimed = os.clock() - (contact.model:GetAttribute("InterceptedAt") or 0) < (CombatConfig.Intercept_ClaimTime or 3.0)
			local clashing = contact.model:GetAttribute("CurrentState") == "MidAirClash"
			-- One already diving is at the floor before anyone gets up to it
			local diving = root and root.AssemblyLinearVelocity.Y < -(CombatConfig.Intercept_MaxTargetFallSpeed or 100)
			if root and offGround and not claimed and not clashing and not diving and root.Position.Y - rootPart.Position.Y >= minHeight then
				nearest, nearestDistance = contact.model, contact.distance
			end
		end
	end
	if not nearest then return nil end

	-- One decision per sighting
	local now = os.clock()
	board.interceptWeighed = board.interceptWeighed or setmetatable({}, { __mode = "k" })
	if now - (board.interceptWeighed[nearest] or 0) < (CombatConfig.Intercept_RollInterval or 3.0) then return nil end
	board.interceptWeighed[nearest] = now

	local aggression = fighter:GetAttribute("Pers_Aggression") or 0.6
	local chance = (CombatConfig.Intercept_ChanceBase or 0.15) + (CombatConfig.Intercept_ChanceAggression or 0.45) * aggression
	if math.random() >= chance then return nil end
	return nearest
end

-- Commit the fighter to the interception; the caller then returns ProjectileJumpState
function AirInterceptModule.commit(fighter, enemy)
	fighter:SetAttribute("ObstacleAwareness", "Going up after a jumper")
	fighter:SetAttribute("JumpStyle", 8) -- the intercept flight: straight at the enemy, tracking it
	fighter:SetAttribute("CurrentTarget", enemy.Name)
	fighter:SetAttribute("TargetQuin", enemy.Name)
	fighter:SetAttribute("LastInterceptTime", os.clock())
	enemy:SetAttribute("InterceptedAt", os.clock())
end

return AirInterceptModule
