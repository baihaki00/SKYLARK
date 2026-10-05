--// TraversalModule.lua
-- Shared spatial probe and parkour planner for player and AI Quins.
-- The module only plans physically continuous trajectories; LocomotionModule applies them.

local DebugDraw = require(game:GetService("ReplicatedStorage"):WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("DebugDraw"))
local Workspace = game:GetService("Workspace")
local CombatConfig = require(game:GetService("ReplicatedStorage"):WaitForChild("QuinCore"):WaitForChild("CombatConfig"))

local TraversalModule = {}

TraversalModule.Config = {
    BodyHeight = 8,
    ProbeDistance = 8,
    StepHeight = 2.2,
    HopHeight = 5.5,
    VaultHeight = 6.8,
    MaxTraversalHeight = (CombatConfig.Jump_MaxReach or 25) + 2, -- apex of the highest jump: what it can gain, plus clearance
    MaxGap = 30,
    LandingMargin = 2.5,
    MinLandingNormalY = 0.55,
    MinLandingWidth = 2.4,
}

local function flat(v)
    local f = Vector3.new(v.X, 0, v.Z)
    return f.Magnitude > 0.001 and f.Unit or Vector3.new(0, 0, -1)
end

local function modelFor(rootPart)
    return rootPart and rootPart:FindFirstAncestorOfClass("Model")
end

local function rayParams(rootPart)
    local p = RaycastParams.new()
    p.FilterType = Enum.RaycastFilterType.Exclude
    local filterList = {}
    local model = modelFor(rootPart)
    if model then table.insert(filterList, model) end
    local qServer = Workspace:FindFirstChild("QuinServer")
    if qServer then table.insert(filterList, qServer) end
    local qGhost = Workspace:FindFirstChild("QuinGhost")
    if qGhost then table.insert(filterList, qGhost) end
    p.FilterDescendantsInstances = filterList
    p.IgnoreWater = true
    return p
end

local function bodyMetrics(rootPart)
    local model = modelFor(rootPart)
    local size = model and model:GetExtentsSize() or Vector3.new(4, TraversalModule.Config.BodyHeight, 4)
    local height = math.max(4, size.Y)
    local width = math.max(2, math.max(size.X, size.Z))
    local radius = math.clamp(width * 0.28, 1.0, 3.5)
    return height, width, radius
end

local function groundAt(point, rootPart, castHeight)
    local params = rayParams(rootPart)
    local origin = Vector3.new(point.X, point.Y + (castHeight or 22), point.Z)
    local hit = DebugDraw.raycast(rootPart, origin, Vector3.new(0, -(castHeight or 22) - 28, 0), params)
    if hit and hit.Instance and hit.Instance.CanCollide and hit.Normal.Y >= TraversalModule.Config.MinLandingNormalY then
        return hit
    end
    return nil
end

local function hasClearance(point, rootPart, height)
    local params = rayParams(rootPart)
    local origin = point + Vector3.new(0, 0.35, 0)
    local hit = DebugDraw.raycast(rootPart, origin, Vector3.new(0, height, 0), params)
    return hit == nil
end

local function landingAt(point, rootPart, height)
    local hit = groundAt(point, rootPart, height + 8)
    if not hit then
        return nil
    end
    if not hasClearance(Vector3.new(point.X, hit.Position.Y, point.Z), rootPart, height) then
        return nil
    end
    return {
        position = hit.Position,
        normal = hit.Normal,
        instance = hit.Instance,
    }
end

local function estimateLanding(rootPart, dir, startGroundY, distance, bodyHeight)
    local root = rootPart.Position + dir * distance
    local landing = landingAt(root, rootPart, bodyHeight)
    if not landing then
        return nil
    end
    return {
        position = landing.position,
        distance = distance,
        deltaY = landing.position.Y - startGroundY,
        normal = landing.normal,
        instance = landing.instance,
    }
end

function TraversalModule.getBodyMetrics(rootPart)
    local height, width, radius = bodyMetrics(rootPart)
    return {height = height, width = width, radius = radius}
end

