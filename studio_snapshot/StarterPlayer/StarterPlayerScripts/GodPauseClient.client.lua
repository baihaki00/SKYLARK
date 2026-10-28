--// GodPauseClient.client.lua
-- The god pause (owner 2026-10-28): F4 or the pill at the top freezes the real game and resumes
-- it where it was (QuinCore Modules/GameFreeze). While frozen the cameras still fly (B, the
-- spectator camera) so the frozen fight can be walked round, and:
--   * click a Quin (the dot in the middle aims when the cursor is locked) to inspect it: what it
--     is doing and why, the clips held on it (weight, where in the clip, the speed it had), and
--     its last changes before the freeze (the flight recorder, QuinRecorder);
--   * "." or the buttons step the real game on by one frame or 0.1 s and freeze it again.
-- Studio, Admins only.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

if not RunService:IsStudio() then return end

local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera
local Modules = ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules")
local GameClock = require(Modules:WaitForChild("GameClock"))
local GameFreeze = require(Modules:WaitForChild("GameFreeze")) -- (also starts this machine's side)

-- shown in the info line, in this order
local INFO_ATTRIBUTES = { "CurrentState", "TacticalState", "Task", "TaskWhy", "PaceGear", "PaceWhy", "CurrentTarget",
	"ObstacleAwareness", "LookMode", "ReactionType", "StrikeResult" }
local FRAME = 1 / 60

local function isAdmin()
	return player:GetAttribute("SkylarkRole") == "Admin"
end

local function escape(text)
	return (tostring(text):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

----------------------------------------------------------------------------------------
-- UI
----------------------------------------------------------------------------------------
local gui = Instance.new("ScreenGui")
gui.Name = "GodPauseUI"
gui.ResetOnSpawn = false
gui.DisplayOrder = 60
gui.Parent = player:WaitForChild("PlayerGui")

local pill = Instance.new("TextButton")
pill.AnchorPoint = Vector2.new(0.5, 0)
pill.Position = UDim2.new(0.5, 0, 0, 10)
pill.Size = UDim2.new(0, 150, 0, 30)
pill.Font = Enum.Font.GothamBold
pill.TextSize = 12
pill.BorderSizePixel = 0
pill.Parent = gui
Instance.new("UICorner", pill).CornerRadius = UDim.new(0, 15)
local stroke = Instance.new("UIStroke", pill)
stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
stroke.Thickness = 1.5

local dot = Instance.new("Frame")
dot.AnchorPoint = Vector2.new(0.5, 0.5)
dot.Position = UDim2.fromScale(0.5, 0.5)
dot.Size = UDim2.fromOffset(6, 6)
dot.BackgroundColor3 = Color3.new(1, 1, 1)
dot.BorderSizePixel = 0
dot.Parent = gui
Instance.new("UICorner", dot).CornerRadius = UDim.new(1, 0)
local dotStroke = Instance.new("UIStroke", dot)
dotStroke.Color = Color3.new(0, 0, 0)

local panel = Instance.new("Frame")
panel.AnchorPoint = Vector2.new(0.5, 1)
panel.Position = UDim2.new(0.5, 0, 1, -168) -- (above the Mind panel, QuinMindPanel)
panel.Size = UDim2.new(0, 820, 0, 132)
panel.BackgroundColor3 = Color3.fromRGB(10, 12, 18)
panel.BackgroundTransparency = 0.12
panel.BorderSizePixel = 0
panel.Parent = gui
Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 8)
local panelStroke = Instance.new("UIStroke", panel)
panelStroke.Color = Color3.fromRGB(60, 170, 255)
panelStroke.Transparency = 0.3

local function button(text, x, width)
	local b = Instance.new("TextButton")
	b.Position = UDim2.new(0, x, 0, 8)
	b.Size = UDim2.new(0, width, 0, 24)
	b.BackgroundColor3 = Color3.fromRGB(32, 40, 58)
	b.TextColor3 = Color3.fromRGB(235, 240, 255)
	b.Font = Enum.Font.GothamBold
	b.TextSize = 11
	b.Text = text
	b.Parent = panel
	Instance.new("UICorner", b).CornerRadius = UDim.new(0, 4)
	return b
end

local title = Instance.new("TextLabel")
title.Position = UDim2.new(0, 10, 0, 8)
title.Size = UDim2.new(0, 90, 0, 24)
title.BackgroundTransparency = 1
title.Font = Enum.Font.GothamBlack
title.TextSize = 12
title.TextColor3 = Color3.fromRGB(60, 170, 255)
title.TextXAlignment = Enum.TextXAlignment.Left
title.Text = "FROZEN"
title.Parent = panel

local frameButton = button("Step 1 frame [.]", 100, 120)
local tenthButton = button("Step 0.1 s", 224, 84)
local secondButton = button("Step 1 s", 312, 70)
local hint = Instance.new("TextLabel")
hint.Position = UDim2.new(0, 392, 0, 8)
hint.Size = UDim2.new(1, -402, 0, 24)
hint.BackgroundTransparency = 1
hint.Font = Enum.Font.Gotham
hint.TextSize = 11
hint.TextColor3 = Color3.fromRGB(170, 185, 210)
hint.TextXAlignment = Enum.TextXAlignment.Right
hint.Text = "Click a Quin to inspect it  ·  B flies  ·  middle mouse frees the cursor"
hint.Parent = panel

local function infoLabel(y, height, size, color)
	local l = Instance.new("TextLabel")
	l.Position = UDim2.new(0, 10, 0, y)
	l.Size = UDim2.new(1, -20, 0, height)
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.Code
	l.TextSize = size
	l.TextColor3 = color
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextYAlignment = Enum.TextYAlignment.Top
	l.TextWrapped = true
	l.RichText = true
	l.Parent = panel
	return l
end
local infoLine = infoLabel(40, 46, 12, Color3.fromRGB(235, 240, 255))
local clipLine = infoLabel(88, 40, 11, Color3.fromRGB(170, 200, 255))

local changes = Instance.new("TextLabel")
changes.AnchorPoint = Vector2.new(1, 0)
changes.Position = UDim2.new(1, -12, 0, 130)
changes.Size = UDim2.new(0, 380, 0, 420)
changes.BackgroundColor3 = Color3.fromRGB(10, 12, 18)
changes.BackgroundTransparency = 0.2
changes.BorderSizePixel = 0
changes.Font = Enum.Font.Code
changes.TextSize = 11
changes.TextColor3 = Color3.fromRGB(220, 230, 255)
changes.TextXAlignment = Enum.TextXAlignment.Left
changes.TextYAlignment = Enum.TextYAlignment.Bottom
changes.TextWrapped = true
changes.RichText = true
changes.Parent = gui
Instance.new("UIPadding", changes).PaddingLeft = UDim.new(0, 8)
Instance.new("UICorner", changes).CornerRadius = UDim.new(0, 6)

local highlight = Instance.new("Highlight")
highlight.FillTransparency = 1
highlight.OutlineColor = Color3.fromRGB(60, 170, 255)
highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop

----------------------------------------------------------------------------------------
-- Inspecting
----------------------------------------------------------------------------------------
local selected -- the Quin being inspected
local frozenAt -- os.clock() when this freeze began (steps do not move it)

local function replayOpen()
	local replay = player.PlayerGui:FindFirstChild("QuinReplayUI")
	return replay ~= nil and replay.Enabled
end

local function select(model)
	selected = model
	highlight.Adornee = model
	highlight.Parent = model and gui or nil
end

local function refreshInfo()
	if not selected or not selected.Parent then
		infoLine.Text = "Click a Quin to see what it is doing and why."
		clipLine.Text = ""
		changes.Visible = false
		return
	end
	local parts = { ("<b>%s</b>"):format(escape(selected.Name)) }
	local humanoid = selected:FindFirstChildOfClass("Humanoid")
	if humanoid then
		table.insert(parts, ("HP %d"):format(humanoid.Health))
		table.insert(parts, "Humanoid " .. humanoid:GetState().Name)
	end
	for _, key in ipairs(INFO_ATTRIBUTES) do
		local v = selected:GetAttribute(key)
		if v ~= nil and v ~= "" then table.insert(parts, ("%s <font color='#3CAAFF'>%s</font>"):format(key, escape(v))) end
	end
	infoLine.Text = table.concat(parts, "  ·  ")

	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	local clips = {}
	local recorder = shared.QuinRecorder and shared.QuinRecorder.live()
	local nameOf = shared.QuinRecorder and shared.QuinRecorder.clipName
	-- the speeds the clips had before the freeze (the recorder's last frame: nothing is recorded
	-- while frozen; the clips themselves show 0 now)
	local frames = recorder and recorder.frames
	local lastPose = frames and frames[#frames] and frames[#frames].quins[selected.Name]
	local speedBefore = {}
	for _, clip in ipairs(lastPose and lastPose.clips or {}) do speedBefore[clip.name] = clip.speed end
	if animator then
		local tracks = animator:GetPlayingAnimationTracks()
		table.sort(tracks, function(a, b) return a.WeightCurrent > b.WeightCurrent end)
		for _, track in ipairs(tracks) do
			if track.WeightCurrent > 0.01 then
				local name = nameOf and nameOf(track) or track.Animation.AnimationId:match("%d+") or "?"
				local held = GameFreeze.heldSpeed(track) or speedBefore[name]
				table.insert(clips, ("%s <font color='#FFFFFF'>%.2f</font> (%.2f/%.2fs, x%.2f)"):format(
					escape(name), track.WeightCurrent,
					track.TimePosition, track.Length, held or track.Speed))
			end
		end
	end
	clipLine.Text = #clips > 0 and ("Clips: " .. table.concat(clips, "  ·  ")) or "Clips: none"

	-- the last changes before (and during the steps of) this freeze
	local track = recorder and recorder.tracks[selected.Name]
	local lines = {}
	for _, event in ipairs(track and track.events or {}) do
		local when = ("%+.2f"):format(event.t - (frozenAt or os.clock()))
		if event.kind == "clip" then
			table.insert(lines, ("<font color='#AAAAAA'>%s</font> ▶ clip %s"):format(when, escape(event.name)))
		elseif event.name ~= "Mind" and (type(event.value) == "string" or type(event.value) == "boolean") then
			table.insert(lines, ("<font color='#AAAAAA'>%s</font> %s → <font color='#3CAAFF'>%s</font>"):format(when, escape(event.name), escape(event.value)))
		end
	end
	changes.Text = #lines > 0 and table.concat(lines, "\n", math.max(1, #lines - 29), #lines) or "(no changes recorded)"
	changes.Visible = true
end

local function refresh()
	local frozen = GameClock.frozen()
	pill.Visible = isAdmin()
	pill.Text = frozen and "▶  RESUME  [F4]" or "||  FREEZE  [F4]"
	pill.BackgroundColor3 = frozen and Color3.fromRGB(60, 170, 255) or Color3.fromRGB(18, 22, 30)
	pill.TextColor3 = frozen and Color3.new(0, 0, 0) or Color3.fromRGB(235, 240, 255)
	stroke.Color = frozen and Color3.new(1, 1, 1) or Color3.fromRGB(60, 170, 255)
	local inspecting = frozen and isAdmin() and not replayOpen()
	panel.Visible = inspecting
	dot.Visible = inspecting and UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter
	if not inspecting then
		changes.Visible = false
		highlight.Parent = nil
	else
		highlight.Parent = selected and gui or nil
		refreshInfo()
	end
end

GameClock.changed:Connect(function(frozen)
	if Workspace:GetAttribute("GameStepping") then return end
	if frozen then
		frozenAt = os.clock()
		-- start on the Quin being watched
		local watched = Workspace:GetAttribute("SpectatedQuin")
		if not selected and type(watched) == "string" and watched ~= "" then
			for _, model in ipairs(CollectionService:GetTagged("Quin")) do
				if model.Name == watched then select(model) break end
			end
		end
	else
		frozenAt = nil
	end
	refresh()
end)
player:GetAttributeChangedSignal("SkylarkRole"):Connect(refresh)

----------------------------------------------------------------------------------------
-- Input
----------------------------------------------------------------------------------------
pill.MouseButton1Click:Connect(function()
	GameFreeze.request("toggle")
end)
frameButton.MouseButton1Click:Connect(function() GameFreeze.request("step", FRAME) end)
tenthButton.MouseButton1Click:Connect(function() GameFreeze.request("step", 0.1) end)
secondButton.MouseButton1Click:Connect(function() GameFreeze.request("step", 1) end)

UserInputService.InputBegan:Connect(function(input, processed)
	if UserInputService:GetFocusedTextBox() or not isAdmin() then return end
	if input.KeyCode == Enum.KeyCode.F4 then
		GameFreeze.request("toggle")
		return
	end
	if not GameClock.frozen() or replayOpen() then return end
	if input.KeyCode == Enum.KeyCode.Period then
		GameFreeze.request("step", FRAME)
	elseif input.UserInputType == Enum.UserInputType.MouseButton1 and not processed then
		local at = UserInputService:GetMouseLocation()
		local ray = camera:ViewportPointToRay(at.X, at.Y)
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Include
		params.FilterDescendantsInstances = CollectionService:GetTagged("Quin")
		local hit = Workspace:Raycast(ray.Origin, ray.Direction * 1500, params)
		if hit then
			for _, model in ipairs(CollectionService:GetTagged("Quin")) do
				if hit.Instance:IsDescendantOf(model) then select(model) break end
			end
			refresh()
		end
	end
end)

-- The panel follows the Quin while the game is stepped, and the dot the cursor's lock
local since = 0
RunService.Heartbeat:Connect(function(dt)
	since += dt
	if since < 0.2 then return end
	since = 0
	if GameClock.frozen() or panel.Visible then refresh() end
end)
refresh()

-- Test handle (a Studio test run has its own shared): Inspect:Invoke(quinName?) -> the panel's text
local inspect = Instance.new("BindableFunction")
inspect.Name = "Inspect"
inspect.OnInvoke = function(name)
	if name then
		for _, model in ipairs(CollectionService:GetTagged("Quin")) do
			if model.Name == name then select(model) break end
		end
	end
	refresh()
	return { panel = panel.Visible, info = infoLine.Text, clips = clipLine.Text, changes = changes.Text }
end
inspect.Parent = script
