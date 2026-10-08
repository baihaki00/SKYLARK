--// LocomotionModule.lua
-- Authoritative Locomotion, Momentum Integration, Ballistic Jumps, and Traction Controller
-- Adheres strictly to the 6 Immutable Ground Rules (README.md)
-- Single Source of Truth: ReplicatedStorage.QuinCore.CombatConfig

local DebugDraw = require(game:GetService("ReplicatedStorage"):WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("DebugDraw"))
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")

local QuinCore = ReplicatedStorage:WaitForChild("QuinCore")
local CombatConfig = require(QuinCore:WaitForChild("CombatConfig"))
local AnimationModule = require(QuinCore:WaitForChild("Modules"):WaitForChild("AnimationModule"))
local KnockbackModule = require(QuinCore:WaitForChild("Modules"):WaitForChild("KnockbackModule"))
local SpatialModule = require(QuinCore:WaitForChild("Modules"):WaitForChild("SpatialModule"))
local AudioModule = require(QuinCore:WaitForChild("Modules"):WaitForChild("AudioModule"))
local VfxModule = require(QuinCore:WaitForChild("Modules"):WaitForChild("VfxModule"))
local TraversalModule = require(QuinCore:WaitForChild("Modules"):WaitForChild("TraversalModule"))
local GaitModule = require(QuinCore:WaitForChild("Modules"):WaitForChild("GaitModule"))
local BodyAwareness = require(QuinCore:WaitForChild("Modules"):WaitForChild("BodyAwareness"))

local LocomotionModule = {}

-- Highest apex a jump may be asked for: what a jump can gain (Jump_MaxReach) plus the clearance
-- over the top it lands on
local MAX_JUMP_HEIGHT = (CombatConfig.Jump_MaxReach or 25) + 2

-- Active full-body locomotion actions (run slide), keyed by fighter
local activeSlides = {}
local endSlide -- forward declaration (section 5)

local function isHumanoidAirborne(humanoid)
	local s = humanoid:GetState()
	return s == Enum.HumanoidStateType.Freefall or s == Enum.HumanoidStateType.Jumping
end

-- Feet on something, by a ray (Humanoid.FloorMaterial and the Humanoid state lag a landing by
-- a few tenths of a second: crossings planned on a landing were dropped, and the edge guard
-- was off while the body drifted to the lip)
function LocomotionModule.isOnGround(rootPart, humanoid)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { rootPart.Parent, Workspace:FindFirstChild("QuinServer") }
	params.RespectCanCollide = true
	local reach = (humanoid and humanoid.HipHeight or 4.2) + rootPart.Size.Y / 2 + 0.9
	return Workspace:Raycast(rootPart.Position, Vector3.new(0, -reach, 0), params) ~= nil
end

function LocomotionModule.isSliding(fighter)
	return fighter ~= nil and activeSlides[fighter] ~= nil
end

-- Per-fighter tracking table (weak keys to prevent memory leaks on Quin death)
local locoData = setmetatable({}, { __mode = "k" })




local function getLocoData(fighter)
	if not locoData[fighter] then
		locoData[fighter] = {
			lastJumpTime = 0,
			lastSkidTime = 0,
			currentSpeed = 0,
			distanceTraveled = 0,
			activeLandedConn = nil,
			activeAlign = nil,
			activeAtt = nil,
		}
	end
	return locoData[fighter]
end

local function flatUnit(vector, fallback)
	local flat = Vector3.new(vector.X, 0, vector.Z)
	if flat.Magnitude > 0.001 then
		return flat.Unit
	end
	return fallback
end

-- The agile body (CombatConfig.Body_Agile, design doc phase 1): a superhuman's grip and quick
-- reversals. Every tuning read below that has a "<key>_Agile" value takes it while the switch is
-- on; off, the earlier values.
local IS_STUDIO = RunService:IsStudio()
local function tune(key, default)
	-- (Studio: a Workspace attribute Tune_<key> overrides it live, for tuning by feel and by probe)
	if IS_STUDIO then
		local live = Workspace:GetAttribute("Tune_" .. key)
		if live ~= nil then return live end
	end
	if CombatConfig.Body_Agile ~= false then
		local agile = CombatConfig[key .. "_Agile"]
		if agile ~= nil then return agile end
	end
	local v = CombatConfig[key]
	if v == nil then return default end
	return v
end

-- Fraction of the soft-landing clip spent absorbing the drop (the rest is the rise)
local LANDING_ABSORB_RATIO = 0.55

local function shortestAngleDelta(target, current)
	return (target - current + math.pi) % (2 * math.pi) - math.pi
end

-- Pure 360° Omnidirectional Free Movement (GTA V / Watch Dogs 2 style):
-- The player or AI supplies desired movement direction in horizontal space.
-- A single continuous damped angular state carves realistic turn radius and physical weight
-- with ZERO angular snapping, ZERO forward-bias squashing, and isotropic 360° responsiveness.
function LocomotionModule.resolveGroundIntent(fighter, rootPart, desiredDirection, dt, referenceForward)
	if not rootPart or not desiredDirection then return Vector3.zero end
	dt = math.clamp(dt or 0.016, 0.001, 0.15)

	local desired = flatUnit(desiredDirection, nil)
	if not desired then return Vector3.zero end

	local data = getLocoData(fighter)
	local rootForward = flatUnit(rootPart.CFrame.LookVector, Vector3.new(0, 0, -1))

	-- Continuous damped heading arc (GTA V / Watch Dogs turn curve)
	local current = data.groundIntentDirection
	if not current or current.Magnitude < 0.1 then
		local velocity = Vector3.new(rootPart.AssemblyLinearVelocity.X, 0, rootPart.AssemblyLinearVelocity.Z)
		current = flatUnit(velocity, rootForward)
	end

	local currentAngle = math.atan2(current.X, current.Z)
	local targetAngle = math.atan2(desired.X, desired.Z)
	local delta = shortestAngleDelta(targetAngle, currentAngle)
	local response = tune("Locomotion_GroundTurnResponse", 16.0)
	local alpha = 1.0 - math.exp(-response * dt)

	-- Speed-scaled yaw-rate ceiling: at pace, momentum widens the turn radius instead of
	-- snapping the heading like a cursor; at walking pace pivots stay nimble.
	-- Committed reversals are handled by the skid plant in steer(), which sheds speed first.
	local planarVel = rootPart.AssemblyLinearVelocity
	local planarSpeed = Vector3.new(planarVel.X, 0, planarVel.Z).Magnitude
	local slowSpeed = CombatConfig.Locomotion_TurnRateSlowSpeed or 8.0
	local fastSpeed = CombatConfig.Locomotion_TurnRateFastSpeed or 44.0
	local paceT = math.clamp((planarSpeed - slowSpeed) / math.max(fastSpeed - slowSpeed, 1), 0, 1)
	local slowRate = tune("Locomotion_TurnRateSlow", 10.0)
	local maxTurnRate = slowRate + (tune("Locomotion_TurnRateFast", 2.2) - slowRate) * paceT
	-- A runner turns by leaning into the ground, so how fast it can turn falls with speed:
	-- yaw rate = sideways grip / speed. The old ceiling (5.5 rad/s at a 40 stud/s sprint, 14 at
	-- a jog) meant 200-380 studs/s^2 sideways - the body snapped through corners while the run
	-- clip ran straight ahead and the feet skated. Reversals still go through the skid plant.
	local grip = tune("Locomotion_LateralGrip", 90)
	maxTurnRate = math.min(maxTurnRate, grip / math.max(planarSpeed, 1))
	local step = math.clamp(delta * alpha, -maxTurnRate * dt, maxTurnRate * dt)
	local nextAngle = currentAngle + step
	local resolved = Vector3.new(math.sin(nextAngle), 0, math.cos(nextAngle))
	data.groundIntentDirection = resolved
	return resolved
end

function LocomotionModule.resetGroundIntent(fighter)
	local data = locoData[fighter]
	if data then
		data.groundIntentDirection = nil
	end
end


-- ============================================================================
-- 1. ACCELERATION & BRAKING (Smooth velocity modulation; zero 1-frame snaps)
-- ============================================================================

function LocomotionModule.isJumpSuppressed(fighter, humanoid)
	if not fighter or not humanoid then return true end
	if fighter:GetAttribute("DisableJumping") == true then return true end
	if workspace:GetAttribute("DisableJumping") == true then return true end
	if humanoid:GetStateEnabled(Enum.HumanoidStateType.Jumping) == false then return true end
	return false
end

function LocomotionModule.modulateSpeed(fighter, humanoid, targetSpeed, dt)
	dt = math.clamp(dt or 0.016, 0.001, 0.15)
	local data = getLocoData(fighter)
	local currentSpeed = humanoid.WalkSpeed

	local accelRate = tune("Locomotion_Acceleration", 80.0)
	local brakeRate = tune("Locomotion_BrakingDeceleration", 140.0)

	local newSpeed = currentSpeed
	if currentSpeed < targetSpeed then
		newSpeed = math.min(currentSpeed + (accelRate * dt), targetSpeed)
	elseif currentSpeed > targetSpeed then
		newSpeed = math.max(currentSpeed - (brakeRate * dt), targetSpeed)
	end

	humanoid.WalkSpeed = newSpeed
	data.currentSpeed = newSpeed
	fighter:SetAttribute("PacingVelocity", math.floor(newSpeed + 0.5))
	return newSpeed
end

-- ============================================================================
-- 2. STEERING & TRACTION (Dynamic 180° Skid & Continuous Centripetal Steering)
-- ============================================================================

-- Per-frame steer driver (AI Quins). States run at 10 Hz; when the heading and the drive speed
-- were only advanced on that tick, a turning Quin changed direction in up to 30 degree steps
-- and its velocity jumped ~25 studs/s every 0.1s. The state now only refreshes the goal
-- (steerTarget / steerSpeed); this driver advances the turn-rate-limited heading and the
-- acceleration every frame until the goal expires.
local steerConns = setmetatable({}, { __mode = "k" })

-- Facing follows the motion. With AutoRotate the body snapped to face the steer heading while
-- the Humanoid's velocity follows that heading ~0.1 s behind, so on any curve the body faced
-- ahead of where it was going (9-17 degrees on sustained turns, the more the tighter): the run
-- cycle drove one way while the body moved another. While the steer driver moves the body it
-- owns the facing: the actual velocity, turned a little into the turn (a runner looks where it
-- goes), smoothed by an AlignOrientation. Below walking pace and in reversals it faces the
-- heading as before. Any other active AlignOrientation (a state's own facing: Fight's lock on
-- its target, a jump, a recovery) takes precedence, and AutoRotate comes back.
local FACING_NAME = "SteerFacing"

