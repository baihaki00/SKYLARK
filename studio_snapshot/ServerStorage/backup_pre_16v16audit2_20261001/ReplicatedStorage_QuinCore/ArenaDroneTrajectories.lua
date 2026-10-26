--// ArenaDroneTrajectories.lua
-- Single Source of Truth for Arena Drone mathematical flight paths, jet intro/outro flips & camera framing

local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

local DroneTrajectories = {}

-- Dynamic ArenaGround metrics calculator (ZERO hardcoding)
function DroneTrajectories.getArenaMetrics()
    local arenaOne = Workspace:FindFirstChild("argoniaonion") and Workspace.argoniaonion:FindFirstChild("ArenaOne")
    local ground = arenaOne and arenaOne:FindFirstChild("ArenaGround") or Workspace:FindFirstChild("ArenaGround", true)
    
    if ground and ground:IsA("BasePart") then
        local cf = ground.CFrame
        local size = ground.Size
        local center = cf.Position + cf.UpVector * (size.Y * 0.5)
        local radius = math.max(size.X, size.Z) * 0.5
        local minRadius = math.min(size.X, size.Z) * 0.5
        return ground, center, size, radius, minRadius
    end
    
    return nil, Vector3.new(0, 2, -438), Vector3.new(600, 4, 600), 300, 300
end

-- Squadron Standby Offsets 600 studs above ArenaGround
local SQUADRON_STANDBY_OFFSETS = {
    Cinematic    = Vector3.new(0, 600, 0),       -- Squadron Lead
    ArenaFootage = Vector3.new(-35, 600, 15),     -- Left Wingman
    LiveAerial   = Vector3.new(35, 600, 15),      -- Right Wingman
    CombatChase  = Vector3.new(-20, 600, 35),     -- Rear Left
    SkylineOrbit = Vector3.new(20, 600, 35),      -- Rear Right
}

function DroneTrajectories.getStandbyCFrame(droneKey, center)
    local offset = SQUADRON_STANDBY_OFFSETS[droneKey] or Vector3.new(0, 600, 0)
    local pos = center + offset
    local lookTarget = center + Vector3.new(offset.X * 0.3, 0, offset.Z * 0.3)
    return CFrame.lookAt(pos, lookTarget)
end

-- Find centroid of active fighting Quins
local function getCombatCentroid(fallbackCenter)
    local sum = Vector3.zero
    local count = 0
    local mostActiveQuin = nil
    local highestSpeed = 0
    
    for _, q in ipairs(CollectionService:GetTagged("Quin")) do
        if q.Parent then
            local hum = q:FindFirstChildOfClass("Humanoid")
            local hrp = q:FindFirstChild("HumanoidRootPart")
            if hum and hum.Health > 0 and hrp then
                sum = sum + hrp.Position
                count = count + 1
                local spd = hrp.AssemblyLinearVelocity.Magnitude
                if spd > highestSpeed or not mostActiveQuin then
                    highestSpeed = spd
                    mostActiveQuin = q
                end
            end
        end
    end
    
    local centroid = (count > 0) and (sum / count) or fallbackCenter
    return centroid, count, mostActiveQuin
end

-- ============================================================================
-- 1. JET INTRO DIVE & CAMERA FLIP (0.0s <= t < 5.0s)
-- High speed 600-stud vertical dive with 360-degree aileron roll / camera flip
-- ============================================================================
local function evaluateJetIntro(startOffset, targetPos, targetLook, t, center, minRadius)
    local introDuration = 5.0
    local alpha = math.clamp(t / introDuration, 0, 1)
    
    -- Smooth acceleration curve (gravity + jet thrust)
    local diveEase = alpha * alpha * (3 - 2 * alpha)
    
    local startPos = center + startOffset
    local currentPos = startPos:Lerp(targetPos, diveEase)
    
    -- Dynamic camera flip / aileron roll during mid-dive (between 1.2s and 3.8s)
    local rollAngle = 0
    if t >= 1.2 and t <= 3.8 then
        local rollAlpha = (t - 1.2) / 2.6
        -- Smooth full 360-degree corkscrew roll
        rollAngle = math.sin(rollAlpha * math.pi) * (math.pi * 2.0)
    end
    
    -- Camera pitch transition: from steep nose-down dive to level target pull-up
    local forwardLook = (targetLook - currentPos).Unit
    local baseCF = CFrame.lookAt(currentPos, currentPos + forwardLook)
    
    return baseCF * CFrame.Angles(0, 0, rollAngle)
end

