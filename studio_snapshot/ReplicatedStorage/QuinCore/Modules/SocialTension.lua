--// SocialTension.lua
-- Lulls in the fighting (SocialSystem part).
--
-- Late in a big match both sides can drift into a chase-and-retreat that never closes: everyone
-- hurt, everyone careful. That stays, but it does not last for ever. The field keeps a lull clock
-- (how long the fighting has been thin). While it runs:
--   waiting   Quins hold their ground instead of running further off and watch the other side:
--             "you move first". The side that is ahead can afford to wait longer.
--   restless  one by one (aggressive ones first, sooner with a crowd in the stands) they have had
--             enough: a look at an ally, a nod, and it goes (SocialUrgency)
--   contagion allies near a Quin that goes go with it; the enemy it goes for answers it
-- Fighting that starts again winds the clock back and the urgency fades.
--
-- Quiet is not the only thing that wears on them (Pass 35). Late in a match hits keep landing
-- somewhere, yet nobody is finished off. Three more things press on a Quin:
--   drought   time since anyone last went down, counted faster the more hurt the field is
--   clock     the match is running out. The side that would lose on time (fewer alive, else
--             less health) feels it in full: stalling is losing. The side that would win can
--             afford to hold its ground and wait.
--   stalling  its own time spent avoiding the fight (retreating, holding a platform, circling):
--             the later it is, the faster that wears on it. "I cannot keep running."
-- A Quin goes when what presses on it outweighs its patience (SocialWhy says which it was).
--
-- Publishes: SocialUrgency (0-1: DecisionSystem retreats less and pursues more), SocialPosture
-- (Waiting / Restless), Workspace TensionStats; events StalemateTense, StalemateBroken (crowd).

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local QuinCore = ReplicatedStorage:WaitForChild("QuinCore")
local CombatConfig = require(QuinCore:WaitForChild("CombatConfig"))
local Modules = QuinCore:WaitForChild("Modules")
local SocialSystem = require(Modules:WaitForChild("SocialSystem"))

local CFG = (CombatConfig.Social or {}).Tension or {}

local SocialTension = {}

local lastHP = {}     -- model -> health last tick
local quins = {}      -- model -> { u, patience, posture }
local lull = 0        -- seconds of thin fighting (wound back when it picks up)
local tenseRaised, brokeRaised = false, false
local fightingSeen = false -- (the walk in before the first exchange is not a lull)
local drought = 0     -- seconds without a knockout, weighted by how hurt the field is
local fightStart = nil -- when the first exchange landed (the nominal match clock runs from it)
local devClockLeft = nil -- Studio hook: seconds left on the clock
local clockRaised = false
local stats = { breaks = 0, maxLull = 0, restless = 0, waiting = 0, tension = 0 }

-- Avoiding the fight, for the stall meter
local AVOIDING = { Retreat = true, Overwatch = true, Circling = true, Idle = true }

local function rootOf(m) return m:FindFirstChild("HumanoidRootPart") end
local function humOf(m) return m:FindFirstChildOfClass("Humanoid") end
local function flatDist(a, b)
	local ra, rb = rootOf(a), rootOf(b)
	if not (ra and rb) then return math.huge end
	return Vector3.new(ra.Position.X - rb.Position.X, 0, ra.Position.Z - rb.Position.Z).Magnitude
end

-- A crowd in the stands is watching (ArenaCrowdManager publishes its phase)
local function crowdWatching()
	return Workspace:GetAttribute("CrowdPhase") == "IN_GAME"
end

local function setAttr(m, key, value)
	if m:GetAttribute(key) ~= value then m:SetAttribute(key, value) end
end

local function clear(m)
	setAttr(m, "SocialUrgency", nil)
	setAttr(m, "SocialPosture", nil)
	setAttr(m, "SocialWhy", nil)
	setAttr(m, "SocialLastStand", nil)
end

-- How far ahead a team is: its share of the living fighters and of their health
local function teamStanding(byTeam)
	local totals, all = {}, 0
	for team, members in pairs(byTeam) do
		local v = 0
		for _, m in ipairs(members) do
			local h = humOf(m)
			v += 1 + (h and h.MaxHealth > 0 and h.Health / h.MaxHealth or 0)
		end
		totals[team] = v
		all += v
	end
	local share = {}
	for team, v in pairs(totals) do share[team] = all > 0 and v / all or 0.5 end
	return share
