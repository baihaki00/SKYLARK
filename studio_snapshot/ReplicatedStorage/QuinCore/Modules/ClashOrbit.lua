--// ClashOrbit.lua
-- The mid-air clash as a fast crossing fight across the arena (the owner's "Combat Gods 2" brief
-- and top-view drawing, 2026-10-27). Two styles (MidAirClash_OrbitLeapChance picks):
--
-- DOGFIGHT (main): no shared centre. Each Quin flies its own wild curve and the curves keep
-- crossing; every crossing is a hit, they are pushed a little off each other's line and fly on,
-- rise and loop out and dive back into the next crossing somewhere else over the arena. The
-- speed along a curve follows gravity (slowest at the top of a loop, fastest diving) plus the
-- hit's push fading out of each crossing; both reach the crossing at the same instant. The body
-- noses along its flight, leans into its turns by what it feels (the flight's pull against
-- gravity), reels back from a hit or backflips, and faces the other in and out of a hit.
--
-- LEAP: every flight is a ballistic arc under (anime-heavy) gravity, fastest at the launch and
-- the drop and slowest at the top, and a body changes direction only when something pushes it:
-- the other Quin or a surface. One cycle:
--   1. the hit (mid-air): they strike and blow each other apart
--   2. each arcs away on its own line (its own distance and height) and plants on the ground
--      or a tree top, at different times
--   3. never both kicking off at once: one leaps and the other goes up after it and cuts it
--      off mid-flight (maybe running at it first), or one pounces on the other, who springs up
--      short to meet it -> the next hit
-- A hit may start a rapid brawl: a few quick exchanges on one shared arc (pushed apart and
-- lunging back, circling a little), then they blow apart. After 1-10 hits (never longer than
-- MaxTime) MidAirClashState resolves the clash (tie or smash) where they last met.
-- The owner's numbers: cadence -> flight time (TimeScale), max radius -> how far a hit blows
-- them (StudsPerUnit studs a unit), ease snappiness -> how heavy the gravity is, precession ->
-- the axis the next crossing is set off on.
-- The body follows its flight: blown back leaning away (sometimes a backflip), upright and
-- facing on a plant, nose along the arc on the way in, face to face at a hit. The client's body
-- layers loosen the arms and legs from the flight's real jolts (ClashOrbit.motion).
--
-- Smoothness: server-driven bodies reach the players' screens in uneven steps, and a fast flight
-- then stutters. So the path is a deterministic simulation (Sim: one seed, fixed 60 Hz steps,
-- only the arena in its raycasts) that the server and every client run alike. The server
-- anchors both bodies, steps the path for the real positions, hits, damage and the end, and
-- publishes the seed and start (attributes on the leader); each client (ClashOrbit.startClient,
-- from a LocalScript) runs the same path and draws both bodies from it every frame.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")

local QuinCore = ReplicatedStorage:WaitForChild("QuinCore")
local CombatConfig = require(QuinCore:WaitForChild("CombatConfig"))
local Modules = QuinCore:WaitForChild("Modules")
local SpatialModule = require(Modules:WaitForChild("SpatialModule"))

local ClashOrbit = {}

-- (client) server model -> { vel, acc, air } of its body on the path this frame, for the body layers
ClashOrbit.motion = setmetatable({}, { __mode = "k" })

local STEP = 1 / 60

local function cfg(key, default)
	local v = CombatConfig["MidAirClash_Orbit" .. key]
	if v == nil then return default end
	return v
end

-- ============================================================
-- The path (the same on the server and on every client)
-- ============================================================

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Include
rayParams.RespectCanCollide = true

local function arenaRoot()
	return Workspace:FindFirstChild("argoniaonion")
end

local function cast(from, dir)
	local root = arenaRoot()
	if not root then return nil end
	rayParams.FilterDescendantsInstances = { root }
	return Workspace:Raycast(from, dir, rayParams)
end

-- the height of whatever is under a point (the ground, or the top of an obstacle). Only the
-- arena is looked at: effects and bodies differ between server and clients.
local function surfaceBelow(p)
	local hit = cast(Vector3.new(p.X, p.Y + 80, p.Z), Vector3.new(0, -500, 0))
	return hit and hit.Position.Y or nil
end

local function rotY(v, a)
	local c, s = math.cos(a), math.sin(a)
	return Vector3.new(v.X * c + v.Z * s, v.Y, -v.X * s + v.Z * c)
end

local function flat(v)
	return Vector3.new(v.X, 0, v.Z)
end

local function unitOr(v, fallback)
	return v.Magnitude > 1e-6 and v.Unit or fallback
end

local Sim = {}
Sim.__index = Sim

-- seed: integer; center, lStart, fStart: where the clash and the two bodies are at the start;
-- standH: how high a standing body's root is over its feet
function ClashOrbit.newLeap(seed, center, lStart, fStart, standH)
	local rng = Random.new(seed)
	local self = setmetatable({}, Sim)
	self.rng = rng
	self.unit = cfg("StudsPerUnit", 12)
	self.timeScale = cfg("TimeScale", 0.6)
	self.cycleLimit = rng:NextInteger(cfg("CyclesMin", 1), cfg("CyclesMax", 10))
	self.maxTime = rng:NextNumber(cfg("MaxTimeMin", 1), cfg("LeapMaxTime", 2)) -- (owner: 1-2 s, it was too long)
	self.bodyGap = cfg("BodyGap", 1.9)
	self.clearance = cfg("Clearance", 5)
	self.brawlChance = cfg("BrawlChance", 0.35)
	self.standH = standH or 5
	self.bounds = SpatialModule.getArenaBounds()
	self.groundY = surfaceBelow(center) or (center.Y - 30)
	self.axis = unitOr(Vector3.new(rng:NextNumber(-1, 1), 0, rng:NextNumber(-1, 1)), Vector3.xAxis)

	self.time = 0
	self.cycles, self.contacts = 0, 0
	self.events = {}
	self.done = false
	local apart = unitOr(flat(lStart - fStart), Vector3.xAxis)
	local function body(p, look)
		local rot = CFrame.lookAt(Vector3.zero, look).Rotation
		return { pos = p, last = p, vel = Vector3.zero, acc = Vector3.zero, rot = rot, lastRot = rot, base = rot, segs = {} }
	end
	self.L = body(lStart, -apart)
	self.F = body(fStart, apart)
	self.L.other, self.F.other = self.F, self.L
	self.center = (lStart + fStart) / 2
	-- the clash itself is the first hit: they blow apart from it
	self:afterHit(0, lStart, fStart, false)
	return self
end

