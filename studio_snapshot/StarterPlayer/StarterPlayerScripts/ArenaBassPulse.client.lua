--// ArenaBassPulse.client.lua
-- The arena's music, listened to on this machine: the low end (40-80 Hz) drives a subtle pulse of
-- the ArenaGlobe (a music visualiser) and gives the crowd its beat (ArenaCrowdClient reads
-- shared.ArenaBass).
--
-- Roblox's Sounds give only overall loudness, so the music playing now (the anthem's drum stem,
-- else the music on the ArenaGlobe) is mirrored into an AudioPlayer -> AudioAnalyzer chain that
-- has no output (nothing extra is heard), kept in step with the Sound's position, and the
-- analyser's spectrum is summed over 40-80 Hz. Without the new audio API, or with no signal (the
-- player's audio off), the Sound's own loudness stands in.
--
--   shared.ArenaBass = { level = 0..1 (the band, auto-levelled), beatAt = os.clock() of the last
--     kick, interval = seconds between kicks, live = a signal is coming in }

local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")

local BAND = { 40, 80 } -- Hz
local GLOBE_PULSE = 0.035 -- the globe grows by up to this share on a kick (subtle)
local KICK_RISE = 1.35 -- a kick: the band this much over its running average...
local KICK_GAP = 0.24 -- ...and at least this long after the last one

local bass = { level = 0, beatAt = 0, interval = 60 / 128, live = false }
shared.ArenaBass = bass

local arena, globe, globeSize = nil, nil, nil
local source = nil -- the Sound being followed
local player, analyzer = nil, nil -- the silent mirror
local avg, peak, lastSignal = 0, 1e-4, 0

local function findArena()
    local root = Workspace:FindFirstChild("argoniaonion")
    arena = root and root:FindFirstChild("ArenaOne")
    globe = arena and arena:FindFirstChild("ArenaGlobe")
    if globe and not globeSize then
        globeSize = globe.Size
    end
end

-- The music playing now: the anthem's drums first (the cleanest kicks), else the globe's music
local function findSource()
    if not arena then
        return nil
    end
    local drum, music = nil, nil
    for _, d in ipairs(arena:GetDescendants()) do
        if d:IsA("Sound") and d.IsPlaying and d.Volume > 0 then
            local name = d.Name:upper()
            if name:find("DRUM") then
                drum = d
            elseif globe and d.Parent == globe and name:find("MUSIC") then
                music = d
            end
        end
    end
    return drum or music
end

local function buildMirror(sound)
    if player then
        player:Destroy()
        player, analyzer = nil, nil
    end
    local ok = pcall(function()
        local p = Instance.new("AudioPlayer")
        p.Name = "ArenaBassMirror"
        p.Asset = sound.SoundId
        p.Looping = sound.Looped
        p.Volume = 1
        local a = Instance.new("AudioAnalyzer")
        a.SpectrumEnabled = true
        a.Parent = p
        local w = Instance.new("Wire")
        w.SourceInstance = p
        w.TargetInstance = a
        w.Parent = p
        p.Parent = SoundService
        p.TimePosition = sound.TimePosition
        p:Play()
        player, analyzer = p, a
    end)
    if not ok then
        player, analyzer = nil, nil
    end
end

-- The 40-80 Hz energy now (nil when the spectrum is not available)
local function bandEnergy()
    if not analyzer then
        return nil
    end
    local ok, spectrum = pcall(function()
        return analyzer:GetSpectrum()
    end)
    if not ok or type(spectrum) ~= "table" or #spectrum == 0 then
        return nil
    end
    local binHz = 24000 / #spectrum
    local sum = 0
    for i = math.max(1, math.floor(BAND[1] / binHz)), math.max(1, math.ceil(BAND[2] / binHz)) do
        sum += spectrum[i] or 0
    end
    return sum
end

local nextScan, nextSync = 0, 0
RunService.RenderStepped:Connect(function(dt)
    local now = os.clock()
    if now >= nextScan then
        nextScan = now + 1
        if not globe or not globe.Parent then
            globeSize = nil
            findArena()
        end
        local s = findSource()
        if s ~= source then
            source = s
            if s then
                buildMirror(s)
            elseif player then
                player:Destroy()
                player, analyzer = nil, nil
            end
        end
    end
    if source and player and now >= nextSync then
        nextSync = now + 1
        pcall(function()
            if math.abs(player.TimePosition - source.TimePosition) > 0.08 then
                player.TimePosition = source.TimePosition
            end
        end)
    end

    -- the band (or the Sound's loudness when the spectrum gives nothing)
    local energy = bandEnergy()
    if (not energy or energy <= 0) and source then
        energy = source.PlaybackLoudness
    end
    energy = energy or 0
    if energy > 1e-6 then
        lastSignal = now
    end
    bass.live = source ~= nil and now - lastSignal < 2

    -- auto-level: the loudest recent kick is 1
    peak = math.max(energy, peak * (1 - 0.15 * dt))
    local level = peak > 1e-6 and math.clamp(energy / peak, 0, 1) or 0
    -- fast up, slower down
    bass.level = level > bass.level and level or bass.level + (level - bass.level) * math.min(1, dt * 9)
    avg += (level - avg) * math.min(1, dt * 3)
    if bass.live and level > avg * KICK_RISE and level > 0.3 and now - bass.beatAt > KICK_GAP then
        local gap = now - bass.beatAt
        if gap < 1.2 then
            bass.interval = bass.interval * 0.75 + gap * 0.25
        end
        bass.beatAt = now
    end

    -- the globe breathes with the bass (only while it is lit and music plays)
    if globe and globeSize and globe.Transparency < 1 then
        globe.Size = globeSize * (1 + GLOBE_PULSE * (bass.live and bass.level or 0))
    elseif globe and globeSize and globe.Size ~= globeSize then
        globe.Size = globeSize
    end
end)
