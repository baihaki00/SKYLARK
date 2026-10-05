--// AirDash.lua
-- A dash in the air (combination moves: jump -> dash, wall run -> dash off the wall).
--
-- Nothing schedules it. A Quin already in the air (a jump onto a platform, the kick off a wall)
-- checks, once per airtime, whether a dash would get it somewhere:
--   at a target   the target is within dash reach and in sight from up here: it dashes in and
--                 lands in the fight. The chance grows with dash preference and aggression, and
--                 is higher off a wall (it has its speed and the wall to push from).
--   to a ledge    a jump onto a platform is coming down short of it: a dash carries it on to
--                 the edge (the jump told it where it meant to land: AirDash.noteJump)
--   along a chase off a wall, a target that kept running is still in sight: it dashes after it
-- The dash cooldown (LastDashTime, shared with the ground dash) and energy apply.
--
-- Physics: the horizontal burst is an ImpulseModule request (one force channel per body); the
-- vertical is set once at the start (a little lift, or down toward a target below) and gravity
-- does the rest: a flat, fast arc, not a hover.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local QuinCore = ReplicatedStorage:WaitForChild("QuinCore")
local Modules = QuinCore:WaitForChild("Modules")
local CombatConfig = require(QuinCore:WaitForChild("CombatConfig"))
local ImpulseModule = require(Modules:WaitForChild("ImpulseModule"))
local AnimationModule = require(Modules:WaitForChild("AnimationModule"))
local AudioModule = require(Modules:WaitForChild("AudioModule"))
local VfxModule = require(Modules:WaitForChild("VfxModule"))
local SpatialModule = require(Modules:WaitForChild("SpatialModule"))

local AirDash = {}

local isStudio = game:GetService("RunService"):IsStudio()

local air = setmetatable({}, { __mode = "k" }) -- fighter -> this airtime { since, used, rolled, wall }
local stats = { attack = 0, ledge = 0, chase = 0, declined = 0 }

local function cfg(key, default)
	local v = CombatConfig["AirDash_" .. key]
	if v == nil then return default end
	return v
end

local function flat(v) return Vector3.new(v.X, 0, v.Z) end

-- Why the last airtime did not dash (debug HUD, probes)
local function skip(fighter, reason)
	if fighter:GetAttribute("AirDashSkip") ~= reason then fighter:SetAttribute("AirDashSkip", reason) end
	return false
end

local function grounded(rootPart, humanoid)
	local state = humanoid:GetState()
	if state == Enum.HumanoidStateType.Freefall or state == Enum.HumanoidStateType.Jumping then return false end
	return SpatialModule.isGrounded(rootPart)
end

local function airtime(fighter)
	local a = air[fighter]
	if not a then
		a = { since = os.clock() }
		air[fighter] = a
	end
	return a
end

local function publish()
	Workspace:SetAttribute("AirDashStats", string.format("attack %d ledge %d chase %d declined %d", stats.attack, stats.ledge, stats.chase, stats.declined))
end

