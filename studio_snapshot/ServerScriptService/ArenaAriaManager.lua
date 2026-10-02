--// ArenaAriaManager.lua
-- Authoritative AI stadium announcer (ARIA) voice playback, acoustic routing & audio ducking
-- Features: Full voice line fallback catalogue, 5-4-3-2-1 Countdown, Winner Sequence (Congratulations -> Team Alpha/Beta Wins) & Non-Truncating Playback Loop

local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local RS = game:GetService("ReplicatedStorage")
local SSS = game:GetService("ServerScriptService")

local ArenaConfig = require(RS.QuinCore.ArenaConfig)
local ArenaAudio = require(SSS:WaitForChild("ArenaAudioManager"))
local ArenaScreen = require(SSS:WaitForChild("ArenaScreenManager"))

local ArenaAria = {}

local arenaGlobe = nil
local arenaSpeakerGroup = nil
local activeAriaSound = nil
local activeThread = nil

-- Complete ARIA Voice Directory Fallback / Overrides
-- Guarantees that even if ArenaConfig is empty, all stadium announcements play authoritatively!
local LOCAL_ARIA_VOICE_LINES = {
    ARIA_ArenaOpen = {
        { Id = "rbxassetid://111233857607492", Name = "ARIA_ArenaIsOpen1", Subtitle = "Arena gates are open! Welcome to the battlefield." },
        { Id = "rbxassetid://117951721866687", Name = "ARIA_ArenaIsOpen2", Subtitle = "The arena is now open. Combatants, prepare yourselves." },
    },
    ARIA_AnnouncementPreparationRoomGuide = {
        { Id = "rbxassetid://105606408923571", Name = "ARIA_Annoucement_PreparationRoomGuide", Subtitle = "All combatants, proceed immediately to designated preparation zones." },
    },
    ARIA_ArenaGenerationCommence = {
        { Id = "rbxassetid://89916411096443", Name = "ARIA_ArenaIsGenerating", Subtitle = "Arena generation commencing. Stand clear of combat sector hazards." },
    },
    ARIA_ArenaGenerationCompleted = {
        { Id = "rbxassetid://92509748412290", Name = "ARIA_ArenaGenerationComplete1", Subtitle = "Arena generation complete. Field calibrated for battle." },
        { Id = "rbxassetid://70625793891633", Name = "ARIA_ArenaGenerationComplete2", Subtitle = "Battleground configuration finished. All systems active." },
    },
    ARIA_TeleportingQuinsToDesignatedAreas = {
        { Id = "rbxassetid://91468162088021", Name = "ARIA_TeleportingQuinsToDesignatedAreas", Subtitle = "Teleporting Quins to designated deployment staging areas." },
    },
    ARIA_54321GameCountdown = {
        { Id = "rbxassetid://110604241211322", Name = "ARIA_FiveFourThreeTwoOne", Subtitle = "5... 4... 3... 2... 1..." },
    },
    ARIA_Congratulations = {
        { Id = "rbxassetid://103182872872153", Name = "ARIA_Congratulations", Subtitle = "CONGRATULATIONS!" },
    },
    ARIA_TeamAlphaWins = {
        { Id = "rbxassetid://87479282909402", Name = "ARIA_TeamAlphaWins", Subtitle = "TEAM ALPHA WINS!" },
    },
    ARIA_TeamBetaWins = {
        { Id = "rbxassetid://91718646757305", Name = "ARIA_TeamBetaWins", Subtitle = "TEAM BETA WINS!" },
    },
    ARIA_ArenaClosing = {
        { Id = "rbxassetid://101847151661997", Name = "ARIA_ArenaIsNowClosing", Subtitle = "The arena is now closing. Match officially concluded." },
    },
    ARIA_LeaveTheArenaGuide = {
        { Id = "rbxassetid://78159893663395", Name = "ARIA_LeaveTheArenaGuide", Subtitle = "Spectators and personnel, please proceed orderly to the arena exits." },
    },
    ARIA_SkylarkClosure = {
        { Id = "rbxassetid://112194526998234", Name = "ARIA_SkylarkClosure", Subtitle = "Skylark Isles arena protocols closing down. Thank you for your presence." },
    },
}

