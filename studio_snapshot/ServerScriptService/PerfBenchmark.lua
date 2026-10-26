--// PerfBenchmark (ModuleScript)
-- Test mode "Performance Benchmark" (Quin Manager > TEST MODES): the same load every time, so each
-- performance change can be measured before and after (SKYLARK_PERFORMANCE_PLAN.md, step A).
--   - a 16v16 where nobody dies: while Workspace.BenchImmortal is set, DamageModule tops a target
--     up before each hit and this loop tops every Quin up 5 times a second (the fight stays a
--     full 32 the whole run);
--   - the stands full (CrowdAlwaysOn) unless the variant says not;
--   - two windows, in seconds from the start: START (0-12: spawn, dressing, countdown) and
--     STEADY (12-32: the fight). The server measures its own tick in both and publishes
--     Workspace.BenchServer (JSON); each client (StarterPlayerScripts.PerfBenchmarkClient) holds a
--     fixed camera, measures its frames over the same windows and shows the results.
-- Variants: "full" (crowd + clothes, the real match), "nocrowd", "noclothes", "bare" (neither).
-- After the run the Quins can die again and the crowd setting is put back.

local RunService = game:GetService("RunService")
local Stats = game:GetService("Stats")
local HttpService = game:GetService("HttpService")
local Workspace = game:GetService("Workspace")

local B = {}

B.START_WINDOW = 12
B.STEADY_WINDOW = 20
B.TEAM_SIZE = 16
B.VARIANTS = {
	full = { crowd = true, clothes = true },
	nocrowd = { crowd = false, clothes = true },
	noclothes = { crowd = true, clothes = false },
	bare = { crowd = false, clothes = false },
}

local runId = 0

local function topUp()
	local folder = Workspace:FindFirstChild("QuinServer")
	if not folder then
		return
	end
	for _, m in ipairs(folder:GetChildren()) do
		local hum = m:FindFirstChildOfClass("Humanoid")
		if hum and hum.Health > 0 and hum.Health < hum.MaxHealth then
			hum.Health = hum.MaxHealth
		end
	end
end

-- this server's tick over `seconds`: rate, frame times, Lua (heartbeat) and physics time
local function measure(seconds, id)
	local dts, hb, ph = {}, 0, 0
	local t0 = os.clock()
	while os.clock() - t0 < seconds and runId == id do
		local dt = RunService.Heartbeat:Wait()
		table.insert(dts, dt)
		hb += Stats.HeartbeatTimeMs
		ph += Stats.PhysicsStepTimeMs
	end
	local n = math.max(1, #dts)
	table.sort(dts)
	return {
		hz = math.floor(#dts / math.max(0.001, os.clock() - t0) + 0.5),
		p95 = math.floor((dts[math.max(1, math.floor(n * 0.95))] or 0) * 1000 + 0.5),
		worst = math.floor((dts[n] or 0) * 1000 + 0.5),
		heartbeatMs = math.floor(hb / n * 10 + 0.5) / 10,
		physicsMs = math.floor(ph / n * 10 + 0.5) / 10,
	}
end

-- startMatch: starts the 16v16 (GameModeManager.startTeamBattle)
function B.start(variant, startMatch)
	variant = B.VARIANTS[variant] and variant or "full"
	local v = B.VARIANTS[variant]
	runId += 1
	local id = runId
	local prevCrowd = Workspace:GetAttribute("BenchPrevCrowd")
	if prevCrowd == nil then
		prevCrowd = Workspace:GetAttribute("CrowdAlwaysOn") == true
		Workspace:SetAttribute("BenchPrevCrowd", prevCrowd)
	end
	Workspace:SetAttribute("BenchServer", nil)
	Workspace:SetAttribute("BenchImmortal", true)
	Workspace:SetAttribute("CrowdAlwaysOn", v.crowd)
	Workspace:SetAttribute("BenchVariant", variant)
	Workspace:SetAttribute("BenchRun", (Workspace:GetAttribute("BenchRun") or 0) + 1)
	Workspace:SetAttribute("BenchRunning", true)
	print(("[Benchmark] run %d: %s (%dv%d, crowd %s, clothes %s)"):format(
		Workspace:GetAttribute("BenchRun"), variant, B.TEAM_SIZE, B.TEAM_SIZE, tostring(v.crowd), tostring(v.clothes)))

	task.spawn(function()
		while runId == id and Workspace:GetAttribute("BenchImmortal") do
			topUp()
			task.wait(0.2)
		end
	end)
	task.spawn(startMatch, B.TEAM_SIZE)
	task.spawn(function()
		local startW = measure(B.START_WINDOW, id)
		local steadyW = measure(B.STEADY_WINDOW, id)
		if runId ~= id then
			return -- (a newer run took over)
		end
		local alive = 0
		local folder = Workspace:FindFirstChild("QuinServer")
		for _, m in ipairs(folder and folder:GetChildren() or {}) do
			local hum = m:FindFirstChildOfClass("Humanoid")
			if hum and hum.Health > 0 then
				alive += 1
			end
		end
		Workspace:SetAttribute("BenchServer", HttpService:JSONEncode({
			start = startW, steady = steadyW, alive = alive, variant = variant,
		}))
		print(("[Benchmark] server %s: start %d Hz (p95 %d ms), steady %d Hz (p95 %d ms, Lua %.1f ms, physics %.1f ms), %d Quins alive"):format(
			variant, startW.hz, startW.p95, steadyW.hz, steadyW.p95, steadyW.heartbeatMs, steadyW.physicsMs, alive))
		B.finish()
	end)
end

-- the end of a run: Quins can die again, the crowd setting is put back
function B.finish()
	runId += 1
	Workspace:SetAttribute("BenchImmortal", nil)
	Workspace:SetAttribute("BenchRunning", nil)
	local prev = Workspace:GetAttribute("BenchPrevCrowd")
	if prev ~= nil then
		Workspace:SetAttribute("CrowdAlwaysOn", prev or nil)
		Workspace:SetAttribute("BenchPrevCrowd", nil)
	end
end

return B
