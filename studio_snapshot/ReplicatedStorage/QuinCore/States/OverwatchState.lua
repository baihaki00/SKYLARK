--// OverwatchState.lua
-- Holding a high platform.
-- A Quin that finds itself on high ground with nobody within reach uses the place: it walks the
-- edge on the side its enemies are on, stops and looks down at them (Cognition.Gaze points its
-- head down from high ground, and up at the sky now and then), and gets its breath back.
-- It leaves when it has a reason to:
--   an enemy is up here with it          -> fight it here
--   it sees a jumper high in the air     -> go up after it (AirInterceptModule)
--   it has watched long enough, wants to fight and sees someone below
--                                        -> dive on them (projectile jump)
--   the watch has gone on too long       -> climb down and rejoin
-- Retreating allies prefer a platform a friend already holds (RetreatTacticsModule), so the
-- wounded gather on the same one.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local QuinCore = ReplicatedStorage:WaitForChild("QuinCore")
local CombatConfig = require(QuinCore:WaitForChild("CombatConfig"))
local Cognition = require(QuinCore:WaitForChild("Cognition"))
local AnimationModule = require(QuinCore:WaitForChild("Modules"):WaitForChild("AnimationModule"))
local LocomotionModule = require(QuinCore:WaitForChild("Modules"):WaitForChild("LocomotionModule"))
local GaitModule = require(QuinCore:WaitForChild("Modules"):WaitForChild("GaitModule"))
local PlatformCatalogue = require(QuinCore:WaitForChild("Modules"):WaitForChild("PlatformCatalogue"))
local AirInterceptModule = require(QuinCore:WaitForChild("Modules"):WaitForChild("AirInterceptModule"))
local TargetingModule = require(QuinCore:WaitForChild("Modules"):WaitForChild("TargetingModule"))
local RuntimeTracer = require(QuinCore:WaitForChild("Modules"):WaitForChild("RuntimeTracer"))

local OverwatchState = { name = "Overwatch" }

local ARRIVE_DISTANCE = 2.5 -- studs from a lookout point at which the Quin stops
local PAUSE_MIN, PAUSE_MAX = 1.5, 3.5 -- seconds spent looking from one point
local SAME_LEVEL = 10 -- studs of height difference within which an enemy is "up here"

local watchData = setmetatable({}, { __mode = "k" })

-- The platform under the Quin if it is high enough to be worth holding, else nil
local function heldPlatform(rootPart)
	local platform = PlatformCatalogue.under(rootPart.Position, 12)
	if platform and platform.heightAboveArenaFloor >= (CombatConfig.Overwatch_MinHeight or 12) then
		return platform
	end
	return nil
end

-- True when the Quin stands on a platform it can hold
function OverwatchState.canHold(fighter, rootPart)
	return CombatConfig.Overwatch_Enabled ~= false
		and fighter:GetAttribute("LeaderShowdownRole") == nil
		and heldPlatform(rootPart) ~= nil
end

-- The nearest enemy the Quin knows of that passes `accept`
local function nearestEnemy(fighter, accept)
	local best = nil
	for _, contact in ipairs(Cognition.knownEnemies(fighter) or {}) do
		if contact.model.Parent and accept(contact) and (not best or contact.distance < best.distance) then
			best = contact
		end
	end
	return best
end

-- A point near the platform's edge on the side the enemies are on (any side if it knows of none)
local function pickLookout(fighter, rootPart, platform)
	local inset = CombatConfig.Overwatch_EdgeInset or 3
	local toward
	local enemy = nearestEnemy(fighter, function() return true end)
	if enemy then
		toward = Vector3.new(enemy.position.X - platform.center.X, 0, enemy.position.Z - platform.center.Z)
	end
	if not toward or toward.Magnitude < 1 then
		local angle = math.random() * math.pi * 2
		toward = Vector3.new(math.cos(angle), 0, math.sin(angle))
	end
	-- Somewhere along that side, not always the same spot
	local across = Vector3.new(-toward.Z, 0, toward.X).Unit
	local spread = math.max(platform.halfA, platform.halfB) * (math.random() - 0.5)
	return PlatformCatalogue.nearestTopPoint(platform, platform.center + toward.Unit * 1000 + across * spread, inset)
end

function OverwatchState.enter(fighter, humanoid, rootPart)
	local aggression = fighter:GetAttribute("Pers_Aggression") or 0.6
	local watchMin = CombatConfig.Overwatch_WatchMin or 4
	local watchMax = CombatConfig.Overwatch_WatchMax or 12
	watchData[fighter] = {
		enterTime = os.clock(),
		lastUpdate = os.clock(),
		watchFor = watchMax + (watchMin - watchMax) * aggression,
		lookout = nil,
		pauseUntil = 0,
	}
	humanoid.AutoRotate = true
	AnimationModule.ensureBaseIdle(humanoid)
	fighter:SetAttribute("ObstacleAwareness", "Holding high ground")
	RuntimeTracer.checkpoint(fighter, "Enter Overwatch (holding a platform)")
