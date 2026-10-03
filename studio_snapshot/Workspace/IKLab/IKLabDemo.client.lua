--[[
	IKLabDemo (client) - an experiment, separate from QuinCore.

	Three copies of the same Quin cross the same obstacle course in step, playing the
	same clips at the same speed. Only the layer on top of the animation differs:

	  A  animation only
	  B  + basic IK: a foot that would sink into the ground is pushed up onto it
	  C  + foot placement: feet follow the ground height, stay locked while planted,
	       tilt to the slope, and the pelvis drops so the lower foot can reach

	The clip's foot path is baked once per clip (IKControl overwrites Bone.Transform, so
	the animated pose cannot be read back while IK is on). Targets are set in PreAnimation,
	right before the engine solves, so the pose and the root always agree.

	Switches (attributes on Workspace.IKLab): TimeScale (default 1), Paused.
	Results per lap: attributes Metrics_A / Metrics_B / Metrics_C (JSON).
]]

local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local lab = script.Parent
local course = lab:WaitForChild("Course")
local template = ReplicatedStorage:WaitForChild("QuinType"):WaitForChild("QuinMale")

local CLIPS = {
	Idle = "rbxassetid://81038616654818",
	Walk = "rbxassetid://117985748552966",
	Run = "rbxassetid://109090784752055",
}
local LANES = {
	{ key = "A", z = 512, mode = "anim", title = "A  animation only" },
	{ key = "B", z = 520, mode = "basic", title = "B  + basic IK" },
	{ key = "C", z = 528, mode = "full", title = "C  + foot placement, lock, pelvis" },
}
local SIDES = { "Left", "Right" }

local FLOOR_Y = 2
local ROOT_HEIGHT = 5.383 -- root part above the sole, standing
local COURSE_X0 = -640
local X_START, X_END = -635, -505
local BAKE_SAMPLES = 24

local ROOT_FOLLOW_RATE = 12 -- how fast the root settles on the ground height (1/s)
local PLANT_LIFT = 0.18 -- clip foot this close to its lowest point counts as planted
local LOCK_MAX_DRIFT = 1.0 -- a locked foot is dragged along past this distance from the clip
local LOCK_RELEASE_TIME = 0.12
local PELVIS_RATE = 10
local PELVIS_MIN, PELVIS_MAX = -1.6, 0.5
local REACH_LIMIT = 0.97 -- of the leg length; a fully straight leg pops
local ALIGN_FADE_LIFT = 0.8 -- slope alignment fades out as the foot lifts

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Include
rayParams.FilterDescendantsInstances = { course, workspace:WaitForChild("MovementTestArena") }

local function castDown(x: number, yTop: number, z: number): (number, Vector3)
	local hit = workspace:Raycast(Vector3.new(x, yTop, z), Vector3.new(0, -14, 0), rayParams)
	if hit then
		return hit.Position.Y, hit.Normal
	end
	return FLOOR_Y, Vector3.yAxis
end

local function sectionAt(x: number): string
	local d = x - COURSE_X0
	if d < 25 then return "flat" end
	if d < 45 then return "ramp" end
	if d < 57 then return "flat" end
	if d < 73 then return "stairs" end
	if d < 75 then return "flat" end
	if d < 95 then return "rubble" end
	if d < 100 then return "flat" end
	if d < 119 then return "crossSlope" end
	return "flat"
end

local function decay(rate: number, dt: number): number
	return 1 - math.exp(-rate * dt)
end

----------------------------------------------------------------------------------------
-- Baked clip data: where each foot and hip joint is, in root space, through the cycle.
----------------------------------------------------------------------------------------
local Baked = {} -- [clipName] = { foot = {Left = {CFrame}, Right = ...}, hip = {...}, speed = number }
local ankleHeight = { Left = 0.46, Right = 0.46 } -- foot bone above the sole, standing

local function sampleBaked(clip, side: string, t: number): (CFrame, Vector3)
	local f = (t % 1) * BAKE_SAMPLES
	local i = math.floor(f)
	local a = f - i
	local i0, i1 = i % BAKE_SAMPLES + 1, (i + 1) % BAKE_SAMPLES + 1
	return clip.foot[side][i0]:Lerp(clip.foot[side][i1], a), clip.hip[side][i0]:Lerp(clip.hip[side][i1], a)
