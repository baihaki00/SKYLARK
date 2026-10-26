--// Momentum.lua
-- A Quin's movement as momentum (the owner's direction, 2026-10-27): two Quins like ballistic balls
-- that hate each other, running, leaping, dashing in the air, bouncing off walls, landing and
-- rolling on, all over the arena, with lulls in between. Not a state: a characteristic. Any
-- Quin, whatever its state, can be sent on one of these moves; while a move has the body, Main
-- skips the state's update (Momentum.busy). A forced state (a hit, a clash, death) still cuts in,
-- and the move lets go of the body at once.
--
-- Step 1 (this file): the moves. Nothing in the game calls them yet but the Studio test command
-- (MomentumDevCommand, below); step 2 is the brain that picks them.
--   leap     a ballistic arc to a spot, topping out apex studs over its higher end
--   hop      a short leap on along the way it is running: it keeps its speed
--   dash     a straight burst at a target (led, re-aimed every frame) or at a spot, at the
--            projectile jump's dive speed
--   bounce   off a wall it flies or dashes into: kicked back out and up (a dash at a target
--            goes again at it off the wall)
--   contact  a dash reaching its target: both strike and are thrown apart, each on its own arc
--   land     touching down: placed on its feet; with speed, a roll that carries the speed on
--            (ImpulseModule), then the state has the body again
--
-- The mechanics are ProjectileJumpState's, copied, not shared (the owner: keep that state exactly
-- as it is): a platform-standing body, one LinearVelocity switched on and off per axis, an
-- AlignOrientation along the flight, arena containment, and the set-down snap on touchdown.
-- Off switch: CombatConfig.Momentum.Enabled = false (Main's guard and the test command stop).
-- The shared loop is started from Server (Momentum.start): a loop started from a Quin's Main dies
-- with that Quin.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local QuinCore = ReplicatedStorage:WaitForChild("QuinCore")
local Modules = QuinCore:WaitForChild("Modules")
local CombatConfig = require(QuinCore:WaitForChild("CombatConfig"))
local AnimationIds = require(QuinCore:WaitForChild("AnimationIds"))
local AnimationModule = require(Modules:WaitForChild("AnimationModule"))
local AudioModule = require(Modules:WaitForChild("AudioModule"))
local VfxModule = require(Modules:WaitForChild("VfxModule"))
local SpatialModule = require(Modules:WaitForChild("SpatialModule"))
local ImpulseModule = require(Modules:WaitForChild("ImpulseModule"))

local Momentum = {}

local FULL_FORCE = Vector3.new(math.huge, math.huge, math.huge)
local ARENA_MARGIN = 30
local MOVER_NAMES = { MOM_Att = true, MOM_LinearVelocity = true, MOM_Align = true }
-- the states that fly the body with movers of their own: a contact does not take them over
local OWN_FLIGHT = { ProjectileJump = true, MidAirClash = true, Knockback = true, WallRun = true, Death = true, BeamStruggle = true }

local moves = {} -- fighter -> the move that has its body

local function cfg(key, default)
	local t = CombatConfig.Momentum
	local v = t and t[key]
	if v == nil then return default end
	return v
end

function Momentum.enabled()
	return CombatConfig.Momentum ~= nil and CombatConfig.Momentum.Enabled ~= false
end

-- True while a move has this Quin's body (Main skips the state's update)
function Momentum.busy(fighter)
	return moves[fighter] ~= nil
end

-- What the move is doing ("leap", "dash", "thrown", "bounce", "air"), nil when none
function Momentum.kind(fighter)
	local rec = moves[fighter]
	return rec and rec.kind or nil
end

-- The Quin a dash is going at (nil: none, or not a dash)
function Momentum.targetOf(fighter)
	local rec = moves[fighter]
	return rec and rec.kind == "dash" and rec.target or nil
end

-- Seconds since the move's current part began (a leap, a dash, a throw)
function Momentum.phaseAge(fighter)
	local rec = moves[fighter]
	return rec and os.clock() - (rec.phaseAt or rec.started) or math.huge
end