end

-- Who loses if time runs out now: the Arena counts fighters alive, then team health
-- (ArenaSystemOrchestrator decideWinner). Returns team -> how much of the clock it feels.
local function clockShares(byTeam)
	local keys, best, worst = {}, -math.huge, math.huge
	for team, members in pairs(byTeam) do
		local health = 0
		for _, m in ipairs(members) do
			local h = humOf(m)
			health += h and h.MaxHealth > 0 and h.Health / h.MaxHealth or 0
		end
		keys[team] = #members + health / 100 -- alive first, health breaks the tie
		best, worst = math.max(best, keys[team]), math.min(worst, keys[team])
	end
	local shares, behind = {}, nil
	local level = best - worst < 0.0005 -- same count, health within about 5% of one fighter
	for team, key in pairs(keys) do
		if level then
			shares[team] = CFG.ClockEvenShare or 0.6
		elseif key >= best then
			shares[team] = CFG.ClockAheadShare or 0.25
		else
			shares[team] = 1
			behind = team
		end
	end
	return shares, behind
end

-- How far the match clock has run into its last part (0 before ClockFrom, 1 at the end).
-- The Arena publishes its own clock (MatchEndsAt / MatchLength); other modes have a nominal one.
local function clockPressure(dt)
	local total, left
	local endsAt = Workspace:GetAttribute("MatchEndsAt")
	if devClockLeft then
		devClockLeft = math.max(0, devClockLeft - dt)
		total, left = CFG.NominalMatchTime or 300, devClockLeft
	elseif endsAt and endsAt - Workspace:GetServerTimeNow() > -5 then -- (older than that: left over from a match that was cut off)
		total, left = Workspace:GetAttribute("MatchLength") or 600, endsAt - Workspace:GetServerTimeNow()
	elseif fightStart then
		total = CFG.NominalMatchTime or 300
		left = total - (SocialSystem.now() - fightStart)
	else
		return 0
	end
	local from = CFG.ClockFrom or 0.6
	return math.clamp((1 - left / math.max(1, total) - from) / (1 - from), 0, 1)
end

-- It has had enough: a look at an ally, a nod, and it goes
local function makeMove(m, allies)
	local nearest, nd = nil, CFG.ContagionRadius or 45
	for _, a in ipairs(allies) do
		local d = flatDist(a, m)
		if a ~= m and d < nd then nearest, nd = a, d end
	end
	if nearest then SocialSystem.acknowledge(m, nearest) end
	task.delay(nearest and 0.9 or 0.2, function()
		if not m.Parent then return end
		local state = m:GetAttribute("CurrentState")
		if state == "Idle" or state == "Circling" or state == "Retreat" then
			m:SetAttribute("ForceState", "Chase")
		end
	end)
end