end

----------------------------------------------------------------------------------------
-- Conductor: one shared path so every lane does exactly the same thing.
----------------------------------------------------------------------------------------
local Conductor = { x = X_START, yaw = -math.pi / 2, speed = 0, gait = "Walk", phase = "go", dir = 1, timer = 0, yawFrom = 0, lap = 0 }

function Conductor:step(dt: number): boolean
	local lapEnded = false
	local natural = Baked[self.gait].speed
	if self.phase == "go" then
		self.speed = math.min(natural, self.speed + 25 * dt)
		if (self.dir == 1 and self.x >= X_END) or (self.dir == -1 and self.x <= X_START) then
			self.phase = "brake"
		end
	elseif self.phase == "brake" then
		self.speed = math.max(0, self.speed - 30 * dt)
		if self.speed == 0 then
			self.phase, self.timer = "rest", 1.2
			lapEnded = true
		end
	elseif self.phase == "rest" then
		self.timer -= dt
		if self.timer <= 0 then
			self.phase, self.timer, self.yawFrom = "turn", 0, self.yaw
		end
	elseif self.phase == "turn" then
		self.timer += dt
		local s = math.clamp(self.timer / 0.7, 0, 1)
		self.yaw = self.yawFrom + math.pi * (s * s * (3 - 2 * s))
		if s >= 1 then
			self.dir = -self.dir
			self.gait = self.gait == "Walk" and "Run" or "Walk"
			self.lap += 1
			self.phase = "go"
		end
	end
	self.x += self.dir * self.speed * dt
	return lapEnded
end

----------------------------------------------------------------------------------------
-- Rig
----------------------------------------------------------------------------------------
local Rig = {}
Rig.__index = Rig

function Rig.new(lane, parent: Instance)
	local self = setmetatable({}, Rig)
	self.lane = lane
	self.mode = lane.mode

	local model = template:Clone()
	model.Name = "Lane" .. lane.key
	local stray = model:FindFirstChild("Sounds")
	if stray then stray:Destroy() end
	self.root = model.HumanoidRootPart
	self.root.Anchored = true
	self.mesh = model.Alpha_Surface
	self.humanoid = model.Humanoid
	self.humanoid.EvaluateStateMachine = false
	self.rootY = FLOOR_Y + ROOT_HEIGHT
	self.root.CFrame = CFrame.new(X_START, self.rootY, lane.z) * CFrame.Angles(0, Conductor.yaw, 0)
	model.Parent = parent

	self.bones = {}
	for _, side in SIDES do
		self.bones[side] = {
			hip = self.mesh:FindFirstChild("mixamorig:" .. side .. "UpLeg", true),
			knee = self.mesh:FindFirstChild("mixamorig:" .. side .. "Leg", true),
			foot = self.mesh:FindFirstChild("mixamorig:" .. side .. "Foot", true),
		}
	end

	self.tracks = {}
	local animator = self.humanoid:FindFirstChildOfClass("Animator")
	for name, id in CLIPS do
		local animation = Instance.new("Animation")
		animation.AnimationId = id
		local track = animator:LoadAnimation(animation)
		track.Looped = true
		track.Priority = Enum.AnimationPriority.Movement -- same priority, so they blend by weight
		track:Play(0, name == "Idle" and 1 or 0.001)
		self.tracks[name] = track
	end

	-- per-foot state for the foot-placement layer
	self.feet = {}
	for _, side in SIDES do
		self.feet[side] = { lock = nil, release = Vector3.zero, releaseT = 1, groundY = FLOOR_Y, normal = Vector3.yAxis, lift = 0, lastPos = nil, wasContact = false }
	end
	self.pelvis = 0
	self.metrics = {}
	self.cost, self.costFrames = 0, 0

	if self.mode ~= "anim" then
		self:buildIK()
	end
	self:buildLabel()
	return self
end

