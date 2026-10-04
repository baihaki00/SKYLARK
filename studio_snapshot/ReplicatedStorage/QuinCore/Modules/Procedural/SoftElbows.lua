--// SoftElbows.lua
-- Body layer: an elbow is never quite straight.
-- The run and strafe clips swing the arms dead straight on about 5% of frames (measured in a
-- 16v16), which reads as a stick. An elbow straighter than CFG.MinBend is bent to it, about the
-- way that elbow bends. Not during a strike or a guard: a punch is meant to land on a straight arm.
-- (Worked out in the IK Lab, lane D, round 7.)

local QuinCore = script.Parent.Parent.Parent
local CombatConfig = require(QuinCore:WaitForChild("CombatConfig"))

local CFG = CombatConfig.ProceduralLayers.SoftElbows
local SIDES = { "Left", "Right" }
local LEARN_BEND = math.rad(25) -- an elbow bent at least this much shows which way it bends

-- turn a bone by a rotation given in world space, on top of its current pose
local function rotateWorld(bone: Bone, rotation: CFrame)
	local world = bone.TransformedWorldCFrame.Rotation
	bone.Transform *= world:Inverse() * rotation * world
end

local SoftElbows = {}
SoftElbows.__index = SoftElbows

function SoftElbows.new(ghostModel: Model)
	local self = setmetatable({}, SoftElbows)
	self.arms = {}
	for _, side in ipairs(SIDES) do
		local function bone(name: string): Bone?
			return ghostModel:FindFirstChild("mixamorig:" .. side .. name, true)
		end
		local upper, fore, hand = bone("Arm"), bone("ForeArm"), bone("Hand")
		if upper and fore and hand then
			-- hinge: the elbow's axis in the upper arm's own frame (an elbow hinges on the upper arm).
			-- Learned from the clips: whenever the elbow is clearly bent, the axis is the one square
			-- to both halves of the arm. (The rest pose of these rigs is not arms-out-to-the-sides,
			-- so it cannot be read off the bind pose.) Until it is known the elbow is left alone.
			self.arms[side] = { upper = upper, fore = fore, hand = hand, hinge = nil }
		end
	end
	return self
end

-- weight: 0..1, how free the arms are (0 in a strike or a guard). Call on the final arm pose.
function SoftElbows:apply(weight: number)
	if weight <= 0.01 then return end
	local minBend = math.rad(CFG.MinBend)
	for _, arm in pairs(self.arms) do
		local elbow = arm.fore.TransformedWorldCFrame.Position
		local upperArm = elbow - arm.upper.TransformedWorldCFrame.Position
		local foreArm = arm.hand.TransformedWorldCFrame.Position - elbow
		if upperArm.Magnitude > 1e-3 and foreArm.Magnitude > 1e-3 then
			local bend = math.acos(math.clamp(upperArm.Unit:Dot(foreArm.Unit), -1, 1)) -- 0 = straight
			local upperW = arm.upper.TransformedWorldCFrame
			if bend > LEARN_BEND then
				local seen = upperW:VectorToObjectSpace(upperArm.Unit:Cross(foreArm.Unit).Unit)
				arm.hinge = arm.hinge and arm.hinge:Lerp(seen, 0.05).Unit or seen
			elseif bend < minBend and arm.hinge then
				rotateWorld(arm.fore, CFrame.fromAxisAngle(upperW:VectorToWorldSpace(arm.hinge), (minBend - bend) * weight))
			end
		end
	end
end

return SoftElbows
