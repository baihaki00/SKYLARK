--// KneeOverToe.lua
-- Body layer: a knee points where the foot under it points, give or take.
-- The clips let the knee turn in of the foot (measured in a 16v16: more than 5 degrees inside on
-- 36-60% of planted frames, by 17-28 degrees on average: "shy legs"). A knee that is too far in
-- or out of its foot is swung round the hip-ankle line, so the hip and the ankle stay exactly
-- where they are, and the foot is turned back by the same amount so it keeps its heading.
-- Only near the ground, and eased in and out: in the air a running foot points down and back,
-- its "direction" swings through half a turn, and a knee held to it is thrown round with it.
-- (Worked out in the IK Lab, lane D, rounds 7 and 7b.)

local QuinCore = script.Parent.Parent.Parent
local CombatConfig = require(QuinCore:WaitForChild("CombatConfig"))

local CFG = CombatConfig.ProceduralLayers.KneeOverToe
local FLAT = Vector3.new(1, 0, 1)
local SIDES = { "Left", "Right" }

-- turn a bone by a rotation given in world space, on top of its current pose
local function rotateWorld(bone: Bone, rotation: CFrame)
	local world = bone.TransformedWorldCFrame.Rotation
	bone.Transform *= world:Inverse() * rotation * world
end

local KneeOverToe = {}
KneeOverToe.__index = KneeOverToe

function KneeOverToe.new(ghostModel: Model)
	local self = setmetatable({}, KneeOverToe)
	self.legs = {}
	self.turn = { Left = 0, Right = 0 } -- how far each knee is swung to stay over its foot (radians, + = to the left)
	for _, side in ipairs(SIDES) do
		local function bone(name: string): Bone?
			return ghostModel:FindFirstChild("mixamorig:" .. side .. name, true)
		end
		local leg = { thigh = bone("UpLeg"), shin = bone("Leg"), foot = bone("Foot"), toe = bone("ToeBase") }
		if leg.thigh and leg.shin and leg.foot and leg.toe then
			self.legs[side] = leg
		end
	end
	return self
end

-- The swing this knee needs now (radians, + = to the left); 0 where the rule has nothing to say
local function wantedTurn(side: string, hip: Vector3, knee: Vector3, ankle: Vector3, toe: Vector3, lift: number): number
	local grounded = 1 - math.clamp((lift - CFG.FullLift) / (CFG.FadeLift - CFG.FullLift), 0, 1)
	local line = ankle - hip
	if grounded <= 0 or line.Magnitude < 1e-3 or -line.Unit.Y < 0.5 then
		return 0 -- in the air, or a leg lying more across than down (a kick, a slide)
	end
	local kneeOut = ((knee - hip) - line * ((knee - hip):Dot(line) / line:Dot(line))) * FLAT
	local toes = (toe - ankle) * FLAT
	if kneeOut.Magnitude < 0.05 or toes.Magnitude < 0.2 then
		return 0 -- a straight leg, or a foot pointing down: no direction to compare
	end
	local turn = math.atan2(toes.Unit:Cross(kneeOut.Unit).Y, toes.Unit:Dot(kneeOut.Unit)) -- + = knee to the left of the foot
	local inward = side == "Left" and -turn or turn
	local excess = 0
	if inward > math.rad(CFG.InMax) then
		excess = inward - math.rad(CFG.InMax)
	elseif inward < -math.rad(CFG.OutMax) then
		excess = inward + math.rad(CFG.OutMax)
	end
	local limit = math.rad(CFG.MaxTurn)
	return math.clamp(side == "Left" and excess or -excess, -limit, limit) * grounded
end

-- footLift: { Left = studs the clip has the foot above its ground, Right = ... }, nil for a foot
-- with no ground under it. on: the layer's switch. Call after the legs are solved.
function KneeOverToe:apply(footLift, on: boolean, dt: number)
	for _, side in ipairs(SIDES) do
		local leg = self.legs[side]
		if leg then
			local hip = leg.thigh.TransformedWorldCFrame.Position
			local ankle = leg.foot.TransformedWorldCFrame.Position
			local lift = footLift[side]
			local wanted = 0
			if on and lift then
				wanted = wantedTurn(side, hip, leg.shin.TransformedWorldCFrame.Position, ankle, leg.toe.TransformedWorldCFrame.Position, lift)
			end
			local turn = self.turn[side] + (wanted - self.turn[side]) * (1 - math.exp(-CFG.Rate * dt))
			self.turn[side] = turn
			if math.abs(turn) > 1e-3 and (hip - ankle).Magnitude > 1e-3 then
				local swing = CFrame.fromAxisAngle((hip - ankle).Unit, turn)
				rotateWorld(leg.thigh, swing)
				rotateWorld(leg.foot, swing:Inverse())
			end
		end
	end
end

return KneeOverToe
