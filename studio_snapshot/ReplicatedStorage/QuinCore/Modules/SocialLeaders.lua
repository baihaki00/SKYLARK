--// SocialLeaders.lua
-- Pack leaders: a temporary battlefield role, not a class (SocialSystem ticker).
--
-- * Standing: every Quin's battlefield record (kills, damage dealt, staying alive, allies
--   choosing to follow it). Nothing from personality.
-- * Leaders: a team gets up to Caps[size] leaders, but a slot only fills when a Quin's standing
--   clearly stands out from its team. A second leader must lead a different part of the field.
-- * Signals: a leader shows intent (attack its target / regroup on it / protect it) with a look
--   at its allies, a look at the target, a nod. Each nearby ally decides on its own whether to
--   follow, from its trust in this leader, the leader's credibility, its distance, its danger
--   and whether it is locked in its own fight. Refusing is visible: it looks at the leader,
--   back at its enemy, and keeps fighting. Witnesses react to the refusal.
-- * Reputation: each signal's outcome is judged a few seconds later and moves the leader's
--   credibility and each follower's trust. Leadership passes on when the leader falls, is
--   down too long, gives up (hurt and alone), loses its credibility, or is outshone.
--
-- Publishes: SocialRole ("Leader"), LeaderCred, FollowingLeader, LeaderTrust, LeaderSignal /
-- LeaderSignalAt, SocialFocus / SocialFocusUntil (an attack signal it chose to follow),
-- SocialGuard / SocialGuardUntil (protect), plus Workspace SocialStats (JSON telemetry).

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local QuinCore = ReplicatedStorage:WaitForChild("QuinCore")
local CombatConfig = require(QuinCore:WaitForChild("CombatConfig"))
local SocialSystem = require(QuinCore:WaitForChild("Modules"):WaitForChild("SocialSystem"))

local CFG = (CombatConfig.Social or {}).Leaders or {}

local SocialLeaders = {}

local leaders = {}      -- team -> { [model] = { since, cred, outshoneSince, downSince } }
local trust = {}        -- follower model -> { [leaderName] = 0..1 }
local followScore = {}  -- model -> accepted-signal count (social proof for standing)
local teamSize = {}     -- team -> largest alive count seen this match
local pending = {}      -- signals awaiting judgement
local lastSignal = {}   -- leader model -> time of its last signal
local lastHealth = {}   -- model -> health last tick (a hit cancels a walk)
local demotedAt = {}    -- model -> when it lost the role (it does not lead again straight away)
local nextElection = 0
local stats = { signals = {}, follow = 0, ignore = 0, witness = {}, transfers = {}, emerged = 0 }

local function now() return os.clock() end

local function rootOf(m) return m:FindFirstChild("HumanoidRootPart") end
local function humOf(m) return m:FindFirstChildOfClass("Humanoid") end
local function hpRatio(m)
	local h = humOf(m)
	return h and h.MaxHealth > 0 and h.Health / h.MaxHealth or 0
end
local function flatDist(a, b)
	local ra, rb = rootOf(a), rootOf(b)
	if not (ra and rb) then return math.huge end
	return Vector3.new(ra.Position.X - rb.Position.X, 0, ra.Position.Z - rb.Position.Z).Magnitude
end
local function find(name)
	local folder = Workspace:FindFirstChild("QuinServer")
	return name and name ~= "" and folder and folder:FindFirstChild(name) or nil
end
local function targetOf(m)
	return find(m:GetAttribute("TargetQuin") or m:GetAttribute("CurrentTarget"))
end
local function count(t) local n = 0 for _ in pairs(t) do n += 1 end return n end
local function bump(tbl, key) tbl[key] = (tbl[key] or 0) + 1 end

-- ============================================================================
-- Standing, trust
-- ============================================================================

