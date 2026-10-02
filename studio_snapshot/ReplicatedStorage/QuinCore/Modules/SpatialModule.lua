--// SpatialModule.lua
-- Environment awareness: obstacle detection, edge detection, intercept prediction

local DebugDraw = require(game:GetService("ReplicatedStorage"):WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("DebugDraw"))
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")

local SpatialModule = {}

-- Raycast forward from rootPart to detect obstacles
function SpatialModule.raycastForward(rootPart, distance)
	distance = distance or 10
	local params = RaycastParams.new()
	params.FilterDescendantsInstances = {rootPart.Parent}
	params.FilterType = Enum.RaycastFilterType.Exclude
	
	local origin = rootPart.Position
	local direction = rootPart.CFrame.LookVector * distance
	local result = DebugDraw.raycast(rootPart, origin, direction, params)
	
	if result then
		return true, result.Position, result.Normal, result.Instance
	end
	return false
end

-- Raycast down to check ground distance and detect edges
function SpatialModule.raycastDown(rootPart, maxDistance)
	maxDistance = maxDistance or 50
	local params = RaycastParams.new()
	params.FilterDescendantsInstances = {rootPart.Parent}
	params.FilterType = Enum.RaycastFilterType.Exclude
	
	local result = DebugDraw.raycast(rootPart, rootPart.Position, Vector3.new(0, -maxDistance, 0), params)
	if result then
		local groundDist = (rootPart.Position - result.Position).Magnitude
		return true, groundDist, result.Position, result.Normal
	end
	return false, maxDistance, nil, nil
end

-- Check if near a true lethal arena edge or void boundary.
-- If allowPlatformDrop is true (e.g. Quin wants to leap down toward a target below),
-- drops with valid ground/baseplate below within 250 studs are permitted.
function SpatialModule.isNearArenaEdge(rootPart, threshold, allowPlatformDrop)
	threshold = threshold or 8
	local params = RaycastParams.new()
	params.FilterDescendantsInstances = {rootPart.Parent}
	params.FilterType = Enum.RaycastFilterType.Exclude
	
	local checkDirs = {
		rootPart.CFrame.LookVector * threshold,
		rootPart.CFrame.RightVector * threshold,
		-rootPart.CFrame.RightVector * threshold,
	}
	
	for _, offset in ipairs(checkDirs) do
		local checkPos = rootPart.Position + offset
		local shallowHit = DebugDraw.raycast(rootPart, checkPos, Vector3.new(0, -20, 0), params)
		if not shallowHit then
			-- No shallow ground found at this offset. Check if this is a platform ledge or true void
			local deepHit = DebugDraw.raycast(rootPart, checkPos, Vector3.new(0, -250, 0), params)
			if not deepHit then
				-- True void! No ground anywhere below = lethal arena boundary!
				return true, -offset.Unit
			else
				-- Valid ground exists below (elevated platform ledge)
				if not allowPlatformDrop then
					return true, -offset.Unit
				end
			end
		end
	end
	return false, Vector3.zero
end

local MAX_DROP_ON_FOOT = 10 -- studs a Quin steps down on foot (more than this off a raised surface is "lava")

-- Keep a running Quin on the surface it stands on ("the floor is lava"). With its target at
-- about the same level, a heading that would carry it off a drop (a raised lane, a platform
-- edge) is bent toward ground that continues, the smallest turn first; boxed in, it stops at
-- the edge. A target well below is a reason to go down, so the heading is left alone.
-- Returns the (possibly new) goal and whether it was changed.
function SpatialModule.keepOnSurface(rootPart, goal, targetPos, reachOverride)
	local params = RaycastParams.new()
	local excludeList = { rootPart.Parent }
	local qs = Workspace:FindFirstChild("QuinServer")
	if qs then table.insert(excludeList, qs) end
	params.FilterDescendantsInstances = excludeList
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.RespectCanCollide = true

	local p = rootPart.Position
	local floor = Workspace:Raycast(p, Vector3.new(0, -9, 0), params)
	if not floor then return goal, false end -- in the air: nothing to keep to
	if targetPos and targetPos.Y < p.Y - 6 then return goal, false end
	local want = Vector3.new(goal.X - p.X, 0, goal.Z - p.Z)
	if want.Magnitude < 0.5 then return goal, false end
	local dir = want.Unit
	local floorY = floor.Position.Y
	local v = rootPart.AssemblyLinearVelocity
	local reach = reachOverride or math.clamp(Vector3.new(v.X, 0, v.Z).Magnitude * 0.25, 3, 10)
	local function onGround(d)
		-- the body is ~2.5 wide: ground must also be there 1.2 to either side of the path, or
		-- the root creeps to the lip on a shallow heading and the body slides off
		local side = Vector3.new(-d.Z, 0, d.X) * 1.2
		local probes = { p + d * 2, p + d * 2 + side, p + d * 2 - side, p + d * (reach * 0.6), p + d * reach }
		if reach > 10 then
			-- a long committed move (a slide): the whole way, edge margin included
			for s = 5, reach, 5 do
				table.insert(probes, p + d * s + side)
				table.insert(probes, p + d * s - side)
			end
		end
		for _, probe in ipairs(probes) do
			-- from above any step it could take, down to a drop it can take on foot
			-- (MAX_DROP_ON_FOOT; off the top of a bar back onto the lane is fine)
			local drop = 6 + MAX_DROP_ON_FOOT
			if not Workspace:Raycast(Vector3.new(probe.X, floorY + 6, probe.Z), Vector3.new(0, -drop, 0), params) then
				return false
			end
		end
		return true
	end
	if onGround(dir) then return goal, false end
	-- (only shallow turns: running along an edge at a steep angle carried a Quin off the end of
	-- a small top on its momentum; past 50 degrees it stops at the edge instead)
	for _, angle in ipairs({ 15, -15, 30, -30, 50, -50 }) do
		local d = CFrame.Angles(0, math.rad(angle), 0):VectorToWorldSpace(dir)
		if onGround(d) then
			return p + d * math.max(want.Magnitude, 8), true
		end
	end
	return p, true
end

