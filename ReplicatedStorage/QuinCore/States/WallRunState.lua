--// WallRunState.lua
-- Dynamic Parkour Wall-Running: momentum maintenance along vertical walls with wall-kick dismount
-- Adheres strictly to PHYSICS ≠ VISUALS: physical HRP maintains tangent velocity, visual rig banks into wall

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local QuinCore = ReplicatedStorage:WaitForChild("QuinCore")
local CombatConfig = require(QuinCore:WaitForChild("CombatConfig"))
local AnimationModule = require(QuinCore:WaitForChild("Modules"):WaitForChild("AnimationModule"))
local SpatialModule = require(QuinCore:WaitForChild("Modules"):WaitForChild("SpatialModule"))
local TargetingModule = require(QuinCore:WaitForChild("Modules"):WaitForChild("TargetingModule"))
local VfxModule = require(QuinCore:WaitForChild("Modules"):WaitForChild("VfxModule"))
local RuntimeTracer = require(QuinCore:WaitForChild("Modules"):WaitForChild("RuntimeTracer"))

local WallRunState = { name = "WallRun" }
local wallRunData = {}

-- Helper to find RootJoint for visual procedural banking
local function findRootJoint(model)
	local rootPart = model:FindFirstChild("HumanoidRootPart")
	if not rootPart then return nil end
	for _, desc in ipairs(model:GetDescendants()) do
		if desc:IsA("Motor6D") and (desc.Part0 == rootPart or desc.Part1 == rootPart) then
			return desc
		end
	end
	return nil
end

function WallRunState.enter(fighter, humanoid, rootPart)
	local now = os.clock()
	fighter:SetAttribute("LastWallRunTime", now)
	fighter:SetAttribute("CurrentState", WallRunState.name)

	local speedMult = workspace:GetAttribute("GameSpeedMultiplier") or 1.0
	local baseSpeed = CombatConfig.WallRunSpeed or 48
	local wallRunSpeed = baseSpeed * speedMult
	local maxDuration = (CombatConfig.WallRunMaxDuration or 1.25) / speedMult

	-- Energy drain
	local energy = fighter:GetAttribute("Energy") or 100
	local cost = CombatConfig.WallRunMinEnergy or 15
	fighter:SetAttribute("Energy", math.max(0, energy - cost))

	-- Query spatial surface information stored or freshly detected
	local wallInfo = SpatialModule.detectWallRunSurface(rootPart, CombatConfig.WallRunRayDistance or 5.2)
	local tangent = rootPart.CFrame.LookVector
	local normal = -rootPart.CFrame.RightVector
	local side = "Left"

	if wallInfo then
		tangent = wallInfo.tangent
		normal = wallInfo.normal
		side = wallInfo.side
	end

	RuntimeTracer.checkpoint(fighter, string.format("Enter WallRun (Side=%s, Speed=%.1f)", side, wallRunSpeed))
	fighter:SetAttribute("WallRunSide", side)

	-- Lock humanoid locomotion so physical BodyVelocity handles momentum
	humanoid.WalkSpeed = 0
	humanoid.AutoRotate = false

	-- Physical suspension constraint: horizontal tangent movement + gentle downward drift
	local att = Instance.new("Attachment")
	att.Name = "WallRun_Att"
	att.Parent = rootPart

	local lv = Instance.new("LinearVelocity")
	lv.Name = "WallRun_Velocity"
	lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	lv.MaxForce = 450000
	lv.VectorVelocity = (tangent * wallRunSpeed) + Vector3.new(0, -2.5, 0)
	lv.Attachment0 = att
	lv.Parent = rootPart

	-- Orient physical HRP along tangent forward
	rootPart.CFrame = CFrame.lookAt(rootPart.Position, rootPart.Position + tangent)

	-- Visual Procedural Banking: tilt RootJoint toward wall surface (Roll angle)
	local rootJoint = findRootJoint(fighter)
	local origC0 = nil
	local tiltDeg = CombatConfig.WallRunTiltDegrees or 18
	if side == "Left" then
		tiltDeg = -tiltDeg
	end

	if rootJoint then
		origC0 = rootJoint:GetAttribute("OriginalC0")
		if not origC0 then
			origC0 = rootJoint.C0
			rootJoint:SetAttribute("OriginalC0", origC0)
		end
		-- Bank visual body inward toward wall
		rootJoint.C0 = origC0 * CFrame.Angles(0, 0, math.rad(tiltDeg))
	end

	-- Animation & Visual friction effects
	AnimationModule.playConfig(humanoid, "Movement.Run", 1.35, Enum.AnimationPriority.Movement, true)
	local elem = fighter:GetAttribute("Element")
	VfxModule.createDust(rootPart.Position + (normal * 0.8), 3, nil, elem)

	wallRunData[fighter] = {
		startTime = now,
		maxDuration = maxDuration,
		wallRunSpeed = wallRunSpeed,
		tangent = tangent,
		normal = normal,
		side = side,
		linearVelocity = lv,
		att = att,
		rootJoint = rootJoint,
		origC0 = origC0,
		isDismounting = false,
		origWalkSpeed = fighter:GetAttribute("Speed") or 40,
	}
