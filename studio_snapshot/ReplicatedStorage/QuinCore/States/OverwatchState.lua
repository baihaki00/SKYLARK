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
local MIN_LEG = 5 -- studs: a lookout nearer than this is the spot it already stands on
local LOOP_POINTS = 8 -- waypoints per lap of a jog loop
local LOOP_ARRIVE = 3.5 -- studs: a loop waypoint is passed through, not stopped at
local SAME_LEVEL = 10 -- studs of height difference within which an enemy is "up here"

local watchData = setmetatable({}, { __mode = "k" })

-- The platform under the Quin if it is high enough to be worth holding, else nil
local function heldPlatform(rootPart)
	local platform = PlatformCatalogue.under(rootPart.Position, 12)
	-- (and room to move: the tops of the tall thin walls, 7 studs across and 50-170 up, passed
	-- as platforms, so a Quin that dived onto one perched up there for 15-30 s - "stuck up a wall")
	local minTop = CombatConfig.Overwatch_MinTopWidth or 10
	if platform and platform.heightAboveArenaFloor >= (CombatConfig.Overwatch_MinHeight or 12)
		and math.min(platform.halfA, platform.halfB) * 2 >= minTop then
		return platform
	end
	return nil
end

-- True when the Quin stands on a platform it can hold
function OverwatchState.canHold(fighter, rootPart)
	return CombatConfig.Overwatch_Enabled ~= false
		and fighter:GetAttribute("RespectRole") == nil
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

-- What the Quin does next up there. Standing at one lookout for the whole watch (narrow
-- platforms gave the same lookout every time, so it stood still for 10-25 s) read as a statue.
--   lookout - walk to a point on the edge facing its enemies, stop and look (as before)
--   pace    - walk back and forth along the platform, short stops at each turn
--   loop    - jog a lap or two around the top (platforms wide enough for a circle)
local function planRoutine(fighter, rootPart, platform)
	local inset = CombatConfig.Overwatch_EdgeInset or 3
	local ua, ub = math.max(platform.halfA - inset, 0), math.max(platform.halfB - inset, 0)
	local longAxis, longHalf = platform.axisA, ua
	if ub > ua then
		longAxis, longHalf = platform.axisB, ub
	end
	local mobility = fighter:GetAttribute("Pers_MobilityPreference") or 0.6
	local walkSpeed = CombatConfig.Overwatch_WalkSpeed or 10
	local roll = math.random()

	-- Jog loop: an ellipse one stud inside the walking inset
	local ra, rb = ua - 1, ub - 1
	if math.min(ra, rb) >= (CombatConfig.Overwatch_LoopMinRadius or 4) and roll < 0.2 + 0.3 * mobility then
		local points = {}
		local start = math.atan2((rootPart.Position - platform.center):Dot(platform.axisB) / rb, (rootPart.Position - platform.center):Dot(platform.axisA) / ra)
		local turn = math.random() < 0.5 and 1 or -1
		local laps = math.random(1, 2)
		for i = 1, LOOP_POINTS * laps do
			local angle = start + turn * i * (2 * math.pi / LOOP_POINTS)
			table.insert(points, platform.center + platform.axisA * (math.cos(angle) * ra) + platform.axisB * (math.sin(angle) * rb))
		end
		return { kind = "loop", points = points, speed = CombatConfig.Overwatch_JogSpeed or 14, turnPause = 0, endPause = { 0.4, 1.2 } }
	end

	-- Pacing: end to end along the long side, turning at a different spot each time
	if longHalf * 2 >= MIN_LEG * 1.6 and roll < 0.75 then
		local points = {}
		local side = (rootPart.Position - platform.center):Dot(longAxis) > 0 and 1 or -1
		for _ = 1, math.random(2, 4) do
			side = -side
			table.insert(points, platform.center + longAxis * (side * longHalf * (0.55 + 0.45 * math.random())))
		end
		return { kind = "pace", points = points, speed = walkSpeed * (0.8 + 0.3 * math.random()), turnPause = { 0.3, 0.9 }, endPause = { 0.8, 2.0 } }
	end

	-- Lookout over the enemies' side
	local lookout = pickLookout(fighter, rootPart, platform)
	local flat = Vector3.new(lookout.X - rootPart.Position.X, 0, lookout.Z - rootPart.Position.Z)
	if flat.Magnitude < MIN_LEG then
		-- Already there: look from here, then do something else
		return { kind = "look", points = {}, speed = walkSpeed, turnPause = 0, endPause = { PAUSE_MIN, PAUSE_MAX } }
	end
	return { kind = "lookout", points = { lookout }, speed = walkSpeed, turnPause = 0, endPause = { PAUSE_MIN, PAUSE_MAX } }
