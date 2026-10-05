--// EdgeAwareness.lua
-- A Quin knows when it is standing at an edge: the rim of a platform, of an obstacle's top, or
-- of the arena wall's top, with a drop beside it.
-- EdgeAwareness.sense answers "is there a drop within reach of my feet, and which way is in";
-- Main publishes it (the NearEdge attribute: the mind panel says it) and, when the Quin has
-- nothing better to do there (it is waiting, or it is up on the arena wall), walks it in from
-- the rim. A Quin that fights, chases or holds high ground at an edge is left to: an edge is
-- where a platform is defended from.
-- The arena floor has no edge inside the walls: a Quin standing on it is not asked.

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local QuinCore = ReplicatedStorage:WaitForChild("QuinCore")
local CombatConfig = require(QuinCore:WaitForChild("CombatConfig"))

local EdgeAwareness = {}

local CFG = CombatConfig.EdgeAwareness
local DIRECTIONS = 8
local FLOOR_NAME = "ArenaGround"

local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Exclude
params.RespectCanCollide = true

-- nil on open ground; otherwise { inward = unit vector away from the drop, surface = the part
-- it stands on }
function EdgeAwareness.sense(fighter: Model, rootPart: BasePart, humanoid: Humanoid)
	params.FilterDescendantsInstances = { fighter, Workspace:FindFirstChild("QuinServer") }
	local standOffset = humanoid.HipHeight + rootPart.Size.Y / 2
	local under = Workspace:Raycast(rootPart.Position, Vector3.new(0, -(standOffset + 2), 0), params)
	if not under or under.Instance.Name == FLOOR_NAME then
		return nil
	end
	local feet = rootPart.Position - Vector3.new(0, standOffset, 0)
	local toDrop = Vector3.zero
	for i = 0, DIRECTIONS - 1 do
		local angle = i * (2 * math.pi / DIRECTIONS)
		local direction = Vector3.new(math.sin(angle), 0, math.cos(angle))
		local probe = feet + direction * CFG.Reach + Vector3.new(0, 2, 0)
		if not Workspace:Raycast(probe, Vector3.new(0, -(2 + CFG.MinDrop), 0), params) then
			toDrop += direction
		end
	end
	if toDrop.Magnitude < 0.5 then
		return nil -- no drop, or drops all round (a top too small to step in on)
	end
	return { inward = -toDrop.Unit, surface = under.Instance }
end

return EdgeAwareness
