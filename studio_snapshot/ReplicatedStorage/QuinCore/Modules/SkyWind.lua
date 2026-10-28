--// SkyWind.lua
-- A subtle wind drone on a Quin that stays airborne: off the ground for AirTime seconds, or
-- already HighUp studs above it. Fades in, loops, fades out on the way down.
--
-- The source wav (35.75 s) fades in over its first second and out over its last: only the
-- steady middle (RegionStart..RegionEnd) is looped, a little slowed down.
--
-- One shared loop, started from Server (a loop connected from a Quin's Main dies with that Quin).
-- Off switch: CombatConfig.SkyWind.Enabled = false.

local GameClock = require(game:GetService("ReplicatedStorage"):WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("GameClock")) -- (the game's clock: a freeze stops it)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local QuinCore = ReplicatedStorage:WaitForChild("QuinCore")
local CombatConfig = require(QuinCore:WaitForChild("CombatConfig"))

local SkyWind = {}

local function cfg(key, default)
	local t = CombatConfig.SkyWind
	local v = t and t[key]
	if v == nil then return default end
	return v
end

local air = setmetatable({}, { __mode = "k" }) -- fighter -> { since, sound, on }

local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Exclude
params.IgnoreWater = true

-- Studs from the feet to whatever is below (math.huge: nothing within reach)
local function heightOf(root, humanoid)
	local feet = root.Position.Y - (humanoid.HipHeight + root.Size.Y / 2)
	local hit = Workspace:Raycast(root.Position, Vector3.new(0, -cfg("ProbeDepth", 400), 0), params)
	if not hit then return math.huge end
	return feet - hit.Position.Y
end

local function fade(sound, volume, time, thenStop)
	local tween = TweenService:Create(sound, TweenInfo.new(time, Enum.EasingStyle.Sine), { Volume = volume })
	tween:Play()
	if thenStop then
		tween.Completed:Connect(function(state)
			if state == Enum.PlaybackState.Completed and sound.Volume <= 0.001 then sound:Stop() end
		end)
	end
end

local function soundOn(root)
	local sound = root:FindFirstChild("SkyWindSound")
	if not sound then
		sound = Instance.new("Sound")
		sound.Name = "SkyWindSound"
		sound.SoundId = cfg("SoundId", "rbxassetid://81548846235276")
		sound.Looped = true
		sound.PlaybackRegionsEnabled = true
		sound.PlaybackRegion = NumberRange.new(cfg("RegionStart", 1.5), cfg("RegionEnd", 34))
		sound.LoopRegion = NumberRange.new(cfg("RegionStart", 1.5), cfg("RegionEnd", 34))
		sound.PlaybackSpeed = cfg("PlaybackSpeed", 0.85)
		sound.RollOffMode = Enum.RollOffMode.Linear
		sound.RollOffMinDistance = cfg("RollOffMin", 20)
		sound.RollOffMaxDistance = cfg("RollOffMax", 250)
		sound.Volume = 0
		sound.Parent = root
	end
	return sound
end

local function step()
	local folder = Workspace:FindFirstChild("QuinServer")
	if not folder then return end
	params.FilterDescendantsInstances = { folder }
	local now = GameClock.now()
	for _, fighter in ipairs(folder:GetChildren()) do
		local humanoid = fighter:FindFirstChildOfClass("Humanoid")
		local root = fighter:FindFirstChild("HumanoidRootPart")
		local a = air[fighter]
		if not humanoid or not root or humanoid.Health <= 0 then
			if a and a.sound and a.on then
				fade(a.sound, 0, cfg("FadeOut", 0.5), true)
				a.on = false
			end
		else
			local h = heightOf(root, humanoid)
			if h > cfg("AirHeight", 6) then
				if not a then
					a = { since = now }
					air[fighter] = a
				elseif not a.since then
					a.since = now
				end
				if not a.on and (now - a.since >= cfg("AirTime", 1) or h >= cfg("HighUp", 40)) then
					a.sound = soundOn(root)
					if not a.sound.IsPlaying then
						a.sound.TimePosition = cfg("RegionStart", 1.5) + math.random() * 20 -- not every Quin in step
						a.sound:Play()
					end
					fade(a.sound, cfg("Volume", 0.25), cfg("FadeIn", 0.4))
					a.on = true
				end
			elseif a then
				a.since = nil
				if a.on and h <= cfg("DownHeight", 3) then
					fade(a.sound, 0, cfg("FadeOut", 0.5), true)
					a.on = false
				end
			end
		end
	end
end

function SkyWind.start()
	if cfg("Enabled", true) == false then return end
	task.spawn(function()
		while true do
			local ok, err = pcall(step)
			if not ok then warn("[SkyWind] " .. tostring(err)) end
			GameClock.wait(cfg("Interval", 0.15))
		end
	end)
end

return SkyWind
