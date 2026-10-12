--[[
make_run_leap.lua: builds the "running long leap" clip (run -> one huge airborne stride with a
little running in the air -> run) from the Quins' own run cycle (Movement.Run), and saves it as
KeyframeSequences in ServerStorage.RBX_ANIMSAVES for the owner to open in the Animation Editor
and publish. Run in the Edit DataModel.

How it is made: the clip walks the run cycle's phase, from the run's own push-off pose to its own
foot-contact pose, one stride plus one full cycle later. In between, the legs and arms swing
further than the run (each bone's turn away from the cycle's average pose is scaled up: super
long strides), the phase lingers at the widest split (the hang), then cycles once quickly (running
in the air). It starts and ends on exact run frames, so it slots between run loops.

  RunLeapRight: pushes off the right foot, lands on the left
  RunLeapLeft:  the same half a run cycle later: pushes off the left, lands on the right
]]

local RUN_ID = "rbxassetid://109090784752055"
local FPS = 30
local LENGTH = 0.9          -- seconds
local SPLIT_PHASE = 0.10    -- run phase (s) of the widest split after the right push-off
-- run phases (s) of the foot contacts (the run's Footstep markers): the right push-off starts at
-- 0 and lands on the left contact; the left one starts half a cycle later, lands on the right
local LEFT_CONTACT, RIGHT_CONTACT = 0.167, 0.433
local AMP_HANG = 1.7        -- stride exaggeration at the hang
local AMP_AIR = 1.35        -- ... while running in the air

local ks = game:GetService("KeyframeSequenceProvider"):GetKeyframeSequenceAsync(RUN_ID)
local kfs = ks:GetKeyframes()
table.sort(kfs, function(a, b) return a.Time < b.Time end)
local CYCLE = kfs[#kfs].Time -- 0.467; the last keyframe equals the first

-- bone -> list of CFrames per run keyframe (the last one dropped: it repeats the first)
local track, order = {}, {}
for i = 1, #kfs - 1 do
	for _, p in ipairs(kfs[i]:GetDescendants()) do
		if p:IsA("Pose") then
			if not track[p.Name] then track[p.Name] = {}; table.insert(order, p.Name) end
			track[p.Name][i] = p.CFrame
		end
	end
end
local N = #kfs - 1
local step = CYCLE / N
-- a bone not keyed on a keyframe is between its neighbouring keys (cyclic)
for _, name in ipairs(order) do
	local c = track[name]
	for i = 1, N do
		if not c[i] then
			local a, b = i, i
			repeat a = (a - 2) % N + 1 until c[a] or a == i
			repeat b = b % N + 1 until c[b] or b == i
			local da, db = (i - a) % N, (b - i) % N
			c[i] = (c[a] and c[b] and da + db > 0) and c[a]:Lerp(c[b], da / (da + db)) or c[a] or c[b]
		end
	end
end
-- the pose tree to copy: the run keyframe that keys the most bones
local treeFrame, most = kfs[1], 0
for i = 1, N do
	local count = 0
	for _, d in ipairs(kfs[i]:GetDescendants()) do if d:IsA("Pose") then count += 1 end end
	if count > most then treeFrame, most = kfs[i], count end
end

local function sample(name, phase)
	local t = (phase % CYCLE) / step
	local i = math.floor(t)
	local a = t - i
	local c = track[name]
	return c[(i % N) + 1]:Lerp(c[((i + 1) % N) + 1], a)
end

-- the cycle's average pose per bone (rotation; position from the first frame)
local mean = {}
for _, name in ipairs(order) do
	local x, y, z, w = 0, 0, 0, 0
	local first
	for i = 1, N do
		local axis, angle = track[name][i]:ToAxisAngle()
		local s = math.sin(angle / 2)
		local q = { axis.X * s, axis.Y * s, axis.Z * s, math.cos(angle / 2) }
		if not first then first = q end
		if q[1] * first[1] + q[2] * first[2] + q[3] * first[3] + q[4] * first[4] < 0 then
			q = { -q[1], -q[2], -q[3], -q[4] }
		end
		x, y, z, w = x + q[1], y + q[2], z + q[3], w + q[4]
	end
	local len = math.sqrt(x * x + y * y + z * z + w * w)
	mean[name] = CFrame.new(0, 0, 0, x / len, y / len, z / len, w / len)
end

-- how much each bone's swing is scaled (legs and arms; the rest follows the run)
local GAIN = {
	UpLeg = 1, Leg = 0.5,          -- thighs fully, knees half
	Arm = 1, ForeArm = 0.6,        -- upper arms fully, elbows a little
}
local function gain(name, amp)
	local part = name:match("^mixamorig:[LR]%a-(%u%a+)$") -- LeftUpLeg -> UpLeg
	local share = part and GAIN[part]
	return share and 1 + (amp - 1) * share or 1
end

local function exaggerate(name, cf, g)
	if g == 1 then return cf end
	local m = mean[name]
	local rel = m:Inverse() * (cf - cf.Position)
	local axis, angle = rel:ToAxisAngle()
	return CFrame.new(cf.Position) * m * CFrame.fromAxisAngle(axis, angle * g)
end

local function smooth(a, b, t) -- eased 0..1 between a and b
	t = math.clamp((t - a) / (b - a), 0, 1)
	return t * t * (3 - 2 * t)
end

-- phase (from the push-off) and stride gain over the clip's time; p_end is where it lands
local function shape(t, p_end)
	local u = t / LENGTH
	local phase, amp
	if u < 0.14 then         -- push-off into the split
		local s = smooth(0, 0.14, u)
		phase = SPLIT_PHASE * s
		amp = 1 + (AMP_HANG - 1) * s
	elseif u < 0.47 then     -- the hang: lingers at the widest split
		local s = (u - 0.14) / 0.33
		phase = SPLIT_PHASE + 0.03 * s
		amp = AMP_HANG
	elseif u < 0.83 then     -- running in the air: one quick cycle, back to the split
		local s = smooth(0.47, 0.83, u)
		phase = SPLIT_PHASE + 0.03 + (CYCLE - 0.03) * s
		amp = AMP_HANG + (AMP_AIR - AMP_HANG) * s
	else                     -- touchdown into the run's contact pose
		local s = smooth(0.83, 1, u)
		phase = SPLIT_PHASE + CYCLE + (p_end - SPLIT_PHASE - CYCLE) * s
		amp = AMP_AIR + (1 - AMP_AIR) * s
	end
	return phase, amp
end

local function build(label, offset, contact)
	local p_end = (contact - offset) % CYCLE + CYCLE
	local seq = Instance.new("KeyframeSequence")
	seq.Name = label
	seq.Loop = false
	seq.Priority = Enum.AnimationPriority.Action2
	local frames = math.floor(LENGTH * FPS + 0.5)
	for f = 0, frames do
		local t = f / FPS
		local phase, amp = shape(t, p_end)
		local kf = Instance.new("Keyframe")
		kf.Time = t
		-- the pose tree, same shape as the run's
		local function copy(srcPose, parent)
			local p = Instance.new("Pose")
			p.Name = srcPose.Name
			p.Weight = srcPose.Weight
			p.EasingStyle = Enum.PoseEasingStyle.Linear
			if track[srcPose.Name] then
				p.CFrame = exaggerate(srcPose.Name, sample(srcPose.Name, phase + offset), gain(srcPose.Name, amp))
			else
				p.CFrame = srcPose.CFrame
			end
			p.Parent = parent
			for _, c in ipairs(srcPose:GetChildren()) do
				if c:IsA("Pose") then copy(c, p) end
			end
		end
		for _, c in ipairs(treeFrame:GetChildren()) do
			if c:IsA("Pose") then copy(c, kf) end
		end
		if f == 2 then
			local m = Instance.new("KeyframeMarker"); m.Name = "Jump"; m.Value = ""; kf:AddMarker(m)
		end
		if f == frames then
			local m = Instance.new("KeyframeMarker"); m.Name = "Footstep"; m.Value = ""; kf:AddMarker(m)
		end
		kf.Parent = seq
	end
	return seq
end

local saves = game:GetService("ServerStorage"):FindFirstChild("RBX_ANIMSAVES")
if not saves then
	saves = Instance.new("Model"); saves.Name = "RBX_ANIMSAVES"; saves.Parent = game:GetService("ServerStorage")
end
local rigName = "QUINTESTMALE"
local folder = saves:FindFirstChild(rigName)
if not folder then folder = Instance.new("ObjectValue"); folder.Name = rigName; folder.Parent = saves end
local made = {}
for _, spec in ipairs({ { "RunLeapRight", 0, LEFT_CONTACT }, { "RunLeapLeft", CYCLE / 2, RIGHT_CONTACT } }) do
	local old = folder:FindFirstChild(spec[1])
	if old then old:Destroy() end
	local seq = build(spec[1], spec[2], spec[3])
	seq.Parent = folder
	table.insert(made, seq:GetFullName() .. " (" .. #seq:GetKeyframes() .. " keyframes)")
end
return table.concat(made, "\n")
