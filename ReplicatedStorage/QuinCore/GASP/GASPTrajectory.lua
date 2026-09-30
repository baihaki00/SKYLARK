local GASPTrajectory = {}

local DEFAULTS = {
    WalkSpeed = 12,
    RunSpeed = 24,
    SprintSpeed = 32,
    GroundAcceleration = 52,
    GroundBraking = 68,
    AirAcceleration = 18,
    TurnRate = math.rad(420),
    PredictionHorizon = 0.55,
    PredictionSamples = 6,
}

local function planar(v)
    return Vector3.new(v.X, 0, v.Z)
end

local function safeUnit(v, fallback)
    local p = planar(v)
    if p.Magnitude > 1e-4 then return p.Unit end
    return fallback or Vector3.new(0, 0, -1)
end

local function approachVector(current, target, maxDelta)
    local delta = target - current
    if delta.Magnitude <= maxDelta then return target end
    return current + delta.Unit * maxDelta
end

local function maxSpeedForIntent(intent, params)
    if intent.sprint then return params.SprintSpeed end
    if intent.run then return params.RunSpeed end
    return params.WalkSpeed
end

function GASPTrajectory.defaults(overrides)
    local params = table.clone(DEFAULTS)
    for key, value in pairs(overrides or {}) do
        if params[key] ~= nil then params[key] = value end
    end
    return params
end

function GASPTrajectory.new(rootCFrame, overrides)
    local params = GASPTrajectory.defaults(overrides)
    local forward = safeUnit(rootCFrame.LookVector)
    return {
        position = rootCFrame.Position,
        velocity = Vector3.zero,
        acceleration = Vector3.zero,
        forward = forward,
        desiredDirection = forward,
        grounded = true,
        surfaceNormal = Vector3.yAxis,
        phaseDistance = 0,
        params = params,
    }
end

function GASPTrajectory.step(state, intent, dt)
    dt = math.clamp(tonumber(dt) or 1/60, 1/240, 1/10)
    intent = intent or {}
    local params = state.params or DEFAULTS
    local requested = safeUnit(intent.direction or state.desiredDirection, state.forward)
    local maxSpeed = maxSpeedForIntent(intent, params)
    local targetVelocity = requested * maxSpeed
    local currentPlanar = planar(state.velocity)
    local accel = targetVelocity.Magnitude > currentPlanar.Magnitude
        and params.GroundAcceleration
        or params.GroundBraking
    if not state.grounded then accel = params.AirAcceleration end

    local nextVelocity = approachVector(currentPlanar, targetVelocity, accel * dt)
    local nextForward = state.forward
    if nextVelocity.Magnitude > 0.05 then
        local desiredAngle = math.atan2(nextVelocity.X, -nextVelocity.Z)
        local currentAngle = math.atan2(nextForward.X, -nextForward.Z)
        local delta = (desiredAngle - currentAngle + math.pi) % (2 * math.pi) - math.pi
        local maxTurn = params.TurnRate * dt
        local applied = math.clamp(delta, -maxTurn, maxTurn)
        local angle = currentAngle + applied
        nextForward = Vector3.new(math.sin(angle), 0, -math.cos(angle))
    end

    local nextAcceleration = (nextVelocity - currentPlanar) / dt
    local displacement = nextVelocity * dt
    state.position += displacement
    state.velocity = Vector3.new(nextVelocity.X, state.velocity.Y, nextVelocity.Z)
    state.acceleration = nextAcceleration
    state.forward = nextForward
    state.desiredDirection = requested
    state.phaseDistance += nextVelocity.Magnitude * dt
    return state
end

function GASPTrajectory.predict(state, intent, horizon, samples)
    local copy = {
        position = state.position,
        velocity = state.velocity,
        acceleration = state.acceleration,
        forward = state.forward,
        desiredDirection = state.desiredDirection,
        grounded = state.grounded,
        surfaceNormal = state.surfaceNormal,
        phaseDistance = state.phaseDistance,
        params = state.params,
    }
    horizon = horizon or copy.params.PredictionHorizon
    samples = samples or copy.params.PredictionSamples
    local result = {}
    local dt = horizon / math.max(samples, 1)
    for index = 1, samples do
        GASPTrajectory.step(copy, intent, dt)
        result[index] = {
            t = dt * index,
            position = copy.position,
            velocity = copy.velocity,
            forward = copy.forward,
        }
    end
    return result
end

function GASPTrajectory.phase(state, strideLength)
    strideLength = strideLength or 4.2
    return (state.phaseDistance / strideLength) % 1
end

return GASPTrajectory
