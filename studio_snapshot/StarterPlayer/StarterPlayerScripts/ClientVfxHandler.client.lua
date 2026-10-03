--// ClientVfxHandler
-- Camera shake. Each CameraShakeEvent (position, radius, intensity) adds "trauma" to the view:
-- more when closer (linear falloff over the radius), scaled by one master volume
-- (CombatConfig.CameraShake_Multiplier, live: Workspace attribute CameraShakeMultiplier, 0 = off).
-- The view turns by trauma^2 along smooth Perlin noise, capped at CameraShake_MaxPitch/Yaw/Roll,
-- and trauma fades at CameraShake_Decay per second: a small knock is a brief tremor, a slam a
-- short heavy rumble, identical at any frame rate. (It used to add random angle spikes every
-- frame and decay per frame, so it jittered, and its length depended on the frame rate.)

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local camera = workspace.CurrentCamera
local localPlayer = Players.LocalPlayer

local shakeEvent = ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Events"):WaitForChild("CameraShakeEvent")
local CombatConfig = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("CombatConfig"))

local trauma = 0
local clock = 0
local seed = math.random() * 100

local function shakeMultiplier()
	local live = workspace:GetAttribute("CameraShakeMultiplier")
	if type(live) == "number" then return live end
	return CombatConfig.CameraShake_Multiplier or 1
end

-- Where the viewer is: the camera itself (spectating, flying) or the character
local function viewerPosition()
	local cam = workspace.CurrentCamera
	return cam and cam.CFrame.Position or nil
end

shakeEvent.OnClientEvent:Connect(function(position, radius, intensity)
	local at = viewerPosition()
	if not at or typeof(position) ~= "Vector3" or not radius or radius <= 0 then return end
	local dist = (at - position).Magnitude
	if dist > radius then return end
	-- squared: an impact beside you is felt, one across the arena barely (16v16 landings
	-- everywhere inside 400-600 studs kept the view rumbling)
	local falloff = (1 - dist / radius) ^ 2
	local added = (intensity or 0) * falloff * shakeMultiplier() * (CombatConfig.CameraShake_TraumaPerDegree or 0.22)
	trauma = math.clamp(trauma + added, 0, 1)
end)

-- After the camera scripts have placed the camera for this frame
RunService:BindToRenderStep("ClientVfxShake", Enum.RenderPriority.Camera.Value + 2, function(dt)
	if trauma <= 0 then return end
	clock += dt
	local amount = trauma * trauma
	local freq = CombatConfig.CameraShake_Frequency or 18
	local t = clock * freq
	local pitch = math.noise(seed, t, 0) * (CombatConfig.CameraShake_MaxPitch or 2.0) * amount
	local yaw = math.noise(seed + 10, t, 0) * (CombatConfig.CameraShake_MaxYaw or 2.0) * amount
	local roll = math.noise(seed + 20, t, 0) * (CombatConfig.CameraShake_MaxRoll or 1.2) * amount
	-- (math.noise stays within about +-0.5; doubled so the caps are reachable)
	camera = workspace.CurrentCamera
	camera.CFrame = camera.CFrame * CFrame.Angles(math.rad(pitch * 2), math.rad(yaw * 2), math.rad(roll * 2))
	trauma = math.max(trauma - (CombatConfig.CameraShake_Decay or 1.6) * dt, 0)
end)
