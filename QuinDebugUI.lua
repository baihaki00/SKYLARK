--// QuinDebugUI.client.lua
-- Creates a comprehensive, toggleable debug GUI for all Quins in the workspace
-- Displays stats, states, energy, and currently playing animations
-- Features: Clickable Quin cards for camera spectator tracking & Q/E key cycling

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local camera = Workspace.CurrentCamera

-- Create ScreenGui
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "QuinDebug"
screenGui.ResetOnSpawn = false
screenGui.Parent = playerGui

-- Create Toggle Button
local toggleBtn = Instance.new("TextButton")
toggleBtn.Size = UDim2.new(0, 140, 0, 30)
toggleBtn.Position = UDim2.new(1, -150, 0, 10)
toggleBtn.BackgroundColor3 = Color3.fromRGB(30, 30, 35)
toggleBtn.TextColor3 = Color3.fromRGB(255, 215, 0)
toggleBtn.Font = Enum.Font.GothamBold
toggleBtn.TextSize = 12
toggleBtn.Text = "Quin Telemetry [T]"
toggleBtn.Parent = screenGui

local btnCorner = Instance.new("UICorner")
btnCorner.CornerRadius = UDim.new(0, 6)
btnCorner.Parent = toggleBtn

-- Create Main Frame
local mainFrame = Instance.new("ScrollingFrame")
mainFrame.Size = UDim2.new(0, 360, 1, -60)
mainFrame.Position = UDim2.new(1, -370, 0, 48)
mainFrame.BackgroundColor3 = Color3.fromRGB(16, 18, 24)
mainFrame.BackgroundTransparency = 0.15
mainFrame.BorderSizePixel = 0
mainFrame.ScrollBarThickness = 6
mainFrame.Visible = true -- Open by default so user can track immediately
mainFrame.Parent = screenGui

local frameCorner = Instance.new("UICorner")
frameCorner.CornerRadius = UDim.new(0, 8)
frameCorner.Parent = mainFrame

local listLayout = Instance.new("UIListLayout")
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Padding = UDim.new(0, 8)
listLayout.Parent = mainFrame

local UIPadding = Instance.new("UIPadding")
UIPadding.PaddingTop = UDim.new(0, 8)
UIPadding.PaddingBottom = UDim.new(0, 8)
UIPadding.PaddingLeft = UDim.new(0, 8)
UIPadding.PaddingRight = UDim.new(0, 8)
UIPadding.Parent = mainFrame

local hintLabel = Instance.new("TextButton")
hintLabel.Name = "HintHeader"
hintLabel.Size = UDim2.new(1, 0, 0, 24)
hintLabel.BackgroundColor3 = Color3.fromRGB(24, 28, 38)
hintLabel.TextColor3 = Color3.fromRGB(200, 220, 255)
hintLabel.Font = Enum.Font.GothamMedium
hintLabel.TextSize = 10
hintLabel.Text = "CLICK CARD TO SPECTATE | Q / E CYCLE | [RESET CAM]"
hintLabel.LayoutOrder = 0
hintLabel.Parent = mainFrame

local hintCorner = Instance.new("UICorner")
hintCorner.CornerRadius = UDim.new(0, 4)
hintCorner.Parent = hintLabel

hintLabel.MouseButton1Click:Connect(function()
	trackQuin(nil)
end)

toggleBtn.MouseButton1Click:Connect(function()
	mainFrame.Visible = not mainFrame.Visible
end)

UserInputService.InputBegan:Connect(function(input, gpe)
	if gpe or UserInputService:GetFocusedTextBox() then return end
	if input.KeyCode == Enum.KeyCode.T then
		mainFrame.Visible = not mainFrame.Visible
	end
end)

-- ============================================================
-- CAMERA TRACKING ENGINE
-- ============================================================
local trackedQuin = nil
local quinFrames = {}

local function getOrderedQuins()
	local list = {}
	local serverFolder = Workspace:FindFirstChild("QuinServer")
	if serverFolder then
		for _, ch in ipairs(serverFolder:GetChildren()) do
			if ch:IsA("Model") and not ch.Name:find("_Visual") and ch.Parent then
				local hum = ch:FindFirstChildOfClass("Humanoid")
				if hum and hum.Health > 0 then
					table.insert(list, ch)
				end
			end
		end
	end
	if #list == 0 then
		for _, q in ipairs(CollectionService:GetTagged("Quin")) do
			if q:IsA("Model") and not q.Name:find("_Visual") and q.Parent then
				local hum = q:FindFirstChildOfClass("Humanoid")
				if hum and hum.Health > 0 then
					table.insert(list, q)
				end
			end
		end
	end
	table.sort(list, function(a, b) return a.Name < b.Name end)
	return list
end

local function trackQuin(quin)
	trackedQuin = quin
	if not quin then
		local char = player.Character
		if char and char:FindFirstChildOfClass("Humanoid") then
			camera.CameraSubject = char:FindFirstChildOfClass("Humanoid")
			camera.CameraType = Enum.CameraType.Custom
		end
		return
	end
	
	local hum = quin:FindFirstChildOfClass("Humanoid")
	if hum then
		-- If freecam is active, disable it so custom orbit tracks the Quin smoothly
		if _G.StopFreecam then
			_G.StopFreecam()
		elseif shared.StopFreecam then
			shared.StopFreecam()
		end
		camera.CameraSubject = hum
		camera.CameraType = Enum.CameraType.Custom
	end
end

