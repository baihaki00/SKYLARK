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

-- Drone look (ArenaConfig.DroneVisuals): body and trail half see-through so they don't get in
-- the way of the arena; name tags shown, faded out after a few seconds, or hidden
local ArenaConfigOk, ArenaConfigModule = pcall(function()
    return require(game:GetService("ReplicatedStorage"):WaitForChild("QuinCore"):WaitForChild("ArenaConfig"))
end)
local function droneVisuals()
    local v = ArenaConfigOk and ArenaConfigModule and ArenaConfigModule.DroneVisuals or {}
    return {
        PartTransparency = v.PartTransparency or 0.5,
        TrailTransparency = v.TrailTransparency or 0.5,
        LabelMode = v.LabelMode or "fade",   -- "on" | "fade" | "off"
        LabelFadeAfter = v.LabelFadeAfter or 3,
        LabelFadeTime = v.LabelFadeTime or 1,
    }
end

local labelToken = 0
local function applyDroneLook(showLabelsNow)
    local v = droneVisuals()
    labelToken += 1
    local token = labelToken
    for _, model in pairs(drones) do
        if model then
            local body = model:FindFirstChild("ArenaDrone")
            if body and body:IsA("BasePart") then body.Transparency = v.PartTransparency end
            for _, d in ipairs(model:GetDescendants()) do
                if d:IsA("Trail") then
                    d.Transparency = NumberSequence.new(v.TrailTransparency, 1)
                elseif d:IsA("BillboardGui") then
                    local label = d:FindFirstChildWhichIsA("TextLabel")
                    if v.LabelMode == "off" then
                        d.Enabled = false
                    else
                        d.Enabled = true
                        if label then
                            label.TextTransparency = 0
                            label.TextStrokeTransparency = math.max(label.TextStrokeTransparency, 0)
                        end
                        if v.LabelMode == "fade" and label and showLabelsNow ~= false then
                            task.delay(v.LabelFadeAfter, function()
                                if token ~= labelToken then return end
                                game:GetService("TweenService"):Create(label, TweenInfo.new(v.LabelFadeTime), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
                                task.delay(v.LabelFadeTime, function()
                                    if token == labelToken then d.Enabled = false end
                                end)
                            end)
                        end
                    end
                end
            end
        end
    end
end
ArenaDroneManager.applyDroneLook = applyDroneLook

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
    
    applyDroneLook(true) -- names show at launch, then fade (DroneVisuals.LabelMode)
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
    applyDroneLook(true)
    ArenaDroneManager.resetDrones()
    print("[ArenaDroneManager] Initialized 5 live footage drones in 600-stud squadron formation.")
end

ArenaDroneManager.init()

return ArenaDroneManager
