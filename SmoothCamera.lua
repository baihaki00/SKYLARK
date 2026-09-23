--// SmoothCamera.client.lua
-- Default Freefly Spectator Camera + Smooth Quin Focus Support
-- Starts by default elevated above the arena for optimal tactical battlefield observation

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Camera = workspace.CurrentCamera

local player = Players.LocalPlayer

-- === SETTINGS (HIGH SPEED TACTICAL FREECAM) ===
local baseFlySpeed = 300 -- Boosted ~5x (was 65) for fast agile arena freefly
local sprintMultiplier = 3.5 -- Holding Shift reaches 1,050 studs/s hyper-fly
local flySensitivity = 0.32
local minAltitude = 5.0
local maxAltitude = 1200.0

-- Orbit mode settings (used when spectating a Quin)
local orbitSmoothness = 10
local posSmoothness = 14
local zoomSpeed = 3.0
local minZoom, maxZoom = 4.0, 45.0

-- === INITIAL STATE: FREEFLY ABOVE ARENA ===
local cameraMode = "FREEFLY" -- "FREEFLY" or "QUIN_SPECTATE"
shared.SpectatorState = { Mode = "FREEFLY" }
local cameraPos = Vector3.new(0, 140, 160)
local yaw = 0
local pitch = -38.0 -- Angled downward at the battlefield center

-- Orbit internals
local smoothYaw, smoothPitch = yaw, pitch
local targetDistance = 18
local currentDistance = targetDistance
local smoothedTargetPos = nil

local isLeftMouseDown = false
local isRightMouseDown = false
local isToggleLocked = false

