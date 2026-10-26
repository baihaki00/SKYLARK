--// Evasion.lua
-- Two moves made in Cascadeur, both played in place with the body driven by physics along the
-- path the owner authored (measured from the source FBX root motion):
--
--   Focused dash  (Tactics.FocusDashForward/Left/Right/Backward) - locked on its target, the Quin
--                 dashes ~4 m (two Cascadeur grids) and keeps facing it the whole way: a quick
--                 reposition without turning its back, a change of angle on a confused target, a
--                 way round a guard to find an opening. The path can bend (an arc; sideways dashes
--                 curve round the target). Timing from the clip's markers: DashStart, DashEnd
--                 (the travel is done), Recover (free to act).
--   Quick evade   (Tactics.QuickEvadeBack/Left/Right) - a lean away from a strike seen coming
--                 (Modules/Instinct). A punch or kick thrown with the left is slipped to the right
--                 and the other way round; back works against either. A Quin can guess wrong and
--                 lean into it: then it is hit. Markers: Evade, EvadeApex (the lean is deepest:
--                 timed to the strike's contact), Recover. The ~0.35 m sway of the clip is driven
--                 by physics too.
--
-- While a move runs, Fight and Circling hold (Evasion.busy) so nothing else steers or turns the body.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local KeyframeSequenceProvider = game:GetService("KeyframeSequenceProvider")

local QuinCore = ReplicatedStorage:WaitForChild("QuinCore")
local CombatConfig = require(QuinCore:WaitForChild("CombatConfig"))
local AnimationConfig = require(QuinCore:WaitForChild("AnimationConfig"))
local Modules = QuinCore:WaitForChild("Modules")
local ImpulseModule = require(Modules:WaitForChild("ImpulseModule"))

local Evasion = {}

local function cfg(key, default)
	local v = CombatConfig[key]
	if v == nil then return default end
	return v
end

local FPS = 30
-- Travel along the move, fraction of the whole, every 2 frames from frame 0 (the source FBX root
-- motion, held at the end: the overshoot past frame 10 is left to friction)
local DASH_PATH = {
	Forward = { 0, 0.13, 0.50, 0.72, 1.00, 1.00 },
	Backward = { 0, 0.70, 0.80, 0.95, 1.00, 1.00 },
	Left = { 0, 0.18, 0.375, 0.72, 0.98, 1.00 },
	Right = { 0, 0.18, 0.375, 0.72, 0.98, 1.00 },
}
-- The evade's sway in metres away from the strike, every 2 frames: out, held, back
local EVADE_PATH = {
	Back = { 0, 0.23, 0.39, 0.34, 0.23, 0.11, 0.01, -0.03, -0.03, -0.01, 0 },
	Left = { 0, 0.22, 0.30, 0.31, 0.32, 0.22, 0.03, -0.05, -0.04, -0.01, 0 },
	Right = { 0, 0.25, 0.34, 0.34, 0.34, 0.31, 0.20, 0.10, 0.07, 0.04, 0.01 },
}
local DASH_CLIP = { Forward = "Tactics.FocusDashForward", Left = "Tactics.FocusDashLeft", Right = "Tactics.FocusDashRight", Backward = "Tactics.FocusDashBackward" }
local EVADE_CLIP = { Back = "Tactics.QuickEvadeBack", Left = "Tactics.QuickEvadeLeft", Right = "Tactics.QuickEvadeRight" }
-- (the owner's frames, used until the clip's own markers are read)
local DASH_MARKS = { DashStart = 0, DashEnd = 8 / FPS, Recover = 15 / FPS }
local EVADE_MARKS = { Evade = 0, EvadeApex = 3 / FPS, Recover = 17 / FPS }

local markers = {} -- asset id -> { [name] = seconds }
local active = setmetatable({}, { __mode = "k" }) -- fighter -> the running move
local stats = { dash = 0, dashRefused = 0, evadeRight = 0, evadeWrong = 0 }

local function entry(path)
	return AnimationConfig.get and AnimationConfig.get(path)
end

local function readMarkers(id)
	local ok, sequence = pcall(function() return KeyframeSequenceProvider:GetKeyframeSequenceAsync(id) end)
	if not ok or not sequence then return end
	local found = {}
	for _, keyframe in ipairs(sequence:GetKeyframes()) do
		for _, marker in ipairs(keyframe:GetMarkers()) do
			found[marker.Name] = keyframe.Time
		end
	end
	markers[id] = found
end

local function marks(path, defaults)
	local e = entry(path)
	local m = e and e.id and markers[e.id]
	if not m then return defaults end
	local out = {}
	for k, v in pairs(defaults) do out[k] = m[k] or v end
	return out
end

-- Read every clip's markers now (server start), not mid-fight
function Evasion.preload()
	for _, list in ipairs({ DASH_CLIP, EVADE_CLIP }) do
		for _, path in pairs(list) do
			local e = entry(path)
			if e and e.id and e.id ~= "" and not markers[e.id] then
				task.spawn(readMarkers, e.id)
			end
		end
	end
	if RunService:IsStudio() then
		task.spawn(function()
			while true do
				task.wait(5)
				Workspace:SetAttribute("EvasionStats", string.format("dash %d refused %d evade right %d wrong %d",
					stats.dash, stats.dashRefused, stats.evadeRight, stats.evadeWrong))
			end
		end)
	end
end

-- Travel fraction at time t along a path sampled every `step` seconds
local function sample(path, t, step)
	local i = t / step
	local a = math.floor(i)
	if a >= #path - 1 then return path[#path] end
	local f = i - a
	return path[a + 1] + (path[a + 2] - path[a + 1]) * f
end

local function flat(v)
	return Vector3.new(v.X, 0, v.Z)
end

local function rotateY(v, angle)
	local c, s = math.cos(angle), math.sin(angle)
	return Vector3.new(v.X * c + v.Z * s, 0, -v.X * s + v.Z * c)
end

local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude
groundParams.RespectCanCollide = true

-- Solid floor under a point, at about the body's height (no drop off a ledge, no wall in the way)
local function clearPath(rootPart, dir, distance)
	groundParams.FilterDescendantsInstances = { rootPart.Parent, Workspace:FindFirstChild("QuinServer") }
	local wall = Workspace:Raycast(rootPart.Position, dir * (distance + 2), groundParams)
	if wall and math.abs(wall.Normal.Y) < 0.5 then return false end
	for _, f in ipairs({ 0.5, 1 }) do
		local p = rootPart.Position + dir * distance * f
		local hit = Workspace:Raycast(p + Vector3.new(0, 2, 0), Vector3.new(0, -9, 0), groundParams)
		if not hit or hit.Normal.Y < 0.7 then return false end
	end
	return true
end

-- The facing that holds the body on its target: the state's own gyro
local function faceGyro(rootPart)
	for _, name in ipairs({ "CirclingGyro", "FightGyro" }) do
		local g = rootPart:FindFirstChild(name)
		if g and g:IsA("AlignOrientation") and g.Enabled then return g end
	end
end

local function stillFree(fighter, humanoid)
	if not fighter.Parent or humanoid.Health <= 0 or fighter:GetAttribute("IsInert") == true then return false end
	if (fighter:GetAttribute("StunEndTime") or 0) > tick() then return false end
	local state = fighter:GetAttribute("CurrentState")
	return state == "Fight" or state == "Circling"
end

-- Drive the body along a path each frame: displacement(t) studs along dir(t). The body is steered
-- to follow it (what it actually covered is measured), capped at maxSpeed: a path that asks for
-- more than physics can give is caught up on rather than lost.
local function drive(fighter, humanoid, rootPart, move, displacement, dirAt, travelEnd, tag, maxForce, maxSpeed)
	local start = os.clock()
	local lastT = 0
	local covered = 0
	local conn
	conn = RunService.Heartbeat:Connect(function()
		local t = os.clock() - start
		local targetRoot = move.target and move.target.Parent and move.target
		if active[fighter] ~= move or not stillFree(fighter, humanoid) then
			conn:Disconnect()
			ImpulseModule.cancel(fighter, tag)
			if active[fighter] == move then active[fighter] = nil end
			return
		end
		-- locked on: the body keeps facing its target the whole move
		local gyro = faceGyro(rootPart)
		if gyro and targetRoot then
			local to = flat(targetRoot.Position - rootPart.Position)
			if to.Magnitude > 0.5 then
				gyro.CFrame = CFrame.lookAt(Vector3.zero, to.Unit)
				gyro.MaxAngularVelocity = 20
			end
		end
		if t >= move.freeAt then
			conn:Disconnect()
			ImpulseModule.cancel(fighter, tag)
			active[fighter] = nil
			return
		end
		local dt = t - lastT
		lastT = t
		local dir = dirAt(math.min(t, travelEnd))
		covered += rootPart.AssemblyLinearVelocity:Dot(dir) * dt
		if t > travelEnd + 0.1 then
			ImpulseModule.cancel(fighter, tag)
			return
		end
		local lead = 1 / 30
		local want = displacement(math.min(t + lead, travelEnd))
		local speed = math.clamp((want - covered) / lead, -maxSpeed, maxSpeed)
		if math.abs(speed) < 0.5 then
			ImpulseModule.cancel(fighter, tag)
		else
			ImpulseModule.push(fighter, tag, speed > 0 and dir or -dir, math.abs(speed), 0.1, {
				profile = "hold", endRatio = 1, rampIn = 0, maxForce = maxForce,
				priority = ImpulseModule.Priority.SelfMotion,
			})
		end
	end)
end

-- True while a dash or an evade has the body (the states hold off)
function Evasion.busy(fighter)
	local move = active[fighter]
	return move ~= nil and os.clock() < move.until_
end

function Evasion.dashReady(fighter)
	if fighter:GetAttribute("PilotedBy") or cfg("FocusDash_Enabled", true) == false then return false end
	if active[fighter] then return false end
	if tick() < (fighter:GetAttribute("FocusDashReadyAt") or 0) then return false end
	return (fighter:GetAttribute("Energy") or 100) >= cfg("FocusDash_MinEnergy", 15)
end

-- Which clip a world direction is, for a body facing its target
local function dashKind(dir, toTarget)
	local fwd = dir:Dot(toTarget)
	local right = dir:Dot(Vector3.new(-toTarget.Z, 0, toTarget.X))
	if fwd > 0.7 then return "Forward" end
	if fwd < -0.7 then return "Backward" end
	return right > 0 and "Right" or "Left"
end

-- Dash, locked on `target` (its root part), toward the world direction `want`.
-- opts: { curve = radians the path bends over the dash (random when nil), distance = studs }
-- Returns the kind of dash, or nil when there is no room for one.
function Evasion.focusDash(fighter, humanoid, rootPart, targetRoot, want, opts)
	opts = opts or {}
	if not Evasion.dashReady(fighter) or not targetRoot then return nil end
	local toTarget = flat(targetRoot.Position - rootPart.Position)
	want = flat(want)
	if toTarget.Magnitude < 0.5 or want.Magnitude < 0.01 then return nil end
	toTarget, want = toTarget.Unit, want.Unit
	local kind = dashKind(want, toTarget)
	local right = Vector3.new(-toTarget.Z, 0, toTarget.X)
	local base = (kind == "Forward" and toTarget) or (kind == "Backward" and -toTarget) or (kind == "Right" and right) or -right
	-- the authored direction, turned part of the way toward the one wanted
	local lean = math.atan2(base:Cross(want).Y, base:Dot(want))
	local startDir = rotateY(base, math.clamp(lean, -0.6, 0.6) * 0.6)
	local maxCurve = math.rad(cfg("FocusDash_CurveMaxDeg", 35))
	local curve = opts.curve or ((math.random() * 2 - 1) * maxCurve)

	local distance = opts.distance or cfg("FocusDash_Distance", 18.5)
	if not clearPath(rootPart, startDir, distance) then
		distance *= 0.55
		if not clearPath(rootPart, startDir, distance) then
			stats.dashRefused += 1
			fighter:SetAttribute("FocusDashReadyAt", tick() + 0.6)
			return nil
		end
	end

	local speedMult = Workspace:GetAttribute("GameSpeedMultiplier") or 1.0
	local clipPath = DASH_CLIP[kind]
	local clip = entry(clipPath)
	local playSpeed = ((clip and clip.speed) or 1) * cfg("FocusDash_PlaySpeed", 1.0) * speedMult
	local m = marks(clipPath, DASH_MARKS)
	local travelEnd = math.max((m.DashEnd - m.DashStart) / playSpeed, 0.1)
	local step = (2 / FPS) * (travelEnd / (8 / FPS)) -- the path's samples, stretched to the clip's own DashEnd
	local path = DASH_PATH[kind]
	local orbit = (kind == "Left" or kind == "Right") and cfg("FocusDash_OrbitBlend", 0.6) or 0

	local move = { kind = kind, target = targetRoot }
	move.freeAt = math.max(m.Recover / playSpeed, travelEnd)
	move.until_ = os.clock() + move.freeAt
	active[fighter] = move

	local energy = fighter:GetAttribute("Energy") or 100
	fighter:SetAttribute("Energy", math.max(0, energy - cfg("FocusDash_EnergyCost", 6)))
	local cdMin, cdMax = cfg("FocusDash_CooldownMin", 1.6), cfg("FocusDash_CooldownMax", 3.2)
	fighter:SetAttribute("FocusDashReadyAt", tick() + cdMin + math.random() * (cdMax - cdMin))
	fighter:SetAttribute("FocusDash", kind)
	fighter:SetAttribute("FocusDashAt", os.clock())
	stats.dash += 1

	local LocomotionModule = require(Modules:WaitForChild("LocomotionModule"))
	local AnimationModule = require(Modules:WaitForChild("AnimationModule"))
	LocomotionModule.cancelSteer(fighter)
	humanoid:Move(Vector3.zero, false)
	AnimationModule.playConfig(humanoid, clipPath, playSpeed / ((clip and clip.speed) or 1), Enum.AnimationPriority.Action3, false)
	local AudioModule = require(Modules:WaitForChild("AudioModule"))
	if AudioModule.playDash then AudioModule.playDash(rootPart) end
	-- the ground dash's look (owner 2026-10-27): the vapour cone at the push-off, the dust trail
	-- for the dash
	local VfxModule = require(Modules:WaitForChild("VfxModule"))
	VfxModule.createVaporCone(rootPart, 0.35)
	local stopTrail = VfxModule.createDashTrail(rootPart)
	task.delay(travelEnd, stopTrail)

	drive(fighter, humanoid, rootPart, move,
		function(t) return sample(path, t, step) * distance end,
		function(t)
			local p = math.clamp(t / travelEnd, 0, 1)
			local dir = rotateY(startDir, curve * p)
			-- sideways: the path bends round the target (an arc at the distance it started from)
			if orbit > 0 and targetRoot.Parent then
				local to = flat(targetRoot.Position - rootPart.Position)
				if to.Magnitude > 1 then
					local tangent = Vector3.new(-to.Unit.Z, 0, to.Unit.X)
					if tangent:Dot(dir) < 0 then tangent = -tangent end
					dir = (dir * (1 - orbit) + tangent * orbit).Unit
				end
			end
			return dir
		end,
		travelEnd, "focusdash", 150000, cfg("FocusDash_MaxSpeed", 110) * speedMult)
	return kind
end

-- Lean away from a strike seen coming. Returns "right" (it slipped it: the strike misses) or
-- "wrong" (it leaned into it), or nil when no evade could be played.
function Evasion.evade(defender, humanoid, rootPart, attacker, attackerRoot, contactAt)
	if cfg("QuickEvade_Enabled", true) == false or active[defender] then return nil end
	local state = defender:GetAttribute("CurrentState")
	if state ~= "Fight" and state ~= "Circling" then return nil end -- (on the run it slides as before)
	local now = tick()
	local timeLeft = contactAt - now
	if timeLeft <= 0 then return nil end

	-- The answer: a left is slipped to the right, a right to the left, back for either
	local side = attacker:GetAttribute("StrikeSide")
	local kind
	if math.random() < cfg("QuickEvade_BackChance", 0.3) then
		kind = "Back"
	elseif side == "Left" then
		kind = "Right"
	elseif side == "Right" then
		kind = "Left"
	else
		kind = math.random() < 0.5 and "Left" or "Right"
	end
	-- ...unless it reads it wrong and leans into the limb (the less aware, the more often)
	local awareness = defender:GetAttribute("Pers_Awareness") or 0.6
	local wrong = false
	if side and kind ~= "Back" and math.random() < cfg("QuickEvade_MistakeChance", 0.2) * (1.5 - awareness) then
		kind = side
		wrong = true
	end

	local clipPath = EVADE_CLIP[kind]
	local clip = entry(clipPath)
	if not clip or not clip.id or clip.id == "" then return nil end
	local m = marks(clipPath, EVADE_MARKS)
	-- played so its deepest lean meets the strike
	local apex = math.max(m.EvadeApex - m.Evade, 1 / FPS)
	local playSpeed = math.clamp(apex / timeLeft, cfg("QuickEvade_MinSpeed", 0.7), cfg("QuickEvade_MaxSpeed", 1.6))

	local away = flat(rootPart.Position - attackerRoot.Position)
	away = away.Magnitude > 0.01 and away.Unit or -flat(rootPart.CFrame.LookVector).Unit
	local toAttacker = -away
	local right = Vector3.new(-toAttacker.Z, 0, toAttacker.X)
	local dir = (kind == "Back" and away) or (kind == "Right" and right) or -right

	local move = { kind = kind, target = attackerRoot }
	move.freeAt = m.Recover / playSpeed
	move.until_ = os.clock() + move.freeAt
	active[defender] = move

	local AnimationModule = require(Modules:WaitForChild("AnimationModule"))
	local LocomotionModule = require(Modules:WaitForChild("LocomotionModule"))
	LocomotionModule.cancelSteer(defender)
	humanoid:Move(Vector3.zero, false)
	AnimationModule.playConfig(humanoid, clipPath, playSpeed / (clip.speed or 1), Enum.AnimationPriority.Action3, false)

	local studsPerMetre = cfg("QuickEvade_StudsPerMetre", 4.1)
	local path = EVADE_PATH[kind]
	local step = (2 / FPS) / playSpeed
	drive(defender, humanoid, rootPart, move,
		function(t) return sample(path, t, step) * studsPerMetre end,
		function() return dir end,
		step * (#path - 1), "evade", 60000, 40)

	if wrong then
		stats.evadeWrong += 1
	else
		stats.evadeRight += 1
		-- the strike from this attacker misses while the lean is in (DamageModule reads it)
		defender:SetAttribute("EvadeFrom", attacker.Name)
		defender:SetAttribute("EvadeSafeUntil", contactAt + cfg("QuickEvade_SafeAfterContact", 0.25))
	end
	defender:SetAttribute("Evade", kind .. (wrong and " (wrong)" or ""))
	defender:SetAttribute("EvadeAt", os.clock())
	return wrong and "wrong" or "right"
end

-- DamageModule: does this target slip this attacker's strike right now?
function Evasion.slips(targetModel, attackerModel)
	local untilT = targetModel:GetAttribute("EvadeSafeUntil")
	return untilT ~= nil and tick() < untilT and targetModel:GetAttribute("EvadeFrom") == attackerModel.Name
end

return Evasion
