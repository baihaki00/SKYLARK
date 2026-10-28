--// LookController.lua
-- Procedural head, neck, and upper torso look-at controller for skinned mesh Quins
-- Operates as a client-side post-animation layer on top of evaluated FBX bone transforms
-- Implements graduated biomechanical distribution and smooth gaze tracking.

local GameClock = require(game:GetService("ReplicatedStorage"):WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("GameClock")) -- (the game's clock: a freeze stops it)
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
-- Head shake (Gaze: "not worth it" to an ally's point): two swings, fading, after ShakeAt
local SHAKE_DURATION = 0.7
local SHAKE_AMP = math.rad(16)

-- Pointing (Cognition/Callouts, owner 2026-10-28: Quins are mute, they point). For PointDuration
-- after the Quin's PointAt, the arm on the enemy's side reaches toward it: a two-bone IK (shoulder,
-- elbow) to a hand point short of full reach, so the elbow keeps a bend, with the elbow dropping
-- down, out and a little back like a person's. The aim is held inside what a shoulder does (a
-- little across the body, never behind it), and the chest turns part of the way.
local COG = okConfig and CombatConfig.Cognition or {}
local POINT_DURATION = COG.PointDuration or 1.1
local POINT_BUSY_STATES = { Fight = true, Knockback = true, Recovery = true, Death = true, Airborne = true,
	ProjectileJump = true, MidAirClash = true, Special = true, WallRun = true }
local POINT_REACH = 0.97           -- hand distance as a share of the arm's full length: ~28 degrees at the elbow (0.9 gave 52, a bent arm)
local POINT_ACROSS = math.rad(25)  -- furthest the aim goes across the body
local POINT_OUT = math.rad(120)    -- furthest out to its own side
local POINT_PITCH_MIN, POINT_PITCH_MAX = math.rad(-35), math.rad(50)
local POINT_CHEST_SHARE, POINT_CHEST_MAX = 0.3, math.rad(20)
local POINT_WRIST = math.rad(35)      -- most the wrist turns to line the finger up
-- The pointing hand: the index straight, the other three curled in tight (the clips hold a loose
-- fist; on this rig a finger curls by turning negative about its own X). The thumb keeps the clip's.
local POINT_FINGERS = {
	Index = { -4, -3, -2 },
	Middle = { -80, -95, -60 },
	Ring = { -85, -95, -60 },
	Pinky = { -85, -90, -60 },
}

local function smooth(a, b, x)
	local t = math.clamp((x - a) / (b - a), 0, 1)
	return t * t * (3 - 2 * t)
end

-- Rotation (world axis, angle) taking direction a onto direction b; nil when already aligned
local function between(a, b)
	local axis = a:Cross(b)
	if axis.Magnitude < 1e-5 then return nil end
	return axis.Unit, math.acos(math.clamp(a:Dot(b), -1, 1))
end

-- Finds the bones. Again later when they were missing or replaced: a controller built before
-- the body finished loading held no arm (or no head) bones, and its Quin never pointed (owner
-- 2026-10-28: "sometimes they point it doesnt work")
function LookController:bindBones()
	local ghostModel = self.ghostModel
	self.headBone = ghostModel:FindFirstChild("mixamorig:Head", true)
	self.arms = {}

	for _, side in ipairs({ "Right", "Left" }) do
		local upper = ghostModel:FindFirstChild("mixamorig:" .. side .. "Arm", true)
		local fore = ghostModel:FindFirstChild("mixamorig:" .. side .. "ForeArm", true)
		local hand = ghostModel:FindFirstChild("mixamorig:" .. side .. "Hand", true)
		if upper and fore and hand then
			local fingers = {}
			for finger, angles in pairs(POINT_FINGERS) do
				for i, deg in ipairs(angles) do
					local bone = hand:FindFirstChild("mixamorig:" .. side .. "Hand" .. finger .. i, true)
					if bone then table.insert(fingers, { bone = bone, pose = CFrame.Angles(math.rad(deg), 0, 0) }) end
				end
			end
			self.arms[side] = { upper = upper, fore = fore, hand = hand, fingers = fingers }
		end
	end
	self.neckBone = ghostModel:FindFirstChild("mixamorig:Neck", true)
	self.spine2Bone = ghostModel:FindFirstChild("mixamorig:Spine2", true)
end

function LookController.new(ghostModel, aiModel)
	local self = setmetatable({}, LookController)

	self.ghostModel = ghostModel
	self.aiModel = aiModel
	self.enabled = true
	self:bindBones()
	self.pointW, self.pointChestYaw = 0, 0
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
		if not isPlayer and glanceUntil and GameClock.serverNow() < glanceUntil and self.rootPart then
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
		if not isPlayer and socialUntil and GameClock.serverNow() < socialUntil then
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

		-- A look at a place (LookPoint until LookUntil): where it was just told to go, a way in it
		-- scans from its post, the spot a teammate called (IdleState, Cognition.Gaze)
		local lookUntil = serverModel:GetAttribute("LookUntil")
		local lookPoint = serverModel:GetAttribute("LookPoint")
		if not isPlayer and lookUntil and typeof(lookPoint) == "Vector3" and GameClock.serverNow() < lookUntil then
			return lookPoint + Vector3.new(0, 2.5, 0), "LOOK"
		end

		-- Scanning (Cognition.Gaze): a glance at the sky, or looking down over the edge of
		-- high ground. The head pitches to the gaze, straight ahead of the body.
		local gazeMode = serverModel:GetAttribute("GazeMode")
		local gazePitch = math.rad(serverModel:GetAttribute("GazePitch") or 0)
		-- A glance up at a Quin overhead (GazeAt): the head goes to that Quin
		local gazeAt = gazeMode == "glance" and serverModel:GetAttribute("GazeAt")
		if not isPlayer and gazeAt then
			local qServer = Workspace:FindFirstChild("QuinServer") or Workspace
			local qGhost = Workspace:FindFirstChild("QuinGhost") or Workspace:FindFirstChild("AIGhosts")
			local other = (qGhost and qGhost:FindFirstChild(gazeAt .. "_Visual")) or qServer:FindFirstChild(gazeAt)
			local otherRoot = other and other:FindFirstChild("HumanoidRootPart")
			if otherRoot then
				return otherRoot.Position + Vector3.new(0, 2, 0), "SCAN"
			end
		end
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
						local now = GameClock.now()
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

-- The animated Transform under any offset written last frame (see applyBoneOffset)
function LookController:baseTransform(bone)
	local last = self.boneWrites and self.boneWrites[bone]
	if last and bone.Transform == last.written then return last.base end
	return bone.Transform
end

-- How far the arm is up this frame, toward what, with which arm, and the chest's share
function LookController:preparePoint()
	self.pointW, self.pointChestYaw = 0, 0
	local model = self.aiModel
	local at = model and model:GetAttribute("PointAt")
	if not at or Workspace:GetAttribute("PointOff") == true then return end
	local t = GameClock.serverNow() - at
	if t < 0 or t >= POINT_DURATION then return end
	-- busy with its body (fighting, striking, in the air, hit): the arm comes down in 0.2 s, and
	-- stays down for this point (owner 2026-10-29: an arm left up into a jump pointed at the sky)
	local busy = POINT_BUSY_STATES[model:GetAttribute("CurrentState") or ""] or model:GetAttribute("Attacking") == true
	if busy and self.pointBusyKey ~= at then
		self.pointBusyKey, self.pointBusyAt = at, t
	end
	local busyFade = self.pointBusyKey == at and smooth(self.pointBusyAt, self.pointBusyAt + 0.2, t) or 0
	if busyFade >= 1 then return end
	-- at a Quin (PointAtName), or at a place (PointAtPos: a spot, a thing, where to go)
	local targetPos
	local name = model:GetAttribute("PointAtName")
	if name and name ~= "" then
		local folder = Workspace:FindFirstChild("QuinServer")
		local enemy = folder and folder:FindFirstChild(name)
		local enemyRoot = enemy and enemy:FindFirstChild("HumanoidRootPart")
		if not enemyRoot then return end
		targetPos = enemyRoot.Position + Vector3.new(0, 1, 0)
	else
		targetPos = model:GetAttribute("PointAtPos")
		if typeof(targetPos) ~= "Vector3" then return end
	end
	local localPos = self.rootPart.CFrame:PointToObjectSpace(targetPos)
	if self.pointKey ~= at then
		self.pointKey = at
		self.pointSide = localPos.X >= 0 and "Right" or "Left" -- (the arm on its side)
	end
	if not self.arms[self.pointSide] then return end
	local w = smooth(0, 0.18, t) * (1 - smooth(POINT_DURATION - 0.3, POINT_DURATION, t)) * (1 - busyFade)
	local yaw = math.atan2(-localPos.X, -localPos.Z)
	-- the enemy swung round behind it mid-point: the arm comes down rather than wrench back
	w *= 1 - smooth(math.rad(105), math.rad(140), math.abs(yaw))
	-- ...or crossed over to the other arm's side (it turned): down rather than point wrong
	local across = self.pointSide == "Right" and yaw or -yaw
	w *= 1 - smooth(POINT_ACROSS + math.rad(10), POINT_ACROSS + math.rad(45), across)
	self.pointW = w
	self.pointTarget = targetPos
	self.pointChestYaw = math.clamp(yaw * POINT_CHEST_SHARE, -POINT_CHEST_MAX, POINT_CHEST_MAX) * w
end

-- Two-bone IK for the pointing arm, after the head/neck/chest are written
function LookController:applyPoint()
	if self.pointW <= 0.001 then return end
	local arm = self.arms[self.pointSide]
	local upper, fore, hand = arm.upper, arm.fore, arm.hand
	local root = self.rootPart.CFrame
	-- the arm as animated (without last frame's offsets)
	local U = upper.TransformedWorldCFrame * upper.Transform:Inverse() * self:baseTransform(upper)
	local F = U * fore.CFrame * self:baseTransform(fore)
	local S, E0, H0 = U.Position, F.Position, (F * hand.CFrame).Position
	local L1, L2 = (E0 - S).Magnitude, (H0 - E0).Magnitude
	if L1 < 0.05 or L2 < 0.05 then return end

	-- aim, held inside what a shoulder does
	local toTarget = self.pointTarget - S
	if toTarget.Magnitude < 0.5 then return end
	local ld = root:VectorToObjectSpace(toTarget.Unit)
	local yaw = math.atan2(-ld.X, -ld.Z) -- (+ = to its left)
	local pitch = math.asin(math.clamp(ld.Y, -1, 1))
	if self.pointSide == "Right" then
		yaw = math.clamp(yaw, -POINT_OUT, POINT_ACROSS)
	else
		yaw = math.clamp(yaw, -POINT_ACROSS, POINT_OUT)
	end
	pitch = math.clamp(pitch, POINT_PITCH_MIN, POINT_PITCH_MAX)
	local dir = root:VectorToWorldSpace(Vector3.new(-math.sin(yaw) * math.cos(pitch), math.sin(pitch), -math.cos(yaw) * math.cos(pitch)))

	-- hand short of full reach; the elbow on the circle that leaves, toward the pole
	local d = (L1 + L2) * POINT_REACH
	local T = S + dir * d
	local cosA = math.clamp((L1 * L1 + d * d - L2 * L2) / (2 * L1 * d), -1, 1)
	local out = root.RightVector * (self.pointSide == "Right" and 1 or -1)
	local pole = -root.UpVector + out * 0.6 - root.LookVector * 0.3
	local perp = pole - dir * pole:Dot(dir)
	if perp.Magnitude < 1e-3 then perp = -root.UpVector - dir * (-root.UpVector):Dot(dir) end
	perp = perp.Unit
	local E = S + dir * (cosA * L1) + perp * (math.sqrt(1 - cosA * cosA) * L1)

	-- upper arm onto the elbow, then the forearm onto the hand point (full solution, as local
	-- offsets), then both eased in by the weight
	local axis1, angle1 = between((E0 - S).Unit, (E - S).Unit)
	local R1 = axis1 and CFrame.fromAxisAngle(axis1, angle1) or CFrame.identity
	local offset1 = axis1 and CFrame.fromAxisAngle(U:VectorToObjectSpace(axis1), angle1) or CFrame.identity
	local f1 = R1:VectorToWorldSpace((H0 - E0).Unit)
	local axis2, angle2 = between(f1, (T - E).Unit)
	local foreRot = R1 * F.Rotation
	local offset2 = axis2 and CFrame.fromAxisAngle(foreRot:VectorToObjectSpace(axis2), angle2) or CFrame.identity
	self:applyBoneOffset(upper, CFrame.identity:Lerp(offset1, self.pointW))
	self:applyBoneOffset(fore, CFrame.identity:Lerp(offset2, self.pointW))
	-- the wrist turns the finger onto the target (the clip's wrist angle left it ~15 degrees off),
	-- at most POINT_WRIST
	local index1 = arm.fingers[1] and hand:FindFirstChild("mixamorig:" .. self.pointSide .. "HandIndex1")
	local index2 = index1 and index1:FindFirstChild("mixamorig:" .. self.pointSide .. "HandIndex2")
	local index3 = index2 and index2:FindFirstChild("mixamorig:" .. self.pointSide .. "HandIndex3")
	if index3 then
		local Hw = hand.TransformedWorldCFrame * hand.Transform:Inverse() * self:baseTransform(hand)
		local tipLocal = (index1.CFrame * index2.CFrame * index3.CFrame).Position - index1.CFrame.Position
		local fingerDir = Hw:VectorToWorldSpace(tipLocal.Unit)
		local axis3, angle3 = between(fingerDir, (self.pointTarget - Hw.Position).Unit)
		if axis3 then
			angle3 = math.min(angle3, POINT_WRIST)
			self:applyBoneOffset(hand, CFrame.identity:Lerp(CFrame.fromAxisAngle(Hw:VectorToObjectSpace(axis3), angle3), self.pointW))
		end
	end
	-- the hand: from the clip's fist to the point, with the arm
	for _, finger in ipairs(arm.fingers) do
		local base = self:baseTransform(finger.bone)
		self:applyBoneOffset(finger.bone, base:Inverse() * base:Lerp(finger.pose, self.pointW))
	end
end

-- Update procedural look-at on top of animation, then the pointing arm
function LookController:update(dt)
	local stale = not self.headBone or not self.headBone:IsDescendantOf(self.ghostModel)
		or not self.arms.Right or not self.arms.Right.upper:IsDescendantOf(self.ghostModel)
	if stale and GameClock.now() >= (self.rebindAt or 0) then
		self.rebindAt = GameClock.now() + 1
		self:bindBones()
		self.boneWrites = nil
	end
	if Workspace:GetAttribute("PointProbe") and self.aiModel then
		self.aiModel:SetAttribute("PointDbg", string.format("head=%s arms=%s stale=%s", tostring(self.headBone ~= nil), tostring(self.arms.Right ~= nil), tostring(stale)))
	end
	if not self.enabled or not self.headBone or not self.rootPart then return end
	if self.aiModel and self.aiModel:GetAttribute("CurrentState") == "Death" then return end
	self:preparePoint()
	self:updateLook(dt)
	self:applyPoint()
	if Workspace:GetAttribute("PointProbe") and self.aiModel then
		self.aiModel:SetAttribute("PointW", math.round(self.pointW * 100) / 100)
	end
end

function LookController:updateLook(dt)

	local targetPos, mode = self:resolveTargetPosition()
	self.gazeMode = mode
	self.lastTargetPos = targetPos -- (the eyes look the rest of the way: QuinEyes)

	-- Nod: two dips of the head (the second smaller), on top of wherever it is looking
	local nodPitch = 0
	local nodAt = self.aiModel and self.aiModel:GetAttribute("NodAt")
	if nodAt then
		local t = GameClock.serverNow() - nodAt
		if t >= 0 and t < NOD_DURATION then
			local wave = math.sin(2 * math.pi * t / NOD_DURATION)
			nodPitch = -NOD_DEPTH * wave * wave * (1 - 0.4 * t / NOD_DURATION)
		end
	end
	local shakeYaw = 0
	local shakeAt = self.aiModel and self.aiModel:GetAttribute("ShakeAt")
	if shakeAt then
		local t = GameClock.serverNow() - shakeAt
		if t >= 0 and t < SHAKE_DURATION then
			shakeYaw = SHAKE_AMP * math.sin(4 * math.pi * t / SHAKE_DURATION) * (1 - t / SHAKE_DURATION)
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
		if nodPitch == 0 and shakeYaw == 0 and self.pointChestYaw == 0 and math.abs(self.currentYaw) < 0.002 and math.abs(self.currentPitch) < 0.002
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
		if self.aiModel and Workspace:GetAttribute("LookDebug") and (Workspace:GetAttribute("DebugScopeQuin") or self.aiModel.Name) == self.aiModel.Name then -- (DebugSwitches scope: Workspace DebugScopeQuin, unset = every Quin)
			self.aiModel:SetAttribute("LookDbg", mode)
		end

		-- Biomechanical Peripheral Gaze Falloff:
		-- Eye/head tracking is active within comfortable field of view (|yaw| <= 70 deg).
		-- Between 70 and 85 deg, tracking smoothly blends to 0 via cubic Hermite curve.
		-- Beyond 85 deg (behind character), gaze weight is 0: head faces forward naturally.
		-- Eliminates branch-cut (+-180 deg) flipping, owl snaps, and idle jitter!
		-- (2026-10-27, owner: "I don't see the Quins tracking their enemies". It followed only to 60
		-- degrees and let go past 85, so anything to the side got no look at all. Now head, neck
		-- and upper back follow to 100 degrees, and it lets go between 100 and 125: still well
		-- short of straight behind, where the look would flip sides.)
		-- Moving forward (owner 2026-10-28: a Quin running straight with its head turned 90 degrees
		-- looked wrong): the head turns at most Look_MovingYawMax, and lets go of a target further
		-- round (Look_MovingLetGoStart..End) - the body turns to it, or it is not watched. Standing,
		-- strafing and backpedalling keep the wide range. Workspace HeadLimitOff = true: old range.
		local moving = 0
		if Workspace:GetAttribute("HeadLimitOff") ~= true then
			local vel = self.rootPart.AssemblyLinearVelocity
			local flatVel = Vector3.new(vel.X, 0, vel.Z)
			local speed = flatVel.Magnitude
			if speed > 1 then
				local look = self.rootPart.CFrame.LookVector
				local flatLook = Vector3.new(look.X, 0, look.Z)
				local along = flatLook.Magnitude > 0.01 and flatVel.Unit:Dot(flatLook.Unit) or 0
				local function ss(a, b, x) local t = math.clamp((x - a) / (b - a), 0, 1) return t * t * (3 - 2 * t) end
				moving = ss(4, 10, speed) * ss(0.5, 0.85, along)
			end
		end
		local letGoStart = math.rad(100) + moving * (math.rad((okConfig and CombatConfig.Look_MovingLetGoStart) or 70) - math.rad(100))
		local letGoEnd = math.rad(125) + moving * (math.rad((okConfig and CombatConfig.Look_MovingLetGoEnd) or 95) - math.rad(125))

		local absYaw = math.abs(rawYaw)
		local gazeWeight = 1.0
		if absYaw > letGoStart then
			if absYaw >= letGoEnd then
				gazeWeight = 0.0
			else
				local p = (absYaw - letGoStart) / (letGoEnd - letGoStart)
				gazeWeight = 1.0 - (p * p * (3 - 2 * p))
			end
		end

		-- A look back over the shoulder turns further, the upper back taking its share
		local yawLimit = ZONE3_MAX + moving * (math.rad((okConfig and CombatConfig.Look_MovingYawMax) or 45) - ZONE3_MAX)
		if mode == "GLANCE_BACK" or mode == "SOCIAL" then
			gazeWeight = 1.0
			yawLimit = ZONE3_MAX -- (a deliberate look keeps its full turn, moving or not)
		end
		local clampedYaw = math.clamp(rawYaw, -yawLimit, yawLimit) * gazeWeight
		local clampedPitch = math.clamp(rawPitch, PITCH_MIN, PITCH_MAX) * gazeWeight
		springTo(clampedYaw, clampedPitch)
	end

	-- Distribution over head, neck and upper back: fixed shares, so the split never jumps.
	-- (Zones with different splits - 100% head to 30 degrees, then 60/40 - moved the head
	-- back 12 degrees the moment a target crossed 30 degrees.)
	local headYaw = self.currentYaw * 0.50 + shakeYaw * 0.7
	local neckYaw = self.currentYaw * 0.30 + shakeYaw * 0.3
	local spineYaw = self.currentYaw * 0.20 + self.pointChestYaw

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
