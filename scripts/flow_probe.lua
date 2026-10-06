--// flow_probe.lua
-- The Phase 0 measurement (QUIN_CREATURE_DESIGN.md, sections 7 and 8). Pasted whole into an MCP
-- execute_luau call on the Server while a match runs; it records in the background and writes a
-- JSON summary to Workspace attribute FlowProbe_<LABEL> (and FlowProbeStatus while it runs).
-- Every later phase re-runs this same file, so before and after are measured the same way.
--
-- Set LABEL and DURATION below before pasting. Sampling: every living Quin at 10 Hz.
--
-- Definitions (fixed-stud approximations of the design's bands until Reach exists):
--   engaged        its CurrentTarget is alive and within 20 studs
--   standing       engaged, under 3 studs/s, not attacking or guarding, in Fight/Circling/Idle:
--                  the "stop and decide" moment the design wants gone
--   action         strike start, dash, slide, air dash, wall run start, projectile jump start,
--                  guard raise, jump (Humanoid Jumping)
--   chain          actions between two standing moments of 0.4 s or more
--   band           target distance: contact < 8, beat < 20, closing < 60, far >= 60
--   in the air     FloorMaterial Air for more than 0.3 s and 4+ studs above the floor below
--   high ground    standing 3+ studs above the arena floor (on a platform or obstacle)
--   answer         a strike that starts within 0.6 s of its target's own strike, dash or guard
--   arena activity share of living Quins attacking, dashing, sliding or in the air (2 s windows)

local LABEL = "baseline16v16"
local DURATION = 240
local MIN_ALIVE = 0 -- stop early when fewer Quins than this are alive (1v1: 2, so the match end is not measured)

local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")

local folder = Workspace:WaitForChild("QuinServer")
local STANDING_STATES = { Fight = true, Circling = true, Idle = true }
local AIR_STATES = { Airborne = true, ProjectileJump = true, MidAirClash = true, WallRun = true }

local floorParams = RaycastParams.new()
floorParams.FilterType = Enum.RaycastFilterType.Exclude
floorParams.RespectCanCollide = true

local function arenaFloorY()
	local root = Workspace:FindFirstChild("argoniaonion")
	local ground = root and root:FindFirstChild("ArenaGround", true)
	return ground and (ground.Position.Y + ground.Size.Y / 2) or 0
end

local q = {}            -- model -> per-Quin record
local totals = {
	samples = 0, engaged = 0, standing = 0, air = 0, high = 0,
	stateTime = {}, bandTime = { contact = 0, beat = 0, closing = 0, far = 0, none = 0 },
	actions = {}, chains = {}, bandChanges = 0, airEntries = 0, wallRuns = 0,
	strikes = 0, strikeResult = {}, answers = 0, strikeSpeed = {},
	transitions = {}, knockdowns = 0, deaths = 0,
	activity = {}, heartbeat = {},
}

local function bump(t, k, n) t[k] = (t[k] or 0) + (n or 1) end

local function record(model)
	local r = q[model]
	if r then return r end
	r = {
		chain = 0, standingFor = 0, lastBand = nil, airFor = 0, inAir = false,
		lastAttacking = false, lastDash = model:GetAttribute("LastDashTime"),
		lastAirDash = model:GetAttribute("AirDashAt"), lastGuard = false,
		lastSlide = false, lastState = model:GetAttribute("CurrentState"), lastSeq = model:GetAttribute("StrikeSeq") or 0,
		lastActionAt = {}, pendingTransition = nil, jumping = false,
	}
	q[model] = r
	return r
end

local function action(model, r, kind, now)
	bump(totals.actions, kind)
	r.chain += 1
	r.lastActionAt[kind] = now
	r.lastAnyAction = now
end

local function median(list)
	if #list == 0 then return nil end
	table.sort(list)
	return list[math.ceil(#list / 2)]
end

local function summary(elapsed)
	local quinMinutes = math.max(totals.samples * 0.1 / 60, 1e-6)
	local s = {
		label = LABEL, seconds = math.floor(elapsed), seed = Workspace:GetAttribute("ArenaSeed"),
		quinMinutes = math.floor(quinMinutes * 10) / 10,
	}
	local function share(n, d) return d > 0 and math.floor(1000 * n / d) / 10 or 0 end
	s.statePct = {}
	for k, v in pairs(totals.stateTime) do s.statePct[k] = share(v, totals.samples) end
	s.bandPct = {}
	for k, v in pairs(totals.bandTime) do s.bandPct[k] = share(v, totals.samples) end
	s.engagedPct = share(totals.engaged, totals.samples)
	s.standingPctOfEngaged = share(totals.standing, totals.engaged)
	s.airPct = share(totals.air, totals.samples)
	s.highGroundPct = share(totals.high, totals.samples)
	s.actionsPerQuinMin = {}
	local actionTotal = 0
	for k, v in pairs(totals.actions) do
		s.actionsPerQuinMin[k] = math.floor(10 * v / quinMinutes) / 10
		actionTotal += v
	end
	local chainSum, chainCount, longChains = 0, #totals.chains, 0
	for _, c in ipairs(totals.chains) do
		chainSum += c
		if c >= 3 then longChains += 1 end
	end
	s.chainMean = chainCount > 0 and math.floor(100 * chainSum / chainCount) / 100 or 0
	s.chainsOf3PlusPct = share(longChains, chainCount)
	s.bandChangesPerQuinMin = math.floor(10 * totals.bandChanges / quinMinutes) / 10
	s.airEntriesPerQuinMin = math.floor(10 * totals.airEntries / quinMinutes) / 10
	s.wallRunsPerQuinMin = math.floor(10 * totals.wallRuns / quinMinutes) / 10
	s.strikes = totals.strikes
	s.strikeResultPct = {}
	local resolved = 0
	for _, v in pairs(totals.strikeResult) do resolved += v end
	for k, v in pairs(totals.strikeResult) do s.strikeResultPct[k] = share(v, resolved) end
	s.answerPct = share(totals.answers, totals.strikes)
	s.strikeStartSpeedMedian = median(totals.strikeSpeed)
	s.speedKeptMedian = {}
	for k, list in pairs(totals.transitions) do
		if #list >= 5 then s.speedKeptMedian[k] = math.floor(100 * median(list)) / 100 end
	end
	s.knockdownsPerQuinMin = math.floor(100 * totals.knockdowns / quinMinutes) / 100
	s.deaths = totals.deaths
	-- rhythm: arena activity per 2 s window; spread and how often it swings across its mean
	local act = totals.activity
	if #act >= 4 then
		local mean = 0
		for _, a in ipairs(act) do mean += a end
		mean /= #act
		local var, crossings = 0, 0
		for i, a in ipairs(act) do
			var += (a - mean) ^ 2
			if i > 1 and (act[i - 1] - mean) * (a - mean) < 0 then crossings += 1 end
		end
		s.activityMeanPct = math.floor(1000 * mean) / 10
		s.activityCv = mean > 0 and math.floor(100 * math.sqrt(var / #act) / mean) / 100 or 0
		s.activitySwingsPerMin = math.floor(10 * crossings / (#act * 2 / 60)) / 10
	end
	s.serverFrameMsMedian = median(totals.heartbeat)
	return s
end

task.spawn(function()
	local t0 = os.clock()
	local floorY = arenaFloorY()
	local hbConn = RunService.Heartbeat:Connect(function(dt)
		if #totals.heartbeat < 20000 then table.insert(totals.heartbeat, math.floor(dt * 10000) / 10) end
	end)
	local windowActive, windowSamples, windowStart = 0, 0, os.clock()

	while os.clock() - t0 < DURATION do
		local now = os.clock()
		local alive = 0
		for _, m in ipairs(folder:GetChildren()) do
			local h = m:FindFirstChildOfClass("Humanoid")
			if h and h.Health > 0 then alive += 1 end
		end
		if alive < MIN_ALIVE then break end
		for _, model in ipairs(folder:GetChildren()) do
			local hum = model:FindFirstChildOfClass("Humanoid")
			local root = model:FindFirstChild("HumanoidRootPart")
			if hum and root and hum.Health > 0 then
				local r = record(model)
				local state = model:GetAttribute("CurrentState") or "?"
				local v = root.AssemblyLinearVelocity
				local speed = Vector3.new(v.X, 0, v.Z).Magnitude
				totals.samples += 1
				bump(totals.stateTime, state)

				-- target and band
				local targetName = model:GetAttribute("CurrentTarget")
				local target = targetName and folder:FindFirstChild(targetName)
				local tRoot = target and target:FindFirstChild("HumanoidRootPart")
				local tHum = target and target:FindFirstChildOfClass("Humanoid")
				local band = "none"
				local dist
				if tRoot and tHum and tHum.Health > 0 then
					dist = (tRoot.Position - root.Position).Magnitude
					band = dist < 8 and "contact" or dist < 20 and "beat" or dist < 60 and "closing" or "far"
					-- (a band is only left 1.5 studs past its edge: a Quin hovering at 8 or 20
					-- studs flickered between two bands and counted dozens of changes a minute)
					local edges = { contact = { 0, 8 }, beat = { 8, 20 }, closing = { 20, 60 }, far = { 60, math.huge } }
					local held = r.lastBand and edges[r.lastBand]
					if held and dist >= held[1] - 1.5 and dist < held[2] + 1.5 then
						band = r.lastBand
					end
				end
				bump(totals.bandTime, band)
				if r.lastBand and band ~= r.lastBand and band ~= "none" and r.lastBand ~= "none" then
					totals.bandChanges += 1
				end
				r.lastBand = band

				-- actions
				local attacking = model:GetAttribute("Attacking") == true
				local guarding = model:GetAttribute("IsGuarding") == true
				local sliding = model:GetAttribute("LocomotionAction") == "Slide"
				local seq = model:GetAttribute("StrikeSeq") or 0
				if attacking and not r.lastAttacking then
					action(model, r, "strike", now)
					totals.strikes += 1
					table.insert(totals.strikeSpeed, math.floor(speed))
					-- an answer: within 0.6 s of its target's own strike, dash or guard
					local tr = target and q[target]
					if tr and tr.lastAnyAction and now - tr.lastAnyAction <= 0.6 then
						totals.answers += 1
					end
				end
				if seq ~= r.lastSeq then
					bump(totals.strikeResult, model:GetAttribute("StrikeResult") or "?")
					r.lastSeq = seq
				end
				local dashAt = model:GetAttribute("LastDashTime")
				if dashAt and dashAt ~= r.lastDash then action(model, r, "dash", now) end
				r.lastDash = dashAt
				local airDashAt = model:GetAttribute("AirDashAt")
				if airDashAt and airDashAt ~= r.lastAirDash then action(model, r, "airDash", now) end
				r.lastAirDash = airDashAt
				if guarding and not r.lastGuard then action(model, r, "guard", now) end
				if sliding and not r.lastSlide then action(model, r, "slide", now) end
				local jumping = hum:GetState() == Enum.HumanoidStateType.Jumping
				if jumping and not r.jumping then action(model, r, "jump", now) end
				r.jumping = jumping
				if state ~= r.lastState then
					if state == "WallRun" then action(model, r, "wallRun", now) totals.wallRuns += 1 end
					if state == "ProjectileJump" then action(model, r, "projectileJump", now) end
					if state == "Knockback" then totals.knockdowns += 1 end
					if state == "Death" then totals.deaths += 1 end
					-- speed kept across the transition: before vs 0.3 s after
					r.pendingTransition = { key = tostring(r.lastState) .. ">" .. state, before = speed, at = now }
				end
				if r.pendingTransition and now - r.pendingTransition.at >= 0.3 then
					local p = r.pendingTransition
					if p.before > 8 then
						totals.transitions[p.key] = totals.transitions[p.key] or {}
						table.insert(totals.transitions[p.key], speed / p.before)
					end
					r.pendingTransition = nil
				end
				r.lastState = state
				r.lastAttacking, r.lastGuard, r.lastSlide = attacking, guarding, sliding

				-- engaged / standing / chains
				local engaged = dist ~= nil and dist < 20
				if engaged then
					totals.engaged += 1
					local standing = speed < 3 and not attacking and not guarding and STANDING_STATES[state]
					if standing then
						totals.standing += 1
						r.standingFor += 0.1
						if r.standingFor >= 0.4 and r.chain > 0 then
							table.insert(totals.chains, r.chain)
							r.chain = 0
						end
					else
						r.standingFor = 0
					end
				end

				-- air and high ground
				local airborneNow = hum.FloorMaterial == Enum.Material.Air or AIR_STATES[state]
				if airborneNow then
					r.airFor += 0.1
					if r.airFor > 0.3 and not r.inAir then
						floorParams.FilterDescendantsInstances = { folder }
						local hit = Workspace:Raycast(root.Position, Vector3.new(0, -40, 0), floorParams)
						if not hit or root.Position.Y - hit.Position.Y > 4 + hum.HipHeight then
							r.inAir = true
							totals.airEntries += 1
						end
					end
				else
					r.airFor = 0
					r.inAir = false
				end
				if r.inAir then totals.air += 1 end
				local feetY = root.Position.Y - hum.HipHeight - root.Size.Y / 2
				if not airborneNow and feetY - floorY > 3 then totals.high += 1 end

				-- arena activity
				windowSamples += 1
				if attacking or sliding or r.inAir or (now - (r.lastActionAt.dash or -9)) < 0.5 then
					windowActive += 1
				end
			end
		end
		if os.clock() - windowStart >= 2 then
			table.insert(totals.activity, windowSamples > 0 and windowActive / windowSamples or 0)
			windowActive, windowSamples, windowStart = 0, 0, os.clock()
		end
		Workspace:SetAttribute("FlowProbeStatus", string.format("%s %.0f/%ds, %d Quins", LABEL, os.clock() - t0, DURATION, #folder:GetChildren()))
		task.wait(0.1)
	end
	hbConn:Disconnect()
	-- chains still open at the end
	for _, r in pairs(q) do
		if r.chain > 0 then table.insert(totals.chains, r.chain) end
	end
	Workspace:SetAttribute("FlowProbe_" .. LABEL, HttpService:JSONEncode(summary(os.clock() - t0)))
	Workspace:SetAttribute("FlowProbeStatus", LABEL .. " done")
end)

return "flow probe started: " .. LABEL .. ", " .. DURATION .. " s"
