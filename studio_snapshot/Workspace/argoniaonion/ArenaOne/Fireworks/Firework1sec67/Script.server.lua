--// Firework Script - Whistle + Boom
-- Place this inside the FireworkPart (with a ProximityPrompt)

local part = script.Parent
local prompt = part:WaitForChild("ProximityPrompt")
local Debris = game:GetService("Debris")

-- === SETTINGS ===
local WHISTLE_DURATION = 3.41
local WHISTLE_PITCH_START = 1.0
local WHISTLE_PITCH_END = 1.2
local BOOM_VOLUME = 6
local BOOM_RADIUS = 400

-- === CREATE SOUNDS ===
local whistle = Instance.new("Sound")
whistle.SoundId = "rbxassetid://117243242368654" -- Whistling sound (adjust if needed)
whistle.Volume = 2
whistle.Looped = false
whistle.Parent = part

local boom = Instance.new("Sound")
boom.SoundId = "rbxassetid://72644283776071" -- Explosion sound
boom.Volume = BOOM_VOLUME
boom.Looped = false
boom.Parent = part

-- === FIREWORK LOGIC ===
local function launchFirework()
	if whistle.IsPlaying then return end -- prevent spam

	-- Lift firework up
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

	-- Play whistle sound as it goes up
	whistle:Play()

	task.spawn(function()
		local startTime = tick()
		while tick() - startTime < WHISTLE_DURATION do
			local t = (tick() - startTime) / WHISTLE_DURATION
			whistle.PlaybackSpeed = WHISTLE_PITCH_START + (WHISTLE_PITCH_END - WHISTLE_PITCH_START) * t
			task.wait(0.05)
		end

		-- Boom time 💥
		whistle:Stop()
		bodyVel:Destroy()

		-- Create quick flash
		local explosion = Instance.new("Explosion")
		explosion.Position = firework.Position
		explosion.BlastPressure = 0
		explosion.BlastRadius = 0
		explosion.Parent = workspace

		-- Play boom sound
		boom:Play()

		-- Create particle effect
		local particles = Instance.new("ParticleEmitter")
		particles.Texture = "rbxassetid://258128463" -- simple sparkle
		particles.Lifetime = NumberRange.new(0.5)
		particles.Rate = 300
		particles.Speed = NumberRange.new(50)
		particles.SpreadAngle = Vector2.new(360, 360)
		particles.Parent = firework

		task.wait(0.3)
		particles.Enabled = false
		Debris:AddItem(firework, 2)
	end)
end

prompt.Triggered:Connect(launchFirework)
