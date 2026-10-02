--// ProceduralCombatReactionController.lua
-- Procedural physical hit reaction, recoil, airborne velocity orientation, and ground impact compression.
-- Layered multiplicatively onto evaluated FBX skeletal Bone.Transforms:
-- FinalPose = AnimatedPose * ReactionOffset * LookAtOffset

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local QuinCore = ReplicatedStorage:WaitForChild("QuinCore")
local CombatConfig = require(QuinCore:WaitForChild("CombatConfig"))
local AnimationModule = require(QuinCore:WaitForChild("Modules"):WaitForChild("AnimationModule"))
local SpatialModule = require(QuinCore:WaitForChild("Modules"):WaitForChild("SpatialModule"))

local ProceduralCombatReactionController = {}
ProceduralCombatReactionController.__index = ProceduralCombatReactionController

function ProceduralCombatReactionController.new(ghostModel, aiModel)
	local self = setmetatable({}, ProceduralCombatReactionController)

	self.ghostModel = ghostModel
	self.aiModel = aiModel
	self.enabled = true

	-- Bone references (skinned mesh)
	self.hipsBone = ghostModel:FindFirstChild("mixamorig:Hips", true)
	self.spineBone = ghostModel:FindFirstChild("mixamorig:Spine", true)
	self.spine1Bone = ghostModel:FindFirstChild("mixamorig:Spine1", true)
	self.spine2Bone = ghostModel:FindFirstChild("mixamorig:Spine2", true)
	self.neckBone = ghostModel:FindFirstChild("mixamorig:Neck", true)
	self.headBone = ghostModel:FindFirstChild("mixamorig:Head", true)

	-- Leg & Foot bone references (Mixamo rig)
	self.leftUpLegBone = ghostModel:FindFirstChild("mixamorig:LeftUpLeg", true)
	self.leftLegBone = ghostModel:FindFirstChild("mixamorig:LeftLeg", true)
	self.leftFootBone = ghostModel:FindFirstChild("mixamorig:LeftFoot", true)
	self.leftToeBone = ghostModel:FindFirstChild("mixamorig:LeftToeBase", true)

	self.rightUpLegBone = ghostModel:FindFirstChild("mixamorig:RightUpLeg", true)
	self.rightLegBone = ghostModel:FindFirstChild("mixamorig:RightLeg", true)
	self.rightFootBone = ghostModel:FindFirstChild("mixamorig:RightFoot", true)
	self.rightToeBone = ghostModel:FindFirstChild("mixamorig:RightToeBase", true)

	self.ghostRootPart = ghostModel:FindFirstChild("HumanoidRootPart")
	self.simRootPart = (aiModel and aiModel:FindFirstChild("HumanoidRootPart")) or self.ghostRootPart
	self.rootPart = self.simRootPart
	self.humanoid = ghostModel:FindFirstChildOfClass("Humanoid") or (aiModel and aiModel:FindFirstChildOfClass("Humanoid"))

	-- Height of the root above the floor while standing (the Humanoid floats it at HipHeight).
	-- The foot solver measures terrain against this, so it has to be the rig's real value.
	self.standHeight = (self.humanoid and self.humanoid.HipHeight or 0) + (self.simRootPart and self.simRootPart.Size.Y / 2 or 0)

	-- Procedural Foot IK & Ledge Gripping Setup (Step 3)
	self.leftFootAtt = nil
	self.rightFootAtt = nil
	self.leftPoleAtt = nil
	self.rightPoleAtt = nil
	self.leftIK = nil
	self.rightIK = nil

	local attParent = self.ghostRootPart or self.rootPart
	if attParent and self.humanoid then
		local leftAtt = attParent:FindFirstChild("GhostLeftFootTargetAtt")
		if not leftAtt or not leftAtt:IsA("Attachment") then
			leftAtt = Instance.new("Attachment")
			leftAtt.Name = "GhostLeftFootTargetAtt"
			leftAtt.Parent = attParent
		end
		leftAtt.Position = Vector3.new(-0.85, -2.6, 0)
		self.leftFootAtt = leftAtt

		local rightAtt = attParent:FindFirstChild("GhostRightFootTargetAtt")
		if not rightAtt or not rightAtt:IsA("Attachment") then
			rightAtt = Instance.new("Attachment")
			rightAtt.Name = "GhostRightFootTargetAtt"
			rightAtt.Parent = attParent
		end
		rightAtt.Position = Vector3.new(0.85, -2.6, 0)
		self.rightFootAtt = rightAtt

		-- Forward Knee Pole Attachments: local +Z is forward in Quin rig space!
		local leftPole = attParent:FindFirstChild("GhostLeftKneePoleAtt")
		if not leftPole or not leftPole:IsA("Attachment") then
			leftPole = Instance.new("Attachment")
			leftPole.Name = "GhostLeftKneePoleAtt"
			leftPole.Parent = attParent
		end
		leftPole.Position = Vector3.new(-0.85, -1.8, 2.5) -- +Z is FORWARD in Quin coordinate space!
		self.leftPoleAtt = leftPole

		local rightPole = attParent:FindFirstChild("GhostRightKneePoleAtt")
		if not rightPole or not rightPole:IsA("Attachment") then
			rightPole = Instance.new("Attachment")
			rightPole.Name = "GhostRightKneePoleAtt"
			rightPole.Parent = attParent
		end
		rightPole.Position = Vector3.new(0.85, -1.8, 2.5) -- +Z is FORWARD
		self.rightPoleAtt = rightPole

		if self.leftUpLegBone and self.leftFootBone then
			local leftIK = self.humanoid:FindFirstChild("GhostLeftFootIK")
			if not leftIK or not leftIK:IsA("IKControl") then
				leftIK = Instance.new("IKControl")
			end
			leftIK.Name = "GhostLeftFootIK"
			leftIK.Type = Enum.IKControlType.Position -- Position solves ankle reach while preserving natural foot rotation
			leftIK.ChainRoot = self.leftUpLegBone
			leftIK.EndEffector = self.leftFootBone
			leftIK.Target = leftAtt
			leftIK.Pole = leftPole
			leftIK.Weight = 0
			leftIK.Enabled = false -- CRITICAL: Must be false when Weight == 0 to prevent Roblox engine wiping EndEffector.Transform to identity
			leftIK.SmoothTime = 0.0 -- Instantaneous response; smoothed in RenderStepped loop (eliminates lag drag)
			leftIK.Parent = self.humanoid
			self.leftIK = leftIK
		end

		if self.rightUpLegBone and self.rightFootBone then
			local rightIK = self.humanoid:FindFirstChild("GhostRightFootIK")
			if not rightIK or not rightIK:IsA("IKControl") then
				rightIK = Instance.new("IKControl")
			end
			rightIK.Name = "GhostRightFootIK"
			rightIK.Type = Enum.IKControlType.Position -- Position solves ankle reach while preserving natural foot rotation
			rightIK.ChainRoot = self.rightUpLegBone
			rightIK.EndEffector = self.rightFootBone
			rightIK.Target = rightAtt
			rightIK.Pole = rightPole
			rightIK.Weight = 0
			rightIK.Enabled = false -- CRITICAL: Must be false when Weight == 0
			rightIK.SmoothTime = 0.0
			rightIK.Parent = self.humanoid
			self.rightIK = rightIK
		end

	end

	-- Raycast filtering (reusable RaycastParams)
	self.ikRayParams = RaycastParams.new()
	self.ikRayParams.FilterType = Enum.RaycastFilterType.Exclude
	local ignoreList = { ghostModel }
	if aiModel then table.insert(ignoreList, aiModel) end
	local quinGhost = Workspace:FindFirstChild("QuinGhost")
	if quinGhost then table.insert(ignoreList, quinGhost) end
	local ghostFolder = Workspace:FindFirstChild("GhostFolder")
	if ghostFolder then table.insert(ignoreList, ghostFolder) end
	local quinServer = Workspace:FindFirstChild("QuinServer")
	if quinServer then table.insert(ignoreList, quinServer) end
	self.ikRayParams.FilterDescendantsInstances = ignoreList

	-- Foot IK state tracking
	self.leftTargetWeight = 0
	self.rightTargetWeight = 0
	self.leftLedgeGrip = false
	self.rightLedgeGrip = false
	self.hipsDipOffset = 0
	self.turnMassDrop = 0
	self.lastHeadingLook = nil
	self.leftToeFlex = 0
	self.rightToeFlex = 0

	-- Damped spring state: Recoil (Pitch, Roll, Yaw)
	self.currentPitch = 0
	self.velocityPitch = 0
	self.currentRoll = 0
	self.velocityRoll = 0
	self.currentYaw = 0
	self.velocityYaw = 0

	-- Spring constants (Critically damped with fast onset & smooth settle)
	self.springK = 220    -- Spring stiffness
	self.damping = 26     -- Spring damping (prevents excessive wobble)
	self.impulseScale = 55.0

	-- Ground impact compression state
	self.hipsOffset = 0
	self.hipsVelocity = 0
	self.spineImpactComp = 0

	-- Airborne flight orientation state
	self.airPitch = 0
	self.airRoll = 0
	self.bodyLeanPitch = 0 -- whole-body lean along the travel direction during a knockback flight
	self.bodyLeanRoll = 0
	self.wallLean = 0 -- whole-body roll away from the wall during a wall-run
	self.wasAirborne = false
	self.maxFallSpeed = 0

	-- Centripetal Torso Banking state
	self.currentBankRoll = 0

	-- Telemetry tracking
	self.lastImpactTime = 0
	self.activeReactionType = "NONE"

	return self
end

