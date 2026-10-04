--// PlatformCatalogue.lua
-- The raised surfaces of the arena a Quin can stand on, and how each can be reached.
--
-- Obstacles are all named "OB" whatever they are; what matters to a Quin is geometry. A part is
-- a platform when its top is level and at least MIN_TOP_WIDTH wide. How a Quin gets onto it
-- depends only on how far the top is above the floor the Quin is standing on (a Quin is 8 studs
-- tall; values in CombatConfig / TraversalModule.Config):
--   Level           within 0.5 studs            walk
--   Step            up to 2.2                    walk (the Humanoid steps up)
--   Vault           up to 6.8                    hop / vault in stride
--   Jump            up to Jump_MaxReach (12)     a jump: apex = height + 2, taken 6-27 studs
--                                                from the edge depending on speed
--                                                (TraversalModule.solveJumpOnto)
--   ProjectileJump  anything higher              only a projectile jump gets there
--   Below           the platform is lower        drop / dive down
-- A platform whose underside is 9+ studs above the floor is floating: a Quin can pass under it.

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local QuinCore = ReplicatedStorage:WaitForChild("QuinCore")
local CombatConfig = require(QuinCore:WaitForChild("CombatConfig"))
local SpatialModule = require(QuinCore:WaitForChild("Modules"):WaitForChild("SpatialModule"))
local TraversalModule = require(QuinCore:WaitForChild("Modules"):WaitForChild("TraversalModule"))

local PlatformCatalogue = {}

PlatformCatalogue.Access = {
	Level = "Level", Step = "Step", Vault = "Vault", Jump = "Jump",
	ProjectileJump = "ProjectileJump", Below = "Below",
}

local OBSTACLE_NAME = "OB"
local MIN_TOP_WIDTH = 5 -- studs: narrower tops (walls, pillars, rails) are not places to stand
local UNDERPASS_CLEARANCE = 9 -- studs under a platform for a Quin to pass

local platforms = nil
local arenaFloorY = 0

-- Which of the part's own axes points up, and the two that span its top
local function topFrame(part)
	local frame = part.CFrame
	local axes = {
		{ dir = frame.RightVector, half = part.Size.X / 2 },
		{ dir = frame.UpVector, half = part.Size.Y / 2 },
		{ dir = frame.LookVector, half = part.Size.Z / 2 },
	}
	for index, axis in ipairs(axes) do
		if math.abs(axis.dir.Y) > 0.95 then
			local a = axes[index % 3 + 1]
			local b = axes[(index + 1) % 3 + 1]
			return axis.half, a, b
		end
	end
	return nil -- tilted: not a level top
end

local function build()
	platforms = {}
	local bounds = SpatialModule.getArenaBounds()
	local arenaRoot = Workspace:FindFirstChild("argoniaonion")
	local ground = arenaRoot and arenaRoot:FindFirstChild("ArenaGround", true)
	arenaFloorY = ground and (ground.Position.Y + ground.Size.Y / 2) or 0

	for _, part in ipairs(Workspace:GetDescendants()) do
		if part:IsA("BasePart") and part.Name == OBSTACLE_NAME and part.CanCollide
			and math.abs(part.Position.X - bounds.center.X) <= bounds.halfX
			and math.abs(part.Position.Z - bounds.center.Z) <= bounds.halfZ then
			local halfHeight, a, b = topFrame(part)
			if halfHeight and math.min(a.half, b.half) * 2 >= MIN_TOP_WIDTH then
				local topY = part.Position.Y + halfHeight
				local bottomY = part.Position.Y - halfHeight
				table.insert(platforms, {
					part = part,
					center = Vector3.new(part.Position.X, topY, part.Position.Z),
					topY = topY,
					bottomY = bottomY,
					axisA = Vector3.new(a.dir.X, 0, a.dir.Z).Unit, halfA = a.half,
					axisB = Vector3.new(b.dir.X, 0, b.dir.Z).Unit, halfB = b.half,
					heightAboveArenaFloor = topY - arenaFloorY,
					isFloating = bottomY - arenaFloorY >= UNDERPASS_CLEARANCE,
				})
			end
		end
	end
end

-- Every platform in the arena (scanned once; the arena is static)
function PlatformCatalogue.all()
	if not platforms then build() end
	return platforms
end

-- Forget the scan (call after the arena geometry changes)
function PlatformCatalogue.refresh()
	platforms = nil
end

-- How a Quin standing on a floor at floorY gets onto this platform
function PlatformCatalogue.accessFrom(platform, floorY)
	local rise = platform.topY - floorY
	if rise < -2 then return PlatformCatalogue.Access.Below end
	if rise <= 0.5 then return PlatformCatalogue.Access.Level end
	if rise <= TraversalModule.Config.StepHeight then return PlatformCatalogue.Access.Step end
	if rise <= TraversalModule.Config.VaultHeight then return PlatformCatalogue.Access.Vault end
	if rise <= (CombatConfig.Jump_MaxReach or 12) then return PlatformCatalogue.Access.Jump end
	return PlatformCatalogue.Access.ProjectileJump
end

-- The point on the platform's top nearest to `position`, kept `inset` studs in from the edge
function PlatformCatalogue.nearestTopPoint(platform, position, inset)
	inset = inset or 0
	local offset = position - platform.center
	local a = math.clamp(offset:Dot(platform.axisA), -math.max(platform.halfA - inset, 0), math.max(platform.halfA - inset, 0))
	local b = math.clamp(offset:Dot(platform.axisB), -math.max(platform.halfB - inset, 0), math.max(platform.halfB - inset, 0))
	return platform.center + platform.axisA * a + platform.axisB * b
end

-- How far past the rim a jump from `from` over `edge` should come down: toward the middle of the
-- top, not on its lip. (Aimed at the nearest point of the rim, every jump onto a platform landed
-- on its edge, and Quins gathered along the edges as if they were snap points.)
function PlatformCatalogue.landingDepth(platform, edge, from)
	local lip = TraversalModule.Config.LandingMargin
	local approach = Vector3.new(edge.X - from.X, 0, edge.Z - from.Z)
	if approach.Magnitude < 0.1 then return lip end
	local toMiddle = Vector3.new(platform.center.X - edge.X, 0, platform.center.Z - edge.Z):Dot(approach.Unit)
	return math.clamp(toMiddle, lip, CombatConfig.Jump_LandingDepthMax or 8)
end

-- The platform a position is standing on (its top is right under the position), or nil
function PlatformCatalogue.under(position, maxDrop)
	maxDrop = maxDrop or 8
	local best = nil
	for _, platform in ipairs(PlatformCatalogue.all()) do
		local offset = position - platform.center
		if math.abs(offset:Dot(platform.axisA)) <= platform.halfA and math.abs(offset:Dot(platform.axisB)) <= platform.halfB then
			local above = position.Y - platform.topY
			if above >= -0.5 and above <= maxDrop and (not best or platform.topY > best.topY) then
				best = platform
			end
		end
	end
	return best
end

-- Platforms whose top comes within `range` studs (flat) of the position: { platform, point, distance }
function PlatformCatalogue.near(position, range)
	local found = {}
	for _, platform in ipairs(PlatformCatalogue.all()) do
		local point = PlatformCatalogue.nearestTopPoint(platform, position, 0)
		local distance = Vector3.new(point.X - position.X, 0, point.Z - position.Z).Magnitude
		if distance <= range then
			table.insert(found, { platform = platform, point = point, distance = distance })
		end
	end
	return found
end

return PlatformCatalogue
