--// ArenaFireworksManager.lua
-- Programmatic, authoritative control of stadium fireworks in ArenaOne

local Debris = game:GetService("Debris")
local Workspace = game:GetService("Workspace")

local ArenaFireworks = {}

local activeShowThread = nil
local isShowActive = false

-- Base sounds
local SOUND_WHISTLE = "rbxassetid://109884925295619"
local SOUND_BOOM    = "rbxassetid://72644283776071"
local SOUND_SIZZLE  = "rbxassetid://81063347593109"
local PARTICLE_TEX  = "rbxassetid://258128463"

local fireworkParts = {}

function ArenaFireworks.init()
    fireworkParts = {}
    local arenaOne = Workspace:FindFirstChild("argoniaonion") and Workspace.argoniaonion:FindFirstChild("ArenaOne")
    local fwFolder = arenaOne and arenaOne:FindFirstChild("Fireworks")
    if fwFolder then
        for _, child in ipairs(fwFolder:GetChildren()) do
            if child:IsA("BasePart") then
                table.insert(fireworkParts, child)
                -- Disable default background auto scripts so fireworks only fire authoritatively
                local s = child:FindFirstChildOfClass("Script")
                if s then
                    s.Disabled = true
                end
            end
        end
    end
    print(string.format("[ArenaFireworksManager] Initialized with %d launch platforms.", #fireworkParts))
end

-- Launch a single rocket with authentic physics, 3D whistling ramp, explosion boom and particle blast
function ArenaFireworks.launchRocket(originPart, customColor, velocityY)
    if not originPart or not originPart.Parent then return end
    
    velocityY = velocityY or math.random(75, 110)
    local col = customColor or Color3.fromHSV(math.random(), 0.85, 1.0)
    
    task.spawn(function()
        -- 1. Rocket Projectile
        local rocket = Instance.new("Part")
        rocket.Name = "ArenaFireworkRocket"
        rocket.Size = Vector3.new(0.6, 0.6, 0.6)
        rocket.Color = col
        rocket.Material = Enum.Material.Neon
        rocket.CanCollide = false
        rocket.Anchored = false
        rocket.CFrame = originPart.CFrame + Vector3.new(math.random(-2, 2), 2, math.random(-2, 2))
        rocket.Parent = Workspace
        
        -- Spark trail
        local trail = Instance.new("ParticleEmitter")
        trail.Texture = PARTICLE_TEX
        trail.Color = ColorSequence.new(col)
        trail.Size = NumberSequence.new(0.4, 0.05)
        trail.Lifetime = NumberRange.new(0.3, 0.5)
        trail.Rate = 120
        trail.Speed = NumberRange.new(5, 15)
        trail.Parent = rocket
        
        local bodyVel = Instance.new("BodyVelocity")
        bodyVel.Velocity = Vector3.new(math.random(-10, 10), velocityY, math.random(-10, 10))
        bodyVel.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
        bodyVel.Parent = rocket
        
        -- Whistle sound
        local whistle = Instance.new("Sound")
        whistle.SoundId = SOUND_WHISTLE
        whistle.Volume = 1.2
        whistle.RollOffMaxDistance = 1200
        whistle.RollOffMinDistance = 60
        whistle.Parent = rocket
        whistle:Play()
        
        local flightTime = math.random(16, 26) / 10 -- 1.6s - 2.6s
        local startTime = os.clock()
        while (os.clock() - startTime) < flightTime and rocket.Parent do
            local progress = (os.clock() - startTime) / flightTime
            whistle.PlaybackSpeed = 0.8 + progress * 0.7
            task.wait(0.05)
        end
        
        if not rocket.Parent then return end
        local explosionPos = rocket.Position
        whistle:Stop()
        rocket:Destroy()
        
        -- 2. Explosion Anchor for 3D Sound
        local soundAnchor = Instance.new("Part")
        soundAnchor.Name = "FireworkDetonationPoint"
        soundAnchor.Size = Vector3.new(0.2, 0.2, 0.2)
        soundAnchor.Transparency = 1
        soundAnchor.CanCollide = false
        soundAnchor.Anchored = true
        soundAnchor.CFrame = CFrame.new(explosionPos)
        soundAnchor.Parent = Workspace
        Debris:AddItem(soundAnchor, 5)
        
        -- Boom sound
        local boom = Instance.new("Sound")
        boom.SoundId = SOUND_BOOM
        boom.Volume = math.random(6, 9)
        boom.PlaybackSpeed = math.random(85, 115) / 100
        boom.RollOffMaxDistance = 2500
        boom.RollOffMinDistance = 100
        boom.Parent = soundAnchor
        boom:Play()
        
        -- Visual Flash & Explosion
        local exp = Instance.new("Explosion")
        exp.Position = explosionPos
        exp.BlastPressure = 0
        exp.BlastRadius = 0
        exp.Parent = Workspace
        
        -- Multi-tier Starburst Particles
        local burst = Instance.new("ParticleEmitter")
        burst.Texture = PARTICLE_TEX
        burst.Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, col),
            ColorSequenceKeypoint.new(0.7, Color3.new(1, 1, 0.8)),
            ColorSequenceKeypoint.new(1, Color3.new(0.2, 0.2, 0.2)),
        })
        burst.Size = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 1.2),
            NumberSequenceKeypoint.new(0.5, 0.8),
            NumberSequenceKeypoint.new(1, 0),
        })
        burst.Lifetime = NumberRange.new(1.2, 2.0)
        burst.Rate = 500
        burst.Speed = NumberRange.new(60, 120)
        burst.SpreadAngle = Vector2.new(360, 360)
        burst.Drag = 3.5
        burst.Parent = soundAnchor
        
        task.wait(0.25)
        burst.Enabled = false
    end)
end

-- Launch opening ceremony barrage (synchronized across stadium)
function ArenaFireworks.launchOpeningShow(duration)
    duration = duration or 6
    ArenaFireworks.stopAll()
    isShowActive = true
    
    activeShowThread = task.spawn(function()
        local endTime = os.clock() + duration
        while isShowActive and os.clock() < endTime do
            if #fireworkParts > 0 then
                -- Pick 2-3 random launchers
                for _ = 1, math.random(2, 4) do
                    local p = fireworkParts[math.random(1, #fireworkParts)]
                    ArenaFireworks.launchRocket(p, nil, math.random(85, 120))
                end
            end
            task.wait(math.random(6, 14) / 10) -- 0.6s to 1.4s between volleys
        end
        isShowActive = false
    end)
end

-- Grand Finale Winner Celebration Show (rapid bursts & grand finale barrage)
function ArenaFireworks.launchWinnerShow(duration)
    duration = duration or 8
    ArenaFireworks.stopAll()
    isShowActive = true
    
    activeShowThread = task.spawn(function()
        local endTime = os.clock() + duration
        -- Rapid gold/cyan victory volleys
        local gold = Color3.fromRGB(255, 215, 0)
        local cyan = Color3.fromRGB(0, 220, 255)
        local white = Color3.fromRGB(255, 255, 255)
        local colors = { gold, cyan, white }
        
        while isShowActive and os.clock() < endTime do
            for _, p in ipairs(fireworkParts) do
                if math.random() > 0.3 then
                    local c = colors[math.random(1, #colors)]
                    ArenaFireworks.launchRocket(p, c, math.random(90, 130))
                end
            end
            task.wait(0.7)
        end
        isShowActive = false
    end)
end

function ArenaFireworks.stopAll()
    isShowActive = false
    if activeShowThread then
        task.cancel(activeShowThread)
        activeShowThread = nil
    end
end

ArenaFireworks.init()

return ArenaFireworks