local function otherAlignActive(rootPart)
	for _, child in ipairs(rootPart:GetChildren()) do
		if child:IsA("AlignOrientation") and child.Enabled and child.Name ~= FACING_NAME then
			return true
		end
	end
	return false
end

local function releaseFacing(data, humanoid, rootPart)
	if not data.ownsFacing then return end
	data.ownsFacing = false
	local align = rootPart and rootPart:FindFirstChild(FACING_NAME)
	if align then align.Enabled = false end
	if humanoid and humanoid.Parent then humanoid.AutoRotate = true end
end

local function claimFacing(data, humanoid, rootPart)
	local align = rootPart:FindFirstChild(FACING_NAME)
	if not align then
		local att = rootPart:FindFirstChild("RootAttachment") or Instance.new("Attachment", rootPart)
		att.Name = "RootAttachment"
		align = Instance.new("AlignOrientation")
		align.Name = FACING_NAME
		align.Mode = Enum.OrientationAlignmentMode.OneAttachment
		align.Attachment0 = att
		align.RigidityEnabled = false
		align.Responsiveness = CombatConfig.Locomotion_FacingResponsiveness or 35
		align.MaxTorque = 400000
		align.MaxAngularVelocity = CombatConfig.Locomotion_FacingMaxTurnRate or 14
		align.CFrame = CFrame.lookAt(Vector3.zero, flatUnit(rootPart.CFrame.LookVector, Vector3.new(0, 0, -1)))
		align.Parent = rootPart
	end
	if not data.ownsFacing then
		align.CFrame = CFrame.lookAt(Vector3.zero, flatUnit(rootPart.CFrame.LookVector, Vector3.new(0, 0, -1)))
	end
	align.MaxAngularVelocity = tune("Locomotion_FacingMaxTurnRate", 14)
	align.Enabled = true
	data.ownsFacing = true
	humanoid.AutoRotate = false
end

local function updateFacing(data, rootPart, dt)
	local align = rootPart:FindFirstChild(FACING_NAME)
	local heading = data.groundIntentDirection
	if not align or not heading then return end
	if data.reversal and data.reversal.phase == "pivot" then
		-- turning on the planted foot: the body turns with the heading, led by the constraint's
		-- lag (without the lead it trailed the turn by 30-45 degrees and drove out crabwise)
		data.prevMotionYaw = nil
		data.motionTurnRate = 0
		align.CFrame = CFrame.lookAt(Vector3.zero, data.reversal.facing or heading)
		-- (a straight reversal is already running back the other way: the body turns round with
		-- its target, not ~0.17 s behind it, or it ran backwards for a moment)
		align.Responsiveness = data.reversal.straight and tune("Locomotion_ReversalFacingResponsiveness", 120)
			or (CombatConfig.Locomotion_FacingResponsiveness or 35)
		return
	end
	align.Responsiveness = CombatConfig.Locomotion_FacingResponsiveness or 35
	local v = rootPart.AssemblyLinearVelocity
	local flat = Vector3.new(v.X, 0, v.Z)
	local facing = heading
	if flat.Magnitude > (CombatConfig.Locomotion_FacingMotionMinSpeed or 6) then
		local motion = flat.Unit
		-- The constraint trails a turning target by ~0.11 s (a turn rate of 3 rad/s left the
		-- body 17 degrees behind its motion); the target leads by the motion's own turn rate
		-- times that, so the body arrives on its motion instead of trailing it
		local motionYaw = math.atan2(motion.X, motion.Z)
		local rate = 0
		if data.prevMotionYaw and dt and dt > 0 then
			local delta = (motionYaw - data.prevMotionYaw + math.pi) % (2 * math.pi) - math.pi
			rate = delta / dt
		end
		data.prevMotionYaw = motionYaw
		data.motionTurnRate = (data.motionTurnRate or 0) + (rate - (data.motionTurnRate or 0)) * math.min(1, (dt or 0.016) * 12)
		local lead = math.clamp(data.motionTurnRate * (CombatConfig.Locomotion_FacingLeadTime or 0.11), -0.6, 0.6)
		local leadYaw = motionYaw + lead
		local led = Vector3.new(math.sin(leadYaw), 0, math.cos(leadYaw))
		if motion:Dot(heading) > -0.2 then
			local intoTurn = CombatConfig.Locomotion_FacingIntoTurn or 0.3
			local blended = led + (heading - motion) * intoTurn
			if blended.Magnitude > 0.05 then
				facing = blended.Unit
			end
		end
	else
		data.prevMotionYaw = nil
		data.motionTurnRate = 0
	end
	align.CFrame = CFrame.lookAt(Vector3.zero, facing)
end

-- Reversals (plant and pivot). A sharp reversal at a run used to drop to ~40% speed and then
-- swing round a running U-turn at 17-25 studs/s: about 24 studs of loop, the body spinning at
-- up to 670 degrees/s while the run cycle played, the feet skating. A runner reverses by
-- braking along its line, turning on the planted foot near a standstill and driving out:
--   brake: heading held on the old line, hard deceleration down to the pivot speed;
--   pivot: the speed held at the pivot speed while the heading turns (the slow-speed turn
--          rate), the body turning with it;
--   then the ordinary acceleration toward the goal.
local reversalRay = RaycastParams.new()
reversalRay.FilterType = Enum.RaycastFilterType.Exclude
reversalRay.RespectCanCollide = true

local function groundAhead(rootPart, direction)
	reversalRay.FilterDescendantsInstances = { rootPart.Parent }
	return Workspace:Raycast(rootPart.Position + direction * 4, Vector3.new(0, -16, 0), reversalRay) ~= nil
end

-- The 180 turn clip over a straight reversal: the right or the left one by the way the body turns
-- round (without a left one, a near-half turn goes right), sped up to the brake and the turn-round
local function startTurnClip(data, humanoid, reversal, fromDir, toDir, speed)
	if tune("Locomotion_ReversalTurnClip", true) == false then return end
	local delta = shortestAngleDelta(math.atan2(toDir.X, toDir.Z), math.atan2(fromDir.X, fromDir.Z))
	local side = delta >= 0 and 1 or -1 -- (+1 turns left, -1 right)
	local right = CombatConfig.Locomotion_ReversalTurnClipRight
	local left = CombatConfig.Locomotion_ReversalTurnClipLeft
	local path
	if side < 0 then
		path = right
	elseif left then
		path = left
	elseif math.abs(delta) > 2.6 then
		side, path = -1, right
	end
	reversal.side = side
	if not path then return end
	local len = AnimationModule.getRawLength(path)
	len = (type(len) == "number" and len > 0) and len or 0.67
	local brakeTime = math.max(speed - tune("Locomotion_ReversalFlipSpeed", 2), 0) / tune("Locomotion_ReversalBrake", 150)
	local turnTime = math.pi / tune("Locomotion_ReversalTurnRate", 7)
	local want = math.clamp(len / (brakeTime + turnTime + (CombatConfig.Locomotion_ReversalTurnClipExtra or 0.12)), 1, 3.5)
	local AnimationConfig = require(QuinCore:WaitForChild("AnimationConfig"))
	local entry = AnimationConfig.get and AnimationConfig.get(path)
	local track = AnimationModule.playConfig(humanoid, path, want / ((entry and entry.speed) or 1), Enum.AnimationPriority.Action2)
	if track then
		data.turnClip, data.turnClipPath = track, path
		reversal.clipTrack = track
	end
end

local function stopTurnClip(data, humanoid)
	if data.turnClip then
		if data.turnClip.IsPlaying then data.turnClip:Stop(0.15) end
		data.turnClip, data.turnClipPath = nil, nil
	end
end

