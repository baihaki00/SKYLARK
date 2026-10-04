--// HeadroomAwareness.lua
-- A Quin knows when it is under something lower than itself.
-- It is 8 studs tall but its collision ends lower, so it can end up under a ledge, a beam or a
-- low platform (pushed, knocked, or following a target in) with its head inside the part, and
-- where the gap is lower still the part tips its body over. It cannot stand, wait or fight
-- there. HeadroomAwareness.exit answers "is there room to stand here, and if not, where is the
-- nearest spot with room"; Main sends the Quin there before its state does anything else.
-- (Passing under a low bar at a run is the slide's job, ChaseState: a sliding Quin is not asked.)

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local QuinCore = ReplicatedStorage:WaitForChild("QuinCore")
local CombatConfig = require(QuinCore:WaitForChild("CombatConfig"))
local TraversalModule = require(QuinCore:WaitForChild("Modules"):WaitForChild("TraversalModule"))

local HeadroomAwareness = {}

local CFG = CombatConfig.Headroom
local DIRECTIONS = 8

local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Exclude
params.RespectCanCollide = true

-- Room to stand at (x, z)? `feetY`: the height the Quin's feet are at now.
-- Returns roomy, floorY (nil where there is no floor near its own level: a drop, a wall).
local function standingRoom(x: number, z: number, feetY: number): (boolean, number?)
	local floor = Workspace:Raycast(Vector3.new(x, feetY + 2, z), Vector3.new(0, -(2 + CFG.MaxStep), 0), params)
	if not floor then
		return false, nil
	end
	local height = TraversalModule.Config.BodyHeight + CFG.Margin
	local ceiling = Workspace:Raycast(floor.Position + Vector3.new(0, 0.3, 0), Vector3.new(0, height, 0), params)
	return ceiling == nil, floor.Position.Y
end

-- nil when the Quin has room to stand where it is; otherwise the nearest point it can stand at.
function HeadroomAwareness.exit(fighter: Model, rootPart: BasePart, humanoid: Humanoid): Vector3?
	params.FilterDescendantsInstances = { fighter, Workspace:FindFirstChild("QuinServer") }
	local position = rootPart.Position
	local feetY = position.Y - (humanoid.HipHeight + rootPart.Size.Y / 2)
	if standingRoom(position.X, position.Z, feetY) then
		return nil
	end
	-- Rings outward, the way it is facing first: the nearest spot with a floor and room over it
	local look = rootPart.CFrame.LookVector
	local base = math.atan2(look.X, look.Z)
	for distance = CFG.SearchStep, CFG.SearchRadius, CFG.SearchStep do
		for i = 0, DIRECTIONS - 1 do
			local angle = base + i * (2 * math.pi / DIRECTIONS)
			local x, z = position.X + math.sin(angle) * distance, position.Z + math.cos(angle) * distance
			local roomy, floorY = standingRoom(x, z, feetY)
			if roomy and floorY then
				return Vector3.new(x, position.Y + (floorY - feetY), z)
			end
		end
	end
	-- nowhere found: back the way it came
	return position - Vector3.new(look.X, 0, look.Z).Unit * CFG.SearchRadius
end

return HeadroomAwareness
