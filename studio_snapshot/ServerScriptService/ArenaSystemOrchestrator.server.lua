--// ArenaSystemOrchestrator.server.lua
-- Single Source of Truth for Argonia ArenaOne Lifecycle & Production Broadcast State Machine
--
-- Phases (durations from the Arena System panel, defaults in ArenaConfig.DefaultDurations):
--   ARENA_OPEN -> ARENA_GENERATION -> PREPARATION_ROOM -> TELEPORTING_QUINS -> STADIUM_ANTHEM
--   -> PRE_GAME (5-4-3-2-1, Pre-Game Timer toggle) -> IN_GAME -> WINNER_DETERMINATION -> POST_GAME -> IDLE
--
-- ArenaGlobe and the ArenaScreen materialize at T+5s of ARENA_OPEN (ArenaHologramsActive); the
-- client brings the ribbon ring up 1s after the globe (LiveFeedScreen).
-- SKIP ends the whole current phase, including what that phase was playing (anthem, ARIA line).

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
local ArenaCrowd = require(ServerScriptService:WaitForChild("ArenaCrowdManager"))
local ArenaGenerator = require(ServerScriptService:WaitForChild("ArenaGenerator"))
local QuinSpawner = require(ServerScriptService:WaitForChild("QuinSpawner"))
local VfxModule = require(ReplicatedStorage.QuinCore.Modules.VfxModule)

local Orchestrator = {}

local HOLOGRAM_IGNITION_TIME = 5.0 -- seconds into ARENA_OPEN
local ANTHEM_RING_OUT = 1.0 -- seconds of reverb tail between the anthem and the countdown

local currentPhase = "IDLE"
local phaseEndTime = 0
local phaseDuration = 0
local skipEpoch = 0 -- bumped by SKIP; every wait inside a phase returns when it changes
local matchThread = nil

local activeConfig = {
    Mode = "TeamBattle",
    TeamSize = 4,
    SelectedTrack = "365",
    SelectedAnthem = "ANTHEM1",
    SelectedInTrack = "ts - butterflyeffect live",
    SelectedPostTrack = "Bai - Tenggelam (feat. Kurt Haikal) MAXIMUS2",
    Toggles = table.clone(ArenaConfig.DefaultToggles),
    Durations = table.clone(ArenaConfig.DefaultDurations),
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
        -- UpdateAudioSettings is handled by ArenaAudioManager (it owns the channels)
    }
end

local remotes = ensureNetwork()
local StateReplication = remotes.StateReplication

-- Instant match (the InstantMatch toggle): everything before the fight is passed through at once
-- and quietly. While `instantLeadIn` is set the ceremonial toggles read as off and the lead-in
-- phases last no time; it is cleared when the fight starts.
local instantLeadIn = false
local QUIET_IN_INSTANT = { Announcer = true, Fireworks = true, ProceduralMusic = true, TimerPreGame = true }
local LEAD_IN_PHASES = { ArenaOpen = 0, ArenaGeneration = 1, PreparationRoom = 0, TeleportingQuins = 0.5, StadiumAnthem = 0, PreGame = 0 }

local function toggle(key)
    if instantLeadIn and QUIET_IN_INSTANT[key] then
        return false
    end
    return activeConfig.Toggles[key] == true
end

local function duration(key)
    if instantLeadIn and LEAD_IN_PHASES[key] then
        return LEAD_IN_PHASES[key]
    end
    local value = tonumber(activeConfig.Durations[key]) or tonumber(ArenaConfig.DefaultDurations[key]) or 10
    return math.max(0, value)
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

                if team == "TeamBeta" then
                    betaHp = betaHp + hp
                    betaMax = betaMax + maxHp
                    if isAlive then betaAlive = betaAlive + 1 end
                else
                    -- TeamAlpha, and every FFA fighter (individual survival)
                    alphaHp = alphaHp + hp
                    alphaMax = alphaMax + maxHp
                    if isAlive then alphaAlive = alphaAlive + 1 end
                end
            end
        end
    end

    return alphaHp, alphaMax, betaHp, betaMax, alphaAlive, betaAlive
end

