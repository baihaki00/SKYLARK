--// LocomotionModule.lua
-- Authoritative Locomotion, Momentum Integration, Ballistic Jumps, and Traction Controller
-- Adheres strictly to the 6 Immutable Ground Rules (README.md)
-- Single Source of Truth: ReplicatedStorage.QuinCore.CombatConfig

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")

local QuinCore = ReplicatedStorage:WaitForChild("QuinCore")
local CombatConfig = require(QuinCore:WaitForChild("CombatConfig"))
local AnimationModule = require(QuinCore:WaitForChild("Modules"):WaitForChild("AnimationModule"))
local KnockbackModule = require(QuinCore:WaitForChild("Modules"):WaitForChild("KnockbackModule"))
local SpatialModule = require(QuinCore:WaitForChild("Modules"):WaitForChild("SpatialModule"))
local AudioModule = require(QuinCore:WaitForChild("Modules"):WaitForChild("AudioModule"))
local VfxModule = require(QuinCore:WaitForChild("Modules"):WaitForChild("VfxModule"))

local LocomotionModule = {}

-- Per-fighter tracking table
local locoData = {}

local function getLocoData(fighter)
	if not locoData[fighter] then
		locoData[fighter] = {
			lastJumpTime = 0,
			lastSkidTime = 0,
			currentSpeed = 0,
			activeLandedConn = nil,
			activeAlign = nil,
			activeAtt = nil,
		}
	end
	return locoData[fighter]
end

-- ============================================================================
-- 1. ACCELERATION & BRAKING (Smooth velocity modulation; zero 1-frame snaps)
-- ============================================================================

function LocomotionModule.modulateSpeed(fighter, humanoid, targetSpeed, dt)
	dt = dt or 0.1
	local data = getLocoData(fighter)
	local currentSpeed = humanoid.WalkSpeed

	local accelRate = CombatConfig.Locomotion_Acceleration or 80.0
	local brakeRate = CombatConfig.Locomotion_BrakingDeceleration or 140.0

	local newSpeed = currentSpeed
	if currentSpeed < targetSpeed then
		newSpeed = math.min(currentSpeed + (accelRate * dt), targetSpeed)
	elseif currentSpeed > targetSpeed then
		newSpeed = math.max(currentSpeed - (brakeRate * dt), targetSpeed)
	end

	humanoid.WalkSpeed = newSpeed
	data.currentSpeed = newSpeed
	return newSpeed
end

-- ============================================================================
-- 2. STEERING & TRACTION (Dynamic 180° Skid & Centripetal Steering)
-- ============================================================================

function LocomotionModule.steer(fighter, humanoid, rootPart, targetPosition, targetSpeed, dt)
	if not fighter or not humanoid or not rootPart or not targetPosition then return end

	dt = dt or 0.1
	local data = getLocoData(fighter)

	-- 1. Smoothly accelerate / decelerate to target speed
	LocomotionModule.modulateSpeed(fighter, humanoid, targetSpeed, dt)

	-- 2. Check for sharp direction reversals (180° Skid)
	local currentVel = rootPart.AssemblyLinearVelocity
	local flatVel = Vector3.new(currentVel.X, 0, currentVel.Z)
	local currentSpeed = flatVel.Magnitude

	local toTarget = (targetPosition - rootPart.Position)
	local flatDesired = Vector3.new(toTarget.X, 0, toTarget.Z)

	local skidThreshold = CombatConfig.Locomotion_SkidSpeedThreshold or 20.0
	local now = os.clock()

	if currentSpeed > skidThreshold and flatDesired.Magnitude > 2.0 then
		local curDir = flatVel.Unit
		local desDir = flatDesired.Unit
		local cosTheta = curDir:Dot(desDir)

		-- Sharp reversal: >= 120 degrees cut (cos theta < -0.5)
		if cosTheta < -0.5 and (now - data.lastSkidTime) >= 1.5 then
			data.lastSkidTime = now

			-- Visual: Play 180 Turn animation
			AnimationModule.playConfig(humanoid, "Movement.RunTurn180", 1.25, Enum.AnimationPriority.Action3, false)

			-- Physical traction slip: carry residual forward momentum along original heading
			local skidSpeed = currentSpeed * (CombatConfig.Locomotion_TractionSlipFactor or 0.35)
			KnockbackModule.applySlide(fighter, curDir, skidSpeed, 0.28)

			-- VFX: Kick up dust along skid vector
			local VfxModule = require(QuinCore:WaitForChild("Modules"):WaitForChild("VfxModule"))
			local elem = fighter:GetAttribute("Element") or "Fire"
			VfxModule.createDust(rootPart.Position, 3, curDir, elem)
		end
	end

	-- 3. Issue steering command to humanoid
	humanoid.AutoRotate = true
	humanoid:MoveTo(targetPosition)
end

-- ============================================================================
-- 3. MELEE BRAKE & CONTINUITY (Slide into combat sweet spot; zero freeze-snaps)
-- ============================================================================