-- ============================================================================
-- 2. JET OUTRO CLIMB & CAMERA FLIP ZOOM-OUT (Final 15s)
-- Fighter jets pull up into vertical climb, flip camera looking down at stadium
-- ============================================================================
local function evaluateJetOutro(currentPos, center, outroElapsed, minRadius, droneIndex)
    local outroTotal = 15.0
    local p = math.clamp(outroElapsed / outroTotal, 0, 1)
    
    -- Outro Phase 1 (0 to 4s): Level speed-run & pitch up
    -- Outro Phase 2 (4 to 10s): High vertical climb + camera flip looking back down
    -- Outro Phase 3 (10 to 15s): Zooming out past 650 studs into the clouds
    
    local climbEase = p * p * (3 - 2 * p)
    local climbHeight = currentPos.Y + (620 - currentPos.Y) * climbEase
    
    -- Break formation outward based on droneIndex
    local spreadAngle = ((droneIndex or 1) - 1) * (math.pi * 2 / 5)
    local spreadDist = p * (minRadius * 0.8)
    local posX = currentPos.X + math.cos(spreadAngle) * spreadDist * (p > 0.3 and (p - 0.3) / 0.7 or 0)
    local posZ = currentPos.Z + math.sin(spreadAngle) * spreadDist * (p > 0.3 and (p - 0.3) / 0.7 or 0)
    local pos = Vector3.new(posX, climbHeight, posZ)
    
    -- Camera flip during climb (between 4s and 9s): rolls inverted so camera points back at arena
    local rollAngle = 0
    if outroElapsed >= 4.0 and outroElapsed <= 9.0 then
        local rollAlpha = (outroElapsed - 4.0) / 5.0
        rollAngle = math.sin(rollAlpha * math.pi) * math.pi
    end
    
    -- Look back at Arena Center shrinking below
    local lookTarget = center + Vector3.new(0, 10, 0)
    local baseCF = CFrame.lookAt(pos, lookTarget)
    
    return baseCF * CFrame.Angles(0, 0, rollAngle)
end

-- ============================================================================
-- 3. SPECIFIC DRONE TRAJECTORIES
-- ============================================================================

-- 1. ArenaDroneCinematic: Lead Drone
function DroneTrajectories.getCinematicCFrame(t, isFlying, isOutro, outroElapsed, center, size, radius, minRadius)
    if not isFlying or t <= 0 then
        return DroneTrajectories.getStandbyCFrame("Cinematic", center)
    end
    
    -- Outro Override (Last 15 seconds)
    if isOutro and outroElapsed and outroElapsed > 0 then
        local normalCF = DroneTrajectories.getCinematicCFrame(t, isFlying, false, 0, center, size, radius, minRadius)
        return evaluateJetOutro(normalCF.Position, center, outroElapsed, minRadius, 1)
    end
    
    -- Intro Jet Dive (0 to 5.0s) from 600 studs
    if t < 5.0 then
        local targetPos = center + Vector3.new(0, 36, minRadius * 0.72)
        local targetLook = center + Vector3.new(0, 10, 0)
        return evaluateJetIntro(SQUADRON_STANDBY_OFFSETS.Cinematic, targetPos, targetLook, t, center, minRadius)
    end
    
    -- Standard Operational Flight:
    local normalT = t - 5.0
    -- Phase B: 360 Stadium Perimeter Orbit (0 <= normalT < 9.5)
    if normalT < 9.5 then
        local progress = normalT / 9.5
        local angle = (math.pi * 0.5) + progress * math.pi * 2.0
        local orbitR = minRadius * 0.72
        local x = center.X + math.cos(angle) * orbitR
        local z = center.Z + math.sin(angle) * orbitR
        local y = center.Y + 38 + math.sin(progress * math.pi * 4) * 8
        local pos = Vector3.new(x, y, z)
        
        local lookAheadAngle = angle + 0.35
        local lookTarget = center + Vector3.new(math.cos(lookAheadAngle) * (orbitR * 0.25), 8, math.sin(lookAheadAngle) * (orbitR * 0.25))
        return CFrame.lookAt(pos, lookTarget)
    else
        -- Phase C: Continuous Traversal & Fight Inspection
        local dt = normalT - 9.5
        local combatCentroid, quinCount = getCombatCentroid(center)
        local inspectAngle = dt * 0.45
        local inspectRadius = (quinCount > 0) and math.clamp(minRadius * 0.25, 25, 60) or (minRadius * 0.45)
        local baseHeight = (quinCount > 0) and (combatCentroid.Y + 20) or (center.Y + 30)
        
        local x = combatCentroid.X + math.cos(inspectAngle) * inspectRadius + math.sin(dt * 0.2) * 12
        local z = combatCentroid.Z + math.sin(inspectAngle) * inspectRadius + math.cos(dt * 0.2) * 12
        local y = baseHeight + math.sin(dt * 0.5) * 6
        local pos = Vector3.new(x, y, z)
        
        local lookTarget = combatCentroid + Vector3.new(0, 4, 0)
        return CFrame.lookAt(pos, lookTarget)
    end
