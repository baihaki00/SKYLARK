--// ArenaSystemOrchestrator.server.lua
-- Single Source of Truth Authoritative Match Lifecycle & Arena Orchestrator for Skylark Isles

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local QuinCore = ReplicatedStorage:WaitForChild("QuinCore")
local ArenaConfig = require(QuinCore:WaitForChild("ArenaConfig"))
local QuinSpawner = require(ServerScriptService:WaitForChild("QuinSpawner"))

local ArenaFireworks = require(ServerScriptService:WaitForChild("ArenaFireworksManager"))
local ArenaAudio = require(ServerScriptService:WaitForChild("ArenaAudioManager"))
local ArenaAria = require(ServerScriptService:WaitForChild("ArenaAriaManager"))
local ArenaScreen = require(ServerScriptService:WaitForChild("ArenaScreenManager"))
local ArenaDroneManager = require(ServerScriptService:WaitForChild("ArenaDroneManager"))

local ArenaNetwork = ReplicatedStorage:WaitForChild("ArenaNetwork")
local StartMatchFunc = ArenaNetwork:WaitForChild("StartMatch")
local StopMatchEvent = ArenaNetwork:WaitForChild("StopMatch")
local SkipPhaseEvent = ArenaNetwork:WaitForChild("SkipPhase")
local UpdateTogglesEvent = ArenaNetwork:WaitForChild("UpdateToggles")
local StateReplication = ArenaNetwork:WaitForChild("StateReplication")
local AnnounceEvent = ArenaNetwork:WaitForChild("Announce")

local Orchestrator = {}
_G.ArenaOrchestrator = Orchestrator
shared.ArenaOrchestrator = Orchestrator

-- Active Match State
local currentPhase = "IDLE"
local phaseEndTime = 0
local matchThread = nil
local skipRequested = false

local activeConfig = {
    Mode = "TeamBattle",
    TeamSize = 4,
    Toggles = table.clone(ArenaConfig.DefaultToggles),
    Durations = table.clone(ArenaConfig.DefaultDurations),
    SelectedTrack = "365",
    SelectedInTrack = "ts - butterflyeffect live",
    SelectedPostTrack = "Bai - Tenggelam (feat. Kurt Haikal) MAXIMUS2",
}

local matchStats = {
    StartTime = 0,
    Winner = nil,
    WinnerTeam = nil,
    EndReason = nil,
    Scores = { TeamAlpha = 0, TeamBeta = 0 }
}

-- Replicate match state snapshot to all clients & update 3D ArenaScreen
local function replicateState()
    local remaining = math.max(0, math.ceil(phaseEndTime - os.clock()))
    local alphaHp, alphaMax, betaHp, betaMax, alphaAlive, betaAlive = Orchestrator.getTeamHealthStats()
    
    local snapshot = {
        Phase = currentPhase,
        TimeRemaining = remaining,
        Mode = activeConfig.Mode,
        TeamSize = activeConfig.TeamSize,
        Winner = matchStats.Winner,
        WinnerTeam = matchStats.WinnerTeam,
        AlphaHp = alphaHp,
        AlphaMax = alphaMax,
        BetaHp = betaHp,
        BetaMax = betaMax,
        AlphaAlive = alphaAlive,
        BetaAlive = betaAlive,
        Toggles = activeConfig.Toggles,
    }
    
    StateReplication:FireAllClients(snapshot)
    
    -- Sync Arena Screen if enabled
    if activeConfig.Toggles.Screen then
        ArenaScreen.setEnabled(true)
        ArenaScreen.updateHealthBars(alphaHp, alphaMax, betaHp, betaMax, alphaAlive, betaAlive)
    else
        ArenaScreen.setEnabled(false)
    end
end

-- Helper to strictly retrieve tournament AI combatants in QuinServer
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
                    -- For FFA, treat individual survival
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
-- LIFECYCLE STATE MACHINE (ARIA SEQUENCED + GLOBE SPEAKER + DUCKING)
-- ============================================================================

