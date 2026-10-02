--// ArenaSystemOrchestrator.server.lua
-- Single Source of Truth for Argonia ArenaOne Lifecycle & Production Broadcast State Machine
-- Controls: 120s Pre-Combat Sequence, Dynamic Back-Timed Stadium Anthem (Ends at T=59s, 1s Reverb Ring-Out),
-- T+5.0s Authoritative Hologram Materialization, Clean ARIA Voice Scheduling & Quin Pacification

local Workspace = game:GetService("Workspace")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local ArenaConfig = require(ReplicatedStorage.QuinCore.ArenaConfig)
local ArenaAudio = require(ServerScriptService:WaitForChild("ArenaAudioManager"))
local ArenaScreen = require(ServerScriptService:WaitForChild("ArenaScreenManager"))
local ArenaAria = require(ServerScriptService:WaitForChild("ArenaAriaManager"))
local ArenaFireworks = require(ServerScriptService:WaitForChild("ArenaFireworksManager"))
local ArenaDroneManager = require(ServerScriptService:WaitForChild("ArenaDroneManager"))
local QuinSpawner = require(ServerScriptService:WaitForChild("QuinSpawner"))

local Orchestrator = {}

local currentPhase = "IDLE"
local phaseEndTime = 0
local skipRequested = false
local matchThread = nil

local activeConfig = {
    Mode = "4vs4",
    TeamSize = 4,
    SelectedTrack = "365",
    SelectedAnthem = "ANTHEM1",
    SelectedInTrack = "365",
    SelectedPostTrack = "365",
    Toggles = {
        Screen = true,
        Fireworks = true,
        ProceduralMusic = true,
        Announcer = true,
        Drones = true,
    }
}

local matchStats = {
    StartTime = 0,
    Winner = nil,
    WinnerTeam = nil,
    EndReason = nil,
}

-- Ensure network remotes exist
local function ensureNetwork()
    local netFolder = ReplicatedStorage:FindFirstChild("ArenaNetwork")
    if not netFolder then
        netFolder = Instance.new("Folder")
        netFolder.Name = "ArenaNetwork"
        netFolder.Parent = ReplicatedStorage
    end

    local function getOrCreate(name, className)
        local inst = netFolder:FindFirstChild(name)
        if not inst then
            inst = Instance.new(className)
            inst.Name = name
            inst.Parent = netFolder
        end
        return inst
    end

    return {
        StartMatch = getOrCreate("StartMatch", "RemoteFunction"),
        StopMatch = getOrCreate("StopMatch", "RemoteEvent"),
        SkipPhase = getOrCreate("SkipPhase", "RemoteEvent"),
        UpdateToggles = getOrCreate("UpdateToggles", "RemoteEvent"),
        StateReplication = getOrCreate("StateReplication", "RemoteEvent"),
        Announce = getOrCreate("Announce", "RemoteEvent"),
        PlayTrack = getOrCreate("PlayTrack", "RemoteEvent"),
        DroneEvent = getOrCreate("DroneEvent", "RemoteEvent"),
        UpdateAudioSettings = getOrCreate("UpdateAudioSettings", "RemoteEvent"),
    }
end

local remotes = ensureNetwork()
local StateReplication = remotes.StateReplication

local function replicateState()
    local remaining = math.max(0, phaseEndTime - os.clock())
    local alphaHp, alphaMax, betaHp, betaMax, alphaAlive, betaAlive = Orchestrator.getTeamHealthStats()
    
    local snapshot = {
        Phase = currentPhase,
        TimeRemaining = remaining,
        TotalPhaseDuration = phaseEndTime - (phaseEndTime - remaining),
        AlphaHp = alphaHp,
        AlphaMax = alphaMax,
        BetaHp = betaHp,
        BetaMax = betaMax,
        AlphaAlive = alphaAlive,
        BetaAlive = betaAlive,
        Toggles = activeConfig.Toggles,
    }
    
    StateReplication:FireAllClients(snapshot)
    
    if activeConfig.Toggles.Screen then
        ArenaScreen.setEnabled(true)
        ArenaScreen.updateMatchState(currentPhase, remaining, alphaHp, alphaMax, betaHp, betaMax, alphaAlive, betaAlive)
    else
        ArenaScreen.setEnabled(false)
    end
end