end

-- 2. ArenaDroneArenaFootage: Agile Broadcast Drone
function DroneTrajectories.getArenaFootageCFrame(t, isFlying, isOutro, outroElapsed, center, size, radius, minRadius)
    if not isFlying or t <= 0 then
        return DroneTrajectories.getStandbyCFrame("ArenaFootage", center)
    end
    
    if isOutro and outroElapsed and outroElapsed > 0 then
        local normalCF = DroneTrajectories.getArenaFootageCFrame(t, isFlying, false, 0, center, size, radius, minRadius)
        return evaluateJetOutro(normalCF.Position, center, outroElapsed, minRadius, 2)
    end
    
    if t < 4.8 then
        local targetPos = center + Vector3.new(-minRadius * 0.45, 28, -minRadius * 0.3)
        local targetLook = center + Vector3.new(0, 6, 0)
        return evaluateJetIntro(SQUADRON_STANDBY_OFFSETS.ArenaFootage, targetPos, targetLook, t, center, minRadius)
    end
    
    -- Continuous broadcast drone traversal with banking
    local dt = t - 4.8
    local freqX = 0.22
    local freqZ = 0.31
    local freqY = 0.40
    
    local x = center.X + math.sin(dt * freqX) * (minRadius * 0.60) + math.cos(dt * 0.07) * (minRadius * 0.15)
    local z = center.Z + math.sin(dt * freqZ) * (minRadius * 0.60) + math.sin(dt * 0.05) * (minRadius * 0.15)
    local y = center.Y + 26 + math.sin(dt * freqY) * 14 + math.cos(dt * 0.11) * 6
    local pos = Vector3.new(x, y, z)
    
    local nextX = center.X + math.sin((dt + 0.1) * freqX) * (minRadius * 0.60) + math.cos((dt + 0.1) * 0.07) * (minRadius * 0.15)
    local nextZ = center.Z + math.sin((dt + 0.1) * freqZ) * (minRadius * 0.60) + math.sin((dt + 0.1) * 0.05) * (minRadius * 0.15)
    local nextY = center.Y + 26 + math.sin((dt + 0.1) * freqY) * 14 + math.cos((dt + 0.1) * 0.11) * 6
    local forwardVel = Vector3.new(nextX - x, nextY - y, nextZ - z).Unit
    
    local lookTarget = pos + forwardVel * 30 + Vector3.new(0, -6, 0)
    local baseCF = CFrame.lookAt(pos, lookTarget)
    local rollAngle = math.clamp(math.sin(dt * freqX * 2.0) * 0.32, -0.45, 0.45)
    return baseCF * CFrame.Angles(0, 0, rollAngle)
end

-- 3. ArenaDroneLiveAerialFootage: High 360 Tactical Orbit
function DroneTrajectories.getLiveAerialCFrame(t, isFlying, isOutro, outroElapsed, center, size, radius, minRadius)
    if not isFlying or t <= 0 then
        return DroneTrajectories.getStandbyCFrame("LiveAerial", center)
    end
    
    if isOutro and outroElapsed and outroElapsed > 0 then
        local normalCF = DroneTrajectories.getLiveAerialCFrame(t, isFlying, false, 0, center, size, radius, minRadius)
        return evaluateJetOutro(normalCF.Position, center, outroElapsed, minRadius, 3)
    end
    
    local targetAltitude = center.Y + 235
    local orbitRadius = minRadius * 0.52
    
    if t < 5.0 then
        local targetPos = center + Vector3.new(orbitRadius, targetAltitude, 0)
        local targetLook = center + Vector3.new(0, 4, 0)
        return evaluateJetIntro(SQUADRON_STANDBY_OFFSETS.LiveAerial, targetPos, targetLook, t, center, minRadius)
    end
    
    local orbitSpeed = 0.075
    local angle = t * orbitSpeed
    local x = center.X + math.cos(angle) * orbitRadius
    local z = center.Z + math.sin(angle) * orbitRadius
    local pos = Vector3.new(x, targetAltitude, z)
    
    local lookTarget = center + Vector3.new(0, 4, 0)
    return CFrame.lookAt(pos, lookTarget)
end