-- Get a safe direction to move when obstacles are ahead with multi-ray whisker array
function SpatialModule.getObstacleAvoidanceDirection(rootPart, checkDistance)
	checkDistance = checkDistance or 14
	local params = RaycastParams.new()
	local excludeList = {rootPart.Parent}
	local qs = Workspace:FindFirstChild("QuinServer")
	if qs then table.insert(excludeList, qs) end
	params.FilterDescendantsInstances = excludeList
	params.FilterType = Enum.RaycastFilterType.Exclude

	local forward = rootPart.CFrame.LookVector
	local flatFwd = Vector3.new(forward.X, 0, forward.Z)
	flatFwd = flatFwd.Magnitude > 0.01 and flatFwd.Unit or forward
	local waistOrigin = rootPart.Position - Vector3.new(0, 2.0, 0)

	-- Check direct forward
	local fwdHit = DebugDraw.raycast(rootPart, waistOrigin, flatFwd * checkDistance, params)
	if not fwdHit then
		return flatFwd -- Clear ahead
	end

	-- Tangent projection if normal is vertical/planar
	if fwdHit.Normal and math.abs(fwdHit.Normal.Y) < 0.3 then
		local flatNorm = Vector3.new(fwdHit.Normal.X, 0, fwdHit.Normal.Z).Unit
		local tangent = flatFwd - (flatFwd:Dot(flatNorm) * flatNorm)
		if tangent.Magnitude > 0.05 then
			local tangentDir = (tangent.Unit + flatNorm * 0.35).Unit
			local tHit = DebugDraw.raycast(rootPart, waistOrigin, tangentDir * (checkDistance * 0.85), params)
			if not tHit then
				return tangentDir
			end
		end
	end

	-- Multi-ray whisker sweep (±25°, ±45°, ±75°, ±90°)
	local angles = { 25, -25, 45, -45, 75, -75, 90, -90 }
	for _, ang in ipairs(angles) do
		local rot = CFrame.Angles(0, math.rad(ang), 0)
		local testDir = (rot * flatFwd).Unit
		local hit = DebugDraw.raycast(rootPart, waistOrigin, testDir * (checkDistance * 0.85), params)
		if not hit then
			return testDir
		end
	end

	return -flatFwd
end

-- Predict intercept point for anime-style arc movement
function SpatialModule.predictIntercept(myPos, mySpeed, targetPos, targetVel)
	if targetVel.Magnitude < 1 then
		return targetPos -- Target is stationary
	end
	
	-- Simple intercept: estimate time to reach target, project target's position
	local dist = (targetPos - myPos).Magnitude
	local timeToReach = dist / math.max(mySpeed, 1)
	
	-- Clamp prediction to 2 seconds max
	timeToReach = math.min(timeToReach, 2.0)
	
	local predictedPos = targetPos + targetVel * timeToReach * 0.6
	return predictedPos
end

-- Check if rootPart is grounded
function SpatialModule.isGrounded(rootPart)
	local params = RaycastParams.new()
	params.FilterDescendantsInstances = {rootPart.Parent}
	params.FilterType = Enum.RaycastFilterType.Exclude
	
	local humanoid = rootPart.Parent:FindFirstChildOfClass("Humanoid")
	local hipHeight = humanoid and humanoid.HipHeight or 0
	local isRagdoll = humanoid and humanoid.PlatformStand or false
	local isStabilized = rootPart:FindFirstChild("KB_Stabilizer") ~= nil
	
	-- In Roblox, HipHeight is distance from bottom of HRP to floor.
	-- Since raycast originates at rootPart.Position (HRP center), true standing distance is halfHeight + HipHeight.
	local halfHeight = rootPart.Size.Y / 2
	local checkDistance = halfHeight + 2.5 -- Generous check for unconstrained / prone ragdoll resting on floor
	
	if not isRagdoll or isStabilized then
		-- Upright: HRP center to bottom (halfHeight) + bottom to floor (hipHeight) + 0.8 stud landing contact margin
		checkDistance = halfHeight + hipHeight + 0.8
	end
	
	local result = DebugDraw.raycast(rootPart, rootPart.Position, Vector3.new(0, -checkDistance, 0), params)
	return result ~= nil
end

function SpatialModule.getArenaCenterPull(rootPart)
	local arenaGround = Workspace:FindFirstChild("argoniaonion") and Workspace.argoniaonion:FindFirstChild("ArenaGround")
	if not arenaGround then return Vector3.zero end
	
	local center = arenaGround.Position
	local radius = math.min(arenaGround.Size.X, arenaGround.Size.Z) / 2
	
	local toCenter = center - rootPart.Position
	toCenter = Vector3.new(toCenter.X, 0, toCenter.Z)
	local dist = toCenter.Magnitude
	
	-- If they are beyond 30% of the arena radius, start pulling them in
	local threshold = radius * 0.3
	if dist > threshold then
		local pullStrength = math.clamp((dist - threshold) / (radius * 0.7), 0, 1)
		return toCenter.Unit * pullStrength
	end
	return Vector3.zero
end

-- Dynamically derive the arena bounds from the ArenaGround part.
-- Never hardcodes 600x600; respects future arena resizes / redesigns.
function SpatialModule.getArenaBounds()
	local arenaRoot = Workspace:FindFirstChild("argoniaonion")
	local arenaGround = arenaRoot and arenaRoot:FindFirstChild("ArenaGround", true)
	-- The movement test course is its own arena (the safety net used to fling Quins spawned
	-- there back into the main arena)
	if Workspace:GetAttribute("CurrentMode") == "MovementTestArena" then
		local course = Workspace:FindFirstChild("MovementTestArena")
		arenaGround = (course and course:FindFirstChild("ArenaGroundMovementTest", true)) or arenaGround
	end
	local size = arenaGround and arenaGround.Size or Vector3.new(600, 4, 600)
	local center = arenaGround and arenaGround.Position or Vector3.zero
	local halfX = size.X / 2
	local halfZ = size.Z / 2
	return {
		center = Vector3.new(center.X, 0, center.Z),
		halfX = halfX,
		halfZ = halfZ,
		radius = math.min(halfX, halfZ),
	}
end

function SpatialModule.isOutOfBounds(rootPart, margin)
	if not rootPart then return false end
	margin = margin or 5
	local pos = rootPart.Position
	if pos.Y < -10 then return true end
	local b = SpatialModule.getArenaBounds()
	if math.abs(pos.X - b.center.X) > (b.halfX - margin) or math.abs(pos.Z - b.center.Z) > (b.halfZ - margin) then
		return true
	end
	return false
end

