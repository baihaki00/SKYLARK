--// SocialRespect.lua
-- The Respect Custom, the Honorable Comeback and the Big Clutch (SocialSystem part).
--
-- Nothing is triggered by numbers alone. A lone survivor facing MinRatio+ opponents only
-- qualifies when its contribution (kills, damage, time fighting) passes this match's threshold
-- (randomised per match: most matches never see it). Then the opponents who perceive it start to
-- recognise it, one by one, faster when allies near them already hesitate:
--   hesitate (stop, step back, a look at an ally and a nod: "cool down, he's alone")
--   observe  (stand off, watch)            make space (back off further)
-- A strike from the survivor sets an opponent's recognition back. When enough have made space,
-- the custom is agreed: everyone walks to a spot round the arena centre at its own time and pace
-- (mostly walking, some jog, a few run), imperfectly placed; the survivor eases off and waits; a
-- ceremony platform rises at the centre if the centre is clear; the opponents' leader (or their
-- best) walks in, the survivor walks in.
--   standoff        the two circle each other, closing in, walking then prowling, until one of
--                   them breaks the tension and goes in; only those two may fight
--   spectators      stand and watch, pace along the edge when it gets heated, and drift with the
--                   fight if it moves (the dais pulls the fight back; it is not a wall)
--   leader wins     the custom ends, spectators drift back
--   survivor wins   Honorable Comeback: a beat of shock, then most of them turn on the survivor
--                   together (a hunting pack: no retreating now); a few hold back and watch,
--                   and join when it turns
--   2 more kills    Big Clutch (the arena stops and stares);  winning it all: Historic
--
-- Publishes: RespectRole (Hesitating / Watching / Spectator / Duelist / Honored),
-- RespectCandidate, SocialStandoff / SocialStandoffPace (the circling gap and pace, CirclingState),
-- SocialWatchPoint (where a watcher faces, IdleState), SocialHunt (DecisionSystem: hunting),
-- Workspace RespectCustomActive / RespectStats, arena events (crowd).

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")

local QuinCore = ReplicatedStorage:WaitForChild("QuinCore")
local CombatConfig = require(QuinCore:WaitForChild("CombatConfig"))
local Modules = QuinCore:WaitForChild("Modules")
local SocialSystem = require(Modules:WaitForChild("SocialSystem"))
local SpatialModule = require(Modules:WaitForChild("SpatialModule"))

local CFG = (CombatConfig.Social or {}).Respect or {}

local SocialRespect = {}

local rec = {}          -- opponent -> recognition
local lastHP = {}       -- model -> health last tick
local matchStart = os.clock()
local thresholdMul = nil
local custom = nil      -- the running custom
local stats = { candidates = 0, accepted = 0, outcomes = {}, comebackReactions = {}, standoffBreaks = {} }

local function now() return os.clock() end
local function rootOf(m) return m and m:FindFirstChild("HumanoidRootPart") end
local function humOf(m) return m and m:FindFirstChildOfClass("Humanoid") end
local function alive(m) local h = humOf(m) return m and m.Parent and h and h.Health > 0 end
local function hpRatio(m) local h = humOf(m) return h and h.MaxHealth > 0 and h.Health / h.MaxHealth or 0 end
local function flat(v) return Vector3.new(v.X, 0, v.Z) end
local function flatDist(a, b)
	local ra, rb = rootOf(a), rootOf(b)
	if not (ra and rb) then return math.huge end
	return flat(ra.Position - rb.Position).Magnitude
end
local function rand(r) return r[1] + math.random() * (r[2] - r[1]) end
local function bump(t, k) t[k] = (t[k] or 0) + 1 end
local function lerp(a, b, t) return a + (b - a) * t end
local function smooth(x) x = math.clamp(x, 0, 1) return x * x * (3 - 2 * x) end
local function aggressionOf(m) return m:GetAttribute("Pers_Aggression") or 0.6 end
local function bearing(v)
	return v.Magnitude > 0.5 and v.Unit or Vector3.new(math.cos(math.random() * 6.28), 0, math.sin(math.random() * 6.28))
end
local function onCircle(center, angle, radius)
	return center + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
end

local function setRole(m, role)
	if m and m.Parent and m:GetAttribute("RespectRole") ~= role then m:SetAttribute("RespectRole", role) end
end

local function arenaCenter()
	local root = Workspace:FindFirstChild("argoniaonion")
	local ground = root and root:FindFirstChild("ArenaGround", true)
	if not ground then return Vector3.new(0, 2, 0), 2 end
	local top = ground.Position.Y + ground.Size.Y / 2
	return Vector3.new(ground.Position.X, top, ground.Position.Z), top
end

local function contribution(s)
	return (s:GetAttribute("MatchKills") or 0) * (CFG.PerKill or 1.0)
		+ (s:GetAttribute("MatchDamageDealt") or 0) / (CFG.DamagePerPoint or 250)
		+ (now() - matchStart) / 60 * (CFG.PerMinute or 0.5)
		- (s:GetAttribute("MatchPenalty") or 0) -- (time off the arena floor, throwing a Quin out of the arena: ArenaTrespass)
end

local function nearestAlly(m, within)
	local best, bd = nil, within or 30
	for _, o in ipairs(SocialSystem.fighters()) do
		if o ~= m and o:GetAttribute("Team") == m:GetAttribute("Team") then
			local d = flatDist(o, m)
			if d < bd then best, bd = o, d end
		end
	end
	return best
end

-- ============================================================================
-- Ceremony platform (only where the centre is clear: the generated arena keeps it open)
-- ============================================================================

-- the ceremony footprint's outer edge (dais + its steps)
local function ceremonyEdge()
	return (CFG.CeremonyRadius or 80) + (CFG.CeremonyStepWidth or 6)
