--// ArenaDroneManager.lua
-- Server-side authoritative controller for physical arena camera drones

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local QuinCore = ReplicatedStorage:WaitForChild("QuinCore")
local DroneTrajectories = require(QuinCore:WaitForChild("ArenaDroneTrajectories"))

local ArenaNetwork = ReplicatedStorage:WaitForChild("ArenaNetwork")
local DroneEvent = ArenaNetwork:WaitForChild("DroneEvent")

local ArenaDroneManager = {}

local drones = {
    Cinematic    = nil,
    ArenaFootage = nil,
    LiveAerial   = nil,
    CombatChase  = nil,
    SkylineOrbit = nil,
}

local isFlying = false
local flightStartTime = 0
local isOutro = false
local outroStartTime = 0
local heartbeatConn = nil

local function getDroneModels()
    local arenaOne = Workspace:FindFirstChild("argoniaonion") and Workspace.argoniaonion:FindFirstChild("ArenaOne")
    if not arenaOne then return end
    
    drones.Cinematic    = arenaOne:FindFirstChild("ArenaDroneCinematic")
    drones.ArenaFootage = arenaOne:FindFirstChild("ArenaDroneArenaFootage")
    drones.LiveAerial   = arenaOne:FindFirstChild("ArenaDroneLiveAerialFootage")
    drones.CombatChase  = arenaOne:FindFirstChild("ArenaDroneCombatChase")
    drones.SkylineOrbit = arenaOne:FindFirstChild("ArenaDroneSkylineOrbit")
    
    for _, model in pairs(drones) do
        if model and not model.PrimaryPart then
            local p = model:FindFirstChild("ArenaDrone")
            if p then model.PrimaryPart = p end
        end
    end
end

-- Position all drones 600 studs above ArenaGround in squadron standby formation
function ArenaDroneManager.resetDrones()
    isFlying = false
    flightStartTime = 0
    isOutro = false
    outroStartTime = 0
    
    if heartbeatConn then
        heartbeatConn:Disconnect()
        heartbeatConn = nil
    end
    
    getDroneModels()
    local _, center, size, radius, minRadius = DroneTrajectories.getArenaMetrics()
    
    for key, model in pairs(drones) do
        if model then
            local cf = DroneTrajectories.getDroneCFrame(key, 0, false, false, 0, center, size, radius, minRadius)
            model:PivotTo(cf)
        end
    end
    
    DroneEvent:FireAllClients("Reset", {
        Center = center,
        Size = size,
        Radius = radius,
        MinRadius = minRadius
    })
    print(string.format("[ArenaDroneManager] 5 Drones positioned 600 studs above ArenaGround at %s.", tostring(center + Vector3.new(0, 600, 0))))
end

-- Starts continuous drone movement (triggered at countdown 4)
function ArenaDroneManager.startDrones()
    if isFlying then return end
    isFlying = true
    isOutro = false
    flightStartTime = os.clock()
    
    getDroneModels()
    local _, center, size, radius, minRadius = DroneTrajectories.getArenaMetrics()
    
    DroneEvent:FireAllClients("Launch", {
        StartTime = flightStartTime,
        Center = center,
        Size = size,
        Radius = radius,
        MinRadius = minRadius
    })
    
    print("[ArenaDroneManager] 5 Drones launched into flight at countdown T-4 with Jet Intro Dive & Camera Flip!")
    
    -- Server physics heartbeat loop
    local lastUpdate = 0
    heartbeatConn = RunService.Heartbeat:Connect(function(dt)
        if not isFlying then return end
        
        local now = os.clock()
        -- Update physical models at ~30Hz on server for optimal network replication
        if now - lastUpdate >= 0.033 then
            lastUpdate = now
            local t = now - flightStartTime
            local outroElapsed = isOutro and (now - outroStartTime) or 0
            local _, curCenter, curSize, curRadius, curMinRadius = DroneTrajectories.getArenaMetrics()
            
            for key, model in pairs(drones) do
                if model then
                    local cf = DroneTrajectories.getDroneCFrame(key, t, isFlying, isOutro, outroElapsed, curCenter, curSize, curRadius, curMinRadius)
                    model:PivotTo(cf)
                end
            end
        end
    end)
end

-- Starts Jet Outro Climb & Camera Flip sequence (triggered during final 15s of post-game)
function ArenaDroneManager.startOutro(duration)
    if not isFlying or isOutro then return end
    isOutro = true
    outroStartTime = os.clock()
    local outroDur = duration or 15
    
    local _, center, size, radius, minRadius = DroneTrajectories.getArenaMetrics()
    DroneEvent:FireAllClients("Outro", {
        OutroStartTime = outroStartTime,
        OutroDuration = outroDur,
        Center = center,
        Size = size,
        Radius = radius,
        MinRadius = minRadius
    })
    
    print(string.format("[ArenaDroneManager] 5 Drones initiated Jet Outro climb & camera flip zoom-out! (%ds duration)", outroDur))
end

function ArenaDroneManager.init()
    getDroneModels()
    ArenaDroneManager.resetDrones()
    print("[ArenaDroneManager] Initialized 5 live footage drones in 600-stud squadron formation.")
end

ArenaDroneManager.init()

return ArenaDroneManager