function Sim:inArena(p, share)
	local b = self.bounds
	local rx, rz = b.halfX * share, b.halfZ * share
	return Vector3.new(math.clamp(p.X, b.center.X - rx, b.center.X + rx), p.Y, math.clamp(p.Z, b.center.Z - rz, b.center.Z + rz))
end

-- one flight's time and gravity for this cycle (the owner's cadence and snappiness)
function Sim:flightTime()
	local bpm = self.rng:NextNumber(cfg("BpmMin", 100), cfg("BpmMax", 140))
	return 60 / bpm * self.timeScale * self.rng:NextNumber(0.85, 1.15)
end

function Sim:gravity()
	local ease = self.rng:NextNumber(cfg("EaseMin", 1), cfg("EaseMax", 7))
	local lo, hi = cfg("GravityMin", 2), cfg("GravityMax", 3.5)
	local share = (ease - cfg("EaseMin", 1)) / math.max(cfg("EaseMax", 7) - cfg("EaseMin", 1), 0.01)
	return Workspace.Gravity * (lo + (hi - lo) * share)
end

local function arcAt(seg, tau)
	return seg.p0 + seg.v0 * tau + Vector3.new(0, -0.5 * seg.g * tau * tau, 0)
end

-- an arc from p0 to p1 in time T under gravity g; nil if it would go through the arena
local function arcSeg(p0, p1, T, g)
	return { kind = "air", p0 = p0, v0 = (p1 - p0) / T + Vector3.new(0, 0.5 * g * T, 0), g = g, T = T, p1 = p1 }
end

local function makeArc(p0, p1, T, g)
	local seg = arcSeg(p0, p1, T, g)
	local prev = p0
	for k = 1, 8 do
		local p = arcAt(seg, T * k / 8)
		local hit = cast(prev, p - prev)
		-- (the end of an arc onto a surface touches it: only a hit before the last stretch counts)
		if hit and k < 8 then return nil end
		prev = p
	end
	return seg
end

local function push(body, seg)
	table.insert(body.segs, seg)
end

-- an arc's time from p0 to p1 when it tops out apex studs over its higher end
local function apexTime(p0, p1, apex, g)
	local topY = math.max(p0.Y, p1.Y) + math.max(apex, 0.5)
	return math.sqrt(2 * (topY - p0.Y) / g) + math.sqrt(2 * (topY - p1.Y) / g)
end

-- standing on whatever is under p (nil: nothing there)
function Sim:groundAt(p)
	local top = surfaceBelow(Vector3.new(p.X, self.groundY + 150, p.Z))
	return top and Vector3.new(p.X, top + self.standH, p.Z) or nil
end

-- a run from a to b is blocked by something in the way at knee height, or a step too high
function Sim:runBlocked(a, b)
	if math.abs(a.Y - b.Y) > 6 then return true end
	local knee = Vector3.new(0, 1.5 - self.standH, 0)
	return cast(a + knee, (b + knee) - (a + knee)) ~= nil
end

