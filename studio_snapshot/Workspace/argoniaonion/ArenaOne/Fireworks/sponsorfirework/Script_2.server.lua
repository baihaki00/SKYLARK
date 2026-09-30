--// 🔹 Auto Firework Script – Whistle + Echoing Boom (20km Sound Range)
-- ✅ Place this inside FireworkPart or any anchored launcher

local part = script.Parent
local Debris = game:GetService("Debris")

-- === SETTINGS ===
local WHISTLE_DURATION = 8.0
local WHISTLE_PITCH_START = 1.0
local WHISTLE_PITCH_END = 1.2
local FIRE_INTERVAL = 6 -- seconds between launches
local BOOM_VOLUME = 8
local SOUND_MAX_RANGE = 1500 -- studs (~10 km audible radius)
local SOUND_MIN_RANGE = 50    -- full-volume zone near listener

--whistle
local whistle = Instance.new("Sound")
whistle.SoundId = "rbxassetid://117243242368654" -- Whistle
whistle.Volume = 2
whistle.Looped = false
whistle.RollOffMode = Enum.RollOffMode.InverseTapered
whistle.RollOffMinDistance = SOUND_MIN_RANGE
whistle.RollOffMaxDistance = SOUND_MAX_RANGE
whistle.Parent = part

local boom = Instance.new("Sound")
boom.SoundId = "rbxassetid://72644283776071" -- Explosion
boom.Volume = BOOM_VOLUME
boom.Looped = false
boom.RollOffMode = Enum.RollOffMode.InverseTapered
boom.RollOffMinDistance = SOUND_MIN_RANGE
boom.RollOffMaxDistance = SOUND_MAX_RANGE
boom.Parent = part

-- === FIREWORK LOGIC ===
local function launchFirework()
	if whistle.IsPlaying then return end

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

	whistle:Play()

	task.spawn(function()
		local startTime = tick()
		while tick() - startTime < WHISTLE_DURATION do
			local t = (tick() - startTime) / WHISTLE_DURATION
			whistle.PlaybackSpeed = WHISTLE_PITCH_START + (WHISTLE_PITCH_END - WHISTLE_PITCH_START) * t
			task.wait(0.05)
		end

		-- 💥 Explosion phase
		whistle:Stop()
		bodyVel:Destroy()

		local explosion = Instance.new("Explosion")
		explosion.Position = firework.Position
		explosion.BlastPressure = 0
		explosion.BlastRadius = 0
		explosion.Parent = workspace

		boom:Play() -- 3D echo carries across ~10km

		-- ✨ Particles
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
	end)
end

-- === AUTO LOOP ===
task.spawn(function()
	while true do
		launchFirework()
		task.wait(FIRE_INTERVAL)
	end
end)
