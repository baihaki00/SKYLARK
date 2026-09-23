-- 🔹 Silver Surfer Fly Script (Smooth Hover + Levitate + Animate Override) for Sir Bai
-- ✅ Place this in: StarterPlayer > StarterPlayerScripts

local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Players = game:GetService("Players")
local player = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local humanoidRootPart = character:WaitForChild("HumanoidRootPart")
local humanoid = character:WaitForChild("Humanoid")

-- ✅ Admin Whitelist
if player.Name ~= "Bai" and player.Name ~= "baiyyaki00" then
	return
end

-- ===== SETTINGS =====
local flySpeed = 180 -- Max speed
local hoverHeight = 4 -- 🪄 Maintain 4 studs above ground
local liftStrength = 250 -- Smooth hover correction force
local acceleration = 2 -- 🌀 Speed buildup rate
local deceleration = 1 -- 🌙 Slowdown rate
local flyEnabled = false
local speedBoost = false
local normalSpeed = 180
local boostedSpeed = 1500

-- 📷 Debug Camera Toggle
local staticCameraEnabled = false

local levitateAnimId = "rbxassetid://104743532035705" -- 🌀 Idle Hover
local flyAnimId = "rbxassetid://121350465480611" -- ⚡ Forward Flight
local idleAnimTrack
local flyAnimTrack
local animateScript

local customWalkAnimId = "rbxassetid://121387473958634"
local customWalkTrack
local customWalkEnabled = false

-- ===== CONTROL STATE =====
local move = Vector3.zero
local currentVelocity = Vector3.zero -- 🧭 Smooth velocity blend
local cam = Workspace.CurrentCamera

-- ===== ANIMATION =====
local function playLevitate()
	if idleAnimTrack then idleAnimTrack:Stop() end
	if flyAnimTrack then flyAnimTrack:Stop() end

	-- Stop all currently playing animations (like Walk, Jump, Fall) from the base animator
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if animator then
		for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
			track:Stop(0.2)
		end
	end

	local idleAnim = Instance.new("Animation")
	idleAnim.AnimationId = levitateAnimId
	idleAnimTrack = humanoid:LoadAnimation(idleAnim)
	idleAnimTrack.Looped = true
	idleAnimTrack.Priority = Enum.AnimationPriority.Action4

	local flyAnim = Instance.new("Animation")
	flyAnim.AnimationId = flyAnimId
	flyAnimTrack = humanoid:LoadAnimation(flyAnim)
	flyAnimTrack.Looped = true
	flyAnimTrack.Priority = Enum.AnimationPriority.Action4

	idleAnimTrack:Play(0.2)
end

local function stopLevitate()
	if idleAnimTrack then
		idleAnimTrack:Stop(0.3)
		idleAnimTrack = nil
	end
	if flyAnimTrack then
		flyAnimTrack:Stop(0.3)
		flyAnimTrack = nil
	end
end

-- ===== ANIMATE OVERRIDE =====
local function disableAnimate()
	if not animateScript then
		animateScript = character:FindFirstChild("Animate")
	end
	if animateScript then
		animateScript.Disabled = true
	end
end

local function enableAnimate()
	if animateScript then
		animateScript.Disabled = false
	end
end

-- ===== FLY =====
local hoverGyro
local hoverVelocity
local hoverConnection

local function startFlying()
	if flyEnabled then return end
	flyEnabled = true

	disableAnimate()

	hoverGyro = Instance.new("BodyGyro")
	hoverGyro.MaxTorque = Vector3.new(400000, 400000, 400000)
	hoverGyro.P = 5000
	hoverGyro.CFrame = humanoidRootPart.CFrame
	hoverGyro.Parent = humanoidRootPart

	hoverVelocity = Instance.new("BodyVelocity")
	hoverVelocity.MaxForce = Vector3.new(400000, 400000, 400000)
	hoverVelocity.Velocity = Vector3.zero
	hoverVelocity.Parent = humanoidRootPart

	playLevitate()

	hoverConnection = RunService.RenderStepped:Connect(function(dt)
		if not flyEnabled then return end

		local cameraCFrame = cam.CFrame
		local targetDirection = (cameraCFrame.RightVector * move.X + cameraCFrame.LookVector * move.Z + Vector3.new(0, move.Y, 0))

		-- === Dynamic Tilt / Orientation ===
		local targetRoll = move.X * math.rad(-35) -- Bank left/right
		local targetPitch = move.Z * math.rad(30) -- Pitch forward/back
		if move.Y > 0 then targetPitch = targetPitch + math.rad(20) end
		if move.Y < 0 then targetPitch = targetPitch - math.rad(20) end

		local tiltCFrame = CFrame.Angles(targetPitch, 0, targetRoll)
		hoverGyro.CFrame = cameraCFrame * tiltCFrame

		-- === Animation Blending ===
		local isMoving = move.X ~= 0 or move.Z ~= 0 or move.Y ~= 0
		if isMoving then
			if not flyAnimTrack.IsPlaying then flyAnimTrack:Play(0.3) end
			if idleAnimTrack.IsPlaying then idleAnimTrack:Stop(0.3) end
		else
			if flyAnimTrack.IsPlaying then flyAnimTrack:Stop(0.3) end
			if not idleAnimTrack.IsPlaying then idleAnimTrack:Play(0.3) end
		end

		-- === Hover logic ===
		local rayOrigin = humanoidRootPart.Position
		local rayDirection = Vector3.new(0, 50, 0)
		local raycastResult = Workspace:Raycast(rayOrigin, rayDirection)

		local verticalCorrection = 0
		if raycastResult then
			local groundDistance = (rayOrigin - raycastResult.Position).Magnitude
			local heightDiff = hoverHeight - groundDistance
			verticalCorrection = heightDiff * liftStrength * dt
		end

		-- === SMOOTH MOVEMENT (ACCELERATION/DECELERATION) ===
		local targetVelocity = targetDirection * flySpeed
		currentVelocity = currentVelocity:Lerp(targetVelocity, math.clamp(dt * (targetDirection.Magnitude > 0 and acceleration or deceleration), 0, 1))

		-- === Apply velocity with hover lift ===
		local finalVelocity = currentVelocity + Vector3.new(0, verticalCorrection, 0)
		hoverVelocity.Velocity = finalVelocity
	end)