end

local function randomIn(range)
	if type(range) ~= "table" then return range end
	return range[1] + math.random() * (range[2] - range[1])
end

function OverwatchState.enter(fighter, humanoid, rootPart)
	local aggression = fighter:GetAttribute("Pers_Aggression") or 0.6
	local watchMin = CombatConfig.Overwatch_WatchMin or 4
	local watchMax = CombatConfig.Overwatch_WatchMax or 12
	watchData[fighter] = {
		enterTime = os.clock(),
		lastUpdate = os.clock(),
		watchFor = watchMax + (watchMin - watchMax) * aggression,
		route = nil,
		routeIndex = 1,
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

	-- A Quin that is restless (a lull dragged on) or hunting does not hold a platform for long
	local urgency = fighter:GetAttribute("SocialHunt") and 1 or (fighter:GetAttribute("SocialUrgency") or 0)
	local watchFor = data.watchFor * (1 - 0.8 * urgency)
	local maxWatch = (CombatConfig.Overwatch_MaxWatch or 25) * (1 - 0.75 * urgency)

	-- Watched long enough and wants back in: dive on someone it can see below
	if watched >= watchFor and fighter:GetAttribute("RecommendedAction") ~= "Retreat" then
		local canDive = CombatConfig.EnableProjectileJump ~= false and fighter:GetAttribute("EnableProjectileJump") ~= false
			and (fighter:GetAttribute("Energy") or 100) >= (CombatConfig.ProjectileJumpMinEnergy or 40)
			and (tick() - (fighter:GetAttribute("LastProjectileJumpTime") or 0)) >= (CombatConfig.ProjectileJump_Cooldown or 14.0)
		local prey = canDive and nearestEnemy(fighter, function(contact)
			return contact.visible and contact.position.Y < rootPart.Position.Y - SAME_LEVEL
		end)
		if prey then
			fighter:SetAttribute("ObstacleAwareness", "Diving from high ground")
			fighter:SetAttribute("JumpStyle", nil) -- any style
			TargetingModule.setTarget(fighter, prey.model, "Dive")
			RuntimeTracer.checkpoint(fighter, "Overwatch: diving on " .. prey.model.Name)
			return require(script.Parent:WaitForChild("ProjectileJumpState"))
		end
	end
	if watched >= maxWatch then
		RuntimeTracer.checkpoint(fighter, "Overwatch: watch over, climbing down")
		return require(script.Parent:WaitForChild("ChaseState"))
	end

	-- Use the platform: look out, pace, jog a loop (planRoutine), with stops in between
	if now < data.pauseUntil then
		LocomotionModule.brake(fighter, humanoid, rootPart, dt)
		return OverwatchState
	end
	local route = data.route
	if not route or data.routeIndex > #route.points then
		if route then
			-- Routine done: stop for a moment, then plan the next
			data.route = nil
			data.pauseUntil = now + randomIn(route.endPause)
			LocomotionModule.brake(fighter, humanoid, rootPart, dt)
			return OverwatchState
		end
		route = planRoutine(fighter, rootPart, platform)
		data.route = route
		data.routeIndex = 1
		fighter:SetAttribute("ObstacleAwareness", "Holding high ground (" .. route.kind .. ")")
		if #route.points == 0 then
			return OverwatchState
		end
	end

	local point = route.points[data.routeIndex]
	local toPoint = Vector3.new(point.X - rootPart.Position.X, 0, point.Z - rootPart.Position.Z)
	if toPoint.Magnitude <= (route.kind == "loop" and LOOP_ARRIVE or ARRIVE_DISTANCE) then
		data.routeIndex += 1
		local turnPause = randomIn(route.turnPause)
		if turnPause > 0 and data.routeIndex <= #route.points then
			data.pauseUntil = now + turnPause
			LocomotionModule.brake(fighter, humanoid, rootPart, dt)
			return OverwatchState
		end
		point = route.points[data.routeIndex]
		if not point then
			return OverwatchState
		end
	end
	LocomotionModule.steer(fighter, humanoid, rootPart, point, route.speed, dt)
	GaitModule.update(humanoid, rootPart, dt)

	return OverwatchState
end

return OverwatchState
