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
-- best) walks in, the survivor walks in, and only those two may fight.
--   leader wins     the custom ends, spectators drift back
--   survivor wins   Honorable Comeback: every remaining opponent reacts on its own (hesitate,
--                   attack, back away, wait its turn, attack together, avenge)
--   2 more kills    Big Clutch (the arena stops and stares);  winning it all: Historic
--
-- Publishes: RespectRole (Hesitating / Watching / Spectator / Duelist / Honored),
-- RespectCandidate, Workspace RespectCustomActive / RespectStats, arena events.

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
local stats = { candidates = 0, accepted = 0, outcomes = {}, comebackReactions = {} }

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
	if not centreClear(center, r + (CFG.CeremonyStepWidth or 6)) then return nil end
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

-- Duellists stay on the dais (SocialSystem.constrainToCeremony is called by Main and the states)
local function ceremonyConstraint(rootPart)
	if not (custom and custom.phase == "Duel" and custom.platform) then return end
	local m = rootPart.Parent
	if not (m and m:GetAttribute("RespectRole") == "Duelist") then return end -- (never pulls spectators in)
	local offset = flat(rootPart.Position - custom.center)
	local limit = (CFG.CeremonyRadius or 80) - (CFG.DuelEdgeMargin or 12)
	if offset.Magnitude > limit then
		local inward = -offset.Unit
		local v = rootPart.AssemblyLinearVelocity
		local outward = flat(v):Dot(-inward)
		if outward > 0 then
			rootPart.AssemblyLinearVelocity = v + inward * (outward + 6)
		end
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
	local away = flat(ro.Position - rs.Position)
	away = away.Magnitude > 0.5 and away.Unit or Vector3.new(1, 0, 0)
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

local function clearRecognition(opponents)
	for o in pairs(rec) do
		if o.Parent and (o:GetAttribute("RespectRole") == "Hesitating" or o:GetAttribute("RespectRole") == "Watching") then
			setRole(o, nil)
			SocialSystem.clearMoveIntent(o)
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
	local dir = ro and flat(ro.Position - center) or Vector3.new(1, 0, 0)
	dir = dir.Magnitude > 1 and dir.Unit or Vector3.new(math.cos(math.random() * 6.28), 0, math.sin(math.random() * 6.28))
	-- its own bearing, a little off: nobody crosses the arena to a numbered seat
	local a = math.atan2(dir.Z, dir.X) + (math.random() - 0.5) * 0.5
	local gap
	local roll = math.random()
	if roll < (CFG.CloseShare or 0.15) then gap = rand(CFG.CloseGap or { 3, 8 })
	elseif roll < (CFG.CloseShare or 0.15) + (CFG.FarShare or 0.1) then gap = rand(CFG.FarGap or { 50, 70 })
	else gap = rand(CFG.RingGap or { 10, 40 }) end
	local r = ceremonyEdge() + gap
	return center + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
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
	custom = { survivor = s, leader = leader, center = center, phase = "Gathering", since = now(),
		opponents = {}, spots = {}, faced = {}, jumps = {}, released = {}, queue = {} }
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
				task.delay(delay, function()
					if custom and custom.spots[o] and o.Parent then
						SocialSystem.setMoveIntent(o, spot, pace, 40)
					end
				end)
				-- a look at the survivor before it goes, sometimes a nod to an ally
				SocialSystem.lookAt(o, s, delay * 0.8 + 0.4)
			end
		end
	end
	-- duellists wait outside the ceremony space for now
	local R = ceremonyEdge() + 8
	for _, m in ipairs({ s, leader }) do
		local rm = rootOf(m)
		if rm then
			local dir = flat(rm.Position - center)
			dir = dir.Magnitude > 1 and dir.Unit or Vector3.new(1, 0, 0)
			if flat(rm.Position - center).Magnitude < R then
				SocialSystem.setMoveIntent(m, center + dir * R, "walk", 12)
			end
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

local function startDuel()
	custom.phase = "Duel"
	custom.duelAt = now()
	local s, l = custom.survivor, custom.leader
	snapshotJump(s)
	snapshotJump(l)
	setRole(s, "Duelist")
	setRole(l, "Duelist")
	s:SetAttribute("TargetOverride", l.Name)
	l:SetAttribute("TargetOverride", s.Name)
	SocialSystem.acknowledge(l, s)
	SocialSystem.acknowledge(s, l, 0.5)
	print(string.format("[Social] The final fight: %s vs %s", s.Name, l.Name))