-- CombatConfig.ClipCorrections: while a listed clip is the main clip on the body, its hip
-- translation is scaled and the whole body (everything under the hips) is turned about the
-- root's vertical axis. All or nothing at 50% weight: a half-applied 180 degree turn would twist.
function ProceduralCombatReactionController:applyClipCorrections()
	local corrections = CombatConfig.ClipCorrections
	if not corrections or not self.hipsBone or not self.humanoid then return end
	local animator = self.humanoid:FindFirstChildOfClass("Animator")
	if not animator then return end
	local correction, weight = nil, 0.5
	for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
		local id = track.Animation and string.match(track.Animation.AnimationId, "%d+$")
		local entry = id and corrections[id]
		if entry and track.WeightCurrent > weight then
			correction, weight = entry, track.WeightCurrent
		end
	end
	self.activeClipCorrection = correction
	if not correction then return end

	local hips = self.hipsBone
	if correction.translationScale then
		local transform = hips.Transform
		hips.Transform = CFrame.new(transform.Position * correction.translationScale) * (transform - transform.Position)
	end
	local root = self.ghostRootPart or self.rootPart
	if correction.yaw and root then
		local rootCF = root.CFrame
		local relative = rootCF:ToObjectSpace(hips.TransformedWorldCFrame)
		local turned = rootCF * CFrame.Angles(0, math.rad(correction.yaw), 0) * relative
		local parent = hips.Parent
		local parentW = parent:IsA("Bone") and parent.TransformedWorldCFrame or parent.CFrame
		hips.Transform = (parentW * hips.CFrame):Inverse() * turned
	end
end

-- Trigger a directional hit recoil impulse
function ProceduralCombatReactionController:triggerImpact(dirWorld, magnitude, impactType)
	if not self.enabled or not self.rootPart then return end
	magnitude = math.clamp(magnitude or 0.5, 0.1, 1.0)
	impactType = impactType or "NORMAL"
	self.activeReactionType = impactType

	-- Project world impact vector into local character space
	-- LookVector = -Z, RightVector = +X, UpVector = +Y
	local localDir = self.rootPart.CFrame:VectorToObjectSpace(dirWorld.Unit)

	-- Recoil direction:
	-- When localDir.Z > 0 (force pushing backward -> hit from front):
	-- Upper body recoils backward (positive pitch).
	-- When localDir.Z < 0 (force pushing forward -> hit from behind):
	-- Upper body folds forward (negative pitch).
	local targetPitchImpulse = (localDir.Z > 0 and 1 or -1) * (math.rad(14) * magnitude)

	-- When localDir.X > 0 (force pushing right -> hit from left):
	-- Upper body tilts right (negative roll).
	-- When localDir.X < 0 (force pushing left -> hit from right):
	-- Upper body tilts left (positive roll).
	local targetRollImpulse = (localDir.X > 0 and -1 or 1) * (math.rad(12) * magnitude)

	-- Slight rotational flinch yaw
	local targetYawImpulse = localDir.X * (math.rad(8) * magnitude)

	-- Apply impulse velocity to the spring
	local mult = (impactType == "HEAVY" or impactType == "KNOCKBACK") and 1.4 or 1.0
	self.velocityPitch = self.velocityPitch + (targetPitchImpulse * self.impulseScale * mult)
	self.velocityRoll = self.velocityRoll + (targetRollImpulse * self.impulseScale * mult)
	self.velocityYaw = self.velocityYaw + (targetYawImpulse * self.impulseScale * mult)

	-- Hips stagger impulse
	self.hipsVelocity = self.hipsVelocity - (0.4 * magnitude * mult)
end

