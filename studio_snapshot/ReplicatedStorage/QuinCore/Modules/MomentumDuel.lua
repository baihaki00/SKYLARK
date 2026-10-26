--// MomentumDuel.lua
-- Step 2 of the momentum work: the duel brain. Two Quins going at each other with the momentum
-- moves (Modules/Momentum), each deciding for itself, beat by beat, from what it sees. Nothing is
-- a script: what happens comes out of two Quins reading each other.
--
-- How a duel starts: a Quin chasing an enemy 50-260 studs away, with energy and sight of it, may
-- open with a leap at it (more often the more aggressive and mobile it is).
-- What each one thinks about, every beat (its own reaction time, its personality, its energy):
--   it is dashing at me    dash first to meet it head on, sidestep it (on the ground), or brace
--   I am in the air        dash at the other (up to AirDashes per airtime), or fall and land
--   it is in the air       dash up at it, leap up after it, or let it come down (the state runs)
--   both on the ground     close and fight on foot (ends the duel), hop on, or leap at it again
-- A contact throws both apart; into a Quin on its feet it may become a fight on the ground (the
-- duel ends there); in the air it may start a brawl: a few quick small exchanges, each at its own
-- moment, before they fly apart.
-- Bursts and lulls: every contact takes some of the duel's intensity (it makes moves less likely);
-- between moves the Quins' own states run (chasing, circling). The duel ends when it has run out,
-- when one is out of energy or out of it, or when they are far apart.
--
-- Off switch: CombatConfig.MomentumDuel.Enabled = false (Momentum's moves stay).
-- Shared loop started from Server (MomentumDuel.start).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local QuinCore = ReplicatedStorage:WaitForChild("QuinCore")
local Modules = QuinCore:WaitForChild("Modules")
local CombatConfig = require(QuinCore:WaitForChild("CombatConfig"))
local SpatialModule = require(Modules:WaitForChild("SpatialModule"))
local Momentum = require(Modules:WaitForChild("Momentum"))

local MomentumDuel = {}

-- the states a Quin can be pulled out of into a move (between moves its state runs on)
local FREE_STATES = { Chase = true, Fight = true, Circling = true, Retreat = true, Idle = true }
-- states that keep a running duel alive (Recovery = the short pause after a landing; it never starts one)
local KEEP_STATES = { Recovery = true }

local duels = {} -- list of { a, b, started, contacts, maxContacts, intensity, brawl }
local mind = setmetatable({}, { __mode = "k" }) -- fighter -> { duel, other, nextThink, airDashes, reacted }
local stats = { started = 0, contacts = 0, brawls = 0, ground = 0, dashes = 0, leaps = 0, hops = 0, sidesteps = 0 }
local endings = {}

local function cfg(key, default)
	local t = CombatConfig.MomentumDuel
	local v = t and t[key]
	if v == nil then return default end
	return v
end

function MomentumDuel.enabled()
	return Momentum.enabled() and CombatConfig.MomentumDuel ~= nil and CombatConfig.MomentumDuel.Enabled ~= false
end

local function flat(v)
	return Vector3.new(v.X, 0, v.Z)
end

local function unitOr(v, fallback)
	return v.Magnitude > 1e-4 and v.Unit or fallback
end

local function rootOf(fighter)
	local humanoid = fighter and fighter.Parent and fighter:FindFirstChildOfClass("Humanoid")
	local root = fighter and fighter:FindFirstChild("HumanoidRootPart")
	if humanoid and root and humanoid.Health > 0 then return root end
	return nil
end

local function pers(fighter, key)
	return fighter:GetAttribute("Pers_" .. key) or 0.5
end

local function energy(fighter)
	return fighter:GetAttribute("Energy") or 100
end

local function spend(fighter, cost)
	fighter:SetAttribute("Energy", math.max(0, energy(fighter) - cost))
end

-- free for a move: alive, the Quin's own (not piloted), and in a state a move may take it from
-- (or in a move already)
local function capable(fighter)
	if not rootOf(fighter) or fighter:GetAttribute("PilotedBy") then return false end
	local st = fighter:GetAttribute("CurrentState") or ""
	return Momentum.busy(fighter) or FREE_STATES[st] == true or KEEP_STATES[st] == true
end

local function publish()
	local ends = {}
	for why, n in pairs(endings) do
		table.insert(ends, why .. " " .. n)
	end
	Workspace:SetAttribute("MomentumDuelStats", string.format("duels %d (%d now) | contacts %d, brawls %d, ground fights %d | dashes %d, leaps %d, hops %d, sidesteps %d | ended: %s",
		stats.started, #duels, stats.contacts, stats.brawls, stats.ground, stats.dashes, stats.leaps, stats.hops, stats.sidesteps, table.concat(ends, ", ")))
end

-- how long this Quin takes to answer what it sees (sharper when more aware)
local function reaction(fighter)
	local lo, hi = cfg("ReactMin", 0.12), cfg("ReactMax", 0.35)
	return (lo + math.random() * (hi - lo)) * (1 + (0.5 - pers(fighter, "Awareness")) * 0.6)
end

local function groundSpot(p)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { Workspace:FindFirstChild("argoniaonion") }
	local hit = Workspace:Raycast(Vector3.new(p.X, p.Y + 150, p.Z), Vector3.new(0, -600, 0), params)
	return hit and hit.Position or nil
end

-- ============================================================
-- Duels
-- ============================================================

local function endDuel(duel, why)
	for i, d in ipairs(duels) do
		if d == duel then
			table.remove(duels, i)
			break
		end
	end
	for _, f in ipairs({ duel.a, duel.b }) do
		if mind[f] and mind[f].duel == duel then mind[f] = nil end
		if f.Parent then
			f:SetAttribute("MomentumDuelWith", nil)
			f:SetAttribute("MomentumDuelAt", os.clock())
		end
	end
	endings[why] = (endings[why] or 0) + 1
	publish()
end

-- seconds a leap of this apex takes from one height to another (Momentum.leap's arc)
local function flightTime(fromY, toY, apex)
	local g = Workspace.Gravity
	local top = math.max(fromY, toY) + math.max(apex, 1)
	return math.sqrt(2 * (top - fromY) / g) + math.sqrt(2 * (top - toY) / g)
end

-- a leap at the other, aimed where it will be when this one comes down (audit 2026-10-27: aimed
-- at where it stood, 13 of 14 leaps that missed landed 40-140 studs away). In reach it comes
-- down at striking distance; from far it closes in and lands short.
local function leapAt(me, other, apexMin, apexMax)
	local root, oRoot = rootOf(me), rootOf(other)
	if not (root and oRoot) then return false end
	local apex = math.random(apexMin, apexMax)
	local lead = math.min(flightTime(root.Position.Y, oRoot.Position.Y, apex), cfg("LeapLeadMax", 1.5))
	local ahead = oRoot.Position + flat(oRoot.AssemblyLinearVelocity) * lead
	local gap = flat(ahead - root.Position)
	local dir = unitOr(gap, Vector3.zAxis)
	local reach = cfg("LeapReach", 160)
	local short = gap.Magnitude <= reach and math.random(cfg("LeapLandGapMin", 8), cfg("LeapLandGapMax", 16))
		or gap.Magnitude - reach * (math.random(80, 100) / 100)
	local side = Vector3.new(-dir.Z, 0, dir.X) * math.random(-cfg("LeapSide", 12), cfg("LeapSide", 12))
	local spot = groundSpot(root.Position + dir * math.max(gap.Magnitude - short, 0) + side)
	if not spot then return false end
	if Momentum.leap(me, spot, apex) then
		spend(me, cfg("LeapCost", 8))
		stats.leaps += 1
		return true
	end
	return false
end

-- can a dash catch it? (audit 2026-10-27: half the dashes flew out their time behind a target
-- moving away). Closing speed = dash speed less how fast it moves away.
local function canCatch(me, other)
	local root, oRoot = rootOf(me), rootOf(other)
	if not (root and oRoot) then return false end
	local mcfg = CombatConfig.Momentum or {}
	local speed = (mcfg.DashSpeed or CombatConfig.ProjectileJump_SlamSpeed or 480) * (Workspace:GetAttribute("GameSpeedMultiplier") or 1)
	local gap = oRoot.Position - root.Position
	local away = oRoot.AssemblyLinearVelocity:Dot(unitOr(gap, Vector3.zAxis))
	local closing = speed - away
	if closing < speed * cfg("DashMinClosing", 0.35) then return false end
	return gap.Magnitude / closing <= (mcfg.DashMaxTime or 1.2) * cfg("DashCatchShare", 0.85)
end

local function dashAt(me, other)
	if not canCatch(me, other) then return false end
	if Momentum.dash(me, other) then
		spend(me, cfg("DashCost", 10))
		stats.dashes += 1
		return true
	end
	return false
end

local function startDuel(a, b)
	local duel = {
		a = a, b = b, started = os.clock(), contacts = 0, brawl = 0, intensity = 1,
		maxContacts = math.random(cfg("ContactsMin", 2), cfg("ContactsMax", 7)),
	}
	table.insert(duels, duel)
	mind[a] = { duel = duel, other = b, nextThink = os.clock() + reaction(a), airDashes = 0 }
	mind[b] = { duel = duel, other = a, nextThink = os.clock() + reaction(b), airDashes = 0 }
	a:SetAttribute("MomentumDuelWith", b.Name)
	b:SetAttribute("MomentumDuelWith", a.Name)
	a:SetAttribute("MomentumDuelAt", os.clock())
	b:SetAttribute("MomentumDuelAt", os.clock())
	stats.started += 1
	leapAt(a, b, cfg("OpenerApexMin", 40), cfg("OpenerApexMax", 100))
	publish()
	return duel
end

-- A contact (Momentum asks how it goes): a brawl's small throws, a fight on the ground, or the
-- full throw apart
function MomentumDuel.contact(dasher, other)
	local m = mind[dasher]
	local duel = m and m.duel
	if not duel or m.other ~= other then return nil end
	duel.contacts += 1
	stats.contacts += 1
	duel.intensity *= math.random(cfg("FadeMin", 70), cfg("FadeMax", 92)) / 100
	local now = os.clock()
	local function rethink(quick)
		for _, f in ipairs({ dasher, other }) do
			local fm = mind[f]
			if fm then
				fm.nextThink = now + (quick and math.random(8, 20) / 100 or reaction(f))
				fm.reacted = nil
			end
		end
	end
	if duel.brawl > 0 then
		duel.brawl -= 1
		rethink(duel.brawl > 0)
		if duel.brawl > 0 then
			return { throw = cfg("BrawlThrow", 0.35), up = cfg("BrawlUp", 0.5) }
		end
		return nil
	end
	if not Momentum.inAir(other) and math.random() < cfg("GroundFightChance", 0.5) then
		stats.ground += 1
		duel.ended = "ground fight"
		return { ground = true }
	end
	if Momentum.inAir(dasher) and Momentum.inAir(other) and math.random() < cfg("BrawlChance", 0.3) then
		duel.brawl = math.random(cfg("BrawlMin", 2), cfg("BrawlMax", 4))
		stats.brawls += 1
		rethink(true)
		return { throw = cfg("BrawlThrow", 0.35), up = cfg("BrawlUp", 0.5) }
	end
	rethink(false)
	return nil
end

-- a choice made at a rate (per second) over the time since the last thought: how often a Quin
-- does it, not a coin flipped every beat (that was near certain within half a second)
local function roll(rate, dt)
	return math.random() < 1 - math.exp(-math.max(rate, 0) * dt)
end

-- One beat of one Quin's thinking (dt: seconds since its last one)
local function think(me, m, dt)
	local duel, other = m.duel, m.other
	local root, oRoot = rootOf(me), rootOf(other)
	if not (root and oRoot) then return end
	local kind = Momentum.kind(me)
	if kind == "dash" then return end
	if kind == "thrown" and Momentum.phaseAge(me) < cfg("ThrownRecover", 0.25) then return end
	local myAir, otherAir = Momentum.inAir(me), Momentum.inAir(other)
	if not myAir then m.airDashes = 0 end
	local d = (oRoot.Position - root.Position).Magnitude
	local want = duel.intensity * (duel.brawl > 0 and 2 or 1)
	local e = energy(me)
	local agg, dashPref, mob = pers(me, "Aggression"), pers(me, "DashPreference"), pers(me, "MobilityPreference")
	local dashCost = cfg("DashCost", 10)

	-- it is dashing at me
	if Momentum.targetOf(other) == me then
		if m.reacted then return end
		m.reacted = true
		local r = math.random()
		local meet = (cfg("MeetBase", 0.15) + cfg("MeetAggression", 0.45) * agg) * want
		if e >= dashCost and d > 15 and r < meet then
			dashAt(me, other)
		elseif not myAir and r < meet + cfg("SidestepChance", 0.35) then
			if Momentum.sidestep(me, oRoot.Position) then
				spend(me, cfg("HopCost", 3))
				stats.sidesteps += 1
			end
		end
		return
	end
	m.reacted = nil

	if myAir then
		-- (in a brawl the exchanges go on past the usual dashes per airtime)
		if (m.airDashes < cfg("AirDashes", 2) or duel.brawl > 0) and d > 12 and d < cfg("AirDashRange", 220) and e >= dashCost then
			local rate = (cfg("AirDashBase", 0.3) + cfg("AirDashPreference", 0.9) * dashPref) * want * (otherAir and 1.2 or 0.7)
			if roll(rate, dt) and dashAt(me, other) then
				m.airDashes += 1
			end
		end
		return
	end
	if Momentum.busy(me) then return end -- (a hop about to land)

	if otherAir then
		if d < cfg("GroundDashRange", 170) and e >= dashCost and roll((cfg("DashUpBase", 0.2) + cfg("DashUpAggression", 0.6) * agg) * want, dt) then
			dashAt(me, other)
		elseif e >= cfg("LeapCost", 8) and roll((cfg("LeapUpBase", 0.2) + cfg("LeapUpMobility", 0.6) * mob) * want, dt) then
			-- up after it, toward under where it is going
			local ahead = oRoot.Position + flat(oRoot.AssemblyLinearVelocity) * 0.5
			local spot = groundSpot(ahead)
			if spot and Momentum.leap(me, spot, math.clamp(oRoot.Position.Y - spot.Y, 15, 90)) then
				spend(me, cfg("LeapCost", 8))
				stats.leaps += 1
			end
		end
		return
	end

	-- both on the ground
	if d < cfg("GroundFightRange", 20) then
		duel.ended = duel.ended or "close: on foot"
		return
	end
	if d < 70 then
		if e >= cfg("HopCost", 3) and roll(cfg("HopMobility", 1.2) * mob * want, dt) and Momentum.hop(me, math.random(4, 9)) then
			spend(me, cfg("HopCost", 3))
			stats.hops += 1
		end
		return
	end
	if e >= cfg("LeapCost", 8) and roll((cfg("LeapAtBase", 0.15) + cfg("LeapAtMobility", 0.5) * mob) * want, dt) then
		leapAt(me, other, cfg("LeapApexMin", 25), cfg("LeapApexMax", 85))
	end
end

-- why this duel is over (nil: it goes on)
local function over(duel)
	if duel.ended then return duel.ended end
	local ra, rb = rootOf(duel.a), rootOf(duel.b)
	if not (ra and rb) then return "one is down" end
	for _, f in ipairs({ duel.a, duel.b }) do
		if not capable(f) then return "taken by " .. tostring(f:GetAttribute("CurrentState")) end
	end
	local onGround = not Momentum.inAir(duel.a) and not Momentum.inAir(duel.b)
	if (ra.Position - rb.Position).Magnitude > cfg("BreakDistance", 320) then return "too far" end
	if os.clock() - duel.started > cfg("MaxTime", 20) then return "time" end
	if onGround then
		if duel.contacts >= duel.maxContacts then return "enough" end
		if duel.intensity < cfg("MinIntensity", 0.3) then return "lull" end
		if energy(duel.a) < cfg("MinEnergy", 12) or energy(duel.b) < cfg("MinEnergy", 12) then return "tired" end
	end
	return nil
end

-- ============================================================
-- Openers and the loop
-- ============================================================

local function findTarget(fighter)
	local name = fighter:GetAttribute("CurrentTarget") or fighter:GetAttribute("TargetQuin")
	local folder = Workspace:FindFirstChild("QuinServer")
	return name and folder and folder:FindFirstChild(name) or nil
end

-- a teammate of q already fighting t on foot (audit 2026-10-27: 5 of 24 duels pulled an
-- enemy out of a teammate's fight)
local function allyFighting(q, t)
	local team = q:GetAttribute("Team")
	if not team then return false end
	for _, ally in ipairs(t.Parent:GetChildren()) do
		if ally ~= q and ally:GetAttribute("Team") == team and ally:GetAttribute("CurrentState") == "Fight"
			and ally:GetAttribute("CurrentTarget") == t.Name then
			return true
		end
	end
	return false
end

local function scanOpeners()
	if #duels >= cfg("MaxDuels", 3) then return end
	local folder = Workspace:FindFirstChild("QuinServer")
	if not folder then return end
	local now = os.clock()
	local boost = RunService:IsStudio() and Workspace:GetAttribute("MomentumDuelAlways") and 20 or 1
	for _, q in ipairs(folder:GetChildren()) do
		local s = q:GetAttribute("CurrentState")
		if (s == "Chase" or s == "Circling") and not mind[q] and capable(q) and not Momentum.busy(q)
			and now - (q:GetAttribute("MomentumDuelAt") or -1e9) > cfg("Cooldown", 10)
			and energy(q) >= cfg("OpenerMinEnergy", 45) then
			local t = findTarget(q)
			local root, tRoot = rootOf(q), t and rootOf(t)
			if tRoot and not mind[t] and capable(t) and not Momentum.busy(t) and not allyFighting(q, t)
				and now - (t:GetAttribute("MomentumDuelAt") or -1e9) > cfg("Cooldown", 10) * 0.5 then
				local d = (tRoot.Position - root.Position).Magnitude
				local chance = cfg("OpenerChance", 0.05) * (0.5 + pers(q, "Aggression")) * (0.5 + pers(q, "MobilityPreference")) * boost
				if d >= cfg("OpenerMinRange", 50) and d <= cfg("OpenerMaxRange", 260) and math.random() < chance
					and SpatialModule.checkLineOfSight(SpatialModule.getEyePosition(root), SpatialModule.getEyePosition(tRoot), { q, t }) then
					startDuel(q, t)
					if #duels >= cfg("MaxDuels", 3) then return end
				end
			end
		end
	end
end

function MomentumDuel.start()
	if MomentumDuel.started then return end
	MomentumDuel.started = true
	Momentum.contactHook = function(dasher, other)
		if not MomentumDuel.enabled() then return nil end
		return MomentumDuel.contact(dasher, other)
	end
	local lastScan = 0
	RunService.Heartbeat:Connect(function()
		if not MomentumDuel.enabled() then
			for i = #duels, 1, -1 do endDuel(duels[i], "switched off") end
			return
		end
		local now = os.clock()
		for i = #duels, 1, -1 do
			local duel = duels[i]
			local why = over(duel)
			if why then
				endDuel(duel, why)
			else
				for _, f in ipairs({ duel.a, duel.b }) do
					local m = mind[f]
					-- a dash coming at it: a reflex, sooner than its next thought
					if m and not m.reacted and not m.reflex and Momentum.targetOf(m.other) == f then
						m.reflex = true
						m.nextThink = math.min(m.nextThink, now + reaction(f) * cfg("ReflexShare", 0.5))
					elseif m and Momentum.targetOf(m.other) ~= f then
						m.reflex = nil
					end
					if m and now >= m.nextThink then
						m.nextThink = now + math.random(cfg("BeatMin", 12), cfg("BeatMax", 30)) / 100
						local dt = math.min(now - (m.lastThink or now - 0.2), 0.5)
						m.lastThink = now
						local ok, err = pcall(think, f, m, dt)
						if not ok then warn("[MomentumDuel] " .. tostring(err)) end
					end
				end
			end
		end
		if now - lastScan >= cfg("ScanInterval", 0.5) then
			lastScan = now
			scanOpeners()
		end
	end)
	if RunService:IsStudio() then
		-- Studio test: Workspace MomentumDuelDevCommand = "start" (two fighting enemies, set apart
		-- in the middle, start a duel), "reset" (stats). MomentumDuelAlways = true: openers x20.
		Workspace:GetAttributeChangedSignal("MomentumDuelDevCommand"):Connect(function()
			local cmd = Workspace:GetAttribute("MomentumDuelDevCommand")
			if cmd == nil or cmd == "" then return end
			Workspace:SetAttribute("MomentumDuelDevCommand", nil)
			if cmd == "reset" then
				stats = { started = 0, contacts = 0, brawls = 0, ground = 0, dashes = 0, leaps = 0, hops = 0, sidesteps = 0 }
				endings = {}
				publish()
			elseif cmd == "start" and MomentumDuel.enabled() then
				local a, b
				for _, q in ipairs(Workspace.QuinServer:GetChildren()) do
					if capable(q) and not mind[q] and FREE_STATES[q:GetAttribute("CurrentState") or ""] then
						if not a then a = q elseif q:GetAttribute("Team") ~= a:GetAttribute("Team") and not b then b = q end
					end
				end
				if a and b then
					local c = SpatialModule.getArenaBounds().center
					a.HumanoidRootPart.CFrame = CFrame.new(c + Vector3.new(-90, 15, 0))
					b.HumanoidRootPart.CFrame = CFrame.new(c + Vector3.new(90, 15, 0))
					Workspace:SetAttribute("MomentumDemoPair", a.Name .. " vs " .. b.Name)
					task.wait(0.8)
					startDuel(a, b)
				end
			end
		end)
	end
end

return MomentumDuel
