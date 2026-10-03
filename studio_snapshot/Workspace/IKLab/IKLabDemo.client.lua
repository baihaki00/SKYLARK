--[[
	IKLabDemo (client) - the "IK Lab" test mode (Quin Manager > TEST MODES).
	Runs while Workspace.CurrentMode == "IKLab"; builds everything locally and removes it after.

	Four copies of the same Quin do the same things in step, with the same clips and speed.
	Only the layer on top of the animation differs:

	  A  animation only
	  B  + basic IK: a foot that would sink into the ground is pushed up onto it
	  C  + foot placement: feet follow the ground height, stay locked while planted,
	       tilt to the slope, and the pelvis drops so the lower foot can reach
	  D  everything: C plus the full-body layers further down. Root level: lean, slope lean,
	       pelvis spring, weight on each footfall, hip twist, stride warp, knee over toe. Pose
	       level: thigh roll, chest squared up in a strafe, spine counter-rotation, QuinCore's
	       LookController, arm sway in three parts (upper arm, forearm, hand), soft elbows,
	       arms kept out of the trunk, arm IK for pointing and for a hand on a rail, toe bend,
	       breathing. Off by default: a blend that carries the last pose into a new clip and
	       knee hinges (measured no better), and the props (a part on a hand bone, a trail, a
	       hanging tag). Each layer has a switch: attribute D_<Name>.

	In C and D the knee bends the way the clip's own knee does: the pole is placed every frame
	from the baked knee. B keeps a pole fixed in front of the body.

	Two programmes:
	  Tour         the walk clip with the body going slower and faster than the clip, then
	               walk, run, jog, strafe both ways and walk backward over the course, turn
	               in place, walk and run circles, run and jump.
	  Strafe test  every strafe clip along a line on the open floor, then circling a point the
	               Quin faces (walk, run, and a tight circle).
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
	  Clip       "" = Tour, "#Strafe" = Strafe test, else an AnimationConfig path such as "Movement.Jog"
	  Focus      "" = camera frames all lanes, else "A".. "D" = orbit that Quin
	             (hold right mouse to look around, wheel to zoom)
	  TimeScale  playback speed (1, 0.3, 0.1)
	  Crowd      extra full-procedural Quins (set before the mode starts), for the cost test
	  Paused
	Results: attributes Metrics_A .. Metrics_D (JSON), refreshed when a programme part ends;
	Perf (rigs, script milliseconds per frame before the solve and at the pose step, fps).
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
local QuinCore = ReplicatedStorage:WaitForChild("QuinCore")
local AnimationConfig = require(QuinCore:WaitForChild("AnimationConfig"))
local LookController = require(QuinCore:WaitForChild("Modules"):WaitForChild("LookController"))

local MODE_NAME = "IKLab"
local LANES = {
	{ key = "A", z = 512, mode = "anim", title = "A  animation only" },
	{ key = "B", z = 520, mode = "basic", title = "B  + basic IK" },
	{ key = "C", z = 528, mode = "full", title = "C  + foot placement" },
	{ key = "D", z = 536, mode = "full", plants = true, full = true, title = "D  full procedural" },
}
local CROWD_Z = { 546, 554, 498, 490, 482, 474 } -- open floor either side of the course
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
-- Of the leg length. The knee keeps about 11 degrees of bend at full reach (the clips' own legs
-- go to 8). At 0.97 it kept 28 degrees: the legs never straightened and the walk looked crouched.
local REACH_LIMIT = 0.995
local ALIGN_FADE_LIFT = 0.8 -- slope alignment fades out as the foot lifts
local IK_FADE_RATE = 25 -- IK weight in and out around a jump (1/s)
local REVERSAL_MIN_SPEED = 0.3 -- studs/s; slower changes are not counted as vibration

-- full-body layers (lane D)
local GRAVITY = 196.2
local ACCEL_LIMIT = 150 -- studs/s^2; a take-off or a teleport is not a real acceleration
local ACCEL_SMOOTH_RATE = 12
local LEAN_PER_ACCEL = 0.004 -- radians of body tilt per stud/s^2 (a turn at a run gives about 15 degrees)
local LEAN_PER_SPEED = 0.004 -- radians of forward tilt per stud/s
local SLOPE_LEAN = 0.35 -- share of the slope angle the body leans uphill
local LEAN_MAX = math.rad(17)
local COUNTER_LEAN = 0.4 -- share of the lean the spine takes back, so the head stays more level
local PELVIS_OMEGA, PELVIS_DAMPING = 14, 0.8
local LANDING_DIP = 0.2 -- pelvis speed gained per stud/s of fall speed at touchdown
local TWIST_PER_STUD = 0.035 -- radians of pelvis yaw per stud one foot is ahead of the other
local TWIST_MAX = math.rad(8)
local TURN_LOOK = 0.07 -- radians the chest turns into a turn per rad/s
local TURN_LOOK_MAX = math.rad(14)
local ARM_OMEGA, ARM_DAMPING = 14, 0.45 -- loose: the arms overshoot a little
local ARM_MAX = math.rad(25)
local FORE_OMEGA, FORE_DAMPING = 9, 0.35 -- the forearm takes up the same sway later and looser than the upper arm...
local HAND_OMEGA, HAND_DAMPING = 12, 0.3 -- ...and the hand later again
local FORE_GAIN, FORE_MAX = 1.2, math.rad(25) -- elbow bend (radians) per unit the forearm's sway differs from the upper arm's
local HAND_GAIN, HAND_MAX = 1.0, math.rad(15) -- the same for the wrist
local ELBOW_MIN = math.rad(10) -- an elbow is never straighter than this (the walk clip's arms are dead straight on 6-11% of frames)
local KNEE_IN_MAX, KNEE_OUT_MAX = math.rad(5), math.rad(25) -- how far a knee may point inward / outward of the foot under it
local WEIGHT_STEP = 1.2 -- pelvis speed (studs/s, downward) a footfall adds at 8 studs/s of travel
local POINT_RANGE, POINT_CONE, POINT_WEIGHT = 30, math.rad(60), 0.7
local POINT_ACROSS = math.rad(15) -- how far to the right of straight ahead the left hand still points
local CONTACT_WEIGHT = 0.85 -- how firmly a hand goes to a rail within reach
local POLE_REACH = 3 -- studs from the knee to its pole
local SQUARE_RATE = 5 -- how fast the chest's average turn is followed (1/s); the stride's own swing is left alone
local SQUARE_GAIN, SQUARE_MAX = 1, math.rad(55) -- how much of that turn is taken back, and the most the spine twists for it
local ARM_CLEAR = 0.95 -- studs an elbow or a wrist keeps from the line through the trunk (the clips' own arms: 0.93-1.09)
local TRUNK_BELOW_HIPS = 1.2 -- the trunk's line starts this far under the hips (the top of the thighs)
local STRIDE_MIN_SPEED = 1.5 -- studs/s of clip travel below which there is no stride to warp
local STRIDE_MIN, STRIDE_MAX = 0.5, 1.6 -- how far a stride is shortened or stretched
local INERTIAL_TIME = 0.25 -- seconds over which the pose carried into a new clip is let go
local SWITCH_JUMP = 0.5 -- a clip weight asked to change by this much at once is a switch, not a blend
local TOE_FADE = 0.4 -- studs above the ground over which the toe bend fades out
local BREATH_HZ, BREATH_ANGLE = 0.25, math.rad(1.2)
local LAYERS = { "Lean", "SlopeLean", "PelvisSpring", "Weight", "HipTwist", "StrideWarp", "ThighTwist", "KneeOverToe", "SpineCounter", "SquareUp", "Look", "ArmLag", "SoftElbows", "ArmClear", "Point", "Contact", "Toes", "Breath", "Inertial", "KneeHinge", "Props" }
-- Off unless switched on, because they measured no better or worse than without:
--   KneeHinge  with the knee pole placed from the clip, a hinge on top changes nothing measurable
--   Inertial   the upper body carries over well, but the legs pop: the engine solves the leg IK
--              before the pose can be edited (a jump: knee and foot acceleration 3-7 times the
--              clip's with it, 1.3 times with the plain cross-fade)
--   Props      the baton, the hanging tag and the trail: they hide the arms, so they are shown on request
local LAYER_OFF_BY_DEFAULT = { KneeHinge = true, Inertial = true, Props = true }

local function layerOn(name: string): boolean
	local switch = lab:GetAttribute("D_" .. name)
	if switch == nil then
		return not LAYER_OFF_BY_DEFAULT[name]
	end
	return switch == true
end

-- rails a hand can rest on (the Contact layer); kept out of the ground rays
local rails = lab:FindFirstChild("Rails")
local railParams = OverlapParams.new()
railParams.FilterType = Enum.RaycastFilterType.Include
railParams.FilterDescendantsInstances = { rails }

-- The nearest point on top of a rail within reach of a shoulder, or nil
local function nearestRailPoint(shoulder: Vector3, reach: number): Vector3?
	if not rails then return nil end
	local best, bestDistance = nil, reach
	for _, part in workspace:GetPartBoundsInRadius(shoulder, reach, railParams) do
		local half = part.Size / 2
		local p = part.CFrame:PointToObjectSpace(shoulder)
		local point = part.CFrame * Vector3.new(math.clamp(p.X, -half.X, half.X), half.Y, math.clamp(p.Z, -half.Z, half.Z))
		local distance = (point - shoulder).Magnitude
		if distance < bestDistance then
			best, bestDistance = point, distance
		end
	end
	return best
end

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
	StrafeLeftRun = { clip = Library.find("StrafeLeftRun"), rate = 1 },
	StrafeRightRun = { clip = Library.find("StrafeRightRun"), rate = 1 },
	StrafeLeftTired = { clip = Library.find("StrafeLeftTired"), rate = 1 },
	StrafeRightTired = { clip = Library.find("StrafeRightTired"), rate = 1 },
	Backward = { clip = Library.find("WalkConfident"), rate = -1 },
}
local JUMP = Library.find("Movement.Jump")
local LAND = Library.find("LandingSoft")
local STRAFE_CLIPS = { IDLE, GAITS.StrafeLeft.clip, GAITS.StrafeRight.clip, GAITS.StrafeLeftRun.clip, GAITS.StrafeRightRun.clip, GAITS.StrafeLeftTired.clip, GAITS.StrafeRightTired.clip }
local TOUR_CLIPS = { IDLE, GAITS.Walk.clip, GAITS.Jog.clip, GAITS.Run.clip, GAITS.StrafeLeft.clip, GAITS.StrafeRight.clip, JUMP, LAND }

----------------------------------------------------------------------------------------
-- Baked clip data: where each foot and hip joint is, in root space, through the clip.
----------------------------------------------------------------------------------------
-- [clip.path] = { foot = {Left = {CFrame}, ...}, hip, knee, toe = positions; thigh, hand = the bone's own rotation; travel }
local Baked = {}
local ankleHeight = { Left = 0.46, Right = 0.46 } -- foot bone above the sole, standing

local function sampleBaked(baked, side: string, t: number): (CFrame, Vector3, Vector3, Vector3)
	local f = (t % 1) * BAKE_SAMPLES
	local i = math.floor(f)
	local a = f - i
	local i0, i1 = i % BAKE_SAMPLES + 1, (i + 1) % BAKE_SAMPLES + 1
	return baked.foot[side][i0]:Lerp(baked.foot[side][i1], a), baked.hip[side][i0]:Lerp(baked.hip[side][i1], a),
		baked.knee[side][i0]:Lerp(baked.knee[side][i1], a), baked.toe[side][i0]:Lerp(baked.toe[side][i1], a)
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
	Conductor.watchCentre = false -- circling: the Quin's opponent stands at the centre (the head looks there)
	Conductor.cut = true -- the rigs were moved discontinuously this frame
end
resetConductor()

-- where a rig's circle is centred (x, z)
local function circleCentre(index: number): (number, number)
	return -645 + ((index - 1) % 4) * 27, 468
end

function Conductor:pose(index: number, lane): (number, number)
	local back = (lane.row or 0) * 9 -- crowd rows follow behind
	if self.mode == "course" then
		return self.x - back, lane.z
	elseif self.mode == "flat" then
		return self.x - back, 448 + ((index - 1) % 13 + 1) * 8
	end
	local cx, cz = circleCentre(index)
	return cx + self.radius * math.cos(self.theta), cz + self.radius * math.sin(self.theta)
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
-- speedScale: the body's speed against the clip's own (1 = matched; the feet slide otherwise)
local function pass(tag: string, gait, toX: number, speedScale: number?)
	local speedMax = gaitSpeed(gait) * (speedScale or 1)
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

-- watch: the centre is its opponent. With a strafe gait the body then faces the centre while it
-- moves round it (the gait's own travel direction decides the facing).
local function circle(tag: string, gait, radius: number, laps: number, dir: number, watch: boolean?)
	local speedMax = gaitSpeed(gait)
	Conductor.watchCentre = watch == true
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
		pass("WalkSlow", GAITS.Walk, COURSE_X0 + 24, 0.6)
		pass("WalkFast", GAITS.Walk, X_START, 1.4)
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

-- Strafing only: every strafe clip along a line on the open floor (left, then back to the right,
-- facing the same way throughout), then round a point the Quin faces.
local function strafeTest()
	while true do
		Conductor.mode, Conductor.x, Conductor.cut, Conductor.watchCentre = "flat", -650, true, false
		pass("StrafeWalk:left", GAITS.StrafeLeft, -590)
		pass("StrafeWalk:right", GAITS.StrafeRight, -650)
		pass("StrafeRun:left", GAITS.StrafeLeftRun, -540)
		pass("StrafeRun:right", GAITS.StrafeRightRun, -650)
		pass("StrafeTired:left", GAITS.StrafeLeftTired, -634)
		pass("StrafeTired:right", GAITS.StrafeRightTired, -650)
		coroutine.yield("publish")
		circle("CircleWalk:left", GAITS.StrafeLeft, 8, 1, 1, true)
		circle("CircleWalk:right", GAITS.StrafeRight, 8, 1, -1, true)
		circle("CircleRun:left", GAITS.StrafeLeftRun, 12, 1.5, 1, true)
		circle("CircleRun:right", GAITS.StrafeRightRun, 12, 1.5, -1, true)
		circle("CircleTight:left", GAITS.StrafeLeft, 4, 1.5, 1, true)
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
local FullBody = {} -- lane D's layers, defined after Rig
FullBody.__index = FullBody

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
		self.legs[side] = { hip = bone(side .. "UpLeg"), knee = bone(side .. "Leg"), foot = bone(side .. "Foot"), toe = bone(side .. "ToeBase") }
	end
	self.handBones = { Left = bone("LeftHand"), Right = bone("RightHand") }
	self.body, self.pose, self.history = {}, {}, {}
	for _, name in BODY do
		self.body[name] = bone(name)
		self.history[name] = {}
	end

	self.tracks, self.weights, self.goals = {}, {}, {} -- by clip path, loaded when first needed
	self.timeScale = 1
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
	if lane.full then
		self.full = FullBody.new(self)
	end
	if not lane.crowd then
		self:buildLabel()
	end
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
		-- The pole says which way the knee bends. It starts in front of the knee (all basic IK
		-- ever has); foot placement moves it every frame to where the clip's own knee points.
		local pole = Instance.new("Attachment")
		pole.Name = side .. "KneePole"
		pole.Position = Vector3.new(sign * 0.6, -2.5, -6)
		pole.Parent = self.root
		ik.Pole = pole
		self.feet[side].pole = pole
		if self.lane.plants then
			-- a hinge between the two leg bones: the knee can only fold one way (layer KneeHinge)
			local hinge = Instance.new("HingeConstraint")
			hinge.Name = side .. "KneeHinge"
			hinge.Attachment0 = self.legs[side].hip
			hinge.Attachment1 = self.legs[side].knee
			hinge.LimitsEnabled = true
			hinge.LowerAngle, hinge.UpperAngle = 0, 150
			hinge.Enabled = false
			hinge.Parent = self.mesh
			self.feet[side].hinge = hinge
		end
		ik.Parent = self.humanoid
		self.feet[side].target = target
		self.feet[side].ik = ik
	end
end

-- Engine features that run with no code after this set-up.
function Rig:buildPlants()
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
	self.props, self.trail = { baton, anchor, tag }, trail
end

function Rig:showProps(shown: boolean)
	for _, part in self.props do
		part.Transparency = shown and 0 or 1
	end
	self.trail.Enabled = shown
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
	self.timeScale = scale
	for path in Conductor.weights do
		self:track(Library.byPath[path])
	end
	local carry = self.full ~= nil and layerOn("Inertial")
	for path, track in self.tracks do
		local clip = Library.byPath[path]
		local goal = Conductor.weights[path] or 0
		if carry then
			-- no cross-fade: the new clip takes over at once and the last pose is carried into it
			if math.abs(goal - (self.goals[path] or 0)) > SWITCH_JUMP or (Conductor.restart[path] and goal > 0) then
				self.full:beginSwitch()
			end
			self.weights[path] = goal
		else
			self.weights[path] += (goal - self.weights[path]) * decay(WEIGHT_RATE, dt)
		end
		self.goals[path] = goal
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
function Rig:clipFoot(side: string, lookAhead: number): (CFrame, Vector3, number, Vector3, Vector3)
	local pos, hip, knee, toe, total = Vector3.zero, Vector3.zero, Vector3.zero, Vector3.zero, 0
	local rot = CFrame.identity
	for path, track in self.tracks do
		local baked = Baked[path]
		local w = track.IsPlaying and track.WeightCurrent or 0
		if baked and w > 0.01 and track.Length > 0 then
			local cf, h, k, t = sampleBaked(baked, side, (track.TimePosition + lookAhead * track.Speed) / track.Length)
			pos += cf.Position * w
			hip += h * w
			knee += k * w
			toe += t * w
			total += w
			rot = rot:Lerp(cf.Rotation, w / total) -- blended, so a cross-fade never pops the foot
		end
	end
	if total == 0 then
		local cf, h, k, t = sampleBaked(Baked[IDLE.path], side, 0)
		return cf, h, 0, k, t
	end
	pos /= total
	hip /= total
	knee /= total
	toe /= total
	local lift = math.max(0, pos.Y + ROOT_HEIGHT - ankleHeight[side])
	return CFrame.new(pos) * rot, hip, lift, knee, toe
end

-- A bone's own rotation (its Transform) as the clips have it, blended like the tracks are.
-- key: "thigh" | "hand"
function Rig:clipRotation(key: string, side: string): CFrame
	local rot, total = CFrame.identity, 0
	for path, track in self.tracks do
		local baked = Baked[path]
		local w = track.IsPlaying and track.WeightCurrent or 0
		if baked and w > 0.01 and track.Length > 0 then
			local f = (track.TimePosition / track.Length % 1) * BAKE_SAMPLES
			local i = math.floor(f)
			local list = baked[key][side]
			local sample = list[i % BAKE_SAMPLES + 1]:Lerp(list[(i + 1) % BAKE_SAMPLES + 1], f - i)
			total += w
			rot = rot:Lerp(sample, w / total)
		end
	end
	return rot
end

-- How fast, and which way, the clips say the body travels (root space, studs/s)
function Rig:clipTravel(): Vector3
	local travel, total = Vector3.zero, 0
	for path, track in self.tracks do
		local baked = Baked[path]
		local w = track.IsPlaying and track.WeightCurrent or 0
		if baked and w > 0.01 then
			travel += baked.travel * (w * track.Speed / self.timeScale)
			total += w
		end
	end
	return total > 0 and travel / total or Vector3.zero
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
	if self.full then
		self.full:observe(base, dt)
	end
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
	local stride, strideDir = 1, nil
	local carried = false
	if self.full then
		stride, strideDir = self.full:strideScale(base, dt)
		carried = self.full:takeFootSwitch()
	end
	for _, side in SIDES do
		local foot = self.feet[side]
		local clip, hip, lift, knee, toe = self:clipFoot(side, dt)
		local bend = knee - (hip + clip.Position) / 2 -- which way the clip's knee points: out from the hip-to-foot line
		local toes = toe - clip.Position -- which way the clip's foot points
		if strideDir then
			-- stretch or shorten the step about the hip, along the way the clip travels
			clip += strideDir * ((clip.Position - hip):Dot(strideDir) * (stride - 1))
		end
		local world = base * clip
		local flat = Vector3.new(world.X, 0, world.Z)
		local yawOffset = 0

		-- lock the foot (position and heading) where it touched down; let go with a short blend
		local fade = 1 - math.clamp(foot.releaseT / LOCK_RELEASE_TIME, 0, 1)
		if self:clipFootStill(foot, flat, lift, dt) and not Conductor.airborne then
			if not foot.lock then
				foot.lock = flat + foot.release * fade
				foot.lockYaw = yaw + foot.releaseYaw * fade
				if self.full then
					self.full:footfall(self.speed)
				end
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
			if carried and foot.lastFlat then
				-- a new clip took over: the foot leaves from where it was, not from where the clip puts it
				foot.release, foot.releaseYaw, foot.releaseT = foot.lastFlat - flat, 0, 0
				fade = 1
			end
			foot.releaseT += dt
			flat += foot.release * fade
			yawOffset = foot.releaseYaw * fade
		end
		foot.lastFlat = flat

		-- ground under the foot, smoothed so a step edge does not snap the leg
		local y, normal = castDown(flat.X, world.Y + 4, flat.Z)
		local rate = foot.lock and 30 or 15
		foot.groundY += (y - foot.groundY) * decay(rate, dt)
		foot.normal = foot.normal:Lerp(normal, decay(rate, dt)).Unit
		foot.lift = lift

		local footY = foot.groundY + ankleHeight[side] + lift
		local rot = CFrame.Angles(0, yaw + yawOffset, 0) * clip.Rotation
		if self.full then
			bend = self.full:kneeOverToe(side, bend, toes, yawOffset)
		end
		wanted[side] = { flat = flat, y = footY, hip = hip, knee = knee, bend = bend, rot = rot, forward = -clip.Position.Z }
		lowest = math.min(lowest, footY - world.Y)
	end

	-- the pelvis follows the foot that has to go lowest, so that leg can reach
	local pelvisGoal = Conductor.airborne and 0 or math.clamp(lowest, PELVIS_MIN, PELVIS_MAX)
	if self.full then
		self.pelvis = self.full:pelvis(self.pelvis, pelvisGoal, dt)
	else
		self.pelvis += (pelvisGoal - self.pelvis) * decay(PELVIS_RATE, dt)
	end
	local rootCF = base + Vector3.new(0, self.pelvis, 0)
	if self.full then
		rootCF = self.full:tiltRoot(rootCF, wanted.Right.forward - wanted.Left.forward, dt)
	end
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

		-- the knee bends the way the clip's knee does
		if w.bend.Magnitude > 0.05 then
			foot.pole.WorldPosition = rootCF * w.knee + rootCF:VectorToWorldSpace(w.bend.Unit) * POLE_REACH
		end
		if foot.hinge then
			foot.hinge.Enabled = layerOn("KneeHinge")
		end
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
-- Full-body layers (lane D). Each is one small rule on top of the clip, switched by D_<Name>.
--
--   Root level, set before the engine solves the legs, so the feet stay where they are:
--     Lean          the body tilts toward its acceleration (starts, stops, turns) and forward with speed
--     SlopeLean     ... and uphill on a slope
--     PelvisSpring  the pelvis follows the feet on a spring and dips on landing
--     HipTwist      the pelvis turns toward the leg that is forward
--   Pose level, written into Bone.Transform after animation and IK (upper body and toes only):
--     SpineCounter  the lower spine takes back part of the lean and the hip twist, and turns into a turn
--     Look          QuinCore's LookController: head, neck and upper back follow a target in front
--     ArmLag        the arms hang the way a loose arm would under the body's acceleration
--     Point         arm IK: the left hand points at the look target when it is in front and near
--     Toes          a toe that would dig into the ground bends flat
--     Breath        the chest rises and falls at idle
----------------------------------------------------------------------------------------
local function springStep(value, velocity, goal, omega: number, damping: number, dt: number)
	velocity += ((goal - value) * (omega * omega) - velocity * (2 * damping * omega)) * dt
	return value + velocity * dt, velocity
end

-- turn a bone by a rotation given in world space, on top of its current pose
local function rotateWorld(bone: Bone, rotation: CFrame)
	local world = bone.TransformedWorldCFrame.Rotation
	bone.Transform *= world:Inverse() * rotation * world
end

local FLAT = Vector3.new(1, 0, 1)
local DOWN = Vector3.new(0, -1, 0)

function FullBody.new(rig)
	local self = setmetatable({}, FullBody)
	self.rig = rig
	self.velocity, self.accel, self.yawRate = Vector3.zero, Vector3.zero, 0
	self.lean, self.leanVel = Vector3.zero, Vector3.zero -- world, horizontal; length = tilt in radians
	self.groundNormal = Vector3.yAxis
	self.pelvisVel = 0
	self.twist = 0
	self.armSwing, self.armSwingVel = Vector3.zero, Vector3.zero -- how far a hanging arm is off straight down
	self.foreSwing, self.foreSwingVel = Vector3.zero, Vector3.zero -- the same sway as the forearm takes it up
	self.handSwing, self.handSwingVel = Vector3.zero, Vector3.zero -- ... and the hand
	self.stride = 1
	self.square = 0 -- how far the clips turn the chest off the front, averaged over a stride (radians, + = left)
	self.clock = 0
	self.wasAirborne = false

	self.spine = { rig.bone("Spine"), rig.bone("Spine1") } -- Spine2, Neck and Head belong to LookController
	self.arms = { Left = { rig.bone("LeftArm"), rig.bone("LeftForeArm") }, Right = { rig.bone("RightArm"), rig.bone("RightForeArm") } }
	self.toes = { Left = rig.bone("LeftToeBase"), Right = rig.bone("RightToeBase") }
	self.look = LookController.new(rig.model, nil)
	self.neck = rig.bone("Neck")
	self.hands = { Left = rig.bone("LeftHand"), Right = rig.bone("RightHand") }
	self.chest = rig.bone("Spine2")

	-- Which way each elbow bends, as an axis in the forearm's own frame: the one that brings the
	-- hand forward from the bind pose (arms out to the sides).
	self.elbowAxis = {}
	for _, side in SIDES do
		local bind = self.arms[side][2].WorldCFrame
		local along = (self.hands[side].WorldCFrame.Position - bind.Position).Unit
		local best, bestScore = Vector3.zAxis, -math.huge
		for _, axis in { Vector3.xAxis, -Vector3.xAxis, Vector3.zAxis, -Vector3.zAxis } do
			local score = (CFrame.fromAxisAngle(bind:VectorToWorldSpace(axis), 0.3) * along):Dot(rig.root.CFrame.LookVector)
			if score > bestScore then
				best, bestScore = axis, score
			end
		end
		self.elbowAxis[side] = best
	end

	-- the pose carried into a new clip (Inertial): the upper body bone by bone, the hips through the root
	self.hips = rig.bone("Hips")
	self.carryBones = {}
	for _, name in { "Spine", "Spine1", "Spine2", "Neck", "Head", "LeftShoulder", "LeftArm", "LeftForeArm", "LeftHand", "RightShoulder", "RightArm", "RightForeArm", "RightHand" } do
		table.insert(self.carryBones, rig.bone(name))
	end
	self.carryLegs = {} -- leg bones: carried only as far as the IK lets go of them (a jump)
	for _, name in { "LeftUpLeg", "LeftLeg", "LeftFoot", "LeftToeBase", "RightUpLeg", "RightLeg", "RightFoot", "RightToeBase" } do
		local bone = rig.bone(name)
		table.insert(self.carryBones, bone)
		self.carryLegs[bone] = true
	end
	self.lastLocal = {} -- bone -> its Transform as last drawn
	self.carry = nil -- bone -> the offset that turns the new clip's pose back into the last one
	self.hipsCarry = CFrame.identity -- the same for the hips, in root space
	self.hipsLast = nil
	self.carryT = INERTIAL_TIME
	self.switchPending, self.footSwitch = false, 0

	-- arm IK: a hand on a rail (Contact, either hand) or pointing (Point, the left hand)
	self.reach = {}
	for _, side in SIDES do
		local sign = side == "Left" and -1 or 1
		local target = Instance.new("Attachment")
		target.Name = side .. "HandTarget"
		target.Parent = rig.root
		local elbow = Instance.new("Attachment")
		elbow.Name = side .. "ElbowPole"
		elbow.Position = Vector3.new(sign * 2.5, -1.5, 1.5) -- out, down and behind
		elbow.Parent = rig.root
		local ik = Instance.new("IKControl")
		ik.Name = side .. "HandIK"
		ik.Type = Enum.IKControlType.Position
		ik.ChainRoot = rig.bone(side .. "Arm")
		ik.EndEffector = rig.bone(side .. "Hand")
		ik.Target = target
		ik.Pole = elbow
		ik.SmoothTime = 0
		ik.Weight = 0
		ik.Enabled = false -- (on only while a hand has a goal: see observe)
		ik.Parent = rig.humanoid
		self.reach[side] = { shoulder = rig.bone(side .. "Arm"), target = target, ik = ik, weight = 0, goal = nil }
	end
	return self
end

-- eased 0..1
local function ease(s: number): number
	s = math.clamp(s, 0, 1)
	return s * s * (3 - 2 * s)
end

-- How much of the carried pose is still held
function FullBody:carryKeep(): number
	return 1 - ease(self.carryT / INERTIAL_TIME)
end

-- A new clip takes over this frame (Rig:driveTracks)
function FullBody:beginSwitch()
	self.switchPending = true
	self.footSwitch = 2 -- (the track weights reach the foot targets a frame later)
end

function FullBody:takeFootSwitch(): boolean
	if self.footSwitch > 0 then
		self.footSwitch -= 1
		return true
	end
	return false
end

-- Weight: every footfall drops the pelvis a little on its spring; the knees give because the feet
-- are held. Heavier the faster the body travels.
function FullBody:footfall(speed: number)
	if layerOn("Weight") and layerOn("PelvisSpring") then
		self.pelvisVel -= WEIGHT_STEP * math.clamp(speed / 8, 0.4, 1.6)
	end
end

-- KneeOverToe: a knee points where the foot under it points, give or take. The clips let it turn
-- in of the foot (more than 15 degrees on 43% of planted frames at a run, 8% walking), and a foot
-- held to the ground while the body turns is left pointing somewhere the clip's knee is not.
-- bend, toes: the clip's knee direction and foot direction (root space); yawOffset: how far the
-- foot's heading is held off the clip's. Returns the knee direction to use.
function FullBody:kneeOverToe(side: string, bend: Vector3, toes: Vector3, yawOffset: number): Vector3
	if not layerOn("KneeOverToe") then
		return bend
	end
	local foot = CFrame.Angles(0, yawOffset, 0) * (toes * FLAT)
	local knee = bend * FLAT
	if foot.Magnitude < 0.2 or knee.Magnitude < 0.05 then
		return bend -- a foot pointing down, or a straight leg: no direction to compare
	end
	local turn = math.atan2(foot.Unit:Cross(knee.Unit).Y, foot.Unit:Dot(knee.Unit)) -- + = knee to the left of the foot
	local inward = side == "Left" and -turn or turn
	local excess = 0
	if inward > KNEE_IN_MAX then
		excess = inward - KNEE_IN_MAX
	elseif inward < -KNEE_OUT_MAX then
		excess = inward + KNEE_OUT_MAX
	end
	if excess == 0 then
		return bend
	end
	return CFrame.Angles(0, side == "Left" and excess or -excess, 0) * bend
end

-- Stride warp: when the body moves slower or faster than the clips' feet do, the step is
-- shortened or stretched along the clip's travel, so a planted foot stays planted.
function FullBody:strideScale(base: CFrame, dt: number): (number, Vector3?)
	local goal, direction = 1, nil
	if layerOn("StrideWarp") and not Conductor.airborne then
		local travel = self.rig:clipTravel()
		if travel.Magnitude >= STRIDE_MIN_SPEED then
			direction = travel.Unit
			local actual = base:VectorToObjectSpace(self.velocity * FLAT):Dot(direction)
			goal = math.clamp(actual / travel.Magnitude, STRIDE_MIN, STRIDE_MAX)
		end
	end
	self.stride += (goal - self.stride) * decay(10, dt)
	if not direction or math.abs(self.stride - 1) < 0.01 then
		return 1, nil
	end
	return self.stride, direction
end

-- Once per frame before the solve: how the body is moving, and every layer's state.
function FullBody:observe(base: CFrame, dt: number)
	local step = math.min(dt, 1 / 30) -- springs stay stable through a slow frame
	self.clock += step
	self.carryT += dt
	if self.rig.props then
		local shown = layerOn("Props")
		if shown ~= self.propsShown then
			self.propsShown = shown
			self.rig:showProps(shown)
		end
	end
	local yaw = Conductor.yaw
	if Conductor.cut or not self.prevBase then
		self.velocity, self.accel, self.yawRate = Vector3.zero, Vector3.zero, 0
		-- (nothing is carried across a cut: not a hand's goal, not a pose)
		for _, arm in self.reach do
			arm.goal, arm.weight = nil, 0
		end
		self.carry, self.hipsCarry, self.hipsLast = nil, CFrame.identity, nil
		self.switchPending, self.footSwitch, self.carryT = false, 0, INERTIAL_TIME
	else
		local velocity = (base.Position - self.prevBase.Position) / dt
		local accel = (velocity - self.velocity) / dt
		if accel.Magnitude > ACCEL_LIMIT then
			accel = accel.Unit * ACCEL_LIMIT
		end
		self.accel = self.accel:Lerp(accel, decay(ACCEL_SMOOTH_RATE, dt))
		self.velocity = velocity
		self.yawRate += (wrapAngle(yaw - self.prevYaw) / dt - self.yawRate) * decay(ACCEL_SMOOTH_RATE, dt)
	end
	self.prevBase, self.prevYaw = base, yaw

	local _, normal = castDown(base.Position.X, base.Position.Y, base.Position.Z)
	self.groundNormal = self.groundNormal:Lerp(normal, decay(8, dt)).Unit

	-- landing: the fall speed goes into the pelvis spring
	if self.wasAirborne and not Conductor.airborne then
		self.pelvisVel -= math.clamp(-self.velocity.Y * LANDING_DIP, 0, 10)
	end
	self.wasAirborne = Conductor.airborne

	-- lean
	local lean = Vector3.zero
	if layerOn("Lean") then
		lean += self.accel * FLAT * LEAN_PER_ACCEL + self.velocity * FLAT * LEAN_PER_SPEED
	end
	if layerOn("SlopeLean") then
		lean -= self.groundNormal * FLAT * SLOPE_LEAN * math.min(1, (self.velocity * FLAT).Magnitude / 5)
	end
	if lean.Magnitude > LEAN_MAX then
		lean = lean.Unit * LEAN_MAX
	end
	self.lean, self.leanVel = springStep(self.lean, self.leanVel, lean, 7, 1, step)

	-- arms: a loose arm hangs along gravity minus the body's acceleration (it floats in free fall)
	local hang = DOWN * GRAVITY - self.accel
	local swing = layerOn("ArmLag") and hang.Magnitude > 20 and hang.Unit - DOWN or Vector3.zero
	self.armSwing, self.armSwingVel = springStep(self.armSwing, self.armSwingVel, swing, ARM_OMEGA, ARM_DAMPING, step)
	self.foreSwing, self.foreSwingVel = springStep(self.foreSwing, self.foreSwingVel, swing, FORE_OMEGA, FORE_DAMPING, step)
	self.handSwing, self.handSwingVel = springStep(self.handSwing, self.handSwingVel, swing, HAND_OMEGA, HAND_DAMPING, step)

	-- hands: the hand nearest a rail within reach rests on it (one hand: the other stays free);
	-- a free left hand points at the look target when that is in front and near
	local railSide, railPoint, railDistance = nil, nil, math.huge
	if layerOn("Contact") and not Conductor.airborne then
		for _, side in SIDES do
			local arm = self.reach[side]
			local shoulder = arm.shoulder.TransformedWorldCFrame.Position
			local point = nearestRailPoint(shoulder, arm.ik:GetChainLength() * 0.97)
			-- (only a rail on its own side: reaching for one across the body puts the arm through the chest)
			local outward = base.RightVector * (side == "Left" and -1 or 1)
			if point and (point - shoulder):Dot(outward) < 0 then
				point = nil
			end
			-- (the hand already on a rail keeps it unless the other is clearly nearer)
			local distance = point and (point - shoulder).Magnitude - (arm.onRail and 0.5 or 0) or math.huge
			if distance < railDistance then
				railSide, railPoint, railDistance = side, point, distance
			end
		end
	end
	for _, side in SIDES do
		local arm = self.reach[side]
		local shoulder = arm.shoulder.TransformedWorldCFrame.Position
		local length = arm.ik:GetChainLength()
		local goal, weight, rate = nil, 0, 4
		arm.onRail = side == railSide
		if arm.onRail then
			goal, weight, rate = railPoint, CONTACT_WEIGHT, 8
		end
		if not goal and side == "Left" and layerOn("Point") and not Conductor.airborne then
			local to = lookTarget.Position - shoulder
			local direction = base:VectorToObjectSpace(to.Unit)
			local bearing = math.atan2(-direction.X, -direction.Z) -- + = to the left
			-- (ahead or to its own side, never across the body)
			if bearing > -POINT_ACROSS and bearing < POINT_CONE and to.Magnitude < POINT_RANGE then
				goal, weight = shoulder + to.Unit * length * 0.9, POINT_WEIGHT
			end
		end
		arm.weight += (weight - arm.weight) * decay(rate, step)
		if goal then
			-- the hand travels to a new goal; it does not jump there
			arm.goal = arm.goal and arm.weight > 0.05 and arm.goal:Lerp(goal, decay(14, step)) or goal
			arm.target.WorldPosition = arm.goal
		elseif arm.weight < 0.02 then
			arm.goal = nil
		end
		arm.ik.Weight = arm.weight
		-- The engine's arm IK takes the hand's own rotation away even at weight 0 (the wrists
		-- freeze flat), so it is on only while the hand has somewhere to be.
		local active = arm.weight > 0.01
		if arm.ik.Enabled ~= active then
			arm.ik.Enabled = active
		end
	end
end

function FullBody:pelvis(current: number, goal: number, dt: number): number
	if not layerOn("PelvisSpring") then
		self.pelvisVel = 0
		return current + (goal - current) * decay(PELVIS_RATE, dt)
	end
	local value
	value, self.pelvisVel = springStep(current, self.pelvisVel, goal, PELVIS_OMEGA, PELVIS_DAMPING, math.min(dt, 1 / 30))
	return math.clamp(value, PELVIS_MIN - 0.5, PELVIS_MAX)
end

-- forwardGap: how far the right foot is ahead of the left in the clip (studs, root space)
function FullBody:tiltRoot(rootCF: CFrame, forwardGap: number, dt: number): CFrame
	local twist = layerOn("HipTwist") and math.clamp(forwardGap * TWIST_PER_STUD, -TWIST_MAX, TWIST_MAX) or 0
	self.twist += (twist - self.twist) * decay(15, dt)
	local out = rootCF * CFrame.Angles(0, self.twist, 0)
	local amount = self.lean.Magnitude
	if amount > 1e-4 then
		-- tilt about the ground under the body, toward the lean
		local pivot = rootCF.Position - Vector3.new(0, ROOT_HEIGHT, 0)
		out = CFrame.new(pivot) * CFrame.fromAxisAngle(Vector3.yAxis:Cross(self.lean.Unit), amount) * CFrame.new(-pivot) * out
	end
	-- the hips' share of a carried pose: moving the root moves the hips and leaves the feet to the IK
	return out * self:hipsCarryNow()
end

function FullBody:hipsCarryNow(): CFrame
	local keep = self:carryKeep()
	return keep > 0 and CFrame.identity:Lerp(self.hipsCarry, keep) or CFrame.identity
end

-- What the head looks at: the opponent it circles, else the look target
function FullBody:lookPoint(): Vector3
	if Conductor.mode == "circle" and Conductor.watchCentre then
		local x, z = circleCentre(self.rig.index)
		return Vector3.new(x, self.rig.root.Position.Y + 1, z)
	end
	return lookTarget.Position
end

-- Once per animation step, after animation and IK: the pose-level layers.
-- dt: the time since the last step (LookController's spring).
function FullBody:pose(dt: number)
	local rig = self.rig
	local amount = self.lean.Magnitude

	-- ThighTwist: the leg IK puts the knee and the foot where they belong but rolls the thigh about
	-- its own length as it likes (up to 70 degrees off the clip: knees that look turned in). The
	-- thigh is rolled back to the clip's, and the shin is turned the other way by the same amount,
	-- so the knee joint, the shin and the foot stay exactly where the IK put them.
	if layerOn("ThighTwist") and rig.ikWeight > 0.01 then
		for _, side in SIDES do
			local thigh, shin = rig.legs[side].hip, rig.legs[side].knee
			local axis, angle = (rig:clipRotation("thigh", side):Inverse() * thigh.Transform.Rotation):ToAxisAngle()
			-- the part of that turn that is about the bone's own length (its Y axis)
			local twist = 2 * math.atan2(axis.Y * math.sin(angle / 2), math.cos(angle / 2))
			twist = wrapAngle(twist) * rig.ikWeight
			if math.abs(twist) > 1e-3 then
				thigh.Transform *= CFrame.Angles(0, -twist, 0)
				shin.Transform = shin.CFrame:Inverse() * CFrame.Angles(0, twist, 0) * shin.CFrame * shin.Transform
			end
		end
	end

	-- A hand the arm IK holds has lost its own rotation: it gets the clip's back.
	for _, side in SIDES do
		if self.reach[side].ik.Enabled then
			self.hands[side].Transform = rig:clipRotation("hand", side)
		end
	end

	-- SquareUp: a strafe clip walks along its travel with the chest turned most of the way with it
	-- (hips about 65 degrees, chest about 42, the head already to the front). This turns the chest
	-- back to the front, the more the clips travel sideways, and leaves the head where the clip
	-- has it. Measured from the shoulders before anything else touches the spine; spread over the
	-- three spine bones so no one joint takes the twist.
	local squared = 0 -- the yaw the spine was turned by (radians)
	do
		local travel = rig:clipTravel()
		local sideways = travel.Magnitude > 0.5 and math.abs(travel.Unit.X) or 0
		local turned = 0
		if layerOn("SquareUp") and sideways > 0.05 then
			local across = rig.root.CFrame:VectorToObjectSpace(
				self.arms.Right[1].TransformedWorldCFrame.Position - self.arms.Left[1].TransformedWorldCFrame.Position)
			local facing = Vector3.yAxis:Cross(across)
			turned = math.atan2(-facing.X, -facing.Z) * sideways
		end
		self.square += (turned - self.square) * decay(SQUARE_RATE, dt) -- (the average: the shoulders keep their swing)
		local correction = math.clamp(-self.square * SQUARE_GAIN, -SQUARE_MAX, SQUARE_MAX)
		if math.abs(correction) > 1e-3 then
			local rotation = CFrame.fromAxisAngle(rig.root.CFrame.UpVector, correction / 3)
			for _, bone in { self.spine[1], self.spine[2], self.chest } do
				rotateWorld(bone, rotation)
			end
			squared = correction
		end
	end

	-- the head follows its target (QuinCore's LookController: in front only, capped, on a spring)
	if layerOn("Look") then
		self.look:setTargetOverride(self:lookPoint())
		self.look:update(dt)
	end
	if squared ~= 0 then
		-- (the head rode round with the chest: the neck takes that turn back out)
		rotateWorld(self.neck, CFrame.fromAxisAngle(rig.root.CFrame.UpVector, -squared))
	end

	if layerOn("SpineCounter") then
		local yaw = -self.twist + math.clamp(self.yawRate * TURN_LOOK, -TURN_LOOK_MAX, TURN_LOOK_MAX)
		local rotation = CFrame.Angles(0, yaw / 2, 0)
		if amount > 1e-4 then
			rotation = CFrame.fromAxisAngle(Vector3.yAxis:Cross(self.lean.Unit), -amount * COUNTER_LEAN / 2) * rotation
		end
		for _, bone in self.spine do
			rotateWorld(bone, rotation)
		end
	end

	if layerOn("Breath") then
		local idle = rig.weights[IDLE.path] or 0
		local angle = math.sin(self.clock * 2 * math.pi * BREATH_HZ) * BREATH_ANGLE * idle
		rotateWorld(self.spine[2], CFrame.fromAxisAngle(rig.root.CFrame.RightVector, angle))
	end

	-- ArmLag: the arm sways the way a loose arm would under the body's acceleration, and not as
	-- one stick: the forearm takes the sway up later and looser than the upper arm (the elbow
	-- gives), the hand later again (the wrist gives).
	-- SoftElbows: an elbow is never quite straight.
	local swayAxis, swayAngle = nil, 0
	if self.armSwing.Magnitude > 1e-3 then
		swayAxis, swayAngle = CFrame.fromRotationBetweenVectors(DOWN, (DOWN + self.armSwing).Unit):ToAxisAngle()
		swayAngle = math.min(swayAngle, ARM_MAX)
	end
	for side, arm in self.arms do
		local loose = 1 - self.reach[side].weight -- (an arm the IK holds to a goal is left where the IK put it)
		if loose > 0.01 then
			local upper, fore, hand = arm[1], arm[2], self.hands[side]
			if swayAxis and swayAngle * loose > 1e-3 then
				rotateWorld(upper, CFrame.fromAxisAngle(swayAxis, swayAngle * loose))
			end

			-- the elbow: its bend now, the bend the forearm's lag adds or takes, and the floor under both
			local elbow = fore.TransformedWorldCFrame.Position
			local along = (hand.TransformedWorldCFrame.Position - elbow).Unit
			local bend = math.acos(math.clamp((elbow - upper.TransformedWorldCFrame.Position).Unit:Dot(along), -1, 1)) -- 0 = straight
			local hinge = self.elbowAxis[side]
			local bendsToward = fore.TransformedWorldCFrame:VectorToWorldSpace(hinge):Cross(along) -- the way the wrist goes as the elbow bends
			local lag = math.clamp((self.foreSwing - self.armSwing):Dot(bendsToward) * FORE_GAIN, -FORE_MAX, FORE_MAX)
			local wantedBend = math.max(bend + lag, layerOn("SoftElbows") and ELBOW_MIN or 0)
			if math.abs(wantedBend - bend) > 1e-3 then
				fore.Transform *= CFrame.fromAxisAngle(hinge, (wantedBend - bend) * loose)
			end

			-- the wrist
			local drag = (self.handSwing - self.foreSwing) * HAND_GAIN
			if drag.Magnitude > 1e-3 then
				local axis, angle = CFrame.fromRotationBetweenVectors(DOWN, (DOWN + drag).Unit):ToAxisAngle()
				rotateWorld(hand, CFrame.fromAxisAngle(axis, math.min(angle, HAND_MAX) * loose))
			end
		end
	end

	-- ArmClear: the layers above move the arms and the chest; an elbow or a wrist that ends up
	-- inside the trunk is pushed back out to its surface.
	if layerOn("ArmClear") then
		local low = self.hips.TransformedWorldCFrame.Position - rig.root.CFrame.UpVector * TRUNK_BELOW_HIPS
		local line = self.chest.TransformedWorldCFrame.Position - low
		-- Where a point inside the trunk should be instead, or nil if it is outside. `toward`: the
		-- side to come out on. The deeper the point, the more that decides the way out (a point at
		-- the centre has no "nearest side" of its own, and the far side means through the chest).
		local function pushedOut(point: Vector3, toward: Vector3): Vector3?
			local onLine = low + line * math.clamp((point - low):Dot(line) / line:Dot(line), 0, 1)
			local out = point - onLine
			local depth = out.Magnitude
			if depth >= ARM_CLEAR then
				return nil
			end
			out = out + toward * (ARM_CLEAR - depth)
			if out.Magnitude < 0.05 then
				out = toward
			end
			return onLine + out.Unit * ARM_CLEAR
		end
		for side, arm in self.arms do
			local ownSide = rig.root.CFrame.RightVector * (side == "Left" and -1 or 1)
			local shoulder = arm[1].TransformedWorldCFrame.Position
			local elbow = arm[2].TransformedWorldCFrame.Position
			local clear = pushedOut(elbow, ownSide)
			if clear then
				rotateWorld(arm[1], CFrame.fromRotationBetweenVectors((elbow - shoulder).Unit, (clear - shoulder).Unit))
				elbow = arm[2].TransformedWorldCFrame.Position
			end
			-- the wrist comes out on the elbow's side. (Also on an arm the IK holds: a goal that would
			-- put the hand in the chest loses.) The forearm's length is fixed, so the point it is
			-- turned toward is not always reached at once: a second pass settles it.
			local elbowSide = elbow - (low + line * math.clamp((elbow - low):Dot(line) / line:Dot(line), 0, 1))
			elbowSide = elbowSide.Magnitude > 0.05 and elbowSide.Unit or ownSide
			for _ = 1, 2 do
				local wrist = self.hands[side].TransformedWorldCFrame.Position
				clear = pushedOut(wrist, elbowSide)
				if not clear then break end
				rotateWorld(arm[2], CFrame.fromRotationBetweenVectors((wrist - elbow).Unit, (clear - elbow).Unit))
			end
		end
	end

	if layerOn("Toes") and not Conductor.airborne then
		for side, toe in self.toes do
			local foot = rig.feet[side]
			local world = toe.TransformedWorldCFrame
			local near = 1 - math.clamp((world.Position.Y - foot.groundY - 0.15) / TOE_FADE, 0, 1)
			local along = world.UpVector -- the toe bone points along its Y axis
			local into = along:Dot(foot.normal)
			if near > 0 and into < 0 then
				local flat = along - foot.normal * into
				if flat.Magnitude > 0.1 then
					rotateWorld(toe, CFrame.identity:Lerp(CFrame.fromRotationBetweenVectors(along, flat.Unit), near))
				end
			end
		end
	end

	self:carryPose()
end

-- Inertial: a new clip takes over at once, and the pose that was on screen is carried into it
-- and let go over INERTIAL_TIME. (A cross-fade shows a mix of two poses that neither clip has.)
-- Runs last, so what it carries is the pose as drawn, every other layer included.
function FullBody:carryPose()
	local root = self.rig.root.CFrame
	-- the hips relative to the root as it would be with nothing carried
	local hipsNow = self:hipsCarryNow() * root:ToObjectSpace(self.hips.TransformedWorldCFrame)

	if self.switchPending and self.hipsLast then
		self.switchPending = false
		local plain = root * self:hipsCarryNow():Inverse()
		local hipsClip = root:ToObjectSpace(self.hips.TransformedWorldCFrame) -- the new clip's hips
		self.carry = {}
		for _, bone in self.carryBones do
			self.carry[bone] = bone.Transform:Inverse() * self.lastLocal[bone]
		end
		self.hipsCarry = self.hipsLast * hipsClip:Inverse()
		self.carryT = 0
		-- this step was solved before the switch was known: put the hips back by hand, once
		local world = self.hips.TransformedWorldCFrame
		self.hips.Transform *= world:Inverse() * (plain * self.hipsLast) -- so its world CFrame becomes plain * hipsLast
		hipsNow = self.hipsLast
	end
	self.switchPending = false

	if self.carry then
		local keep = self:carryKeep()
		if keep <= 0 then
			self.carry = nil
		else
			local free = 1 - self.rig.ikWeight -- how far the legs are the clip's, not the IK's
			for bone, offset in self.carry do
				local share = self.carryLegs[bone] and keep * free or keep
				if share > 0.001 then
					bone.Transform *= CFrame.identity:Lerp(offset, share)
				end
			end
		end
	end
	for _, bone in self.carryBones do
		self.lastLocal[bone] = bone.Transform
	end
	self.hipsLast = hipsNow
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
	local baked = { foot = { Left = {}, Right = {} }, hip = { Left = {}, Right = {} }, knee = { Left = {}, Right = {} }, toe = { Left = {}, Right = {} }, thigh = { Left = {}, Right = {} }, hand = { Left = {}, Right = {} }, travel = Vector3.zero, length = track.Length }
	for i = 1, BAKE_SAMPLES do
		track.TimePosition = (i - 1) / BAKE_SAMPLES * track.Length
		for _ = 1, 3 do RunService.Heartbeat:Wait() end
		for _, side in SIDES do
			baked.foot[side][i] = rig.root.CFrame:ToObjectSpace(rig.legs[side].foot.TransformedWorldCFrame)
			baked.hip[side][i] = rig.root.CFrame:PointToObjectSpace(rig.legs[side].hip.TransformedWorldCFrame.Position)
			baked.knee[side][i] = rig.root.CFrame:PointToObjectSpace(rig.legs[side].knee.TransformedWorldCFrame.Position)
			baked.toe[side][i] = rig.root.CFrame:PointToObjectSpace(rig.legs[side].toe.TransformedWorldCFrame.Position)
			-- bones whose own pose the IK takes away, as the clip has them
			baked.thigh[side][i] = rig.legs[side].hip.Transform.Rotation
			baked.hand[side][i] = rig.handBones[side].Transform.Rotation
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
	bar.Size = UDim2.fromOffset(960, 96)
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
	button("Strafe test", 816, 10, 134, set("Clip", "#Strafe"))

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

	-- lane D's layers, one switch each
	local panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(0, 1)
	panel.Position = UDim2.new(0, 16, 1, -16)
	panel.Size = UDim2.fromOffset(150, 30 + #LAYERS * 26)
	panel.BackgroundColor3 = Color3.fromRGB(15, 20, 30)
	panel.BackgroundTransparency = 0.15
	panel.Parent = gui
	Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 8)
	local heading = hint:Clone()
	heading.Position = UDim2.fromOffset(0, 2)
	heading.Size = UDim2.new(1, 0, 0, 24)
	heading.Text = "Lane D layers"
	heading.TextSize = 13
	heading.Parent = panel
	for index, name in LAYERS do
		local b = Instance.new("TextButton")
		b.Position = UDim2.fromOffset(8, 28 + (index - 1) * 26)
		b.Size = UDim2.new(1, -16, 0, 22)
		b.TextColor3 = Color3.new(1, 1, 1)
		b.Font = Enum.Font.GothamBold
		b.TextSize = 12
		b.Parent = panel
		Instance.new("UICorner", b).CornerRadius = UDim.new(0, 5)
		local function show()
			b.Text = name .. (layerOn(name) and "  ON" or "  off")
			b.BackgroundColor3 = layerOn(name) and Color3.fromRGB(40, 110, 70) or Color3.fromRGB(70, 45, 45)
		end
		b.MouseButton1Click:Connect(function()
			lab:SetAttribute("D_" .. name, not layerOn(name))
		end)
		local changed = lab:GetAttributeChangedSignal("D_" .. name):Connect(show)
		b.Destroying:Connect(function()
			changed:Disconnect()
		end)
		show()
	end

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
	local lanes = table.clone(rigs) -- the four that are measured
	-- the point each lane circles (its "opponent" in the strafe test)
	for index in LANES do
		local x, z = circleCentre(index)
		local marker = Instance.new("Part")
		marker.Name = "CircleCentre"
		marker.Shape = Enum.PartType.Ball
		marker.Size = Vector3.one * 1.2
		marker.Anchored, marker.CanCollide, marker.CanQuery = true, false, false
		marker.Material = Enum.Material.Neon
		marker.Color = Color3.fromRGB(255, 120, 90)
		marker.Position = Vector3.new(x, FLOOR_Y + 6, z)
		marker.Parent = runtime
	end
	-- the cost test: more full-procedural Quins on the open floor beside the course
	for i = 1, lab:GetAttribute("Crowd") or 0 do
		local z = CROWD_Z[(i - 1) % #CROWD_Z + 1]
		table.insert(rigs, Rig.new(#rigs + 1, { key = "X" .. i, z = z, row = (i - 1) // #CROWD_Z, mode = "full", full = true, crowd = true, title = "" }, runtime))
	end
	local perf = { frames = 0, steps = 0, before = 0, pose = 0, time = 0 } -- frames: drawn; steps: animation steps

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
			elseif path == "#Strafe" then
				title.Text = "loading the strafe clips"
				for _, strafeClip in STRAFE_CLIPS do
					bake(rigs[1], strafeClip)
					if mine ~= session or lab:GetAttribute("Clip") ~= path then return end
				end
				title.Text = "Strafe test: each strafe clip along a line, then circling a point it faces"
				run(strafeTest)
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
		local first, last = lanes[1].root.Position, lanes[#lanes].root.Position
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

	-- pose-level layers: after animation and IK, before the frame is drawn. The engine rewrites
	-- every bone on each animation step, so the edits are made once per step.
	local poseFresh = false
	table.insert(connections, RunService.PreAnimation:Connect(function()
		poseFresh = true
	end))
	-- The measurements are taken here too, from the pose as it is about to be drawn. (The engine
	-- can run several animation steps per drawn frame; read at PreAnimation, the steps in between
	-- show the pose without these edits and look like a flicker that is never on screen.)
	local poseDt = 0
	local cutSeen = true -- the rigs were moved discontinuously since the last measurement
	RunService:BindToRenderStep("IKLabPose", Enum.RenderPriority.Last.Value - 1, function(dt)
		poseDt += dt
		if not poseFresh then return end
		local started = os.clock()
		for _, rig in rigs do
			if rig.full then
				rig.full:pose(poseDt)
			end
		end
		perf.pose += os.clock() - started
		perf.frames += 1

		if not busy and programme and not lab:GetAttribute("Paused") then
			local elapsed = poseDt * (lab:GetAttribute("TimeScale") or 1)
			local tag = Conductor.tag
			local footKey = Conductor.mode == "course" and tag .. ":" .. sectionAt(Conductor.x) or tag
			local continuous = not cutSeen -- (a cut starts the history again)
			for _, rig in lanes do
				rig:measureFeet(elapsed, footKey, continuous)
				rig:sampleBody()
			end
			for _, rig in lanes do
				rig:measureBody(lanes[1], elapsed, tag, continuous)
			end
			cutSeen = false
		end
		poseFresh, poseDt = false, 0
	end)
	table.insert(cleanup, function()
		RunService:UnbindFromRenderStep("IKLabPose")
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
		perf.steps += 1

		-- 1. last step's cut has been acted on
		local tag = Conductor.tag
		local footKey = Conductor.mode == "course" and tag .. ":" .. sectionAt(Conductor.x) or tag
		Conductor.cut = false
		local started = os.clock()

		-- 2. advance the shared movement script
		local ok, message = coroutine.resume(programme, dt)
		if not ok then
			warn("[IKLabDemo] " .. tostring(message))
			programme = nil
			return
		end
		if message == "publish" then
			for _, rig in lanes do rig:publish() end
			coroutine.resume(programme, dt)
		end

		-- 3. drive every rig
		for _, rig in rigs do
			rig:driveTracks(dt, scale)
			rig:update(dt)
		end
		Conductor.restart = {}
		if Conductor.cut then
			cutSeen = true
		end

		-- what all this costs: script time before the solve and at the pose step, per frame
		perf.before += os.clock() - started
		perf.time += dt / scale
		if perf.time >= 1 then
			lab:SetAttribute("Perf", string.format("rigs %d (full %d)  per animation step %.2f ms (%.0f steps/s)  per drawn frame %.2f ms (%.0f fps)",
				#rigs, #rigs - 3, perf.before / perf.steps * 1000, perf.steps / perf.time,
				perf.pose / math.max(1, perf.frames) * 1000, perf.frames / perf.time))
			perf.frames, perf.steps, perf.before, perf.pose, perf.time = 0, 0, 0, 0, 0
		end

		labelTimer += dt
		if labelTimer > 0.25 then
			labelTimer = 0
			for _, rig in lanes do
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
