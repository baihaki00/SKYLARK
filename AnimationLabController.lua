--// QuinManagerController.client.lua
-- Unified Quin Manager Menu: Combat Orchestrator, Animation Powerhouse & Test Suite
-- Single Source of Truth: ReplicatedStorage.QuinCore.AnimationConfig

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera
local pGui = player:WaitForChild("PlayerGui")

local QuinCore = ReplicatedStorage:WaitForChild("QuinCore")
local AnimationConfig = require(QuinCore:WaitForChild("AnimationConfig"))
local CombatConfig = require(QuinCore:WaitForChild("CombatConfig"))
local Events = QuinCore:WaitForChild("Events")
local labEvent = Events:WaitForChild("AnimationLabEvent")

-- Target references
local testerName = "QuinA_Tester"
local partnerName = "QuinB_SparringPartner"

-- Forward declarations for Powerhouse Rig controls
local rigStatusBadge = nil
local respawnRigsBtn = nil
local checkAndSpawnTesters = nil
local updateRigStatusBadge = nil

-- UI State
local activeMainTab = "Powerhouse" -- "Powerhouse", "GameModes", "TestModes"
local currentCategory = "All"
local currentEntryPath = "Attacks.Punches.Punch1"
local currentEntryData = AnimationConfig.get(currentEntryPath) or {}
local comboChain = {
	{ path = "Attacks.Punches.Punch1", name = "Lead Jab" },
	{ path = "Attacks.Punches.CrossRight", name = "Cross Right" },
	{ path = "Attacks.Kicks.PowerKick", name = "Power Kick" },
}
local slomoSpeed = 1.0
local isFreecamActive = true -- Default to Blender Freecam on startup
local isNormalCombatActive = false
local isInfiniteStrafeActive = false

-- Colors
local C_BG = Color3.fromRGB(18, 21, 28)
local C_PANEL = Color3.fromRGB(25, 29, 40)
local C_CARD = Color3.fromRGB(32, 38, 52)
local C_ACCENT = Color3.fromRGB(0, 195, 255)
local C_TEXT = Color3.fromRGB(240, 245, 252)
local C_TEXT_MUTED = Color3.fromRGB(145, 155, 172)
local C_SUCCESS = Color3.fromRGB(45, 215, 120)
local C_DANGER = Color3.fromRGB(240, 75, 75)
local C_BORDER = Color3.fromRGB(48, 56, 76)
local C_ACTIVE_TAB = Color3.fromRGB(0, 140, 210)

local screenGui = script.Parent
if not screenGui or not screenGui:IsA("ScreenGui") then
	screenGui = pGui:FindFirstChild("AnimationLabUI")
	if not screenGui then
		screenGui = Instance.new("ScreenGui")
		screenGui.Name = "AnimationLabUI"
		screenGui.ResetOnSpawn = false
		screenGui.DisplayOrder = 100
		screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
		screenGui.Parent = pGui
	end
end

-- Clear old UI elements inside screenGui, but PRESERVE this script!
for _, child in ipairs(screenGui:GetChildren()) do
	if child ~= script and not child:IsA("LocalScript") and not child:IsA("Script") then
		child:Destroy()
	end
end

local function applyCorner(inst, r)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r or 6)
	c.Parent = inst
	return c
end

local function applyStroke(inst, color, thick)
	local s = Instance.new("UIStroke")
	s.Color = color or C_BORDER
	s.Thickness = thick or 1
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = inst
	return s
end

--------------------------------------------------------------------------------
-- 1. BLENDER-STYLE FREECAM SYSTEM (CANONICAL CAS CONTROLLER & SEAMLESS FLYING)
--------------------------------------------------------------------------------
local startFreecam, stopFreecam, toggleFreelookLock
do
	local CAS = game:GetService("ContextActionService")
local isFreecamBound = false
local camPosition = Vector3.new(-18, 12, 12.5)
local camPitch = -14
local camYaw = -90
local baseFlySpeed = 300 -- Boosted ~5x (was 66) for fast agile arena freefly navigation
local isRightMouseDown = false
local isFreelookLocked = false

local keyboard = {
	W = 0, A = 0, S = 0, D = 0, Space = 0, LeftControl = 0, C = 0, LeftShift = 0, RightShift = 0
}

local function setControlsEnabled(enabled)
	local playerScripts = player:WaitForChild("PlayerScripts")
	local playerModule = playerScripts:FindFirstChild("PlayerModule")
	if playerModule then
		pcall(function()
			local Controls = require(playerModule):GetControls()
			if Controls then
				if enabled then Controls:Enable() else Controls:Disable() end
			end
		end)
	end
	local sc = playerScripts:FindFirstChild("SmoothCamera")
	if sc then
		sc.Disabled = not enabled
	end
	local char = player.Character
	if char then
		for _, part in ipairs(char:GetDescendants()) do
			if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
				part.LocalTransparencyModifier = enabled and 0 or 1
			elseif part:IsA("Decal") then
				part.Transparency = enabled and 0 or 1
			end
		end
		local hrp = char:FindFirstChild("HumanoidRootPart")
		if hrp then
			hrp.Anchored = not enabled
		end
		local hum = char:FindFirstChildOfClass("Humanoid")
		if hum then
			hum.WalkSpeed = enabled and 16 or 0
			hum.JumpPower = enabled and 50 or 0
		end
	end
end

local function isKeyDown(key)
	if UserInputService:GetFocusedTextBox() then return 0 end
	if keyboard[key.Name] == 1 then return 1 end
	if UserInputService:IsKeyDown(key) then return 1 end
	return 0
end

local function updateFlycam(dt)
	if not isFreecamActive then return end

	-- Restore mouse behavior whenever RMB is released and freelook is not toggled
	if not isRightMouseDown and not isFreelookLocked then
		if UserInputService.MouseBehavior ~= Enum.MouseBehavior.Default then
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		end
		if not UserInputService.MouseIconEnabled then
			UserInputService.MouseIconEnabled = true
		end
	end

	-- Speed multiplier (Shift = Sprint)
	local isSprint = (isKeyDown(Enum.KeyCode.LeftShift) == 1 or isKeyDown(Enum.KeyCode.RightShift) == 1)
	local speed = isSprint and (baseFlySpeed * 3.5) or baseFlySpeed
	
	-- Boost speed if in freelook mode
	if isFreelookLocked then
		speed = speed * 1.8
	end

	-- Local velocity in camera space (-Z is Forward, +X is Right, +Y is Up: Space = Up, LeftControl / C = Down)
	local upVal = isKeyDown(Enum.KeyCode.Space)
	local downVal = math.max(isKeyDown(Enum.KeyCode.LeftControl), isKeyDown(Enum.KeyCode.C))
	local localVel = Vector3.new(
		isKeyDown(Enum.KeyCode.D) - isKeyDown(Enum.KeyCode.A),
		upVal - downVal,
		isKeyDown(Enum.KeyCode.S) - isKeyDown(Enum.KeyCode.W)
	)

	local camRotCF = CFrame.fromOrientation(math.rad(camPitch), math.rad(camYaw), 0)

	if localVel.Magnitude > 0 then
		local worldDelta = camRotCF:VectorToWorldSpace(localVel.Unit * speed * dt)
		camPosition = camPosition + worldDelta
	end

	-- Recompute CFrame with STRICT zero roll
	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = CFrame.new(camPosition) * camRotCF
	camera.Focus = camera.CFrame
end

local function FreecamKeypress(action, state, input)
	if UserInputService:GetFocusedTextBox() then
		return Enum.ContextActionResult.Pass
	end
	local name = input.KeyCode.Name
	if keyboard[name] ~= nil then
		keyboard[name] = (state == Enum.UserInputState.Begin) and 1 or 0
	end
	return Enum.ContextActionResult.Sink
end

startFreecam = function()
	isFreecamActive = true
	workspace:SetAttribute("QuinFreecamActive", true)
	camera.CameraType = Enum.CameraType.Scriptable
	setControlsEnabled(false)

	-- Bind CAS input interception without Q/E so Q/E are free for Quin tracking!
	CAS:BindActionAtPriority("QuinFreecamKB", FreecamKeypress, false, 2000,
		Enum.KeyCode.W, Enum.KeyCode.A, Enum.KeyCode.S, Enum.KeyCode.D,
		Enum.KeyCode.Space, Enum.KeyCode.LeftControl, Enum.KeyCode.C,
		Enum.KeyCode.LeftShift, Enum.KeyCode.RightShift
	)

	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	UserInputService.MouseIconEnabled = true

	if not isFreecamBound then
		isFreecamBound = true
		RunService:BindToRenderStep("QuinBlenderFlycam", Enum.RenderPriority.Camera.Value, updateFlycam)
	end
end

stopFreecam = function()
	isFreecamActive = false
	workspace:SetAttribute("QuinFreecamActive", false)
	CAS:UnbindAction("QuinFreecamKB")
	for k in pairs(keyboard) do keyboard[k] = 0 end

	if isFreecamBound then
		RunService:UnbindFromRenderStep("QuinBlenderFlycam")
		isFreecamBound = false
	end
	camera.CameraType = Enum.CameraType.Custom
	setControlsEnabled(true)
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	UserInputService.MouseIconEnabled = true
end

_G.StartFreecam = startFreecam
_G.StopFreecam = stopFreecam
_G.IsFreecamActive = function() return isFreecamActive end

shared.StartFreecam = startFreecam
shared.StopFreecam = stopFreecam
shared.IsFreecamActive = function() return isFreecamActive end

toggleFreelookLock = function()
	if not UserInputService:GetFocusedTextBox() then
		isFreelookLocked = not isFreelookLocked
		if isFreelookLocked then
			UserInputService.MouseBehavior = Enum.MouseBehavior.LockCurrentPosition
			UserInputService.MouseIconEnabled = false
		else
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
			UserInputService.MouseIconEnabled = true
		end
	end
end

-- Input Listeners for Freecam
UserInputService.InputBegan:Connect(function(input, gpe)
	if gpe or UserInputService:GetFocusedTextBox() then return end
	if input.KeyCode == Enum.KeyCode.F then
		if _G.ToggleCamMode then
			_G.ToggleCamMode()
		end
		return
	end
	if not isFreecamActive then return end
	if input.UserInputType == Enum.UserInputType.MouseButton2 then
		isRightMouseDown = true
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCurrentPosition
		UserInputService.MouseIconEnabled = false
	elseif input.UserInputType == Enum.UserInputType.MouseButton3 then
		-- Middle Mouse: Toggle persistent Blender Fly freelook navigation
		toggleFreelookLock()
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton2 then
		isRightMouseDown = false
		if not isFreelookLocked then
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
			UserInputService.MouseIconEnabled = true
		end
	end
end)

UserInputService.InputChanged:Connect(function(input, gpe)
	if not isFreecamActive then return end
	if (isRightMouseDown or isFreelookLocked) and input.UserInputType == Enum.UserInputType.MouseMovement then
		local sens = 0.22
		camYaw = (camYaw - input.Delta.X * sens) % 360
		camPitch = math.clamp(camPitch - input.Delta.Y * sens, -85, 85)
	elseif input.UserInputType == Enum.UserInputType.MouseWheel then
		-- Scroll wheel moves camera forward / backward along look direction
		local camRotCF = CFrame.fromOrientation(math.rad(camPitch), math.rad(camYaw), 0)
		camPosition = camPosition + camRotCF.LookVector * (input.Position.Z * 45.0)
	end
end)

-- Auto-transition: when a Quin is selected for spectating, yield Freecam so SmoothCamera tracks smoothly
RunService.Heartbeat:Connect(function()
	if isFreecamActive and (shared.SpectatedQuin or _G.SpectatedQuin) then
		stopFreecam()
		if _G.UpdateCamBtnText then
			_G.UpdateCamBtnText("Cam: Spectating [F]")
		end
	end
end)

-- Character respawn watcher: ensures avatar stays disabled while freecam is active
player.CharacterAdded:Connect(function(char)
	if isFreecamActive then
		task.wait(0.1)
		setControlsEnabled(false)
	end
end)

-- Default to Character / SmoothCamera mode on game load
	task.defer(function()
		stopFreecam()
	end)
end

--------------------------------------------------------------------------------
-- 2. MAIN WINDOW CONTAINER
--------------------------------------------------------------------------------
local mainFrame = Instance.new("Frame")
mainFrame.Name = "MainFrame"
mainFrame.Size = UDim2.new(0, 960, 0, 620)
mainFrame.Position = UDim2.new(0.5, -480, 0.5, -310)
mainFrame.BackgroundColor3 = C_BG
mainFrame.ClipsDescendants = true
mainFrame.Active = true
mainFrame.Visible = false
mainFrame.Parent = screenGui
applyCorner(mainFrame, 10)
applyStroke(mainFrame, Color3.fromRGB(60, 72, 95), 1.5)

-- Floating Toggle Pill (Docked bottom-right in stack)
local togglePill = Instance.new("TextButton")
togglePill.Size = UDim2.new(0, 180, 0, 36)
togglePill.AnchorPoint = Vector2.new(1, 1)
togglePill.Position = UDim2.new(1, -20, 1, -69)
togglePill.BackgroundColor3 = Color3.fromRGB(18, 22, 30)
togglePill.BackgroundTransparency = 0.15
togglePill.TextColor3 = Color3.fromRGB(240, 245, 255)
togglePill.Font = Enum.Font.GothamBold
togglePill.TextSize = 12
togglePill.Text = "âš”ï¸ Quin Manager [M]"
togglePill.Visible = true
togglePill.Parent = screenGui
applyCorner(togglePill, 18)
local pillStroke = applyStroke(togglePill, Color3.fromRGB(0, 200, 255), 1.5)
pillStroke.Transparency = 0.4

-- Subtle hover animation
togglePill.MouseEnter:Connect(function()
	TweenService:Create(togglePill, TweenInfo.new(0.2), { BackgroundTransparency = 0.05 }):Play()
	TweenService:Create(pillStroke, TweenInfo.new(0.2), { Transparency = 0.1 }):Play()
end)

togglePill.MouseLeave:Connect(function()
	TweenService:Create(togglePill, TweenInfo.new(0.2), { BackgroundTransparency = 0.15 }):Play()
	TweenService:Create(pillStroke, TweenInfo.new(0.2), { Transparency = 0.4 }):Play()
end)

updateRigStatusBadge = function()
	if not rigStatusBadge or not respawnRigsBtn then return false end
	local quinServer = Workspace:FindFirstChild("QuinServer")
	local tester = quinServer and quinServer:FindFirstChild(testerName)
	if tester and tester.Parent then
		local hum = tester:FindFirstChildOfClass("Humanoid")
		if hum and hum.Health > 0 then
			rigStatusBadge.Text = "â— Rig: Ready"
			rigStatusBadge.TextColor3 = C_SUCCESS
			respawnRigsBtn.Text = "ðŸ”„ Reset Rig"
			respawnRigsBtn.BackgroundColor3 = Color3.fromRGB(35, 75, 110)
			return true
		end
	end
	rigStatusBadge.Text = "â— Rig: Missing"
	rigStatusBadge.TextColor3 = Color3.fromRGB(255, 170, 40)
	respawnRigsBtn.Text = "âš¡ Spawn Rig"
	respawnRigsBtn.BackgroundColor3 = Color3.fromRGB(180, 100, 30)
	return false
end

checkAndSpawnTesters = function(force)
	local isReady = updateRigStatusBadge and updateRigStatusBadge() or false
	if force or not isReady then
		if respawnRigsBtn then
			respawnRigsBtn.Text = "â³ Spawning..."
			respawnRigsBtn.BackgroundColor3 = Color3.fromRGB(50, 60, 80)
		end
		labEvent:FireServer("EnsureTesterRigs", { force = force == true })
	end
end

local function toggleMenuVisibility()
	mainFrame.Visible = not mainFrame.Visible
	togglePill.Visible = not mainFrame.Visible
	if mainFrame.Visible and activeMainTab == "Powerhouse" then
		checkAndSpawnTesters(false)
		updateRigStatusBadge()
	end
end

togglePill.MouseButton1Click:Connect(toggleMenuVisibility)

UserInputService.InputBegan:Connect(function(input, gpe)
	if input.KeyCode == Enum.KeyCode.M then
		if not UserInputService:GetFocusedTextBox() then
			toggleMenuVisibility()
		end
	end
end)

-- Title Bar (Drag Handle)
local titleBar = Instance.new("Frame")
titleBar.Name = "TitleBar"
titleBar.Size = UDim2.new(1, 0, 0, 44)
titleBar.BackgroundColor3 = C_PANEL
titleBar.Active = true
titleBar.Parent = mainFrame
applyCorner(titleBar, 10)

local titleLabel = Instance.new("TextLabel")
titleLabel.Text = " âš”ï¸ QUIN MANAGER"
titleLabel.Size = UDim2.new(0, 150, 1, 0)
titleLabel.BackgroundTransparency = 1
titleLabel.TextColor3 = C_TEXT
titleLabel.Font = Enum.Font.GothamBold
titleLabel.TextSize = 12
titleLabel.TextXAlignment = Enum.TextXAlignment.Left
titleLabel.Parent = titleBar

-- Freecam Toggle Button on Title Bar
local camToggleBtn = Instance.new("TextButton")
camToggleBtn.Size = UDim2.new(0, 115, 0, 28)
camToggleBtn.Position = UDim2.new(0, 155, 0, 8)
camToggleBtn.BackgroundColor3 = Color3.fromRGB(45, 52, 70)
camToggleBtn.TextColor3 = C_TEXT
camToggleBtn.Font = Enum.Font.GothamBold
camToggleBtn.TextSize = 11
camToggleBtn.Text = "Cam: Char [F]"
camToggleBtn.Parent = titleBar
applyCorner(camToggleBtn, 6)

local function updateCamBtnDisplay(text)
	camToggleBtn.Text = text
	if isFreecamActive then
		camToggleBtn.BackgroundColor3 = Color3.fromRGB(35, 75, 110)
		camToggleBtn.TextColor3 = C_ACCENT
	else
		camToggleBtn.BackgroundColor3 = Color3.fromRGB(45, 52, 70)
		camToggleBtn.TextColor3 = C_TEXT
	end
end

local function toggleCamMode()
	if isFreecamActive then
		stopFreecam()
		updateCamBtnDisplay("Cam: Char [F]")
	else
		startFreecam()
		updateCamBtnDisplay("Cam: Fly [F]")
	end
end

_G.ToggleCamMode = toggleCamMode
_G.UpdateCamBtnText = updateCamBtnDisplay

camToggleBtn.MouseButton1Click:Connect(toggleCamMode)

-- Normal Combat Mode Toggle Button on Title Bar
local combatModeBtn = Instance.new("TextButton")
combatModeBtn.Size = UDim2.new(0, 115, 0, 28)
combatModeBtn.Position = UDim2.new(0, 276, 0, 8)
combatModeBtn.BackgroundColor3 = Color3.fromRGB(48, 56, 74)
combatModeBtn.TextColor3 = C_TEXT
combatModeBtn.Font = Enum.Font.GothamBold
combatModeBtn.TextSize = 11
combatModeBtn.Text = "Combat: OFF"
combatModeBtn.Parent = titleBar
applyCorner(combatModeBtn, 6)

combatModeBtn.MouseButton1Click:Connect(function()
	isNormalCombatActive = not isNormalCombatActive
	combatModeBtn.Text = isNormalCombatActive and "Combat: ACTIVE" or "Combat: OFF"
	combatModeBtn.BackgroundColor3 = isNormalCombatActive and Color3.fromRGB(0, 180, 120) or Color3.fromRGB(48, 56, 74)
	combatModeBtn.TextColor3 = isNormalCombatActive and Color3.new(0, 0, 0) or C_TEXT
	labEvent:FireServer("ToggleCombatMode", { enabled = isNormalCombatActive })
end)

-- ============================================================
-- EMBEDDED BATTLE SPEED CONTROLLER (Inside Quin Manager Menu)
-- ============================================================
do
	local speedEvent = ReplicatedStorage:FindFirstChild("GameSpeedEvent")
if not speedEvent then
	speedEvent = Instance.new("RemoteEvent")
	speedEvent.Name = "GameSpeedEvent"
	speedEvent.Parent = ReplicatedStorage
end

local speedContainer = Instance.new("Frame")
speedContainer.Name = "SpeedControllerContainer"
speedContainer.Size = UDim2.new(0, 420, 0, 28)
speedContainer.Position = UDim2.new(0, 398, 0, 8)
speedContainer.BackgroundColor3 = Color3.fromRGB(15, 20, 28)
speedContainer.BorderSizePixel = 0
speedContainer.Parent = titleBar
applyCorner(speedContainer, 6)
applyStroke(speedContainer, Color3.fromRGB(45, 60, 85), 1)

local speedBtnLayout = Instance.new("UIListLayout")
speedBtnLayout.FillDirection = Enum.FillDirection.Horizontal
speedBtnLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
speedBtnLayout.VerticalAlignment = Enum.VerticalAlignment.Center
speedBtnLayout.SortOrder = Enum.SortOrder.LayoutOrder
speedBtnLayout.Padding = UDim.new(0, 4)
speedBtnLayout.Parent = speedContainer

local speedLabel = Instance.new("TextLabel")
speedLabel.Size = UDim2.new(0, 60, 1, 0)
speedLabel.LayoutOrder = 1
speedLabel.BackgroundTransparency = 1
speedLabel.Font = Enum.Font.GothamBold
speedLabel.TextSize = 10
speedLabel.TextColor3 = Color3.fromRGB(255, 215, 0)
speedLabel.TextXAlignment = Enum.TextXAlignment.Center
speedLabel.Text = "âš¡ Speed:"
speedLabel.Parent = speedContainer

local SPEED_OPTIONS = { 1, 2, 4, 5, 6, 8, 10 }
local DEFAULT_SPEED = 1.0
local speedButtons = {}

local function updateSpeedUI(activeSpeed)
	for speedVal, btn in pairs(speedButtons) do
		local isActive = (math.abs(speedVal - activeSpeed) < 0.05)
		if isActive then
			btn.BackgroundColor3 = Color3.fromRGB(0, 200, 255)
			btn.TextColor3 = Color3.fromRGB(10, 15, 25)
			btn.Font = Enum.Font.GothamBlack
		else
			btn.BackgroundColor3 = Color3.fromRGB(28, 35, 48)
			btn.TextColor3 = Color3.fromRGB(200, 215, 235)
			btn.Font = Enum.Font.GothamBold
		end
	end
end

local function setBattleSpeed(speedVal)
	local clamped = math.clamp(speedVal, 1.0, 10.0)
	Workspace:SetAttribute("GameSpeedMultiplier", clamped)
	speedEvent:FireServer(clamped)
	updateSpeedUI(clamped)
	print(string.format("[QuinManager] Simulation speed set to %.1fx", clamped))
end

for idx, speedVal in ipairs(SPEED_OPTIONS) do
	local sBtn = Instance.new("TextButton")
	sBtn.Name = "SpeedBtn_" .. tostring(speedVal) .. "x"
	sBtn.LayoutOrder = idx + 1
	sBtn.Size = UDim2.new(0, 44, 0, 22)
	sBtn.BackgroundColor3 = (speedVal == 1) and Color3.fromRGB(0, 200, 255) or Color3.fromRGB(28, 35, 48)
	sBtn.TextColor3 = (speedVal == 1) and Color3.fromRGB(10, 15, 25) or Color3.fromRGB(200, 215, 235)
	sBtn.Font = (speedVal == 1) and Enum.Font.GothamBlack or Enum.Font.GothamBold
	sBtn.TextSize = 10
	sBtn.Text = tostring(speedVal) .. "x"
	sBtn.Parent = speedContainer
	applyCorner(sBtn, 4)

	speedButtons[speedVal] = sBtn

	sBtn.MouseButton1Click:Connect(function()
		setBattleSpeed(speedVal)
	end)
end

Workspace:GetAttributeChangedSignal("GameSpeedMultiplier"):Connect(function()
	local cur = Workspace:GetAttribute("GameSpeedMultiplier") or DEFAULT_SPEED
	updateSpeedUI(cur)
	end)
end

-- Minimize Button
local minBtn = Instance.new("TextButton")
minBtn.Text = "-"
minBtn.Size = UDim2.new(0, 28, 0, 28)
minBtn.Position = UDim2.new(1, -34, 0, 8)
minBtn.BackgroundColor3 = Color3.fromRGB(45, 52, 70)
minBtn.TextColor3 = C_TEXT
minBtn.Font = Enum.Font.GothamBold
minBtn.TextSize = 16
minBtn.Parent = titleBar
applyCorner(minBtn, 6)

minBtn.MouseButton1Click:Connect(function()
	mainFrame.Visible = false
	togglePill.Visible = true
end)

-- Window Dragging Logic
do
	local isDragging = false
local dragStart = Vector3.zero
local startPos = UDim2.new()

