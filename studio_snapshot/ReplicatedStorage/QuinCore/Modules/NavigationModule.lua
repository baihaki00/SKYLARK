--// NavigationModule.lua
-- Can a Quin get to its target on foot, and if not, which way round.
-- Fight and Chase used to treat "close" as "reachable": two Quins on either side of a wall
-- 40 studs tall, 10 studs apart, stood in Fight facing each other for the rest of the match,
-- and a Quin under a platform its target stood on ran in circles below it.
--   isReachable(rootPart, targetRoot)  -> bool, reason ("height" | "blocked")
--   detourWaypoint(fighter, rootPart, targetPosition) -> next point of a path round, or nil
-- Paths come from PathfindingService, computed in the background (the state loop never waits)
-- and refreshed when old or when the target has moved.

local GameClock = require(game:GetService("ReplicatedStorage"):WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("GameClock")) -- (the game's clock: a freeze stops it)
local Workspace = game:GetService("Workspace")
local PathfindingService = game:GetService("PathfindingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CombatConfig = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("CombatConfig"))

local NavigationModule = {}

local MAX_HEIGHT_ON_FOOT = 7 -- studs of height between the two above which it is not a walk-up
-- studs above the root: obstacles below this are stepped, skidded or hurdled. The sweep's
-- underside sits ~10 studs above the feet, so jumpable bars (up to Hurdle_MaxRise) are not
-- walls: at 4.5 an 8-stud bar on a raised lane sent the Quin looking for a path round, off the edge.
local SWEEP_HEIGHT = 7
local SWEEP_RADIUS = 2.0 -- about the body's half width: a thinner sweep passed lines the body could not (grazing a pillar)

local function sweepParams(a, b)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { a, b, Workspace:FindFirstChild("QuinServer") }
	params.RespectCanCollide = true
	return params
end

function NavigationModule.isReachable(rootPart, targetRoot)
	if not rootPart or not targetRoot then return true end
	local from, to = rootPart.Position, targetRoot.Position
	if math.abs(to.Y - from.Y) > (CombatConfig.Nav_MaxHeightOnFoot or MAX_HEIGHT_ON_FOOT) then
		return false, "height"
	end
	local lift = Vector3.new(0, CombatConfig.Nav_SweepHeight or SWEEP_HEIGHT, 0)
	local offset = (to + lift) - (from + lift)
	if offset.Magnitude < 0.5 then return true end
	local params = sweepParams(rootPart.Parent, targetRoot.Parent)
	local hit = Workspace:Spherecast(from + lift, SWEEP_RADIUS, offset, params)
	if hit then
		return false, "blocked"
	end
	-- and at chest height: the sweep above runs over the head, so a wall about as tall as the
	-- Quins was not "in the way" and two of them fought (and hit) across it (owner 2026-10-27)
	local chest = Vector3.new(0, 1.5, 0)
	local offsetChest = (to + chest) - (from + chest)
	if offsetChest.Magnitude > 0.5 and Workspace:Spherecast(from + chest, 0.6, offsetChest, params) then
		return false, "wall"
	end
	return true
end

-- Whether a strike can land from here. A walk allows Nav_MaxHeightOnFoot (7) studs of height
-- (isReachable), but no limb reaches a body more than Fight_StrikeMaxRise above or Fight_StrikeMaxDrop
-- below (the clips land from 2.8 below the root to 1.7 above; a body spans 3 below to 2.5 above),
-- and nothing solid may stand between the two chests. (Owner's bookmarks 2026-10-29: two Quins 7
-- studs apart, one on a box, traded strikes - and hits - through its edge for seconds.)
-- Fight does not strike without it and hands over to Chase; Chase does not hand back until it
-- holds, and climbs or drops in the meantime. Switch: Fight_StrikeHeightCheck = false.
function NavigationModule.canStrikeAt(rootPart, targetRoot)
	if CombatConfig.Fight_StrikeHeightCheck == false or not rootPart or not targetRoot then return true end
	local rise = targetRoot.Position.Y - rootPart.Position.Y
	if rise > (CombatConfig.Fight_StrikeMaxRise or 4.5) then return false, "above" end
	if rise < -(CombatConfig.Fight_StrikeMaxDrop or 5) then return false, "below" end
	local chest = Vector3.new(0, 1, 0)
	local offset = (targetRoot.Position + chest) - (rootPart.Position + chest)
	if offset.Magnitude > 0.5 and Workspace:Raycast(rootPart.Position + chest, offset, sweepParams(rootPart.Parent, targetRoot.Parent)) then
		return false, "wall"
	end
	return true
end

-- Nothing in the way on a straight walk to a point (at the Quin's own height)
function NavigationModule.isClearTo(rootPart, point)
	if not rootPart then return true end
	local lift = Vector3.new(0, CombatConfig.Nav_SweepHeight or SWEEP_HEIGHT, 0)
	local from = rootPart.Position + lift
	local offset = Vector3.new(point.X, rootPart.Position.Y, point.Z) + lift - from
	if offset.Magnitude < 0.5 then return true end
	return Workspace:Spherecast(from, SWEEP_RADIUS, offset, sweepParams(rootPart.Parent)) == nil
end

-- Something low right ahead that the sweep above passes over (waist-high cover, a low
-- platform): how high its top is over the feet, or nil. A low wall stopped a walking Quin dead.
function NavigationModule.lowObstacle(rootPart, humanoid, direction, distance)
	if not rootPart or direction.Magnitude < 0.1 then return nil end
	local dir = Vector3.new(direction.X, 0, direction.Z).Unit
	local feetY = rootPart.Position.Y - (humanoid and humanoid.HipHeight or 2) - rootPart.Size.Y / 2
	local from = Vector3.new(rootPart.Position.X, feetY + 3.2, rootPart.Position.Z)
	local params = sweepParams(rootPart.Parent)
	local hit = Workspace:Spherecast(from, 1.2, dir * distance, params)
	if not hit or hit.Normal.Y > 0.5 then
		-- a knee-high step passes under that sweep (its bottom is 2 studs up): a lower one (owner
		-- 2026-10-27, "stuck, bro just kept walking": a Quin walked into the 2-stud orb pedestal)
		hit = Workspace:Spherecast(Vector3.new(from.X, feetY + 1.1, from.Z), 0.6, dir * distance, params)
		if not hit or hit.Normal.Y > 0.5 then return nil end
	end
	local probe = hit.Position + dir * 0.8
	local top = Workspace:Raycast(Vector3.new(probe.X, feetY + 16, probe.Z), Vector3.new(0, -16, 0), params)
	if not top then return nil end
	return top.Position.Y - feetY
end

local paths = setmetatable({}, { __mode = "k" }) -- fighter -> { waypoints, index, time, goal, computing }

local function requestPath(fighter, rootPart, goal)
	local entry = paths[fighter]
	if not entry then
		entry = {}
		paths[fighter] = entry
	end
	if entry.computing then return end
	entry.computing = true
	local start = rootPart.Position
	task.spawn(function()
		local path = PathfindingService:CreatePath({
			AgentRadius = CombatConfig.Nav_AgentRadius or 2.5,
			AgentHeight = 8,
			AgentCanJump = true,
			WaypointSpacing = 6,
		})
		local ok = pcall(function()
			path:ComputeAsync(start, goal)
		end)
		entry.computing = false
		entry.time = GameClock.now()
		entry.goal = goal
		if ok and path.Status == Enum.PathStatus.Success then
			entry.waypoints = path:GetWaypoints()
			entry.index = 2
		else
			entry.waypoints = nil
		end
	end)
end

-- The next point to steer to on a way round, or nil (no path yet / none found)
function NavigationModule.detourWaypoint(fighter, rootPart, targetPosition)
	local entry = paths[fighter]
	local now = GameClock.now()
	local stale = not entry or not entry.time or now - entry.time > (CombatConfig.Nav_PathRefresh or 1.0)
		or (entry.goal and (entry.goal - targetPosition).Magnitude > 10)
	if stale then
		requestPath(fighter, rootPart, targetPosition)
	end
	entry = paths[fighter]
	if not entry or not entry.waypoints then return nil end
	local waypoints = entry.waypoints
	-- Skip the points already reached
	while entry.index <= #waypoints do
		local point = waypoints[entry.index].Position
		local flat = Vector3.new(point.X - rootPart.Position.X, 0, point.Z - rootPart.Position.Z)
		if flat.Magnitude > 4 then break end
		entry.index += 1
	end
	local waypoint = waypoints[entry.index]
	if not waypoint then return nil end
	-- Off the path (thrown by a knockback, carried by a slide): a path from where it used to
	-- be leads the wrong way, so plan again from here
	local gap = Vector3.new(waypoint.Position.X - rootPart.Position.X, 0, waypoint.Position.Z - rootPart.Position.Z)
	if gap.Magnitude > (CombatConfig.Nav_OffPathDistance or 24) then
		entry.waypoints = nil
		requestPath(fighter, rootPart, targetPosition)
		return nil
	end
	return waypoint.Position, waypoint.Action == Enum.PathWaypointAction.Jump
end

-- Stepping stones. A target standing on something well above the Quin is climbed to through
-- whatever surfaces are around: the solid, level top (2.5+ studs wide, room to stand) that
-- makes the most progress toward the target (height still to climb + half the flat distance
-- left), with a small extra cost for distance and for hops higher than a jump. Nothing is
-- named or placed for this; any geometry works. Returns { point, rise, hop, part } or nil
-- (the target is not above, or nothing nearer to it can be reached).
local STONE_SEARCH_RADIUS = 70
local STONE_MIN_WIDTH = 2.5
local STONE_INSET = 1.2

-- Stones it hopped for and did not end up on (a head into a canopy, a top that was not one):
-- skipped for Nav_StoneFailMemory seconds, so it does not try the same one over and over.
-- fighter -> { try = { part, at }, failed = { [part] = until } }
local stoneTries = setmetatable({}, { __mode = "k" })

function NavigationModule.noteStoneTry(fighter, part)
	local entry = stoneTries[fighter] or { failed = {} }
	stoneTries[fighter] = entry
	entry.try = { part = part, at = os.clock() }
end

-- Visible anchored geometry in a column above a point (non-collidable leaves count: a body
-- jumping up through them looks wrong, and the solid blocks inside a canopy hide in them)
local function columnBlocked(origin, height, exclude)
	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Exclude
	overlap.FilterDescendantsInstances = exclude
	local box = CFrame.new(origin + Vector3.new(0, 0.3 + height / 2, 0))
	for _, p in ipairs(Workspace:GetPartBoundsInBox(box, Vector3.new(2, height, 2), overlap)) do
		if p.Anchored and (p.CanCollide or p.Transparency < 0.95) then
			return true
		end
	end
	return false
end

function NavigationModule.nextStone(fighter, rootPart, targetRoot, minClimb)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { fighter, targetRoot.Parent, Workspace:FindFirstChild("QuinServer") }
	params.RespectCanCollide = true
	local here = rootPart.Position
	local myFloor = Workspace:Raycast(here, Vector3.new(0, -9, 0), params)
	local targetFloor = Workspace:Raycast(targetRoot.Position, Vector3.new(0, -9, 0), params)
	if not myFloor or not targetFloor then return nil end -- in the air, or not standing on anything
	local fy, ty = myFloor.Position.Y, targetFloor.Position.Y
	-- How the last hop went: standing on the stone it went for, or not (judged once it is down)
	local tries = stoneTries[fighter]
	if tries and tries.try and os.clock() - tries.try.at > 1.5 then
		if myFloor.Instance ~= tries.try.part then
			tries.failed[tries.try.part] = os.clock() + (CombatConfig.Nav_StoneFailMemory or 20)
			fighter:SetAttribute("StoneFails", (fighter:GetAttribute("StoneFails") or 0) + 1) -- (probes)
		end
		tries.try = nil
	end
	local failed = tries and tries.failed or {}
	-- Little room over its own head (under a canopy, a ledge): only stones it moves out to
	local lowCeiling = Workspace:Raycast(here, Vector3.new(0, 10, 0), params) ~= nil
	local exclude = { fighter, targetRoot.Parent, Workspace:FindFirstChild("QuinServer") }
	-- (a few studs up is a run and a vault, not a climb)
	if ty - fy < (minClimb or CombatConfig.Nav_StoneMinClimb or 8) then return nil end

	local function remaining(position, topY)
		local flat = Vector3.new(targetRoot.Position.X - position.X, 0, targetRoot.Position.Z - position.Z).Magnitude
		return math.abs(ty - topY) + 0.5 * flat
	end
	local now = remaining(here, fy)

	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Exclude
	overlap.FilterDescendantsInstances = { fighter, Workspace:FindFirstChild("QuinServer") }
	local best = nil
	for _, part in ipairs(Workspace:GetPartBoundsInRadius(here, STONE_SEARCH_RADIUS, overlap)) do
		if part.Anchored and part.CanCollide and part ~= myFloor.Instance and math.abs(part.CFrame.UpVector.Y) > 0.98
			and math.min(part.Size.X, part.Size.Z) >= STONE_MIN_WIDTH
			and not (failed[part] and failed[part] > os.clock()) then
			local topY = part.Position.Y + part.Size.Y / 2
			local rise = topY - fy
			if rise >= 1.5 and rise <= (CombatConfig.Nav_StoneMaxRise or 40) then
				local rel = part.CFrame:PointToObjectSpace(here)
				-- (aimed well in from the rim, toward the middle of the top: at the rim's inset alone
				-- every hop landed on the edge)
				local inX = math.max(STONE_INSET, math.min(part.Size.X * 0.3, CombatConfig.Jump_LandingDepthMax or 8))
				local inZ = math.max(STONE_INSET, math.min(part.Size.Z * 0.3, CombatConfig.Jump_LandingDepthMax or 8))
				local hx = math.max(part.Size.X / 2 - inX, 0)
				local hz = math.max(part.Size.Z / 2 - inZ, 0)
				local point = part.CFrame:PointToWorldSpace(Vector3.new(math.clamp(rel.X, -hx, hx), part.Size.Y / 2, math.clamp(rel.Z, -hz, hz)))
				-- A real top: a ray down at the point lands on this part (a mesh's box top is not a
				-- surface: tree trunks were taken for stones). Room to stand: nothing within 8 studs
				-- overhead, leaves included (blocks hidden inside canopies were picked, and Quins
				-- hit their heads on the leaves going up to them).
				local surface = Workspace:Raycast(point + Vector3.new(0, 1.5, 0), Vector3.new(0, -3, 0), params)
				local hopOut = Vector3.new(point.X - here.X, 0, point.Z - here.Z).Magnitude
				if surface and surface.Instance == part
					and not Workspace:Raycast(point + Vector3.new(0, 0.2, 0), Vector3.new(0, 8, 0), params)
					and not columnBlocked(point, 8, exclude)
					and not (lowCeiling and hopOut < (CombatConfig.Nav_StoneCeilingHop or 10)) then
					local left = remaining(point, topY)
					local hop = Vector3.new(point.X - here.X, 0, point.Z - here.Z).Magnitude
					if left < now - 4 and hop <= (CombatConfig.Nav_StoneMaxHop or 60) then
						local cost = left + 0.3 * hop + (rise > 12 and 6 or 0)
						if not best or cost < best.cost then
							best = { point = point, rise = rise, hop = hop, part = part, cost = cost }
						end
					end
				end
			end
		end
	end
	return best
end

function NavigationModule.clear(fighter)
	paths[fighter] = nil
end

return NavigationModule
