--// ProjectileJumpState/Flight.lua
-- The flight's geometry: the jump's tuning (Config), the aim at a moving target, the arc's lowest
-- point and whether its curve is clear, the room the arena leaves along a direction, a strafe
-- side, and keeping the flight inside the arena and off platform faces.
-- (Moved out of ProjectileJumpState as it was: QuinCore audit 2026-10-27, step 7.)

local DebugDraw = require(game:GetService("ReplicatedStorage"):WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("DebugDraw"))
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local CombatConfig = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("CombatConfig"))
local SpatialModule = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("SpatialModule"))

local Flight = {}

local Config = {
	JumpPowerMin = 350,
	JumpPowerMax = 400,
	DashExecuteTimeMin = 2.0,
	DashExecuteTimeMax = 2.5,

	MultiJumpPowerMin = 200,
	MultiJumpPowerMax = 250,
	MultiJumpGapTimeMin = 0.75,
	MultiJumpGapTimeMax = 1.25,
	MultiJumpDashTimeMin = 0.75,
	MultiJumpDashTimeMax = 1.25,

	SlamSpeed = CombatConfig.ProjectileJump_SlamSpeed or 480,
	StrafeDistanceMin = 150,
	StrafeDistanceMax = 300,
	CurveAggressiveness = 1,
	ArcSpeedXZ = 100,

	MultiJumpForwardSpeedMin = 100,
	MultiJumpForwardSpeedMax = 200,
	MultiJumpSideSpeedMin = -200,
	MultiJumpSideSpeedMax = 200,

	ComboGapTimeMin = 0.3,
	ComboGapTimeMax = 0.6,

	-- New Bezier Settings
	BezierArcHeightBase = 50,
	BezierLateralBendBase = 40,
	SlamSpeedMultiplier = 1.15
}

local function getFloat(min, max)
	return min + math.random() * (max - min)
end

-- Math Helpers for Style 5
local function calculateLowestY(Y0, Y2, ArcHeight)
	if ArcHeight == 0 then return math.min(Y0, Y2) end
	local tLowest = 0.5 - (Y0 - Y2) / (4 * ArcHeight)
	if tLowest >= 0.0 and tLowest <= 1.0 then
		local midY = (Y0 + Y2) / 2
		local P1Y = midY + ArcHeight
		return ((1 - tLowest)^2 * Y0) + (2 * (1 - tLowest) * tLowest * P1Y) + (tLowest^2 * Y2)
	else
		return math.min(Y0, Y2)
	end
end

local function isCurveSafe(P0, P1, P2, fighter, target)
	local segments = 10
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = {fighter, target}

	local prevPoint = P0
	for i = 1, segments do
		local t = i / segments
		local nextPoint = ((1 - t)^2 * P0) + (2 * (1 - t) * t * P1) + (t^2 * P2)
		local dir = nextPoint - prevPoint
		local dist = dir.Magnitude
		if dist > 0.01 then
			local hit = workspace:Spherecast(prevPoint, 2, dir.Unit * dist, params)
			if hit then return false end
		end
		prevPoint = nextPoint
	end
	return true
end

