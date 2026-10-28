--// fight_probe_server.lua
-- FIGHT_PROGRAMME.md step 0: the fight measures flow_probe.lua does not take. Runs on the Server
-- next to flow_probe.lua; records in the background and writes a JSON summary to Workspace
-- attribute FightProbe_<LABEL> (FightProbeStatus while it runs). Every later step re-runs it.
-- Loaded as `return function(LABEL_, DURATION_, MIN_ALIVE_) ... end` (see the audit for how).
--
-- Definitions:
--   strike        Attacking false -> true; its clip is the Attacks clip playing at that moment
--   repeat        the same clip as this Quin's own previous strike
--   pair          a Quin and its CurrentTarget, both alive; engaged within 20 studs (root to root)
--   overlap       engaged pair with roots under 3 studs (two 1.5-stud body radii: HitboxModule)
--   phrase        a pair's strikes (either side) with gaps of 1.2 s or less
--   fast / slow   engaged pair sample: fast = either over 18 studs/s, striking or in the air;
--                 slow = both under 6 studs/s, neither striking; else mid. A tempo switch is a
--                 change between fast and slow (mid does not count as either)
--   drift         how far the pair's midpoint wanders in a 10 s engaged window (its max distance
--                 from the window's start): a fight held in one ring is small
--   re-entry      an engaged pair that came apart past 12 studs for 1 s and closed under 8 again

return function(LABEL_, DURATION_, MIN_ALIVE_)
local LABEL = LABEL_ or "fight"
local DURATION = DURATION_ or 150
local MIN_ALIVE = MIN_ALIVE_ or 0

local Workspace = game:GetService("Workspace")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local AnimationConfig = require(ReplicatedStorage.QuinCore.AnimationConfig)

local folder = Workspace:WaitForChild("QuinServer")
local AIR_STATES = { Airborne = true, ProjectileJump = true, MidAirClash = true, WallRun = true }

-- asset id -> clip name, for every Attacks clip
local clipName = {}
local function walk(tbl, path)
	for k, v in pairs(tbl) do
		if type(v) == "table" then
			if type(v.id) == "string" and v.id ~= "" then
				clipName[v.id] = path .. k
			else
				walk(v, path .. k .. ".")
			end
		end
	end
end
walk(AnimationConfig.Registry.Attacks or {}, "")

