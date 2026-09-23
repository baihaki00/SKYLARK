--// SpatialModule.lua
-- Environment awareness: obstacle detection, edge detection, intercept prediction

local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")

local SpatialModule = {}

local function drawDebugRay(origin, direction, hitResult)
	if not Workspace:GetAttribute("Debug_Rays") then return end
	local part = Instance.new("Part")
	part.Name = "DebugRay"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Material = Enum.Material.Neon
	
	local distance = hitResult and (origin - hitResult.Position).Magnitude or direction.Magnitude
	part.Size = Vector3.new(0.15, 0.15, distance)
	-- LookAt can error if direction is 0,0,0 but direction shouldn't be
	if direction.Magnitude > 0.001 then
		part.CFrame = CFrame.lookAt(origin, origin + direction) * CFrame.new(0, 0, -distance/2)
	end
	
	if hitResult then
		part.Color = Color3.new(1, 0, 0) -- Extra red when it touches
		part.Transparency = 0.0 
	else
		part.Color = Color3.new(0, 1, 0) -- Green when missing
		part.Transparency = 0.5 -- Visible enough to see it
	end
	
	local highlight = Instance.new("Highlight")
	highlight.Adornee = part
	highlight.FillColor = part.Color
	highlight.OutlineColor = Color3.new(1, 1, 1)
	highlight.FillTransparency = part.Transparency
	highlight.OutlineTransparency = 0
	highlight.Parent = part
	
	part.Parent = Workspace
	Debris:AddItem(part, 0.1)
end

-- Raycast forward from rootPart to detect obstacles
function SpatialModule.raycastForward(rootPart, distance)
	distance = distance or 10
	local params = RaycastParams.new()
	params.FilterDescendantsInstances = {rootPart.Parent}
	params.FilterType = Enum.RaycastFilterType.Exclude
	
	local origin = rootPart.Position
	local direction = rootPart.CFrame.LookVector * distance
	local result = Workspace:Raycast(origin, direction, params)
	drawDebugRay(origin, direction, result)
	
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
	
	local result = Workspace:Raycast(rootPart.Position, Vector3.new(0, -maxDistance, 0), params)
	if result then
		local groundDist = (rootPart.Position - result.Position).Magnitude
		return true, groundDist, result.Position, result.Normal
	end
	return false, maxDistance, nil, nil
end

-- Check if near an edge by raycasting down at forward+left+right offsets
function SpatialModule.isNearArenaEdge(rootPart, threshold)
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
		local result = Workspace:Raycast(checkPos, Vector3.new(0, -20, 0), params)
		if not result then
			-- No ground found at this offset = edge detected
			return true, -offset.Unit -- Return direction AWAY from edge
		end
	end
	return false, Vector3.zero
end

-- Get a safe direction to move when obstacles are ahead
function SpatialModule.getObstacleAvoidanceDirection(rootPart, checkDistance)
	checkDistance = checkDistance or 8
	local params = RaycastParams.new()
	params.FilterDescendantsInstances = {rootPart.Parent}
	params.FilterType = Enum.RaycastFilterType.Exclude
	
	local forward = rootPart.CFrame.LookVector
	local right = rootPart.CFrame.RightVector
	
	-- Check forward
	local fwd = Workspace:Raycast(rootPart.Position, forward * checkDistance, params)
	if not fwd then
		return forward -- Clear ahead
	end
	
	-- Check right
	local rgt = Workspace:Raycast(rootPart.Position, right * checkDistance, params)
	if not rgt then
		return right
	end
	
	-- Check left
	local lft = Workspace:Raycast(rootPart.Position, -right * checkDistance, params)
	if not lft then
		return -right
	end
	
	-- Check backward
	return -forward
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
	
	local result = Workspace:Raycast(rootPart.Position, Vector3.new(0, -checkDistance, 0), params)
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
	local arenaGround = arenaRoot and arenaRoot:FindFirstChild("ArenaGround")
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
		local rHit = Workspace:Raycast(rOrigin, dir * checkDistance, params)
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

	-- Measure height of obstacle by casting down from above hit position
	local maxCheckH = 80
	local upRayOrigin = hit.Position + Vector3.new(0, maxCheckH, 0)
	local downHit = Workspace:Raycast(upRayOrigin, Vector3.new(0, -maxCheckH * 1.5, 0), params)

	local topY = downHit and downHit.Position.Y or (hit.Position.Y + 2.0)
	-- Actual ground level beneath the Quin (raycast, matching isGrounded's skin calibration;
	-- a fixed -2.5 offset under-measured low OBs and caused "stuck on feet")
	local groundRay = Workspace:Raycast(rootPart.Position, Vector3.new(0, -20, 0), params)
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
		local testHit = Workspace:Raycast(waistOrigin, testDir * (checkDistance * 0.9), params)
		if not testHit then
			local dot = testDir:Dot(dir)
			if dot > bestDot then
				bestDot = dot
				bestSteerDir = testDir
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
		local hit = Workspace:Raycast(targetPos + Vector3.new(0, 2, 0), Vector3.new(0, -10, 0))
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
		local hit = Workspace:Raycast(upOrigin, Vector3.new(0, -(maxReach + 4), 0), params)
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
	-- Ray forward at upper-body height to catch a low ceiling the Quin would hit its head on
	local origin = Vector3.new(pos.X, pos.Y - 1.0, pos.Z)
	local dir = rootPart.CFrame.LookVector * forwardDist
	local hit = Workspace:Raycast(origin, dir, params)
	if not hit or not hit.Instance then return nil end

	local part = hit.Instance
	local isOB = (part.Name == "OB" or part.Name:find("OB") ~= nil)
	if not isOB then return nil end

	-- Estimate the obstacle's bottom edge (axis-aligned placeholder)
	local bottomY = part.Position.Y - (part.Size.Y / 2)
	local groundY = pos.Y - 5.4 -- feet (skin bottom)
	local gapHeight = bottomY - groundY

	if gapHeight > 0.8 and gapHeight < 3.5 then
		return { bottomY = bottomY, gapHeight = gapHeight, part = part }
	end
	return nil
