--// QuinMindPanel.client.lua
-- The mind of the Quin you are spectating: health, mana, what it is doing and a running stream
-- of what it is thinking, in its own words (Modules/ThoughtVoice).
--
-- Separate from the Spectator HUD (QuinDebugHUD), which is left as it is. The panel appears
-- whenever a Quin is spectated (Workspace attribute SpectatedQuin, set by the Spectator HUD and
-- the Quin Manager) and hides when nobody is.
--
-- Only the watched Quin publishes its reasoning: this script tells the server which one that is
-- (MindWatchEvent), and DecisionSystem then writes that Quin's "Mind" attribute.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local ThoughtVoice = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("ThoughtVoice"))
local mindEvent = ReplicatedStorage:WaitForChild("MindWatchEvent")

local MAX_LINES = 60 -- thought lines kept to scroll back through
local FRESH_SECONDS = 6 -- a line is bright this long, then dims
local REPEAT_SECONDS = 4 -- the same thought is not said again sooner than this
local REFRESH = 0.1

local TEAM_COLORS = {
	TeamAlpha = Color3.fromRGB(90, 170, 255),
	TeamBeta = Color3.fromRGB(255, 110, 110),
}

----------------------------------------------------------------------------------------
-- Panel
----------------------------------------------------------------------------------------
local gui = Instance.new("ScreenGui")
gui.Name = "QuinMindPanel"
gui.ResetOnSpawn = false
gui.DisplayOrder = 40
gui.Enabled = false
gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

-- Bottom middle of the screen, wide and low: clear of the Spectator HUD on the left and the
-- menu buttons on the right. Who it is and how it is doing on the left, its thoughts beside that.
local DETAILS_WIDTH = 240

local panel = Instance.new("Frame")
panel.AnchorPoint = Vector2.new(0.5, 1)
panel.Position = UDim2.new(0.5, 40, 1, -12)
panel.Size = UDim2.new(0.42, 0, 0, 150)
panel.BackgroundColor3 = Color3.fromRGB(14, 18, 26)
panel.BackgroundTransparency = 0.12
panel.Parent = gui
Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 10)
local panelWidth = Instance.new("UISizeConstraint")
panelWidth.MinSize = Vector2.new(460, 150)
panelWidth.MaxSize = Vector2.new(700, 150)
panelWidth.Parent = panel

local function label(y: number, height: number, size: number, bold: boolean): TextLabel
	local l = Instance.new("TextLabel")
	l.Position = UDim2.fromOffset(12, y)
	l.Size = UDim2.fromOffset(DETAILS_WIDTH - 24, height)
	l.BackgroundTransparency = 1
	l.TextColor3 = Color3.fromRGB(235, 240, 250)
	l.Font = bold and Enum.Font.GothamBold or Enum.Font.Gotham
	l.TextSize = size
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextTruncate = Enum.TextTruncate.AtEnd
	l.Parent = panel
	return l
end

-- a bar with its number on it; returns the fill and the text
local function bar(y: number, color: Color3): (Frame, TextLabel)
	local back = Instance.new("Frame")
	back.Position = UDim2.fromOffset(12, y)
	back.Size = UDim2.fromOffset(DETAILS_WIDTH - 24, 16)
	back.BackgroundColor3 = Color3.fromRGB(34, 40, 54)
	back.Parent = panel
	Instance.new("UICorner", back).CornerRadius = UDim.new(0, 5)
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = color
	fill.Parent = back
	Instance.new("UICorner", fill).CornerRadius = UDim.new(0, 5)
	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.TextColor3 = Color3.new(1, 1, 1)
	text.Font = Enum.Font.GothamBold
	text.TextSize = 11
	text.ZIndex = 2
	text.Parent = back
	return fill, text
end

local nameLabel = label(8, 22, 16, true)
local roleLabel = label(30, 16, 11, false)
roleLabel.TextColor3 = Color3.fromRGB(160, 172, 196)
local healthFill, healthText = bar(52, Color3.fromRGB(80, 200, 110))
local manaFill, manaText = bar(72, Color3.fromRGB(80, 150, 255))
local doingLabel = label(96, 18, 12, true)
doingLabel.TextColor3 = Color3.fromRGB(255, 225, 140)
local optionsLabel = label(116, 14, 10, false)
optionsLabel.TextColor3 = Color3.fromRGB(130, 142, 166)

local stream = Instance.new("ScrollingFrame")
stream.Position = UDim2.fromOffset(DETAILS_WIDTH, 10)
stream.Size = UDim2.new(1, -DETAILS_WIDTH - 12, 1, -20)
stream.BackgroundTransparency = 1
stream.BorderSizePixel = 0
stream.ScrollBarThickness = 4
stream.AutomaticCanvasSize = Enum.AutomaticSize.Y
stream.CanvasSize = UDim2.new()
stream.Parent = panel
local layout = Instance.new("UIListLayout")
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Padding = UDim.new(0, 3)
layout.Parent = stream

----------------------------------------------------------------------------------------
-- Thought stream
----------------------------------------------------------------------------------------
local lines = {} -- { label, at }
local lineOrder = 0
local watchStart = os.clock()

local function clearStream()
	for _, line in lines do
		line.label:Destroy()
	end
	lines = {}
	watchStart = os.clock()
end