end

local function centreClear(center, radius)
	local params = OverlapParams.new()
	local exclude = { Workspace:FindFirstChild("QuinServer"), Workspace:FindFirstChild("PlayerCostumes") }
	local root = Workspace:FindFirstChild("argoniaonion")
	local ground = root and root:FindFirstChild("ArenaGround", true)
	if ground then table.insert(exclude, ground) end
	params.FilterDescendantsInstances = exclude
	params.FilterType = Enum.RaycastFilterType.Exclude
	local hits = Workspace:GetPartBoundsInBox(CFrame.new(center + Vector3.new(0, 6, 0)), Vector3.new(radius * 2, 10, radius * 2), params)
	for _, p in ipairs(hits) do
		if p.CanCollide and flat(p.Position - center).Magnitude < radius + p.Size.Magnitude / 2 then
			return false
		end
	end
	return true
end

local function buildPlatform(center, floorY)
	local r = CFG.CeremonyRadius or 80
	if not centreClear(center, ceremonyEdge()) then return nil end
	local folder = Instance.new("Folder")
	folder.Name = "RespectCeremony"
	folder.Parent = (Workspace:FindFirstChild("argoniaonion") and Workspace.argoniaonion:FindFirstChild("ArenaOne")) or Workspace
	local rise = CFG.CeremonyRise or 3
	local function disc(name, radius, height, topY, color)
		local p = Instance.new("Part")
		p.Name = name
		p.Shape = Enum.PartType.Cylinder
		p.Size = Vector3.new(height, radius * 2, radius * 2)
		p.Anchored = true
		p.Material = Enum.Material.SmoothPlastic
		p.Color = color
		p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
		local up = CFrame.new(center.X, topY - height / 2, center.Z) * CFrame.Angles(0, 0, math.pi / 2)
		p.CFrame = up - Vector3.new(0, height, 0) -- starts below the floor
		p.Parent = folder
		return p, up
	end
	-- shallow tiers (each lower than a Quin's collision-body clearance) so they walk straight up
	local width = CFG.CeremonyStepWidth or 6
	local tiers = math.max(1, math.ceil(rise / (CFG.CeremonyTierHeight or 0.4)))
	local t = CFG.CeremonyRiseTime or 2.5
	local parts, down = {}, {}
	for i = 1, tiers do
		local isDais = i == tiers
		local topY = floorY + rise * i / tiers
		local radius = r + width * (tiers - i) / tiers
		local shade = isDais and Color3.fromRGB(224, 218, 202) or Color3.fromRGB(196, 190, 176):Lerp(Color3.fromRGB(224, 218, 202), (i - 1) / tiers)
		local part, upCF = disc(isDais and "Dais" or ("Step" .. i), radius, topY - floorY, topY, shade)
		TweenService:Create(part, TweenInfo.new(t * (1 + 0.1 * i / tiers), Enum.EasingStyle.Sine, Enum.EasingDirection.Out), { CFrame = upCF }):Play()
		table.insert(parts, part)
		table.insert(down, upCF - Vector3.new(0, (topY - floorY) * 1.5, 0))
	end
	return { folder = folder, parts = parts, down = down }
end

local function sinkPlatform(platform)
	if not platform then return end
	for i, p in ipairs(platform.parts) do
		TweenService:Create(p, TweenInfo.new(2.5, Enum.EasingStyle.Sine, Enum.EasingDirection.In), { CFrame = platform.down[i] }):Play()
	end
	task.delay(2.7, function() platform.folder:Destroy() end)
end

-- The same round dais for a match fought on it (Player Quin match mode): rises at `center` from a
-- floor at floorY. A handle for sinkDais, or nil when the centre is not clear. daisTop: the height
-- of its top above the floor; daisRadius: its top's radius.
function SocialRespect.buildDais(center, floorY)
	return buildPlatform(center, floorY)
end
function SocialRespect.sinkDais(handle)
	sinkPlatform(handle)
end
function SocialRespect.daisRadius()
	return CFG.CeremonyRadius or 80
end
function SocialRespect.daisTop()
	return CFG.CeremonyRise or 3
end

-- The dais pulls the duellists back toward its middle (SocialSystem.constrainToCeremony is
-- called by Main and the states). A pull, not a wall: it grows past the margin, then fades out
-- well off the dais, so a brawl can spill off it and find its way back.
local function ceremonyConstraint(rootPart)
	if not (custom and (custom.phase == "Duel" or custom.phase == "Standoff") and custom.platform) then return end
	local m = rootPart.Parent
	if not (m and m:GetAttribute("RespectRole") == "Duelist") then return end -- (never pulls spectators in)
	local offset = flat(rootPart.Position - custom.center)
	local over = offset.Magnitude - ((CFG.CeremonyRadius or 80) - (CFG.DuelEdgeMargin or 12))
	if over <= 0 then return end
	local zone = CFG.DuelSoftZone or 30
	local weight = over < zone and over / zone or math.max(0, 1 - (over - zone) / zone)
	local inward = -offset.Unit
	local v = rootPart.AssemblyLinearVelocity
	local outward = flat(v):Dot(-inward)
	if outward > 0 and weight > 0 then
		rootPart.AssemblyLinearVelocity = v + inward * outward * (CFG.DuelGravity or 0.7) * weight
	end
end
SocialSystem.ceremonyConstraint = ceremonyConstraint

-- ============================================================================
-- Recognition (before the custom)
-- ============================================================================

local function stageOf(r)
	local S = CFG.Stages or {}
	if r >= (S.Space or 3) then return 3 end
	if r >= (S.Observe or 2) then return 2 end
	if r >= (S.Hesitate or 1) then return 1 end
	return 0
end

local function onStage(o, s, stage)
	local ro, rs = rootOf(o), rootOf(s)
	if not (ro and rs) then return end
	local away = bearing(flat(ro.Position - rs.Position))
	if stage == 1 then
		-- stops, steps back, a look at the survivor, a look at an ally and a nod: "cool down"
		setRole(o, "Hesitating")
		SocialSystem.setMoveIntent(o, ro.Position + away * 6, "walk", 3)
		SocialSystem.lookAt(o, s, 1.2)
		local ally = nearestAlly(o, 30)
		if ally then
			task.delay(1.3, function() SocialSystem.acknowledge(o, ally) end)
		end
	elseif stage == 2 then
		setRole(o, "Watching")
		SocialSystem.setMoveIntent(o, rs.Position + away * (20 + math.random() * 8), "walk", 5)
		SocialSystem.lookAt(o, s, 2)
	elseif stage == 3 then
		setRole(o, "Watching")
		SocialSystem.setMoveIntent(o, rs.Position + away * (32 + math.random() * 8), "walk", 5)
	end
	o:SetAttribute("SocialWatchPoint", rs.Position)
end

local acceptCustom -- forward

local function recognise(s, opponents, dt)
	local threshold = (CFG.ContributionThreshold or 3) * thresholdMul
	local strength = math.min(2, contribution(s) / threshold)
	local spaceCount = 0
	for _, o in ipairs(opponents) do
		local r = rec[o] or 0
		local before = stageOf(r)
		-- a strike from the survivor brings it back into the fight
		local h = humOf(o)
		if h and lastHP[o] and h.Health < lastHP[o] - 1 and o:GetAttribute("LastAttackerName") == s.Name then
			r -= CFG.HitSetback or 1.5
		end
		local d = flatDist(o, s)
		local perceives = d <= 25 or (d <= (CFG.PerceiveRange or 70) and SpatialModule.checkLineOfSight(
			SpatialModule.getEyePosition(rootOf(o)), SpatialModule.getEyePosition(rootOf(s)), { o, s }))
		local contagion = 0
		for _, a in ipairs(opponents) do
			if a ~= o and (rec[a] or 0) >= 1 and flatDist(a, o) < 30 then contagion += 1 end
		end
		contagion = math.min(contagion, CFG.ContagionCap or 3)
		if perceives then
			r += dt * ((CFG.RecRate or 0.35) * strength + (CFG.ContagionRate or 0.25) * contagion)
		else
			r -= dt * 0.15
		end
		r = math.clamp(r, 0, 4)
		rec[o] = r
		local after = stageOf(r)
		if after ~= before then
			if after == 0 then
				setRole(o, nil)
				SocialSystem.clearMoveIntent(o)
			elseif after > before then
				onStage(o, s, after)
			end
		end
		if after >= 3 then spaceCount += 1 end
	end
	if spaceCount >= math.max(CFG.AcceptMin or 2, math.ceil(#opponents * (CFG.AcceptShare or 0.5))) then
		acceptCustom(s, opponents)
	end
end

local function clearRecognition()
	for o in pairs(rec) do
		if o.Parent and (o:GetAttribute("RespectRole") == "Hesitating" or o:GetAttribute("RespectRole") == "Watching") then
			setRole(o, nil)
			SocialSystem.clearMoveIntent(o)
			o:SetAttribute("SocialWatchPoint", nil)
		end
	end
	rec = {}
end

-- ============================================================================
-- The custom
-- ============================================================================

local function pickPace()
	local p = CFG.Paces or { walk = 0.7, jog = 0.2, run = 0.1 }
	local r = math.random()
	if r < p.walk then return "walk" end
	if r < p.walk + p.jog then return "jog" end
	return "run"
end

local function spectatorSpot(o, center)
	local ro = rootOf(o)
	local dir = bearing(ro and flat(ro.Position - center) or Vector3.zero)
	-- its own bearing, a little off: nobody crosses the arena to a numbered seat
	local a = math.atan2(dir.Z, dir.X) + (math.random() - 0.5) * 0.5
	local gap
	local roll = math.random()
	if roll < (CFG.CloseShare or 0.15) then gap = rand(CFG.CloseGap or { 3, 8 })
	elseif roll < (CFG.CloseShare or 0.15) + (CFG.FarShare or 0.1) then gap = rand(CFG.FarGap or { 50, 70 })
	else gap = rand(CFG.RingGap or { 10, 40 }) end
	return onCircle(center, a, ceremonyEdge() + gap)
end

acceptCustom = function(s, opponents)
	local center = arenaCenter()
	stats.accepted += 1
	-- who meets the survivor: the opponents' leader, else their best
	local leader, best = nil, -math.huge
	for _, o in ipairs(opponents) do
		local score = (o:GetAttribute("SocialRole") == "Leader" and 100 or 0) + (o:GetAttribute("LeaderCred") or 0) * 10
			+ (SocialSystem.standingOf and SocialSystem.standingOf(o) or 0)
		if alive(o) and score > best then leader, best = o, score end
	end
	if not leader then return end
	custom = { survivor = s, leader = leader, center = center, focus = center, heat = 0, phase = "Gathering", since = now(),
		opponents = {}, spots = {}, faced = {}, watch = {}, jumps = {}, hunters = {}, reserved = {}, duelHP = {}, speeds = {} }
	Workspace:SetAttribute("RespectCustomActive", true)
	SocialSystem.raiseEvent("RespectCustom", { text = s.Name .. " is given a proper fight", survivor = s, leader = leader })
	print(string.format("[Social] Respect custom: %s (contribution %.1f) faces %s", s.Name, contribution(s), leader.Name))

	-- the survivor eases off: holds fire, looks round at them
	setRole(s, "Honored")
	s:SetAttribute("TargetOverride", nil)
	SocialSystem.clearMoveIntent(s)
	local looks = 0
	for _, o in ipairs(opponents) do
		if looks < 3 and flatDist(o, s) < 60 then
			looks += 1
			task.delay(looks * 1.1, function() SocialSystem.lookAt(s, o, 1.0) end)
		end
	end

	for _, o in ipairs(opponents) do
		if alive(o) then
			table.insert(custom.opponents, o)
			if o == leader then
				setRole(o, "Watching")
			else
				setRole(o, "Spectator")
				local spot = spectatorSpot(o, center)
				custom.spots[o] = spot
				local delay = rand(CFG.Delay or { 0.5, 4 })
				local pace = pickPace()
				custom.watch[o] = { pref = flat(spot - center).Magnitude, nextThink = now() + delay + rand(CFG.WatchThink or { 2, 5 }) }
				o:SetAttribute("SocialWatchPoint", center)
				task.delay(delay, function()
					if custom and custom.spots[o] and o.Parent then
						SocialSystem.setMoveIntent(o, spot, pace, 40)
					end
				end)
				-- a look at the survivor before it goes
				SocialSystem.lookAt(o, s, delay * 0.8 + 0.4)
			end
		end
	end
	-- duellists wait outside the ceremony space for now
	local R = ceremonyEdge() + 8
	for _, m in ipairs({ s, leader }) do
		local rm = rootOf(m)
		m:SetAttribute("SocialWatchPoint", center)
		if rm and flat(rm.Position - center).Magnitude < R then
			SocialSystem.setMoveIntent(m, center + bearing(flat(rm.Position - center)) * R, "walk", 12)
		end
	end
	-- the ceremony space, once nobody stands where it rises
	custom.platformAt = now() + (CFG.PlatformDelay or 3)
end

local function snapshotJump(m)
	local h = humOf(m)
	if h then custom.jumps[m] = { h.UseJumpPower, h.JumpPower, h.JumpHeight } end
end

local function restoreJumps()
	if not custom then return end
	for m, j in pairs(custom.jumps) do
		local h = humOf(m)
		if h then h.UseJumpPower, h.JumpPower, h.JumpHeight = j[1], j[2], j[3] end
	end
	custom.jumps = {}
end

local function clearStandoff(m)
	if m and m.Parent then
		m:SetAttribute("SocialStandoff", nil)
		m:SetAttribute("SocialStandoffPace", nil)
	end
end

-- The two meet on the dais and circle each other before anyone goes in
local function startStandoff()
	local c = custom
	local s, l = c.survivor, c.leader
	c.phase = "Standoff"
	snapshotJump(s)
	snapshotJump(l)
	setRole(s, "Duelist")
	setRole(l, "Duelist")
	s:SetAttribute("TargetOverride", l.Name)
	l:SetAttribute("TargetOverride", s.Name)
	local gap0 = math.clamp(flatDist(s, l), (CFG.StandoffMinGap or 9) + 8, CFG.StandoffStartGap or 34)
	c.standoff = { at = now(), duration = rand(CFG.StandoffTime or { 7, 16 }), gap0 = gap0, hp = {} }
	for _, m in ipairs({ s, l }) do
		SocialSystem.clearMoveIntent(m)
		m:SetAttribute("SocialWatchPoint", nil)
		m:SetAttribute("SocialStandoff", gap0)
		m:SetAttribute("SocialStandoffPace", "walk")
		c.standoff.hp[m] = humOf(m) and humOf(m).Health
	end
	SocialSystem.acknowledge(l, s)
	SocialSystem.acknowledge(s, l, 0.5)
	SocialSystem.raiseEvent("Standoff", { text = s.Name .. " and " .. l.Name })
	print(string.format("[Social] Standoff: %s and %s (%.1f s planned)", s.Name, l.Name, c.standoff.duration))
end

-- One of them has had enough: it goes in, and the duel is on
local function breakStandoff(breaker, reason)
	local c = custom
	local other = breaker == c.survivor and c.leader or c.survivor
	clearStandoff(c.survivor)
	clearStandoff(c.leader)
	c.phase = "Duel"
	c.duelAt = now()
	bump(stats.standoffBreaks, reason)
	local rb, ro, hum = rootOf(breaker), rootOf(other), humOf(breaker)
	if rb and ro and hum then
		local d = flat(ro.Position - rb.Position).Magnitude
		if d >= (CombatConfig.DashMinDistance or 10) and d <= (CombatConfig.DashMaxDistance or 28) then
			local LocomotionModule = require(Modules:WaitForChild("LocomotionModule"))
			pcall(LocomotionModule.dash, breaker, hum, rb, ro.Position, d)
		end
		breaker:SetAttribute("ForceState", d <= (CombatConfig.CombatRange or 8) * 2.5 and "Fight" or "Chase")
	end
	SocialSystem.raiseEvent("StandoffBreak", { text = breaker.Name })
	print(string.format("[Social] The final fight: %s goes in on %s (%s, after %.1f s)", breaker.Name, other.Name, reason, now() - c.standoff.at))
end

local function updateStandoff(c, dt)
	local s, l = c.survivor, c.leader
	local so = c.standoff
	local t = now() - so.at
	local p = math.clamp(t / so.duration, 0, 1)
	-- the circle closes in (a spiral), and the walk turns to a prowl as it tightens
	local gap = lerp(so.gap0, CFG.StandoffMinGap or 9, smooth(p))
	for i, m in ipairs({ s, l }) do
		local wobble = math.sin(t * 0.9 + i * 1.7) * 1.5
		m:SetAttribute("SocialStandoff", math.floor((gap + wobble) * 10 + 0.5) / 10)
		local prowlAt = (CFG.StandoffProwlAt or 0.45) * (1.3 - aggressionOf(m) * 0.6)
		m:SetAttribute("SocialStandoffPace", p >= prowlAt and "run" or "walk")
		-- struck: the other one broke it
		local h = humOf(m)
		if h and so.hp[m] and h.Health < so.hp[m] - 1 then
			breakStandoff(i == 1 and l or s, "struck")
			return
		end
		so.hp[m] = h and h.Health
	end
	if t < (CFG.StandoffMinTime or 3) then return end
	-- the nerve to go in grows as the circle tightens; aggressive ones go sooner
	local rate = (CFG.StandoffBreakRate or 0.05) + (CFG.StandoffBreakGrowth or 0.6) * p * p
	for _, m in ipairs({ s, l }) do
		if math.random() < rate * (0.5 + aggressionOf(m)) * dt * 0.5 then
			breakStandoff(m, "nerve")
			return
		end
	end
	if p >= 1 then
		breakStandoff(aggressionOf(s) >= aggressionOf(l) and s or l, "closed in")
	end
end

-- Spectators: stand and watch, pace along the edge when it is heated, drift with the fight
local function updateSpectators(c, dt)
	local s, l = c.survivor, c.leader
	local target = c.center
	if (c.phase == "Standoff" or c.phase == "Duel") and alive(s) and alive(l) then
		target = (rootOf(s).Position + rootOf(l).Position) / 2
		target = Vector3.new(target.X, c.center.Y, target.Z)
	end
	c.focus = c.focus:Lerp(target, math.min(1, dt * 0.6))
	c.heat = c.heat * math.exp(-dt / (CFG.HeatDecay or 4))
	-- (only a fight that has left the dais draws them in: while it is on the dais they keep to the edge)
	local shift = math.max(0, flat(c.focus - c.center).Magnitude - ((CFG.CeremonyRadius or 80) - (CFG.DuelEdgeMargin or 12)))
	local minD = CFG.WatchMin or 22
	for o, w in pairs(c.watch) do
		if not alive(o) then
			c.watch[o] = nil
		elseif (c.faced[o] or now() - c.since > 25) and now() >= w.nextThink and not o:GetAttribute("SocialMoveTo") then
			w.nextThink = now() + rand(CFG.WatchThink or { 2, 5 })
			o:SetAttribute("SocialWatchPoint", c.focus)
			local ro = rootOf(o)
			local off = flat(ro.Position - c.focus)
			local d = off.Magnitude
			local dir = bearing(off)
			local a = math.atan2(dir.Z, dir.X)
			-- the further the fight has moved off the middle, the closer they come in after it
			local want = math.clamp(w.pref - shift, minD + 10, w.pref)
			if d < minD then
				SocialSystem.setMoveIntent(o, c.focus + dir * (minD + rand({ 6, 12 })), d < minD * 0.6 and "jog" or "walk", 4)
			elseif math.abs(d - want) > (CFG.WatchTolerance or 15) then
				local dest = onCircle(c.focus, a + (math.random() - 0.5) * 0.4, want)
				SocialSystem.setMoveIntent(o, dest, math.abs(d - want) > 40 and "jog" or "walk", 8)
			else
				local chance = (CFG.PaceChance or 0.25) + (CFG.PaceHeat or 0.4) * math.min(1, c.heat) + (aggressionOf(o) - 0.5) * 0.3
				if math.random() < chance then
					local arc = rand(CFG.PaceArc or { 0.12, 0.3 }) * (math.random() < 0.5 and -1 or 1)
					SocialSystem.setMoveIntent(o, onCircle(c.focus, a + arc, d + (math.random() - 0.5) * 4), "walk", 5)
				end
			end
		end
	end
end

local HUNT_ATTRIBUTES = { "SocialHunt", "SocialStandoff", "SocialStandoffPace", "SocialWatchPoint", "ComebackReaction" }

local function endCustom(outcome)
	if not custom then return end
	bump(stats.outcomes, outcome)
	print("[Social] Respect custom ends: " .. outcome)
	restoreJumps()
	local c = custom
	custom = nil
	for m, base in pairs(c.speeds) do
		if m.Parent then m:SetAttribute("Speed", base or nil) end
	end
	Workspace:SetAttribute("RespectCustomActive", false)
	SocialSystem.raiseEvent("RespectCustomEnd", { text = outcome }) -- (a plain signal, no level)
	sinkPlatform(c.platform)
	for _, m in ipairs(SocialSystem.fighters()) do
		local function release()
			if not m.Parent then return end
			setRole(m, nil)
			SocialSystem.clearMoveIntent(m)
			for _, key in ipairs(HUNT_ATTRIBUTES) do m:SetAttribute(key, nil) end
			local override = m:GetAttribute("TargetOverride")
			if override == c.survivor.Name or override == c.leader.Name then
				m:SetAttribute("TargetOverride", nil)
			end
		end
		-- spectators drift back at their own time
		if m:GetAttribute("RespectRole") then task.delay(math.random() * 4, release) else release() end
	end
	if c.survivor.Parent then
		c.survivor:SetAttribute("RespectCandidate", nil)
		c.survivor:SetAttribute("TargetOverride", nil)
	end
	rec = {}
end

-- After the clutch: what the survivor does is chosen by its body and its fight, not a script
local function afterClutch(s)
	local h = humOf(s)
	if not h then return end
	local hp = hpRatio(s)
	local energy = (s:GetAttribute("Energy") or 100) / 100
	local choice
	if hp < 0.2 then choice = "Exhausted"
	elseif hp < 0.45 then choice = "Kneel"
	elseif energy < 0.3 then choice = "Sit"
	else
		local options = { "LookUp", "Celebrate", "Still", "WalkAway" }
		choice = options[math.random(1, #options)]
	end
	stats.afterClutch = choice
	print("[Social] After the clutch: " .. s.Name .. " - " .. choice)
	if choice == "WalkAway" then
		local rs = rootOf(s)
		if rs then SocialSystem.setMoveIntent(s, rs.Position + rs.CFrame.LookVector * -12, "walk", 6) end
	elseif choice ~= "Still" then
		SocialSystem.playSlot(h, choice) -- (blank slot: it simply stands still)
	end
end

-- A hunter goes after the survivor: no standing back, no retreating (DecisionSystem reads SocialHunt)
local function hunt(o)
	local c = custom
	if not (c and c.phase == "Comeback" and alive(o) and alive(c.survivor)) then return end
	if not c.hunters[o] then
		-- adrenaline: a hunter runs a little faster than it normally would (an even race never closes)
		local base = o:GetAttribute("Speed")
		c.speeds[o] = base or false
		o:SetAttribute("Speed", (base or CFG.BaseRunSpeed or 40) * (1 + (CFG.HuntSpeedBoost or 0.12)))
	end
	c.hunters[o] = true
	setRole(o, nil)
	SocialSystem.clearMoveIntent(o)
	o:SetAttribute("SocialWatchPoint", nil)
	o:SetAttribute("TargetOverride", c.survivor.Name)
	o:SetAttribute("SocialHunt", c.survivor.Name)
	o:SetAttribute("ForceState", "Chase")
end

-- The comeback: the leader is down. A beat of shock, then each decides: most turn on the
-- survivor together, a few hold back and watch
local function comeback()
	local c = custom
	local s = c.survivor
	c.phase = "Comeback"
	c.comebackKills = s:GetAttribute("MatchKills") or 0
	c.lastKills = c.comebackKills
	c.watch = {}
	restoreJumps()
	clearStandoff(s)
	setRole(s, nil)
	s:SetAttribute("TargetOverride", nil)
	SocialSystem.raiseEvent("UnexpectedLeaderDefeat", { text = s.Name .. " beat " .. c.leader.Name })
	task.delay(1.5, function()
		if custom == c and c.phase == "Comeback" then
			SocialSystem.raiseEvent("HonorableComeback", { text = s.Name })
		end
	end)
	-- shock: everyone stops dead, stares at the survivor, at each other
	local others = {}
	for _, o in ipairs(c.opponents) do
		if alive(o) and o ~= c.leader then table.insert(others, o) end
	end
	local rs = rootOf(s)
	for i, o in ipairs(others) do
		setRole(o, "Watching")
		SocialSystem.clearMoveIntent(o)
		o:SetAttribute("SocialWatchPoint", rs and rs.Position)
		SocialSystem.lookAt(o, s, 1.0)
		local other = others[(i % #others) + 1]
		if other ~= o then
			task.delay(0.9 + math.random() * 0.4, function() SocialSystem.lookAt(o, other, 0.7) end)
		end
	end
	task.delay(rand(CFG.ShockTime or { 1.4, 2.4 }), function()
		if not (custom == c and c.phase == "Comeback" and alive(s)) then return end
		local W = CFG.ComebackReactions or { pack = 0.6, avenge = 0.15, reserved = 0.25 }
		local pack = {}
		for _, o in ipairs(others) do
			if alive(o) then
				-- a hurt survivor draws them in; a hurt opponent is likelier to hold back
				local wPack = (W.pack or 0.6) * (1 + (1 - hpRatio(s)) * 0.5)
				local wAvenge = (W.avenge or 0.15) * (0.5 + (o:GetAttribute("FollowingLeader") == c.leader.Name and 1 or 0))
				local wReserved = (W.reserved or 0.25) * (1 + (1 - hpRatio(o)))
				local r = math.random() * (wPack + wAvenge + wReserved)
				local kind = r < wPack and "pack" or (r < wPack + wAvenge and "avenge" or "reserved")
				bump(stats.comebackReactions, kind)
				o:SetAttribute("ComebackReaction", kind)
				if kind == "reserved" then
					c.reserved[o] = { joinAt = now() + rand(CFG.ReservedJoin or { 10, 25 }), nextThink = 0 }
				else
					if kind == "avenge" then o:SetAttribute("GrudgeTarget", s.Name) end
					table.insert(pack, o)
				end
			end
		end
		-- the pack: a look and a nod between them, then they go, a beat apart
		for i, o in ipairs(pack) do
			local other = pack[(i % #pack) + 1]
			if other ~= o then SocialSystem.acknowledge(o, other, 0) end
			task.delay(0.6 + math.random() * 0.8, function() hunt(o) end)
		end
		if #pack > 0 then
			task.delay(1.2, function()
				if custom == c then SocialSystem.raiseEvent("ComebackHunt", { text = s.Name }) end
			end)
		end
	end)
end

local function updateComeback(c)
	local s = c.survivor
	local kills = s:GetAttribute("MatchKills") or 0
	if kills > c.lastKills then
		c.lastKills = kills
		local clutchNow = not c.bigClutch and kills >= c.comebackKills + (CFG.BigClutchKills or 2)
		if not clutchNow then SocialSystem.raiseEvent("ComebackKill", { text = s.Name }) end
		-- another one down: some of the ones holding back are stung into it
		for _, r in pairs(c.reserved) do
			if math.random() < (CFG.ReservedJoinOnKill or 0.5) then r.joinAt = math.min(r.joinAt, now() + rand({ 0.5, 1.5 })) end
		end
	end
	-- the ones holding back keep their distance and watch; they join when it turns
	local rs = rootOf(s)
	for o, r in pairs(c.reserved) do
		if not alive(o) then
			c.reserved[o] = nil
		elseif now() >= r.joinAt or hpRatio(s) < (CFG.ReservedJoinHP or 0.35) then
			c.reserved[o] = nil
			SocialSystem.lookAt(o, s, 0.8)
			hunt(o)
		elseif rs and now() >= r.nextThink then
			r.nextThink = now() + rand({ 1.5, 3 })
			o:SetAttribute("SocialWatchPoint", rs.Position)
			local off = flat(rootOf(o).Position - rs.Position)
			local d = off.Magnitude
			local band = CFG.ReservedDistance or { 30, 45 }
			if d < band[1] or d > band[2] + 15 then
				SocialSystem.setMoveIntent(o, rs.Position + bearing(off) * rand(band), d > band[2] + 40 and "jog" or "walk", 4)
			end
		end
	end
	-- Big Clutch: the survivor keeps winning; the arena stops and stares for a beat
	if not c.bigClutch and kills >= c.comebackKills + (CFG.BigClutchKills or 2) then
		c.bigClutch = true
		SocialSystem.raiseEvent("BigClutch", { text = s.Name })
		local watchers = {}
		for _, o in ipairs(SocialSystem.fighters()) do
			if o ~= s then table.insert(watchers, o) end
		end
		for i, o in ipairs(watchers) do
			local wasHunting = c.hunters[o]
			setRole(o, "Watching")
			SocialSystem.clearMoveIntent(o)
			local other = watchers[(i % #watchers) + 1]
			if other ~= o then SocialSystem.lookAt(o, other, 0.9) end
			task.delay(1.0, function() SocialSystem.lookAt(o, s, 1.6) end)
			task.delay(rand({ 0.8, 1.2 }) * (CFG.StillnessTime or 2.5), function()
				if custom == c and wasHunting and o.Parent then hunt(o) end
			end)
		end
	end
end

-- ============================================================================
-- Tick
-- ============================================================================

local function updateCustom(dt)
	local c = custom
	local s, l = c.survivor, c.leader
	if not alive(s) then
		if c.phase == "Comeback" then
			SocialSystem.raiseEvent("ComebackFall", { text = s.Name })
			endCustom(c.bigClutch and "survivor fell after the big clutch" or "survivor fell after the comeback")
		else
			endCustom("leader won")
		end
		return
	end
	-- how heated the fight is (the duellists' lost health), for the spectators
	for _, m in ipairs({ s, l }) do
		local h = humOf(m)
		if h then
			if c.duelHP[m] and h.Health < c.duelHP[m] then c.heat += (c.duelHP[m] - h.Health) / math.max(1, h.MaxHealth) * 8 end
			c.duelHP[m] = h.Health
		end
	end
	if c.phase == "Gathering" then
		if not alive(l) then endCustom("leader lost before the fight") return end
		-- the dais rises once its space is empty
		if not c.platform and not c.noPlatform and now() >= c.platformAt then
			local R = ceremonyEdge()
			local occupied = false
			for _, m in ipairs(SocialSystem.fighters()) do
				local rm = rootOf(m)
				local off = rm and flat(rm.Position - c.center)
				if off and off.Magnitude < R + 2 then
					occupied = true
					-- anyone idling in the footprint steps out of it (not a duellist on its way)
					if not m:GetAttribute("SocialMoveTo") then
						SocialSystem.setMoveIntent(m, c.center + bearing(off) * (R + 6), "walk", 8)
					end
				end
			end
			if not occupied then
				c.platform = buildPlatform(c.center, c.center.Y)
				if not c.platform then c.noPlatform = true end
				c.walkInAt = now() + (CFG.CeremonyRiseTime or 2.5) + 1
			elseif now() - c.platformAt > 15 then
				c.noPlatform = true
				c.walkInAt = now()
			end
		end
		-- spectators who arrived turn to the centre (one small step inward)
		for o, spot in pairs(c.spots) do
			local ro = rootOf(o)
			if ro and not c.faced[o] and not o:GetAttribute("SocialMoveTo") and flat(ro.Position - spot).Magnitude < 8 then
				c.faced[o] = true
				local inward = flat(c.center - ro.Position)
				local step = math.min(6, inward.Magnitude - ceremonyEdge() - 2)
				if step > 0.5 then
					SocialSystem.setMoveIntent(o, ro.Position + inward.Unit * step, "walk", 3)
				end
			end
		end
		-- the leader walks in last; the survivor answers
		local half = (CFG.StandoffStartGap or 34) / 2
		if c.walkInAt and now() >= c.walkInAt and not c.walking then
			c.walking = true
			local rl = rootOf(l)
			local dir = bearing(rl and flat(rl.Position - c.center) or Vector3.zero)
			c.walkDir = dir
			SocialSystem.setMoveIntent(l, c.center + dir * half, "walk", 30)
			task.delay(1.2, function()
				if custom == c then
					SocialSystem.lookAt(s, l, 1.5)
					SocialSystem.setMoveIntent(s, c.center - dir * half, "walk", 30)
				end
			end)
		end
		if c.walking then
			local arrived = flat(rootOf(s).Position - c.center).Magnitude < half + 10 and flat(rootOf(l).Position - c.center).Magnitude < half + 10
			if arrived or now() - c.walkInAt > (CFG.DuelStartTimeout or 30) then startStandoff() end
		end
		-- spectators watch, now and then
		if math.random() < 0.2 then
			local o = c.opponents[math.random(1, #c.opponents)]
			if o and o ~= l and alive(o) then SocialSystem.lookAt(o, math.random() < 0.6 and s or l, 1.5 + math.random()) end
		end
		updateSpectators(c, dt)
	elseif c.phase == "Standoff" or c.phase == "Duel" then
		if not alive(l) then comeback() return end
		if c.phase == "Standoff" then updateStandoff(c, dt) end
		-- a brawl that has spilled well off the dais works its way back, casually (between exchanges)
		if c.phase == "Duel" and c.platform then
			c.offSince = c.offSince or {}
			for _, m in ipairs({ s, l }) do
				local off = flat(rootOf(m).Position - c.center)
				if off.Magnitude > (CFG.CeremonyRadius or 80) then
					c.offSince[m] = c.offSince[m] or now()
					if now() - c.offSince[m] > (CFG.OffDaisWander or 6) and not m:GetAttribute("SocialMoveTo") and m:GetAttribute("CurrentState") ~= "Fight" then
						SocialSystem.setMoveIntent(m, c.center + off.Unit * (CFG.CeremonyRadius or 80) * rand({ 0.3, 0.6 }), "jog", 3)
					end
				else
					c.offSince[m] = nil
				end
			end
		end
		if math.random() < 0.3 then
			local o = c.opponents[math.random(1, #c.opponents)]
			if o and o ~= l and alive(o) then SocialSystem.lookAt(o, math.random() < 0.5 and s or l, 1.5 + math.random() * 1.5) end
		end
		updateSpectators(c, dt)
	elseif c.phase == "Comeback" then
		updateComeback(c)
		local anyLeft = false
		for _, o in ipairs(c.opponents) do
			if alive(o) then anyLeft = true break end
		end
		if not anyLeft then
			if c.bigClutch then SocialSystem.raiseEvent("Historic", { text = s.Name }) end
			afterClutch(s)
			endCustom(c.bigClutch and "historic clutch" or "honorable comeback won")
		end
	end
end

local function tick(dt)
	if CFG.Enabled == false then return end
	if not thresholdMul then thresholdMul = rand(CFG.ThresholdJitter or { 0.8, 1.6 }) end
	local fighters = SocialSystem.fighters()
	if custom then
		updateCustom(dt)
	else
		local byTeam, teams = {}, 0
		for _, m in ipairs(fighters) do
			local t = m:GetAttribute("Team")
			if t and t ~= "" and not m:GetAttribute("IsCostume") then
				if not byTeam[t] then byTeam[t] = {} teams += 1 end
				table.insert(byTeam[t], m)
			end
		end
		local survivor, opponents = nil, nil
		if teams == 2 and Workspace:GetAttribute("MatchStarted") ~= false then
			for t, members in pairs(byTeam) do
				if #members == 1 then
					for t2, others in pairs(byTeam) do
						if t2 ~= t and #others >= (CFG.MinRatio or 3) then survivor, opponents = members[1], others end
					end
				end
			end
		end
		if survivor and contribution(survivor) >= (CFG.ContributionThreshold or 3) * thresholdMul then
			if not survivor:GetAttribute("RespectCandidate") then
				survivor:SetAttribute("RespectCandidate", true)
				stats.candidates += 1
			end
			recognise(survivor, opponents, dt)
		elseif next(rec) then
			clearRecognition()
		end
	end
	for _, m in ipairs(fighters) do
		local h = humOf(m)
		if h then lastHP[m] = h.Health end
	end
	if math.random() < 0.1 then
		Workspace:SetAttribute("RespectStats", HttpService:JSONEncode({
			candidates = stats.candidates, accepted = stats.accepted, outcomes = stats.outcomes,
			comebackReactions = stats.comebackReactions, afterClutch = stats.afterClutch, standoffBreaks = stats.standoffBreaks,
			phase = custom and custom.phase or "none", thresholdMul = math.floor(thresholdMul * 100) / 100,
		}))
	end
end

local function reset()
	if custom then endCustom("match reset") end
	rec, lastHP = {}, {}
	matchStart = os.clock()
	thresholdMul = nil
	stats = { candidates = 0, accepted = 0, outcomes = {}, comebackReactions = {}, standoffBreaks = {} }
	Workspace:SetAttribute("RespectStats", nil)
	Workspace:SetAttribute("RespectCustomActive", nil)
	local old = Workspace:FindFirstChild("RespectCeremony", true)
	if old then old:Destroy() end
end

-- Targeting: the candidate survivor leaves alone those who stopped fighting it
function SocialRespect.targetScore(quin, candidate)
	if quin:GetAttribute("RespectCandidate") then
		local role = candidate:GetAttribute("RespectRole")
		if role == "Hesitating" or role == "Watching" or role == "Spectator" then return -1e6 end
	end
	return 0
end

SocialSystem.addTicker("Respect", tick, reset)
SocialSystem.addTargetTerm(SocialRespect.targetScore)

-- Studio test hook: Workspace attribute RespectDevCommand = "seed <name> <kills> <damage>"
-- (gives a Quin a fighting record; the custom itself still has to emerge)
if game:GetService("RunService"):IsStudio() then
	Workspace:GetAttributeChangedSignal("RespectDevCommand"):Connect(function()
		local cmd = Workspace:GetAttribute("RespectDevCommand")
		if type(cmd) ~= "string" or cmd == "" then return end
		Workspace:SetAttribute("RespectDevCommand", nil)
		local verb, name, a, b = cmd:match("^(%S+)%s*(%S*)%s*(%S*)%s*(%S*)")
		local q = Workspace:FindFirstChild("QuinServer") and Workspace.QuinServer:FindFirstChild(name)
		if verb == "seed" and q then
			q:SetAttribute("MatchKills", tonumber(a) or 3)
			q:SetAttribute("MatchDamageDealt", tonumber(b) or 1200)
		end
	end)
end

return SocialRespect