-- Update procedural physical offsets each frame
function ProceduralCombatReactionController:update(dt)
	if not self.enabled or not self.rootPart then return end
	if self.aiModel and self.aiModel:GetAttribute("CurrentState") == "Death" then return end
	dt = math.clamp(dt, 0.001, 0.05)

	-- 0. Clips authored facing backwards or with oversized root motion are put right before
	-- anything here reads the pose (CombatConfig.ClipCorrections)
	self:applyClipCorrections()

	-- 1. Check server model for new replicated impact event
	local serverModel = self.aiModel
	if serverModel and serverModel.Parent then
		local impactTime = serverModel:GetAttribute("ImpactTime")
		if impactTime and impactTime ~= self.lastImpactTime then
			self.lastImpactTime = impactTime
			local dir = serverModel:GetAttribute("ImpactDir") or Vector3.new(0, 0, 1)
			local mag = serverModel:GetAttribute("ImpactMag") or 0.5
			local iType = serverModel:GetAttribute("ImpactType") or "NORMAL"
			self:triggerImpact(dir, mag, iType)
		end
	end

	-- 2. Advance Damped Spring Physics for Hit Recoil
	local forceP = -self.springK * self.currentPitch - self.damping * self.velocityPitch
	self.velocityPitch = self.velocityPitch + forceP * dt
	self.currentPitch = self.currentPitch + self.velocityPitch * dt

	local forceR = -self.springK * self.currentRoll - self.damping * self.velocityRoll
	self.velocityRoll = self.velocityRoll + forceR * dt
	self.currentRoll = self.currentRoll + self.velocityRoll * dt

	local forceY = -self.springK * self.currentYaw - self.damping * self.velocityYaw
	self.velocityYaw = self.velocityYaw + forceY * dt
	self.currentYaw = self.currentYaw + self.velocityYaw * dt

	-- 3. Airborne Velocity Orientation & Ground Impact Detection
	local rootVel = self.rootPart.AssemblyLinearVelocity
	local flatVel = Vector3.new(rootVel.X, 0, rootVel.Z)
	local velY = rootVel.Y
	local speed = flatVel.Magnitude
	local isAirborne = false

	local serverState = serverModel and serverModel:GetAttribute("CurrentState") or ""
	local isGrounded = self.rootPart and SpatialModule.isGrounded(self.rootPart)
	if serverState == "Airborne" or serverState == "Knockback" or (not isGrounded and (velY < -15 or velY > 20)) then
		isAirborne = true
	end

	if isAirborne then
		self.wasAirborne = true
		if velY < self.maxFallSpeed then
			self.maxFallSpeed = velY -- Track peak falling speed for impact
		end

		-- Subtle aerodynamic flight orientation
		local localVel = self.rootPart.CFrame:VectorToObjectSpace(rootVel)
		local targetAirPitch = 0
		if velY > 10 then
			-- Rising: slight backward chest arch
			targetAirPitch = math.rad(10)
		elseif velY < -15 then
			-- Falling: slight forward tuck
			targetAirPitch = -math.rad(8)
		end
		local targetAirRoll = math.clamp(-localVel.X * 0.003, -math.rad(12), math.rad(12))

		local blendSpeed = 12.0
		self.airPitch = self.airPitch + (targetAirPitch - self.airPitch) * (1 - math.exp(-blendSpeed * dt))
		self.airRoll = self.airRoll + (targetAirRoll - self.airRoll) * (1 - math.exp(-blendSpeed * dt))
	else
		-- Just landed: Trigger restrained ground impact compression (only from substantial falls)
		if self.wasAirborne then
			self.wasAirborne = false
			if math.abs(self.maxFallSpeed) > 15 then
				local impactSeverity = math.clamp(math.abs(self.maxFallSpeed) / 60, 0.3, 1.0)
				self.maxFallSpeed = 0

				-- Restrained vertical compression: Hips drop slightly, spine compresses forward
				self.hipsVelocity = self.hipsVelocity - (1.8 * impactSeverity)
				self.velocityPitch = self.velocityPitch + (math.rad(12) * impactSeverity * self.impulseScale)
				self.activeReactionType = "GROUND_IMPACT"
			else
				self.maxFallSpeed = 0
			end
		end

		-- Settle air offsets back to zero
		self.airPitch = self.airPitch * math.exp(-15.0 * dt)
		self.airRoll = self.airRoll * math.exp(-15.0 * dt)
	end

	-- 3b. Knockback flight: the authored air-knockback clip supplies the pose; this lays the
	-- whole body back (or sideways) along the direction it is being thrown, scaled by speed.
	local leanPitchTarget, leanRollTarget = 0, 0
	if CombatConfig.AirKnockback_ProceduralRagdollEnabled and serverModel and serverModel:GetAttribute("ProceduralRagdollActive") == true then
		local localVel = self.rootPart.CFrame:VectorToObjectSpace(flatVel)
		local maxLean = math.rad(CombatConfig.Ragdoll_BodyLeanDegrees or 50)
		local fullLeanSpeed = CombatConfig.Ragdoll_BodyLeanFullSpeed or 90
		leanPitchTarget = math.clamp(localVel.Z / fullLeanSpeed, -1, 1) * maxLean
		leanRollTarget = math.clamp(-localVel.X / fullLeanSpeed, -1, 1) * maxLean * 0.6
	elseif serverModel and serverModel:GetAttribute("LandingSlide") == true then
		-- Skidding out of a landing: the body lays back against the slide (and to the side of
		-- a slide that goes across it) in proportion to its speed, so it rights itself as the
		-- slide runs out
		local localVel = self.rootPart.CFrame:VectorToObjectSpace(flatVel)
		local maxLean = math.rad(CombatConfig.ProjectileJump_LandingLeanDegrees or 22)
		local fullLeanSpeed = CombatConfig.ProjectileJump_LandingLeanFullSpeed or 40
		leanPitchTarget = math.clamp(-localVel.Z / fullLeanSpeed, -1, 1) * maxLean
		leanRollTarget = math.clamp(localVel.X / fullLeanSpeed, -1, 1) * maxLean
	end
	local leanAlpha = 1 - math.exp(-9.0 * dt)
	self.bodyLeanPitch = self.bodyLeanPitch + (leanPitchTarget - self.bodyLeanPitch) * leanAlpha
	self.bodyLeanRoll = self.bodyLeanRoll + (leanRollTarget - self.bodyLeanRoll) * leanAlpha

	-- 3c. Wall-run: lean the whole body away from the wall
	local wallLeanTarget = 0
	if serverState == "WallRun" then
		local side = serverModel and serverModel:GetAttribute("WallRunSide")
		local tilt = math.rad(CombatConfig.WallRunTiltDegrees or 18)
		wallLeanTarget = (side == "Left" and -tilt) or (side == "Right" and tilt) or 0
	end
	self.wallLean = self.wallLean + (wallLeanTarget - self.wallLean) * (1 - math.exp(-10.0 * dt))

	-- 4. Centripetal Torso Banking & Dynamic Mass Drop for Ground Locomotion
	if not isAirborne and speed > 2.0 then
		local currentLook = self.rootPart.CFrame.LookVector
		local flatLook = Vector3.new(currentLook.X, 0, currentLook.Z)
		if flatLook.Magnitude > 0.01 then
			flatLook = flatLook.Unit
		else
			flatLook = Vector3.new(0, 0, -1)
		end

		-- Physical Angular Velocity (continuous physics solver yaw rate; zero finite-difference derivative noise)
		local physAngY = self.rootPart.AssemblyAngularVelocity.Y
		self.smoothedTurnRate = (self.smoothedTurnRate or 0) + (physAngY - (self.smoothedTurnRate or 0)) * (1 - math.exp(-14.0 * dt))

		-- Angular Velocity Deadzone:
		-- Noise floor on straight locomotion is typically +-0.2 to 0.35 rad/s.
		-- Gentle and medium carving turns begin at 0.35 rad/s, allowing hips and torso
		-- to bank immediately into curves rather than drifting wide and upright!
		local rawRate = self.smoothedTurnRate or 0
		local effectiveTurnRate = 0
		local turnDeadzone = 0.35
		if math.abs(rawRate) > turnDeadzone then
			effectiveTurnRate = math.sign(rawRate) * (math.abs(rawRate) - turnDeadzone)
		end

		local skidTime = serverModel and serverModel:GetAttribute("SkidTurnTime") or 0
		local skidDur = serverModel and serverModel:GetAttribute("SkidTurnDuration") or 0.32
		local skidElapsed = os.clock() - skidTime

		local isChattering = serverModel and serverModel:GetAttribute("DirectionalChatter") == true
		local isSkidding = (skidElapsed >= 0 and skidElapsed < skidDur)

		-- Chatter Damping: during rapid WASD mashing / chatter, stabilize torso core upright
		-- Eliminates resonant 10Hz torso flapping while preserving cinematic banking on smooth arcs
		local chatterDampen = isChattering and 0.15 or 1.0

		-- Pure Skeletal Animation (Zero Jitter, Zero Hips Offset):
		-- Torso roll, inward hips shift, and mass drop are disabled during normal locomotion
		-- so the author-keyed animation plays 100% pure without physics-solver contact jitter.
		self.currentBankRoll = 0
		self.turnMassDrop = 0
		self.turnInwardLean = 0

		-- Procedural Hip & Spine Twist (Strafing & Turning)
		local localVel = self.rootPart.CFrame:VectorToObjectSpace(flatVel)
		local moveAngle = 0
		if localVel.Magnitude > 2.0 then
			-- Sideways share of the motion, symmetric for forward and backward travel. Measuring the
			-- full heading (atan2 against -Z) wrapped at straight-back and swung the hips ~130 degrees
			-- whenever a backpedalling Quin drifted across that line.
			moveAngle = math.atan2(localVel.X, math.abs(localVel.Z))
		end
		local targetHipsYaw = moveAngle * 0.38 * (self.twistScale or 1)
		local targetSpineYaw = -targetHipsYaw * 0.85
		self.locomotionHipsYaw = (self.locomotionHipsYaw or 0) + (targetHipsYaw - (self.locomotionHipsYaw or 0)) * (1 - math.exp(-12.0 * dt))
		self.locomotionSpineYaw = (self.locomotionSpineYaw or 0) + (targetSpineYaw - (self.locomotionSpineYaw or 0)) * (1 - math.exp(-12.0 * dt))

		local skidPitch = 0
		if isSkidding then
			local p = math.clamp(skidElapsed / skidDur, 0, 1)
			if p < 0.45 then
				local brakeFactor = math.sin((p / 0.45) * (math.pi * 0.5))
				skidPitch = math.rad(10.5) * brakeFactor
			else
				local driveFactor = (p - 0.45) / 0.55
				skidPitch = math.rad(10.5) * (1.0 - driveFactor) + math.rad(-7.5) * driveFactor
			end
		end

		-- Forward Acceleration & Braking Plant Pitch:
		-- Only intentional skids and direction reversals apply braking/drive pitch.
		-- Normal ground running leaves author-keyed spine pitch clean and jitter-free.
		local targetPitch = 0
		if isSkidding then
			targetPitch = skidPitch
		end
		self.locomotionPitch = (self.locomotionPitch or 0) + (targetPitch - (self.locomotionPitch or 0)) * (1 - math.exp(-12.0 * dt))

	else
		self.currentBankRoll = self.currentBankRoll * math.exp(-10.0 * dt)
		self.turnMassDrop = (self.turnMassDrop or 0) * math.exp(-8.0 * dt)
		self.turnInwardLean = (self.turnInwardLean or 0) * math.exp(-10.0 * dt)
		self.locomotionPitch = (self.locomotionPitch or 0) * math.exp(-10.0 * dt)
		self.locomotionHipsYaw = (self.locomotionHipsYaw or 0) * math.exp(-10.0 * dt)
		self.locomotionSpineYaw = (self.locomotionSpineYaw or 0) * math.exp(-10.0 * dt)
		if self.rootPart then
			local currentLook = self.rootPart.CFrame.LookVector
			local flatLook = Vector3.new(currentLook.X, 0, currentLook.Z)
			if flatLook.Magnitude > 0.01 then
				self.lastHeadingLook = flatLook.Unit
			end
		end
	end

	-- 4b. Force lean: the upper body leans into the acceleration the body is under - forward
	-- as it drives off, back as it brakes, into a turn or a sidestep, away from a hit that
	-- shoves it. The acceleration is taken from a smoothed velocity so solver jitter does not
	-- reach the spine.
	-- Per-Quin style (experiment, off by default): each Quin leans and twists a little
	-- differently and with its own weight, seeded from its name so it is always the same Quin.
	local styleSwitch = workspace:GetAttribute("ProceduralStyle")
	local styleOn = styleSwitch == true or (styleSwitch == nil and CombatConfig.ProceduralStyle_Enabled == true)
	if not self.style then
		local seed = 0
		local name = serverModel and serverModel.Name or ""
		for i = 1, #name do
			seed = (seed * 31 + string.byte(name, i)) % 100003
		end
		local rng = Random.new(seed)
		self.style = { lean = rng:NextNumber(0.6, 1.5), twist = rng:NextNumber(0.7, 1.4), response = rng:NextNumber(5, 11) }
	end
	local leanScale = styleOn and self.style.lean or 1
	local leanResponse = styleOn and self.style.response or 8
	self.twistScale = styleOn and self.style.twist or 1

	local previousVelocity = self.leanVelocity or flatVel
	self.leanVelocity = previousVelocity + (flatVel - previousVelocity) * (1 - math.exp(-10.0 * dt))
	local rawAcceleration = dt > 0 and (self.leanVelocity - previousVelocity) / dt or Vector3.zero
	local smoothedAcceleration = self.leanAcceleration or Vector3.zero
	self.leanAcceleration = smoothedAcceleration + (rawAcceleration - smoothedAcceleration) * (1 - math.exp(-6.0 * dt))

	local forcePitchTarget, forceRollTarget = 0, 0
	if CombatConfig.Locomotion_ForceLeanEnabled ~= false and not isAirborne then
		local localAcceleration = self.rootPart.CFrame:VectorToObjectSpace(self.leanAcceleration)
		local fullAcceleration = CombatConfig.Locomotion_ForceLeanFullAcceleration or 60
		forcePitchTarget = math.clamp(localAcceleration.Z / fullAcceleration, -1, 1) * math.rad(CombatConfig.Locomotion_ForceLeanPitchDegrees or 14) * leanScale
		forceRollTarget = math.clamp(-localAcceleration.X / fullAcceleration, -1, 1) * math.rad(CombatConfig.Locomotion_ForceLeanRollDegrees or 12) * leanScale
	end
	local leanBlend = 1 - math.exp(-leanResponse * dt)
	self.forceLeanPitch = (self.forceLeanPitch or 0) + (forcePitchTarget - (self.forceLeanPitch or 0)) * leanBlend
	self.forceLeanRoll = (self.forceLeanRoll or 0) + (forceRollTarget - (self.forceLeanRoll or 0)) * leanBlend

	-- 5. Advance Hips Ground Compression Spring
	local hipsK = 260
	local hipsD = 28
	local forceHips = -hipsK * self.hipsOffset - hipsD * self.hipsVelocity
	self.hipsVelocity = self.hipsVelocity + forceHips * dt
	self.hipsOffset = math.clamp(self.hipsOffset + self.hipsVelocity * dt, -0.65, 0.1)

	-- Total torso recoil angles = spring recoil + airborne orientation + centripetal bank roll + locomotion pitch
	local totalPitch = self.currentPitch + self.airPitch + (self.locomotionPitch or 0) + self.forceLeanPitch
	local totalYaw = self.currentYaw

	-- Torso bank roll applies strictly to the spine chain (Spine, Spine1, Spine2)
	local spineRoll = self.currentRoll + self.airRoll + self.currentBankRoll + self.forceLeanRoll
	local headRoll  = self.currentRoll + self.airRoll

	-- Hierarchical distribution across spine chain:
	-- Spine (lower): 30% Pitch, 35% Roll, 25% Yaw + procedural counter-twist
	-- Spine1 (mid):   35% Pitch, 35% Roll, 35% Yaw + procedural counter-twist
	-- Spine2 (chest): 35% Pitch, 30% Roll, 40% Yaw + procedural counter-twist
	local spineTwist = self.locomotionSpineYaw or 0
	local s0Pitch, s0Roll, s0Yaw = totalPitch * 0.30, spineRoll * 0.35, (totalYaw * 0.25) + (spineTwist * 0.40)
	local s1Pitch, s1Roll, s1Yaw = totalPitch * 0.35, spineRoll * 0.35, (totalYaw * 0.35) + (spineTwist * 0.40)
	local s2Pitch, s2Roll, s2Yaw = totalPitch * 0.35, spineRoll * 0.30, (totalYaw * 0.40) + (spineTwist * 0.20)

	-- VOR (Vestibulo-Ocular Reflex): Horizon stabilization
	-- Neck and head counter-rotate against the cumulative torso bank roll (-spineRoll)
	-- perfectly cancelling out lateral spine tilt so the head remains rock-solid level with the world horizon!
	local vorCounterRoll = -spineRoll
	local nPitch, nRoll  = totalPitch * 0.20, (headRoll * 0.20) + (vorCounterRoll * 0.50)
	local hPitch, hRoll  = totalPitch * 0.15, headRoll * 0.15

	-- Apply to bones multiplicatively on top of evaluated animation track
	local hasHipsOffset = math.abs(self.hipsOffset) > 0.001 or math.abs(self.hipsDipOffset or 0) > 0.001
		or math.abs(self.turnMassDrop or 0) > 0.001 or math.abs(self.turnInwardLean or 0) > 0.001
	local hipsYaw = self.locomotionHipsYaw or 0

	local hipsPitch = self.bodyLeanPitch
	local hipsRoll = self.bodyLeanRoll + self.wallLean
	local hasHipsRotation = math.abs(hipsYaw) > 0.005 or math.abs(hipsPitch) > 0.005 or math.abs(hipsRoll) > 0.005

	if self.hipsBone and (hasHipsOffset or hasHipsRotation) then
		local totalHipsY = self.hipsOffset + (self.hipsDipOffset or 0) + (self.turnMassDrop or 0)
		local totalHipsX = self.turnInwardLean or 0
		self.hipsBone.Transform = self.hipsBone.Transform * CFrame.new(totalHipsX, totalHipsY, 0) * CFrame.Angles(hipsPitch, hipsYaw, hipsRoll)
	end

	-- 4c. Whole-body tilt (Tales Runner / Watch Dogs style): the body leans from the feet
	-- into the acceleration it is under - into a curve, forward driving off, back braking -
	-- by the physical lean angle atan(a / g), scaled and capped, plus a forward run lean
	-- that grows with speed. The whole body turns about a point on the ground under the root,
	-- so the feet stay where they are (the foot solver below plants them).
	local tiltSwitch = workspace:GetAttribute("BodyTilt") -- live A/B switch
	local tiltOn = tiltSwitch == true or (tiltSwitch == nil and CombatConfig.BodyTilt_Enabled ~= false)
	local tiltStates = { Knockback = true, Recovery = true, ProjectileJump = true, MidAirClash = true, WallRun = true, Death = true, BeamStruggle = true }
	local tiltTarget = Vector3.zero
	if tiltOn and not isAirborne and not tiltStates[serverState] and not (self.humanoid and self.humanoid.PlatformStand) then
		local gravity = Workspace.Gravity
		local scale = CombatConfig.BodyTilt_Scale or 0.6
		local accel = self.leanAcceleration or Vector3.zero
		local flatAccel = Vector3.new(accel.X, 0, accel.Z)
		local maxTilt = math.rad(CombatConfig.BodyTilt_MaxDegrees or 16)
		if flatAccel.Magnitude > 1 then
			local angle = math.min(math.atan(flatAccel.Magnitude / gravity) * scale, maxTilt)
			tiltTarget += flatAccel.Unit * angle
		end
		-- Forward run lean with speed (none at a walk)
		local runLean = math.rad(CombatConfig.BodyTilt_RunLeanDegrees or 7)
		local leanSpeed = CombatConfig.BodyTilt_RunLeanFullSpeed or 40
		if speed > 8 then
			tiltTarget += flatVel.Unit * runLean * math.clamp((speed - 8) / (leanSpeed - 8), 0, 1)
		end
		if tiltTarget.Magnitude > maxTilt then
			tiltTarget = tiltTarget.Unit * maxTilt
		end
		-- fade out near a standstill (idle sway is the clip's)
		tiltTarget *= math.clamp(speed / 4, 0, 1)
	end
	self.bodyTilt = self.bodyTilt or Vector3.zero
	self.bodyTilt = self.bodyTilt:Lerp(tiltTarget, 1 - math.exp(-(CombatConfig.BodyTilt_Response or 7) * dt))
	if self.hipsBone and self.bodyTilt.Magnitude > math.rad(0.3) then
		local axis = Vector3.yAxis:Cross(self.bodyTilt.Unit) -- the top of the body moves toward the tilt
		if axis.Magnitude > 1e-4 then
			local pivot = self.rootPart.Position - Vector3.new(0, self.standHeight, 0)
			local rotation = CFrame.new(pivot) * CFrame.fromAxisAngle(axis.Unit, self.bodyTilt.Magnitude) * CFrame.new(-pivot)
			local hipsW = self.hipsBone.TransformedWorldCFrame
			local parent = self.hipsBone.Parent
			local parentW = parent:IsA("Bone") and parent.TransformedWorldCFrame or parent.CFrame
			self.hipsBone.Transform = (parentW * self.hipsBone.CFrame):Inverse() * (rotation * hipsW)
		end
	end

	if self.spineBone then
		self.spineBone.Transform = self.spineBone.Transform * CFrame.Angles(s0Pitch, s0Yaw, s0Roll)
	end

	if self.spine1Bone then
		self.spine1Bone.Transform = self.spine1Bone.Transform * CFrame.Angles(s1Pitch, s1Yaw, s1Roll)
	end

	if self.spine2Bone then
		self.spine2Bone.Transform = self.spine2Bone.Transform * CFrame.Angles(s2Pitch, s2Yaw, s2Roll)
	end

	if self.neckBone then
		self.neckBone.Transform = self.neckBone.Transform * CFrame.Angles(nPitch, 0, nRoll)
	end

	if self.headBone then
		if self.aiModel then
			self.headBone.Transform = self.headBone.Transform * CFrame.Angles(hPitch, 0, hRoll)
		else
			-- Player gait asset has a distracting baked yaw/roll wobble. Preserve pitch
			-- bob while keeping the head stable in the horizontal plane.
			local headPitch = select(1, self.headBone.Transform:ToOrientation())
			local headPosition = self.headBone.Transform.Position
			self.headBone.Transform = CFrame.new(headPosition) * CFrame.Angles(headPitch, 0, 0)
		end
	end

	-- 7. Procedural Foot IK & Ledge Gripping (Step 3: Anatomically Sound Terrain Adaptation)
	if CombatConfig.FootIK_Enabled and self.leftIK and self.rightIK and self.leftFootAtt and self.rightFootAtt and self.rootPart then
		local hrpCF = self.rootPart.CFrame
		local hrpPos = self.rootPart.Position
		local rightVec = hrpCF.RightVector
		local lookVec = hrpCF.LookVector
		local upVec = hrpCF.UpVector

		local rayDist = CombatConfig.FootIK_RayDistance or 6.8
		local maxStepDown = CombatConfig.FootIK_MaxStepDown or 2.4
		local maxStepUp = CombatConfig.FootIK_MaxStepUp or 1.6
		local heightOffset = CombatConfig.FootIK_HeightOffset or 0.0
		local ankleConform = CombatConfig.FootIK_AnkleAlignment ~= false
		local ledgeGripEnabled = CombatConfig.FootIK_LedgeGrip ~= false

		-- Flat-ground reference: where the floor is when the Quin simply stands on it. This was a
		-- fixed 5.36 while the rig actually floats 5.11 above the floor, so level ground measured
		-- as a 0.25 stud step and the foot IK kept switching on and off on it.
		local nominalFloorDist = self.standHeight
		local ankleHeight = 0.48 + heightOffset

		-- 1. Sagittal Knee Hinge Constraint: Anchored strictly forward along the thigh bone axis
		-- Keeps knees strictly bending forward in the anatomical hinge plane (+Z in Quin rig space)
		if self.leftUpLegBone and self.leftPoleAtt then
			local leftThighCF = self.leftUpLegBone.TransformedWorldCFrame
			self.leftPoleAtt.WorldPosition = leftThighCF.Position + (leftThighCF.LookVector * 3.0)
		end
		if self.rightUpLegBone and self.rightPoleAtt then
			local rightThighCF = self.rightUpLegBone.TransformedWorldCFrame
			self.rightPoleAtt.WorldPosition = rightThighCF.Position + (rightThighCF.LookVector * 3.0)
		end

		-- 2. Turn / Spin Attenuation: Attenuate IK during high angular velocity or rapid heading changes
		-- Allows athletic plant cuts, 90 cuts, and 180 direction reversals to play cleanly without IK ankle drag
		local angVelY = math.abs(self.smoothedTurnRate or self.rootPart.AssemblyAngularVelocity.Y)
		local rawTurnDampen = math.clamp(1.0 - (angVelY - 4.0) / 8.0, 0.0, 1.0)
		self.currentTurnDampen = (self.currentTurnDampen or 1.0) + (rawTurnDampen - (self.currentTurnDampen or 1.0)) * (1 - math.exp(-8.0 * dt))
		-- Plant-and-pivot reversals (LocomotionModule, server ReversalPhase "pivot") turn at ~7 rad/s
		-- on purpose, on a planted foot: the turn attenuation above let go of that foot (~60% pinned)
		-- and it dragged round with the body. Held fully, the pinned foot falls behind the turning
		-- clip and the plant/step logic below steps it round: a two-step pivot.
		local pivotSwitch = workspace:GetAttribute("PivotPin") -- live A/B switch
		local pivotPinOn = pivotSwitch == true or (pivotSwitch == nil and CombatConfig.FootIK_PivotPin ~= false)
		local pivoting = pivotPinOn and serverModel ~= nil and serverModel:GetAttribute("ReversalPhase") == "pivot"
		if pivoting then
			self.currentTurnDampen = 1.0
		end
		local turnDampen = self.currentTurnDampen

		-- 3. Foot placement.
		-- Pure forward (X, Z) stride is authored by animation; this conforms the foot height to
		-- the ground and (FootIK_Plant) holds a foot that is down where it touched the ground.
		--
		-- Planting: the clips move the feet at their own pace, the body moves at its own, so a
		-- foot on the ground used to skate (median 12.6 studs/s while moving, measured). A foot
		-- that comes down is pinned to that spot until the clip lifts it. If the clip drags it
		-- more than FootIK_PlantMaxDrift away, or the leg would have to stretch past its reach,
		-- it lets go (and waits for the next lift before planting again) and fades back to the
		-- clip from the pinned spot instead of snapping. Not while the body is being pushed or
		-- skids out of a landing: then the feet are meant to slide.
		--
		-- Stepping: some clips never lift a foot while the body moves (the fight stance played
		-- through Circling and Fight footwork: the body glided on still feet). When a pinned foot
		-- falls behind and the clip does not lift it, it takes a short arc step to a spot just
		-- ahead of where the body is going and plants there. One foot steps at a time.
		--
		-- The legs are solved here (two bones, in the plane the clip bends the knee in) and
		-- written into the bone Transforms, not through IKControl: IKControl writes its result
		-- into Bone.Transform, so once it was on the clip's own foot position was gone and a
		-- pinned foot looked still forever - it could not tell when the clip lifted it.
		local plantSwitch = workspace:GetAttribute("FootPlant") -- live A/B switch
		local plantOn = plantSwitch == true or (plantSwitch == nil and CombatConfig.FootIK_Plant ~= false)
		local stepOn = plantOn and CombatConfig.FootIK_Step ~= false
		local stepLead = CombatConfig.FootIK_StepLead or 0.1
		local now = os.clock()
		local plantContact = CombatConfig.FootIK_PlantContact or 0.15
		local plantLift = CombatConfig.FootIK_PlantLift or 0.35
		-- A running clip's planted foot still creeps a little (4-14 studs/s at a sprint): the
		-- allowance grows with speed so a stance is held to the end instead of being let go
		-- (or stepped) halfway through it
		local plantMaxDrift = (CombatConfig.FootIK_PlantMaxDrift or 1.4) + speed * (CombatConfig.FootIK_PlantDriftPerSpeed or 0.04)
		local plantLetGo = plantMaxDrift * 2 -- (a pivot steps sooner but lets go no sooner)
		if pivoting then
			-- A pivot swings the clip's feet round the pinned one fast (180 degrees in ~0.45 s):
			-- held to the usual allowance the foot overreached before a step could start, was let
			-- go and spent the turn unpinned. Pivot steps start sooner and are quicker.
			plantMaxDrift = CombatConfig.FootIK_PivotMaxDrift or 0.7
		end
		-- Procedural steps are for clips that do not step (a stance played while moving); at a
		-- run the clip lifts the foot itself
		local stepMaxSpeed = CombatConfig.FootIK_StepMaxSpeed or 12

		local impulse = self.rootPart:FindFirstChild("ImpulseLV")
		-- Only a knockback (ImpulseModule priority 3: a 10-18 stud skid) slides the feet. The
		-- body's own pushes (lunge, spacing step back) and a hit flinch (2-5 studs) are stepped:
		-- the feet used to glide backwards through every spacing correction and every flinch
		local pushed = impulse ~= nil and impulse:IsA("LinearVelocity") and impulse.MaxAxesForce.X > 0
			and (impulse:GetAttribute("Priority") or 3) >= 3
		local footsFree = self.wasAirborne or serverState == "Recovery" or serverState == "Knockback"
			or (self.humanoid and self.humanoid.PlatformStand)
			or (serverModel and serverModel:GetAttribute("LandingSlide") == true)
			or (serverModel and serverModel:GetAttribute("LocomotionAction") ~= nil) -- a run slide, a dash: the clip has the feet

		self.plant = self.plant or {}
		self.plantArmed = self.plantArmed or { Left = true, Right = true }
		self.plantFade = self.plantFade or {}
		self.legWeight = self.legWeight or { Left = 0, Right = 0 }
		self.step = self.step or {}
		self.footNormal = self.footNormal or {}

		-- Where a procedural step has the foot at this moment (eased along, arced up)
		local function stepPosition(step)
			local s = math.clamp((now - step.t0) / step.duration, 0, 1)
			local eased = s * s * (3 - 2 * s)
			return step.from:Lerp(step.to, eased) + Vector3.new(0, step.arc * math.sin(math.pi * s), 0)
		end

		-- Clip pose of one leg: hip, knee and ankle positions and the reach of the leg
		local function clipLeg(isLeft)
			local up = isLeft and self.leftUpLegBone or self.rightUpLegBone
			local leg = isLeft and self.leftLegBone or self.rightLegBone
			local foot = isLeft and self.leftFootBone or self.rightFootBone
			if not (up and leg and foot) then return nil end
			local hipW, kneeW, footW = up.TransformedWorldCFrame, leg.TransformedWorldCFrame, foot.TransformedWorldCFrame
			local reach = (kneeW.Position - hipW.Position).Magnitude + (footW.Position - kneeW.Position).Magnitude
			return { up = up, leg = leg, foot = foot, hipW = hipW, kneeW = kneeW, footW = footW, reach = reach }
		end

		local function solveFoot(isLeft)
			local side = isLeft and "Left" or "Right"
			local leg = clipLeg(isLeft)
			if not leg then return nil, 0, false, 0, false, nil end

			-- Where the clip puts the ankle this frame
			local animFootPos = leg.footW.Position
			local hipPos = leg.hipW.Position
			local maxReach = leg.reach * 0.98 -- just short of a locked knee

			-- Cast ray straight down from above the animated foot
			local rayOrigin = Vector3.new(animFootPos.X, hrpPos.Y + 0.5, animFootPos.Z)
			local hit = Workspace:Raycast(rayOrigin, -upVec * rayDist, self.ikRayParams)
			self.footNormal[side] = hit and hit.Normal or Vector3.yAxis

			local targetPos = animFootPos
			local targetWeight = 0
			local isLedge = false
			local elevDelta = 0
			local planted = false

			if hit and not footsFree then
				local floorY = hit.Position.Y
				-- Vertical clearance of animated foot above detected surface
				local liftAboveSurface = animFootPos.Y - (floorY + ankleHeight)

				-- Elevation difference between actual terrain surface and nominal character floor level
				local nominalGroundY = hrpPos.Y - nominalFloorDist
				elevDelta = floorY - nominalGroundY
				local reachable = elevDelta >= -maxStepDown and elevDelta <= maxStepUp

				-- Plant
				local lock = self.plant[side]
				local step = self.step[side]
				if plantOn and not pushed and reachable and hit.Normal.Y >= 0.7 then
					if liftAboveSurface > plantLift then
						-- The clip lifts the foot: it walks by itself
						self.plantFade[side] = (step and stepPosition(step)) or lock or self.plantFade[side]
						lock, step = nil, nil
						self.plantArmed[side] = true
					elseif step then
						if now - step.t0 >= step.duration then
							lock, step = step.to, nil -- landed: planted there
						end
					elseif lock then
						local drift = Vector3.new(animFootPos.X - lock.X, 0, animFootPos.Z - lock.Z).Magnitude
						-- Out of reach is judged against what the clip itself asks of the leg. A walk
						-- lands on a nearly straight leg and the pin sits at floor height, a little
						-- lower than the clip has the ankle: against the bare leg length the spot was
						-- 0.1-0.2 studs "out of reach" from the first frame of every stance, so one
						-- foot was stepped all through a plain walk and the other let go.
						local clipExtension = (animFootPos - hipPos).Magnitude
						local overreach = (lock - hipPos).Magnitude > math.max(maxReach, clipExtension + (CombatConfig.FootIK_OverreachSlack or 0.3))
						if drift > plantMaxDrift or overreach then
							local other = isLeft and "Right" or "Left"
							local landing = nil
							if stepOn and speed < stepMaxSpeed and not self.step[other] then
								-- Just ahead of where the clip has the foot, as far as the leg reaches
								local hipHeight = hipPos.Y - (floorY + ankleHeight)
								local reachFlat = math.sqrt(math.max(maxReach * maxReach - hipHeight * hipHeight, 0)) * 0.85
								local duration = math.clamp((CombatConfig.FootIK_StepDuration or 0.28) - speed * 0.006, 0.14, 0.3)
								if pivoting then
									duration = CombatConfig.FootIK_PivotStepDuration or 0.16
								end
								local aim = Vector3.new(animFootPos.X, 0, animFootPos.Z) + flatVel * (duration * 0.5 + stepLead)
								local fromHip = aim - Vector3.new(hipPos.X, 0, hipPos.Z)
								if fromHip.Magnitude > reachFlat then
									aim = Vector3.new(hipPos.X, 0, hipPos.Z) + fromHip.Unit * reachFlat
								end
								local landHit = Workspace:Raycast(Vector3.new(aim.X, hrpPos.Y + 0.5, aim.Z), -upVec * rayDist, self.ikRayParams)
								if landHit and landHit.Normal.Y >= 0.7 and math.abs(landHit.Position.Y - floorY) <= maxStepUp then
									local to = Vector3.new(aim.X, landHit.Position.Y + ankleHeight, aim.Z)
									local length = (to - lock).Magnitude
									landing = { from = lock, to = to, t0 = now, duration = duration, arc = math.clamp(0.25 + 0.12 * length, 0.25, 0.7) }
								end
							end
							if landing then
								step, lock = landing, nil
							elseif overreach or drift > plantLetGo then
								-- No step possible (the other foot is up, nowhere to land): let go
								self.plantFade[side] = lock
								lock = nil
								self.plantArmed[side] = false
							end
							-- otherwise it holds a moment longer, until the other foot is down
						end
					elseif self.plantArmed[side] and liftAboveSurface <= plantContact then
						lock = Vector3.new(animFootPos.X, floorY + ankleHeight, animFootPos.Z)
						self.plantArmed[side] = false
						self.plantFade[side] = nil
					end
				else
					self.plantFade[side] = (step and stepPosition(step)) or lock or self.plantFade[side]
					lock, step = nil, nil
				end
				self.plant[side] = lock
				self.step[side] = step

				if step then
					targetPos = stepPosition(step)
					targetWeight = turnDampen
					planted = true
				elseif lock then
					targetPos = lock
					targetWeight = turnDampen
					planted = true
				else
					-- A foot that is not planted on flat ground follows the clip untouched
					local flatTolerance = speed > 15.0 and 0.35 or 0.22
					local isFlatFloor = (hit.Normal.Y >= 0.94 and math.abs(elevDelta) <= flatTolerance)

					if isFlatFloor then
						targetWeight = 0.0
					elseif reachable then
						-- Uneven ground, slopes, stairs, rocks, or platform steps: conform the
						-- height near ground contact; a foot in its swing swings freely.
						if liftAboveSurface <= 0.35 then
							targetPos = Vector3.new(animFootPos.X, floorY + ankleHeight, animFootPos.Z)
							local contactWeight = math.clamp(1.0 - (liftAboveSurface / 0.35), 0.0, 1.0)
							targetWeight = contactWeight * turnDampen
						end
					elseif elevDelta < -maxStepDown then
						isLedge = true
					end
				end
			else
				-- In the air, thrown, getting up or on PlatformStand: the clip has the feet at
				-- once (a foot left pinned to the floor would stretch the leg as the body leaves)
				self.plant[side] = nil
				self.step[side] = nil
				self.plantFade[side] = nil
				self.plantArmed[side] = true
				self.legWeight[side] = 0
			end

			-- A released plant fades from where it was pinned (no snap to the clip)
			if not planted and targetWeight <= 0 and self.plantFade[side] then
				if self.legWeight[side] > 0.02 then
					targetPos = self.plantFade[side]
				else
					self.plantFade[side] = nil
				end
			end

			-- (debug: why the left foot is or is not planted; client-only attribute)
			if self.aiModel and workspace:GetAttribute("FootDebug") then
				local reason = footsFree and "free" or (not hit and "nohit") or (pushed and "pushed")
					or (self.step[side] and "step") or (self.plant[side] and "lock")
					or (self.plantArmed[side] and "armed") or "waitLift"
				self.aiModel:SetAttribute(isLeft and "FootDbg" or "FootDbgR", string.format("%s lift=%.2f w=%.2f", reason, animFootPos.Y - ((hit and hit.Position.Y or 0) + ankleHeight), self.legWeight[side]))
			end

			return targetPos, targetWeight, isLedge, elevDelta, planted, leg
		end

		-- Shortest rotation taking direction a onto direction b
		local function rotationBetween(a, b)
			local ua, ub = a.Unit, b.Unit
			local axis = ua:Cross(ub)
			local dot = math.clamp(ua:Dot(ub), -1, 1)
			if axis.Magnitude < 1e-5 then
				return CFrame.identity
			end
			return CFrame.fromAxisAngle(axis.Unit, math.acos(dot))
		end

		-- Two-bone solve: put the ankle on goal, knee in the plane the clip bends it in, the
		-- foot keeping the clip's orientation. Writes the three Transforms.
		local function applyLeg(leg, goal, normal, weight)
			local H, K, A = leg.hipW.Position, leg.kneeW.Position, leg.footW.Position
			local L1, L2 = (K - H).Magnitude, (A - K).Magnitude
			local toGoal = goal - H
			if toGoal.Magnitude < 1e-3 or L1 < 1e-3 or L2 < 1e-3 then return end
			-- Soft reach: near a straight leg a hair of distance swings the knee tens of degrees
			-- (it popped 172 -> 136 -> 172 between frames). Past 92% of the leg the distance is
			-- eased toward full length instead of clamped, so the knee straightens smoothly and
			-- the foot falls a little short of a goal it could only reach with a locked knee.
			local full = L1 + L2
			local soft = full * 0.92
			local hard = full * 0.995
			local dist = toGoal.Magnitude
			if dist > soft then
				dist = soft + (hard - soft) * (1 - math.exp(-(dist - soft) / (hard - soft)))
			end
			local d = math.clamp(dist, math.abs(L1 - L2) + 0.01, hard)
			local dir = toGoal.Unit
			-- The knee bends the way the clip bends it, biased forward: a nearly straight clip
			-- leg has no clear bend direction, and switching to "forward" outright when it got
			-- small flipped the thigh between frames
			local forward = lookVec - dir * lookVec:Dot(dir)
			local bend = (K - H) - dir * (K - H):Dot(dir)
			if forward.Magnitude > 1e-3 then
				bend = bend + forward.Unit * 0.35
			end
			if bend.Magnitude < 1e-3 then
				bend = lookVec
			end
			-- Smoothed over time per leg: the clip's bend and the body's facing both turn fast
			-- in fight footwork, and the knee plane flipped with them between frames
			local key = leg.up
			self.bendDir = self.bendDir or {}
			self.bendTime = self.bendTime or {}
			-- (a smoothing left from an earlier solve is stale: start from the clip again)
			local previous = (now - (self.bendTime[key] or 0) < 0.1) and self.bendDir[key] or nil
			self.bendTime[key] = now
			bend = bend.Unit
			if previous then
				bend = previous:Lerp(bend, math.clamp(18 * dt, 0, 1))
				if bend.Magnitude < 1e-3 then bend = previous end
				bend = bend.Unit
			end
			self.bendDir[key] = bend
			-- Perpendicular to the hip-goal line again (the smoothing leaves a small tilt)
			bend = bend - dir * bend:Dot(dir)
			if bend.Magnitude < 1e-3 then bend = forward.Magnitude > 1e-3 and forward or lookVec end
			bend = bend.Unit
			local along = (L1 * L1 + d * d - L2 * L2) / (2 * d)
			local out = math.sqrt(math.max(L1 * L1 - along * along, 0))
			local newKnee = H + dir * along + bend * out
			local newAnkle = H + dir * d

			-- Thigh
			local hipRot = leg.hipW - H
			local newHipW = CFrame.new(H) * rotationBetween(K - H, newKnee - H) * hipRot
			local parentW = leg.up.Parent:IsA("Bone") and leg.up.Parent.TransformedWorldCFrame or leg.up.Parent.CFrame
			leg.up.Transform = (parentW * leg.up.CFrame):Inverse() * newHipW
			-- Shin (as the thigh carried it, then turned onto the ankle)
			local kneeAfter = newHipW * (leg.hipW:Inverse() * leg.kneeW)
			local ankleAfter = kneeAfter * (leg.kneeW:Inverse() * leg.footW)
			local kneeRot = kneeAfter - kneeAfter.Position
			local newKneeW = CFrame.new(kneeAfter.Position) * rotationBetween(ankleAfter.Position - kneeAfter.Position, newAnkle - kneeAfter.Position) * kneeRot
			leg.leg.Transform = (newHipW * leg.leg.CFrame):Inverse() * newKneeW
			-- Foot: the clip's orientation at the new ankle, tilted onto the surface it stands on
			-- (FootIK_AnkleAlignment): the clips are authored on flat ground, so the turn from
			-- flat to this surface is laid over the clip's own heel-strike and toe-off angles.
			-- Flat ground leaves the clip untouched.
			local footRot = leg.footW - leg.footW.Position
			if ankleConform and normal and normal.Y > 0.5 and normal.Y < 0.999 then
				local tilt = math.acos(math.clamp(normal.Y, -1, 1))
				local axis = Vector3.yAxis:Cross(normal)
				if axis.Magnitude > 1e-4 then
					footRot = CFrame.fromAxisAngle(axis.Unit, tilt * math.clamp(weight or 1, 0, 1)) * footRot
				end
			end
			local newFootW = CFrame.new(newAnkle) * footRot
			leg.foot.Transform = (newKneeW * leg.foot.CFrame):Inverse() * newFootW
		end

		local lPos, lWeight, lLedge, lDelta, lPlanted, lLeg = solveFoot(true)
		local rPos, rWeight, rLedge, rDelta, rPlanted, rLeg = solveFoot(false)

		-- Weight: a plant takes hold at once (a running stance lasts ~0.12 s), everything else
		-- attacks fast and releases smoothly
		local function blendWeight(side, target, isPlanted)
			local current = self.legWeight[side]
			local rate = isPlanted and 40.0 or (target > current and 24.0 or (self.plantFade[side] and 20.0 or 14.0))
			current = current + (target - current) * math.clamp(rate * dt, 0, 1)
			if current < 0.005 and target <= 0 then current = 0 end
			self.legWeight[side] = current
			return current
		end
		local lW = blendWeight("Left", lWeight, lPlanted)
		local rW = blendWeight("Right", rWeight, rPlanted)
		if lLeg and lPos and lW > 0 then applyLeg(lLeg, lLeg.footW.Position:Lerp(lPos, lW), self.footNormal.Left, lW) end
		if rLeg and rPos and rW > 0 then applyLeg(rLeg, rLeg.footW.Position:Lerp(rPos, rW), self.footNormal.Right, rW) end

		-- Toe flex (FootIK_ToeFlexion): a toe whose tip would go through the ground bends up at
		-- the ball of the foot, as a real toe does when the heel rises (push-off, a foot planted
		-- on a step edge, a tilted foot). The clips never bend the toe, so the tip used to sink
		-- into the floor. Runs on the final foot pose, solved or not.
		if CombatConfig.FootIK_ToeFlexion ~= false then
			local sole = CombatConfig.FootIK_ToeSoleThickness or 0.14
			local maxFlex = math.rad(CombatConfig.FootIK_ToeMaxFlexDegrees or 50)
			self.toeFlexSmoothed = self.toeFlexSmoothed or { Left = 0, Right = 0 }
			for _, side in ipairs({ "Left", "Right" }) do
				local toe = side == "Left" and self.leftToeBone or self.rightToeBone
				local target = 0
				local axis = nil
				if toe and not footsFree then
					local toeW = toe.TransformedWorldCFrame
					local length = toe.CFrame.Position.Magnitude * 0.7 -- toe segment, about 70% of foot-to-ball
					local tipDir = toeW.UpVector -- bones point along their +Y
					local tip = toeW.Position + tipDir * length
					local floorHit = Workspace:Raycast(tip + Vector3.new(0, 1.5, 0), Vector3.new(0, -3, 0), self.ikRayParams)
					if floorHit then
						local depth = (floorHit.Position.Y + sole) - tip.Y
						local across = tipDir:Cross(Vector3.yAxis)
						if depth > 0 and across.Magnitude > 1e-3 then
							target = math.min(math.asin(math.clamp(depth / length, 0, 1)), maxFlex)
							axis = across.Unit
						end
					end
				end
				local current = self.toeFlexSmoothed[side]
				current = current + (target - current) * math.clamp((target > current and 35 or 12) * dt, 0, 1)
				self.toeFlexSmoothed[side] = current
				if toe and current > 0.005 then
					local toeW = toe.TransformedWorldCFrame
					axis = axis or toeW.UpVector:Cross(Vector3.yAxis)
					if axis.Magnitude > 1e-3 then
						local newToeW = CFrame.new(toeW.Position) * CFrame.fromAxisAngle(axis.Unit, current) * (toeW - toeW.Position)
						local parentW = toe.Parent:IsA("Bone") and toe.Parent.TransformedWorldCFrame or toe.Parent.CFrame
						toe.Transform = (parentW * toe.CFrame):Inverse() * newToeW
					end
				end
				if side == "Left" then self.leftToeFlex = current else self.rightToeFlex = current end
			end
		end
		self.leftPlanted = lPlanted
		self.rightPlanted = rPlanted

		-- The IKControls stay off (see above); their Weight carries the solver's weight for the
		-- telemetry and the Animation Lab readout
		self.leftIK.Enabled = false
		self.rightIK.Enabled = false
		self.leftIK.Weight = lW
		self.rightIK.Weight = rW
		if lPos then self.leftFootAtt.WorldPosition = lPos end
		if rPos then self.rightFootAtt.WorldPosition = rPos end

		-- Pelvis Dip Offset: sink the hips when one foot stands lower (a step, the edge of a
		-- platform) so that foot reaches its ground instead of hanging in the air
		local hipsDipScale = CombatConfig.FootIK_HipsDipScale or 0.35
		local maxHipsDip = CombatConfig.FootIK_MaxHipsDip or 0.6
		local lowestDelta = math.min(lDelta or 0, rDelta or 0)
		if lowestDelta < -0.30 and not footsFree then
			local targetDip = math.clamp(lowestDelta * hipsDipScale, -maxHipsDip, 0.0)
			self.hipsDipOffset = (self.hipsDipOffset or 0) + (targetDip - (self.hipsDipOffset or 0)) * math.clamp(8.0 * dt, 0, 1)
		else
			self.hipsDipOffset = (self.hipsDipOffset or 0) * math.exp(-10.0 * dt)
		end

		self.leftLedgeGrip = lLedge
		self.rightLedgeGrip = rLedge

	else
		if self.leftIK then self.leftIK.Weight = 0; self.leftIK.Enabled = false end
		if self.rightIK then self.rightIK.Weight = 0; self.rightIK.Enabled = false end
		self.hipsDipOffset = 0
		self.leftToeFlex = 0
		self.rightToeFlex = 0
	end

	-- 8. Secondary motion: the arms follow the clip with a little weight of their own
	local smSwitch = workspace:GetAttribute("SecondaryMotion") -- live A/B switch
	local smOn = smSwitch == true or (smSwitch == nil and CombatConfig.SecondaryMotion_Enabled ~= false)
	-- (not in a mid-air clash: that state places the body by CFrame every tick, and the arms
	-- whipped after every jump)
	if smOn and serverState ~= "MidAirClash" then
		self:updateSecondaryMotion(dt)
	else
		self.smState = nil
	end

	-- Attribute telemetry for diagnostics
	if math.abs(self.currentPitch) < 0.005 and math.abs(self.velocityPitch) < 0.05
		and math.abs(self.currentRoll) < 0.005 and math.abs(self.velocityRoll) < 0.05
		and not isAirborne
		and math.abs(self.hipsOffset) < 0.008 and math.abs(self.hipsVelocity) < 0.05 then
		self.activeReactionType = "NONE"
	end
end

-- Secondary motion (overlap and follow-through) for the arms.
-- Each upper arm and forearm tip follows where the clip puts it through a damped spring that
-- is also fed the clip's own velocity: steady motion (running, a steady turn) is followed
-- with no lag, and only a change - the body starting, stopping, turning, being hit - leaves
-- the arm trailing for a moment and settling with a slight overshoot. The offset is capped
-- per bone, and it fades out while the clip itself moves the arm fast relative to the body
-- (a punch), so strikes stay as authored.
-- The spine, neck and head follow the same way with smaller caps (SecondaryMotion_Spine):
-- the upper body trails a turn or a stop by a few degrees and settles. Parents first.
local ARM_CHAIN = {
	{ "Spine1", "Spine2", "spine" },
	{ "Spine2", "Neck", "spine" },
	{ "Neck", "Head", "neck" },
	{ "Head", nil, "neck", 0.8 }, -- no head-top bone: a point 0.8 studs up the head
	{ "LeftArm", "LeftForeArm", "upper" },
	{ "LeftForeArm", "LeftHand", "fore" },
	{ "RightArm", "RightForeArm", "upper" },
	{ "RightForeArm", "RightHand", "fore" },
}

local function chainTip(entry)
	if entry.child then
		return entry.child.TransformedWorldCFrame.Position
	end
	local w = entry.bone.TransformedWorldCFrame
	return w.Position + w.UpVector * entry.length
end

function ProceduralCombatReactionController:updateSecondaryMotion(dt)
	if not self.smBones then
		self.smBones = {}
		local spineOn = CombatConfig.SecondaryMotion_Spine ~= false
		for _, link in ipairs(ARM_CHAIN) do
			local isTorso = link[3] == "spine" or link[3] == "neck"
			local bone = self.ghostModel and self.ghostModel:FindFirstChild("mixamorig:" .. link[1], true)
			local child = link[2] and self.ghostModel and self.ghostModel:FindFirstChild("mixamorig:" .. link[2], true)
			if bone and (child or link[4]) and (spineOn or not isTorso) then
				table.insert(self.smBones, { bone = bone, child = child, kind = link[3], length = link[4] })
			end
		end
	end
	if #self.smBones == 0 or not self.rootPart then return end

	local frequency = CombatConfig.SecondaryMotion_Frequency or 6
	local zeta = CombatConfig.SecondaryMotion_Damping or 0.75
	local maxUpper = math.rad(CombatConfig.SecondaryMotion_MaxUpperArmDegrees or 14)
	local maxFore = math.rad(CombatConfig.SecondaryMotion_MaxForearmDegrees or 20)
	local maxSpine = math.rad(CombatConfig.SecondaryMotion_MaxSpineDegrees or 5)
	local maxNeck = math.rad(CombatConfig.SecondaryMotion_MaxNeckDegrees or 7)
	local caps = { upper = maxUpper, fore = maxFore, spine = maxSpine, neck = maxNeck }
	local fastClip = CombatConfig.SecondaryMotion_FastClipSpeed or 12 -- studs/s of a tip relative to the body
	local omega = 2 * math.pi * frequency
	-- The springs run in the body's own frame. In world space they tracked the bone tips through
	-- the body's replicated position, which arrives in small steps (and far Quins' animation is
	-- stepped too): on the short spine bones a few hundredths of a stud of that became degrees of
	-- turn every frame, a high-frequency shiver from the waist up (4-7 reversals/s at the upper
	-- spine, 11/s for the worst Quins). In the body's frame those steps cancel; the sway comes
	-- from the body's smoothed acceleration (inertia, as the body tilt uses) and the clip's own
	-- motion - the same physics, without the noise.
	local rootCF = self.rootPart.CFrame
	local inertia = CombatConfig.SecondaryMotion_Inertia or 1
	-- (its own, smoother copy of the body acceleration: the lean's copy follows the replicated
	-- velocity, which arrives in ~20 Hz steps, and its ripple kept the spine twitching)
	local rawBody = self.leanAcceleration or Vector3.zero
	self.smAcceleration = (self.smAcceleration or rawBody):Lerp(rawBody, 1 - math.exp(-(CombatConfig.SecondaryMotion_AccelerationResponse or 6) * dt))
	local bodyAcceleration = rootCF:VectorToObjectSpace(self.smAcceleration) * inertia
	-- Saturated: a running body's sway does not grow with a projectile jump's launch or a
	-- knockback (thousands of studs/s^2 of horizontal acceleration pushed the springs past their
	-- reset distance every other frame, and the torso flipped between bent and straight)
	local maxAcceleration = CombatConfig.SecondaryMotion_MaxAcceleration or 80
	if bodyAcceleration.Magnitude > maxAcceleration then
		bodyAcceleration = bodyAcceleration.Unit * maxAcceleration
	end
	self.smState = self.smState or {}

	-- The clip's tips (in the body's frame), before any bone here is turned
	local tips = {}
	for i, entry in ipairs(self.smBones) do
		tips[i] = rootCF:PointToObjectSpace(chainTip(entry))
	end

	-- Springs (sub-stepped: a 6 Hz spring at a 20 fps frame is past stable for one step)
	local steps = math.max(1, math.ceil(dt / (1 / 120)))
	local h = dt / steps
	local weights = {}
	for i, tip in ipairs(tips) do
		local s = self.smState[i]
		if not s or (tip - s.x).Magnitude > 4 then
			s = { x = tip, v = Vector3.zero, prevTip = tip }
			self.smState[i] = s
		end
		-- Low-passed: far Quins have their animation stepped at a lower rate, and the raw
		-- per-frame velocity alternated between 0 and double
		local rawVelocity = (tip - s.prevTip) / dt
		s.prevTip = tip
		s.cv = s.cv and s.cv:Lerp(rawVelocity, math.clamp(25 * dt, 0, 1)) or rawVelocity
		local clipVelocity = s.cv
		-- The torso is heavy: the spine and neck sway slower and settle without bouncing
		-- (at the arms' 6 Hz under-damped spring they overshot and rebounded 3-4 times a
		-- second); the arms keep their livelier spring
		local kind = self.smBones[i].kind
		local w, z = omega, zeta
		if kind == "spine" or kind == "neck" then
			w = 2 * math.pi * (CombatConfig.SecondaryMotion_TorsoFrequency or 3.5)
			z = CombatConfig.SecondaryMotion_TorsoDamping or 1.0
		end
		for _ = 1, steps do
			local acceleration = (tip - s.x) * (w * w) + (clipVelocity - s.v) * (2 * z * w) - bodyAcceleration
			s.v += acceleration * h
			s.x += s.v * h
		end
		-- A soft leash instead of a reset: past it the spring is held at the leash, so a hard
		-- shove bends the bone to its cap and holds it rather than flicking it every frame
		local leash = CombatConfig.SecondaryMotion_Leash or 1.5
		local offset = s.x - tip
		if offset.Magnitude > leash then
			s.x = tip + offset.Unit * leash
			s.v = clipVelocity
		end
		-- Fade out while the clip moves the arm fast; rate-limited (a per-frame weight from a
		-- per-frame speed flickered and turned the arm up to 20 degrees between frames)
		local relativeSpeed = clipVelocity.Magnitude -- (already relative to the body)
		local targetWeight = math.clamp(1 - (relativeSpeed - fastClip) / fastClip, 0, 1)
		local current = s.weight or targetWeight
		local rate = targetWeight < current and 14 or 4
		current = current + (targetWeight - current) * math.clamp(rate * dt, 0, 1)
		s.weight = current
		weights[i] = current
	end

	-- Which torso parts follow: workspace SecondaryMotionTorso = "none" | "spine" | "all"
	-- (A/B), else the config
	local torso = workspace:GetAttribute("SecondaryMotionTorso")
		or (CombatConfig.SecondaryMotion_Spine == false and "none")
		or (CombatConfig.SecondaryMotion_Neck == false and "spine")
		or "all"

	-- Turn each bone from where its tip is toward where the spring has it (parents first)
	for i, entry in ipairs(self.smBones) do
		local weight = weights[i]
		if (entry.kind == "spine" and torso == "none") or (entry.kind == "neck" and torso ~= "all") then
			weight = 0
		end
		if weight > 0.01 then
			local boneW = entry.bone.TransformedWorldCFrame
			local current = chainTip(entry) - boneW.Position
			local wanted = rootCF:PointToWorldSpace(self.smState[i].x) - boneW.Position
			if current.Magnitude > 1e-3 and wanted.Magnitude > 1e-3 then
				local cu, wu = current.Unit, wanted.Unit
				local axis = cu:Cross(wu)
				if axis.Magnitude > 1e-5 then
					local angle = math.acos(math.clamp(cu:Dot(wu), -1, 1))
					angle = math.min(angle, caps[entry.kind] or maxFore) * weight
					local newW = CFrame.new(boneW.Position) * CFrame.fromAxisAngle(axis.Unit, angle) * (boneW - boneW.Position)
					local parent = entry.bone.Parent
					local parentW = parent:IsA("Bone") and parent.TransformedWorldCFrame or parent.CFrame
					entry.bone.Transform = (parentW * entry.bone.CFrame):Inverse() * newW
				end
			end
		end
	end
