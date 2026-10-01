--// WallRunState.lua
-- Parkour wall-run: the Quin leaves the floor, carries its momentum along a vertical wall a few
-- studs up, and kicks off at the end. The root is driven by a velocity constraint (tangent speed,
-- climb to the run height, hold distance to the wall); the presentation layer leans the body away
-- from the wall (CombatConfig.WallRunTiltDegrees, read from the WallRunSide attribute).

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

local function removeMovers(rootPart)
	for _, name in ipairs({ MOVER_NAME, ALIGN_NAME, ATT_NAME }) do
		local child = rootPart:FindFirstChild(name)
		if child then child:Destroy() end
	end
end

-- Velocity for this moment of the run: along the wall, toward the run height, and toward the
-- hold distance from the wall
local function runVelocity(data, rootPart, wallDistance)
	local climb = math.clamp((data.runY - rootPart.Position.Y) * 6, -8, 14)
	local intoWall = wallDistance and math.clamp((wallDistance - WALL_HOLD_DISTANCE) * 6, -6, 10) or 0
	return data.tangent * data.wallRunSpeed + Vector3.new(0, climb, 0) - data.normal * intoWall
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
	local tangent = rootPart.CFrame.LookVector
	local normal = -rootPart.CFrame.RightVector
	local side = "Left"
	if wallInfo then
		tangent = wallInfo.tangent
		normal = wallInfo.normal
		side = wallInfo.side
	end

	RuntimeTracer.checkpoint(fighter, string.format("Enter WallRun (Side=%s, Speed=%.1f, Runway=%.0f)", side, wallRunSpeed, wallInfo and wallInfo.runway or 0))
	fighter:SetAttribute("WallRunSide", side)

	-- The velocity constraint owns translation for the whole run
	humanoid.WalkSpeed = 0
	humanoid.AutoRotate = false
	removeMovers(rootPart)

	local data = {
		startTime = now,
		maxDuration = maxDuration,
		wallRunSpeed = wallRunSpeed,
		tangent = tangent,
		normal = normal,
		side = side,
		runY = rootPart.Position.Y + (CombatConfig.WallRunHeight or 3.5),
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

	AnimationModule.playConfig(humanoid, "Movement.Run", 1.35, Enum.AnimationPriority.Movement, true)
	VfxModule.createDust(rootPart.Position + (normal * 0.8), 3, nil, fighter:GetAttribute("Element"))
end

function WallRunState.update(fighter, humanoid, rootPart, DEBUG)
	local data = wallRunData[fighter]
	if not data then
		return require(script.Parent:WaitForChild("IdleState"))
	end

	-- Same clock as data.startTime. With tick() here `elapsed` was ~1.7e9 seconds, so every
	-- wall-run hit its max duration on the first update.
	local elapsed = os.clock() - data.startTime

	local checkParams = RaycastParams.new()
	checkParams.FilterDescendantsInstances = { fighter, Workspace:FindFirstChild("QuinServer") }
	checkParams.FilterType = Enum.RaycastFilterType.Exclude
	local wallHit = Workspace:Raycast(rootPart.Position, -data.normal * WALL_PROBE_DISTANCE, checkParams)
	local wallLost = wallHit == nil
	-- A corner or obstacle in the lane ends the run before the body hits it
	local laneBlocked = Workspace:Raycast(rootPart.Position, data.tangent * (data.wallRunSpeed * 0.15), checkParams) ~= nil

	local target, dist = TargetingModule.getNearest(rootPart, 18)
	local interceptTarget = target ~= nil and dist ~= nil and dist <= 14.0 and elapsed >= MIN_COMMIT_TIME

	if elapsed >= data.maxDuration or wallLost or laneBlocked or interceptTarget then
		local reason = (wallLost and "WallEnd") or (laneBlocked and "LaneBlocked") or (interceptTarget and "TargetIntercept") or "Duration"
		RuntimeTracer.checkpoint(fighter, string.format("Wall-Kick Dismount (Reason: %s, %.2fs)", reason, elapsed))

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

		if interceptTarget and dist <= (CombatConfig.CombatRange or 8.2) + 2.0 then
			return require(script.Parent:WaitForChild("FightState"))
		end
		return require(script.Parent:WaitForChild("ChaseState"))
	end

	if data.linearVelocity then
		data.linearVelocity.VectorVelocity = runVelocity(data, rootPart, wallHit.Distance)
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
