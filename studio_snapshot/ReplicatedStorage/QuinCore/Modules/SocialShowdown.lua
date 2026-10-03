--// SocialShowdown.lua
-- Leader showdowns, emergent (SocialSystem part). Nobody is paired: opposing pack leaders that
-- see each other for a while recognise each other as significant, and each pair decides once
-- what that means:
--   engage       both turn on each other
--   approach     one walks to the other, the other turns to meet it
--   refuse       one backs off and keeps fighting others (the other may still come)
--   ignore       a look, and both carry on
-- While two leaders fight, their trusting allies step in between ("you have to get through me")
-- and go for the challenger; others make space (they leave the pair alone) and glance over.
-- It ends when a leader goes down, they drift apart, or it runs too long.
--
-- Publishes: SocialDuel / SocialDuelUntil (a leader's showdown opponent), SocialAvoid /
-- SocialAvoidUntil (a duellist others leave alone), ShowdownRole (Duelist / Interceptor /
-- Watcher), Workspace ShowdownStats (JSON), and raises the arena event "LeaderShowdown".

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local QuinCore = ReplicatedStorage:WaitForChild("QuinCore")
local CombatConfig = require(QuinCore:WaitForChild("CombatConfig"))
local Modules = QuinCore:WaitForChild("Modules")
local SocialSystem = require(Modules:WaitForChild("SocialSystem"))
local SpatialModule = require(Modules:WaitForChild("SpatialModule"))

local CFG = (CombatConfig.Social or {}).Showdown or {}

local SocialShowdown = {}

local recognition = {}  -- pairKey -> seconds of mutual sight
local decidedAt = {}    -- pairKey -> when this pair last decided
local active = {}       -- list of { a, b, kind, since, apartSince }
local stats = { recognised = 0, outcomes = {}, intercepts = 0, spaceMakers = 0, ended = {} }

local function now() return os.clock() end
local function rootOf(m) return m and m:FindFirstChild("HumanoidRootPart") end
local function humOf(m) return m and m:FindFirstChildOfClass("Humanoid") end
local function alive(m) local h = humOf(m) return m and m.Parent and h and h.Health > 0 end
local function hpRatio(m) local h = humOf(m) return h and h.MaxHealth > 0 and h.Health / h.MaxHealth or 0 end
local function isDown(m)
	local s = m:GetAttribute("CurrentState")
	return s == "Knockback" or s == "Recovery" or s == "Airborne" or s == "ReEntry"
end
local function flatDist(a, b)
	local ra, rb = rootOf(a), rootOf(b)
	if not (ra and rb) then return math.huge end
	return Vector3.new(ra.Position.X - rb.Position.X, 0, ra.Position.Z - rb.Position.Z).Magnitude
end
local function pairKey(a, b)
	return a.Name < b.Name and (a.Name .. "|" .. b.Name) or (b.Name .. "|" .. a.Name)
end
local function bump(tbl, key) tbl[key] = (tbl[key] or 0) + 1 end
local function inShowdown(m)
	for _, s in ipairs(active) do
		if s.a == m or s.b == m then return s end
	end
	return nil
end

local function busy(m)
	return m:GetAttribute("CurrentState") == "Fight" and (m:GetAttribute("FocusCount") or 0) >= 2
end

-- ============================================================================
-- Starting and ending a showdown
-- ============================================================================

-- Target selection only scores enemies in the Quin's local awareness, so a duel is held through
-- TargetingModule's explicit override (TargetOverride) for as long as it lasts. (A +150 score
-- term alone left the two leaders on their old targets 24 s out of 24.)
local function setDuel(m, other, seconds)
	m:SetAttribute("SocialDuel", other.Name)
	m:SetAttribute("SocialDuelUntil", SocialSystem.now() + seconds)
	m:SetAttribute("ShowdownRole", "Duelist")
	m:SetAttribute("TargetOverride", other.Name)
end