function SocialLeaders.standing(m)
	local kills = m:GetAttribute("MatchKills") or 0
	local damage = m:GetAttribute("MatchDamageDealt") or 0
	return kills * (CFG.StandingPerKill or 1.0)
		+ damage / (CFG.StandingDamagePerPoint or 150)
		+ hpRatio(m) * (CFG.StandingHealthWeight or 0.6)
		+ (followScore[m] or 0) * (CFG.StandingPerFollow or 0.15)
		- (m:GetAttribute("MatchPenalty") or 0) -- (time off the arena floor, throwing a Quin out of the arena: ArenaTrespass)
end

function SocialLeaders.trustOf(follower, leaderName)
	local t = trust[follower]
	return (t and t[leaderName]) or (CFG.TrustStart or 0.5)
end

local function setTrust(follower, leaderName, value)
	trust[follower] = trust[follower] or {}
	trust[follower][leaderName] = math.clamp(value, 0, 1)
	if follower:GetAttribute("FollowingLeader") == leaderName then
		follower:SetAttribute("LeaderTrust", math.floor(trust[follower][leaderName] * 100) / 100)
	end
end

local function capFor(size)
	local cap = 0
	for _, entry in ipairs(CFG.Caps or {}) do
		if size >= entry[1] then cap = entry[2] end
	end
	return cap
end

local function isDown(m)
	local s = m:GetAttribute("CurrentState")
	return s == "Knockback" or s == "Recovery" or s == "Airborne" or s == "ReEntry"
end

-- ============================================================================
-- Leaders: emergence and transfer
-- ============================================================================

local function demote(team, m, reason)
	local entry = leaders[team] and leaders[team][m]
	if not entry then return end
	leaders[team][m] = nil
	demotedAt[m] = now()
	if m.Parent then
		m:SetAttribute("SocialRole", nil)
		m:SetAttribute("LeaderCred", nil)
		m:SetAttribute("LeaderSignal", nil)
	end
	table.insert(stats.transfers, reason)
	print(string.format("[Social] %s stops leading %s (%s)", m.Name, team, reason))
end

local function promote(team, m, standing)
	leaders[team] = leaders[team] or {}
	leaders[team][m] = { since = now(), cred = CFG.CredStart or 0.6 }
	m:SetAttribute("SocialRole", "Leader")
	m:SetAttribute("LeaderCred", CFG.CredStart or 0.6)
	stats.emerged += 1
	print(string.format("[Social] %s emerges as a leader of %s (standing %.2f)", m.Name, team, standing))
	-- allies close by notice: a look, sometimes a nod
	for _, ally in ipairs(SocialSystem.fighters()) do
		if ally ~= m and ally:GetAttribute("Team") == team and flatDist(ally, m) < (CFG.NoticeRadius or 40) and math.random() < 0.5 then
			task.delay(math.random() * 1.2, function()
				if math.random() < 0.5 then SocialSystem.acknowledge(ally, m) else SocialSystem.lookAt(ally, m, 1.0) end
			end)
		end
	end
end