local function cycleQuin(delta)
	local list = getOrderedQuins()
	if #list == 0 then return end
	local curIdx = 1
	for idx, q in ipairs(list) do
		if q == trackedQuin then
			curIdx = idx
			break
		end
	end
	curIdx = ((curIdx - 1 + delta) % #list) + 1
	trackQuin(list[curIdx])
end

-- Key listeners for Q and E
UserInputService.InputBegan:Connect(function(input, gpe)
	if gpe or UserInputService:GetFocusedTextBox() then return end
	if input.KeyCode == Enum.KeyCode.Q then
		cycleQuin(-1)
	elseif input.KeyCode == Enum.KeyCode.E then
		cycleQuin(1)
	end
end)

-- ============================================================
-- CARD CREATION & CLICK HANDLER
-- ============================================================
local function createQuinFrame(quin)
	local frame = Instance.new("Frame")
	frame.Size = UDim2.new(1, 0, 0, 140)
	frame.BackgroundColor3 = Color3.fromRGB(26, 28, 38)
	frame.BackgroundTransparency = 0.2
	frame.BorderSizePixel = 0
	
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = frame
	
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(255, 215, 0)
	stroke.Thickness = 0
	stroke.Parent = frame
	
	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, -10, 0, 22)
	title.Position = UDim2.new(0, 6, 0, 4)
	title.BackgroundTransparency = 1
	title.TextColor3 = Color3.fromRGB(255, 215, 80)
	title.Font = Enum.Font.GothamBold
	title.TextSize = 13
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = frame
	
	local content = Instance.new("TextLabel")
	content.Size = UDim2.new(1, -10, 1, -30)
	content.Position = UDim2.new(0, 6, 0, 28)
	content.BackgroundTransparency = 1
	content.TextColor3 = Color3.fromRGB(210, 210, 210)
	content.Font = Enum.Font.Code
	content.TextSize = 11
	content.TextXAlignment = Enum.TextXAlignment.Left
	content.TextYAlignment = Enum.TextYAlignment.Top
	content.RichText = true
	content.Parent = frame
	
	-- Full card click button
	local clickBtn = Instance.new("TextButton")
	clickBtn.Size = UDim2.new(1, 0, 1, 0)
	clickBtn.BackgroundTransparency = 1
	clickBtn.Text = ""
	clickBtn.ZIndex = 5
	clickBtn.Parent = frame
	
	clickBtn.MouseButton1Click:Connect(function()
		trackQuin(quin)
	end)
	
	return frame, title, content, stroke
end

-- ============================================================
-- UPDATE LOOP
-- ============================================================
RunService.RenderStepped:Connect(function()
	if not mainFrame.Visible then return end
	
	local quins = getOrderedQuins()
	
	-- Auto-cycle if currently spectated Quin dies or despawns
	if trackedQuin then
		local hum = trackedQuin:FindFirstChildOfClass("Humanoid")
		if not trackedQuin.Parent or not trackedQuin:IsDescendantOf(workspace) or not hum or hum.Health <= 0 then
			cycleQuin(1)
		end
	end
	
	-- Add new frames
	for _, quin in ipairs(quins) do
		if not quinFrames[quin] then
			local f, t, c, s = createQuinFrame(quin)
			f.Parent = mainFrame
			quinFrames[quin] = {frame = f, title = t, content = c, stroke = s}
		end
	end
	
	-- Remove old frames and update existing
	local totalHeight = 40
	for quin, data in pairs(quinFrames) do
		if not quin.Parent or not quin:IsDescendantOf(workspace) then
			data.frame:Destroy()
			quinFrames[quin] = nil
		else
			local humanoid = quin:FindFirstChildOfClass("Humanoid")
			if humanoid then
				local isTracked = (quin == trackedQuin)
				data.stroke.Thickness = isTracked and 2.0 or 0
				
				local team = quin:GetAttribute("Team") or "Solo"
				local nameColor = isTracked and "#FFD700" or "#FFAA50"
				data.title.Text = string.format("<font color='%s'><b>%s</b></font> [%s]%s", nameColor, quin.Name, team, isTracked and " 📷 TRACKING" or "")
				
				local hp = math.floor(humanoid.Health)
				local maxHp = humanoid.MaxHealth
				local energy = math.floor(quin:GetAttribute("Energy") or 0)
				local state = quin:GetAttribute("CurrentState") or "None"
				local targetQuin = quin:GetAttribute("TargetQuin") or "None"
				
				local anims = {}
				local animator = humanoid:FindFirstChildOfClass("Animator")
				if animator then
					for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
						if track.Weight > 0.01 then
							local id = tostring(track.Animation.AnimationId):gsub("rbxassetid://", "")
							table.insert(anims, string.format("[%s] Spd:%.1f", id, track.Speed))
						end
					end
				end
				local animStr = #anims > 0 and table.concat(anims, " | ") or "None"
				
				data.content.Text = string.format(
					"HP: <font color='#50FF50'>%d/%d</font> | EN: <font color='#50C8FF'>%d</font>\n" ..
					"State: <font color='#FFAA50'>%s</font> | Tgt: %s\n" ..
					"Anim: %s",
					hp, maxHp, energy, state, targetQuin, animStr
				)
				
				local targetHeight = 85
				data.frame.Size = UDim2.new(1, 0, 0, targetHeight)
				totalHeight = totalHeight + targetHeight + 8
			end
		end
	end
	
	mainFrame.CanvasSize = UDim2.new(0, 0, 0, totalHeight)
end)

print("[QuinDebugUI] Initialized with clickable card spectator tracking & Q/E cycling.")