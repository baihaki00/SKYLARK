--// LocomotionModule.lua
-- Authoritative Locomotion, Momentum Integration, Ballistic Jumps, and Traction Controller
-- Adheres strictly to the 6 Immutable Ground Rules (README.md)
-- Single Source of Truth: ReplicatedStorage.QuinCore.CombatConfig

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

local LocomotionModule = {}

-- Active full-body locomotion actions (run slide), keyed by fighter
local activeSlides = {}
local endSlide -- forward declaration (section 5)

local function isHumanoidAirborne(humanoid)
	local s = humanoid:GetState()
	return s == Enum.HumanoidStateType.Freefall or s == Enum.HumanoidStateType.Jumping
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

	-- Speed-scaled yaw-rate ceiling: at pace, momentum widens the turn radius instead of
	-- snapping the heading like a cursor; at walking pace pivots stay nimble.
	-- Committed reversals are handled by the skid plant in steer(), which sheds speed first.
	local planarVel = rootPart.AssemblyLinearVelocity
	local planarSpeed = Vector3.new(planarVel.X, 0, planarVel.Z).Magnitude
	local slowSpeed = CombatConfig.Locomotion_TurnRateSlowSpeed or 8.0
	local fastSpeed = CombatConfig.Locomotion_TurnRateFastSpeed or 44.0
	local paceT = math.clamp((planarSpeed - slowSpeed) / math.max(fastSpeed - slowSpeed, 1), 0, 1)
	local slowRate = CombatConfig.Locomotion_TurnRateSlow or 14.0
	local maxTurnRate = slowRate + ((CombatConfig.Locomotion_TurnRateFast or 5.5) - slowRate) * paceT
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

-- Per-frame steer driver (AI Quins). States run at 10 Hz; when the heading and the drive speed
-- were only advanced on that tick, a turning Quin changed direction in up to 30 degree steps
-- and its velocity jumped ~25 studs/s every 0.1s. The state now only refreshes the goal
-- (steerTarget / steerSpeed); this driver advances the turn-rate-limited heading and the
-- acceleration every frame until the goal expires.
local steerConns = setmetatable({}, { __mode = "k" })

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
		if not data.steerTarget or os.clock() > (data.steerUntil or 0) then return end
		if activeSlides[fighter] or humanoid.PlatformStand or fighter:GetAttribute("IsPlayerControlled") == true then return end

		frameDt = math.clamp(frameDt, 0.001, 0.05)
		local target = data.steerSpeed or humanoid.WalkSpeed
		local speed = humanoid.WalkSpeed
		if speed < target then
			speed = math.min(speed + (CombatConfig.Locomotion_Acceleration or 80.0) * frameDt, target)
		elseif speed > target then
			speed = math.max(speed - (CombatConfig.Locomotion_BrakingDeceleration or 140.0) * frameDt, target)
		end
		humanoid.WalkSpeed = speed
		data.currentSpeed = speed

		local toTarget = data.steerTarget - rootPart.Position
		local flat = Vector3.new(toTarget.X, 0, toTarget.Z)
		if flat.Magnitude < 0.1 then return end
		humanoid:Move(LocomotionModule.resolveGroundIntent(fighter, rootPart, flat.Unit, frameDt), false)
	end)
	steerConns[fighter] = conn
end

-- Drop the current steer goal (state change, brake): the driver stops issuing movement
function LocomotionModule.cancelSteer(fighter)
	local data = locoData[fighter]
	if data then
		data.steerUntil = 0
	end
end

