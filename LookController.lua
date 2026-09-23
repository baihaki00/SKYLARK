--// LookController.lua
-- Procedural head, neck, and upper torso look-at controller for skinned mesh Quins
-- Operates as a client-side post-animation layer on top of evaluated FBX bone transforms
-- Implements graduated biomechanical distribution and smooth gaze tracking.

local Workspace = game:GetService("Workspace")

local LookController = {}
LookController.__index = LookController

-- Biomechanical constants
local ZONE1_MAX = math.rad(30)   -- 0-30 deg: Head only
local ZONE2_MAX = math.rad(60)   -- 30-60 deg: Head (60%) + Neck (40%)
local ZONE3_MAX = math.rad(100)  -- 60-100 deg: Head (40%) + Neck (30%) + Spine2 (30%)
local PITCH_MIN = -math.rad(45)  -- Looking down max
local PITCH_MAX = math.rad(65)   -- Looking up max

function LookController.new(ghostModel, aiModel)
	local self = setmetatable({}, LookController)

	self.ghostModel = ghostModel
	self.aiModel = aiModel
	self.enabled = true

	-- Bones
	self.headBone = ghostModel:FindFirstChild("mixamorig:Head", true)
	self.neckBone = ghostModel:FindFirstChild("mixamorig:Neck", true)
	self.spine2Bone = ghostModel:FindFirstChild("mixamorig:Spine2", true)
	self.rootPart = ghostModel:FindFirstChild("HumanoidRootPart") or (aiModel and aiModel:FindFirstChild("HumanoidRootPart"))

	-- State
	self.currentYaw = 0
	self.currentPitch = 0
	self.targetYaw = 0
	self.targetPitch = 0

	self.smoothSpeed = 14.0 -- Responsive, natural head turning speed
	self.gazeMode = "IDLE" -- "TARGET_COMBAT", "TARGET_AIRBORNE", "ALLY_AWARE", "IDLE_GLANCE"

	-- Ambient glance tracking
	self.glanceTimer = math.random() * 2
	self.glanceInterval = 3.5 + math.random() * 1.5
	self.ambientOffset = Vector3.zero

	-- Explicit target override for testing
	self.targetOverride = nil

	return self
end

-- Resolve the world-space target position for this frame
function LookController:resolveTargetPosition()
	if self.targetOverride then
		if typeof(self.targetOverride) == "Vector3" then
			return self.targetOverride, "OVERRIDE"
		elseif typeof(self.targetOverride) == "Instance" and self.targetOverride:FindFirstChild("HumanoidRootPart") then
			return self.targetOverride.HumanoidRootPart.Position + Vector3.new(0, 2.0, 0), "OVERRIDE"
		end
	end

	-- 1. Check AI server model for active target
	local serverModel = self.aiModel
	if serverModel and serverModel.Parent then
		local targetName = serverModel:GetAttribute("TargetQuin") or serverModel:GetAttribute("CurrentTarget")
		if targetName and targetName ~= "" then
			local qServer = Workspace:FindFirstChild("QuinServer") or Workspace
			local qGhost = Workspace:FindFirstChild("QuinGhost") or Workspace:FindFirstChild("AIGhosts")
			
			-- Look toward target's visual ghost or server model
			local targetModel = (qGhost and qGhost:FindFirstChild(targetName .. "_Visual")) 
				or (qServer:FindFirstChild(targetName)) 
				or Workspace:FindFirstChild(targetName)
				
			if targetModel and targetModel.Parent then
				local tRoot = targetModel:FindFirstChild("HumanoidRootPart")
				local tHum = targetModel:FindFirstChildOfClass("Humanoid")
				if tRoot and (not tHum or tHum.Health > 0) then
					local tHead = targetModel:FindFirstChild("mixamorig:Head", true)
					local targetPos = tHead and tHead.WorldCFrame.Position or (tRoot.Position + Vector3.new(0, 2.0, 0))
					
					-- Check if airborne threat
					local selfY = self.rootPart and self.rootPart.Position.Y or 0
					if targetPos.Y > selfY + 8 then
						return targetPos, "TARGET_AIRBORNE"
					else
						return targetPos, "TARGET_COMBAT"
					end
				end
			end
		end

		-- 2. Check distressed ally for protective awareness
		local distressedName = serverModel:GetAttribute("DistressedAllyName")
		if distressedName and distressedName ~= "" then
			local qServer = Workspace:FindFirstChild("QuinServer") or Workspace
			local allyModel = qServer:FindFirstChild(distressedName) or Workspace:FindFirstChild(distressedName)
			if allyModel and allyModel:FindFirstChild("HumanoidRootPart") then
				return allyModel.HumanoidRootPart.Position + Vector3.new(0, 1.8, 0), "ALLY_AWARE"
			end
		end
	end

	-- 3. No active combat target: Ambient glance or forward gaze
	if self.rootPart then
		local forwardPoint = self.rootPart.Position + (self.rootPart.CFrame.LookVector * 25) + Vector3.new(0, 1.5, 0)
		return forwardPoint + self.ambientOffset, "IDLE_GLANCE"
	end

	return nil, "NONE"