function Rig:buildIK()
	for _, side in SIDES do
		local sign = side == "Left" and -1 or 1
		local target = Instance.new("Attachment")
		target.Name = side .. "FootTarget"
		target.Visible = true
		target.Parent = self.root
		-- the pole rides with the body, in front of the knee
		local pole = Instance.new("Attachment")
		pole.Name = side .. "KneePole"
		pole.Position = Vector3.new(sign * 0.6, -2.5, -6)
		pole.Parent = self.root

		local ik = Instance.new("IKControl")
		ik.Name = side .. "FootIK"
		ik.Type = self.mode == "full" and Enum.IKControlType.Transform or Enum.IKControlType.Position
		ik.ChainRoot = self.bones[side].hip
		ik.EndEffector = self.bones[side].foot
		ik.Target = target
		ik.Pole = pole
		ik.SmoothTime = 0 -- targets are already smoothed here; engine smoothing only adds lag
		ik.Weight = 0
		ik.Parent = self.humanoid
		self.feet[side].target = target
		self.feet[side].ik = ik
	end
end

function Rig:buildLabel()
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromScale(16, 2.6)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 5.5, 0)
	gui.AlwaysOnTop = true
	gui.Adornee = self.root
	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundColor3 = Color3.fromRGB(15, 20, 30)
	text.BackgroundTransparency = 0.25
	text.TextColor3 = Color3.new(1, 1, 1)
	text.Font = Enum.Font.GothamBold
	text.TextScaled = true
	text.Text = self.lane.title
	text.Parent = gui
	gui.Parent = self.root
	self.label = text
end

function Rig:setGaitWeights(gait: string, amount: number)
	for name, track in self.tracks do
		local w = 0.001
		if name == gait then w = math.max(0.001, amount) elseif name == "Idle" then w = math.max(0.001, 1 - amount) end
		track:AdjustWeight(w, 0)
	end
end

-- The foot pose the clips ask for, in root space, blended like the tracks are.
function Rig:clipFoot(side: string, lookAhead: number): (CFrame, Vector3, number)
	local pos, hip, total = Vector3.zero, Vector3.zero, 0
	local rot, best = CFrame.identity, 0
	for name, track in self.tracks do
		local w = track.WeightCurrent
		if w > 0.01 and track.Length > 0 then
			local cf, h = sampleBaked(Baked[name], side, (track.TimePosition + lookAhead * track.Speed) / track.Length)
			pos += cf.Position * w
			hip += h * w
			total += w
			if w > best then best, rot = w, cf.Rotation end
		end
	end
	pos /= total
	hip /= total
	local lift = math.max(0, pos.Y + ROOT_HEIGHT - ankleHeight[side])
	return CFrame.new(pos) * rot, hip, lift
end

-- What was drawn last frame: sole height over the ground, slide while the clip says "planted".
function Rig:measure(dt: number, gait: string)
	local key = gait .. ":" .. sectionAt(self.root.Position.X)
	local m = self.metrics[key]
	if not m then
		m = { contact = 0, float = 0, pen = 0, penMax = 0, slide = 0, slideN = 0, frames = 0, straight = 0 }
		self.metrics[key] = m
	end
	for _, side in SIDES do
		local foot, bones = self.feet[side], self.bones[side]
		local p = bones.foot.TransformedWorldCFrame.Position
		local groundY = castDown(p.X, p.Y + 4, p.Z)
		local sole = p.Y - ankleHeight[side] - groundY
		local contact = foot.lift < 0.1
		m.frames += 1
		m.pen += math.max(0, -sole)
		m.penMax = math.max(m.penMax, -sole)
		if contact then
			m.contact += 1
			m.float += math.max(0, sole)
			if foot.wasContact and foot.lastPos and dt > 0 then
				m.slide += ((p - foot.lastPos) * Vector3.new(1, 0, 1)).Magnitude / dt
				m.slideN += 1
			end
		end
		local k = bones.knee.TransformedWorldCFrame.Position
		local a = (bones.hip.TransformedWorldCFrame.Position - k).Unit
		local b = (p - k).Unit
		if a:Dot(b) < -0.99 then m.straight += 1 end
		foot.lastPos, foot.wasContact = p, contact
	end
end

