--// MenuController.client.lua
-- Quin Manager Menu & Quin-by-Quin Spectator Camera Tracker
-- Tailored for debugging single combat and massive 16v16 arena battles

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

local localPlayer = Players.LocalPlayer
local camera = Workspace.CurrentCamera
local GameCommand = ReplicatedStorage:WaitForChild("GameCommand")

local screenGui = script:FindFirstAncestorOfClass("ScreenGui") or script.Parent
local mainFrame = script.Parent:IsA("Frame") and script.Parent or script.Parent:FindFirstChild("MainFrame")

-- Ensure main frame is nicely sized and styled
if mainFrame then
	mainFrame.Size = UDim2.new(0, 320, 0, 360)
	mainFrame.Position = UDim2.new(0, 20, 0, 80)
	mainFrame.BackgroundColor3 = Color3.fromRGB(18, 18, 24)
	mainFrame.BackgroundTransparency = 0.15
	mainFrame.BorderSizePixel = 0
	mainFrame.Visible = false -- Starts minimized/hidden; press M to open
	
	-- Title
	local title = mainFrame:FindFirstChild("Title") or Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, 0, 0, 32)
	title.Position = UDim2.new(0, 0, 0, 0)
	title.BackgroundColor3 = Color3.fromRGB(28, 28, 38)
	title.TextColor3 = Color3.fromRGB(255, 215, 0)
	title.Font = Enum.Font.GothamBold
	title.TextSize = 13
	title.Text = "QUIN MANAGER & ARENA TRACKER [M]"
	title.Parent = mainFrame
	
	local titleCorner = Instance.new("UICorner")
	titleCorner.CornerRadius = UDim.new(0, 6)
	titleCorner.Parent = title
end

-- ============================================================
-- SPECTATOR CAMERA STATE
-- ============================================================
local trackedQuin = nil
local trackedIndex = 1
local actionCamEnabled = true
local isSpectating = false

local function getActiveQuins()
	local quins = {}
	local serverFolder = Workspace:FindFirstChild("QuinServer")
	if serverFolder then
		for _, child in ipairs(serverFolder:GetChildren()) do
			if child:IsA("Model") and not child.Name:find("_Visual") then
				local hum = child:FindFirstChildOfClass("Humanoid")
				if hum and hum.Health > 0 then
					table.insert(quins, child)
				end
			end
		end
	end
	if #quins == 0 then
		for _, tagged in ipairs(CollectionService:GetTagged("Quin")) do
			if tagged:IsA("Model") and not tagged.Name:find("_Visual") then
				local hum = tagged:FindFirstChildOfClass("Humanoid")
				if hum and hum.Health > 0 then
					table.insert(quins, tagged)
				end
			end
		end
	end
	table.sort(quins, function(a, b) return a.Name < b.Name end)
	return quins
end

local function setTrackedQuin(quin)
	trackedQuin = quin
	if quin then
		local hum = quin:FindFirstChildOfClass("Humanoid")
		if hum then
			camera.CameraSubject = hum
			camera.CameraType = Enum.CameraType.Custom
			isSpectating = true
		end
	else
		isSpectating = false
		local char = localPlayer.Character
		if char and char:FindFirstChildOfClass("Humanoid") then
			camera.CameraSubject = char:FindFirstChildOfClass("Humanoid")
		end
	end
end

