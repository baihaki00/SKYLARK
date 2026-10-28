--// QuinDebugHUD.client.lua
-- Canonical Left-Side HUD: Live telemetry, authoritative AnimationTrack display,
-- Runtime Execution Tracing breadcrumbs, clickable Quin spectate cards & Q/E cycling.
-- Smooth GTA camera tracking integration via shared.SpectatedQuin & Workspace SpectatedQuin attribute.

local StarterGui = game:GetService("StarterGui")
pcall(function() StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Chat, false) end)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera

local QuinCore = ReplicatedStorage:WaitForChild("QuinCore")
local RuntimeVisualizer = nil
-- (the server writes the debug-only attributes - trace, retreat score, target reason - only while
-- this screen is open; DebugReadouts)
local DebugReadouts = require(QuinCore:WaitForChild("Modules"):WaitForChild("DebugReadouts"))
pcall(function()
	RuntimeVisualizer = require(QuinCore:WaitForChild("Modules"):WaitForChild("RuntimeVisualizer"))
end)

-- ============================================================
-- AUTHORITATIVE ANIMATION REGISTRY LOOKUP
-- ============================================================
local animNameLookup = {
	["rbxassetid://109837817595150"] = "Idle / Block",
	["rbxassetid://109090784752055"] = "Run / Sprint",
	["rbxassetid://133182359318358"] = "Dash",
	["rbxassetid://74552125029304"]  = "WalkConfident / WalkThug",
	["rbxassetid://85622241844167"]  = "Jump",
	["rbxassetid://79340771026707"]  = "Fall",
	["rbxassetid://88475997278069"]  = "FallAirKnockback",
	["rbxassetid://90752953215195"]  = "LeftPunch",
	["rbxassetid://100294955898321"] = "RightPunch / DesperateCounter",
	["rbxassetid://120201409079711"] = "LowKickRight",
	["rbxassetid://128873647170869"] = "LowKickLeft",
	["rbxassetid://112847704540861"] = "HighKickRight / Special / RivalFinisher",
	["rbxassetid://78628980439076"]  = "HighKickLeft",
	["rbxassetid://72225232579765"]  = "WheelDriveRight / Slam",
	["rbxassetid://103890244670922"] = "WheelDriveLeft",
	["rbxassetid://83869147275692"]  = "HitLight / Knockback",
	["rbxassetid://82096408080514"]  = "HitHeavy",
	["rbxassetid://79207866638803"]  = "GetUpBackFast",
	["rbxassetid://82291519563301"]  = "StrafeRightWalk",
	["rbxassetid://71421932655009"]  = "StrafeLeftWalk",
	["rbxassetid://107962284182266"] = "StrafeRightRun",
	["rbxassetid://123318024844911"] = "StrafeLeftRun",
	["rbxassetid://110691224052109"] = "StrafeRightTired",
	["rbxassetid://91032818959845"]  = "StrafeLeftTired",
}

-- Populate dynamically from AnimationConfig registry if available
pcall(function()
	local qc = ReplicatedStorage:FindFirstChild("QuinCore")
	if qc and qc:FindFirstChild("AnimationConfig") then
		local AnimationConfig = require(qc.AnimationConfig)
		local function scanRegistry(tbl)
			if type(tbl) ~= "table" then return end
			for k, v in pairs(tbl) do
				if type(v) == "table" then
					if v.id then
						local rawId = tostring(v.id)
						local name = v.name or k
						animNameLookup[rawId] = name
						local num = rawId:match("%d+")
						if num then
							animNameLookup[num] = name
							animNameLookup["rbxassetid://" .. num] = name
						end
					else
						scanRegistry(v)
					end
				end
			end
		end
		scanRegistry(AnimationConfig.Registry)
	end
end)

-- Helper to inspect active authoritative AnimationTrack from Animator
local function getAuthoritativeAnimation(model)
	if not model then return nil end
	local tracks = {}

	-- 1. Check direct Humanoid on model
	local hum = model:FindFirstChildOfClass("Humanoid")
	local anim = hum and hum:FindFirstChildOfClass("Animator")
	if anim then
		tracks = anim:GetPlayingAnimationTracks()
	elseif hum then
		tracks = hum:GetPlayingAnimationTracks()
	end

	-- 2. Fallback check on Client Ghost in Workspace.QuinGhost
	if #tracks == 0 then
		local qGhost = Workspace:FindFirstChild("QuinGhost")
		local ghost = qGhost and qGhost:FindFirstChild(model.Name .. "_Visual")
		local gHum = ghost and ghost:FindFirstChildOfClass("Humanoid")
		local gAnim = gHum and gHum:FindFirstChildOfClass("Animator")
		if gAnim then
			tracks = gAnim:GetPlayingAnimationTracks()
		elseif gHum then
			tracks = gHum:GetPlayingAnimationTracks()
		end
	end

	if #tracks == 0 then return nil end

	-- Find highest priority track (prioritize active combat/movement over background idle)
	local bestTrack = nil
	for _, t in ipairs(tracks) do
		if t.IsPlaying and t.WeightCurrent > 0.01 then
			if not bestTrack then
				bestTrack = t
			else
				local tPrio = t.Priority.Value
				local bPrio = bestTrack.Priority.Value
				if tPrio > bPrio then
					bestTrack = t
				elseif tPrio == bPrio and t.WeightCurrent > bestTrack.WeightCurrent then
					bestTrack = t
				end
			end
		end
	end
	return bestTrack
end

-- ============================================================
-- GUI SETUP
-- ============================================================
local gui = Instance.new("ScreenGui")
gui.Name = "QuinDebugGui"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = player:WaitForChild("PlayerGui")

-- HUD Visibility flag (Closed by default; press H or click pill to toggle)
local isHudVisible = false
local showVerboseTrace = true

-- Floating Toggle Pill (Docked bottom-right in stack)
local togglePill = Instance.new("TextButton")
togglePill.Name = "SpectatorTogglePill"
togglePill.Size = UDim2.new(0, 180, 0, 36)
togglePill.AnchorPoint = Vector2.new(1, 1)
togglePill.Position = UDim2.new(1, -20, 1, -25)
togglePill.BackgroundColor3 = Color3.fromRGB(18, 22, 30)
togglePill.BackgroundTransparency = 0.15
togglePill.TextColor3 = Color3.fromRGB(240, 245, 255)
togglePill.Font = Enum.Font.GothamBold
togglePill.TextSize = 12
togglePill.Text = "👁️ Spectator HUD [H]"
togglePill.Visible = player:GetAttribute("ShowDebugButtons") == true -- (a debug button: F8, SkylarkRoleClient)
togglePill.Parent = gui
player:GetAttributeChangedSignal("ShowDebugButtons"):Connect(function()
	togglePill.Visible = player:GetAttribute("ShowDebugButtons") == true and Workspace:GetAttribute("HideSpectatorHUD") ~= true
end)

local pillCorner = Instance.new("UICorner")
pillCorner.CornerRadius = UDim.new(0, 18)
pillCorner.Parent = togglePill

local pillStroke = Instance.new("UIStroke")
pillStroke.Color = Color3.fromRGB(0, 200, 255)
pillStroke.Thickness = 1.5
pillStroke.Transparency = 0.4
pillStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
pillStroke.Parent = togglePill

-- Subtle hover animation
togglePill.MouseEnter:Connect(function()
	TweenService:Create(togglePill, TweenInfo.new(0.2), { BackgroundTransparency = 0.05 }):Play()
	TweenService:Create(pillStroke, TweenInfo.new(0.2), { Transparency = 0.1 }):Play()
end)

togglePill.MouseLeave:Connect(function()
	TweenService:Create(togglePill, TweenInfo.new(0.2), { BackgroundTransparency = 0.15 }):Play()
	TweenService:Create(pillStroke, TweenInfo.new(0.2), { Transparency = 0.4 }):Play()
end)