-- 4. ArenaDroneCombatChase: Wingman Action Chase Drone (CAM 4)
function DroneTrajectories.getCombatChaseCFrame(t, isFlying, isOutro, outroElapsed, center, size, radius, minRadius)
    if not isFlying or t <= 0 then
        return DroneTrajectories.getStandbyCFrame("CombatChase", center)
    end
    
    if isOutro and outroElapsed and outroElapsed > 0 then
        local normalCF = DroneTrajectories.getCombatChaseCFrame(t, isFlying, false, 0, center, size, radius, minRadius)
        return evaluateJetOutro(normalCF.Position, center, outroElapsed, minRadius, 4)
    end
    
    if t < 4.5 then
        local targetPos = center + Vector3.new(0, 22, -minRadius * 0.35)
        local targetLook = center + Vector3.new(0, 5, 0)
        return evaluateJetIntro(SQUADRON_STANDBY_OFFSETS.CombatChase, targetPos, targetLook, t, center, minRadius)
    end
    
    -- Chase active fighter
    local combatCentroid, quinCount, targetQuin = getCombatCentroid(center)
    local targetHRP = targetQuin and targetQuin:FindFirstChild("HumanoidRootPart")
    
    if targetHRP then
        local quinCF = targetHRP.CFrame
        local quinVel = targetHRP.AssemblyLinearVelocity
        local horizVel = Vector3.new(quinVel.X, 0, quinVel.Z)
        
        -- Fly slightly behind and above over the shoulder
        local backOffset = -quinCF.LookVector * 22 + Vector3.new(0, 10, 0) + quinCF.RightVector * 8
        local pos = targetHRP.Position + backOffset
        local lookTarget = targetHRP.Position + quinCF.LookVector * 12 + Vector3.new(0, 3, 0)
        
        -- Bank with turn
        local bank = math.clamp(-quinCF.RightVector:Dot(horizVel.Unit) * 0.35, -0.4, 0.4)
        return CFrame.lookAt(pos, lookTarget) * CFrame.Angles(0, 0, bank)
    else
        -- Fallback: Low-altitude midfield sweep
        local dt = t - 4.5
        local x = center.X + math.cos(dt * 0.35) * (minRadius * 0.45)
        local z = center.Z + math.sin(dt * 0.45) * (minRadius * 0.45)
        local y = center.Y + 16 + math.sin(dt * 0.8) * 4
        return CFrame.lookAt(Vector3.new(x, y, z), center + Vector3.new(0, 4, 0))
    end
end

-- 5. ArenaDroneSkylineOrbit: Stadium Skyline Panorama Drone (CAM 5)
function DroneTrajectories.getSkylineOrbitCFrame(t, isFlying, isOutro, outroElapsed, center, size, radius, minRadius)
    if not isFlying or t <= 0 then
        return DroneTrajectories.getStandbyCFrame("SkylineOrbit", center)
    end
    
    if isOutro and outroElapsed and outroElapsed > 0 then
        local normalCF = DroneTrajectories.getSkylineOrbitCFrame(t, isFlying, false, 0, center, size, radius, minRadius)
        return evaluateJetOutro(normalCF.Position, center, outroElapsed, minRadius, 5)
    end
    
    local targetAlt = center.Y + 140
    local skylineRadius = radius * 1.05
    
    if t < 5.2 then
        local targetPos = center + Vector3.new(-skylineRadius, targetAlt, 0)
        local targetLook = center + Vector3.new(0, 20, 0)
        return evaluateJetIntro(SQUADRON_STANDBY_OFFSETS.SkylineOrbit, targetPos, targetLook, t, center, minRadius)
    end
    
    local orbitSpeed = 0.055
    local angle = t * orbitSpeed + math.pi * 0.3
    local x = center.X + math.cos(angle) * skylineRadius
    local z = center.Z + math.sin(angle) * skylineRadius
    local y = targetAlt + math.sin(t * 0.15) * 15
    local pos = Vector3.new(x, y, z)
    
    local lookTarget = center + Vector3.new(0, 15, 0)
    return CFrame.lookAt(pos, lookTarget)
end

-- Unified router
function DroneTrajectories.getDroneCFrame(droneKey, t, isFlying, isOutro, outroElapsed, center, size, radius, minRadius)
    if droneKey == "Cinematic" then
        return DroneTrajectories.getCinematicCFrame(t, isFlying, isOutro, outroElapsed, center, size, radius, minRadius)
    elseif droneKey == "ArenaFootage" then
        return DroneTrajectories.getArenaFootageCFrame(t, isFlying, isOutro, outroElapsed, center, size, radius, minRadius)
    elseif droneKey == "LiveAerial" then
        return DroneTrajectories.getLiveAerialCFrame(t, isFlying, isOutro, outroElapsed, center, size, radius, minRadius)
    elseif droneKey == "CombatChase" then
        return DroneTrajectories.getCombatChaseCFrame(t, isFlying, isOutro, outroElapsed, center, size, radius, minRadius)
    elseif droneKey == "SkylineOrbit" then
        return DroneTrajectories.getSkylineOrbitCFrame(t, isFlying, isOutro, outroElapsed, center, size, radius, minRadius)
    else
        return DroneTrajectories.getCinematicCFrame(t, isFlying, isOutro, outroElapsed, center, size, radius, minRadius)
    end
end

return DroneTrajectories