local function releaseOverride(m, names)
	local cur = m:GetAttribute("TargetOverride")
	for _, n in ipairs(names) do
		if cur == n then m:SetAttribute("TargetOverride", nil) return end
	end
end

local function clearRole(m, opponent)
	if not m or not m.Parent then return end
	if m:GetAttribute("ShowdownRole") then m:SetAttribute("ShowdownRole", nil) end
	m:SetAttribute("SocialDuel", nil)
	m:SetAttribute("SocialDuelUntil", nil)
	if opponent then releaseOverride(m, { opponent.Name }) end
end

-- Allies around each duellist: the trusting ones step in, the rest make space
local function rally(showdown)
	local duration = CFG.MaxTime or 30
	for _, pairSide in ipairs({ { mine = showdown.a, theirs = showdown.b }, { mine = showdown.b, theirs = showdown.a } }) do
		local leader, challenger = pairSide.mine, pairSide.theirs
		local team = leader:GetAttribute("Team")
		for _, m in ipairs(SocialSystem.fighters()) do
			if m ~= leader and m ~= challenger and not m:GetAttribute("IsCostume") then
				local d = flatDist(m, leader)
				if m:GetAttribute("Team") == team and d < (CFG.InterceptRadius or 25) then
					local trust = SocialSystem.trustOf and SocialSystem.trustOf(m, leader.Name) or 0.5
					if trust >= (CFG.InterceptTrust or 0.55) and math.random() < (CFG.InterceptChance or 0.6) then
						-- "you want him? you go through me": step between, go for the challenger
						local rl, rc = rootOf(leader), rootOf(challenger)
						if rl and rc then
							local dir = Vector3.new(rc.Position.X - rl.Position.X, 0, rc.Position.Z - rl.Position.Z)
							if dir.Magnitude > 0.5 then
								SocialSystem.setMoveIntent(m, rl.Position + dir.Unit * math.min(8, dir.Magnitude * 0.5), "run", 3)
							end
						end
						m:SetAttribute("SocialFocus", challenger.Name)
						m:SetAttribute("SocialFocusUntil", SocialSystem.now() + duration)
						m:SetAttribute("ShowdownRole", "Interceptor")
						m:SetAttribute("TargetOverride", challenger.Name) -- (committed to the challenger)
						SocialSystem.lookAt(m, challenger, 1.2)
						showdown.helpers[m] = true
						stats.intercepts += 1
					end
				end
				if not showdown.helpers[m] and d < (CFG.SpaceRadius or 45) then
					-- making space: leave the two leaders to it, glance over now and then
					for _, duelist in ipairs({ showdown.a, showdown.b }) do
						if m:GetAttribute("Team") ~= duelist:GetAttribute("Team") then
							m:SetAttribute("SocialAvoid", duelist.Name)
							m:SetAttribute("SocialAvoidUntil", SocialSystem.now() + duration)
						end
					end
					if not m:GetAttribute("ShowdownRole") then m:SetAttribute("ShowdownRole", "Watcher") end
					showdown.helpers[m] = false
					stats.spaceMakers += 1
					task.delay(math.random() * 2, function()
						if m.Parent and showdown.a.Parent then
							SocialSystem.lookAt(m, math.random() < 0.5 and showdown.a or showdown.b, 1.0 + math.random())
						end
					end)
				end
			end
		end
	end
end

local function start(a, b, kind)
	local duration = CFG.MaxTime or 30
	local showdown = { a = a, b = b, kind = kind, since = now(), helpers = {} }
	table.insert(active, showdown)
	setDuel(a, b, duration)
	setDuel(b, a, duration)
	if kind == "approach" then
		-- a walks over; b turns to it and waits for it
		local ra, rb = rootOf(a), rootOf(b)
		if ra and rb then
			SocialSystem.setMoveIntent(a, rb.Position, "walk", 4)
		end
		SocialSystem.lookAt(b, a, 2.5)
		SocialSystem.nod(b, 1.0)
	else
		SocialSystem.acknowledge(a, b, 0.2)
		SocialSystem.acknowledge(b, a, 0.4)
	end
	rally(showdown)
	SocialSystem.raiseEvent("LeaderShowdown", { text = a.Name .. " vs " .. b.Name, a = a, b = b })
	print(string.format("[Social] Leader showdown (%s): %s vs %s", kind, a.Name, b.Name))
