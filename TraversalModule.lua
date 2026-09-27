--// TraversalModule.lua
-- Shared spatial probe and parkour planner for player and AI Quins.
-- The module only plans physically continuous trajectories; LocomotionModule applies them.

local Workspace = game:GetService("Workspace")

local TraversalModule = {}

TraversalModule.Config = {
    BodyHeight = 8,
    ProbeDistance = 8,
    StepHeight = 2.2,
    HopHeight = 5.5,
    VaultHeight = 6.8,
    MaxTraversalHeight = 14,
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
    local model = modelFor(rootPart)
    p.FilterDescendantsInstances = model and {model} or {rootPart}
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
    local hit = Workspace:Raycast(origin, Vector3.new(0, -(castHeight or 22) - 28, 0), params)
    if hit and hit.Instance and hit.Instance.CanCollide and hit.Normal.Y >= TraversalModule.Config.MinLandingNormalY then
        return hit
    end
    return nil
end

local function hasClearance(point, rootPart, height)
    local params = rayParams(rootPart)
    local origin = point + Vector3.new(0, 0.35, 0)
    local hit = Workspace:Raycast(origin, Vector3.new(0, height, 0), params)
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
    local obstacle = Workspace:Raycast(chestOrigin, dir * distance, params)
    -- Low sweep catches short parkour obstacles that sit below the chest ray.
    local lowOrigin = rootPart.Position - Vector3.new(0, height * 0.25, 0) + dir * math.max(0.25, radius * 0.35)
    local lowObstacle = Workspace:Raycast(lowOrigin, dir * distance, params)
    local shinOrigin = rootPart.Position - Vector3.new(0, height * 0.45, 0) + dir * math.max(0.25, radius * 0.35)
    local shinObstacle = Workspace:Raycast(shinOrigin, dir * distance, params)
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
    local topHit = Workspace:Raycast(topOrigin, Vector3.new(0, -(TraversalModule.Config.MaxTraversalHeight + height * 1.5), 0), params)
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
    local overhead = Workspace:Raycast(overheadOrigin, dir * math.max(2, distance * 0.65), params)

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