-- Outer Container Frame (Docked Left)
local outerFrame = Instance.new("Frame")
outerFrame.Size = UDim2.new(0, 400, 1, -64)
outerFrame.Position = UDim2.new(0, 15, 0, 49) -- (below the Teleport Debug pill)
outerFrame.BackgroundTransparency = 0.20
outerFrame.BackgroundColor3 = Color3.fromRGB(10, 12, 18)
outerFrame.BorderSizePixel = 0
outerFrame.Visible = true
outerFrame.Active = true -- (the wheel over it scrolls it, not the camera)
outerFrame.Parent = gui

-- shared.PointerOverMenu(): the pointer is over the debug menu, the GAME bar (GodPauseClient) or
-- the replay bar (QuinReplay) - the cameras leave the wheel to them (SmoothCamera, QuinReplay)
local DEBUG_GUIS = { "QuinDebugGui", "GodPauseUI", "QuinReplayUI" }
local GuiService = game:GetService("GuiService")
function shared.PointerOverMenu()
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	-- (a locked cursor sits on the centre dot, not on a menu)
	if not playerGui or UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter then return false end
	local mouse = UserInputService:GetMouseLocation()
	local inset = GuiService:GetGuiInset()
	for _, name in ipairs(DEBUG_GUIS) do
		local screen = playerGui:FindFirstChild(name)
		if screen and screen.Enabled then
			local at = screen.IgnoreGuiInset and mouse or mouse - inset
			for _, child in ipairs(screen:GetChildren()) do
				if child:IsA("GuiObject") and child.Visible and child.BackgroundTransparency < 1 then
					local p, size = child.AbsolutePosition, child.AbsoluteSize
					if at.X >= p.X and at.X <= p.X + size.X and at.Y >= p.Y and at.Y <= p.Y + size.Y then
						return true
					end
				end
			end
		end
	end
	return false
end

local outerCorner = Instance.new("UICorner")
outerCorner.CornerRadius = UDim.new(0, 8)
outerCorner.Parent = outerFrame

local outerStroke = Instance.new("UIStroke")
outerStroke.Color = Color3.fromRGB(40, 50, 70)
outerStroke.Thickness = 1.5
outerStroke.Parent = outerFrame

-- Header Bar
local headerBar = Instance.new("Frame")
headerBar.Size = UDim2.new(1, 0, 0, 28)
headerBar.Position = UDim2.new(0, 0, 0, 0)
headerBar.BackgroundColor3 = Color3.fromRGB(18, 22, 32)
headerBar.BorderSizePixel = 0
headerBar.Parent = outerFrame

local headerCorner = Instance.new("UICorner")
headerCorner.CornerRadius = UDim.new(0, 8)
headerCorner.Parent = headerBar

local headerPadding = Instance.new("UIPadding")
headerPadding.PaddingLeft = UDim.new(0, 10)
headerPadding.PaddingRight = UDim.new(0, 8)
headerPadding.Parent = headerBar

local headerTitle = Instance.new("TextLabel")
headerTitle.Size = UDim2.new(1, -265, 1, 0)
headerTitle.Position = UDim2.new(0, 0, 0, 0)
headerTitle.BackgroundTransparency = 1
headerTitle.TextColor3 = Color3.fromRGB(255, 215, 0)
headerTitle.Font = Enum.Font.GothamBold
headerTitle.TextSize = 11
headerTitle.TextXAlignment = Enum.TextXAlignment.Left
headerTitle.Text = "QUIN SPECTATOR HUD [H]"
headerTitle.Parent = headerBar

-- (no Pilot button here: owner 2026-10-28; P still pilots, PlayerQuinController)
local vizBtn = Instance.new("TextButton")
vizBtn.Name = "ToggleVizBtn"
vizBtn.Size = UDim2.new(0, 58, 0, 22)
vizBtn.Position = UDim2.new(1, -172, 0, 3)
vizBtn.BackgroundColor3 = Color3.fromRGB(0, 160, 220)
vizBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
vizBtn.Font = Enum.Font.GothamBold
vizBtn.TextSize = 10
vizBtn.Text = "📊 3D [K]"
vizBtn.Parent = headerBar

local vizCorner = Instance.new("UICorner")
vizCorner.CornerRadius = UDim.new(0, 4)
vizCorner.Parent = vizBtn

local resetCamBtn = Instance.new("TextButton")
resetCamBtn.Size = UDim2.new(0, 80, 0, 22)
resetCamBtn.Position = UDim2.new(1, -110, 0, 3)
resetCamBtn.BackgroundColor3 = Color3.fromRGB(45, 55, 75)
resetCamBtn.TextColor3 = Color3.fromRGB(220, 235, 255)
resetCamBtn.Font = Enum.Font.GothamBold
resetCamBtn.TextSize = 10
resetCamBtn.Text = "📷 Reset (R)"
resetCamBtn.Parent = headerBar

local resetCorner = Instance.new("UICorner")
resetCorner.CornerRadius = UDim.new(0, 4)
resetCorner.Parent = resetCamBtn

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.new(0, 24, 0, 22)
closeBtn.Position = UDim2.new(1, -27, 0, 3)
closeBtn.BackgroundColor3 = Color3.fromRGB(45, 55, 75)
closeBtn.TextColor3 = Color3.fromRGB(220, 235, 255)
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 12
closeBtn.Text = "—"
closeBtn.Parent = headerBar

local closeCorner = Instance.new("UICorner")
closeCorner.CornerRadius = UDim.new(0, 4)
closeCorner.Parent = closeBtn

-- ============================================================
-- TABS (owner 2026-10-28: one menu for all the debugging, not panels all over the screen)
-- Quins: the cards. Inspect: the Quin looked at in a freeze (GodPauseClient) or the replay
-- (QuinReplay): its changes in a list that scrolls, a change's before / after card, its report.
-- Switches: every layer and label switch, in groups that fold.
-- ============================================================
local TAB_Y = 32
local CONTENT_Y = TAB_Y + 26
local TAB_NAMES = { "Quins", "Inspect", "Switches" }
local tabContent, tabButtons = {}, {}
local currentTab = "Quins"

local function showTab(name)
	currentTab = name
	for tabName, frame in pairs(tabContent) do
		frame.Visible = tabName == name
		local b = tabButtons[tabName]
		b.BackgroundColor3 = tabName == name and Color3.fromRGB(255, 215, 0) or Color3.fromRGB(24, 30, 44)
		b.TextColor3 = tabName == name and Color3.new(0, 0, 0) or Color3.fromRGB(200, 210, 230)
	end
end

