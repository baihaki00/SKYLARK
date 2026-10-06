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
local FLOOR_LOOK_PITCH = -math.rad(12) -- a look steeper down than this is checked against the floor...
local FLOOR_LOOK_REACH = 40           -- ...within this many studs of the head (a head 8 studs up looking 12 degrees down meets its floor 38 studs out)

-- Social nod (SocialSystem.nod): two quick dips after the Quin's NodAt time
local okConfig, CombatConfig = pcall(function() return require(script.Parent.Parent:WaitForChild("CombatConfig")) end)
local SOCIAL = okConfig and CombatConfig.Social or {}
local NOD_DURATION = SOCIAL.NodDuration or 0.6
local NOD_DEPTH = math.rad(SOCIAL.NodDepth or 12)

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
		-- A piloted Quin (Player Quin) looks where its player looks: its sight is the player's view
		-- (QUIN_CREATURE_DESIGN.md 5.8). The pilot's own client reads its camera; everyone else
		-- reads the direction the pilot's client sends (PilotLookYaw / PilotLookPitch).
		local pilotedBy = serverModel:GetAttribute("PilotedBy")
		if pilotedBy and self.rootPart then
			local origin = self.headBone and self.headBone.WorldCFrame.Position or (self.rootPart.Position + Vector3.new(0, 2.5, 0))
			local localPlayer = game:GetService("Players").LocalPlayer
			if localPlayer and pilotedBy == localPlayer.UserId and Workspace.CurrentCamera then
				return origin + Workspace.CurrentCamera.CFrame.LookVector * 60, "PILOT_VIEW"
			end
			local yaw, pitch = serverModel:GetAttribute("PilotLookYaw"), serverModel:GetAttribute("PilotLookPitch")
			if yaw then
				local y, p = math.rad(yaw), math.rad(pitch or 0)
				return origin + Vector3.new(math.sin(y) * math.cos(p), math.sin(p), math.cos(y) * math.cos(p)) * 60, "PILOT_VIEW"
			end
		end

		local isPlayer = (serverModel:GetAttribute("IsPlayerControlled") == true)
			or (game.Players.LocalPlayer and serverModel:GetAttribute("ControllingPlayer") == game.Players.LocalPlayer.Name)

		-- For player-controlled Quins: do not wrench head towards background AI while exploring/moving.
		-- Only engage look tracking if an explicit lock-on target is active.
		if isPlayer then
			local lockedTarget = serverModel:GetAttribute("LockedCombatTarget")
			if not lockedTarget or lockedTarget == "" then
				return nil, "NONE"
			end
		end

		-- Looking back over the shoulder while running (the full-body glance clip froze the legs):
		-- at the threat behind if there is one, else to one side
		local glanceUntil = serverModel:GetAttribute("GlanceBackUntil")
		if not isPlayer and glanceUntil and workspace:GetServerTimeNow() < glanceUntil and self.rootPart then
			local threatName = serverModel:GetAttribute("ClosestRearThreat")
			local qServer = Workspace:FindFirstChild("QuinServer") or Workspace
			local threat = threatName and qServer:FindFirstChild(threatName)
			local threatRoot = threat and threat:FindFirstChild("HumanoidRootPart")
			if threatRoot then
				return threatRoot.Position + Vector3.new(0, 2, 0), "GLANCE_BACK"
			end
			if not self.glanceSide or (self.glanceSideUntil or 0) < glanceUntil then
				self.glanceSide = math.random() < 0.5 and -1 or 1
				self.glanceSideUntil = glanceUntil
			end
			local cf = self.rootPart.CFrame
			return self.rootPart.Position + (cf.RightVector * self.glanceSide - cf.LookVector * 0.6) * 30 + Vector3.new(0, 2, 0), "GLANCE_BACK"
		end

		-- Social body language (SocialSystem): a look at another Quin - the leader, an ally it
		-- nods to, one that ignored a signal, a duel it watches
		local socialUntil = serverModel:GetAttribute("SocialLookUntil")
		if not isPlayer and socialUntil and workspace:GetServerTimeNow() < socialUntil then
			local name = serverModel:GetAttribute("SocialLookAt")
			local qServer = Workspace:FindFirstChild("QuinServer") or Workspace
			local qGhost = Workspace:FindFirstChild("QuinGhost") or Workspace:FindFirstChild("AIGhosts")
			local other = name and ((qGhost and qGhost:FindFirstChild(name .. "_Visual")) or qServer:FindFirstChild(name))
			local otherHead = other and other:FindFirstChild("mixamorig:Head", true)
			local otherRoot = other and other:FindFirstChild("HumanoidRootPart")
			if otherHead then
				return otherHead.WorldCFrame.Position, "SOCIAL"
			elseif otherRoot then
				return otherRoot.Position + Vector3.new(0, 2, 0), "SOCIAL"
			end
		end

		-- Scanning (Cognition.Gaze): a glance at the sky, or looking down over the edge of
		-- high ground. The head pitches to the gaze, straight ahead of the body.
		local gazeMode = serverModel:GetAttribute("GazeMode")
		local gazePitch = math.rad(serverModel:GetAttribute("GazePitch") or 0)
		if not isPlayer and (gazeMode == "glance" or gazeMode == "resting") and math.abs(gazePitch) > math.rad(5) and self.rootPart then
			local look = self.rootPart.CFrame.LookVector
			local flat = Vector3.new(look.X, 0, look.Z)
			if flat.Magnitude > 0.01 then
				local origin = self.headBone and self.headBone.WorldCFrame.Position or self.rootPart.Position
				return origin + (flat.Unit * math.cos(gazePitch) + Vector3.new(0, math.sin(gazePitch), 0)) * 50, "SCAN"
			end
		end

		-- Running into a turn, the head (and chest, through the graduated distribution) turns toward
		-- where the body means to go before the body does (SteerIntent from the steer; design doc
		-- phase 1: intent shows in layers)
		if not isPlayer and self.rootPart and (not okConfig or CombatConfig.Body_HeadLeadsTurn ~= false) then
			local intent = serverModel:GetAttribute("SteerIntent")
			local pace = serverModel:GetAttribute("PacingVelocity") or 0
			if intent and pace > 12 then
				local yaw = math.rad(intent)
				local dir = Vector3.new(math.sin(yaw), 0, math.cos(yaw))
				local look = self.rootPart.CFrame.LookVector
				local flatLook = Vector3.new(look.X, 0, look.Z)
				local minAngle = math.rad(okConfig and CombatConfig.Body_HeadLeadMinAngle or 20)
				if flatLook.Magnitude > 0.01 and flatLook.Unit:Dot(dir) < math.cos(minAngle) then
					local origin = self.headBone and self.headBone.WorldCFrame.Position or self.rootPart.Position
					return origin + dir * 40, "INTENT"
				end
			end
		end

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

					-- A target it cannot see is looked for where it last saw it, not stared at
					-- through the wall or the floor between them. Checked here with a ray from its
					-- own head, ten times a second (the server's TargetHasLoS said "visible" for
					-- 59% of the targets such a ray found hidden).
					-- (Workspace LookSight = false switches both sight rules off, for A/B)
					if not isPlayer and self.headBone and Workspace:GetAttribute("LookSight") ~= false then
						local now = os.clock()
						if self.sightName ~= targetName then
							self.sightName, self.lastSeenPos, self.sightAt = targetName, nil, 0
						end
						if now - self.sightAt >= 0.1 then
							self.sightAt = now
							local eye = self.headBone.TransformedWorldCFrame.Position
							local toTarget = targetPos - eye
							self.sightClear = toTarget.Magnitude < 6 or Workspace:Raycast(eye, toTarget, self:sightFilter()) == nil
						end
						if self.sightClear then
							self.lastSeenPos = targetPos
						elseif self.lastSeenPos then
							return self.lastSeenPos, "TARGET_LAST_SEEN"
						else
							return nil, "NONE"
						end
					end
					
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

	-- 3. No active combat target: Return nil so the natural author animation breathes with 100% purity
	return nil, "NONE"
