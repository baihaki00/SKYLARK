--// SquareUp.lua
-- Body layer: the chest stays to the front in a strafe.
-- The strafe clips are "move 90 degrees left or right, look forward", but they walk along the
-- travel with the hips about 65 degrees toward it and the chest about 42, only the head to the
-- front. This turns the chest back to where the Quin faces, by as much as the shoulders are
-- measured off it while a strafe clip plays, and leaves the head where the clip has it.
-- The average turn is followed, not the pose of the moment: the shoulders keep their swing.
-- (Worked out in the IK Lab, lane D: 44 degrees off the front down to under 10.)

local QuinCore = script.Parent.Parent.Parent
local CombatConfig = require(QuinCore:WaitForChild("CombatConfig"))
local AnimationConfig = require(QuinCore:WaitForChild("AnimationConfig"))

local CFG = CombatConfig.ProceduralLayers.SquareUp

-- asset number -> true for the clips that turn the chest toward the travel
local turnedClips = {}
for _, path in ipairs(CFG.Clips) do
	local entry = AnimationConfig.get(path)
	local id = entry and entry.id and string.match(entry.id, "%d+$")
	if id then
		turnedClips[id] = true
	end
end

-- turn a bone by a rotation given in world space, on top of its current pose
local function rotateWorld(bone: Bone, rotation: CFrame)
	local world = bone.TransformedWorldCFrame.Rotation
	bone.Transform *= world:Inverse() * rotation * world
end

local SquareUp = {}
SquareUp.__index = SquareUp

-- Running sideways (owner 2026-10-29, the strafe run): the head staring 90 degrees off the way
-- the body runs looked goofy. Fast and sideways, the chest stays turned into the run as the clip
-- has it (no square-up) and the head looks at most Look_RunMaxOffTravel off the travel
-- (LookController). 0 = walking or moving along the facing, 1 = sideways at a run.
-- Workspace RunLeadOff = true: square to the front at every pace, as before.
function SquareUp.runLead(rootPart: BasePart): number
	if workspace:GetAttribute("RunLeadOff") == true or CombatConfig.Look_RunLead == false then return 0 end
	local v = rootPart.AssemblyLinearVelocity
	local flat = Vector3.new(v.X, 0, v.Z)
	local speed = flat.Magnitude
	if speed < 1 then return 0 end
	local look = rootPart.CFrame.LookVector
	local flatLook = Vector3.new(look.X, 0, look.Z)
	if flatLook.Magnitude < 0.01 then return 0 end
	local along = math.abs(flat.Unit:Dot(flatLook.Unit))
	local function ss(a, b, x) local t = math.clamp((x - a) / (b - a), 0, 1) return t * t * (3 - 2 * t) end
	return ss(CombatConfig.Look_RunLeadFrom or 10, CombatConfig.Look_RunLeadFull or 15, speed) * (1 - ss(0.5, 0.8, along))
end

function SquareUp.new(ghostModel: Model, humanoid: Humanoid?)
	local function bone(name: string): Bone?
		return ghostModel:FindFirstChild("mixamorig:" .. name, true)
	end
	local self = setmetatable({}, SquareUp)
	self.humanoid = humanoid
	self.spine = { bone("Spine"), bone("Spine1"), bone("Spine2") } -- the twist is shared, so no one joint takes it
	self.neck = bone("Neck")
	self.leftShoulder, self.rightShoulder = bone("LeftArm"), bone("RightArm")
	self.complete = #self.spine == 3 and self.neck ~= nil and self.leftShoulder ~= nil and self.rightShoulder ~= nil
	self.share = 0 -- how much of the body is in a strafe clip this step (0..1), for other layers to read
	self.turn = 0 -- how far the clips turn the chest off the front, averaged over a stride (radians, + = left)
	self.applied = 0 -- the twist put on the spine this step (radians), for readouts
	return self
end

-- How much of the body is in a strafe clip: 0 = none, 1 = at least CFG.FullAt of its weight
function SquareUp:strafeShare(): number
	local animator = self.animator
	if not animator then
		animator = self.humanoid and self.humanoid:FindFirstChildOfClass("Animator")
		self.animator = animator
		if not animator then return 0 end
	end
	local weight = 0
	for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
		local id = track.Animation and string.match(track.Animation.AnimationId, "%d+$")
		if id and turnedClips[id] then
			weight += track.WeightCurrent
		end
	end
	return math.clamp(weight / CFG.FullAt, 0, 1)
end

-- rootCF: where the Quin faces. on: the layer's switch (off, the twist eases out). Call once per
-- fresh animation step, before anything else turns the spine.
-- runLead: SquareUp.runLead of the body (the chest is left turned into a sideways run).
function SquareUp:apply(rootCF: CFrame, on: boolean, dt: number, runLead: number?)
	if not self.complete then return end
	local turned = 0
	local share = self:strafeShare()
	self.share = share
	share *= 1 - (runLead or 0)
	if on and share > 0 then
		local across = rootCF:VectorToObjectSpace(
			self.rightShoulder.TransformedWorldCFrame.Position - self.leftShoulder.TransformedWorldCFrame.Position)
		local facing = Vector3.yAxis:Cross(across)
		turned = math.atan2(-facing.X, -facing.Z) * share
	end
	self.turn += (turned - self.turn) * (1 - math.exp(-CFG.Rate * dt))

	local limit = math.rad(CFG.MaxTwist)
	local twist = math.clamp(-self.turn * CFG.Gain, -limit, limit)
	if math.abs(twist) < 1e-3 then
		self.applied = 0
		return
	end
	self.applied = twist
	local up = rootCF.UpVector
	local share3 = CFrame.fromAxisAngle(up, twist / #self.spine)
	for _, spineBone in ipairs(self.spine) do
		rotateWorld(spineBone, share3)
	end
	-- (the head rode round with the chest: the neck takes that turn back out)
	rotateWorld(self.neck, CFrame.fromAxisAngle(up, -twist))
end

return SquareUp