local function getGlobe()
    if not arenaGlobe or not arenaGlobe.Parent then
        local arenaOne = Workspace:FindFirstChild("argoniaonion") and Workspace.argoniaonion:FindFirstChild("ArenaOne")
        arenaGlobe = arenaOne and arenaOne:FindFirstChild("ArenaGlobe")
    end
    return arenaGlobe
end

local function getSpeakerGroup()
    if not arenaSpeakerGroup or not arenaSpeakerGroup.Parent then
        arenaSpeakerGroup = SoundService:FindFirstChild("ArenaSpeakerGroup")
    end
    return arenaSpeakerGroup
end

-- Find pre-existing sound asset in Workspace.argoniaonion.ArenaOne.AriaAnnouncement
local function findAssetSound(assetNameOrId)
    local arenaOne = Workspace:FindFirstChild("argoniaonion") and Workspace.argoniaonion:FindFirstChild("ArenaOne")
    local ariaFolder = arenaOne and arenaOne:FindFirstChild("AriaAnnouncement")
    if not ariaFolder then return nil end
    
    for _, s in ipairs(ariaFolder:GetChildren()) do
        if s:IsA("Sound") and (s.Name == assetNameOrId or s.SoundId == assetNameOrId) then
            return s
        end
    end
    return nil
end

function ArenaAria.init()
    getGlobe()
    getSpeakerGroup()
    print("[ArenaAriaManager] Initialized ARIA Stadium Announcer.")
end