local function think(text: string)
	local elapsed = os.clock() - watchStart
	local l = Instance.new("TextLabel")
	l.Size = UDim2.new(1, -6, 0, 0)
	l.AutomaticSize = Enum.AutomaticSize.Y
	l.BackgroundTransparency = 1
	l.TextColor3 = Color3.fromRGB(240, 244, 252)
	l.Font = Enum.Font.GothamMedium
	l.TextSize = 13
	l.TextWrapped = true
	l.RichText = true
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Text = string.format('<font color="#7c88a4">%d:%02d</font>  %s', math.floor(elapsed / 60), math.floor(elapsed % 60), text)
	lineOrder += 1
	l.LayoutOrder = lineOrder
	l.Parent = stream
	table.insert(lines, { label = l, at = os.clock() })
	if #lines > MAX_LINES then
		table.remove(lines, 1).label:Destroy()
	end
	-- keep the newest in view
	task.defer(function()
		stream.CanvasPosition = Vector2.new(0, math.max(0, stream.AbsoluteCanvasSize.Y - stream.AbsoluteSize.Y))
	end)
end

----------------------------------------------------------------------------------------
-- The watched Quin
----------------------------------------------------------------------------------------
local watched: Model? = nil
local holding = {} -- thought keys that hold right now (a key is said once when it starts to hold)
local lastSaid = {} -- key -> when it was last said

local function findQuin(name: string?): Model?
	local folder = Workspace:FindFirstChild("QuinServer")
	local model = name and name ~= "" and folder and folder:FindFirstChild(name)
	return model and model:IsA("Model") and model or nil
end

local function watch(model: Model?)
	if model == watched then return end
	watched = model
	holding, lastSaid = {}, {}
	clearStream()
	mindEvent:FireServer(model and model.Name or "")
	gui.Enabled = model ~= nil
end

-- "action|tactical state|reason keys|best three options" (DecisionSystem)
local function readMind(model: Model)
	local mind = model:GetAttribute("Mind")
	if type(mind) ~= "string" then
		return nil, {}, ""
	end
	local parts = string.split(mind, "|")
	local reasons = {}
	for _, key in string.split(parts[3] or "", ",") do
		if key ~= "" then table.insert(reasons, key) end
	end
	local options = (parts[4] or ""):gsub(",", "   "):gsub(":", " ")
	return parts[1], reasons, options
end

local function refresh()
	local model = watched
	if not model then return end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not model.Parent or not humanoid then
		watch(nil)
		return
	end

	-- who
	local team = model:GetAttribute("Team")
	nameLabel.Text = model.Name
	nameLabel.TextColor3 = TEAM_COLORS[team] or Color3.fromRGB(235, 240, 250)
	local role = model:GetAttribute("SocialRole")
	roleLabel.Text = string.format("%s%s", tostring(team or "no team"), role and role ~= "" and ("  -  " .. tostring(role)) or "")

	-- health and mana
	local health = math.max(0, humanoid.Health)
	local healthRatio = math.clamp(health / math.max(1, humanoid.MaxHealth), 0, 1)
	healthFill.Size = UDim2.fromScale(healthRatio, 1)
	healthFill.BackgroundColor3 = Color3.fromRGB(220, 70, 70):Lerp(Color3.fromRGB(80, 200, 110), healthRatio)
	healthText.Text = string.format("HP  %d / %d", health, humanoid.MaxHealth)
	local energy = model:GetAttribute("Energy") or 0
	local maxEnergy = model:GetAttribute("MaxEnergy") or 100
	manaFill.Size = UDim2.fromScale(math.clamp(energy / math.max(1, maxEnergy), 0, 1), 1)
	manaText.Text = string.format("MANA  %d / %d", energy, maxEnergy)

	-- what it is doing, and what else it weighed
	local action, reasons, options = readMind(model)
	local target = model:GetAttribute("CurrentTarget") or model:GetAttribute("TargetQuin")
	local state = model:GetAttribute("CurrentState")
	doingLabel.Text = ThoughtVoice.doing(state, target)
	optionsLabel.Text = options

	-- thoughts: say each one once, when it starts to hold
	if health <= 0 then return end
	local keys = ThoughtVoice.keys({
		action = action,
		reasons = reasons,
		posture = model:GetAttribute("SocialPosture"),
		why = model:GetAttribute("SocialWhy"),
		respectRole = model:GetAttribute("RespectRole"),
		inWay = model:GetAttribute("BodyInWay") ~= nil,
		lost = state == "Idle" and (target == nil or target == ""),
	})
	local now, clock = {}, os.clock()
	for _, key in keys do
		now[key] = true
		if not holding[key] and clock - (lastSaid[key] or -math.huge) >= REPEAT_SECONDS then
			lastSaid[key] = clock
			think(ThoughtVoice.say(key, model:GetAttribute("Pers_Aggression")))
		end
	end
	holding = now
end

----------------------------------------------------------------------------------------
-- Run
----------------------------------------------------------------------------------------
local function sync()
	watch(findQuin(Workspace:GetAttribute("SpectatedQuin")))
end
Workspace:GetAttributeChangedSignal("SpectatedQuin"):Connect(sync)
sync()

local timer = 0
RunService.Heartbeat:Connect(function(dt)
	timer += dt
	if timer < REFRESH then return end
	timer = 0
	refresh()
	local clock = os.clock()
	for _, line in lines do
		line.label.TextTransparency = clock - line.at > FRESH_SECONDS and 0.45 or 0
	end
end)
