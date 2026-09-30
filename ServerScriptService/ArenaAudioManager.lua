--// ArenaAudioManager.lua
-- Authoritative acoustic sound & music manager for ArenaOne emitting from ArenaGlobe

local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local RS = game:GetService("ReplicatedStorage")

local ArenaConfig = require(RS.QuinCore.ArenaConfig)

local ArenaAudio = {}

local arenaGlobe = nil
local arenaSpeakerGroup = nil
local activeMusicSound = nil
local currentMusicType = "None"
local baselineMusicVolume = 1.0
local isDucked = false
local duckCount = 0

-- Ensure SoundService.ArenaSpeakerGroup exists with Bai's tuned acoustic effects
local function ensureSpeakerGroup()
    arenaSpeakerGroup = SoundService:FindFirstChild("ArenaSpeakerGroup")
    if not arenaSpeakerGroup then
        arenaSpeakerGroup = Instance.new("SoundGroup")
        arenaSpeakerGroup.Name = "ArenaSpeakerGroup"
        arenaSpeakerGroup.Volume = 1.0
        arenaSpeakerGroup.Parent = SoundService
    end
    
    local echo = arenaSpeakerGroup:FindFirstChildOfClass("EchoSoundEffect")
    if not echo then
        echo = Instance.new("EchoSoundEffect")
        echo.Name = "ArenaEcho"
        echo.Parent = arenaSpeakerGroup
    end
    echo.Delay = ArenaConfig.AudioSettings.Echo.Delay
    echo.DryLevel = ArenaConfig.AudioSettings.Echo.DryLevel
    echo.Feedback = ArenaConfig.AudioSettings.Echo.Feedback
    echo.WetLevel = ArenaConfig.AudioSettings.Echo.WetLevel
    
    local reverb = arenaSpeakerGroup:FindFirstChildOfClass("ReverbSoundEffect")
    if not reverb then
        reverb = Instance.new("ReverbSoundEffect")
        reverb.Name = "ArenaReverb"
        reverb.Parent = arenaSpeakerGroup
    end
    reverb.DecayTime = ArenaConfig.AudioSettings.Reverb.DecayTime
    reverb.Density = ArenaConfig.AudioSettings.Reverb.Density
    reverb.Diffusion = ArenaConfig.AudioSettings.Reverb.Diffusion
    reverb.DryLevel = ArenaConfig.AudioSettings.Reverb.DryLevel
    reverb.WetLevel = ArenaConfig.AudioSettings.Reverb.WetLevel
    
    return arenaSpeakerGroup
end

-- Locate ArenaGlobe speaker part
local function findArenaGlobe()
    local arenaOne = Workspace:FindFirstChild("argoniaonion") and Workspace.argoniaonion:FindFirstChild("ArenaOne")
    arenaGlobe = arenaOne and arenaOne:FindFirstChild("ArenaGlobe")
    return arenaGlobe
end

function ArenaAudio.init()
    ensureSpeakerGroup()
    findArenaGlobe()
    if arenaGlobe then
        print(string.format("[ArenaAudio] Initialized. ArenaGlobe at %s, SpeakerGroup connected.", tostring(arenaGlobe.Position)))
    else
        warn("[ArenaAudio] ArenaGlobe not found in Workspace.argoniaonion.ArenaOne!")
    end
end

-- Find a sound asset by Name or Id in Workspace.argoniaonion.ArenaOne.Music
local function findMusicSoundAsset(trackNameOrId, playlistType)
    local arenaOne = Workspace:FindFirstChild("argoniaonion") and Workspace.argoniaonion:FindFirstChild("ArenaOne")
    local musicFolder = arenaOne and arenaOne:FindFirstChild("Music")
    if not musicFolder then return nil end
    
    local foldersToCheck = {}
    if playlistType == "PreGame" then
        table.insert(foldersToCheck, musicFolder:FindFirstChild("PreGameMusic"))
        table.insert(foldersToCheck, musicFolder:FindFirstChild("FantasyMusic"))
    elseif playlistType == "PostGame" then
        table.insert(foldersToCheck, musicFolder:FindFirstChild("PostGameMusic"))
    else
        table.insert(foldersToCheck, musicFolder:FindFirstChild("PreGameMusic"))
        table.insert(foldersToCheck, musicFolder:FindFirstChild("FantasyMusic"))
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
    
    -- Fallback: return first sound found in first valid folder
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

