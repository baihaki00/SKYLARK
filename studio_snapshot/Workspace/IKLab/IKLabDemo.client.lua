--[[
	IKLabDemo (client) - the "IK Lab" test mode (Quin Manager > TEST MODES).
	Runs while Workspace.CurrentMode == "IKLab"; builds everything locally and removes it after.

	Four copies of the same Quin do the same things in step, with the same clips and speed.
	Only the layer on top of the animation differs:

	  A  animation only
	  B  + basic IK: a foot that would sink into the ground is pushed up onto it
	  C  + foot placement: feet follow the ground height, stay locked while planted,
	       tilt to the slope, and the pelvis drops so the lower foot can reach
	  D  C + engine features that need no per-frame code: knee hinges instead of poles,
	       head LookAt, a part fixed to a hand bone, a trail, a hanging tag on a ball socket

	Two programmes:
	  Tour         walk, run, jog, strafe both ways and walk backward over the course, turn in
	               place, walk and run circles, run and jump.
	  Single clip  any clip of QuinCore's AnimationConfig (Prev / Next). A looping clip that
	               travels carries the Quins up and down the course; any other clip is played
	               standing on the rubble.

	Measured every frame from the drawn pose:
	  feet - sole inside / above the ground and slide while the clip says "planted"
	  body - every tracked bone against lane A's same bone (the layer's own contribution)

	The clip's foot path is baked once per clip (IKControl overwrites Bone.Transform, so the
	animated pose cannot be read back while IK is on). Targets are set in PreAnimation, right
	before the engine solves, so the pose and the root always agree.

	State (attributes on Workspace.IKLab; the on-screen buttons only write these):
	  Clip       "" = Tour, else an AnimationConfig path such as "Movement.Jog"
	  Focus      "" = camera frames all lanes, else "A".. "D" = orbit that Quin
	             (hold right mouse to look around, wheel to zoom)
	  TimeScale  playback speed (1, 0.3, 0.1)
	  Paused
	Results: attributes Metrics_A .. Metrics_D (JSON), refreshed when a programme part ends.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local lab = script.Parent
local course = lab:WaitForChild("Course")
local lookTarget = lab:WaitForChild("LookTarget")
local template = ReplicatedStorage:WaitForChild("QuinType"):WaitForChild("QuinMale")
local AnimationConfig = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("AnimationConfig"))

local MODE_NAME = "IKLab"
local LANES = {
	{ key = "A", z = 512, mode = "anim", title = "A  animation only" },
	{ key = "B", z = 520, mode = "basic", title = "B  + basic IK" },
	{ key = "C", z = 528, mode = "full", title = "C  + foot placement" },
	{ key = "D", z = 536, mode = "full", plants = true, title = "D  C + engine parts" },
}
local SIDES = { "Left", "Right" }
local BODY = { "Hips", "Spine2", "Head", "LeftArm", "LeftForeArm", "LeftHand", "RightArm", "RightForeArm", "RightHand", "LeftLeg", "RightLeg", "LeftFoot", "RightFoot", "LeftToeBase", "RightToeBase" }

local FLOOR_Y = 2
local ROOT_HEIGHT = 5.383 -- root part above the sole, standing
local COURSE_X0 = -640
local X_START, X_END = -635, -505
local STAND_X = COURSE_X0 + 85 -- on the rubble: where clips that do not travel are played
local BAKE_SAMPLES = 24
local MIN_TRAVEL_SPEED = 1.5 -- a looping clip slower than this is played standing

local ROOT_FOLLOW_RATE = 12 -- how fast the root settles on the ground height (1/s)
local WEIGHT_RATE = 25 -- clip cross-fade (1/s)
local PLANT_LIFT = 0.18 -- clip foot this close to its lowest point may be planted...
local PLANT_STILL_MIN = 3 -- ...if the clip also holds it still in the world (studs/s)
local PLANT_STILL_PER_SPEED = 0.35 -- the allowance grows with the body's speed
local LOCK_MAX_DRIFT = 1.0 -- a locked foot is dragged along past this distance from the clip
local LOCK_MAX_YAW = math.rad(60)
local LOCK_RELEASE_TIME = 0.12
local PELVIS_RATE = 10
local PELVIS_MIN, PELVIS_MAX = -1.6, 0.5
local REACH_LIMIT = 0.97 -- of the leg length; a fully straight leg pops
local ALIGN_FADE_LIFT = 0.8 -- slope alignment fades out as the foot lifts
local IK_FADE_RATE = 25 -- IK weight in and out around a jump (1/s)
local REVERSAL_MIN_SPEED = 0.3 -- studs/s; slower changes are not counted as vibration

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
	if d < 70 then return "stairs" end
	if d < 75 then return "flat" end
	if d < 95 then return "rubble" end
	if d < 100 then return "flat" end
	if d < 119 then return "crossSlope" end
	return "flat"
end

local function decay(rate: number, dt: number): number
	return 1 - math.exp(-rate * dt)
end

local function wrapAngle(a: number): number
	return (a + math.pi) % (2 * math.pi) - math.pi
end

-- yaw that makes a root look along v
local function headingOf(v: Vector3): number
	return math.atan2(-v.X, -v.Z)
end

----------------------------------------------------------------------------------------
-- Clip library: every clip of QuinCore's AnimationConfig, in path order.
----------------------------------------------------------------------------------------
local Library = { list = {}, byPath = {} }
for _, item in AnimationConfig.getAllPaths() do
	local clip = {
		path = item.path,
		category = item.category,
		label = item.name,
		id = item.entry.id,
		rate = item.entry.speed or 1,
		looped = item.entry.looped == true,
	}
	table.insert(Library.list, clip)
	Library.byPath[clip.path] = clip
end