end

-- Telemetry query for tests and audits
function ProceduralCombatReactionController:getTelemetry()
	return {
		activeReaction = self.activeReactionType,
		pitchDeg = math.deg(self.currentPitch),
		rollDeg = math.deg(self.currentRoll),
		yawDeg = math.deg(self.currentYaw),
		bankRollDeg = math.deg(self.currentBankRoll),
		hipsOffsetStuds = self.hipsOffset,
		hipsDipStuds = self.hipsDipOffset or 0,
		isAirborne = self.wasAirborne,
		footIK = {
			enabled = CombatConfig.FootIK_Enabled == true,
			leftWeight = self.leftIK and self.leftIK.Weight or 0,
			rightWeight = self.rightIK and self.rightIK.Weight or 0,
			leftLedge = self.leftLedgeGrip or false,
			rightLedge = self.rightLedgeGrip or false,
			hipsDip = self.hipsDipOffset or 0,
			leftToeFlexDeg = math.deg(self.leftToeFlex or 0),
			rightToeFlexDeg = math.deg(self.rightToeFlex or 0),
		},
		bodyLean = {
			enabled = CombatConfig.AirKnockback_ProceduralRagdollEnabled == true,
			pitchDeg = math.deg(self.bodyLeanPitch),
			rollDeg = math.deg(self.bodyLeanRoll),
			wallLeanDeg = math.deg(self.wallLean),
		},
	}