end

-- What its sight is blocked by: the world, not other Quins
function LookController:sightFilter()
	if not self.sightParams then
		self.sightParams = RaycastParams.new()
		self.sightParams.FilterType = Enum.RaycastFilterType.Exclude
		self.sightParams.FilterDescendantsInstances = { Workspace:FindFirstChild("QuinServer"), Workspace:FindFirstChild("QuinGhost"), self.ghostModel }
	end
	return self.sightParams
end

-- Writes `offset` on top of the bone's animated pose. When the Animator has not re-evaluated the
-- bone since the last write (animation can update at a lower rate than rendering), the bone still
-- holds the previous result; multiplying onto that compounded the offset frame by frame (a nod
-- read as -6, -41, -18, -60 degrees on alternate frames). The previous base is reused instead.
function LookController:applyBoneOffset(bone, offset)
	self.boneWrites = self.boneWrites or {}
	local last = self.boneWrites[bone]
	local current = bone.Transform
	local base = (last and current == last.written) and last.base or current
	bone.Transform = base * offset
	self.boneWrites[bone] = { base = base, written = bone.Transform }
end

-- Update procedural look-at on top of animation
function LookController:update(dt)
	if not self.enabled or not self.headBone or not self.rootPart then return end
	if self.aiModel and self.aiModel:GetAttribute("CurrentState") == "Death" then return end

	local targetPos, mode = self:resolveTargetPosition()
	self.gazeMode = mode

	-- Nod: two dips of the head (the second smaller), on top of wherever it is looking
	local nodPitch = 0
	local nodAt = self.aiModel and self.aiModel:GetAttribute("NodAt")
	if nodAt then
		local t = workspace:GetServerTimeNow() - nodAt
		if t >= 0 and t < NOD_DURATION then
			local wave = math.sin(2 * math.pi * t / NOD_DURATION)
			nodPitch = -NOD_DEPTH * wave * wave * (1 - 0.4 * t / NOD_DURATION)
		end
	end

	-- The head turns on a critically damped spring with a top speed: it eases into a turn and
	-- settles without overshoot. (An exponential lerp started every turn at full speed, and a
	-- 1.2 degree dead zone held the head still then let it jump.)
	local function springTo(targetYaw, targetPitch)
		local omega = 11.0
		local maxSpeed = math.rad(420)
		dt = math.clamp(dt, 0.001, 0.05)
		self.yawVelocity = self.yawVelocity or 0
		self.pitchVelocity = self.pitchVelocity or 0
		local yawAccel = omega * omega * (targetYaw - self.currentYaw) - 2 * omega * self.yawVelocity
		local pitchAccel = omega * omega * (targetPitch - self.currentPitch) - 2 * omega * self.pitchVelocity
		self.yawVelocity = math.clamp(self.yawVelocity + yawAccel * dt, -maxSpeed, maxSpeed)
		self.pitchVelocity = math.clamp(self.pitchVelocity + pitchAccel * dt, -maxSpeed, maxSpeed)
		self.currentYaw += self.yawVelocity * dt
		self.currentPitch += self.pitchVelocity * dt
	end

	if not targetPos then
		-- No target: settle back to the clip's own head
		springTo(0, 0)
		if nodPitch == 0 and math.abs(self.currentYaw) < 0.002 and math.abs(self.currentPitch) < 0.002
			and math.abs(self.yawVelocity) < 0.01 and math.abs(self.pitchVelocity) < 0.01 then
			self.currentYaw, self.currentPitch, self.yawVelocity, self.pitchVelocity = 0, 0, 0, 0
			return -- Early return: leaves author-keyed head/neck bone transforms 100% untouched
		end
	else
		-- Active combat target tracking
		local headWorldPos = self.headBone.WorldCFrame.Position
		local toTarget = targetPos - headWorldPos
		local dist = toTarget.Magnitude

		if dist < 0.3 then return end

		local dir = toTarget / dist

		-- Transform direction vector into local character root space
		-- In Roblox: -Z is forward, +X is right, +Y is up
		local localDir = self.rootPart.CFrame:VectorToObjectSpace(dir)

		-- Raw desired yaw and pitch
		local rawYaw = math.atan2(-localDir.X, -localDir.Z)
		local rawPitch = math.asin(math.clamp(localDir.Y, -0.98, 0.98))

		-- It does not look into the floor it stands on. A look down that meets the ground within
		-- a few studs (its target is under the platform, or it "looks over the edge" from the
		-- middle of a wide top) is held level; from the rim the same look clears the edge and
		-- goes down. (On platforms the head was pitched into the top on 21% of frames.)
		if rawPitch < FLOOR_LOOK_PITCH and Workspace:GetAttribute("LookSight") ~= false then
			local floor = Workspace:Raycast(headWorldPos, dir * math.min(dist, FLOOR_LOOK_REACH), self:sightFilter())
			if floor and floor.Normal.Y > 0.7 then
				rawPitch = 0
				mode = mode .. "+FLOOR"
			end
		end
		-- (debug: what the head is doing and why; client-only attribute, Workspace LookDebug)
		if self.aiModel and Workspace:GetAttribute("LookDebug") then
			self.aiModel:SetAttribute("LookDbg", mode)
		end

		-- Biomechanical Peripheral Gaze Falloff:
		-- Eye/head tracking is active within comfortable field of view (|yaw| <= 70 deg).
		-- Between 70 and 85 deg, tracking smoothly blends to 0 via cubic Hermite curve.
		-- Beyond 85 deg (behind character), gaze weight is 0: head faces forward naturally.
		-- Eliminates branch-cut (+-180 deg) flipping, owl snaps, and idle jitter!
		local absYaw = math.abs(rawYaw)
		local gazeWeight = 1.0
		if absYaw > math.rad(70) then
			if absYaw >= math.rad(85) then
				gazeWeight = 0.0
			else
				local p = (absYaw - math.rad(70)) / math.rad(15)
				gazeWeight = 1.0 - (p * p * (3 - 2 * p))
			end
		end

		-- A look back over the shoulder turns further, the upper back taking its share
		local yawLimit = ZONE2_MAX
		if mode == "GLANCE_BACK" or mode == "SOCIAL" then
			gazeWeight = 1.0
			yawLimit = ZONE3_MAX
		end
		local clampedYaw = math.clamp(rawYaw, -yawLimit, yawLimit) * gazeWeight
		local clampedPitch = math.clamp(rawPitch, PITCH_MIN, PITCH_MAX) * gazeWeight
		springTo(clampedYaw, clampedPitch)
	end

	-- Distribution over head, neck and upper back: fixed shares, so the split never jumps.
	-- (Zones with different splits - 100% head to 30 degrees, then 60/40 - moved the head
	-- back 12 degrees the moment a target crossed 30 degrees.)
	local headYaw = self.currentYaw * 0.50
	local neckYaw = self.currentYaw * 0.30
	local spineYaw = self.currentYaw * 0.20

	-- Pitch distribution: 70% Head, 30% Neck
	local headPitch = self.currentPitch * 0.70 + nodPitch * 0.75
	local neckPitch = self.currentPitch * 0.30 + nodPitch * 0.25

	-- Apply multiplicatively to Bone.Transform on top of evaluated animation track
	if self.headBone then
		self:applyBoneOffset(self.headBone, CFrame.Angles(headPitch, headYaw, 0))
	end
	if self.neckBone then
		self:applyBoneOffset(self.neckBone, CFrame.Angles(neckPitch, neckYaw, 0))
	end
	if self.spine2Bone and spineYaw ~= 0 then
		self:applyBoneOffset(self.spine2Bone, CFrame.Angles(0, spineYaw, 0))
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
