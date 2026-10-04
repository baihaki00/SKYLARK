--// ArmClear.lua
-- Body layer: an elbow or a wrist stays out of the trunk.
-- The clips keep their arms about 0.93-1.09 studs from the line through the trunk. The other
-- layers (the chest squared in a strafe, the arms' follow-through, the tilt) move the chest and
-- the arms a little, and a wrist then sits inside that distance three times as often as in the
-- clip alone (1.0% -> 3.3% of frames at a run). A point that ends up inside CFG.Radius of the
-- trunk's line is turned back out to it. Not during a strike or a guard.
-- (Worked out in the IK Lab, lane D, round 6.)

local QuinCore = script.Parent.Parent.Parent
local CombatConfig = require(QuinCore:WaitForChild("CombatConfig"))

local CFG = CombatConfig.ProceduralLayers.ArmClear
local SIDES = { "Left", "Right" }

-- turn a bone by a rotation given in world space, on top of its current pose
local function rotateWorld(bone: Bone, rotation: CFrame)
	local world = bone.TransformedWorldCFrame.Rotation
	bone.Transform *= world:Inverse() * rotation * world
end

local ArmClear = {}
ArmClear.__index = ArmClear

function ArmClear.new(ghostModel: Model)
	local function bone(name: string): Bone?
		return ghostModel:FindFirstChild("mixamorig:" .. name, true)
	end
	local self = setmetatable({}, ArmClear)
	self.hips, self.chest = bone("Hips"), bone("Spine2")
	self.arms = {}
	for _, side in ipairs(SIDES) do
		local upper, fore, hand = bone(side .. "Arm"), bone(side .. "ForeArm"), bone(side .. "Hand")
		if upper and fore and hand then
			self.arms[side] = { upper = upper, fore = fore, hand = hand }
		end
	end
	return self
end

-- rootCF: the body's frame. weight: 0..1, how free the arms are (0 in a strike or a guard).
-- Call last, on the final arm pose.
function ArmClear:apply(rootCF: CFrame, weight: number)
	if weight <= 0.01 or not (self.hips and self.chest) then return end
	local radius = CFG.Radius
	local low = self.hips.TransformedWorldCFrame.Position - rootCF.UpVector * CFG.BelowHips -- (the top of the thighs)
	local line = self.chest.TransformedWorldCFrame.Position - low
	if line:Dot(line) < 1e-3 then return end

	local function onTrunk(point: Vector3): Vector3
		return low + line * math.clamp((point - low):Dot(line) / line:Dot(line), 0, 1)
	end
	-- Where a point inside the trunk should be instead, or nil if it is outside. `toward`: the
	-- side to come out on. The deeper the point, the more that decides the way out (a point at
	-- the centre has no "nearest side" of its own, and the far side means through the chest).
	local function pushedOut(point: Vector3, toward: Vector3): Vector3?
		local centre = onTrunk(point)
		local out = point - centre
		local depth = out.Magnitude
		if depth >= radius then
			return nil
		end
		out += toward * (radius - depth)
		if out.Magnitude < 0.05 then
			out = toward
		end
		return centre + out.Unit * (depth + (radius - depth) * weight)
	end

	for side, arm in pairs(self.arms) do
		local ownSide = rootCF.RightVector * (side == "Left" and -1 or 1)
		local shoulder = arm.upper.TransformedWorldCFrame.Position
		local elbow = arm.fore.TransformedWorldCFrame.Position
		local clear = pushedOut(elbow, ownSide)
		if clear then
			rotateWorld(arm.upper, CFrame.fromRotationBetweenVectors((elbow - shoulder).Unit, (clear - shoulder).Unit))
			elbow = arm.fore.TransformedWorldCFrame.Position
		end
		-- The wrist comes out on the elbow's side. The forearm's length is fixed, so the point it
		-- is turned toward is not always reached at once: a second pass settles it.
		local elbowSide = elbow - onTrunk(elbow)
		elbowSide = elbowSide.Magnitude > 0.05 and elbowSide.Unit or ownSide
		for _ = 1, 2 do
			local wrist = arm.hand.TransformedWorldCFrame.Position
			clear = pushedOut(wrist, elbowSide)
			if not clear then break end
			rotateWorld(arm.fore, CFrame.fromRotationBetweenVectors((wrist - elbow).Unit, (clear - elbow).Unit))
		end
	end
end

return ArmClear