-- Ensure player character is non-interfering spectator
local function isolatePlayerCharacter(char)
	if not char then return end
	local root = char:WaitForChild("HumanoidRootPart", 5)
	local hum = char:FindFirstChildOfClass("Humanoid")
	if root then
		root.Anchored = true
		root.CFrame = CFrame.new(0, 600, 0)
	end
	for _, part in ipairs(char:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CanCollide = false
			part.Transparency = 1
			part.CastShadow = false
		end
	end
	if hum then
		hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	end
end

if player.Character then
	isolatePlayerCharacter(player.Character)
end
player.CharacterAdded:Connect(isolatePlayerCharacter)

-- === MOUSE CONTROLS ===
local function updateMouseBehavior()
	if isLeftMouseDown or isRightMouseDown or isToggleLocked then
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
		UserInputService.MouseIconEnabled = false
	else
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		UserInputService.MouseIconEnabled = true
	end
end

local function lockMouse()
	isToggleLocked = true
	updateMouseBehavior()
end

local function unlockMouse()
	isToggleLocked = false
	isLeftMouseDown = false
	isRightMouseDown = false
	updateMouseBehavior()
end

-- Helper to verify an object and all its ancestors are truly visible
local function isTrulyVisible(obj, playerGui)
	local cur = obj
	while cur and cur ~= playerGui and not cur:IsA("ScreenGui") do
		if not cur.Visible then return false end
		cur = cur.Parent
	end
	return true
end

-- Helper to check if a mouse position is over an interactive GUI element
local function isClickOnGui(mousePos)
	if not mousePos then
		mousePos = UserInputService:GetMouseLocation()
	end
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	if not playerGui then return false end

	local guis = playerGui:GetGuiObjectsAtPosition(mousePos.X, mousePos.Y)
	for _, obj in ipairs(guis) do
		if isTrulyVisible(obj, playerGui) then
			-- Interactive controls
			if obj:IsA("GuiButton") or obj:IsA("TextBox") or (obj:IsA("ScrollingFrame") and obj.Active) then
				return true
			end
			-- Quin Manager Menu window (AnimationLabUI)
			if obj:FindFirstAncestor("AnimationLabUI") or obj.Name == "AnimationLabUI" then
				return true
			end
			-- Spectator HUD (QuinDebugGui)
			if obj:FindFirstAncestor("QuinDebugGui") or obj.Name == "QuinDebugGui" then
				return true
			end
			-- Explicitly active GUI frames
			if obj.Active then
				return true
			end
		end
	end
	return false
end

-- Keep cursor and look state synced when window focus changes or Studio resets mouse
UserInputService.WindowFocusReleased:Connect(function()
	unlockMouse()
end)

UserInputService:GetPropertyChangedSignal("MouseBehavior"):Connect(function()
	if UserInputService.MouseBehavior == Enum.MouseBehavior.Default then
		if not isLeftMouseDown and not isRightMouseDown then
			isToggleLocked = false
		end
	end
end)

-- Check active spectated Quin
local function getActiveSpectatedQuin()
	local specQuin = shared.SpectatedQuin or _G.SpectatedQuin
	if not specQuin or not specQuin.Parent then
		local specName = workspace:GetAttribute("SpectatedQuin")
		if specName and specName ~= "" then
			local qServer = workspace:FindFirstChild("QuinServer")
			specQuin = qServer and qServer:FindFirstChild(specName)
		end
	end
	if specQuin and specQuin.Parent and specQuin.Parent.Name == "QuinServer" and specQuin.Name ~= "QuinTest" and specQuin.Name ~= "QuinTypeA" then
		local hum = specQuin:FindFirstChildOfClass("Humanoid")
		local hrp = specQuin:FindFirstChild("HumanoidRootPart")
		if hum and hum.Health > 0 and hrp then
			return hrp, specQuin
		end
	end
	return nil, nil
end

-- === INPUT HANDLING ===
UserInputService.InputBegan:Connect(function(input, gp)
	if UserInputService:GetFocusedTextBox() then return end

	-- Mouse Controls: Left Click or Right Click to look around
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		if gp or isClickOnGui(input.Position) then
			-- Clicked on GUI (e.g. Spectator HUD button/card)
			return
		end
		isLeftMouseDown = true
		updateMouseBehavior()

	elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
		if gp or isClickOnGui(input.Position) then return end
		isRightMouseDown = true
		updateMouseBehavior()

	-- Toggle hands-free look lock with L
	elseif input.KeyCode == Enum.KeyCode.L then
		if isToggleLocked then
			unlockMouse()
		else
			lockMouse()
		end

	-- Mouse Unlock keys
	elseif input.KeyCode == Enum.KeyCode.Tab or input.KeyCode == Enum.KeyCode.Escape then
		unlockMouse()

	elseif input.KeyCode == Enum.KeyCode.R then
		-- Return to Freefly overview
		cameraMode = "FREEFLY"
		shared.SpectatedQuin = nil
		_G.SpectatedQuin = nil
		workspace:SetAttribute("SpectatedQuin", "")
		cameraPos = Vector3.new(0, 140, 160)
		pitch = -38.0
		yaw = 0
		print("[SmoothCamera] Returned to default Freefly Spectator overview.")

	elseif input.KeyCode == Enum.KeyCode.F then
		-- Toggle Freefly mode
		if cameraMode == "QUIN_SPECTATE" then
			cameraMode = "FREEFLY"
			cameraPos = Camera.CFrame.Position
			shared.SpectatedQuin = nil
			workspace:SetAttribute("SpectatedQuin", "")
			print("[SmoothCamera] Released Quin focus to Freefly.")
		else
			local hrp = getActiveSpectatedQuin()
			if hrp then
				cameraMode = "QUIN_SPECTATE"
				print("[SmoothCamera] Focused on spectated Quin.")
			end
		end
	end
end)

UserInputService.InputEnded:Connect(function(input, gp)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		isLeftMouseDown = false
		updateMouseBehavior()
	elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
		isRightMouseDown = false
		updateMouseBehavior()
	end
end)

-- Scroll wheel
UserInputService.InputChanged:Connect(function(input, gp)
	if gp then return end
	if input.UserInputType == Enum.UserInputType.MouseWheel then
		if cameraMode == "QUIN_SPECTATE" then
			targetDistance = math.clamp(targetDistance - input.Position.Z * zoomSpeed, minZoom, maxZoom)
		else
			-- In freefly, wheel nudges camera forward/backward along view
			local forward = Camera.CFrame.LookVector
			cameraPos = cameraPos + forward * (input.Position.Z * 50)
			cameraPos = Vector3.new(cameraPos.X, math.clamp(cameraPos.Y, minAltitude, maxAltitude), cameraPos.Z)
		end
	end
end)

-- === RENDER STEP LOOP ===
RunService:BindToRenderStep("SpectatorFreeflyCamera", Enum.RenderPriority.Camera.Value + 1, function(dt)
	local isOverride = (workspace:GetAttribute("CameraOverrideActive") == true) or (shared.CameraOverrideCFrame ~= nil)
	if isOverride then
		Camera.CameraType = Enum.CameraType.Scriptable
		if shared.CameraOverrideCFrame then
			Camera.CFrame = shared.CameraOverrideCFrame
		else
			local posX = workspace:GetAttribute("CamPosX") or 0
			local posY = workspace:GetAttribute("CamPosY") or 8.0
			local posZ = workspace:GetAttribute("CamPosZ") or -20.0
			local lookX = workspace:GetAttribute("CamLookX") or 0
			local lookY = workspace:GetAttribute("CamLookY") or 6.0
			local lookZ = workspace:GetAttribute("CamLookZ") or -38.0
			Camera.CFrame = CFrame.lookAt(Vector3.new(posX, posY, posZ), Vector3.new(lookX, lookY, lookZ))
		end
		return
	end

	Camera.CameraType = Enum.CameraType.Scriptable

	-- Check if a Quin is selected from the HUD
	local targetHRP, quinModel = getActiveSpectatedQuin()
	if targetHRP and cameraMode ~= "QUIN_SPECTATE" then
		cameraMode = "QUIN_SPECTATE"
		shared.SpectatorState.Mode = cameraMode
	elseif not targetHRP and cameraMode == "QUIN_SPECTATE" then
		cameraMode = "FREEFLY"
		shared.SpectatorState.Mode = cameraMode
		cameraPos = Camera.CFrame.Position
	end

	-- Mouse rotation
	local isHoldingLook = isLeftMouseDown or isRightMouseDown or isToggleLocked
	if isHoldingLook then
		local delta = UserInputService:GetMouseDelta()
		yaw = (yaw - delta.X * flySensitivity) % 360
		pitch = math.clamp(pitch - delta.Y * flySensitivity, -85, 85)
	end

	if cameraMode == "FREEFLY" then
		-- === FREEFLY NAVIGATION ===
		local speed = baseFlySpeed
		if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) or UserInputService:IsKeyDown(Enum.KeyCode.RightShift) then
			speed = speed * sprintMultiplier
		end

		local rotCF = CFrame.Angles(0, math.rad(yaw), 0) * CFrame.Angles(math.rad(pitch), 0, 0)
		local moveDir = Vector3.zero

		-- Keyboard Inputs
		if UserInputService:IsKeyDown(Enum.KeyCode.W) then
			moveDir += rotCF.LookVector
		end
		if UserInputService:IsKeyDown(Enum.KeyCode.S) then
			moveDir -= rotCF.LookVector
		end
		if UserInputService:IsKeyDown(Enum.KeyCode.A) then
			moveDir -= rotCF.RightVector
		end
		if UserInputService:IsKeyDown(Enum.KeyCode.D) then
			moveDir += rotCF.RightVector
		end
		if UserInputService:IsKeyDown(Enum.KeyCode.Space) or UserInputService:IsKeyDown(Enum.KeyCode.E) then
			moveDir += Vector3.new(0, 1.2, 0)
		end
		if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) or UserInputService:IsKeyDown(Enum.KeyCode.C) or UserInputService:IsKeyDown(Enum.KeyCode.Q) then
			moveDir -= Vector3.new(0, 1.2, 0)
		end

		if moveDir.Magnitude > 0.001 then
			cameraPos += moveDir.Unit * (speed * dt)
		end

		-- Altitude Clamp
		cameraPos = Vector3.new(cameraPos.X, math.clamp(cameraPos.Y, minAltitude, maxAltitude), cameraPos.Z)

		Camera.CFrame = CFrame.new(cameraPos) * rotCF

	else
		-- === QUIN SPECTATE (ORBIT) ===
		local rotAlpha = 1 - math.exp(-orbitSmoothness * dt)
		local zoomAlpha = 1 - math.exp(-10 * dt)
		local posAlpha = 1 - math.exp(-posSmoothness * dt)

		smoothYaw += (yaw - smoothYaw) * rotAlpha
		smoothPitch += (pitch - smoothPitch) * rotAlpha
		currentDistance += (targetDistance - currentDistance) * zoomAlpha

		local rawTargetPos = targetHRP.Position + Vector3.new(0, 2.5, 0)
		if not smoothedTargetPos or (rawTargetPos - smoothedTargetPos).Magnitude > 60 then
			smoothedTargetPos = rawTargetPos
		else
			smoothedTargetPos = smoothedTargetPos:Lerp(rawTargetPos, posAlpha)
		end

		local camRotation = CFrame.Angles(0, math.rad(smoothYaw), 0) * CFrame.Angles(math.rad(smoothPitch), 0, 0)
		local camPos = smoothedTargetPos - camRotation.LookVector * currentDistance

		if camPos.Y < 2.0 then
			camPos = Vector3.new(camPos.X, 2.0, camPos.Z)
		end

		Camera.CFrame = CFrame.lookAt(camPos, smoothedTargetPos)
		cameraPos = camPos -- keep synced if switched to freefly
	end
end)