end

local function finish(index, reason)
	local s = active[index]
	table.remove(active, index)
	clearRole(s.a, s.b)
	clearRole(s.b, s.a)
	for m in pairs(s.helpers) do
		if m.Parent then
			releaseOverride(m, { s.a.Name, s.b.Name })
			if m:GetAttribute("ShowdownRole") then m:SetAttribute("ShowdownRole", nil) end
			m:SetAttribute("SocialAvoid", nil)
			m:SetAttribute("SocialAvoidUntil", nil)
		end
	end
	bump(stats.ended, reason)
	print(string.format("[Social] Leader showdown %s vs %s ends: %s", s.a.Name, s.b.Name, reason))
end

-- ============================================================================
-- Tick
-- ============================================================================

local function decide(a, b)
	-- weighted by how the two stand right now
	local credA, credB = a:GetAttribute("LeaderCred") or 0.5, b:GetAttribute("LeaderCred") or 0.5
	local hpA, hpB = hpRatio(a), hpRatio(b)
	local wEngage = (CFG.EngageWeight or 0.3) + (credA + credB) * 0.15 + math.min(hpA, hpB) * 0.2
	local wApproach = CFG.ApproachWeight or 0.25
	local wRefuse = (CFG.RefuseWeight or 0.15) + (1 - math.min(hpA, hpB)) * 0.4
	local wIgnore = (CFG.IgnoreWeight or 0.2) + ((busy(a) or busy(b)) and 0.35 or 0)
	local total = wEngage + wApproach + wRefuse + wIgnore
	local r = math.random() * total
	if r < wEngage then return "engage" end
	r -= wEngage
	if r < wApproach then return "approach" end
	r -= wApproach
	if r < wRefuse then return "refuse" end
	return "ignore"
end