function Rig:update(dt: number)
	local started = os.clock()
	local x, z = Conductor.x, self.lane.z
	local groundY = castDown(x, self.rootY + 2, z)
	self.rootY += (groundY + ROOT_HEIGHT - self.rootY) * decay(ROOT_FOLLOW_RATE, dt)
	local base = CFrame.new(x, self.rootY, z) * CFrame.Angles(0, Conductor.yaw, 0)

	if self.mode == "anim" then
		self.root.CFrame = base
		for _, side in SIDES do
			local _, _, lift = self:clipFoot(side, dt)
			self.feet[side].lift = lift
		end
	elseif self.mode == "basic" then
		self.root.CFrame = base
		for _, side in SIDES do
			local foot = self.feet[side]
			local clip, _, lift = self:clipFoot(side, dt)
			local world = base * clip
			local y = castDown(world.X, world.Y + 4, world.Z)
			foot.lift = lift
			foot.target.WorldCFrame = CFrame.new(world.X, math.max(world.Y, y + ankleHeight[side]), world.Z)
			foot.ik.Weight = 1
		end
	else
		self:placeFeet(base, dt)
	end
	self.cost += os.clock() - started
	self.costFrames += 1
end

function Rig:placeFeet(base: CFrame, dt: number)
	local wanted = {}
	local lowest = math.huge
	for _, side in SIDES do
		local foot = self.feet[side]
		local clip, hip, lift = self:clipFoot(side, dt)
		local world = base * clip
		local flat = Vector3.new(world.X, 0, world.Z)

		-- lock the foot where it touched down; let go with a short blend
		if lift < PLANT_LIFT then
			if not foot.lock then
				foot.lock = flat + foot.release * (1 - math.clamp(foot.releaseT / LOCK_RELEASE_TIME, 0, 1))
			end
			local drift = foot.lock - flat
			if drift.Magnitude > LOCK_MAX_DRIFT then
				foot.lock = flat + drift.Unit * LOCK_MAX_DRIFT
			end
			flat = foot.lock
		else
			if foot.lock then
				foot.release, foot.releaseT, foot.lock = foot.lock - flat, 0, nil
			end
			foot.releaseT += dt
			flat += foot.release * (1 - math.clamp(foot.releaseT / LOCK_RELEASE_TIME, 0, 1))
		end

		-- ground under the foot, smoothed so a step edge does not snap the leg
		local y, normal = castDown(flat.X, world.Y + 4, flat.Z)
		local rate = foot.lock and 30 or 15
		foot.groundY += (y - foot.groundY) * decay(rate, dt)
		foot.normal = foot.normal:Lerp(normal, decay(rate, dt)).Unit
		foot.lift = lift

		local footY = foot.groundY + ankleHeight[side] + lift
		wanted[side] = { flat = flat, y = footY, hip = hip, rot = (base * clip).Rotation }
		lowest = math.min(lowest, footY - world.Y)
	end

	-- the pelvis follows the foot that has to go lowest, so that leg can reach
	self.pelvis += (math.clamp(lowest, PELVIS_MIN, PELVIS_MAX) - self.pelvis) * decay(PELVIS_RATE, dt)
	local rootCF = base + Vector3.new(0, self.pelvis, 0)
	self.root.CFrame = rootCF

	for _, side in SIDES do
		local foot, w = self.feet[side], wanted[side]
		local position = Vector3.new(w.flat.X, w.y, w.flat.Z)
		local hipWorld = rootCF * w.hip
		local reach = position - hipWorld
		local limit = foot.ik:GetChainLength() * REACH_LIMIT
		if reach.Magnitude > limit then
			position = hipWorld + reach.Unit * limit
		end
		-- tilt the sole onto the slope while it is near the ground
		local align = 1 - math.clamp(foot.lift / ALIGN_FADE_LIFT, 0, 1)
		local tilt = CFrame.identity:Lerp(CFrame.fromRotationBetweenVectors(Vector3.yAxis, foot.normal), align)
		foot.target.WorldCFrame = CFrame.new(position) * tilt * w.rot
		foot.ik.Weight = 1
	end
end

function Rig:publish()
	local out = {}
	for key, m in self.metrics do
		out[key] = {
			float = m.contact > 0 and m.float / m.contact or 0,
			pen = m.pen / math.max(1, m.frames),
			penMax = m.penMax,
			slide = m.slideN > 0 and m.slide / m.slideN or 0,
			straight = m.straight / math.max(1, m.frames),
			frames = m.frames,
		}
	end
	out.costMicroseconds = self.cost / math.max(1, self.costFrames) * 1e6
	lab:SetAttribute("Metrics_" .. self.lane.key, HttpService:JSONEncode(out))
