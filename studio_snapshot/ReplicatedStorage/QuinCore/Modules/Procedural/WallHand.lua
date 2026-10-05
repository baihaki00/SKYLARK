--// WallHand.lua
-- Body layer: on a wall run, the hand on the wall's side is on the wall.
-- The run clip swings both arms as on the ground; on a wall the near arm reaches out instead and
-- the palm brushes along the surface just ahead of the shoulder, pushing off it as the body
-- strides (a small sway along the wall in time with the stride). The arm is solved as two bones
-- (shoulder - elbow - wrist) with the elbow bent down and back, the fingers turned forward and up
-- along the wall. Out of reach (the wall too far for the arm) it lets the clip have the arm.
-- Client only (ProceduralCombatReactionController), on the final arm pose.

local Workspace = game:GetService("Workspace")

local QuinCore = script.Parent.Parent.Parent
local CombatConfig = require(QuinCore:WaitForChild("CombatConfig"))

local CFG = CombatConfig.ProceduralLayers.WallHand

-- turn a bone by a rotation given in world space, on top of its current pose
local function rotateWorld(bone: Bone, rotation: CFrame)
	local world = bone.TransformedWorldCFrame.Rotation
	bone.Transform *= world:Inverse() * rotation * world
end

local function turnToward(bone: Bone, from: Vector3, to: Vector3, weight: number)
	if from.Magnitude < 1e-4 or to.Magnitude < 1e-4 then return end
	local full = CFrame.fromRotationBetweenVectors(from.Unit, to.Unit)
	rotateWorld(bone, CFrame.new():Lerp(full, weight))
end

local WallHand = {}
WallHand.__index = WallHand

function WallHand.new(ghostModel: Model)
	local function bone(name: string): Bone?
		return ghostModel:FindFirstChild("mixamorig:" .. name, true)
	end
	local self = setmetatable({}, WallHand)
	self.ghostModel = ghostModel
	self.arms = {}
	for _, side in ipairs({ "Left", "Right" }) do
		local upper, fore, hand = bone(side .. "Arm"), bone(side .. "ForeArm"), bone(side .. "Hand")
		if upper and fore and hand then
			self.arms[side] = { upper = upper, fore = fore, hand = hand, finger = bone(side .. "HandMiddle1") }
		end
	end
	self.weight = 0
	self.side = nil
	self.phase = 0
	self.params = RaycastParams.new()
	self.params.FilterType = Enum.RaycastFilterType.Exclude
	return self
end

-- side: "Left" / "Right" while wall-running, else nil. rootCF: the body's frame (its facing).
-- speed: studs/s of the run (the sway keeps time with the stride).
function WallHand:apply(side: string?, rootCF: CFrame, speed: number, dt: number)
	if side then self.side = side end
	local arm = self.side and self.arms[self.side]
	local wanted = side and 1 or 0
	if not arm then self.weight = 0 return end

	local shoulder = arm.upper.TransformedWorldCFrame.Position
	local flatRight = Vector3.new(rootCF.RightVector.X, 0, rootCF.RightVector.Z)
	if flatRight.Magnitude < 1e-3 then return end
	local toWall = flatRight.Unit * (self.side == "Left" and -1 or 1)
	local forward = Vector3.new(rootCF.LookVector.X, 0, rootCF.LookVector.Z).Unit

	-- the wall at shoulder height
	local ignore = { self.ghostModel, Workspace:FindFirstChild("QuinServer") }
	if self.ghostModel.Parent and self.ghostModel.Parent ~= Workspace then table.insert(ignore, self.ghostModel.Parent) end
	self.params.FilterDescendantsInstances = ignore
	local hit = Workspace:Raycast(shoulder, toWall * CFG.Reach, self.params)
	if not hit or math.abs(hit.Normal.Y) > 0.4 then wanted = 0 end

	self.weight += (wanted - self.weight) * (1 - math.exp(-(wanted > self.weight and CFG.BlendIn or CFG.BlendOut) * dt))
	if self.weight < 0.01 or not hit then return end

	local normal = hit.Normal
	local along = (forward - normal * forward:Dot(normal))
	along = along.Magnitude > 1e-3 and along.Unit or forward
	self.phase = (self.phase + dt * CFG.SwayPerStud * math.max(speed, 0)) % (2 * math.pi)
	local target = hit.Position + normal * CFG.PalmOffset + along * (CFG.Ahead + math.sin(self.phase) * CFG.Sway) - Vector3.yAxis * CFG.Drop

	-- two bones: the elbow placed by the triangle's lengths, bent down and back
	local elbow = arm.fore.TransformedWorldCFrame.Position
	local wrist = arm.hand.TransformedWorldCFrame.Position
	local a, b = (elbow - shoulder).Magnitude, (wrist - elbow).Magnitude
	local reach = target - shoulder
	local d = math.clamp(reach.Magnitude, math.abs(a - b) + 0.05, (a + b) * 0.995)
	local dir = reach.Unit
	local pole = -Vector3.yAxis * 1.0 - along * 0.6 + normal * 0.3
	pole -= dir * pole:Dot(dir)
	pole = pole.Magnitude > 1e-3 and pole.Unit or -Vector3.yAxis
	local cosA = math.clamp((a * a + d * d - b * b) / (2 * a * d), -1, 1)
	local newElbow = shoulder + dir * (a * cosA) + pole * (a * math.sqrt(1 - cosA * cosA))
	local w = self.weight
	turnToward(arm.upper, elbow - shoulder, newElbow - shoulder, w)
	elbow = arm.fore.TransformedWorldCFrame.Position
	wrist = arm.hand.TransformedWorldCFrame.Position
	turnToward(arm.fore, wrist - elbow, (shoulder + dir * d) - elbow, w)

	-- the fingers forward and up along the wall
	if arm.finger then
		wrist = arm.hand.TransformedWorldCFrame.Position
		local fingers = arm.finger.TransformedWorldCFrame.Position - wrist
		turnToward(arm.hand, fingers, along * CFG.FingersForward + Vector3.yAxis * CFG.FingersUp, w)
	end
end

return WallHand
