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

	-- Arm bone references (Mixamo rig)
	self.leftArmBone = ghostModel:FindFirstChild("mixamorig:LeftArm", true)
	self.leftForeArmBone = ghostModel:FindFirstChild("mixamorig:LeftForeArm", true)
	self.rightArmBone = ghostModel:FindFirstChild("mixamorig:RightArm", true)
	self.rightForeArmBone = ghostModel:FindFirstChild("mixamorig:RightForeArm", true)

	self.ghostRootPart = ghostModel:FindFirstChild("HumanoidRootPart")
	self.simRootPart = (aiModel and aiModel:FindFirstChild("HumanoidRootPart")) or self.ghostRootPart
	self.rootPart = self.simRootPart
	self.humanoid = ghostModel:FindFirstChildOfClass("Humanoid") or (aiModel and aiModel:FindFirstChildOfClass("Humanoid"))

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

		-- Procedural Arm IK & Elbow Pole Setup (Step 4: Active Ragdoll Flailing)
		self.leftHandBone = ghostModel:FindFirstChild("mixamorig:LeftHand", true)
		self.rightHandBone = ghostModel:FindFirstChild("mixamorig:RightHand", true)
		self.leftHandAtt = nil
		self.rightHandAtt = nil
		self.leftElbowPoleAtt = nil
		self.rightElbowPoleAtt = nil
		self.leftArmIK = nil
		self.rightArmIK = nil

		local leftHandAtt = attParent:FindFirstChild("GhostLeftHandTargetAtt")
		if not leftHandAtt or not leftHandAtt:IsA("Attachment") then
			leftHandAtt = Instance.new("Attachment")
			leftHandAtt.Name = "GhostLeftHandTargetAtt"
			leftHandAtt.Parent = attParent
		end
		leftHandAtt.Position = Vector3.new(-1.8, 0, 0)
		self.leftHandAtt = leftHandAtt

		local rightHandAtt = attParent:FindFirstChild("GhostRightHandTargetAtt")
		if not rightHandAtt or not rightHandAtt:IsA("Attachment") then
			rightHandAtt = Instance.new("Attachment")
			rightHandAtt.Name = "GhostRightHandTargetAtt"
			rightHandAtt.Parent = attParent
		end
		rightHandAtt.Position = Vector3.new(1.8, 0, 0)
		self.rightHandAtt = rightHandAtt

		-- Elbow pole vectors: placed backward and slightly outward
		local leftElbowPole = attParent:FindFirstChild("GhostLeftElbowPoleAtt")
		if not leftElbowPole or not leftElbowPole:IsA("Attachment") then
			leftElbowPole = Instance.new("Attachment")
			leftElbowPole.Name = "GhostLeftElbowPoleAtt"
			leftElbowPole.Parent = attParent
		end
		leftElbowPole.Position = Vector3.new(-2.2, 0.5, -2.0)
		self.leftElbowPoleAtt = leftElbowPole

		local rightElbowPole = attParent:FindFirstChild("GhostRightElbowPoleAtt")
		if not rightElbowPole or not rightElbowPole:IsA("Attachment") then
			rightElbowPole = Instance.new("Attachment")
			rightElbowPole.Name = "GhostRightElbowPoleAtt"
			rightElbowPole.Parent = attParent
		end
		rightElbowPole.Position = Vector3.new(2.2, 0.5, -2.0)
		self.rightElbowPoleAtt = rightElbowPole

		if self.leftArmBone and self.leftHandBone then
			local leftArmIK = self.humanoid:FindFirstChild("GhostLeftArmIK")
			if not leftArmIK or not leftArmIK:IsA("IKControl") then
				leftArmIK = Instance.new("IKControl")
			end
			leftArmIK.Name = "GhostLeftArmIK"
			leftArmIK.Type = Enum.IKControlType.Position
			leftArmIK.ChainRoot = self.leftArmBone
			leftArmIK.EndEffector = self.leftHandBone
			leftArmIK.Target = leftHandAtt
			leftArmIK.Pole = leftElbowPole
			leftArmIK.Weight = 0
			leftArmIK.Enabled = false
			leftArmIK.SmoothTime = 0.0
			leftArmIK.Parent = self.humanoid
			self.leftArmIK = leftArmIK
		end

		if self.rightArmBone and self.rightHandBone then
			local rightArmIK = self.humanoid:FindFirstChild("GhostRightArmIK")
			if not rightArmIK or not rightArmIK:IsA("IKControl") then
				rightArmIK = Instance.new("IKControl")
			end
			rightArmIK.Name = "GhostRightArmIK"
			rightArmIK.Type = Enum.IKControlType.Position
			rightArmIK.ChainRoot = self.rightArmBone
			rightArmIK.EndEffector = self.rightHandBone
			rightArmIK.Target = rightHandAtt
			rightArmIK.Pole = rightElbowPole
			rightArmIK.Weight = 0
			rightArmIK.Enabled = false
			rightArmIK.SmoothTime = 0.0
			rightArmIK.Parent = self.humanoid
			self.rightArmIK = rightArmIK
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
	self.currentArmRoll = 0
	self.currentArmFlare = 0

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
	self.wasAirborne = false
	self.maxFallSpeed = 0

	-- Centripetal Torso Banking state
	self.currentBankRoll = 0

	-- Telemetry tracking
	self.lastImpactTime = 0
	self.activeReactionType = "NONE"

	return self
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
			moveAngle = math.atan2(localVel.X, -localVel.Z)
		end
		local targetHipsYaw = moveAngle * 0.38
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

	-- 5. Advance Hips Ground Compression Spring
	local hipsK = 260
	local hipsD = 28
	local forceHips = -hipsK * self.hipsOffset - hipsD * self.hipsVelocity
	self.hipsVelocity = self.hipsVelocity + forceHips * dt
	self.hipsOffset = math.clamp(self.hipsOffset + self.hipsVelocity * dt, -0.65, 0.1)

	-- Total torso recoil angles = spring recoil + airborne orientation + centripetal bank roll + locomotion pitch
	local totalPitch = self.currentPitch + self.airPitch + (self.locomotionPitch or 0)
	local totalYaw = self.currentYaw

	-- Torso bank roll applies strictly to the spine chain (Spine, Spine1, Spine2)
	local spineRoll = self.currentRoll + self.airRoll + self.currentBankRoll
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

	if self.hipsBone and (hasHipsOffset or math.abs(hipsYaw) > 0.005) then
		local totalHipsY = self.hipsOffset + (self.hipsDipOffset or 0) + (self.turnMassDrop or 0)
		local totalHipsX = self.turnInwardLean or 0
		self.hipsBone.Transform = self.hipsBone.Transform * CFrame.new(totalHipsX, totalHipsY, 0) * CFrame.Angles(0, hipsYaw, 0)
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

		-- Nominal flat ground distance from HRP to sole
		local nominalFloorDist = 5.36
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
		local turnDampen = self.currentTurnDampen

		-- 3. Physically Accurate Anatomical Terrain Solver:
		-- Pure forward (X, Z) stride is authored by animation; IK strictly conforms vertical (Y) terrain adaptation
		local function solveFoot(footBone, isLeft)
			if not footBone then return nil, 0, false, 0 end

			-- Read authoritative animated world position of the foot bone
			local animFootPos = footBone.TransformedWorldCFrame.Position
			
			-- Cast ray straight down from above the animated foot
			local rayOrigin = Vector3.new(animFootPos.X, hrpPos.Y + 0.5, animFootPos.Z)
			local hit = Workspace:Raycast(rayOrigin, -upVec * rayDist, self.ikRayParams)

			local targetPos = animFootPos
			local targetWeight = 0
			local isLedge = false
			local elevDelta = 0

			if hit then
				local floorY = hit.Position.Y
				-- Vertical clearance of animated foot above detected surface
				local liftAboveSurface = animFootPos.Y - (floorY + ankleHeight)
				
				-- Elevation difference between actual terrain surface and nominal character floor level
				local nominalGroundY = hrpPos.Y - nominalFloorDist
				elevDelta = floorY - nominalGroundY

				-- A. Flat Ground Deadzone (Preserve Pure Author Animation):
				-- On flat ground (|elevDelta| <= 0.25 and normal >= 0.94), the author animation is already
				-- calibrated to floor level. Zero IK interference on flat ground completely eliminates leg contortions!
				local flatTolerance = speed > 15.0 and 0.35 or 0.22
				local isFlatFloor = (hit.Normal.Y >= 0.94 and math.abs(elevDelta) <= flatTolerance)

				local chainRoot = isLeft and self.leftUpLegBone or self.rightUpLegBone
				local hipPos = chainRoot and chainRoot.TransformedWorldCFrame.Position or hrpPos

				if isFlatFloor then
					-- Flat turf: 100% pure author animation, zero IK distortion
					targetPos = animFootPos
					targetWeight = 0.0
				elseif elevDelta >= -maxStepDown and elevDelta <= maxStepUp then
					-- Uneven ground, slopes, stairs, rocks, or platform steps!
					-- Anatomical Stride Phase Rule:
					-- Only engage IK when the foot is near ground contact (liftAboveSurface <= 0.35 studs).
					-- If foot is in forward swing phase (liftAboveSurface > 0.35), swing freely!
					if liftAboveSurface <= 0.35 then
						-- Conformed target: Keep the animated X and Z stride! Only conform Y (height)
						targetPos = Vector3.new(animFootPos.X, floorY + ankleHeight, animFootPos.Z)

						-- Anatomical Extension Soft Limit (Joint Constraint):
						-- Leg length is ~4.6 studs. Prevent overextension / knee locking beyond 4.2 studs
						local legVec = targetPos - hipPos
						local legDist = legVec.Magnitude
						if legDist > 4.2 then
							targetPos = hipPos + legVec.Unit * 4.2
						end

						local contactWeight = math.clamp(1.0 - (liftAboveSurface / 0.35), 0.0, 1.0)
						targetWeight = contactWeight * turnDampen
					else
						targetWeight = 0.0
					end
				else
					targetWeight = 0.0
					if elevDelta < -maxStepDown then
						isLedge = true
					end
				end
			else
				targetWeight = 0.0
			end

			-- Disable during airborne, knockback, or ragdoll
			if self.wasAirborne or (self.humanoid and self.humanoid.PlatformStand) then
				targetWeight = 0.0
			end

			return targetPos, targetWeight, isLedge, elevDelta
		end

		local lPos, lWeight, lLedge, lDelta = solveFoot(self.leftFootBone, true)
		local rPos, rWeight, rLedge, rDelta = solveFoot(self.rightFootBone, false)

		-- Always update target attachment transforms to avoid stale offsets
		if lPos then
			self.leftFootAtt.WorldPosition = lPos
		end
		if rPos then
			self.rightFootAtt.WorldPosition = rPos
		end

		-- Responsive weight interpolation (fast attack, smooth release)
		local weightSpeed = (lWeight > self.leftIK.Weight and 24.0 or 14.0) * dt
		self.leftIK.Weight = self.leftIK.Weight + (lWeight - self.leftIK.Weight) * math.clamp(weightSpeed, 0, 1)

		local rWeightSpeed = (rWeight > self.rightIK.Weight and 24.0 or 14.0) * dt
		self.rightIK.Weight = self.rightIK.Weight + (rWeight - self.rightIK.Weight) * math.clamp(rWeightSpeed, 0, 1)

		-- CRITICAL ENGINE GUARD: Disable IKControl when Weight <= 0.005.
		-- In Roblox C++, when IKControl.Enabled == true, the engine zeroes out EndEffector.Transform
		-- to identity even if Weight == 0! Setting Enabled = false completely unhooks the solver,
		-- letting author-keyed ankle dorsiflexion/plantarflexion play with 100% purity.
		self.leftIK.Enabled = (self.leftIK.Weight > 0.005)
		self.rightIK.Enabled = (self.rightIK.Weight > 0.005)

		-- Pelvis Dip Offset (sink hips when stepping down on uneven ground to prevent hyperextension)
		local hipsDipScale = CombatConfig.FootIK_HipsDipScale or 0.35
		local lowestDelta = math.min(lDelta or 0, rDelta or 0)
		if lowestDelta < -0.30 then
			local targetDip = math.clamp(lowestDelta * hipsDipScale, -0.15, 0.0)
			self.hipsDipOffset = (self.hipsDipOffset or 0) + (targetDip - (self.hipsDipOffset or 0)) * math.clamp(8.0 * dt, 0, 1)
		else
			self.hipsDipOffset = (self.hipsDipOffset or 0) * math.exp(-10.0 * dt)
		end

		self.leftLedgeGrip = lLedge
		self.rightLedgeGrip = rLedge

		-- Clean, uncorrupted toe tracking (preserves author animation without artificial spatula bending)
		self.leftToeFlex = 0
		self.rightToeFlex = 0
	else
		if self.leftIK then self.leftIK.Weight = 0; self.leftIK.Enabled = false end
		if self.rightIK then self.rightIK.Weight = 0; self.rightIK.Enabled = false end
		self.hipsDipOffset = 0
		self.leftToeFlex = 0
		self.rightToeFlex = 0
	end

	-- 8. Procedural Full-Body Active Ragdoll & Arm IK (Air Knockback & Tumble)
	local isRagdollActive = CombatConfig.AirKnockback_ProceduralRagdollEnabled
		and (serverState == "Knockback" or (serverModel and serverModel:GetAttribute("ProceduralRagdollActive") == true) or (isAirborne and speed > 32))

	if self.leftArmIK and self.rightArmIK and self.leftHandAtt and self.rightHandAtt and self.rootPart then
		if isRagdollActive and CombatConfig.Ragdoll_ArmIK_Enabled ~= false then
			local hrpCF = self.rootPart.CFrame
			local hrpPos = self.rootPart.Position
			local rootVel = self.rootPart.AssemblyLinearVelocity
			local angVel = self.rootPart.AssemblyAngularVelocity

			-- Aerodynamic drag lag: hands trail behind velocity vector
			local dragCompliance = CombatConfig.Ragdoll_DragCompliance or 0.85
			local dragLag = -rootVel * (0.040 * dragCompliance)
			if dragLag.Magnitude > 3.0 then
				dragLag = dragLag.Unit * 3.0
			end

			-- Atmospheric wind flutter / turbulence
			local flailMult = CombatConfig.Ragdoll_FlailTurbulence or 1.0
			local t = os.clock() * 16.0
			local turbLeft = Vector3.new(
				math.sin(t) * 0.35,
				math.cos(t * 1.3) * 0.45,
				math.sin(t * 0.7) * 0.30
			) * flailMult
			local turbRight = Vector3.new(
				math.cos(t * 1.1) * 0.35,
				math.sin(t * 1.4) * 0.45,
				math.cos(t * 0.8) * 0.30
			) * flailMult

			-- Centrifugal angular velocity flail
			local centrifugalL = angVel:Cross(-hrpCF.RightVector) * 0.08
			local centrifugalR = angVel:Cross(hrpCF.RightVector) * 0.08

			-- Shoulder anchor origins
			local leftShoulderPos = self.leftArmBone and self.leftArmBone.TransformedWorldCFrame.Position
				or (hrpPos - (hrpCF.RightVector * 1.4) + (hrpCF.UpVector * 1.2))
			local rightShoulderPos = self.rightArmBone and self.rightArmBone.TransformedWorldCFrame.Position
				or (hrpPos + (hrpCF.RightVector * 1.4) + (hrpCF.UpVector * 1.2))

			-- Natural resting flail direction: hands spread out and back
			local leftHandTarget = leftShoulderPos - (hrpCF.RightVector * 1.6) - (hrpCF.UpVector * 0.4) + dragLag + turbLeft + centrifugalL
			local rightHandTarget = rightShoulderPos + (hrpCF.RightVector * 1.6) - (hrpCF.UpVector * 0.4) + dragLag + turbRight + centrifugalR

			self.leftHandAtt.WorldPosition = leftHandTarget
			self.rightHandAtt.WorldPosition = rightHandTarget

			-- Elbow poles positioned backward/outward to ensure natural elbow flexion
			if self.leftElbowPoleAtt then
				self.leftElbowPoleAtt.WorldPosition = leftShoulderPos - (hrpCF.LookVector * 2.5) - (hrpCF.RightVector * 1.2)
			end
			if self.rightElbowPoleAtt then
				self.rightElbowPoleAtt.WorldPosition = rightShoulderPos - (hrpCF.LookVector * 2.5) + (hrpCF.RightVector * 1.2)
			end

			-- Fast attack weight interpolation
			local armWeightSpeed = 24.0 * dt
			self.leftArmIK.Weight = self.leftArmIK.Weight + (1.0 - self.leftArmIK.Weight) * math.clamp(armWeightSpeed, 0, 1)
			self.rightArmIK.Weight = self.rightArmIK.Weight + (1.0 - self.rightArmIK.Weight) * math.clamp(armWeightSpeed, 0, 1)
			self.leftArmIK.Enabled = true
			self.rightArmIK.Enabled = true

			-- Legs flail & trail behind momentum with knee flexion during air ragdoll
			if CombatConfig.Ragdoll_LegIK_Enabled ~= false and self.leftIK and self.rightIK and self.leftFootAtt and self.rightFootAtt then
				local legDrag = -rootVel * 0.035
				if legDrag.Magnitude > 2.5 then legDrag = legDrag.Unit * 2.5 end

				local legT = os.clock() * 12.0
				local flutterL = math.sin(legT) * 0.25
				local flutterR = math.cos(legT) * 0.25

				self.leftFootAtt.WorldPosition = hrpPos - (hrpCF.RightVector * 0.8) - (hrpCF.UpVector * 4.0) + legDrag + Vector3.new(0, flutterL, 0)
				self.rightFootAtt.WorldPosition = hrpPos + (hrpCF.RightVector * 0.8) - (hrpCF.UpVector * 4.0) + legDrag - Vector3.new(0, flutterR, 0)

				local legWeightSpeed = 20.0 * dt
				self.leftIK.Weight = self.leftIK.Weight + (0.85 - self.leftIK.Weight) * math.clamp(legWeightSpeed, 0, 1)
				self.rightIK.Weight = self.rightIK.Weight + (0.85 - self.rightIK.Weight) * math.clamp(legWeightSpeed, 0, 1)
				self.leftIK.Enabled = true
				self.rightIK.Enabled = true
			end
		else
			-- Smooth decay of Arm IK weight on landing/recovery
			local armDecaySpeed = 16.0 * dt
			self.leftArmIK.Weight = self.leftArmIK.Weight + (0.0 - self.leftArmIK.Weight) * math.clamp(armDecaySpeed, 0, 1)
			self.rightArmIK.Weight = self.rightArmIK.Weight + (0.0 - self.rightArmIK.Weight) * math.clamp(armDecaySpeed, 0, 1)
			self.leftArmIK.Enabled = (self.leftArmIK.Weight > 0.005)
			self.rightArmIK.Enabled = (self.rightArmIK.Weight > 0.005)
		end
	end

	-- Attribute telemetry for diagnostics
	if math.abs(self.currentPitch) < 0.005 and math.abs(self.velocityPitch) < 0.05
		and math.abs(self.currentRoll) < 0.005 and math.abs(self.velocityRoll) < 0.05
		and not isAirborne
		and math.abs(self.hipsOffset) < 0.008 and math.abs(self.hipsVelocity) < 0.05 then
		self.activeReactionType = "NONE"
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
		armIK = {
			enabled = CombatConfig.Ragdoll_ArmIK_Enabled ~= false,
			leftWeight = self.leftArmIK and self.leftArmIK.Weight or 0,
			rightWeight = self.rightArmIK and self.rightArmIK.Weight or 0,
			ragdollActive = CombatConfig.AirKnockback_ProceduralRagdollEnabled == true,
		}
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
	if self.leftArmIK then self.leftArmIK:Destroy() self.leftArmIK = nil end
	if self.rightArmIK then self.rightArmIK:Destroy() self.rightArmIK = nil end
	if self.leftHandAtt then self.leftHandAtt:Destroy() self.leftHandAtt = nil end
	if self.rightHandAtt then self.rightHandAtt:Destroy() self.rightHandAtt = nil end
	if self.leftElbowPoleAtt then self.leftElbowPoleAtt:Destroy() self.leftElbowPoleAtt = nil end
	if self.rightElbowPoleAtt then self.rightElbowPoleAtt:Destroy() self.rightElbowPoleAtt = nil end
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
	self.leftArmBone = nil
	self.leftForeArmBone = nil
	self.leftHandBone = nil
	self.rightArmBone = nil
	self.rightForeArmBone = nil
	self.rightHandBone = nil
	self.rootPart = nil
	self.humanoid = nil
end

return ProceduralCombatReactionController