local function getTournamentFighters()
    local fighters = {}
    local qServer = Workspace:FindFirstChild("QuinServer")
    if qServer then
        for _, child in ipairs(qServer:GetChildren()) do
            if child:IsA("Model") and CollectionService:HasTag(child, "AI_Fighter") and not child:GetAttribute("IsPlayerControlled") and not child:GetAttribute("IsCostume") then
                table.insert(fighters, child)
            end
        end
    end
    return fighters
end

function Orchestrator.getTeamHealthStats()
    local alphaHp, alphaMax, alphaAlive = 0, 0, 0
    local betaHp, betaMax, betaAlive = 0, 0, 0
    
    for _, quin in ipairs(getTournamentFighters()) do
        if quin.Parent then
            local hum = quin:FindFirstChildOfClass("Humanoid")
            if hum then
                local team = quin:GetAttribute("Team")
                local hp = math.max(0, hum.Health)
                local maxHp = hum.MaxHealth
                local isAlive = hp > 0
                
                if team == "TeamAlpha" then
                    alphaHp = alphaHp + hp
                    alphaMax = alphaMax + maxHp
                    if isAlive then alphaAlive = alphaAlive + 1 end
                elseif team == "TeamBeta" then
                    betaHp = betaHp + hp
                    betaMax = betaMax + maxHp
                    if isAlive then betaAlive = betaAlive + 1 end
                else
                    alphaHp = alphaHp + hp
                    alphaMax = alphaMax + maxHp
                    if isAlive then alphaAlive = alphaAlive + 1 end
                end
            end
        end
    end
    
    return alphaHp, alphaMax, betaHp, betaMax, alphaAlive, betaAlive
end

local function waitPhaseDuration(duration)
    phaseEndTime = os.clock() + duration
    skipRequested = false
    
    while os.clock() < phaseEndTime and not skipRequested do
        replicateState()
        task.wait(0.25)
    end
    skipRequested = false
end

local function pacifyAllQuins()
    for _, q in ipairs(getTournamentFighters()) do
        q:SetAttribute("IsInert", true)
        q:SetAttribute("InCombat", false)
        q:SetAttribute("ForceState", "Idle")
        q:SetAttribute("CurrentState", "Idle")
        q:SetAttribute("TargetQuin", nil)
        q:SetAttribute("CurrentTarget", nil)
        local hum = q:FindFirstChildOfClass("Humanoid")
        local hrp = q:FindFirstChild("HumanoidRootPart")
        if hum then hum.WalkSpeed = 0 end
        if hrp then hrp.AssemblyLinearVelocity = Vector3.zero end
    end
end

-- ============================================================================
-- LIFECYCLE STATE MACHINE (120s TO IN-GAME)
-- ============================================================================