-- After a hit at time t (bodies at pL, pF): each is blown away on its own arc (its own distance
-- and height, so they come down at different times) and plants; then the next crossing (an
-- interception or a pounce, below). (Or a rapid brawl first.)
function Sim:afterHit(t, pL, pF, brawl)
	local rng = self.rng
	if brawl then
		t, pL, pF = self:brawl(t, pL, pF)
	end
	local g = self:gravity()
	local scale = cfg("LeapScale", 1.5)
	local bodies = { self.L, self.F }
	local who = { "L", "F" }
	local ready, lands, plants = {}, {}, {}
	for i, b in ipairs({ { pL, pF }, { pF, pL } }) do
		local body, from, other = bodies[i], b[1], b[2]
		local away = unitOr(flat(from - other), rotY(self.axis, i == 1 and 0 or math.pi))
		local dist = rng:NextNumber(cfg("MaxRadiusLow", 5), cfg("MaxRadius", 9)) * self.unit * scale * rng:NextNumber(0.6, 1.2)
		local apex = rng:NextNumber(cfg("LeapApexMin", 15), cfg("LeapApexMax", 80))
		local seg, land, T
		for try = 1, 6 do
			local dir = rotY(away, math.rad(rng:NextNumber(-50, 50)) * (1 + try * 0.3))
			local spot = self:inArena(from + dir * dist * (1 - try * 0.08), cfg("ArenaShare", 0.85))
			land = self:groundAt(spot) or Vector3.new(spot.X, self.groundY + self.standH, spot.Z)
			T = apexTime(from, land, apex, g)
			seg = makeArc(from, land, T, g)
			if seg then break end
		end
		seg = seg or arcSeg(from, land, T, g)
		seg.t0, seg.role = t, "away"
		-- sometimes a backflip on the way out
		seg.flip = rng:NextNumber() < cfg("FlipChance", 0.4) and math.pi * 2 or 0
		seg.roll = math.rad(rng:NextNumber(-20, 20))
		push(body, seg)
		local plantT = rng:NextNumber(cfg("PlantMin", 0.05), cfg("PlantMax", 0.25))
		plants[i] = { kind = "plant", t0 = t + T, T = plantT, p0 = land }
		ready[i] = t + T + plantT
		lands[i] = land
	end

	-- the next crossing. Never both off the ground at once:
	--   interception: one leaps (high, its own way) and the other goes up after it and cuts it
	--   off mid-flight, maybe running at it first; or
	--   pounce: the one down first waits crouched, the other leaps onto it, and it springs up
	--   short to meet it at the last instant
	local inMin, inMax = cfg("LeapInApexMin", 10), cfg("LeapInApexMax", 60)
	local stagger = cfg("LeapStagger", 0.3)
	local first = ready[1] <= ready[2] and 1 or 2
	local kicks, starts, goals, Tin, arcs, runs = {}, { lands[1], lands[2] }, {}, {}, {}, {}
	local tMeet
	if rng:NextNumber() < cfg("LeapPounceChance", 0.25) then
		local w, p = first, 3 - first
		local meet = lands[w] + Vector3.new(0, rng:NextNumber(4, 10), 0)
		local toP = unitOr(flat(lands[p] - lands[w]), self.axis)
		goals[w], goals[p] = meet - toP * self.bodyGap, meet + toP * self.bodyGap
		Tin[p] = apexTime(lands[p], goals[p], rng:NextNumber(inMin, inMax), g)
		Tin[w] = apexTime(lands[w], goals[w], rng:NextNumber(1, 3), g)
		kicks[p] = ready[p] + rng:NextNumber(0, cfg("LeapWaitMax", 0.4))
		tMeet = math.max(kicks[p] + Tin[p], ready[w] + Tin[w] + stagger)
		kicks[p] = tMeet - Tin[p]
		kicks[w] = tMeet - Tin[w]
	else
		-- the jumper: more often the one down first
		local j = rng:NextNumber() < 0.6 and first or 3 - first
		local i = 3 - j
		local toI = unitOr(flat(lands[i] - lands[j]), self.axis)
		local dist = rng:NextNumber(cfg("MaxRadiusLow", 5), cfg("MaxRadius", 9)) * self.unit * cfg("LeapScale", 1.5) * rng:NextNumber(0.6, 1.2)
		local segJ, TJ, u
		for try = 1, 6 do
			local dir = rotY(toI, math.rad(rng:NextNumber(-70, 70)))
			local spot = self:inArena(lands[j] + dir * dist * (1 - try * 0.1), cfg("ArenaShare", 0.85))
			local land = self:groundAt(spot) or Vector3.new(spot.X, self.groundY + self.standH, spot.Z)
			TJ = apexTime(lands[j], land, rng:NextNumber(inMin, inMax) * 1.3, g)
			segJ = makeArc(lands[j], land, TJ, g) or (try == 6 and arcSeg(lands[j], land, TJ, g))
			if segJ then
				-- where on its flight it is cut off: up in the air, clear of what is under it
				u = rng:NextNumber(0.4, 0.8)
				local m = arcAt(segJ, u * TJ)
				local top = surfaceBelow(m) or self.groundY
				if m.Y > top + self.clearance + self.standH + 8 or try == 6 then break end
				segJ = nil
			end
		end
		kicks[j] = ready[j] + rng:NextNumber(0, cfg("LeapWaitMax", 0.4))
		local meetJ = arcAt(segJ, u * TJ)
		local fromI = unitOr(flat(lands[i] - meetJ), toI)
		goals[j], goals[i] = meetJ, meetJ + fromI * self.bodyGap * 2
		-- the interceptor goes up fast and steep
		Tin[j] = u * TJ
		Tin[i] = apexTime(lands[i], goals[i], rng:NextNumber(3, 15), g)
		-- (never kicking off together: after the jumper, or before it when its cut-off comes quick)
		if Tin[i] > Tin[j] - stagger then
			Tin[i] = Tin[j] - stagger >= 0.25 and Tin[j] - stagger or Tin[j] + stagger
		end
		-- (the interceptor needs its own time down first: the jumper holds a moment longer)
		kicks[j] = math.max(kicks[j], ready[i] + Tin[i] + 0.1 - Tin[j])
		tMeet = kicks[j] + Tin[j]
		kicks[i] = tMeet - Tin[i]
		arcs[j] = segJ
		arcs[j].faceAt = math.max(u - 0.15, 0)
		-- with time to spare it runs at the other first, to get under it
		local spare = kicks[i] - ready[i]
		if spare > 0.3 and rng:NextNumber() < cfg("LeapRunChance", 0.5) then
			local toward = flat(goals[i] - lands[i])
			local runDist = math.min(spare * cfg("LeapRunSpeed", 140) * 0.7, toward.Magnitude * 0.7)
			local runEnd = runDist > 12 and self:groundAt(lands[i] + unitOr(toward, toI) * runDist)
			if runEnd and not self:runBlocked(lands[i], runEnd) then
				local tin = math.min(apexTime(runEnd, goals[i], rng:NextNumber(3, 15), g), Tin[i])
				local runT = tMeet - tin - ready[i]
				if runT > 0.1 and math.abs(Tin[j] - tin) >= stagger then
					runs[i] = { kind = "run", t0 = ready[i], T = runT, p0 = lands[i], p1 = runEnd }
					starts[i], Tin[i], kicks[i] = runEnd, tin, ready[i] + runT
				end
			end
		end
	end

	for i = 1, 2 do
		local seg = arcs[i] or makeArc(starts[i], goals[i], Tin[i], g) or arcSeg(starts[i], goals[i], Tin[i], g)
		seg.t0, seg.role, seg.flip, seg.roll = kicks[i], "in", 0, math.rad(rng:NextNumber(-25, 25))
		if not runs[i] then
			plants[i].T = kicks[i] - plants[i].t0
		end
		push(bodies[i], plants[i])
		self:event(plants[i].t0, "plant", who[i], nil, plants[i].T)
		if runs[i] then
			push(bodies[i], runs[i])
			self:event(runs[i].t0, "run", who[i])
		end
		push(bodies[i], seg)
		self:event(kicks[i], "launch", who[i])
	end
	self:event(tMeet, "hit")
	-- the owner's precession: the next crossing is set off on a turned axis
	self.axis = rotY(self.axis, math.rad(rng:NextNumber(cfg("ShiftMin", 10), cfg("ShiftMax", 120))) * (rng:NextNumber() < 0.5 and -1 or 1))
end

