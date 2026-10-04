--// Breath.lua
-- Body layer: the chest rises and falls with how spent the Quin is.
-- The idle clips sway the chest 2.5-5 degrees over a loop of 2-8 s whatever state the Quin is
-- in. This adds its breathing on top: slow and shallow when it is fresh, fast and deep as its
-- energy runs out, so a spent Quin is seen to heave. It fades out as the body picks up speed
-- (the run clip owns the torso) and while it strikes, guards or is thrown.
-- The upper spine takes the breath in two parts; the neck gives half of it back so the head
-- stays level.

local QuinCore = script.Parent.Parent.Parent
local CombatConfig = require(QuinCore:WaitForChild("CombatConfig"))

local CFG = CombatConfig.ProceduralLayers.Breath
local TAU = 2 * math.pi

-- turn a bone by a rotation given in world space, on top of its current pose
local function rotateWorld(bone: Bone, rotation: CFrame)
	local world = bone.TransformedWorldCFrame.Rotation
	bone.Transform *= world:Inverse() * rotation * world
end

local Breath = {}
Breath.__index = Breath

function Breath.new(ghostModel: Model, seed: number)
	local function bone(name: string): Bone?
		return ghostModel:FindFirstChild("mixamorig:" .. name, true)
	end
	local self = setmetatable({}, Breath)
	self.spine = { bone("Spine1"), bone("Spine2") }
	self.neck = bone("Neck")
	self.complete = #self.spine == 2 and self.neck ~= nil
	self.phase = (seed % 1000) / 1000 * TAU -- (each Quin on its own beat)
	self.exertion = 0 -- 0 = fresh, 1 = spent (eased: breathing does not jump with a number)
	self.weight = 0
	return self
end

-- rootCF: the body's frame. energy: 0..1 of its energy left. speed: studs/s over the ground.
-- calm: 0..1, 0 while it strikes, guards or is thrown. on: the layer's switch.
function Breath:apply(rootCF: CFrame, energy: number, speed: number, calm: number, on: boolean, dt: number)
	if not self.complete then return end
	self.exertion += ((1 - math.clamp(energy, 0, 1)) - self.exertion) * (1 - math.exp(-CFG.ExertionRate * dt))
	local wanted = on and calm * (1 - math.clamp(speed / CFG.FadeSpeed, 0, 1)) or 0
	self.weight += (wanted - self.weight) * (1 - math.exp(-4 * dt))
	self.phase = (self.phase + TAU * (CFG.RestHz + (CFG.SpentHz - CFG.RestHz) * self.exertion) * dt) % TAU
	if self.weight < 0.01 then return end

	local depth = math.rad(CFG.RestDegrees + (CFG.SpentDegrees - CFG.RestDegrees) * self.exertion)
	local angle = math.sin(self.phase) * depth * self.weight -- + = the chest lifts (breathing in)
	local across = rootCF.RightVector
	local share = CFrame.fromAxisAngle(across, angle / #self.spine)
	for _, spineBone in ipairs(self.spine) do
		rotateWorld(spineBone, share)
	end
	rotateWorld(self.neck, CFrame.fromAxisAngle(across, -angle * 0.5))
end

return Breath
