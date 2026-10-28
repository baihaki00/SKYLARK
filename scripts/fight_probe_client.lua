--// fight_probe_client.lua
-- FIGHT_PROGRAMME.md step 0, the drawn half: how often limbs and bodies of two fighting Quins sit
-- inside each other on the bodies the player sees. QuinRenderMode "Direct" (the default) draws the
-- QuinServer models in place; "Ghost" draws clones in QuinGhost/<name>_Visual. Both are handled.
-- Pasted into an MCP execute_luau call on the Client; samples every 3rd rendered frame after the
-- draw (RenderPriority.Last) and writes JSON to the client's Workspace attribute
-- FightProbeClient_<LABEL>. Set LABEL / DURATION below.
--
-- Body shapes, from each ghost's own bones (so any rig size works):
--   torso   capsule from Hips to Neck, radius 0.30 x that spine length
--   head    sphere on Head, radius 0.22 x spine length
--   limbs   points: both hands, forearms (mid), feet, shins (mid)
-- A pair counts when the server says one targets the other and their roots are under 12 studs.
--   limbIn      a limb point of either inside the other's torso or head by 0.15 x spine or more
--   torsoIn     the two torso capsules overlap by 0.15 x spine or more
-- Depths are reported in studs.

local LABEL = "fight"
local DURATION = 150

local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")

local serverFolder = Workspace:WaitForChild("QuinServer", 10)

-- the body drawn for a server model: its ghost in Ghost mode, else the model itself
local function drawn(model)
	local ghostFolder = Workspace:FindFirstChild("QuinGhost")
	return ghostFolder and ghostFolder:FindFirstChild(model.Name .. "_Visual") or model
end

local LIMBS = { "LeftHand", "RightHand", "LeftFoot", "RightFoot" }
local MIDS = { { "LeftForeArm", "LeftHand" }, { "RightForeArm", "RightHand" }, { "LeftLeg", "LeftFoot" }, { "RightLeg", "RightFoot" } }

local boneCache = setmetatable({}, { __mode = "k" })
local function bones(ghost)
	local b = boneCache[ghost]
	if b then return b end
	b = {}
	for _, n in ipairs({ "Hips", "Neck", "Head", "LeftHand", "RightHand", "LeftFoot", "RightFoot", "LeftForeArm", "RightForeArm", "LeftLeg", "RightLeg" }) do
		b[n] = ghost:FindFirstChild("mixamorig:" .. n, true)
	end
	boneCache[ghost] = b
	return b
end

local function pos(bone) return bone.TransformedWorldCFrame.Position end

local function segPoint(p, a, b)
	local ab = b - a
	local t = ab:Dot(ab) > 1e-6 and math.clamp((p - a):Dot(ab) / ab:Dot(ab), 0, 1) or 0
	return a + ab * t
end

-- closest distance between segments a1-a2 and b1-b2 (sampled: good enough for a probe)
local function segSeg(a1, a2, b1, b2)
	local best = math.huge
	for i = 0, 8 do
		local p = a1:Lerp(a2, i / 8)
		best = math.min(best, (p - segPoint(p, b1, b2)).Magnitude)
	end
	return best
end

local function shape(ghost)
	local b = bones(ghost)
	if not (b.Hips and b.Neck and b.Head) then return nil end
	local hips, neck = pos(b.Hips), pos(b.Neck)
	local spine = (neck - hips).Magnitude
	if spine < 0.1 then return nil end
	local s = { hips = hips, neck = neck, head = pos(b.Head), spine = spine, rT = 0.30 * spine, rH = 0.22 * spine, points = {} }
	for _, n in ipairs(LIMBS) do
		if b[n] then table.insert(s.points, pos(b[n])) end
	end
	for _, m in ipairs(MIDS) do
		if b[m[1]] and b[m[2]] then table.insert(s.points, (pos(b[m[1]]) + pos(b[m[2]])) / 2) end
	end
	return s
end