-- A traversal jump says where it means to land (the platform's top, past the edge)
function AirDash.noteJump(fighter, aimPoint)
	air[fighter] = { since = os.clock(), aim = aimPoint }
end

-- The kick off a wall: the next check is a wall dash (after the kick has carried it clear)
function AirDash.noteWallKick(fighter)
	air[fighter] = { since = os.clock(), wall = true }
end

-- The dash itself. vertical: the body's vertical speed at the start (nil: a small lift)
local function perform(fighter, humanoid, rootPart, point, travel, vertical, reason)
	local dir = flat(point - rootPart.Position)
	if dir.Magnitude < 0.5 then return false end
	dir = dir.Unit
	local duration = cfg("Duration", 0.26)
	local speed = math.min(cfg("Speed", 115), ImpulseModule.speedForDistance(travel, duration, "hold", 0.25))
	local v = rootPart.AssemblyLinearVelocity
	rootPart.AssemblyLinearVelocity = Vector3.new(v.X, vertical or cfg("Lift", 6), v.Z)
	ImpulseModule.push(fighter, "airdash", dir, speed, duration, {
		profile = "hold", endRatio = 0.25, priority = ImpulseModule.Priority.SelfMotion, maxForce = cfg("Force", 40000),
	})
	-- face the dash (whichever facing constraint is driving the body, else the humanoid's turn)
	humanoid:Move(dir, false)
	for _, child in ipairs(rootPart:GetChildren()) do
		if child:IsA("AlignOrientation") and child.Enabled then
			child.CFrame = CFrame.lookAt(Vector3.zero, dir)
		end
	end
	-- the pose: the start of the ninja jump (the push-off), cut when the burst ends
	local track = AnimationModule.playConfig(humanoid, "Movement.AirDash", cfg("ClipSpeed", 1.4), Enum.AnimationPriority.Action3, false)
	if track then
		task.delay(duration + cfg("ClipHold", 0.1), function()
			if track.IsPlaying then track:Stop(cfg("ClipFade", 0.15)) end
		end)
	end
	-- the ground dash's own sound and vapour cone
	AudioModule.playDash(rootPart)
	VfxModule.createVaporCone(rootPart, cfg("ConeTime", 0.4))
	fighter:SetAttribute("LastDashTime", tick())
	fighter:SetAttribute("Energy", math.max(0, (fighter:GetAttribute("Energy") or 100) - cfg("EnergyCost", 15)))
	fighter:SetAttribute("AirDashReason", reason)
	fighter:SetAttribute("AirDashAt", os.clock())
	stats[reason] = (stats[reason] or 0) + 1
	publish()
	return true
end

-- Called by the states that carry a Quin through the air (ChaseState). True when it dashed.
function AirDash.consider(fighter, humanoid, rootPart, target)
	if CombatConfig.AirDash_Enabled == false then return false end
	if grounded(rootPart, humanoid) then
		air[fighter] = nil
		return false
	end
	local a = airtime(fighter)
	if a.used then return false end
	local inAir = os.clock() - a.since
	if inAir < (a.wall and cfg("WallKickTime", 0.24) or cfg("MinAirTime", 0.12)) then return false end
	if tick() - (fighter:GetAttribute("LastDashTime") or 0) < cfg("Cooldown", 5) then return skip(fighter, "cooldown") end
	if (fighter:GetAttribute("Energy") or 100) < cfg("MinEnergy", 20) then return skip(fighter, "energy") end

	local v = rootPart.AssemblyLinearVelocity
	local feetY = rootPart.Position.Y - (humanoid.HipHeight + rootPart.Size.Y / 2)

	-- To a ledge: a jump onto a platform coming down short of it
	if a.aim and v.Y < 0 and feetY > a.aim.Y + 0.3 then
		local h = feetY - a.aim.Y
		local g = Workspace.Gravity
		local fall = (v.Y + math.sqrt(v.Y * v.Y + 2 * g * h)) / g -- seconds until the feet reach the top
		local reach = flat(v).Magnitude * fall
		local gap = flat(a.aim - rootPart.Position).Magnitude
		if gap > reach + cfg("LedgeMargin", 1.5) and gap <= cfg("MaxTravel", 40) then
			a.used = true
			fighter:SetAttribute("ObstacleAwareness", "Dash to make the ledge")
			return perform(fighter, humanoid, rootPart, a.aim, gap + 2, cfg("LedgeLift", 14), "ledge")
		end
	end

	-- At a target (or after it, off a wall)
	local targetRoot = target and target.Parent and target:FindFirstChild("HumanoidRootPart")
	if not targetRoot or a.rolled then return false end
	-- Only with air enough left to fly the dash: a hop or a short drop lands before the burst is
	-- through, and the floor stops it (measured: 2-10 studs covered, touchdown 0.1-0.2 s in)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { fighter, Workspace:FindFirstChild("QuinServer") }
	local down = Workspace:Raycast(rootPart.Position, Vector3.new(0, -cfg("GroundProbe", 80), 0), params)
	if down then
		-- (the dash flattens the jump: what counts is the air left from the vertical speed it
		-- will set, not the climb it is in now)
		local h = math.max(0, feetY - down.Position.Y)
		local g = Workspace.Gravity
		local vy = math.min(v.Y, cfg("Lift", 6))
		local airLeft = (vy + math.sqrt(vy * vy + 2 * g * h)) / g
		if airLeft < cfg("MinAirLeft", 0.3) then return skip(fighter, string.format("air left %.2fs", airLeft)) end
	end
	local toTarget = targetRoot.Position - rootPart.Position
	local d = flat(toTarget).Magnitude
	local maxRange = a.wall and cfg("WallRange", 45) or cfg("Range", 36)
	local inReach = d >= cfg("MinRange", 8) and d <= maxRange and toTarget.Y >= -cfg("MaxDrop", 30) and toTarget.Y <= cfg("MaxRise", 8)
	local chasing = a.wall and not inReach and d > maxRange and d <= cfg("ChaseRange", 90)
	if not (inReach or chasing) then return skip(fighter, string.format("out of reach %.0f/%.0f", d, toTarget.Y)) end
	if not SpatialModule.checkLineOfSight(SpatialModule.getEyePosition(rootPart), SpatialModule.getEyePosition(targetRoot), { fighter, target }) then
		return skip(fighter, "no sight")
	end
	-- one decision per airtime
	a.rolled = true
	local dashPref = fighter:GetAttribute("Pers_DashPreference") or 0.6
	local aggression = fighter:GetAttribute("Pers_Aggression") or 0.6
	local base = a.wall and cfg("WallChance", 0.55) or cfg("Chance", 0.3)
	if isStudio and Workspace:GetAttribute("AirDashAlways") then base = 10 end -- (test switch)
	if math.random() >= base * (0.5 + dashPref) * (0.5 + aggression) then
		stats.declined += 1
		publish()
		return skip(fighter, "declined")
	end
	a.used = true
	if inReach then
		-- in at the target: stops short at striking range, down toward it if it is below
		local travel = math.clamp(d - (CombatConfig.CombatRange or 8) * 0.9, 6, cfg("MaxTravel", 40))
		local vertical = toTarget.Y < -4 and math.max(toTarget.Y / (cfg("Duration", 0.26) * 2), -cfg("MaxDropSpeed", 45)) or nil
		fighter:SetAttribute("ObstacleAwareness", a.wall and "Dash off the wall at the target" or "Jump -> dash at the target")
		return perform(fighter, humanoid, rootPart, targetRoot.Position, travel, vertical, "attack")
	end
	fighter:SetAttribute("ObstacleAwareness", "Dash off the wall after the target")
	return perform(fighter, humanoid, rootPart, targetRoot.Position, cfg("MaxTravel", 40), nil, "chase")
end

-- Off the wall itself, at the top of a wall run (WallRunState asks once per run): the target is in
-- dash reach and not behind the wall. release() is called before the dash so the run's movers let
-- go of the body. True when it dashed. (The kick at the end of a full arc comes from about floor
-- height, with no air left for a dash.)
function AirDash.fromWall(fighter, humanoid, rootPart, target, normal, release)
	if CombatConfig.AirDash_Enabled == false then return false end
	if tick() - (fighter:GetAttribute("LastDashTime") or 0) < cfg("Cooldown", 5) then return skip(fighter, "cooldown") end
	if (fighter:GetAttribute("Energy") or 100) < cfg("MinEnergy", 20) then return skip(fighter, "energy") end
	local targetRoot = target and target.Parent and target:FindFirstChild("HumanoidRootPart")
	if not targetRoot then return false end
	local toTarget = targetRoot.Position - rootPart.Position
	local d = flat(toTarget).Magnitude
	if d < cfg("MinRange", 8) or d > cfg("WallRange", 45) or toTarget.Y < -cfg("MaxDrop", 30) or toTarget.Y > cfg("MaxRise", 8) then
		return skip(fighter, string.format("wall: out of reach %.0f/%.0f", d, toTarget.Y))
	end
	if flat(toTarget).Unit:Dot(normal) < cfg("WallMinOut", -0.1) then return skip(fighter, "wall: target behind the wall") end
	if not SpatialModule.checkLineOfSight(SpatialModule.getEyePosition(rootPart), SpatialModule.getEyePosition(targetRoot), { fighter, target }) then
		return skip(fighter, "wall: no sight")
	end
	local dashPref = fighter:GetAttribute("Pers_DashPreference") or 0.6
	local aggression = fighter:GetAttribute("Pers_Aggression") or 0.6
	local base = cfg("WallChance", 0.55)
	if isStudio and Workspace:GetAttribute("AirDashAlways") then base = 10 end -- (test switch)
	if math.random() >= base * (0.5 + dashPref) * (0.5 + aggression) then
		stats.declined += 1
		publish()
		return skip(fighter, "wall: declined")
	end
	release()
	air[fighter] = { since = os.clock(), used = true, wall = true }
	local travel = math.clamp(d - (CombatConfig.CombatRange or 8) * 0.9, 6, cfg("MaxTravel", 40))
	local vertical = toTarget.Y < -4 and math.max(toTarget.Y / (cfg("Duration", 0.26) * 2), -cfg("MaxDropSpeed", 45)) or nil
	fighter:SetAttribute("ObstacleAwareness", "Dash off the wall at the target")
	return perform(fighter, humanoid, rootPart, targetRoot.Position, travel, vertical, "attack")
end

-- Studio test hook: Workspace attribute AirDashDevCommand = "reset" (clears the stats)
if game:GetService("RunService"):IsStudio() and game:GetService("RunService"):IsServer() then
	Workspace:GetAttributeChangedSignal("AirDashDevCommand"):Connect(function()
		local cmd = Workspace:GetAttribute("AirDashDevCommand")
		if cmd == nil or cmd == "" then return end
		Workspace:SetAttribute("AirDashDevCommand", nil)
		if cmd == "reset" then
			stats = { attack = 0, ledge = 0, chase = 0, declined = 0 }
			publish()
		end
	end)
end

return AirDash