function TraversalModule.probe(rootPart, desiredDirection, requestedDistance)
    if not rootPart or not rootPart.Parent then
        return {kind = "Blocked", reason = "MissingRoot"}
    end

    local height, width, radius = bodyMetrics(rootPart)
    local dir = flat(desiredDirection or rootPart.CFrame.LookVector)
    local params = rayParams(rootPart)
    local ground = groundAt(rootPart.Position, rootPart, height)
    local groundY = ground and ground.Position.Y or (rootPart.Position.Y - height * 0.5)
    local speed = Vector3.new(rootPart.AssemblyLinearVelocity.X, 0, rootPart.AssemblyLinearVelocity.Z).Magnitude
    local distance = requestedDistance or math.clamp(4 + speed * 0.16, 6, TraversalModule.Config.ProbeDistance + 8)

    local chestOrigin = rootPart.Position + Vector3.new(0, math.max(1.5, height * 0.42), 0) + dir * math.max(0.25, radius * 0.35)
    local obstacle = DebugDraw.raycast(rootPart, chestOrigin, dir * distance, params)
    -- Low sweep catches short parkour obstacles that sit below the chest ray.
    local lowOrigin = rootPart.Position - Vector3.new(0, height * 0.25, 0) + dir * math.max(0.25, radius * 0.35)
    local lowObstacle = DebugDraw.raycast(rootPart, lowOrigin, dir * distance, params)
    local shinOrigin = rootPart.Position - Vector3.new(0, height * 0.45, 0) + dir * math.max(0.25, radius * 0.35)
    local shinObstacle = DebugDraw.raycast(rootPart, shinOrigin, dir * distance, params)
    if lowObstacle and (not obstacle or lowObstacle.Distance < obstacle.Distance) then
        obstacle = lowObstacle
    end
    if shinObstacle and (not obstacle or shinObstacle.Distance < obstacle.Distance) then
        obstacle = shinObstacle
    end

    -- Sample the route ahead for a missing floor. This creates a real gap candidate.
    if not obstacle then
        local far = math.clamp(distance + radius * 2, 8, TraversalModule.Config.MaxGap)
        local landing = estimateLanding(rootPart, dir, groundY, far, height)
        if landing and landing.deltaY < -3 then
            return {
                kind = "Drop",
                takeoff = rootPart.Position,
                landing = landing.position,
                landingNormal = landing.normal,
                distance = far,
                deltaY = landing.deltaY,
                bodyHeight = height,
                radius = radius,
                direction = dir,
            }
        end
        local hadGap = false
        local gapStart = nil
        for d = 8, TraversalModule.Config.MaxGap, 4 do
            local sample = groundAt(rootPart.Position + dir * d, rootPart, height)
            if sample then
                if hadGap and ground then
                    return {
                        kind = "LongJump",
                        takeoff = rootPart.Position,
                        landing = sample.Position,
                        distance = d,
                        deltaY = sample.Position.Y - groundY,
                        bodyHeight = height,
                        radius = radius,
                        direction = dir,
                    }
                end
                break
            else
                hadGap = true
                gapStart = gapStart or d
            end
        end
        return {kind = "None", direction = dir, bodyHeight = height, radius = radius}
    end

    if not obstacle.Instance or not obstacle.Instance.CanCollide then
        return {kind = "None", direction = dir, bodyHeight = height, radius = radius}
    end

    local topOrigin = obstacle.Position + Vector3.new(0, TraversalModule.Config.MaxTraversalHeight + height, 0)
    local topHit = DebugDraw.raycast(rootPart, topOrigin, Vector3.new(0, -(TraversalModule.Config.MaxTraversalHeight + height * 1.5), 0), params)
    if not topHit or not topHit.Instance or not topHit.Instance.CanCollide or topHit.Normal.Y < TraversalModule.Config.MinLandingNormalY then
        return {kind = "Blocked", reason = "NoWalkableTop", direction = dir, bodyHeight = height, radius = radius}
    end

    local obstacleHeight = topHit.Position.Y - groundY
    if obstacleHeight < -1 then
        obstacleHeight = 0
    end
    local landingPoint = topHit.Position + dir * (radius + TraversalModule.Config.LandingMargin)
    local landing = landingAt(landingPoint, rootPart, height)
    local overheadOrigin = rootPart.Position + Vector3.new(0, height * 0.72, 0)
    local overhead = DebugDraw.raycast(rootPart, overheadOrigin, dir * math.max(2, distance * 0.65), params)

    if obstacleHeight <= TraversalModule.Config.StepHeight and landing then
        return {
            kind = "StepUp",
            takeoff = rootPart.Position,
            landing = landing.position,
            landingNormal = landing.normal,
            obstacleHeight = obstacleHeight,
            distance = (landing.position - rootPart.Position).Magnitude,
            deltaY = landing.position.Y - rootPart.Position.Y,
            bodyHeight = height,
            radius = radius,
            direction = dir,
        }
    end

    if obstacleHeight <= TraversalModule.Config.VaultHeight and landing and not overhead then
        local kind = obstacleHeight <= TraversalModule.Config.HopHeight and "Hop" or "Vault"
        return {
            kind = kind,
            takeoff = rootPart.Position,
            landing = landing.position,
            landingNormal = landing.normal,
            obstacleHeight = obstacleHeight,
            distance = (landing.position - rootPart.Position).Magnitude,
            deltaY = landing.position.Y - rootPart.Position.Y,
            bodyHeight = height,
            radius = radius,
            direction = dir,
        }
    end

    return {
        kind = "Blocked",
        reason = overhead and "HeadClearance" or "TooHigh",
        obstacleHeight = obstacleHeight,
        direction = dir,
        bodyHeight = height,
        radius = radius,
    }