end

local function endCustom(outcome, keepSurvivorFighting)
	if not custom then return end
	bump(stats.outcomes, outcome)
	print("[Social] Respect custom ends: " .. outcome)
	restoreJumps()
	local c = custom
	custom = nil
	Workspace:SetAttribute("RespectCustomActive", false)
	SocialSystem.raiseEvent("RespectCustomEnd", { text = outcome }) -- (below the current level: only signals)
	sinkPlatform(c.platform)
	for _, m in ipairs(SocialSystem.fighters()) do
		if m:GetAttribute("RespectRole") then
			-- spectators drift back at their own time
			task.delay(math.random() * 4, function()
				if m.Parent then
					setRole(m, nil)
					SocialSystem.clearMoveIntent(m)
					if m:GetAttribute("TargetOverride") == c.survivor.Name or m:GetAttribute("TargetOverride") == c.leader.Name then
						m:SetAttribute("TargetOverride", nil)
					end
				end
			end)
		end
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

-- The comeback: each remaining opponent reacts on its own
local function comeback()
	local s = custom.survivor
	custom.phase = "Comeback"
	custom.comebackKills = s:GetAttribute("MatchKills") or 0
	restoreJumps()
	setRole(s, nil)
	s:SetAttribute("TargetOverride", nil)
	SocialSystem.raiseEvent("UnexpectedLeaderDefeat", { text = s.Name .. " beat " .. custom.leader.Name })
	task.delay(1.5, function()
		if custom and custom.phase == "Comeback" then
			SocialSystem.raiseEvent("HonorableComeback", { text = s.Name })
		end
	end)
	local W = CFG.ComebackReactions or {}
	local kinds, total = {}, 0
	for k, w in pairs(W) do table.insert(kinds, { k, w }) total += w end
	local coordinatedGroup = {}
	for _, o in ipairs(custom.opponents) do
		if alive(o) and o ~= custom.leader then
			local r, kind = math.random() * total, "attack"
			for _, kw in ipairs(kinds) do
				r -= kw[2]
				if r <= 0 then kind = kw[1] break end
			end
			if kind == "finish" and hpRatio(s) > 0.35 then kind = "attack" end
			bump(stats.comebackReactions, kind)
			o:SetAttribute("ComebackReaction", kind)
			SocialSystem.lookAt(o, s, 1.5)
			setRole(o, "Watching") -- still standing back until its own moment
			local function release(delay)
				task.delay(delay, function()
					if custom and o.Parent and alive(o) then
						custom.released[o] = true
						setRole(o, nil)
						SocialSystem.clearMoveIntent(o)
					end
				end)
			end
			if kind == "attack" or kind == "finish" then release(0.5 + math.random())
			elseif kind == "hesitate" then release(rand({ 4, 8 }))
			elseif kind == "backAway" then
				local ro, rs = rootOf(o), rootOf(s)
				if ro and rs then SocialSystem.setMoveIntent(o, ro.Position + flat(ro.Position - rs.Position).Unit * 15, "walk", 4) end
				release(rand({ 6, 10 }))
			elseif kind == "avenge" then
				o:SetAttribute("GrudgeTarget", s.Name)
				release(1 + math.random())
			elseif kind == "coordinated" then
				table.insert(coordinatedGroup, o)
			else -- oneAtATime
				table.insert(custom.queue, o)
			end
		end
	end
	-- the coordinated ones look at each other, nod, and go together
	if #coordinatedGroup > 0 then
		for i, o in ipairs(coordinatedGroup) do
			local other = coordinatedGroup[(i % #coordinatedGroup) + 1]
			if other ~= o then SocialSystem.acknowledge(o, other, 0.6) end
		end
		task.delay(2.2, function()
			for _, o in ipairs(coordinatedGroup) do
				if custom and o.Parent and alive(o) then
					custom.released[o] = true
					setRole(o, nil)
				end
			end
		end)
	end
end

local function updateComeback()
	local s = custom.survivor
	-- one at a time: the next steps in when nobody else from the queue is fighting
	local busy = false
	for o in pairs(custom.released) do
		if o.Parent and alive(o) and o:GetAttribute("ComebackReaction") == "oneAtATime" then busy = true break end
	end
	if not busy and #custom.queue > 0 then
		local o = table.remove(custom.queue, 1)
		if alive(o) then
			custom.released[o] = true
			setRole(o, nil)
			SocialSystem.lookAt(o, s, 1)
		end
	end
	-- Big Clutch: the survivor keeps winning
	if not custom.bigClutch and (s:GetAttribute("MatchKills") or 0) >= custom.comebackKills + (CFG.BigClutchKills or 2) then
		custom.bigClutch = true
		SocialSystem.raiseEvent("BigClutch", { text = s.Name })
		-- the arena stops and stares: a beat of stillness, looks at each other, at the survivor
		local watchers = {}
		for _, o in ipairs(SocialSystem.fighters()) do
			if o ~= s and alive(o) then table.insert(watchers, o) end
		end
		for i, o in ipairs(watchers) do
			local wasRole = o:GetAttribute("RespectRole")
			setRole(o, "Watching")
			local other = watchers[(i % #watchers) + 1]
			if other ~= o then SocialSystem.lookAt(o, other, 0.9) end
			task.delay(1.0, function() SocialSystem.lookAt(o, s, 1.6) end)
			task.delay(CFG.StillnessTime or 2.5, function()
				if o.Parent and (custom == nil or custom.released[o]) then setRole(o, wasRole) end
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
		endCustom(c.phase == "Comeback" and "survivor fell after the comeback" or "leader won")
		return
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
						local dir = off.Magnitude > 1 and off.Unit or Vector3.new(1, 0, 0)
						SocialSystem.setMoveIntent(m, c.center + dir * (R + 6), "walk", 8)
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
		if c.walkInAt and now() >= c.walkInAt and not c.walking then
			c.walking = true
			local rl = rootOf(l)
			local dir = rl and flat(rl.Position - c.center) or Vector3.new(1, 0, 0)
			dir = dir.Magnitude > 1 and dir.Unit or Vector3.new(1, 0, 0)
			SocialSystem.setMoveIntent(l, c.center + dir * 12, "walk", 30)
			task.delay(1.2, function()
				if custom == c then
					SocialSystem.lookAt(s, l, 1.5)
					SocialSystem.setMoveIntent(s, c.center - dir * 12, "walk", 30)
				end
			end)
		end
		if c.walking then
			local near = flatDist(s, l) < (CFG.DuelStartDistance or 30)
				and flat(rootOf(s).Position - c.center).Magnitude < 40 and flat(rootOf(l).Position - c.center).Magnitude < 40
			if near or now() - c.walkInAt > (CFG.DuelStartTimeout or 30) then startDuel() end
		end
		-- spectators watch, now and then
		if math.random() < 0.2 then
			local list = c.opponents
			local o = list[math.random(1, #list)]
			if o and o ~= l and alive(o) then SocialSystem.lookAt(o, math.random() < 0.6 and s or l, 1.5 + math.random()) end
		end
	elseif c.phase == "Duel" then
		if not alive(l) then comeback() return end
		-- a duellist knocked or backed off the dais walks back up (the fight belongs on it)
		if c.platform then
			for _, m in ipairs({ s, l }) do
				local rm = rootOf(m)
				local off = rm and flat(rm.Position - c.center)
				if off and off.Magnitude > (CFG.CeremonyRadius or 80) and not m:GetAttribute("SocialMoveTo") then
					SocialSystem.setMoveIntent(m, c.center + off.Unit * (CFG.CeremonyRadius or 80) * 0.5, "jog", 4)
				end
			end
		end
		if math.random() < 0.3 then
			local o = c.opponents[math.random(1, #c.opponents)]
			if o and o ~= l and alive(o) then SocialSystem.lookAt(o, math.random() < 0.5 and s or l, 1.5 + math.random() * 1.5) end
		end
	elseif c.phase == "Comeback" then
		updateComeback()
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
			comebackReactions = stats.comebackReactions, afterClutch = stats.afterClutch,
			phase = custom and custom.phase or "none", thresholdMul = math.floor(thresholdMul * 100) / 100,
		}))
	end
end

local function reset()
	if custom then endCustom("match reset") end
	rec, lastHP = {}, {}
	matchStart = os.clock()
	thresholdMul = nil
	stats = { candidates = 0, accepted = 0, outcomes = {}, comebackReactions = {} }
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