-- Play a track on ArenaGlobe with speaker acoustics
local function playOnGlobe(assetSound, trackId, trackName, volume, fadeTime, looped, soundType)
    findArenaGlobe()
    ensureSpeakerGroup()
    if not arenaGlobe then return nil end
    
    fadeTime = fadeTime or 1.5
    volume = volume or ArenaConfig.AudioSettings.BaselineVolume
    baselineMusicVolume = volume
    isDucked = false
    duckCount = 0
    currentMusicType = soundType or "Music"
    
    -- Stop previous music cleanly
    if activeMusicSound and activeMusicSound.Parent then
        local old = activeMusicSound
        TweenService:Create(old, TweenInfo.new(fadeTime * 0.5), { Volume = 0 }):Play()
        task.delay(fadeTime * 0.5, function()
            old:Stop()
            old:Destroy()
        end)
    end
    
    -- Instantiate fresh sound on ArenaGlobe
    local sound = Instance.new("Sound")
    sound.Name = "ArenaMusic_" .. (trackName or "Track")
    sound.SoundId = assetSound and assetSound.SoundId or trackId
    sound.Looped = (looped ~= false)
    sound.Volume = 0
    sound.RollOffMinDistance = ArenaConfig.AudioSettings.SpeakerMinDistance
    sound.RollOffMaxDistance = ArenaConfig.AudioSettings.SpeakerMaxDistance
    sound.RollOffMode = ArenaConfig.AudioSettings.SpeakerRollOffMode
    sound.SoundGroup = arenaSpeakerGroup
    sound.Parent = arenaGlobe
    
    sound:Play()
    TweenService:Create(sound, TweenInfo.new(fadeTime), { Volume = volume }):Play()
    activeMusicSound = sound
    
    print(string.format("[ArenaAudio] Playing %s: '%s' on ArenaGlobe (Volume: %.2f, Fade: %.1fs)",
        currentMusicType, trackName or sound.SoundId, volume, fadeTime))
    return sound
end

-- 1. PreGame Music (Fades in during ArenaOpen, fades out during PreGame countdown)
function ArenaAudio.playPregameMusic(trackNameOrId, volume, fadeTime)
    trackNameOrId = trackNameOrId or "Bai - Skycastle Parade"
    volume = volume or ArenaConfig.AudioSettings.BaselineVolume
    fadeTime = fadeTime or 2.0
    
    local asset = findMusicSoundAsset(trackNameOrId, "PreGame")
    local soundId = asset and asset.SoundId or "rbxassetid://113929509678352"
    local soundName = asset and asset.Name or trackNameOrId
    
    return playOnGlobe(asset, soundId, soundName, volume, fadeTime, true, "PreGameMusic")
end

function ArenaAudio.stopPregameMusic(fadeTime)
    fadeTime = fadeTime or 2.0
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

-- 2. PostGame Music (Fades in during Arena Closure, fades out while ARIA_SkylarkClosure)
function ArenaAudio.playPostgameMusic(trackNameOrId, volume, fadeTime)
    trackNameOrId = trackNameOrId or "Bai - Tenggelam (feat. Kurt Haikal) MAXIMUS2"
    volume = volume or ArenaConfig.AudioSettings.BaselineVolume
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

-- 3. Dynamic Audio Ducking (for ARIA announcements)
function ArenaAudio.duck(multiplier, tweenTime)
    multiplier = multiplier or ArenaConfig.AudioSettings.DuckingMultiplier
    tweenTime = tweenTime or ArenaConfig.AudioSettings.DuckTweenTime
    duckCount = duckCount + 1
    
    if activeMusicSound and activeMusicSound.Parent then
        local targetVol = baselineMusicVolume * multiplier
        TweenService:Create(activeMusicSound, TweenInfo.new(tweenTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
            Volume = targetVol
        }):Play()
        isDucked = true
    end
end

function ArenaAudio.unduck(tweenTime)
    tweenTime = tweenTime or ArenaConfig.AudioSettings.UnduckTweenTime
    duckCount = math.max(0, duckCount - 1)
    
    if duckCount == 0 and activeMusicSound and activeMusicSound.Parent then
        TweenService:Create(activeMusicSound, TweenInfo.new(tweenTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
            Volume = baselineMusicVolume
        }):Play()
        isDucked = false
    end
end

-- Stop all sounds on ArenaGlobe
function ArenaAudio.stopAll(fadeTime)
    fadeTime = fadeTime or 0.8
    duckCount = 0
    isDucked = false
    
    findArenaGlobe()
    if arenaGlobe then
        for _, child in ipairs(arenaGlobe:GetChildren()) do
            if child:IsA("Sound") and child.Name:find("Arena") then
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
    return activeMusicSound and activeMusicSound.Name or "None"
end

ArenaAudio.init()

return ArenaAudio
