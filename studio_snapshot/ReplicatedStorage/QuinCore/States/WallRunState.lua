--// WallRunState.lua
-- Parkour wall-run: the Quin leaves the floor, carries its momentum along a vertical wall, and
-- kicks off at the end. It is an arc, not a ledge: the speed it arrives with is what it has.
-- Part of that speed goes into the climb (WallRun_ClimbRatio); while its feet are on the wall it
-- falls at a fraction of gravity (WallRun_GravityScale: the push of its feet against the wall
-- carries the rest) and loses speed along the wall (WallRun_Drag). So it rises, tops out and
-- starts to sink, and the faster it came in the higher and further it goes (measured: 16 studs
-- up and 98 along in 2.3 s from 48 studs/s; by the same arc about 10 up and 75 along from 40,
-- 6 up and 40 along from 30). When it is sinking fast (WallRun_SinkSpeed) it kicks off.
-- (It used to climb 3.5 studs, hold that height at a fixed 48 studs/s and let go after 1.25 s.)
-- The root is driven by a velocity constraint (along the wall, the arc, the distance held from
-- the wall); the presentation layer leans the body away from the wall
-- (CombatConfig.WallRunTiltDegrees, read from the WallRunSide attribute).

local DebugDraw = require(game:GetService("ReplicatedStorage"):WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("DebugDraw"))
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")
local Workspace = game:GetService("Workspace")

local QuinCore = ReplicatedStorage:WaitForChild("QuinCore")
local CombatConfig = require(QuinCore:WaitForChild("CombatConfig"))
local AnimationModule = require(QuinCore:WaitForChild("Modules"):WaitForChild("AnimationModule"))
local GaitModule = require(QuinCore:WaitForChild("Modules"):WaitForChild("GaitModule"))
local SpatialModule = require(QuinCore:WaitForChild("Modules"):WaitForChild("SpatialModule"))
local TargetingModule = require(QuinCore:WaitForChild("Modules"):WaitForChild("TargetingModule"))
local VfxModule = require(QuinCore:WaitForChild("Modules"):WaitForChild("VfxModule"))
local RuntimeTracer = require(QuinCore:WaitForChild("Modules"):WaitForChild("RuntimeTracer"))

local WallRunState = { name = "WallRun" }
local wallRunData = setmetatable({}, { __mode = "k" })

local MOVER_NAME = "WallRun_Velocity"
local ALIGN_NAME = "WallRun_Align"
local ATT_NAME = "WallRun_Att"

-- How long a nearby target is ignored before it can end the run
local MIN_COMMIT_TIME = 0.35
-- Wall probe reach from the root, and the gap the body holds from the wall
local WALL_PROBE_DISTANCE = 5.5
local WALL_HOLD_DISTANCE = 2.4

-- The wall beside the body, found by looking both ways. (The run used to assume the wall was
-- on the left whenever SpatialModule.detectWallRunSurface failed at the start: with the wall on
-- the right it then probed empty air and dropped off after 0.1 s.)
local function wallBeside(fighter, rootPart)
	local params = RaycastParams.new()
	params.FilterDescendantsInstances = { fighter, Workspace:FindFirstChild("QuinServer") }
	params.FilterType = Enum.RaycastFilterType.Exclude
	local best, bestSide = nil, nil
	for _, side in ipairs({ "Left", "Right" }) do
		local dir = rootPart.CFrame.RightVector * (side == "Left" and -1 or 1)
		local hit = Workspace:Raycast(rootPart.Position, Vector3.new(dir.X, 0, dir.Z).Unit * (WALL_PROBE_DISTANCE + 1), params)
		if hit and math.abs(hit.Normal.Y) < 0.3 and (not best or hit.Distance < best.Distance) then
			best, bestSide = hit, side
		end
	end
	if not best then return nil end
	local normal = Vector3.new(best.Normal.X, 0, best.Normal.Z).Unit
	local look = rootPart.CFrame.LookVector
	local along = Vector3.new(look.X, 0, look.Z) - normal * Vector3.new(look.X, 0, look.Z):Dot(normal)
	if along.Magnitude < 0.1 then return nil end
	return { normal = normal, tangent = along.Unit, side = bestSide, wallDistance = best.Distance }
