local GASPStateGraph = {}

function GASPStateGraph.resolve(input)
    input = input or {}
    local speed = tonumber(input.speed) or 0
    local grounded = input.grounded ~= false
    local verticalVelocity = tonumber(input.verticalVelocity) or 0
    local intent = input.intent or {}
    local intentDir = intent.direction
    local hasIntent = intentDir and intentDir.Magnitude > 0.05
    local characterForward = input.characterForward or Vector3.new(0, 0, -1)
    local characterRight = input.characterRight or Vector3.new(1, 0, 0)
    local previousMode = input.previousMode or "Idle"
    local previousAction = input.previousAction or "Loop"
    local timeInAction = input.timeInAction or 1.0

    -- 1. Airborne & Landing
    if not grounded then
        if verticalVelocity > 2 or intent.jump then
            return {
                mode = "Jump",
                action = "Start",
                direction = "Forward",
                speed = speed,
            }
        else
            return {
                mode = "Jump",
                action = "Loop",
                direction = "Forward",
                speed = speed,
            }
        end
    end

    if input.landing or (previousMode == "Jump" and grounded and timeInAction < 0.45) then
        return {
            mode = "Jump",
            action = "Stop",
            direction = "Forward",
            speed = speed,
            lockDuration = 0.45,
        }
    end

    -- 2. Directional Angle relative to character heading
    local angleDeg = 0
    local direction = "Forward"
    if hasIntent then
        local fwdDot = math.clamp(characterForward:Dot(intentDir.Unit), -1, 1)
        local rightDot = characterRight:Dot(intentDir.Unit)
        angleDeg = math.deg(math.atan2(rightDot, fwdDot))
        if math.abs(angleDeg) <= 45 then
            direction = "Forward"
        elseif angleDeg >= -135 and angleDeg < -45 then
            direction = "Left"
        elseif angleDeg > 45 and angleDeg <= 135 then
            direction = "Right"
        else
            direction = "Backward"
        end
    end

    -- 3. Sharp 180° Directional Reversal / Skid Turn
    if (previousMode == "Run" or previousMode == "Sprint" or speed > 15) and hasIntent then
        local fwdDot = characterForward:Dot(intentDir.Unit)
        if (fwdDot < -0.42 or input.isSkidReversal) and (previousAction ~= "Turn" or timeInAction > 0.5) then
            local turnSide = (angleDeg < 0) and "L" or "R"
            return {
                mode = "Run",
                action = "Turn",
                direction = (turnSide == "L" and "Left" or "Right"),
                turnAngle = 180,
                turnSide = turnSide,
                speed = 16,
                lockDuration = 0.45,
            }
        end
    end

    -- If a locked one-shot action (Turn, Stop, Start) is actively playing, keep it until its lockDuration
    if input.lockedAction and timeInAction < input.lockedDuration then
        return input.lockedQuery
    end

    -- 4. Stationary & Idle
    if not hasIntent and speed < 1.0 then
        -- In-place turning while stationary
        if input.inPlaceTurnAngle and math.abs(input.inPlaceTurnAngle) > 40 then
            local turnSide = input.inPlaceTurnAngle < 0 and "L" or "R"
            local turnAngle = math.abs(input.inPlaceTurnAngle) > 135 and 180 or 90
            return {
                mode = "Idle",
                action = "Turn",
                direction = (turnSide == "L" and "Left" or "Right"),
                turnAngle = turnAngle,
                turnSide = turnSide,
                speed = 0,
                lockDuration = (turnAngle == 180 and 0.50 or 0.35),
            }
        end

        return {
            mode = "Idle",
            action = "Loop",
            direction = "Neutral",
            speed = 0,
        }
    end

    -- 5. Braking / Stop (Moving -> Input released)
    if not hasIntent and speed >= 1.0 then
        local stopMode = (speed > 26 or previousMode == "Sprint") and "Sprint"
            or (speed > 13 or previousMode == "Run") and "Run"
            or "Walk"
        return {
            mode = stopMode,
            action = "Stop",
            direction = "Forward",
            speed = 0,
            lockDuration = (stopMode == "Sprint" and 0.55 or 0.45),
        }
    end

    -- 6. Moving: Determine Gait Mode
    local currentMode
    if intent.sprint or speed > 26 then
        currentMode = "Sprint"
    elseif intent.run or speed > 13 then
        currentMode = "Run"
    else
        currentMode = "Walk"
    end

    -- 7. Start Push-Off (from Rest to Moving)
    if (previousMode == "Idle" or (previousAction == "Stop" and timeInAction > 0.3)) and hasIntent and speed < 12 then
        return {
            mode = currentMode,
            action = "Start",
            direction = "Forward",
            speed = (currentMode == "Sprint" and 32 or (currentMode == "Run" and 24 or 12)),
            lockDuration = 0.35,
        }
    end

    -- 8. Gait Transitions (Walk <-> Run, Run <-> Sprint)
    if previousAction == "Loop" and previousMode ~= currentMode then
        if (previousMode == "Walk" and currentMode == "Run") or
           (previousMode == "Run" and currentMode == "Walk") or
           (previousMode == "Run" and currentMode == "Sprint") or
           (previousMode == "Sprint" and currentMode == "Run") then
            return {
                mode = "Transition",
                action = "Transition",
                fromMode = previousMode,
                toMode = currentMode,
                direction = "Forward",
                speed = speed,
                lockDuration = 0.30,
            }
        end
    end

    -- 9. Locomotion Loop (Steady movement with directional strafe)
    return {
        mode = currentMode,
        action = "Loop",
        direction = direction,
        speed = speed,
    }
end

return GASPStateGraph