end

function OverwatchState.exit(fighter, humanoid, rootPart)
	watchData[fighter] = nil
end

function OverwatchState.update(fighter, humanoid, rootPart, DEBUG)
	local data = watchData[fighter]
	local platform = heldPlatform(rootPart)
	if not data or not platform then
		return require(script.Parent:WaitForChild("ChaseState"))
	end

	local now = os.clock()
	local dt = math.clamp(now - data.lastUpdate, 0.016, 0.25)
	data.lastUpdate = now
	local watched = now - data.enterTime

	-- Getting its breath back
	local energy = fighter:GetAttribute("Energy") or 100
	fighter:SetAttribute("Energy", math.min(CombatConfig.MaxEnergy or 100, energy + (CombatConfig.EnergyRecovery_Idle or 8) * 0.1))

	-- An enemy up here with it
	local intruder = nearestEnemy(fighter, function(contact)
		return contact.visible and contact.distance <= (CombatConfig.Overwatch_EngageRange or 30)
			and math.abs(contact.position.Y - rootPart.Position.Y) <= SAME_LEVEL
	end)
	if intruder then
		TargetingModule.setTarget(fighter, intruder.model)
		RuntimeTracer.checkpoint(fighter, "Overwatch: enemy on the platform")
		if intruder.distance <= (CombatConfig.CombatRange or 8) * 1.2 then
			return require(script.Parent:WaitForChild("FightState"))
		end
		return require(script.Parent:WaitForChild("ChaseState"))
	end

	-- A jumper in the sky
	local jumper = AirInterceptModule.consider(fighter, rootPart)
	if jumper then
		AirInterceptModule.commit(fighter, jumper)
		RuntimeTracer.checkpoint(fighter, "Overwatch: going up after a jumper")
		return require(script.Parent:WaitForChild("ProjectileJumpState"))
	end

	-- Watched long enough and wants back in: dive on someone it can see below
	if watched >= data.watchFor and fighter:GetAttribute("RecommendedAction") ~= "Retreat" then
		local canDive = CombatConfig.EnableProjectileJump ~= false and fighter:GetAttribute("EnableProjectileJump") ~= false
			and (fighter:GetAttribute("Energy") or 100) >= (CombatConfig.ProjectileJumpMinEnergy or 40)
			and (tick() - (fighter:GetAttribute("LastProjectileJumpTime") or 0)) >= (CombatConfig.ProjectileJump_Cooldown or 14.0)
		local prey = canDive and nearestEnemy(fighter, function(contact)
			return contact.visible and contact.position.Y < rootPart.Position.Y - SAME_LEVEL
		end)
		if prey then
			fighter:SetAttribute("ObstacleAwareness", "Diving from high ground")
			fighter:SetAttribute("JumpStyle", nil) -- any style
			fighter:SetAttribute("CurrentTarget", prey.model.Name)
			fighter:SetAttribute("TargetQuin", prey.model.Name)
			RuntimeTracer.checkpoint(fighter, "Overwatch: diving on " .. prey.model.Name)
			return require(script.Parent:WaitForChild("ProjectileJumpState"))
		end
	end
	if watched >= (CombatConfig.Overwatch_MaxWatch or 25) then
		RuntimeTracer.checkpoint(fighter, "Overwatch: watch over, climbing down")
		return require(script.Parent:WaitForChild("ChaseState"))
	end

	-- Walk the edge: to a lookout point, stand and look, then to the next
	if now < data.pauseUntil then
		LocomotionModule.brake(fighter, humanoid, rootPart, dt)
		return OverwatchState
	end
	if not data.lookout then
		data.lookout = pickLookout(fighter, rootPart, platform)
	end
	local toLookout = Vector3.new(data.lookout.X - rootPart.Position.X, 0, data.lookout.Z - rootPart.Position.Z)
	if toLookout.Magnitude <= ARRIVE_DISTANCE then
		data.lookout = nil
		data.pauseUntil = now + PAUSE_MIN + math.random() * (PAUSE_MAX - PAUSE_MIN)
		LocomotionModule.brake(fighter, humanoid, rootPart, dt)
	else
		LocomotionModule.steer(fighter, humanoid, rootPart, data.lookout, CombatConfig.Overwatch_WalkSpeed or 10, dt)
		GaitModule.update(humanoid, rootPart, dt)
	end

	return OverwatchState
end

return OverwatchState
