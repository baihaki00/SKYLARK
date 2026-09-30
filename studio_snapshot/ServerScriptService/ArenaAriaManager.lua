--// ArenaAriaManager.lua
-- Authoritative AI stadium announcer (ARIA) voice playback, acoustic routing & audio ducking

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
    local lines = ArenaConfig.AriaVoiceLines[categoryName]
    if not lines or #lines == 0 then
        -- Blank category (e.g. ARIA_54321GameCountdown, ARIA_AnnounceWinner) gracefully ignored
        print(string.format("[ArenaAria] Category '%s' is empty. Skipping.", tostring(categoryName)))
        return nil, 0
    end
    
    -- Randomize selection from the 1-3 available clips
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
    
    -- Check if preloaded in AriaAnnouncement folder to read TimeLength
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
    sound.SoundGroup = sGroup
    sound.Parent = globe
    
    activeAriaSound = sound
    sound:Play()
    print(string.format("[ArenaAria] Speaking: %s - '%s' (Est Duration: %.2fs)", categoryName, subtitleText, estDuration))
    
    return sound, estDuration
end

-- Asynchronous playback (runs in background coroutine)
function ArenaAria.speak(categoryName)
    local sound, estDuration = playVoiceLineInternal(categoryName)
    if not sound then return end
    
    activeThread = task.spawn(function()
        -- Wait for sound completion or fallback timeout
        local finished = false
        local conn
        conn = sound.Ended:Connect(function()
            finished = true
        end)
        
        local deadline = os.clock() + (sound.TimeLength > 0 and (sound.TimeLength + 0.5) or (estDuration + 0.5))
        while not finished and os.clock() < deadline and sound.Parent and sound.IsPlaying do
            task.wait(0.1)
        end
        if conn then conn:Disconnect() end
        
        -- Clean up & unduck music
        if sound == activeAriaSound then
            activeAriaSound = nil
        end
        sound:Destroy()
        ArenaAudio.unduck(ArenaConfig.AudioSettings.UnduckTweenTime)
    end)
end

-- Synchronous playback (yields calling thread until line completes)
function ArenaAria.speakAndWait(categoryName)
    local sound, estDuration = playVoiceLineInternal(categoryName)
    if not sound then return end
    
    local finished = false
    local conn
    conn = sound.Ended:Connect(function()
        finished = true
    end)
    
    local deadline = os.clock() + (sound.TimeLength > 0 and (sound.TimeLength + 0.5) or (estDuration + 0.5))
    while not finished and os.clock() < deadline and sound.Parent and sound.IsPlaying do
        task.wait(0.1)
    end
    if conn then conn:Disconnect() end
    
    if sound == activeAriaSound then
        activeAriaSound = nil
    end
    sound:Destroy()
    ArenaAudio.unduck(ArenaConfig.AudioSettings.UnduckTweenTime)
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