-- by its last name, whatever category it sits in ("LandingSoft")
function Library.find(key: string)
	for _, clip in Library.list do
		if clip.path == key or clip.path:sub(-#key - 1) == "." .. key then
			return clip
		end
	end
	error("[IKLabDemo] no clip named " .. key)
end

local IDLE = Library.find("Movement.Idle")
-- a gait is a clip played at a rate; its travel direction and speed come from the bake
local GAITS = {
	Walk = { clip = Library.find("WalkConfident"), rate = 1 },
	Jog = { clip = Library.find("Movement.Jog"), rate = 1 },
	Run = { clip = Library.find("Movement.Run"), rate = 1 },
	StrafeLeft = { clip = Library.find("StrafeLeftWalk"), rate = 1 },
	StrafeRight = { clip = Library.find("StrafeRightWalk"), rate = 1 },
	Backward = { clip = Library.find("WalkConfident"), rate = -1 },
}
local JUMP = Library.find("Movement.Jump")
local LAND = Library.find("LandingSoft")
local TOUR_CLIPS = { IDLE, GAITS.Walk.clip, GAITS.Jog.clip, GAITS.Run.clip, GAITS.StrafeLeft.clip, GAITS.StrafeRight.clip, JUMP, LAND }

----------------------------------------------------------------------------------------
-- Baked clip data: where each foot and hip joint is, in root space, through the clip.
----------------------------------------------------------------------------------------
local Baked = {} -- [clip.path] = { foot = {Left = {CFrame}, ...}, hip = {...}, travel = Vector3 }
local ankleHeight = { Left = 0.46, Right = 0.46 } -- foot bone above the sole, standing

local function sampleBaked(baked, side: string, t: number): (CFrame, Vector3)
	local f = (t % 1) * BAKE_SAMPLES
	local i = math.floor(f)
	local a = f - i
	local i0, i1 = i % BAKE_SAMPLES + 1, (i + 1) % BAKE_SAMPLES + 1
	return baked.foot[side][i0]:Lerp(baked.foot[side][i1], a), baked.hip[side][i0]:Lerp(baked.hip[side][i1], a)
end

local function gaitTravel(gait): Vector3
	return Baked[gait.clip.path].travel * gait.rate
end

----------------------------------------------------------------------------------------
-- Conductor: one shared script of movement so every lane does exactly the same thing.
----------------------------------------------------------------------------------------
local Conductor = {}

local function resetConductor()
	Conductor.mode = "course" -- course: along X in the lane; flat: along X on open floor; circle
	Conductor.x, Conductor.yaw, Conductor.theta, Conductor.radius = X_START, -math.pi / 2, 0, 5
	Conductor.air, Conductor.airborne = 0, false
	Conductor.weights, Conductor.rates, Conductor.restart = { [IDLE.path] = 1 }, {}, {}
	Conductor.tag = "Start"
	Conductor.cut = true -- the rigs were moved discontinuously this frame
end
resetConductor()

function Conductor:pose(index: number, lane): (number, number)
	if self.mode == "course" then
		return self.x, lane.z
	elseif self.mode == "flat" then
		return self.x, 448 + index * 8
	end
	return -645 + (index - 1) * 27 + self.radius * math.cos(self.theta), 468 + self.radius * math.sin(self.theta)
end

local function frame(): number
	return coroutine.yield()
end

local function setIdle()
	Conductor.weights, Conductor.rates = { [IDLE.path] = 1 }, {}
end

local function setGait(gait, amount: number)
	Conductor.weights = { [IDLE.path] = 1 - amount, [gait.clip.path] = amount }
	Conductor.rates = { [gait.clip.path] = gait.rate * gait.clip.rate }
end

local function gaitSpeed(gait): number
	return gaitTravel(gait).Magnitude * gait.clip.rate
end

local function gaitYaw(gait, moveDir: Vector3): number
	return headingOf(moveDir) - headingOf(gaitTravel(gait))
end

local function rest(seconds: number)
	setIdle()
	while seconds > 0 do
		seconds -= frame()
	end
end

local function turnInPlace(yaw: number)
	Conductor.tag = "TurnInPlace"
	setIdle()
	while true do
		local dt = frame()
		local diff = wrapAngle(yaw - Conductor.yaw)
		local step = 4 * dt
		if math.abs(diff) <= step then
			Conductor.yaw = yaw
			return
		end
		Conductor.yaw += math.sign(diff) * step
	end
end

-- Cross the course (or part of it) with one gait: turn to suit the gait, speed up, go, brake.
local function pass(tag: string, gait, toX: number)
	local speedMax = gaitSpeed(gait)
	local dir = math.sign(toX - Conductor.x)
	turnInPlace(gaitYaw(gait, Vector3.new(dir, 0, 0)))
	Conductor.tag = tag
	local speed = 0
	while (toX - Conductor.x) * dir > 0 or speed > 0 do
		local dt = frame()
		if (toX - Conductor.x) * dir > 0 then
			speed = math.min(speedMax, speed + 25 * dt)
		else
			speed = math.max(0, speed - 30 * dt)
		end
		Conductor.x += dir * speed * dt
		setGait(gait, speed / speedMax)
	end
	rest(0.6)
end

local function circle(tag: string, gait, radius: number, laps: number, dir: number)
	local speedMax = gaitSpeed(gait)
	local function tangent()
		return Vector3.new(-math.sin(Conductor.theta), 0, math.cos(Conductor.theta)) * dir
	end
	Conductor.mode, Conductor.radius, Conductor.theta = "circle", radius, 0
	Conductor.yaw = gaitYaw(gait, tangent())
	Conductor.cut = true
	Conductor.tag = tag
	local speed, turned = 0, 0
	while turned < laps * 2 * math.pi or speed > 0 do
		local dt = frame()
		if turned < laps * 2 * math.pi then
			speed = math.min(speedMax, speed + 25 * dt)
		else
			speed = math.max(0, speed - 30 * dt)
		end
		local step = speed * dt / radius
		Conductor.theta += dir * step
		turned += step
		Conductor.yaw = gaitYaw(gait, tangent())
		setGait(gait, speed / speedMax)
	end
	rest(0.6)
end

-- Run on open floor and jump three times: ballistic root, Jump clip in the air, Land clip after.
local function jumps()
	local gait = GAITS.Run
	local speedMax = gaitSpeed(gait)
	Conductor.mode, Conductor.x = "flat", -650
	Conductor.yaw = gaitYaw(gait, Vector3.xAxis)
	Conductor.cut = true
	local marks, nextMark = { -615, -575, -535 }, 1
	local speed = 0
	while Conductor.x < -495 or speed > 0 do
		local dt = frame()
		if Conductor.x < -495 then
			speed = math.min(speedMax, speed + 25 * dt)
		else
			speed = math.max(0, speed - 30 * dt)
		end
		Conductor.x += speed * dt
		Conductor.tag = "Jump:run"
		setGait(gait, speed / speedMax)
		if marks[nextMark] and Conductor.x >= marks[nextMark] then
			nextMark += 1
			local t = 0
			Conductor.airborne, Conductor.tag = true, "Jump:air"
			Conductor.restart[JUMP.path] = true
			Conductor.weights, Conductor.rates = { [JUMP.path] = 1 }, { [JUMP.path] = JUMP.rate }
			while true do
				local step = frame()
				t += step
				local height = 48.5 * t - 98.1 * t * t
				if height <= 0 then break end
				Conductor.air = height
				Conductor.x += speed * step
			end
			Conductor.air, Conductor.airborne, Conductor.tag = 0, false, "Jump:land"
			Conductor.restart[LAND.path] = true
			local landed = 0
			while landed < 0.45 do
				local step = frame()
				landed += step
				local s = landed / 0.45
				Conductor.x += speed * (0.5 + 0.5 * s) * step
				local w = 1 - math.clamp((s - 0.6) / 0.4, 0, 1)
				Conductor.weights = { [LAND.path] = w, [gait.clip.path] = 1 - w }
				Conductor.rates = { [LAND.path] = LAND.rate, [gait.clip.path] = gait.clip.rate }
			end
		end
	end
	rest(0.6)
end

local function tour()
	while true do
		Conductor.mode, Conductor.x, Conductor.cut = "course", X_START, true
		pass("Walk", GAITS.Walk, X_END)
		pass("Run", GAITS.Run, X_START)
		pass("StrafeLeft", GAITS.StrafeLeft, COURSE_X0 + 72)
		pass("Backward", GAITS.Backward, X_START)
		pass("Jog", GAITS.Jog, X_END)
		pass("StrafeRight", GAITS.StrafeRight, COURSE_X0 + 72)
		coroutine.yield("publish")
		circle("CircleWalk", GAITS.Walk, 4, 1.5, 1)
		circle("CircleRun", GAITS.Run, 10, 3, -1)
		jumps()
		coroutine.yield("publish")
	end
end

-- One clip from the library: carried over the course if it loops and travels, else standing.
local function single(clip)
	local gait = { clip = clip, rate = 1 }
	if clip.looped and Baked[clip.path].travel.Magnitude * clip.rate >= MIN_TRAVEL_SPEED then
		Conductor.mode, Conductor.x, Conductor.cut = "course", X_START, true
		while true do
			pass(clip.path, gait, X_END)
			coroutine.yield("publish")
			pass(clip.path, gait, X_START)
			coroutine.yield("publish")
		end
	end
	Conductor.mode, Conductor.x, Conductor.cut = "course", STAND_X, true
	Conductor.tag = clip.path
	while true do
		Conductor.restart[clip.path] = true
		Conductor.weights, Conductor.rates = { [clip.path] = 1 }, { [clip.path] = clip.rate }
		local seconds = clip.looped and 6 or (Baked[clip.path].length / clip.rate + 0.3)
		while seconds > 0 do
			seconds -= frame()
		end
		if not clip.looped then
			rest(0.5)
			Conductor.tag = clip.path
		end
		coroutine.yield("publish")
	end
end

----------------------------------------------------------------------------------------
-- Rig
----------------------------------------------------------------------------------------
local Rig = {}
Rig.__index = Rig

function Rig.new(index: number, lane, parent: Instance)
	local self = setmetatable({}, Rig)
	self.index = index
	self.lane = lane
	self.mode = lane.mode

	local model = template:Clone()
	model.Name = "Lane" .. lane.key
	local stray = model:FindFirstChild("Sounds")
	if stray then stray:Destroy() end
	self.model = model
	self.root = model.HumanoidRootPart
	self.root.Anchored = true
	self.mesh = model.Alpha_Surface
	self.humanoid = model.Humanoid
	self.humanoid.EvaluateStateMachine = false
	self.animator = self.humanoid:FindFirstChildOfClass("Animator")
	self.rootY = FLOOR_Y + ROOT_HEIGHT
	self.base = CFrame.new(X_START, self.rootY, lane.z) * CFrame.Angles(0, Conductor.yaw, 0)
	self.root.CFrame = self.base
	model.Parent = parent

	local function bone(name: string): Bone
		return self.mesh:FindFirstChild("mixamorig:" .. name, true)
	end
	self.bone = bone
	self.legs = {}
	for _, side in SIDES do
		self.legs[side] = { hip = bone(side .. "UpLeg"), knee = bone(side .. "Leg"), foot = bone(side .. "Foot") }
	end
	self.body, self.pose, self.history = {}, {}, {}
	for _, name in BODY do
		self.body[name] = bone(name)
		self.history[name] = {}
	end

	self.tracks, self.weights = {}, {} -- by clip path, loaded when first needed
	self:track(IDLE)

	self.feet = {}
	for _, side in SIDES do
		self.feet[side] = { lock = nil, lockYaw = 0, release = Vector3.zero, releaseYaw = 0, releaseT = 1, groundY = FLOOR_Y, normal = Vector3.yAxis, lift = 0, lastPos = nil, wasContact = false, still = false }
	end
	self.pelvis = 0
	self.speed = 0
	self.ikWeight = 1
	self.cost, self.costFrames = 0, 0
	self:resetStats()

	if self.mode ~= "anim" then
		self:buildIK()
	end
	if lane.plants then
		self:buildPlants()
	end
	self:buildLabel()
	return self
end

function Rig:resetStats()
	self.footStats, self.bodyStats = {}, {}
end

function Rig:track(clip): AnimationTrack
	local track = self.tracks[clip.path]
	if not track then
		local animation = Instance.new("Animation")
		animation.AnimationId = clip.id
		track = self.animator:LoadAnimation(animation)
		track.Looped = true -- one-shot clips are held at their end by hand
		track.Priority = Enum.AnimationPriority.Movement -- same priority, so they blend by weight
		self.tracks[clip.path] = track
		self.weights[clip.path] = 0
	end
	return track
end

function Rig:buildIK()
	for _, side in SIDES do
		local sign = side == "Left" and -1 or 1
		local target = Instance.new("Attachment")
		target.Name = side .. "FootTarget"
		target.Visible = true
		target.Parent = self.root

		local ik = Instance.new("IKControl")
		ik.Name = side .. "FootIK"
		ik.Type = self.mode == "full" and Enum.IKControlType.Transform or Enum.IKControlType.Position
		ik.ChainRoot = self.legs[side].hip
		ik.EndEffector = self.legs[side].foot
		ik.Target = target
		ik.SmoothTime = 0 -- targets are already smoothed here; engine smoothing only adds lag
		ik.Weight = 0
		if self.lane.plants then
			-- a hinge between the two leg bones keeps the knee bending forward; no pole needed
			local hinge = Instance.new("HingeConstraint")
			hinge.Name = side .. "KneeHinge"
			hinge.Attachment0 = self.legs[side].hip
			hinge.Attachment1 = self.legs[side].knee
			hinge.LimitsEnabled = true
			hinge.LowerAngle, hinge.UpperAngle = 0, 150
			hinge.Parent = self.mesh
		else
			-- the pole rides with the body, in front of the knee
			local pole = Instance.new("Attachment")
			pole.Name = side .. "KneePole"
			pole.Position = Vector3.new(sign * 0.6, -2.5, -6)
			pole.Parent = self.root
			ik.Pole = pole
		end
		ik.Parent = self.humanoid
		self.feet[side].target = target
		self.feet[side].ik = ik
	end
end

-- Engine features that run with no code after this set-up.
function Rig:buildPlants()
	local look = Instance.new("IKControl")
	look.Name = "HeadLook"
	look.Type = Enum.IKControlType.LookAt
	look.ChainRoot = self.bone("Neck")
	look.EndEffector = self.bone("Head")
	look.Target = lookTarget
	look.Weight = 0.7
	look.SmoothTime = 0.15
	look.Parent = self.humanoid

	local function prop(name: string, size: Vector3, color: Color3): Part
		local part = Instance.new("Part")
		part.Name = name
		part.Size = size
		part.Color = color
		part.Material = Enum.Material.Neon
		part.CanCollide, part.CanQuery, part.CanTouch, part.Massless = false, false, false, true
		part.CFrame = self.root.CFrame
		part.Parent = self.model
		return part
	end

	-- a part fixed to the right hand bone
	local baton = prop("Baton", Vector3.new(0.25, 0.25, 2.4), Color3.fromRGB(255, 170, 60))
	local grip = Instance.new("Attachment")
	grip.Parent = baton
	local rigid = Instance.new("RigidConstraint")
	rigid.Attachment0 = self.bone("RightHand")
	rigid.Attachment1 = grip
	rigid.Parent = baton
	self.baton, self.batonBone = grip, self.bone("RightHand")

	-- a trail between two arm bones
	local trail = Instance.new("Trail")
	trail.Attachment0 = self.bone("LeftHand")
	trail.Attachment1 = self.bone("LeftForeArm")
	trail.Lifetime = 0.25
	trail.Color = ColorSequence.new(Color3.fromRGB(90, 200, 255))
	trail.Transparency = NumberSequence.new(0.2, 1)
	trail.Parent = self.mesh

	-- a tag hanging from the chest on a ball socket: physics does the swinging
	local anchor = prop("TagAnchor", Vector3.new(0.2, 0.2, 0.2), Color3.fromRGB(255, 80, 120))
	local anchorAtt = Instance.new("Attachment")
	anchorAtt.Parent = anchor
	local anchorRigid = Instance.new("RigidConstraint")
	anchorRigid.Attachment0 = self.bone("Spine2")
	anchorRigid.Attachment1 = anchorAtt
	anchorRigid.Parent = anchor
	local tag = prop("Tag", Vector3.new(0.3, 1.2, 0.3), Color3.fromRGB(255, 80, 120))
	tag.Massless = false
	local top = Instance.new("Attachment")
	top.Position = Vector3.new(0, 0.6, 0)
	top.Parent = tag
	local hang = Instance.new("Attachment")
	hang.Position = Vector3.new(0, 0, -1.2)
	hang.Parent = anchor
	local socket = Instance.new("BallSocketConstraint")
	socket.Attachment0 = hang
	socket.Attachment1 = top
	socket.Parent = tag
	self.tagTop, self.tagHang = top, hang
end

function Rig:buildLabel()
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromScale(7.2, 3) -- lanes are 8 studs apart
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

-- Follow the conductor's clip weights and rates. A clip nobody asks for is stopped.
function Rig:driveTracks(dt: number, scale: number)
	for path in Conductor.weights do
		self:track(Library.byPath[path])
	end
	for path, track in self.tracks do
		local clip = Library.byPath[path]
		local goal = Conductor.weights[path] or 0
		self.weights[path] += (goal - self.weights[path]) * decay(WEIGHT_RATE, dt)
		local weight = self.weights[path]
		if goal == 0 and weight < 0.005 then
			if track.IsPlaying then track:Stop(0) end
			continue
		end
		if not track.IsPlaying then
			track:Play(0, 0.001)
		end
		track:AdjustWeight(math.max(0.001, weight), 0)
		if Conductor.restart[path] then
			track.TimePosition = 0
		end
		local rate = Conductor.rates[path] or (clip.looped and clip.rate or 0)
		if not clip.looped and track.Length > 0 and track.TimePosition > 0.9 * track.Length then
			rate = 0
		end
		track:AdjustSpeed(dt > 0 and rate * scale or 0)
	end
end

-- The foot pose the clips ask for, in root space, blended like the tracks are.
function Rig:clipFoot(side: string, lookAhead: number): (CFrame, Vector3, number)
	local pos, hip, total = Vector3.zero, Vector3.zero, 0
	local rot = CFrame.identity
	for path, track in self.tracks do
		local baked = Baked[path]
		local w = track.IsPlaying and track.WeightCurrent or 0
		if baked and w > 0.01 and track.Length > 0 then
			local cf, h = sampleBaked(baked, side, (track.TimePosition + lookAhead * track.Speed) / track.Length)
			pos += cf.Position * w
			hip += h * w
			total += w
			rot = rot:Lerp(cf.Rotation, w / total) -- blended, so a cross-fade never pops the foot
		end
	end
	if total == 0 then
		local cf, h = sampleBaked(Baked[IDLE.path], side, 0)
		return cf, h, 0
	end
	pos /= total
	hip /= total
	local lift = math.max(0, pos.Y + ROOT_HEIGHT - ankleHeight[side])
	return CFrame.new(pos) * rot, hip, lift
end

-- Is the clip holding this foot still on the ground? Low is not enough: a strafe shuffles low feet.
function Rig:clipFootStill(foot, flat: Vector3, lift: number, dt: number): boolean
	local speed = foot.clipPrev and (flat - foot.clipPrev).Magnitude / dt or 0
	foot.clipPrev = flat
	foot.still = lift < PLANT_LIFT and speed <= math.max(PLANT_STILL_MIN, self.speed * PLANT_STILL_PER_SPEED)
	return foot.still
end

-- Feet, from what was drawn last frame: sole height over the ground, slide while planted.
function Rig:measureFeet(dt: number, key: string, continuous: boolean)
	local m = self.footStats[key]
	if not m then
		m = { contact = 0, float = 0, pen = 0, penMax = 0, slide = 0, slideN = 0, frames = 0, straight = 0 }
		self.footStats[key] = m
	end
	for _, side in SIDES do
		local foot, leg = self.feet[side], self.legs[side]
		local p = leg.foot.TransformedWorldCFrame.Position
		local groundY = castDown(p.X, p.Y + 4, p.Z)
		local sole = p.Y - ankleHeight[side] - groundY
		local contact = foot.lift < 0.1 and foot.still and not Conductor.airborne
		m.frames += 1
		m.pen += math.max(0, -sole)
		m.penMax = math.max(m.penMax, -sole)
		if contact then
			m.contact += 1
			m.float += math.max(0, sole)
			if continuous and foot.wasContact and foot.lastPos then
				m.slide += ((p - foot.lastPos) * Vector3.new(1, 0, 1)).Magnitude / dt
				m.slideN += 1
			end
		end
		local k = leg.knee.TransformedWorldCFrame.Position
		if (leg.hip.TransformedWorldCFrame.Position - k).Unit:Dot((p - k).Unit) < -0.99 then
			m.straight += 1
		end
		foot.lastPos, foot.wasContact = p, contact
	end
end

-- Body: each tracked bone in the frame of the lane's un-adjusted root, so lanes compare directly.
function Rig:sampleBody()
	for name, bone in self.body do
		self.pose[name] = self.base:ToObjectSpace(bone.TransformedWorldCFrame)
	end
end

function Rig:measureBody(reference, dt: number, key: string, continuous: boolean)
	local stats = self.bodyStats[key]
	if not stats then
		stats = { time = 0, bones = {} }
		for _, name in BODY do
			stats.bones[name] = { n = 0, d2 = 0, ang2 = 0, vn = 0, v2 = 0, vPeak = 0, rev = 0, angRate2 = 0, an = 0, acc2 = 0 }
		end
		self.bodyStats[key] = stats
	end
	stats.time += dt
	for name, cf in self.pose do
		local s, h = stats.bones[name], self.history[name]
		local ref = reference.pose[name]
		local d = cf.Position - ref.Position
		local _, angle = (ref.Rotation:Inverse() * cf.Rotation):ToAxisAngle()
		s.n += 1
		s.d2 += d:Dot(d)
		s.ang2 += angle * angle
		local p = cf.Position
		if continuous and h.d then
			local v = (d - h.d) / dt
			s.vn += 1
			s.v2 += v:Dot(v)
			s.vPeak = math.max(s.vPeak, v.Magnitude)
			local sign = v.Y > REVERSAL_MIN_SPEED and 1 or v.Y < -REVERSAL_MIN_SPEED and -1 or 0
			if sign ~= 0 then
				if h.sign and h.sign ~= sign then s.rev += 1 end
				h.sign = sign
			end
			local angRate = (angle - h.angle) / dt
			s.angRate2 += angRate * angRate
			local pv = (p - h.p) / dt
			if h.pv then
				local a = (pv - h.pv) / dt
				s.an += 1
				s.acc2 += a:Dot(a)
			end
			h.pv = pv
		else
			h.pv, h.sign = nil, nil
		end
		h.d, h.angle, h.p = d, angle, p
	end
end

function Rig:update(dt: number)
	local started = os.clock()
	local x, z = Conductor:pose(self.index, self.lane)
	local groundY = castDown(x, self.rootY + 2, z)
	if Conductor.cut then
		self.rootY = groundY + ROOT_HEIGHT
		for _, side in SIDES do
			local foot = self.feet[side]
			foot.lock, foot.release, foot.releaseYaw, foot.groundY, foot.lastPos, foot.clipPrev = nil, Vector3.zero, 0, groundY, nil, nil
		end
	else
		self.rootY += (groundY + ROOT_HEIGHT - self.rootY) * decay(ROOT_FOLLOW_RATE, dt)
	end
	local base = CFrame.new(x, self.rootY + Conductor.air, z) * CFrame.Angles(0, Conductor.yaw, 0)
	self.speed = Conductor.cut and 0 or ((base.Position - self.base.Position) * Vector3.new(1, 0, 1)).Magnitude / dt
	self.base = base
	self.ikWeight += ((Conductor.airborne and 0 or 1) - self.ikWeight) * decay(IK_FADE_RATE, dt)

	if self.mode == "anim" then
		self.root.CFrame = base
		for _, side in SIDES do
			local clip, _, lift = self:clipFoot(side, dt)
			local world = base * clip
			self.feet[side].lift = lift
			self:clipFootStill(self.feet[side], Vector3.new(world.X, 0, world.Z), lift, dt)
		end
	elseif self.mode == "basic" then
		self.root.CFrame = base
		for _, side in SIDES do
			local foot = self.feet[side]
			local clip, _, lift = self:clipFoot(side, dt)
			local world = base * clip
			local y = castDown(world.X, world.Y + 4, world.Z)
			foot.lift = lift
			self:clipFootStill(foot, Vector3.new(world.X, 0, world.Z), lift, dt)
			foot.target.WorldCFrame = CFrame.new(world.X, math.max(world.Y, y + ankleHeight[side]), world.Z)
			foot.ik.Weight = self.ikWeight
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
	local yaw = Conductor.yaw
	for _, side in SIDES do
		local foot = self.feet[side]
		local clip, hip, lift = self:clipFoot(side, dt)
		local world = base * clip
		local flat = Vector3.new(world.X, 0, world.Z)
		local yawOffset = 0

		-- lock the foot (position and heading) where it touched down; let go with a short blend
		local fade = 1 - math.clamp(foot.releaseT / LOCK_RELEASE_TIME, 0, 1)
		if self:clipFootStill(foot, flat, lift, dt) and not Conductor.airborne then
			if not foot.lock then
				foot.lock = flat + foot.release * fade
				foot.lockYaw = yaw + foot.releaseYaw * fade
			end
			local drift = foot.lock - flat
			if drift.Magnitude > LOCK_MAX_DRIFT then
				foot.lock = flat + drift.Unit * LOCK_MAX_DRIFT
			end
			yawOffset = math.clamp(wrapAngle(foot.lockYaw - yaw), -LOCK_MAX_YAW, LOCK_MAX_YAW)
			foot.lockYaw = yaw + yawOffset
			flat = foot.lock
		else
			if foot.lock then
				foot.release, foot.releaseYaw, foot.releaseT, foot.lock = foot.lock - flat, wrapAngle(foot.lockYaw - yaw), 0, nil
				fade = 1
			end
			foot.releaseT += dt
			flat += foot.release * fade
			yawOffset = foot.releaseYaw * fade
		end

		-- ground under the foot, smoothed so a step edge does not snap the leg
		local y, normal = castDown(flat.X, world.Y + 4, flat.Z)
		local rate = foot.lock and 30 or 15
		foot.groundY += (y - foot.groundY) * decay(rate, dt)
		foot.normal = foot.normal:Lerp(normal, decay(rate, dt)).Unit
		foot.lift = lift

		local footY = foot.groundY + ankleHeight[side] + lift
		local rot = CFrame.Angles(0, yaw + yawOffset, 0) * clip.Rotation
		wanted[side] = { flat = flat, y = footY, hip = hip, rot = rot }
		lowest = math.min(lowest, footY - world.Y)
	end

	-- the pelvis follows the foot that has to go lowest, so that leg can reach
	local pelvisGoal = Conductor.airborne and 0 or math.clamp(lowest, PELVIS_MIN, PELVIS_MAX)
	self.pelvis += (pelvisGoal - self.pelvis) * decay(PELVIS_RATE, dt)
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
		foot.ik.Weight = self.ikWeight
	end
end

function Rig:publish()
	local out = { feet = {}, body = {} }
	for key, m in self.footStats do
		out.feet[key] = {
			float = m.contact > 0 and m.float / m.contact or 0,
			pen = m.pen / math.max(1, m.frames),
			penMax = m.penMax,
			slide = m.slideN > 0 and m.slide / m.slideN or 0,
			straight = m.straight / math.max(1, m.frames),
			frames = m.frames,
		}
	end
	for key, stats in self.bodyStats do
		local bones = {}
		for name, s in stats.bones do
			bones[name] = {
				offset = math.sqrt(s.d2 / math.max(1, s.n)), -- studs, RMS, against lane A
				offsetSpeed = math.sqrt(s.v2 / math.max(1, s.vn)), -- studs/s, RMS
				offsetSpeedPeak = s.vPeak,
				reversalsPerSecond = s.rev / math.max(0.001, stats.time),
				angle = math.deg(math.sqrt(s.ang2 / math.max(1, s.n))), -- degrees, RMS, against lane A
				angleRate = math.deg(math.sqrt(s.angRate2 / math.max(1, s.vn))), -- degrees/s, RMS
				acceleration = math.sqrt(s.acc2 / math.max(1, s.an)), -- studs/s^2, RMS, this lane's own
			}
		end
		out.body[key] = bones
	end
	out.costMicroseconds = self.cost / math.max(1, self.costFrames) * 1e6
	if self.baton then
		out.batonGap = (self.baton.WorldPosition - self.batonBone.TransformedWorldCFrame.Position).Magnitude
		out.tagGap = (self.tagTop.WorldPosition - self.tagHang.WorldPosition).Magnitude
	end
	lab:SetAttribute("Metrics_" .. self.lane.key, HttpService:JSONEncode(out))
end

----------------------------------------------------------------------------------------
-- Bake: step a clip frame by frame on a rig with no IK and record the feet. Yields.
----------------------------------------------------------------------------------------
local bakeBusy = false -- the bake poses a rig, so only one runs at a time

local function bake(rig, clip): boolean
	while bakeBusy do
		task.wait()
	end
	if Baked[clip.path] then
		return true
	end
	local track = rig:track(clip)
	local waited = 0
	while track.Length <= 0 do
		waited += task.wait()
		if waited > 5 then
			return false -- the asset did not load
		end
	end
	bakeBusy = true
	for path, other in rig.tracks do
		if other ~= track and other.IsPlaying then other:Stop(0) end
		rig.weights[path] = 0
	end
	track:Play(0, 1, 0)
	local baked = { foot = { Left = {}, Right = {} }, hip = { Left = {}, Right = {} }, travel = Vector3.zero, length = track.Length }
	for i = 1, BAKE_SAMPLES do
		track.TimePosition = (i - 1) / BAKE_SAMPLES * track.Length
		for _ = 1, 3 do RunService.Heartbeat:Wait() end
		for _, side in SIDES do
			baked.foot[side][i] = rig.root.CFrame:ToObjectSpace(rig.legs[side].foot.TransformedWorldCFrame)
			baked.hip[side][i] = rig.root.CFrame:PointToObjectSpace(rig.legs[side].hip.TransformedWorldCFrame.Position)
		end
	end
	track:Stop(0)
	if clip == IDLE then
		-- the idle clip gives the ankle height
		for _, side in SIDES do
			ankleHeight[side] = baked.foot[side][1].Position.Y + ROOT_HEIGHT
		end
	elseif clip.looped then
		-- a planted foot moves backward under the body: the opposite of that is the clip's travel
		local moves = {}
		local step = track.Length / BAKE_SAMPLES
		for _, side in SIDES do
			for i = 1, BAKE_SAMPLES do
				local a, b = baked.foot[side][i].Position, baked.foot[side][i % BAKE_SAMPLES + 1].Position
				if math.max(a.Y, b.Y) + ROOT_HEIGHT - ankleHeight[side] < 0.25 then
					table.insert(moves, (a - b) * Vector3.new(1, 0, 1) / step)
				end
			end
		end
		table.sort(moves, function(a, b) return a.Magnitude < b.Magnitude end)
		baked.travel = moves[math.ceil(#moves / 2)] or Vector3.zero
	end
	Baked[clip.path] = baked
	bakeBusy = false
	return true
end

----------------------------------------------------------------------------------------
-- On-screen controls. Buttons only write the attributes; the session reads them.
----------------------------------------------------------------------------------------
local function clipIndex(): number
	local clip = Library.byPath[lab:GetAttribute("Clip") or ""]
	return clip and table.find(Library.list, clip) or 0
end

local function stepClip(delta: number)
	local count = #Library.list
	local index = clipIndex()
	index = index == 0 and (delta > 0 and 1 or count) or (index - 1 + delta) % count + 1
	lab:SetAttribute("Clip", Library.list[index].path)
end

-- jump to the first clip of the next / previous category
local function stepCategory(delta: number)
	local count = #Library.list
	local index = math.max(1, clipIndex())
	local category = Library.list[index].category
	for _ = 1, count do
		index = (index - 1 + delta) % count + 1
		if Library.list[index].category ~= category then
			break
		end
	end
	category = Library.list[index].category
	while index > 1 and Library.list[index - 1].category == category do
		index -= 1
	end
	lab:SetAttribute("Clip", Library.list[index].path)
end

local function buildHud(): (ScreenGui, TextLabel)
	local gui = Instance.new("ScreenGui")
	gui.Name = "IKLabHud"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 50

	local bar = Instance.new("Frame")
	bar.AnchorPoint = Vector2.new(0.5, 1)
	bar.Position = UDim2.new(0.5, 0, 1, -16)
	bar.Size = UDim2.fromOffset(820, 96)
	bar.BackgroundColor3 = Color3.fromRGB(15, 20, 30)
	bar.BackgroundTransparency = 0.15
	bar.Parent = gui
	Instance.new("UICorner", bar).CornerRadius = UDim.new(0, 8)

	local function button(text: string, x: number, y: number, width: number, onClick: () -> ())
		local b = Instance.new("TextButton")
		b.Position = UDim2.fromOffset(x, y)
		b.Size = UDim2.fromOffset(width, 30)
		b.BackgroundColor3 = Color3.fromRGB(45, 60, 90)
		b.TextColor3 = Color3.new(1, 1, 1)
		b.Font = Enum.Font.GothamBold
		b.TextSize = 13
		b.Text = text
		b.Parent = bar
		Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
		b.MouseButton1Click:Connect(onClick)
		return b
	end
	local function set(name: string, value: any)
		return function()
			lab:SetAttribute(name, value)
		end
	end

	-- row 1: which animation
	button("<< Category", 10, 10, 96, function() stepCategory(-1) end)
	button("< Prev", 112, 10, 70, function() stepClip(-1) end)
	local title = Instance.new("TextLabel")
	title.Position = UDim2.fromOffset(188, 10)
	title.Size = UDim2.fromOffset(372, 30)
	title.BackgroundColor3 = Color3.fromRGB(25, 32, 48)
	title.TextColor3 = Color3.fromRGB(255, 230, 140)
	title.Font = Enum.Font.GothamBold
	title.TextSize = 13
	title.TextTruncate = Enum.TextTruncate.AtEnd
	title.Parent = bar
	button("Next >", 566, 10, 70, function() stepClip(1) end)
	button("Category >>", 642, 10, 96, function() stepCategory(1) end)
	button("Tour", 744, 10, 66, set("Clip", ""))

	-- row 2: camera, speed, pause
	button("All", 10, 54, 50, set("Focus", ""))
	for index, lane in LANES do
		button("Look at " .. lane.key, 66 + (index - 1) * 86, 54, 80, set("Focus", lane.key))
	end
	for index, scale in { 1, 0.3, 0.1 } do
		button(scale .. "x", 424 + (index - 1) * 56, 54, 50, set("TimeScale", scale))
	end
	button("Pause", 598, 54, 70, function()
		lab:SetAttribute("Paused", not lab:GetAttribute("Paused"))
	end)
	local hint = Instance.new("TextLabel")
	hint.Position = UDim2.fromOffset(674, 54)
	hint.Size = UDim2.fromOffset(136, 30)
	hint.BackgroundTransparency = 1
	hint.TextColor3 = Color3.fromRGB(170, 180, 200)
	hint.Font = Enum.Font.Gotham
	hint.TextSize = 11
	hint.TextWrapped = true
	hint.Text = "right mouse: orbit\nwheel: zoom"
	hint.Parent = bar

	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	return gui, title
end

----------------------------------------------------------------------------------------
-- Session: everything that exists only while the mode is on.
----------------------------------------------------------------------------------------
local session = 0 -- bumped on every start and stop; a stale thread sees it changed and quits
local cleanup: { () -> () } = {}

local function stop()
	session += 1
	for _, undo in cleanup do
		undo()
	end
	cleanup = {}
end

local function start()
	stop()
	local mine = session
	resetConductor()
	lab:SetAttribute("Clip", "")
	lab:SetAttribute("Focus", "")
	lab:SetAttribute("TimeScale", 1)
	lab:SetAttribute("Paused", false)

	local runtime = Instance.new("Folder")
	runtime.Name = "Runtime"
	runtime.Parent = lab
	table.insert(cleanup, function() runtime:Destroy() end)

	local rigs = {}
	for index, lane in LANES do
		table.insert(rigs, Rig.new(index, lane, runtime))
	end

	local hud, title = buildHud()
	table.insert(cleanup, function() hud:Destroy() end)

	-- programme: a coroutine stepped once per frame; busy while a clip is being baked
	local programme: thread? = nil
	local busy = true
	local function run(body: () -> ())
		resetConductor()
		for _, rig in rigs do
			rig:resetStats()
		end
		programme = coroutine.create(body)
		coroutine.resume(programme)
	end

	local function choose()
		local path = lab:GetAttribute("Clip") or ""
		local clip = Library.byPath[path]
		busy = true
		task.spawn(function()
			if clip then
				title.Text = string.format("loading  %s", clip.path)
				local ok = bake(rigs[1], clip)
				if mine ~= session or lab:GetAttribute("Clip") ~= path then return end
				if not ok then
					title.Text = string.format("%s  did not load  (%s)", clip.path, clip.id)
					return
				end
				local travel = Baked[clip.path].travel.Magnitude * clip.rate
				title.Text = string.format("%d/%d  %s  [%s]  %s", table.find(Library.list, clip), #Library.list, clip.path, clip.label, clip.looped and travel >= MIN_TRAVEL_SPEED and string.format("%.1f studs/s", travel) or "standing")
				run(function() single(clip) end)
			else
				title.Text = "Tour: walk, run, strafe, backward, jog, circles, jumps"
				run(tour)
			end
			busy = false
		end)
	end

	-- camera: frames all lanes, or orbits one Quin
	local camera = workspace.CurrentCamera
	local savedType, savedFov = camera.CameraType, camera.FieldOfView
	local orbit = { yaw = math.rad(140), pitch = math.rad(12), distance = 14, dragging = false }
	local camCentre: Vector3? = nil
	RunService:BindToRenderStep("IKLabCamera", Enum.RenderPriority.Last.Value, function(dt)
		local focus = lab:GetAttribute("Focus") or ""
		local centre, offset
		local first, last = rigs[1].root.Position, rigs[#rigs].root.Position
		if focus == "" then
			centre = (first + last) / 2 - Vector3.new(0, 1.5, 0)
			local distance = 16 + (first - last).Magnitude * 0.75
			offset = (Conductor.mode == "circle" and Vector3.new(0, 0.45, 1) or Vector3.new(1, 0.3, -0.25)) * distance
		else
			for _, rig in rigs do
				if rig.lane.key == focus then
					centre = rig.root.Position - Vector3.new(0, 1, 0)
				end
			end
			centre = centre or first
			offset = (CFrame.Angles(0, orbit.yaw, 0) * CFrame.Angles(-orbit.pitch, 0, 0)).LookVector * -orbit.distance
		end
		camCentre = camCentre and not Conductor.cut and camCentre:Lerp(centre, decay(focus == "" and 8 or 30, dt)) or centre
		camera.CameraType = Enum.CameraType.Scriptable
		camera.FieldOfView = 50
		camera.CFrame = CFrame.lookAt(camCentre + offset, camCentre)
	end)
	table.insert(cleanup, function()
		RunService:UnbindFromRenderStep("IKLabCamera")
		camera.CameraType, camera.FieldOfView = savedType, savedFov
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	end)

	local connections = {}
	table.insert(cleanup, function()
		for _, connection in connections do
			connection:Disconnect()
		end
	end)
	table.insert(connections, UserInputService.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			orbit.dragging = true
			UserInputService.MouseBehavior = Enum.MouseBehavior.LockCurrentPosition
		end
	end))
	table.insert(connections, UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			orbit.dragging = false
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		end
	end))
	table.insert(connections, UserInputService.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseMovement and orbit.dragging then
			orbit.yaw -= input.Delta.X * 0.006
			orbit.pitch = math.clamp(orbit.pitch + input.Delta.Y * 0.006, math.rad(-35), math.rad(80))
		elseif input.UserInputType == Enum.UserInputType.MouseWheel then
			orbit.distance = math.clamp(orbit.distance * 0.88 ^ input.Position.Z, 3, 60)
		end
	end))
	table.insert(connections, lab:GetAttributeChangedSignal("Clip"):Connect(choose))

	local labelTimer = 0
	table.insert(connections, RunService.PreAnimation:Connect(function(dt)
		if busy or not programme then return end
		if lab:GetAttribute("Paused") then dt = 0 end
		local scale = lab:GetAttribute("TimeScale") or 1
		dt *= scale
		if dt <= 0 then
			for _, rig in rigs do rig:driveTracks(0, scale) end
			return
		end

		-- 1. measure what was drawn last frame (a cut frame starts the history again)
		local continuous = not Conductor.cut
		local tag = Conductor.tag
		local footKey = Conductor.mode == "course" and tag .. ":" .. sectionAt(Conductor.x) or tag
		for _, rig in rigs do
			rig:measureFeet(dt, footKey, continuous)
			rig:sampleBody()
		end
		for _, rig in rigs do
			rig:measureBody(rigs[1], dt, tag, continuous)
		end
		Conductor.cut = false

		-- 2. advance the shared movement script
		local ok, message = coroutine.resume(programme, dt)
		if not ok then
			warn("[IKLabDemo] " .. tostring(message))
			programme = nil
			return
		end
		if message == "publish" then
			for _, rig in rigs do rig:publish() end
			coroutine.resume(programme, dt)
		end

		-- 3. drive every rig
		for _, rig in rigs do
			rig:driveTracks(dt, scale)
			rig:update(dt)
		end
		Conductor.restart = {}

		labelTimer += dt
		if labelTimer > 0.25 then
			labelTimer = 0
			for _, rig in rigs do
				local m = rig.footStats[footKey]
				if m and m.contact > 0 then
					rig.label.Text = string.format("%s\n%s\nabove %.2f  inside %.2f\nslide %.1f studs/s", rig.lane.title, footKey, m.float / m.contact, m.pen / m.frames, m.slideN > 0 and m.slide / m.slideN or 0)
				else
					rig.label.Text = string.format("%s\n%s", rig.lane.title, footKey)
				end
			end
		end
	end))

	-- bake what the tour needs, then begin
	task.spawn(function()
		title.Text = "loading the tour's clips"
		for _, clip in TOUR_CLIPS do
			bake(rigs[1], clip)
			if mine ~= session then return end
		end
		choose()
	end)
end

local function sync()
	if workspace:GetAttribute("CurrentMode") == MODE_NAME then
		start()
	else
		stop()
	end
end
workspace:GetAttributeChangedSignal("CurrentMode"):Connect(sync)
if workspace:GetAttribute("CurrentMode") == MODE_NAME then
	start()
end