function SpatialModule.getArenaCenterDirection(rootPart)
	if not rootPart then return Vector3.new(0, 0, -1) end
	local pos = rootPart.Position
	local b = SpatialModule.getArenaBounds()
	local dir = Vector3.new(b.center.X - pos.X, 0, b.center.Z - pos.Z)
	if dir.Magnitude > 0.001 then
		return dir.Unit
	end
	return Vector3.new(0, 0, -1)
end

-- Comprehensive obstacle & OB situational awareness with multi-level whiskers
function SpatialModule.analyzeObstacleAhead(rootPart, targetPos, checkDistance)
	checkDistance = checkDistance or 22
	local params = RaycastParams.new()
	local excludeList = { rootPart.Parent }
	local qs = Workspace:FindFirstChild("QuinServer")
	if qs then table.insert(excludeList, qs) end
	local qg = Workspace:FindFirstChild("QuinGhost")
	if qg then table.insert(excludeList, qg) end
	params.FilterDescendantsInstances = excludeList
	params.FilterType = Enum.RaycastFilterType.Exclude

	local origin = rootPart.Position
	local toTarget = targetPos and (targetPos - origin) or (rootPart.CFrame.LookVector * checkDistance)
	local flatDir = Vector3.new(toTarget.X, 0, toTarget.Z)
	local dir = (flatDir.Magnitude > 0.1) and flatDir.Unit or rootPart.CFrame.LookVector

	-- 3-Tier Multi-Level Whisker Raycasting (Foot, Waist, Chest)
	-- Custom Alpha_Surface skin extends ~5.4 studs below the HRP (the actual feet), so the
	-- whisker rays are calibrated down to the real body: foot/low-step, waist, and chest/shoulder.
	local footOrigin = origin - Vector3.new(0, 4.5, 0)
	local waistOrigin = origin - Vector3.new(0, 2.0, 0)
	local chestOrigin = origin + Vector3.new(0, 0.5, 0)

	local hit = nil
	local rayOrigins = { footOrigin, waistOrigin, chestOrigin }
	for _, rOrigin in ipairs(rayOrigins) do
		local rHit = DebugDraw.raycast(rootPart, rOrigin, dir * checkDistance, params)
		if rHit and rHit.Instance and rHit.Instance.CanCollide then
			local pName = rHit.Instance.Name
			if pName ~= "ArenaGround" and pName ~= "Baseplate" and pName ~= "Floor" then
				hit = rHit
				break
			end
		end
	end

	if not hit or not hit.Instance or not hit.Instance.CanCollide then
		return { hasObstacle = false }
	end

	local hitPart = hit.Instance
	local isOB = (hitPart.Name == "OB" or hitPart.Name:find("OB") ~= nil)

	-- Open space beneath it (a floating bar): not something to jump over, the slide-under
	-- check deals with it (its face at chest height used to be skidded or hurdled into)
	do
		local floorBelow = Workspace:Raycast(origin, Vector3.new(0, -9, 0), params)
		local floorY = floorBelow and floorBelow.Position.Y or (origin.Y - 5.11)
		local inside = hit.Position - Vector3.new(hit.Normal.X, 0, hit.Normal.Z) * 0.4
		local under = Workspace:Raycast(Vector3.new(inside.X, floorY + 0.3, inside.Z), Vector3.new(0, 14, 0), params)
		if under and under.Position.Y - floorY >= 2.5 then
			return { hasObstacle = false, overhead = true }
		end
	end

	-- Measure height of obstacle by casting down from above hit position
	-- From just inside the face: cast from the face plane itself, the ray grazed past the top
	-- of thin bars and hit the floor (height 0: a 3-stud bar read as "no obstacle" or as a
	-- step, so the Quin ran into it)
	local maxCheckH = 80
	local inside = hit.Position - Vector3.new(hit.Normal.X, 0, hit.Normal.Z) * 0.4
	local upRayOrigin = inside + Vector3.new(0, maxCheckH, 0)
	local downHit = DebugDraw.raycast(rootPart, upRayOrigin, Vector3.new(0, -maxCheckH * 1.5, 0), params)

	local topY = downHit and downHit.Position.Y or (hit.Position.Y + 2.0)
	-- Actual ground level beneath the Quin (raycast, matching isGrounded's skin calibration;
	-- a fixed -2.5 offset under-measured low OBs and caused "stuck on feet")
	local groundRay = DebugDraw.raycast(rootPart, rootPart.Position, Vector3.new(0, -20, 0), params)
	local groundY = groundRay and groundRay.Position.Y or (rootPart.Position.Y - 5.4)
	local obstacleHeight = math.max(0, topY - groundY)

	local canVault = (obstacleHeight >= 1.2 and obstacleHeight <= 14.0)
	local isTall = (obstacleHeight > 14.0)

	-- Find best avoidance steer direction using whisker sweeps (±35°, ±60°, ±90°)
	local angles = { 35, -35, 60, -60, 90, -90 }
	local bestSteerDir = nil
	local bestDot = -math.huge

	for _, ang in ipairs(angles) do
		local rotCFrame = CFrame.Angles(0, math.rad(ang), 0)
		local testDir = (rotCFrame * Vector3.new(dir.X, 0, dir.Z)).Unit
		local testHit = DebugDraw.raycast(rootPart, waistOrigin, testDir * (checkDistance * 0.9), params)
		if not testHit then
			local dot = testDir:Dot(dir)
			if dot > bestDot then
				bestDot = dot
				bestSteerDir = testDir
			end
		end
	end

	-- Calculate obstacle surface tangent if hit normal is planar/vertical
	if hit.Normal and math.abs(hit.Normal.Y) < 0.35 then
		local flatNorm = Vector3.new(hit.Normal.X, 0, hit.Normal.Z).Unit
		local proj = dir - (dir:Dot(flatNorm) * flatNorm)
		if proj.Magnitude > 0.05 then
			local tangentCandidate = (proj.Unit + flatNorm * 0.35).Unit
			local tHit = DebugDraw.raycast(rootPart, waistOrigin, tangentCandidate * (checkDistance * 0.85), params)
			if not tHit then
				bestSteerDir = tangentCandidate
			end
		end
	end

	if not bestSteerDir then
		-- Fallback steer sideways
		bestSteerDir = Vector3.new(-dir.Z, 0, dir.X)
	end

	return {
		hasObstacle = true,
		part = hitPart,
		isOB = isOB,
		hitPosition = hit.Position,
		normal = hit.Normal,
		height = obstacleHeight,
		canVault = canVault,
		isTall = isTall,
		steerDirection = bestSteerDir,
		topSurfaceY = topY,
	}