local function elect(byTeam)
	for team, members in pairs(byTeam) do
		teamSize[team] = math.max(teamSize[team] or 0, #members)
		local cap = capFor(teamSize[team])
		leaders[team] = leaders[team] or {}
		local roster = leaders[team]

		-- current leaders: keep, or let go
		local standings, sum = {}, 0
		for _, m in ipairs(members) do
			standings[m] = SocialLeaders.standing(m)
			sum += standings[m]
		end
		local mean = #members > 0 and sum / #members or 0
		for m, entry in pairs(roster) do
			local reason = nil
			if not m.Parent or not humOf(m) or humOf(m).Health <= 0 then
				reason = "fell"
			elseif isDown(m) then
				entry.downSince = entry.downSince or now()
				if now() - entry.downSince > (CFG.DownTooLong or 5) then reason = "down too long" end
			else
				entry.downSince = nil
			end
			if not reason and entry.cred < (CFG.CredFloor or 0.25) then
				reason = "lost credibility"
			end
			if not reason and hpRatio(m) < (CFG.GiveUpHealth or 0.22) then
				local alone = true
				for _, ally in ipairs(members) do
					if ally ~= m and flatDist(ally, m) < (CFG.SignalRadius or 70) then alone = false break end
				end
				if alone then reason = "gave up (hurt and alone)" end
			end
			if not reason then
				-- outshone: another stands clearly higher for a while
				local best = nil
				for _, other in ipairs(members) do
					if not roster[other] and standings[other] > (standings[m] or 0) + (CFG.OutshineMargin or 1.5) then best = other break end
				end
				if best then
					entry.outshoneSince = entry.outshoneSince or now()
					if now() - entry.outshoneSince > (CFG.OutshineTime or 8) then reason = "outshone by " .. best.Name end
				else
					entry.outshoneSince = nil
				end
			end
			if reason then demote(team, m, reason) end
		end
		if cap <= 0 then
			for m in pairs(roster) do demote(team, m, "team too small") end
		end

		-- open slots: only a standout candidate, away from the other leaders
		local candidates = {}
		for _, m in ipairs(members) do
			if not roster[m] and not isDown(m) and hpRatio(m) > 0.35
				and now() - (demotedAt[m] or -math.huge) >= (CFG.ReemergeCooldown or 30) then
				table.insert(candidates, m)
			end
		end
		table.sort(candidates, function(a, b) return standings[a] > standings[b] end)
		for _, m in ipairs(candidates) do
			if count(roster) >= cap then break end
			local s = standings[m]
			if s >= (CFG.MinStanding or 2.0) and s >= mean + (CFG.StandoutMargin or 1.0) then
				local farEnough = true
				for other in pairs(roster) do
					if flatDist(other, m) < (CFG.LeaderSpacing or 60) then farEnough = false break end
				end
				if farEnough then promote(team, m, s) end
			end
		end

		-- followers: the nearest leader of the team within reach
		for _, m in ipairs(members) do
			if roster[m] then
				m:SetAttribute("FollowingLeader", nil)
				m:SetAttribute("LeaderTrust", nil)
			else
				local best, bestD = nil, CFG.FollowRadius or 120
				for leader in pairs(roster) do
					local d = flatDist(m, leader)
					if d < bestD then best, bestD = leader, d end
				end
				m:SetAttribute("FollowingLeader", best and best.Name or nil)
				m:SetAttribute("LeaderTrust", best and math.floor(SocialLeaders.trustOf(m, best.Name) * 100) / 100 or nil)
			end
		end
	end
end

-- ============================================================================
-- Signals: a leader shows intent, each ally decides
-- ============================================================================

local function respond(follower, leader, kind, info)
	local leaderName = leader.Name
	local t = SocialLeaders.trustOf(follower, leaderName)
	local cred = leaders[leader:GetAttribute("Team")] and leaders[leader:GetAttribute("Team")][leader] and leaders[leader:GetAttribute("Team")][leader].cred or 0.5
	local d = flatDist(follower, leader)
	local radius = CFG.SignalRadius or 70
	local engaged = follower:GetAttribute("CurrentState") == "Fight"
	local myTarget = targetOf(follower)
	if kind == "Attack" and myTarget == info.target then engaged = false end -- already on it
	local danger = math.min(1, (follower:GetAttribute("FocusCount") or 0) / 3) * 0.5 + (1 - hpRatio(follower)) * 0.5
	local p = t * (CFG.FollowTrustWeight or 0.6) + cred * (CFG.FollowCredWeight or 0.4)
		- (engaged and (CFG.FollowEngagedPenalty or 0.25) or 0)
		- danger * (CFG.FollowDangerPenalty or 0.3)
		- (d / radius) * (CFG.FollowDistancePenalty or 0.2)
	if t < (CFG.NeverFollowTrust or 0.2) then p = 0 end
	if kind == "Regroup" and engaged then p = 0 end -- a Quin in the middle of its fight does not walk off
	p = math.clamp(p, 0, 0.95)

	-- reaction time: quick when it trusts the leader
	local delay = (CFG.ReactMin or 0.3) + (1 - t) * ((CFG.ReactMax or 1.4) - (CFG.ReactMin or 0.3)) + math.random() * 0.3
	local follows = math.random() < p
	task.delay(delay, function()
		if not (follower.Parent and leader.Parent) then return end
		SocialSystem.lookAt(follower, leader, 0.8)
		if follows then
			stats.follow += 1
			followScore[leader] = (followScore[leader] or 0) + 1
			if math.random() < 0.5 then SocialSystem.nod(follower, 0.5) end
			if kind == "Attack" and info.target then
				follower:SetAttribute("SocialFocus", info.target.Name)
				follower:SetAttribute("SocialFocusUntil", SocialSystem.now() + (CFG.FocusTime or 8))
				task.delay(0.9, function() SocialSystem.lookAt(follower, info.target, 1.0) end)
			elseif kind == "Regroup" and info.point then
				local jitter = Vector3.new(math.random() * 16 - 8, 0, math.random() * 16 - 8)
				SocialSystem.setMoveIntent(follower, info.point + jitter, danger > 0.4 and "run" or "jog", CFG.RegroupTime or 5)
			elseif kind == "Protect" then
				follower:SetAttribute("SocialGuard", leaderName)
				follower:SetAttribute("SocialGuardUntil", SocialSystem.now() + (CFG.GuardTime or 10))
			end
			table.insert(info.followers, follower)
		else
			stats.ignore += 1
			table.insert(info.ignorers, follower)
			-- refusal: looks at the leader, then back at its own enemy, and keeps fighting
			if myTarget then
				task.delay(0.9, function() SocialSystem.lookAt(follower, myTarget, 1.0) end)
			end
			-- witnesses: allies close to the one who refused, not busy themselves
			for _, w in ipairs(SocialSystem.fighters()) do
				if w ~= follower and w ~= leader and w:GetAttribute("Team") == follower:GetAttribute("Team")
					and w:GetAttribute("CurrentState") ~= "Fight" and flatDist(w, follower) < (CFG.WitnessRadius or 30) then
					local r = math.random()
					task.delay(0.4 + math.random() * 0.8, function()
						if not (w.Parent and follower.Parent) then return end
						if r < 0.35 then
							SocialSystem.lookAt(w, follower, 1.2) -- a look at the one who refused
							bump(stats.witness, "look")
						elseif r < 0.55 and kind == "Attack" and info.target then
							SocialSystem.lookAt(w, leader, 0.8) -- follows the leader anyway
							w:SetAttribute("SocialFocus", info.target.Name)
							w:SetAttribute("SocialFocusUntil", SocialSystem.now() + (CFG.FocusTime or 8))
							bump(stats.witness, "followLeader")
						elseif r < 0.68 and myTarget then
							SocialSystem.lookAt(w, follower, 0.8) -- goes with the one who refused
							w:SetAttribute("SocialFocus", myTarget.Name)
							w:SetAttribute("SocialFocusUntil", SocialSystem.now() + (CFG.FocusTime or 8))
							followScore[follower] = (followScore[follower] or 0) + 0.5
							bump(stats.witness, "followRefuser")
						else
							bump(stats.witness, "ignore")
						end
					end)
				end
			end
		end
	end)
end

local function signal(leader, team, kind, info, members)
	lastSignal[leader] = now()
	leader:SetAttribute("LeaderSignal", kind .. (info.target and (":" .. info.target.Name) or ""))
	leader:SetAttribute("LeaderSignalAt", SocialSystem.now())
	bump(stats.signals, kind)
	info.kind, info.leader, info.team, info.at = kind, leader, team, now()
	info.followers, info.ignorers = {}, {}
	info.targetHealth0 = info.target and humOf(info.target) and humOf(info.target).Health or nil
	-- body language: a look round at the allies, a look at the target, a nod
	local nearest, nd = nil, math.huge
	for _, m in ipairs(members) do
		local d = flatDist(m, leader)
		if m ~= leader and d < nd then nearest, nd = m, d end
	end
	if nearest then SocialSystem.lookAt(leader, nearest, 0.7) end
	task.delay(0.7, function()
		if info.target then SocialSystem.lookAt(leader, info.target, 0.9) end
		SocialSystem.nod(leader, 0.3)
	end)
	for _, m in ipairs(members) do
		if m ~= leader and m:GetAttribute("FollowingLeader") == leader.Name and flatDist(m, leader) < (CFG.SignalRadius or 70) then
			info.aliveAtStart = (info.aliveAtStart or 0) + 1
			respond(m, leader, kind, info)
		end
	end
	table.insert(pending, info)
end

local function considerSignals(byTeam)
	for team, members in pairs(byTeam) do
		for leader, entry in pairs(leaders[team] or {}) do
			if leader.Parent and not isDown(leader) and now() - (lastSignal[leader] or 0) >= (CFG.SignalCooldown or 6) then
				local root = rootOf(leader)
				local nearAllies, nearEnemies, enemyCentroid = 0, 0, Vector3.zero
				for _, m in ipairs(SocialSystem.fighters()) do
					local d = flatDist(m, leader)
					if m ~= leader and d < (CFG.SignalRadius or 70) then
						if m:GetAttribute("Team") == team then
							nearAllies += 1
						elseif d < 40 then
							nearEnemies += 1
							enemyCentroid += rootOf(m).Position
						end
					end
				end
				if nearAllies > 0 and root then
					local target = targetOf(leader)
					if hpRatio(leader) < (CFG.ProtectHealth or 0.35) and nearEnemies > 0 then
						signal(leader, team, "Protect", {}, members)
					elseif nearEnemies >= nearAllies + 2 then
						local away = root.Position - enemyCentroid / nearEnemies
						away = Vector3.new(away.X, 0, away.Z)
						local point = root.Position + (away.Magnitude > 0.1 and away.Unit * 20 or Vector3.zero)
						signal(leader, team, "Regroup", { point = point }, members)
					elseif target and target:GetAttribute("Team") ~= team and (leader:GetAttribute("CurrentState") == "Fight" or leader:GetAttribute("CurrentState") == "Chase") then
						signal(leader, team, "Attack", { target = target }, members)
					end
				end
			end
		end
	end
end

-- ============================================================================
-- Reputation: judge each signal after a while
-- ============================================================================

local function judge()
	local keep = {}
	for _, info in ipairs(pending) do
		if now() - info.at < (CFG.JudgeAfter or 8) then
			table.insert(keep, info)
		else
			local deaths = 0
			for _, f in ipairs(info.followers) do
				if not f.Parent or not humOf(f) or humOf(f).Health <= 0 then deaths += 1 end
			end
			local good
			if info.kind == "Attack" then
				local th = info.target and humOf(info.target)
				local lost = info.targetHealth0 and th and (info.targetHealth0 - th.Health) / math.max(1, th.MaxHealth) or 1
				good = (not th or th.Health <= 0 or lost >= (CFG.AttackSuccessDamage or 0.25)) and deaths == 0
			else
				good = deaths == 0
			end
			local disaster = deaths >= 2
			local team = info.team
			-- an attack nobody followed says little about the leader's judgement
			local unheeded = info.kind == "Attack" and #info.followers == 0
			local entry = leaders[team] and leaders[team][info.leader]
			local dCred = disaster and -(CFG.CredDisaster or 0.15) or (good and (CFG.CredGain or 0.06) or -(CFG.CredLoss or 0.08))
			if unheeded then dCred = 0 end
			if entry then
				entry.cred = math.clamp(entry.cred + dCred, 0, 1)
				if info.leader.Parent then info.leader:SetAttribute("LeaderCred", math.floor(entry.cred * 100) / 100) end
			end
			local name = info.leader.Name
			for _, f in ipairs(info.followers) do
				if f.Parent then setTrust(f, name, SocialLeaders.trustOf(f, name) + (good and (CFG.TrustGain or 0.06) or -(CFG.TrustLoss or 0.08))) end
			end
			for _, f in ipairs(info.ignorers) do
				-- the ones who refused learn from how it went
				if f.Parent then setTrust(f, name, SocialLeaders.trustOf(f, name) + (good and 0.03 or -0.02)) end
			end
			bump(stats.signals, info.kind .. (unheeded and "Unheeded" or (disaster and "Disaster" or (good and "Good" or "Bad"))))
		end
	end
	pending = keep
end

-- ============================================================================
-- Targeting hook: what a followed signal adds to a candidate (TargetingModule term 13)
-- ============================================================================

function SocialLeaders.targetScore(quin, candidate)
	local score = 0
	local t = SocialSystem.now()
	if quin:GetAttribute("SocialFocus") == candidate.Name and t < (quin:GetAttribute("SocialFocusUntil") or 0) then
		score += CFG.FocusScore or 70
	end
	-- an enemy going for the leader it follows (or guards) is worth intercepting, the more the
	-- more it trusts that leader
	local leaderName = quin:GetAttribute("SocialGuard")
	local guarding = leaderName and t < (quin:GetAttribute("SocialGuardUntil") or 0)
	if not guarding then leaderName = quin:GetAttribute("FollowingLeader") end
	if leaderName then
		local candTarget = candidate:GetAttribute("TargetQuin") or candidate:GetAttribute("CurrentTarget")
		if candTarget == leaderName then
			local tr = SocialLeaders.trustOf(quin, leaderName)
			if guarding or tr >= (CFG.InterceptTrust or 0.65) then
				score += (CFG.InterceptScore or 45) * tr * (guarding and 1.3 or 1)
			end
		end
	end
	return score
end

-- ============================================================================
-- Tick
-- ============================================================================

local function publishStats()
	local out = { leaders = {}, signals = stats.signals, follow = stats.follow, ignore = stats.ignore,
		witness = stats.witness, emerged = stats.emerged, transfers = #stats.transfers, lastTransfers = {} }
	for team, roster in pairs(leaders) do
		local names = {}
		for m, e in pairs(roster) do table.insert(names, string.format("%s(%.2f)", m.Name, e.cred)) end
		out.leaders[team] = names
	end
	for i = math.max(1, #stats.transfers - 4), #stats.transfers do table.insert(out.lastTransfers, stats.transfers[i]) end
	Workspace:SetAttribute("SocialStats", HttpService:JSONEncode(out))
end

local function tick()
	if CFG.Enabled == false then return end
	local byTeam = {}
	for _, m in ipairs(SocialSystem.fighters()) do
		local team = m:GetAttribute("Team")
		if team and team ~= "" and not m:GetAttribute("IsCostume") then
			byTeam[team] = byTeam[team] or {}
			table.insert(byTeam[team], m)
		end
		-- a hit breaks a walk off (regrouping under fire is not a stroll)
		local h = humOf(m)
		if h then
			if lastHealth[m] and h.Health < lastHealth[m] - 1 and m:GetAttribute("SocialMoveTo") and SocialSystem.respectRole(m) == nil then
				SocialSystem.clearMoveIntent(m)
			end
			lastHealth[m] = h.Health
		end
	end
	if now() >= nextElection then
		nextElection = now() + (CFG.ElectionInterval or 2)
		elect(byTeam)
		publishStats()
	end
	considerSignals(byTeam)
	judge()
end

local function reset()
	for team, roster in pairs(leaders) do
		for m in pairs(roster) do
			if m.Parent then m:SetAttribute("SocialRole", nil) m:SetAttribute("LeaderCred", nil) end
		end
	end
	leaders, trust, followScore, teamSize, pending, lastSignal, lastHealth, demotedAt = {}, {}, {}, {}, {}, {}, {}, {}
	stats = { signals = {}, follow = 0, ignore = 0, witness = {}, transfers = {}, emerged = 0 }
	Workspace:SetAttribute("SocialStats", nil)
end

SocialSystem.addTicker("Leaders", tick, reset)
SocialSystem.leaderTargetScore = SocialLeaders.targetScore
SocialSystem.trustOf = SocialLeaders.trustOf
SocialSystem.standingOf = SocialLeaders.standing

return SocialLeaders