local function runMatchLifecycle()
    -- -------------------------------------------------------------
    -- PHASE 1: ARENA OPEN
    -- -------------------------------------------------------------
    currentPhase = "ARENA_OPEN"
    print("[ArenaSystemOrchestrator] Entering Phase: ARENA_OPEN")
    
    ArenaScreen.setTitle("ARENA ONE", "GATES ARE OPEN • PREPARING MATCH")
    
    if activeConfig.Toggles.Fireworks then
        ArenaFireworks.launchOpeningShow(activeConfig.Durations.ArenaOpen or 10)
    end
    
    if activeConfig.Toggles.ProceduralMusic then
        ArenaAudio.playPregameMusic(activeConfig.SelectedTrack or "Bai - Skycastle Parade", 1.0, 2.0)
    end
    
    if activeConfig.Toggles.Announcer then
        ArenaAria.speak("ARIA_ArenaOpen")
    end
    
    waitPhaseDuration(activeConfig.Durations.ArenaOpen or 10)
    
    -- -------------------------------------------------------------
    -- PHASE 2: ARENA GENERATION
    -- -------------------------------------------------------------
    currentPhase = "ARENA_GENERATION"
    print("[ArenaSystemOrchestrator] Entering Phase: ARENA_GENERATION")
    
    ArenaScreen.setTitle("ARENA GENERATION", "CONFIGURING COMBAT SECTOR")
    
    if activeConfig.Toggles.Announcer then
        ArenaAria.speak("ARIA_ArenaGenerationCommence")
    end
    
    -- Check Procedural Terrain toggle
    if activeConfig.Toggles.ProceduralTerrain then
        print("[ArenaSystemOrchestrator] Procedural terrain generation active.")
    else
        print("[ArenaSystemOrchestrator] Using standard edit-mode arena obstacle configuration.")
    end
    
    local genDuration = math.max(5.5, activeConfig.Durations.ArenaGeneration or 15)
    
    -- Mid-generation confirmation (delayed so it does not overlap with generation commence)
    task.delay(math.max(2.2, genDuration * 0.55), function()
        if currentPhase == "ARENA_GENERATION" and activeConfig.Toggles.Announcer then
            ArenaAria.speak("ARIA_ArenaGenerationCompleted")
        end
    end)
    
    waitPhaseDuration(genDuration)
    
    -- -------------------------------------------------------------
    -- PHASE 3: PREPARATION ROOM (STAGING / WARM-UP) (30s DEFAULT)
    -- -------------------------------------------------------------
    currentPhase = "PREPARATION_ROOM"
    print("[ArenaSystemOrchestrator] Entering Phase: PREPARATION_ROOM")
    
    QuinSpawner.cleanAll()
    Workspace:SetAttribute("MatchStarted", false)
    
    -- Non-truncating prepDuration: minimum 12.5s so ARIA_AnnouncementPreparationRoomGuide (11.65s) is NEVER cut off!
    local prepDuration = math.max(12.5, activeConfig.Durations.PreparationRoom or 30)
    ArenaScreen.setTitle("PREPARATION ROOM", string.format("FIGHTERS STAGED IN PREPARATION SECTORS • %d SECONDS", prepDuration))
    
    -- Procedural Anthem 1: combines ARIA_SkylarkAnthem1Procedural + Anthem1DrumFX + Anthem1CrowdFX
    -- Plays during and after ARIA_AnnouncementPreparationRoomGuide (ducked while ARIA speaks, unducked after)
    if activeConfig.Toggles.ProceduralMusic then
        ArenaAudio.playProceduralAnthem1(1.0, 1.5, true, "PreGameMusic")
    end
    
    if activeConfig.Toggles.Announcer then
        ArenaAria.speak("ARIA_AnnouncementPreparationRoomGuide")
    end
    
    -- Spawn fighters in their staging pads in warm-up / survey mode
    local mode = activeConfig.Mode
    local teamSize = activeConfig.TeamSize or 4
    
    local positions = QuinSpawner.getSpawnPositions()
    local posAlpha = positions[1] or Vector3.new(158, 2.05, -605)
    local posBeta = positions[2] or Vector3.new(-137, 2.05, -233)
    
    local prepOffsetAlpha = Vector3.new(35, 0, 35)
    local prepOffsetBeta = Vector3.new(-35, 0, -35)
    
    if mode == "1vs1" then
        local p1 = posAlpha + prepOffsetAlpha
        local p2 = posBeta + prepOffsetBeta
        local qA = QuinSpawner.spawn("Male", p1, "TeamAlpha")
        local qB = QuinSpawner.spawn("Female", p2, "TeamBeta")
        if qA and qB then
            qA:SetAttribute("CurrentState", "Idle")
            qB:SetAttribute("CurrentState", "Idle")
            qA:SetAttribute("IsInert", true)
            qB:SetAttribute("IsInert", true)
        end
    elseif mode == "FFA" then
        local ffaCount = teamSize
        local spawned = QuinSpawner.spawnTeam({"Male", "Female"}, nil, ffaCount)
        for _, q in ipairs(getTournamentFighters()) do
            q:SetAttribute("CurrentState", "Idle")
            q:SetAttribute("IsInert", true)
        end
    else
        -- Team Battle: Balanced mix of Male and Female Quins
        QuinSpawner.spawnTeam({"Male", "Female"}, "TeamAlpha", teamSize, 1, posAlpha + prepOffsetAlpha)
        task.wait(0.15)
        QuinSpawner.spawnTeam({"Female", "Male"}, "TeamBeta", teamSize, 2, posBeta + prepOffsetBeta)
        
        for _, q in ipairs(getTournamentFighters()) do
            q:SetAttribute("CurrentState", "Idle")
            q:SetAttribute("IsInert", true)
        end
    end
    
    waitPhaseDuration(prepDuration)
    
    -- -------------------------------------------------------------
    -- PHASE 4: TELEPORTING QUINS TO DESIGNATED AREAS (10s DEFAULT)
    -- -------------------------------------------------------------
    currentPhase = "TELEPORTING_QUINS"
    print("[ArenaSystemOrchestrator] Entering Phase: TELEPORTING_QUINS")
    
    local teleportDuration = math.max(5.5, activeConfig.Durations.TeleportingQuins or 10)
    ArenaScreen.setTitle("TELEPORTING QUINS", "DEPLOYING TO COMBAT STATIONS")
    ArenaScreen.displayAnnouncement("TELEPORTING QUINS TO DESIGNATED AREAS", 2.5, "ARENA DISPATCH", Color3.fromRGB(0, 200, 255))
    
    if activeConfig.Toggles.Announcer then
        ArenaAria.speak("ARIA_TeleportingQuinsToDesignatedAreas")
    end
    
    -- Teleport Quins to authoritative battle-ready positions facing opponents
    if mode == "1vs1" then
        local p1 = Vector3.new(posAlpha.X * 0.4 + posBeta.X * 0.6, posAlpha.Y, posAlpha.Z * 0.4 + posBeta.Z * 0.6)
        local p2 = Vector3.new(posBeta.X * 0.4 + posAlpha.X * 0.6, posBeta.Y, posBeta.Z * 0.4 + posAlpha.Z * 0.6)
        for _, q in ipairs(getTournamentFighters()) do
            local team = q:GetAttribute("Team")
            local targetPos = (team == "TeamAlpha") and p1 or p2
            local lookAtPos = (team == "TeamAlpha") and p2 or p1
            local hrp = q:FindFirstChild("HumanoidRootPart")
            if hrp then
                q:PivotTo(CFrame.lookAt(targetPos, Vector3.new(lookAtPos.X, targetPos.Y, lookAtPos.Z)))
                hrp.AssemblyLinearVelocity = Vector3.zero
            end
            q:SetAttribute("IsInert", true)
        end
    elseif mode == "FFA" then
        local _, center, _, radius = DroneTrajectories.getArenaMetrics()
        local quins = getTournamentFighters()
        local numQuins = #quins
        for idx, q in ipairs(quins) do
            local angle = (idx / math.max(1, numQuins)) * (math.pi * 2)
            local r = math.clamp(radius * 0.55, 40, 120)
            local spawnPos = center + Vector3.new(math.cos(angle) * r, 2, math.sin(angle) * r)
            local hrp = q:FindFirstChild("HumanoidRootPart")
            if hrp then
                q:PivotTo(CFrame.lookAt(spawnPos, Vector3.new(center.X, spawnPos.Y, center.Z)))
                hrp.AssemblyLinearVelocity = Vector3.zero
            end
            q:SetAttribute("IsInert", true)
        end
    else
        -- Team Battle: Teleport Alpha and Beta squads to their frontline deployment lines
        local alphaQuins = {}
        local betaQuins = {}
        for _, q in ipairs(getTournamentFighters()) do
            local team = q:GetAttribute("Team")
            if team == "TeamAlpha" then
                table.insert(alphaQuins, q)
            else
                table.insert(betaQuins, q)
            end
        end
        
        local forwardDir = (posBeta - posAlpha).Unit
        local sideDir = Vector3.new(-forwardDir.Z, 0, forwardDir.X)
        
        for idx, q in ipairs(alphaQuins) do
            local sideOffset = (idx - (#alphaQuins + 1) * 0.5) * 12
            local pos = posAlpha + sideDir * sideOffset + Vector3.new(0, 2, 0)
            local hrp = q:FindFirstChild("HumanoidRootPart")
            if hrp then
                q:PivotTo(CFrame.lookAt(pos, pos + forwardDir))
                hrp.AssemblyLinearVelocity = Vector3.zero
            end
            q:SetAttribute("IsInert", true)
        end
        
        for idx, q in ipairs(betaQuins) do
            local sideOffset = (idx - (#betaQuins + 1) * 0.5) * 12
            local pos = posBeta + sideDir * sideOffset + Vector3.new(0, 2, 0)
            local hrp = q:FindFirstChild("HumanoidRootPart")
            if hrp then
                q:PivotTo(CFrame.lookAt(pos, pos - forwardDir))
                hrp.AssemblyLinearVelocity = Vector3.zero
            end
            q:SetAttribute("IsInert", true)
        end
    end
    
    waitPhaseDuration(teleportDuration)
    
    -- -------------------------------------------------------------
    -- PHASE 4: PRE-GAME (COUNTDOWN & MUSIC FADE OUT)
    -- -------------------------------------------------------------
    currentPhase = "PRE_GAME"
    print("[ArenaSystemOrchestrator] Entering Phase: PRE_GAME")
    
    -- Fade out PreGame music leading into match start
    ArenaAudio.stopPregameMusic(2.0)
    
    if activeConfig.Toggles.Announcer then
        ArenaAria.speak("ARIA_54321GameCountdown")
    end
    
    if activeConfig.Toggles.TimerPreGame then
        ArenaScreen.setTitle("PRE-GAME", "COMMENCING COUNTDOWN")
        
        for count = 5, 1, -1 do
            if count == 4 then
                ArenaDroneManager.startDrones()
                ArenaScreen.setTitle(tostring(count), "DRONES LIVE • COMMENCING")
                ArenaScreen.displayAnnouncement("ARENA DRONES LAUNCHED -- LIVE FOOTAGE ACTIVE", 1.0, "ARENA BROADCAST", Color3.fromRGB(0, 220, 255))
                print("[ArenaSystemOrchestrator] Countdown T-4: Arena Drones launched into flight!")
            else
                ArenaScreen.setTitle(tostring(count), "GET READY!")
                ArenaScreen.displayAnnouncement(string.format("T-MINUS %d SECONDS", count), 1.0, "ARENA COUNTDOWN", (count <= 2) and Color3.fromRGB(255, 60, 60) or Color3.fromRGB(255, 180, 50))
            end
            task.wait(1.0)
        end
        
        ArenaScreen.setTitle("⚔️ FIGHT! ⚔️", "ENGAGE ALL TARGETS")
        ArenaScreen.displayAnnouncement("⚔️ ENGAGE ALL TARGETS! ⚔️", 2.0, "ARENA ONE", Color3.fromRGB(0, 255, 120))
    else
        ArenaDroneManager.startDrones()
        ArenaScreen.setTitle("⚔️ FIGHT! ⚔️", "ENGAGE ALL TARGETS")
        ArenaScreen.displayAnnouncement("⚔️ ENGAGE ALL TARGETS! ⚔️", 2.0, "ARENA ONE", Color3.fromRGB(0, 255, 120))
    end
    
    -- -------------------------------------------------------------
    -- PHASE 5: IN-GAME (ACTIVE COMBAT & TIEBREAKER CAP)
    -- -------------------------------------------------------------
    currentPhase = "IN_GAME"
    print("[ArenaSystemOrchestrator] Entering Phase: IN_GAME")
    
    Workspace:SetAttribute("MatchStarted", true)
    
    -- Sound Stadium Warhorn right as Quins start moving!
    ArenaAudio.playWarhorn()
    ArenaScreen.displayAnnouncement("📯 WARHORN SOUNDS -- ENGAGE! 📯", 2.0, "ARENA ONE", Color3.fromRGB(255, 180, 50))
    
    -- Start In-Game combat music if ProceduralMusic toggle is on
    if activeConfig.Toggles.ProceduralMusic then
        ArenaAudio.playInGameMusic(activeConfig.SelectedInTrack or "ts - butterflyeffect live", 1.0, 1.5)
    end
    
    -- Release inert locks and activate Quin AI
    for _, q in ipairs(getTournamentFighters()) do
        q:SetAttribute("IsInert", false)
        q:SetAttribute("InCombat", true)
        q:SetAttribute("ForceState", nil)
    end
    
    local gameTimeLimit = activeConfig.Durations.GameTime or 600
    local gameEndTime = os.clock() + gameTimeLimit
    phaseEndTime = gameEndTime
    skipRequested = false
    
    local matchConcluded = false
    local winnerName = "Undetermined"
    local winnerTeam = "None"
    
    while os.clock() < gameEndTime and not matchConcluded and not skipRequested do
        replicateState()
        task.wait(0.5)
        
        local alphaHp, alphaMax, betaHp, betaMax, alphaAlive, betaAlive = Orchestrator.getTeamHealthStats()
        
        if mode == "FFA" then
            if alphaAlive <= 1 then
                matchConcluded = true
                for _, q in ipairs(getTournamentFighters()) do
                    local h = q:FindFirstChildOfClass("Humanoid")
                    if h and h.Health > 0 then
                        winnerName = q.Name
                        winnerTeam = "FFA Champion"
                        break
                    end
                end
                if alphaAlive == 0 then
                    winnerName = "DRAW"
                    winnerTeam = "Mutual Elimination"
                end
            end
        else
            -- Team or 1v1
            if alphaAlive == 0 and betaAlive == 0 then
                matchConcluded = true
                winnerName = "DRAW"
                winnerTeam = "Mutual Elimination"
            elseif alphaAlive == 0 then
                matchConcluded = true
                winnerName = "TEAM BETA"
                winnerTeam = "TeamBeta"
            elseif betaAlive == 0 then
                matchConcluded = true
                winnerName = "TEAM ALPHA"
                winnerTeam = "TeamAlpha"
            end
        end
    end
    
    -- -------------------------------------------------------------
    -- TIEBREAKER: Determine winner from better team if time expires!
    -- -------------------------------------------------------------
    if not matchConcluded then
        print("[ArenaSystemOrchestrator] Game Time Expired! Evaluating tiebreaker metrics...")
        local alphaHp, alphaMax, betaHp, betaMax, alphaAlive, betaAlive = Orchestrator.getTeamHealthStats()
        local alphaPct = (alphaMax > 0) and (alphaHp / alphaMax) or 0
        local betaPct = (betaMax > 0) and (betaHp / betaMax) or 0
        
        if alphaPct > betaPct then
            winnerName = "TEAM ALPHA"
            winnerTeam = "TeamAlpha"
            matchStats.EndReason = string.format("Time Limit (Higher Health: %.1f%% vs %.1f%%)", alphaPct * 100, betaPct * 100)
        elseif betaPct > alphaPct then
            winnerName = "TEAM BETA"
            winnerTeam = "TeamBeta"
            matchStats.EndReason = string.format("Time Limit (Higher Health: %.1f%% vs %.1f%%)", betaPct * 100, alphaPct * 100)
        else
            if alphaAlive > betaAlive then
                winnerName = "TEAM ALPHA"
                winnerTeam = "TeamAlpha"
                matchStats.EndReason = string.format("Time Limit (More Living Fighters: %d vs %d)", alphaAlive, betaAlive)
            elseif betaAlive > alphaAlive then
                winnerName = "TEAM BETA"
                winnerTeam = "TeamBeta"
                matchStats.EndReason = string.format("Time Limit (More Living Fighters: %d vs %d)", betaAlive, alphaAlive)
            else
                winnerName = "DRAW"
                winnerTeam = "Tiebreaker Deadlock"
                matchStats.EndReason = "Time Limit (Equal Health & Count)"
            end
        end
    end
    
    matchStats.Winner = winnerName
    matchStats.WinnerTeam = winnerTeam
    
    -- -------------------------------------------------------------
    -- PHASE 6: WINNER DETERMINATION & CELEBRATION
    -- -------------------------------------------------------------
    currentPhase = "WINNER_DETERMINATION"
    print(string.format("[ArenaSystemOrchestrator] Entering Phase: WINNER_DETERMINATION (%s)", winnerName))
    
    Workspace:SetAttribute("MatchStarted", false)
    pacifyAllQuins()
    ArenaAudio.stopInGameMusic(2.0)
    
    ArenaScreen.showWinner(winnerName, matchStats.EndReason or "VICTORY ACHIEVED")
    
    if activeConfig.Toggles.Announcer then
        ArenaAria.playWinnerSequence(matchStats.WinnerTeam or winnerName)
    end
    
    if activeConfig.Toggles.Fireworks then
        ArenaFireworks.launchWinnerShow(activeConfig.Durations.WinnerDetermination or 8)
    end
    
    local winnerDuration = math.max(7.5, activeConfig.Durations.WinnerDetermination or 8)
    waitPhaseDuration(winnerDuration)
    
    -- -------------------------------------------------------------
    -- PHASE 7: POST-GAME / ARENA CLOSURE / SPECTATORS LEAVING (3 MINUTES DEFAULT)
    -- -------------------------------------------------------------
    currentPhase = "POST_GAME"
    local postDuration = activeConfig.Durations.PostGame or 180
    print(string.format("[ArenaSystemOrchestrator] Entering Phase: POST_GAME / ARENA CLOSURE (%d seconds)", postDuration))
    
    pacifyAllQuins()
    ArenaScreen.setTitle("ARENA CLOSURE", "SPECTATOR EXIT PROTOCOLS ACTIVE")
    
    -- 1. Fade in PostGame music for spectators leaving
    if activeConfig.Toggles.ProceduralMusic then
        ArenaAudio.playPostgameMusic(activeConfig.SelectedPostTrack or "Bai - Tenggelam (feat. Kurt Haikal) MAXIMUS2", 1.0, 2.5)
    end
    
    -- 2. ARIA announces Arena is closing immediately
    if activeConfig.Toggles.Announcer then
        ArenaAria.speak("ARIA_ArenaClosing")
    end
    
    -- 3. ARIA announces Leave The Arena Guide shortly after (scaled for fast test or full 3 min)
    local guideDelay = math.clamp(postDuration * 0.15, 2.5, 6.0)
    task.delay(guideDelay, function()
        if currentPhase == "POST_GAME" and activeConfig.Toggles.Announcer then
            ArenaAria.speak("ARIA_LeaveTheArenaGuide")
        end
    end)
    
    -- 4. Jet Outro Climb & Camera Flip sequence during final 15 seconds
    local outroLeadTime = 15.0
    local outroTriggerTime = math.max(guideDelay + 2.0, postDuration - outroLeadTime)
    task.delay(outroTriggerTime, function()
        if currentPhase == "POST_GAME" then
            ArenaDroneManager.startOutro(outroLeadTime)
            ArenaScreen.displayAnnouncement("ARENA DRONES OUTRO -- FORMATION CLIMB", 2.5, "ARENA BROADCAST", Color3.fromRGB(220, 80, 255))
        end
    end)
    
    -- 5. Near end of PostGame phase, play ARIA_SkylarkClosure & fade out music
    local closureTriggerTime = math.max(outroTriggerTime + 6.0, postDuration - 7)
    task.delay(closureTriggerTime, function()
        if currentPhase == "POST_GAME" then
            if activeConfig.Toggles.Announcer then
                ArenaAria.speak("ARIA_SkylarkClosure")
            end
            ArenaAudio.stopPostgameMusic(5.0)
        end
    end)
    
    waitPhaseDuration(postDuration)
    
    -- -------------------------------------------------------------
    -- RETURN TO IDLE
    -- -------------------------------------------------------------
    Orchestrator.reset()
end

function Orchestrator.startMatch(config)
    Orchestrator.reset()
    
    config = config or {}
    activeConfig.Mode = config.Mode or "TeamBattle"
    activeConfig.TeamSize = config.TeamSize or 4
    activeConfig.SelectedTrack = config.SelectedTrack or "365"
    activeConfig.SelectedInTrack = config.SelectedInTrack or "ts - butterflyeffect live"
    activeConfig.SelectedPostTrack = config.SelectedPostTrack or "Bai - Tenggelam (feat. Kurt Haikal) MAXIMUS2"
    
    if config.Toggles then
        for k, v in pairs(config.Toggles) do
            activeConfig.Toggles[k] = v
        end
    end
    
    if config.Durations then
        for k, v in pairs(config.Durations) do
            activeConfig.Durations[k] = tonumber(v) or activeConfig.Durations[k]
        end
    end
    
    matchStats.Winner = nil
    matchStats.WinnerTeam = nil
    matchStats.EndReason = nil
    matchStats.StartTime = os.clock()
    
    matchThread = task.spawn(runMatchLifecycle)
    return { ok = true, mode = activeConfig.Mode, teamSize = activeConfig.TeamSize }
end

function Orchestrator.reset()
    if matchThread and matchThread ~= coroutine.running() then
        task.cancel(matchThread)
    end
    matchThread = nil
    
    currentPhase = "IDLE"
    phaseEndTime = 0
    skipRequested = false
    
    QuinSpawner.cleanAll()
    Workspace:SetAttribute("MatchStarted", false)
    
    ArenaFireworks.stopAll()
    ArenaAudio.stopAll(1.0)
    ArenaAria.stopAll()
    ArenaDroneManager.resetDrones()
    ArenaScreen.setTitle("ARENA ONE", "READY FOR NEXT BATTLE")
    ArenaScreen.clearAnnouncement()
    
    replicateState()
    print("[ArenaSystemOrchestrator] Match reset to IDLE.")
end

function Orchestrator.skipPhase()
    if currentPhase ~= "IDLE" then
        print("[ArenaSystemOrchestrator] Skipping current phase: " .. currentPhase)
        skipRequested = true
        phaseEndTime = os.clock()
    end
end

function Orchestrator.updateToggles(newToggles)
    if newToggles then
        for k, v in pairs(newToggles) do
            activeConfig.Toggles[k] = v
        end
        replicateState()
    end
end

-- Remote Listeners
StartMatchFunc.OnServerInvoke = function(player, config)
    print(string.format("[ArenaSystemOrchestrator] StartMatch invoked by %s (Mode: %s)", player.Name, tostring(config and config.Mode)))
    return Orchestrator.startMatch(config)
end

StopMatchEvent.OnServerEvent:Connect(function(player)
    print(string.format("[ArenaSystemOrchestrator] StopMatch requested by %s", player.Name))
    Orchestrator.reset()
end)

SkipPhaseEvent.OnServerEvent:Connect(function(player)
    print(string.format("[ArenaSystemOrchestrator] SkipPhase requested by %s", player.Name))
    Orchestrator.skipPhase()
end)

UpdateTogglesEvent.OnServerEvent:Connect(function(player, toggles)
    Orchestrator.updateToggles(toggles)
end)

print("[ArenaSystemOrchestrator] Initialized & listening on ArenaNetwork.")
