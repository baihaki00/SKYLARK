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
togglePill.Text = "⚔️ Quin Manager [M]"
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
	{ id = "AnimCombinator", label = "🎛️ Animation Combinator" },
	{ id = "LocoIK", label = "🏃 Locomotion & IK" },
	{ id = "RagdollLab", label = "💥 Ragdoll Lab" },
	{ id = "Maneuvers", label = "🎮 Maneuvers" },
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
searchBox.Text = ""
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
	directIdHeader.Text = "⚡ DIRECT ID INSERTER"
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
	previewIdBtn.Text = "▶ Audition"
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
	libHeader.Text = "📚 PRE-REGISTERED LIBRARY"
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
	combSearchBox.PlaceholderText = "🔍 Search library (e.g. idle, punch)..."
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
	stackTitle.Text = "🎛️ COMBINATION STACK"
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
	clearStackBtn.Text = "🗑 Clear"
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
	transTitle.Text = "⚡ TRANSITION INSPECTOR"
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
	playTransitionBtn.Text = "⚡ Play Transition Only"
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
	presetsTitle.Text = "✨ QUICK PRESETS"
	presetsTitle.Size = UDim2.new(1, -12, 0, 20)
	presetsTitle.Position = UDim2.new(0, 6, 0, 160)
	presetsTitle.BackgroundTransparency = 1
	presetsTitle.TextColor3 = C_TEXT
	presetsTitle.Font = Enum.Font.GothamBold
	presetsTitle.TextSize = 11
	presetsTitle.TextXAlignment = Enum.TextXAlignment.Left
	presetsTitle.Parent = inspScroll

	local presetList = {
		{ name = "🏃 Run + 👊 Lead Punch", presetId = "RunPunch" },
		{ name = "🧘 Idle + ⚔️ Ready Stance", presetId = "IdleStance" },
		{ name = "⚡ Sprint + 🔄 180 Turn", presetId = "Sprint180" },
		{ name = "🦸 Superhero Landing", presetId = "SuperheroLanding" },
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
	exportStackBtn.Text = "📋 Export Stack to Luau"
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
	timeReadout.Text = "⏱ Scrub: 0.00s / 2.00s"
	timeReadout.Size = UDim2.new(0, 180, 0, 18)
	timeReadout.Position = UDim2.new(0, 10, 0, 4)
	timeReadout.BackgroundTransparency = 1
	timeReadout.TextColor3 = C_ACCENT
	timeReadout.Font = Enum.Font.GothamBold
	timeReadout.TextSize = 11
	timeReadout.TextXAlignment = Enum.TextXAlignment.Left
	timeReadout.Parent = bottomPanel

	local frameReadout = Instance.new("TextLabel")
	frameReadout.Text = "🎞 Frame: 0 / 60 (@ 30 FPS)"
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
	jumpStartBtn.Text = "⏮ Start"
	jumpStartBtn.Size = UDim2.new(0, 60, 0, 26)
	jumpStartBtn.Position = UDim2.new(0, 0, 0, 3)
	jumpStartBtn.BackgroundColor3 = Color3.fromRGB(38, 45, 60)
	jumpStartBtn.TextColor3 = C_TEXT
	jumpStartBtn.Font = Enum.Font.GothamBold
	jumpStartBtn.TextSize = 10
	jumpStartBtn.Parent = transportRow
	applyCorner(jumpStartBtn, 4)

	local stepBackBtn = Instance.new("TextButton")
	stepBackBtn.Text = "◀ 1 Frame"
	stepBackBtn.Size = UDim2.new(0, 75, 0, 26)
	stepBackBtn.Position = UDim2.new(0, 66, 0, 3)
	stepBackBtn.BackgroundColor3 = Color3.fromRGB(38, 45, 60)
	stepBackBtn.TextColor3 = C_TEXT
	stepBackBtn.Font = Enum.Font.GothamBold
	stepBackBtn.TextSize = 10
	stepBackBtn.Parent = transportRow
	applyCorner(stepBackBtn, 4)

	local playPauseBtn = Instance.new("TextButton")
	playPauseBtn.Text = "▶ Play Stack"
	playPauseBtn.Size = UDim2.new(0, 110, 0, 26)
	playPauseBtn.Position = UDim2.new(0, 147, 0, 3)
	playPauseBtn.BackgroundColor3 = C_ACCENT
	playPauseBtn.TextColor3 = Color3.new(0, 0, 0)
	playPauseBtn.Font = Enum.Font.GothamBold
	playPauseBtn.TextSize = 11
	playPauseBtn.Parent = transportRow
	applyCorner(playPauseBtn, 4)

	local stepFwdBtn = Instance.new("TextButton")
	stepFwdBtn.Text = "▶ 1 Frame"
	stepFwdBtn.Size = UDim2.new(0, 75, 0, 26)
	stepFwdBtn.Position = UDim2.new(0, 263, 0, 3)
	stepFwdBtn.BackgroundColor3 = Color3.fromRGB(38, 45, 60)
	stepFwdBtn.TextColor3 = C_TEXT
	stepFwdBtn.Font = Enum.Font.GothamBold
	stepFwdBtn.TextSize = 10
	stepFwdBtn.Parent = transportRow
	applyCorner(stepFwdBtn, 4)

	local jumpEndBtn = Instance.new("TextButton")
	jumpEndBtn.Text = "⏭ End"
	jumpEndBtn.Size = UDim2.new(0, 60, 0, 26)
	jumpEndBtn.Position = UDim2.new(0, 344, 0, 3)
	jumpEndBtn.BackgroundColor3 = Color3.fromRGB(38, 45, 60)
	jumpEndBtn.TextColor3 = C_TEXT
	jumpEndBtn.Font = Enum.Font.GothamBold
	jumpEndBtn.TextSize = 10
	jumpEndBtn.Parent = transportRow
	applyCorner(jumpEndBtn, 4)

	local loopBtn = Instance.new("TextButton")
	loopBtn.Text = "🔄 Loop: ON"
	loopBtn.Size = UDim2.new(0, 85, 0, 26)
	loopBtn.Position = UDim2.new(0, 410, 0, 3)
	loopBtn.BackgroundColor3 = Color3.fromRGB(30, 95, 65)
	loopBtn.TextColor3 = Color3.fromRGB(220, 255, 230)
	loopBtn.Font = Enum.Font.GothamBold
	loopBtn.TextSize = 10
	loopBtn.Parent = transportRow
	applyCorner(loopBtn, 4)

	local stopResetBtn = Instance.new("TextButton")
	stopResetBtn.Text = "■ Reset Idle"
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
		timeReadout.Text = string.format("⏱ Scrub: %.2fs / %.2fs", combinatorCurrentTime, combinatorGlobalDuration)
		local curFrame = math.floor(combinatorCurrentTime * 30)
		local maxFrame = math.floor(combinatorGlobalDuration * 30)
		frameReadout.Text = string.format("🎞 Frame: %d / %d (@ 30 FPS)", curFrame, maxFrame)

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
		playPauseBtn.Text = "⏸ Pause Stack"
		playPauseBtn.BackgroundColor3 = Color3.fromRGB(240, 175, 45)
		labEvent:FireServer("Combinator_PlayStack", {
			targetName = testerName,
			layers = getActiveLayersPayload(),
		})
		updateScrubberVisuals()
	end

	stopCombinatorPlayback = function()
		combinatorIsPlaying = false
		playPauseBtn.Text = "▶ Play Stack"
		playPauseBtn.BackgroundColor3 = C_ACCENT
		combinatorCurrentTime = 0.0
		if isTransitionTesting and transitionThread then
			task.cancel(transitionThread)
			isTransitionTesting = false
			playTransitionBtn.Text = "⚡ Play Transition Only"
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
				playPauseBtn.Text = "▶ Play Stack"
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
			playPauseBtn.Text = "▶ Play Stack"
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
		loopBtn.Text = combinatorLoop and "🔄 Loop: ON" or "🔄 Loop: OFF"
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
					playPauseBtn.Text = "▶ Play Stack"
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

	pla... (truncated)