local function handleDragStart(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		isDragging = true
		dragStart = input.Position
		startPos = mainFrame.Position
	end
end

titleBar.InputBegan:Connect(handleDragStart)
titleLabel.InputBegan:Connect(handleDragStart)

UserInputService.InputChanged:Connect(function(input)
	if isDragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
		local delta = input.Position - dragStart
		mainFrame.Position = UDim2.new(
			startPos.X.Scale,
			startPos.X.Offset + delta.X,
			startPos.Y.Scale,
			startPos.Y.Offset + delta.Y
		)
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		isDragging = false
	end
	end)
end

--------------------------------------------------------------------------------
-- 3. TOP NAVIGATION BAR (GAME MODES | TEST MODES | ANIMATION POWERHOUSE)
--------------------------------------------------------------------------------
local mainNav = Instance.new("Frame")
mainNav.Size = UDim2.new(1, -20, 0, 34)
mainNav.Position = UDim2.new(0, 10, 0, 48)
mainNav.BackgroundTransparency = 1
mainNav.Parent = mainFrame

local mainNavLayout = Instance.new("UIListLayout")
mainNavLayout.FillDirection = Enum.FillDirection.Horizontal
mainNavLayout.Padding = UDim.new(0, 10)
mainNavLayout.Parent = mainNav

local mainTabs = {
	{ id = "Powerhouse", label = "âš¡ Animation Powerhouse" },
	{ id = "GameModes", label = "ðŸŽ® Game Modes" },
	{ id = "TestModes", label = "ðŸ§ª Test Modes" },
}

-- Views
local powerhouseView = Instance.new("Frame")
powerhouseView.Name = "PowerhouseView"
powerhouseView.Size = UDim2.new(1, 0, 1, -86)
powerhouseView.Position = UDim2.new(0, 0, 0, 86)
powerhouseView.BackgroundTransparency = 1
powerhouseView.Parent = mainFrame

local gameModesView = Instance.new("Frame")
gameModesView.Name = "GameModesView"
gameModesView.Size = UDim2.new(1, 0, 1, -86)
gameModesView.Position = UDim2.new(0, 0, 0, 86)
gameModesView.BackgroundTransparency = 1
gameModesView.Visible = false
gameModesView.Parent = mainFrame

local testModesView = Instance.new("Frame")
testModesView.Name = "TestModesView"
testModesView.Size = UDim2.new(1, 0, 1, -86)
testModesView.Position = UDim2.new(0, 0, 0, 86)
testModesView.BackgroundTransparency = 1
testModesView.Visible = false
testModesView.Parent = mainFrame

local function switchMainTab(tabId)
	activeMainTab = tabId
	powerhouseView.Visible = (tabId == "Powerhouse")
	gameModesView.Visible = (tabId == "GameModes")
	testModesView.Visible = (tabId == "TestModes")

	if tabId == "Powerhouse" then
		if checkAndSpawnTesters then checkAndSpawnTesters(false) end
		if updateRigStatusBadge then updateRigStatusBadge() end
	end

	for _, child in ipairs(mainNav:GetChildren()) do
		if child:IsA("TextButton") then
			local isActive = (child:GetAttribute("TabId") == tabId)
			child.BackgroundColor3 = isActive and C_ACTIVE_TAB or Color3.fromRGB(30, 36, 48)
			child.TextColor3 = isActive and Color3.new(1, 1, 1) or C_TEXT_MUTED
		end
	end
end
_G.SwitchMainTab = switchMainTab
shared.SwitchMainTab = switchMainTab

mainFrame:GetAttributeChangedSignal("ActiveTab"):Connect(function()
	local tab = mainFrame:GetAttribute("ActiveTab")
	if tab then switchMainTab(tab) end
end)

for _, tab in ipairs(mainTabs) do
	local b = Instance.new("TextButton")
	b.Size = UDim2.new(0, 190, 1, 0)
	b.BackgroundColor3 = (tab.id == activeMainTab) and C_ACTIVE_TAB or Color3.fromRGB(30, 36, 48)
	b.TextColor3 = (tab.id == activeMainTab) and Color3.new(1, 1, 1) or C_TEXT_MUTED
	b.Font = Enum.Font.GothamBold
	b.TextSize = 12
	b.Text = tab.label
	b:SetAttribute("TabId", tab.id)
	b.Parent = mainNav
	applyCorner(b, 6)
	applyStroke(b, C_BORDER, 1)

	b.MouseButton1Click:Connect(function()
		switchMainTab(tab.id)
	end)
end

--------------------------------------------------------------------------------
-- 4. POWERHOUSE VIEW: SUB-NAVIGATION & 4 DEDICATED LABORATORIES
--------------------------------------------------------------------------------
local activePowerhouseSubTab = "AnimStudio"

-- Sub-Navigation Bar
local subNavFrame = Instance.new("Frame")
subNavFrame.Size = UDim2.new(1, -260, 0, 30)
subNavFrame.Position = UDim2.new(0, 10, 0, 4)
subNavFrame.BackgroundTransparency = 1
subNavFrame.Parent = powerhouseView

local subNavLayout = Instance.new("UIListLayout")
subNavLayout.FillDirection = Enum.FillDirection.Horizontal
subNavLayout.Padding = UDim.new(0, 6)
subNavLayout.Parent = subNavFrame

local subTabs = {
	{ id = "AnimStudio", label = "ðŸŽ¬ Animation Studio" },
	{ id = "AnimCombinator", label = "ðŸŽ›ï¸ Animation Combinator" },
	{ id = "LocoIK", label = "ðŸƒ Locomotion & IK" },
	{ id = "RagdollLab", label = "ðŸ’¥ Ragdoll Lab" },
	{ id = "Maneuvers", label = "ðŸŽ® Maneuvers" },
}

-- 5 Sub-View Containers inside powerhouseView:
local animStudioView = Instance.new("Frame")
animStudioView.Name = "AnimStudioView"
animStudioView.Size = UDim2.new(1, 0, 1, -38)
animStudioView.Position = UDim2.new(0, 0, 0, 38)
animStudioView.BackgroundTransparency = 1
animStudioView.Parent = powerhouseView

local animCombinatorView = Instance.new("Frame")
animCombinatorView.Name = "AnimCombinatorView"
animCombinatorView.Size = UDim2.new(1, 0, 1, -38)
animCombinatorView.Position = UDim2.new(0, 0, 0, 38)
animCombinatorView.BackgroundTransparency = 1
animCombinatorView.Visible = false
animCombinatorView.Parent = powerhouseView

local locoIkView = Instance.new("Frame")
locoIkView.Name = "LocoIKView"
locoIkView.Size = UDim2.new(1, 0, 1, -38)
locoIkView.Position = UDim2.new(0, 0, 0, 38)
locoIkView.BackgroundTransparency = 1
locoIkView.Visible = false
locoIkView.Parent = powerhouseView

local ragdollLabView = Instance.new("Frame")
ragdollLabView.Name = "RagdollLabView"
ragdollLabView.Size = UDim2.new(1, 0, 1, -38)
ragdollLabView.Position = UDim2.new(0, 0, 0, 38)
ragdollLabView.BackgroundTransparency = 1
ragdollLabView.Visible = false
ragdollLabView.Parent = powerhouseView

local maneuversView = Instance.new("Frame")
maneuversView.Name = "ManeuversView"
maneuversView.Size = UDim2.new(1, 0, 1, -38)
maneuversView.Position = UDim2.new(0, 0, 0, 38)
maneuversView.BackgroundTransparency = 1
maneuversView.Visible = false
maneuversView.Parent = powerhouseView

local function switchPowerhouseSubTab(subId)
	activePowerhouseSubTab = subId
	animStudioView.Visible = (subId == "AnimStudio")
	animCombinatorView.Visible = (subId == "AnimCombinator")
	locoIkView.Visible = (subId == "LocoIK")
	ragdollLabView.Visible = (subId == "RagdollLab")
	maneuversView.Visible = (subId == "Maneuvers")

	for _, b in ipairs(subNavFrame:GetChildren()) do
		if b:IsA("TextButton") then
			local isActive = (b:GetAttribute("SubId") == subId)
			b.BackgroundColor3 = isActive and C_ACTIVE_TAB or Color3.fromRGB(30, 36, 48)
			b.TextColor3 = isActive and Color3.new(1, 1, 1) or C_TEXT_MUTED
		end
	end
end

for _, tab in ipairs(subTabs) do
	local b = Instance.new("TextButton")
	local label = tab.label
	b.Size = UDim2.new(0, math.max(130, #label * 7 + 10), 1, 0)
	b.BackgroundColor3 = (tab.id == activePowerhouseSubTab) and C_ACTIVE_TAB or Color3.fromRGB(30, 36, 48)
	b.TextColor3 = (tab.id == activePowerhouseSubTab) and Color3.new(1, 1, 1) or C_TEXT_MUTED
	b.Font = Enum.Font.GothamBold
	b.TextSize = 11
	b.Text = label
	b:SetAttribute("SubId", tab.id)
	b.Parent = subNavFrame
	applyCorner(b, 6)
	applyStroke(b, C_BORDER, 1)

	b.MouseButton1Click:Connect(function()
		switchPowerhouseSubTab(tab.id)
	end)
end

_G.SwitchPowerhouseSubTab = switchPowerhouseSubTab
shared.SwitchPowerhouseSubTab = switchPowerhouseSubTab
powerhouseView:GetAttributeChangedSignal("SubTab"):Connect(function()
	local sub = powerhouseView:GetAttribute("SubTab")
	if sub then switchPowerhouseSubTab(sub) end
end)

-- Top Right: Rig Status & Spawn / Reset Controls (shared on top)
local rigControls = Instance.new("Frame")
rigControls.Size = UDim2.new(0, 240, 0, 30)
rigControls.Position = UDim2.new(1, -250, 0, 4)
rigControls.BackgroundTransparency = 1
rigControls.Parent = powerhouseView

rigStatusBadge = Instance.new("TextLabel")
rigStatusBadge.Size = UDim2.new(0, 114, 1, 0)
rigStatusBadge.Position = UDim2.new(0, 0, 0, 0)
rigStatusBadge.BackgroundColor3 = Color3.fromRGB(24, 28, 38)
rigStatusBadge.TextColor3 = Color3.fromRGB(255, 170, 40)
rigStatusBadge.Font = Enum.Font.GothamBold
rigStatusBadge.TextSize = 10
rigStatusBadge.Text = "â— Rig: Checking..."
rigStatusBadge.Parent = rigControls
applyCorner(rigStatusBadge, 6)
applyStroke(rigStatusBadge, C_BORDER, 1)

respawnRigsBtn = Instance.new("TextButton")
respawnRigsBtn.Size = UDim2.new(0, 122, 1, 0)
respawnRigsBtn.Position = UDim2.new(0, 118, 0, 0)
respawnRigsBtn.BackgroundColor3 = Color3.fromRGB(35, 75, 110)
respawnRigsBtn.TextColor3 = C_ACCENT
respawnRigsBtn.Font = Enum.Font.GothamBold
respawnRigsBtn.TextSize = 10
respawnRigsBtn.Text = "ðŸ”„ Reset Rig"
respawnRigsBtn.Parent = rigControls
applyCorner(respawnRigsBtn, 6)
applyStroke(respawnRigsBtn, C_BORDER, 1)

respawnRigsBtn.MouseButton1Click:Connect(function()
	if checkAndSpawnTesters then
		checkAndSpawnTesters(true)
	end
end)

local function createPrecisionSlider(parent, yPos, labelText, minVal, maxVal, defaultVal, step, formatStr, onChange)
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(0.48, 0, 0, 18)
	label.Position = UDim2.new(0, 10, 0, yPos)
	label.BackgroundTransparency = 1
	label.TextColor3 = C_TEXT_MUTED
	label.Font = Enum.Font.Gotham
	label.TextSize = 11
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Text = labelText
	label.Parent = parent

	local minusBtn = Instance.new("TextButton")
	minusBtn.Size = UDim2.new(0, 20, 0, 18)
	minusBtn.Position = UDim2.new(0.50, 0, 0, yPos)
	minusBtn.BackgroundColor3 = Color3.fromRGB(42, 48, 64)
	minusBtn.TextColor3 = C_TEXT
	minusBtn.Font = Enum.Font.GothamBold
	minusBtn.TextSize = 11
	minusBtn.Text = "-"
	minusBtn.Parent = parent
	applyCorner(minusBtn, 4)

	local valBox = Instance.new("TextBox")
	valBox.Size = UDim2.new(0, 60, 0, 18)
	valBox.Position = UDim2.new(0.50, 24, 0, yPos)
	valBox.BackgroundColor3 = Color3.fromRGB(36, 42, 56)
	valBox.TextColor3 = C_ACCENT
	valBox.Font = Enum.Font.GothamBold
	valBox.TextSize = 11
	valBox.Text = string.format(formatStr, defaultVal)
	valBox.ClearTextOnFocus = false
	valBox.Active = true
	valBox.Selectable = true
	valBox.Parent = parent
	applyCorner(valBox, 4)
	applyStroke(valBox, Color3.fromRGB(55, 65, 85), 1)

	local plusBtn = Instance.new("TextButton")
	plusBtn.Size = UDim2.new(0, 20, 0, 18)
	plusBtn.Position = UDim2.new(0.50, 88, 0, yPos)
	plusBtn.BackgroundColor3 = Color3.fromRGB(42, 48, 64)
	plusBtn.TextColor3 = C_TEXT
	plusBtn.Font = Enum.Font.GothamBold
	plusBtn.TextSize = 11
	plusBtn.Text = "+"
	plusBtn.Parent = parent
	applyCorner(plusBtn, 4)

	local track = Instance.new("Frame")
	track.Size = UDim2.new(1, -20, 0, 8)
	track.Position = UDim2.new(0, 10, 0, yPos + 22)
	track.BackgroundColor3 = Color3.fromRGB(42, 48, 64)
	track.Parent = parent
	applyCorner(track, 4)

	local fill = Instance.new("Frame")
	local initRatio = math.clamp((defaultVal - minVal) / (maxVal - minVal), 0, 1)
	fill.Size = UDim2.new(initRatio, 0, 1, 0)
	fill.BackgroundColor3 = C_ACCENT
	fill.BorderSizePixel = 0
	fill.Parent = track
	applyCorner(fill, 4)

	local currentVal = defaultVal
	local isSliderDragging = false

	local function setVal(v, notify)
		v = math.clamp(v, minVal, maxVal)
		if step and step > 0 then
			v = math.floor((v / step) + 0.5) * step
		end
		currentVal = v
		valBox.Text = string.format(formatStr, v)
		local ratio = math.clamp((v - minVal) / (maxVal - minVal), 0, 1)
		fill.Size = UDim2.new(ratio, 0, 1, 0)
		if notify ~= false and onChange then onChange(v) end
	end

	minusBtn.MouseButton1Click:Connect(function()
		setVal(currentVal - (step or 0.05))
	end)

	plusBtn.MouseButton1Click:Connect(function()
		setVal(currentVal + (step or 0.05))
	end)

	valBox.FocusLost:Connect(function()
		local cleanStr = string.gsub(valBox.Text, "[^%d%.%-]", "")
		local num = tonumber(cleanStr)
		if num then
			setVal(num)
		else
			valBox.Text = string.format(formatStr, currentVal)
		end
	end)

	track.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			isSliderDragging = true
			local r = math.clamp((input.Position.X - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
			setVal(minVal + r * (maxVal - minVal))
		end
	end)

	UserInputService.InputChanged:Connect(function(input)
		if isSliderDragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			local r = math.clamp((input.Position.X - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
			setVal(minVal + r * (maxVal - minVal))
		end
	end)

	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			isSliderDragging = false
		end
	end)

	return {
		getValue = function() return currentVal end,
		setValue = function(v) setVal(v, false) end,
	}
end

local savePermBtn, statusToast, selectAnimation

--------------------------------------------------------------------------------
-- 4A. SUB-TAB 1: ANIMATION STUDIO (BROWSER, PRECISION KNOBS, COMBO)
--------------------------------------------------------------------------------
do
local catTabBar = Instance.new("ScrollingFrame")
catTabBar.Size = UDim2.new(1, -20, 0, 26)
catTabBar.Position = UDim2.new(0, 10, 0, 2)
catTabBar.BackgroundTransparency = 1
catTabBar.BorderSizePixel = 0
catTabBar.ScrollBarThickness = 2
catTabBar.ScrollBarImageColor3 = Color3.fromRGB(60, 80, 110)
catTabBar.ScrollingDirection = Enum.ScrollingDirection.X
catTabBar.AutomaticCanvasSize = Enum.AutomaticSize.X
catTabBar.CanvasSize = UDim2.new(0, 0, 0, 0)
catTabBar.ClipsDescendants = true
catTabBar.Parent = animStudioView

local catTabLayout = Instance.new("UIListLayout")
catTabLayout.FillDirection = Enum.FillDirection.Horizontal
catTabLayout.Padding = UDim.new(0, 6)
catTabLayout.Parent = catTabBar

-- Left Panel Top: Instant Live Search Bar
local searchContainer = Instance.new("Frame")
searchContainer.Size = UDim2.new(0, 250, 0, 28)
searchContainer.Position = UDim2.new(0, 10, 0, 32)
searchContainer.BackgroundColor3 = Color3.fromRGB(28, 34, 46)
searchContainer.Parent = animStudioView
applyCorner(searchContainer, 6)
applyStroke(searchContainer, C_BORDER, 1)

local searchBox = Instance.new("TextBox")
searchBox.Name = "AnimSearchBox"
searchBox.Text = ""
searchBox.Size = UDim2.new(1, -30, 1, 0)
searchBox.Position = UDim2.new(0, 8, 0, 0)
searchBox.BackgroundTransparency = 1
searchBox.TextColor3 = C_TEXT
searchBox.PlaceholderText = "ðŸ” Search (e.g. idle, kick, block)..."
searchBox.PlaceholderColor3 = C_TEXT_MUTED
searchBox.Font = Enum.Font.Gotham
searchBox.TextSize = 10
searchBox.TextXAlignment = Enum.TextXAlignment.Left
searchBox.ClearTextOnFocus = false
searchBox.Parent = searchContainer

local clearSearchBtn = Instance.new("TextButton")
clearSearchBtn.Name = "ClearSearchBtn"
clearSearchBtn.Size = UDim2.new(0, 20, 0, 20)
clearSearchBtn.Position = UDim2.new(1, -24, 0.5, -10)
clearSearchBtn.BackgroundColor3 = Color3.fromRGB(42, 50, 68)
clearSearchBtn.TextColor3 = C_TEXT_MUTED
clearSearchBtn.Font = Enum.Font.GothamBold
clearSearchBtn.TextSize = 10
clearSearchBtn.Text = "âœ•"
clearSearchBtn.Visible = false
clearSearchBtn.Parent = searchContainer
applyCorner(clearSearchBtn, 4)

-- Left Panel: Animation List
local listFrame = Instance.new("ScrollingFrame")
listFrame.Size = UDim2.new(0, 250, 1, -66)
listFrame.Position = UDim2.new(0, 10, 0, 64)
listFrame.BackgroundColor3 = C_PANEL
listFrame.ScrollBarThickness = 4
listFrame.ClipsDescendants = true
listFrame.Parent = animStudioView
applyCorner(listFrame, 8)
applyStroke(listFrame, C_BORDER, 1)

local listLayout = Instance.new("UIListLayout")
listLayout.Padding = UDim.new(0, 4)
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Parent = listFrame
listFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y

-- Center Panel: Precision Knobs (Scrollable)
local centerPanel = Instance.new("ScrollingFrame")
centerPanel.Size = UDim2.new(0, 400, 1, -38)
centerPanel.Position = UDim2.new(0, 270, 0, 32)
centerPanel.BackgroundColor3 = C_PANEL
centerPanel.ClipsDescendants = true
centerPanel.ScrollBarThickness = 4
centerPanel.CanvasSize = UDim2.new(0, 0, 0, 560)
centerPanel.Parent = animStudioView
applyCorner(centerPanel, 8)
applyStroke(centerPanel, C_BORDER, 1)

-- Right Panel: Combo Sequencer & Production Save
local rightPanel = Instance.new("Frame")
rightPanel.Size = UDim2.new(0, 270, 1, -38)
rightPanel.Position = UDim2.new(0, 680, 0, 32)
rightPanel.BackgroundColor3 = C_PANEL
rightPanel.ClipsDescendants = true
rightPanel.Parent = animStudioView
applyCorner(rightPanel, 8)
applyStroke(rightPanel, C_BORDER, 1)

-- Center Panel Elements
local activeAnimLabel = Instance.new("TextLabel")
activeAnimLabel.Size = UDim2.new(1, -20, 0, 26)
activeAnimLabel.Position = UDim2.new(0, 10, 0, 8)
activeAnimLabel.BackgroundColor3 = Color3.fromRGB(35, 41, 55)
activeAnimLabel.TextColor3 = C_ACCENT
activeAnimLabel.Font = Enum.Font.GothamBold
activeAnimLabel.TextSize = 12
activeAnimLabel.Text = "Selected: Attacks.Punches.Punch1"
activeAnimLabel.Parent = centerPanel
applyCorner(activeAnimLabel, 6)


local function triggerAutoHotSwap()
	labEvent:FireServer("UpdateConfig", {
		path = currentEntryPath,
		newValues = {
			id = currentEntryData.id,
			speed = currentEntryData.speed,
			fadeTime = currentEntryData.fadeTime,
			priority = currentEntryData.priority,
			looped = currentEntryData.looped,
			impactRatio = currentEntryData.impactRatio,
			cancelRatio = currentEntryData.cancelRatio,
		}
	})
end

local speedSlider = createPrecisionSlider(centerPanel, 40, "Playback Speed", 0.1, 3.5, currentEntryData.speed or 1.0, 0.05, "%.2fx", function(v)
	currentEntryData.speed = v
	triggerAutoHotSwap()
end)

local fadeSlider = createPrecisionSlider(centerPanel, 78, "Blend / Fade Time", 0.00, 0.50, currentEntryData.fadeTime or 0.05, 0.01, "%.2fs", function(v)
	currentEntryData.fadeTime = v
	triggerAutoHotSwap()
end)

local impactSlider = createPrecisionSlider(centerPanel, 116, "Impact Point (Ratio)", 0.05, 0.95, currentEntryData.impactRatio or 0.35, 0.05, "%.2f", function(v)
	currentEntryData.impactRatio = v
	triggerAutoHotSwap()
end)

local cancelSlider = createPrecisionSlider(centerPanel, 154, "Combo Cancel Point", 0.10, 1.00, currentEntryData.cancelRatio or 0.70, 0.05, "%.2f", function(v)
	currentEntryData.cancelRatio = v
	triggerAutoHotSwap()
end)

-- Looped & Priority
local loopToggle = Instance.new("TextButton")
loopToggle.Size = UDim2.new(0.46, 0, 0, 26)
loopToggle.Position = UDim2.new(0, 10, 0, 196)
loopToggle.BackgroundColor3 = Color3.fromRGB(36, 42, 56)
loopToggle.TextColor3 = C_TEXT
loopToggle.Font = Enum.Font.GothamBold
loopToggle.TextSize = 11
loopToggle.Text = "Looped: OFF"
loopToggle.Parent = centerPanel
applyCorner(loopToggle, 6)

loopToggle.MouseButton1Click:Connect(function()
	currentEntryData.looped = not currentEntryData.looped
	loopToggle.Text = currentEntryData.looped and "Looped: ON" or "Looped: OFF"
	loopToggle.TextColor3 = currentEntryData.looped and C_SUCCESS or C_TEXT
	triggerAutoHotSwap()
end)

local priorities = { "Action4", "Action", "Movement", "Idle" }
local priorityBtn = Instance.new("TextButton")
priorityBtn.Size = UDim2.new(0.46, 0, 0, 26)
priorityBtn.Position = UDim2.new(0.52, 0, 0, 196)
priorityBtn.BackgroundColor3 = Color3.fromRGB(36, 42, 56)
priorityBtn.TextColor3 = C_TEXT
priorityBtn.Font = Enum.Font.GothamBold
priorityBtn.TextSize = 11
priorityBtn.Text = "Priority: " .. (currentEntryData.priority or "Action4")
priorityBtn.Parent = centerPanel
applyCorner(priorityBtn, 6)

priorityBtn.MouseButton1Click:Connect(function()
	local cur = currentEntryData.priority or "Action4"
	local nextIdx = 1
	for idx, p in ipairs(priorities) do
		if p == cur then nextIdx = (idx % #priorities) + 1 break end
	end
	currentEntryData.priority = priorities[nextIdx]
	priorityBtn.Text = "Priority: " .. currentEntryData.priority
	triggerAutoHotSwap()
end)

-- Timeline Scrubber
local scrubSlider = createPrecisionSlider(centerPanel, 234, "Frame Scrubber (Freeze & Inspect)", 0.0, 2.5, 0.0, 0.02, "%.2fs", function(timePos)
	labEvent:FireServer("ScrubAnimation", {
		targetName = testerName,
		animId = currentEntryData.id,
		timePos = timePos,
		priority = currentEntryData.priority,
	})
end)

-- Animation Trimming (Sub-Phase Auditioning)
local startCutSlider = createPrecisionSlider(centerPanel, 272, "Trim Start Cut (s)", 0.0, 3.0, currentEntryData.startCut or 0.0, 0.02, "%.2fs", function(v)
	currentEntryData.startCut = v
	triggerAutoHotSwap()
end)

local endCutSlider = createPrecisionSlider(centerPanel, 310, "Trim End Cut (s)", 0.0, 3.0, currentEntryData.endCut or 0.0, 0.02, "%.2fs", function(v)
	currentEntryData.endCut = v
	triggerAutoHotSwap()
end)

-- Transport Action Buttons
local playBtn = Instance.new("TextButton")
playBtn.Size = UDim2.new(0, 110, 0, 30)
playBtn.Position = UDim2.new(0, 10, 0, 352)
playBtn.BackgroundColor3 = C_ACCENT
playBtn.TextColor3 = Color3.new(0, 0, 0)
playBtn.Font = Enum.Font.GothamBold
playBtn.TextSize = 11
playBtn.Text = "â–¶ Play Test"
playBtn.Parent = centerPanel
applyCorner(playBtn, 6)

local stopBtn = Instance.new("TextButton")
stopBtn.Size = UDim2.new(0, 110, 0, 30)
stopBtn.Position = UDim2.new(0, 126, 0, 352)
stopBtn.BackgroundColor3 = Color3.fromRGB(48, 56, 74)
stopBtn.TextColor3 = C_TEXT
stopBtn.Font = Enum.Font.GothamBold
stopBtn.TextSize = 11
stopBtn.Text = "â–  Stop"
stopBtn.Parent = centerPanel
applyCorner(stopBtn, 6)

local hotSwapBtn = Instance.new("TextButton")
hotSwapBtn.Size = UDim2.new(0, 134, 0, 30)
hotSwapBtn.Position = UDim2.new(0, 244, 0, 352)
hotSwapBtn.BackgroundColor3 = Color3.fromRGB(30, 140, 85)
hotSwapBtn.TextColor3 = C_TEXT
hotSwapBtn.Font = Enum.Font.GothamBold
hotSwapBtn.TextSize = 11
hotSwapBtn.Text = "âš¡ Hot-Swap Live"
hotSwapBtn.Parent = centerPanel
applyCorner(hotSwapBtn, 6)

-- Save Permanently Button
savePermBtn = Instance.new("TextButton")
savePermBtn.Size = UDim2.new(1, -20, 0, 28)
savePermBtn.Position = UDim2.new(0, 10, 0, 388)
savePermBtn.BackgroundColor3 = Color3.fromRGB(35, 95, 160)
savePermBtn.TextColor3 = Color3.fromRGB(240, 248, 255)
savePermBtn.Font = Enum.Font.GothamBold
savePermBtn.TextSize = 11
savePermBtn.Text = "ðŸ’¾ Save Permanently to Production"
savePermBtn.Parent = centerPanel
applyCorner(savePermBtn, 6)

-- Toast Banner
statusToast = Instance.new("TextLabel")
statusToast.Size = UDim2.new(1, -20, 0, 30)
statusToast.Position = UDim2.new(0, 10, 0, 490)
statusToast.BackgroundColor3 = Color3.fromRGB(20, 24, 34)
statusToast.TextColor3 = Color3.fromRGB(130, 210, 250)
statusToast.Font = Enum.Font.Gotham
statusToast.TextSize = 10
statusToast.Text = "Ready. Dials connect directly to ReplicatedStorage.QuinCore.AnimationConfig."
statusToast.ClipsDescendants = true
statusToast.Parent = centerPanel
applyCorner(statusToast, 6)
applyStroke(statusToast, Color3.fromRGB(40, 50, 70), 1)

savePermBtn.MouseButton1Click:Connect(function()
	local focus = UserInputService:GetFocusedTextBox()
	if focus then focus:ReleaseFocus() end

	savePermBtn.Text = "Saving to Production..."
	savePermBtn.BackgroundColor3 = Color3.fromRGB(60, 120, 180)
	
	-- Explicitly send current values
	local payload = {
		path = currentEntryPath,
		newValues = {
			id = currentEntryData.id,
			speed = currentEntryData.speed,
			fadeTime = currentEntryData.fadeTime,
			priority = currentEntryData.priority,
			looped = currentEntryData.looped,
			impactRatio = currentEntryData.impactRatio,
			cancelRatio = currentEntryData.cancelRatio,
			startCut = currentEntryData.startCut,
			endCut = currentEntryData.endCut,
		},
		luauCode = AnimationConfig.exportLuau()
	}
	labEvent:FireServer("SaveConfigPermanent", payload)
end)

playBtn.MouseButton1Click:Connect(function()
	if currentEntryData and currentEntryData.id then
		if checkAndSpawnTesters then checkAndSpawnTesters(false) end
		labEvent:FireServer("PlayAnimation", {
			targetName = testerName,
			animId = currentEntryData.id,
			speed = (currentEntryData.speed or 1.0) * slomoSpeed,
			fadeTime = currentEntryData.fadeTime or 0.05,
			priority = currentEntryData.priority or "Action4",
			looped = currentEntryData.looped == true,
			startCut = currentEntryData.startCut or 0.0,
			endCut = (currentEntryData.endCut and currentEntryData.endCut > 0) and currentEntryData.endCut or nil,
		})
	end
end)

stopBtn.MouseButton1Click:Connect(function()
	labEvent:FireServer("StopAnimation", { targetName = testerName })
end)

hotSwapBtn.MouseButton1Click:Connect(function()
	triggerAutoHotSwap()
	hotSwapBtn.Text = "âœ“ Hot-Swapped!"
	hotSwapBtn.BackgroundColor3 = C_SUCCESS
	task.delay(1.5, function()
		hotSwapBtn.Text = "âš¡ Hot-Swap Live"
		hotSwapBtn.BackgroundColor3 = Color3.fromRGB(30, 140, 85)
	end)
end)

-- Slow-Motion Buttons
local slomoLabel = Instance.new("TextLabel")
slomoLabel.Text = "Slow-Motion:"
slomoLabel.Size = UDim2.new(0, 80, 0, 22)
slomoLabel.Position = UDim2.new(0, 10, 0, 422)
slomoLabel.BackgroundTransparency = 1
slomoLabel.TextColor3 = C_TEXT_MUTED
slomoLabel.Font = Enum.Font.Gotham
slomoLabel.TextSize = 11
slomoLabel.TextXAlignment = Enum.TextXAlignment.Left
slomoLabel.Parent = centerPanel

local slomoButtons = {
	{ text = "1.0x", mult = 1.0 },
	{ text = "0.5x", mult = 0.5 },
	{ text = "0.25x", mult = 0.25 },
}

for i, sm in ipairs(slomoButtons) do
	local b = Instance.new("TextButton")
	b.Size = UDim2.new(0, 75, 0, 22)
	b.Position = UDim2.new(0, 95 + (i - 1) * 85, 0, 422)
	b.BackgroundColor3 = (sm.mult == slomoSpeed) and C_ACCENT or Color3.fromRGB(38, 44, 58)
	b.TextColor3 = (sm.mult == slomoSpeed) and Color3.new(0, 0, 0) or C_TEXT
	b.Font = Enum.Font.GothamBold
	b.TextSize = 11
	b.Text = sm.text
	b.Parent = centerPanel
	applyCorner(b, 4)

	b.MouseButton1Click:Connect(function()
		slomoSpeed = sm.mult
		for _, child in ipairs(centerPanel:GetChildren()) do
			if child:IsA("TextButton") and (child.Text == "1.0x" or child.Text == "0.5x" or child.Text == "0.25x") then
				child.BackgroundColor3 = Color3.fromRGB(38, 44, 58)
				child.TextColor3 = C_TEXT
			end
		end
		b.BackgroundColor3 = C_ACCENT
		b.TextColor3 = Color3.new(0, 0, 0)
	end)
end

-- Raw ID Box
local idLabel = Instance.new("TextLabel")
idLabel.Text = "Animation ID:"
idLabel.Size = UDim2.new(0, 80, 0, 22)
idLabel.Position = UDim2.new(0, 10, 0, 452)
idLabel.BackgroundTransparency = 1
idLabel.TextColor3 = C_TEXT_MUTED
idLabel.Font = Enum.Font.Gotham
idLabel.TextSize = 11
idLabel.TextXAlignment = Enum.TextXAlignment.Left
idLabel.Parent = centerPanel

local idBox = Instance.new("TextBox")
idBox.Size = UDim2.new(1, -105, 0, 22)
idBox.Position = UDim2.new(0, 95, 0, 452)
idBox.BackgroundColor3 = Color3.fromRGB(36, 42, 56)
idBox.TextColor3 = C_TEXT
idBox.Font = Enum.Font.Gotham
idBox.TextSize = 11
idBox.Text = currentEntryData.id or ""
idBox.ClearTextOnFocus = false
idBox.Active = true
idBox.Selectable = true
idBox.Parent = centerPanel
applyCorner(idBox, 4)
applyStroke(idBox, Color3.fromRGB(55, 65, 85), 1)

idBox.FocusLost:Connect(function()
	currentEntryData.id = idBox.Text
	triggerAutoHotSwap()
end)

-- Right Panel: Combo Sequencer
local comboTitle = Instance.new("TextLabel")
comboTitle.Text = "COMBO SEQUENCER"
comboTitle.Size = UDim2.new(1, 0, 0, 22)
comboTitle.Position = UDim2.new(0, 10, 0, 8)
comboTitle.BackgroundTransparency = 1
comboTitle.TextColor3 = C_TEXT
comboTitle.Font = Enum.Font.GothamBold
comboTitle.TextSize = 12
comboTitle.TextXAlignment = Enum.TextXAlignment.Left
comboTitle.Parent = rightPanel

local comboScroll = Instance.new("ScrollingFrame")
comboScroll.Size = UDim2.new(1, -20, 0, 230)
comboScroll.Position = UDim2.new(0, 10, 0, 32)
comboScroll.BackgroundColor3 = Color3.fromRGB(22, 25, 33)
comboScroll.ScrollBarThickness = 3
comboScroll.ClipsDescendants = true
comboScroll.Parent = rightPanel
applyCorner(comboScroll, 6)

local comboLayout = Instance.new("UIListLayout")
comboLayout.Padding = UDim.new(0, 4)
comboLayout.Parent = comboScroll

local function renderComboList()
	for _, child in ipairs(comboScroll:GetChildren()) do
		if child:IsA("Frame") then child:Destroy() end
	end
	for idx, item in ipairs(comboChain) do
		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, -6, 0, 28)
		row.BackgroundColor3 = Color3.fromRGB(35, 41, 55)
		row.Parent = comboScroll
		applyCorner(row, 4)

		local numLbl = Instance.new("TextLabel")
		numLbl.Text = string.format("%d. %s", idx, item.name or item.path)
		numLbl.Size = UDim2.new(0.8, 0, 1, 0)
		numLbl.Position = UDim2.new(0, 6, 0, 0)
		numLbl.BackgroundTransparency = 1
		numLbl.TextColor3 = C_TEXT
		numLbl.Font = Enum.Font.Gotham
		numLbl.TextSize = 11
		numLbl.TextXAlignment = Enum.TextXAlignment.Left
		numLbl.Parent = row

		local delBtn = Instance.new("TextButton")
		delBtn.Text = "X"
		delBtn.Size = UDim2.new(0, 20, 0, 20)
		delBtn.Position = UDim2.new(1, -24, 0, 4)
		delBtn.BackgroundColor3 = Color3.fromRGB(60, 32, 32)
		delBtn.TextColor3 = C_DANGER
		delBtn.Font = Enum.Font.GothamBold
		delBtn.TextSize = 10
		delBtn.Parent = row
		applyCorner(delBtn, 4)

		delBtn.MouseButton1Click:Connect(function()
			table.remove(comboChain, idx)
			renderComboList()
		end)
	end
	comboScroll.CanvasSize = UDim2.new(0, 0, 0, #comboChain * 32)
end

renderComboList()

local addMoveBtn = Instance.new("TextButton")
addMoveBtn.Size = UDim2.new(1, -20, 0, 28)
addMoveBtn.Position = UDim2.new(0, 10, 0, 270)
addMoveBtn.BackgroundColor3 = Color3.fromRGB(38, 44, 58)
addMoveBtn.TextColor3 = C_ACCENT
addMoveBtn.Font = Enum.Font.GothamBold
addMoveBtn.TextSize = 11
addMoveBtn.Text = "+ Add Selected to Combo"
addMoveBtn.Parent = rightPanel
applyCorner(addMoveBtn, 6)

addMoveBtn.MouseButton1Click:Connect(function()
	table.insert(comboChain, {
		path = currentEntryPath,
		name = currentEntryData.name or currentEntryPath,
		customSpeed = currentEntryData.speed,
		customFade = currentEntryData.fadeTime,
	})
	renderComboList()
end)

local playComboBtn = Instance.new("TextButton")
playComboBtn.Size = UDim2.new(1, -20, 0, 36)
playComboBtn.Position = UDim2.new(0, 10, 0, 306)
playComboBtn.BackgroundColor3 = Color3.fromRGB(0, 180, 120)
playComboBtn.TextColor3 = Color3.new(0, 0, 0)
playComboBtn.Font = Enum.Font.GothamBold
playComboBtn.TextSize = 12
playComboBtn.Text = "â–¶ Play Full Combo"
playComboBtn.Parent = rightPanel
applyCorner(playComboBtn, 6)

playComboBtn.MouseButton1Click:Connect(function()
	if #comboChain == 0 then return end
	labEvent:FireServer("PlayCombo", {
		targetName = testerName,
		partnerName = partnerName,
		steps = comboChain,
	})
end)

local clearComboBtn = Instance.new("TextButton")
clearComboBtn.Size = UDim2.new(1, -20, 0, 24)
clearComboBtn.Position = UDim2.new(0, 10, 0, 350)
clearComboBtn.BackgroundColor3 = Color3.fromRGB(45, 30, 30)
clearComboBtn.TextColor3 = C_DANGER
clearComboBtn.Font = Enum.Font.Gotham
clearComboBtn.TextSize = 10
clearComboBtn.Text = "Clear Combo Chain"
clearComboBtn.Parent = rightPanel
applyCorner(clearComboBtn, 4)

clearComboBtn.MouseButton1Click:Connect(function()
	comboChain = {}
	renderComboList()
end)

-- Export Button
local exportBtn = Instance.new("TextButton")
exportBtn.Size = UDim2.new(1, -20, 0, 36)
exportBtn.Position = UDim2.new(0, 10, 0, 386)
exportBtn.BackgroundColor3 = C_ACCENT
exportBtn.TextColor3 = Color3.new(0, 0, 0)
exportBtn.Font = Enum.Font.GothamBold
exportBtn.TextSize = 12
exportBtn.Text = "[#] View / Export Luau Config"
exportBtn.Parent = rightPanel
applyCorner(exportBtn, 6)

--------------------------------------------------------------------------------
-- 5. POPUP MODAL FOR EXPORTED CODE
--------------------------------------------------------------------------------
local showLuauExportModal
do
	local modalBackdrop = Instance.new("Frame")
modalBackdrop.Size = UDim2.new(1, 0, 1, 0)
modalBackdrop.BackgroundColor3 = Color3.new(0, 0, 0)
modalBackdrop.BackgroundTransparency = 0.5
modalBackdrop.Visible = false
modalBackdrop.ZIndex = 50
modalBackdrop.Parent = screenGui

local modalFrame = Instance.new("Frame")
modalFrame.Size = UDim2.new(0, 620, 0, 440)
modalFrame.Position = UDim2.new(0.5, -310, 0.5, -220)
modalFrame.BackgroundColor3 = C_BG
modalFrame.ClipsDescendants = true
modalFrame.ZIndex = 51
modalFrame.Parent = modalBackdrop
applyCorner(modalFrame, 10)
applyStroke(modalFrame, C_ACCENT, 1.5)

local modalTitle = Instance.new("TextLabel")
modalTitle.Text = "  EXPORTED ANIMATION CONFIG (LUAU)"
modalTitle.Size = UDim2.new(1, -40, 0, 40)
modalTitle.BackgroundColor3 = C_PANEL
modalTitle.TextColor3 = C_TEXT
modalTitle.Font = Enum.Font.GothamBold
modalTitle.TextSize = 13
modalTitle.TextXAlignment = Enum.TextXAlignment.Left
modalTitle.ZIndex = 52
modalTitle.Parent = modalFrame

local modalCloseBtn = Instance.new("TextButton")
modalCloseBtn.Text = "X"
modalCloseBtn.Size = UDim2.new(0, 32, 0, 32)
modalCloseBtn.Position = UDim2.new(1, -36, 0, 4)
modalCloseBtn.BackgroundColor3 = Color3.fromRGB(50, 30, 30)
modalCloseBtn.TextColor3 = C_DANGER
modalCloseBtn.Font = Enum.Font.GothamBold
modalCloseBtn.TextSize = 12
modalCloseBtn.ZIndex = 53
modalCloseBtn.Parent = modalFrame
applyCorner(modalCloseBtn, 6)

modalCloseBtn.MouseButton1Click:Connect(function()
	modalBackdrop.Visible = false
end)

local modalScroll = Instance.new("ScrollingFrame")
modalScroll.Size = UDim2.new(1, -20, 0, 330)
modalScroll.Position = UDim2.new(0, 10, 0, 50)
modalScroll.BackgroundColor3 = Color3.fromRGB(15, 17, 22)
modalScroll.ScrollBarThickness = 4
modalScroll.ZIndex = 52
modalScroll.Parent = modalFrame
applyCorner(modalScroll, 6)

local modalTextBox = Instance.new("TextBox")
modalTextBox.Size = UDim2.new(1, -10, 1, -10)
modalTextBox.Position = UDim2.new(0, 5, 0, 5)
modalTextBox.BackgroundTransparency = 1
modalTextBox.TextColor3 = Color3.fromRGB(180, 245, 180)
modalTextBox.Font = Enum.Font.Code
modalTextBox.TextSize = 11
modalTextBox.TextXAlignment = Enum.TextXAlignment.Left
modalTextBox.TextYAlignment = Enum.TextYAlignment.Top
modalTextBox.ClearTextOnFocus = false
modalTextBox.MultiLine = true
modalTextBox.ZIndex = 53
modalTextBox.Parent = modalScroll

local copyNotifyBtn = Instance.new("TextButton")
copyNotifyBtn.Size = UDim2.new(1, -20, 0, 36)
copyNotifyBtn.Position = UDim2.new(0, 10, 0, 390)
copyNotifyBtn.BackgroundColor3 = C_ACCENT
copyNotifyBtn.TextColor3 = Color3.new(0, 0, 0)
copyNotifyBtn.Font = Enum.Font.GothamBold
copyNotifyBtn.TextSize = 12
copyNotifyBtn.Text = "Print to Studio Output & Select All"
copyNotifyBtn.ZIndex = 53
copyNotifyBtn.Parent = modalFrame
applyCorner(copyNotifyBtn, 6)

showLuauExportModal = function(code, title)
	modalTitle.Text = title or "  EXPORTED ANIMATION CONFIG (LUAU)"
	modalTextBox.Text = code or ""
	modalScroll.CanvasSize = UDim2.new(0, 0, 0, math.max(600, #modalTextBox.Text * 0.8))
	modalBackdrop.Visible = true
end

exportBtn.MouseButton1Click:Connect(function()
	local luauCode = AnimationConfig.exportLuau()
	showLuauExportModal(luauCode, "  EXPORTED ANIMATION CONFIG (LUAU)")
end)

copyNotifyBtn.MouseButton1Click:Connect(function()
	local luauCode = modalTextBox.Text
	print("========================================")
	print(modalTitle.Text)
	print(luauCode)
	print("========================================")
	modalTextBox:CaptureFocus()
	copyNotifyBtn.Text = "âœ“ Printed to Console Output!"
	task.delay(1.5, function() copyNotifyBtn.Text = "Print to Studio Output & Select All" end)
end)
end

--------------------------------------------------------------------------------
-- 6. DYNAMIC CATEGORY & ANIMATION ITEM LOADER
--------------------------------------------------------------------------------
selectAnimation = function(item)
	currentEntryPath = item.path
	currentEntryData = item.entry or AnimationConfig.get(item.path) or {}
	activeAnimLabel.Text = "Selected: " .. (item.name or item.path)
	idBox.Text = currentEntryData.id or ""

	speedSlider.setValue(currentEntryData.speed or 1.0)
	fadeSlider.setValue(currentEntryData.fadeTime or 0.05)
	impactSlider.setValue(currentEntryData.impactRatio or 0.35)
	cancelSlider.setValue(currentEntryData.cancelRatio or 0.70)
	if startCutSlider then startCutSlider.setValue(currentEntryData.startCut or 0.0) end
	if endCutSlider then endCutSlider.setValue(currentEntryData.endCut or 0.0) end

	loopToggle.Text = currentEntryData.looped and "Looped: ON" or "Looped: OFF"
	loopToggle.TextColor3 = currentEntryData.looped and C_SUCCESS or C_TEXT
	priorityBtn.Text = "Priority: " .. (currentEntryData.priority or "Action4")
end

local function populateList(category, searchQuery)
	for _, child in ipairs(listFrame:GetChildren()) do
		if child:IsA("TextButton") or child:IsA("TextLabel") then child:Destroy() end
	end

	local allPaths = AnimationConfig.getAllPaths()
	local query = searchQuery and string.lower(string.gsub(searchQuery, "^%s*(.-)%s*$", "%1")) or ""
	local isSearching = (query ~= "")
	local count = 0

	for _, item in ipairs(allPaths) do
		local match = false
		if isSearching then
			local nameLower = string.lower(item.name or "")
			local pathLower = string.lower(item.path or "")
			local catLower = string.lower(item.category or "")
			if nameLower:find(query, 1, true) or pathLower:find(query, 1, true) or catLower:find(query, 1, true) then
				match = true
			end
		else
			if category == "Custom" then
				match = item.category:find("Custom") ~= nil
			elseif category == "All" then
				match = true
			else
				match = item.category:find(category) ~= nil or item.path:find(category) ~= nil
			end
		end

		if match then
			count = count + 1
			local isSelected = (item.path == currentEntryPath)
			local btn = Instance.new("TextButton")
			btn.Size = UDim2.new(1, -8, 0, 32)
			btn.BackgroundColor3 = isSelected and Color3.fromRGB(30, 80, 125) or Color3.fromRGB(30, 35, 46)
			btn.TextColor3 = isSelected and Color3.fromRGB(0, 235, 255) or C_TEXT
			btn.Font = isSelected and Enum.Font.GothamBold or Enum.Font.Gotham
			btn.TextSize = 11
			btn.TextXAlignment = Enum.TextXAlignment.Left
			btn.Text = "  " .. item.name
			btn.Parent = listFrame
			applyCorner(btn, 4)
			if isSelected then
				applyStroke(btn, Color3.fromRGB(0, 210, 255), 1.2)
			end

			btn.MouseButton1Click:Connect(function()
				selectAnimation(item)
				populateList(category, searchBox.Text)
			end)
		end
	end

	if count == 0 then
		local noRes = Instance.new("TextLabel")
		noRes.Size = UDim2.new(1, -10, 0, 40)
		noRes.BackgroundTransparency = 1
		noRes.TextColor3 = C_TEXT_MUTED
		noRes.Font = Enum.Font.Gotham
		noRes.TextSize = 11
		noRes.Text = isSearching and ("No matches for '" .. query .. "'") or "No animations in this category."
		noRes.Parent = listFrame
	end
end

-- Wire up search input box
searchBox:GetPropertyChangedSignal("Text"):Connect(function()
	local text = searchBox.Text
	clearSearchBtn.Visible = (#text > 0)
	populateList(currentCategory, text)
end)

clearSearchBtn.MouseButton1Click:Connect(function()
	searchBox.Text = ""
	clearSearchBtn.Visible = false
	populateList(currentCategory, "")
end)

-- Compute counts for each category
local allPathsForCounts = AnimationConfig.getAllPaths()
local catCounts = {}
for _, item in ipairs(allPathsForCounts) do
	local topCat = string.match(item.path, "^([^%.]+)") or item.category
	catCounts[topCat] = (catCounts[topCat] or 0) + 1
	catCounts["All"] = (catCounts["All"] or 0) + 1
end

-- Discover categories from registry
local categories = { "All" }
for catKey in pairs(AnimationConfig.Registry) do
	table.insert(categories, catKey)
end
table.sort(categories, function(a, b)
	if a == "All" then return true end
	if b == "All" then return false end
	if a == "Idles" then return true end
	if b == "Idles" then return false end
	return a < b
end)
if not table.find(categories, "Custom") then
	table.insert(categories, "Custom")
end

for _, cat in ipairs(categories) do
	local count = catCounts[cat] or 0
	local btn = Instance.new("TextButton")
	local label = cat .. " (" .. tostring(count) .. ")"
	btn.Size = UDim2.new(0, math.max(100, #label * 8 + 16), 1, 0)
	btn.BackgroundColor3 = (cat == currentCategory) and C_ACCENT or Color3.fromRGB(35, 40, 52)
	btn.TextColor3 = (cat == currentCategory) and Color3.new(0, 0, 0) or C_TEXT
	btn.Font = Enum.Font.GothamBold
	btn.TextSize = 11
	btn.Text = label
	btn:SetAttribute("CategoryName", cat)
	btn.Parent = catTabBar
	applyCorner(btn, 6)

	btn.MouseButton1Click:Connect(function()
		currentCategory = cat
		searchBox.Text = ""
		clearSearchBtn.Visible = false
		for _, b in ipairs(catTabBar:GetChildren()) do
			if b:IsA("TextButton") then
				local bCat = b:GetAttribute("CategoryName")
				local isActive = (bCat == cat)
				b.BackgroundColor3 = isActive and C_ACCENT or Color3.fromRGB(35, 40, 52)
				b.TextColor3 = isActive and Color3.new(0, 0, 0) or C_TEXT
			end
		end
		populateList(cat, "")
	end)
end

populateList(currentCategory, "")

_G.SelectCategory = function(cat)
	currentCategory = cat
	searchBox.Text = ""
	clearSearchBtn.Visible = false
	for _, b in ipairs(catTabBar:GetChildren()) do
		if b:IsA("TextButton") then
			local bCat = b:GetAttribute("CategoryName")
			local isActive = (bCat == cat)
			b.BackgroundColor3 = isActive and C_ACCENT or Color3.fromRGB(35, 40, 52)
			b.TextColor3 = isActive and Color3.new(0, 0, 0) or C_TEXT
		end
	end
	populateList(cat, "")
end

_G.SetAnimSearch = function(query)
	searchBox.Text = query
	clearSearchBtn.Visible = (#query > 0)
	populateList(currentCategory, query)
end

shared.SelectCategory = _G.SelectCategory
shared.SetAnimSearch = _G.SetAnimSearch

mainFrame:GetAttributeChangedSignal("SelectedCategory"):Connect(function()
	local cat = mainFrame:GetAttribute("SelectedCategory")
	if cat and _G.SelectCategory then _G.SelectCategory(cat) end
end)

mainFrame:GetAttributeChangedSignal("SearchQuery"):Connect(function()
	local q = mainFrame:GetAttribute("SearchQuery")
	if q and _G.SetAnimSearch then _G.SetAnimSearch(q) end
end)

end

--------------------------------------------------------------------------------
-- 4A2. SUB-TAB: ANIMATION COMBINATOR (LABORATORY, STACK, SCRUBBER, TRANSITIONS)
--------------------------------------------------------------------------------
do
	-- State for Combinator
	local combinatorLayers = {}
	local combinatorGlobalDuration = 2.0
	local combinatorCurrentTime = 0.0
	local combinatorIsPlaying = false
	local combinatorLoop = true
	local combinatorPlaySpeed = 1.0

	-- Transition Inspector State
	local transLayerAIdx = 1
	local transLayerBIdx = 2
	local transBlendTime = 0.15
	local isTransitionTesting = false
	local transitionThread = nil

	-- Forward declarations
	local refreshStackView
	local updateGlobalDuration
	local updateScrubberVisuals
	local syncScrubToServer
	local triggerStackPlayback
	local stopCombinatorPlayback
	local getActiveLayersPayload

	-- Master Top Container (3 Columns)
	local topArea = Instance.new("Frame")
	topArea.Name = "CombinatorTopArea"
	topArea.Size = UDim2.new(1, 0, 1, -112)
	topArea.Position = UDim2.new(0, 0, 0, 4)
	topArea.BackgroundTransparency = 1
	topArea.Parent = animCombinatorView

	-- Master Bottom Container (Global Timeline Scrubber & Master Transport)
	local bottomPanel = Instance.new("Frame")
	bottomPanel.Name = "CombinatorBottomPanel"
	bottomPanel.Size = UDim2.new(1, -16, 0, 104)
	bottomPanel.Position = UDim2.new(0, 8, 1, -106)
	bottomPanel.BackgroundColor3 = C_PANEL
	bottomPanel.ClipsDescendants = true
	bottomPanel.Parent = animCombinatorView
	applyCorner(bottomPanel, 8)
	applyStroke(bottomPanel, C_BORDER, 1)

	----------------------------------------------------------------------------
	-- LEFT COLUMN: DIRECT ID INSERTER & PRE-REGISTERED LIBRARY
	----------------------------------------------------------------------------
	local libPanel = Instance.new("Frame")
	libPanel.Name = "LibraryPanel"
	libPanel.Size = UDim2.new(0, 270, 1, 0)
	libPanel.Position = UDim2.new(0, 8, 0, 0)
	libPanel.BackgroundColor3 = C_PANEL
	libPanel.ClipsDescendants = true
	libPanel.Parent = topArea
	applyCorner(libPanel, 8)
	applyStroke(libPanel, C_BORDER, 1)

	-- Direct ID Inserter Header
	local directIdHeader = Instance.new("TextLabel")
	directIdHeader.Text = "âš¡ DIRECT ID INSERTER"
	directIdHeader.Size = UDim2.new(1, -16, 0, 20)
	directIdHeader.Position = UDim2.new(0, 8, 0, 6)
	directIdHeader.BackgroundTransparency = 1
	directIdHeader.TextColor3 = C_ACCENT
	directIdHeader.Font = Enum.Font.GothamBold
	directIdHeader.TextSize = 11
	directIdHeader.TextXAlignment = Enum.TextXAlignment.Left
	directIdHeader.Parent = libPanel

	local directIdBox = Instance.new("TextBox")
	directIdBox.Name = "DirectIdBox"
	directIdBox.Size = UDim2.new(1, -16, 0, 26)
	directIdBox.Position = UDim2.new(0, 8, 0, 28)
	directIdBox.BackgroundColor3 = Color3.fromRGB(30, 36, 48)
	directIdBox.TextColor3 = C_TEXT
	directIdBox.PlaceholderText = "Paste ID (e.g. 81038616654818)..."
	directIdBox.PlaceholderColor3 = C_TEXT_MUTED
	directIdBox.Font = Enum.Font.Code
	directIdBox.TextSize = 11
	directIdBox.TextXAlignment = Enum.TextXAlignment.Left
	directIdBox.ClearTextOnFocus = false
	directIdBox.Text = ""
	directIdBox.Parent = libPanel
	applyCorner(directIdBox, 4)
	applyStroke(directIdBox, Color3.fromRGB(50, 60, 80), 1)

	local directBtnsFrame = Instance.new("Frame")
	directBtnsFrame.Size = UDim2.new(1, -16, 0, 26)
	directBtnsFrame.Position = UDim2.new(0, 8, 0, 58)
	directBtnsFrame.BackgroundTransparency = 1
	directBtnsFrame.Parent = libPanel

	local previewIdBtn = Instance.new("TextButton")
	previewIdBtn.Text = "â–¶ Audition"
	previewIdBtn.Size = UDim2.new(0.48, -2, 1, 0)
	previewIdBtn.Position = UDim2.new(0, 0, 0, 0)
	previewIdBtn.BackgroundColor3 = Color3.fromRGB(40, 80, 120)
	previewIdBtn.TextColor3 = Color3.fromRGB(220, 245, 255)
	previewIdBtn.Font = Enum.Font.GothamBold
	previewIdBtn.TextSize = 11
	previewIdBtn.Parent = directBtnsFrame
	applyCorner(previewIdBtn, 4)

	local addIdBtn = Instance.new("TextButton")
	addIdBtn.Text = "+ Add Layer"
	addIdBtn.Size = UDim2.new(0.52, -2, 1, 0)
	addIdBtn.Position = UDim2.new(0.48, 4, 0, 0)
	addIdBtn.BackgroundColor3 = C_ACCENT
	addIdBtn.TextColor3 = Color3.new(0, 0, 0)
	addIdBtn.Font = Enum.Font.GothamBold
	addIdBtn.TextSize = 11
	addIdBtn.Parent = directBtnsFrame
	applyCorner(addIdBtn, 4)

	-- Divider
	local libDivider = Instance.new("Frame")
	libDivider.Size = UDim2.new(1, -16, 0, 1)
	libDivider.Position = UDim2.new(0, 8, 0, 90)
	libDivider.BackgroundColor3 = Color3.fromRGB(45, 52, 70)
	libDivider.BorderSizePixel = 0
	libDivider.Parent = libPanel

	-- Pre-Registered Library Header
	local libHeader = Instance.new("TextLabel")
	libHeader.Text = "ðŸ“š PRE-REGISTERED LIBRARY"
	libHeader.Size = UDim2.new(1, -16, 0, 20)
	libHeader.Position = UDim2.new(0, 8, 0, 96)
	libHeader.BackgroundTransparency = 1
	libHeader.TextColor3 = C_TEXT
	libHeader.Font = Enum.Font.GothamBold
	libHeader.TextSize = 11
	libHeader.TextXAlignment = Enum.TextXAlignment.Left
	libHeader.Parent = libPanel

	-- Category Tabs Bar
	local combCatTabBar = Instance.new("ScrollingFrame")
	combCatTabBar.Size = UDim2.new(1, -16, 0, 24)
	combCatTabBar.Position = UDim2.new(0, 8, 0, 118)
	combCatTabBar.BackgroundTransparency = 1
	combCatTabBar.ScrollBarThickness = 2
	combCatTabBar.CanvasSize = UDim2.new(0, 520, 0, 0)
	combCatTabBar.Parent = libPanel

	local combCatLayout = Instance.new("UIListLayout")
	combCatLayout.FillDirection = Enum.FillDirection.Horizontal
	combCatLayout.Padding = UDim.new(0, 4)
	combCatLayout.Parent = combCatTabBar

	-- Library Search Box
	local combSearchBox = Instance.new("TextBox")
	combSearchBox.Size = UDim2.new(1, -16, 0, 24)
	combSearchBox.Position = UDim2.new(0, 8, 0, 146)
	combSearchBox.BackgroundColor3 = Color3.fromRGB(28, 34, 46)
	combSearchBox.TextColor3 = C_TEXT
	combSearchBox.PlaceholderText = "ðŸ” Search library (e.g. idle, punch)..."
	combSearchBox.PlaceholderColor3 = C_TEXT_MUTED
	combSearchBox.Font = Enum.Font.Gotham
	combSearchBox.TextSize = 10
	combSearchBox.TextXAlignment = Enum.TextXAlignment.Left
	combSearchBox.ClearTextOnFocus = false
	combSearchBox.Text = ""
	combSearchBox.Parent = libPanel
	applyCorner(combSearchBox, 4)
	applyStroke(combSearchBox, C_BORDER, 1)

	-- Library Scroll List
	local libScroll = Instance.new("ScrollingFrame")
	libScroll.Size = UDim2.new(1, -16, 1, -176)
	libScroll.Position = UDim2.new(0, 8, 0, 174)
	libScroll.BackgroundColor3 = Color3.fromRGB(20, 24, 32)
	libScroll.ScrollBarThickness = 3
	libScroll.ClipsDescendants = true
	libScroll.Parent = libPanel
	applyCorner(libScroll, 6)

	local libLayout = Instance.new("UIListLayout")
	libLayout.Padding = UDim.new(0, 3)
	libLayout.SortOrder = Enum.SortOrder.LayoutOrder
	libLayout.Parent = libScroll
	libScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y

	----------------------------------------------------------------------------
	-- CENTER COLUMN: COMBINATION STACK & LAYER INSPECTOR
	----------------------------------------------------------------------------
	local stackPanel = Instance.new("Frame")
	stackPanel.Name = "StackPanel"
	stackPanel.Size = UDim2.new(0, 420, 1, 0)
	stackPanel.Position = UDim2.new(0, 286, 0, 0)
	stackPanel.BackgroundColor3 = C_PANEL
	stackPanel.ClipsDescendants = true
	stackPanel.Parent = topArea
	applyCorner(stackPanel, 8)
	applyStroke(stackPanel, C_BORDER, 1)

	-- Stack Top Bar
	local stackTitle = Instance.new("TextLabel")
	stackTitle.Text = "ðŸŽ›ï¸ COMBINATION STACK"
	stackTitle.Size = UDim2.new(0, 170, 0, 28)
	stackTitle.Position = UDim2.new(0, 10, 0, 4)
	stackTitle.BackgroundTransparency = 1
	stackTitle.TextColor3 = C_ACCENT
	stackTitle.Font = Enum.Font.GothamBold
	stackTitle.TextSize = 12
	stackTitle.TextXAlignment = Enum.TextXAlignment.Left
	stackTitle.Parent = stackPanel

	local stackCountBadge = Instance.new("TextLabel")
	stackCountBadge.Text = "(0 Layers)"
	stackCountBadge.Size = UDim2.new(0, 70, 0, 28)
	stackCountBadge.Position = UDim2.new(0, 175, 0, 4)
	stackCountBadge.BackgroundTransparency = 1
	stackCountBadge.TextColor3 = C_TEXT_MUTED
	stackCountBadge.Font = Enum.Font.Gotham
	stackCountBadge.TextSize = 11
	stackCountBadge.TextXAlignment = Enum.TextXAlignment.Left
	stackCountBadge.Parent = stackPanel

	local addEmptyLayerBtn = Instance.new("TextButton")
	addEmptyLayerBtn.Text = "+ Add Blank"
	addEmptyLayerBtn.Size = UDim2.new(0, 85, 0, 22)
	addEmptyLayerBtn.Position = UDim2.new(1, -165, 0, 7)
	addEmptyLayerBtn.BackgroundColor3 = Color3.fromRGB(36, 75, 115)
	addEmptyLayerBtn.TextColor3 = Color3.fromRGB(220, 245, 255)
	addEmptyLayerBtn.Font = Enum.Font.GothamBold
	addEmptyLayerBtn.TextSize = 10
	addEmptyLayerBtn.Parent = stackPanel
	applyCorner(addEmptyLayerBtn, 4)

	local clearStackBtn = Instance.new("TextButton")
	clearStackBtn.Text = "ðŸ—‘ Clear"
	clearStackBtn.Size = UDim2.new(0, 65, 0, 22)
	clearStackBtn.Position = UDim2.new(1, -74, 0, 7)
	clearStackBtn.BackgroundColor3 = Color3.fromRGB(70, 32, 36)
	clearStackBtn.TextColor3 = C_DANGER
	clearStackBtn.Font = Enum.Font.GothamBold
	clearStackBtn.TextSize = 10
	clearStackBtn.Parent = stackPanel
	applyCorner(clearStackBtn, 4)

	-- Stack Scroll List
	local stackScroll = Instance.new("ScrollingFrame")
	stackScroll.Name = "StackScroll"
	stackScroll.Size = UDim2.new(1, -16, 1, -40)
	stackScroll.Position = UDim2.new(0, 8, 0, 34)
	stackScroll.BackgroundColor3 = Color3.fromRGB(18, 21, 28)
	stackScroll.ScrollBarThickness = 4
	stackScroll.ClipsDescendants = true
	stackScroll.Parent = stackPanel
	applyCorner(stackScroll, 6)

	local stackLayout = Instance.new("UIListLayout")
	stackLayout.Padding = UDim.new(0, 6)
	stackLayout.SortOrder = Enum.SortOrder.LayoutOrder
	stackLayout.Parent = stackScroll
	stackScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y

	local emptyStackNotice = Instance.new("TextLabel")
	emptyStackNotice.Text = "No animation layers in stack.\nClick '+' on any clip in the Library or use\nDirect ID Inserter to start combining animations!"
	emptyStackNotice.Size = UDim2.new(1, -20, 0, 90)
	emptyStackNotice.Position = UDim2.new(0, 10, 0, 20)
	emptyStackNotice.BackgroundTransparency = 1
	emptyStackNotice.TextColor3 = C_TEXT_MUTED
	emptyStackNotice.Font = Enum.Font.Gotham
	emptyStackNotice.TextSize = 11
	emptyStackNotice.TextYAlignment = Enum.TextYAlignment.Center
	emptyStackNotice.Parent = stackScroll

	----------------------------------------------------------------------------
	-- RIGHT COLUMN: TRANSITION INSPECTOR, PRESETS & EXPORT
	----------------------------------------------------------------------------
	local inspPanel = Instance.new("Frame")
	inspPanel.Name = "InspectorPanel"
	inspPanel.Size = UDim2.new(1, -714, 1, 0)
	inspPanel.Position = UDim2.new(0, 714, 0, 0)
	inspPanel.BackgroundColor3 = C_PANEL
	inspPanel.ClipsDescendants = true
	inspPanel.Parent = topArea
	applyCorner(inspPanel, 8)
	applyStroke(inspPanel, C_BORDER, 1)

	local inspScroll = Instance.new("ScrollingFrame")
	inspScroll.Size = UDim2.new(1, -8, 1, -8)
	inspScroll.Position = UDim2.new(0, 4, 0, 4)
	inspScroll.BackgroundTransparency = 1
	inspScroll.ScrollBarThickness = 3
	inspScroll.CanvasSize = UDim2.new(0, 0, 0, 440)
	inspScroll.Parent = inspPanel

	-- Section: Transition Inspector
	local transTitle = Instance.new("TextLabel")
	transTitle.Text = "âš¡ TRANSITION INSPECTOR"
	transTitle.Size = UDim2.new(1, -12, 0, 20)
	transTitle.Position = UDim2.new(0, 6, 0, 4)
	transTitle.BackgroundTransparency = 1
	transTitle.TextColor3 = C_ACCENT
	transTitle.Font = Enum.Font.GothamBold
	transTitle.TextSize = 11
	transTitle.TextXAlignment = Enum.TextXAlignment.Left
	transTitle.Parent = inspScroll

	local transSubtitle = Instance.new("TextLabel")
	transSubtitle.Text = "Inspect blend & handoff between 2 layers"
	transSubtitle.Size = UDim2.new(1, -12, 0, 14)
	transSubtitle.Position = UDim2.new(0, 6, 0, 24)
	transSubtitle.BackgroundTransparency = 1
	transSubtitle.TextColor3 = C_TEXT_MUTED
	transSubtitle.Font = Enum.Font.Gotham
	transSubtitle.TextSize = 9
	transSubtitle.TextXAlignment = Enum.TextXAlignment.Left
	transSubtitle.Parent = inspScroll

	local transLayerABtn = Instance.new("TextButton")
	transLayerABtn.Text = "From: Layer 1"
	transLayerABtn.Size = UDim2.new(0.48, -2, 0, 24)
	transLayerABtn.Position = UDim2.new(0, 6, 0, 42)
	transLayerABtn.BackgroundColor3 = Color3.fromRGB(30, 36, 48)
	transLayerABtn.TextColor3 = C_TEXT
	transLayerABtn.Font = Enum.Font.GothamBold
	transLayerABtn.TextSize = 10
	transLayerABtn.Parent = inspScroll
	applyCorner(transLayerABtn, 4)
	applyStroke(transLayerABtn, C_BORDER, 1)

	local transLayerBBtn = Instance.new("TextButton")
	transLayerBBtn.Text = "To: Layer 2"
	transLayerBBtn.Size = UDim2.new(0.48, -2, 0, 24)
	transLayerBBtn.Position = UDim2.new(0.50, 4, 0, 42)
	transLayerBBtn.BackgroundColor3 = Color3.fromRGB(30, 36, 48)
	transLayerBBtn.TextColor3 = C_TEXT
	transLayerBBtn.Font = Enum.Font.GothamBold
	transLayerBBtn.TextSize = 10
	transLayerBBtn.Parent = inspScroll
	applyCorner(transLayerBBtn, 4)
	applyStroke(transLayerBBtn, C_BORDER, 1)

	local transBlendLabel = Instance.new("TextLabel")
	transBlendLabel.Text = string.format("Blend Crossfade: %.2fs (F%d)", transBlendTime, math.floor(transBlendTime * 30))
	transBlendLabel.Size = UDim2.new(1, -12, 0, 18)
	transBlendLabel.Position = UDim2.new(0, 6, 0, 70)
	transBlendLabel.BackgroundTransparency = 1
	transBlendLabel.TextColor3 = C_TEXT
	transBlendLabel.Font = Enum.Font.Gotham
	transBlendLabel.TextSize = 10
	transBlendLabel.TextXAlignment = Enum.TextXAlignment.Left
	transBlendLabel.Parent = inspScroll

	local transBlendMinus = Instance.new("TextButton")
	transBlendMinus.Text = "- 1F"
	transBlendMinus.Size = UDim2.new(0, 36, 0, 20)
	transBlendMinus.Position = UDim2.new(0, 6, 0, 90)
	transBlendMinus.BackgroundColor3 = Color3.fromRGB(40, 48, 64)
	transBlendMinus.TextColor3 = C_TEXT
	transBlendMinus.Font = Enum.Font.GothamBold
	transBlendMinus.TextSize = 10
	transBlendMinus.Parent = inspScroll
	applyCorner(transBlendMinus, 4)

	local transBlendPlus = Instance.new("TextButton")
	transBlendPlus.Text = "+ 1F"
	transBlendPlus.Size = UDim2.new(0, 36, 0, 20)
	transBlendPlus.Position = UDim2.new(0, 48, 0, 90)
	transBlendPlus.BackgroundColor3 = Color3.fromRGB(40, 48, 64)
	transBlendPlus.TextColor3 = C_TEXT
	transBlendPlus.Font = Enum.Font.GothamBold
	transBlendPlus.TextSize = 10
	transBlendPlus.Parent = inspScroll
	applyCorner(transBlendPlus, 4)

	local playTransitionBtn = Instance.new("TextButton")
	playTransitionBtn.Text = "âš¡ Play Transition Only"
	playTransitionBtn.Size = UDim2.new(1, -12, 0, 28)
	playTransitionBtn.Position = UDim2.new(0, 6, 0, 116)
	playTransitionBtn.BackgroundColor3 = Color3.fromRGB(35, 100, 150)
	playTransitionBtn.TextColor3 = Color3.fromRGB(240, 250, 255)
	playTransitionBtn.Font = Enum.Font.GothamBold
	playTransitionBtn.TextSize = 11
	playTransitionBtn.Parent = inspScroll
	applyCorner(playTransitionBtn, 6)

	-- Section: Presets
	local presetsDivider = Instance.new("Frame")
	presetsDivider.Size = UDim2.new(1, -12, 0, 1)
	presetsDivider.Position = UDim2.new(0, 6, 0, 154)
	presetsDivider.BackgroundColor3 = Color3.fromRGB(45, 52, 70)
	presetsDivider.BorderSizePixel = 0
	presetsDivider.Parent = inspScroll

	local presetsTitle = Instance.new("TextLabel")
	presetsTitle.Text = "âœ¨ QUICK PRESETS"
	presetsTitle.Size = UDim2.new(1, -12, 0, 20)
	presetsTitle.Position = UDim2.new(0, 6, 0, 160)
	presetsTitle.BackgroundTransparency = 1
	presetsTitle.TextColor3 = C_TEXT
	presetsTitle.Font = Enum.Font.GothamBold
	presetsTitle.TextSize = 11
	presetsTitle.TextXAlignment = Enum.TextXAlignment.Left
	presetsTitle.Parent = inspScroll

	local presetList = {
		{ name = "ðŸƒ Run + ðŸ‘Š Lead Punch", presetId = "RunPunch" },
		{ name = "ðŸ§˜ Idle + âš”ï¸ Ready Stance", presetId = "IdleStance" },
		{ name = "âš¡ Sprint + ðŸ”„ 180 Turn", presetId = "Sprint180" },
		{ name = "ðŸ¦¸ Superhero Landing", presetId = "SuperheroLanding" },
	}

	for pIdx, pData in ipairs(presetList) do
		local pBtn = Instance.new("TextButton")
		pBtn.Text = pData.name
		pBtn.Size = UDim2.new(1, -12, 0, 24)
		pBtn.Position = UDim2.new(0, 6, 0, 182 + (pIdx - 1) * 28)
		pBtn.BackgroundColor3 = Color3.fromRGB(30, 36, 48)
		pBtn.TextColor3 = C_TEXT
		pBtn.Font = Enum.Font.Gotham
		pBtn.TextSize = 10
		pBtn.Parent = inspScroll
		applyCorner(pBtn, 4)
		applyStroke(pBtn, C_BORDER, 1)

		pBtn.MouseButton1Click:Connect(function()
			if pData.presetId == "RunPunch" then
				combinatorLayers = {
					{
						id = "rbxassetid://109090784752055",
						name = "Movement.Run",
						enabled = true,
						muted = false,
						solo = false,
						startCut = 0.0,
						endCut = 0.467,
						weight = 1.0,
						speed = 1.0,
						priority = "Movement",
						bodyMask = "Lower Body",
						looped = true,
					},
					{
						id = "rbxassetid://113219639247452",
						name = "Attacks.Punch1",
						enabled = true,
						muted = false,
						solo = false,
						startCut = 0.0,
						endCut = 0.833,
						weight = 1.0,
						speed = 1.0,
						priority = "Action4",
						bodyMask = "Upper Body",
						looped = true,
					}
				}
			elseif pData.presetId == "IdleStance" then
				combinatorLayers = {
					{
						id = "rbxassetid://81038616654818",
						name = "IDLE_DEFAULT",
						enabled = true,
						muted = false,
						solo = false,
						startCut = 0.0,
						endCut = 4.0,
						weight = 0.6,
						speed = 1.0,
						priority = "Idle",
						bodyMask = "Full Body",
						looped = true,
					},
					{
						id = "rbxassetid://123350689285769",
						name = "IDLEREADY_STANCE",
						enabled = true,
						muted = false,
						solo = false,
						startCut = 0.0,
						endCut = 1.95,
						weight = 0.8,
						speed = 1.0,
						priority = "Action",
						bodyMask = "Upper Body",
						looped = true,
					}
				}
			elseif pData.presetId == "Sprint180" then
				combinatorLayers = {
					{
						id = "rbxassetid://109090784752055",
						name = "Movement.Run",
						enabled = true,
						muted = false,
						solo = false,
						startCut = 0.0,
						endCut = 0.467,
						weight = 0.5,
						speed = 1.0,
						priority = "Movement",
						bodyMask = "Full Body",
						looped = true,
					},
					{
						id = "rbxassetid://129355316172688",
						name = "RunTurn180",
						enabled = true,
						muted = false,
						solo = false,
						startCut = 0.0,
						endCut = 0.667,
						weight = 1.0,
						speed = 1.0,
						priority = "Action3",
						bodyMask = "Full Body",
						looped = true,
					}
				}
			elseif pData.presetId == "SuperheroLanding" then
				combinatorLayers = {
					{
						id = "rbxassetid://94804914683754",
						name = "SUPERHERO LANDING",
						enabled = true,
						muted = false,
						solo = false,
						startCut = 0.0,
						endCut = 0.883,
						weight = 1.0,
						speed = 1.0,
						priority = "Action4",
						bodyMask = "Full Body",
						looped = false,
					},
					{
						id = "rbxassetid://95406088712190",
						name = "GetUpBackFast",
						enabled = true,
						muted = false,
						solo = false,
						startCut = 0.0,
						endCut = 1.0,
						weight = 0.9,
						speed = 1.0,
						priority = "Action",
						bodyMask = "Full Body",
						looped = false,
					}
				}
			end
			updateGlobalDuration()
			refreshStackView()
		end)
	end

	-- Section: Export
	local exportDivider = Instance.new("Frame")
	exportDivider.Size = UDim2.new(1, -12, 0, 1)
	exportDivider.Position = UDim2.new(0, 6, 0, 304)
	exportDivider.BackgroundColor3 = Color3.fromRGB(45, 52, 70)
	exportDivider.BorderSizePixel = 0
	exportDivider.Parent = inspScroll

	local exportStackBtn = Instance.new("TextButton")
	exportStackBtn.Text = "ðŸ“‹ Export Stack to Luau"
	exportStackBtn.Size = UDim2.new(1, -12, 0, 30)
	exportStackBtn.Position = UDim2.new(0, 6, 0, 314)
	exportStackBtn.BackgroundColor3 = C_ACCENT
	exportStackBtn.TextColor3 = Color3.new(0, 0, 0)
	exportStackBtn.Font = Enum.Font.GothamBold
	exportStackBtn.TextSize = 11
	exportStackBtn.Parent = inspScroll
	applyCorner(exportStackBtn, 6)

	exportStackBtn.MouseButton1Click:Connect(function()
		local lines = {}
		table.insert(lines, "-- Generated Quin Animation Combinator Configuration")
		table.insert(lines, "-- Timestamp: " .. os.date("!%Y-%m-%dT%H:%M:%SZ"))
		table.insert(lines, "local CombinatorStack = {")
		table.insert(lines, string.format("\tDuration = %.3f,", combinatorGlobalDuration))
		table.insert(lines, "\tLayers = {")
		for i, l in ipairs(combinatorLayers) do
			table.insert(lines, string.format("\t\t[%d] = {", i))
			table.insert(lines, string.format("\t\t\tname = %q,", l.name))
			table.insert(lines, string.format("\t\t\tid = %q,", l.id))
			table.insert(lines, string.format("\t\t\tenabled = %s,", tostring(l.enabled)))
			table.insert(lines, string.format("\t\t\tstartCut = %.3f, -- Frame %d", l.startCut, math.floor(l.startCut * 30)))
			table.insert(lines, string.format("\t\t\tendCut = %.3f, -- Frame %d", l.endCut, math.floor(l.endCut * 30)))
			table.insert(lines, string.format("\t\t\tweight = %.2f,", l.weight))
			table.insert(lines, string.format("\t\t\tspeed = %.2f,", l.speed))
			table.insert(lines, string.format("\t\t\tpriority = %q,", l.priority))
			table.insert(lines, string.format("\t\t\tbodyMask = %q,", l.bodyMask))
			table.insert(lines, "\t\t},")
		end
		table.insert(lines, "\t}")
		table.insert(lines, "}")
		table.insert(lines, "return CombinatorStack")
		local luauCode = table.concat(lines, "\n")
		if showLuauExportModal then
			showLuauExportModal(luauCode, "  EXPORTED COMBINATOR STACK CONFIG (LUAU)")
		else
			print(luauCode)
		end
	end)

	----------------------------------------------------------------------------
	-- BOTTOM PANEL: GLOBAL TIMELINE SCRUBBER & MASTER TRANSPORT CONTROLS
	----------------------------------------------------------------------------
	-- Row 1: Readouts
	local timeReadout = Instance.new("TextLabel")
	timeReadout.Text = "â± Scrub: 0.00s / 2.00s"
	timeReadout.Size = UDim2.new(0, 180, 0, 18)
	timeReadout.Position = UDim2.new(0, 10, 0, 4)
	timeReadout.BackgroundTransparency = 1
	timeReadout.TextColor3 = C_ACCENT
	timeReadout.Font = Enum.Font.GothamBold
	timeReadout.TextSize = 11
	timeReadout.TextXAlignment = Enum.TextXAlignment.Left
	timeReadout.Parent = bottomPanel

	local frameReadout = Instance.new("TextLabel")
	frameReadout.Text = "ðŸŽž Frame: 0 / 60 (@ 30 FPS)"
	frameReadout.Size = UDim2.new(0, 200, 0, 18)
	frameReadout.Position = UDim2.new(0, 200, 0, 4)
	frameReadout.BackgroundTransparency = 1
	frameReadout.TextColor3 = C_TEXT
	frameReadout.Font = Enum.Font.Gotham
	frameReadout.TextSize = 10
	frameReadout.TextXAlignment = Enum.TextXAlignment.Left
	frameReadout.Parent = bottomPanel

	local statusReadout = Instance.new("TextLabel")
	statusReadout.Text = "Stack: Ready (0 Layers Active)"
	statusReadout.Size = UDim2.new(1, -420, 0, 18)
	statusReadout.Position = UDim2.new(0, 410, 0, 4)
	statusReadout.BackgroundTransparency = 1
	statusReadout.TextColor3 = C_TEXT_MUTED
	statusReadout.Font = Enum.Font.Gotham
	statusReadout.TextSize = 10
	statusReadout.TextXAlignment = Enum.TextXAlignment.Right
	statusReadout.Parent = bottomPanel

	-- Row 2: Draggable Timeline Scrubber Track
	local scrubTrack = Instance.new("Frame")
	scrubTrack.Name = "ScrubTrack"
	scrubTrack.Size = UDim2.new(1, -20, 0, 14)
	scrubTrack.Position = UDim2.new(0, 10, 0, 24)
	scrubTrack.BackgroundColor3 = Color3.fromRGB(35, 42, 58)
	scrubTrack.Parent = bottomPanel
	applyCorner(scrubTrack, 7)
	applyStroke(scrubTrack, Color3.fromRGB(55, 65, 88), 1)

	local scrubFill = Instance.new("Frame")
	scrubFill.Name = "ScrubFill"
	scrubFill.Size = UDim2.new(0, 0, 1, 0)
	scrubFill.BackgroundColor3 = C_ACCENT
	scrubFill.BorderSizePixel = 0
	scrubFill.Parent = scrubTrack
	applyCorner(scrubFill, 7)

	local scrubHead = Instance.new("Frame")
	scrubHead.Name = "ScrubHead"
	scrubHead.Size = UDim2.new(0, 16, 0, 16)
	scrubHead.AnchorPoint = Vector2.new(0.5, 0.5)
	scrubHead.Position = UDim2.new(0, 0, 0.5, 0)
	scrubHead.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	scrubHead.Parent = scrubTrack
	applyCorner(scrubHead, 8)
	applyStroke(scrubHead, C_ACCENT, 2)

	-- Row 3: Master Transport & Frame Stepping Controls
	local transportRow = Instance.new("Frame")
	transportRow.Size = UDim2.new(1, -20, 0, 32)
	transportRow.Position = UDim2.new(0, 10, 0, 50)
	transportRow.BackgroundTransparency = 1
	transportRow.Parent = bottomPanel

	local jumpStartBtn = Instance.new("TextButton")
	jumpStartBtn.Text = "â® Start"
	jumpStartBtn.Size = UDim2.new(0, 60, 0, 26)
	jumpStartBtn.Position = UDim2.new(0, 0, 0, 3)
	jumpStartBtn.BackgroundColor3 = Color3.fromRGB(38, 45, 60)
	jumpStartBtn.TextColor3 = C_TEXT
	jumpStartBtn.Font = Enum.Font.GothamBold
	jumpStartBtn.TextSize = 10
	jumpStartBtn.Parent = transportRow
	applyCorner(jumpStartBtn, 4)

	local stepBackBtn = Instance.new("TextButton")
	stepBackBtn.Text = "â—€ 1 Frame"
	stepBackBtn.Size = UDim2.new(0, 75, 0, 26)
	stepBackBtn.Position = UDim2.new(0, 66, 0, 3)
	stepBackBtn.BackgroundColor3 = Color3.fromRGB(38, 45, 60)
	stepBackBtn.TextColor3 = C_TEXT
	stepBackBtn.Font = Enum.Font.GothamBold
	stepBackBtn.TextSize = 10
	stepBackBtn.Parent = transportRow
	applyCorner(stepBackBtn, 4)

	local playPauseBtn = Instance.new("TextButton")
	playPauseBtn.Text = "â–¶ Play Stack"
	playPauseBtn.Size = UDim2.new(0, 110, 0, 26)
	playPauseBtn.Position = UDim2.new(0, 147, 0, 3)
	playPauseBtn.BackgroundColor3 = C_ACCENT
	playPauseBtn.TextColor3 = Color3.new(0, 0, 0)
	playPauseBtn.Font = Enum.Font.GothamBold
	playPauseBtn.TextSize = 11
	playPauseBtn.Parent = transportRow
	applyCorner(playPauseBtn, 4)

	local stepFwdBtn = Instance.new("TextButton")
	stepFwdBtn.Text = "â–¶ 1 Frame"
	stepFwdBtn.Size = UDim2.new(0, 75, 0, 26)
	stepFwdBtn.Position = UDim2.new(0, 263, 0, 3)
	stepFwdBtn.BackgroundColor3 = Color3.fromRGB(38, 45, 60)
	stepFwdBtn.TextColor3 = C_TEXT
	stepFwdBtn.Font = Enum.Font.GothamBold
	stepFwdBtn.TextSize = 10
	stepFwdBtn.Parent = transportRow
	applyCorner(stepFwdBtn, 4)

	local jumpEndBtn = Instance.new("TextButton")
	jumpEndBtn.Text = "â­ End"
	jumpEndBtn.Size = UDim2.new(0, 60, 0, 26)
	jumpEndBtn.Position = UDim2.new(0, 344, 0, 3)
	jumpEndBtn.BackgroundColor3 = Color3.fromRGB(38, 45, 60)
	jumpEndBtn.TextColor3 = C_TEXT
	jumpEndBtn.Font = Enum.Font.GothamBold
	jumpEndBtn.TextSize = 10
	jumpEndBtn.Parent = transportRow
	applyCorner(jumpEndBtn, 4)

	local loopBtn = Instance.new("TextButton")
	loopBtn.Text = "ðŸ”„ Loop: ON"
	loopBtn.Size = UDim2.new(0, 85, 0, 26)
	loopBtn.Position = UDim2.new(0, 410, 0, 3)
	loopBtn.BackgroundColor3 = Color3.fromRGB(30, 95, 65)
	loopBtn.TextColor3 = Color3.fromRGB(220, 255, 230)
	loopBtn.Font = Enum.Font.GothamBold
	loopBtn.TextSize = 10
	loopBtn.Parent = transportRow
	applyCorner(loopBtn, 4)

	local stopResetBtn = Instance.new("TextButton")
	stopResetBtn.Text = "â–  Reset Idle"
	stopResetBtn.Size = UDim2.new(0, 85, 0, 26)
	stopResetBtn.Position = UDim2.new(0, 501, 0, 3)
	stopResetBtn.BackgroundColor3 = Color3.fromRGB(65, 35, 40)
	stopResetBtn.TextColor3 = C_DANGER
	stopResetBtn.Font = Enum.Font.GothamBold
	stopResetBtn.TextSize = 10
	stopResetBtn.Parent = transportRow
	applyCorner(stopResetBtn, 4)

	-- Speed Selector Pills
	local speedPillsFrame = Instance.new("Frame")
	speedPillsFrame.Size = UDim2.new(0, 160, 0, 26)
	speedPillsFrame.Position = UDim2.new(1, -165, 0, 3)
	speedPillsFrame.BackgroundTransparency = 1
	speedPillsFrame.Parent = transportRow

	local speedOptions = {
		{ label = "0.25x", val = 0.25 },
		{ label = "0.5x",  val = 0.5 },
		{ label = "1.0x",  val = 1.0 },
		{ label = "1.5x",  val = 1.5 },
	}
	for sIdx, sOpt in ipairs(speedOptions) do
		local sBtn = Instance.new("TextButton")
		sBtn.Text = sOpt.label
		sBtn.Size = UDim2.new(0.24, -2, 1, 0)
		sBtn.Position = UDim2.new((sIdx - 1) * 0.25, 0, 0, 0)
		sBtn.BackgroundColor3 = (sOpt.val == combinatorPlaySpeed) and C_ACCENT or Color3.fromRGB(38, 44, 58)
		sBtn.TextColor3 = (sOpt.val == combinatorPlaySpeed) and Color3.new(0, 0, 0) or C_TEXT
		sBtn.Font = Enum.Font.GothamBold
		sBtn.TextSize = 9
		sBtn.Parent = speedPillsFrame
		applyCorner(sBtn, 4)

		sBtn.MouseButton1Click:Connect(function()
			combinatorPlaySpeed = sOpt.val
			for _, child in ipairs(speedPillsFrame:GetChildren()) do
				if child:IsA("TextButton") then
					local isActive = (child.Text == sOpt.label)
					child.BackgroundColor3 = isActive and C_ACCENT or Color3.fromRGB(38, 44, 58)
					child.TextColor3 = isActive and Color3.new(0, 0, 0) or C_TEXT
				end
			end
		end)
	end

	----------------------------------------------------------------------------
	-- CORE LOGIC & SYNC ENGINE
	----------------------------------------------------------------------------
	getActiveLayersPayload = function()
		local hasSolo = false
		for _, layer in ipairs(combinatorLayers) do
			if layer.solo then hasSolo = true break end
		end
		local list = {}
		for _, layer in ipairs(combinatorLayers) do
			local isMuted = layer.muted or (hasSolo and not layer.solo)
			local effWeight = isMuted and 0 or (layer.weight or 1.0)
			table.insert(list, {
				id = layer.id,
				name = layer.name,
				enabled = layer.enabled and not isMuted,
				muted = isMuted,
				weight = effWeight,
				speed = layer.speed or 1.0,
				startCut = layer.startCut or 0.0,
				endCut = layer.endCut or 2.0,
				priority = layer.priority or "Action4",
				bodyMask = layer.bodyMask or "Full Body",
				looped = layer.looped == true,
			})
		end
		return list
	end

	updateScrubberVisuals = function()
		local ratio = math.clamp(combinatorCurrentTime / math.max(0.01, combinatorGlobalDuration), 0, 1)
		scrubFill.Size = UDim2.new(ratio, 0, 1, 0)
		scrubHead.Position = UDim2.new(ratio, 0, 0.5, 0)
		timeReadout.Text = string.format("â± Scrub: %.2fs / %.2fs", combinatorCurrentTime, combinatorGlobalDuration)
		local curFrame = math.floor(combinatorCurrentTime * 30)
		local maxFrame = math.floor(combinatorGlobalDuration * 30)
		frameReadout.Text = string.format("ðŸŽž Frame: %d / %d (@ 30 FPS)", curFrame, maxFrame)

		local activeCount = 0
		for _, l in ipairs(combinatorLayers) do
			if l.enabled and not l.muted then activeCount = activeCount + 1 end
		end
		statusReadout.Text = string.format("Stack: %s (%d Layers Active)", combinatorIsPlaying and "Playing" or "Ready", activeCount)
	end

	updateGlobalDuration = function()
		local maxDur = 0.1
		for _, layer in ipairs(combinatorLayers) do
			if layer.enabled and not layer.muted then
				local d = math.max(0.05, ((layer.endCut or 2.0) - (layer.startCut or 0.0)) / math.max(0.1, layer.speed or 1.0))
				if d > maxDur then maxDur = d end
			end
		end
		combinatorGlobalDuration = math.max(0.5, maxDur)
		updateScrubberVisuals()
	end

	local lastScrubFire = 0
	syncScrubToServer = function(force)
		local now = os.clock()
		if not force and (now - lastScrubFire < 0.033) then return end
		lastScrubFire = now
		labEvent:FireServer("Combinator_Scrub", {
			targetName = testerName,
			scrubTime = combinatorCurrentTime,
			layers = getActiveLayersPayload(),
		})
	end

	triggerStackPlayback = function()
		combinatorIsPlaying = true
		playPauseBtn.Text = "â¸ Pause Stack"
		playPauseBtn.BackgroundColor3 = Color3.fromRGB(240, 175, 45)
		labEvent:FireServer("Combinator_PlayStack", {
			targetName = testerName,
			layers = getActiveLayersPayload(),
		})
		updateScrubberVisuals()
	end

	stopCombinatorPlayback = function()
		combinatorIsPlaying = false
		playPauseBtn.Text = "â–¶ Play Stack"
		playPauseBtn.BackgroundColor3 = C_ACCENT
		combinatorCurrentTime = 0.0
		if isTransitionTesting and transitionThread then
			task.cancel(transitionThread)
			isTransitionTesting = false
			playTransitionBtn.Text = "âš¡ Play Transition Only"
			playTransitionBtn.BackgroundColor3 = Color3.fromRGB(35, 100, 150)
		end
		updateScrubberVisuals()
		labEvent:FireServer("Combinator_Stop", { targetName = testerName })
	end

	-- Scrub track interaction
	local isScrubDragging = false
	scrubTrack.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			isScrubDragging = true
			if combinatorIsPlaying then
				combinatorIsPlaying = false
				playPauseBtn.Text = "â–¶ Play Stack"
				playPauseBtn.BackgroundColor3 = C_ACCENT
			end
			local r = math.clamp((input.Position.X - scrubTrack.AbsolutePosition.X) / math.max(1, scrubTrack.AbsoluteSize.X), 0, 1)
			combinatorCurrentTime = r * combinatorGlobalDuration
			updateScrubberVisuals()
			syncScrubToServer(true)
		end
	end)

	UserInputService.InputChanged:Connect(function(input)
		if isScrubDragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			local r = math.clamp((input.Position.X - scrubTrack.AbsolutePosition.X) / math.max(1, scrubTrack.AbsoluteSize.X), 0, 1)
			combinatorCurrentTime = r * combinatorGlobalDuration
			updateScrubberVisuals()
			syncScrubToServer(false)
		end
	end)

	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			if isScrubDragging then
				isScrubDragging = false
				syncScrubToServer(true)
			end
		end
	end)

	-- Transport Buttons Wireup
	jumpStartBtn.MouseButton1Click:Connect(function()
		combinatorCurrentTime = 0.0
		updateScrubberVisuals()
		syncScrubToServer(true)
	end)

	jumpEndBtn.MouseButton1Click:Connect(function()
		combinatorCurrentTime = combinatorGlobalDuration
		updateScrubberVisuals()
		syncScrubToServer(true)
	end)

	stepBackBtn.MouseButton1Click:Connect(function()
		combinatorCurrentTime = math.max(0, combinatorCurrentTime - (1 / 30))
		updateScrubberVisuals()
		syncScrubToServer(true)
	end)

	stepFwdBtn.MouseButton1Click:Connect(function()
		combinatorCurrentTime = math.min(combinatorGlobalDuration, combinatorCurrentTime + (1 / 30))
		updateScrubberVisuals()
		syncScrubToServer(true)
	end)

	playPauseBtn.MouseButton1Click:Connect(function()
		if combinatorIsPlaying then
			combinatorIsPlaying = false
			playPauseBtn.Text = "â–¶ Play Stack"
			playPauseBtn.BackgroundColor3 = C_ACCENT
			syncScrubToServer(true)
		else
			if combinatorCurrentTime >= combinatorGlobalDuration then
				combinatorCurrentTime = 0.0
			end
			triggerStackPlayback()
		end
	end)

	loopBtn.MouseButton1Click:Connect(function()
		combinatorLoop = not combinatorLoop
		loopBtn.Text = combinatorLoop and "ðŸ”„ Loop: ON" or "ðŸ”„ Loop: OFF"
		loopBtn.BackgroundColor3 = combinatorLoop and Color3.fromRGB(30, 95, 65) or Color3.fromRGB(48, 54, 66)
	end)

	stopResetBtn.MouseButton1Click:Connect(function()
		stopCombinatorPlayback()
	end)

	-- Heartbeat playback progression loop
	RunService.Heartbeat:Connect(function(dt)
		if combinatorIsPlaying and animCombinatorView.Visible then
			combinatorCurrentTime = combinatorCurrentTime + (dt * combinatorPlaySpeed)
			if combinatorCurrentTime >= combinatorGlobalDuration then
				if combinatorLoop then
					combinatorCurrentTime = 0.0
					triggerStackPlayback()
				else
					combinatorCurrentTime = combinatorGlobalDuration
					combinatorIsPlaying = false
					playPauseBtn.Text = "â–¶ Play Stack"
					playPauseBtn.BackgroundColor3 = C_ACCENT
				end
			end
			updateScrubberVisuals()
		end
	end)

	-- Transition Crossfade Inspector Wireup
	local function updateTransitionPickers()
		local count = #combinatorLayers
		if count == 0 then
			transLayerABtn.Text = "From: None"
			transLayerBBtn.Text = "To: None"
			return
		end
		if transLayerAIdx > count then transLayerAIdx = 1 end
		if transLayerBIdx > count then transLayerBIdx = math.min(2, count) end
		local lA = combinatorLayers[transLayerAIdx]
		local lB = combinatorLayers[transLayerBIdx]
		transLayerABtn.Text = string.format("From: L%d (%s)", transLayerAIdx, lA and lA.name:sub(1, 10) or "?")
		transLayerBBtn.Text = string.format("To: L%d (%s)", transLayerBIdx, lB and lB.name:sub(1, 10) or "?")
	end

	transLayerABtn.MouseButton1Click:Connect(function()
		if #combinatorLayers > 0 then
			transLayerAIdx = (transLayerAIdx % #combinatorLayers) + 1
			updateTransitionPickers()
		end
	end)

	transLayerBBtn.MouseButton1Click:Connect(function()
		if #combinatorLayers > 0 then
			transLayerBIdx = (transLayerBIdx % #combinatorLayers) + 1
			updateTransitionPickers()
		end
	end)

	transBlendMinus.MouseButton1Click:Connect(function()
		transBlendTime = math.clamp(transBlendTime - (1 / 30), 0.033, 0.60)
		transBlendLabel.Text = string.format("Blend Crossfade: %.2fs (F%d)", transBlendTime, math.floor(transBlendTime * 30))
	end)

	transBlendPlus.MouseButton1Click:Connect(function()
		transBlendTime = math.clamp(transBlendTime + (1 / 30), 0.033, 0.60)
		transBlendLabel.Text = string.format("Blend Crossfade: %.2fs (F%d)", transBlendTime, math.floor(transBlendTime * 30))
	end)

	playTransitionBtn.MouseButton1Click:Connect(function()
		if isTransitionTesting then
			if transitionThread then task.cancel(transitionThread) end
			isTransitionTesting = false
			playTransitionBtn.Text = "âš¡ Play Transition Only"
			playTransitionBtn.BackgroundColor3 = Color3.fromRGB(35, 100, 150)
			labEvent:FireServer("Combinator_Stop", { targetName = testerName })
			return
		end

		if #combinatorLayers < 2 then
			playTransitionBtn.Text = "âš ï¸ Need 2 Layers!"
			task.delay(1.2, function() playTransitionBtn.Text = "âš¡ Play Transition Only" end)
			return
		end

		isTransitionTesting = true
		playTransitionBtn.Text = "â¹ Stop Transition"
		playTransitionBtn.BackgroundColor3 = C_DANGER

		transitionThread = task.spawn(function()
			while isTransitionTesting do
				local layerA = combinatorLayers[transLayerAIdx]
				local layerB = combinatorLayers[transLayerBIdx]
				if not layerA or not layerB then break end

				-- Play Layer A
				labEvent:FireServer("PlayAnimation", {
					targetName = testerName,
					animId = layerA.id,
					speed = layerA.speed or 1.0,
					fadeTime = 0.05,
					priority = layerA.priority or "Action4",
					looped = false,
					startCut = layerA.startCut or 0.0,
					endCut = layerA.endCut,
				})
				local durA = math.max(0.1, ((layerA.endCut or 1.0) - (layerA.startCut or 0.0)) / math.max(0.1, layerA.speed or 1.0))
				local waitBeforeBlend = math.max(0.05, durA - transBlendTime)
				task.wait(waitBeforeBlend)
				if not isTransitionTesting then break end

				-- Crossfade to Layer B
				labEvent:FireServer("PlayAnimation", {
					targetName = testerName,
					animId = layerB.id,
					speed = layerB.speed or 1.0,
					fadeTime = transBlendTime,
					priority = layerB.priority or "Action4",
					looped = false,
					startCut = layerB.startCut or 0.0,
					endCut = layerB.endCut,
				})
				local durB = math.max(0.1, ((layerB.endCut or 1.0) - (layerB.startCut or 0.0)) / math.max(0.1, layerB.speed or 1.0))
				task.wait(durB + 0.3)
			end
			isTransitionTesting = false
			playTransitionBtn.Text = "âš¡ Play Transition Only"
			playTransitionBtn.BackgroundColor3 = Color3.fromRGB(35, 100, 150)
		end)
	end)

	----------------------------------------------------------------------------
	-- STACK VIEW RENDERING
	----------------------------------------------------------------------------
	refreshStackView = function()
		for _, child in ipairs(stackScroll:GetChildren()) do
			if child:IsA("Frame") and child ~= emptyStackNotice then
				child:Destroy()
			end
		end

		local count = #combinatorLayers
		stackCountBadge.Text = string.format("(%d Layers)", count)
		emptyStackNotice.Visible = (count == 0)
		updateTransitionPickers()

		local priorities = { "Action4", "Action3", "Action2", "Action", "Movement", "Idle" }
		local bodyMasks = { "Full Body", "Upper Body", "Lower Body", "Head Only" }

		for idx, layer in ipairs(combinatorLayers) do
			local card = Instance.new("Frame")
			card.Name = "LayerCard_" .. tostring(idx)
			card.Size = UDim2.new(1, -8, 0, 134)
			card.BackgroundColor3 = Color3.fromRGB(25, 30, 42)
			card.ClipsDescendants = true
			card.Parent = stackScroll
			applyCorner(card, 6)
			applyStroke(card, layer.enabled and Color3.fromRGB(50, 65, 90) or Color3.fromRGB(40, 45, 55), 1)

			-- Row 1: Header
			local header = Instance.new("Frame")
			header.Size = UDim2.new(1, -12, 0, 22)
			header.Position = UDim2.new(0, 6, 0, 4)
			header.BackgroundTransparency = 1
			header.Parent = card

			local title = Instance.new("TextLabel")
			title.Text = string.format("L%d: %s", idx, layer.name)
			title.Size = UDim2.new(1, -160, 1, 0)
			title.Position = UDim2.new(0, 0, 0, 0)
			title.BackgroundTransparency = 1
			title.TextColor3 = layer.enabled and C_ACCENT or C_TEXT_MUTED
			title.Font = Enum.Font.GothamBold
			title.TextSize = 11
			title.TextXAlignment = Enum.TextXAlignment.Left
			title.Parent = header

			-- Active Toggle [ðŸ‘]
			local eyeBtn = Instance.new("TextButton")
			eyeBtn.Text = layer.enabled and "ðŸ‘" or "âŠ˜"
			eyeBtn.Size = UDim2.new(0, 22, 0, 20)
			eyeBtn.Position = UDim2.new(1, -154, 0, 1)
			eyeBtn.BackgroundColor3 = layer.enabled and Color3.fromRGB(30, 80, 50) or Color3.fromRGB(45, 45, 55)
			eyeBtn.TextColor3 = layer.enabled and C_SUCCESS or C_TEXT_MUTED
			eyeBtn.Font = Enum.Font.GothamBold
			eyeBtn.TextSize = 10
			eyeBtn.Parent = header
			applyCorner(eyeBtn, 3)

			eyeBtn.MouseButton1Click:Connect(function()
				layer.enabled = not layer.enabled
				updateGlobalDuration()
				refreshStackView()
				if combinatorIsPlaying then triggerStackPlayback() end
			end)

			-- Mute Toggle [ðŸ”‡]
			local muteBtn = Instance.new("TextButton")
			muteBtn.Text = layer.muted and "ðŸ”‡" or "ðŸ”Š"
			muteBtn.Size = UDim2.new(0, 22, 0, 20)
			muteBtn.Position = UDim2.new(1, -128, 0, 1)
			muteBtn.BackgroundColor3 = layer.muted and Color3.fromRGB(80, 35, 40) or Color3.fromRGB(36, 42, 56)
			muteBtn.TextColor3 = layer.muted and C_DANGER or C_TEXT
			muteBtn.Font = Enum.Font.GothamBold
			muteBtn.TextSize = 10
			muteBtn.Parent = header
			applyCorner(muteBtn, 3)

			muteBtn.MouseButton1Click:Connect(function()
				layer.muted = not layer.muted
				updateGlobalDuration()
				refreshStackView()
				if combinatorIsPlaying then triggerStackPlayback() end
			end)

			-- Solo Toggle [S]
			local soloBtn = Instance.new("TextButton")
			soloBtn.Text = "S"
			soloBtn.Size = UDim2.new(0, 22, 0, 20)
			soloBtn.Position = UDim2.new(1, -102, 0, 1)
			soloBtn.BackgroundColor3 = layer.solo and Color3.fromRGB(180, 140, 20) or Color3.fromRGB(36, 42, 56)
			soloBtn.TextColor3 = layer.solo and Color3.new(0, 0, 0) or C_TEXT_MUTED
			soloBtn.Font = Enum.Font.GothamBold
			soloBtn.TextSize = 10
			soloBtn.Parent = header
			applyCorner(soloBtn, 3)

			soloBtn.MouseButton1Click:Connect(function()
				layer.solo = not layer.solo
				refreshStackView()
				if combinatorIsPlaying then triggerStackPlayback() end
			end)

			-- Move Up [â–²]
			local upBtn = Instance.new("TextButton")
			upBtn.Text = "â–²"
			upBtn.Size = UDim2.new(0, 20, 0, 20)
			upBtn.Position = UDim2.new(1, -76, 0, 1)
			upBtn.BackgroundColor3 = Color3.fromRGB(36, 42, 56)
			upBtn.TextColor3 = C_TEXT
			upBtn.Font = Enum.Font.GothamBold
			upBtn.TextSize = 9
			upBtn.Parent = header
			applyCorner(upBtn, 3)

			upBtn.MouseButton1Click:Connect(function()
				if idx > 1 then
					local temp = combinatorLayers[idx]
					combinatorLayers[idx] = combinatorLayers[idx - 1]
					combinatorLayers[idx - 1] = temp
					refreshStackView()
				end
			end)

			-- Move Down [â–¼]
			local downBtn = Instance.new("TextButton")
			downBtn.Text = "â–¼"
			downBtn.Size = UDim2.new(0, 20, 0, 20)
			downBtn.Position = UDim2.new(1, -52, 0, 1)
			downBtn.BackgroundColor3 = Color3.fromRGB(36, 42, 56)
			downBtn.TextColor3 = C_TEXT
			downBtn.Font = Enum.Font.GothamBold
			downBtn.TextSize = 9
			downBtn.Parent = header
			applyCorner(downBtn, 3)

			downBtn.MouseButton1Click:Connect(function()
				if idx < #combinatorLayers then
					local temp = combinatorLayers[idx]
					combinatorLayers[idx] = combinatorLayers[idx + 1]
					combinatorLayers[idx + 1] = temp
					refreshStackView()
				end
			end)

			-- Delete [âœ•]
			local delBtn = Instance.new("TextButton")
			delBtn.Text = "âœ•"
			delBtn.Size = UDim2.new(0, 24, 0, 20)
			delBtn.Position = UDim2.new(1, -28, 0, 1)
			delBtn.BackgroundColor3 = Color3.fromRGB(70, 30, 35)
			delBtn.TextColor3 = C_DANGER
			delBtn.Font = Enum.Font.GothamBold
			delBtn.TextSize = 10
			delBtn.Parent = header
			applyCorner(delBtn, 3)

			delBtn.MouseButton1Click:Connect(function()
				table.remove(combinatorLayers, idx)
				updateGlobalDuration()
				refreshStackView()
			end)

			-- Row 2: ID input box
			local idRow = Instance.new("Frame")
			idRow.Size = UDim2.new(1, -12, 0, 20)
			idRow.Position = UDim2.new(0, 6, 0, 28)
			idRow.BackgroundTransparency = 1
			idRow.Parent = card

			local idLabel = Instance.new("TextLabel")
			idLabel.Text = "ID:"
			idLabel.Size = UDim2.new(0, 24, 1, 0)
			idLabel.Position = UDim2.new(0, 0, 0, 0)
			idLabel.BackgroundTransparency = 1
			idLabel.TextColor3 = C_TEXT_MUTED
			idLabel.Font = Enum.Font.Gotham
			idLabel.TextSize = 10
			idLabel.Parent = idRow

			local cardIdBox = Instance.new("TextBox")
			cardIdBox.Size = UDim2.new(1, -30, 1, 0)
			cardIdBox.Position = UDim2.new(0, 26, 0, 0)
			cardIdBox.BackgroundColor3 = Color3.fromRGB(32, 38, 52)
			cardIdBox.TextColor3 = C_TEXT
			cardIdBox.Font = Enum.Font.Code
			cardIdBox.TextSize = 10
			cardIdBox.TextXAlignment = Enum.TextXAlignment.Left
			cardIdBox.ClearTextOnFocus = false
			cardIdBox.Text = layer.id or ""
			cardIdBox.Parent = idRow
			applyCorner(cardIdBox, 3)

			cardIdBox.FocusLost:Connect(function()
				layer.id = cardIdBox.Text
			end)

			-- Row 3: Trimming Sliders (Start Cut & End Cut)
			local trimRow = Instance.new("Frame")
			trimRow.Size = UDim2.new(1, -12, 0, 24)
			trimRow.Position = UDim2.new(0, 6, 0, 52)
			trimRow.BackgroundTransparency = 1
			trimRow.Parent = card

			-- Start Cut
			local startCutLabel = Instance.new("TextLabel")
			startCutLabel.Text = string.format("Start: %.2fs (F%d)", layer.startCut or 0.0, math.floor((layer.startCut or 0.0) * 30))
			startCutLabel.Size = UDim2.new(0.35, 0, 1, 0)
			startCutLabel.Position = UDim2.new(0, 0, 0, 0)
			startCutLabel.BackgroundTransparency = 1
			startCutLabel.TextColor3 = C_TEXT
			startCutLabel.Font = Enum.Font.Gotham
			startCutLabel.TextSize = 9
			startCutLabel.TextXAlignment = Enum.TextXAlignment.Left
			startCutLabel.Parent = trimRow

			local startMinus = Instance.new("TextButton")
			startMinus.Text = "-"
			startMinus.Size = UDim2.new(0, 18, 0, 18)
			startMinus.Position = UDim2.new(0.35, 2, 0, 3)
			startMinus.BackgroundColor3 = Color3.fromRGB(40, 48, 64)
			startMinus.TextColor3 = C_TEXT
			startMinus.Font = Enum.Font.GothamBold
			startMinus.TextSize = 10
			startMinus.Parent = trimRow
			applyCorner(startMinus, 3)

			local startPlus = Instance.new("TextButton")
			startPlus.Text = "+"
			startPlus.Size = UDim2.new(0, 18, 0, 18)
			startPlus.Position = UDim2.new(0.35, 22, 0, 3)
			startPlus.BackgroundColor3 = Color3.fromRGB(40, 48, 64)
			startPlus.TextColor3 = C_TEXT
			startPlus.Font = Enum.Font.GothamBold
			startPlus.TextSize = 10
			startPlus.Parent = trimRow
			applyCorner(startPlus, 3)

			startMinus.MouseButton1Click:Connect(function()
				layer.startCut = math.max(0, (layer.startCut or 0.0) - (1 / 30))
				startCutLabel.Text = string.format("Start: %.2fs (F%d)", layer.startCut, math.floor(layer.startCut * 30))
				updateGlobalDuration()
			end)
			startPlus.MouseButton1Click:Connect(function()
				layer.startCut = math.min((layer.endCut or 2.0) - 0.033, (layer.startCut or 0.0) + (1 / 30))
				startCutLabel.Text = string.format("Start: %.2fs (F%d)", layer.startCut, math.floor(layer.startCut * 30))
				updateGlobalDuration()
			end)

			-- End Cut
			local endCutLabel = Instance.new("TextLabel")
			endCutLabel.Text = string.format("End: %.2fs (F%d)", layer.endCut or 2.0, math.floor((layer.endCut or 2.0) * 30))
			endCutLabel.Size = UDim2.new(0.35, 0, 1, 0)
			endCutLabel.Position = UDim2.new(0.52, 0, 0, 0)
			endCutLabel.BackgroundTransparency = 1
			endCutLabel.TextColor3 = C_TEXT
			endCutLabel.Font = Enum.Font.Gotham
			endCutLabel.TextSize = 9
			endCutLabel.TextXAlignment = Enum.TextXAlignment.Left
			endCutLabel.Parent = trimRow

			local endMinus = Instance.new("TextButton")
			endMinus.Text = "-"
			endMinus.Size = UDim2.new(0, 18, 0, 18)
			endMinus.Position = UDim2.new(0.87, 0, 0, 3)
			endMinus.BackgroundColor3 = Color3.fromRGB(40, 48, 64)
			endMinus.TextColor3 = C_TEXT
			endMinus.Font = Enum.Font.GothamBold
			endMinus.TextSize = 10
			endMinus.Parent = trimRow
			applyCorner(endMinus, 3)

			local endPlus = Instance.new("TextButton")
			endPlus.Text = "+"
			endPlus.Size = UDim2.new(0, 18, 0, 18)
			endPlus.Position = UDim2.new(0.87, 20, 0, 3)
			endPlus.BackgroundColor3 = Color3.fromRGB(40, 48, 64)
			endPlus.TextColor3 = C_TEXT
			endPlus.Font = Enum.Font.GothamBold
			endPlus.TextSize = 10
			endPlus.Parent = trimRow
			applyCorner(endPlus, 3)

			endMinus.MouseButton1Click:Connect(function()
				layer.endCut = math.max((layer.startCut or 0.0) + 0.033, (layer.endCut or 2.0) - (1 / 30))
				endCutLabel.Text = string.format("End: %.2fs (F%d)", layer.endCut, math.floor(layer.endCut * 30))
				updateGlobalDuration()
			end)
			endPlus.MouseButton1Click:Connect(function()
				layer.endCut = (layer.endCut or 2.0) + (1 / 30)
				endCutLabel.Text = string.format("End: %.2fs (F%d)", layer.endCut, math.floor(layer.endCut * 30))
				updateGlobalDuration()
			end)

			-- Row 4: Weight & Speed
			local wsRow = Instance.new("Frame")
			wsRow.Size = UDim2.new(1, -12, 0, 22)
			wsRow.Position = UDim2.new(0, 6, 0, 80)
			wsRow.BackgroundTransparency = 1
			wsRow.Parent = card

			local wLabel = Instance.new("TextLabel")
			wLabel.Text = string.format("Weight: %.2f", layer.weight or 1.0)
			wLabel.Size = UDim2.new(0.35, 0, 1, 0)
			wLabel.Position = UDim2.new(0, 0, 0, 0)
			wLabel.BackgroundTransparency = 1
			wLabel.TextColor3 = C_TEXT_MUTED
			wLabel.Font = Enum.Font.Gotham
			wLabel.TextSize = 9
			wLabel.TextXAlignment = Enum.TextXAlignment.Left
			wLabel.Parent = wsRow

			local wMinus = Instance.new("TextButton")
			wMinus.Text = "-"
			wMinus.Size = UDim2.new(0, 18, 0, 18)
			wMinus.Position = UDim2.new(0.35, 2, 0, 2)
			wMinus.BackgroundColor3 = Color3.fromRGB(40, 48, 64)
			wMinus.TextColor3 = C_TEXT
			wMinus.Font = Enum.Font.GothamBold
			wMinus.TextSize = 10
			wMinus.Parent = wsRow
			applyCorner(wMinus, 3)

			local wPlus = Instance.new("TextButton")
			wPlus.Text = "+"
			wPlus.Size = UDim2.new(0, 18, 0, 18)
			wPlus.Position = UDim2.new(0.35, 22, 0, 2)
			wPlus.BackgroundColor3 = Color3.fromRGB(40, 48, 64)
			wPlus.TextColor3 = C_TEXT
			wPlus.Font = Enum.Font.GothamBold
			wPlus.TextSize = 10
			wPlus.Parent = wsRow
			applyCorner(wPlus, 3)

			wMinus.MouseButton1Click:Connect(function()
				layer.weight = math.clamp((layer.weight or 1.0) - 0.1, 0.0, 1.0)
				wLabel.Text = string.format("Weight: %.2f", layer.weight)
			end)
			wPlus.MouseButton1Click:Connect(function()
				layer.weight = math.clamp((layer.weight or 1.0) + 0.1, 0.0, 1.0)
				wLabel.Text = string.format("Weight: %.2f", layer.weight)
			end)

			local sLabel = Instance.new("TextLabel")
			sLabel.Text = string.format("Speed: %.2fx", layer.speed or 1.0)
			sLabel.Size = UDim2.new(0.35, 0, 1, 0)
			sLabel.Position = UDim2.new(0.52, 0, 0, 0)
			sLabel.BackgroundTransparency = 1
			sLabel.TextColor3 = C_TEXT_MUTED
			sLabel.Font = Enum.Font.Gotham
			sLabel.TextSize = 9
			sLabel.TextXAlignment = Enum.TextXAlignment.Left
			sLabel.Parent = wsRow

			local sMinus = Instance.new("TextButton")
			sMinus.Text = "-"
			sMinus.Size = UDim2.new(0, 18, 0, 18)
			sMinus.Position = UDim2.new(0.87, 0, 0, 2)
			sMinus.BackgroundColor3 = Color3.fromRGB(40, 48, 64)
			sMinus.TextColor3 = C_TEXT
			sMinus.Font = Enum.Font.GothamBold
			sMinus.TextSize = 10
			sMinus.Parent = wsRow
			applyCorner(sMinus, 3)

			local sPlus = Instance.new("TextButton")
			sPlus.Text = "+"
			sPlus.Size = UDim2.new(0, 18, 0, 18)
			sPlus.Position = UDim2.new(0.87, 20, 0, 2)
			sPlus.BackgroundColor3 = Color3.fromRGB(40, 48, 64)
			sPlus.TextColor3 = C_TEXT
			sPlus.Font = Enum.Font.GothamBold
			sPlus.TextSize = 10
			sPlus.Parent = wsRow
			applyCorner(sPlus, 3)

			sMinus.MouseButton1Click:Connect(function()
				layer.speed = math.clamp((layer.speed or 1.0) - 0.1, 0.1, 3.0)
				sLabel.Text = string.format("Speed: %.2fx", layer.speed)
				updateGlobalDuration()
			end)
			sPlus.MouseButton1Click:Connect(function()
				layer.speed = math.clamp((layer.speed or 1.0) + 0.1, 0.1, 3.0)
				sLabel.Text = string.format("Speed: %.2fx", layer.speed)
				updateGlobalDuration()
			end)

			-- Row 5: Priority & Body Mask Selectors
			local metaRow = Instance.new("Frame")
			metaRow.Size = UDim2.new(1, -12, 0, 22)
			metaRow.Position = UDim2.new(0, 6, 0, 106)
			metaRow.BackgroundTransparency = 1
			metaRow.Parent = card

			local pBtn = Instance.new("TextButton")
			pBtn.Text = "Prio: " .. (layer.priority or "Action4")
			pBtn.Size = UDim2.new(0.48, -2, 1, 0)
			pBtn.Position = UDim2.new(0, 0, 0, 0)
			pBtn.BackgroundColor3 = Color3.fromRGB(36, 42, 58)
			pBtn.TextColor3 = Color3.fromRGB(200, 230, 255)
			pBtn.Font = Enum.Font.GothamBold
			pBtn.TextSize = 9
			pBtn.Parent = metaRow
			applyCorner(pBtn, 3)

			pBtn.MouseButton1Click:Connect(function()
				local cur = layer.priority or "Action4"
				local nextIdx = 1
				for pI, pVal in ipairs(priorities) do
					if pVal == cur then nextIdx = (pI % #priorities) + 1 break end
				end
				layer.priority = priorities[nextIdx]
				pBtn.Text = "Prio: " .. layer.priority
			end)

			local mBtn = Instance.new("TextButton")
			mBtn.Text = "Mask: " .. (layer.bodyMask or "Full Body")
			mBtn.Size = UDim2.new(0.48, -2, 1, 0)
			mBtn.Position = UDim2.new(0.50, 4, 0, 0)
			mBtn.BackgroundColor3 = Color3.fromRGB(36, 42, 58)
			mBtn.TextColor3 = Color3.fromRGB(240, 220, 170)
			mBtn.Font = Enum.Font.GothamBold
			mBtn.TextSize = 9
			mBtn.Parent = metaRow
			applyCorner(mBtn, 3)

			mBtn.MouseButton1Click:Connect(function()
				local cur = layer.bodyMask or "Full Body"
				local nextIdx = 1
				for mI, mVal in ipairs(bodyMasks) do
					if mVal == cur then nextIdx = (mI % #bodyMasks) + 1 break end
				end
				layer.bodyMask = bodyMasks[nextIdx]
				mBtn.Text = "Mask: " .. layer.bodyMask
			end)
		end
	end

	-- Add Blank Layer
	addEmptyLayerBtn.MouseButton1Click:Connect(function()
		table.insert(combinatorLayers, {
			id = "rbxassetid://109837817595150",
			name = "CustomLayer_" .. tostring(#combinatorLayers + 1),
			enabled = true,
			muted = false,
			solo = false,
			startCut = 0.0,
			endCut = 2.0,
			weight = 1.0,
			speed = 1.0,
			priority = "Action4",
			bodyMask = "Full Body",
			looped = true,
		})
		updateGlobalDuration()
		refreshStackView()
	end)

	-- Clear Stack
	clearStackBtn.MouseButton1Click:Connect(function()
		combinatorLayers = {}
		stopCombinatorPlayback()
		updateGlobalDuration()
		refreshStackView()
	end)

	----------------------------------------------------------------------------
	-- DIRECT ID INSERTER & LIBRARY ACTIONS
	----------------------------------------------------------------------------
	previewIdBtn.MouseButton1Click:Connect(function()
		local rawDigits = string.match(directIdBox.Text, "%d+")
		if rawDigits then
			local id = "rbxassetid://" .. rawDigits
			labEvent:FireServer("PlayAnimation", {
				targetName = testerName,
				animId = id,
				speed = 1.0,
				fadeTime = 0.05,
				priority = "Action4",
				looped = true,
			})
		else
			directIdBox.PlaceholderText = "âš ï¸ Please paste a valid numeric ID!"
		end
	end)

	addIdBtn.MouseButton1Click:Connect(function()
		local rawDigits = string.match(directIdBox.Text, "%d+")
		if rawDigits then
			local id = "rbxassetid://" .. rawDigits
			local name = "Clip_" .. rawDigits:sub(-4)
			table.insert(combinatorLayers, {
				id = id,
				name = name,
				enabled = true,
				muted = false,
				solo = false,
				startCut = 0.0,
				endCut = 2.0,
				weight = 1.0,
				speed = 1.0,
				priority = "Action4",
				bodyMask = "Full Body",
				looped = true,
			})
			directIdBox.Text = ""
			updateGlobalDuration()
			refreshStackView()
		else
			directIdBox.PlaceholderText = "âš ï¸ Enter ID first!"
		end
	end)

	-- Populate Pre-Registered Library
	local combCurrentCat = "All"
	local function populateLibraryList(cat, query)
		for _, child in ipairs(libScroll:GetChildren()) do
			if child:IsA("Frame") or child:IsA("TextLabel") then child:Destroy() end
		end

		local allPaths = AnimationConfig.getAllPaths()
		local q = query and string.lower(string.gsub(query, "^%s*(.-)%s*$", "%1")) or ""
		local isSearching = (#q > 0)
		local count = 0

		for _, item in ipairs(allPaths) do
			local match = false
			if isSearching then
				local nLower = string.lower(item.name or "")
				local pLower = string.lower(item.path or "")
				local cLower = string.lower(item.category or "")
				if nLower:find(q, 1, true) or pLower:find(q, 1, true) or cLower:find(q, 1, true) then
					match = true
				end
			else
				if cat == "All" then
					match = true
				elseif cat == "Custom" then
					match = item.category:find("Custom") ~= nil
				else
					match = item.category:find(cat) ~= nil or item.path:find(cat) ~= nil
				end
			end

			if match then
				count = count + 1
				local row = Instance.new("Frame")
				row.Size = UDim2.new(1, -6, 0, 26)
				row.BackgroundColor3 = Color3.fromRGB(28, 34, 46)
				row.Parent = libScroll
				applyCorner(row, 4)

				local label = Instance.new("TextLabel")
				label.Text = item.name
				label.Size = UDim2.new(1, -64, 1, 0)
				label.Position = UDim2.new(0, 6, 0, 0)
				label.BackgroundTransparency = 1
				label.TextColor3 = C_TEXT
				label.Font = Enum.Font.Gotham
				label.TextSize = 10
				label.TextXAlignment = Enum.TextXAlignment.Left
				label.Parent = row
				local auditionBtn = Instance.new("TextButton")
				auditionBtn.Text = "â–¶"
				auditionBtn.Size = UDim2.new(0, 24, 0, 20)
				auditionBtn.Position = UDim2.new(1, -54, 0, 3)
				auditionBtn.BackgroundColor3 = Color3.fromRGB(40, 80, 120)
				auditionBtn.TextColor3 = Color3.fromRGB(220, 245, 255)
				auditionBtn.Font = Enum.Font.GothamBold
				auditionBtn.TextSize = 10
				auditionBtn.Parent = row
				applyCorner(auditionBtn, 3)

				auditionBtn.MouseButton1Click:Connect(function()
					local entry = item.entry or AnimationConfig.get(item.path) or {}
					if entry.id then
						labEvent:FireServer("PlayAnimation", {
							targetName = testerName,
							animId = entry.id,
							speed = entry.speed or 1.0,
							fadeTime = 0.05,
							priority = entry.priority or "Action4",
							looped = true,
						})
					end
				end)

				local addBtn = Instance.new("TextButton")
				addBtn.Text = "+"
				addBtn.Size = UDim2.new(0, 24, 0, 20)
				addBtn.Position = UDim2.new(1, -26, 0, 3)
				addBtn.BackgroundColor3 = C_ACCENT
				addBtn.TextColor3 = Color3.new(0, 0, 0)
				addBtn.Font = Enum.Font.GothamBold
				addBtn.TextSize = 12
				addBtn.Parent = row
				applyCorner(addBtn, 3)

				addBtn.MouseButton1Click:Connect(function()
					local entry = item.entry or AnimationConfig.get(item.path) or {}
					local animId = entry.id or ""
					local startCut = entry.startCut or 0.0
					local endCut = entry.endCut or 2.0
					if endCut <= 0 then endCut = 2.0 end
					table.insert(combinatorLayers, {
						id = animId,
						name = item.name or item.path,
						enabled = true,
						muted = false,
						solo = false,
						startCut = startCut,
						endCut = endCut,
						weight = 1.0,
						speed = entry.speed or 1.0,
						priority = entry.priority or "Action4",
						bodyMask = "Full Body",
						looped = true,
					})
					updateGlobalDuration()
					refreshStackView()
				end)
			end
		end

		if count == 0 then
			local noRes = Instance.new("TextLabel")
			noRes.Text = isSearching and ("No matches for '" .. q .. "'") or "No clips in category."
			noRes.Size = UDim2.new(1, -10, 0, 30)
			noRes.BackgroundTransparency = 1
			noRes.TextColor3 = C_TEXT_MUTED
			noRes.Font = Enum.Font.Gotham
			noRes.TextSize = 10
			noRes.Parent = libScroll
		end
	end

	-- Categories setup
	local libCategories = { "All", "Attacks", "Idles", "Movement", "Parkour", "Reactions", "Strafe", "Custom" }
	for _, cat in ipairs(libCategories) do
		local cBtn = Instance.new("TextButton")
		cBtn.Text = cat
		cBtn.Size = UDim2.new(0, math.max(50, #cat * 8 + 14), 1, 0)
		cBtn.BackgroundColor3 = (cat == combCurrentCat) and C_ACCENT or Color3.fromRGB(35, 42, 56)
		cBtn.TextColor3 = (cat == combCurrentCat) and Color3.new(0, 0, 0) or C_TEXT
		cBtn.Font = Enum.Font.GothamBold
		cBtn.TextSize = 10
		cBtn.Parent = combCatTabBar
		applyCorner(cBtn, 4)

		cBtn.MouseButton1Click:Connect(function()
			combCurrentCat = cat
			combSearchBox.Text = ""
			for _, b in ipairs(combCatTabBar:GetChildren()) do
				if b:IsA("TextButton") then
					local isActive = (b.Text == cat)
					b.BackgroundColor3 = isActive and C_ACCENT or Color3.fromRGB(35, 42, 56)
					b.TextColor3 = isActive and Color3.new(0, 0, 0) or C_TEXT
				end
			end
			populateLibraryList(cat, "")
		end)
	end

	combSearchBox:GetPropertyChangedSignal("Text"):Connect(function()
		populateLibraryList(combCurrentCat, combSearchBox.Text)
	end)

	-- Initial populate
	populateLibraryList("All", "")
	refreshStackView()
	updateGlobalDuration()
end

-- Forward declarations for controls referenced across tabs & Section 9 event listeners
local walkStrideSlider, runStrideSlider, maxRollSlider, bankRespSlider
local isFootIKActive = false
local ikToggleBtn
local rayDistSlider, heightOffsetSlider, maxStepDownSlider, hipsDipSlider
local isAnkleAlign = true
local ankleBtn
local isLedgeGrip = true
local ledgeBtn
local muscleStiffSlider, dampingSlider, tumbleScaleSlider, groundFrictionSlider, recoveryDelaySlider
isContinuousRagdoll = false
local toggleContinuousRagBtn
local createModeCard

--------------------------------------------------------------------------------
-- 4B. SUB-TAB 2: CONTINUOUS LOCOMOTION & PROCEDURAL FOOT IK
--------------------------------------------------------------------------------
do
-- Left Card: Continuous Locomotion Tuning
local locoCard = Instance.new("ScrollingFrame")
locoCard.Size = UDim2.new(0, 460, 1, -12)
locoCard.Position = UDim2.new(0, 10, 0, 6)
locoCard.BackgroundColor3 = C_PANEL
locoCard.ClipsDescendants = true
locoCard.ScrollBarThickness = 4
locoCard.CanvasSize = UDim2.new(0, 0, 0, 480)
locoCard.Parent = locoIkView
applyCorner(locoCard, 8)
applyStroke(locoCard, C_BORDER, 1)

local locoTitle = Instance.new("TextLabel")
locoTitle.Text = "ðŸƒ CONTINUOUS LOCOMOTION TUNING"
locoTitle.Size = UDim2.new(1, -20, 0, 22)
locoTitle.Position = UDim2.new(0, 10, 0, 8)
locoTitle.BackgroundTransparency = 1
locoTitle.TextColor3 = C_TEXT
locoTitle.Font = Enum.Font.GothamBold
locoTitle.TextSize = 12
locoTitle.TextXAlignment = Enum.TextXAlignment.Left
locoTitle.Parent = locoCard

local locoSub = Instance.new("TextLabel")
locoSub.Text = "Synchronized stride scaling & centripetal torso roll banking into turns."
locoSub.Size = UDim2.new(1, -20, 0, 16)
locoSub.Position = UDim2.new(0, 10, 0, 28)
locoSub.BackgroundTransparency = 1
locoSub.TextColor3 = C_TEXT_MUTED
locoSub.Font = Enum.Font.Gotham
locoSub.TextSize = 10
locoSub.TextXAlignment = Enum.TextXAlignment.Left
locoSub.Parent = locoCard

walkStrideSlider = createPrecisionSlider(locoCard, 50, "Walk Stride Base (Studs/s)", 8.0, 32.0, CombatConfig.WalkStrideBase or 16.0, 0.5, "%.1f studs/s", function(v)
	CombatConfig.WalkStrideBase = v
	labEvent:FireServer("UpdateLocomotionConfig", { key = "WalkStrideBase", value = v })
end)

runStrideSlider = createPrecisionSlider(locoCard, 96, "Run Stride Base (Studs/s)", 20.0, 60.0, CombatConfig.RunStrideBase or 38.0, 1.0, "%.1f studs/s", function(v)
	CombatConfig.RunStrideBase = v
	labEvent:FireServer("UpdateLocomotionConfig", { key = "RunStrideBase", value = v })
end)

maxRollSlider = createPrecisionSlider(locoCard, 142, "Torso Banking Max Roll", 0.0, 35.0, CombatConfig.TorsoBankingMaxRoll or 12.0, 1.0, "%.1fÂ°", function(v)
	CombatConfig.TorsoBankingMaxRoll = v
	labEvent:FireServer("UpdateLocomotionConfig", { key = "TorsoBankingMaxRoll", value = v })
end)

bankRespSlider = createPrecisionSlider(locoCard, 188, "Banking Responsiveness", 2.0, 25.0, CombatConfig.TorsoBankingResponsiveness or 10.0, 0.5, "%.1f", function(v)
	CombatConfig.TorsoBankingResponsiveness = v
	labEvent:FireServer("UpdateLocomotionConfig", { key = "TorsoBankingResponsiveness", value = v })
end)

local locoTelemetryBox = Instance.new("Frame")
locoTelemetryBox.Size = UDim2.new(1, -20, 0, 120)
locoTelemetryBox.Position = UDim2.new(0, 10, 0, 240)
locoTelemetryBox.BackgroundColor3 = Color3.fromRGB(20, 24, 34)
locoTelemetryBox.Parent = locoCard
applyCorner(locoTelemetryBox, 6)
applyStroke(locoTelemetryBox, Color3.fromRGB(45, 55, 75), 1)

local locoTelemetryLabel = Instance.new("TextLabel")
locoTelemetryLabel.Size = UDim2.new(1, -16, 1, -12)
locoTelemetryLabel.Position = UDim2.new(0, 8, 0, 6)
locoTelemetryLabel.BackgroundTransparency = 1
locoTelemetryLabel.TextColor3 = Color3.fromRGB(150, 220, 255)
locoTelemetryLabel.Font = Enum.Font.Code
locoTelemetryLabel.TextSize = 10
locoTelemetryLabel.TextXAlignment = Enum.TextXAlignment.Left
locoTelemetryLabel.TextYAlignment = Enum.TextYAlignment.Top
locoTelemetryLabel.Text = "Locomotion Telemetry: Connecting to QuinA_Tester..."
locoTelemetryLabel.Parent = locoTelemetryBox

-- Right Card: Procedural Foot IK
local ikCard = Instance.new("ScrollingFrame")
ikCard.Size = UDim2.new(0, 470, 1, -12)
ikCard.Position = UDim2.new(0, 480, 0, 6)
ikCard.BackgroundColor3 = C_PANEL
ikCard.ClipsDescendants = true
ikCard.ScrollBarThickness = 4
ikCard.CanvasSize = UDim2.new(0, 0, 0, 520)
ikCard.Parent = locoIkView
applyCorner(ikCard, 8)
applyStroke(ikCard, C_BORDER, 1)

local ikTitle = Instance.new("TextLabel")
ikTitle.Text = "ðŸ¦¶ PROCEDURAL FOOT IK (IKControl)"
ikTitle.Size = UDim2.new(1, -20, 0, 22)
ikTitle.Position = UDim2.new(0, 10, 0, 8)
ikTitle.BackgroundTransparency = 1
ikTitle.TextColor3 = C_TEXT
ikTitle.Font = Enum.Font.GothamBold
ikTitle.TextSize = 12
ikTitle.TextXAlignment = Enum.TextXAlignment.Left
ikTitle.Parent = ikCard

local ikSub = Instance.new("TextLabel")
ikSub.Text = "Two-bone raycast floor conformer on mixamorig:LeftLeg & RightLeg."
ikSub.Size = UDim2.new(1, -20, 0, 16)
ikSub.Position = UDim2.new(0, 10, 0, 28)
ikSub.BackgroundTransparency = 1
ikSub.TextColor3 = C_TEXT_MUTED
ikSub.Font = Enum.Font.Gotham
ikSub.TextSize = 10
ikSub.TextXAlignment = Enum.TextXAlignment.Left
ikSub.Parent = ikCard

isFootIKActive = (CombatConfig.FootIK_Enabled ~= false)

ikToggleBtn = Instance.new("TextButton")
ikToggleBtn.Size = UDim2.new(1, -20, 0, 32)
ikToggleBtn.Position = UDim2.new(0, 10, 0, 52)
ikToggleBtn.BackgroundColor3 = isFootIKActive and C_SUCCESS or Color3.fromRGB(48, 56, 74)
ikToggleBtn.TextColor3 = isFootIKActive and Color3.new(0, 0, 0) or C_TEXT
ikToggleBtn.Font = Enum.Font.GothamBold
ikToggleBtn.TextSize = 11
ikToggleBtn.Text = isFootIKActive and "Foot IK: ACTIVE (Conforming to Terrain)" or "Foot IK: OFF (Canned Poses Only)"
ikToggleBtn.Parent = ikCard
applyCorner(ikToggleBtn, 6)

ikToggleBtn.MouseButton1Click:Connect(function()
	isFootIKActive = not isFootIKActive
	CombatConfig.FootIK_Enabled = isFootIKActive
	ikToggleBtn.Text = isFootIKActive and "Foot IK: ACTIVE (Conforming to Terrain)" or "Foot IK: OFF (Canned Poses Only)"
	ikToggleBtn.BackgroundColor3 = isFootIKActive and C_SUCCESS or Color3.fromRGB(48, 56, 74)
	ikToggleBtn.TextColor3 = isFootIKActive and Color3.new(0, 0, 0) or C_TEXT
	labEvent:FireServer("ToggleFootIK", { enabled = isFootIKActive })
end)

rayDistSlider = createPrecisionSlider(ikCard, 96, "Raycast Ground Distance", 4.0, 9.0, CombatConfig.FootIK_RayDistance or 6.8, 0.1, "%.1f studs", function(v)
	CombatConfig.FootIK_RayDistance = v
	labEvent:FireServer("UpdateLocomotionConfig", { key = "FootIK_RayDistance", value = v })
end)

heightOffsetSlider = createPrecisionSlider(ikCard, 142, "Foot Height Offset (Fine Pitch)", -1.0, 1.0, CombatConfig.FootIK_HeightOffset or 0.0, 0.05, "%.2f studs", function(v)
	CombatConfig.FootIK_HeightOffset = v
	labEvent:FireServer("UpdateLocomotionConfig", { key = "FootIK_HeightOffset", value = v })
end)

maxStepDownSlider = createPrecisionSlider(ikCard, 188, "Max Step Drop Limit", 0.5, 4.0, CombatConfig.FootIK_MaxStepDown or 2.4, 0.1, "%.1f studs", function(v)
	CombatConfig.FootIK_MaxStepDown = v
	labEvent:FireServer("UpdateLocomotionConfig", { key = "FootIK_MaxStepDown", value = v })
end)

hipsDipSlider = createPrecisionSlider(ikCard, 234, "Pelvis Dip Compensation Scale", 0.0, 1.0, CombatConfig.FootIK_HipsDipScale or 0.50, 0.05, "%.2f", function(v)
	CombatConfig.FootIK_HipsDipScale = v
	labEvent:FireServer("UpdateLocomotionConfig", { key = "FootIK_HipsDipScale", value = v })
end)

local togglesRow = Instance.new("Frame")
togglesRow.Size = UDim2.new(1, -20, 0, 32)
togglesRow.Position = UDim2.new(0, 10, 0, 280)
togglesRow.BackgroundTransparency = 1
togglesRow.Parent = ikCard

isAnkleAlign = (CombatConfig.FootIK_AnkleAlignment ~= false)
ankleBtn = Instance.new("TextButton")
ankleBtn.Size = UDim2.new(0.48, -4, 1, 0)
ankleBtn.Position = UDim2.new(0, 0, 0, 0)
ankleBtn.BackgroundColor3 = isAnkleAlign and C_PRIMARY or Color3.fromRGB(48, 56, 74)
ankleBtn.TextColor3 = C_TEXT
ankleBtn.Font = Enum.Font.GothamBold
ankleBtn.TextSize = 10
ankleBtn.Text = isAnkleAlign and "Surface Normal: ON" or "Surface Normal: FLAT"
ankleBtn.Parent = togglesRow
applyCorner(ankleBtn, 6)

ankleBtn.MouseButton1Click:Connect(function()
	isAnkleAlign = not isAnkleAlign
	CombatConfig.FootIK_AnkleAlignment = isAnkleAlign
	ankleBtn.BackgroundColor3 = isAnkleAlign and C_PRIMARY or Color3.fromRGB(48, 56, 74)
	ankleBtn.Text = isAnkleAlign and "Surface Normal: ON" or "Surface Normal: FLAT"
	labEvent:FireServer("UpdateLocomotionConfig", { key = "FootIK_AnkleAlignment", value = isAnkleAlign })
end)

isLedgeGrip = (CombatConfig.FootIK_LedgeGrip ~= false)
ledgeBtn = Instance.new("TextButton")
ledgeBtn.Size = UDim2.new(0.48, -4, 1, 0)
ledgeBtn.Position = UDim2.new(0.52, 0, 0, 0)
ledgeBtn.BackgroundColor3 = isLedgeGrip and C_ACCENT or Color3.fromRGB(48, 56, 74)
ledgeBtn.TextColor3 = Color3.new(0, 0, 0)
ledgeBtn.Font = Enum.Font.GothamBold
ledgeBtn.TextSize = 10
ledgeBtn.Text = isLedgeGrip and "Ledge Gripping: ON" or "Ledge Gripping: OFF"
ledgeBtn.Parent = togglesRow
applyCorner(ledgeBtn, 6)

ledgeBtn.MouseButton1Click:Connect(function()
	isLedgeGrip = not isLedgeGrip
	CombatConfig.FootIK_LedgeGrip = isLedgeGrip
	ledgeBtn.BackgroundColor3 = isLedgeGrip and C_ACCENT or Color3.fromRGB(48, 56, 74)
	ledgeBtn.Text = isLedgeGrip and "Ledge Gripping: ON" or "Ledge Gripping: OFF"
	labEvent:FireServer("UpdateLocomotionConfig", { key = "FootIK_LedgeGrip", value = isLedgeGrip })
end)

local ikTelemetryBox = Instance.new("Frame")
ikTelemetryBox.Size = UDim2.new(1, -20, 0, 140)
ikTelemetryBox.Position = UDim2.new(0, 10, 0, 322)
ikTelemetryBox.BackgroundColor3 = Color3.fromRGB(20, 24, 34)
ikTelemetryBox.Parent = ikCard
applyCorner(ikTelemetryBox, 6)
applyStroke(ikTelemetryBox, Color3.fromRGB(45, 55, 75), 1)

local ikTelemetryLabel = Instance.new("TextLabel")
ikTelemetryLabel.Size = UDim2.new(1, -16, 1, -12)
ikTelemetryLabel.Position = UDim2.new(0, 8, 0, 6)
ikTelemetryLabel.BackgroundTransparency = 1
ikTelemetryLabel.TextColor3 = Color3.fromRGB(150, 255, 200)
ikTelemetryLabel.Font = Enum.Font.Code
ikTelemetryLabel.TextSize = 10
ikTelemetryLabel.TextXAlignment = Enum.TextXAlignment.Left
ikTelemetryLabel.TextYAlignment = Enum.TextYAlignment.Top
ikTelemetryLabel.Text = "Foot IK Telemetry: Initializing..."
ikTelemetryLabel.Parent = ikTelemetryBox

end

--------------------------------------------------------------------------------
-- 4C. SUB-TAB 3: ACTIVE MUSCLE RAGDOLL & SPECTACLE KNOCKBACK SANDBOX
--------------------------------------------------------------------------------
do
local ragdollCard = Instance.new("ScrollingFrame")
ragdollCard.Size = UDim2.new(0, 460, 1, -12)
ragdollCard.Position = UDim2.new(0, 10, 0, 6)
ragdollCard.BackgroundColor3 = C_PANEL
ragdollCard.ClipsDescendants = true
ragdollCard.ScrollBarThickness = 4
ragdollCard.CanvasSize = UDim2.new(0, 0, 0, 480)
ragdollCard.Parent = ragdollLabView
applyCorner(ragdollCard, 8)
applyStroke(ragdollCard, C_BORDER, 1)

local ragTitle = Instance.new("TextLabel")
ragTitle.Text = "ðŸ’¥ ACTIVE MUSCLE RAGDOLL CALIBRATION"
ragTitle.Size = UDim2.new(1, -20, 0, 22)
ragTitle.Position = UDim2.new(0, 10, 0, 8)
ragTitle.BackgroundTransparency = 1
ragTitle.TextColor3 = C_TEXT
ragTitle.Font = Enum.Font.GothamBold
ragTitle.TextSize = 12
ragTitle.TextXAlignment = Enum.TextXAlignment.Left
ragTitle.Parent = ragdollCard

local ragSub = Instance.new("TextLabel")
ragSub.Text = "AlignOrientation muscle spring stiffness, tumble torque, and ground slide friction."
ragSub.Size = UDim2.new(1, -20, 0, 16)
ragSub.Position = UDim2.new(0, 10, 0, 28)
ragSub.BackgroundTransparency = 1
ragSub.TextColor3 = C_TEXT_MUTED
ragSub.Font = Enum.Font.Gotham
ragSub.TextSize = 10
ragSub.TextXAlignment = Enum.TextXAlignment.Left
ragSub.Parent = ragdollCard

muscleStiffSlider = createPrecisionSlider(ragdollCard, 50, "Muscle Stiffness (AlignTorque)", 1000, 50000, CombatConfig.Ragdoll_MuscleStiffness or 8000, 500, "%.0f N*m", function(v)
	CombatConfig.Ragdoll_MuscleStiffness = v
	labEvent:FireServer("UpdateLocomotionConfig", { key = "Ragdoll_MuscleStiffness", value = v })
end)

dampingSlider = createPrecisionSlider(ragdollCard, 96, "Ragdoll Joint Damping", 20, 400, CombatConfig.Ragdoll_Damping or 120, 10, "%.0f", function(v)
	CombatConfig.Ragdoll_Damping = v
	labEvent:FireServer("UpdateLocomotionConfig", { key = "Ragdoll_Damping", value = v })
end)

tumbleScaleSlider = createPrecisionSlider(ragdollCard, 142, "Tumble Angular Torque Scale", 0.0, 3.0, CombatConfig.Ragdoll_TumbleScale or 1.0, 0.1, "%.1fx", function(v)
	CombatConfig.Ragdoll_TumbleScale = v
	labEvent:FireServer("UpdateLocomotionConfig", { key = "Ragdoll_TumbleScale", value = v })
end)

groundFrictionSlider = createPrecisionSlider(ragdollCard, 188, "Ground Impact Slide Friction", 0.1, 1.0, CombatConfig.Ragdoll_GroundFriction or 0.55, 0.05, "%.2f", function(v)
	CombatConfig.Ragdoll_GroundFriction = v
	labEvent:FireServer("UpdateLocomotionConfig", { key = "Ragdoll_GroundFriction", value = v })
end)

recoveryDelaySlider = createPrecisionSlider(ragdollCard, 234, "Recovery Get-Up Delay", 0.1, 2.5, CombatConfig.Ragdoll_RecoveryDelay or 0.40, 0.05, "%.2fs", function(v)
	CombatConfig.Ragdoll_RecoveryDelay = v
	labEvent:FireServer("UpdateLocomotionConfig", { key = "Ragdoll_RecoveryDelay", value = v })
end)

-- Right Card: Spectacle Test Launches
local launchCard = Instance.new("ScrollingFrame")
launchCard.Size = UDim2.new(0, 470, 1, -12)
launchCard.Position = UDim2.new(0, 480, 0, 6)
launchCard.BackgroundColor3 = C_PANEL
launchCard.ClipsDescendants = true
launchCard.ScrollBarThickness = 4
launchCard.CanvasSize = UDim2.new(0, 0, 0, 480)
launchCard.Parent = ragdollLabView
applyCorner(launchCard, 8)
applyStroke(launchCard, C_BORDER, 1)

local launchTitle = Instance.new("TextLabel")
launchTitle.Text = "ðŸ§ª SPECTACLE TEST LAUNCHES"
launchTitle.Size = UDim2.new(1, -20, 0, 22)
launchTitle.Position = UDim2.new(0, 10, 0, 8)
launchTitle.BackgroundTransparency = 1
launchTitle.TextColor3 = C_TEXT
launchTitle.Font = Enum.Font.GothamBold
launchTitle.TextSize = 12
launchTitle.TextXAlignment = Enum.TextXAlignment.Left
launchTitle.Parent = launchCard

local launchSub = Instance.new("TextLabel")
launchSub.Text = "Fire physical parabolic knockbacks on QuinA_Tester to audition dynamic ragdoll & get-up recovery."
launchSub.Size = UDim2.new(1, -20, 0, 16)
launchSub.Position = UDim2.new(0, 10, 0, 28)
launchSub.BackgroundTransparency = 1
launchSub.TextColor3 = C_TEXT_MUTED
launchSub.Font = Enum.Font.Gotham
launchSub.TextSize = 10
launchSub.TextXAlignment = Enum.TextXAlignment.Left
launchSub.Parent = launchCard

local highArcBtn = Instance.new("TextButton")
highArcBtn.Size = UDim2.new(1, -20, 0, 36)
highArcBtn.Position = UDim2.new(0, 10, 0, 52)
highArcBtn.BackgroundColor3 = Color3.fromRGB(0, 160, 220)
highArcBtn.TextColor3 = Color3.new(1, 1, 1)
highArcBtn.Font = Enum.Font.GothamBold
highArcBtn.TextSize = 11
highArcBtn.Text = "ðŸ’¥ Launch Test Knockback (High Arc Parabolic)"
highArcBtn.Parent = launchCard
applyCorner(highArcBtn, 6)

highArcBtn.MouseButton1Click:Connect(function()
	if checkAndSpawnTesters then checkAndSpawnTesters(false) end
	labEvent:FireServer("TestKnockbackLaunch", { style = "high_arc" })
	statusToast.Text = "ðŸ’¥ High Arc Parabolic Knockback Launched on QuinA_Tester!"
	statusToast.TextColor3 = C_ACCENT
end)

local lowSmashBtn = Instance.new("TextButton")
lowSmashBtn.Size = UDim2.new(1, -20, 0, 36)
lowSmashBtn.Position = UDim2.new(0, 10, 0, 96)
lowSmashBtn.BackgroundColor3 = Color3.fromRGB(220, 100, 40)
lowSmashBtn.TextColor3 = Color3.new(1, 1, 1)
lowSmashBtn.Font = Enum.Font.GothamBold
lowSmashBtn.TextSize = 11
lowSmashBtn.Text = "âš¡ Launch Test Knockback (Low Smash Horizontal)"
lowSmashBtn.Parent = launchCard
applyCorner(lowSmashBtn, 6)

lowSmashBtn.MouseButton1Click:Connect(function()
	if checkAndSpawnTesters then checkAndSpawnTesters(false) end
	labEvent:FireServer("TestKnockbackLaunch", { style = "low_smash" })
	statusToast.Text = "âš¡ Low Smash Horizontal Knockback Launched on QuinA_Tester!"
	statusToast.TextColor3 = Color3.fromRGB(255, 170, 50)
end)

isContinuousRagdoll = false
toggleContinuousRagBtn = Instance.new("TextButton")
toggleContinuousRagBtn.Size = UDim2.new(1, -20, 0, 34)
toggleContinuousRagBtn.Position = UDim2.new(0, 10, 0, 140)
toggleContinuousRagBtn.BackgroundColor3 = Color3.fromRGB(48, 56, 74)
toggleContinuousRagBtn.TextColor3 = C_TEXT
toggleContinuousRagBtn.Font = Enum.Font.GothamBold
toggleContinuousRagBtn.TextSize = 11
toggleContinuousRagBtn.Text = "Toggle Continuous Ragdoll Mode (PlatformStand)"
toggleContinuousRagBtn.Parent = launchCard
applyCorner(toggleContinuousRagBtn, 6)

toggleContinuousRagBtn.MouseButton1Click:Connect(function()
	isContinuousRagdoll = not isContinuousRagdoll
	toggleContinuousRagBtn.Text = isContinuousRagdoll and "Continuous Ragdoll: ACTIVE (Loose Limbs)" or "Continuous Ragdoll: OFF"
	toggleContinuousRagBtn.BackgroundColor3 = isContinuousRagdoll and C_DANGER or Color3.fromRGB(48, 56, 74)
	labEvent:FireServer("ToggleRagdoll", { active = isContinuousRagdoll })
end)

local ragResetBtn = Instance.new("TextButton")
ragResetBtn.Size = UDim2.new(1, -20, 0, 32)
ragResetBtn.Position = UDim2.new(0, 10, 0, 182)
ragResetBtn.BackgroundColor3 = Color3.fromRGB(35, 75, 110)
ragResetBtn.TextColor3 = C_ACCENT
ragResetBtn.Font = Enum.Font.GothamBold
ragResetBtn.TextSize = 11
ragResetBtn.Text = "ðŸ”„ Reset Tester Upright & Stationary"
ragResetBtn.Parent = launchCard
applyCorner(ragResetBtn, 6)

ragResetBtn.MouseButton1Click:Connect(function()
	if checkAndSpawnTesters then checkAndSpawnTesters(true) end
end)

local ragTelemetryBox = Instance.new("Frame")
ragTelemetryBox.Size = UDim2.new(1, -20, 0, 120)
ragTelemetryBox.Position = UDim2.new(0, 10, 0, 224)
ragTelemetryBox.BackgroundColor3 = Color3.fromRGB(20, 24, 34)
ragTelemetryBox.Parent = launchCard
applyCorner(ragTelemetryBox, 6)
applyStroke(ragTelemetryBox, Color3.fromRGB(45, 55, 75), 1)

local ragTelemetryLabel = Instance.new("TextLabel")
ragTelemetryLabel.Size = UDim2.new(1, -16, 1, -12)
ragTelemetryLabel.Position = UDim2.new(0, 8, 0, 6)
ragTelemetryLabel.BackgroundTransparency = 1
ragTelemetryLabel.TextColor3 = Color3.fromRGB(255, 200, 150)
ragTelemetryLabel.Font = Enum.Font.Code
ragTelemetryLabel.TextSize = 10
ragTelemetryLabel.TextXAlignment = Enum.TextXAlignment.Left
ragTelemetryLabel.TextYAlignment = Enum.TextYAlignment.Top
ragTelemetryLabel.Text = "Ragdoll Telemetry: Ready for impact tests."
ragTelemetryLabel.Parent = ragTelemetryBox

end

--------------------------------------------------------------------------------
-- 4D. SUB-TAB 4: AUTONOMOUS LOCOMOTION MANEUVER SUITE
--------------------------------------------------------------------------------
do
local manHeader = Instance.new("TextLabel")
manHeader.Text = "QUIN AUTONOMOUS LOCOMOTION MANEUVER SUITE"
manHeader.Size = UDim2.new(1, -20, 0, 22)
manHeader.Position = UDim2.new(0, 10, 0, 8)
manHeader.BackgroundTransparency = 1
manHeader.TextColor3 = C_TEXT
manHeader.Font = Enum.Font.GothamBold
manHeader.TextSize = 13
manHeader.TextXAlignment = Enum.TextXAlignment.Left
manHeader.Parent = maneuversView

local manSub = Instance.new("TextLabel")
manSub.Text = "Command QuinA_Tester through high-stress directional cuts, orbital banking arcs, and hard braking."
manSub.Size = UDim2.new(1, -20, 0, 16)
manSub.Position = UDim2.new(0, 10, 0, 30)
manSub.BackgroundTransparency = 1
manSub.TextColor3 = C_TEXT_MUTED
manSub.Font = Enum.Font.Gotham
manSub.TextSize = 10
manSub.TextXAlignment = Enum.TextXAlignment.Left
manSub.Parent = maneuversView

local manGrid = Instance.new("ScrollingFrame")
manGrid.Size = UDim2.new(1, -20, 1, -56)
manGrid.Position = UDim2.new(0, 10, 0, 50)
manGrid.BackgroundTransparency = 1
manGrid.ScrollBarThickness = 4
manGrid.CanvasSize = UDim2.new(0, 960, 0, 0)
manGrid.Parent = maneuversView

local function createManeuverCard(parent, xPos, title, badge, desc, accentCol, onClick)
	local card = Instance.new("Frame")
	card.Size = UDim2.new(0, 224, 0, 380)
	card.Position = UDim2.new(0, xPos, 0, 0)
	card.BackgroundColor3 = C_CARD
	card.Parent = parent
	applyCorner(card, 8)
	applyStroke(card, C_BORDER, 1)

	local cardBadge = Instance.new("TextLabel")
	cardBadge.Size = UDim2.new(1, -20, 0, 18)
	cardBadge.Position = UDim2.new(0, 10, 0, 12)
	cardBadge.BackgroundTransparency = 1
	cardBadge.TextColor3 = accentCol
	cardBadge.Font = Enum.Font.GothamBold
	cardBadge.TextSize = 10
	cardBadge.TextXAlignment = Enum.TextXAlignment.Left
	cardBadge.Text = string.upper(badge)
	cardBadge.Parent = card

	local cardTitle = Instance.new("TextLabel")
	cardTitle.Size = UDim2.new(1, -20, 0, 24)
	cardTitle.Position = UDim2.new(0, 10, 0, 32)
	cardTitle.BackgroundTransparency = 1
	cardTitle.TextColor3 = C_TEXT
	cardTitle.Font = Enum.Font.GothamBold
	cardTitle.TextSize = 14
	cardTitle.TextXAlignment = Enum.TextXAlignment.Left
	cardTitle.Text = title
	cardTitle.Parent = card

	local cardDesc = Instance.new("TextLabel")
	cardDesc.Size = UDim2.new(1, -20, 0, 80)
	cardDesc.Position = UDim2.new(0, 10, 0, 60)
	cardDesc.BackgroundTransparency = 1
	cardDesc.TextColor3 = C_TEXT_MUTED
	cardDesc.Font = Enum.Font.Gotham
	cardDesc.TextSize = 10
	cardDesc.TextXAlignment = Enum.TextXAlignment.Left
	cardDesc.TextYAlignment = Enum.TextYAlignment.Top
	cardDesc.TextWrapped = true
	cardDesc.Text = desc
	cardDesc.Parent = card

	local actBtn = Instance.new("TextButton")
	actBtn.Size = UDim2.new(1, -20, 0, 36)
	actBtn.Position = UDim2.new(0, 10, 1, -48)
	actBtn.BackgroundColor3 = accentCol
	actBtn.TextColor3 = Color3.new(0, 0, 0)
	actBtn.Font = Enum.Font.GothamBold
	actBtn.TextSize = 11
	actBtn.Text = "Execute Maneuver â–¶"
	actBtn.Parent = card
	applyCorner(actBtn, 6)

	actBtn.MouseButton1Click:Connect(function()
		if onClick then onClick(actBtn) end
	end)
end

createManeuverCard(
	manGrid, 0, "Sprint & 180Â° Cut", "Directional Pivot",
	"Commands QuinA_Tester to sprint at 50 studs/s, execute an instant 180-degree directional pivot, and sprint back. Inspects stride scaling and anti-sliding.",
	Color3.fromRGB(0, 220, 255),
	function(btn)
		labEvent:FireServer("RunLocomotionTest", { testType = "Sprint180" })
		statusToast.Text = "ðŸƒ Executing Sprint & 180Â° Cut maneuver..."
		statusToast.TextColor3 = C_ACCENT
	end
)

createManeuverCard(
	manGrid, 238, "Arc Run 30Â°", "Centripetal Banking",
	"Drives QuinA_Tester along a 28-stud radius circular orbital path at 44 studs/s, tilting the torso roll angle into the turn based on centripetal speed.",
	Color3.fromRGB(160, 220, 40),
	function(btn)
		labEvent:FireServer("RunLocomotionTest", { testType = "ArcRun" })
		statusToast.Text = "ðŸŒ€ Executing 30Â° Centripetal Arc Run maneuver..."
		statusToast.TextColor3 = Color3.fromRGB(180, 240, 50)
	end
)

createManeuverCard(
	manGrid, 476, "Sprint & Hard Brake", "Kinetic Skid",
	"Sprints forward at 52 studs/s and halts abruptly into a kinetic skid stop, testing deceleration friction decay and transition into combat idle.",
	Color3.fromRGB(255, 160, 40),
	function(btn)
		labEvent:FireServer("RunLocomotionTest", { testType = "SprintBrake" })
		statusToast.Text = "ðŸ›‘ Executing Sprint & Hard Brake skid..."
		statusToast.TextColor3 = Color3.fromRGB(255, 180, 50)
	end
)

createManeuverCard(
	manGrid, 714, "Diagnostic Filmstrip", "Python Capture Ready",
	"Positions camera and arms QuinA_Tester for high-frequency burst frame captures via inspect_locomotion_cycle.py.",
	Color3.fromRGB(220, 100, 255),
	function(btn)
		statusToast.Text = "ðŸ“¸ Diagnostic Burst Ready: Run inspect_locomotion_cycle.py in terminal!"
		statusToast.TextColor3 = Color3.fromRGB(230, 120, 255)
	end
)

-- Periodic Telemetry Heartbeat updater for Locomotion, IK, and Ragdoll tabs
RunService.Heartbeat:Connect(function()
	if not mainFrame.Visible or activeMainTab ~= "Powerhouse" then return end
	local quinServer = Workspace:FindFirstChild("QuinServer")
	local tester = quinServer and quinServer:FindFirstChild(testerName)
	if not tester or not tester.Parent then return end

	local hrp = tester:FindFirstChild("HumanoidRootPart")
	local hum = tester:FindFirstChildOfClass("Humanoid")
	if not hrp or not hum then return end

	if activePowerhouseSubTab == "LocoIK" then
		local linVel = hrp.AssemblyLinearVelocity
		local horizSpeed = Vector3.new(linVel.X, 0, linVel.Z).Magnitude
		local strideBase = CombatConfig.RunStrideBase or 38.0
		local dynamicMult = horizSpeed > 0.5 and (horizSpeed / strideBase) or 1.0
		local rollAngle = hrp.Orientation.Z

		locoTelemetryLabel.Text = string.format(
			"Rig: %s\nHorizontal Speed: %.1f studs/s\nWalkSpeed: %.1f\nCalculated Stride Scale: %.2fx (Base: %.1f)\nCurrent Torso Bank Roll: %.1fÂ° (Max: %.1fÂ°)",
			tester.Name, horizSpeed, hum.WalkSpeed, dynamicMult, strideBase, rollAngle, CombatConfig.TorsoBankingMaxRoll or 12.0
		)

		local lIK = hum:FindFirstChild("LeftFootIK") or hum:FindFirstChild("GhostLeftFootIK")
		local rIK = hum:FindFirstChild("RightFootIK") or hum:FindFirstChild("GhostRightFootIK")
		local lWeight = lIK and lIK.Weight or 0
		local rWeight = rIK and rIK.Weight or 0
		local lAtt = hrp:FindFirstChild("LeftFootTargetAtt") or hrp:FindFirstChild("GhostLeftFootTargetAtt")
		local rAtt = hrp:FindFirstChild("RightFootTargetAtt") or hrp:FindFirstChild("GhostRightFootTargetAtt")

		ikTelemetryLabel.Text = string.format(
			"Foot IK Status: %s | Normal Align: %s | Ledge Grip: %s\nLeft Foot Weight: %.2f | Target: %s\nRight Foot Weight: %.2f | Target: %s\nRay Dist: %.1f studs | Max Step Drop: %.1f studs\nPelvis Dip Scale: %.2f | Ankle Height Offset: %.2f studs",
			(CombatConfig.FootIK_Enabled and "ACTIVE" or "DISABLED"),
			(CombatConfig.FootIK_AnkleAlignment ~= false and "YES" or "NO"),
			(CombatConfig.FootIK_LedgeGrip ~= false and "YES" or "NO"),
			lWeight, lAtt and string.format("(%.1f, %.1f, %.1f)", lAtt.Position.X, lAtt.Position.Y, lAtt.Position.Z) or "None",
			rWeight, rAtt and string.format("(%.1f, %.1f, %.1f)", rAtt.Position.X, rAtt.Position.Y, rAtt.Position.Z) or "None",
			CombatConfig.FootIK_RayDistance or 6.8,
			CombatConfig.FootIK_MaxStepDown or 2.4,
			CombatConfig.FootIK_HipsDipScale or 0.50,
			CombatConfig.FootIK_HeightOffset or 0.0
		)

	elseif activePowerhouseSubTab == "RagdollLab" then
		local linVel = hrp.AssemblyLinearVelocity
		local angVel = hrp.AssemblyAngularVelocity
		local isProne = hum.PlatformStand
		local hasMuscle = hrp:FindFirstChild("LabMuscleStabilizer") ~= nil

		ragTelemetryLabel.Text = string.format(
			"Rig: %s | PlatformStand: %s\nLinear Velocity: (%.1f, %.1f, %.1f) Mag: %.1f\nAngular Velocity: (%.1f, %.1f, %.1f) Rad/s\nActive Muscle Stabilizer: %s (MaxTorque: %.0f N*m)\nGround Contact Ray: %.1f studs to floor",
			tester.Name, tostring(isProne), linVel.X, linVel.Y, linVel.Z, linVel.Magnitude,
			angVel.X, angVel.Y, angVel.Z,
			hasMuscle and "ENGAGED" or "NONE",
			CombatConfig.Ragdoll_MuscleStiffness or 8000,
			(Workspace:Raycast(hrp.Position, Vector3.new(0, -10, 0)) and (hrp.Position - (Workspace:Raycast(hrp.Position, Vector3.new(0, -10, 0)).Position)).Magnitude or 99.0)
		)
	end
end)

end

function createModeCard(parent, xPos, title, badge, desc, accentCol, onClick)
	local card = Instance.new("Frame")
	card.Size = UDim2.new(0, 220, 0, 420)
	card.Position = UDim2.new(0, xPos, 0, 0)
	card.BackgroundColor3 = C_CARD
	card.Parent = parent
	applyCorner(card, 8)
	applyStroke(card, C_BORDER, 1)

	local cardBadge = Instance.new("TextLabel")
	cardBadge.Size = UDim2.new(1, -20, 0, 20)
	cardBadge.Position = UDim2.new(0, 10, 0, 14)
	cardBadge.BackgroundTransparency = 1
	cardBadge.TextColor3 = accentCol
	cardBadge.Font = Enum.Font.GothamBold
	cardBadge.TextSize = 10
	cardBadge.TextXAlignment = Enum.TextXAlignment.Left
	cardBadge.Text = string.upper(badge)
	cardBadge.Parent = card

	local cardTitle = Instance.new("TextLabel")
	cardTitle.Size = UDim2.new(1, -20, 0, 26)
	cardTitle.Position = UDim2.new(0, 10, 0, 36)
	cardTitle.BackgroundTransparency = 1
	cardTitle.TextColor3 = C_TEXT
	cardTitle.Font = Enum.Font.GothamBold
	cardTitle.TextSize = 15
	cardTitle.TextXAlignment = Enum.TextXAlignment.Left
	cardTitle.Text = title
	cardTitle.Parent = card

	local cardDesc = Instance.new("TextLabel")
	cardDesc.Size = UDim2.new(1, -20, 0, 240)
	cardDesc.Position = UDim2.new(0, 10, 0, 68)
	cardDesc.BackgroundTransparency = 1
	cardDesc.TextColor3 = C_TEXT_MUTED
	cardDesc.Font = Enum.Font.Gotham
	cardDesc.TextSize = 12
	cardDesc.TextXAlignment = Enum.TextXAlignment.Left
	cardDesc.TextYAlignment = Enum.TextYAlignment.Top
	cardDesc.TextWrapped = true
	cardDesc.Text = desc
	cardDesc.Parent = card

	local launchBtn = Instance.new("TextButton")
	launchBtn.Size = UDim2.new(1, -20, 0, 40)
	launchBtn.Position = UDim2.new(0, 10, 1, -52)
	launchBtn.BackgroundColor3 = accentCol
	launchBtn.TextColor3 = Color3.new(0, 0, 0)
	launchBtn.Font = Enum.Font.GothamBold
	launchBtn.TextSize = 12
	launchBtn.Text = "Launch Mode â–¶"
	launchBtn.Parent = card
	applyCorner(launchBtn, 6)

	launchBtn.MouseButton1Click:Connect(function()
		onClick(launchBtn)
	end)

	return card
end

--------------------------------------------------------------------------------
-- 7. GAME MODES VIEW (1v1, 2v2, FFA, CLEAN)
--------------------------------------------------------------------------------
do
local gmHeader = Instance.new("TextLabel")
gmHeader.Text = "QUIN PRODUCTION GAME MODES"
gmHeader.Size = UDim2.new(1, -20, 0, 26)
gmHeader.Position = UDim2.new(0, 10, 0, 8)
gmHeader.BackgroundTransparency = 1
gmHeader.TextColor3 = C_TEXT
gmHeader.Font = Enum.Font.GothamBold
gmHeader.TextSize = 14
gmHeader.TextXAlignment = Enum.TextXAlignment.Left
gmHeader.Parent = gameModesView

local gmSub = Instance.new("TextLabel")
gmSub.Text = "Launch autonomous Quin combat encounters. Spectate AI tactics, decision loops, and health dynamics."
gmSub.Size = UDim2.new(1, -20, 0, 18)
gmSub.Position = UDim2.new(0, 10, 0, 36)
gmSub.BackgroundTransparency = 1
gmSub.TextColor3 = C_TEXT_MUTED
gmSub.Font = Enum.Font.Gotham
gmSub.TextSize = 11
gmSub.TextXAlignment = Enum.TextXAlignment.Left
gmSub.Parent = gameModesView

local gmGrid = Instance.new("ScrollingFrame")
gmGrid.Name = "ModesGrid"
gmGrid.Size = UDim2.new(1, -20, 1, -76)
gmGrid.Position = UDim2.new(0, 10, 0, 64)
gmGrid.BackgroundTransparency = 1
gmGrid.BorderSizePixel = 0
gmGrid.ScrollBarThickness = 6
gmGrid.ScrollBarImageColor3 = Color3.fromRGB(80, 120, 180)
gmGrid.CanvasSize = UDim2.new(0, 1220, 0, 0)
gmGrid.Parent = gameModesView



local function createTeamBattleCard(parent, xPos)
	local card = Instance.new("Frame")
	card.Size = UDim2.new(0, 220, 0, 420)
	card.Position = UDim2.new(0, xPos, 0, 0)
	card.BackgroundColor3 = C_CARD
	card.Parent = parent
	applyCorner(card, 8)
	applyStroke(card, C_BORDER, 1)

	local cardBadge = Instance.new("TextLabel")
	cardBadge.Size = UDim2.new(1, -20, 0, 20)
	cardBadge.Position = UDim2.new(0, 10, 0, 14)
	cardBadge.BackgroundTransparency = 1
	cardBadge.TextColor3 = Color3.fromRGB(160, 110, 255)
	cardBadge.Font = Enum.Font.GothamBold
	cardBadge.TextSize = 10
	cardBadge.TextXAlignment = Enum.TextXAlignment.Left
	cardBadge.Text = "SELECTABLE SIZES"
	cardBadge.Parent = card

	local cardTitle = Instance.new("TextLabel")
	cardTitle.Size = UDim2.new(1, -20, 0, 26)
	cardTitle.Position = UDim2.new(0, 10, 0, 36)
	cardTitle.BackgroundTransparency = 1
	cardTitle.TextColor3 = C_TEXT
	cardTitle.Font = Enum.Font.GothamBold
	cardTitle.TextSize = 15
	cardTitle.TextXAlignment = Enum.TextXAlignment.Left
	cardTitle.Text = "Team Skirmish / War"
	cardTitle.Parent = card

	local cardDesc = Instance.new("TextLabel")
	cardDesc.Size = UDim2.new(1, -20, 0, 110)
	cardDesc.Position = UDim2.new(0, 10, 0, 68)
	cardDesc.BackgroundTransparency = 1
	cardDesc.TextColor3 = C_TEXT_MUTED
	cardDesc.Font = Enum.Font.Gotham
	cardDesc.TextSize = 12
	cardDesc.TextXAlignment = Enum.TextXAlignment.Left
	cardDesc.TextYAlignment = Enum.TextYAlignment.Top
	cardDesc.TextWrapped = true
	cardDesc.Text = "Two opposing teams battle in coordinated combat. Select team size below (2v2 up to massive 16v16 Arena War with 32 Quins):"
	cardDesc.Parent = card

	-- Team Size Pills Container
	local pillsFrame = Instance.new("Frame")
	pillsFrame.Size = UDim2.new(1, -20, 0, 36)
	pillsFrame.Position = UDim2.new(0, 10, 0, 190)
	pillsFrame.BackgroundTransparency = 1
	pillsFrame.Parent = card

	local selectedTeamCount = 4
	local pillBtns = {}
	local sizes = {
		{ label = "2v2", count = 2 },
		{ label = "4v4", count = 4 },
		{ label = "6v6", count = 6 },
		{ label = "8v8", count = 8 },
		{ label = "16v16", count = 16 },
	}

	local launchBtn = Instance.new("TextButton")
	launchBtn.Size = UDim2.new(1, -20, 0, 40)
	launchBtn.Position = UDim2.new(0, 10, 1, -52)
	launchBtn.BackgroundColor3 = Color3.fromRGB(160, 110, 255)
	launchBtn.TextColor3 = Color3.new(0, 0, 0)
	launchBtn.Font = Enum.Font.GothamBold
	launchBtn.TextSize = 12
	launchBtn.Text = "Launch 4 vs 4 â–¶"
	launchBtn.Parent = card
	applyCorner(launchBtn, 6)

	local pillWidth = 36
	local pillGap = 3
	for i, sz in ipairs(sizes) do
		local pBtn = Instance.new("TextButton")
		pBtn.Size = UDim2.new(0, pillWidth, 0, 28)
		pBtn.Position = UDim2.new(0, (i - 1) * (pillWidth + pillGap), 0, 4)
		pBtn.BackgroundColor3 = (sz.count == selectedTeamCount) and Color3.fromRGB(160, 110, 255) or Color3.fromRGB(35, 40, 55)
		pBtn.TextColor3 = (sz.count == selectedTeamCount) and Color3.new(0, 0, 0) or C_TEXT
		pBtn.Font = Enum.Font.GothamBold
		pBtn.TextSize = 9
		pBtn.Text = sz.label
		pBtn.Parent = pillsFrame
		applyCorner(pBtn, 4)
		table.insert(pillBtns, { btn = pBtn, count = sz.count, label = sz.label })

		pBtn.MouseButton1Click:Connect(function()
			selectedTeamCount = sz.count
			for _, item in ipairs(pillBtns) do
				local isSel = (item.count == selectedTeamCount)
				item.btn.BackgroundColor3 = isSel and Color3.fromRGB(160, 110, 255) or Color3.fromRGB(35, 40, 55)
				item.btn.TextColor3 = isSel and Color3.new(0, 0, 0) or C_TEXT
			end
			if selectedTeamCount == 16 then
				launchBtn.Text = "Launch 16 vs 16 (Arena War) â–¶"
			else
				launchBtn.Text = "Launch " .. tostring(selectedTeamCount) .. " vs " .. tostring(selectedTeamCount) .. " â–¶"
			end
		end)
	end

	launchBtn.MouseButton1Click:Connect(function()
		labEvent:FireServer("SetGameMode", { mode = "team", count = selectedTeamCount })
		statusToast.Text = string.format("ðŸŽ® Launched %d vs %d Team Battle (%d Quins total).", 
			selectedTeamCount, selectedTeamCount, selectedTeamCount * 2)
		statusToast.TextColor3 = C_SUCCESS
	end)

	return card
end

-- Card 1: 1 vs 1 Sparring Match
createModeCard(
	gmGrid, 0, "1 vs 1 Sparring Match", "Standard Sparring",
	"Two Quins enter the ring facing each other (TeamAlpha vs TeamBeta). Exercises anticipation, standoff circling, combo hitstops, and knockback recovery loops.",
	C_ACCENT,
	function(btn)
		labEvent:FireServer("SetGameMode", { mode = "1v1" })
		statusToast.Text = "ðŸŽ® Launched 1v1 Sparring Match."
		statusToast.TextColor3 = C_SUCCESS
	end
)

-- Card 2: Team Skirmish / Arena War (Selectable Sizes)
createTeamBattleCard(gmGrid, 230)

-- Card 3: Mid-Air Clash Duel (Z-Relocating Brawl)
createModeCard(
	gmGrid, 460, "Mid-Air Clash Duel", "Z-Relocating Brawl",
	"Two Quins enter an immediate mid-air clash. Relocates dynamically across aerial coordinates until one is meteor-smashed to earth or both clash-tie!",
	Color3.fromRGB(0, 220, 255),
	function(btn)
		labEvent:FireServer("SetGameMode", { mode = "midair_clash" })
		statusToast.Text = "âš”ï¸ Launched Mid-Air Clash Duel Mode."
		statusToast.TextColor3 = C_SUCCESS
	end
)

-- Card 4: Battle Mode (FFA)
createModeCard(
	gmGrid, 690, "Battle Mode (FFA)", "8-Man Free-For-All",
	"Eight Quins spawned in a perimeter ring. Full free-for-all brawl with dynamic target switching, multi-agent collision, and survival prioritization.",
	Color3.fromRGB(255, 130, 40),
	function(btn)
		labEvent:FireServer("SetGameMode", { mode = "ffa", count = 8 })
		statusToast.Text = "ðŸŽ® Launched 8-Man Free-For-All Battle Mode."
		statusToast.TextColor3 = C_SUCCESS
	end
)

-- Card 5: Reset Arena / Clear Quins
createModeCard(
	gmGrid, 920, "Reset Arena", "Clear Quins",
	"Instantly cleans all spawned Quins, resets match state attributes, and flushes physics attachments for a fresh clean slate.",
	C_DANGER,
	function(btn)
		labEvent:FireServer("SetGameMode", { mode = "clean" })
		statusToast.Text = "ðŸ§¹ Arena cleared."
		statusToast.TextColor3 = Color3.fromRGB(250, 180, 50)
	end
)

end
--------------------------------------------------------------------------------
-- 8. TEST MODES VIEW (SPARRING LAB | INFINITE STRAFE | PROJECTILE JUMP)
--------------------------------------------------------------------------------
do
local tmHeader = Instance.new("TextLabel")
tmHeader.Text = "QUIN STATE & BEHAVIOR TEST SUITE"
tmHeader.Size = UDim2.new(1, -20, 0, 26)
tmHeader.Position = UDim2.new(0, 10, 0, 8)
tmHeader.BackgroundTransparency = 1
tmHeader.TextColor3 = C_TEXT
tmHeader.Font = Enum.Font.GothamBold
tmHeader.TextSize = 14
tmHeader.TextXAlignment = Enum.TextXAlignment.Left
tmHeader.Parent = testModesView

local tmSub = Instance.new("TextLabel")
tmSub.Text = "Dedicated testing environments to calibrate specific AI state machines, trajectory physics, and animation priorities."
tmSub.Size = UDim2.new(1, -20, 0, 18)
tmSub.Position = UDim2.new(0, 10, 0, 36)
tmSub.BackgroundTransparency = 1
tmSub.TextColor3 = C_TEXT_MUTED
tmSub.Font = Enum.Font.Gotham
tmSub.TextSize = 11
tmSub.TextXAlignment = Enum.TextXAlignment.Left
tmSub.Parent = testModesView

local function createJumpStyleCard(parent, xPos)
	local card = Instance.new("Frame")
	card.Size = UDim2.new(0, 220, 0, 420)
	card.Position = UDim2.new(0, xPos, 0, 0)
	card.BackgroundColor3 = C_CARD
	card.Parent = parent
	applyCorner(card, 8)
	applyStroke(card, C_BORDER, 1)

	local cardBadge = Instance.new("TextLabel")
	cardBadge.Size = UDim2.new(1, -20, 0, 20)
	cardBadge.Position = UDim2.new(0, 10, 0, 14)
	cardBadge.BackgroundTransparency = 1
	cardBadge.TextColor3 = Color3.fromRGB(240, 180, 40)
	cardBadge.Font = Enum.Font.GothamBold
	cardBadge.TextSize = 10
	cardBadge.TextXAlignment = Enum.TextXAlignment.Left
	cardBadge.Text = "7 TRAJECTORY STYLES"
	cardBadge.Parent = card

	local cardTitle = Instance.new("TextLabel")
	cardTitle.Size = UDim2.new(1, -20, 0, 26)
	cardTitle.Position = UDim2.new(0, 10, 0, 36)
	cardTitle.BackgroundTransparency = 1
	cardTitle.TextColor3 = C_TEXT
	cardTitle.Font = Enum.Font.GothamBold
	cardTitle.TextSize = 15
	cardTitle.TextXAlignment = Enum.TextXAlignment.Left
	cardTitle.Text = "Projectile Jump Lab"
	cardTitle.Parent = card

	local cardDesc = Instance.new("TextLabel")
	cardDesc.Size = UDim2.new(1, -20, 0, 110)
	cardDesc.Position = UDim2.new(0, 10, 0, 68)
	cardDesc.BackgroundTransparency = 1
	cardDesc.TextColor3 = C_TEXT_MUTED
	cardDesc.Font = Enum.Font.Gotham
	cardDesc.TextSize = 12
	cardDesc.TextXAlignment = Enum.TextXAlignment.Left
	cardDesc.TextYAlignment = Enum.TextYAlignment.Top
	cardDesc.TextWrapped = true
	cardDesc.Text = "Calibrate predictive jump physics against incoming threats. Select from 7 distinct aerial styles:"
	cardDesc.Parent = card

	local pillsFrame = Instance.new("Frame")
	pillsFrame.Size = UDim2.new(1, -20, 0, 36)
	pillsFrame.Position = UDim2.new(0, 10, 0, 190)
	pillsFrame.BackgroundTransparency = 1
	pillsFrame.Parent = card

	local selectedStyle = 1
	local pillBtns = {}
	local styles = {
		{ label = "S1", style = 1, name = "Vertical" },
		{ label = "S2", style = 2, name = "Lunge" },
		{ label = "S3", style = 3, name = "Apex" },
		{ label = "S4", style = 4, name = "Skim" },
		{ label = "S5", style = 5, name = "Hop" },
		{ label = "S6", style = 6, name = "Flip" },
		{ label = "S7", style = 7, name = "Float" },
	}

	local launchBtn = Instance.new("TextButton")
	launchBtn.Size = UDim2.new(1, -20, 0, 40)
	launchBtn.Position = UDim2.new(0, 10, 1, -52)
	launchBtn.BackgroundColor3 = Color3.fromRGB(240, 180, 40)
	launchBtn.TextColor3 = Color3.new(0, 0, 0)
	launchBtn.Font = Enum.Font.GothamBold
	launchBtn.TextSize = 12
	launchBtn.Text = "Launch Style 1 (Vertical) â–¶"
	launchBtn.Parent = card
	applyCorner(launchBtn, 6)

	local pillWidth = 25
	local pillGap = 3
	for i, st in ipairs(styles) do
		local pBtn = Instance.new("TextButton")
		pBtn.Size = UDim2.new(0, pillWidth, 0, 28)
		pBtn.Position = UDim2.new(0, (i - 1) * (pillWidth + pillGap), 0, 4)
		pBtn.BackgroundColor3 = (st.style == selectedStyle) and Color3.fromRGB(240, 180, 40) or Color3.fromRGB(35, 40, 55)
		pBtn.TextColor3 = (st.style == selectedStyle) and Color3.new(0, 0, 0) or C_TEXT
		pBtn.Font = Enum.Font.GothamBold
		pBtn.TextSize = 9
		pBtn.Text = st.label
		pBtn.Parent = pillsFrame
		applyCorner(pBtn, 4)
		table.insert(pillBtns, { btn = pBtn, style = st.style, name = st.name })

		pBtn.MouseButton1Click:Connect(function()
			selectedStyle = st.style
			for _, item in ipairs(pillBtns) do
				local isSel = (item.style == selectedStyle)
				item.btn.BackgroundColor3 = isSel and Color3.fromRGB(240, 180, 40) or Color3.fromRGB(35, 40, 55)
				item.btn.TextColor3 = isSel and Color3.new(0, 0, 0) or C_TEXT
			end
			launchBtn.Text = string.format("Launch Style %d (%s) â–¶", selectedStyle, st.name)
		end)
	end

	launchBtn.MouseButton1Click:Connect(function()
		labEvent:FireServer("SetTestMode", { mode = "ProjectileJump", style = selectedStyle })
		statusToast.Text = string.format("ðŸ§ª Launched Projectile Jump Style %d (%s).", selectedStyle, styles[selectedStyle].name)
		statusToast.TextColor3 = C_SUCCESS
	end)

	return card
end

local tmGrid = Instance.new("ScrollingFrame")
tmGrid.Size = UDim2.new(1, -20, 1, -76)
tmGrid.Position = UDim2.new(0, 10, 0, 64)
tmGrid.BackgroundTransparency = 1
tmGrid.BorderSizePixel = 0
tmGrid.ScrollBarThickness = 6
tmGrid.ScrollBarImageColor3 = Color3.fromRGB(80, 120, 180)
tmGrid.CanvasSize = UDim2.new(0, 1720, 0, 0)
tmGrid.Parent = testModesView

-- Card 1: Animation Sparring Lab
createModeCard(
	tmGrid, 0, "Animation Sparring", "Stationary Calibration",
	"Spawns QuinA (Tester) and QuinB (Partner) 5 studs apart, locked in Idle. Perfect for scrubbing frames, dialing playback speeds, and testing combos.",
	C_ACCENT,
	function(btn)
		labEvent:FireServer("SetTestMode", { mode = "AnimationLab" })
		switchMainTab("Powerhouse")
	end
)

-- Card 2: Directional Block & Parry Lab
createModeCard(
	tmGrid, 240, "Block & Counter Lab", "Parry & Riposte Diagnostics",
	"Exercises directional blocking! QuinB guards against incoming strikes, rolling BlockFront, BlockLeft, or BlockRight, and immediately fires retaliatory riposte counters on success!",
	Color3.fromRGB(0, 230, 180),
	function(btn)
		labEvent:FireServer("SetTestMode", { mode = "BlockParryLab" })
		statusToast.Text = "ðŸ›¡ï¸ Directional Block & Counter Lab ACTIVE!"
		statusToast.TextColor3 = C_SUCCESS
	end
)

-- Card 3: 7 Jump Styles Trajectory Lab
createJumpStyleCard(tmGrid, 480)

-- Card 4: Infinite Strafe
createModeCard(
	tmGrid, 720, "Infinite Strafe", "Standoff Calibration",
	"Locks Quins into CirclingState standoff at 25-30 studs. Suppresses tension snaps so you can visually inspect and dial strafe speeds live.",
	Color3.fromRGB(0, 200, 240),
	function(btn)
		isInfiniteStrafeActive = not isInfiniteStrafeActive
		btn.Text = isInfiniteStrafeActive and "ACTIVE (Continuous) â– " or "Launch Mode â–¶"
		btn.BackgroundColor3 = isInfiniteStrafeActive and C_SUCCESS or Color3.fromRGB(0, 200, 240)
		labEvent:FireServer("SetTestMode", { mode = "InfiniteStrafe", active = isInfiniteStrafeActive })
		if isInfiniteStrafeActive and not isNormalCombatActive then
			isNormalCombatActive = true
			combatModeBtn.Text = "Combat: ACTIVE"
			combatModeBtn.BackgroundColor3 = Color3.fromRGB(0, 180, 120)
			combatModeBtn.TextColor3 = Color3.new(0, 0, 0)
			labEvent:FireServer("ToggleCombatMode", { enabled = true })
		end
		statusToast.Text = isInfiniteStrafeActive and "ðŸ§ª Infinite Strafe ACTIVE: Quins circle without snapping to fight." or "ðŸ§ª Infinite Strafe OFF."
		statusToast.TextColor3 = isInfiniteStrafeActive and C_SUCCESS or C_TEXT_MUTED
	end
)

-- Card 5: Smooth Landing AI
createModeCard(
	tmGrid, 960, "Smooth Landing AI", "Impact Absorption",
	"Isolates Quin ground-impact kinetics. Calibrates fall velocity dampening, foot alignment on uneven terrain, and transition into guard stance.",
	Color3.fromRGB(80, 170, 255),
	function(btn)
		labEvent:FireServer("SetTestMode", { mode = "SmoothLanding" })
		statusToast.Text = "ðŸ§ª Launched Smooth Landing AI Test Mode."
		statusToast.TextColor3 = C_SUCCESS
	end
)

-- Card 6: Tournament Elimination Bracket
createModeCard(
	tmGrid, 1200, "Tournament Bracket", "8-Quin Bracket Cup",
	"Executes the full automated 8-Quin elimination tournament from GameModeManager. Tracks bracket progress, quarterfinals, semifinals, and crowns the champion!",
	Color3.fromRGB(255, 200, 50),
	function(btn)
		labEvent:FireServer("SetTestMode", { mode = "Tournament" })
		statusToast.Text = "ðŸ† 8-Quin Tournament Elimination Bracket started!"
		statusToast.TextColor3 = C_SUCCESS
	end
)

-- Card 7: Deterministic Scenarios Evaluator
createModeCard(
	tmGrid, 1440, "Deterministic Test", "State Verification",
	"Spawns TypeA and TypeB facing each other with 3-2-1 countdown and forces TestState for deterministic physics and combat evaluation.",
	Color3.fromRGB(180, 110, 255),
	function(btn)
		labEvent:FireServer("SetTestMode", { mode = "DeterministicTest" })
		statusToast.Text = "ðŸ§ª Launched Deterministic Test Mode."
		statusToast.TextColor3 = C_SUCCESS
	end
)

end

--------------------------------------------------------------------------------
-- 9. EVENT LISTENERS & PRODUCTION SYNCHRONIZATION
--------------------------------------------------------------------------------
labEvent.OnClientEvent:Connect(function(cmd, data)
	data = data or {}
	if cmd == "OpenLab" then
		testerName = data.testerName or "QuinA_Tester"
		partnerName = data.partnerName or "QuinB_SparringPartner"
		mainFrame.Visible = true
		togglePill.Visible = false
	elseif cmd == "ConfigSnapshot" then
		if data.updates then
			for path, values in pairs(data.updates) do
				AnimationConfig.update(path, values)
			end
			-- Refresh UI if currently selected
			if currentEntryPath then
				local item = { path = currentEntryPath, name = currentEntryData.name or currentEntryPath }
				selectAnimation(item)
			end
		end
	elseif cmd == "ConfigUpdated" then
		if data.path and data.newValues then
			AnimationConfig.update(data.path, data.newValues)
			statusToast.Text = "âœ“ Hot-swapped " .. tostring(data.path) .. " live in combat!"
			statusToast.TextColor3 = C_SUCCESS
		end
	elseif cmd == "SaveResult" then
		if data.success then
			savePermBtn.Text = "âœ“ Saved to Production!"
			savePermBtn.BackgroundColor3 = C_SUCCESS
			statusToast.Text = "âœ“ " .. (data.message or "Saved permanently to production.")
			statusToast.TextColor3 = C_SUCCESS
		else
			savePermBtn.Text = "âš ï¸ Save Warning"
			savePermBtn.BackgroundColor3 = Color3.fromRGB(180, 60, 60)
			statusToast.Text = "âš ï¸ " .. (data.message or "Could not save.")
			statusToast.TextColor3 = C_DANGER
		end
		task.delay(3, function()
			savePermBtn.Text = "ðŸ’¾ Save Permanently to Production"
			savePermBtn.BackgroundColor3 = Color3.fromRGB(35, 95, 160)
		end)
	elseif cmd == "CombatModeChanged" then
		isNormalCombatActive = data.enabled == true
		combatModeBtn.Text = isNormalCombatActive and "Combat Mode: ACTIVE" or "Combat Mode: OFF"
		combatModeBtn.BackgroundColor3 = isNormalCombatActive and Color3.fromRGB(0, 180, 120) or Color3.fromRGB(48, 56, 74)
		combatModeBtn.TextColor3 = isNormalCombatActive and Color3.new(0, 0, 0) or C_TEXT
		statusToast.Text = isNormalCombatActive and "âš”ï¸ Combat ACTIVE: Quins fighting autonomously. Dials hot-swap mid-combat!" or "ðŸŽ¯ Lab Mode: Quins reset to stationary positions."
		statusToast.TextColor3 = isNormalCombatActive and Color3.fromRGB(0, 220, 130) or Color3.fromRGB(130, 210, 250)
	elseif cmd == "TestModeChanged" then
		if data.mode == "InfiniteStrafe" then
			isInfiniteStrafeActive = data.active == true
		end
	elseif cmd == "TesterRigsReady" then
		testerName = data.testerName or "QuinA_Tester"
		partnerName = data.partnerName or "QuinB_SparringPartner"
		if updateRigStatusBadge then updateRigStatusBadge() end
		if statusToast then
			statusToast.Text = "âœ“ Test Quins spawned and ready in arena!"
			statusToast.TextColor3 = C_SUCCESS
		end
	elseif cmd == "LocomotionConfigUpdated" then
		if data.key and data.value ~= nil then
			CombatConfig[data.key] = data.value
			if data.key == "WalkStrideBase" and walkStrideSlider then walkStrideSlider.setValue(data.value) end
			if data.key == "RunStrideBase" and runStrideSlider then runStrideSlider.setValue(data.value) end
			if data.key == "TorsoBankingMaxRoll" and maxRollSlider then maxRollSlider.setValue(data.value) end
			if data.key == "TorsoBankingResponsiveness" and bankRespSlider then bankRespSlider.setValue(data.value) end
			if data.key == "FootIK_RayDistance" and rayDistSlider then rayDistSlider.setValue(data.value) end
			if data.key == "FootIK_HeightOffset" and heightOffsetSlider then heightOffsetSlider.setValue(data.value) end
			if data.key == "FootIK_MaxStepDown" and maxStepDownSlider then maxStepDownSlider.setValue(data.value) end
			if data.key == "FootIK_HipsDipScale" and hipsDipSlider then hipsDipSlider.setValue(data.value) end
			if data.key == "FootIK_AnkleAlignment" and ankleBtn then
				isAnkleAlign = data.value ~= false
				ankleBtn.BackgroundColor3 = isAnkleAlign and C_PRIMARY or Color3.fromRGB(48, 56, 74)
				ankleBtn.Text = isAnkleAlign and "Surface Normal: ON" or "Surface Normal: FLAT"
			end
			if data.key == "FootIK_LedgeGrip" and ledgeBtn then
				isLedgeGrip = data.value ~= false
				ledgeBtn.BackgroundColor3 = isLedgeGrip and C_ACCENT or Color3.fromRGB(48, 56, 74)
				ledgeBtn.Text = isLedgeGrip and "Ledge Gripping: ON" or "Ledge Gripping: OFF"
			end
			if data.key == "Ragdoll_MuscleStiffness" and muscleStiffSlider then muscleStiffSlider.setValue(data.value) end
			if data.key == "Ragdoll_Damping" and dampingSlider then dampingSlider.setValue(data.value) end
			if data.key == "Ragdoll_TumbleScale" and tumbleScaleSlider then tumbleScaleSlider.setValue(data.value) end
			if data.key == "Ragdoll_GroundFriction" and groundFrictionSlider then groundFrictionSlider.setValue(data.value) end
			if data.key == "Ragdoll_RecoveryDelay" and recoveryDelaySlider then recoveryDelaySlider.setValue(data.value) end
			if statusToast then
				statusToast.Text = string.format("âœ“ Updated %s = %s", tostring(data.key), tostring(data.value))
				statusToast.TextColor3 = C_SUCCESS
			end
		end
	elseif cmd == "FootIKToggled" then
		isFootIKActive = data.enabled == true
		if ikToggleBtn then
			ikToggleBtn.Text = isFootIKActive and "Foot IK: ACTIVE (Conforming to Terrain)" or "Foot IK: OFF (Canned Poses Only)"
			ikToggleBtn.BackgroundColor3 = isFootIKActive and C_SUCCESS or Color3.fromRGB(48, 56, 74)
			ikToggleBtn.TextColor3 = isFootIKActive and Color3.new(0, 0, 0) or C_TEXT
		end
		if statusToast then
			statusToast.Text = isFootIKActive and "ðŸ¦¶ Foot IK ACTIVE: Feet conforming to terrain." or "ðŸ¦¶ Foot IK OFF."
			statusToast.TextColor3 = isFootIKActive and C_SUCCESS or C_TEXT_MUTED
		end
	elseif cmd == "RagdollModeChanged" then
		isContinuousRagdoll = data.active == true
		if toggleContinuousRagBtn then
			toggleContinuousRagBtn.Text = isContinuousRagdoll and "Continuous Ragdoll: ACTIVE (Loose Limbs)" or "Continuous Ragdoll: OFF"
			toggleContinuousRagBtn.BackgroundColor3 = isContinuousRagdoll and C_DANGER or Color3.fromRGB(48, 56, 74)
		end
		if statusToast then
			statusToast.Text = isContinuousRagdoll and "ðŸ’¥ Continuous Ragdoll ACTIVE on QuinA_Tester." or "ðŸ’¥ Ragdoll OFF: Rig upright."
			statusToast.TextColor3 = isContinuousRagdoll and Color3.fromRGB(255, 120, 120) or C_SUCCESS
		end
	elseif cmd == "KnockbackTestLaunched" then
		if statusToast then
			statusToast.Text = "ðŸ’¥ High Impulse Knockback Launching QuinA_Tester into Ragdoll!"
			statusToast.TextColor3 = C_ACCENT
		end
	elseif cmd == "KnockbackTestCompleted" then
		if statusToast then
			statusToast.Text = "âœ“ Ragdoll Impact Absorbed & Get-Up Recovery Completed!"
			statusToast.TextColor3 = C_SUCCESS
		end
	elseif cmd == "LocomotionTestStarted" then
		if statusToast then
			statusToast.Text = string.format("ðŸƒ Maneuver Test '%s' executing...", tostring(data.testType))
			statusToast.TextColor3 = C_ACCENT
		end
	elseif cmd == "LocomotionTestEnded" then
		if statusToast then
			statusToast.Text = string.format("âœ“ Maneuver Test '%s' completed successfully!", tostring(data.testType))
			statusToast.TextColor3 = C_SUCCESS
		end
	end
end)

-- Heartbeat to update rig status badge periodically when in Powerhouse view
local lastRigCheck = 0
RunService.Heartbeat:Connect(function()
	local now = os.clock()
	if now - lastRigCheck >= 1.0 then
		lastRigCheck = now
		if mainFrame and mainFrame.Visible and activeMainTab == "Powerhouse" then
			if updateRigStatusBadge then updateRigStatusBadge() end
		end
	end
end)

-- Request latest config overrides from server on startup
labEvent:FireServer("RequestConfigSnapshot")

print("[QuinManager] Unified Controller Ready: Powerhouse + Game Modes + Test Suite.")