local function ensureSteerDriver(fighter, humanoid, rootPart)
	if steerConns[fighter] then return end
	local conn
	conn = RunService.Heartbeat:Connect(function(frameDt)
		local data = locoData[fighter]
		if not data or not fighter.Parent or not humanoid.Parent or humanoid.Health <= 0 or not rootPart.Parent then
			conn:Disconnect()
			steerConns[fighter] = nil
			return
		end
		if data.turnClip and (not data.reversal or data.reversal.clipTrack ~= data.turnClip) then
			stopTurnClip(data, humanoid)
		end
		if data.ownsFacing and (not data.steerTarget or os.clock() > (data.steerUntil or 0) or activeSlides[fighter]
			or humanoid.PlatformStand or otherAlignActive(rootPart)) then
			releaseFacing(data, humanoid, rootPart)
		end
		local steering = data.steerTarget and os.clock() <= (data.steerUntil or 0)
		if not steering or activeSlides[fighter] or humanoid.PlatformStand or fighter:GetAttribute("IsPlayerControlled") == true then
			if data.reversal then
				-- (a reversal only lives under continuous steering)
				data.reversal = nil
				fighter:SetAttribute("ReversalPhase", nil)
			end
			return
		end

		frameDt = math.clamp(frameDt, 0.001, 0.05)
		local target = data.steerSpeed or humanoid.WalkSpeed
		if os.clock() < math.max(data.landingHoldUntil or 0, fighter:GetAttribute("LandingHoldUntil") or 0) then
			target = 0 -- absorbing a landing: brake first, move on as the body rises
		end
		local toTarget = data.steerTarget - rootPart.Position
		local flat = Vector3.new(toTarget.X, 0, toTarget.Z)
		local decel = tune("Locomotion_BrakingDeceleration", 140.0)

		local reversal = data.reversal
		if reversal and (os.clock() - reversal.started > 1.2 or isHumanoidAirborne(humanoid)) then
			data.reversal = nil
			reversal = nil
		end
		if reversal then
			-- Straight (Locomotion_ReversalStraight): the body comes back along its own line. It
			-- brakes to ReversalFlipSpeed, its motion flips onto the new way at once (nothing
			-- sideways: no hook), and it drives out while the body turns round on the spot. (With
			-- the motion following a turning heading it traced a small hook at the bottom, about a
			-- stud wide, whatever the settings.) Otherwise it pivots at ReversalPivotSpeed.
			local straight = tune("Locomotion_ReversalStraight", true) ~= false
			local pivotSpeed = tune("Locomotion_ReversalPivotSpeed", 6)
			local floorSpeed = straight and tune("Locomotion_ReversalFlipSpeed", 2) or pivotSpeed
			if reversal.phase == "brake" then
				local v = rootPart.AssemblyLinearVelocity
				if Vector3.new(v.X, 0, v.Z).Magnitude <= floorSpeed + 1 or os.clock() - reversal.started > 0.45
					or not groundAhead(rootPart, reversal.dir) then
					reversal.phase = "pivot"
					if straight then
						reversal.straight = true
						local look = flatUnit(rootPart.CFrame.LookVector, reversal.dir)
						reversal.faceAngle = math.atan2(look.X, look.Z)
						data.driveOutUntil = os.clock() + tune("Locomotion_ReversalDriveOutTime", 0) + 0.25
					end
				else
					decel = tune("Locomotion_ReversalBrake", 150)
				end
			end
			if not reversal.straight then
				target = math.min(target, floorSpeed)
			end
			if reversal.phase == "pivot" then
				local heading = data.groundIntentDirection
				local look = flatUnit(rootPart.CFrame.LookVector, Vector3.new(0, 0, -1))
				local alignedCos = CombatConfig.Locomotion_ReversalAlignedCos or 0.9
				if flat.Magnitude < 0.1 or (heading and heading:Dot(flat.Unit) > alignedCos and look:Dot(flat.Unit) > alignedCos - 0.1) then
					data.reversal = nil -- facing the new way: drive out
					reversal = nil
					data.driveOutUntil = os.clock() + (tune("Locomotion_ReversalDriveOutTime", 0))
				end
			end
		end
		fighter:SetAttribute("ReversalPhase", reversal and reversal.phase or nil)

		-- In the air a body keeps the flight it has: it can only lean it a little (air control).
		-- (With the ground drive in the air the horizontal motion followed the input at once:
		-- up, across, down, a box instead of an arc.)
		if isHumanoidAirborne(humanoid) and CombatConfig.Locomotion_AirControl ~= false then
			local v = rootPart.AssemblyLinearVelocity
			local current = Vector3.new(v.X, 0, v.Z)
			-- (a planned flight keeps its speed; otherwise a body can drift up to AirDriftSpeed on its
			-- own: from a standing jump the cap was its takeoff speed, 2 studs/s, and it hung in place)
			local cap = data.airSpeedCap or target
			if not data.airSpeedHold then
				cap = math.max(cap, tune("Locomotion_AirDriftSpeed", 14))
			end
			local wanted = flat.Magnitude > 0.1 and flat.Unit * math.min(target, math.max(cap, current.Magnitude)) or current
			local change = wanted - current
			local most = (tune("Locomotion_AirAcceleration", 30)) * frameDt
			if change.Magnitude > most then
				change = change.Unit * most
			end
			local nextVelocity = current + change
			humanoid.WalkSpeed = nextVelocity.Magnitude
			data.currentSpeed = nextVelocity.Magnitude
			if nextVelocity.Magnitude > 0.5 then
				data.groundIntentDirection = nextVelocity.Unit
				humanoid:Move(nextVelocity.Unit, false)
			end
			-- (the jump's own facing hold turns with the drift: it held the takeoff facing all flight)
			local jumpAlign = data.activeAlign
			if jumpAlign and jumpAlign.Parent and nextVelocity.Magnitude > 3 and CombatConfig.Locomotion_AirFacing ~= false then
				jumpAlign.CFrame = CFrame.lookAt(Vector3.zero, nextVelocity.Unit)
			end
			if data.ownsFacing then
				updateFacing(data, rootPart, frameDt)
			end
			return
		end

		local speed = humanoid.WalkSpeed
		if speed < target then
			local accel = tune("Locomotion_Acceleration", 80.0)
			if os.clock() < (data.driveOutUntil or 0) then
				accel = math.max(accel, tune("Locomotion_ReversalDriveOutAccel", accel)) -- (out of a pivot)
			end
			speed = math.min(speed + accel * frameDt, target)
		elseif speed > target then
			speed = math.max(speed - decel * frameDt, target)
		end
		humanoid.WalkSpeed = speed
		data.currentSpeed = speed

		if reversal and reversal.phase == "brake" then
			data.groundIntentDirection = reversal.dir
			humanoid:Move(reversal.dir, false)
			if data.ownsFacing then
				updateFacing(data, rootPart, frameDt)
			end
			return
		end
		if flat.Magnitude < 0.1 then return end
		if reversal and reversal.straight then
			-- straight back along the line; the body turns round on the spot, on its own
			local goal = flat.Unit
			data.groundIntentDirection = goal
			local delta = shortestAngleDelta(math.atan2(goal.X, goal.Z), reversal.faceAngle)
			if not reversal.side then
				reversal.side = delta >= 0 and 1 or -1 -- (one way round, not flipping at 180)
			end
			if delta * reversal.side < 0 then
				-- the chosen way round (the turn clip's; near a half turn the short way can flip)
				delta = delta - 2 * math.pi * (delta > 0 and 1 or -1)
			end
			local maxStep = tune("Locomotion_ReversalTurnRate", 7) * frameDt
			reversal.faceAngle += math.clamp(delta, -maxStep, maxStep)
			reversal.facing = Vector3.new(math.sin(reversal.faceAngle), 0, math.cos(reversal.faceAngle))
			humanoid:Move(goal, false)
		elseif reversal and data.groundIntentDirection then
			-- the pivot turns at a stepping pace (at the slow-speed turn rate it spun round in
			-- 0.2 s, faster than feet can step round)
			local heading = data.groundIntentDirection
			local current = math.atan2(heading.X, heading.Z)
			local delta = shortestAngleDelta(math.atan2(flat.X, flat.Z), current)
			local maxStep = (tune("Locomotion_ReversalTurnRate", 7)) * frameDt
			local nextAngle = current + math.clamp(delta, -maxStep, maxStep)
			data.groundIntentDirection = Vector3.new(math.sin(nextAngle), 0, math.cos(nextAngle))
			local remaining = delta - math.clamp(delta, -maxStep, maxStep)
			local lead = (tune("Locomotion_ReversalTurnRate", 7)) * (CombatConfig.Locomotion_FacingLeadTime or 0.11)
			local facingAngle = nextAngle + math.clamp(remaining, -lead, lead)
			reversal.facing = Vector3.new(math.sin(facingAngle), 0, math.cos(facingAngle))
			humanoid:Move(data.groundIntentDirection, false)
		else
			-- (someone standing in the way is walked round, not through)
			local desired = BodyAwareness.adjust(fighter, rootPart, flat.Unit, speed)
			humanoid:Move(LocomotionModule.resolveGroundIntent(fighter, rootPart, desired, frameDt), false)
		end
		if data.ownsFacing then
			updateFacing(data, rootPart, frameDt)
		end
	end)
	steerConns[fighter] = conn
end

-- Drop the current steer goal (state change, brake): the driver stops issuing movement
function LocomotionModule.cancelSteer(fighter)
	local data = locoData[fighter]
	if data then
		data.steerUntil = 0
		if data.reversal then
			data.reversal = nil
			fighter:SetAttribute("ReversalPhase", nil)
		end
		if data.ownsFacing then
			local humanoid = fighter:FindFirstChildOfClass("Humanoid")
			releaseFacing(data, humanoid, fighter:FindFirstChild("HumanoidRootPart"))
		end
	end
end

function LocomotionModule.steer(fighter, humanoid, rootPart, targetPosition, targetSpeed, dt, resolvedDirection)
	if not fighter or not humanoid or not rootPart or not targetPosition then return end
	-- A committed slide owns translation until it hands back to the gait
	if activeSlides[fighter] then return activeSlides[fighter].dir end

	dt = math.clamp(dt or 0.016, 0.001, 0.15)
	local data = getLocoData(fighter)

	-- The floor is lava: whatever state is steering, a Quin on raised ground does not run off
	-- it unless where it is going is well below (SpatialModule.keepOnSurface)
	if LocomotionModule.isOnGround(rootPart, humanoid) then
		-- (where it is really headed decides whether going down is wanted: a ledge dive steers
		-- at a point level with itself, toward a target below)
		local reference = targetPosition
		local targetName = fighter:GetAttribute("CurrentTarget")
		if targetName then
			local container = Workspace:FindFirstChild("QuinServer")
			local model = (container and container:FindFirstChild(targetName)) or Workspace:FindFirstChild(targetName)
			local targetRoot = model and model:FindFirstChild("HumanoidRootPart")
			if targetRoot then
				reference = targetRoot.Position
			end
		end
		local held
		targetPosition, held = SpatialModule.keepOnSurface(rootPart, targetPosition, reference)
		fighter:SetAttribute("EdgeHeld", held or nil)
	elseif data.airSpeedCap and os.clock() < (data.airCapUntil or 0) then
		-- In the air nothing pushes the body forward: the run could not speed it up past its
		-- launch (it carried a shortened jump on at 40 studs/s and into the next obstacle)
		targetSpeed = data.airSpeedHold and data.airSpeedCap
			or math.min(targetSpeed, math.max(data.airSpeedCap, tune("Locomotion_AirDriftSpeed", 14)))
	end

	-- 1. Smoothly accelerate / decelerate to target speed. AI Quins hand the goal to the
	-- per-frame steer driver; a piloted Quin (resolvedDirection supplied) is advanced here.
	local useDriver = (resolvedDirection == nil) and fighter:GetAttribute("IsPlayerControlled") ~= true
	if useDriver then
		data.steerTarget = targetPosition
		data.steerSpeed = targetSpeed
		data.steerUntil = os.clock() + 0.25
		ensureSteerDriver(fighter, humanoid, rootPart)
		fighter:SetAttribute("PacingVelocity", math.floor(humanoid.WalkSpeed + 0.5))
	else
		LocomotionModule.modulateSpeed(fighter, humanoid, targetSpeed, dt)
	end

	-- 2. Check for sharp direction reversals (180° Skid)
	local currentVel = rootPart.AssemblyLinearVelocity
	local flatVel = Vector3.new(currentVel.X, 0, currentVel.Z)
	local currentSpeed = flatVel.Magnitude

	local toTarget = (targetPosition - rootPart.Position)
	local flatDesired = Vector3.new(toTarget.X, 0, toTarget.Z)
	local fallbackForward = flatUnit(rootPart.CFrame.LookVector, Vector3.new(0, 0, -1))
	local intentDirection = flatDesired.Magnitude > 0.1 and flatDesired.Unit or fallbackForward
	-- Where it means to go, for the head: a turn shows in the head and chest before the body
	-- (LookController). Published only when it changes by 15 degrees or more, at most 5 times a second.
	if flatDesired.Magnitude > 2 then
		local intentYaw = math.atan2(intentDirection.X, intentDirection.Z)
		if not data.intentYaw or (os.clock() - (data.intentAt or 0) > 0.2 and math.abs(shortestAngleDelta(intentYaw, data.intentYaw)) > 0.26) then
			data.intentYaw, data.intentAt = intentYaw, os.clock()
			fighter:SetAttribute("SteerIntent", math.round(math.deg(intentYaw)))
		end
	end
	local driveDirection = resolvedDirection
	if not driveDirection then
		if useDriver and data.groundIntentDirection then
			driveDirection = data.groundIntentDirection -- the driver owns the heading
		else
			driveDirection = LocomotionModule.resolveGroundIntent(fighter, rootPart, intentDirection, useDriver and (1 / 60) or dt)
		end
	end

	local skidThreshold = CombatConfig.Locomotion_SkidSpeedThreshold or 13.0
	local now = os.clock()

	-- Reset braking single-shot latch when actively steering
	data.stopRunTriggered = false
	if data.stopRunEndTime and now < data.stopRunEndTime then
		data.stopRunEndTime = nil
		AnimationModule.stop(humanoid, "Movement.StopRun", 0.08)
	end

	-- For autonomous AI Quins (when not player controlled), initialize movement and track sprint start timestamp
	if not fighter:GetAttribute("IsPlayerControlled") then
		if not data.isMoving and flatDesired.Magnitude > 2.0 then
			data.isMoving = true
			if targetSpeed > 25.0 then
				data.sprintStartTime = now
			end
		end
	else
		data.isMoving = true
	end
	fighter:SetAttribute("LastActivityTime", now)

	local isChattering = fighter:GetAttribute("DirectionalChatter") == true
	local skidCooldown = CombatConfig.Locomotion_SkidCooldown or 0.70
	local skidLockout = CombatConfig.Locomotion_SkidLockout or 0.65

	local isStrafing = (fighter:GetAttribute("IsStrafing") == true) or (humanoid.AutoRotate == false and not data.ownsFacing)

	-- Skid plants need traction: never trigger one in the air or during tactical strafing/feints
	-- (a reversal plants and pivots from any pace above a slow walk; the old skid stays at a run)
	local reversalMin = math.min(skidThreshold, tune("Locomotion_ReversalMinSpeed", skidThreshold))
	if not isStrafing and currentSpeed > reversalMin and flatDesired.Magnitude > 2.0 and not isHumanoidAirborne(humanoid) then
		local curDir = flatVel.Unit
		local desDir = flatDesired.Unit
		local cosTheta = curDir:Dot(desDir)

		-- Sharp reversal: >= 115 degrees cut (cos theta < -0.42)
		-- Fully procedural turnaround: kinetic plant friction, procedural mass drop, braking pitch, and grey smoke burst!
		if cosTheta < -0.42 and (now - (data.lastSkidTime or 0)) >= skidCooldown and not data.reversal
			and useDriver and CombatConfig.Locomotion_ReversalPivot ~= false then
			-- Plant and pivot (see groundAhead): the driver brakes along the old line, turns, drives out
			local pivotSpeed = tune("Locomotion_ReversalPivotSpeed", 6)
			local turnDuration = math.max(currentSpeed - pivotSpeed, 0) / (tune("Locomotion_ReversalBrake", 150)) + 0.3
			data.lastSkidTime = now
			data.skidEndTime = now + turnDuration
			data.reversal = { dir = curDir, phase = "brake", started = now }
			if tune("Locomotion_ReversalStraight", true) ~= false then
				startTurnClip(data, humanoid, data.reversal, curDir, desDir, currentSpeed)
			end
			fighter:SetAttribute("SkidTurnTime", now)
			fighter:SetAttribute("SkidTurnDuration", turnDuration)
			if currentSpeed > skidThreshold then -- (the scuff of a plant at a run, not a walk's turn)
				VfxModule.createArcaneFootBurst(fighter, rootPart.Position, curDir)
			end
		elseif cosTheta < -0.42 and (now - (data.lastSkidTime or 0)) >= skidCooldown and currentSpeed > skidThreshold then
			local turnDuration = skidLockout
			data.lastSkidTime = now
			data.skidEndTime = now + turnDuration

			-- Signal procedural controller for hips mass drop & braking-to-drive pitch
			fighter:SetAttribute("SkidTurnTime", now)
			fighter:SetAttribute("SkidTurnDuration", turnDuration)

			-- Kinetic plant friction: drop speed dynamically for athletic turf bite (cleats digging in)
			-- The drop is spread over a few frames; assigning it at once removed 60% of the speed in
			-- a single frame and read as a hitch rather than a plant.
			local plantSpeed = math.max(12.0, currentSpeed * 0.40)
			local fromSpeed = humanoid.WalkSpeed
			data.currentSpeed = plantSpeed
			data.skidToken = (data.skidToken or 0) + 1
			local skidToken = data.skidToken
			if fromSpeed > plantSpeed then
				task.spawn(function()
					local rampStart = os.clock()
					while humanoid.Parent and data.skidToken == skidToken do
						local p = (os.clock() - rampStart) / 0.14
						if p >= 1 then break end
						humanoid.WalkSpeed = math.min(humanoid.WalkSpeed, fromSpeed + (plantSpeed - fromSpeed) * p)
						RunService.Heartbeat:Wait()
					end
				end)
			end

			-- VFX: Stylized grey foot smoke burst along turf scrape vector (zero physics parts)
			VfxModule.createArcaneFootBurst(fighter, rootPart.Position, curDir)
		end
	end
	if data.reversal and data.reversal.phase == "brake" then
		driveDirection = data.reversal.dir -- (the driver holds the old line while it brakes)
	end

	-- 3. Issue the resolved curved heading to the humanoid. Both player and AI
	-- use this same ground-intent result and Move translation API; arrival deceleration eliminated!
	if not isStrafing then
		local aiDriven = useDriver and CombatConfig.Locomotion_FacingFollowsMotion ~= false
		if aiDriven and not otherAlignActive(rootPart) then
			claimFacing(data, humanoid, rootPart)
		else
			releaseFacing(data, humanoid, rootPart)
			humanoid.AutoRotate = true
		end
	end
	humanoid:Move(driveDirection, false)

	-- Debug: where it is told to go (yellow), where its turn-limited heading points (orange)
	if DebugDraw.isActive("Steer", fighter) then
		local origin = rootPart.Position
		DebugDraw.line("Steer", fighter, origin, targetPosition, Color3.fromRGB(255, 225, 60))
		DebugDraw.line("Steer", fighter, origin, origin + driveDirection * 8, Color3.fromRGB(255, 140, 40))
		DebugDraw.text("Steer", fighter, targetPosition + Vector3.new(0, 2, 0), string.format("goal %.0f studs/s", targetSpeed), Color3.fromRGB(255, 225, 60))
	end
	-- Note: Footstep audio is driven authoritatively by animation keyframe markers via AnimationModule
	return driveDirection
end

-- ============================================================================
-- 3. MELEE BRAKE & CONTINUITY (Slide into combat sweet spot; zero freeze-snaps)
-- ============================================================================

function LocomotionModule.brake(fighter, humanoid, rootPart, dt)
	if not fighter or not humanoid or not rootPart then return end
	-- A committed slide carries its own deceleration and exit
	if activeSlides[fighter] then return end

	local data = getLocoData(fighter)
	data.steerUntil = 0 -- braking ends any steer goal
	if data.intentYaw then
		data.intentYaw = nil
		fighter:SetAttribute("SteerIntent", nil)
	end
	local currentVel = rootPart.AssemblyLinearVelocity
	local flatVel = Vector3.new(currentVel.X, 0, currentVel.Z)
	local speed = flatVel.Magnitude
	local now = os.clock()

	-- Nothing to brake against in the air: the body carries its flight until it lands. (The
	-- ground brake ran in the air too, and a jump stopped dead across the ground in mid-flight.)
	if isHumanoidAirborne(humanoid) and CombatConfig.Locomotion_AirControl ~= false then
		if speed > 0.5 then
			humanoid.WalkSpeed = speed
			humanoid:Move(flatVel.Unit, false)
		end
		return
	end

	-- The stop-run plant is for a Quin pulling up out of a full run: one that had reached its
	-- top speed (its Speed, within StopRun_TopSpeedShare). Anything slower just slows down.
	-- (It used to play from 24 studs/s, or whenever the Quin was flagged as sprinting: a third
	-- of them were from runs that never got to top speed, some at 60 % of it.)
	local topSpeed = fighter:GetAttribute("Speed") or 40
	local atTopSpeed = speed >= topSpeed * (CombatConfig.StopRun_TopSpeedShare or 0.9)

	-- Single-shot latch for braking transition
	if not data.stopRunTriggered then
		data.stopRunTriggered = true
		data.isMoving = false

		if atTopSpeed then
			data.lastStopRunTime = now
			data.stopRunEndTime = now + 0.68

			-- Fast fade out running track & push-offs
			AnimationModule.stop(humanoid, "Movement.Run", 0.08)
			AnimationModule.stop(humanoid, "Movement.WalkConfident", 0.08)
			AnimationModule.stop(humanoid, "Movement.StartRun", 0.08)

			-- Play StopRun plant animation (rbxassetid://89237107000987)
			AnimationModule.playConfig(humanoid, "Movement.StopRun", 1.15, Enum.AnimationPriority.Action2, false)

			-- Enter Ready Stance & mark last activity time for 5s inactivity cooldown
			fighter:SetAttribute("CurrentIdleStance", "Ready")
			fighter:SetAttribute("LastActivityTime", now)

			-- VFX: small ground dust puff along stopping vector (NO physics LinearVelocity slide)
			local slideDir = flatVel.Magnitude > 0.1 and flatVel.Unit or rootPart.CFrame.LookVector
			local elem = fighter:GetAttribute("Element") or "Earth"
			VfxModule.createDust(rootPart.Position, 2, slideDir, elem)
			VfxModule.createGroundMark(rootPart, slideDir, math.clamp(speed * 0.12, 1.5, 4.5), 0.9, 3.5)
		else
			-- Clean walking halt: no StopRun slide. The shared gait keeps stepping while the
			-- body decelerates and fades into the Ready stance as speed reaches zero.
			data.stopRunEndTime = nil
			AnimationModule.stop(humanoid, "Movement.StartRun", 0.08)

			-- Enter Ready Stance & mark last activity time for 5s inactivity cooldown
			fighter:SetAttribute("CurrentIdleStance", "Ready")
			fighter:SetAttribute("LastActivityTime", now)
		end
	elseif speed <= 2.0 then
		data.isMoving = false
		data.groundIntentDirection = nil
	end

	-- Modulate speed to 0 smoothly instead of snapping in 1 frame
	LocomotionModule.modulateSpeed(fighter, humanoid, 0, dt or 0.1)

	-- Actively cancel humanoid active MoveTo translation so it doesn't walk in place
	-- Preserve a short grounded slide in the current travel direction while WalkSpeed decays.
	-- Cancelling input outright makes a 50-stud/s Quin freeze unnaturally; diminishing momentum
	-- lets the StopRun plant and body weight read visually.
	local brakeDir = speed > 0.1 and flatVel.Unit or Vector3.zero
	if speed > 0.5 and humanoid.WalkSpeed > 0.5 then
		humanoid:Move(brakeDir, false)
	else
		humanoid:Move(Vector3.zero, false)
	end

	-- When no StopRun braking overlay is active, ensure idle (handles Ready -> 5s inactivity -> Default)
	local isOverlayActive = (data.stopRunEndTime and now < data.stopRunEndTime)

	if not isOverlayActive then
		-- Feet keep cycling while the humanoid is still decelerating under its own drive
		-- (no skating slide into idle). Once the drive has decayed, any leftover velocity
		-- is external (pushes, uneven footing) and the Quin stands in idle.
		if speed > 1.2 and humanoid.WalkSpeed > 0.5 then
			GaitModule.update(humanoid, rootPart, dt or 0.1)
		elseif GaitModule.isActive(humanoid) then
			GaitModule.stop(humanoid, 0.2)
		end

		-- Check 5-second inactivity timeout: if Ready stance has been inactive for >= 5s, relax to Default
		local stance = fighter:GetAttribute("CurrentIdleStance")
		local lastAct = fighter:GetAttribute("LastActivityTime") or now
		if stance == "Ready" and (now - lastAct) >= 5.0 then
			fighter:SetAttribute("CurrentIdleStance", "Default")
		end

		AnimationModule.ensureBaseIdle(humanoid)
	end
end

-- ============================================================================
-- 4. BALLISTIC JUMP (Zero BodyVelocity; Single Impulse; 88% Landing Retention)
-- ============================================================================

-- (MAX_JUMP_HEIGHT is the one at the top: Jump_MaxReach + 2. A second definition here, 14,
-- shadowed it for every jump below, so Pass 63's reach of 25 never reached a jump.)

function LocomotionModule.getTraversalProbe(rootPart, desiredDirection)
	return TraversalModule.probe(rootPart, desiredDirection)
end

function LocomotionModule.detectObstacle(rootPart)
	local candidate = TraversalModule.probe(rootPart, rootPart and rootPart.CFrame.LookVector or nil)
	local traversable = candidate and candidate.kind ~= "None" and candidate.kind ~= "Blocked"
	return traversable, candidate and (candidate.obstacleHeight or 0) or 0, candidate
end

function LocomotionModule.planTraversal(fighter, rootPart, desiredDirection, requestedHeight, forwardSpeed)
	if not rootPart then return nil end
	local plan, candidate = TraversalModule.plan(rootPart, desiredDirection, requestedHeight, forwardSpeed)
	if plan then
		plan.candidate = candidate
	end
	return plan, candidate
end

-- Skid-over: the clip itself carries the body up and over (hips rise, a hand on top, legs
-- swing through), so the body is not thrown on a ballistic arc. It keeps its running height
-- and speed on a mover, with its collision off for the crossing (the obstacle passes under the
-- legs), and the clip's airborne part (0.08 -> 0.97 s) is fitted to the crossing time. Over a
-- 3-stud obstacle Y is locked; taller ones (up to 5) get a small eased lift of (h - 3) at the
-- middle so the legs clear the top.
local function runSkidOver(fighter, humanoid, rootPart, speed, rise, direction)
	local gravity = Workspace.Gravity
	local duration = 2 * math.sqrt(2 * math.max(rise or 3, 0.5) / gravity)
	local obstacleHeight = fighter:GetAttribute("SkidObstacleHeight") or 3
	local lift = math.clamp(obstacleHeight - 3, 0, 2.5)
	local data = getLocoData(fighter)

	local saved = {}
	for _, part in ipairs(fighter:GetDescendants()) do
		if part:IsA("BasePart") and part.CanCollide then
			saved[part] = true
			part.CanCollide = false
		end
	end
	humanoid.PlatformStand = true
	fighter:SetAttribute("SkidOverActive", true)

	local att = rootPart:FindFirstChild("RootAttachment") or Instance.new("Attachment", rootPart)
	local mover = Instance.new("LinearVelocity")
	mover.Name = "SkidOverMover"
	mover.Attachment0 = att
	mover.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	mover.ForceLimitMode = Enum.ForceLimitMode.Magnitude
	mover.MaxForce = math.huge
	mover.VectorVelocity = direction * speed
	mover.Parent = rootPart
	local align = Instance.new("AlignOrientation")
	align.Name = "SkidOverAlign"
	align.Mode = Enum.OrientationAlignmentMode.OneAttachment
	align.Attachment0 = att
	align.Responsiveness = 40
	align.MaxTorque = 1e7
	align.CFrame = CFrame.lookAt(Vector3.zero, direction)
	align.Parent = rootPart

	local track = AnimationModule.playConfig(humanoid, "Parkour.SkidOverOB", 1.0, Enum.AnimationPriority.Action3, true)
	if track then
		track:AdjustSpeed(math.clamp((0.97 - 0.08) / math.max(duration, 0.1), 0.5, 2.6))
		if track.Length > 0 then
			track.TimePosition = 0.08
		end
	end
	AudioModule.playJump(fighter, 0.5)

	local baseY = rootPart.Position.Y
	local start = os.clock()
	local conn
	conn = RunService.Heartbeat:Connect(function(dt)
		local t = os.clock() - start
		if t >= duration or not fighter.Parent or humanoid.Health <= 0 then
			conn:Disconnect()
			mover:Destroy()
			align:Destroy()
			for part in pairs(saved) do
				if part.Parent then part.CanCollide = true end
			end
			humanoid.PlatformStand = false
			fighter:SetAttribute("SkidOverActive", nil)
			if rootPart.Parent then
				rootPart.AssemblyLinearVelocity = direction * speed
			end
			humanoid:ChangeState(Enum.HumanoidStateType.Running)
			data.airCapUntil = 0
			return
		end
		local y = baseY + lift * math.sin(math.pi * t / duration)
		local vy = math.clamp((y - rootPart.Position.Y) / math.max(dt, 1 / 240), -60, 60)
		mover.VectorVelocity = direction * speed + Vector3.new(0, vy, 0)
	end)
	return true
end

-- flightTime (optional): a jump aimed at a landing spot (a jump down off a platform) gives the
-- whole time it will be in the air; it then keeps its launch speed across the ground until it is
-- down, as a body in the air does.
function LocomotionModule.jump(fighter, humanoid, rootPart, height, forwardImpulse, jumpType, flightTime)
	-- Universal argument normalization: support both (fighter, humanoid, rootPart, ...)
	-- and legacy (humanoid, rootPart, height, forwardImpulse, jumpType) callers
	if fighter and fighter:IsA("Humanoid") then
		jumpType = forwardImpulse
		forwardImpulse = height
		height = rootPart
		rootPart = humanoid
		humanoid = fighter
		fighter = rootPart and rootPart.Parent
	end
	if not fighter or not humanoid or not rootPart then return end

	-- Pure Ground Locomotion: suppress ballistic jump impulse if jumping is disabled
	if LocomotionModule.isJumpSuppressed(fighter, humanoid) then
		fighter:SetAttribute("JumpSkip", "suppressed")
		return
	end

	-- Ballistic jumps launch from the ground only (Rule 6): no mid-air re-launch. An obstacle
	-- crossing goes by real ground contact: the Humanoid state still reads Jumping/Freefall for
	-- a moment after touchdown, and a skid-over planned on landing was refused into the wall.
	local crossing = jumpType == "skidover" or jumpType == "hurdle"
	if isHumanoidAirborne(humanoid) and not (crossing and LocomotionModule.isOnGround(rootPart, humanoid)) then
		fighter:SetAttribute("JumpSkip", "airborne " .. tostring(jumpType))
		return
	end

	-- Jumping out of a slide cancels the glide and launches with its momentum
	if activeSlides[fighter] then
		endSlide(fighter, humanoid, rootPart, false)
	end

	-- Traversal parkour planning integration (vaults, jumps, dismounts)
	local plannedFlightTime = nil
	-- ("free": a jump a player asked for. It is not re-planned into an obstacle crossing or refused
	-- because of where it would land: that is the player's choice, as an AI's choice is its own.)
	local shouldPlan = (jumpType == nil or jumpType == "jump" or jumpType == "vault" or jumpType == "dismount")
	if shouldPlan and rootPart:IsA("BasePart") then
		local plan = LocomotionModule.planTraversal(
			fighter,
			rootPart,
			rootPart.CFrame.LookVector,
			height,
			forwardImpulse
		)
		if plan then
			plannedFlightTime = plan.flightTime
			TraversalModule.markTraversal(fighter, plan)
			fighter:SetAttribute("TraversalVelocityX", plan.horizontalVelocity.X)
			fighter:SetAttribute("TraversalVelocityZ", plan.horizontalVelocity.Z)
			height = plan.height
			forwardImpulse = plan.horizontalVelocity.Magnitude
			jumpType = plan.animationType
			task.delay((plan.flightTime or 0.6) + 0.45, function()
				if fighter and fighter.Parent then
					TraversalModule.clearTraversal(fighter)
					fighter:SetAttribute("TraversalVelocityX", 0)
					fighter:SetAttribute("TraversalVelocityZ", 0)
				end
			end)
		end
	end
	-- A jump that was not planned over a known obstacle is checked before it is taken: the
	-- Quin only leaves the ground when the arc comes down on something it can stand on, inside
	-- the arena. (A straight-up hop always does.)
	if not plannedFlightTime and rootPart:IsA("BasePart") and jumpType ~= "free" then
		local flatVelocity = Vector3.new(rootPart.AssemblyLinearVelocity.X, 0, rootPart.AssemblyLinearVelocity.Z)
		local across = forwardImpulse or (flatVelocity.Magnitude > 2.0 and flatVelocity.Magnitude or 0)
		if across > 4 then
			local look = Vector3.new(rootPart.CFrame.LookVector.X, 0, rootPart.CFrame.LookVector.Z)
			look = look.Magnitude > 0.01 and look.Unit or Vector3.new(0, 0, -1)
			-- a crossing launches along its velocity (the facing can lag a turn)
			if crossing and flatVelocity.Magnitude > 4 then
				look = flatVelocity.Unit
			end
			local up = math.sqrt(2 * Workspace.Gravity * math.clamp(height or 8.0, 3.0, MAX_JUMP_HEIGHT))
			local valid, landing, reason = TraversalModule.validateArc(rootPart, look * across + Vector3.new(0, up, 0), humanoid.HipHeight + rootPart.Size.Y / 2)
			-- A crossing's arc was solved to clear the obstacle with margin; this coarser trace
			-- (one point at the feet, 0.06 s steps) called it a wall hit and cancelled it, and the
			-- Quin ran into the bar. Only its landing is checked (no ground = lava).
			if not valid and crossing and (reason == "HitsWall" or reason == "NoHeadroom") then
				valid, reason = true, nil
			end
			if valid and SpatialModule.isOutOfBounds({ Position = landing }, 4) then
				valid, reason = false, "OutOfArena"
			end
			if not valid then
				fighter:SetAttribute("JumpRejected", reason)
				fighter:SetAttribute("JumpRejectedCount", (fighter:GetAttribute("JumpRejectedCount") or 0) + 1)
				if DebugDraw.isActive("Jump", fighter) then
					DebugDraw.sphere("Jump", fighter, landing, 1.0, Color3.fromRGB(255, 70, 70), 1.2)
					DebugDraw.text("Jump", fighter, landing + Vector3.new(0, 2.5, 0), "jump rejected: " .. reason, Color3.fromRGB(255, 70, 70), 1.2)
				end
				return false
			end
		end
	end

	if fighter and fighter:IsA("Instance") then
		if not fighter:GetAttribute("TraversalVelocityX") then
			fighter:SetAttribute("TraversalVelocityX", 0)
			fighter:SetAttribute("TraversalVelocityZ", 0)
		end
	end

	local data = getLocoData(fighter)
	local now = os.clock()

	-- Enforce jump debounce to eliminate rapid-fire double-hopping
	-- (an obstacle crossing only needs to be back on the ground: bars in a row are taken
	-- landing-to-takeoff within a few tenths of a second)
	local debounce = crossing and 0.15 or (CombatConfig.Locomotion_JumpDebounce or 0.35)
	-- (down again since the last jump: it can go again once its feet are under it. The debounce
	-- from takeoff kept a body that had landed waiting ~0.3 s for nothing)
	if (data.lastLandTime or 0) > data.lastJumpTime then
		debounce = math.min(debounce, (data.lastLandTime - data.lastJumpTime) + (CombatConfig.Locomotion_JumpReplant or 0.1))
	end
	if (now - data.lastJumpTime) < debounce then
		fighter:SetAttribute("JumpSkip", string.format("debounce %.2f %s", now - data.lastJumpTime, tostring(jumpType)))
		return
	end
	data.lastJumpTime = now

	if jumpType == "skidover" then
		local flatVel = Vector3.new(rootPart.AssemblyLinearVelocity.X, 0, rootPart.AssemblyLinearVelocity.Z)
		local direction = flatVel.Magnitude > 4 and flatVel.Unit
			or Vector3.new(rootPart.CFrame.LookVector.X, 0, rootPart.CFrame.LookVector.Z).Unit
		return runSkidOver(fighter, humanoid, rootPart, forwardImpulse or flatVel.Magnitude, height, direction)
	end

	local isVault = (jumpType == "vault")
    -- Stepping off a height: planned drops and the ledge dive both land softly
    local isDismount = (jumpType == "dismount" or jumpType == "leap_down")
    local isHop = (jumpType == "hop")
    local isLongJump = (jumpType == "longjump")
    -- Skid-over: a speed vault over a low obstacle, a hand on top (Parkour.SkidOverOB)
    local isSkid = (jumpType == "skidover")
    local jumpAnim = isSkid and "Parkour.SkidOverOB" or (isVault and "Parkour.VaultObstacle" or "Movement.Jump")

    -- Keep the gait underneath the traversal layer. The parkour clip supplies
    -- anticipation and silhouette while the run cycle preserves continuity.
    AnimationModule.stopConfig(humanoid, "Movement.Fall", 0.10)
    -- A deliberate launch hands the body to the jump clip immediately (the ground
    -- contract's grace period is only for walking off small ledges)
    GaitModule.notifyLaunch(humanoid)
    if isDismount then
        AnimationModule.playConfig(humanoid, "Movement.Fall", 1.0, Enum.AnimationPriority.Action3, true)
    elseif isSkid then
        -- The clip leaves the ground at 0.08 s and its feet are down again at 0.97 s (Footstep
        -- marker): that part is fitted to the real flight, so a long obstacle (a longer, higher
        -- flight) plays it slower and a short one faster.
        local rise = math.clamp(height or 4.0, 3.0, MAX_JUMP_HEIGHT)
        local flight = 2 * math.sqrt(2 * Workspace.Gravity * rise) / Workspace.Gravity
        local track = AnimationModule.playConfig(humanoid, jumpAnim, 1.0, Enum.AnimationPriority.Action3, true)
        if track then
            track:AdjustSpeed(math.clamp((0.97 - 0.08) / math.max(flight, 0.1), 0.5, 2.6))
            if track.Length > 0 then
                track.TimePosition = 0.08
            else
                -- First use: the asset is still loading. Once it arrives, put the clip where
                -- it would be by now, so the feet still come down with the body.
                local launched = os.clock()
                task.spawn(function()
                    while track.Length == 0 and os.clock() - launched < 0.5 do
                        task.wait()
                    end
                    if track.IsPlaying and track.Length > 0 then
                        track.TimePosition = math.min(0.08 + (os.clock() - launched) * track.Speed, 0.95)
                    end
                end)
            end
        end
    else
        -- The jump clip carries its own rise and fall (hips travel ~4 studs up and back down).
        -- Fit the clip to the real flight so that arc lands with the body; at a fixed rate a
        -- short hop touched down while the clip was still at its apex and the mesh dropped late.
        local estHeight = math.clamp(height or 8.0, 3.0, MAX_JUMP_HEIGHT)
        local estFlight = plannedFlightTime or (2 * math.sqrt((2 * estHeight) / Workspace.Gravity))
        local clipDuration = AnimationModule.getEffectiveDuration(humanoid, jumpAnim, 1.0)
        local launchSpeed = math.clamp(clipDuration / math.max(estFlight, 0.2), 0.85, 2.0)
        AnimationModule.playConfig(humanoid, jumpAnim, launchSpeed, Enum.AnimationPriority.Action3, true)
    end

    -- Audio feedback via QuinCore AudioModule (Authentic normal jump sound)
	AudioModule.playJump(fighter or rootPart, 0.5)

	-- Single vertical ballistic impulse: v_y = sqrt(2 * g * h)
	local gravity = Workspace.Gravity
	local targetHeight = math.clamp(height or 8.0, 3.0, MAX_JUMP_HEIGHT)
	local upImpulse = math.sqrt(2 * gravity * targetHeight)

	-- Forward momentum conservation
	local rootCF = rootPart.CFrame
	local flatLook = Vector3.new(rootCF.LookVector.X, 0, rootCF.LookVector.Z)
	if flatLook.Magnitude < 0.01 then
		flatLook = Vector3.new(0, 0, -1)
	else
		flatLook = flatLook.Unit
	end

	local currentHVel = Vector3.new(rootPart.AssemblyLinearVelocity.X, 0, rootPart.AssemblyLinearVelocity.Z).Magnitude
	-- A hurdle is cleared along the way the body is travelling (the facing can lag a turn)
	if (jumpType == "hurdle" or isSkid) and currentHVel > 4 then
		flatLook = Vector3.new(rootPart.AssemblyLinearVelocity.X, 0, rootPart.AssemblyLinearVelocity.Z).Unit
	end
	local fwdSpeed = forwardImpulse
	if fwdSpeed == nil then
		fwdSpeed = (currentHVel > 2.0) and currentHVel or 0.0
	end

	-- The Humanoid adds its own takeoff (JumpPower, 50) on the physics step after it enters
	-- Jumping: every jump that needed less than 50 studs/s up (hurdles, skid-overs, hops) flew
	-- at 50, higher and longer than solved. For the takeoff it is set to this jump's own speed.
	local savedJumpPower = humanoid.JumpPower
	humanoid.UseJumpPower = true
	humanoid.JumpPower = upImpulse
	task.delay(0.15, function()
		if humanoid.Parent and humanoid.JumpPower == upImpulse then
			humanoid.JumpPower = savedJumpPower
		end
	end)

	-- Unstick humanoid from ground plane
	humanoid:ChangeState(Enum.HumanoidStateType.Jumping)

	-- Direct native physics assignment: ZERO BodyVelocity!
	local plannedHorizontal = Vector3.new(
        fighter:GetAttribute("TraversalVelocityX") or 0,
        0,
        fighter:GetAttribute("TraversalVelocityZ") or 0
    )
    -- (a crossing is its own plan: a vault's velocity can still be on the attributes)
    if crossing or plannedHorizontal.Magnitude < 0.01 then
        plannedHorizontal = flatLook * fwdSpeed
    end
    rootPart.AssemblyLinearVelocity = plannedHorizontal + Vector3.new(0, upImpulse, 0)
    data.airSpeedCap = math.max(plannedHorizontal.Magnitude, 2)
    data.airCapUntil = os.clock() + (flightTime or 2 * upImpulse / gravity) + 0.15
    -- (The chase's own pace took over as soon as the body was in the air: braking for its
    -- target, it slowed a jump down to half its speed and landed it 40 % short.)
    data.airSpeedHold = flightTime ~= nil
    if data.airSpeedHold then
        humanoid.WalkSpeed = data.airSpeedCap
    end

    -- Debug: the arc this jump was launched on, until it comes back down to launch height
    if DebugDraw.isActive("Jump", fighter) then
        local launchVelocity = plannedHorizontal + Vector3.new(0, upImpulse, 0)
        local airTime = 2 * upImpulse / gravity
        local showFor = airTime + 0.6
        local color = Color3.fromRGB(200, 120, 255)
        local from = rootPart.Position
        local segments = 14
        for i = 1, segments do
            local t = airTime * i / segments
            local to = rootPart.Position + launchVelocity * t + Vector3.new(0, -0.5 * gravity * t * t, 0)
            DebugDraw.line("Jump", fighter, from, to, color, showFor)
            from = to
        end
        DebugDraw.sphere("Jump", fighter, from, 0.9, color, showFor)
        DebugDraw.text("Jump", fighter, from + Vector3.new(0, 2, 0), string.format("%s: %.0f up, %.0f across", tostring(jumpType or "jump"), targetHeight, plannedHorizontal.Magnitude * airTime), color, showFor)
    end
	rootPart.AssemblyAngularVelocity = Vector3.zero

	-- Modern AlignOrientation to prevent mid-air tumbling
	if data.activeAlign then data.activeAlign:Destroy() end
	if data.activeAtt then data.activeAtt:Destroy() end

	local align = Instance.new("AlignOrientation")
	align.Name = "Loco_JumpAlign"
	align.Mode = Enum.OrientationAlignmentMode.OneAttachment
	align.RigidityEnabled = false
	align.Responsiveness = 30 -- (80 locked the facing for the whole flight)
	align.MaxTorque = 300000
	align.MaxAngularVelocity = 20
	local alignLook = plannedHorizontal.Magnitude > 0.01 and plannedHorizontal.Unit or flatLook
	align.CFrame = CFrame.lookAt(Vector3.zero, alignLook)

	local att = Instance.new("Attachment")
	att.Name = "Loco_JumpAtt"
	att.Parent = rootPart
	align.Attachment0 = att
	align.Parent = rootPart

	data.activeAlign = align
	data.activeAtt = att
	local flightTime = math.sqrt((2 * targetHeight) / gravity) * 2
	-- Dynamic AlignOrientation lifetime matching calculated ballistic arc
	Debris:AddItem(align, flightTime + 0.25)
	Debris:AddItem(att, flightTime + 0.25)
	local jumpStartTime = os.clock()
	local landedHandled = false
	local function onLanded()
		if landedHandled then return end
		landedHandled = true
		data.lastLandTime = os.clock()
		if data.activeLandedConn then
			data.activeLandedConn:Disconnect()
			data.activeLandedConn = nil
		end

		-- Conserve 88% of horizontal momentum (Rule 6: NO ZEROING ON LANDING)
		local retention = CombatConfig.Locomotion_LandingRetention or 0.88
		if rootPart and rootPart.Parent then
			local currentVel = rootPart.AssemblyLinearVelocity
			local preservedH = Vector3.new(currentVel.X, 0, currentVel.Z) * retention
			rootPart.AssemblyLinearVelocity = preservedH
			rootPart.AssemblyAngularVelocity = Vector3.zero
			if preservedH.Magnitude > 1.0 then
				humanoid:Move(preservedH.Unit, false)
			end
		end

		if align and align.Parent then align:Destroy() end
		if att and att.Parent then att:Destroy() end
		-- (down: the pace is the state's again)
		data.airSpeedHold = false

		AnimationModule.stopConfig(humanoid, jumpAnim, 0.15)
		AnimationModule.stopConfig(humanoid, "Movement.Fall")

		-- Audio feedback on landing via QuinCore AudioModule (only if genuinely airborne)
		local airTime = os.clock() - jumpStartTime
		if airTime >= 0.18 and rootPart and rootPart.Parent then
			AudioModule.playFallOnGround(rootPart.Position)
			VfxModule.createLandingDust(rootPart, math.clamp(airTime / 1.2, 0.25, 0.8))
		end

		local landingVelocity = rootPart and rootPart.AssemblyLinearVelocity or Vector3.zero
        local impactSpeed = math.abs(landingVelocity.Y)
        local traversalType = fighter:GetAttribute("TraversalType") or "None"
        local traversalHeight = fighter:GetAttribute("TraversalObstacleHeight") or 0
        if isDismount then
            -- A drop from a platform. The soft landing is the unhurried one: it belongs to a
            -- drop that comes straight down (a Quin that stepped off the ledge in its own time).
            -- A dive that lands with speed across the ground takes the hard landing. (The
            -- superhero landing is kept for projectile-jump impacts.)
            -- The Quin absorbs the drop where it lands: it brakes through the crouch and the clip
            -- is released as it rises, so it never glides at a sprint in a landing pose.
            local across = Vector3.new(landingVelocity.X, 0, landingVelocity.Z).Magnitude
            local landingClip = across <= (CombatConfig.Landing_SoftMaxSpeed or 8) and "Parkour.LandingSoft" or "Parkour.LandingHard"
            local absorb = AnimationModule.getEffectiveDuration(humanoid, landingClip, 1.0) * LANDING_ABSORB_RATIO
            data.landingHoldUntil = os.clock() + absorb
            if landingClip == "Parkour.LandingSoft" then
                fighter:SetAttribute("CasualUntil", os.clock() + absorb + (CombatConfig.Landing_CasualWalkTime or 2.5))
            end
            AnimationModule.playConfig(humanoid, landingClip, 1.0, Enum.AnimationPriority.Action3, true)
            task.delay(absorb, function()
                if humanoid.Parent then
                    AnimationModule.stopConfig(humanoid, landingClip, 0.25)
                end
            end)
        elseif traversalType == "None" and impactSpeed > 50 and airTime > 0.9 then
            AnimationModule.playConfig(humanoid, "Parkour.LandingHard", 1.0, Enum.AnimationPriority.Action3, true)
        end

        local currentVel = rootPart and rootPart.AssemblyLinearVelocity or Vector3.zero
		local flatSpeed = Vector3.new(currentVel.X, 0, currentVel.Z).Magnitude
		if flatSpeed > 3.0 then
			GaitModule.update(humanoid, rootPart, 1 / 60)
		else
			AnimationModule.ensureBaseIdle(humanoid)
		end
	end

	-- Hook landing event to CONSERVE 88% forward momentum
	data.activeLandedConn = humanoid.StateChanged:Connect(function(_, new)
		if new == Enum.HumanoidStateType.Running or new == Enum.HumanoidStateType.Landed then
			onLanded()
		end
	end)

	-- Safety fallback timer: if server Humanoid StateChanged fails to fire on small vaults/hops,
	-- clean up tracks after calculated ballistic arc + safety margin
	task.delay(flightTime + 0.15, function()
		if not landedHandled and humanoid and humanoid.Parent and rootPart and rootPart.Parent then
			local isGrounded = SpatialModule.isGrounded(rootPart)
			if isGrounded or math.abs(rootPart.AssemblyLinearVelocity.Y) < 5 then
				onLanded()
			end
		end
	end)
	return true -- launched (nil / false: suppressed, debounced or rejected)
end

-- A jump let go early is a short hop: the rise is cut while it is still climbing (within
-- Locomotion_JumpCutWindow of the takeoff). Anyone's jump can be cut; a player's Quin cuts it when
-- the jump button is released.
function LocomotionModule.cutJump(fighter, humanoid, rootPart)
	local data = locoData[fighter]
	if not data or not humanoid or not rootPart then return false end
	if os.clock() - (data.lastJumpTime or 0) > (CombatConfig.Locomotion_JumpCutWindow or 0.3) then return false end
	local v = rootPart.AssemblyLinearVelocity
	if v.Y <= 0 or not isHumanoidAirborne(humanoid) then return false end
	rootPart.AssemblyLinearVelocity = Vector3.new(v.X, v.Y * (CombatConfig.Locomotion_JumpCutKeep or 0.45), v.Z)
	return true
end

function LocomotionModule.checkAndJump(fighter, humanoid, rootPart, forwardImpulse)
	local hasObstacle, height = LocomotionModule.detectObstacle(rootPart)
	if hasObstacle then
		local jumpType = (height <= 5.0) and "vault" or "jump"
		LocomotionModule.jump(fighter, humanoid, rootPart, math.max(3.5, height + 2), forwardImpulse, jumpType)
		return true
	end
	return false
end

-- ============================================================================
-- 5. ATHLETIC DASH & SLIDE ROUTINES
-- ============================================================================

function LocomotionModule.dash(fighter, humanoid, rootPart, targetPos, distance)
	-- tick(): every reader of LastDashTime compares against tick(). Written with os.clock()
	-- the cooldown never applied and dashes could chain back to back.
	fighter:SetAttribute("LastDashTime", tick())

	local speedMult = workspace:GetAttribute("GameSpeedMultiplier") or 1.0
	local dist = distance or 35
	-- The dash stops short at striking range. It used to cover at least 31 studs whatever the
	-- gap, so from a 16-22 stud standoff it drove straight through the target and shoved it.
	-- Short gaps become a quick step-in at a lower speed over the same minimum duration.
	local travel = math.clamp(dist - (CombatConfig.CombatRange or 8) * 0.9, 8, 60)
	local maxDashSpeed = (CombatConfig.DashSpeed or 110) * speedMult
	local slideDuration = math.clamp(travel / maxDashSpeed, 0.22 / speedMult, 0.55 / speedMult)
	local dashSpeed = math.min(maxDashSpeed, travel / (slideDuration * 0.8)) -- 0.8: mean of the slide's speed envelope

	-- Energy drain
	local energy = fighter:GetAttribute("Energy") or 100
	local drain = CombatConfig.EnergyDrain_Dash or 20
	fighter:SetAttribute("Energy", math.max(0, energy - drain))

	-- Direction
	local dashDir
	if targetPos then
		local diff = targetPos - rootPart.Position
		local flatDiff = Vector3.new(diff.X, 0, diff.Z)
		dashDir = flatDiff.Magnitude > 0.001 and flatDiff.Unit or rootPart.CFrame.LookVector
	else
		local look = rootPart.CFrame.LookVector
		dashDir = Vector3.new(look.X, 0, look.Z).Unit
	end

	-- Face the dash through the humanoid's own turn (or the active facing gyro); the one-shot
	-- CFrame blend here yawed the body up to 60 degrees in a single frame
	getLocoData(fighter).steerUntil = 0
	humanoid:Move(dashDir, false)

	-- Animation & Sensory VFX
	AnimationModule.stopConfig(humanoid, "Movement.Run")
	AnimationModule.playConfig(humanoid, "Movement.Dash", 1.4, Enum.AnimationPriority.Action3, false)
	AudioModule.playDash(rootPart)
	VfxModule.createVaporCone(rootPart, 0.4)

	-- Physical propulsion
	KnockbackModule.applySlide(fighter, dashDir, dashSpeed, slideDuration)

	task.delay(slideDuration, function()
		if humanoid and humanoid.Parent then
			AnimationModule.stopConfig(humanoid, "Movement.Dash", 0.1)
		end
	end)

	return slideDuration
end

-- Run Slide: a single clip carries run stride -> drop -> glide -> rise -> run strides.
-- Physics follows the clip's own timeline (Slide_* markers in CombatConfig), so the body
-- keeps its run momentum until the drop, bleeds speed to friction during the glide, and
-- regains pace while rising. At Slide_ExitTime the gait resumes on the footfall that
-- matches the clip pose, so run -> slide -> run is one continuous motion.
endSlide = function(fighter, humanoid, rootPart, handOff)
	local s = activeSlides[fighter]
	if not s then return end
	activeSlides[fighter] = nil
	if s.conn then s.conn:Disconnect() end
	if s.stoppedConn then s.stoppedConn:Disconnect() end
	if s.lv and s.lv.Parent then s.lv:Destroy() end
	VfxModule.stopSlideSmoke(s.smoke)
	if s.att and s.att.Parent then s.att:Destroy() end
	if s.savedCollide then
		for part in pairs(s.savedCollide) do
			if part.Parent then part.CanCollide = true end
		end
	end
	if s.rootCollide and rootPart and rootPart.Parent then
		rootPart.CanCollide = true
	end
	if s.platformStand and humanoid and humanoid.Parent then
		humanoid.PlatformStand = false
		humanoid:ChangeState(Enum.HumanoidStateType.Running)
	end
	if fighter.Parent then
		fighter:SetAttribute("LocomotionAction", nil)
	end
	if not humanoid or not humanoid.Parent then return end
	humanoid.AutoRotate = true
	if handOff and rootPart and rootPart.Parent then
		-- Carry the exit speed into the drivers' acceleration curve and resume the gait
		-- on the matching footfall while the slide clip crossfades out.
		local v = rootPart.AssemblyLinearVelocity
		humanoid.WalkSpeed = Vector3.new(v.X, 0, v.Z).Magnitude
		getLocoData(fighter).currentSpeed = humanoid.WalkSpeed
		GaitModule.setEntryPhase(humanoid, CombatConfig.Slide_ExitGaitPhase or 0.35)
		GaitModule.update(humanoid, rootPart, 1 / 60)
		AnimationModule.stopConfig(humanoid, "Movement.Slide", CombatConfig.Slide_ExitFade or 0.18)
	else
		AnimationModule.stopConfig(humanoid, "Movement.Slide", 0.12)
	end
end

-- Returns the slide's duration in seconds, or 0 when a slide cannot start.
-- slideDir is accepted for API compatibility; a slide always commits to the current
-- travel direction because it is momentum, not a new drive.
-- opts.underGap: sliding under something (a bar 4-8 studs up). The pose goes low but the
-- collision body stays 8 tall, so it hit the bar and was bumped up onto it; collision is off
-- for the slide (the Humanoid keeps its height above the floor by its own ray).
function LocomotionModule.slide(fighter, humanoid, rootPart, slideDir, _legacyDuration, opts)
	if not fighter or not humanoid or not rootPart then return 0 end
	if activeSlides[fighter] or isHumanoidAirborne(humanoid) then return 0 end

	local vel = rootPart.AssemblyLinearVelocity
	local flatVel = Vector3.new(vel.X, 0, vel.Z)
	local startSpeed = flatVel.Magnitude
	if startSpeed < (CombatConfig.Slide_MinStartSpeed or 8.0) then return 0 end
	local dir = flatVel.Unit
	-- (a slide aimed at something - a tackle - turns onto it if that is within maxTurn of the run)
	if opts and opts.aim then
		local aim = Vector3.new(opts.aim.X, 0, opts.aim.Z)
		if aim.Magnitude > 0.01 and aim.Unit:Dot(dir) >= math.cos(math.rad(opts.maxTurn or 40)) then
			dir = aim.Unit
		end
	end
	-- A slide is not steered once it starts, so it must not head off a raised edge
	do
		local glideLength = math.clamp(startSpeed * 1.1, 10, 35)
		local goal, bent = SpatialModule.keepOnSurface(rootPart, rootPart.Position + dir * glideLength, rootPart.Position, glideLength)
		if bent then
			local flatGoal = Vector3.new(goal.X - rootPart.Position.X, 0, goal.Z - rootPart.Position.Z)
			if flatGoal.Magnitude < 0.5 then return 0 end -- nowhere to slide to
			dir = flatGoal.Unit
		end
	end

	local now = os.clock()
	fighter:SetAttribute("LastSlideTime", tick()) -- readers compare against tick()
	fighter:SetAttribute("LastActivityTime", now)

	-- Energy drain
	local energy = fighter:GetAttribute("Energy") or 100
	fighter:SetAttribute("Energy", math.max(0, energy - (CombatConfig.SlideMinEnergy or 12)))

	local speedMult = workspace:GetAttribute("GameSpeedMultiplier") or 1.0
	local rate = (CombatConfig.Slide_AnimRate or 1.15) * speedMult
	local dropT = CombatConfig.Slide_DropTime or 0.10
	local stopT = CombatConfig.Slide_StopTime or 1.07
	local exitT = CombatConfig.Slide_ExitTime or 1.38
	local glideStart = math.max(startSpeed * (CombatConfig.Slide_EntryBoost or 1.10), (CombatConfig.Slide_MinEntrySpeed or 30.0) * speedMult)
	local glideEnd = glideStart * (CombatConfig.Slide_EndSpeedRatio or 0.55)
	local recoverSpeed = math.max(startSpeed, glideEnd)

	-- The clip contains its own run strides in and out: hand the base gait over to it
	fighter:SetAttribute("LocomotionAction", "Slide")
	GaitModule.stop(humanoid, 0.12)
	AnimationModule.stop(humanoid, "Movement.StopRun", 0.08)
	local track = AnimationModule.playConfig(humanoid, "Movement.Slide", 1.0, Enum.AnimationPriority.Action3, false)
	AudioModule.playDash(rootPart)
	VfxModule.createDust(rootPart.Position - dir * 2, 4, nil, fighter:GetAttribute("Element"))

	humanoid.AutoRotate = false

	local att = Instance.new("Attachment")
	att.Name = "LocoSlideAtt"
	att.Parent = rootPart
	local lv = Instance.new("LinearVelocity")
	lv.Name = "LocoSlideLV"
	lv.Attachment0 = att
	lv.RelativeTo = Enum.ActuatorRelativeTo.World
	lv.ForceLimitMode = Enum.ForceLimitMode.PerAxis
	lv.MaxAxesForce = Vector3.new(150000, 0, 150000)
	lv.VectorVelocity = dir * startSpeed
	lv.Parent = rootPart

	local slide = { dir = dir, lv = lv, att = att, smoke = VfxModule.createSlideSmoke(rootPart), lastMark = 0, onGlide = opts and opts.onGlide }
	activeSlides[fighter] = slide
	if opts and opts.underGap then
		slide.savedCollide = {}
		for _, part in ipairs(fighter:GetDescendants()) do
			if part:IsA("BasePart") and part.CanCollide and part ~= rootPart then
				slide.savedCollide[part] = true
				part.CanCollide = false
			end
		end
		-- the root (2 x 2 x 1 at hip height) is the Humanoid's floor contact: it stays solid but
		-- must not catch the bar either
		if rootPart.CanCollide then
			slide.rootCollide = true
			rootPart.CanCollide = false
		end
		-- Its root rides higher (5.4 studs) than a low gap's underside: the Humanoid's own floor
		-- sensor found the bar and stood the body up on it (it climbed 5 studs). Under a gap the
		-- slide carries the body at its height instead (platform-stand, the mover holds Y).
		humanoid.PlatformStand = true
		slide.platformStand = true
		slide.underGap = true
		lv.MaxAxesForce = Vector3.new(150000, 150000, 150000)
	end

	-- A higher-tier reaction (hit, knockback) that stops the clip ends the glide.
	-- (Stopped never fires for our own exit: endSlide clears activeSlides first.)
	if track then
		slide.stoppedConn = track.Stopped:Once(function()
			if activeSlides[fighter] == slide then
				endSlide(fighter, humanoid, rootPart, false)
			end
		end)
	end

	local startClock = os.clock()
	slide.conn = RunService.Heartbeat:Connect(function()
		if not fighter.Parent or not humanoid.Parent or humanoid.Health <= 0 or not rootPart.Parent then
			endSlide(fighter, humanoid, rootPart, false)
			return
		end
		-- Sliding off a ledge or being launched ends the glide; the air contract takes over
		if isHumanoidAirborne(humanoid) then
			endSlide(fighter, humanoid, rootPart, false)
			return
		end

		-- Follow the clip's own clock once it is playing; until the asset has loaded,
		-- advance on wall time at the clip rate so physics never stalls.
		local t = (os.clock() - startClock) * rate
		if track and track.IsPlaying and track.Length > 0 then
			t = track.TimePosition
		end

		-- Under a gap the slide does not come up while something is still low overhead (it
		-- rose and turned its collision back on half under the next bar, and was thrown off
		-- the lane): it stays in the glide, which also carries it under bars close together.
		-- held at its height with nothing under it (gone past an edge): end it now rather than
		-- carry the body out over the drop
		if slide.underGap and not LocomotionModule.isOnGround(rootPart, humanoid) then
			endSlide(fighter, humanoid, rootPart, false)
			return
		end
		if slide.underGap and t >= stopT - 0.12 then
			local params = RaycastParams.new()
			params.FilterType = Enum.RaycastFilterType.Exclude
			params.FilterDescendantsInstances = { fighter, Workspace:FindFirstChild("QuinServer") }
			params.RespectCanCollide = true
			local feet = rootPart.Position - Vector3.new(0, rootPart.Size.Y / 2 + humanoid.HipHeight - 0.5, 0)
			local low = false
			for _, along in ipairs({ -2, 0, 2.5, 5 }) do
				if Workspace:Raycast(feet + dir * along, Vector3.new(0, 8.5, 0), params) then
					low = true
					break
				end
			end
			if low and os.clock() - startClock < 4 then
				if track and track.IsPlaying and track.Length > 0 then
					track.TimePosition = math.max(dropT + 0.1, stopT - 0.35)
				end
				lv.VectorVelocity = dir * math.max(glideEnd, 22)
				return
			end
		end

		local speed
		if t < dropT then
			speed = startSpeed -- still in the run stride: hold momentum
		elseif t < stopT then
			local p = (t - dropT) / (stopT - dropT)
			local entry = math.clamp(p / 0.12, 0, 1) -- ease the boost in over the drop
			local glide = glideStart + (glideEnd - glideStart) * p -- constant friction
			speed = startSpeed + (glide - startSpeed) * entry
		elseif t < exitT then
			local p = (t - stopT) / (exitT - stopT)
			speed = glideEnd + (recoverSpeed - glideEnd) * p * 0.6 -- legs drive again while rising
		else
			endSlide(fighter, humanoid, rootPart, true)
			return
		end
		lv.VectorVelocity = dir * speed

		-- (a tackle checks its lane every glide frame: Modules/SlideTackle)
		if slide.onGlide and t >= dropT and t < stopT then
			local ok, err = pcall(slide.onGlide, t, speed, dir)
			if not ok then
				slide.onGlide = nil
				warn("[Slide] onGlide: " .. tostring(err))
			end
		end

		-- The glide leaves a streak on the turf
		if t >= dropT and t < stopT and os.clock() - slide.lastMark >= 0.07 then
			slide.lastMark = os.clock()
			VfxModule.createGroundMark(rootPart, dir, speed * 0.08 + 0.6, 1.0, 3.5)
		end
	end)

	return exitT / rate
end

-- ============================================================================
-- 6. CLEANUP & LIFECYCLE
-- ============================================================================

function LocomotionModule.cleanup(fighter)
	if activeSlides[fighter] then
		endSlide(fighter, fighter:FindFirstChildOfClass("Humanoid"), fighter:FindFirstChild("HumanoidRootPart"), false)
	end
	if steerConns[fighter] then
		steerConns[fighter]:Disconnect()
		steerConns[fighter] = nil
	end
	local data = locoData[fighter]
	if data then
		if data.activeLandedConn then
			data.activeLandedConn:Disconnect()
		end
		if data.activeAlign and data.activeAlign.Parent then
			data.activeAlign:Destroy()
		end
		if data.activeAtt and data.activeAtt.Parent then
			data.activeAtt:Destroy()
		end
	end
	locoData[fighter] = nil
end

LocomotionModule.performJump = LocomotionModule.jump

return LocomotionModule