function LocomotionModule.brake(fighter, humanoid, rootPart, dt)
	if not fighter or not humanoid or not rootPart then return end

	local currentVel = rootPart.AssemblyLinearVelocity
	local flatVel = Vector3.new(currentVel.X, 0, currentVel.Z)
	local speed = flatVel.Magnitude

	-- If the Quin was sprinting into range, carry follow-through momentum into melee stance
	if speed > 15.0 then
		local slideDir = flatVel.Unit
		local slideSpeed = math.min(speed * 0.45, CombatConfig.Melee_SlideSpeed or 12.0)
		KnockbackModule.applySlide(fighter, slideDir, slideSpeed, 0.18)
	end

	-- Modulate speed to 0 smoothly instead of snapping in 1 frame
	LocomotionModule.modulateSpeed(fighter, humanoid, 0, dt or 0.1)

	if AnimationModule.isPlaying(humanoid, "Movement.Run") then
		AnimationModule.stop(humanoid, "Movement.Run", 0.2)
	end
	AnimationModule.ensureBaseIdle(humanoid)
end

-- ============================================================================
-- 4. BALLISTIC JUMP (Zero BodyVelocity; Single Impulse; 88% Landing Retention)
-- ============================================================================

local MIN_JUMP_HEIGHT = 2.0
local MAX_JUMP_HEIGHT = 14.0
local JUMP_RAY_DIST = 4.5

function LocomotionModule.detectObstacle(rootPart)
	if not rootPart then return false, 0 end

	local origin = rootPart.Position + Vector3.new(0, -1, 0)
	local direction = rootPart.CFrame.LookVector * JUMP_RAY_DIST

	local params = RaycastParams.new()
	local model = rootPart:FindFirstAncestorOfClass("Model")
	if model and model ~= Workspace then
		params.FilterDescendantsInstances = { model }
	else
		params.FilterDescendantsInstances = { rootPart }
	end
	params.FilterType = Enum.RaycastFilterType.Exclude

	local result = Workspace:Raycast(origin, direction, params)
	if result and result.Instance and result.Instance.CanCollide then
		local hitPos = result.Position
		local upwardOrigin = hitPos + Vector3.new(0, MAX_JUMP_HEIGHT, 0)
		local upwardResult = Workspace:Raycast(upwardOrigin, Vector3.new(0, -MAX_JUMP_HEIGHT * 1.5, 0), params)

		local topY = upwardResult and upwardResult.Position.Y or hitPos.Y
		local groundRay = Workspace:Raycast(rootPart.Position, Vector3.new(0, -20, 0), params)
		local groundY = groundRay and groundRay.Position.Y or (rootPart.Position.Y - 2.5)
		local height = math.max(0, topY - groundY)

		if height >= MIN_JUMP_HEIGHT and height <= MAX_JUMP_HEIGHT then
			return true, height
		end
	end
	return false, 0
end

function LocomotionModule.jump(fighter, humanoid, rootPart, height, forwardImpulse, jumpType)
	-- Support both (fighter, humanoid, rootPart, ...) and (humanoid, rootPart, height, forwardImpulse, jumpType)
	if fighter and fighter:IsA("Humanoid") then
		jumpType = forwardImpulse
		forwardImpulse = height
		height = rootPart
		rootPart = humanoid
		humanoid = fighter
		fighter = rootPart and rootPart.Parent
	end
	if not fighter or not humanoid or not rootPart then return end

	local data = getLocoData(fighter)
	local now = os.clock()

	-- Enforce jump debounce to eliminate rapid-fire double-hopping
	local debounce = CombatConfig.Locomotion_JumpDebounce or 1.0
	if (now - data.lastJumpTime) < debounce then
		return
	end
	data.lastJumpTime = now

	local isVault = (jumpType == "vault")
	local isDismount = (jumpType == "dismount")
	local jumpAnim = isVault and "Parkour.VaultObstacle" or "Movement.Jump"

	AnimationModule.stop(humanoid, "Movement.Run")
	AnimationModule.playConfig(humanoid, jumpAnim)

	-- Single vertical ballistic impulse: v_y = sqrt(2 * g * h)
	local gravity = Workspace.Gravity
	local targetHeight = math.clamp(height or 8.0, 3.0, 14.0)
	local upImpulse = math.sqrt(2 * gravity * targetHeight)

	-- Forward momentum conservation
	local rootCF = rootPart.CFrame
	local flatLook = Vector3.new(rootCF.LookVector.X, 0, rootCF.LookVector.Z)
	if flatLook.Magnitude < 0.01 then
		flatLook = Vector3.new(0, 0, -1)
	else
		flatLook = flatLook.Unit
	end

	local fwdSpeed = forwardImpulse or math.max(rootPart.AssemblyLinearVelocity.Magnitude, 38.0)

	-- Direct native physics assignment: ZERO BodyVelocity!
	rootPart.AssemblyLinearVelocity = (flatLook * fwdSpeed) + Vector3.new(0, upImpulse, 0)
	rootPart.AssemblyAngularVelocity = Vector3.zero

	-- Modern AlignOrientation to prevent mid-air tumbling
	if data.activeAlign then data.activeAlign:Destroy() end
	if data.activeAtt then data.activeAtt:Destroy() end

	local align = Instance.new("AlignOrientation")
	align.Name = "Loco_JumpAlign"
	align.Mode = Enum.OrientationAlignmentMode.OneAttachment
	align.RigidityEnabled = false
	align.Responsiveness = 80
	align.MaxTorque = 300000
	align.MaxAngularVelocity = 20
	align.CFrame = CFrame.lookAt(Vector3.zero, flatLook)

	local att = Instance.new("Attachment")
	att.Name = "Loco_JumpAtt"
	att.Parent = rootPart
	align.Attachment0 = att
	align.Parent = rootPart

	data.activeAlign = align
	data.activeAtt = att
	Debris:AddItem(align, 0.35)
	Debris:AddItem(att, 0.35)

	local flightTime = math.sqrt((2 * targetHeight) / gravity) * 2
	local landedHandled = false
	local function onLanded()
		if landedHandled then return end
		landedHandled = true
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
		end

		if align and align.Parent then align:Destroy() end
		if att and att.Parent then att:Destroy() end

		AnimationModule.stopConfig(humanoid, jumpAnim)
		AnimationModule.stopConfig(humanoid, "Movement.Fall")

		if isDismount then
			AnimationModule.playConfig(humanoid, "Parkour.LedgeDropLanding", 1.4, Enum.AnimationPriority.Action3, false)
		end

		local pacingVel = fighter:GetAttribute("PacingVelocity") or 40
		local resumeAnim = pacingVel < 20 and "Movement.WalkConfident" or "Movement.Run"
		AnimationModule.playConfig(humanoid, resumeAnim)
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
end