end

local function solveTrajectory(rootPart, candidate, requestedHeight, forwardSpeed)
    local gravity = Workspace.Gravity
    local start = rootPart.Position
    local target = candidate.landing or (start + candidate.direction * (candidate.distance or 8))
    local deltaY = target.Y - start.Y
    local height = math.clamp(math.max(requestedHeight or 0, candidate.obstacleHeight or 0, deltaY + 3), 3.5, TraversalModule.Config.MaxTraversalHeight)
    local vy = math.sqrt(2 * gravity * height)
    local discriminant = math.max(0, vy * vy - 2 * gravity * deltaY)
    local flightTime = math.max(0.28, (vy + math.sqrt(discriminant)) / gravity)
    local flatTarget = Vector3.new(target.X, start.Y, target.Z)
    local flatDelta = flatTarget - Vector3.new(start.X, start.Y, start.Z)
    local currentSpeed = Vector3.new(rootPart.AssemblyLinearVelocity.X, 0, rootPart.AssemblyLinearVelocity.Z).Magnitude
    local neededSpeed = flatDelta.Magnitude / flightTime
    local horizontalSpeed = math.clamp(math.max(currentSpeed * 0.92, neededSpeed), 14, 58)
    if forwardSpeed and forwardSpeed > 0 then
        horizontalSpeed = math.max(horizontalSpeed, math.min(forwardSpeed, 58))
    end
    local horizontal = flatDelta.Magnitude > 0.01 and flatDelta.Unit * horizontalSpeed or candidate.direction * horizontalSpeed
    return {
        type = candidate.kind,
        animationType = candidate.kind == "Vault" and "vault" or (candidate.kind == "Drop" and "dismount" or ((candidate.kind == "Hop" or candidate.kind == "StepUp") and "hop" or (candidate.kind == "LongJump" and "longjump" or "jump"))),
        height = height,
        flightTime = flightTime,
        horizontalVelocity = horizontal,
        verticalVelocity = vy,
        landing = target,
        obstacleHeight = candidate.obstacleHeight or 0,
        direction = candidate.direction,
    }
end

function TraversalModule.plan(rootPart, desiredDirection, requestedHeight, forwardSpeed)
    if not rootPart or not rootPart.Parent then
        return nil
    end
    local candidate = TraversalModule.probe(rootPart, desiredDirection, nil)
    if candidate.kind == "None" or candidate.kind == "Blocked" then
        return nil, candidate
    end
    local plan = solveTrajectory(rootPart, candidate, requestedHeight, forwardSpeed)
    plan.candidate = candidate
    return plan, candidate
end

-- Would a body launched from where it stands at `launchVelocity` come down somewhere it can
-- stand? Follows the arc of the feet until it meets something.
-- Returns valid, landingPosition, reason ("NoLanding", "HitsWall", "NoHeadroom").
function TraversalModule.validateArc(rootPart, launchVelocity, feetBelowRoot)
    local params = rayParams(rootPart)
    local gravity = Vector3.new(0, -Workspace.Gravity, 0)
    local height = bodyMetrics(rootPart)
    local position = rootPart.Position - Vector3.new(0, feetBelowRoot - 0.6, 0)
    local velocity = launchVelocity
    local step = 0.06
    for _ = 1, 50 do
        local nextPosition = position + velocity * step + 0.5 * gravity * (step * step)
        local hit = DebugDraw.raycast(rootPart, position, nextPosition - position, params)
        if hit and hit.Instance and hit.Instance.CanCollide then
            if hit.Normal.Y < TraversalModule.Config.MinLandingNormalY then
                return false, hit.Position, "HitsWall"
            end
            if not hasClearance(hit.Position, rootPart, height) then
                return false, hit.Position, "NoHeadroom"
            end
            return true, hit.Position, nil
        end
        position = nextPosition
        velocity += gravity * step
    end
    return false, position, "NoLanding"