end

-- Detect if target is elevated on an OB floating platform
function SpatialModule.detectElevatedPlatform(rootPart, targetPos)
	if not rootPart or not targetPos then return { isElevated = false } end
	local yDiff = targetPos.Y - rootPart.Position.Y
	if yDiff > 6.0 then
		local hit = DebugDraw.raycast(rootPart, targetPos + Vector3.new(0, 2, 0), Vector3.new(0, -10, 0))
		local onOB = hit and (hit.Instance.Name == "OB" or hit.Instance.Name:find("OB") ~= nil)
		return {
			isElevated = true,
			heightDiff = yDiff,
			isOB = onOB,
			platform = hit and hit.Instance or nil
		}
	end
	return { isElevated = false }
end

-- Find a floating OB platform above the Quin whose top surface is within jump reach.
-- Returns { topY, position, part } or nil. Used for high-ground climbing.
function SpatialModule.findReachableOverheadPlatform(rootPart, maxReach, minReach)
	maxReach = maxReach or 14
	minReach = minReach or 2.5
	if not rootPart then return nil end

	local params = RaycastParams.new()
	local excludeList = { rootPart.Parent }
	local qs = Workspace:FindFirstChild("QuinServer")
	if qs then table.insert(excludeList, qs) end
	params.FilterDescendantsInstances = excludeList
	params.FilterType = Enum.RaycastFilterType.Exclude

	local pos = rootPart.Position
	-- Probe directly above + slightly forward/left/right to catch nearby platforms
	local offsets = {
		Vector3.new(0, 0, 0),
		Vector3.new(0, 0, -4),
		Vector3.new(4, 0, 0),
		Vector3.new(-4, 0, 0),
	}
	local best = nil
	for _, off in ipairs(offsets) do
		local probeXZ = pos + off
		local upOrigin = Vector3.new(probeXZ.X, pos.Y + maxReach + 2, probeXZ.Z)
		local hit = DebugDraw.raycast(rootPart, upOrigin, Vector3.new(0, -(maxReach + 4), 0), params)
		if hit then
			local topY = hit.Position.Y
			-- Must be above us (not the ground below) and within [minReach, maxReach] jump range
			if topY > pos.Y + minReach and topY <= pos.Y + maxReach + 2 then
				local part = hit.Instance
				local isOB = (part.Name == "OB" or part.Name:find("OB") ~= nil)
				if isOB and (not best or topY < best.topY) then
					best = { topY = topY, position = hit.Position, part = part }
				end
			end
		end
	end
	return best
end

-- Detect a low-overhead obstacle with a slideable gap beneath it (for slide-under).
-- Returns { bottomY, gapHeight, part } or nil.
function SpatialModule.detectLowOverheadGap(rootPart, forwardDist)
	forwardDist = forwardDist or 8
	if not rootPart then return nil end

	local params = RaycastParams.new()
	local excludeList = { rootPart.Parent }
	local qs = Workspace:FindFirstChild("QuinServer")
	if qs then table.insert(excludeList, qs) end
	params.FilterDescendantsInstances = excludeList
	params.FilterType = Enum.RaycastFilterType.Exclude

	local pos = rootPart.Position
	params.RespectCanCollide = true
	-- Along the way it is moving (the facing can lag), at chest and head height: something the
	-- body would hit with open space beneath it (a bar 2.5-8.5 studs up) is slid under. Any part
	-- (it used to need "OB" in the name) and any gap a slide fits (it used to be 0.8-3.5 only).
	local v = rootPart.AssemblyLinearVelocity
	local flat = Vector3.new(v.X, 0, v.Z)
	local look = flat.Magnitude > 4 and flat.Unit or Vector3.new(rootPart.CFrame.LookVector.X, 0, rootPart.CFrame.LookVector.Z).Unit
	local floor = Workspace:Raycast(pos, Vector3.new(0, -9, 0), params)
	local groundY = floor and floor.Position.Y or (pos.Y - 5.11)
	local hit
	for _, rise in ipairs({ 2.6, 4.5, 6.5 }) do
		hit = Workspace:Raycast(Vector3.new(pos.X, groundY + rise, pos.Z), look * forwardDist, params)
		if hit then break end
	end
	if not hit then return nil end
	local inside = hit.Position - Vector3.new(hit.Normal.X, 0, hit.Normal.Z) * 0.4
	local under = Workspace:Raycast(Vector3.new(inside.X, groundY + 0.3, inside.Z), Vector3.new(0, 12, 0), params)
	if not under then return nil end -- solid to the floor: not a gap
	local gapHeight = under.Position.Y - groundY
	if gapHeight >= 2.5 and gapHeight < 8.5 then
		local faceDistance = Vector3.new(hit.Position.X - pos.X, 0, hit.Position.Z - pos.Z).Magnitude
		return { bottomY = under.Position.Y, gapHeight = gapHeight, part = hit.Instance, faceDistance = faceDistance }
	end
	return nil
end

-- Detect a viable vertical surface to initiate an athletic Wall-Run (Phase 6 Parkour).
-- Scans left and right at torso height for near-vertical obstacles at an incident angle.
-- Returns: { hitPart, hitPosition, normal, tangent, side, distance } or nil
-- Length of wall still ahead along `tangent`, in studs: how far a wall-run could actually go.
-- Samples the wall every few studs and stops at the first gap, corner or obstruction.
local WALL_RUNWAY_STEP = 4
local WALL_RUNWAY_MAX = 60
local function measureWallRunway(origin, tangent, flatNormal, wallDistance, params)
	local reach = wallDistance + 2.5
	local runway = 0
	for d = WALL_RUNWAY_STEP, WALL_RUNWAY_MAX, WALL_RUNWAY_STEP do
		local wallHit = DebugDraw.raycast(rootPart, origin + tangent * d, -flatNormal * reach, params)
		if not wallHit or math.abs(wallHit.Normal.Y) >= 0.25 then
			break
		end
		runway = d
	end
	-- Something standing in the lane (a corner, another wall) ends the run early
	local blocked = DebugDraw.raycast(rootPart, origin, tangent * math.max(runway, WALL_RUNWAY_STEP), params)
	if blocked then
		runway = math.min(runway, math.max(0, blocked.Distance - 2))
	end
	return runway