local function replicateState()
    local remaining = math.max(0, math.ceil(phaseEndTime - os.clock()))
    if currentPhase == "IDLE" then
        remaining = 0
    end
    local alphaHp, alphaMax, betaHp, betaMax, alphaAlive, betaAlive = Orchestrator.getTeamHealthStats()

    StateReplication:FireAllClients({
        Phase = currentPhase,
        TimeRemaining = remaining,
        TotalPhaseDuration = math.ceil(phaseDuration),
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
    })

    if toggle("Screen") then
        ArenaScreen.setEnabled(true)
        ArenaScreen.updateMatchState(currentPhase, remaining, alphaHp, alphaMax, betaHp, betaMax, alphaAlive, betaAlive)
    else
        ArenaScreen.setEnabled(false)
    end
end

-- Start a phase: the screen switches to the phase's scene first, so its title lands on it
local function beginPhase(name, seconds, title, subtitle)
    currentPhase = name
    phaseDuration = seconds
    phaseEndTime = os.clock() + seconds
    print(string.format("[ArenaSystemOrchestrator] Entering Phase: %s (%.0fs)", name, seconds))
    ArenaScreen.setSequence(name, title, subtitle, seconds)
    ArenaCrowd.setPhase(name)
    replicateState()
    return skipEpoch
end

-- Wait until the phase deadline (or `untilTime`); returns false if the phase was skipped
local function waitPhase(epoch, untilTime)
    local deadline = untilTime or phaseEndTime
    while os.clock() < deadline do
        if skipEpoch ~= epoch then
            return false
        end
        replicateState()
        task.wait(0.25)
    end
    return skipEpoch == epoch
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

local function getArenaGlobe()
    local arenaOne = Workspace:FindFirstChild("argoniaonion") and Workspace.argoniaonion:FindFirstChild("ArenaOne")
    return arenaOne and arenaOne:FindFirstChild("ArenaGlobe")
end

local function igniteHolograms()
    if Workspace:GetAttribute("ArenaHologramsActive") == true then return end
    print("[ArenaSystemOrchestrator] Holograms: ArenaGlobe + ArenaScreen materialize (ring follows 1s later on clients)")
    Workspace:SetAttribute("ArenaHologramsActive", true)
    ArenaScreen.setHologramActive(true)
    local globe = getArenaGlobe()
    if globe then
        globe.Material = Enum.Material.ForceField
        globe.Color = Color3.fromRGB(0, 210, 255)
        globe.Transparency = 0.45
    end
end