-- deepest a limb point of `att` sits inside `def`'s torso or head (studs; <= 0: outside)
local function limbDepth(att, def)
	local deepest = -math.huge
	for _, p in ipairs(att.points) do
		deepest = math.max(deepest, def.rT - (p - segPoint(p, def.hips, def.neck)).Magnitude)
		deepest = math.max(deepest, def.rH - (p - def.head).Magnitude)
	end
	return deepest
end

local stats = { pairFrames = 0, limbIn = 0, torsoIn = 0, limbInStriking = 0, strikingFrames = 0, depths = {}, spine = {}, frames = 0, frameMs = {} }
local frame = 0
local t0 = os.clock()
local lastClock = os.clock()

local function sample()
	local now = os.clock()
	table.insert(stats.frameMs, (now - lastClock) * 1000)
	lastClock = now
	frame += 1
	if frame % 3 ~= 0 then return end
	stats.frames += 1
	local done = {}
	for _, a in ipairs(serverFolder:GetChildren()) do
		local tn = a:GetAttribute("CurrentTarget")
		local b = tn and serverFolder:FindFirstChild(tn)
		local ga = drawn(a)
		local gb = b and drawn(b)
		local ra, rb = a:FindFirstChild("HumanoidRootPart"), b and b:FindFirstChild("HumanoidRootPart")
		local key = b and (a.Name < b.Name and a.Name .. "|" .. b.Name or b.Name .. "|" .. a.Name)
		if ga and gb and ra and rb and not done[key] and (ra.Position - rb.Position).Magnitude < 12 then
			done[key] = true
			local sa, sb = shape(ga), shape(gb)
			if sa and sb then
				stats.pairFrames += 1
				table.insert(stats.spine, sa.spine)
				local tol = 0.15 * math.min(sa.spine, sb.spine)
				local depth = math.max(limbDepth(sa, sb), limbDepth(sb, sa))
				local striking = a:GetAttribute("Attacking") == true or b:GetAttribute("Attacking") == true
				if striking then stats.strikingFrames += 1 end
				if depth >= tol then
					stats.limbIn += 1
					if striking then stats.limbInStriking += 1 end
					table.insert(stats.depths, depth)
				end
				local torsoGap = segSeg(sa.hips, sa.neck, sb.hips, sb.neck) - (sa.rT + sb.rT)
				if -torsoGap >= tol then stats.torsoIn += 1 end
			end
		end
	end
end

local function finish()
	RunService:UnbindFromRenderStep("FightProbeClient")
	local function share(n, d) return d > 0 and math.floor(1000 * n / d) / 10 or 0 end
	local function med(list)
		if #list == 0 then return nil end
		table.sort(list)
		return math.floor(list[math.ceil(#list / 2)] * 100) / 100
	end
	local function p90(list)
		if #list == 0 then return nil end
		table.sort(list)
		return math.floor(list[math.ceil(#list * 0.9)] * 100) / 100
	end
	local s = {
		label = LABEL, seconds = math.floor(os.clock() - t0), sampledFrames = stats.frames,
		closePairFrames = stats.pairFrames,
		limbInPct = share(stats.limbIn, stats.pairFrames),
		limbInWhileStrikingPct = share(stats.limbInStriking, stats.strikingFrames),
		limbInWhileNotStrikingPct = share(stats.limbIn - stats.limbInStriking, stats.pairFrames - stats.strikingFrames),
		torsoInPct = share(stats.torsoIn, stats.pairFrames),
		limbDepthStudsMedian = med(stats.depths), limbDepthStudsP90 = p90(stats.depths),
		spineStudsMedian = med(stats.spine),
		clientFrameMsMedian = med(stats.frameMs), clientFrameMsP90 = p90(stats.frameMs),
	}
	Workspace:SetAttribute("FightProbeClient_" .. LABEL, HttpService:JSONEncode(s))
end

RunService:BindToRenderStep("FightProbeClient", Enum.RenderPriority.Last.Value, function()
	if os.clock() - t0 >= DURATION then
		finish()
		return
	end
	local ok, err = pcall(sample)
	if not ok then Workspace:SetAttribute("FightProbeClientError", tostring(err)) end
end)

return "fight probe (client) started: " .. LABEL .. ", " .. DURATION .. " s"