function LocomotionModule.steer(fighter, humanoid, rootPart, targetPosition, targetSpeed, dt, resolvedDirection)
	if not fighter or not humanoid or not rootPart or not targetPosition then return end
	-- A committed slide owns translation until it hands back to the gait
	if activeSlides[fighter] then return activeSlides[fighter].dir end

	dt = math.clamp(dt or 0.016, 0.001, 0.15)
	local data = getLocoData(fighter)

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

	local isStrafing = (fighter:GetAttribute("IsStrafing") == true) or (humanoid.AutoRotate == false)

	-- Skid plants need traction: never trigger one in the air or during tactical strafing/feints
	if not isStrafing and currentSpeed > skidThreshold and flatDesired.Magnitude > 2.0 and not isHumanoidAirborne(humanoid) then
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

	-- 3. Issue the resolved curved heading to the humanoid. Both player and AI
	-- use this same ground-intent result and Move translation API; arrival deceleration eliminated!
	if not isStrafing then
		humanoid.AutoRotate = true
	end
	humanoid:Move(driveDirection, false)
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

local MIN_JUMP_HEIGHT = 2.0
local MAX_JUMP_HEIGHT = 14.0

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

function LocomotionModule.jump(fighter, humanoid, rootPart, height, forwardImpulse, jumpType)
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
		return
	end

	-- Ballistic jumps launch from the ground only (Rule 6): no mid-air re-launch
	if isHumanoidAirborne(humanoid) then
		return
	end

	-- Jumping out of a slide cancels the glide and launches with its momentum
	if activeSlides[fighter] then
		endSlide(fighter, humanoid, rootPart, false)
	end

	-- Traversal parkour planning integration (vaults, jumps, dismounts)
	local plannedFlightTime = nil
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
	if fighter and fighter:IsA("Instance") then
		if not fighter:GetAttribute("TraversalVelocityX") then
			fighter:SetAttribute("TraversalVelocityX", 0)
			fighter:SetAttribute("TraversalVelocityZ", 0)
		end
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
    -- A deliberate launch hands the body to the jump clip immediately (the ground
    -- contract's grace period is only for walking off small ledges)
    GaitModule.notifyLaunch(humanoid)
    if isDismount then
        AnimationModule.playConfig(humanoid, "Movement.Fall", 1.0, Enum.AnimationPriority.Action3, true)
    else
        -- The jump clip carries its own rise and fall (hips travel ~4 studs up and back down).
        -- Fit the clip to the real flight so that arc lands with the body; at a fixed rate a
        -- short hop touched down while the clip was still at its apex and the mesh dropped late.
        local estHeight = math.clamp(height or 8.0, 3.0, 14.0)
        local estFlight = plannedFlightTime or (2 * math.sqrt((2 * estHeight) / Workspace.Gravity))
        local clipDuration = AnimationModule.getEffectiveDuration(humanoid, jumpAnim, 1.0)
        local launchSpeed = math.clamp(clipDuration / math.max(estFlight, 0.2), 0.85, 2.0)
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
	local flightTime = math.sqrt((2 * targetHeight) / gravity) * 2
	-- Dynamic AlignOrientation lifetime matching calculated ballistic arc
	Debris:AddItem(align, flightTime + 0.25)
	Debris:AddItem(att, flightTime + 0.25)
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
			if preservedH.Magnitude > 1.0 then
				humanoid:Move(preservedH.Unit, false)
			end
		end

		if align and align.Parent then align:Destroy() end
		if att and att.Parent then att:Destroy() end

		AnimationModule.stopConfig(humanoid, jumpAnim, 0.15)
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
	if s.att and s.att.Parent then s.att:Destroy() end
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
function LocomotionModule.slide(fighter, humanoid, rootPart, slideDir, _legacyDuration)
	if not fighter or not humanoid or not rootPart then return 0 end
	if activeSlides[fighter] or isHumanoidAirborne(humanoid) then return 0 end

	local vel = rootPart.AssemblyLinearVelocity
	local flatVel = Vector3.new(vel.X, 0, vel.Z)
	local startSpeed = flatVel.Magnitude
	if startSpeed < (CombatConfig.Slide_MinStartSpeed or 8.0) then return 0 end
	local dir = flatVel.Unit

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

	local slide = { dir = dir, lv = lv, att = att }
	activeSlides[fighter] = slide

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
