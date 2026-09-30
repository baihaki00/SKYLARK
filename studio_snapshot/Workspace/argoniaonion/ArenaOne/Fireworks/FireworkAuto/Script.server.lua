--// Firework Auto Launcher - Whistle + Boom + Sizzle (Real 3D Position)
-- Boom and sizzle originate from explosion point in the sky

local part = script.Parent
local Debris = game:GetService("Debris")

-- === SETTINGS ===
local FIREWORK_COUNT = 100
local DELAY_BETWEEN = 3
local STARTUP_DELAY_MIN = 0.5
local STARTUP_DELAY_MAX = 5
local SOUND_MAX_RANGE = 1500
local SOUND_MIN_RANGE = 50

-- === SOUND SETTINGS ===
local WHISTLE_DURATION_MIN = 3.0
local WHISTLE_DURATION_MAX = 4.0
local WHISTLE_PITCH_MIN = 1
local WHISTLE_PITCH_MAX = 1.4
local WHISTLE_VOLUME = 0.1

local BOOM_VOLUME_MIN = 9
local BOOM_VOLUME_MAX = 11
local BOOM_PITCH_MIN = 0.8
local BOOM_PITCH_MAX = 1.1

local SIZZLE_VOLUME_MIN = 1.5
local SIZZLE_VOLUME_MAX = 3.0
local SIZZLE_PITCH_MIN = 0.9
local SIZZLE_PITCH_MAX = 1.8
local SIZZLE_DURATION = 2.3

-- === BASE SOUNDS ===
local baseWhistle = Instance.new("Sound")
baseWhistle.SoundId = "rbxassetid://109884925295619"
baseWhistle.Volume = 2
baseWhistle.Looped = false
baseWhistle.Parent = part
baseWhistle.RollOffMode = Enum.RollOffMode.InverseTapered
baseWhistle.RollOffMinDistance = SOUND_MIN_RANGE
baseWhistle.RollOffMaxDistance = SOUND_MAX_RANGE

local baseBoom = Instance.new("Sound")
baseBoom.SoundId = "rbxassetid://72644283776071"
baseBoom.Looped = false
baseBoom.RollOffMode = Enum.RollOffMode.InverseTapered
baseBoom.RollOffMinDistance = SOUND_MIN_RANGE
baseBoom.RollOffMaxDistance = SOUND_MAX_RANGE

local baseSizzle = Instance.new("Sound")
baseSizzle.SoundId = "rbxassetid://81063347593109"
baseSizzle.Looped = false
baseSizzle.RollOffMode = Enum.RollOffMode.InverseTapered
baseSizzle.RollOffMinDistance = SOUND_MIN_RANGE
baseSizzle.RollOffMaxDistance = SOUND_MAX_RANGE

-- === FIREWORK FUNCTION ===
local function launchFirework()
	return task.spawn(function()
		local whistle = baseWhistle:Clone()
		whistle.Parent = part

		local whistlePitchEnd = math.random(WHISTLE_PITCH_MIN * 100, WHISTLE_PITCH_MAX * 100) / 100

		-- Firework projectile
		local firework = Instance.new("Part")
		firework.Size = Vector3.new(0.4, 0.4, 0.4)
		firework.Color = Color3.new(1, 1, 0.8)
		firework.Material = Enum.Material.Neon
		firework.CanCollide = false
		firework.Anchored = false
		firework.CFrame = part.CFrame + Vector3.new(0, 2, 0)
		firework.Parent = workspace

		local bodyVel = Instance.new("BodyVelocity")
		bodyVel.Velocity = Vector3.new(0, 80, 0)
		bodyVel.MaxForce = Vector3.new(0, math.huge, 0)
		bodyVel.Parent = firework
		
		local WHISTLE_DURATION = math.random() * (WHISTLE_DURATION_MAX - WHISTLE_DURATION_MIN) + WHISTLE_DURATION_MIN

		-- === WHISTLE STAGE ===
		whistle.Volume = WHISTLE_VOLUME
		whistle:Play()
		local startTime = tick()
		while tick() - startTime < WHISTLE_DURATION do
			local t = (tick() - startTime) / WHISTLE_DURATION
			whistle.PlaybackSpeed = 0.6 + (whistlePitchEnd - 0.6) * t
			task.wait(0.05)
		end
		whistle:Stop()
		bodyVel:Destroy()

		-- === EXPLOSION POSITION ===
		local explosionPos = firework.Position

		-- Anchor part at explosion spot for sound 3D origin
		local soundAnchor = Instance.new("Part")
		soundAnchor.Size = Vector3.new(0.1, 0.1, 0.1)
		soundAnchor.Transparency = 1
		soundAnchor.CanCollide = false
		soundAnchor.Anchored = true
		soundAnchor.CFrame = CFrame.new(explosionPos)
		soundAnchor.Parent = workspace

		-- === BOOM STAGE 💥 ===
		local boom = baseBoom:Clone()
		boom.Volume = math.random(BOOM_VOLUME_MIN, BOOM_VOLUME_MAX)
		boom.PlaybackSpeed = math.random() * (BOOM_PITCH_MAX - BOOM_PITCH_MIN) + BOOM_PITCH_MIN
		boom.Parent = soundAnchor
		boom:Play()

		local explosion = Instance.new("Explosion")
		explosion.Position = explosionPos
		explosion.BlastPressure = 0
		explosion.BlastRadius = 0
		explosion.Parent = workspace

		local particles = Instance.new("ParticleEmitter")
		particles.Texture = "rbxassetid://258128463"
		particles.Lifetime = NumberRange.new(1)
		particles.Rate = 400
		particles.Speed = NumberRange.new(100)
		particles.SpreadAngle = Vector2.new(360, 360)
		particles.Parent = firework

		task.wait(0.3)
		particles.Enabled = false
		Debris:AddItem(firework, 2)

		-- === SIZZLE STAGE 🔥 ===
		local sizzle = baseSizzle:Clone()
		sizzle.Volume = math.random() * (SIZZLE_VOLUME_MAX - SIZZLE_VOLUME_MIN) + SIZZLE_VOLUME_MIN
		sizzle.PlaybackSpeed = math.random() * (SIZZLE_PITCH_MAX - SIZZLE_PITCH_MIN) + SIZZLE_PITCH_MIN
		sizzle.Parent = soundAnchor
		sizzle:Play()

		task.wait(SIZZLE_DURATION)
		sizzle:Stop()

		-- Cleanup
		whistle:Destroy()
		boom:Destroy()
		sizzle:Destroy()
		Debris:AddItem(soundAnchor, 2)
	end)
end

-- === SEQUENTIAL LOOP ===
task.spawn(function()
	local startupDelay = math.random(STARTUP_DELAY_MIN * 100, STARTUP_DELAY_MAX * 100) / 100
	task.wait(startupDelay)

	for i = 1, FIREWORK_COUNT do
		local delaylocal = math.clamp(math.random(), 1.0, 4.5)
		task.wait(delaylocal)
		launchFirework()
		task.wait(DELAY_BETWEEN)
	end
end)