local function cycleQuin(delta)
	local quins = getActiveQuins()
	if #quins == 0 then
		setTrackedQuin(nil)
		return
	end
	trackedIndex = ((trackedIndex - 1 + delta) % #quins) + 1
	setTrackedQuin(quins[trackedIndex])
end

-- ============================================================
-- UI BUILDER: HUD OVERLAY & CONTROL BUTTONS
-- ============================================================
-- 1. Container for Spectator Controls
local specFrame = Instance.new("Frame")
specFrame.Name = "SpecControls"
specFrame.Size = UDim2.new(1, -20, 0, 80)
specFrame.Position = UDim2.new(0, 10, 0, 40)
specFrame.BackgroundColor3 = Color3.fromRGB(24, 24, 32)
specFrame.BackgroundTransparency = 0.3
specFrame.Parent = mainFrame

local specCorner = Instance.new("UICorner")
specCorner.CornerRadius = UDim.new(0, 6)
specCorner.Parent = specFrame

-- Tracked info labels
local infoLabel = Instance.new("TextLabel")
infoLabel.Name = "TrackedInfo"
infoLabel.Size = UDim2.new(1, -10, 0, 20)
infoLabel.Position = UDim2.new(0, 5, 0, 5)
infoLabel.BackgroundTransparency = 1
infoLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
infoLabel.Font = Enum.Font.GothamMedium
infoLabel.TextSize = 11
infoLabel.TextXAlignment = Enum.TextXAlignment.Left
infoLabel.Text = "Track: None (Press Q/E to cycle)"
infoLabel.Parent = specFrame

local statusLabel = Instance.new("TextLabel")
statusLabel.Name = "StatusInfo"
statusLabel.Size = UDim2.new(1, -10, 0, 18)
statusLabel.Position = UDim2.new(0, 5, 0, 24)
statusLabel.BackgroundTransparency = 1
statusLabel.TextColor3 = Color3.fromRGB(100, 255, 120)
statusLabel.Font = Enum.Font.Code
statusLabel.TextSize = 10
statusLabel.TextXAlignment = Enum.TextXAlignment.Left
statusLabel.Text = "HP: -- | State: --"
statusLabel.Parent = specFrame

-- Prev / Next Buttons
local prevBtn = Instance.new("TextButton")
prevBtn.Name = "PrevBtn"
prevBtn.Size = UDim2.new(0.3, -4, 0, 26)
prevBtn.Position = UDim2.new(0, 5, 0, 48)
prevBtn.BackgroundColor3 = Color3.fromRGB(40, 40, 55)
prevBtn.TextColor3 = Color3.new(1, 1, 1)
prevBtn.Font = Enum.Font.GothamBold
prevBtn.TextSize = 11
prevBtn.Text = "< Prev (Q)"
prevBtn.Parent = specFrame

local nextBtn = Instance.new("TextButton")
nextBtn.Name = "NextBtn"
nextBtn.Size = UDim2.new(0.3, -4, 0, 26)
nextBtn.Position = UDim2.new(0.35, 0, 0, 48)
nextBtn.BackgroundColor3 = Color3.fromRGB(40, 40, 55)
nextBtn.TextColor3 = Color3.new(1, 1, 1)
nextBtn.Font = Enum.Font.GothamBold
nextBtn.TextSize = 11
nextBtn.Text = "Next (E) >"
nextBtn.Parent = specFrame

local freeBtn = Instance.new("TextButton")
freeBtn.Name = "FreeCamBtn"
freeBtn.Size = UDim2.new(0.32, -4, 0, 26)
freeBtn.Position = UDim2.new(0.68, 0, 0, 48)
freeBtn.BackgroundColor3 = Color3.fromRGB(60, 30, 30)
freeBtn.TextColor3 = Color3.new(1, 1, 1)
freeBtn.Font = Enum.Font.GothamBold
freeBtn.TextSize = 10
freeBtn.Text = "Reset (F)"
freeBtn.Parent = specFrame

prevBtn.MouseButton1Click:Connect(function() cycleQuin(-1) end)
nextBtn.MouseButton1Click:Connect(function() cycleQuin(1) end)
freeBtn.MouseButton1Click:Connect(function() setTrackedQuin(nil) end)

-- Action Cam Toggle
local actionCamBtn = Instance.new("TextButton")
actionCamBtn.Name = "ActionCamBtn"
actionCamBtn.Size = UDim2.new(1, -20, 0, 24)
actionCamBtn.Position = UDim2.new(0, 10, 0, 126)
actionCamBtn.BackgroundColor3 = Color3.fromRGB(20, 50, 40)
actionCamBtn.TextColor3 = Color3.fromRGB(150, 255, 180)
actionCamBtn.Font = Enum.Font.GothamBold
actionCamBtn.TextSize = 11
actionCamBtn.Text = "ACTION CAM: ON (Auto-tracks Air Clash)"
actionCamBtn.Parent = mainFrame

actionCamBtn.MouseButton1Click:Connect(function()
	actionCamEnabled = not actionCamEnabled
	if actionCamEnabled then
		actionCamBtn.BackgroundColor3 = Color3.fromRGB(20, 50, 40)
		actionCamBtn.TextColor3 = Color3.fromRGB(150, 255, 180)
		actionCamBtn.Text = "ACTION CAM: ON (Auto-tracks Air Clash)"
	else
		actionCamBtn.BackgroundColor3 = Color3.fromRGB(45, 30, 30)
		actionCamBtn.TextColor3 = Color3.fromRGB(255, 160, 160)
		actionCamBtn.Text = "ACTION CAM: OFF (Manual Only)"
	end
end)

-- 2. Scenario Buttons Container
local scenarioLabel = Instance.new("TextLabel")
scenarioLabel.Size = UDim2.new(1, -20, 0, 18)
scenarioLabel.Position = UDim2.new(0, 10, 0, 156)
scenarioLabel.BackgroundTransparency = 1
scenarioLabel.TextColor3 = Color3.fromRGB(200, 200, 220)
scenarioLabel.Font = Enum.Font.GothamBold
scenarioLabel.TextSize = 11
scenarioLabel.TextXAlignment = Enum.TextXAlignment.Left
scenarioLabel.Text = "ARENA SCENARIOS & BRAWLS:"
scenarioLabel.Parent = mainFrame

local function makeScenarioBtn(name, yPos, text, color, cmd, arg)
	local b = Instance.new("TextButton")
	b.Name = name
	b.Size = UDim2.new(1, -20, 0, 28)
	b.Position = UDim2.new(0, 10, 0, yPos)
	b.BackgroundColor3 = color
	b.TextColor3 = Color3.new(1, 1, 1)
	b.Font = Enum.Font.GothamBold
	b.TextSize = 11
	b.Text = text
	b.Parent = mainFrame
	
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 5)
	c.Parent = b
	
	b.MouseButton1Click:Connect(function()
		GameCommand:FireServer(cmd, arg)
	end)
	return b
