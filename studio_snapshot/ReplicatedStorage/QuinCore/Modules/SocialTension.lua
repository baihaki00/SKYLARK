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
local stats = { breaks = 0, maxLull = 0, restless = 0, waiting = 0, tension = 0 }

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
	for _, m in ipairs(fighters) do
		local team = m:GetAttribute("Team")
		if team and team ~= "" and not m:GetAttribute("IsCostume") then
			if not byTeam[team] then byTeam[team] = {} teams += 1 end
			table.insert(byTeam[team], m)
		end
		local h = humOf(m)
		if h then
			if lastHP[m] and h.Health < lastHP[m] then activity += (lastHP[m] - h.Health) / math.max(1, h.MaxHealth) end
			lastHP[m] = h.Health
		end
	end
	-- the respect custom has its own rhythm; one team left is no stalemate
	if teams < 2 or Workspace:GetAttribute("RespectCustomActive") then
		lull = 0
		for m in pairs(quins) do if m.Parent then clear(m) end end
		quins = {}
		return
	end

	-- the lull clock: thin fighting runs it, real fighting winds it back
	if activity > 0 then fightingSeen = true end
	if not fightingSeen then
		lull = 0
	elseif activity / math.max(dt, 1e-3) < (CFG.LullDamageRate or 0.03) then
		lull += dt * (crowdWatching() and (CFG.CrowdFactor or 1.35) or 1)
	else
		lull = math.max(0, lull - dt * (CFG.LullRecover or 3))
	end
	stats.maxLull = math.max(stats.maxLull, lull)
	local tension = math.clamp((lull - (CFG.LullGrace or 8)) / (CFG.LullFull or 25), 0, 1)
	stats.tension = tension
	if lull <= 0 then tenseRaised, brokeRaised = false, false end

	local share = teamStanding(byTeam)
	local restless, waiting = 0, 0
	for team, members in pairs(byTeam) do
		for _, m in ipairs(members) do
			local q = quins[m]
			if not q then
				local P = CFG.PatienceRange or { 0.2, 0.8 }
				local calm = 1 - (m:GetAttribute("Pers_Aggression") or 0.6)
				q = { u = 0, patience = math.clamp(P[1] + (P[2] - P[1]) * calm + (math.random() - 0.5) * 0.15, 0.05, 0.95) }
				quins[m] = q
			end
			if m:GetAttribute("RespectRole") then
				q.u, q.posture = 0, nil
			else
				-- the side that is ahead can wait longer; the side behind has to do something
				local patience = q.patience + ((share[team] or 0.5) - 0.5) * (CFG.AheadPatience or 0.5)
				local want = tension >= patience and 1 or 0
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
				elseif tension > (CFG.WaitFrom or 0.1) then
					posture = "Waiting"
				end
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
		}))
	end
end

local function reset()
	for m in pairs(quins) do if m.Parent then clear(m) end end
	quins, lastHP = {}, {}
	lull = 0
	fightingSeen = false
	tenseRaised, brokeRaised = false, false
	stats = { breaks = 0, maxLull = 0, restless = 0, waiting = 0, tension = 0 }
	Workspace:SetAttribute("TensionStats", nil)
end

SocialSystem.addTicker("Tension", tick, reset)

-- Studio test hook: Workspace attribute TensionDevCommand = "lull <seconds>" (sets the lull clock)
if game:GetService("RunService"):IsStudio() then
	Workspace:GetAttributeChangedSignal("TensionDevCommand"):Connect(function()
		local cmd = Workspace:GetAttribute("TensionDevCommand")
		if type(cmd) ~= "string" or cmd == "" then return end
		Workspace:SetAttribute("TensionDevCommand", nil)
		local verb, a = cmd:match("^(%S+)%s*(%S*)")
		if verb == "lull" then lull = tonumber(a) or 0 end
	end)
end

return SocialTension