local function tick(dt)
	if CFG.Enabled == false then return end
	local fighters = SocialSystem.fighters()
	local byTeam, teams = {}, 0
	local activity = 0
	local living, healthSum = {}, 0
	for _, m in ipairs(fighters) do
		living[m] = true
		local team = m:GetAttribute("Team")
		if team and team ~= "" and not m:GetAttribute("IsCostume") then
			if not byTeam[team] then byTeam[team] = {} teams += 1 end
			table.insert(byTeam[team], m)
		end
		local h = humOf(m)
		if h then
			if lastHP[m] and h.Health < lastHP[m] then activity += (lastHP[m] - h.Health) / math.max(1, h.MaxHealth) end
			lastHP[m] = h.Health
			healthSum += h.Health / math.max(1, h.MaxHealth)
		end
	end
	-- (fighters() lists the living: one that was here last tick and is not now went down)
	local deaths = 0
	for m in pairs(lastHP) do
		if not living[m] then
			lastHP[m] = nil
			deaths += 1
		end
	end
	-- the respect custom has its own rhythm; one team left is no stalemate
	if teams < 2 or Workspace:GetAttribute("RespectCustomActive") then
		lull, drought = 0, 0
		for m in pairs(quins) do if m.Parent then clear(m) end end
		quins = {}
		return
	end

	-- the lull clock: thin fighting runs it, real fighting winds it back
	if activity > 0 and not fightingSeen then
		fightingSeen = true
		fightStart = SocialSystem.now()
	end
	if not fightingSeen then
		lull = 0
	elseif activity / math.max(dt, 1e-3) < (CFG.LullDamageRate or 0.03) then
		lull += dt * (crowdWatching() and (CFG.CrowdFactor or 1.35) or 1)
	else
		lull = math.max(0, lull - dt * (CFG.LullRecover or 3))
	end
	stats.maxLull = math.max(stats.maxLull, lull)
	local lullTension = math.clamp((lull - (CFG.LullGrace or 8)) / (CFG.LullFull or 25), 0, 1)

	-- the drought: nobody has gone down. It only weighs once the field is hurt (that is when
	-- they turn careful), and a knockout takes some of it away.
	local hurt = math.clamp(((CFG.KillHurtFrom or 0.45) - healthSum / math.max(1, #fighters)) / (CFG.KillHurtSpan or 0.2), 0, 1)
	if deaths > 0 then drought = math.max(0, drought - deaths * (CFG.KillRelief or 15)) end
	if fightingSeen then
		drought += dt * hurt * (crowdWatching() and (CFG.CrowdFactor or 1.35) or 1)
	end
	local droughtTension = math.clamp((drought - (CFG.KillGrace or 20)) / (CFG.KillFull or 30), 0, 1)

	local tension = math.max(lullTension, droughtTension)
	stats.tension = tension
	if tension <= 0 and lull <= 0 then tenseRaised, brokeRaised = false, false end

	local clock = clockPressure(dt)
	local clockShare, behind = clockShares(byTeam)
	local late = math.max(hurt, clock) -- how late in the match it is: avoiding wears on them faster
	if clock >= (CFG.ClockCrowdAt or 0.75) and not clockRaised then
		clockRaised = true
		SocialSystem.raiseEvent("ClockRunningOut", { text = behind and (behind .. " is running out of time") or "time is running out" })
	end

	local share = teamStanding(byTeam)
	local restless, waiting = 0, 0
	for team, members in pairs(byTeam) do
		for _, m in ipairs(members) do
			local q = quins[m]
			if not q then
				local P = CFG.PatienceRange or { 0.2, 0.8 }
				local calm = 1 - (m:GetAttribute("Pers_Aggression") or 0.6)
				q = { u = 0, stall = 0, patience = math.clamp(P[1] + (P[2] - P[1]) * calm + (math.random() - 0.5) * 0.15, 0.05, 0.95) }
				quins[m] = q
			end
			if m:GetAttribute("RespectRole") then
				q.u, q.posture = 0, nil
				setAttr(m, "SocialWhy", nil)
				setAttr(m, "SocialLastStand", nil)
			else
				-- the side that is ahead can wait longer; the side behind has to do something
				local patience = q.patience + ((share[team] or 0.5) - 0.5) * (CFG.AheadPatience or 0.5)

				-- its own stalling: fills while it avoids the fight, drains while it fights
				local state = m:GetAttribute("CurrentState")
				if AVOIDING[state] then
					q.stall = math.min(1, q.stall + dt * late / (CFG.StallFull or 15))
				else
					q.stall = math.max(0, q.stall - dt / ((CFG.StallDrain or 6) * (state == "Fight" and 1 or 2)))
				end

				-- what presses on it, and the heaviest of them (SocialWhy)
				local clockPart = clock * (clockShare[team] or 1)
				local stallPart = q.stall * (CFG.StallWeight or 0.5)
				local h = humOf(m)
				local futile = team == behind and clock > 0 and h and h.Health / math.max(1, h.MaxHealth) < (CFG.FutileHealth or 0.25)
				local pressure = tension + clockPart + stallPart + (futile and (CFG.FutilePush or 0.3) or 0)
				local why = futile and "Futile" or (lullTension >= droughtTension and "Lull" or "Drought")
				local heaviest = math.max(tension, clockPart, stallPart)
				if not futile and heaviest > 0 then
					if heaviest == clockPart then why = "Clock" elseif heaviest == stallPart then why = "Stall" end
				end
				local want = pressure >= patience and 1 or 0
				for _, o in ipairs(fighters) do
					local qo = quins[o]
					if o ~= m and qo and qo.posture == "Restless" then
						local d = flatDist(o, m)
						if o:GetAttribute("Team") == team then
							if d < (CFG.ContagionRadius or 45) then want = math.max(want, CFG.ContagionLevel or 0.75) end
						elseif d < (CFG.ResponseRadius or 60) and o:GetAttribute("CurrentTarget") == m.Name then
							want = math.max(want, CFG.ResponseLevel or 0.85)
						end
					end
				end
				local rate = want > q.u and (CFG.UrgencyRise or 0.6) or (CFG.UrgencyFall or 0.25)
				q.u = q.u + math.clamp(want - q.u, -rate * dt, rate * dt)
				local posture = nil
				if q.u >= 0.5 then
					posture = "Restless"
				elseif tension + clockPart > (CFG.WaitFrom or 0.1) then
					posture = "Waiting"
				end
				setAttr(m, "SocialWhy", posture and why or nil)
				-- It does not run (DecisionSystem's survival instinct is off) when there is nothing left
				-- to save itself for: nearly dead on the side losing on time, or time all but gone for
				-- its side; or when it has simply run enough (stall meter full) - then it turns and
				-- fights until that has worn off.
				local S = CFG.StallLastStand or { 0.9, 0.4 }
				if q.stall >= S[1] then q.ranEnough = true elseif q.stall < S[2] then q.ranEnough = false end
				setAttr(m, "SocialLastStand", (futile or q.ranEnough or clockPart >= (CFG.LastStandClock or 0.8)) or nil)
				if posture == "Restless" and q.posture ~= "Restless" then
					makeMove(m, members)
					if not brokeRaised and tension > 0 then
						brokeRaised = true
						stats.breaks += 1
						SocialSystem.raiseEvent("StalemateBroken", { text = m.Name .. " makes the first move" })
					end
				end
				q.posture = posture
			end
			setAttr(m, "SocialUrgency", q.u > 0.02 and math.floor(q.u * 20 + 0.5) / 20 or nil)
			setAttr(m, "SocialPosture", q.posture)
			if q.posture == "Restless" then restless += 1 elseif q.posture == "Waiting" then waiting += 1 end
		end
	end
	stats.restless, stats.waiting = restless, waiting
	if tension >= 0.5 and restless == 0 and not tenseRaised then
		tenseRaised = true
		SocialSystem.raiseEvent("StalemateTense", { text = "nobody wants to move first" })
	end
	if math.random() < 0.1 then
		Workspace:SetAttribute("TensionStats", HttpService:JSONEncode({
			lull = math.floor(lull * 10) / 10, tension = math.floor(tension * 100) / 100, restless = restless,
			waiting = waiting, breaks = stats.breaks, maxLull = math.floor(stats.maxLull),
			drought = math.floor(drought), hurt = math.floor(hurt * 100) / 100,
			clock = math.floor(clock * 100) / 100, behind = behind,
		}))
	end
end

local function reset()
	for m in pairs(quins) do if m.Parent then clear(m) end end
	quins, lastHP = {}, {}
	lull, drought = 0, 0
	fightingSeen, fightStart, devClockLeft = false, nil, nil
	tenseRaised, brokeRaised, clockRaised = false, false, false
	stats = { breaks = 0, maxLull = 0, restless = 0, waiting = 0, tension = 0 }
	Workspace:SetAttribute("TensionStats", nil)
end

SocialSystem.addTicker("Tension", tick, reset)

-- Studio test hook: Workspace attribute TensionDevCommand = "lull <seconds>" (sets the lull clock),
-- "nokill <seconds>" (sets the drought), "clock <seconds left>" (runs the match clock from there)
if game:GetService("RunService"):IsStudio() then
	Workspace:GetAttributeChangedSignal("TensionDevCommand"):Connect(function()
		local cmd = Workspace:GetAttribute("TensionDevCommand")
		if type(cmd) ~= "string" or cmd == "" then return end
		Workspace:SetAttribute("TensionDevCommand", nil)
		local verb, a = cmd:match("^(%S+)%s*(%S*)")
		if verb == "lull" then lull = tonumber(a) or 0 end
		if verb == "nokill" then drought = tonumber(a) or 0 end
		if verb == "clock" then devClockLeft = tonumber(a) end
	end)
end

return SocialTension