end

-- Update procedural look-at on top of animation
function LookController:update(dt)
	if not self.enabled or not self.headBone or not self.rootPart then return end
	if self.aiModel and self.aiModel:GetAttribute("CurrentState") == "Death" then return end

	-- Update ambient glance timer
	self.glanceTimer = self.glanceTimer + dt
	if self.glanceTimer >= self.glanceInterval then
		self.glanceTimer = 0
		self.glanceInterval = 2.5 + math.random() * 2.0
		-- Random natural small glance offset
		local rx = (math.random() - 0.5) * 6.0
		local ry = (math.random() - 0.5) * 2.5
		self.ambientOffset = (self.rootPart.CFrame.RightVector * rx) + Vector3.new(0, ry, 0)
	end

	local targetPos, mode = self:resolveTargetPosition()
	self.gazeMode = mode

	if not targetPos then return end

	local headWorldPos = self.headBone.WorldCFrame.Position
	local toTarget = targetPos - headWorldPos
	local dist = toTarget.Magnitude

	if dist < 0.3 then return end

	local dir = toTarget / dist

	-- Transform direction vector into local character root space
	-- In Roblox: -Z is forward, +X is right, +Y is up
	local localDir = self.rootPart.CFrame:VectorToObjectSpace(dir)

	-- Raw desired yaw and pitch
	-- When localDir.X < 0 (left): -localDir.X > 0 => atan2 > 0 => positive Y rotates LEFT
	-- When localDir.X > 0 (right): -localDir.X < 0 => atan2 < 0 => negative Y rotates RIGHT
	local rawYaw = math.atan2(-localDir.X, -localDir.Z)
	local rawPitch = math.asin(math.clamp(localDir.Y, -0.98, 0.98))

	-- Clamp total yaw at ZONE3_MAX (100 degrees) to prevent unnatural owl rotation
	local absYaw = math.abs(rawYaw)
	local clampedYaw = rawYaw
	if absYaw > ZONE3_MAX then
		clampedYaw = math.sign(rawYaw) * ZONE3_MAX
	end

	-- Clamp pitch
	local clampedPitch = math.clamp(rawPitch, PITCH_MIN, PITCH_MAX)

	-- Smooth rotation over time (exponential decay lerp)
	local alpha = 1 - math.exp(-self.smoothSpeed * dt)
	self.currentYaw = self.currentYaw + (clampedYaw - self.currentYaw) * alpha
	self.currentPitch = self.currentPitch + (clampedPitch - self.currentPitch) * alpha

	-- Graduated biomechanical distribution
	local headYaw, neckYaw, spineYaw = 0, 0, 0
	local curAbsYaw = math.abs(self.currentYaw)

	if curAbsYaw <= ZONE1_MAX then
		-- Zone 1 (0-30 deg): 100% Head
		headYaw = self.currentYaw
		neckYaw = 0
		spineYaw = 0
	elseif curAbsYaw <= ZONE2_MAX then
		-- Zone 2 (30-60 deg): 60% Head, 40% Neck
		headYaw = self.currentYaw * 0.60
		neckYaw = self.currentYaw * 0.40
		spineYaw = 0
	else
		-- Zone 3 (60-100 deg): 40% Head, 30% Neck, 30% Spine2
		headYaw = self.currentYaw * 0.40
		neckYaw = self.currentYaw * 0.30
		spineYaw = self.currentYaw * 0.30
	end

	-- Pitch distribution: 70% Head, 30% Neck
	local headPitch = self.currentPitch * 0.70
	local neckPitch = self.currentPitch * 0.30

	-- Apply multiplicatively to Bone.Transform on top of evaluated animation track
	if self.headBone then
		self.headBone.Transform = self.headBone.Transform * CFrame.Angles(headPitch, headYaw, 0)
	end
	if self.neckBone then
		self.neckBone.Transform = self.neckBone.Transform * CFrame.Angles(neckPitch, neckYaw, 0)
	end
	if self.spine2Bone and spineYaw ~= 0 then
		self.spine2Bone.Transform = self.spine2Bone.Transform * CFrame.Angles(0, spineYaw, 0)
	end
end

-- Override target for isolated testing
function LookController:setTargetOverride(target)
	self.targetOverride = target
end

-- Return gaze telemetry for testing and audits
function LookController:getGazeTelemetry()
	return {
		mode = self.gazeMode,
		yawDeg = math.deg(self.currentYaw),
		pitchDeg = math.deg(self.currentPitch),
		hasHead = self.headBone ~= nil,
		hasNeck = self.neckBone ~= nil,
		hasSpine2 = self.spine2Bone ~= nil,
	}
end

function LookController:destroy()
	self.enabled = false
	self.ghostModel = nil
	self.aiModel = nil
	self.headBone = nil
	self.neckBone = nil
	self.spine2Bone = nil
	self.rootPart = nil
end

return LookController
