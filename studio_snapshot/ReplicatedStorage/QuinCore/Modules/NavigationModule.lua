--// NavigationModule.lua
-- Can a Quin get to its target on foot, and if not, which way round.
-- Fight and Chase used to treat "close" as "reachable": two Quins on either side of a wall
-- 40 studs tall, 10 studs apart, stood in Fight facing each other for the rest of the match,
-- and a Quin under a platform its target stood on ran in circles below it.
--   isReachable(rootPart, targetRoot)  -> bool, reason ("height" | "blocked")
--   detourWaypoint(fighter, rootPart, targetPosition) -> next point of a path round, or nil
-- Paths come from PathfindingService, computed in the background (the state loop never waits)
-- and refreshed when old or when the target has moved.

local Workspace = game:GetService("Workspace")
local PathfindingService = game:GetService("PathfindingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CombatConfig = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("CombatConfig"))

local NavigationModule = {}

local MAX_HEIGHT_ON_FOOT = 7 -- studs of height between the two above which it is not a walk-up
local SWEEP_HEIGHT = 4.5 -- studs above the root: obstacles below this are stepped, vaulted or jumped
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
	local hit = Workspace:Spherecast(from + lift, SWEEP_RADIUS, offset, sweepParams(rootPart.Parent, targetRoot.Parent))
	if hit then
		return false, "blocked"
	end
	return true
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
		entry.time = os.clock()
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
	local now = os.clock()
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

function NavigationModule.clear(fighter)
	paths[fighter] = nil
end

return NavigationModule
