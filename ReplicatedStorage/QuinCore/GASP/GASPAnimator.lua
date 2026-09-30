--// GASPAnimator.lua
-- Manages Motion Matching animation tracks, inertial cross-fading, and stride warping.
local Manifest = require(script.Parent:WaitForChild("GASPAnimationManifest"))

local GASPAnimator = {}
GASPAnimator.__index = GASPAnimator

local trackCaches = {}   -- [humanoid] = { [clipLabel] = track }
local activeClip = {}    -- [humanoid] = clipLabel
local currentTrack = {}  -- [humanoid] = track
local fadingTrack = {}   -- [humanoid] = track

local function getOrCreateTrack(humanoid, label)
    local cache = trackCaches[humanoid]
    if not cache then
        cache = {}
        trackCaches[humanoid] = cache
    end
    if cache[label] then return cache[label] end

    local clipData = Manifest.Clips[label]
    if not clipData or not clipData.id or clipData.id == "" then return nil end

    local animator = humanoid:FindFirstChildOfClass("Animator")
    if not animator then return nil end

    local anim = Instance.new("Animation")
    anim.Name = label
    anim.AnimationId = clipData.id

    local track = animator:LoadAnimation(anim)

    -- Multi-layer priority hierarchy matching Unreal AnimGraph
    if clipData.mode == "Idle" and clipData.action == "Loop" then
        track.Priority = Enum.AnimationPriority.Idle
    elseif clipData.action == "Stop" or clipData.action == "Turn" or clipData.action == "Start" or clipData.mode == "Jump" then
        track.Priority = Enum.AnimationPriority.Action
    else
        track.Priority = Enum.AnimationPriority.Movement
    end

    track.Looped = (clipData.action == "Loop")
    cache[label] = track
    return track
end

function GASPAnimator.play(humanoid, clipLabel, fadeTime, speedScale)
    if not humanoid or not clipLabel or clipLabel == "" then return nil end
    fadeTime = fadeTime or 0.20
    speedScale = speedScale or 1.00

    -- If requested clip is already actively playing, adjust stride warping speed
    if activeClip[humanoid] == clipLabel and currentTrack[humanoid] and currentTrack[humanoid].IsPlaying then
        currentTrack[humanoid]:AdjustSpeed(speedScale)
        return currentTrack[humanoid]
    end

    local newTrack = getOrCreateTrack(humanoid, clipLabel)
    if not newTrack then return nil end

    local oldTrack = currentTrack[humanoid]
    if oldTrack and oldTrack.IsPlaying and oldTrack ~= newTrack then
        oldTrack:Stop(fadeTime)
        fadingTrack[humanoid] = oldTrack
    end

    newTrack:Play(fadeTime)
    newTrack:AdjustSpeed(speedScale)
    currentTrack[humanoid] = newTrack
    activeClip[humanoid] = clipLabel
    return newTrack
end

function GASPAnimator.adjustSpeed(humanoid, speedScale)
    local track = currentTrack[humanoid]
    if track and track.IsPlaying then
        track:AdjustSpeed(speedScale)
    end
end

function GASPAnimator.getActiveClip(humanoid)
    return activeClip[humanoid]
end

function GASPAnimator.stop(humanoid, fadeTime)
    fadeTime = fadeTime or 0.20
    if currentTrack[humanoid] then
        currentTrack[humanoid]:Stop(fadeTime)
        currentTrack[humanoid] = nil
    end
    if fadingTrack[humanoid] then
        fadingTrack[humanoid]:Stop(fadeTime)
        fadingTrack[humanoid] = nil
    end
    activeClip[humanoid] = nil
end

function GASPAnimator.cleanup(humanoid)
    GASPAnimator.stop(humanoid, 0.1)
    trackCaches[humanoid] = nil
    activeClip[humanoid] = nil
    currentTrack[humanoid] = nil
    fadingTrack[humanoid] = nil
end

return GASPAnimator