end

function WallRunState.update(fighter, humanoid, rootPart, DEBUG)
	local data = wallRunData[fighter]
	if not data then
		return require(script.Parent:WaitForChild("IdleState"))
	end

	local now = tick()
	local elapsed = now - data.startTime

	-- 1. Wall presence verification: cast ray into wall normal
	local checkParams = RaycastParams.new()
	checkParams.FilterDescendantsInstances = { fighter }
	checkParams.FilterType = Enum.RaycastFilterType.Exclude

	-- Ray into the wall surface
	local wallRayHit = Workspace:Raycast(rootPart.Position, (-data.normal) * 4.5, checkParams)
	local wallLost = (not wallRayHit or not wallRayHit.Instance)

	-- 2. Target intercept check: target within athletic strike/kick range
	local target, dist = TargetingModule.getNearest(rootPart, 18)
	local interceptTarget = (target and dist and dist <= 14.0)

	-- 3. Check for Wall-Kick Dismount trigger
	if elapsed >= data.maxDuration or wallLost or interceptTarget then
		data.isDismounting = true
		RuntimeTracer.checkpoint(fighter, string.format("Wall-Kick Dismount (Reason: %s)", 
			wallLost and "WallEnd" or (interceptTarget and "TargetIntercept" or "Duration")))

		-- Trigger explosive outward Wall-Kick impulse
		local outward = (CombatConfig.WallKickOutwardImpulse or 28)
		local forward = (CombatConfig.WallKickForwardImpulse or 34)
		local upward = (CombatConfig.WallKickUpwardImpulse or 18)
		local kickImpulse = (data.normal * outward) + (data.tangent * forward) + Vector3.new(0, upward, 0)

		if data.linearVelocity and data.linearVelocity.Parent then
			data.linearVelocity.VectorVelocity = kickImpulse
			data.linearVelocity.MaxForce = 350000
			Debris:AddItem(data.linearVelocity, 0.22)
			if data.att and data.att.Parent then
				Debris:AddItem(data.att, 0.22)
			end
			data.linearVelocity = nil
			data.att = nil
		end

		-- Play vault/jump animation and launch shockwave
		AnimationModule.playConfig(humanoid, "Parkour.VaultObstacle", 1.25, Enum.AnimationPriority.Action, false)
		local elem = fighter:GetAttribute("Element")
		VfxModule.createShockwave(rootPart.Position, 8, 0.35, elem)

		-- Orient toward dismount trajectory
		rootPart.CFrame = CFrame.lookAt(rootPart.Position, rootPart.Position + Vector3.new(kickImpulse.X, 0, kickImpulse.Z))

		if interceptTarget and dist and dist <= (CombatConfig.CombatRange or 8.2) + 2.0 then
			return require(script.Parent:WaitForChild("FightState"))
		else
			return require(script.Parent:WaitForChild("ChaseState"))
		end
	end

	-- Periodic friction sparks along the wall
	if math.random() < 0.40 then
		local elem = fighter:GetAttribute("Element")
		VfxModule.createDust(rootPart.Position - (data.normal * 1.2), 2, nil, elem)
	end

	return WallRunState
end

function WallRunState.exit(fighter, humanoid, rootPart)
	local data = wallRunData[fighter]
	if not data then return end

	-- Clean up physical velocity constraint
	if data.linearVelocity and data.linearVelocity.Parent then
		data.linearVelocity:Destroy()
	end
	if data.att and data.att.Parent then
		data.att:Destroy()
	end
	local existingLv = rootPart:FindFirstChild("WallRun_Velocity")
	if existingLv then existingLv:Destroy() end
	local existingAtt = rootPart:FindFirstChild("WallRun_Att")
	if existingAtt then existingAtt:Destroy() end

	-- Smoothly restore visual torso banking
	if data.rootJoint and data.origC0 then
		local tween = TweenService:Create(
			data.rootJoint,
			TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ C0 = data.origC0 }
		)
		tween:Play()
	end

	-- Restore humanoid properties
	humanoid.AutoRotate = true
	humanoid.WalkSpeed = data.origWalkSpeed or 40

	fighter:SetAttribute("WallRunSide", nil)
	wallRunData[fighter] = nil
end

return WallRunState
