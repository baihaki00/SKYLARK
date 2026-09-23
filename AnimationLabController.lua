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

-- Floating Toggle Pill
local togglePill = Instance.new("TextButton")
togglePill.Size = UDim2.new(0, 180, 0, 36)
togglePill.Position = UDim2.new(1, -195, 0, 15)
togglePill.BackgroundColor3 = C_PANEL
togglePill.TextColor3 = C_ACCENT
togglePill.Font = Enum.Font.GothamBold
togglePill.TextSize = 12
togglePill.Text = "⚔️ Quin Manager [M]"
togglePill.Visible = true
togglePill.Parent = screenGui
applyCorner(togglePill, 18)
applyStroke(togglePill, C_ACCENT, 1.5)

updateRigStatusBadge = function()
	if not rigStatusBadge or not respawnRigsBtn then return false end
	local quinServer = Workspace:FindFirstChild("QuinServer")
	local tester = quinServer and quinServer:FindFirstChild(testerName)
	if tester and tester.Parent then
		local hum = tester:FindFirstChildOfClass("Humanoid")
		if hum and hum.Health > 0 then
			rigStatusBadge.Text = "● Rig: Ready"
			rigStatusBadge.TextColor3 = C_SUCCESS
			respawnRigsBtn.Text = "🔄 Reset Rig"
			respawnRigsBtn.BackgroundColor3 = Color3.fromRGB(35, 75, 110)
			return true
		end
	end
	rigStatusBadge.Text = "● Rig: Missing"
	rigStatusBadge.TextColor3 = Color3.fromRGB(255, 170, 40)
	respawnRigsBtn.Text = "⚡ Spawn Rig"
	respawnRigsBtn.BackgroundColor3 = Color3.fromRGB(180, 100, 30)
	return false
end

checkAndSpawnTesters = function(force)
	local isReady = updateRigStatusBadge and updateRigStatusBadge() or false
	if force or not isReady then
		if respawnRigsBtn then
			respawnRigsBtn.Text = "⏳ Spawning..."
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
titleLabel.Text = " ⚔️ QUIN MANAGER"
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
speedLabel.Text = "⚡ Speed:"
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
	{ id = "Powerhouse", label = "⚡ Animation Powerhouse" },
	{ id = "GameModes", label = "🎮 Game Modes" },
	{ id = "TestModes", label = "🧪 Test Modes" },
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
	{ id = "AnimStudio", label = "🎬 Animation Studio" },
	{ id = "LocoIK", label = "🏃 Locomotion & IK" },
	{ id = "RagdollLab", label = "💥 Ragdoll Lab" },
	{ id = "Maneuvers", label = "🎮 Maneuvers" },
}

-- 4 Sub-View Containers inside powerhouseView:
local animStudioView = Instance.new("Frame")
animStudioView.Name = "AnimStudioView"
animStudioView.Size = UDim2.new(1, 0, 1, -38)
animStudioView.Position = UDim2.new(0, 0, 0, 38)
animStudioView.BackgroundTransparency = 1
animStudioView.Parent = powerhouseView

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
rigStatusBadge.Text = "● Rig: Checking..."
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
respawnRigsBtn.Text = "🔄 Reset Rig"
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
searchBox.Size = UDim2.new(1, -30, 1, 0)
searchBox.Position = UDim2.new(0, 8, 0, 0)
searchBox.BackgroundTransparency = 1
searchBox.TextColor3 = C_TEXT
searchBox.PlaceholderText = "🔍 Search (e.g. idle, kick, block)..."
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
clearSearchBtn.Text = "✕"
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
playBtn.Text = "▶ Play Test"
playBtn.Parent = centerPanel
applyCorner(playBtn, 6)

local stopBtn = Instance.new("TextButton")
stopBtn.Size = UDim2.new(0, 110, 0, 30)
stopBtn.Position = UDim2.new(0, 126, 0, 352)
stopBtn.BackgroundColor3 = Color3.fromRGB(48, 56, 74)
stopBtn.TextColor3 = C_TEXT
stopBtn.Font = Enum.Font.GothamBold
stopBtn.TextSize = 11
stopBtn.Text = "■ Stop"
stopBtn.Parent = centerPanel
applyCorner(stopBtn, 6)

