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
local TraversalModule = require(QuinCore:WaitForChild("Modules"):WaitForChild("TraversalModule"))

local LocomotionModule = {}

-- Per-fighter tracking table
local locoData = {}




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
	local response = CombatConfig.Locomotion_GroundTurnResponse or 16.0
	local alpha = 1.0 - math.exp(-response * dt)
	local nextAngle = currentAngle + delta * alpha
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
	dt = dt or 0.05
	dt = math.clamp(dt, 0.016, 0.25)
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
	fighter:SetAttribute("PacingVelocity", math.floor(newSpeed + 0.5))
	return newSpeed
end

-- ============================================================================
-- 2. STEERING & TRACTION (Dynamic 180° Skid & Continuous Centripetal Steering)
-- ============================================================================

function LocomotionModule.steer(fighter, humanoid, rootPart, targetPosition, targetSpeed, dt, resolvedDirection)
	if not fighter or not humanoid or not rootPart or not targetPosition then return end

	dt = dt or 0.05
	dt = math.clamp(dt, 0.016, 0.25)
	local data = getLocoData(fighter)

	-- 1. Smoothly accelerate / decelerate to target speed
	LocomotionModule.modulateSpeed(fighter, humanoid, targetSpeed, dt)

	-- 2. Check for sharp direction reversals (180° Skid)
	local currentVel = rootPart.AssemblyLinearVelocity
	local flatVel = Vector3.new(currentVel.X, 0, currentVel.Z)
	local currentSpeed = flatVel.Magnitude

	local toTarget = (targetPosition - rootPart.Position)
	local flatDesired = Vector3.new(toTarget.X, 0, toTarget.Z)
	local fallbackForward = flatUnit(rootPart.CFrame.LookVector, Vector3.new(0, 0, -1))
	local intentDirection = flatDesired.Magnitude > 0.1 and flatDesired.Unit or fallbackForward
	local driveDirection = resolvedDirection or LocomotionModule.resolveGroundIntent(fighter, rootPart, intentDirection, dt)

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

	if currentSpeed > skidThreshold and flatDesired.Magnitude > 2.0 then
		local curDir = flatVel.Unit
		local desDir = flatDesired.Unit
		local cosTheta = curDir:Dot(desDir)

		-- Sharp reversal: >= 115 degrees cut (cos theta < -0.42)
		-- Fully procedural turnaround: kinetic plant friction, procedural mass drop, braking pitch, and grey smoke burst!
		if cosTheta < -0.42 and (now - (data.lastSkidTime or 0)) >= skidCooldown then
			local turnDuration = skidLockout
			data.lastSkidTime = now
			data.skidEndTime = now + turnDuration

			-- Signal procedural controller for hips mass drop & braking-to-drive pitch
			fighter:SetAttribute("SkidTurnTime", now)
			fighter:SetAttribute("SkidTurnDuration", turnDuration)

			-- Kinetic plant friction: drop speed dynamically for athletic turf bite (cleats digging in)
			humanoid.WalkSpeed = math.max(12.0, currentSpeed * 0.40)
			data.currentSpeed = humanoid.WalkSpeed

			-- VFX: Stylized grey foot smoke burst along turf scrape vector (zero physics parts)
			VfxModule.createArcaneFootBurst(fighter, rootPart.Position, curDir)
		end
	end

	-- 3. Issue the resolved curved heading to the humanoid. Both player and AI
	-- use this same ground-intent result; only the input source differs.
	humanoid.AutoRotate = true
	if fighter:GetAttribute("IsPlayerControlled") then
		humanoid:Move(driveDirection, false)
	else
		humanoid:MoveTo(rootPart.Position + driveDirection * 15)
	end
	-- Note: Footstep audio is driven authoritatively by animation keyframe markers via AnimationModule
	return driveDirection
end

-- ============================================================================
-- 3. MELEE BRAKE & CONTINUITY (Slide into combat sweet spot; zero freeze-snaps)
-- ============================================================================