-- Off the ground: in a move, or falling or jumping on its own
function Momentum.inAir(fighter)
	if moves[fighter] then return true end
	local humanoid = fighter:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.FloorMaterial == Enum.Material.Air
end

-- Contact outcomes are asked of this, when set (MomentumDuel): hook(dasher, other) ->
-- nil (thrown apart) or { throw = x, up = x } (scaled throws: a brawl's small ones) or
-- { ground = true } (the dasher lands beside a standing Quin: the fight goes on on the ground)
Momentum.contactHook = nil

local function flat(v)
	return Vector3.new(v.X, 0, v.Z)
end

local function unitOr(v, fallback)
	return v.Magnitude > 1e-4 and v.Unit or fallback
end

local function bodyOf(fighter)
	local humanoid = fighter and fighter.Parent and fighter:FindFirstChildOfClass("Humanoid")
	local root = fighter and fighter:FindFirstChild("HumanoidRootPart")
	if humanoid and root and humanoid.Health > 0 then
		return humanoid, root
	end
	return nil
end

local function standOffset(humanoid, root)
	return humanoid.HipHeight + root.Size.Y / 2
end

local function worldParams(fighter)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { fighter, Workspace:FindFirstChild("QuinServer") }
	params.RespectCanCollide = true
	return params
end

-- how far the feet are over whatever is under them (math.huge: nothing)
local function heightAboveStand(rec)
	local hit = Workspace:Raycast(rec.root.Position, Vector3.new(0, -500, 0), rec.params)
	if not hit then return math.huge end
	return rec.root.Position.Y - standOffset(rec.humanoid, rec.root) - hit.Position.Y
end

-- the standing spot on whatever is under a point (nil: nothing there)
local function groundBelow(fighter, p)
	local hit = Workspace:Raycast(Vector3.new(p.X, p.Y + 150, p.Z), Vector3.new(0, -600, 0), worldParams(fighter))
	return hit and hit.Position or nil
end

-- Removes the outward part of a horizontal velocity once the position is past the margin
local function containVelocity(position, velocity)
	local bounds = SpatialModule.getArenaBounds()
	local x, z = velocity.X, velocity.Z
	local dx, dz = position.X - bounds.center.X, position.Z - bounds.center.Z
	if math.abs(dx) > bounds.halfX - ARENA_MARGIN and dx * x > 0 then x = 0 end
	if math.abs(dz) > bounds.halfZ - ARENA_MARGIN and dz * z > 0 then z = 0 end
	return Vector3.new(x, velocity.Y, z)
end

local function inArena(p)
	local b = SpatialModule.getArenaBounds()
	local rx, rz = b.halfX - ARENA_MARGIN - 10, b.halfZ - ARENA_MARGIN - 10
	return Vector3.new(math.clamp(p.X, b.center.X - rx, b.center.X + rx), p.Y, math.clamp(p.Z, b.center.Z - rz, b.center.Z + rz))
end

-- ============================================================
-- The body: taken for a move, given back after
-- ============================================================

local function playClip(rec, path, speed, looped, priority)
	-- (playConfig's 5th argument is "overlay", not "looped": the dash pose, a 0.1 s clip, played
	-- once and the fight idle showed through the rest of the dash. play() takes the loop flag.)
	AnimationModule.ensureBaseIdle(rec.humanoid)
	local track = AnimationModule.play(rec.humanoid, path, priority or Enum.AnimationPriority.Action3, looped or false, speed or 1, nil, looped or false)
	if looped then rec.loops[path] = true end
	return track
end

local function stopLoops(rec, except)
	for path in pairs(rec.loops) do
		if path ~= except then
			AnimationModule.stopConfig(rec.humanoid, path, 0.1)
			rec.loops[path] = nil
		end
	end
end

local function take(fighter, humanoid, root)
	local rec = moves[fighter]
	if rec then return rec end
	for _, child in ipairs(root:GetChildren()) do
		if MOVER_NAMES[child.Name] then child:Destroy() end
	end
	rec = {
		fighter = fighter, humanoid = humanoid, root = root,
		state = fighter:GetAttribute("CurrentState"),
		params = worldParams(fighter),
		loops = {}, disabled = {},
		bounces = 0, started = os.clock(),
	}
	-- whatever facing constraint the state left on is held off while the move turns the body
	for _, child in ipairs(root:GetChildren()) do
		if child:IsA("AlignOrientation") and child.Enabled then
			child.Enabled = false
			table.insert(rec.disabled, child)
		end
	end
	humanoid:Move(Vector3.zero, false)
	humanoid.PlatformStand = true
	local att = Instance.new("Attachment")
	att.Name = "MOM_Att"
	att.Parent = root
	local lv = Instance.new("LinearVelocity")
	lv.Name = "MOM_LinearVelocity"
	lv.Attachment0 = att
	lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	lv.ForceLimitMode = Enum.ForceLimitMode.PerAxis
	lv.MaxAxesForce = Vector3.zero
	lv.VectorVelocity = Vector3.zero
	lv.Parent = root
	local ao = Instance.new("AlignOrientation")
	ao.Name = "MOM_Align"
	ao.Mode = Enum.OrientationAlignmentMode.OneAttachment
	ao.Attachment0 = att
	ao.MaxTorque = 1e7
	ao.Responsiveness = 40
	ao.CFrame = root.CFrame
	ao.Parent = root
	rec.att, rec.lv, rec.ao = att, lv, ao
	moves[fighter] = rec
	fighter:SetAttribute("MomentumMove", "take")
	return rec
end

-- interrupted: a forced state has the body now (it set up its own movers and stance): only the
-- move's own things are removed
local function finish(rec, interrupted)
	if moves[rec.fighter] ~= rec then return end
	moves[rec.fighter] = nil
	stopLoops(rec)
	if rec.dashFx then rec.dashFx() rec.dashFx = nil end
	for _, inst in ipairs({ rec.att, rec.lv, rec.ao }) do
		if inst and inst.Parent then inst:Destroy() end
	end
	if not interrupted then
		for _, align in ipairs(rec.disabled) do
			if align.Parent then align.Enabled = true end
		end
		if rec.humanoid.Parent then rec.humanoid.PlatformStand = false end
	end
	if rec.fighter.Parent then rec.fighter:SetAttribute("MomentumMove", nil) end
end

local function setBallistic(rec, velocity, kind)
	if rec.dashFx then rec.dashFx() rec.dashFx = nil end
	rec.kind = kind or "air"
	rec.target, rec.point = nil, nil
	rec.lv.MaxAxesForce = Vector3.zero
	rec.root.AssemblyLinearVelocity = containVelocity(rec.root.Position, velocity)
	rec.phaseAt = os.clock()
	rec.fighter:SetAttribute("MomentumMove", rec.kind)
end

-- ============================================================
-- The moves
-- ============================================================

-- A ballistic arc from where it is to a standing spot (the feet's point), topping out apex studs
-- over its higher end. True when it went.
function Momentum.leap(fighter, spot, apex)
	local humanoid, root = bodyOf(fighter)
	if not humanoid then return false end
	local g = Workspace.Gravity
	local p0 = root.Position
	local p1 = inArena(spot) + Vector3.new(0, standOffset(humanoid, root), 0)
	local topY = math.max(p0.Y, p1.Y) + math.max(apex or 30, 1)
	local up = math.sqrt(2 * g * (topY - p0.Y))
	local T = up / g + math.sqrt(2 * (topY - p1.Y) / g)
	local rec = take(fighter, humanoid, root)
	stopLoops(rec)
	setBallistic(rec, flat(p1 - p0) / T + Vector3.yAxis * up, "leap")
	playClip(rec, "ProjectileJump.NinjaJump", cfg("LeapClipSpeed", 1.3), false)
	playClip(rec, "Movement.Fall", 1, true, Enum.AnimationPriority.Action)
	AudioModule.playJumpUp(root.Position)
	if (apex or 30) >= cfg("BigLeapApex", 30) then
		VfxModule.createLaunchShockwave(root)
	end
	return true
end

-- A short leap on along the way it is running: the run's speed is kept
function Momentum.hop(fighter, apex)
	local humanoid, root = bodyOf(fighter)
	if not humanoid then return false end
	apex = apex or cfg("HopApex", 6)
	local v = flat(root.AssemblyLinearVelocity)
	local speed = math.max(v.Magnitude, cfg("HopMinSpeed", 40))
	local dir = unitOr(v, unitOr(flat(root.CFrame.LookVector), Vector3.zAxis))
	local T = 2 * math.sqrt(2 * apex / Workspace.Gravity)
	local spot = groundBelow(fighter, root.Position + dir * speed * T)
	if not spot then return false end
	return Momentum.leap(fighter, spot, apex)
end

-- A quick low leap to one side, out of the line of something coming at it from threat
function Momentum.sidestep(fighter, threat)
	local humanoid, root = bodyOf(fighter)
	if not humanoid then return false end
	local toward = unitOr(flat(threat - root.Position), flat(root.CFrame.LookVector))
	local side = Vector3.new(-toward.Z, 0, toward.X) * (math.random() < 0.5 and -1 or 1)
	local spot = groundBelow(fighter, root.Position + side * math.random(cfg("SidestepMin", 20), cfg("SidestepMax", 35)))
	if not spot then return false end
	return Momentum.leap(fighter, spot, cfg("SidestepApex", 5))
end

-- A burst at a target (a Quin: led and re-aimed every frame) or at a spot (a Vector3)
function Momentum.dash(fighter, target, speed)
	local humanoid, root = bodyOf(fighter)
	if not humanoid then return false end
	local rec = take(fighter, humanoid, root)
	rec.kind = "dash"
	rec.phaseAt = os.clock()
	if typeof(target) == "Vector3" then
		rec.target, rec.point = nil, target
	else
		rec.target, rec.point = target, nil
	end
	rec.speed = (speed or cfg("DashSpeed", CombatConfig.ProjectileJump_SlamSpeed or 480)) * (Workspace:GetAttribute("GameSpeedMultiplier") or 1)
	rec.lv.MaxAxesForce = FULL_FORCE
	fighter:SetAttribute("MomentumMove", "dash")
	stopLoops(rec)
	-- (a dash out of a leap: the leap's push-off clip is cut, the dash pose shows)
	AnimationModule.stopConfig(humanoid, "ProjectileJump.NinjaJump", 0.08)
	AnimationModule.stopConfig(humanoid, "Movement.AirDash", 0.08)
	playClip(rec, "Movement.Dash", 1.4, true) -- the ground dash's pose (a 0.1 s clip), held for the flight
	AudioModule.playDash(root) -- the ground dash's sound (the sonic boom stays ProjectileJump's own)
	VfxModule.createVaporCone(root, 0.5)
	if rec.dashFx then rec.dashFx() end
	rec.dashFx = VfxModule.createDashTrail(root) -- the cone's dust kept up for the whole dash
	return true
end

-- Off a wall: kicked back out and up; a dash at a target goes again at it off the wall
local function bounce(rec, velocity, normal, at)
	local target = rec.target
	local out = velocity - normal * 2 * velocity:Dot(normal)
	local speed = math.clamp(out.Magnitude * cfg("BounceKeep", 0.5), cfg("BounceMinSpeed", 60), cfg("BounceMaxSpeed", 220))
	rec.bounces += 1
	stopLoops(rec)
	setBallistic(rec, unitOr(flat(out), normal) * speed + normal * cfg("BouncePush", 30) + Vector3.yAxis * cfg("BounceUp", 90), "bounce")
	playClip(rec, "Movement.AirDash", 1.4, false)
	playClip(rec, "Movement.Fall", 1, true, Enum.AnimationPriority.Action)
	AudioModule.playDash(rec.root)
	VfxModule.createShockwave(at, 4, 0.15)
	if target then
		rec.redash = { target = target, at = os.clock() + cfg("BounceRedashDelay", 0.22) }
	end
end

local land -- (below)

-- A dash reached its target: both strike and are thrown apart, each on its own arc
local function contact(rec, other)
	local oHum, oRoot = bodyOf(other)
	if not oHum then
		setBallistic(rec, rec.lv.VectorVelocity * 0.3)
		return
	end
	local root = rec.root
	local mid = (root.Position + oRoot.Position) / 2
	local away = unitOr(flat(root.Position - oRoot.Position), -flat(root.CFrame.LookVector).Unit)
	local punches, kicks = AnimationIds.Punches or {}, AnimationIds.Kicks or {}
	local function strike(humanoid)
		local list = (math.random() < 0.5 and #punches > 0) and punches or kicks
		if #list > 0 then
			-- the blow only: then the fall it is thrown into shows (the whole strike clip flew it
			-- across the arena in a punch pose)
			local track = AnimationModule.play(humanoid, list[math.random(1, #list)], Enum.AnimationPriority.Action4, false, 1.6)
			if track then
				task.delay(cfg("ContactStrikeHold", 0.18), function()
					if track.IsPlaying then track:Stop(0.15) end
				end)
			end
		end
	end
	strike(rec.humanoid)
	strike(oHum)
	AudioModule.playSlam(mid)
	VfxModule.createShockwave(mid, 7, 0.18)
	VfxModule.shakeScreen(mid, 250, 6)
	local victim = math.random() < 0.5 and rec.humanoid or oHum
	victim:TakeDamage(cfg("ContactDamage", 2))
	rec.fighter:SetAttribute("MomentumContactAt", os.clock())
	other:SetAttribute("MomentumContactAt", os.clock())

	local outcome = Momentum.contactHook and Momentum.contactHook(rec.fighter, other) or nil
	if outcome and outcome.ground then
		-- into a Quin on its feet: the dasher comes down beside it, and the fight goes on there
		local dir = unitOr(flat(oRoot.Position - root.Position), unitOr(flat(root.CFrame.LookVector), Vector3.zAxis))
		local spot = groundBelow(rec.fighter, oRoot.Position - dir * cfg("GroundContactGap", 5))
		if spot then
			land(rec, dir * 20, spot + Vector3.new(0, standOffset(rec.humanoid, root), 0))
		else
			setBallistic(rec, dir * 20)
		end
		if not moves[other] then
			ImpulseModule.push(other, "momentum_hit", dir, cfg("GroundHitPush", 70), 0.3, {
				profile = "decay", priority = ImpulseModule.Priority.Reaction,
			})
		end
		return
	end
	local throwScale, upScale = outcome and outcome.throw or 1, outcome and outcome.up or 1

	local function throw()
		local side = math.rad(math.random(-35, 35))
		local c, s = math.cos(side), math.sin(side)
		return math.random(cfg("ThrowMin", 70), cfg("ThrowMax", 140)) * throwScale, math.random(cfg("ThrowUpMin", 50), cfg("ThrowUpMax", 110)) * upScale, c, s
	end
	local function turned(v, c, s)
		return Vector3.new(v.X * c + v.Z * s, 0, -v.X * s + v.Z * c)
	end
	local push, up, c, s = throw()
	stopLoops(rec)
	setBallistic(rec, turned(away, c, s) * push + Vector3.yAxis * up, "thrown")
	rec.face = other
	playClip(rec, "Movement.FallAirKnockback", 1, true)
	-- the other is thrown too, unless a state of its own is flying it
	if not OWN_FLIGHT[other:GetAttribute("CurrentState") or ""] then
		local orec = take(other, oHum, oRoot)
		push, up, c, s = throw()
		stopLoops(orec)
		setBallistic(orec, turned(-away, c, s) * push + Vector3.yAxis * up, "thrown")
		orec.face = rec.fighter
		playClip(orec, "Movement.FallAirKnockback", 1, true)
	end
end

-- Touchdown: on its feet; with speed, a roll that carries it on
land = function(rec, velocity, standPos)
	local h = flat(velocity)
	local look = unitOr(h, unitOr(flat(rec.root.CFrame.LookVector), Vector3.zAxis))
	rec.root.CFrame = CFrame.lookAt(standPos, standPos + look)
	rec.root.AssemblyLinearVelocity = Vector3.zero
	local fighter, humanoid, root = rec.fighter, rec.humanoid, rec.root
	local fall = -velocity.Y
	finish(rec, false)
	fighter:SetAttribute("MomentumLandedAt", os.clock())
	if h.Magnitude >= cfg("RollMinSpeed", 40) then
		ImpulseModule.push(fighter, "momentum_roll", look, math.min(h.Magnitude, cfg("RollMaxSpeed", 160)), cfg("RollTime", 0.5), {
			profile = "friction", endRatio = cfg("RollEndRatio", 0.3), priority = ImpulseModule.Priority.SelfMotion,
		})
		AnimationModule.playConfig(humanoid, "Parkour.LandingSoft", cfg("RollClipSpeed", 1.7), Enum.AnimationPriority.Action3, false)
	else
		AnimationModule.playConfig(humanoid, fall > cfg("HardLandingSpeed", 150) and "Parkour.LandingSuperHero" or "Parkour.LandingSoft", 1.3, Enum.AnimationPriority.Action3, false)
	end
	if fall > cfg("HardLandingSpeed", 150) then
		VfxModule.createShockwave(root.Position - Vector3.new(0, standOffset(humanoid, root), 0), 5, 0.15)
	end
end

-- ============================================================
-- The shared loop
-- ============================================================

local function aimAt(rec)
	if rec.point then return rec.point, nil end
	local tHum, tRoot = bodyOf(rec.target)
	if not tHum then return nil, nil end
	local gap = tRoot.Position - rec.root.Position
	local lead = math.clamp(gap.Magnitude / rec.speed, 0, 0.5)
	return tRoot.Position + tRoot.AssemblyLinearVelocity * lead, tRoot
end

local function face(rec, velocity)
	local root = rec.root
	local look
	local other = rec.face and rec.face.Parent and rec.face:FindFirstChild("HumanoidRootPart")
	if other and rec.kind == "thrown" then
		-- thrown: still facing the one it hit, leaning back
		look = unitOr(flat(other.Position - root.Position), flat(root.CFrame.LookVector)) * math.cos(0.35) + Vector3.yAxis * math.sin(0.35)
	elseif velocity.Magnitude > 15 then
		local flatV = flat(velocity)
		local flatDir = unitOr(flatV, unitOr(flat(root.CFrame.LookVector), Vector3.zAxis))
		if rec.kind == "dash" then
			-- head first along the dash, flaring upright over the last stretch to the ground
			local headFirst = math.clamp((heightAboveStand(rec) - 6) / 25, 0, 1)
			look = flatDir:Lerp(velocity.Unit, headFirst)
		else
			local elevation = math.atan2(velocity.Y, math.max(flatV.Magnitude, 0.001))
			local tilt = elevation > 0 and math.clamp(math.pi / 2 - elevation, 0, 0.6) or 0.2
			look = flatDir * math.cos(tilt) - Vector3.yAxis * math.sin(tilt)
		end
	end
	if look and look.Magnitude > 0.01 then
		rec.ao.CFrame = CFrame.lookAt(root.Position, root.Position + look)
	end
end

local function step(rec, dt)
	local fighter, humanoid, root, lv = rec.fighter, rec.humanoid, rec.root, rec.lv
	if humanoid.Health <= 0 or not root.Parent or not lv.Parent then
		finish(rec, true)
		return
	end
	-- a forced state took the body (a hit, a clash): it is that state's now
	if fighter:GetAttribute("CurrentState") ~= rec.state then
		finish(rec, true)
		return
	end
	local now = os.clock()
	if now - rec.started > cfg("MaxMoveTime", 6) then
		finish(rec, false)
		return
	end
	if rec.redash and now >= rec.redash.at then
		local target = rec.redash.target
		rec.redash = nil
		Momentum.dash(fighter, target)
	end

	local velocity
	if rec.kind == "dash" then
		local aim, tRoot = aimAt(rec)
		if not aim then
			setBallistic(rec, lv.VectorVelocity * 0.4)
		elseif tRoot and (tRoot.Position - root.Position).Magnitude <= cfg("ContactDistance", 7) + rec.speed * dt then
			-- (caught a frame early and set down just in front of it: at dash speed it would be
			-- inside the other body next frame, and the physics threw them apart - 37 studs in a frame)
			local gap = tRoot.Position - root.Position
			if gap.Magnitude > cfg("ContactDistance", 7) then
				local at = tRoot.Position - gap.Unit * cfg("ContactDistance", 7)
				root.CFrame = root.CFrame.Rotation + at
			end
			contact(rec, rec.target)
			return
		elseif now - rec.phaseAt > cfg("DashMaxTime", 1.2) then
			setBallistic(rec, lv.VectorVelocity * 0.4)
		else
			local offset = aim - root.Position
			if not tRoot and offset.Magnitude <= rec.speed * dt * 1.5 then
				setBallistic(rec, offset.Unit * rec.speed * 0.3)
			else
				lv.MaxAxesForce = FULL_FORCE
				lv.VectorVelocity = containVelocity(root.Position, unitOr(offset, root.CFrame.LookVector) * rec.speed)
			end
		end
	end
	velocity = rec.kind == "dash" and lv.VectorVelocity or root.AssemblyLinearVelocity
	if rec.kind ~= "dash" then
		root.AssemblyLinearVelocity = containVelocity(root.Position, velocity)
	end

	-- a wall ahead: bounce off it
	if velocity.Magnitude > 20 and rec.bounces < cfg("BounceMax", 2) then
		local hit = Workspace:Raycast(root.Position, velocity * dt * 2 + velocity.Unit * 3, rec.params)
		if hit and math.abs(hit.Normal.Y) < 0.5 then
			bounce(rec, velocity, hit.Normal, hit.Position)
			return
		end
	end

	face(rec, velocity)

	-- touchdown (the projectile jump's set-down snap): once the floor is within the next frame's
	-- travel, the body is placed on it on its feet
	local airTime = now - (rec.phaseAt or rec.started)
	local falling = velocity.Y < 0 and (rec.kind ~= "dash" or velocity.Unit.Y < -0.2)
	if falling and airTime > 0.08 then
		local offset = standOffset(humanoid, root)
		local feet = root.Position - Vector3.new(0, offset, 0)
		local hit = Workspace:Raycast(feet, velocity * dt * 1.5, rec.params)
		local standPos
		if hit and hit.Normal.Y > 0.5 then
			standPos = hit.Position + Vector3.new(0, offset, 0)
		else
			local gap = heightAboveStand(rec)
			if gap <= math.max(-velocity.Y * dt * 1.5, 1.0) then
				standPos = root.Position - Vector3.new(0, gap, 0)
			end
		end
		if standPos then
			land(rec, velocity, standPos)
		end
	end
end

function Momentum.start()
	if Momentum.started then return end
	Momentum.started = true
	RunService.Heartbeat:Connect(function(dt)
		for _, rec in pairs(moves) do
			local ok, err = pcall(step, rec, dt)
			if not ok then
				warn("[Momentum] " .. tostring(err))
				finish(rec, false)
			end
		end
	end)
	if RunService:IsStudio() then
		Momentum.startDevCommand()
	end
end

-- ============================================================
-- Studio test command: Workspace attribute MomentumDevCommand
--   "leap <Quin> [distance] [apex]"  leap ahead
--   "hop <Quin>"                      a running hop
--   "dash <Quin> <Target>"            dash at a Quin
--   "demo [<A> <B>]"                  the moves strung together for the eye (not the brain:
--                                     step 2 decides for real); no names: two fighting enemies
--                                     are picked and set apart in the middle
-- ============================================================

local function quin(name)
	local folder = Workspace:FindFirstChild("QuinServer")
	return folder and name and folder:FindFirstChild(name)
end

local function waitUntil(fn, timeout)
	local t0 = os.clock()
	while not fn() and os.clock() - t0 < timeout do
		RunService.Heartbeat:Wait()
	end
end

local function towardSpot(fighter, from, to, distance, sideways)
	local dir = unitOr(flat(to - from), Vector3.zAxis)
	local side = Vector3.new(-dir.Z, 0, dir.X) * sideways
	return groundBelow(fighter, from + dir * distance + side) or from
end

local function demo(a, b)
	for round = 1, cfg("DemoRounds", 3) do
		local first, second = a, b
		if round % 2 == 0 then first, second = b, a end
		local _, r1 = bodyOf(first)
		local _, r2 = bodyOf(second)
		if not (r1 and r2) then return end
		-- the first leaps high toward the other (off to a side)
		local gap = flat(r2.Position - r1.Position).Magnitude
		Momentum.leap(first, towardSpot(first, r1.Position, r2.Position, gap * 0.7, math.random(-40, 40)), math.random(50, 90))
		task.wait(math.random(25, 55) / 100)
		local roll = math.random()
		if roll < 0.5 then
			-- the other goes up after it; at the top, the first dashes at it
			Momentum.leap(second, towardSpot(second, r2.Position, r1.Position, gap * 0.4, math.random(-30, 30)), math.random(30, 60))
			waitUntil(function() return r1.AssemblyLinearVelocity.Y < 0 end, 1.5)
			Momentum.dash(first, second)
		elseif roll < 0.8 then
			-- the one in the air dashes down at the one on the ground; it dashes first to meet it
			waitUntil(function() return r1.AssemblyLinearVelocity.Y < 0 end, 1.5)
			Momentum.dash(first, second)
			task.wait(0.08)
			Momentum.dash(second, first)
		else
			-- the one on the ground runs on and hops; the one in the air dashes at it
			Momentum.hop(second, 8)
			waitUntil(function() return r1.AssemblyLinearVelocity.Y < 0 end, 1.5)
			Momentum.dash(first, second)
		end
		waitUntil(function() return not moves[a] and not moves[b] end, 6)
		task.wait(0.6)
	end
end

function Momentum.startDevCommand()
	Workspace:GetAttributeChangedSignal("MomentumDevCommand"):Connect(function()
		local cmd = Workspace:GetAttribute("MomentumDevCommand")
		if cmd == nil or cmd == "" then return end
		Workspace:SetAttribute("MomentumDevCommand", nil)
		if not Momentum.enabled() then
			warn("[Momentum] off (CombatConfig.Momentum.Enabled)")
			return
		end
		local words = string.split(cmd, " ")
		local what, a, b = words[1], quin(words[2]), quin(words[3])
		if what == "demo" and not a then
			-- (no names: two enemies that are fighting, set 160 studs apart in the middle)
			for _, q in ipairs(Workspace.QuinServer:GetChildren()) do
				local h = q:FindFirstChildOfClass("Humanoid")
				local s = q:GetAttribute("CurrentState")
				if h and h.Health > 0 and not q:GetAttribute("PilotedBy") and (s == "Fight" or s == "Chase" or s == "Circling") then
					if not a then a = q elseif q:GetAttribute("Team") ~= a:GetAttribute("Team") and not b then b = q end
				end
			end
			if a and b then
				local c = SpatialModule.getArenaBounds().center
				a.HumanoidRootPart.CFrame = CFrame.new(c + Vector3.new(-80, 15, 0))
				b.HumanoidRootPart.CFrame = CFrame.new(c + Vector3.new(80, 15, 0))
				Workspace:SetAttribute("MomentumDemoPair", a.Name .. " vs " .. b.Name)
				task.wait(0.8)
			end
		end
		if not a then
			warn("[Momentum] no Quin " .. tostring(words[2]))
			return
		end
		local _, root = bodyOf(a)
		if not root then return end
		if what == "leap" then
			local distance, apex = tonumber(words[3]) or 120, tonumber(words[4]) or 60
			local spot = groundBelow(a, root.Position + unitOr(flat(root.CFrame.LookVector), Vector3.zAxis) * distance)
			if spot then Momentum.leap(a, spot, apex) end
		elseif what == "hop" then
			Momentum.hop(a)
		elseif what == "dash" and b then
			Momentum.dash(a, b)
		elseif what == "demo" and b then
			task.spawn(demo, a, b)
		end
	end)
end

return Momentum