-- A rapid brawl from time t: a few quick exchanges on one shared arc; returns where it ends
function Sim:brawl(t, pL, pF)
	local rng = self.rng
	local n = rng:NextInteger(cfg("BrawlCyclesMin", 2), cfg("BrawlCyclesMax", 4))
	local Tb = 60 / cfg("BrawlBpm", 140) * self.timeScale * 1.4
	local total = n * Tb
	local g = Workspace.Gravity * cfg("GravityMin", 2)
	local c0 = (pL + pF) / 2
	local floor = surfaceBelow(c0) or self.groundY
	local drift = rotY(self.axis, rng:NextNumber(-1, 1)) * rng:NextNumber(30, 80)
	-- (rises and comes back to about its height: never into the ground)
	local lift = 0.5 * g * total + math.max(0, floor + self.clearance + self.standH + 4 - c0.Y) / total
	local seg = {
		kind = "brawl", t0 = t, T = total, c0 = c0, v0 = drift + Vector3.new(0, lift, 0), g = g, Tb = Tb,
		axis0 = unitOr(pL - pF, Vector3.xAxis), turn = math.rad(rng:NextNumber(40, 90)) * (rng:NextNumber() < 0.5 and -1 or 1),
		gapMax = rng:NextNumber(cfg("BrawlMaxRadiusLow", 1.5), cfg("BrawlMaxRadius", 3.0)) * 2,
	}
	local segL, segF = table.clone(seg), table.clone(seg)
	segL.side, segF.side = 1, -1
	push(self.L, segL)
	push(self.F, segF)
	for i = 1, n do
		self:event(t + i * Tb, "hit", nil, true)
	end
	local endL = self:brawlAt(segL, total)
	local endF = self:brawlAt(segF, total)
	-- (the brawl's own hits are counted as they come; the last one is where they blow apart)
	self.brawlUntil = t + total
	return t + total, endL, endF
end

function Sim:brawlAt(seg, tau)
	local c = seg.c0 + seg.v0 * tau + Vector3.new(0, -0.5 * seg.g * tau * tau, 0)
	local u = (tau % seg.Tb) / seg.Tb
	local gap = self.bodyGap + seg.gapMax * math.sin(math.pi * u)
	local axis = rotY(seg.axis0, seg.turn * tau / seg.Tb)
	return c + axis * gap * seg.side
end

function Sim:event(t, kind, who, brawl, dur)
	table.insert(self.events, { t = t, kind = kind, who = who, brawl = brawl, dur = dur })
	table.sort(self.events, function(a, b) return a.t < b.t end)
end

local function segAt(body, t)
	local segs = body.segs
	while #segs > 1 and t >= segs[2].t0 do
		table.remove(segs, 1)
	end
	return segs[1]
end

-- Where a body is at time t, and how it is turned (unsmoothed)
function Sim:pose(body, t)
	local seg = segAt(body, t)
	if not seg then return body.pos, body.base, false, 0 end
	body.gNow = (seg.kind == "air" or seg.kind == "brawl") and seg.g or 0 -- (the gravity it falls with: the body layers take it out)
	local tau = math.clamp(t - seg.t0, 0, seg.T)
	local other = body.other
	local toOther = unitOr(flat(other.pos - body.pos), body.base.LookVector)
	if seg.kind == "plant" then
		return seg.p0, CFrame.lookAt(Vector3.zero, toOther).Rotation, false, 0
	elseif seg.kind == "run" then
		-- sprinting into the jump (picking up speed), on whatever ground is under it
		local s = tau / seg.T
		local q = seg.p0:Lerp(seg.p1, s * (0.6 + 0.4 * s))
		local hit = cast(q + Vector3.new(0, 8, 0), Vector3.new(0, -8 - self.standH * 2, 0))
		if hit then q = Vector3.new(q.X, hit.Position.Y + self.standH, q.Z) end
		local run = unitOr(flat(seg.p1 - seg.p0), toOther)
		return q, CFrame.lookAt(Vector3.zero, run).Rotation * CFrame.Angles(math.rad(-12), 0, 0), false, 0
	elseif seg.kind == "brawl" then
		local p = self:brawlAt(seg, tau)
		local look = unitOr(other.pos - body.pos, toOther)
		return p, CFrame.lookAt(Vector3.zero, look).Rotation, true, 0
	end
	local p = arcAt(seg, tau)
	local vel = seg.v0 + Vector3.new(0, -seg.g * tau, 0)
	local share = tau / seg.T
	local rot
	if seg.role == "away" then
		-- blown back: facing the other, leaning away, and maybe a backflip
		local lean = math.rad(math.clamp(vel.Magnitude / 400, 0, 1) * 35)
		local s = share * share * (3 - 2 * share)
		rot = CFrame.lookAt(Vector3.zero, toOther).Rotation * CFrame.Angles(lean + seg.flip * s, 0, seg.roll * math.sin(math.pi * share))
	else
		-- on the way in: nose along the arc, turning onto the other for the hit
		local along = unitOr(vel, toOther)
		local pitch = math.asin(math.clamp(along.Y, -0.85, 0.85))
		local face = share > (seg.faceAt or 0.8) and unitOr(other.pos - body.pos, along) or unitOr(flat(along), toOther) * math.cos(pitch) + Vector3.new(0, along.Y, 0)
		rot = CFrame.lookAt(Vector3.zero, unitOr(face, along)).Rotation * CFrame.Angles(0, 0, seg.roll * math.sin(math.pi * share))
	end
	return p, rot, true, seg.flip ~= 0 and seg.role == "away" and share < 1 and 1 or 0
end

-- last safety only: in the arena and over the surface
function Sim:safe(p, air)
	p = self:inArena(p, 0.96)
	if air then
		local floor = surfaceBelow(p)
		if floor and p.Y < floor + self.standH * 0.6 then
			p = Vector3.new(p.X, floor + self.standH * 0.6, p.Z)
		end
	end
	return p
end

-- One fixed step. Returns the events that happened on it ({ kind = "hit"|"plant"|"launch", ... }).
function Sim:step()
	if self.done then return nil end
	self.time += STEP
	local t = self.time
	local fired
	while self.events[1] and self.events[1].t <= t do
		local e = table.remove(self.events, 1)
		fired = fired or {}
		table.insert(fired, e)
		if e.kind == "hit" then
			self.cycles += 1
			self.contacts += 1
			if self.cycles >= self.cycleLimit then
				self.done, self.reason = true, "cycles"
			elseif not e.brawl then
				-- what follows this hit: a rapid brawl first, or straight apart
				local brawl = self.rng:NextNumber() < self.brawlChance
				self:afterHit(e.t, self.L.pos, self.F.pos, brawl)
			elseif self.brawlUntil and e.t >= self.brawlUntil - 1e-6 then
				self.brawlUntil = nil
			end
		end
	end
	if self.time > self.maxTime and not self.done then
		self.done, self.reason = true, "time"
	end
	for _, body in ipairs({ self.L, self.F }) do
		local p, rot, air, flipping = self:pose(body, t)
		p = self:safe(p, air)
		body.last, body.lastRot = body.pos, body.rot
		local vel = (p - body.pos) / STEP
		body.acc = (vel - body.vel) / STEP
		body.vel = vel
		body.air = air
		body.pos = p
		-- turned smoothly; a flip is taken as is (smoothing would eat it)
		if flipping == 1 then
			body.base = rot
		else
			body.base = body.base:Lerp(rot, 1 - math.exp(-18 * STEP))
		end
		body.rot = body.base
	end
	self.lPos, self.fPos = self.L.pos, self.F.pos
	self.center = (self.L.pos + self.F.pos) / 2
	return fired
end

-- the two bodies' CFrames between the last two steps (alpha 0..1)
function Sim:frames(alpha)
	local function cf(b)
		return CFrame.new(b.last:Lerp(b.pos, alpha)) * b.lastRot:Lerp(b.rot, alpha)
	end
	return cf(self.L), cf(self.F)
end

-- ============================================================
-- The dogfight path
-- ============================================================

local Dog = {}
Dog.__index = Dog
Dog.frames = Sim.frames

local function hermite(p0, m0, p1, m1, s)
	local s2, s3 = s * s, s * s * s
	return p0 * (2 * s3 - 3 * s2 + 1) + m0 * (s3 - 2 * s2 + s) + p1 * (-2 * s3 + 3 * s2) + m1 * (s3 - s2)
end

function ClashOrbit.newDogfight(seed, center, lStart, fStart, standH)
	local rng = Random.new(seed)
	local self = setmetatable({}, Dog)
	self.rng = rng
	self.unit = cfg("StudsPerUnit", 12)
	self.timeScale = cfg("DogfightTimeScale", 0.75)
	self.cycleLimit = rng:NextInteger(cfg("CyclesMin", 1), cfg("CyclesMax", 10))
	self.maxTime = rng:NextNumber(cfg("MaxTimeMin", 1), cfg("MaxTime", 2)) -- (owner: 1-2 s, it was too long)
	self.bodyGap = cfg("BodyGap", 1.9)
	self.clearance = cfg("Clearance", 5)
	self.brawlChance = cfg("BrawlChance", 0.35)
	self.maxSpeed = cfg("DogfightMaxSpeed", 2500)
	self.floorGap = math.max(self.clearance, (standH or 5) + 1) -- (feet never in the ground when skimming low)
	self.g = Workspace.Gravity * cfg("DogfightGravity", 2.5)
	self.bounds = SpatialModule.getArenaBounds()
	self.groundY = surfaceBelow(center) or (center.Y - 30)
	self.axis = unitOr(Vector3.new(rng:NextNumber(-1, 1), 0, rng:NextNumber(-1, 1)), Vector3.xAxis)

	self.brawlLeft = 0
	self.time = 0
	self.cycles, self.contacts = 0, 0
	self.done = false
	local apart = unitOr(flat(lStart - fStart), Vector3.xAxis)
	local function body(p, look)
		local rot = CFrame.lookAt(Vector3.zero, look).Rotation
		return { pos = p, last = p, vel = Vector3.zero, acc = Vector3.zero, rot = rot, lastRot = rot, base = rot, air = true, gNow = 0 }
	end
	self.L = body(lStart, -apart)
	self.F = body(fStart, apart)
	self.L.other, self.F.other = self.F, self.L
	self.lPos, self.fPos = lStart, fStart
	self.center = (lStart + fStart) / 2
	-- the clash itself is the first hit: they fling apart from it, rising
	self:hitReaction(self.L, false)
	self:hitReaction(self.F, false)
	self:newLeg(lStart, fStart, unitOr(apart + self:rise(), apart), unitOr(-apart + self:rise(), -apart))
	return self
end

Dog.inArena = Sim.inArena

function Dog:rise()
	return Vector3.new(0, self.rng:NextNumber(cfg("DogfightRiseMin", 0.3), cfg("DogfightRiseMax", 0.8)), 0)
end

-- a hit's jolt on a body: mostly a snap back that recovers, sometimes a backflip
function Dog:hitReaction(body, brawl)
	local rng = self.rng
	body.spinT = 0
	if not brawl and rng:NextNumber() < cfg("DogfightFlipChance", 0.25) then
		body.spinKind, body.spinAmp = "flip", math.pi * 2
	else
		body.spinKind = "reel"
		body.spinAmp = math.rad(rng:NextNumber(cfg("DogfightReelMin", 25), cfg("DogfightReelMax", 55))) * (brawl and 0.5 or 1)
	end
	body.twist = math.rad(rng:NextNumber(-35, 35)) * (brawl and 0.5 or 1)
end

-- the jolt's pitch (back) and roll now
local function spinAngle(body)
	local t = body.spinT
	if not t then return 0, 0 end
	if body.spinKind == "flip" then
		local s = math.clamp(t / (body.spinLen or 0.4), 0, 1)
		return body.spinAmp * s * s * (3 - 2 * s), body.twist * math.sin(math.pi * s)
	end
	local tau = cfg("DogfightReelTime", 0.12)
	local k = (t / tau) * math.exp(1 - t / tau)
	return body.spinAmp * k, body.twist * k
end

-- A body's curve for one leg, timed by physics: along the curve the speed is what a body falling
-- under g would have (slowest at the top, fastest at the bottom), plus the hit's push fading out
-- of the start; then the whole leg is scaled to last T (so both arrive together). gEff is the
-- gravity that timing works out to (the body layers take it out of what the body feels).
function Dog:curve(p0, m0, p1, m1, T, easeShare)
	local N = 48
	local pts = table.create(N + 1)
	local top, low = -math.huge, math.huge
	for i = 0, N do
		local p = hermite(p0, m0, p1, m1, i / N)
		pts[i + 1] = p
		top = math.max(top, p.Y)
		low = math.min(low, p.Y)
	end
	local g = self.g
	local hi, lo = cfg("DogfightTopSpeedMax", 0.9), cfg("DogfightTopSpeedMin", 0.3)
	local vTop = math.sqrt(2 * g * math.max(top - low, 4)) * (hi + (lo - hi) * easeShare)
	local kick, kickLen = self.kick or cfg("DogfightKick", 0.8), cfg("DogfightKickLength", 0.15)
	local times = table.create(N + 1)
	times[1] = 0
	for i = 2, N + 1 do
		local a, b = pts[i - 1], pts[i]
		local u = (i - 1.5) / N
		local v = math.sqrt(vTop * vTop + 2 * g * math.max(top - (a.Y + b.Y) / 2, 0)) * (1 + kick * math.exp(-u / kickLen))
		times[i] = times[i - 1] + (b - a).Magnitude / v
	end
	local scale = T / math.max(times[N + 1], 1e-4)
	for i = 2, N + 1 do
		times[i] *= scale
	end
	return { p0 = p0, m0 = m0, p1 = p1, m1 = m1, times = times, N = N, i = 2, gEff = math.min(g / (scale * scale), Workspace.Gravity * 8) }
end

local function curveAt(c, tau)
	local times = c.times
	local i = c.i
	while i < #times and times[i] < tau do
		i += 1
	end
	c.i = i
	local t0, t1 = times[i - 1], times[i]
	local f = t1 > t0 and math.clamp((tau - t0) / (t1 - t0), 0, 1) or 1
	return hermite(c.p0, c.m0, c.p1, c.m1, (i - 2 + f) / c.N)
end

-- the next meeting: a point across the arena, each body's own curve to it from its own side
function Dog:newLeg(fromL, fromF, outL, outF)
	local rng, unit = self.rng, self.unit
	local brawl = self.brawlLeft > 0
	local bpm, ease, dist
	if brawl then
		bpm = cfg("BrawlBpm", 140)
		ease = rng:NextNumber(1, cfg("BrawlEaseMax", 2.5))
		dist = 2 * rng:NextNumber(cfg("BrawlMaxRadiusLow", 1.5), cfg("BrawlMaxRadius", 3.0)) * unit
	else
		bpm = rng:NextNumber(cfg("BpmMin", 100), cfg("BpmMax", 140))
		ease = rng:NextNumber(cfg("EaseMin", 1), cfg("EaseMax", 7))
		dist = 2 * rng:NextNumber(cfg("MaxRadiusLow", 5), cfg("MaxRadius", 9)) * unit * cfg("DogfightScale", 1.4)
	end
	-- (no two legs alike: some quick snaps, some long sweeps, the push out of the hit harder or softer)
	local tempo = rng:NextNumber(cfg("DogfightTempoMin", 0.75), cfg("DogfightTempoMax", 1.3))
	dist *= rng:NextNumber(0.7, 1.3) * math.sqrt(tempo)
	self.kick = cfg("DogfightKick", 0.8) * rng:NextNumber(0.5, 1.5)
	local easeShare = math.clamp((ease - cfg("EaseMin", 1)) / math.max(cfg("EaseMax", 7) - cfg("EaseMin", 1), 0.01), 0, 1)
	local mid = (fromL + fromF) / 2
	local heading = unitOr(self.axis + Vector3.new(rng:NextNumber(-1, 1), 0, rng:NextNumber(-1, 1)) * 0.6, self.axis)
	local p = self:inArena(mid + heading * dist, cfg("DogfightArenaShare", 0.7))
	-- (high enough over whatever is there)
	local top = surfaceBelow(Vector3.new(p.X, self.groundY + 150, p.Z)) or self.groundY
	for k = 0, 3 do
		local a = k * math.pi / 2
		local s = surfaceBelow(Vector3.new(p.X + math.cos(a) * 12, self.groundY + 150, p.Z + math.sin(a) * 12))
		if s and s > top then top = s end
	end
	p = Vector3.new(p.X, top + self.clearance + rng:NextNumber(cfg("DogfightAltitudeMin", 4), cfg("DogfightAltitudeMax", 130)), p.Z)

	-- they come in from different sides (the crossing), mostly diving, and touch without overlapping
	local approach = unitOr(Vector3.new(p.X - mid.X, 0, p.Z - mid.Z), heading)
	local cross = math.rad(rng:NextNumber(cfg("DogfightCrossMin", 70), cfg("DogfightCrossMax", 180)))
	local diveMin, diveMax = cfg("DogfightDiveMin", -0.6), cfg("DogfightDiveMax", 0.05)
	local inL = unitOr(rotY(approach, cross / 2) + Vector3.new(0, rng:NextNumber(diveMin, diveMax), 0), approach)
	local inF = unitOr(rotY(approach, -cross / 2) + Vector3.new(0, rng:NextNumber(diveMin, diveMax), 0), approach)
	local loopMin, loopMax = cfg("DogfightLoopMin", 0.8), cfg("DogfightLoopMax", 1.8)
	local T = 60 / bpm * self.timeScale * tempo
	local endL, endF = p - inL * self.bodyGap, p - inF * self.bodyGap
	self.leg = {
		T = T,
		t = 0,
		inL = inL, inF = inF,
		endL = endL, endF = endF,
		L = self:curve(fromL, outL * dist * rng:NextNumber(loopMin, loopMax), endL, inL * dist * rng:NextNumber(loopMin, loopMax), T, easeShare),
		F = self:curve(fromF, outF * dist * rng:NextNumber(loopMin, loopMax), endF, inF * dist * rng:NextNumber(loopMin, loopMax), T, easeShare),
	}
	local flipLen = math.min(cfg("DogfightFlipTime", 0.4), T * 0.7)
	self.L.spinLen, self.F.spinLen = flipLen, flipLen
	-- the owner's precession: the axis of the next meeting turns
	self.axis = rotY(self.axis, math.rad(rng:NextNumber(cfg("ShiftMin", 10), cfg("ShiftMax", 120))) * (rng:NextNumber() < 0.5 and -1 or 1))
end

-- last safety only: in the arena, over the surface, under the speed cap
function Dog:place(want, prev)
	want = self:inArena(want, 0.96)
	local floor = surfaceBelow(want)
	if floor and want.Y < floor + self.floorGap then
		want = Vector3.new(want.X, floor + self.floorGap, want.Z)
	end
	local step = want - prev
	local most = self.maxSpeed * STEP
	if step.Magnitude > most then
		want = prev + step.Unit * most
	end
	return want
end

-- how the body is turned: nose along its flight (never straight up or down), turned onto the
-- other near a hit, leaning into the turn by what it feels (its pull against gravity)
local function orient(vel, acc, g, toOther, facing, prev)
	local dir = unitOr(vel, prev.LookVector)
	if facing > 0 then
		dir = unitOr(dir:Lerp(toOther, facing), dir)
	end
	local maxPitch = math.rad(cfg("DogfightMaxPitch", 55))
	local pitch = math.clamp(math.asin(math.clamp(dir.Y, -1, 1)), -maxPitch, maxPitch)
	local flatDir = unitOr(flat(dir), unitOr(flat(prev.LookVector), Vector3.zAxis))
	local fwd = flatDir * math.cos(pitch) + Vector3.new(0, math.sin(pitch), 0)
	local feel = acc * cfg("DogfightLean", 0.6) + Vector3.new(0, g, 0)
	local upright = unitOr(Vector3.yAxis - fwd * fwd.Y, Vector3.yAxis)
	local up = unitOr(feel - fwd * feel:Dot(fwd), upright)
	local bankMax = math.rad(cfg("DogfightBankMax", 70))
	local a = math.acos(math.clamp(up:Dot(upright), -1, 1))
	if a > bankMax then
		up = unitOr(upright:Lerp(up, bankMax / a), upright)
	end
	return CFrame.fromMatrix(Vector3.zero, fwd:Cross(up), up)
end

-- One fixed step. Returns the events that happened on it ({ kind = "hit", brawl = ... }).
function Dog:step()
	if self.done then return nil end
	self.time += STEP
	if self.time > self.maxTime then
		self.done, self.reason = true, "time"
		return nil
	end
	local leg = self.leg
	leg.t += STEP
	local fired
	if leg.t >= leg.T then
		-- they meet: the hit, then each is pushed off the other's line and rises on
		local over = leg.t - leg.T
		local atL, atF = leg.endL, leg.endF
		local brawl = self.brawlLeft > 0
		self.cycles += 1
		self.contacts += 1
		fired = { { kind = "hit", brawl = brawl } }
		if self.cycles >= self.cycleLimit and self.brawlLeft <= 1 then
			for _, pair in ipairs({ { self.L, atL }, { self.F, atF } }) do
				local body = pair[1]
				body.last, body.lastRot = body.pos, body.rot
				body.pos = pair[2]
			end
			self.lPos, self.fPos = atL, atF
			self.done, self.reason = true, "cycles"
			return fired
		end
		if self.brawlLeft > 0 then
			self.brawlLeft -= 1
		elseif self.rng:NextNumber() < self.brawlChance then
			self.brawlLeft = self.rng:NextInteger(cfg("BrawlCyclesMin", 2), cfg("BrawlCyclesMax", 4))
		end
		local n = unitOr(atL - atF, -leg.inL)
		local pushMin, pushMax = cfg("DogfightPushMin", 0.4), cfg("DogfightPushMax", 0.9)
		local outL = unitOr(flat(leg.inL) + n * self.rng:NextNumber(pushMin, pushMax) + self:rise(), leg.inL)
		local outF = unitOr(flat(leg.inF) - n * self.rng:NextNumber(pushMin, pushMax) + self:rise(), leg.inF)
		self:hitReaction(self.L, brawl)
		self:hitReaction(self.F, brawl)
		self:newLeg(atL, atF, outL, outF)
		leg = self.leg
		leg.t = over
	end

	local tau = math.min(leg.t, leg.T)
	local share = tau / leg.T
	for _, key in ipairs({ "L", "F" }) do
		local body = self[key]
		local c = leg[key]
		local p = self:place(curveAt(c, tau), body.pos)
		local vel = (p - body.pos) / STEP
		-- (what it feels, a little smoothed: the curve is timed in small pieces)
		body.acc = body.acc:Lerp((vel - body.vel) / STEP, 1 - math.exp(-25 * STEP))
		body.vel = vel
		body.last, body.lastRot = body.pos, body.rot
		body.pos = p
		body.gNow = c.gEff
		if body.spinT then body.spinT += STEP end
	end
	-- facing the other out of a hit and into the next, flying in between
	local facing = share > 0.8 and (share - 0.8) / 0.2 or (share < 0.1 and 1 - share / 0.1 or 0)
	for _, body in ipairs({ self.L, self.F }) do
		local toOther = unitOr(body.other.pos - body.pos, body.base.LookVector)
		local want = orient(body.vel, body.acc, body.gNow, toOther, facing, body.base)
		body.base = body.base:Lerp(want, 1 - math.exp(-16 * STEP))
		local back, roll = spinAngle(body)
		body.rot = body.base * CFrame.Angles(back, 0, roll)
	end
	self.lPos, self.fPos = self.L.pos, self.F.pos
	self.center = (self.L.pos + self.F.pos) / 2
	return fired
end

-- style: "Dogfight" or "Leap"
function ClashOrbit.newSim(style, seed, center, lStart, fStart, standH)
	if style == "Leap" then
		return ClashOrbit.newLeap(seed, center, lStart, fStart, standH)
	end
	return ClashOrbit.newDogfight(seed, center, lStart, fStart, standH)
end

-- ============================================================
-- Server: run the clash on the real bodies
-- ============================================================

local TRAIL_NAMES = { RocketTrail = true, RocketTrailAtt0 = true, RocketTrailAtt1 = true }
local ATTRS = { "OrbitSeed", "OrbitStart", "OrbitPartner", "OrbitC0", "OrbitL0", "OrbitF0", "OrbitStand", "OrbitStyle" }

local function release(root)
	if not root or not root.Parent then return end
	root.Anchored = false
	local antiGrav = root:FindFirstChild("MidAir_AntiGrav")
	if antiGrav then antiGrav.Enabled = true end
	root.AssemblyLinearVelocity = Vector3.zero
	for _, child in ipairs(root:GetChildren()) do
		if child.Name == "RocketTrail" then
			child.Enabled = false
			Debris:AddItem(child, child.Lifetime)
		elseif TRAIL_NAMES[child.Name] then
			Debris:AddItem(child, 2)
		end
	end
end

local function inClash(model)
	local h = model and model.Parent and model:FindFirstChildOfClass("Humanoid")
	return h and h.Health > 0 and model:GetAttribute("CurrentState") == "MidAirClash"
end

local function standHeight(humanoid, root)
	return humanoid.HipHeight + root.Size.Y / 2
end

-- Run the clash on two Quins. Returns a handle: handle.done turns true when it is over
-- (handle.reason: "cycles", "time" or "broken"). handle.stop() ends it early.
function ClashOrbit.run(leader, follower, center)
	local AnimationModule = require(Modules:WaitForChild("AnimationModule"))
	local AudioModule = require(Modules:WaitForChild("AudioModule"))
	local VfxModule = require(Modules:WaitForChild("VfxModule"))
	local AnimationIds = require(QuinCore:WaitForChild("AnimationIds"))

	local handle = { done = false, cycles = 0, contacts = 0, center = center }
	local lRoot, fRoot = leader:FindFirstChild("HumanoidRootPart"), follower:FindFirstChild("HumanoidRootPart")
	local lHum, fHum = leader:FindFirstChildOfClass("Humanoid"), follower:FindFirstChildOfClass("Humanoid")
	if not (lRoot and fRoot and lHum and fHum) then
		handle.done, handle.reason = true, "broken"
		return handle
	end

	local seed = math.random(1, 2 ^ 30)
	local stand = standHeight(lHum, lRoot)
	local style = math.random() < cfg("LeapChance", 0.25) and "Leap" or "Dogfight"
	local sim = ClashOrbit.newSim(style, seed, center, lRoot.Position, fRoot.Position, stand)
	handle.style = style
	local startAt = Workspace:GetServerTimeNow()
	leader:SetAttribute("OrbitStyle", style)
	leader:SetAttribute("OrbitPartner", follower.Name)
	leader:SetAttribute("OrbitC0", center)
	leader:SetAttribute("OrbitL0", lRoot.Position)
	leader:SetAttribute("OrbitF0", fRoot.Position)
	leader:SetAttribute("OrbitStand", stand)
	leader:SetAttribute("OrbitStart", startAt)
	leader:SetAttribute("OrbitSeed", seed) -- (last: the clients start on it)

	-- the path moves them: anchored, so no physics or other movers fight it
	for _, root in ipairs({ lRoot, fRoot }) do
		local antiGrav = root:FindFirstChild("MidAir_AntiGrav")
		if antiGrav then antiGrav.Enabled = false end
		root.Anchored = true
	end

	local function strike(humanoid, n)
		local punches, kicks = AnimationIds.Punches or {}, AnimationIds.Kicks or {}
		local list = (n % 2 == 1 and #punches > 0) and punches or kicks
		if #list > 0 then
			AnimationModule.play(humanoid, list[math.random(1, #list)], Enum.AnimationPriority.Action4, false, 1.6)
		end
	end

	AnimationModule.playConfig(lHum, "Movement.Fall", 1.0, Enum.AnimationPriority.Action, false)
	AnimationModule.playConfig(fHum, "Movement.Fall", 1.0, Enum.AnimationPriority.Action, false)
	VfxModule.createRocketTrail(lRoot)
	VfxModule.createRocketTrail(fRoot)
	AudioModule.playSonicBoom(center)

	local conn
	local function finish(reason)
		if handle.done then return end
		handle.done, handle.reason = true, reason
		if conn then conn:Disconnect() end
		for _, name in ipairs(ATTRS) do leader:SetAttribute(name, nil) end
		release(lRoot)
		release(fRoot)
		AnimationModule.stopConfig(lHum, "Movement.Fall", 0.1)
		AnimationModule.stopConfig(fHum, "Movement.Fall", 0.1)
		AnimationModule.stopConfig(lHum, "Movement.Run", 0.1)
		AnimationModule.stopConfig(fHum, "Movement.Run", 0.1)
	end
	handle.stop = function() finish("stopped") end

	local hums = { L = lHum, F = fHum }
	local start = os.clock()
	conn = RunService.Heartbeat:Connect(function()
		local grace = os.clock() - start < 0.4 -- (the follower enters the clash a tick later)
		if not inClash(leader) or (not grace and not inClash(follower)) then
			finish("broken")
			return
		end
		-- step the path up to now (fixed steps, as the clients do)
		local now = Workspace:GetServerTimeNow() - startAt
		while not sim.done and sim.time + STEP <= now do
			for _, e in ipairs(sim:step() or {}) do
				if e.kind == "hit" then
					handle.contacts += 1
					strike(lHum, handle.contacts)
					strike(fHum, handle.contacts + 1)
					local mid = (sim.lPos + sim.fPos) / 2
					AudioModule.playSlam(mid)
					VfxModule.createShockwave(mid, e.brawl and 4 or 7, 0.18)
					VfxModule.shakeScreen(mid, 250, e.brawl and 3 or 6)
					-- chip damage: whoever got the better of this exchange
					local victim = math.random() < 0.5 and lHum or fHum
					local DamageModule = require(script.Parent:WaitForChild("DamageModule"))
					DamageModule.chip(victim == lHum and follower or leader, victim.Parent, cfg("ContactDamage", 4))
				elseif e.kind == "plant" then
					-- a crouch while it is down (a landing clip: fast for an instant, slower for a wait)
					local humanoid = hums[e.who]
					local speed = (e.dur or 0) > 0.2 and 1.2 or 2.4
					AnimationModule.playConfig(humanoid, math.random() < 0.5 and "Parkour.LandingSoft" or "Parkour.LandingSuperHero", speed, Enum.AnimationPriority.Action3, false)
					local root = e.who == "L" and lRoot or fRoot
					VfxModule.createShockwave(root.Position - Vector3.new(0, stand, 0), 3, 0.12)
				elseif e.kind == "run" then
					local humanoid = hums[e.who]
					AnimationModule.stopConfig(humanoid, "Parkour.LandingSoft", 0.05)
					AnimationModule.stopConfig(humanoid, "Parkour.LandingSuperHero", 0.05)
					AnimationModule.playConfig(humanoid, "Movement.Run", 1.6, Enum.AnimationPriority.Action3, true)
				elseif e.kind == "launch" then
					local humanoid = hums[e.who]
					AnimationModule.stopConfig(humanoid, "Parkour.LandingSoft", 0.05)
					AnimationModule.stopConfig(humanoid, "Parkour.LandingSuperHero", 0.05)
					AnimationModule.stopConfig(humanoid, "Movement.Run", 0.05)
					AnimationModule.playConfig(humanoid, "ProjectileJump.NinjaJump", 1.8, Enum.AnimationPriority.Action3, false)
				end
			end
		end
		handle.cycles = sim.cycles
		handle.center = sim.center or center
		local lcf, fcf = sim:frames(1)
		lRoot.CFrame = lcf
		fRoot.CFrame = fcf
		if sim.done then
			finish(sim.reason)
		end
	end)
	return handle
end

-- ============================================================
-- Client: draw every clash from its own run of the path
-- ============================================================

function ClashOrbit.startClient()
	local running = {} -- leader -> { sim, startAt, lRoot, fRoot, follower }

	local function begin(leader)
		local seed = leader:GetAttribute("OrbitSeed")
		local startAt = leader:GetAttribute("OrbitStart")
		local folder = leader.Parent
		local follower = folder and folder:FindFirstChild(leader:GetAttribute("OrbitPartner") or "")
		local c0, l0, f0 = leader:GetAttribute("OrbitC0"), leader:GetAttribute("OrbitL0"), leader:GetAttribute("OrbitF0")
		local lRoot = leader:FindFirstChild("HumanoidRootPart")
		local fRoot = follower and follower:FindFirstChild("HumanoidRootPart")
		if not (seed and startAt and c0 and l0 and f0 and lRoot and fRoot) then return end
		running[leader] = { sim = ClashOrbit.newSim(leader:GetAttribute("OrbitStyle") or "Dogfight", seed, c0, l0, f0, leader:GetAttribute("OrbitStand")), startAt = startAt, lRoot = lRoot, fRoot = fRoot, follower = follower }
	end

	local function stop(leader)
		local run = running[leader]
		if run then
			ClashOrbit.motion[leader] = nil
			ClashOrbit.motion[run.follower] = nil
		end
		running[leader] = nil
	end

	local function watch(model)
		if not model:IsA("Model") then return end
		model:GetAttributeChangedSignal("OrbitSeed"):Connect(function()
			if model:GetAttribute("OrbitSeed") then begin(model) else stop(model) end
		end)
		if model:GetAttribute("OrbitSeed") then begin(model) end
	end

	task.spawn(function()
		local folder = Workspace:WaitForChild("QuinServer")
		for _, m in ipairs(folder:GetChildren()) do watch(m) end
		folder.ChildAdded:Connect(watch)
	end)

	RunService:BindToRenderStep("ClashOrbitDraw", Enum.RenderPriority.Camera.Value - 1, function()
		local now = Workspace:GetServerTimeNow()
		for leader, run in pairs(running) do
			local sim = run.sim
			if not leader.Parent or not run.lRoot.Parent or not run.fRoot.Parent then
				stop(leader)
			else
				local t = now - run.startAt
				local guard = 0
				while not sim.done and sim.time + STEP <= t and guard < 600 do
					sim:step()
					guard += 1
				end
				if sim.done then
					stop(leader) -- (the server lets go of them next)
				else
					local alpha = math.clamp((t - sim.time) / STEP, 0, 1)
					local lcf, fcf = sim:frames(alpha)
					run.lRoot.CFrame = lcf
					run.fRoot.CFrame = fcf
					ClashOrbit.motion[leader] = sim.L
					ClashOrbit.motion[run.follower] = sim.F
				end
			end
		end
	end)
end

return ClashOrbit