end

local function stopFlying()
	flyEnabled = false

	if hoverConnection then
		hoverConnection:Disconnect()
		hoverConnection = nil
	end

	if hoverGyro then
		hoverGyro:Destroy()
		hoverGyro = nil
	end

	if hoverVelocity then
		hoverVelocity:Destroy()
		hoverVelocity = nil
	end

	stopLevitate()
	enableAnimate()
end

-- ===== INPUT HANDLERS =====
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end

	-- 🪽 Fly Toggle (F)
	if input.KeyCode == Enum.KeyCode.F then
		if flyEnabled then
			stopFlying()
		else
			startFlying()
		end
	end

	-- 📷 Static Camera Debug Toggle (C)
	if input.KeyCode == Enum.KeyCode.C then
		staticCameraEnabled = not staticCameraEnabled
		if staticCameraEnabled then
			cam.CameraType = Enum.CameraType.Scriptable
			print("📷 Debug Camera FROZEN")
		else
			cam.CameraType = Enum.CameraType.Custom
			cam.CameraSubject = humanoid
			print("📷 Debug Camera NORMAL")
		end
	end

	-- 🚶 Custom Walk Toggle (U)
	if input.KeyCode == Enum.KeyCode.U then
		customWalkEnabled = not customWalkEnabled
		humanoid.WalkSpeed = customWalkEnabled and 14 or 16
		print(customWalkEnabled and "🚶 Custom Walk Engaged" or "🚶 Normal Walk Restored")
	end

	-- 🟢 Speed boost toggle (J)
	if input.KeyCode == Enum.KeyCode.J and flyEnabled then
		speedBoost = not speedBoost
		flySpeed = speedBoost and boostedSpeed or normalSpeed
		print(speedBoost and "⚡ Speed Boost Activated, Sir Bai!" or "🌙 Speed Boost Deactivated")
	end

	-- Movement
	if input.KeyCode == Enum.KeyCode.W then move = Vector3.new(move.X, move.Y, 1) end
	if input.KeyCode == Enum.KeyCode.S then move = Vector3.new(move.X, move.Y, -1) end
	if input.KeyCode == Enum.KeyCode.A then move = Vector3.new(-1, move.Y, move.Z) end
	if input.KeyCode == Enum.KeyCode.D then move = Vector3.new(1, move.Y, move.Z) end
	if input.KeyCode == Enum.KeyCode.Space then move = Vector3.new(move.X, 1, move.Z) end
	if input.KeyCode == Enum.KeyCode.LeftShift then move = Vector3.new(move.X, -1, move.Z) end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.W or input.KeyCode == Enum.KeyCode.S then move = Vector3.new(move.X, move.Y, 0) end
	if input.KeyCode == Enum.KeyCode.A or input.KeyCode == Enum.KeyCode.D then move = Vector3.new(0, move.Y, move.Z) end
	if input.KeyCode == Enum.KeyCode.Space or input.KeyCode == Enum.KeyCode.LeftShift then move = Vector3.new(move.X, 0, move.Z) end
end)

-- === Custom Walk Logic ===
RunService.RenderStepped:Connect(function()
	if flyEnabled then
		if customWalkTrack and customWalkTrack.IsPlaying then
			customWalkTrack:Stop(0.2)
		end
		return
	end

	if customWalkEnabled then
		local isMoving = humanoid.MoveDirection.Magnitude > 0
		local isGrounded = humanoid.FloorMaterial ~= Enum.Material.Air

		if isMoving and isGrounded then
			if not customWalkTrack then
				local anim = Instance.new("Animation")
				anim.AnimationId = customWalkAnimId
				customWalkTrack = humanoid:LoadAnimation(anim)
				customWalkTrack.Priority = Enum.AnimationPriority.Action4
				customWalkTrack.Looped = true
			end
			if not customWalkTrack.IsPlaying then 
				customWalkTrack:Play(0.2, 1.0, 0.8) -- 0.8x speed for a slow, badass walk
			end
		else
			if customWalkTrack and customWalkTrack.IsPlaying then customWalkTrack:Stop(0.2) end
		end
	else
		if customWalkTrack and customWalkTrack.IsPlaying then customWalkTrack:Stop(0.2) end
	end
end)