for index, name in ipairs(TAB_NAMES) do
	local b = Instance.new("TextButton")
	b.Name = "Tab_" .. name
	b.Size = UDim2.new(1 / #TAB_NAMES, -6, 0, 22)
	b.Position = UDim2.new((index - 1) / #TAB_NAMES, 3, 0, TAB_Y)
	b.Font = Enum.Font.GothamBold
	b.TextSize = 11
	b.Text = name
	b.BorderSizePixel = 0
	b.Parent = outerFrame
	Instance.new("UICorner", b).CornerRadius = UDim.new(0, 4)
	b.MouseButton1Click:Connect(function() showTab(name) end)
	tabButtons[name] = b

	local frame = Instance.new("Frame")
	frame.Name = "TabContent_" .. name
	frame.Size = UDim2.new(1, 0, 1, -CONTENT_Y)
	frame.Position = UDim2.new(0, 0, 0, CONTENT_Y)
	frame.BackgroundTransparency = 1
	frame.Visible = false
	frame.Parent = outerFrame
	tabContent[name] = frame
end

local function newScroll(parent, name)
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = name
	scroll.Size = UDim2.fromScale(1, 1)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 5
	scroll.ScrollBarImageColor3 = Color3.fromRGB(80, 120, 180)
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.new()
	scroll.Parent = parent
	local list = Instance.new("UIListLayout")
	list.Padding = UDim.new(0, 4)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = scroll
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 6)
	padding.PaddingRight = UDim.new(0, 10)
	padding.PaddingTop = UDim.new(0, 4)
	padding.PaddingBottom = UDim.new(0, 6)
	padding.Parent = scroll
	return scroll
end

-- ============================================================
-- SWITCHES TAB: the 3D overlays (RuntimeVisualizer) and their scope, the AI layers
-- (Cognition.Layers, server-owned), the body layers + split + presets (Procedural.Layers) and the
-- labels / prints (DebugSwitches, Admin only). A group's fold is remembered for the session.
-- ============================================================
local CognitionLayers = require(QuinCore:WaitForChild("Cognition"):WaitForChild("Layers"))
local BodyLayers = require(QuinCore:WaitForChild("Modules"):WaitForChild("Procedural"):WaitForChild("Layers"))
local DebugSwitches = require(QuinCore:WaitForChild("Modules"):WaitForChild("DebugSwitches"))
local BODY_PRESETS = { "Default", "Legacy", "None" }
local LAYER_ROW_HEIGHT = 20

local switchScroll = newScroll(tabContent.Switches, "DebugLayerPanel")

local groupOrder = 0
local function addGroup(title)
	groupOrder += 1
	local header = Instance.new("TextButton")
	header.LayoutOrder = groupOrder * 2
	header.Size = UDim2.new(1, 0, 0, 22)
	header.BackgroundColor3 = Color3.fromRGB(30, 38, 56)
	header.BorderSizePixel = 0
	header.Font = Enum.Font.GothamBold
	header.TextSize = 11
	header.TextColor3 = Color3.fromRGB(255, 215, 0)
	header.TextXAlignment = Enum.TextXAlignment.Left
	header.Parent = switchScroll
	Instance.new("UICorner", header).CornerRadius = UDim.new(0, 4)
	Instance.new("UIPadding", header).PaddingLeft = UDim.new(0, 8)

	local grid = Instance.new("Frame")
	grid.LayoutOrder = groupOrder * 2 + 1
	grid.Size = UDim2.new(1, 0, 0, 0)
	grid.AutomaticSize = Enum.AutomaticSize.Y
	grid.BackgroundTransparency = 1
	grid.Parent = switchScroll
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.new(0.5, -3, 0, LAYER_ROW_HEIGHT - 3)
	layout.CellPadding = UDim2.fromOffset(4, 3)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = grid

	local group = { grid = grid, count = 0 }
	local key = "DebugGroupFolded_" .. title:gsub("%W", "")
	function group.refresh()
		local folded = player:GetAttribute(key) == true
		grid.Visible = not folded
		header.Text = (folded and "+  " or "-  ") .. title .. "  (" .. group.count .. ")"
	end
	header.MouseButton1Click:Connect(function()
		player:SetAttribute(key, not (player:GetAttribute(key) == true))
		group.refresh()
	end)
	return group
end

local function addLayerToggle(group, text, isOn, toggle)
	group.count += 1
	local button = Instance.new("TextButton")
	button.Name = "Layer_" .. tostring(group.count)
	button.LayoutOrder = group.count
	button.BackgroundColor3 = Color3.fromRGB(24, 30, 44)
	button.BorderSizePixel = 0
	button.Font = Enum.Font.Gotham
	button.TextSize = 10
	button.TextXAlignment = Enum.TextXAlignment.Left
	button.TextTruncate = Enum.TextTruncate.AtEnd
	button.Parent = group.grid
	Instance.new("UICorner", button).CornerRadius = UDim.new(0, 3)

	local function refresh()
		local on = isOn()
		button.Text = (on and "  [x] " or "  [  ] ") .. text
		button.TextColor3 = on and Color3.fromRGB(120, 255, 190) or Color3.fromRGB(170, 185, 210)
	end
	button.MouseButton1Click:Connect(function()
		toggle()
		refresh()
	end)
	refresh()
	group.refresh()
	return refresh
end

-- SCOPE (owner 2026-10-28: "shows for current quin that is selected, and add a toggle between this
-- quin / all quin"): one switch for the labels, the prints and the 3D overlays. "This Quin" is the
-- selected Quin (a card, or a Quin clicked while paused); the server is told through
-- DebugSwitches (Workspace DebugScopeQuin), the 3D overlays through RuntimeVisualizer.
local scopeAll = false
local scopeBar = Instance.new("Frame")
scopeBar.LayoutOrder = 1
scopeBar.Size = UDim2.new(1, 0, 0, 26)
scopeBar.BackgroundTransparency = 1
scopeBar.Parent = switchScroll
local function scopeButton(x, width)
	local b = Instance.new("TextButton")
	b.Position = UDim2.new(x, x > 0 and 2 or 0, 0, 0)
	b.Size = UDim2.new(width, x > 0 and -2 or -2, 1, 0)
	b.BorderSizePixel = 0
	b.Font = Enum.Font.GothamBold
	b.TextSize = 11
	b.TextTruncate = Enum.TextTruncate.AtEnd
	b.Parent = scopeBar
	Instance.new("UICorner", b).CornerRadius = UDim.new(0, 4)
	return b
end
local thisButton = scopeButton(0, 0.62)
local allButton = scopeButton(0.62, 0.38)
thisButton.Name = "ScopeThis" -- (names: test handles)
allButton.Name = "ScopeAll"
allButton.Text = "All Quins"

local function selectedQuin()
	local model = shared.SpectatedQuin or _G.SpectatedQuin
	return typeof(model) == "Instance" and model.Parent and model or nil
end

local function refreshScope()
	local model = selectedQuin()
	thisButton.Text = "This Quin: " .. (model and model.Name or "pick one (card / click)")
	for _, pair in ipairs({ { thisButton, not scopeAll }, { allButton, scopeAll } }) do
		pair[1].BackgroundColor3 = pair[2] and Color3.fromRGB(255, 215, 0) or Color3.fromRGB(24, 30, 44)
		pair[1].TextColor3 = pair[2] and Color3.new(0, 0, 0) or Color3.fromRGB(200, 210, 230)
	end
end

-- (asks the server only when the scope it holds is not the one wanted; "" = no Quin selected)
local askedScope, askedAt = nil, 0
local function syncScope()
	local model = selectedQuin()
	local want = not scopeAll and (model and model.Name or "") or nil
	if Workspace:GetAttribute(DebugSwitches.SCOPE) ~= want and (askedScope ~= want or os.clock() - askedAt > 1) then
		askedScope, askedAt = want, os.clock()
		DebugSwitches.requestScope(want)
	end
	if RuntimeVisualizer and RuntimeVisualizer.isWatchingAll() ~= scopeAll then RuntimeVisualizer.setWatchAll(scopeAll) end
	refreshScope()
end
thisButton.MouseButton1Click:Connect(function() scopeAll = false syncScope() end)
allButton.MouseButton1Click:Connect(function() scopeAll = true syncScope() end)
refreshScope()

do
	local labels = addGroup("Labels & prints")
	for _, switch in ipairs(DebugSwitches.List) do
		local refresh = addLayerToggle(labels, switch.label, function()
			return DebugSwitches.isOn(switch.attribute)
		end, function()
			DebugSwitches.request(switch.attribute, not DebugSwitches.isOn(switch.attribute))
		end)
		Workspace:GetAttributeChangedSignal(switch.attribute):Connect(refresh)
	end

	if RuntimeVisualizer then
		local overlays = addGroup("3D overlays")
		for _, layer in ipairs(RuntimeVisualizer.getLayers()) do
			addLayerToggle(overlays, layer.label, function()
				return RuntimeVisualizer.isLayerEnabled(layer.id)
			end, function()
				RuntimeVisualizer.setLayerEnabled(layer.id, not RuntimeVisualizer.isLayerEnabled(layer.id))
			end)
		end
	end

	local ai = addGroup("AI layers (all Quins)")
	for _, layer in ipairs(CognitionLayers.Switchable) do
		local refresh = addLayerToggle(ai, layer.label, function()
			return CognitionLayers.isEnabled(layer.id)
		end, function()
			CognitionLayers.request(layer.id, not CognitionLayers.isEnabled(layer.id))
		end)
		-- The switch shows the server's state once it has changed
		Workspace:GetAttributeChangedSignal("Cognition_" .. layer.id):Connect(refresh)
	end

	local body = addGroup("Body layers (all Quins)")
	for _, layer in ipairs(BodyLayers.List) do
		local refresh = addLayerToggle(body, layer.label, function()
			return BodyLayers.isOn(layer.name)
		end, function()
			BodyLayers.set(layer.name, not BodyLayers.isOn(layer.name))
		end)
		Workspace:GetAttributeChangedSignal(layer.attribute):Connect(refresh)
	end
	local refreshSplit = addLayerToggle(body, "Split (every other Quin legacy)", function()
		return Workspace:GetAttribute("LayerSplit") == "odd"
	end, function()
		Workspace:SetAttribute("LayerSplit", Workspace:GetAttribute("LayerSplit") ~= "odd" and "odd" or nil)
	end)
	Workspace:GetAttributeChangedSignal("LayerSplit"):Connect(refreshSplit)
	for _, preset in ipairs(BODY_PRESETS) do
		addLayerToggle(body, "Preset: " .. preset, function()
			return false -- a button, not a state
		end, function()
			BodyLayers.preset(preset)
		end)
	end
end

-- ============================================================
-- INSPECT TAB (shared.DebugDock.setInspect): fed by the freeze and the replay.
--   data = { source, title, info, clips, rows = {{t, text}}, pick = function(t) -> rich card,
--            report = function(t) -> plain text }
-- Click a change row: its before / after card. Copy report: the card as plain text, selected
-- for Ctrl+C (and printed to Output).
-- ============================================================
-- (the Quin's state, clips and the card stay at the top; only the changes scroll)
local inspectTop = Instance.new("Frame")
inspectTop.Name = "InspectTop"
inspectTop.Size = UDim2.new(1, 0, 0, 0)
inspectTop.AutomaticSize = Enum.AutomaticSize.Y
inspectTop.BackgroundTransparency = 1
inspectTop.Parent = tabContent.Inspect
local topList = Instance.new("UIListLayout")
topList.Padding = UDim.new(0, 4)
topList.SortOrder = Enum.SortOrder.LayoutOrder
topList.Parent = inspectTop
local topPadding = Instance.new("UIPadding")
topPadding.PaddingLeft, topPadding.PaddingRight = UDim.new(0, 6), UDim.new(0, 10)
topPadding.PaddingTop, topPadding.PaddingBottom = UDim.new(0, 4), UDim.new(0, 4)
topPadding.Parent = inspectTop

local inspectScroll = newScroll(tabContent.Inspect, "InspectList")
local function fitRows()
	local height = inspectTop.AbsoluteSize.Y
	inspectScroll.Position = UDim2.new(0, 0, 0, height)
	inspectScroll.Size = UDim2.new(1, 0, 1, -height)
end
inspectTop:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitRows)
fitRows()

local function inspectLabel(order, size, color)
	local label = Instance.new("TextLabel")
	label.LayoutOrder = order
	label.Size = UDim2.new(1, 0, 0, 0)
	label.AutomaticSize = Enum.AutomaticSize.Y
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.Code
	label.TextSize = size
	label.TextColor3 = color
	label.TextWrapped = true
	label.RichText = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Top
	label.Parent = inspectTop
	return label
end

local inspectTitle = inspectLabel(1, 13, Color3.fromRGB(255, 215, 0))
inspectTitle.Font = Enum.Font.GothamBold
inspectTitle.Text = "Nothing to inspect yet.\nPAUSE (F4) and click a Quin."
local inspectInfo = inspectLabel(2, 11, Color3.fromRGB(220, 230, 245))
local inspectClips = inspectLabel(3, 11, Color3.fromRGB(160, 175, 200))

local cardFrame = Instance.new("Frame")
cardFrame.LayoutOrder = 4
cardFrame.Size = UDim2.new(1, 0, 0, 0)
cardFrame.AutomaticSize = Enum.AutomaticSize.Y
cardFrame.BackgroundColor3 = Color3.fromRGB(26, 32, 48)
cardFrame.BorderSizePixel = 0
cardFrame.Visible = false
cardFrame.Parent = inspectTop
Instance.new("UICorner", cardFrame).CornerRadius = UDim.new(0, 6)
local cardPadding = Instance.new("UIPadding")
cardPadding.PaddingLeft, cardPadding.PaddingRight = UDim.new(0, 6), UDim.new(0, 6)
cardPadding.PaddingTop, cardPadding.PaddingBottom = UDim.new(0, 4), UDim.new(0, 6)
cardPadding.Parent = cardFrame
local cardList = Instance.new("UIListLayout")
cardList.Padding = UDim.new(0, 4)
cardList.SortOrder = Enum.SortOrder.LayoutOrder
cardList.Parent = cardFrame

local cardText = Instance.new("TextLabel")
cardText.LayoutOrder = 1
cardText.Size = UDim2.new(1, 0, 0, 0)
cardText.AutomaticSize = Enum.AutomaticSize.Y
cardText.BackgroundTransparency = 1
cardText.Font = Enum.Font.Code
cardText.TextSize = 11
cardText.TextColor3 = Color3.fromRGB(230, 235, 245)
cardText.TextWrapped = true
cardText.RichText = true
cardText.TextXAlignment = Enum.TextXAlignment.Left
cardText.Parent = cardFrame

local cardButtons = Instance.new("Frame")
cardButtons.LayoutOrder = 2
cardButtons.Size = UDim2.new(1, 0, 0, 22)
cardButtons.BackgroundTransparency = 1
cardButtons.Parent = cardFrame
local function cardButton(text, x, color)
	local b = Instance.new("TextButton")
	b.Size = UDim2.new(0, 110, 1, 0)
	b.Position = UDim2.new(0, x, 0, 0)
	b.BackgroundColor3 = color
	b.BorderSizePixel = 0
	b.Font = Enum.Font.GothamBold
	b.TextSize = 11
	b.TextColor3 = Color3.new(1, 1, 1)
	b.Text = text
	b.Parent = cardButtons
	Instance.new("UICorner", b).CornerRadius = UDim.new(0, 4)
	return b
end
local copyButton = cardButton("Copy report", 0, Color3.fromRGB(0, 140, 90))
local closeCardButton = cardButton("Close card", 116, Color3.fromRGB(70, 80, 100))

local reportBox = Instance.new("TextBox")
reportBox.LayoutOrder = 3
reportBox.Size = UDim2.new(1, 0, 0, 0)
reportBox.AutomaticSize = Enum.AutomaticSize.Y
reportBox.BackgroundColor3 = Color3.fromRGB(8, 10, 16)
reportBox.BorderSizePixel = 0
reportBox.ClearTextOnFocus = false
reportBox.TextEditable = false
reportBox.MultiLine = true
reportBox.TextWrapped = true
reportBox.Font = Enum.Font.Code
reportBox.TextSize = 10
reportBox.TextColor3 = Color3.fromRGB(200, 255, 220)
reportBox.TextXAlignment = Enum.TextXAlignment.Left
reportBox.Visible = false
reportBox.Parent = cardFrame

local changesHeader = inspectLabel(5, 11, Color3.fromRGB(170, 170, 170))
changesHeader.Font = Enum.Font.GothamBold
changesHeader.Text = ""

local rowsFrame = Instance.new("Frame")
rowsFrame.LayoutOrder = 6
rowsFrame.Size = UDim2.new(1, 0, 0, 0)
rowsFrame.AutomaticSize = Enum.AutomaticSize.Y
rowsFrame.BackgroundTransparency = 1
rowsFrame.Parent = inspectScroll
local rowsList = Instance.new("UIListLayout")
rowsList.Padding = UDim.new(0, 1)
rowsList.SortOrder = Enum.SortOrder.LayoutOrder
rowsList.Parent = rowsFrame

local inspectData = nil
local pickedT = nil
local rowSignature = nil

local function showCard(t)
	pickedT = t
	if not (inspectData and t and inspectData.pick) then
		cardFrame.Visible = false
		return
	end
	cardText.Text = inspectData.pick(t)
	reportBox.Visible = false
	cardFrame.Visible = true
end

copyButton.MouseButton1Click:Connect(function()
	if not (inspectData and pickedT and inspectData.report) then return end
	local text = inspectData.report(pickedT)
	print("[QuinDebug report]\n" .. text)
	reportBox.Text = text
	reportBox.Visible = true
	reportBox:CaptureFocus()
	reportBox.SelectionStart = 1
	reportBox.CursorPosition = #text + 1
end)
closeCardButton.MouseButton1Click:Connect(function()
	showCard(nil)
end)

local ROW_WINDOW = 150 -- rows drawn at once (a 120 s recording can hold many more)
local rowButtons = {} -- { button, t } in order

-- The scrubber's moment in the list (owner 2026-10-28: the list follows the scrubber): the last
-- change at or before it is gold, the changes after it are dimmed; scrolled into view when moved
local markedCursor = nil
local function markCursor(cursorT, scroll)
	markedCursor = cursorT
	local current
	for _, entry in ipairs(rowButtons) do
		local after = cursorT ~= nil and entry.t > cursorT + 1e-4
		entry.button.TextTransparency = after and 0.65 or 0
		if not after then current = entry end
	end
	for _, entry in ipairs(rowButtons) do
		local picked = entry.t == pickedT
		entry.button.BackgroundColor3 = (cursorT and entry == current) and Color3.fromRGB(120, 95, 20) or Color3.fromRGB(20, 26, 38)
		entry.button.BackgroundTransparency = ((cursorT and entry == current) or picked) and 0 or 0.6
	end
	if scroll and cursorT and current then
		task.defer(function()
			if not current.button.Parent then return end
			local y = current.button.AbsolutePosition.Y - rowsFrame.AbsolutePosition.Y
			local window = inspectScroll.AbsoluteWindowSize.Y
			inspectScroll.CanvasPosition = Vector2.new(0, math.clamp(y - window / 2, 0, math.max(0, inspectScroll.AbsoluteCanvasSize.Y - window)))
		end)
	end
end

-- (with a scrubber, the window of rows sits round it; without, the newest)
local function windowStart(rows, cursorT)
	local newest = math.max(1, #rows - ROW_WINDOW + 1)
	if not cursorT then return newest end
	local at = 0
	for index, row in ipairs(rows) do
		if row.t <= cursorT + 1e-4 then at = index else break end
	end
	return math.clamp(at - ROW_WINDOW + 50, 1, newest)
end

local function rebuildRows(rows, cursorT)
	local atBottom = inspectScroll.CanvasPosition.Y >= inspectScroll.AbsoluteCanvasSize.Y - inspectScroll.AbsoluteWindowSize.Y - 30
	for _, child in ipairs(rowsFrame:GetChildren()) do
		if child:IsA("TextButton") then child:Destroy() end
	end
	rowButtons = {}
	local first = windowStart(rows, cursorT)
	for index = first, math.min(#rows, first + ROW_WINDOW - 1) do
		local row = rows[index]
		local b = Instance.new("TextButton")
		b.LayoutOrder = index
		b.Size = UDim2.new(1, 0, 0, 16)
		b.BackgroundColor3 = Color3.fromRGB(20, 26, 38)
		b.BackgroundTransparency = row.t == pickedT and 0 or 0.6
		b.BorderSizePixel = 0
		b.Font = Enum.Font.Code
		b.TextSize = 11
		b.TextColor3 = Color3.fromRGB(225, 230, 240)
		b.RichText = true
		b.TextXAlignment = Enum.TextXAlignment.Left
		b.TextTruncate = Enum.TextTruncate.AtEnd
		b.Text = " " .. row.text
		b.Parent = rowsFrame
		table.insert(rowButtons, { button = b, t = row.t })
		b.MouseButton1Click:Connect(function()
			if inspectData and inspectData.onPick then inspectData.onPick(row.t) end
			showCard(row.t)
			rowSignature = nil -- (redraw the highlight)
		end)
	end
	markCursor(cursorT, cursorT ~= nil)
	if atBottom and not cursorT then
		task.defer(function()
			inspectScroll.CanvasPosition = Vector2.new(0, math.max(0, inspectScroll.AbsoluteCanvasSize.Y - inspectScroll.AbsoluteWindowSize.Y))
		end)
	end
end

-- ============================================================
-- Labels over the heads (DebugSwitches): Look / Gait / Foot write a value on the Quin, shown here
-- for the Quins in scope. While paused the real Quins' labels are off and the ghosts carry the
-- recorded ones, as they were at the scrubber's moment (QuinRecorder, QuinReplay)
-- ============================================================
local VALUE_LABELS = {
	{ switch = "LookDebug", attribute = "LookDbg", label = "look" },
	{ switch = "GaitDebug", attribute = "GaitSide", label = "gait side" },
	{ switch = "FootDebug", attribute = "FootDbg", label = "foot L" },
	{ switch = "FootDebug", attribute = "FootDbgR", label = "foot R" },
}

local function valueTag(root)
	local gui = root:FindFirstChild("DebugValuesTag")
	if gui then return gui end
	gui = Instance.new("BillboardGui")
	gui.Name = "DebugValuesTag"
	gui.Size = UDim2.fromOffset(280, 64)
	gui.StudsOffset = Vector3.new(0, 4.5, 0)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.Code
	text.TextSize = 13
	text.TextColor3 = Color3.fromRGB(150, 230, 255)
	text.TextStrokeTransparency = 0
	text.TextYAlignment = Enum.TextYAlignment.Bottom
	text.Parent = gui
	gui.Parent = root
	return gui
end

local labelSince = 0
RunService.Heartbeat:Connect(function(dt)
	labelSince += dt
	if labelSince < 0.2 then return end
	labelSince = 0
	syncScope()
	local replay = shared.QuinReplay
	local paused = replay and replay.isOpen and replay.isOpen()
	for _, model in ipairs(game:GetService("CollectionService"):GetTagged("Quin")) do
		local root = model:FindFirstChild("HumanoidRootPart")
		if root and paused then
			-- (left as they were at the pause: the recorder would count a change made now as the game's)
		elseif root then
			local lines = {}
			if DebugSwitches.inScope(model) then
				for _, value in ipairs(VALUE_LABELS) do
					local v = DebugSwitches.isOn(value.switch) and model:GetAttribute(value.attribute)
					if v ~= nil and v ~= false then table.insert(lines, value.label .. ": " .. tostring(v)) end
				end
			end
			if #lines > 0 then
				valueTag(root).TextLabel.Text = table.concat(lines, "\n")
			elseif root:FindFirstChild("DebugValuesTag") then
				root.DebugValuesTag:Destroy()
			end
		end
	end
end)

-- ============================================================
-- shared.DebugDock: the menu, for GodPauseClient and QuinReplay
-- ============================================================
local DebugDock = {}
shared.DebugDock = DebugDock

function DebugDock.showTab(name)
	showTab(name)
end

function DebugDock.setInspect(data)
	local sameQuin = inspectData and data and inspectData.title == data.title and inspectData.source == data.source
	inspectData = data
	if not data then
		inspectTitle.Text = "Nothing to inspect yet.\nPAUSE (F4) and click a Quin."
		inspectInfo.Text, inspectClips.Text, changesHeader.Text = "", "", ""
		rebuildRows({})
		rowSignature, markedCursor = nil, nil
		showCard(nil)
		return
	end
	inspectTitle.Text = ("%s  <font color='#AAAAAA'>(%s)</font>"):format(data.title or "?", data.source or "")
	inspectInfo.Text = data.info or ""
	inspectClips.Text = "Clips: " .. (data.clips or "none")
	local rows = data.rows or {}
	changesHeader.Text = ("CHANGES (%d)  - click one for its before / after"):format(#rows)
	local last = rows[#rows]
	local signature = ("%s|%d|%s|%s|%d"):format(data.title or "", #rows, last and tostring(last.t) or "", tostring(pickedT), windowStart(rows, data.cursor))
	if signature ~= rowSignature then
		rowSignature = signature
		rebuildRows(rows, data.cursor)
	elseif data.cursor ~= markedCursor then
		markCursor(data.cursor, true)
	end
	if not sameQuin then
		showCard(nil)
	elseif pickedT and cardFrame.Visible and not reportBox.Visible then
		cardText.Text = data.pick and data.pick(pickedT) or ""
	end
end

-- Main Scrollable Card List Frame
local scrollFrame = Instance.new("ScrollingFrame")
scrollFrame.Size = UDim2.fromScale(1, 1)
scrollFrame.Position = UDim2.new()
scrollFrame.BackgroundTransparency = 0.35
scrollFrame.BackgroundColor3 = Color3.fromRGB(15, 18, 26)
scrollFrame.BorderSizePixel = 0
scrollFrame.ScrollBarThickness = 5
scrollFrame.ScrollBarImageColor3 = Color3.fromRGB(80, 120, 180)
scrollFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
scrollFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
scrollFrame.Parent = tabContent.Quins
showTab("Quins")

local scrollCorner = Instance.new("UICorner")
scrollCorner.CornerRadius = UDim.new(0, 6)
scrollCorner.Parent = scrollFrame

local listLayout = Instance.new("UIListLayout")
listLayout.Padding = UDim.new(0, 6)
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Parent = scrollFrame

local padding = Instance.new("UIPadding")
padding.PaddingLeft = UDim.new(0, 6)
padding.PaddingRight = UDim.new(0, 6)
padding.PaddingTop = UDim.new(0, 6)
padding.PaddingBottom = UDim.new(0, 6)
padding.Parent = scrollFrame

-- ============================================================
-- SPECTATOR LOGIC
-- ============================================================
local cardInstances = {}

local function getAllAliveQuins()
	local quins = {}
	-- STRICT FILTER: Only query QuinServer folder (where arena combatants reside).
	-- Never scan raw Workspace to avoid picking up static rigs/world dummies (QuinTest, QuinTypeA).
	local serverFolder = Workspace:FindFirstChild("QuinServer")
	if not serverFolder then return quins end

	for _, model in ipairs(serverFolder:GetChildren()) do
		if model:IsA("Model") and not model.Name:find("_Visual") and model.Parent then
			-- Arena Quin verification: Must be an arena combatant
			local isArenaQuin = model:GetAttribute("QuinId") ~= nil
				or CollectionService:HasTag(model, "Quin")
				or CollectionService:HasTag(model, "AI_Fighter")
				or model:GetAttribute("IsPlayerControlled")
				or string.match(model.Name, "^Quin_")

			-- (shared.SpectateFilter: while at a preparation room terminal, only the player's own Quins)
			local allowed = not shared.SpectateFilter or shared.SpectateFilter(model)
			if isArenaQuin and allowed and model.Name ~= "QuinTest" and model.Name ~= "QuinTypeA" then
				local hum = model:FindFirstChildOfClass("Humanoid")
				local hrp = model:FindFirstChild("HumanoidRootPart")
				if hum and hum.Health > 0 and hrp then
					table.insert(quins, model)
				end
			end
		end
	end
	table.sort(quins, function(a, b)
		local aPilot = (a:GetAttribute("IsPlayerControlled") or a == player.Character) and 1 or 0
		local bPilot = (b:GetAttribute("IsPlayerControlled") or b == player.Character) and 1 or 0
		if aPilot ~= bPilot then return aPilot > bPilot end
		return a.Name < b.Name
	end)
	return quins
end

local function setSpectatedQuin(model)
	if model and shared.SpectateFilter and not shared.SpectateFilter(model) then
		return -- (someone else's Quin, from a preparation room terminal)
	end
	shared.SpectatedQuin = model
	_G.SpectatedQuin = model
	Workspace:SetAttribute("SpectatedQuin", model and model.Name or "")
	if not model then
		if player.Character and player.Character:FindFirstChildOfClass("Humanoid") then
			camera.CameraSubject = player.Character:FindFirstChildOfClass("Humanoid")
		end
	else
		local hum = model:FindFirstChildOfClass("Humanoid")
		if hum then
			camera.CameraSubject = hum
		end
	end
end

local function cycleSpectatedQuin(delta)
	local quins = getAllAliveQuins()
	if #quins == 0 then
		setSpectatedQuin(nil)
		return
	end

	local curQuin = shared.SpectatedQuin or _G.SpectatedQuin
	if not curQuin then
		local curName = Workspace:GetAttribute("SpectatedQuin")
		if curName and curName ~= "" then
			curQuin = Workspace:FindFirstChild(curName) or (Workspace:FindFirstChild("QuinServer") and Workspace.QuinServer:FindFirstChild(curName))
		end
	end

	local curIdx = 1
	for idx, q in ipairs(quins) do
		if q == curQuin then
			curIdx = idx
			break
		end
	end

	curIdx = ((curIdx - 1 + delta) % #quins) + 1
	setSpectatedQuin(quins[curIdx])
end

local visualizerDrawn = false

local function setHudVisibility(visible)
	isHudVisible = visible
	local hideOverride = (Workspace:GetAttribute("HideSpectatorHUD") == true)
	if hideOverride then
		outerFrame.Visible = false
		togglePill.Visible = false
	else
		outerFrame.Visible = visible
		togglePill.Visible = player:GetAttribute("ShowDebugButtons") == true
		togglePill.Text = visible and "👁️ Close Spectator [H]" or "👁️ Spectator HUD [H]"
	end
end

togglePill.MouseButton1Click:Connect(function()
	setHudVisibility(not isHudVisible)
end)

-- (the freeze and the replay open the menu on the Inspect tab)
function DebugDock.open(tab)
	setHudVisibility(true)
	if tab then showTab(tab) end
end

vizBtn.MouseButton1Click:Connect(function()
	if RuntimeVisualizer then
		local vEnabled = RuntimeVisualizer.toggle()
		vizBtn.BackgroundColor3 = vEnabled and Color3.fromRGB(0, 200, 120) or Color3.fromRGB(70, 80, 100)
	end
end)

closeBtn.MouseButton1Click:Connect(function()
	setHudVisibility(false)
end)

resetCamBtn.MouseButton1Click:Connect(function()
	setSpectatedQuin(nil)
end)

-- Keybinds: Q/E cycle, R reset, H toggle HUD, T toggle verbose trace, V toggle 3D visualizers
UserInputService.InputBegan:Connect(function(input, gp)
	if gp or UserInputService:GetFocusedTextBox() then return end
	if (input.KeyCode == Enum.KeyCode.Q or input.KeyCode == Enum.KeyCode.E) and (shared.PlayerControlledQuin or _G.PlayerControlledQuin) then return end
	-- (a Roblox player gets the HUD only at a preparation room terminal: SkylarkRoles)
	if not (shared.IsAdmin and shared.IsAdmin()) and shared.SpectateFilter == nil then return end
	if input.KeyCode == Enum.KeyCode.Q then
		cycleSpectatedQuin(-1)
	elseif input.KeyCode == Enum.KeyCode.E then
		cycleSpectatedQuin(1)
	elseif input.KeyCode == Enum.KeyCode.R then
		setSpectatedQuin(nil)
	elseif input.KeyCode == Enum.KeyCode.H then
		setHudVisibility(not isHudVisible)
	elseif input.KeyCode == Enum.KeyCode.T then
		showVerboseTrace = not showVerboseTrace
	elseif input.KeyCode == Enum.KeyCode.K then
		if RuntimeVisualizer then
			local vEnabled = RuntimeVisualizer.toggle()
			vizBtn.BackgroundColor3 = vEnabled and Color3.fromRGB(0, 200, 120) or Color3.fromRGB(70, 80, 100)
		end
	end
end)

-- ============================================================
-- CARD FACTORY
-- ============================================================
local function getOrCreateCard(quinModel)
	local name = quinModel.Name
	if cardInstances[name] then
		return cardInstances[name]
	end

	local cardBtn = Instance.new("TextButton")
	cardBtn.Name = name
	cardBtn.Size = UDim2.new(1, 0, 0, 0)
	cardBtn.AutomaticSize = Enum.AutomaticSize.Y
	cardBtn.BackgroundColor3 = Color3.fromRGB(22, 26, 36)
	cardBtn.BackgroundTransparency = 0.2
	cardBtn.Text = ""
	cardBtn.AutoButtonColor = true
	cardBtn.Parent = scrollFrame

	local cardCorner = Instance.new("UICorner")
	cardCorner.CornerRadius = UDim.new(0, 6)
	cardCorner.Parent = cardBtn

	local cardPad = Instance.new("UIPadding")
	cardPad.PaddingLeft = UDim.new(0, 8)
	cardPad.PaddingRight = UDim.new(0, 8)
	cardPad.PaddingTop = UDim.new(0, 6)
	cardPad.PaddingBottom = UDim.new(0, 8)
	cardPad.Parent = cardBtn

	local cardStroke = Instance.new("UIStroke")
	cardStroke.Color = Color3.fromRGB(0, 200, 255)
	cardStroke.Thickness = 0
	cardStroke.Parent = cardBtn

	local textLabel = Instance.new("TextLabel")
	textLabel.Size = UDim2.new(1, 0, 0, 0)
	textLabel.Position = UDim2.new(0, 0, 0, 0)
	textLabel.AutomaticSize = Enum.AutomaticSize.Y
	textLabel.TextWrapped = true
	textLabel.BackgroundTransparency = 1
	textLabel.TextColor3 = Color3.fromRGB(200, 255, 200)
	textLabel.Font = Enum.Font.RobotoMono
	textLabel.TextSize = 11
	textLabel.TextXAlignment = Enum.TextXAlignment.Left
	textLabel.TextYAlignment = Enum.TextYAlignment.Top
	textLabel.RichText = true
	textLabel.Parent = cardBtn

	cardBtn.MouseButton1Click:Connect(function()
		setSpectatedQuin(quinModel)
	end)

	local cardObj = {
		btn = cardBtn,
		stroke = cardStroke,
		label = textLabel,
		model = quinModel,
	}
	cardInstances[name] = cardObj
	return cardObj
end

-- ============================================================
-- MAIN UPDATE LOOP
-- ============================================================
-- The cards are text for reading: each is rebuilt every CARD_STRIDE frames (a few cards a frame,
-- in turn), and only while the HUD is open. (All of them rebuilt every frame, open or closed,
-- cost 10.7 ms of a 24 ms frame in a 16v16.)
local CARD_STRIDE = 10
local frameCounter = 0

RunService.Heartbeat:Connect(function()
	local activeQuins = {}
	local count = 0
	frameCounter += 1
	local cardsOpen = isHudVisible and Workspace:GetAttribute("HideSpectatorHUD") ~= true
	DebugReadouts.report(cardsOpen) -- (the 3D visualizer draws only while the HUD is open too)

	local quins = getAllAliveQuins()
	local curSpectated = shared.SpectatedQuin or _G.SpectatedQuin
	if not curSpectated then
		local curName = Workspace:GetAttribute("SpectatedQuin")
		if curName and curName ~= "" then
			local qServer = Workspace:FindFirstChild("QuinServer")
			curSpectated = qServer and qServer:FindFirstChild(curName)
		end
	end

	-- Auto-cycle if currently spectated Quin dies or despawns or is not in QuinServer
	if curSpectated then
		local hum = curSpectated:FindFirstChildOfClass("Humanoid")
		local isAliveArena = curSpectated.Parent and curSpectated.Parent.Name == "QuinServer" and hum and hum.Health > 0
		if not isAliveArena then
			cycleSpectatedQuin(1)
			curSpectated = shared.SpectatedQuin or _G.SpectatedQuin
		end
	end

	for index, model in ipairs(quins) do
		activeQuins[model.Name] = true
		count = count + 1
		if not cardsOpen or (index + frameCounter) % CARD_STRIDE ~= 0 then continue end

		local card = getOrCreateCard(model)
		local isSpectatingThis = (model == curSpectated)

		card.stroke.Thickness = isSpectatingThis and 2.0 or 0
		card.stroke.Color = isSpectatingThis and Color3.fromRGB(255, 215, 0) or Color3.fromRGB(0, 200, 255)
		card.btn.BackgroundColor3 = isSpectatingThis and Color3.fromRGB(30, 36, 52) or Color3.fromRGB(22, 26, 36)

		local state = model:GetAttribute("CurrentState") or "None"
		local startY = model:GetAttribute("StartY") or 0
		local targetName = model:GetAttribute("TargetQuin") or "None"

		local hrp = model:FindFirstChild("HumanoidRootPart")
		local targetQuin = Workspace:FindFirstChild(targetName)
		local quinServer = Workspace:FindFirstChild("QuinServer")
		if not targetQuin and quinServer then
			targetQuin = quinServer:FindFirstChild(targetName)
		end
		local targetHrp = targetQuin and targetQuin:FindFirstChild("HumanoidRootPart")

		local alt = hrp and (hrp.Position.Y - startY) or 0
		local dist = (hrp and targetHrp) and (targetHrp.Position - hrp.Position).Magnitude or 0
		local speed = hrp and hrp.AssemblyLinearVelocity.Magnitude or 0
		local vy = hrp and hrp.AssemblyLinearVelocity.Y or 0

		local dashArmed = model:GetAttribute("DashArmed") or false

		local qType = model:GetAttribute("QuinType") or "TypeA"
		local qElem = model:GetAttribute("Element") or "Fire"
		local elemColor = model:GetAttribute("ElementColor") or Color3.fromRGB(255, 140, 40)
		local hexColor = string.format("#%02X%02X%02X", math.floor(elemColor.R * 255), math.floor(elemColor.G * 255), math.floor(elemColor.B * 255))

		local tactical = model:GetAttribute("TacticalState") or "ENGAGING"
		local conf = model:GetAttribute("CurrentConfidence") or 0.5
		local awareness = model:GetAttribute("AwarenessLevel") or model:GetAttribute("Pers_Awareness") or 0.65
		local threatZone = model:GetAttribute("ThreatZone") or "Front"
		local pacingVel = model:GetAttribute("PacingVelocity") or 0
		local decision = model:GetAttribute("RecommendedAction") or "—"
		local targetReason = model:GetAttribute("TargetReason") or ""
		local teamRole = model:GetAttribute("TeamRole") or "Solo"
		-- (the moment's job for the pack: TargetingModule PackIntent, with the ally it is for)
		local packIntent = model:GetAttribute("PackIntent")
		if packIntent then
			local packAlly = model:GetAttribute("PackIntentAlly") or ""
			teamRole = teamRole .. " / " .. packIntent .. (packAlly ~= "" and (" for " .. packAlly) or "") .. (model:GetAttribute("Flanking") and " (going round)" or "")
		end
		-- (what it set out to do: Modules/TaskChoice)
		local task = model:GetAttribute("Task")
		if task then
			teamRole = teamRole .. "  |  Task " .. task .. ": " .. tostring(model:GetAttribute("TaskWhy") or "")
		end
		local temperament = model:GetAttribute("Temperament") or "—"
		local curSpecial = model:GetAttribute("CurrentSpecial")

		-- 1. Authoritative Animation Information
		local activeAnim = getAuthoritativeAnimation(model)
		local animName = "None"
		local animId = "N/A"
		local animPrio = "None"
		local animLoop = "false"
		local animTime = "0.00s / 0.00s"
		local animSpeed = "1.0x"

		if activeAnim then
			local rawId = activeAnim.Animation and activeAnim.Animation.AnimationId or ""
			local num = rawId:match("%d+")
			animId = rawId ~= "" and rawId or "N/A"
			animName = animNameLookup[rawId] or (num and animNameLookup[num]) or activeAnim.Name
			if animName == "Animation" and activeAnim.Name == "Animation" then
				animName = num and ("Anim_" .. num) or "Active"
			end
			animPrio = activeAnim.Priority.Name
			animLoop = tostring(activeAnim.Looped)
			animTime = string.format("%.2fs / %.2fs", activeAnim.TimePosition, activeAnim.Length)
			animSpeed = string.format("%.1fx", activeAnim.Speed)
		end

		-- 2. Execution Context Tracing
		local breadcrumb = model:GetAttribute("TraceBreadcrumb") or "Main.lua:72 (Init)"
		local traceLog = model:GetAttribute("TraceLog") or ""

		local isPilot = model:GetAttribute("IsPlayerControlled") == true or model == player.Character
		local nameHeader
		if isPilot then
			nameHeader = string.format("<font color='#00FFCC'><b>[%s] 🎮 YOU (PILOT)</b></font>", model.Name)
		elseif isSpectatingThis then
			nameHeader = string.format("<font color='#FFD700'><b>[%s] 📷 SPECTATING</b></font>", model.Name)
		else
			nameHeader = string.format("<b>[%s]</b>", model.Name)
		end

		local hasTrace = (traceLog ~= "")
		local traceDisplay = ""
		if hasTrace then
			traceDisplay = string.format(
				"\n<font color='#80D0FF'><b>▶ Trace:</b> %s</font>\n<font color='#A8B4C4'>%s</font>",
				breadcrumb, traceLog
			)
		else
			traceDisplay = string.format("\n<font color='#80D0FF'><b>▶ Trace:</b> %s</font>", breadcrumb)
		end

		local retreatScore = model:GetAttribute("RetreatScore")
		local isCornered = model:GetAttribute("IsCornered")
		local retreatObj = model:GetAttribute("RetreatObjective")
		local chaseCommit = model:GetAttribute("ChaseCommitment")
		local retreatTag = ""
		if isCornered then
			retreatTag = " <font color='#FF3333'><b>[CORNERED]</b></font>"
		elseif retreatObj then
			local scoreStr = retreatScore and string.format(" (%.1f)", retreatScore) or ""
			retreatTag = string.format(" <font color='#66FF66'><b>[%s%s]</b></font>", retreatObj, scoreStr)
		elseif retreatScore then
			retreatTag = string.format(" <font color='#66FF66'>[Safe:%.2f]</font>", retreatScore)
		end

		local chaseTag = ""
		if state == "Chase" and chaseCommit then
			chaseTag = string.format(" <font color='#FFAA00'>[Commit:%.0f%%]</font>", chaseCommit * 100)
		end

		local specialTag = curSpecial and string.format(" <font color='#FF44AA'><b>[%s]</b></font>", curSpecial) or ""

		local obsAware = model:GetAttribute("ObstacleAwareness")
		local wallSide = model:GetAttribute("WallRunSide")
		local travTag = ""
		if state == "Slide" then
			travTag = " <font color='#00FFCC'><b>[SLIDING]</b></font>"
		elseif state == "WallRun" then
			travTag = string.format(" <font color='#FFCC00'><b>[WALL RUN %s]</b></font>", wallSide or "")
		elseif obsAware and obsAware:find("Sliding") then
			travTag = " <font color='#00FFCC'><b>[SLIDE GAP]</b></font>"
		elseif obsAware and obsAware:find("Wall-Running") then
			travTag = " <font color='#FFCC00'><b>[WALL RUN]</b></font>"
		end

		local equippedTitle = model:GetAttribute("EquippedTitle") or "Rookie"
		local primaryRival = model:GetAttribute("PrimaryRivalId")
		local rivalScore = model:GetAttribute("PrimaryRivalScore") or ""
		local winStreak = model:GetAttribute("WinStreak") or 0

		local historyLine = string.format("Title: <font color='#FFDF70'><b>«%s»</b></font>", equippedTitle)
		if winStreak > 1 then
			historyLine = historyLine .. string.format(" <font color='#FF5555'><b>[%dW Streak]</b></font>", winStreak)
		end
		if primaryRival then
			historyLine = historyLine .. string.format(" | Rival: <font color='#FF6666'><b>%s</b></font> (%s)", primaryRival, rivalScore)
		end

		local idleStance = model:GetAttribute("CurrentIdleStance") or "Default"
		local lastAct = model:GetAttribute("LastActivityTime") or os.clock()
		local inactiveSec = math.max(0, 5.0 - (os.clock() - lastAct))
		local stanceTag = (idleStance == "Ready") and string.format(" <font color='#FFAA00'><b>[READY:%.1fs]</b></font>", inactiveSec)
			or ((idleStance == "Fight") and " <font color='#FF5555'><b>[FIGHT]</b></font>" or " <font color='#88CCFF'>[DEFAULT]</font>")

		card.label.Text = string.format(
			"%s  <font color='%s'><b>[%s • %s]</b></font>\n" ..
			"%s\n" ..
			"State: <font color='#FFAA50'><b>%s</b></font>%s%s%s%s | Tact: <font color='#00E5FF'><b>%s</b></font> | Conf: %.2f\n" ..
			"Role: <font color='#FFD700'><b>%s</b></font> | Temperament: <font color='#E080FF'><b>%s</b></font>\n" ..
			"Alt: %.1f | Dist: %.1f | Spd: %.1f | Vy: %.1f | Dash: %s\n" ..
			"<font color='#FFB000'>Aware: %.2f</font> | <font color='#00FFAA'>Zone: %s</font> | <font color='#FF8080'>Pace: %.0f</font>\n" ..
			"<font color='#FFC0FF'><b>Decision:</b> <font color='#FFFFFF'>%s</font></font>%s <font color='#99AABB'>%s</font>\n" ..
			"<font color='#FF80DF'><b>Anim:</b></font> <font color='#FFFFFF'><b>%s</b></font> [<font color='#FFD700'>%s</font>] (Loop=%s)\n" ..
			"<font color='#888888'>Id: %s | Time: %s (%s)</font>%s",
			nameHeader, hexColor, qType, qElem,
			historyLine,
			state, stanceTag, specialTag, travTag, chaseTag, tactical, conf,
			teamRole, temperament,
			alt, dist, speed, vy, tostring(dashArmed),
			awareness, threatZone, pacingVel,
			decision, retreatTag, targetReason,
			animName, animPrio, animLoop,
			animId, animTime, animSpeed, traceDisplay
		)
	end

	local hideOverride = (Workspace:GetAttribute("HideSpectatorHUD") == true)
	if hideOverride then
		outerFrame.Visible = false
		togglePill.Visible = false
	else
		local showHUD = isHudVisible
		outerFrame.Visible = showHUD
		togglePill.Visible = player:GetAttribute("ShowDebugButtons") == true
		togglePill.Text = showHUD and "👁️ Close Spectator [H]" or "👁️ Spectator HUD [H]"

		if count == 0 and showHUD then
			if not cardInstances["__empty_state__"] then
				local emptyCard = Instance.new("TextLabel")
				emptyCard.Name = "__empty_state__"
				emptyCard.Size = UDim2.new(1, 0, 0, 80)
				emptyCard.BackgroundColor3 = Color3.fromRGB(15, 20, 32)
				emptyCard.BackgroundTransparency = 0.3
				emptyCard.TextColor3 = Color3.fromRGB(170, 190, 220)
				emptyCard.TextSize = 13
				emptyCard.Font = Enum.Font.GothamMedium
				emptyCard.Text = "⚡ No Arena Quins Active\nPress [P] to Pilot / Spawn Quin"
				local c = Instance.new("UICorner", emptyCard)
				c.CornerRadius = UDim.new(0, 8)
				emptyCard.Parent = scrollFrame
				cardInstances["__empty_state__"] = { btn = emptyCard }
			end
			activeQuins["__empty_state__"] = true
		end
	end

	-- 3D Debug Visualizers (LoS, LKP, Trajectories, Platform Intent)
	-- Only while the Spectator HUD is open: closed, nothing is drawn over the Quins
	if RuntimeVisualizer then
		-- (for the selected Quin only - never a stand-in; while paused, drawn from the recording at
		-- the scrubber's moment: QuinReplay.overlay)
		local replay = shared.QuinReplay
		local recorded = replay and replay.overlay and replay.overlay()
		if isHudVisible and not hideOverride then
			if recorded then
				RuntimeVisualizer.updateReplay(recorded)
			else
				RuntimeVisualizer.update(curSpectated, quins)
			end
			visualizerDrawn = true
		elseif visualizerDrawn then
			RuntimeVisualizer.stop()
			visualizerDrawn = false
		end
	end

	-- Prune stale cards
	for name, card in pairs(cardInstances) do
		if not activeQuins[name] then
			card.btn:Destroy()
			cardInstances[name] = nil
		end
	end
end)

print("[QuinDebugHUD] Loaded: Authoritative AnimationTrack inspector & RuntimeTracer breadcrumbs active.")