local function tick(dt)
	if CFG.Enabled == false then return end
	local leaders = {}
	for _, m in ipairs(SocialSystem.fighters()) do
		if m:GetAttribute("SocialRole") == "Leader" and not isDown(m) then table.insert(leaders, m) end
	end

	-- ongoing showdowns
	for i = #active, 1, -1 do
		local s = active[i]
		local reason = nil
		if not alive(s.a) then reason = s.b.Name .. " won (" .. s.a.Name .. " fell)"
		elseif not alive(s.b) then reason = s.a.Name .. " won (" .. s.b.Name .. " fell)"
		elseif now() - s.since > (CFG.MaxTime or 30) then reason = "time"
		else
			if flatDist(s.a, s.b) > (CFG.BreakDistance or 120) then
				s.apartSince = s.apartSince or now()
				if now() - s.apartSince > 5 then reason = "drifted apart" end
			else
				s.apartSince = nil
			end
		end
		if reason then finish(i, reason) end
	end

	-- recognition between opposing leaders
	local seen = {}
	for i = 1, #leaders do
		for j = i + 1, #leaders do
			local a, b = leaders[i], leaders[j]
			if a:GetAttribute("Team") ~= b:GetAttribute("Team") then
				local key = pairKey(a, b)
				seen[key] = true
				local d = flatDist(a, b)
				local sees = d <= (CFG.RecognizeRange or 60) and SpatialModule.checkLineOfSight(
					SpatialModule.getEyePosition(rootOf(a)), SpatialModule.getEyePosition(rootOf(b)), { a, b })
				recognition[key] = math.max(0, (recognition[key] or 0) + (sees and dt or -dt))
				if recognition[key] >= (CFG.RecognizeTime or 2)
					and not inShowdown(a) and not inShowdown(b)
					and now() - (decidedAt[key] or -math.huge) >= (CFG.PairCooldown or 45)
					and #active < (CFG.MaxActive or 1) then
					decidedAt[key] = now()
					recognition[key] = 0
					stats.recognised += 1
					-- recognition: they look at each other first
					SocialSystem.lookAt(a, b, 1.5)
					SocialSystem.lookAt(b, a, 1.5)
					local outcome = decide(a, b)
					bump(stats.outcomes, outcome)
					if outcome == "engage" then
						start(a, b, "engage")
					elseif outcome == "approach" then
						-- the stronger one comes to the other
						if (a:GetAttribute("LeaderCred") or 0.5) + hpRatio(a) >= (b:GetAttribute("LeaderCred") or 0.5) + hpRatio(b) then
							start(a, b, "approach")
						else
							start(b, a, "approach")
						end
					elseif outcome == "refuse" then
						-- the weaker one backs off and turns back to other fights
						local refuser = hpRatio(a) <= hpRatio(b) and a or b
						local other = refuser == a and b or a
						local rr, ro = rootOf(refuser), rootOf(other)
						if rr and ro then
							local away = Vector3.new(rr.Position.X - ro.Position.X, 0, rr.Position.Z - ro.Position.Z)
							if away.Magnitude > 0.5 then
								SocialSystem.setMoveIntent(refuser, rr.Position + away.Unit * 15, "jog", 3)
							end
						end
						refuser:SetAttribute("SocialAvoid", other.Name)
						refuser:SetAttribute("SocialAvoidUntil", SocialSystem.now() + 10)
						print(string.format("[Social] %s refuses %s's challenge", refuser.Name, other.Name))
					end
				end
			end
		end
	end
	for key in pairs(recognition) do
		if not seen[key] then recognition[key] = nil end
	end

	if math.random() < 0.1 then
		Workspace:SetAttribute("ShowdownStats", HttpService:JSONEncode({
			recognised = stats.recognised, outcomes = stats.outcomes, intercepts = stats.intercepts,
			spaceMakers = stats.spaceMakers, ended = stats.ended, active = #active,
		}))
	end
end

local function reset()
	for i = #active, 1, -1 do finish(i, "match reset") end
	recognition, decidedAt, active = {}, {}, {}
	stats = { recognised = 0, outcomes = {}, intercepts = 0, spaceMakers = 0, ended = {} }
	Workspace:SetAttribute("ShowdownStats", nil)
end

-- Targeting: a duellist goes for its opponent; others leave a duellist they make space for
function SocialShowdown.targetScore(quin, candidate)
	local t = SocialSystem.now()
	local score = 0
	if quin:GetAttribute("SocialDuel") == candidate.Name and t < (quin:GetAttribute("SocialDuelUntil") or 0) then
		score += CFG.DuelScore or 150
	end
	if quin:GetAttribute("SocialAvoid") == candidate.Name and t < (quin:GetAttribute("SocialAvoidUntil") or 0) then
		score -= CFG.AvoidPenalty or 80
	end
	return score
end

SocialSystem.addTicker("Showdown", tick, reset)
SocialSystem.addTargetTerm(SocialShowdown.targetScore)

-- Studio test hook: Workspace attribute ShowdownDevCommand = "start <a> <b>" (forces a pair)
if game:GetService("RunService"):IsStudio() then
	Workspace:GetAttributeChangedSignal("ShowdownDevCommand"):Connect(function()
		local cmd = Workspace:GetAttribute("ShowdownDevCommand")
		if type(cmd) ~= "string" or cmd == "" then return end
		Workspace:SetAttribute("ShowdownDevCommand", nil)
		local verb, an, bn = cmd:match("^(%S+)%s*(%S*)%s*(%S*)")
		local folder = Workspace:FindFirstChild("QuinServer")
		local a, b = folder and folder:FindFirstChild(an), folder and folder:FindFirstChild(bn)
		if verb == "start" and a and b then start(a, b, "engage") end
	end)
end

return SocialShowdown