end

-- Detect a viable vertical surface to initiate an athletic Wall-Run (Phase 6 Parkour).
-- Scans left and right at torso height for near-vertical obstacles at an incident angle.
-- Returns: { hitPart, hitPosition, normal, tangent, side, distance } or nil
function SpatialModule.detectWallRunSurface(rootPart, checkDist)
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
		local hit = Workspace:Raycast(origin, probe.dir, params)
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

						if isObstacle then
							drawDebugRay(origin, probe.dir, hit)
							return {
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

	-- Arena center (flat)
	local arenaCenter = Vector3.zero
	local arenaRadius = 290 -- default fallback
	local arenaGround = Workspace:FindFirstChild("argoniaonion") and Workspace.argoniaonion:FindFirstChild("ArenaGround")
	if arenaGround then
		arenaCenter = Vector3.new(arenaGround.Position.X, 0, arenaGround.Position.Z)
		arenaRadius = math.min(arenaGround.Size.X, arenaGround.Size.Z) / 2
	end

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
		local edgeCheck = Workspace:Raycast(
			Vector3.new(candidateTarget.X, myPos.Y + 2, candidateTarget.Z),
			Vector3.new(0, -20, 0),
			params
		)
		if not edgeCheck then
			-- No ground at candidate position = arena edge / void
			score = score - 2.0 * boundaryPenaltyWeight
		end

		-- 4. Obstacle Clearance: raycast in candidate direction for blocking geometry
		local obstacleHit = Workspace:Raycast(myPos, candidateDir * searchRadius, params)
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

-- Detect whether this Quin is currently perched on an elevated OB platform.
-- Returns (isElevated, info) where info = { part, surfaceY, elevation, isOB }.
function SpatialModule.isOnElevatedPlatform(rootPart, threshold)
	threshold = threshold or 6.0
	if not rootPart then return false, nil end

	local pos = rootPart.Position

	local params = RaycastParams.new()
	params.FilterDescendantsInstances = { rootPart.Parent }
	params.FilterType = Enum.RaycastFilterType.Exclude

	-- Surface directly beneath the Quin's feet
	local hit = Workspace:Raycast(pos + Vector3.new(0, 0.5, 0), Vector3.new(0, -60, 0), params)
	if not hit then return false, nil end

	local surfacePart = hit.Instance
	local surfaceY = hit.Position.Y
	local isOB = (surfacePart.Name == "OB" or surfacePart.Name:find("OB") ~= nil or surfacePart.Name:find("Platform") ~= nil)

	-- Measure vertical drop from this surface down to the arena floor,
	-- excluding the platform part itself so we pierce through to real ground.
	local gapParams = RaycastParams.new()
	gapParams.FilterDescendantsInstances = { rootPart.Parent, surfacePart }
	gapParams.FilterType = Enum.RaycastFilterType.Exclude
	local floorHit = Workspace:Raycast(Vector3.new(pos.X, surfaceY - 0.5, pos.Z), Vector3.new(0, -300, 0), gapParams)
	local floorY = floorHit and floorHit.Position.Y or surfaceY
	local elevation = surfaceY - floorY

	local info = {
		part = surfacePart,
		surfaceY = surfaceY,
		elevation = elevation,
		isOB = isOB,
	}

	if isOB and elevation >= threshold then
		return true, info
	end
	return false, info
end

-- Find the nearest safe ledge direction to dismount an elevated platform,
-- biased toward the target position or open ground.
function SpatialModule.getPlatformDismountDirection(rootPart, targetPos)
	if not rootPart then return Vector3.new(0, 0, -1) end

	local _, info = SpatialModule.isOnElevatedPlatform(rootPart)
	local platformPart = info and info.part
	if not platformPart then
		-- Not on a platform; no dismount needed.
		if targetPos then
			local tDir = Vector3.new(targetPos.X - rootPart.Position.X, 0, targetPos.Z - rootPart.Position.Z)
			if tDir.Magnitude > 0.01 then return tDir.Unit end
		end
		return SpatialModule.getArenaCenterDirection(rootPart)
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

	local rayCount = 12
	local maxRange = 15.0
	local bestDir = nil
	local bestScore = -math.huge

	for i = 0, rayCount - 1 do
		local angle = (i / rayCount) * math.pi * 2
		local dir = Vector3.new(math.sin(angle), 0, math.cos(angle))

		-- Step outward to find the first distance where the platform surface ends
		local edgeDist = nil
		for _, d in ipairs({ 3, 6, 9, 12, 15 }) do
			local probe = pos + dir * d
			local hit = Workspace:Raycast(Vector3.new(probe.X, pos.Y + 1, probe.Z), Vector3.new(0, -40, 0), params)
			if (not hit) or (hit.Instance ~= platformPart) then
				edgeDist = d
				break
			end
		end

		if edgeDist then
			local score = 0
			if targetDir.Magnitude > 0.01 then
				score = score + dir:Dot(targetDir) * 2.0
			end
			score = score + (1.0 - edgeDist / maxRange) * 1.0
			if score > bestScore then
				bestScore = score
				bestDir = dir
			end
		end
	end

	if bestDir then return bestDir end
	if targetDir.Magnitude > 0.01 then return targetDir end
	return SpatialModule.getArenaCenterDirection(rootPart)
end

-- ============================================================
-- LINE OF SIGHT & ENVIRONMENTAL SENSING (Section 41 & 44)
-- ============================================================

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

	params.FilterDescendantsInstances = exclude
	params.FilterType = Enum.RaycastFilterType.Exclude

	local hit = Workspace:Raycast(posA, diff, params)
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
		for _, d in ipairs({ 12, 22, 35, maxDist }) do
			local probe = pos + dir * d
			local rayOrigin = Vector3.new(probe.X, pos.Y + maxHeight + 4, probe.Z)
			local hit = Workspace:Raycast(rayOrigin, Vector3.new(0, -(maxHeight + 8), 0), params)
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

	local NUM_SAMPLES = 8
	for i = 0, NUM_SAMPLES - 1 do
		local angle = (i / NUM_SAMPLES) * math.pi * 2
		local dir = Vector3.new(math.sin(angle), 0, math.cos(angle))
		for _, d in ipairs({ 10, 20, maxDist }) do
			local samplePos = myPos + dir * d
			local groundHit = Workspace:Raycast(Vector3.new(samplePos.X, myPos.Y + 3, samplePos.Z), Vector3.new(0, -10, 0), params)
			if groundHit then
				local standPos = groundHit.Position + Vector3.new(0, 3, 0)
				local toEnemy = (enemyPos - standPos)
				local enemySight = Workspace:Raycast(standPos, toEnemy, params)
				if enemySight and enemySight.Instance and enemySight.Instance.CanCollide and enemySight.Instance.Transparency < 0.9 then
					local hitName = enemySight.Instance.Name
					if hitName ~= "ArenaGround" and hitName ~= "Baseplate" and hitName ~= "Floor" then
						-- Ensure the Quin can actually reach this cover position from its current position
						local toCover = (standPos - myPos)
						local pathBlocked = Workspace:Raycast(myPos, toCover, params)
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

