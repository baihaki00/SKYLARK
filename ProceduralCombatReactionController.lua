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
		local leftAtt = Instance.new("Attachment")
		leftAtt.Name = "GhostLeftFootTargetAtt"
		leftAtt.Position = Vector3.new(-0.85, -2.6, 0)
		leftAtt.Parent = attParent
		self.leftFootAtt = leftAtt

		local rightAtt = Instance.new("Attachment")
		rightAtt.Name = "GhostRightFootTargetAtt"
		rightAtt.Position = Vector3.new(0.85, -2.6, 0)
		rightAtt.Parent = attParent
		self.rightFootAtt = rightAtt

		-- Forward Knee Pole Attachments: local -Z is forward in Roblox coordinate space!
		local leftPole = Instance.new("Attachment")
		leftPole.Name = "GhostLeftKneePoleAtt"
		leftPole.Position = Vector3.new(-0.85, -1.8, -2.5) -- -Z is FORWARD in Roblox!
		leftPole.Parent = attParent
		self.leftPoleAtt = leftPole

		local rightPole = Instance.new("Attachment")
		rightPole.Name = "GhostRightKneePoleAtt"
		rightPole.Position = Vector3.new(0.85, -1.8, -2.5) -- -Z is FORWARD
		rightPole.Parent = attParent
		self.rightPoleAtt = rightPole

		if self.leftUpLegBone and self.leftFootBone then
			local leftIK = Instance.new("IKControl")
			leftIK.Name = "GhostLeftFootIK"
			leftIK.Type = Enum.IKControlType.Transform -- Transform preserves author-keyed forward foot angle
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
			local rightIK = Instance.new("IKControl")
			rightIK.Name = "GhostRightFootIK"
			rightIK.Type = Enum.IKControlType.Transform -- Transform preserves author-keyed forward foot angle
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
	local velY = rootVel.Y
	local speed = rootVel.Magnitude
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
		-- Physics solver contact noise on straight locomotion is typically +-0.5 to 1.2 rad/s.
		-- Below 1.5 rad/s, there is NO intentional turn! Force effectiveTurnRate to 0.
		-- Completely eliminates hips mass drop vibration and torso roll wobble during straight-line running!
		local rawRate = self.smoothedTurnRate or 0
		local effectiveTurnRate = 0
		if math.abs(rawRate) > 1.5 then
			effectiveTurnRate = math.sign(rawRate) * (math.abs(rawRate) - 1.5)
		end

		local skidTime = serverModel and serverModel:GetAttribute("SkidTurnTime") or 0
		local skidDur = serverModel and serverModel:GetAttribute("SkidTurnDuration") or 0.32
		local skidElapsed = os.clock() - skidTime

		local isChattering = serverModel and serverModel:GetAttribute("DirectionalChatter") == true
		local isSkidding = (skidElapsed >= 0 and skidElapsed < skidDur)

		-- Chatter Damping: during rapid WASD mashing / chatter, stabilize torso core upright
		-- Eliminates resonant 10Hz torso flapping while preserving cinematic banking on smooth arcs
		local chatterDampen = isChattering and 0.15 or 1.0

		local maxRollDeg = (CombatConfig.TorsoBankingMaxRoll or 15.0) * chatterDampen
		local responsiveness = isChattering and 6.0 or (CombatConfig.TorsoBankingResponsiveness or 14.0)
		local strideBase = CombatConfig.RunStrideBase or 50.0

		-- In Roblox right-handed coordinates for spine chain:
		-- Negative roll tilts to character's right (banking into right turn, crossY < 0)
		-- Positive roll tilts to character's left (banking into left turn, crossY > 0)
		local speedRatio = math.clamp(speed / strideBase, 0.25, 1.25)
		local targetRoll = -math.clamp(effectiveTurnRate * speedRatio * math.rad(maxRollDeg * 0.18), -math.rad(maxRollDeg), math.rad(maxRollDeg))
		self.currentBankRoll = self.currentBankRoll + (targetRoll - self.currentBankRoll) * (1 - math.exp(-responsiveness * dt))

		-- Centripetal Knee Flexion / Turn Mass Drop
		-- During chatter: maintain a stable athletic crouch (-0.12 studs) rather than
		-- bouncing up and down with alternating angular velocity zero-crossings (10Hz jackhammer!)
		local maxTurnDrop = (CombatConfig.TurnMassDropMax or 0.45)
		local turnDrop = 0
		if not isChattering then
			turnDrop = -math.clamp(math.abs(effectiveTurnRate) * speedRatio * 0.065, 0, maxTurnDrop)
		end

		-- Skid Reversal Mass Drop: when 180 skid is active, sink hips firmly into the turf
		local skidDrop = 0
		if skidElapsed >= 0 and skidElapsed < skidDur then
			local p = skidElapsed / skidDur
			local curve = math.sin(p * math.pi)
			local skidMaxAmount = CombatConfig.SkidMassDropAmount or 0.55
			skidDrop = -skidMaxAmount * curve
		end

		-- Chatter mass drop: stable athletic crouch during rapid footwork
		local chatterDrop = isChattering and -0.12 or 0

		local targetTotalMassDrop = turnDrop + skidDrop + chatterDrop
		self.turnMassDrop = (self.turnMassDrop or 0) + (targetTotalMassDrop - (self.turnMassDrop or 0)) * (1 - math.exp(-10.0 * dt))

		-- Dynamic Arm Counter-Balancing & Athletic Flare
		-- During chatter: ZERO roll flapping! Arms flare outward into athletic balance guard.
		local turnArmRollTarget = 0
		if not isChattering then
			turnArmRollTarget = -math.clamp(effectiveTurnRate * speedRatio * math.rad(10.0 * 0.15), -math.rad(8.0), math.rad(8.0))
		end

		local flareTarget = 0
		if isSkidding then
			local p = math.clamp(skidElapsed / skidDur, 0, 1)
			flareTarget = math.rad(18.0) * math.sin(p * math.pi)
		elseif isChattering then
			flareTarget = math.rad(14.0) -- Athletic balance posture during rapid WASD cuts
		else
			flareTarget = math.clamp(math.abs(effectiveTurnRate) * 0.02, 0, math.rad(8.0))
		end

		local armResp = isChattering and 8.0 or 12.0
		self.currentArmRoll = (self.currentArmRoll or 0) + (turnArmRollTarget - (self.currentArmRoll or 0)) * (1 - math.exp(-armResp * dt))
		self.currentArmFlare = (self.currentArmFlare or 0) + (flareTarget - (self.currentArmFlare or 0)) * (1 - math.exp(-armResp * dt))
	else
		self.currentBankRoll = self.currentBankRoll * math.exp(-10.0 * dt)
		self.turnMassDrop = (self.turnMassDrop or 0) * math.exp(-8.0 * dt)
		self.currentArmRoll = (self.currentArmRoll or 0) * math.exp(-10.0 * dt)
		self.currentArmFlare = (self.currentArmFlare or 0) * math.exp(-10.0 * dt)
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

	-- Total torso recoil angles = spring recoil + airborne orientation + centripetal bank roll
	local totalPitch = self.currentPitch + self.airPitch
	local totalYaw = self.currentYaw

	-- Torso bank roll applies strictly to the spine chain (Spine, Spine1, Spine2)
	-- Neck and head maintain horizon stabilization (VOR) and do NOT whip with torso banking
	local spineRoll = self.currentRoll + self.airRoll + self.currentBankRoll
	local headRoll  = self.currentRoll + self.airRoll -- Pure combat recoil/airborne flinch only; 0 bank roll whip!

	-- Hierarchical distribution across spine chain:
	-- Spine (lower): 30% Pitch, 35% Roll, 25% Yaw
	-- Spine1 (mid):   35% Pitch, 35% Roll, 35% Yaw
	-- Spine2 (chest): 35% Pitch, 30% Roll, 40% Yaw
	-- Neck:           20% secondary pitch/recoil roll
	-- Head:           15% secondary flinch
	local s0Pitch, s0Roll, s0Yaw = totalPitch * 0.30, spineRoll * 0.35, totalYaw * 0.25
	local s1Pitch, s1Roll, s1Yaw = totalPitch * 0.35, spineRoll * 0.35, totalYaw * 0.35
	local s2Pitch, s2Roll, s2Yaw = totalPitch * 0.35, spineRoll * 0.30, totalYaw * 0.40
	local nPitch, nRoll          = totalPitch * 0.20, headRoll * 0.20
	local hPitch, hRoll          = totalPitch * 0.15, headRoll * 0.15

	-- Apply to bones multiplicatively on top of evaluated animation track
	if self.hipsBone and (math.abs(self.hipsOffset) > 0.001 or math.abs(self.hipsDipOffset or 0) > 0.001 or math.abs(self.turnMassDrop or 0) > 0.001) then
		local totalHipsY = self.hipsOffset + (self.hipsDipOffset or 0) + (self.turnMassDrop or 0)
		self.hipsBone.Transform = self.hipsBone.Transform * CFrame.new(0, totalHipsY, 0)
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
		self.headBone.Transform = self.headBone.Transform * CFrame.Angles(hPitch, 0, hRoll)
	end

	-- Dynamic Arm Counter-Balancing & Athletic Flare (stabilization during rapid WASD cuts & 180 skids)
	local armFlare = self.currentArmFlare or 0
	local armRoll = self.currentArmRoll or 0
	if math.abs(armRoll) > 0.001 or math.abs(armFlare) > 0.001 then
		if self.leftArmBone then
			-- Left arm: flare outward (-Y), pitch forward (+X), bank roll (+Z)
			self.leftArmBone.Transform = self.leftArmBone.Transform * CFrame.Angles(armFlare * 0.40, -armFlare, armRoll)
		end
		if self.rightArmBone then
			-- Right arm: flare outward (+Y), pitch forward (+X), bank roll (+Z)
			self.rightArmBone.Transform = self.rightArmBone.Transform * CFrame.Angles(armFlare * 0.40, armFlare, armRoll)
		end
		if self.leftForeArmBone and armFlare > 0.001 then
			-- Forearm elbow flexion: bends elbow forward for athletic ready posture
			self.leftForeArmBone.Transform = self.leftForeArmBone.Transform * CFrame.Angles(armFlare * 0.70, 0, 0)
		end
		if self.rightForeArmBone and armFlare > 0.001 then
			self.rightForeArmBone.Transform = self.rightForeArmBone.Transform * CFrame.Angles(armFlare * 0.70, 0, 0)
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

		-- 1. Sagittal Knee Pole Alignment: Anchored forward from animated hip root
		-- Keeps knees strictly bending forward in the character's facing direction without circular distortion
		if self.leftUpLegBone and self.leftPoleAtt then
			local leftHipPos = self.leftUpLegBone.TransformedWorldCFrame.Position
			self.leftPoleAtt.WorldPosition = leftHipPos + (lookVec * 2.5) - (upVec * 1.5)
		end
		if self.rightUpLegBone and self.rightPoleAtt then
			local rightHipPos = self.rightUpLegBone.TransformedWorldCFrame.Position
			self.rightPoleAtt.WorldPosition = rightHipPos + (lookVec * 2.5) - (upVec * 1.5)
		end

		-- 2. Turn / Spin Attenuation: Attenuate IK during high angular velocity or rapid heading changes
		-- Allows athletic plant cuts, 90 cuts, and 180 direction reversals to play cleanly without IK ankle drag
		local angVelY = math.abs(self.smoothedTurnRate or self.rootPart.AssemblyAngularVelocity.Y)
		local rawTurnDampen = math.clamp(1.0 - (angVelY - 4.0) / 8.0, 0.0, 1.0)
		self.currentTurnDampen = (self.currentTurnDampen or 1.0) + (rawTurnDampen - (self.currentTurnDampen or 1.0)) * (1 - math.exp(-8.0 * dt))
		local turnDampen = self.currentTurnDampen

		-- 3. Anatomical Solver: Respects the animated (X, Z) stride and swing phase!
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

				-- A. Flat Ground Deadzone:
				-- If surface is nearly flat (Normal.Y >= 0.94) AND at normal floor level (|elevDelta| <= 0.20):
				-- The artist's locomotion animation is already 100% physically calibrated! Zero IK interference.
				local isFlatFloor = (hit.Normal.Y >= 0.94 and math.abs(elevDelta) <= 0.20)

				if not isFlatFloor and elevDelta >= -maxStepDown and elevDelta <= maxStepUp then
					-- Foot is on uneven terrain, slope, stairs, or platform step!
					-- Anatomical Stride Phase Rule:
					-- Only engage IK when the foot is near ground contact (liftAboveSurface <= 0.35 studs).
					-- If the foot is high in the air during the forward swing phase (liftAboveSurface > 0.35),
					-- DO NOT drag it to the floor! Let the leg swing freely forward.
					if liftAboveSurface <= 0.35 then
						-- Conformed target: Keep the animated X and Z stride! Only conform Y (height)
						targetPos = Vector3.new(animFootPos.X, floorY + ankleHeight, animFootPos.Z)
						
						-- Smooth weight transition: 1.0 at contact, blending down if foot is lifting
						local contactWeight = math.clamp(1.0 - (liftAboveSurface / 0.35), 0.0, 1.0)
						targetWeight = contactWeight * turnDampen
					else
						targetWeight = 0.0
					end
				else
					-- Off edge, ledge dropoff, or step out of range: let leg swing naturally without horizontal wall snapping
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
			local animRot = self.leftFootBone.TransformedWorldCFrame.Rotation
			self.leftFootAtt.WorldCFrame = CFrame.new(lPos) * animRot
		end
		if rPos then
			local animRot = self.rightFootBone.TransformedWorldCFrame.Rotation
			self.rightFootAtt.WorldCFrame = CFrame.new(rPos) * animRot
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
		local hipsDipScale = CombatConfig.FootIK_HipsDipScale or 0.50
		local lowestDelta = math.min(lDelta or 0, rDelta or 0)
		if lowestDelta < -0.15 then
			local targetDip = math.clamp(lowestDelta * hipsDipScale, -1.2, 0.0)
			self.hipsDipOffset = (self.hipsDipOffset or 0) + (targetDip - (self.hipsDipOffset or 0)) * math.clamp(14.0 * dt, 0, 1)
		else
			self.hipsDipOffset = (self.hipsDipOffset or 0) * math.exp(-12.0 * dt)
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