-- Fighters are deployed one at a time, in a random order across both sides, each taking shape in
-- a holographic glitch, over `window` seconds (0: all at once). A SKIP places the rest at once.
local function spawnFighters(window, epoch)
    local jobs = {} -- each places one fighter and returns it
    local mode = activeConfig.Mode
    local teamSize = math.max(1, tonumber(activeConfig.TeamSize) or 4)
    local positions = QuinSpawner.getSpawnPositions()
    local posAlpha = positions[1] or Vector3.new(158, 2.05, -605)
    local posBeta = positions[2] or Vector3.new(-137, 2.05, -233)
    local forwardDir = (posBeta - posAlpha).Unit
    local sideDir = Vector3.new(-forwardDir.Z, 0, forwardDir.X)

    local function settle(q, cf)
        if not q then return end
        -- (keep the height QuinSpawner stood it at; the spawn points are pad level)
        local standY = q:GetPivot().Position.Y
        q:PivotTo(cf.Rotation + Vector3.new(cf.Position.X, standY, cf.Position.Z))
        q:SetAttribute("CurrentState", "Idle")
        q:SetAttribute("IsInert", true)
    end

    if mode == "1vs1" then
        local p1 = posAlpha:Lerp(posBeta, 0.6)
        local p2 = posBeta:Lerp(posAlpha, 0.6)
        table.insert(jobs, function()
            local q = QuinSpawner.spawn("Male", p1, "TeamAlpha")
            settle(q, CFrame.lookAt(p1, Vector3.new(p2.X, p1.Y, p2.Z)))
            return q
        end)
        table.insert(jobs, function()
            local q = QuinSpawner.spawn("Female", p2, "TeamBeta")
            settle(q, CFrame.lookAt(p2, Vector3.new(p1.X, p2.Y, p1.Z)))
            return q
        end)
    elseif mode == "FFA" then
        local DroneTrajectories = require(ReplicatedStorage.QuinCore:WaitForChild("ArenaDroneTrajectories"))
        local _, center, _, radius = DroneTrajectories.getArenaMetrics()
        local count = math.max(2, teamSize)
        local r = math.clamp((radius or 150) * 0.55, 40, 120)
        if ArenaGenerator.isActive() then
            r = math.min(r, ArenaGenerator.getCenterClearHalf() - 12) -- (the generated centre is the open ground)
        end
        for i = 1, count do
            local angle = (i / count) * math.pi * 2
            local pos = center + Vector3.new(math.cos(angle) * r, 2, math.sin(angle) * r)
            table.insert(jobs, function()
                local q = QuinSpawner.spawn((i % 2 == 1) and "Male" or "Female", pos, nil)
                settle(q, CFrame.lookAt(pos, Vector3.new(center.X, pos.Y, center.Z)))
                return q
            end)
        end
    elseif ArenaGenerator.isActive() then
        -- Generated arena: each team spawns scattered round its anchor (mirrored pattern)
        for _, team in ipairs({ "TeamAlpha", "TeamBeta" }) do
            local points, facing = ArenaGenerator.getSpawnPoints(team, teamSize)
            for i, p in ipairs(points or {}) do
                local gender = ((i % 2 == 1) == (team == "TeamAlpha")) and "Male" or "Female"
                table.insert(jobs, function()
                    local q = QuinSpawner.spawn(gender, p, team)
                    settle(q, CFrame.lookAt(p, Vector3.new(facing.X, p.Y, facing.Z)))
                    return q
                end)
            end
        end
    else
        -- Team Battle: two lines facing each other
        for i = 1, teamSize do
            local sideOffset = (i - (teamSize + 1) * 0.5) * 12
            local pA = posAlpha + sideDir * sideOffset + Vector3.new(0, 2, 0)
            local pB = posBeta + sideDir * sideOffset + Vector3.new(0, 2, 0)
            table.insert(jobs, function()
                local q = QuinSpawner.spawn((i % 2 == 1) and "Male" or "Female", pA, "TeamAlpha")
                settle(q, CFrame.lookAt(pA, pA + forwardDir))
                return q
            end)
            table.insert(jobs, function()
                local q = QuinSpawner.spawn((i % 2 == 1) and "Female" or "Male", pB, "TeamBeta")
                settle(q, CFrame.lookAt(pB, pB - forwardDir))
                return q
            end)
        end
    end

    -- Deploy: shuffled, spread over the window
    local rng = Random.new()
    for i = #jobs, 2, -1 do
        local j = rng:NextInteger(1, i)
        jobs[i], jobs[j] = jobs[j], jobs[i]
    end
    window = window or 0
    for i, job in ipairs(jobs) do
        local q = job()
        if q and window > 0 then
            VfxModule.holoGlitch(q, ArenaConfig.Teleport.GlitchTime, "in")
        end
        if window > 0 and i < #jobs and (epoch == nil or skipEpoch == epoch) then
            task.wait(window / #jobs)
        end
    end
end

-- Who won: an elimination, or at the time limit more fighters alive, then more health
local function decideWinner(mode)
    local alphaHp, alphaMax, betaHp, betaMax, alphaAlive, betaAlive = Orchestrator.getTeamHealthStats()
    if mode == "FFA" then
        local best, bestHp = nil, -1
        for _, q in ipairs(getTournamentFighters()) do
            local h = q:FindFirstChildOfClass("Humanoid")
            if h and h.Health > 0 and h.Health > bestHp then
                best, bestHp = q, h.Health
            end
        end
        if best then
            return best.Name, "FFA Champion", alphaAlive <= 1 and "Last Quin Standing" or "Time Limit (Highest Health)"
        end
        return "DRAW", "Draw", "Mutual Elimination"
    end
    if alphaAlive == 0 and betaAlive == 0 then
        return "DRAW", "Draw", "Mutual Elimination"
    elseif betaAlive == 0 then
        return "TEAM ALPHA", "TeamAlpha", "Elimination"
    elseif alphaAlive == 0 then
        return "TEAM BETA", "TeamBeta", "Elimination"
    end
    if alphaAlive ~= betaAlive then
        local alpha = alphaAlive > betaAlive
        return alpha and "TEAM ALPHA" or "TEAM BETA", alpha and "TeamAlpha" or "TeamBeta",
            string.format("Time Limit (Fighters Alive %d vs %d)", math.max(alphaAlive, betaAlive), math.min(alphaAlive, betaAlive))
    end
    local alphaPct = alphaMax > 0 and alphaHp / alphaMax or 0
    local betaPct = betaMax > 0 and betaHp / betaMax or 0
    if math.abs(alphaPct - betaPct) < 1e-3 then
        return "DRAW", "Draw", "Time Limit (Equal Health & Count)"
    end
    local alpha = alphaPct > betaPct
    return alpha and "TEAM ALPHA" or "TEAM BETA", alpha and "TeamAlpha" or "TeamBeta",
        string.format("Time Limit (Health %.0f%% vs %.0f%%)", math.max(alphaPct, betaPct) * 100, math.min(alphaPct, betaPct) * 100)
end

-- ============================================================================
-- LIFECYCLE STATE MACHINE
-- ============================================================================

local function runMatchLifecycle()
    local mode = activeConfig.Mode
    instantLeadIn = activeConfig.Toggles.InstantMatch == true
    ArenaCrowd.resetMatch(mode)
    ArenaCrowd.setEnabled(toggle("CrowdFX"))

    -- PHASE 1: ARENA OPEN. Globe + screen materialize at T+5s.
    Workspace:SetAttribute("ArenaHologramsActive", false)
    ArenaScreen.setHologramActive(false)
    local openTime = duration("ArenaOpen")
    local epoch = beginPhase("ARENA_OPEN", openTime, "ARENA ONE", "GATES ARE OPEN • PREPARING MATCH")
    if toggle("Fireworks") then
        ArenaFireworks.launchOpeningShow(openTime)
    end
    if toggle("ProceduralMusic") then
        ArenaAudio.playPregameMusic(activeConfig.SelectedTrack or "365", 1.0, 2.0) -- runs through Prep Room
    end
    if toggle("Announcer") then
        ArenaAria.speak("ARIA_ArenaOpen")
    end
    if waitPhase(epoch, os.clock() + math.min(HOLOGRAM_IGNITION_TIME, openTime)) then
        igniteHolograms()
        waitPhase(epoch)
    end
    igniteHolograms() -- (an Arena Open skipped before T+5s still brings them up)

    -- PHASE 2: ARENA GENERATION
    local generationTime = duration("ArenaGeneration")
    epoch = beginPhase("ARENA_GENERATION", generationTime, "ARENA GENERATION", "CONFIGURING COMBAT SECTOR")
    if toggle("Announcer") then
        ArenaAria.speak("ARIA_ArenaGenerationCommence")
    end
    -- "Generation completed" is only announced once the generation sequence has finished (it used
    -- to play at 55% of the phase, while the bar was still filling)
    local generationCompleted
    if toggle("ProceduralTerrain") then
        -- Hologram seed sweep -> lock -> materialize (ArenaGenerator); SKIP hurries it, and the
        -- phase waits for it to finish so nobody is spawned into a half-built arena
        local generationEpoch = epoch
        local finished = false
        task.spawn(function()
            local ok, err = pcall(ArenaGenerator.runSequence, generationTime, function()
                return skipEpoch ~= generationEpoch
            end)
            if not ok then
                warn("[ArenaSystemOrchestrator] Arena generation failed: " .. tostring(err))
            end
            finished = true
        end)
        generationCompleted = waitPhase(epoch)
        while not finished do
            task.wait(0.1)
        end
    else
        ArenaGenerator.restore() -- (toggle off: the edit-mode arena)
        generationCompleted = waitPhase(epoch)
    end

    -- PHASE 3: PREPARATION ROOM. Fighters calibrating in the backrooms: none on the field.
    QuinSpawner.cleanAll()
    Workspace:SetAttribute("MatchStarted", false)
    local prepTime = duration("PreparationRoom")
    epoch = beginPhase("PREPARATION_ROOM", prepTime, "PREPARATION ROOM", string.format("FIGHTERS CALIBRATING IN BACKROOMS • %d SECONDS", prepTime))
    if toggle("Announcer") then
        -- Completion line first, then a 5 s breath before the preparation-room guide
        local prepEpoch = epoch
        task.spawn(function()
            if generationCompleted then
                ArenaAria.speakAndWait("ARIA_ArenaGenerationCompleted")
                task.wait(ArenaConfig and ArenaConfig.AriaGapAfterGeneration or 5)
            end
            if skipEpoch == prepEpoch and currentPhase == "PREPARATION_ROOM" then
                ArenaAria.speak("ARIA_AnnouncementPreparationRoomGuide")
            end
        end)
    end
    if not waitPhase(epoch) then
        ArenaAria.stopAll()
    end

    -- PHASE 4: TELEPORTING QUINS. Pre-game music fades, fighters materialize at their stations.
    epoch = beginPhase("TELEPORTING_QUINS", duration("TeleportingQuins"), "DEPLOYMENT TELEPORT", "MATERIALIZING FIGHTERS AT COMBAT STATIONS")
    ArenaAudio.stopPregameMusic(1.5)
    ArenaScreen.displayAnnouncement("TELEPORTING QUINS TO DESIGNATED AREAS", 3.0, "ARENA DISPATCH", Color3.fromRGB(0, 220, 255))
    if toggle("Announcer") then
        ArenaAria.speak("ARIA_TeleportingQuinsToDesignatedAreas")
    end
    -- (one at a time over the first seconds of the phase; at once in an instant match)
    spawnFighters(instantLeadIn and 0 or math.min(ArenaConfig.Teleport.Window, duration("TeleportingQuins") * 0.8), epoch)
    ArenaCrowd.assignTeams(mode) -- stand sections pick a side; kept until the match ends
    if not waitPhase(epoch) then
        ArenaAria.stopAll()
    end

    -- PHASE 5: STADIUM ANTHEM. Back-timed to end ANTHEM_RING_OUT before the window closes;
    -- no ARIA lines over it. A longer anthem than the window starts at once and is not cut.
    local anthemWindow = duration("StadiumAnthem")
    local anthemPrefix = activeConfig.SelectedAnthem or "ANTHEM1"
    local anthemLength = toggle("ProceduralMusic") and ArenaAudio.getAnthemLength(anthemPrefix) or 0
    local startDelay = math.max(0, anthemWindow - ANTHEM_RING_OUT - anthemLength)
    epoch = beginPhase("STADIUM_ANTHEM", math.max(anthemWindow, anthemLength + ANTHEM_RING_OUT), "STADIUM ANTHEM", "ALL RISE FOR THE ARENA ONE ANTHEM")
    ArenaScreen.displayAnnouncement("STADIUM ANTHEM // CEREMONIAL TRADITION", 4.0, "CEREMONY", Color3.fromRGB(212, 175, 55))
    print(string.format("[ArenaSystemOrchestrator] Anthem %s: %.2fs, starts at T+%.2fs of a %.0fs window", anthemPrefix, anthemLength, startDelay, phaseDuration))
    if waitPhase(epoch, os.clock() + startDelay) and toggle("ProceduralMusic") then
        ArenaAudio.playAnthem(anthemPrefix, 1.0)
    end
    if not waitPhase(epoch) then
        ArenaAudio.stopAnthem(1.5)
    end

    -- PHASE 6: PRE-GAME COUNTDOWN (Pre-Game Timer toggle). Warhorn at T-5, drones at T-4.
    if toggle("TimerPreGame") then
        epoch = beginPhase("PRE_GAME", duration("PreGame"), "STAND BY FOR COMBAT", "SECONDS TO ENGAGEMENT")
        ArenaAudio.playWarhorn(1.0)
        if toggle("Announcer") then
            ArenaAria.speak("ARIA_54321GameCountdown")
        end
        if waitPhase(epoch, os.clock() + math.min(1.0, phaseDuration)) and toggle("Drones") then
            ArenaDroneManager.startDrones()
        end
        waitPhase(epoch)
    end

    -- PHASE 7: IN-GAME. Quins released; ends on an elimination or the game time limit.
    instantLeadIn = false -- (an instant match is an ordinary match from here on)
    Workspace:SetAttribute("MatchStarted", true)
    epoch = beginPhase("IN_GAME", duration("GameTime"), "COMBAT ENGAGEMENT", "SECTOR ALPHA VS SECTOR BETA")
    -- (the Quins know how long they have: SocialTension)
    Workspace:SetAttribute("MatchLength", duration("GameTime"))
    Workspace:SetAttribute("MatchEndsAt", Workspace:GetServerTimeNow() + duration("GameTime"))
    if not toggle("TimerPreGame") then
        ArenaAudio.playWarhorn(1.0)
        if toggle("Drones") then
            ArenaDroneManager.startDrones()
        end
    end
    for _, q in ipairs(getTournamentFighters()) do
        q:SetAttribute("IsInert", false)
        q:SetAttribute("InCombat", true)
        q:SetAttribute("ForceState", nil)
    end
    ArenaScreen.displayAnnouncement("ENGAGEMENT COMMENCED // TOURNAMENT PROTOCOL LIVE", 4.0, "SYSTEM", Color3.fromRGB(0, 210, 255))
    if toggle("ProceduralMusic") then
        ArenaAudio.playInGameMusic(activeConfig.SelectedInTrack, 1.0, 1.5)
    end
    while os.clock() < phaseEndTime and skipEpoch == epoch do
        replicateState()
        local _, _, _, _, alphaAlive, betaAlive = Orchestrator.getTeamHealthStats()
        if mode == "FFA" then
            if alphaAlive <= 1 then break end
        elseif alphaAlive == 0 or betaAlive == 0 then
            break
        end
        task.wait(0.25)
    end

    -- PHASE 8: WINNER DETERMINATION / VICTORY CEREMONY
    local winnerName, winnerTeam, reason = decideWinner(mode)
    matchStats.Winner, matchStats.WinnerTeam, matchStats.EndReason = winnerName, winnerTeam, reason
    Workspace:SetAttribute("MatchStarted", false)
    Workspace:SetAttribute("MatchEndsAt", nil)
    pacifyAllQuins()
    ArenaAudio.stopInGameMusic(2.0)
    local victoryTime = duration("WinnerDetermination")
    epoch = beginPhase("WINNER_DETERMINATION", victoryTime, nil, nil)
    ArenaCrowd.onWinner(winnerTeam)
    ArenaScreen.showWinner(winnerName, reason)
    if toggle("Fireworks") then
        ArenaFireworks.launchWinnerShow(victoryTime)
    end
    if toggle("Announcer") then
        ArenaAria.playWinnerSequence(winnerTeam)
    end
    if not waitPhase(epoch) then
        ArenaAria.stopAll()
    end

    -- PHASE 9: POST-GAME. Spectators leave; closing lines, drone outro in the last 15s.
    local postTime = duration("PostGame")
    epoch = beginPhase("POST_GAME", postTime, "ARENA CLOSURE", "SPECTATOR EXIT PROTOCOLS ACTIVE")
    pacifyAllQuins()
    if toggle("ProceduralMusic") then
        ArenaAudio.playPostgameMusic(activeConfig.SelectedPostTrack, 1.0, 2.5)
    end
    if toggle("Announcer") then
        ArenaAria.speak("ARIA_ArenaClosing")
    end
    local postStart = os.clock()
    local guideAt = postStart + math.clamp(postTime * 0.15, 2.5, 6.0)
    local outroLead = math.min(15.0, postTime)
    local outroAt = math.max(guideAt + 2.0, postStart + postTime - outroLead)
    local closureAt = math.max(outroAt + 1.0, postStart + postTime - 7.0)
    if waitPhase(epoch, guideAt) and toggle("Announcer") then
        ArenaAria.speak("ARIA_LeaveTheArenaGuide")
    end
    if waitPhase(epoch, outroAt) and toggle("Drones") then
        ArenaDroneManager.startOutro(math.max(1, postStart + postTime - os.clock()))
        ArenaScreen.displayAnnouncement("ARENA DRONES OUTRO -- FORMATION CLIMB", 2.5, "ARENA BROADCAST", Color3.fromRGB(220, 80, 255))
    end
    if waitPhase(epoch, closureAt) then
        if toggle("Announcer") then
            ArenaAria.speak("ARIA_SkylarkClosure")
        end
        ArenaAudio.stopPostgameMusic(5.0)
    end
    waitPhase(epoch)

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

    activeConfig.Toggles = table.clone(ArenaConfig.DefaultToggles)
    activeConfig.Durations = table.clone(ArenaConfig.DefaultDurations)
    if type(settings) == "table" then
        if settings.Mode then activeConfig.Mode = settings.Mode end
        if settings.TeamSize then activeConfig.TeamSize = tonumber(settings.TeamSize) or activeConfig.TeamSize end
        if settings.SelectedTrack then activeConfig.SelectedTrack = settings.SelectedTrack end
        if settings.SelectedAnthem then activeConfig.SelectedAnthem = settings.SelectedAnthem end
        if settings.SelectedInTrack then activeConfig.SelectedInTrack = settings.SelectedInTrack end
        if settings.SelectedPostTrack then activeConfig.SelectedPostTrack = settings.SelectedPostTrack end
        if type(settings.Toggles) == "table" then
            for k, v in pairs(settings.Toggles) do
                activeConfig.Toggles[k] = (v == true)
            end
        end
        if type(settings.Durations) == "table" then
            for k, v in pairs(settings.Durations) do
                local n = tonumber(v)
                if n and n >= 0 then
                    activeConfig.Durations[k] = n
                end
            end
        end
    end

    matchStats.StartTime = os.clock()
    matchStats.Winner = nil
    matchStats.WinnerTeam = nil
    matchStats.EndReason = nil

    print(string.format("[ArenaSystemOrchestrator] Match starting: %s, team size %s", tostring(activeConfig.Mode), tostring(activeConfig.TeamSize)))
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
    print("[ArenaSystemOrchestrator] Match stopped -> IDLE.")
    if matchThread and matchThread ~= coroutine.running() then
        task.cancel(matchThread)
    end
    matchThread = nil
    skipEpoch += 1

    currentPhase = "IDLE"
    phaseEndTime = 0
    phaseDuration = 0

    Workspace:SetAttribute("MatchStarted", false)
    Workspace:SetAttribute("ArenaHologramsActive", false)
    ArenaScreen.setHologramActive(false)
    ArenaScreen.setSequence("IDLE", "ARENA ONE", "STANDBY", 0)
    ArenaScreen.clearAnnouncement()

    local globe = getArenaGlobe()
    if globe then
        globe.Transparency = 1.0
    end

    ArenaAria.stopAll()
    ArenaAudio.stopAll(1.0)
    ArenaCrowd.setPhase("IDLE")
    ArenaGenerator.restore() -- the edit-mode arena comes back
    ArenaFireworks.stopAll()
    ArenaDroneManager.resetDrones()
    QuinSpawner.cleanAll()
    replicateState()
end

function Orchestrator.skipPhase()
    if currentPhase ~= "IDLE" then
        print(string.format("[ArenaSystemOrchestrator] Skipping phase: %s", currentPhase))
        skipEpoch += 1
    end
end

function Orchestrator.getPhase()
    return currentPhase, math.max(0, phaseEndTime - os.clock())
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
    if type(newToggles) == "table" then
        for k, v in pairs(newToggles) do
            activeConfig.Toggles[k] = (v == true)
        end
        ArenaCrowd.setEnabled(toggle("CrowdFX") and currentPhase ~= "IDLE")
        replicateState()
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
        ArenaDroneManager.startDrones()
    elseif action == "Stop" then
        ArenaDroneManager.resetDrones()
    end
end)

_G.ArenaOrchestrator = Orchestrator
shared.ArenaOrchestrator = Orchestrator

-- Studio test hook: Workspace attribute ArenaDevCommand = "start <json>" | "skip" | "stop"
if game:GetService("RunService"):IsStudio() then
    Workspace:GetAttributeChangedSignal("ArenaDevCommand"):Connect(function()
        local cmd = Workspace:GetAttribute("ArenaDevCommand")
        if cmd == nil or cmd == "" then return end
        Workspace:SetAttribute("ArenaDevCommand", nil)
        if cmd == "skip" then
            Orchestrator.skipPhase()
        elseif cmd == "stop" then
            Orchestrator.stopMatch()
        elseif type(cmd) == "string" and cmd:sub(1, 5) == "start" then
            local ok, cfg = pcall(function()
                return game:GetService("HttpService"):JSONDecode(cmd:sub(7))
            end)
            Orchestrator.startMatch(ok and cfg or nil)
        end
    end)
end

print("[ArenaSystemOrchestrator] Ready for operations.")