end

makeScenarioBtn("BtnMidAir", 178, "MIDAIR CLASH DUEL (Z-Relocating Brawl)", Color3.fromRGB(70, 40, 110), "midair_clash")
makeScenarioBtn("Btn1v1", 212, "1 vs 1 SPARRING MATCH", Color3.fromRGB(35, 55, 85), "team", 1)
makeScenarioBtn("Btn4v4", 246, "4 vs 4 TEAM SKIRMISH", Color3.fromRGB(40, 70, 60), "team", 4)
makeScenarioBtn("Btn16v16", 280, "16 vs 16 ARENA WAR (32 Quins)", Color3.fromRGB(110, 35, 35), "team", 16)
makeScenarioBtn("BtnClean", 316, "RESET ARENA / CLEAR QUINS", Color3.fromRGB(50, 45, 50), "clean")

-- ============================================================
-- INPUT BINDINGS (Q, E, F, M to toggle menu)
-- ============================================================
UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.Q then
		cycleQuin(-1)
	elseif input.KeyCode == Enum.KeyCode.E then
		cycleQuin(1)
	elseif input.KeyCode == Enum.KeyCode.F then
		setTrackedQuin(nil)
	elseif input.KeyCode == Enum.KeyCode.M then
		if mainFrame then
			mainFrame.Visible = not mainFrame.Visible
		end
	end
end)

-- ============================================================
-- RENDERSTEPPED LOOP: TELEMETRY HUD & ACTION CAM
-- ============================================================
RunService.RenderStepped:Connect(function()
	local quins = getActiveQuins()
	
	-- Action Cam: Automatically switch to active MidAirClash
	if actionCamEnabled then
		for _, q in ipairs(quins) do
			if q:GetAttribute("CurrentState") == "MidAirClash" then
				if trackedQuin ~= q and (not trackedQuin or trackedQuin:GetAttribute("CurrentState") ~= "MidAirClash") then
					setTrackedQuin(q)
					break
				end
			end
		end
	end
	
	-- Verify trackedQuin validity
	if trackedQuin and (not trackedQuin.Parent or not trackedQuin:FindFirstChildOfClass("Humanoid") or trackedQuin:FindFirstChildOfClass("Humanoid").Health <= 0) then
		cycleQuin(1)
	end
	
	-- Update HUD
	if trackedQuin and trackedQuin.Parent then
		local hum = trackedQuin:FindFirstChildOfClass("Humanoid")
		local hrp = trackedQuin:FindFirstChild("HumanoidRootPart")
		local team = trackedQuin:GetAttribute("Team") or "Solo"
		local state = trackedQuin:GetAttribute("CurrentState") or "None"
		local tgt = trackedQuin:GetAttribute("TargetQuin") or "None"
		local hp = hum and math.floor(hum.Health) or 0
		local maxHp = hum and math.floor(hum.MaxHealth) or 100
		
		infoLabel.Text = string.format("[%d/%d] %s (%s)", trackedIndex, #quins, trackedQuin.Name, team)
		statusLabel.Text = string.format("HP: %d/%d | State: %s | Tgt: %s", hp, maxHp, state, tgt)
	else
		infoLabel.Text = string.format("Tracking: Player / Free (%d active Quins)", #quins)
		statusLabel.Text = "Press Q / E to spectate a Quin | M to toggle menu"
	end
end)

print("[QuinManager] Initialized with Spectator Camera and Arena Scenarios.")