function LocomotionModule.brake(fighter, humanoid, rootPart, dt)
	if not fighter or not humanoid or not rootPart then return end

	local data = getLocoData(fighter)
	local currentVel = rootPart.AssemblyLinearVelocity
	local flatVel = Vector3.new(currentVel.X, 0, currentVel.Z)
	local speed = flatVel.Magnitude
	local now = os.clock()

	local wasSprinting = (fighter:GetAttribute("IsSprinting") == true) or (speed > 24.0)

	-- Single-shot latch for braking transition
	if not data.stopRunTriggered then
		data.stopRunTriggered = true
		data.isMoving = false

		-- If the Quin was running/sprinting, play StopRun plant animation (rbxassetid://89237107000987)
		if wasSprinting and speed > 12.0 then
			data.lastStopRunTime = now
			data.stopRunEndTime = now + 0.55

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
		else
			-- Clean walking halt: fade out walk/run tracks directly into Ready stance without StopRun slide
			data.stopRunEndTime = nil
			AnimationModule.stop(humanoid, "Movement.Run", 0.12)
			AnimationModule.stop(humanoid, "Movement.WalkConfident", 0.12)
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
	local brakeInput = math.clamp(speed / 42.0, 0, 1)
	humanoid:Move(brakeDir * brakeInput, false)

	-- When no StopRun braking overlay is active, ensure idle (handles Ready -> 5s inactivity -> Default)
	local isOverlayActive = (data.stopRunEndTime and now < data.stopRunEndTime)

	if not isOverlayActive then
		if AnimationModule.isPlaying(humanoid, "Movement.Run") then
			AnimationModule.stop(humanoid, "Movement.Run", 0.15)
		end
		if AnimationModule.isPlaying(humanoid, "Movement.WalkConfident") then
			AnimationModule.stop(humanoid, "Movement.WalkConfident", 0.15)
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

	-- Pure Ground Locomotion: suppress ballistic jump impulse if jumping is disabled
	if LocomotionModule.isJumpSuppressed(fighter, humanoid) then
		return
	end

	local data = getLocoData(fighter)
	local now = os.clock()

	-- Enforce jump debounce to eliminate rapid-fire double-hopping
	local debounce = CombatConfig.Locomotion_JumpDebounce or 0.35
	if (now - data.lastJumpTime) < debounce then
		return
	end
	data.lastJumpTime = now

	local isVault = (jumpType == "vault")
    local isDismount = (jumpType == "dismount")
    local isHop = (jumpType == "hop")
    local isLongJump = (jumpType == "longjump")
    local jumpAnim = isVault and "Parkour.VaultObstacle" or "Movement.Jump"

    -- Keep the gait underneath the traversal layer. The parkour clip supplies
    -- anticipation and silhouette while the run cycle preserves continuity.
    AnimationModule.stopConfig(humanoid, "Movement.Fall", 0.10)
    if isDismount then
        AnimationModule.playConfig(humanoid, "Movement.Fall", 1.0, Enum.AnimationPriority.Action3, true)
    else
        local launchSpeed = (isLongJump and 1.08) or (isHop and 1.12) or 1.0
        AnimationModule.playConfig(humanoid, jumpAnim, launchSpeed, Enum.AnimationPriority.Action3, true)
    end

    -- Audio feedback via QuinCore AudioModule (Authentic normal jump sound)
	AudioModule.playJump(fighter or rootPart, 0.5)

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

	local currentHVel = Vector3.new(rootPart.AssemblyLinearVelocity.X, 0, rootPart.AssemblyLinearVelocity.Z).Magnitude
	local fwdSpeed = forwardImpulse
	if fwdSpeed == nil then
		fwdSpeed = (currentHVel > 2.0) and currentHVel or 0.0
	end

	-- Unstick humanoid from ground plane
	humanoid:ChangeState(Enum.HumanoidStateType.Jumping)

	-- Direct native physics assignment: ZERO BodyVelocity!
	local plannedHorizontal = Vector3.new(
        fighter:GetAttribute("TraversalVelocityX") or 0,
        0,
        fighter:GetAttribute("TraversalVelocityZ") or 0
    )
    if plannedHorizontal.Magnitude < 0.01 then
        plannedHorizontal = flatLook * fwdSpeed
    end
    rootPart.AssemblyLinearVelocity = plannedHorizontal + Vector3.new(0, upImpulse, 0)
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
	local alignLook = plannedHorizontal.Magnitude > 0.01 and plannedHorizontal.Unit or flatLook
	align.CFrame = CFrame.lookAt(Vector3.zero, alignLook)

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
	local jumpStartTime = os.clock()
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

		-- Audio feedback on landing via QuinCore AudioModule (only if genuinely airborne)
		local airTime = os.clock() - jumpStartTime
		if airTime >= 0.18 and rootPart and rootPart.Parent then
			AudioModule.playFallOnGround(rootPart.Position)
		end

		local landingVelocity = rootPart and rootPart.AssemblyLinearVelocity or Vector3.zero
        local impactSpeed = math.abs(landingVelocity.Y)
        local traversalType = fighter:GetAttribute("TraversalType") or "None"
        local traversalHeight = fighter:GetAttribute("TraversalObstacleHeight") or 0
        if isDismount then
            if traversalHeight >= 8 or impactSpeed > 55 then
                AnimationModule.playConfig(humanoid, "Parkour.LandingSuperHero", 1.0, Enum.AnimationPriority.Action3, true)
            -- Soft landing (also aliased as LedgeDropLanding) is intentionally not
            -- played automatically: ordinary landings continue into the current gait.
            end
        elseif traversalType == "None" and impactSpeed > 50 and airTime > 0.9 then
            AnimationModule.playConfig(humanoid, "Parkour.LandingHard", 1.0, Enum.AnimationPriority.Action3, true)
        end

        local currentVel = rootPart and rootPart.AssemblyLinearVelocity or Vector3.zero
		local flatSpeed = Vector3.new(currentVel.X, 0, currentVel.Z).Magnitude
		if flatSpeed > 3.0 then
			local pacingVel = fighter:GetAttribute("PacingVelocity") or 40
			local resumeAnim = pacingVel < 20 and "Movement.WalkConfident" or "Movement.Run"
			AnimationModule.playConfig(humanoid, resumeAnim)
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

	-- Align orientation smoothly towards dash direction
	local targetLookCF = CFrame.lookAt(rootPart.Position, rootPart.Position + dashDir)
	rootPart.CFrame = rootPart.CFrame:Lerp(targetLookCF, 0.35)

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
	AudioModule.playDash(rootPart)
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

--// Spatial parkour bridge: all callers keep using LocomotionModule.
-- The planner is shared by the player controller and AI state machines.
local legacyJump = LocomotionModule.jump
local legacyDetectObstacle = LocomotionModule.detectObstacle

function LocomotionModule.planTraversal(fighter, rootPart, desiredDirection, requestedHeight, forwardSpeed)
    if not rootPart then return nil end
    local plan, candidate = TraversalModule.plan(rootPart, desiredDirection, requestedHeight, forwardSpeed)
    if plan then
        plan.candidate = candidate
    end
    return plan, candidate
end

function LocomotionModule.jump(fighter, humanoid, rootPart, height, forwardImpulse, jumpType)
    local shouldPlan = jumpType == nil or jumpType == "jump" or jumpType == "vault" or jumpType == "dismount"
    if shouldPlan and fighter and humanoid and rootPart then
        local plan = LocomotionModule.planTraversal(
            fighter,
            rootPart,
            rootPart.CFrame.LookVector,
            height,
            forwardImpulse
        )
        if plan then
            TraversalModule.markTraversal(fighter, plan)
            fighter:SetAttribute("TraversalVelocityX", plan.horizontalVelocity.X)
            fighter:SetAttribute("TraversalVelocityZ", plan.horizontalVelocity.Z)
            local result = legacyJump(
                fighter,
                humanoid,
                rootPart,
                plan.height,
                plan.horizontalVelocity.Magnitude,
                plan.animationType
            )
            task.delay((plan.flightTime or 0.6) + 0.45, function()
                if fighter and fighter.Parent then
                    TraversalModule.clearTraversal(fighter)
                    fighter:SetAttribute("TraversalVelocityX", 0)
                    fighter:SetAttribute("TraversalVelocityZ", 0)
                end
            end)
            return result
        end
    end
    if fighter then
        fighter:SetAttribute("TraversalVelocityX", 0)
        fighter:SetAttribute("TraversalVelocityZ", 0)
    end
    return legacyJump(fighter, humanoid, rootPart, height, forwardImpulse, jumpType)
end

function LocomotionModule.detectObstacle(rootPart)
    local candidate = TraversalModule.probe(rootPart, rootPart and rootPart.CFrame.LookVector or nil)
    local traversable = candidate and candidate.kind ~= "None" and candidate.kind ~= "Blocked"
    return traversable, candidate and (candidate.obstacleHeight or 0) or 0, candidate
end

function LocomotionModule.checkAndJump(fighter, humanoid, rootPart, forwardImpulse)
    local traversable, height = LocomotionModule.detectObstacle(rootPart)
    if traversable then
        LocomotionModule.jump(fighter, humanoid, rootPart, math.max(3.5, height + 2), forwardImpulse, "jump")
        return true
    end
    return false
end

function LocomotionModule.getTraversalProbe(rootPart, desiredDirection)
    return TraversalModule.probe(rootPart, desiredDirection)
end

return LocomotionModule