end

-- minRunway (optional): only report a surface with at least this much wall ahead
function SpatialModule.detectWallRunSurface(rootPart, checkDist, minRunway)
	checkDist = checkDist or 5.2
	if not rootPart then return nil end

	local pos = rootPart.Position
	local look = rootPart.CFrame.LookVector
	local right = rootPart.CFrame.RightVector
	local flatLook = Vector3.new(look.X, 0, look.Z)
	if flatLook.Magnitude < 0.1 then return nil end
	flatLook = flatLook.Unit

	local flatRight = Vector3.new(right.X, 0, right.Z).Unit

	local params = RaycastParams.new()
	local excludeList = { rootPart.Parent }
	local qs = Workspace:FindFirstChild("QuinServer")
	if qs then table.insert(excludeList, qs) end
	params.FilterDescendantsInstances = excludeList
	params.FilterType = Enum.RaycastFilterType.Exclude

	local origin = pos + Vector3.new(0, 0.5, 0)

	-- Probe angles: Left flank (~45° forward-left), Right flank (~45° forward-right), and direct sides
	local candidates = {
		{ dir = (flatLook * 0.707 - flatRight * 0.707).Unit * checkDist, side = "Left" },
		{ dir = (flatLook * 0.707 + flatRight * 0.707).Unit * checkDist, side = "Right" },
		{ dir = (-flatRight).Unit * (checkDist * 0.85), side = "Left" },
		{ dir = (flatRight).Unit * (checkDist * 0.85), side = "Right" },
	}

	for _, probe in ipairs(candidates) do
		local hit = DebugDraw.raycast(rootPart, origin, probe.dir, params)
		if hit and hit.Instance and hit.Normal then
			-- Surface must be nearly vertical (Normal.Y near 0)
			local normal = hit.Normal
			if math.abs(normal.Y) < 0.25 then
				local flatNormal = Vector3.new(normal.X, 0, normal.Z).Unit
				local approachDot = flatLook:Dot(-flatNormal)

				-- Incident angle must be between ~20° and 75° (dot between 0.30 and 0.95)
				-- If dot > 0.95, it's a head-on crash. If dot < 0.25, it's nearly parallel or moving away.
				if approachDot >= 0.25 and approachDot <= 0.95 then
					-- Compute horizontal tangent along the wall matching forward momentum
					local tangent = flatLook - (flatLook:Dot(flatNormal) * flatNormal)
					if tangent.Magnitude > 0.05 then
						tangent = tangent.Unit

						-- Verify obstacle has sufficient vertical height (at least 6 studs tall)
						local isObstacle = hit.Instance.Name:find("OB") ~= nil 
							or hit.Instance.Size.Y >= 6.0 
							or (hit.Instance.Parent and hit.Instance.Parent.Name:find("OB") ~= nil)

						local wallDistance = (hit.Position - origin):Dot(-flatNormal)
						local runway = isObstacle and measureWallRunway(origin, tangent, flatNormal, wallDistance, params) or 0
						if isObstacle and runway >= (minRunway or 0) then
								return {
								runway = runway,
								wallDistance = wallDistance,
								hitPart = hit.Instance,
								hitPosition = hit.Position,
								normal = flatNormal,
								tangent = tangent,
								side = probe.side,
								distance = (hit.Position - origin).Magnitude
							}
						end
					end
				end
			end
		end
	end

	return nil
end

-- Evaluates 8 candidate retreat directions (45° increments) and scores
-- each based on:
--   1. Enemy Repulsion  — maximize distance from enemy threat centroid
--   2. Ally Attraction  — prefer directions that route toward allied cluster
--   3. Boundary Safety  — penalize directions that lead off-arena or toward walls
--   4. Obstacle Clearance — penalize directions blocked by obstacles
--   5. Arena Center Pull — slight bias toward arena center for safety
--
-- Returns: { direction: Vector3, score: number, isCornered: boolean }
--   direction  = best weighted XZ unit vector for retreat movement
--   score      = 0..1 quality metric (1 = wide open safe retreat, 0 = trapped)
--   isCornered = true if no viable retreat direction exists (all scores near 0)

