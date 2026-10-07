-- Solo turning probe (Server, Player Solo match running). Drives the piloted Quin through the
-- PilotTestInput hook and measures how the run turns:
--   step turns: run straight, then the input swings by A degrees at once; the time for the
--               velocity and the facing to come within 10 degrees of it, and the slowest speed
--   sweep:      the input turns steadily at R degrees/s (a mouse sweep); the mean lag of the
--               velocity heading and of the facing behind the input
-- Returns a text report.
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

local q
for _, m in ipairs(workspace.QuinServer:GetChildren()) do
	if m:GetAttribute("PilotedBy") then q = m end
end
if not q then return "no piloted quin" end
local root = q.HumanoidRootPart

local function send(kind, a, b)
	workspace:SetAttribute("PilotTestInput", HttpService:JSONEncode({ kind = kind, a = a, b = b }))
end
local function dirOf(deg)
	local r = math.rad(deg)
	return { math.sin(r), 0, math.cos(r) }
end
local function yawOf(v)
	return math.deg(math.atan2(v.X, v.Z))
end
local function diff(a, b)
	return (a - b + 180) % 360 - 180
end
local function holdMove(deg, pace, seconds, onFrame)
	local t0 = os.clock()
	local lastSend = 0
	while os.clock() - t0 < seconds do
		local d = type(deg) == "function" and deg(os.clock() - t0) or deg
		if os.clock() - lastSend > 0.05 then
			send("move", dirOf(d), pace)
			lastSend = os.clock()
		end
		local dt = RunService.Heartbeat:Wait()
		if onFrame then onFrame(os.clock() - t0, d, dt) end
	end
end
local function home(base)
	send("move", { 0, 0, 0 }, "jog")
	task.wait(0.8)
	q:PivotTo(CFrame.new(base) * CFrame.Angles(0, 0, 0))
	task.wait(0.4)
end

local pace = PACE_ or "run"
local base = BASE_ or Vector3.new(0, root.Position.Y, -438 + 0)
local out = {}
for _, A in ipairs(ANGLES_ or { 30, 60, 90, 135 }) do
	home(base)
	holdMove(180, pace, 1.6) -- (180 deg: toward -Z)
	local target = 180 + A
	local vAt, fAt, minSpeed, startSpeed = nil, nil, math.huge, nil
	holdMove(target, pace, 1.4, function(t)
		local v = root.AssemblyLinearVelocity
		local flat = Vector3.new(v.X, 0, v.Z)
		startSpeed = startSpeed or flat.Magnitude
		minSpeed = math.min(minSpeed, flat.Magnitude)
		if not vAt and flat.Magnitude > 2 and math.abs(diff(yawOf(flat), target)) < 10 then vAt = t end
		local look = root.CFrame.LookVector
		if not fAt and math.abs(diff(yawOf(look), target)) < 10 then fAt = t end
	end)
	table.insert(out, string.format("step %3d deg (%s): velocity %s s, facing %s s, speed %.0f -> min %.0f",
		A, pace, vAt and string.format("%.2f", vAt) or "never", fAt and string.format("%.2f", fAt) or "never", startSpeed or 0, minSpeed))
end
for _, R in ipairs(RATES_ or { 90, 180, 360 }) do
	home(base)
	holdMove(180, pace, 1.2)
	local lagV, lagF, n, speedSum = 0, 0, 0, 0
	holdMove(function(t) return 180 + R * t end, pace, 2.0, function(t, d)
		if t < 0.5 then return end
		local v = root.AssemblyLinearVelocity
		local flat = Vector3.new(v.X, 0, v.Z)
		if flat.Magnitude > 2 then
			lagV += math.abs(diff(d, yawOf(flat)))
			lagF += math.abs(diff(d, yawOf(root.CFrame.LookVector)))
			speedSum += flat.Magnitude
			n += 1
		end
	end)
	table.insert(out, string.format("sweep %3d deg/s (%s): velocity lags %.0f deg, facing lags %.0f deg, speed %.0f",
		R, pace, lagV / math.max(n, 1), lagF / math.max(n, 1), speedSum / math.max(n, 1)))
end
send("move", { 0, 0, 0 }, "jog")
return table.concat(out, "\n")
