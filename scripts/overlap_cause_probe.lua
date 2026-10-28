--// overlap_cause_probe.lua
-- FIGHT_PROGRAMME.md step 1: what drives two fighting Quins into each other. Every Heartbeat, for
-- each Quin and its CurrentTarget: when their roots come under 3 studs an overlap episode starts
-- (it ends past 3.5). At the start it records which body was closing faster (the driver) and what
-- was moving it, and the time spent overlapped is put down to that cause.
-- Loaded as `return function(LABEL_, DURATION_) ... end`; result in Workspace OverlapProbe_<LABEL>.
--
-- What moved the driver (ImpulseModule's mover "ImpulseLV" on the root: its Priority attribute is
-- 1 for the body's own moves, 2 a flinch, 3 a knockback):
--   strike step-in    own move while Attacking
--   dash              own move within 0.6 s of LastDashTime
--   own slide         own move otherwise (spacing step back, slip, counter lunge, cornered counter)
--   pushed            a flinch or knockback carried it in
--   walking           no push: the Humanoid's own walk (Fight approach, Chase arriving, Circling)
--   drifting          neither closing at 3 studs/s or more

return function(LABEL_, DURATION_)
local LABEL = LABEL_ or "overlap"
local DURATION = DURATION_ or 120

local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local folder = Workspace:WaitForChild("QuinServer")

local episodes = {}   -- pair key -> open episode
local byCause = {}    -- cause -> { n, seconds, minDist sum }
local byDetail = {}   -- "cause | state | other state" -> n
local total = { n = 0, seconds = 0, bothDriving = 0 }

local function closing(root, otherRoot)
	local dir = otherRoot.Position - root.Position
	dir = Vector3.new(dir.X, 0, dir.Z)
	if dir.Magnitude < 0.01 then return 0 end
	return root.AssemblyLinearVelocity:Dot(dir.Unit)
end

local function causeOf(model, root, otherRoot, now)
	local mover = root:FindFirstChild("ImpulseLV")
	local prio = mover and mover:GetAttribute("Priority") or 0
	local moverSpeed = 0
	if mover then
		local dir = otherRoot.Position - root.Position
		dir = Vector3.new(dir.X, 0, dir.Z)
		moverSpeed = dir.Magnitude > 0.01 and mover.VectorVelocity:Dot(dir.Unit) or 0
	end
	if prio >= 2 and moverSpeed > 2 then return "pushed" end
	if prio == 1 and moverSpeed > 2 then
		if model:GetAttribute("Attacking") == true then return "strike step-in" end
		local dashAt = model:GetAttribute("LastDashTime")
		if dashAt and math.abs(now - dashAt) < 0.6 then return "dash" end
		return "own slide"
	end
	return "walking"
end

local function bump(t, k, n) t[k] = (t[k] or 0) + (n or 1) end

local t0 = os.clock()
local conn
conn = RunService.Heartbeat:Connect(function(dt)
	local now = os.clock()
	local tick = workspace:GetServerTimeNow()
	if now - t0 >= DURATION then
		conn:Disconnect()
		local s = { label = LABEL, seconds = math.floor(now - t0), episodes = total.n, overlapSeconds = math.floor(total.seconds * 10) / 10, bothDrivingPct = total.n > 0 and math.floor(1000 * total.bothDriving / total.n) / 10 or 0, byCause = {}, topDetails = {} }
		for cause, c in pairs(byCause) do
			s.byCause[cause] = { episodesPct = math.floor(1000 * c.n / math.max(total.n, 1)) / 10, timePct = math.floor(1000 * c.seconds / math.max(total.seconds, 1e-6)) / 10, minDistMean = c.closed > 0 and math.floor(100 * c.minSum / c.closed) / 100 or nil }
		end
		local list = {}
		for k, v in pairs(byDetail) do table.insert(list, { k = k, v = v }) end
		table.sort(list, function(a, b) return a.v > b.v end)
		for i = 1, math.min(12, #list) do s.topDetails[list[i].k] = list[i].v end
		Workspace:SetAttribute("OverlapProbe_" .. LABEL, HttpService:JSONEncode(s))
		return
	end
	local seen = {}
	for _, a in ipairs(folder:GetChildren()) do
		local tn = a:GetAttribute("CurrentTarget")
		local b = tn and folder:FindFirstChild(tn)
		local ra, rb = a:FindFirstChild("HumanoidRootPart"), b and b:FindFirstChild("HumanoidRootPart")
		local ha, hb = a:FindFirstChildOfClass("Humanoid"), b and b:FindFirstChildOfClass("Humanoid")
		if ra and rb and ha and hb and ha.Health > 0 and hb.Health > 0 then
			local key = a.Name < b.Name and a.Name .. "|" .. b.Name or b.Name .. "|" .. a.Name
			if not seen[key] then
				seen[key] = true
				local d = Vector3.new(rb.Position.X - ra.Position.X, 0, rb.Position.Z - ra.Position.Z).Magnitude
				local ep = episodes[key]
				if not ep and d < 3 and math.abs(rb.Position.Y - ra.Position.Y) < 4 then
					local ca, cb = closing(ra, rb), closing(rb, ra)
					local driver, other, dRoot, oRoot = a, b, ra, rb
					if cb > ca then driver, other, dRoot, oRoot = b, a, rb, ra end
					local cause = math.max(ca, cb) < 3 and "drifting" or causeOf(driver, dRoot, oRoot, tick)
					if ca > 5 and cb > 5 then total.bothDriving += 1 end
					ep = { cause = cause, minDist = d }
					episodes[key] = ep
					total.n += 1
					local c = byCause[cause] or { n = 0, seconds = 0, minSum = 0, closed = 0 }
					byCause[cause] = c
					c.n += 1
					bump(byDetail, cause .. " | " .. tostring(driver:GetAttribute("CurrentState")) .. (driver:GetAttribute("Attacking") and "+atk" or "") .. " -> " .. tostring(other:GetAttribute("CurrentState")) .. (other:GetAttribute("Attacking") and "+atk" or ""))
				end
				if ep then
					ep.minDist = math.min(ep.minDist, d)
					total.seconds += dt
					byCause[ep.cause].seconds += dt
					if d > 3.5 then
						byCause[ep.cause].minSum += ep.minDist
						byCause[ep.cause].closed += 1
						episodes[key] = nil
					end
				end
			end
		end
	end
end)

return "overlap probe started: " .. LABEL .. ", " .. DURATION .. " s"
end