end

function ProceduralCombatReactionController:getLocomotionBankingTelemetry()
	return {
		bankRollDeg = math.round(math.deg(self.currentBankRoll) * 10) / 10,
		isAirborne = self.wasAirborne,
	}
end

function ProceduralCombatReactionController:getFootIKTelemetry()
	return {
		enabled = CombatConfig.FootIK_Enabled == true,
		leftWeight = self.leftIK and self.leftIK.Weight or 0,
		rightWeight = self.rightIK and self.rightIK.Weight or 0,
		leftLedge = self.leftLedgeGrip or false,
		rightLedge = self.rightLedgeGrip or false,
		hipsDip = self.hipsDipOffset or 0,
	}
end

function ProceduralCombatReactionController:destroy()
	self.enabled = false
	if self.leftIK then self.leftIK:Destroy() self.leftIK = nil end
	if self.rightIK then self.rightIK:Destroy() self.rightIK = nil end
	if self.leftFootAtt then self.leftFootAtt:Destroy() self.leftFootAtt = nil end
	if self.rightFootAtt then self.rightFootAtt:Destroy() self.rightFootAtt = nil end
	if self.leftPoleAtt then self.leftPoleAtt:Destroy() self.leftPoleAtt = nil end
	if self.rightPoleAtt then self.rightPoleAtt:Destroy() self.rightPoleAtt = nil end
	self.ghostModel = nil
	self.aiModel = nil
	self.hipsBone = nil
	self.spineBone = nil
	self.spine1Bone = nil
	self.spine2Bone = nil
	self.neckBone = nil
	self.headBone = nil
	self.leftUpLegBone = nil
	self.leftLegBone = nil
	self.leftFootBone = nil
	self.leftToeBone = nil
	self.rightUpLegBone = nil
	self.rightLegBone = nil
	self.rightFootBone = nil
	self.rightToeBone = nil
	self.rootPart = nil
	self.humanoid = nil
end

return ProceduralCombatReactionController