end

local function removeMovers(rootPart)
	for _, name in ipairs({ MOVER_NAME, ALIGN_NAME, ATT_NAME }) do
		local child = rootPart:FindFirstChild(name)
		if child then child:Destroy() end
	end
end

-- Velocity for this moment of the run: along the wall, toward the run height, and toward the
-- hold distance from the wall
local function runVelocity(data, rootPart, wallDistance)
	local intoWall = wallDistance and math.clamp((wallDistance - WALL_HOLD_DISTANCE) * 6, -6, 10) or 0
	return data.tangent * data.along + Vector3.new(0, data.rise, 0) - data.normal * intoWall
end

-- A wall run is a sprint: a Quin goes up a wall only with this much of its speed along it.
-- (It used to start from 18 studs/s and read as a jog, even a walk, up the wall.) Chase and
-- Retreat ask before they send it up.
function WallRunState.fastEnough(rootPart, wallSurface)
	local velocity = rootPart.AssemblyLinearVelocity
	return Vector3.new(velocity.X, 0, velocity.Z):Dot(wallSurface.tangent) >= (CombatConfig.WallRun_MinEntrySpeed or 32)
end

function WallRunState.enter(fighter, humanoid, rootPart)
	local now = os.clock()
	fighter:SetAttribute("LastWallRunTime", tick()) -- readers compare against tick()

	local speedMult = workspace:GetAttribute("GameSpeedMultiplier") or 1.0
	local wallRunSpeed = (CombatConfig.WallRunSpeed or 48) * speedMult
	local maxDuration = (CombatConfig.WallRunMaxDuration or 1.25) / speedMult

	local energy = fighter:GetAttribute("Energy") or 100
	fighter:SetAttribute("Energy", math.max(0, energy - (CombatConfig.WallRunMinEnergy or 15)))

	-- The caller just detected the surface; read it again from the current position
	local wallInfo = SpatialModule.detectWallRunSurface(rootPart, CombatConfig.WallRunRayDistance or 5.2)
		or wallBeside(fighter, rootPart)
	local tangent = rootPart.CFrame.LookVector
	local normal = -rootPart.CFrame.RightVector
	local side = "Left"
	if wallInfo then
		tangent = wallInfo.tangent
		normal = wallInfo.normal
		side = wallInfo.side
	end
	fighter:SetAttribute("WallRunFound", wallInfo ~= nil) -- (debug: false = no wall either side, the run is dropped)

	RuntimeTracer.checkpoint(fighter, string.format("Enter WallRun (Side=%s, Speed=%.1f, Runway=%.0f)", side, wallRunSpeed, wallInfo and wallInfo.runway or 0))
	fighter:SetAttribute("WallRunSide", side)

	-- The velocity constraint owns translation for the whole run
	humanoid.WalkSpeed = 0
	humanoid.AutoRotate = false
	removeMovers(rootPart)

	-- What it brings to the wall: its speed along it (at least the speed a run needs, at most
	-- the wall-run's top speed), and the share of that it puts into the climb
	local velocity = rootPart.AssemblyLinearVelocity
	local arriving = Vector3.new(velocity.X, 0, velocity.Z):Dot(tangent)
	-- (test hook: WallRunEntrySpeed on the Quin stands in for the speed it arrives with, once)
	local staged = fighter:GetAttribute("WallRunEntrySpeed")
	if staged then
		arriving = staged
		fighter:SetAttribute("WallRunEntrySpeed", nil)
	end
	local along = math.clamp(arriving, CombatConfig.WallRun_MinEntrySpeed or 32, wallRunSpeed)
	local data = {
		startTime = now,
		lastUpdate = now,
		maxDuration = maxDuration,
		wallRunSpeed = wallRunSpeed, -- (the lane ahead is probed at this speed)
		along = along,
		rise = along * (CombatConfig.WallRun_ClimbRatio or 0.6),
		startY = rootPart.Position.Y,
		tangent = tangent,
		normal = normal,
		side = side,
		origWalkSpeed = fighter:GetAttribute("Speed") or 40,
	}
	wallRunData[fighter] = data

	local att = Instance.new("Attachment")
	att.Name = ATT_NAME
	att.Parent = rootPart

	local lv = Instance.new("LinearVelocity")
	lv.Name = MOVER_NAME
	lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	lv.MaxForce = 450000
	lv.VectorVelocity = runVelocity(data, rootPart, wallInfo and wallInfo.wallDistance)
	lv.Attachment0 = att
	lv.Parent = rootPart
	data.linearVelocity = lv

	-- Turn onto the wall's tangent with torque (assigning the CFrame yawed the body up to 75
	-- degrees in a single frame)
	local align = Instance.new("AlignOrientation")
	align.Name = ALIGN_NAME
	align.Mode = Enum.OrientationAlignmentMode.OneAttachment
	align.RigidityEnabled = false
	align.Responsiveness = 40
	align.MaxTorque = 1000000
	align.CFrame = CFrame.lookAt(Vector3.zero, tangent)
	align.Attachment0 = att
	align.Parent = rootPart

	data.noWall = wallInfo == nil
	-- Only the run plays on a wall. Whatever locomotion clip the last state left on the body (a
	-- strafe from Circling, the gait's sideways blend) is stopped first: nothing updates it here,
	-- so it stayed at full weight and the Quin strafed along the wall.
	GaitModule.stop(humanoid, 0.1)
	local animator = humanoid:FindFirstChildOfClass("Animator")
	for _, track in ipairs(animator and animator:GetPlayingAnimationTracks() or {}) do
		if track.Looped and track.Priority == Enum.AnimationPriority.Movement then
			track:Stop(0.1)
		end
	end
	-- the stride follows the body's real speed (along and up), not a fixed rate
	data.track = AnimationModule.playConfig(humanoid, "Movement.Run", 1.35, Enum.AnimationPriority.Movement, true)
	VfxModule.createDust(rootPart.Position + (normal * 0.8), 3, nil, fighter:GetAttribute("Element"))
end

function WallRunState.update(fighter, humanoid, rootPart, DEBUG)
	local data = wallRunData[fighter]
	if not data then
		return require(script.Parent:WaitForChild("IdleState"))
	end
	if data.noWall then
		RuntimeTracer.checkpoint(fighter, "WallRun: no wall either side, dropped")
		fighter:SetAttribute("WallKickReason", "NoWall 0.00s")
		return require(script.Parent:WaitForChild("ChaseState"))
	end

	-- Same clock as data.startTime. With tick() here `elapsed` was ~1.7e9 seconds, so every
	-- wall-run hit its max duration on the first update.
	local nowClock = os.clock()
	local elapsed = nowClock - data.startTime
	local dt = math.clamp(nowClock - data.lastUpdate, 0, 0.25)
	data.lastUpdate = nowClock

	-- The arc: it falls at a fraction of gravity and loses speed along the wall
	data.rise -= Workspace.Gravity * (CombatConfig.WallRun_GravityScale or 0.15) * dt
	data.along = math.max(data.along - (CombatConfig.WallRun_Drag or 5) * dt, 0)
	-- Spent: sinking, back down where it started, or too slow to stay on the wall
	local spent = data.rise <= -(CombatConfig.WallRun_SinkSpeed or 8)
		or (data.rise < 0 and rootPart.Position.Y <= data.startY)
		or data.along < (CombatConfig.WallRun_MinAlongSpeed or 14)

	local checkParams = RaycastParams.new()
	checkParams.FilterDescendantsInstances = { fighter, Workspace:FindFirstChild("QuinServer") }
	checkParams.FilterType = Enum.RaycastFilterType.Exclude
	local wallHit = DebugDraw.raycast(rootPart, rootPart.Position, -data.normal * WALL_PROBE_DISTANCE, checkParams)
	local wallLost = wallHit == nil
	-- A corner or obstacle in the lane ends the run before the body hits it
	local laneBlocked = DebugDraw.raycast(rootPart, rootPart.Position, data.tangent * (data.wallRunSpeed * 0.15), checkParams) ~= nil

	local target, dist = TargetingModule.getNearest(rootPart, 18)
	local interceptTarget = target ~= nil and dist ~= nil and dist <= 14.0 and elapsed >= MIN_COMMIT_TIME

	if elapsed >= data.maxDuration or wallLost or laneBlocked or interceptTarget or spent then
		local reason = (wallLost and "WallEnd") or (laneBlocked and "LaneBlocked") or (interceptTarget and "TargetIntercept") or (spent and "ArcSpent") or "Duration"
		RuntimeTracer.checkpoint(fighter, string.format("Wall-Kick Dismount (Reason: %s, %.2fs)", reason, elapsed))
		fighter:SetAttribute("WallKickReason", string.format("%s %.2fs", reason, elapsed)) -- (debug HUD, probes)

		-- Kick off the wall: out, forward and up
		local kickImpulse = (data.normal * (CombatConfig.WallKickOutwardImpulse or 28))
			+ (data.tangent * (CombatConfig.WallKickForwardImpulse or 34))
			+ Vector3.new(0, CombatConfig.WallKickUpwardImpulse or 18, 0)

		local lv = data.linearVelocity
		if lv and lv.Parent then
			lv.VectorVelocity = kickImpulse
			lv.MaxForce = 350000
			lv.Name = "WallKick_Velocity" -- outlives the state for the length of the kick
			Debris:AddItem(lv, 0.22)
		end
		data.linearVelocity = nil

		local align = rootPart:FindFirstChild(ALIGN_NAME)
		if align then
			align.CFrame = CFrame.lookAt(Vector3.zero, Vector3.new(kickImpulse.X, 0, kickImpulse.Z))
			align.Name = "WallKick_Align"
			Debris:AddItem(align, 0.22)
		end
		local att = rootPart:FindFirstChild(ATT_NAME)
		if att then
			att.Name = "WallKick_Att"
			Debris:AddItem(att, 0.22)
		end

		AnimationModule.playConfig(humanoid, "Parkour.VaultObstacle", 1.25, Enum.AnimationPriority.Action, false)
		VfxModule.createShockwave(rootPart.Position, 8, 0.35, fighter:GetAttribute("Element"))
		-- (off the wall it may dash on: at its target, or after one that kept running; Modules/AirDash)
		require(script.Parent.Parent:WaitForChild("Modules"):WaitForChild("AirDash")).noteWallKick(fighter)

		if interceptTarget and dist <= (CombatConfig.CombatRange or 8.2) + 2.0 then
			return require(script.Parent:WaitForChild("FightState"))
		end
		return require(script.Parent:WaitForChild("ChaseState"))
	end

	if data.linearVelocity then
		data.linearVelocity.VectorVelocity = runVelocity(data, rootPart, wallHit.Distance)
	end
	if data.track and data.track.IsPlaying then
		local speed = math.sqrt(data.along * data.along + data.rise * data.rise)
		local rate = math.clamp(speed / (CombatConfig.Gait_RunAuthoredSpeed or 29.5), CombatConfig.WallRun_MinClipRate or 0.9, CombatConfig.WallRun_MaxClipRate or 1.9)
		data.track:AdjustSpeed(rate)
	end

	-- Friction dust along the wall
	if math.random() < 0.40 then
		VfxModule.createDust(rootPart.Position - (data.normal * 1.2), 2, nil, fighter:GetAttribute("Element"))
	end

	return WallRunState
end

function WallRunState.exit(fighter, humanoid, rootPart)
	local data = wallRunData[fighter]
	if not data then return end

	removeMovers(rootPart)

	-- Release the wall-run stride; the next state's driver resumes the ground gait
	-- (or the ground contract covers the dismount with the Fall pose)
	GaitModule.stop(humanoid, 0.15)

	humanoid.AutoRotate = true
	humanoid.WalkSpeed = data.origWalkSpeed

	fighter:SetAttribute("WallRunSide", nil)
	wallRunData[fighter] = nil
end

return WallRunState