end

-- The jump that lands a Quin on a surface `rise` studs above its feet whose near edge is
-- `edgeDistance` studs away: { height = apex above the feet, speed = horizontal studs/s }.
-- The feet must clear the lip before they reach it and come down past it, so there is a
-- nearest and a farthest take-off point. Returns nil and why: "TooHigh" (no jump reaches;
-- use a projectile jump), "TooClose" (back off for a run-up), "TooFar" (get nearer).
-- landingDepth (optional): how far past the edge to come down (default Config.LandingMargin,
-- just over the lip; PlatformCatalogue.landingDepth gives the way to the middle of a top).
function TraversalModule.solveJumpOnto(rise, edgeDistance, maxReach, landingDepth)
    if rise > maxReach then
        return nil, "TooHigh"
    end
    local gravity = Workspace.Gravity
    local apex = math.clamp(math.max(rise, 0) + 2, 3.5, TraversalModule.Config.MaxTraversalHeight)
    local up = math.sqrt(2 * gravity * apex)
    local root = math.sqrt(math.max(up * up - 2 * gravity * math.max(rise, 0), 0))
    local clearTime = (up - root) / gravity -- feet pass the height of the top on the way up
    local landTime = (up + root) / gravity -- feet come back down to it
    local speed = math.max((edgeDistance + (landingDepth or TraversalModule.Config.LandingMargin)) / (landTime * 0.92), 10)
    if speed > 58 then
        return nil, "TooFar"
    end
    if speed * clearTime > edgeDistance - 1.0 then
        return nil, "TooClose"
    end
    return { height = apex, speed = speed }
end

-- A jump down off a height, to land `distance` away across the ground and `drop` studs lower.
-- The arc is as big as the distance asks: a hop for a near spot, a full arc for a far one. A
-- spot beyond a jump's speed gets the longest jump that way (it lands short and runs on).
-- Returns { height, speed, flightTime }, or nil when that arc would come down before the ledge
-- (`ledgeDistance` ahead of the jumper, plus `margin`): then it has to get nearer the ledge
-- first. (A first version raised the arc until it cleared the ledge: a near target with the
-- ledge far off got a 15-stud jump straight up that came down where it started.)
local MAX_JUMP_SPEED = 58 -- studs/s across the ground (the same limit solveJumpOnto works to)
local MIN_JUMP_SPEED = 14

function TraversalModule.solveJumpDown(drop, distance, ledgeDistance, margin)
    local gravity = Workspace.Gravity
    local apex = math.clamp(distance * (CombatConfig.Jump_DownArcPerStud or 0.12), 3, TraversalModule.Config.MaxTraversalHeight)
    local riseTime = math.sqrt(2 * apex / gravity)
    local flightTime = riseTime + math.sqrt(2 * (apex + math.max(drop, 0)) / gravity)
    local speed = math.clamp(distance / flightTime, MIN_JUMP_SPEED, MAX_JUMP_SPEED)
    -- (back down at the height it left from, it has to be past the ledge)
    if speed * 2 * riseTime < ledgeDistance + (margin or 2.5) then
        return nil
    end
    return { height = apex, speed = speed, flightTime = flightTime }
end

function TraversalModule.markTraversal(fighter, plan)
    if not fighter or not plan then return end
    fighter:SetAttribute("TraversalType", plan.type)
    fighter:SetAttribute("TraversalPhase", "Anticipation")
    fighter:SetAttribute("TraversalTargetY", plan.landing and plan.landing.Y or 0)
    fighter:SetAttribute("TraversalObstacleHeight", plan.obstacleHeight or 0)
    fighter:SetAttribute("TraversalFlightTime", plan.flightTime or 0)
    fighter:SetAttribute("TraversalStartTime", os.clock())
    task.delay(math.min(0.22, (plan.flightTime or 0.5) * 0.28), function()
        if fighter.Parent then fighter:SetAttribute("TraversalPhase", "Airborne") end
    end)
    task.delay(math.max(0.24, (plan.flightTime or 0.5) * 0.78), function()
        if fighter.Parent then fighter:SetAttribute("TraversalPhase", "LandingApproach") end
    end)
end

function TraversalModule.clearTraversal(fighter)
    if fighter and fighter.Parent then
        fighter:SetAttribute("TraversalPhase", "Recover")
        fighter:SetAttribute("TraversalType", "None")
    end
end

return TraversalModule