function SpatialModule.getSafeRetreatDirection(rootPart, enemies, allies, config)
	if not rootPart then
		return { direction = Vector3.new(0, 0, -1), score = 0, isCornered = true }
	end

	config = config or {}
	local enemyRepulsionWeight = config.RetreatEnemyRepulsionWeight or 1.5
	local allyAttractionWeight = config.RetreatAllyAttractionWeight or 0.8
	local boundaryPenaltyWeight = config.RetreatBoundaryPenalty or 1.2
	local obstaclePenaltyWeight = config.RetreatObstaclePenalty or 1.0
	local centerBiasWeight = config.RetreatCenterBias or 0.3
	local searchRadius = config.RetreatSearchRadius or 30.0
	local corneredThreshold = config.CorneredScoreThreshold or 0.15

	local myPos = rootPart.Position
	local myPosFlat = Vector3.new(myPos.X, 0, myPos.Z)

	-- Extract HRP helper that works with either Model Instance or table entry { model = ..., ... }
	local function getEntityHRP(entity)
		if not entity then return nil end
		if typeof(entity) == "Instance" then
			if entity:IsA("Model") then
				return entity:FindFirstChild("HumanoidRootPart")
			elseif entity:IsA("BasePart") and entity.Name == "HumanoidRootPart" then
				return entity
			end
		elseif typeof(entity) == "table" then
			if entity.model and typeof(entity.model) == "Instance" then
				return entity.model:FindFirstChild("HumanoidRootPart")
			elseif entity.HRP and typeof(entity.HRP) == "Instance" then
				return entity.HRP
			elseif entity.rootPart and typeof(entity.rootPart) == "Instance" then
				return entity.rootPart
			end
		end
		return nil
	end

	-- Compute enemy threat centroid (flat XZ)
	local enemyCentroid = Vector3.zero
	local enemyPositions = {}
	local enemyCount = 0
	if enemies and #enemies > 0 then
		for _, enemy in ipairs(enemies) do
			local eHRP = getEntityHRP(enemy)
			if eHRP then
				local ePos = Vector3.new(eHRP.Position.X, 0, eHRP.Position.Z)
				table.insert(enemyPositions, ePos)
				enemyCentroid = enemyCentroid + ePos
				enemyCount = enemyCount + 1
			end
		end
		if enemyCount > 0 then
			enemyCentroid = enemyCentroid / enemyCount
		end
	end

	-- Compute ally centroid (flat XZ)
	local allyCentroid = Vector3.zero
	local allyCount = 0
	if allies and #allies > 0 then
		for _, ally in ipairs(allies) do
			local aHRP = getEntityHRP(ally)
			if aHRP then
				local aPos = Vector3.new(aHRP.Position.X, 0, aHRP.Position.Z)
				allyCentroid = allyCentroid + aPos
				allyCount = allyCount + 1
			end
		end
		if allyCount > 0 then
			allyCentroid = allyCentroid / allyCount
		end
	end

	-- Arena centre and radius from the real ground part. (A direct-child lookup found nothing,
	-- so the boundary penalty was measured from the world origin: every direction looked like
	-- it led off the arena and Quins read as cornered ~40% of the time.)
	local arenaBounds = SpatialModule.getArenaBounds()
	local arenaCenter = arenaBounds.center
	local arenaRadius = arenaBounds.radius

	-- Raycast params (exclude self and Quin containers)
	local params = RaycastParams.new()
	local excludeList = { rootPart.Parent }
	local qs = Workspace:FindFirstChild("QuinServer")
	if qs then table.insert(excludeList, qs) end
	local qg = Workspace:FindFirstChild("QuinGhost")
	if qg then table.insert(excludeList, qg) end
	params.FilterDescendantsInstances = excludeList
	params.FilterType = Enum.RaycastFilterType.Exclude

	-- 8 candidate directions at 45° increments
	local NUM_RAYS = 8
	local bestDir = nil
	local bestScore = -math.huge
	local scores = {}

	for i = 0, NUM_RAYS - 1 do
		local angle = (i / NUM_RAYS) * math.pi * 2
		local candidateDir = Vector3.new(math.sin(angle), 0, math.cos(angle))
		local candidateTarget = myPosFlat + candidateDir * searchRadius

		local score = 0

		-- 1. Enemy Repulsion: prefer directions AWAY from enemy centroid
		if enemyCount > 0 then
			local dirToEnemyCentroid = (enemyCentroid - myPosFlat)
			if dirToEnemyCentroid.Magnitude > 0.1 then
				local repulsionDot = -candidateDir:Dot(dirToEnemyCentroid.Unit)
				-- repulsionDot is +1 when moving directly AWAY from enemies, -1 when toward
				score = score + (repulsionDot + 1) * 0.5 * enemyRepulsionWeight
			end

			-- Per-enemy proximity penalty: if moving toward ANY nearby enemy, penalize more
			for _, ePos in ipairs(enemyPositions) do
				local toEnemy = (ePos - myPosFlat)
				if toEnemy.Magnitude > 0.1 and toEnemy.Magnitude < searchRadius then
					local proximityDot = candidateDir:Dot(toEnemy.Unit)
					if proximityDot > 0.3 then
						-- Moving toward this specific enemy
						local closeness = 1 - math.clamp(toEnemy.Magnitude / searchRadius, 0, 1)
						score = score - proximityDot * closeness * enemyRepulsionWeight * 0.6
					end
				end
			end
		end

		-- 2. Ally Attraction: prefer directions TOWARD ally centroid
		if allyCount > 0 then
			local dirToAllyCentroid = (allyCentroid - myPosFlat)
			if dirToAllyCentroid.Magnitude > 5 then -- Only attract if allies are not already on top of us
				local attractionDot = candidateDir:Dot(dirToAllyCentroid.Unit)
				score = score + (attractionDot + 1) * 0.5 * allyAttractionWeight
			end
		end

		-- 3. Boundary Safety: penalize directions that lead off-arena
		local distFromCenter = (candidateTarget - arenaCenter).Magnitude
		local boundaryProximity = math.clamp(distFromCenter / arenaRadius, 0, 1)
		if boundaryProximity > 0.75 then
			score = score - (boundaryProximity - 0.75) * 4 * boundaryPenaltyWeight
		end

		-- Also check edge: raycast down at candidate position for ground
		local edgeCheck = DebugDraw.raycast(rootPart, 
			Vector3.new(candidateTarget.X, myPos.Y + 2, candidateTarget.Z),
			Vector3.new(0, -20, 0),
			params
		)
		if not edgeCheck then
			-- No ground at candidate position = arena edge / void
			score = score - 2.0 * boundaryPenaltyWeight
		end

		-- 4. Obstacle Clearance: raycast in candidate direction for blocking geometry
		local obstacleHit = DebugDraw.raycast(rootPart, myPos, candidateDir * searchRadius, params)
		if obstacleHit then
			local obstacleDist = (obstacleHit.Position - myPos).Magnitude
			if obstacleDist < searchRadius * 0.5 then
				-- Close obstacle in this direction
				local clearancePenalty = 1 - math.clamp(obstacleDist / (searchRadius * 0.5), 0, 1)
				-- Don't penalize arena floor
				local hitName = obstacleHit.Instance and obstacleHit.Instance.Name or ""
				if hitName ~= "ArenaGround" and hitName ~= "Baseplate" and hitName ~= "Floor" then
					local obstacleMult = 1.0
					if obstacleDist < 10.0 then
						obstacleMult = 2.5 * (1.0 - (obstacleDist / 10.0)) + 1.0
					end
					score = score - clearancePenalty * (config.RetreatObstaclePenalty or 1.5) * obstacleMult
				end
			end
		end

		-- 5. Arena Center Bias: gentle pull toward center for safety
		local dirToCenter = (arenaCenter - myPosFlat)
		if dirToCenter.Magnitude > 5 then
			local centerDot = candidateDir:Dot(dirToCenter.Unit)
			score = score + (centerDot + 1) * 0.5 * centerBiasWeight
		end

		scores[i] = score
		if score > bestScore then
			bestScore = score
			bestDir = candidateDir
		end
	end

	-- Normalize score to 0..1 range for quality assessment
	local normalizedScore = 1.0
	local isCornered = false

	if enemyCount > 0 then
		local maxPossibleScore = enemyRepulsionWeight + allyAttractionWeight + centerBiasWeight
		normalizedScore = math.clamp(bestScore / math.max(maxPossibleScore, 0.01), 0, 1)
		isCornered = normalizedScore < corneredThreshold
	else
		-- Zero enemies nearby: Quin has total movement freedom
		normalizedScore = 1.0
		isCornered = false
	end

	-- Debug: the eight candidates, longer and greener the better they scored
	if DebugDraw.isActive("Retreat", rootPart) then
		local topScore = math.max(enemyRepulsionWeight + allyAttractionWeight + centerBiasWeight, 0.01)
		for i = 0, NUM_RAYS - 1 do
			local angle = (i / NUM_RAYS) * math.pi * 2
			local candidateDir = Vector3.new(math.sin(angle), 0, math.cos(angle))
			local quality = math.clamp(scores[i] / topScore, 0, 1)
			DebugDraw.line("Retreat", rootPart, myPos, myPos + candidateDir * (4 + quality * searchRadius),
				candidateDir == bestDir and Color3.fromRGB(80, 255, 140) or Color3.fromRGB(255, 90 + math.floor(quality * 150), 60))
		end
		if bestDir then
			DebugDraw.text("Retreat", rootPart, myPos + bestDir * (4 + normalizedScore * searchRadius) + Vector3.new(0, 2, 0),
				string.format("retreat %.2f%s", normalizedScore, isCornered and " CORNERED" or ""), Color3.fromRGB(80, 255, 140))
		end
	end

	if not bestDir then
		-- Absolute fallback: away from enemy centroid or toward center
		if enemyCount > 0 then
			local awayFromEnemies = (myPosFlat - enemyCentroid)
			if awayFromEnemies.Magnitude > 0.1 then
				bestDir = awayFromEnemies.Unit
			else
				bestDir = Vector3.new(0, 0, -1)
			end
			normalizedScore = 0
			isCornered = true
		else
			local toCenter = (arenaCenter - myPosFlat)
			bestDir = (toCenter.Magnitude > 1) and toCenter.Unit or Vector3.new(0, 0, -1)
			normalizedScore = 1.0
			isCornered = false
		end
	end

	return {
		direction = bestDir,
		score = normalizedScore,
		isCornered = isCornered,
	}