local function bump(t, k, n) t[k] = (t[k] or 0) + (n or 1) end
local function median(list)
	if #list == 0 then return nil end
	table.sort(list)
	return list[math.ceil(#list / 2)]
end
local function pct(list, p)
	if #list == 0 then return nil end
	table.sort(list)
	return list[math.clamp(math.ceil(#list * p), 1, #list)]
end
local function share(n, d) return d > 0 and math.floor(1000 * n / d) / 10 or 0 end
local function r1(x) return x and math.floor(x * 10 + 0.5) / 10 or nil end

local strikes = { n = 0, repeats = 0, triples = 0, byClip = {}, kind = { punch = 0, kick = 0, other = 0 }, unknown = 0 }
local quin = {} -- model -> { last, prev, used = {clip=true}, count }
local pairs_ = {} -- "A|B" (sorted) -> pair record
local engagedSamples, overlapSamples, under48Samples = 0, 0, 0
local tempo = { fast = 0, slow = 0, mid = 0, switches = 0 }
local phrases, phraseStrikes, phraseGaps, drifts, midSpeeds = {}, {}, {}, {}, {}
local reentries, pairSeconds = 0, 0
local conns = {}

local function pairKey(a, b)
	if a.Name < b.Name then return a.Name .. "|" .. b.Name end
	return b.Name .. "|" .. a.Name
end

local function strikeClip(model)
	local hum = model:FindFirstChildOfClass("Humanoid")
	local animator = hum and hum:FindFirstChildOfClass("Animator")
	if not animator then return nil end
	local best, bestT = nil, math.huge
	for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
		local id = track.Animation and track.Animation.AnimationId
		local name = id and clipName[id]
		if name and track.TimePosition < bestT then
			best, bestT = name, track.TimePosition
		end
	end
	return best
end

local function onStrike(model, now)
	local clip = strikeClip(model)
	strikes.n += 1
	if not clip then
		strikes.unknown += 1
		clip = "?"
	end
	bump(strikes.byClip, clip)
	local kind = clip:find("Kick") and "kick" or clip:find("Punch") and "punch" or "other"
	strikes.kind[kind] += 1
	local q = quin[model] or { used = {}, count = 0 }
	quin[model] = q
	if q.last and q.last == clip then strikes.repeats += 1 end
	if q.last and q.prev and q.last == clip and q.prev == clip then strikes.triples += 1 end
	q.prev, q.last = q.last, clip
	q.used[clip] = true
	q.count += 1
	-- the phrase of the pair this strike belongs to
	local targetName = model:GetAttribute("CurrentTarget")
	local target = targetName and folder:FindFirstChild(targetName)
	if target then
		local p = pairs_[pairKey(model, target)]
		if p then
			if p.phraseLast and now - p.phraseLast <= 1.2 then
				p.phraseCount += 1
			else
				if p.phraseLast then
					table.insert(phrases, p.phraseLast - p.phraseStart)
					table.insert(phraseStrikes, p.phraseCount)
					table.insert(phraseGaps, now - p.phraseLast)
				end
				p.phraseStart, p.phraseCount = now, 1
			end
			p.phraseLast = now
		end
	end
end

local function watch(model)
	if conns[model] then return end
	conns[model] = model:GetAttributeChangedSignal("Attacking"):Connect(function()
		if model:GetAttribute("Attacking") == true then onStrike(model, os.clock()) end
	end)
end

task.spawn(function()
	local t0 = os.clock()
	for _, m in ipairs(folder:GetChildren()) do watch(m) end
	local added = folder.ChildAdded:Connect(watch)
	while os.clock() - t0 < DURATION do
		local now = os.clock()
		local alive = 0
		for _, m in ipairs(folder:GetChildren()) do
			local h = m:FindFirstChildOfClass("Humanoid")
			if h and h.Health > 0 then alive += 1 end
		end
		if alive < MIN_ALIVE then break end
		local seen = {}
		for _, a in ipairs(folder:GetChildren()) do
			local ha, ra = a:FindFirstChildOfClass("Humanoid"), a:FindFirstChild("HumanoidRootPart")
			local tn = a:GetAttribute("CurrentTarget")
			local b = tn and folder:FindFirstChild(tn)
			local hb, rb = b and b:FindFirstChildOfClass("Humanoid"), b and b:FindFirstChild("HumanoidRootPart")
			if ha and ra and hb and rb and ha.Health > 0 and hb.Health > 0 then
				local key = pairKey(a, b)
				if not seen[key] then
					seen[key] = true
					local p = pairs_[key]
					if not p then
						p = { apartFor = 0, apart = false }
						pairs_[key] = p
					end
					local d = (rb.Position - ra.Position).Magnitude
					local mid = (ra.Position + rb.Position) / 2
					-- re-entries
					if d > 12 then
						p.apartFor += 0.1
						if p.apartFor >= 1 then p.apart = true end
					else
						p.apartFor = 0
						if p.apart and d < 8 then
							reentries += 1
							p.apart = false
						end
					end
					if d < 20 then
						engagedSamples += 1
						pairSeconds += 0.1
						if d < 3 then overlapSamples += 1 end
						if d < 4.8 then under48Samples += 1 end
						-- tempo
						local va, vb = ra.AssemblyLinearVelocity, rb.AssemblyLinearVelocity
						local sa, sb = Vector3.new(va.X, 0, va.Z).Magnitude, Vector3.new(vb.X, 0, vb.Z).Magnitude
						local striking = a:GetAttribute("Attacking") == true or b:GetAttribute("Attacking") == true
						local air = AIR_STATES[a:GetAttribute("CurrentState") or ""] or AIR_STATES[b:GetAttribute("CurrentState") or ""]
						local t = (math.max(sa, sb) > 18 or striking or air) and "fast" or (sa < 6 and sb < 6) and "slow" or "mid"
						tempo[t] += 1
						if t ~= "mid" then
							if p.lastTempo and p.lastTempo ~= t then tempo.switches += 1 end
							p.lastTempo = t
						end
						-- drift and midpoint speed
						if p.lastMid then table.insert(midSpeeds, (mid - p.lastMid).Magnitude / 0.1) end
						p.lastMid = mid
						if not p.windowStart then
							p.windowStart, p.windowAt, p.windowMax = mid, now, 0
						end
						p.windowMax = math.max(p.windowMax, (mid - p.windowStart).Magnitude)
						if now - p.windowAt >= 10 then
							table.insert(drifts, p.windowMax)
							p.windowStart, p.windowAt, p.windowMax = mid, now, 0
						end
					else
						p.lastMid, p.windowStart = nil, nil
					end
				end
			end
		end
		Workspace:SetAttribute("FightProbeStatus", string.format("%s %.0f/%ds", LABEL, now - t0, DURATION))
		task.wait(0.1)
	end
	added:Disconnect()
	for _, c in pairs(conns) do c:Disconnect() end
	local elapsed = os.clock() - t0

	local s = { label = LABEL, seconds = math.floor(elapsed), seed = Workspace:GetAttribute("ArenaSeed") }
	s.strikes = strikes.n
	s.clipUnknownPct = share(strikes.unknown, strikes.n)
	s.repeatPct = share(strikes.repeats, strikes.n)
	s.threeInARowPct = share(strikes.triples, strikes.n)
	s.kindPct = { punch = share(strikes.kind.punch, strikes.n), kick = share(strikes.kind.kick, strikes.n), other = share(strikes.kind.other, strikes.n) }
	s.byClipPct = {}
	for k, v in pairs(strikes.byClip) do s.byClipPct[k] = share(v, strikes.n) end
	local usedShare = {}
	local clipCount = 0
	for _ in pairs(clipName) do clipCount += 1 end
	for _, q in pairs(quin) do
		if q.count >= 10 then
			local n = 0
			for _ in pairs(q.used) do n += 1 end
			table.insert(usedShare, n)
		end
	end
	s.clipsInConfig = clipCount
	s.clipsUsedPerQuinMedian = median(usedShare)
	s.overlapPctOfEngaged = share(overlapSamples, engagedSamples)
	s.under4_8PctOfEngaged = share(under48Samples, engagedSamples)
	local tt = tempo.fast + tempo.slow + tempo.mid
	s.tempoPct = { fast = share(tempo.fast, tt), slow = share(tempo.slow, tt), mid = share(tempo.mid, tt) }
	s.tempoSwitchesPerPairMin = pairSeconds > 0 and r1(tempo.switches / (pairSeconds / 60)) or 0
	s.phrases = #phrases
	s.phraseSecondsMedian = r1(median(phrases))
	s.phraseSecondsP90 = r1(pct(phrases, 0.9))
	s.phraseStrikesMedian = median(phraseStrikes)
	s.phraseGapSecondsMedian = r1(median(phraseGaps))
	s.driftStudsMedian = r1(median(drifts))
	s.driftStudsP90 = r1(pct(drifts, 0.9))
	s.pairMidSpeedMedian = r1(median(midSpeeds))
	s.reentriesPerPairMin = pairSeconds > 0 and math.floor(100 * reentries / (pairSeconds / 60)) / 100 or 0
	s.engagedPairMinutes = r1(pairSeconds / 60)
	Workspace:SetAttribute("FightProbe_" .. LABEL, HttpService:JSONEncode(s))
	Workspace:SetAttribute("FightProbeStatus", LABEL .. " done")
end)

return "fight probe (server) started: " .. LABEL .. ", " .. DURATION .. " s"
end
