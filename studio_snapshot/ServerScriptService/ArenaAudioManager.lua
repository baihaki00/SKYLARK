--// ArenaAudioManager.lua
-- Authoritative acoustic sound & music manager for ArenaOne emitting from ArenaGlobe
-- Features: Clean Reverb Acoustics (Echo Removed), Dedicated ARIA Voice & Music Channels,
-- Dynamic Multi-Stem Stadium Anthem Scanning (ANTHEM1, ANTHEM2...), Dynamic Back-Timing Length Inspector,
-- Warhorns & Real-Time Slider Mixing (Master, AriaVoice, Music, Reverb Decay, Reverb Wetness)

local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local RS = game:GetService("ReplicatedStorage")

local ArenaConfig = require(RS.QuinCore.ArenaConfig)
-- Crowd (ArenaCrowdManager): anthem _CrowdFX / _DrumFX stems play through the stand emitters
local ArenaCrowd = require(game:GetService("ServerScriptService"):WaitForChild("ArenaCrowdManager"))

local ArenaAudio = {}

local arenaGlobe = nil
local masterGroup = nil
local ariaChannel = nil
local musicChannel = nil

local activeMusicSound = nil
local activeAnthemStems = {} -- { [Sound] = volumeWeight }
local standStemBase = {} -- { [Sound] = weight before ArenaCrowd's AnthemStemScale } (stems played from the stands)
local currentMusicType = "None"
local isAnthemActive = false

-- Volume Channel Baselines
local channelVolumes = {
    Master = 1.0,
    AriaVoice = 1.2,
    Music = 0.85,
    ReverbDecay = 3.5,
    ReverbWet = 2.0,
}

local isDucked = false
local duckCount = 0

-- Stadium Warhorn Assets
local WARHORNS = {
    { Name = "WARHORN1", Id = "rbxassetid://70588093438719" },
    { Name = "WARHORN2", Id = "rbxassetid://102327524117254" },
}

-- Setup Master SoundGroup and sub-channels (Echo Removed, Reverb Polished)
local function ensureSoundGroups()
    masterGroup = SoundService:FindFirstChild("ArenaSpeakerGroup")
    if not masterGroup then
        masterGroup = Instance.new("SoundGroup")
        masterGroup.Name = "ArenaSpeakerGroup"
        masterGroup.Parent = SoundService
    end
    masterGroup.Volume = channelVolumes.Master

    -- REMOVE ECHO completely per Bai's directive
    local echo = masterGroup:FindFirstChildOfClass("EchoSoundEffect")
    if echo then
        echo:Destroy()
        print("[ArenaAudio] Echo effect removed from ArenaSpeakerGroup.")
    end

    -- Polish Reverb
    local reverb = masterGroup:FindFirstChildOfClass("ReverbSoundEffect")
    if not reverb then
        reverb = Instance.new("ReverbSoundEffect")
        reverb.Name = "ArenaReverb"
        reverb.Parent = masterGroup
    end
    reverb.DecayTime = channelVolumes.ReverbDecay
    reverb.WetLevel = channelVolumes.ReverbWet
    reverb.DryLevel = 0
    reverb.Density = 1.0
    reverb.Diffusion = 1.0

    -- Sub-channel: ARIA Voice
    ariaChannel = masterGroup:FindFirstChild("ArenaAriaChannel")
    if not ariaChannel then
        ariaChannel = Instance.new("SoundGroup")
        ariaChannel.Name = "ArenaAriaChannel"
        ariaChannel.Parent = masterGroup
    end
    ariaChannel.Volume = channelVolumes.AriaVoice

    -- Sub-channel: Music & Anthem
    musicChannel = masterGroup:FindFirstChild("ArenaMusicChannel")
    if not musicChannel then
        musicChannel = Instance.new("SoundGroup")
        musicChannel.Name = "ArenaMusicChannel"
        musicChannel.Parent = masterGroup
    end
    musicChannel.Volume = channelVolumes.Music

    return masterGroup
end

-- Locate ArenaGlobe speaker part
local function findArenaGlobe()
    local arenaOne = Workspace:FindFirstChild("argoniaonion") and Workspace.argoniaonion:FindFirstChild("ArenaOne")
    arenaGlobe = arenaOne and arenaOne:FindFirstChild("ArenaGlobe")
    return arenaGlobe
end

function ArenaAudio.init()
    ensureSoundGroups()
    findArenaGlobe()
    if arenaGlobe then
        print(string.format("[ArenaAudio] Initialized. Globe at %s, Master/Aria/Music channels routed.", tostring(arenaGlobe.Position)))
    else
        warn("[ArenaAudio] ArenaGlobe not found in Workspace.argoniaonion.ArenaOne!")
    end
end

function ArenaAudio.getAriaChannel()
    ensureSoundGroups()
    return ariaChannel
end

function ArenaAudio.getMusicChannel()
    ensureSoundGroups()
    return musicChannel
end

-- ============================================================================
-- DYNAMIC ANTHEM SCANNING & PLAYBACK (Stems in ArenaOne.Anthem)
-- Dynamically finds all stems prefixed with e.g. "ANTHEM1" and plays them together
-- ============================================================================

local function getAnthemFolder()
    local arenaOne = Workspace:FindFirstChild("argoniaonion") and Workspace.argoniaonion:FindFirstChild("ArenaOne")
    return arenaOne and arenaOne:FindFirstChild("Anthem")
end

-- Returns dynamic length in seconds of an anthem track prefix (e.g. "ANTHEM1")
function ArenaAudio.getAnthemLength(anthemPrefix)
    anthemPrefix = anthemPrefix or "ANTHEM1"
    local folder = getAnthemFolder()
    if not folder then
        return 45.03 -- Fallback for Anthem1
    end
    
    local maxLength = 0
    for _, sound in ipairs(folder:GetChildren()) do
        if sound:IsA("Sound") and string.find(string.upper(sound.Name), string.upper(anthemPrefix), 1, true) then
            if sound.TimeLength > maxLength then
                maxLength = sound.TimeLength
            end
        end
    end
    
    if maxLength <= 0 then
        -- Default known duration for ANTHEM1
        return 45.03
    end
    return maxLength
end

-- Play all stems of the selected anthem simultaneously from ArenaGlobe
function ArenaAudio.playAnthem(anthemPrefix, volume, fadeTime)
    findArenaGlobe()
    ensureSoundGroups()
    if not arenaGlobe then return {} end
    
    anthemPrefix = anthemPrefix or "ANTHEM1"
    fadeTime = fadeTime or 1.5
    volume = volume or channelVolumes.Music
    
    -- Stop active music & existing anthems
    ArenaAudio.stopAnthem(fadeTime * 0.5)
    if activeMusicSound and activeMusicSound.Parent then
        local old = activeMusicSound
        TweenService:Create(old, TweenInfo.new(fadeTime * 0.5), { Volume = 0 }):Play()
        task.delay(fadeTime * 0.5, function()
            old:Stop()
            old:Destroy()
        end)
        activeMusicSound = nil
    end
    
    local folder = getAnthemFolder()
    local stemsToPlay = {}
    
    if folder then
        for _, template in ipairs(folder:GetChildren()) do
            if template:IsA("Sound") and string.find(string.upper(template.Name), string.upper(anthemPrefix), 1, true) then
                table.insert(stemsToPlay, template)
            end
        end
    end
    
    -- Fallback hardcoded ANTHEM1 if folder empty
    if #stemsToPlay == 0 then
        local fallbackAnthem1 = {
            { Name = "ANTHEM1_ARIA",    Id = "rbxassetid://133883167606286", Vol = 1.0 },
            { Name = "ANTHEM1_DrumFX",  Id = "rbxassetid://74373537405672",  Vol = 0.95 },
            { Name = "ANTHEM1_CrowdFX", Id = "rbxassetid://86633259711410",  Vol = 0.85 },
        }
        for _, info in ipairs(fallbackAnthem1) do
            local s = Instance.new("Sound")
            s.Name = info.Name
            s.SoundId = info.Id
            table.insert(stemsToPlay, s)
        end
    end
    
    activeAnthemStems = {}
    standStemBase = {}
    isAnthemActive = true
    currentMusicType = "StadiumAnthem"
    
    for _, template in ipairs(stemsToPlay) do
        local nameUpper = string.upper(template.Name)
        local volWeight = 1.0
        if string.find(nameUpper, "DRUM", 1, true) then
            volWeight = 0.95
        elseif string.find(nameUpper, "CROWD", 1, true) then
            volWeight = 0.85
        end

        -- Crowd and drum stems sound like the stadium, so they come from the stands (one copy per
        -- stand section); everything else plays from the ArenaGlobe speaker
        local parents = { arenaGlobe }
        local baseWeight = volWeight
        local isStandStem = string.find(nameUpper, "CROWD", 1, true) or string.find(nameUpper, "DRUM", 1, true)
        if isStandStem then
            local emitters = ArenaCrowd.getStemEmitters()
            if #emitters > 0 then
                parents = emitters
                volWeight *= ArenaCrowd.getStemScale()
            end
        end

        for _, parent in ipairs(parents) do
            local sound = Instance.new("Sound")
            sound.Name = "ActiveAnthem_" .. template.Name
            sound.SoundId = template.SoundId
            sound.Looped = false
            sound.Volume = 0
            if parent == arenaGlobe then
                sound.RollOffMinDistance = ArenaConfig.AudioSettings.SpeakerMinDistance
                sound.RollOffMaxDistance = ArenaConfig.AudioSettings.SpeakerMaxDistance
                sound.RollOffMode = ArenaConfig.AudioSettings.SpeakerRollOffMode
            else
                sound.RollOffMinDistance, sound.RollOffMaxDistance = ArenaCrowd.getRollOff()
                sound.RollOffMode = Enum.RollOffMode.InverseTapered
            end

            -- Route ARIA vocals to AriaChannel, Drums & Crowd to MusicChannel
            if string.find(nameUpper, "ARIA", 1, true) or string.find(nameUpper, "VOCAL", 1, true) then
                sound.SoundGroup = ariaChannel
            else
                sound.SoundGroup = musicChannel
            end

            sound.Parent = parent
            sound.TimePosition = 0
            sound:Play()

            TweenService:Create(sound, TweenInfo.new(fadeTime), { Volume = volume * volWeight }):Play()
            activeAnthemStems[sound] = volWeight
            if parent ~= arenaGlobe then
                standStemBase[sound] = baseWeight
            end
        end
    end
    
    print(string.format("[ArenaAudio] Stadium Anthem '%s' started with %d stems on ArenaGlobe (Volume: %.2f)",
        anthemPrefix, #stemsToPlay, volume))
    return activeAnthemStems
end

function ArenaAudio.stopAnthem(fadeTime)
    fadeTime = fadeTime or 1.5
    isAnthemActive = false
    
    if next(activeAnthemStems) ~= nil then
        print(string.format("[ArenaAudio] Fading out Stadium Anthem stems (%.1fs)", fadeTime))
        local stemsToStop = activeAnthemStems
        activeAnthemStems = {}
        currentMusicType = "None"
        
        for sound, _ in pairs(stemsToStop) do
            if sound and sound.Parent then
                TweenService:Create(sound, TweenInfo.new(fadeTime), { Volume = 0 }):Play()
                task.delay(fadeTime, function()
                    sound:Stop()
                    sound:Destroy()
                end)
            end
        end
    end
end

function ArenaAudio.isAnthemActive()
    return isAnthemActive and next(activeAnthemStems) ~= nil
end

-- ============================================================================
-- WARHORN FX
-- ============================================================================

function ArenaAudio.playWarhorn(volume)
    findArenaGlobe()
    ensureSoundGroups()
    if not arenaGlobe then return nil end
    
    local chosen = WARHORNS[math.random(1, #WARHORNS)]
    local sound = Instance.new("Sound")
    sound.Name = "ArenaWarhorn_" .. chosen.Name
    sound.SoundId = chosen.Id
    sound.Looped = false
    sound.Volume = volume or 1.3
    sound.RollOffMinDistance = ArenaConfig.AudioSettings.SpeakerMinDistance
    sound.RollOffMaxDistance = ArenaConfig.AudioSettings.SpeakerMaxDistance
    sound.RollOffMode = ArenaConfig.AudioSettings.SpeakerRollOffMode
    sound.SoundGroup = masterGroup
    sound.Parent = arenaGlobe
    
    sound:Play()
    print(string.format("[ArenaAudio] Warhorn Sounded: %s (SoundId: %s, Vol: %.2f)", chosen.Name, chosen.Id, sound.Volume))
    
    task.delay(6.0, function()
        if sound and sound.Parent then
            sound:Stop()
            sound:Destroy()
        end
    end)
    return sound
end

-- ============================================================================
-- STANDARD PLAYLIST TRACK PLAYBACK (PreGame, InGame, PostGame)
-- ============================================================================

local function findMusicSoundAsset(trackNameOrId, playlistType)
    local arenaOne = Workspace:FindFirstChild("argoniaonion") and Workspace.argoniaonion:FindFirstChild("ArenaOne")
    local musicFolder = arenaOne and arenaOne:FindFirstChild("Music")
    if not musicFolder then return nil end
    
    local foldersToCheck = {}
    if playlistType == "PreGame" then
        table.insert(foldersToCheck, musicFolder:FindFirstChild("PreGameMusic"))
    elseif playlistType == "InGame" then
        table.insert(foldersToCheck, musicFolder:FindFirstChild("InGameMusic"))
    elseif playlistType == "PostGame" then
        table.insert(foldersToCheck, musicFolder:FindFirstChild("PostGameMusic"))
    else
        table.insert(foldersToCheck, musicFolder:FindFirstChild("PreGameMusic"))
        table.insert(foldersToCheck, musicFolder:FindFirstChild("InGameMusic"))
        table.insert(foldersToCheck, musicFolder:FindFirstChild("PostGameMusic"))
    end
    
    for _, folder in ipairs(foldersToCheck) do
        if folder then
            for _, s in ipairs(folder:GetChildren()) do
                if s:IsA("Sound") then
                    if trackNameOrId and (s.Name == trackNameOrId or s.SoundId == trackNameOrId) then
                        return s
                    end
                end
            end
        end
    end
    
    for _, folder in ipairs(foldersToCheck) do
        if folder then
            for _, s in ipairs(folder:GetChildren()) do
                if s:IsA("Sound") then
                    return s
                end
            end
        end
    end
    return nil
end

local function playOnGlobe(assetSound, trackId, trackName, volume, fadeTime, looped, soundType)
    findArenaGlobe()
    ensureSoundGroups()
    if not arenaGlobe then return nil end
    
    fadeTime = fadeTime or 1.5
    volume = volume or channelVolumes.Music
    isDucked = false
    duckCount = 0
    currentMusicType = soundType or "Music"
    
    if isAnthemActive then
        ArenaAudio.stopAnthem(fadeTime * 0.5)
    end
    
    if activeMusicSound and activeMusicSound.Parent then
        local old = activeMusicSound
        TweenService:Create(old, TweenInfo.new(fadeTime * 0.5), { Volume = 0 }):Play()
        task.delay(fadeTime * 0.5, function()
            old:Stop()
            old:Destroy()
        end)
    end
    
    local sound = Instance.new("Sound")
    sound.Name = "ArenaMusic_" .. (trackName or "Track")
    sound.SoundId = assetSound and assetSound.SoundId or trackId
    sound.Looped = (looped ~= false)
    sound.Volume = 0
    sound.RollOffMinDistance = ArenaConfig.AudioSettings.SpeakerMinDistance
    sound.RollOffMaxDistance = ArenaConfig.AudioSettings.SpeakerMaxDistance
    sound.RollOffMode = ArenaConfig.AudioSettings.SpeakerRollOffMode
    sound.SoundGroup = musicChannel
    sound.Parent = arenaGlobe
    
    sound:Play()
    TweenService:Create(sound, TweenInfo.new(fadeTime), { Volume = volume }):Play()
    activeMusicSound = sound
    
    print(string.format("[ArenaAudio] Playing %s: '%s' on ArenaGlobe (Volume: %.2f, Fade: %.1fs)",
        currentMusicType, trackName or sound.SoundId, volume, fadeTime))
    return sound
end

-- 1. PreGame Music (Runs across Open, Generation, and Prep Room = 50s total)
function ArenaAudio.playPregameMusic(trackNameOrId, volume, fadeTime)
    trackNameOrId = trackNameOrId or "365"
    volume = volume or channelVolumes.Music
    fadeTime = fadeTime or 2.0
    
    local asset = findMusicSoundAsset(trackNameOrId, "PreGame")
    local soundId = asset and asset.SoundId or "rbxassetid://99750260128110"
    local soundName = asset and asset.Name or trackNameOrId
    
    return playOnGlobe(asset, soundId, soundName, volume, fadeTime, true, "PreGameMusic")
end

function ArenaAudio.stopPregameMusic(fadeTime)
    fadeTime = fadeTime or 1.5
    if activeMusicSound and currentMusicType == "PreGameMusic" then
        print(string.format("[ArenaAudio] Fading out PreGameMusic (%.1fs)", fadeTime))
        local s = activeMusicSound
        TweenService:Create(s, TweenInfo.new(fadeTime), { Volume = 0 }):Play()
        task.delay(fadeTime, function()
            if s == activeMusicSound then
                activeMusicSound = nil
                currentMusicType = "None"
            end
            s:Stop()
            s:Destroy()
        end)
    end
end

-- 2. InGame Music
function ArenaAudio.playInGameMusic(trackNameOrId, volume, fadeTime)
    trackNameOrId = trackNameOrId or "ts - butterflyeffect live"
    volume = volume or channelVolumes.Music
    fadeTime = fadeTime or 1.5
    
    local asset = findMusicSoundAsset(trackNameOrId, "InGame")
    local soundId = asset and asset.SoundId or "rbxassetid://133867258789343"
    local soundName = asset and asset.Name or trackNameOrId
    
    return playOnGlobe(asset, soundId, soundName, volume, fadeTime, true, "InGameMusic")
end

function ArenaAudio.stopInGameMusic(fadeTime)
    fadeTime = fadeTime or 2.0
    if activeMusicSound and currentMusicType == "InGameMusic" then
        print(string.format("[ArenaAudio] Fading out InGameMusic (%.1fs)", fadeTime))
        local s = activeMusicSound
        TweenService:Create(s, TweenInfo.new(fadeTime), { Volume = 0 }):Play()
        task.delay(fadeTime, function()
            if s == activeMusicSound then
                activeMusicSound = nil
                currentMusicType = "None"
            end
            s:Stop()
            s:Destroy()
        end)
    end
end

-- 3. PostGame Music
function ArenaAudio.playPostgameMusic(trackNameOrId, volume, fadeTime)
    trackNameOrId = trackNameOrId or "Bai - Tenggelam (feat. Kurt Haikal) MAXIMUS2"
    volume = volume or channelVolumes.Music
    fadeTime = fadeTime or 2.5
    
    local asset = findMusicSoundAsset(trackNameOrId, "PostGame")
    local soundId = asset and asset.SoundId or "rbxassetid://139341117198830"
    local soundName = asset and asset.Name or trackNameOrId
    
    return playOnGlobe(asset, soundId, soundName, volume, fadeTime, true, "PostGameMusic")
end

function ArenaAudio.stopPostgameMusic(fadeTime)
    fadeTime = fadeTime or 3.0
    if activeMusicSound and currentMusicType == "PostGameMusic" then
        print(string.format("[ArenaAudio] Fading out PostGameMusic (%.1fs)", fadeTime))
        local s = activeMusicSound
        TweenService:Create(s, TweenInfo.new(fadeTime), { Volume = 0 }):Play()
        task.delay(fadeTime, function()
            if s == activeMusicSound then
                activeMusicSound = nil
                currentMusicType = "None"
            end
            s:Stop()
            s:Destroy()
        end)
    end
end

-- ============================================================================
-- DYNAMIC AUDIO DUCKING (When ARIA Speaks)
-- ============================================================================

function ArenaAudio.duck(multiplier, tweenTime)
    multiplier = multiplier or ArenaConfig.AudioSettings.DuckingMultiplier
    tweenTime = tweenTime or ArenaConfig.AudioSettings.DuckTweenTime
    duckCount = duckCount + 1
    ArenaCrowd.duck(true, tweenTime)
    
    if activeMusicSound and activeMusicSound.Parent then
        local targetVol = channelVolumes.Music * multiplier
        TweenService:Create(activeMusicSound, TweenInfo.new(tweenTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
            Volume = targetVol
        }):Play()
        isDucked = true
    end
    
    if next(activeAnthemStems) ~= nil then
        for sound, volWeight in pairs(activeAnthemStems) do
            if sound and sound.Parent then
                local targetVol = channelVolumes.Music * volWeight * multiplier
                TweenService:Create(sound, TweenInfo.new(tweenTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
                    Volume = targetVol
                }):Play()
            end
        end
        isDucked = true
    end
end

function ArenaAudio.unduck(tweenTime)
    tweenTime = tweenTime or ArenaConfig.AudioSettings.UnduckTweenTime
    duckCount = math.max(0, duckCount - 1)
    
    if duckCount == 0 then
        ArenaCrowd.duck(false, tweenTime)
        if activeMusicSound and activeMusicSound.Parent then
            TweenService:Create(activeMusicSound, TweenInfo.new(tweenTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
                Volume = channelVolumes.Music
            }):Play()
            isDucked = false
        end
        
        if next(activeAnthemStems) ~= nil then
            for sound, volWeight in pairs(activeAnthemStems) do
                if sound and sound.Parent then
                    local targetVol = channelVolumes.Music * volWeight
                    TweenService:Create(sound, TweenInfo.new(tweenTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
                        Volume = targetVol
                    }):Play()
                end
            end
            isDucked = false
        end
    end
end

-- Stop all sounds on ArenaGlobe
function ArenaAudio.stopAll(fadeTime)
    fadeTime = fadeTime or 0.8
    duckCount = 0
    isDucked = false
    ArenaCrowd.duck(false, 0.3)
    
    ArenaAudio.stopAnthem(fadeTime)
    
    findArenaGlobe()
    if arenaGlobe then
        for _, child in ipairs(arenaGlobe:GetChildren()) do
            if child:IsA("Sound") and (child.Name:find("Arena") or child.Name:find("ARIA") or child.Name:find("ActiveAnthem")) then
                if fadeTime > 0 then
                    TweenService:Create(child, TweenInfo.new(fadeTime), { Volume = 0 }):Play()
                    task.delay(fadeTime, function()
                        child:Stop()
                        child:Destroy()
                    end)
                else
                    child:Stop()
                    child:Destroy()
                end
            end
        end
    end
    activeMusicSound = nil
    currentMusicType = "None"
end

function ArenaAudio.getActiveTrackName()
    if isAnthemActive then
        return "Stadium Anthem (Multi-Stem)"
    end
    return activeMusicSound and activeMusicSound.Name or "None"
end

-- ============================================================================
-- REAL-TIME SLIDER UPDATES (Master Vol, Reverb Decay, Reverb Wetness, ARIA Voice, Music)
-- ============================================================================

function ArenaAudio.updateAcoustics(settings)
    ensureSoundGroups()
    if not masterGroup then return end
    if not settings or type(settings) ~= "table" then return end
    
    -- 1. Master Volume
    if settings.Master ~= nil or settings.Volume ~= nil then
        local vol = math.clamp(tonumber(settings.Master or settings.Volume) or 1.0, 0, 2)
        channelVolumes.Master = vol
        masterGroup.Volume = vol
    end
    
    -- 2. ARIA Voice Channel
    if settings.AriaVoice ~= nil then
        local vol = math.clamp(tonumber(settings.AriaVoice) or 1.2, 0, 2)
        channelVolumes.AriaVoice = vol
        if ariaChannel then
            ariaChannel.Volume = vol
        end
    end
    
    -- 3. Music Channel
    if settings.Music ~= nil then
        local vol = math.clamp(tonumber(settings.Music) or 0.85, 0, 2)
        channelVolumes.Music = vol
        if musicChannel then
            musicChannel.Volume = vol
        end
        if activeMusicSound and activeMusicSound.Parent and not isDucked then
            activeMusicSound.Volume = vol
        end
        if next(activeAnthemStems) ~= nil and not isDucked then
            for sound, volWeight in pairs(activeAnthemStems) do
                if sound and sound.Parent then
                    sound.Volume = vol * volWeight
                end
            end
        end
    end
    
    -- 3b. Crowd mix (ArenaCrowdManager); the anthem's stand stems follow AnthemStemScale live
    if type(settings.Crowd) == "table" then
        ArenaCrowd.setLevels(settings.Crowd)
        local scale = ArenaCrowd.getStemScale()
        for sound, base in pairs(standStemBase) do
            if activeAnthemStems[sound] and sound.Parent then
                activeAnthemStems[sound] = base * scale
                if not isDucked then
                    sound.Volume = channelVolumes.Music * base * scale
                end
            end
        end
        return
    end

    -- 4. Reverb Decay & Wetness (Echo is permanently removed)
    local reverb = masterGroup:FindFirstChildOfClass("ReverbSoundEffect")
    if reverb then
        if settings.ReverbDecay ~= nil then
            local decay = math.clamp(tonumber(settings.ReverbDecay) or 3.5, 0.1, 10.0)
            channelVolumes.ReverbDecay = decay
            reverb.DecayTime = decay
        end
        if settings.ReverbWet ~= nil then
            local wet = math.clamp(tonumber(settings.ReverbWet) or 2.0, -40.0, 15.0)
            channelVolumes.ReverbWet = wet
            reverb.WetLevel = wet
        end
    end
    
    print(string.format("[ArenaAudio] Channels Updated: Master=%.2f, AriaVoice=%.2f, Music=%.2f, RevDecay=%.2fs, RevWet=%.1fdB",
        channelVolumes.Master, channelVolumes.AriaVoice, channelVolumes.Music, channelVolumes.ReverbDecay, channelVolumes.ReverbWet))
end

function ArenaAudio.getAcousticSettings()
    return table.clone(channelVolumes)
end

-- Network Listener for UI Sliders
local ArenaNetwork = RS:FindFirstChild("ArenaNetwork")
if ArenaNetwork then
    local updateEvent = ArenaNetwork:FindFirstChild("UpdateAudioSettings")
    if not updateEvent then
        updateEvent = Instance.new("RemoteEvent")
        updateEvent.Name = "UpdateAudioSettings"
        updateEvent.Parent = ArenaNetwork
    end
    updateEvent.OnServerEvent:Connect(function(player, settings)
        ArenaAudio.updateAcoustics(settings)
    end)
end

ArenaAudio.init()

return ArenaAudio