local hotSwapBtn = Instance.new("TextButton")
hotSwapBtn.Size = UDim2.new(0, 134, 0, 30)
hotSwapBtn.Position = UDim2.new(0, 244, 0, 352)
hotSwapBtn.BackgroundColor3 = Color3.fromRGB(30, 140, 85)
hotSwapBtn.TextColor3 = C_TEXT
hotSwapBtn.Font = Enum.Font.GothamBold
hotSwapBtn.TextSize = 11
hotSwapBtn.Text = "⚡ Hot-Swap Live"
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
savePermBtn.Text = "💾 Save Permanently to Production"
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
	hotSwapBtn.Text = "✓ Hot-Swapped!"
	hotSwapBtn.BackgroundColor3 = C_SUCCESS
	task.delay(1.5, function()
		hotSwapBtn.Text = "⚡ Hot-Swap Live"
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
playComboBtn.Text = "▶ Play Full Combo"
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

exportBtn.MouseButton1Click:Connect(function()
	local luauCode = AnimationConfig.exportLuau()
	modalTextBox.Text = luauCode
	modalScroll.CanvasSize = UDim2.new(0, 0, 0, 1400)
	modalBackdrop.Visible = true
end)

copyNotifyBtn.MouseButton1Click:Connect(function()
	local luauCode = AnimationConfig.exportLuau()
	print("========================================")
	print("QUIN ANIMATION CONFIG EXPORT:")
	print(luauCode)
	print("========================================")
	modalTextBox:CaptureFocus()
	copyNotifyBtn.Text = "✓ Printed to Console Output!"
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
locoTitle.Text = "🏃 CONTINUOUS LOCOMOTION TUNING"
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

maxRollSlider = createPrecisionSlider(locoCard, 142, "Torso Banking Max Roll", 0.0, 35.0, CombatConfig.TorsoBankingMaxRoll or 12.0, 1.0, "%.1f°", function(v)
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
ikTitle.Text = "🦶 PROCEDURAL FOOT IK (IKControl)"
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
ragTitle.Text = "💥 ACTIVE MUSCLE RAGDOLL CALIBRATION"
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
launchTitle.Text = "🧪 SPECTACLE TEST LAUNCHES"
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
highArcBtn.Text = "💥 Launch Test Knockback (High Arc Parabolic)"
highArcBtn.Parent = launchCard
applyCorner(highArcBtn, 6)

highArcBtn.MouseButton1Click:Connect(function()
	if checkAndSpawnTesters then checkAndSpawnTesters(false) end
	labEvent:FireServer("TestKnockbackLaunch", { style = "high_arc" })
	statusToast.Text = "💥 High Arc Parabolic Knockback Launched on QuinA_Tester!"
	statusToast.TextColor3 = C_ACCENT
end)

local lowSmashBtn = Instance.new("TextButton")
lowSmashBtn.Size = UDim2.new(1, -20, 0, 36)
lowSmashBtn.Position = UDim2.new(0, 10, 0, 96)
lowSmashBtn.BackgroundColor3 = Color3.fromRGB(220, 100, 40)
lowSmashBtn.TextColor3 = Color3.new(1, 1, 1)
lowSmashBtn.Font = Enum.Font.GothamBold
lowSmashBtn.TextSize = 11
lowSmashBtn.Text = "⚡ Launch Test Knockback (Low Smash Horizontal)"
lowSmashBtn.Parent = launchCard
applyCorner(lowSmashBtn, 6)

lowSmashBtn.MouseButton1Click:Connect(function()
	if checkAndSpawnTesters then checkAndSpawnTesters(false) end
	labEvent:FireServer("TestKnockbackLaunch", { style = "low_smash" })
	statusToast.Text = "⚡ Low Smash Horizontal Knockback Launched on QuinA_Tester!"
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
ragResetBtn.Text = "🔄 Reset Tester Upright & Stationary"
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
	actBtn.Text = "Execute Maneuver ▶"
	actBtn.Parent = card
	applyCorner(actBtn, 6)

	actBtn.MouseButton1Click:Connect(function()
		if onClick then onClick(actBtn) end
	end)
end

createManeuverCard(
	manGrid, 0, "Sprint & 180° Cut", "Directional Pivot",
	"Commands QuinA_Tester to sprint at 50 studs/s, execute an instant 180-degree directional pivot, and sprint back. Inspects stride scaling and anti-sliding.",
	Color3.fromRGB(0, 220, 255),
	function(btn)
		labEvent:FireServer("RunLocomotionTest", { testType = "Sprint180" })
		statusToast.Text = "🏃 Executing Sprint & 180° Cut maneuver..."
		statusToast.TextColor3 = C_ACCENT
	end
)

createManeuverCard(
	manGrid, 238, "Arc Run 30°", "Centripetal Banking",
	"Drives QuinA_Tester along a 28-stud radius circular orbital path at 44 studs/s, tilting the torso roll angle into the turn based on centripetal speed.",
	Color3.fromRGB(160, 220, 40),
	function(btn)
		labEvent:FireServer("RunLocomotionTest", { testType = "ArcRun" })
		statusToast.Text = "🌀 Executing 30° Centripetal Arc Run maneuver..."
		statusToast.TextColor3 = Color3.fromRGB(180, 240, 50)
	end
)

createManeuverCard(
	manGrid, 476, "Sprint & Hard Brake", "Kinetic Skid",
	"Sprints forward at 52 studs/s and halts abruptly into a kinetic skid stop, testing deceleration friction decay and transition into combat idle.",
	Color3.fromRGB(255, 160, 40),
	function(btn)
		labEvent:FireServer("RunLocomotionTest", { testType = "SprintBrake" })
		statusToast.Text = "🛑 Executing Sprint & Hard Brake skid..."
		statusToast.TextColor3 = Color3.fromRGB(255, 180, 50)
	end
)

createManeuverCard(
	manGrid, 714, "Diagnostic Filmstrip", "Python Capture Ready",
	"Positions camera and arms QuinA_Tester for high-frequency burst frame captures via inspect_locomotion_cycle.py.",
	Color3.fromRGB(220, 100, 255),
	function(btn)
		statusToast.Text = "📸 Diagnostic Burst Ready: Run inspect_locomotion_cycle.py in terminal!"
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
			"Rig: %s\nHorizontal Speed: %.1f studs/s\nWalkSpeed: %.1f\nCalculated Stride Scale: %.2fx (Base: %.1f)\nCurrent Torso Bank Roll: %.1f° (Max: %.1f°)",
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
	launchBtn.Text = "Launch Mode ▶"
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
	launchBtn.Text = "Launch 4 vs 4 ▶"
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
				launchBtn.Text = "Launch 16 vs 16 (Arena War) ▶"
			else
				launchBtn.Text = "Launch " .. tostring(selectedTeamCount) .. " vs " .. tostring(selectedTeamCount) .. " ▶"
			end
		end)
	end

	launchBtn.MouseButton1Click:Connect(function()
		labEvent:FireServer("SetGameMode", { mode = "team", count = selectedTeamCount })
		statusToast.Text = string.format("🎮 Launched %d vs %d Team Battle (%d Quins total).", 
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
		statusToast.Text = "🎮 Launched 1v1 Sparring Match."
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
		statusToast.Text = "⚔️ Launched Mid-Air Clash Duel Mode."
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
		statusToast.Text = "🎮 Launched 8-Man Free-For-All Battle Mode."
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
		statusToast.Text = "🧹 Arena cleared."
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
	launchBtn.Text = "Launch Style 1 (Vertical) ▶"
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
			launchBtn.Text = string.format("Launch Style %d (%s) ▶", selectedStyle, st.name)
		end)
	end

	launchBtn.MouseButton1Click:Connect(function()
		labEvent:FireServer("SetTestMode", { mode = "ProjectileJump", style = selectedStyle })
		statusToast.Text = string.format("🧪 Launched Projectile Jump Style %d (%s).", selectedStyle, styles[selectedStyle].name)
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
		statusToast.Text = "🛡️ Directional Block & Counter Lab ACTIVE!"
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
		btn.Text = isInfiniteStrafeActive and "ACTIVE (Continuous) ■" or "Launch Mode ▶"
		btn.BackgroundColor3 = isInfiniteStrafeActive and C_SUCCESS or Color3.fromRGB(0, 200, 240)
		labEvent:FireServer("SetTestMode", { mode = "InfiniteStrafe", active = isInfiniteStrafeActive })
		if isInfiniteStrafeActive and not isNormalCombatActive then
			isNormalCombatActive = true
			combatModeBtn.Text = "Combat: ACTIVE"
			combatModeBtn.BackgroundColor3 = Color3.fromRGB(0, 180, 120)
			combatModeBtn.TextColor3 = Color3.new(0, 0, 0)
			labEvent:FireServer("ToggleCombatMode", { enabled = true })
		end
		statusToast.Text = isInfiniteStrafeActive and "🧪 Infinite Strafe ACTIVE: Quins circle without snapping to fight." or "🧪 Infinite Strafe OFF."
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
		statusToast.Text = "🧪 Launched Smooth Landing AI Test Mode."
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
		statusToast.Text = "🏆 8-Quin Tournament Elimination Bracket started!"
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
		statusToast.Text = "🧪 Launched Deterministic Test Mode."
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
			statusToast.Text = "✓ Hot-swapped " .. tostring(data.path) .. " live in combat!"
			statusToast.TextColor3 = C_SUCCESS
		end
	elseif cmd == "SaveResult" then
		if data.success then
			savePermBtn.Text = "✓ Saved to Production!"
			savePermBtn.BackgroundColor3 = C_SUCCESS
			statusToast.Text = "✓ " .. (data.message or "Saved permanently to production.")
			statusToast.TextColor3 = C_SUCCESS
		else
			savePermBtn.Text = "⚠️ Save Warning"
			savePermBtn.BackgroundColor3 = Color3.fromRGB(180, 60, 60)
			statusToast.Text = "⚠️ " .. (data.message or "Could not save.")
			statusToast.TextColor3 = C_DANGER
		end
		task.delay(3, function()
			savePermBtn.Text = "💾 Save Permanently to Production"
			savePermBtn.BackgroundColor3 = Color3.fromRGB(35, 95, 160)
		end)
	elseif cmd == "CombatModeChanged" then
		isNormalCombatActive = data.enabled == true
		combatModeBtn.Text = isNormalCombatActive and "Combat Mode: ACTIVE" or "Combat Mode: OFF"
		combatModeBtn.BackgroundColor3 = isNormalCombatActive and Color3.fromRGB(0, 180, 120) or Color3.fromRGB(48, 56, 74)
		combatModeBtn.TextColor3 = isNormalCombatActive and Color3.new(0, 0, 0) or C_TEXT
		statusToast.Text = isNormalCombatActive and "⚔️ Combat ACTIVE: Quins fighting autonomously. Dials hot-swap mid-combat!" or "🎯 Lab Mode: Quins reset to stationary positions."
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
			statusToast.Text = "✓ Test Quins spawned and ready in arena!"
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
				statusToast.Text = string.format("✓ Updated %s = %s", tostring(data.key), tostring(data.value))
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
			statusToast.Text = isFootIKActive and "🦶 Foot IK ACTIVE: Feet conforming to terrain." or "🦶 Foot IK OFF."
			statusToast.TextColor3 = isFootIKActive and C_SUCCESS or C_TEXT_MUTED
		end
	elseif cmd == "RagdollModeChanged" then
		isContinuousRagdoll = data.active == true
		if toggleContinuousRagBtn then
			toggleContinuousRagBtn.Text = isContinuousRagdoll and "Continuous Ragdoll: ACTIVE (Loose Limbs)" or "Continuous Ragdoll: OFF"
			toggleContinuousRagBtn.BackgroundColor3 = isContinuousRagdoll and C_DANGER or Color3.fromRGB(48, 56, 74)
		end
		if statusToast then
			statusToast.Text = isContinuousRagdoll and "💥 Continuous Ragdoll ACTIVE on QuinA_Tester." or "💥 Ragdoll OFF: Rig upright."
			statusToast.TextColor3 = isContinuousRagdoll and Color3.fromRGB(255, 120, 120) or C_SUCCESS
		end
	elseif cmd == "KnockbackTestLaunched" then
		if statusToast then
			statusToast.Text = "💥 High Impulse Knockback Launching QuinA_Tester into Ragdoll!"
			statusToast.TextColor3 = C_ACCENT
		end
	elseif cmd == "KnockbackTestCompleted" then
		if statusToast then
			statusToast.Text = "✓ Ragdoll Impact Absorbed & Get-Up Recovery Completed!"
			statusToast.TextColor3 = C_SUCCESS
		end
	elseif cmd == "LocomotionTestStarted" then
		if statusToast then
			statusToast.Text = string.format("🏃 Maneuver Test '%s' executing...", tostring(data.testType))
			statusToast.TextColor3 = C_ACCENT
		end
	elseif cmd == "LocomotionTestEnded" then
		if statusToast then
			statusToast.Text = string.format("✓ Maneuver Test '%s' completed successfully!", tostring(data.testType))
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