end

-- ============================================================
-- Phase 4: Vertical Navigation & Floating Platform Reasoning
-- ============================================================

-- Detect whether this Quin is currently perched on an elevated platform or obstacle.
-- Returns (isElevated, info) where info = { part, surfaceY, elevation, floorY, isOB }.
function SpatialModule.isOnElevatedPlatform(rootPart, threshold)
	threshold = threshold or 5.0
	if not rootPart then return false, nil end

	local pos = rootPart.Position

	local params = RaycastParams.new()
	params.FilterDescendantsInstances = { rootPart.Parent }
	params.FilterType = Enum.RaycastFilterType.Exclude

	-- Surface directly beneath the Quin's feet
	local hit = DebugDraw.raycast(rootPart, pos + Vector3.new(0, 0.5, 0), Vector3.new(0, -60, 0), params)
	if not hit then return false, nil end

	local surfacePart = hit.Instance
	local surfaceY = hit.Position.Y
	local nameLower = surfacePart.Name:lower()
	local isOB = (nameLower:find("ob") ~= nil or nameLower:find("platform") ~= nil)

	-- Measure vertical drop from this surface down to the arena floor,
	-- excluding the platform part itself so we pierce through to real ground.
	local gapParams = RaycastParams.new()
	gapParams.FilterDescendantsInstances = { rootPart.Parent, surfacePart }
	gapParams.FilterType = Enum.RaycastFilterType.Exclude
	local floorHit = DebugDraw.raycast(rootPart, Vector3.new(pos.X, surfaceY - 0.5, pos.Z), Vector3.new(0, -300, 0), gapParams)
	local floorY = floorHit and floorHit.Position.Y or surfaceY
	local elevation = surfaceY - floorY

	local info = {
		part = surfacePart,
		surfaceY = surfaceY,
		elevation = elevation,
		floorY = floorY,
		isOB = isOB,
	}

	-- Any anchored surface elevated above nominal floor qualifies as a platform
	if elevation >= threshold then
		return true, info
	end
	return false, info
end

-- Find the nearest safe ledge direction to dismount an elevated platform,
-- biased toward the target position or open ground.
-- Returns (bestDir, bestDist)
function SpatialModule.getPlatformDismountDirection(rootPart, targetPos)
	if not rootPart then return Vector3.new(0, 0, -1), 999 end

	local isElevated, info = SpatialModule.isOnElevatedPlatform(rootPart)
	local platformPart = info and info.part
	if not platformPart then
		-- Not on a platform; no dismount needed.
		if targetPos then
			local tDir = Vector3.new(targetPos.X - rootPart.Position.X, 0, targetPos.Z - rootPart.Position.Z)
			if tDir.Magnitude > 0.01 then return tDir.Unit, 0 end
		end
		return SpatialModule.getArenaCenterDirection(rootPart), 0
	end

	local params = RaycastParams.new()
	params.FilterDescendantsInstances = { rootPart.Parent }
	params.FilterType = Enum.RaycastFilterType.Exclude

	local pos = rootPart.Position
	local targetDir = Vector3.zero
	if targetPos then
		targetDir = Vector3.new(targetPos.X - pos.X, 0, targetPos.Z - pos.Z)
		if targetDir.Magnitude > 0.01 then targetDir = targetDir.Unit end
	end

	local rayCount = 16
	local maxRange = 24.0
	local bestDir = nil
	local bestDist = 999
	local bestScore = -math.huge

	for i = 0, rayCount - 1 do
		local angle = (i / rayCount) * math.pi * 2
		local dir = Vector3.new(math.sin(angle), 0, math.cos(angle))

		-- Step outward to find where the platform surface ends
		local edgeDist = nil
		for _, d in ipairs({ 2, 4, 6, 8, 10, 14, 18, 22 }) do
			local probe = pos + dir * d
			local hit = DebugDraw.raycast(rootPart, Vector3.new(probe.X, pos.Y + 1, probe.Z), Vector3.new(0, -40, 0), params)
			if (not hit) or (hit.Instance ~= platformPart) then
				edgeDist = d
				break
			end
		end

		if edgeDist then
			local score = 0
			if targetDir.Magnitude > 0.01 then
				score = score + dir:Dot(targetDir) * 2.5
			end
			score = score + (1.0 - edgeDist / maxRange) * 1.2
			if score > bestScore then
				bestScore = score
				bestDir = dir
				bestDist = edgeDist
			end
		end
	end

	if bestDir then return bestDir, bestDist end
	if targetDir.Magnitude > 0.01 then return targetDir, 999 end
	return SpatialModule.getArenaCenterDirection(rootPart), 999