-- scatterAngle is rolled once per jump: re-rolling it on every update moved the landing spot
-- 5-25 studs each tick, so a diving Quin kept re-aiming between scattered points near the ground.
local function calculateCombatAimPoint(rootPart, targetHRP, dashSpeed, humanoid, scatterAngle, precise)
	local targetPos = targetHRP.Position
	local targetVel = targetHRP.AssemblyLinearVelocity
	local flatTargetVel = Vector3.new(targetVel.X, 0, targetVel.Z)

	-- Dynamic arrival time for lead interception
	local currentDist = (targetPos - rootPart.Position).Magnitude
	local speed = dashSpeed or Config.SlamSpeed or 500
	local tArrival = math.clamp(currentDist / speed, 0.04, 0.40)

	-- First-order lead position (where the moving target will be upon dive arrival)
	local leadPos = targetPos + (flatTargetVel * tArrival)

	-- Approach vector on XZ plane
	local toLeadFlat = Vector3.new(leadPos.X - rootPart.Position.X, 0, leadPos.Z - rootPart.Position.Z)
	local approachDir = toLeadFlat.Magnitude > 0.01 and toLeadFlat.Unit or rootPart.CFrame.LookVector

	-- Arena floor altitude at the landing point
	local groundY = targetPos.Y
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = {rootPart.Parent, targetHRP.Parent}
	-- (all the way down: a 35-stud ray found nothing under an airborne target or a tall
	-- platform, the aim fell back to the target's own height and the dive went up at it)
	rayParams.FilterDescendantsInstances = {rootPart.Parent, targetHRP.Parent, Workspace:FindFirstChild("QuinServer")}
	rayParams.RespectCanCollide = true
	local floorRay = DebugDraw.raycast(rootPart, leadPos + Vector3.new(0, 10, 0), Vector3.new(0, -1000, 0), rayParams)
	if floorRay then
		groundY = floorRay.Position.Y + (humanoid and humanoid.HipHeight or 2.0) + (rootPart.Size.Y / 2)
	end

	-- Striking landing spot with organic clamped trajectory scatter (Sections 42 & 43)
	-- smashes are not 100% laser-guided; landing has a 5 to 25 studs scatter (clamped strictly <= 30)
	local jumpDist = (leadPos - rootPart.Position).Magnitude
	local scatterDist = math.clamp(jumpDist * 0.12, 5.0, 25.0)
	local randAngle = scatterAngle or (math.random() * math.pi * 2)
	local scatterOffset = Vector3.new(math.cos(randAngle), 0, math.sin(randAngle)) * scatterDist

	local landingSpot = leadPos - (approachDir * 4.5) + scatterOffset
	if precise then
		landingSpot = leadPos -- a jump to a spot (a platform) lands on the spot
	end
	landingSpot = Vector3.new(landingSpot.X, groundY, landingSpot.Z)

	return landingSpot, approachDir, groundY
end

-- Arena containment. Mid-air strafes cover 150-300 studs and the jump drifts another couple of
-- hundred; from most of the arena that carried the jumper over the wall, where the out-of-bounds
-- safety net teleported it back to the centre.
local ARENA_MARGIN = 30

-- Distance available along flatDir before the arena margin
local function arenaRoom(position, flatDir)
	local bounds = SpatialModule.getArenaBounds()
	local room = math.huge
	local function limit(p, d, center, half)
		if d > 0.001 then
			room = math.min(room, (center + half - ARENA_MARGIN - p) / d)
		elseif d < -0.001 then
			room = math.min(room, (center - half + ARENA_MARGIN - p) / d)
		end
	end
	limit(position.X, flatDir.X, bounds.center.X, bounds.halfX)
	limit(position.Z, flatDir.Z, bounds.center.Z, bounds.halfZ)
	return math.max(room, 0)
end

-- Sideways strafe: a random side, flipped and shortened as needed to stay inside the arena
local function pickStrafe(rootPart)
	local right = rootPart.CFrame.RightVector
	local dir = Vector3.new(right.X, 0, right.Z)
	dir = (dir.Magnitude > 0.01 and dir.Unit or Vector3.new(1, 0, 0)) * (math.random() > 0.5 and 1 or -1)
	local dist = getFloat(Config.StrafeDistanceMin, Config.StrafeDistanceMax)
	local room = arenaRoom(rootPart.Position, dir)
	if room < dist then
		local otherRoom = arenaRoom(rootPart.Position, -dir)
		if otherRoom > room then
			dir, room = -dir, otherRoom
		end
	end
	return dir, math.min(dist, room)
end

-- Removes the outward part of a horizontal velocity once the position is past the margin
local function containVelocity(position, velocity)
	local bounds = SpatialModule.getArenaBounds()
	local x, z = velocity.X, velocity.Z
	local dx, dz = position.X - bounds.center.X, position.Z - bounds.center.Z
	if math.abs(dx) > bounds.halfX - ARENA_MARGIN and dx * x > 0 then x = 0 end
	if math.abs(dz) > bounds.halfZ - ARENA_MARGIN and dz * z > 0 then z = 0 end
	return Vector3.new(x, velocity.Y, z)
end

-- Platforms in the flight's way (owner 2026-10-27: jumps flew into the underside of floating
-- platforms, 60-200 studs up). Looked for a quarter second ahead along the flight: under a
-- platform the climb stops and the body swerves toward that platform's nearest edge; a side
-- face ahead is glided along. Tops are landings and are left alone. (CombatConfig
-- ProjectileJump_AvoidPlatforms = false switches it off.)
local avoidParams
local function avoidPlatforms(position, velocity)
	if CombatConfig.ProjectileJump_AvoidPlatforms == false or velocity.Magnitude < 20 then return velocity end
	local world = workspace:FindFirstChild("argoniaonion")
	if not world then return velocity end
	if not avoidParams then
		avoidParams = RaycastParams.new()
		avoidParams.FilterType = Enum.RaycastFilterType.Include
	end
	avoidParams.FilterDescendantsInstances = { world }
	local ahead = velocity * (CombatConfig.ProjectileJump_AvoidLookahead or 0.25)
	if ahead.Magnitude > 150 then ahead = ahead.Unit * 150 end
	local hit = workspace:Spherecast(position + Vector3.new(0, 2, 0), 2.5, ahead, avoidParams)
	if not hit or not hit.Instance.CanCollide then return velocity end
	local n = hit.Normal
	if n.Y > 0.5 then return velocity end -- a top: somewhere to land
	if n.Y < -0.5 then
		-- an underside: no more climbing, out toward the nearest edge of the part
		local part = hit.Instance
		local flatSpeed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
		local escape = Vector3.zero
		if part:IsA("BasePart") then
			local localPos = part.CFrame:PointToObjectSpace(position)
			local half = part.Size / 2
			local toX = half.X - math.abs(localPos.X)
			local toZ = half.Z - math.abs(localPos.Z)
			local axis = toX < toZ and part.CFrame.RightVector * (localPos.X >= 0 and 1 or -1)
				or part.CFrame.LookVector * (localPos.Z >= 0 and -1 or 1)
			escape = Vector3.new(axis.X, 0, axis.Z)
			escape = escape.Magnitude > 0.01 and escape.Unit or Vector3.zero
		end
		local push = math.max(flatSpeed, velocity.Magnitude * 0.6)
		local flat = Vector3.new(velocity.X, 0, velocity.Z) + escape * push
		if flat.Magnitude > push then flat = flat.Unit * push end
		return Vector3.new(flat.X, math.min(velocity.Y, 0), flat.Z)
	end
	-- a side face: slide along it
	return velocity - n * math.min(velocity:Dot(n), 0)
end

Flight.Config = Config
Flight.getFloat = getFloat
Flight.calculateLowestY = calculateLowestY
Flight.isCurveSafe = isCurveSafe
Flight.calculateCombatAimPoint = calculateCombatAimPoint
Flight.pickStrafe = pickStrafe
Flight.containVelocity = containVelocity
Flight.avoidPlatforms = avoidPlatforms

return Flight