local function runMatchLifecycle()
    -- -------------------------------------------------------------
    -- PHASE 1: ARENA OPEN (10 SECONDS)
    -- Holograms start invisible, ignite at T+5.0s
    -- -------------------------------------------------------------
    currentPhase = "ARENA_OPEN"
    print("[ArenaSystemOrchestrator] Entering Phase: ARENA_OPEN (10s)")
    
    Workspace:SetAttribute("ArenaHologramsActive", false)
    ArenaScreen.setHologramActive(false)
    ArenaScreen.setTitle("ARENA ONE", "GATES ARE OPEN • PREPARING MATCH")
    
    if activeConfig.Toggles.Fireworks then
        ArenaFireworks.launchOpeningShow(10)
    end
    
    -- Pre-Game music begins (spans Open, Generation, Prep Room = 50s total)
    if activeConfig.Toggles.ProceduralMusic then
        ArenaAudio.playPregameMusic(activeConfig.SelectedTrack or "365", 1.0, 2.0)
    end
    
    if activeConfig.Toggles.Announcer then
        ArenaAria.speak("ARIA_ArenaOpen")
    end
    
    -- T+5.0s Hologram Ignition
    task.delay(5.0, function()
        if currentPhase == "ARENA_OPEN" or currentPhase == "ARENA_GENERATION" then
            print("[ArenaSystemOrchestrator] T+5s: Holographic materialization active!")
            Workspace:SetAttribute("ArenaHologramsActive", true)
            ArenaScreen.setHologramActive(true)
            
            -- Authoritative Server Globe ForceField Hologram Ignition
            local arenaOne = Workspace:FindFirstChild("argoniaonion") and Workspace.argoniaonion:FindFirstChild("ArenaOne")
            local globe = arenaOne and arenaOne:FindFirstChild("ArenaGlobe")
            if globe then
                globe.Material = Enum.Material.ForceField
                globe.Color = Color3.fromRGB(0, 210, 255)
                globe.Transparency = 0.45
            end
        end
    end)
    
    waitPhaseDuration(10)
    
    -- -------------------------------------------------------------
    -- PHASE 2: ARENA GENERATION (10 SECONDS)
    -- -------------------------------------------------------------
    currentPhase = "ARENA_GENERATION"
    print("[ArenaSystemOrchestrator] Entering Phase: ARENA_GENERATION (10s)")
    
    ArenaScreen.setTitle("ARENA GENERATION", "CONFIGURING COMBAT SECTOR")
    
    if activeConfig.Toggles.Announcer then
        ArenaAria.speak("ARIA_ArenaGenerationCommence")
    end
    
    task.delay(5.5, function()
        if currentPhase == "ARENA_GENERATION" and activeConfig.Toggles.Announcer then
            ArenaAria.speak("ARIA_ArenaGenerationCompleted")
        end
    end)
    
    waitPhaseDuration(10)
    
    -- -------------------------------------------------------------
    -- PHASE 3: PREPARATION ROOM (30 SECONDS)
    -- Fighters calibrating in staging backrooms. ZERO Quins on field!
    -- -------------------------------------------------------------
    currentPhase = "PREPARATION_ROOM"
    print("[ArenaSystemOrchestrator] Entering Phase: PREPARATION_ROOM (30s)")
    
    QuinSpawner.cleanAll()
    Workspace:SetAttribute("MatchStarted", false)
    
    ArenaScreen.setTitle("PREPARATION ROOM", "FIGHTERS CALIBRATING IN BACKROOMS • 30 SECONDS")
    
    if activeConfig.Toggles.Announcer then
        ArenaAria.speak("ARIA_AnnouncementPreparationRoomGuide")
    end
    
    waitPhaseDuration(30)
    
    -- -------------------------------------------------------------
    -- PHASE 4: TELEPORTING QUINS TO DESIGNATED AREAS (5 SECONDS)
    -- Pre-Game music fades out, Quins spawn onto the field!
    -- -------------------------------------------------------------
    currentPhase = "TELEPORTING_QUINS"
    print("[ArenaSystemOrchestrator] Entering Phase: TELEPORTING_QUINS (5s)")
    
    -- Smooth fade out of Pre-Game music
    ArenaAudio.stopPregameMusic(1.5)
    
    ArenaScreen.setTitle("DEPLOYMENT TELEPORT", "MATERIALIZING FIGHTERS AT COMBAT STATIONS")
    ArenaScreen.displayAnnouncement("TELEPORTING QUINS TO DESIGNATED AREAS", 3.0, "ARENA DISPATCH", Color3.fromRGB(0, 220, 255))
    
    if activeConfig.Toggles.Announcer then
        ArenaAria.speak("ARIA_TeleportingQuinsToDesignatedAreas")
    end
    
    -- Authoritative Field Spawning
    local mode = activeConfig.Mode
    local teamSize = activeConfig.TeamSize or 4
    local positions = QuinSpawner.getSpawnPositions()
    local posAlpha = positions[1] or Vector3.new(158, 2.05, -605)
    local posBeta = positions[2] or Vector3.new(-137, 2.05, -233)
    local forwardDir = (posBeta - posAlpha).Unit
    local sideDir = Vector3.new(-forwardDir.Z, 0, forwardDir.X)
    
    if mode == "1vs1" then
        local p1 = Vector3.new(posAlpha.X * 0.4 + posBeta.X * 0.6, posAlpha.Y, posAlpha.Z * 0.4 + posBeta.Z * 0.6)
        local p2 = Vector3.new(posBeta.X * 0.4 + posAlpha.X * 0.6, posBeta.Y, posBeta.Z * 0.4 + posAlpha.Z * 0.6)
        local qA = QuinSpawner.spawn("Male", p1, "TeamAlpha")
        local qB = QuinSpawner.spawn("Female", p2, "TeamBeta")
        if qA then
            qA:PivotTo(CFrame.lookAt(p1, Vector3.new(p2.X, p1.Y, p2.Z)))
            qA:SetAttribute("CurrentState", "Idle")
            qA:SetAttribute("IsInert", true)
        end
        if qB then
            qB:PivotTo(CFrame.lookAt(p2, Vector3.new(p1.X, p2.Y, p1.Z)))
            qB:SetAttribute("CurrentState", "Idle")
            qB:SetAttribute("IsInert", true)
        end
    elseif mode == "FFA" then
        local DroneTrajectories = require(ServerScriptService:WaitForChild("ArenaDroneManager"))
        local _, center, _, radius = DroneTrajectories.getArenaMetrics()
        local quins = QuinSpawner.spawnTeam({"Male", "Female"}, nil, teamSize)
        for idx, q in ipairs(getTournamentFighters()) do
            local angle = (idx / math.max(1, #getTournamentFighters())) * (math.pi * 2)
            local r = math.clamp(radius * 0.55, 40, 120)
            local spawnPos = center + Vector3.new(math.cos(angle) * r, 2, math.sin(angle) * r)
            q:PivotTo(CFrame.lookAt(spawnPos, Vector3.new(center.X, spawnPos.Y, center.Z)))
            q:SetAttribute("CurrentState", "Idle")
            q:SetAttribute("IsInert", true)
        end
    else
        -- Team Battle
        for i = 1, teamSize do
            local sideOffset = (i - (teamSize + 1) * 0.5) * 12
            local pA = posAlpha + sideDir * sideOffset + Vector3.new(0, 2, 0)
            local pB = posBeta + sideDir * sideOffset + Vector3.new(0, 2, 0)
            local genderA = (i % 2 == 1) and "Male" or "Female"
            local genderB = (i % 2 == 1) and "Female" or "Male"
            
            local qA = QuinSpawner.spawn(genderA, pA, "TeamAlpha")
            local qB = QuinSpawner.spawn(genderB, pB, "TeamBeta")
            
            if qA then
                qA:PivotTo(CFrame.lookAt(pA, pA + forwardDir))
                qA:SetAttribute("CurrentState", "Idle")
                qA:SetAttribute("IsInert", true)
            end
            if qB then
                qB:PivotTo(CFrame.lookAt(pB, pB - forwardDir))
                qB:SetAttribute("CurrentState", "Idle")
                qB:SetAttribute("IsInert", true)
            end
        end
    end
    
    waitPhaseDuration(5)
    
    -- -------------------------------------------------------------
    -- PHASE 5: STADIUM ANTHEM (60 SECONDS WINDOW)
    -- Dynamic Back-Timing: Anthem ends at T=59s, followed by 1.0s reverb offset
    -- Zero ARIA voiceovers during anthem to prevent overlapping
    -- -------------------------------------------------------------
    currentPhase = "STADIUM_ANTHEM"
    print("[ArenaSystemOrchestrator] Entering Phase: STADIUM_ANTHEM (60s Window)")
    
    ArenaScreen.setTitle("STADIUM ANTHEM", "ALL RISE FOR THE ARENA ONE ANTHEM")
    ArenaScreen.displayAnnouncement("STADIUM ANTHEM // CEREMONIAL TRADITION", 4.0, "CEREMONY", Color3.fromRGB(212, 175, 55))
    
    local anthemPrefix = activeConfig.SelectedAnthem or "ANTHEM1"
    local anthemLength = ArenaAudio.getAnthemLength(anthemPrefix)
    local phaseWindow = 60.0
    local targetEndOffset = 1.0 -- Exactly 1s silence/reverb offset before pregame
    local startDelay = math.max(0, (phaseWindow - targetEndOffset) - anthemLength)
    
    print(string.format("[ArenaSystemOrchestrator] Anthem back-timing: Length=%.2fs, Delay=%.2fs, Ending at T=59.0s (1s Reverb Ring-Out)",
        anthemLength, startDelay))
    
    -- Step 1: Wait initial buildup delay if anthem is shorter than 59s
    if startDelay > 0 then
        waitPhaseDuration(startDelay)
    end
    
    -- Step 2: Start Anthem playback
    if activeConfig.Toggles.ProceduralMusic then
        ArenaAudio.playAnthemGroup(anthemPrefix, 1.0)
    end
    
    -- Step 3: Wait Anthem playback duration
    waitPhaseDuration(anthemLength)
    
    -- Step 4: 1.0s Reverb Ring-Out / Delay Offset before Pre-Game
    print("[ArenaSystemOrchestrator] Anthem concluded. Holding 1.0s acoustic reverb offset before combat countdown...")
    waitPhaseDuration(targetEndOffset)
    
    -- -------------------------------------------------------------
    -- PHASE 6: PRE-GAME COUNTDOWN (5 SECONDS)
    -- Colossal numerals 5-4-3-2-1 with shockwaves and warhorn
    -- -------------------------------------------------------------
    currentPhase = "PRE_GAME"
    print("[ArenaSystemOrchestrator] Entering Phase: PRE_GAME (5s)")
    
    ArenaScreen.setTitle("STAND BY FOR COMBAT", "5 SECONDS TO ENGAGEMENT")
    
    -- Deploy live drones over the arena
    if activeConfig.Toggles.Drones then
        ArenaDroneManager.deployDrones()
    end
    
    -- Sound warhorn at T-5
    ArenaAudio.playWarhorn("WARHORN1", 1.0)
    
    -- ARIA countdown voiceover
    if activeConfig.Toggles.Announcer then
        ArenaAria.speak("ARIA_PreGameCountdown")
    end
    
    waitPhaseDuration(5)
    
    -- -------------------------------------------------------------
    -- PHASE 7: IN-GAME (LIVE COMBAT)
    -- Uninert Quins, engage AI, battle music starts!
    -- -------------------------------------------------------------
    currentPhase = "IN_GAME"
    print("[ArenaSystemOrchestrator] Entering Phase: IN_GAME")
    
    Workspace:SetAttribute("MatchStarted", true)
    
    -- Uninert all fighters on field
    for _, q in ipairs(getTournamentFighters()) do
        q:SetAttribute("IsInert", false)
        q:SetAttribute("InCombat", true)
        local hum = q:FindFirstChildOfClass("Humanoid")
        if hum then hum.WalkSpeed = 16 end
    end
    
    ArenaScreen.setTitle("COMBAT ENGAGEMENT", "SECTOR ALPHA VS SECTOR BETA")
    ArenaScreen.displayAnnouncement("ENGAGEMENT COMMENCED // TOURNAMENT PROTOCOL LIVE", 4.0, "SYSTEM", Color3.fromRGB(0, 210, 255))
    
    -- Play In-Game Combat Music
    if activeConfig.Toggles.ProceduralMusic then
        ArenaAudio.playIngameMusic(activeConfig.SelectedInTrack or "365", 1.0, 1.5)
    end
    
    if activeConfig.Toggles.Fireworks then
        ArenaFireworks.launchCombatBurst(6)
    end
    
    -- Live Match Monitoring Loop
    local matchDuration = 180.0
    phaseEndTime = os.clock() + matchDuration
    skipRequested = false
    
    while os.clock() < phaseEndTime and not skipRequested do
        replicateState()
        
        local alphaHp, _, betaHp, _, alphaAlive, betaAlive = Orchestrator.getTeamHealthStats()
        if (alphaAlive == 0 or betaAlive == 0) and (alphaHp == 0 or betaHp == 0) then
            print("[ArenaSystemOrchestrator] Squad wiped out! Determining winner...")
            break
        end
        
        task.wait(0.25)
    end
    
    -- -------------------------------------------------------------
    -- PHASE 8: WINNER DETERMINATION & VICTORY CEREMONY
    -- -------------------------------------------------------------
    currentPhase = "WINNER_DETERMINATION"
    print("[ArenaSystemOrchestrator] Entering Phase: WINNER_DETERMINATION")
    
    pacifyAllQuins()
    
    local alphaHp, _, betaHp, _, alphaAlive, betaAlive = Orchestrator.getTeamHealthStats()
    local winnerTeam = "TeamAlpha"
    local winnerName = "TEAM ALPHA"
    
    if betaAlive > alphaAlive or (betaAlive == alphaAlive and betaHp > alphaHp) then
        winnerTeam = "TeamBeta"
        winnerName = "TEAM BETA"
    elseif alphaAlive == betaAlive and alphaHp == betaHp then
        winnerTeam = "Draw"
        winnerName = "DRAW"
    end
    
    matchStats.Winner = winnerName
    matchStats.WinnerTeam = winnerTeam
    matchStats.EndReason = "Combat Victory"
    
    ArenaScreen.showWinner(winnerName, string.format("CONQUEST RECORDED • %s ACHIEVED VICTORY", winnerName))
    
    if activeConfig.Toggles.Fireworks then
        ArenaFireworks.launchOpeningShow(12)
    end
    
    if activeConfig.Toggles.Announcer then
        ArenaAria.speak("ARIA_MatchConclusion")
    end
    
    waitPhaseDuration(10)
    
    -- -------------------------------------------------------------
    -- PHASE 9: POST_GAME & RESET
    -- -------------------------------------------------------------
    currentPhase = "POST_GAME"
    print("[ArenaSystemOrchestrator] Entering Phase: POST_GAME (Clean up)")
    
    ArenaAudio.stopAll(2.0)
    ArenaDroneManager.stopDrones()
    QuinSpawner.cleanAll()
    
    waitPhaseDuration(5)
    
    Orchestrator.stopMatch()
end

-- ============================================================================
-- EXTERNAL API & REMOTE HANDLERS
-- ============================================================================

function Orchestrator.startMatch(settings)
    if currentPhase ~= "IDLE" then
        print("[ArenaSystemOrchestrator] Cannot start match: already active in phase " .. currentPhase)
        return false, "Match already running."
    end
    
    if settings then
        if settings.Mode then activeConfig.Mode = settings.Mode end
        if settings.TeamSize then activeConfig.TeamSize = settings.TeamSize end
        if settings.Toggles then activeConfig.Toggles = settings.Toggles end
        if settings.SelectedTrack then activeConfig.SelectedTrack = settings.SelectedTrack end
        if settings.SelectedAnthem then activeConfig.SelectedAnthem = settings.SelectedAnthem end
        if settings.SelectedInTrack then activeConfig.SelectedInTrack = settings.SelectedInTrack end
        if settings.SelectedPostTrack then activeConfig.SelectedPostTrack = settings.SelectedPostTrack end
    end
    
    matchStats.StartTime = os.clock()
    matchStats.Winner = nil
    matchStats.WinnerTeam = nil
    matchStats.EndReason = nil
    
    matchThread = task.spawn(function()
        local success, err = pcall(runMatchLifecycle)
        if not success then
            warn("[ArenaSystemOrchestrator] Match runtime error:", err)
            Orchestrator.stopMatch()
        end
    end)
    
    return true, "Match initialized successfully."
end

function Orchestrator.stopMatch()
    print("[ArenaSystemOrchestrator] Force stopping match.")
    if matchThread then
        task.cancel(matchThread)
        matchThread = nil
    end
    
    currentPhase = "IDLE"
    phaseEndTime = 0
    skipRequested = false
    
    Workspace:SetAttribute("MatchStarted", false)
    Workspace:SetAttribute("ArenaHologramsActive", false)
    ArenaScreen.setHologramActive(false)
    ArenaScreen.setTitle("ARENA ONE", "STANDBY")
    
    local arenaOne = Workspace:FindFirstChild("argoniaonion") and Workspace.argoniaonion:FindFirstChild("ArenaOne")
    local globe = arenaOne and arenaOne:FindFirstChild("ArenaGlobe")
    if globe then
        globe.Transparency = 1.0
    end
    
    ArenaAudio.stopAll(1.0)
    ArenaDroneManager.stopDrones()
    QuinSpawner.cleanAll()
    replicateState()
end

function Orchestrator.skipPhase()
    if currentPhase ~= "IDLE" then
        print(string.format("[ArenaSystemOrchestrator] Skipping current phase: %s", currentPhase))
        skipRequested = true
    end
end

-- Wire Remotes
remotes.StartMatch.OnServerInvoke = function(player, settings)
    return Orchestrator.startMatch(settings)
end

remotes.StopMatch.OnServerEvent:Connect(function(player)
    Orchestrator.stopMatch()
end)

remotes.SkipPhase.OnServerEvent:Connect(function(player)
    Orchestrator.skipPhase()
end)

remotes.UpdateToggles.OnServerEvent:Connect(function(player, newToggles)
    if newToggles and type(newToggles) == "table" then
        for k, v in pairs(newToggles) do
            activeConfig.Toggles[k] = (v == true)
        end
    end
end)

remotes.Announce.OnServerEvent:Connect(function(player, msg, dur, tag, col)
    ArenaScreen.displayAnnouncement(msg, dur, tag, col)
end)

remotes.PlayTrack.OnServerEvent:Connect(function(player, trackName, vol, fade)
    ArenaAudio.playPregameMusic(trackName, vol, fade)
end)

remotes.DroneEvent.OnServerEvent:Connect(function(player, action)
    if action == "Deploy" then
        ArenaDroneManager.deployDrones()
    elseif action == "Stop" then
        ArenaDroneManager.stopDrones()
    end
end)

remotes.UpdateAudioSettings.OnServerEvent:Connect(function(player, channel, val)
    ArenaAudio.setChannelVolume(channel, val)
end)

print("[ArenaSystemOrchestrator] Ready for operations.")

return Orchestrator