end

----------------------------------------------------------------------------------------
-- Bake: step each clip frame by frame on one rig with no IK and record the feet.
----------------------------------------------------------------------------------------
local function bake(rig)
	for _, track in rig.tracks do
		while track.Length <= 0 do task.wait() end
	end
	for name, track in rig.tracks do
		for other, t in rig.tracks do
			t:AdjustWeight(other == name and 1 or 0.001, 0)
			t:AdjustSpeed(0)
		end
		local clip = { foot = { Left = {}, Right = {} }, hip = { Left = {}, Right = {} }, speed = 0 }
		for i = 1, BAKE_SAMPLES do
			track.TimePosition = (i - 1) / BAKE_SAMPLES * track.Length
			for _ = 1, 3 do RunService.Heartbeat:Wait() end
			for _, side in SIDES do
				clip.foot[side][i] = rig.root.CFrame:ToObjectSpace(rig.bones[side].foot.TransformedWorldCFrame)
				clip.hip[side][i] = rig.root.CFrame:PointToObjectSpace(rig.bones[side].hip.TransformedWorldCFrame.Position)
			end
		end
		Baked[name] = clip
	end
	-- the idle clip gives the ankle height; a planted foot's backward speed gives each clip's travel speed
	for _, side in SIDES do
		ankleHeight[side] = Baked.Idle.foot[side][1].Position.Y + ROOT_HEIGHT
	end
	for name, clip in Baked do
		local speeds = {}
		local step = rig.tracks[name].Length / BAKE_SAMPLES
		for _, side in SIDES do
			for i = 1, BAKE_SAMPLES do
				local a, b = clip.foot[side][i].Position, clip.foot[side][i % BAKE_SAMPLES + 1].Position
				if math.max(a.Y, b.Y) + ROOT_HEIGHT - ankleHeight[side] < 0.25 then
					table.insert(speeds, (b.Z - a.Z) / step) -- root forward is -Z
				end
			end
		end
		table.sort(speeds)
		clip.speed = name == "Idle" and 0 or math.max(1, speeds[math.ceil(#speeds / 2)] or 1)
	end
	for _, track in rig.tracks do
		track:AdjustSpeed(1)
	end
end

----------------------------------------------------------------------------------------
-- Run
----------------------------------------------------------------------------------------
local runtime = Instance.new("Folder")
runtime.Name = "Runtime"
runtime.Parent = lab

local rigs = {}
for _, lane in LANES do
	table.insert(rigs, Rig.new(lane, runtime))
end
bake(rigs[1])
lab:SetAttribute("BakedSpeeds", string.format("walk %.1f run %.1f ankle %.2f", Baked.Walk.speed, Baked.Run.speed, ankleHeight.Left))

-- start every rig's clips together so the lanes stay in step
for _, rig in rigs do
	for _, track in rig.tracks do
		track.TimePosition = 0
	end
end

local labelTimer = 0
RunService.PreAnimation:Connect(function(dt)
	if lab:GetAttribute("Paused") then dt = 0 end
	local scale = lab:GetAttribute("TimeScale") or 1
	dt *= scale
	local gait = Conductor.gait
	if dt > 0 then -- a paused frame would count the same pose again
		for _, rig in rigs do
			rig:measure(dt, gait)
		end
	end
	local lapEnded = Conductor:step(dt)
	local amount = math.clamp(Conductor.speed / Baked[gait].speed, 0, 1)
	for _, rig in rigs do
		for _, track in rig.tracks do
			track:AdjustSpeed(dt > 0 and scale or 0)
		end
		rig:setGaitWeights(gait, amount)
		rig:update(dt)
		if lapEnded then rig:publish() end
	end
	labelTimer += dt
	if labelTimer > 0.25 then
		labelTimer = 0
		for _, rig in rigs do
			local m = rig.metrics[gait .. ":" .. sectionAt(Conductor.x)]
			if m and m.contact > 0 then
				rig.label.Text = string.format("%s\nplanted foot: %.2f above ground, %.2f inside it, slides %.1f studs/s", rig.lane.title, m.float / m.contact, m.pen / m.frames, m.slideN > 0 and m.slide / m.slideN or 0)
			end
		end
	end
end)