end

-- ============================================================
-- LINE OF SIGHT & ENVIRONMENTAL SENSING (Section 41 & 44)
-- ============================================================

-- Eye-level sensory position for 8-stud tall Quin (eyes at Y + 3.0 above HRP center)
function SpatialModule.getEyePosition(rootPart)
	if not rootPart then return Vector3.zero end
	return rootPart.Position + Vector3.new(0, 3.0, 0)
end

function SpatialModule.checkLineOfSight(posA, posB, ignoreInstances)
	local diff = posB - posA
	local dist = diff.Magnitude
	if dist < 0.1 then return true end

	local params = RaycastParams.new()
	local exclude = {}
	if ignoreInstances then
		if typeof(ignoreInstances) == "Instance" then
			table.insert(exclude, ignoreInstances)
		elseif type(ignoreInstances) == "table" then
			for _, inst in ipairs(ignoreInstances) do
				if typeof(inst) == "Instance" then table.insert(exclude, inst) end
			end
		end
	end
	local qs = Workspace:FindFirstChild("QuinServer")
	if qs then table.insert(exclude, qs) end
	local qg = Workspace:FindFirstChild("QuinGhost")
	if qg then table.insert(exclude, qg) end

	local CollectionService = game:GetService("CollectionService")
	for _, q in ipairs(CollectionService:GetTagged("Quin")) do
		table.insert(exclude, q)
	end

	params.FilterDescendantsInstances = exclude
	params.FilterType = Enum.RaycastFilterType.Exclude

	local hit = DebugDraw.raycast(rootPart, posA, diff, params)
	if hit then
		if hit.Instance and hit.Instance.CanCollide and hit.Instance.Transparency < 0.9 then
			local hitName = hit.Instance.Name
			if hitName ~= "ArenaGround" and hitName ~= "Baseplate" and hitName ~= "Floor" then
				return false, hit.Position, hit.Instance
			end
		end
	end
	return true
end

function SpatialModule.findNearbyPlatforms(rootPart, maxDist, minHeight, maxHeight)
	maxDist = maxDist or 45
	minHeight = minHeight or 4
	maxHeight = maxHeight or 25
	local pos = rootPart.Position
	local platforms = {}

	local params = RaycastParams.new()
	local exclude = { rootPart.Parent }
	local qs = Workspace:FindFirstChild("QuinServer")
	if qs then table.insert(exclude, qs) end
	local qg = Workspace:FindFirstChild("QuinGhost")
	if qg then table.insert(exclude, qg) end
	params.FilterDescendantsInstances = exclude
	params.FilterType = Enum.RaycastFilterType.Exclude

	local NUM_RAYS = 12
	local seenInstances = {}
	for i = 0, NUM_RAYS - 1 do
		local angle = (i / NUM_RAYS) * math.pi * 2
		local dir = Vector3.new(math.sin(angle), 0, math.cos(angle))
		for d = 12, maxDist, 14 do
			local probe = pos + dir * d
			local rayOrigin = Vector3.new(probe.X, pos.Y + maxHeight + 4, probe.Z)
			local hit = DebugDraw.raycast(rootPart, rayOrigin, Vector3.new(0, -(maxHeight + 8), 0), params)
			if hit and hit.Instance and hit.Instance.CanCollide and not seenInstances[hit.Instance] then
				local heightDiff = hit.Position.Y - pos.Y
				if heightDiff >= minHeight and heightDiff <= maxHeight and hit.Normal.Y > 0.7 then
					seenInstances[hit.Instance] = true
					table.insert(platforms, {
						position = hit.Position,
						normal = hit.Normal,
						heightDiff = heightDiff,
						distance = (hit.Position - pos).Magnitude,
						instance = hit.Instance,
					})
				end
			end
		end
	end
	return platforms
end

function SpatialModule.findCoverPositions(rootPart, enemyPos, maxDist)
	maxDist = maxDist or 35
	local myPos = rootPart.Position
	local coverPositions = {}

	local params = RaycastParams.new()
	local exclude = { rootPart.Parent }
	local qs = Workspace:FindFirstChild("QuinServer")
	if qs then table.insert(exclude, qs) end
	local qg = Workspace:FindFirstChild("QuinGhost")
	if qg then table.insert(exclude, qg) end
	params.FilterDescendantsInstances = exclude
	params.FilterType = Enum.RaycastFilterType.Exclude

	-- Rings out to maxDist (a 3-ring search left a 100-stud hole when the range grew with the arena)
	local rings = { 10, 20 }
	for d = 35, maxDist, 25 do
		table.insert(rings, d)
	end
	if rings[#rings] < maxDist then
		table.insert(rings, maxDist)
	end

	local NUM_SAMPLES = 12
	for i = 0, NUM_SAMPLES - 1 do
		local angle = (i / NUM_SAMPLES) * math.pi * 2
		local dir = Vector3.new(math.sin(angle), 0, math.cos(angle))
		for _, d in ipairs(rings) do
			local samplePos = myPos + dir * d
			local groundHit = DebugDraw.raycast(rootPart, Vector3.new(samplePos.X, myPos.Y + 3, samplePos.Z), Vector3.new(0, -10, 0), params)
			if groundHit then
				local standPos = groundHit.Position + Vector3.new(0, 3, 0)
				local toEnemy = (enemyPos - standPos)
				local enemySight = DebugDraw.raycast(rootPart, standPos, toEnemy, params)
				if enemySight and enemySight.Instance and enemySight.Instance.CanCollide and enemySight.Instance.Transparency < 0.9 then
					local hitName = enemySight.Instance.Name
					if hitName ~= "ArenaGround" and hitName ~= "Baseplate" and hitName ~= "Floor" then
						-- Ensure the Quin can actually reach this cover position from its current position
						local toCover = (standPos - myPos)
						local pathBlocked = DebugDraw.raycast(rootPart, myPos, toCover, params)
						if not pathBlocked then
							table.insert(coverPositions, standPos)
							break
						end
					end
				end
			end
		end
	end
	return coverPositions
end

return SpatialModule