-- Play a categorized ARIA voice line
-- Returns sound instance, or nil if category is empty
local function playVoiceLineInternal(categoryName)
    local lines = ArenaConfig.AriaVoiceLines and ArenaConfig.AriaVoiceLines[categoryName]
    if not lines or #lines == 0 then
        lines = LOCAL_ARIA_VOICE_LINES[categoryName]
    end
    
    -- Fallback: check direct sound asset in AriaAnnouncement folder
    if not lines or #lines == 0 then
        local asset = findAssetSound(categoryName)
        if asset then
            lines = { { Id = asset.SoundId, Name = asset.Name, Subtitle = asset.Name } }
        end
    end
    
    if not lines or #lines == 0 then
        print(string.format("[ArenaAria] Category '%s' is empty. Skipping.", tostring(categoryName)))
        return nil, 0
    end
    
    -- Randomize selection from the available clips
    local chosen = lines[math.random(1, #lines)]
    if not chosen or not chosen.Id then return nil, 0 end
    
    local globe = getGlobe()
    local sGroup = getSpeakerGroup()
    if not globe then
        warn("[ArenaAria] ArenaGlobe not found! Cannot play 3D announcement.")
        return nil, 0
    end
    
    -- Stop any previous ARIA speech cleanly
    if activeAriaSound and activeAriaSound.Parent then
        activeAriaSound:Stop()
        activeAriaSound:Destroy()
        activeAriaSound = nil
    end
    
    -- Duck background music
    ArenaAudio.duck(ArenaConfig.AudioSettings.DuckingMultiplier, ArenaConfig.AudioSettings.DuckTweenTime)
    
    -- Check if preloaded in AriaAnnouncement folder to read authoritative TimeLength
    local existingAsset = findAssetSound(chosen.Name) or findAssetSound(chosen.Id)
    local estDuration = existingAsset and existingAsset.TimeLength or 3.5
    if estDuration <= 0 then estDuration = 3.5 end
    
    -- Display announcement on double-sided ArenaScreen jumbotron
    local subtitleText = chosen.Subtitle or chosen.Name
    ArenaScreen.displayAnnouncement(subtitleText, estDuration + 1.0, "🎙️ ARIA // STADIUM ANNOUNCER", Color3.fromRGB(0, 220, 255))
    
    -- Create speaker sound on ArenaGlobe
    local sound = Instance.new("Sound")
    sound.Name = "ARIA_" .. (chosen.Name or categoryName)
    sound.SoundId = chosen.Id
    sound.Volume = ArenaConfig.AudioSettings.BaselineVolume
    sound.Looped = false
    sound.RollOffMinDistance = ArenaConfig.AudioSettings.SpeakerMinDistance
    sound.RollOffMaxDistance = ArenaConfig.AudioSettings.SpeakerMaxDistance
    sound.RollOffMode = ArenaConfig.AudioSettings.SpeakerRollOffMode
    sound.SoundGroup = ArenaAudio.getAriaChannel()
    sound.Parent = globe
    
    activeAriaSound = sound
    sound:Play()
    print(string.format("[ArenaAria] Speaking: %s - '%s' (Est Duration: %.2fs)", categoryName, subtitleText, estDuration))
    
    return sound, estDuration
end

-- Asynchronous playback (runs in background coroutine with non-truncating wait)
function ArenaAria.speak(categoryName)
    local sound, estDuration = playVoiceLineInternal(categoryName)
    if not sound then return end
    
    activeThread = task.spawn(function()
        task.wait(0.1) -- allow audio subsystem to transition to Playing state
        
        local finished = false
        local conn
        conn = sound.Ended:Connect(function()
            finished = true
        end)
        
        -- Non-truncating deadline: ensure sound has time to complete in full plus safety buffer
        local duration = (sound.TimeLength > 0 and sound.TimeLength) or estDuration
        local deadline = os.clock() + duration + 0.5
        
        while not finished and os.clock() < deadline and sound.Parent and sound.IsPlaying do
            task.wait(0.05)
        end
        if conn then conn:Disconnect() end
        
        -- Clean up & unduck music
        if sound == activeAriaSound then
            activeAriaSound = nil
        end
        if sound.Parent then
            sound:Stop()
            sound:Destroy()
        end
        ArenaAudio.unduck(ArenaConfig.AudioSettings.UnduckTweenTime)
    end)
    return activeThread
end

-- Synchronous playback (yields calling thread until line completes in full)
function ArenaAria.speakAndWait(categoryName)
    local sound, estDuration = playVoiceLineInternal(categoryName)
    if not sound then return end
    
    task.wait(0.1) -- allow audio subsystem to transition to Playing state
    
    local finished = false
    local conn
    conn = sound.Ended:Connect(function()
        finished = true
    end)
    
    local duration = (sound.TimeLength > 0 and sound.TimeLength) or estDuration
    local deadline = os.clock() + duration + 0.5
    
    while not finished and os.clock() < deadline and sound.Parent and sound.IsPlaying do
        task.wait(0.05)
    end
    if conn then conn:Disconnect() end
    
    if sound == activeAriaSound then
        activeAriaSound = nil
    end
    if sound.Parent then
        sound:Stop()
        sound:Destroy()
    end
    ArenaAudio.unduck(ArenaConfig.AudioSettings.UnduckTweenTime)
end

-- ============================================================================
-- WINNER ANNOUNCEMENT SEQUENCE
-- Plays ARIA_Congratulations after 1s delay, then ARIA_TeamAlphaWins or ARIA_TeamBetaWins
-- ============================================================================
function ArenaAria.playWinnerSequence(winnerTeam)
    if activeThread then
        task.cancel(activeThread)
        activeThread = nil
    end
    
    activeThread = task.spawn(function()
        print(string.format("[ArenaAria] Commencing Winner Sequence for: %s", tostring(winnerTeam)))
        
        -- 1. Play ARIA_Congratulations after 1 second of team winning the game
        task.wait(1.0)
        
        ArenaAria.speakAndWait("ARIA_Congratulations")
        
        task.wait(0.25)
        
        -- 2. Play Team Alpha Wins or Team Beta Wins sound
        local lower = string.lower(tostring(winnerTeam))
        if lower:find("alpha") then
            ArenaAria.speakAndWait("ARIA_TeamAlphaWins")
        elseif lower:find("beta") then
            ArenaAria.speakAndWait("ARIA_TeamBetaWins")
        else
            print(string.format("[ArenaAria] Winner is not team-based (%s), congratulations complete.", tostring(winnerTeam)))
        end
    end)
    return activeThread
end

function ArenaAria.stopAll()
    if activeThread then
        task.cancel(activeThread)
        activeThread = nil
    end
    if activeAriaSound and activeAriaSound.Parent then
        activeAriaSound:Stop()
        activeAriaSound:Destroy()
        activeAriaSound = nil
    end
    ArenaAudio.unduck(0.2)
    ArenaScreen.clearAnnouncement()
end

ArenaAria.init()

return ArenaAria