function LocomotionModule.checkAndJump(fighter, humanoid, rootPart, forwardImpulse)
	local hasObstacle, height = LocomotionModule.detectObstacle(rootPart)
	if hasObstacle then
		local jumpType = (height <= 5.0) and "vault" or "jump"
		LocomotionModule.jump(fighter, humanoid, rootPart, height, forwardImpulse, jumpType)
		return true
	end
	return false
end

-- ============================================================================
-- 5. ATHLETIC DASH & SLIDE ROUTINES
-- ============================================================================

function LocomotionModule.dash(fighter, humanoid, rootPart, targetPos, distance)
	local now = os.clock()
	fighter:SetAttribute("LastDashTime", now)

	local speedMult = workspace:GetAttribute("GameSpeedMultiplier") or 1.0
	local dist = distance or 35
	local clampedDist = math.clamp(dist, 20, 60)
	local dashSpeed = (CombatConfig.DashSpeed or 110) * speedMult
	local slideDuration = math.clamp(clampedDist / dashSpeed, 0.28 / speedMult, 0.55 / speedMult)

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

	-- Face direction
	rootPart.CFrame = CFrame.lookAt(rootPart.Position, rootPart.Position + dashDir)

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

function LocomotionModule.slide(fighter, humanoid, rootPart, slideDir, duration)
	local now = os.clock()
	fighter:SetAttribute("LastSlideTime", now)

	local speedMult = workspace:GetAttribute("GameSpeedMultiplier") or 1.0
	local baseSpeed = CombatConfig.SlideSpeed or 56
	local slideSpeed = baseSpeed * speedMult
	local slideDuration = (duration or CombatConfig.SlideDuration or 0.42) / speedMult

	-- Energy drain
	local energy = fighter:GetAttribute("Energy") or 100
	local cost = CombatConfig.SlideMinEnergy or 12
	fighter:SetAttribute("Energy", math.max(0, energy - cost))

	-- Direction
	local dir = slideDir
	if not dir then
		local look = rootPart.CFrame.LookVector
		local flat = Vector3.new(look.X, 0, look.Z)
		dir = flat.Magnitude > 0.001 and flat.Unit or rootPart.CFrame.LookVector
	end

	-- Animation & Sensory VFX
	AnimationModule.playConfig(humanoid, "Movement.Slide", 1.25, Enum.AnimationPriority.Action3, false)
	local elem = fighter:GetAttribute("Element")
	VfxModule.createDust(rootPart.Position - dir * 2, 4, nil, elem)

	-- Physical propulsion
	KnockbackModule.applySlide(fighter, dir, slideSpeed, slideDuration)

	task.delay(slideDuration, function()
		if humanoid and humanoid.Parent then
			AnimationModule.stopConfig(humanoid, "Movement.Slide", 0.1)
		end
	end)

	return slideDuration
end

-- ============================================================================
-- 6. CLEANUP & LIFECYCLE
-- ============================================================================

function LocomotionModule.cleanup(fighter)
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
