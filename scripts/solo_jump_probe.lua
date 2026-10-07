-- Solo jump probe (Server, Player Solo match running). One jump through the PilotTestInput hook,
-- sampled every frame from the press until 1.2 s after touchdown:
--   t, root height above the takeoff, vertical speed, horizontal speed, Humanoid state,
--   the lowest foot's height above the ground under it, and the clips carrying the body.
-- Prints a row every SAMPLE_ seconds, and a summary (apex time, hang near the apex, flight,
-- when the Humanoid said it landed vs when the feet reached the ground).
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

local q
for _, m in ipairs(workspace.QuinServer:GetChildren()) do
	if m:GetAttribute("PilotedBy") then q = m end
end
if not q then return "no piloted quin" end
local root, hum = q.HumanoidRootPart, q.Humanoid
local animator = hum:FindFirstChildOfClass("Animator")

local function send(kind, a, b)
	workspace:SetAttribute("PilotTestInput", HttpService:JSONEncode({ kind = kind, a = a, b = b }))
end
local feet = {}
for _, d in ipairs(q:GetDescendants()) do
	if d:IsA("Bone") and (d.Name:match("LeftToeBase$") or d.Name:match("RightToeBase$") or d.Name:match("LeftFoot$") or d.Name:match("RightFoot$")) then
		table.insert(feet, d)
	end
end
local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Exclude
params.FilterDescendantsInstances = { workspace.QuinServer }
local function footClearance()
	local best = math.huge
	for _, b in ipairs(feet) do
		local p = b.TransformedWorldCFrame.Position
		local hit = workspace:Raycast(p + Vector3.new(0, 3, 0), Vector3.new(0, -60, 0), params)
		if hit then best = math.min(best, p.Y - hit.Position.Y) end
	end
	return best
end
local function clips()
	local list = {}
	for _, t in ipairs(animator:GetPlayingAnimationTracks()) do
		if t.WeightCurrent > 0.3 then
			table.insert(list, string.format("%s%.1f", (t.Animation and t.Animation.Name ~= "Animation" and t.Animation.Name) or t.Name, t.WeightCurrent))
		end
	end
	return table.concat(list, ",")
end

local pace = PACE_ -- nil: standing jump
local holdJump = HOLD_ or 0.5 -- seconds Space is held
local sample = SAMPLE_ or 0.05
-- stand still (or run up) first
if pace then
	local t0 = os.clock()
	while os.clock() - t0 < 1.2 do send("move", { 0, 0, -1 }, pace) task.wait(0.05) end
else
	send("move", { 0, 0, 0 }, "jog")
	task.wait(1.0)
end
local y0 = root.Position.Y
local restClear = footClearance()
local rows = {}
local t0 = os.clock()
send("action", "Jump")
local released, apexT, apexY, landT, feetT, leftT = false, nil, y0, nil, nil, nil
local lastRow = -1
local hang = 0
local landedAt
while true do
	local dt = RunService.Heartbeat:Wait()
	local t = os.clock() - t0
	if pace and math.floor(t / 0.05) ~= math.floor((t - dt) / 0.05) then send("move", { 0, 0, -1 }, pace) end
	if not released and t >= holdJump then send("action", "JumpRelease") released = true end
	local v = root.AssemblyLinearVelocity
	local y = root.Position.Y - y0
	local state = hum:GetState().Name
	local clear = footClearance() - restClear
	if not leftT and y > 0.3 then leftT = t end
	if y > apexY - y0 then apexY = root.Position.Y apexT = t end
	if leftT and math.abs(v.Y) < 8 and not landT then hang += dt end
	if leftT and not landT and (state == "Running" or state == "Landed") then landT = t end
	if leftT and t > 0.2 and not feetT and y < 0.5 and clear < 0.4 then feetT = t end
	if t - lastRow >= sample then
		lastRow = t
		table.insert(rows, string.format("%.2f y%+.1f vy%+.0f h%.0f %s feet%+.1f %s", t, y, v.Y, Vector3.new(v.X, 0, v.Z).Magnitude, state, clear, clips()))
	end
	if landT then landedAt = landedAt or t end
	if (landedAt and t - landedAt > 1.2) or t > 4 then break end
end
send("move", { 0, 0, 0 }, "jog")
local summary = string.format("apex %+.1f studs at %s s; time near the apex (|vy|<8) %.2f s; Humanoid landed at %s s; feet on the ground at %s s",
	apexY - y0, apexT and string.format("%.2f", apexT) or "?", hang, landT and string.format("%.2f", landT) or "never", feetT and string.format("%.2f", feetT) or "never")
return summary .. "\n" .. table.concat(rows, "\n")
