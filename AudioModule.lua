--// AudioModule.lua
-- Centralized audio playback with high bass and long roll-off distances

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")

local AudioModule = {}

-- Audio assets
local AudioIds = {
	ImpactLight = {
		"rbxassetid://137152517374202",
		"rbxassetid://106364380451721",
		"rbxassetid://137152517374202"
	},
	--ImpactHeavy = {
	--	"rbxassetid://90318464419858",
	--	"rbxassetid://90318464419858"
	--},
	ImpactHeavy = {
		"rbxassetid://90318464419858",
		"rbxassetid://90318464419858"
	},
	Slam = "rbxassetid://128160597080272", -- BOOM / Slam
	Shockwave = "rbxassetid://90318464419858", -- Explosion/Shockwave
	Dash = "rbxassetid://113019448050553",
	
	-- New Projectile Jump Sounds
	JumpUp = {
		"rbxassetid://133592422008028", -- JUMP_UP_HIGH_MID_AIR
		"rbxassetid://133966294953268"  -- JUMP_UP_HIGH_MID_AIR2
	},
	HitChargeup = "rbxassetid://99418155852897",
	MidairSwoosh = "rbxassetid://120299431620517",
	SonicBoom = {
		"rbxassetid://79960135069211",  -- MIDAIR_OVERHEAD_SONICBOOM
		"rbxassetid://128073196468988" -- MIDAIR_OVERHEAD_SONICBOOM2
	},
	FallOnGround = {
		"rbxassetid://127998881677599", -- FALL_ON_THE_GROUND
		"rbxassetid://128160597080272"  -- FALL_ON_THE_GROUND2
	},
	FallOnGroundMidAir = {
		"rbxassetid://128160597080272"  -- FALL_ON_THE_GROUND2
	}
}

local function playSoundAt(id, position, volume, pitch, eqGain)
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.Transparency = 1
	part.Size = Vector3.new(0.1, 0.1, 0.1)
	part.Position = position
	part.Parent = workspace

	local sound = Instance.new("Sound")
	
	if type(id) == "table" then
		sound.SoundId = id[math.random(1, #id)]
	else
		sound.SoundId = id
	end
	sound.Volume = volume or 1
	sound.PlaybackSpeed = pitch or 1
	sound.RollOffMode = Enum.RollOffMode.LinearSquare
	sound.RollOffMinDistance = 20
	sound.RollOffMaxDistance = 500 -- Hear from far away
	sound.Parent = part
	
	if eqGain then
		local eq = Instance.new("EqualizerSoundEffect")
		eq.LowGain = eqGain
		eq.MidGain = 0
		eq.HighGain = 0
		eq.Parent = sound
	end
	
	-- Add a tiny bit of reverb for spatial ambiance
	local reverb = Instance.new("ReverbSoundEffect")
	reverb.Density = 0.8
	reverb.Diffusion = 0.8
	reverb.DryLevel = 0      -- Full original sound volume
	reverb.DecayTime = 0.8   -- Short decay for a punchy, tight room feel
	reverb.WetLevel = -12    -- Low wet level so it's a "tiny bit" and not overwhelming
	reverb.Parent = sound
	
	sound:Play()
	Debris:AddItem(part, sound.TimeLength > 0 and sound.TimeLength + 1 or 5)
end

function AudioModule.playImpact(position, isHeavy)
	if isHeavy then
		playSoundAt(AudioIds.ImpactHeavy, position, 0.05, math.random(80, 100)/100, 15)
	else
		playSoundAt(AudioIds.ImpactLight, position, 0.05, math.random(90, 110)/100, 5)
	end
end

function AudioModule.playSlam(position)
	playSoundAt(AudioIds.Slam, position, 0.05, 0.8, 25)
	playSoundAt(AudioIds.Shockwave, position, 0.05, 0.7, 30)
end

function AudioModule.playDash(targetOrPos)
	local sound = Instance.new("Sound")
	sound.Name = "DashSound"
	sound.SoundId = AudioIds.Dash
	sound.Volume = 1.2
	sound.RollOffMinDistance = 15
	sound.RollOffMaxDistance = 150
	sound.RollOffMode = Enum.RollOffMode.Linear
	sound.PlaybackSpeed = math.random(95, 110) / 100

	if typeof(targetOrPos) == "Instance" then
		sound.Parent = targetOrPos
		sound:Play()
		Debris:AddItem(sound, 2)
	elseif typeof(targetOrPos) == "Vector3" then
		local part = Instance.new("Part")
		part.Anchored = true
		part.CanCollide = false
		part.Transparency = 1
		part.Size = Vector3.new(0.1, 0.1, 0.1)
		part.Position = targetOrPos
		part.Parent = workspace
		sound.Parent = part
		sound:Play()
		Debris:AddItem(part, 2)
	else
		sound.Parent = workspace
		sound:Play()
		Debris:AddItem(sound, 2)
	end
end

-- Projectile Jump Audio Methods
function AudioModule.playJumpUp(position)
	playSoundAt(AudioIds.JumpUp, position, 0.05, math.random(90, 110)/100, 5)
end

function AudioModule.playChargeup(position)
	playSoundAt(AudioIds.HitChargeup, position, 0.5, 1, 10)
end

function AudioModule.playMidairSwoosh(position)
	playSoundAt(AudioIds.MidairSwoosh, position, 1.6, math.random(95, 105)/100, 5)
end

function AudioModule.playSonicBoom(position)
	playSoundAt(AudioIds.SonicBoom, position, 1, math.random(90, 110)/100, 20)
end

function AudioModule.playFallOnGround(position)
	playSoundAt(AudioIds.FallOnGround, position, 0.03, math.random(70, 100)/100, 15)
end

function AudioModule.playFallOnGroundAfterMidAir(position)
	playSoundAt(AudioIds.FallOnGroundMidAir, position, 0.03, math.random(70, 100)/100, 15)
end

local lastFootstep = {}
local SoundFootstepsFolder = ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Assets"):WaitForChild("SoundFootsteps")
local footstepSounds = SoundFootstepsFolder:GetChildren()

function AudioModule.playFootstep(fighter, volume)
	local hrp = fighter:FindFirstChild("HumanoidRootPart")
	if not hrp then return end
	
	if #footstepSounds == 0 then return end
	
	-- Pick a random footstep that isn't the last one
	local chosenIdx = math.random(1, #footstepSounds)
	if lastFootstep[fighter] == chosenIdx and #footstepSounds > 1 then
		chosenIdx = (chosenIdx % #footstepSounds) + 1
	end
	lastFootstep[fighter] = chosenIdx
	
	local originalSound = footstepSounds[chosenIdx]
	if originalSound and originalSound:IsA("Sound") then
		local clone = originalSound:Clone()
		clone.Volume = volume or 0.5
		clone.PlaybackSpeed = math.random(84, 106) / 100
		clone.RollOffMinDistance = 20
		clone.RollOffMaxDistance = 300
		clone.RollOffMode = Enum.RollOffMode.Linear
		clone.Parent = hrp
		clone:Play()
		Debris:AddItem(clone, 0.6)
	end
end

function AudioModule.playClash(position)
	playSoundAt(AudioIds.SonicBoom, position, 0.8, 1.2, 20)
	playSoundAt(AudioIds.ImpactHeavy, position, 0.6, 1.1, 15)
end

function AudioModule.playDodge(position)
	playSoundAt(AudioIds.Dash, position, 0.6, 1.2, 10)
end

return AudioModule
