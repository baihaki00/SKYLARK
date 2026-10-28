--// GodPauseClient.client.lua
-- The god pause (owner 2026-10-28): F4 or the bar at the top freezes the real game and resumes
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
local QuinTimeline = require(script.Parent:WaitForChild("QuinTimeline"))

local FRAME = 1 / 60

local function isAdmin()
	return player:GetAttribute("SkylarkRole") == "Admin"
end

local escape = QuinTimeline.escape

----------------------------------------------------------------------------------------
-- UI: one bar at the top (owner 2026-10-28: the resume beside the steps, not panels everywhere;
-- "make sure there's no extra buttons that do the same thing"): the GAME bar - its state, freeze /
-- resume, the steps (only while frozen) and Open replay. While the replay is open this bar hides
-- and the replay's own bar takes its place (QuinReplay), so one button per action is on screen.
-- What the clicked Quin is doing goes to the debug menu's Inspect tab (QuinDebugHUD).
----------------------------------------------------------------------------------------
local gui = Instance.new("ScreenGui")
gui.Name = "GodPauseUI"
gui.ResetOnSpawn = false
gui.DisplayOrder = 60
gui.Parent = player:WaitForChild("PlayerGui")

local bar = Instance.new("Frame")
bar.Name = "DebugBar"
bar.AnchorPoint = Vector2.new(0.5, 0)
bar.Position = UDim2.new(0.5, 0, 0, 8)
bar.Size = UDim2.new(0, 0, 0, 32)
bar.AutomaticSize = Enum.AutomaticSize.X
bar.BackgroundColor3 = Color3.fromRGB(10, 12, 18)
bar.BackgroundTransparency = 0.12
bar.BorderSizePixel = 0
bar.Active = true -- (the wheel over it does not reach the camera)
bar.Parent = gui
Instance.new("UICorner", bar).CornerRadius = UDim.new(0, 8)
local stroke = Instance.new("UIStroke", bar)
stroke.Thickness = 1.5
local barList = Instance.new("UIListLayout")
barList.FillDirection = Enum.FillDirection.Horizontal
barList.VerticalAlignment = Enum.VerticalAlignment.Center
barList.Padding = UDim.new(0, 4)
barList.SortOrder = Enum.SortOrder.LayoutOrder
barList.Parent = bar
local barPadding = Instance.new("UIPadding")
barPadding.PaddingLeft, barPadding.PaddingRight = UDim.new(0, 4), UDim.new(0, 4)
barPadding.Parent = bar

local buttonCount = 0
local function button(text, width)
	buttonCount += 1
	local b = Instance.new("TextButton")
	b.LayoutOrder = buttonCount
	b.Size = UDim2.new(0, width, 0, 24)
	b.BackgroundColor3 = Color3.fromRGB(32, 40, 58)
	b.TextColor3 = Color3.fromRGB(235, 240, 255)
	b.Font = Enum.Font.SourceSansBold -- (Gotham drew "0.1" as "0J")
	b.TextSize = 14
	b.Text = text
	b.BorderSizePixel = 0
	b.Parent = bar
	Instance.new("UICorner", b).CornerRadius = UDim.new(0, 4)
	return b
end

local stateChip = button("GAME RUNNING", 120)
stateChip.AutoButtonColor = false
stateChip.Active = false
local freezeButton = button("Freeze game [F4]", 130)
local frameButton = button("Step 1 frame [.]", 112)
local tenthButton = button("Step 0.1 s", 76)
local secondButton = button("Step 1 s", 64)
local replayButton = button("Open replay [F6]", 120)
local stepButtons = { frameButton, tenthButton, secondButton }

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

-- The clicked Quin, to the menu's Inspect tab: what it is doing and why, the clips held on it
-- (weight, where in the clip, the speed it had), its changes (the flight recorder, QuinRecorder)
-- with each one's before / after and report (QuinTimeline)
local function sendInspect()
	local dock = shared.DebugDock
	if not dock then return end
	if not selected or not selected.Parent then
		dock.setInspect({ source = "frozen", title = "Frozen", info = "Click a Quin to see what it is doing and why  ·  B flies  ·  middle mouse frees the cursor", rows = {} })
		return
	end
	local name = selected.Name
	local parts = {}
	local humanoid = selected:FindFirstChildOfClass("Humanoid")
	if humanoid then
		table.insert(parts, ("HP %d"):format(humanoid.Health))
		table.insert(parts, "Humanoid " .. humanoid:GetState().Name)
	end
	for _, key in ipairs(QuinTimeline.KEYS) do
		local v = selected:GetAttribute(key)
		if v ~= nil and v ~= "" then table.insert(parts, ("%s <font color='#3CAAFF'>%s</font>"):format(key, escape(v))) end
	end

	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	local clips = {}
	local recorder = shared.QuinRecorder and shared.QuinRecorder.live()
	local nameOf = shared.QuinRecorder and shared.QuinRecorder.clipName
	-- the speeds the clips had before the freeze (the recorder's last frame: nothing is recorded
	-- while frozen; the clips themselves show 0 now)
	local frames = recorder and recorder.frames
	-- (newest frame first, back over the last second: the newest frames can already show a clip
	-- held by the server before this machine saw the freeze)
	local speedBefore = {}
	for index = #(frames or {}), math.max(1, #(frames or {}) - 30), -1 do
		local pose = frames[index].quins[name]
		for _, clip in ipairs(pose and pose.clips or {}) do
			if speedBefore[clip.name] == nil and clip.speed ~= 0 then speedBefore[clip.name] = clip.speed end
		end
	end
	if animator then
		local tracks = animator:GetPlayingAnimationTracks()
		table.sort(tracks, function(a, b) return a.WeightCurrent > b.WeightCurrent end)
		for _, track in ipairs(tracks) do
			if track.WeightCurrent > 0.01 then
				local clipName = nameOf and nameOf(track) or track.Animation.AnimationId:match("%d+") or "?"
				local held = GameFreeze.heldSpeed(track) or speedBefore[clipName]
				table.insert(clips, ("%s <font color='#FFFFFF'>%.2f</font> (%.2f/%.2fs, x%.2f)"):format(
					escape(clipName), track.WeightCurrent,
					track.TimePosition, track.Length, held or track.Speed))
			end
		end
	end

	local track = recorder and recorder.tracks[name]
	local refT = frozenAt or os.clock()
	dock.setInspect({
		source = "frozen",
		title = name,
		info = table.concat(parts, "  ·  "),
		clips = #clips > 0 and table.concat(clips, "  ·  ") or "none",
		rows = QuinTimeline.rows(track, refT),
		pick = function(t) return QuinTimeline.card(track, frames, name, t, refT, true) end,
		report = function(t) return QuinTimeline.card(track, frames, name, t, refT, false) end,
	})
end

local function refresh()
	local frozen = GameClock.frozen()
	local replay = replayOpen()
	bar.Visible = isAdmin() and not replay
	stateChip.Text = frozen and "GAME FROZEN" or "GAME RUNNING"
	stateChip.BackgroundColor3 = frozen and Color3.fromRGB(60, 170, 255) or Color3.fromRGB(30, 140, 100)
	stateChip.TextColor3 = frozen and Color3.new(0, 0, 0) or Color3.new(1, 1, 1)
	freezeButton.Text = frozen and "Resume game [F4]" or "Freeze game [F4]"
	stroke.Color = frozen and Color3.fromRGB(60, 170, 255) or Color3.fromRGB(40, 50, 70)
	for _, b in ipairs(stepButtons) do b.Visible = frozen end
	local inspecting = frozen and isAdmin() and not replay
	dot.Visible = inspecting and UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter
	if not inspecting then
		highlight.Parent = nil
	else
		highlight.Parent = selected and gui or nil
		sendInspect()
	end
end

GameClock.changed:Connect(function(frozen)
	if Workspace:GetAttribute("GameStepping") then return end
	if frozen then
		frozenAt = os.clock()
		if isAdmin() and shared.DebugDock and not replayOpen() then shared.DebugDock.open("Inspect") end
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
freezeButton.MouseButton1Click:Connect(function()
	GameFreeze.request("toggle")
end)
local function stepBy(seconds)
	if GameClock.frozen() then GameFreeze.request("step", seconds) end
end
frameButton.MouseButton1Click:Connect(function() stepBy(FRAME) end)
tenthButton.MouseButton1Click:Connect(function() stepBy(0.1) end)
secondButton.MouseButton1Click:Connect(function() stepBy(1) end)
replayButton.MouseButton1Click:Connect(function()
	if shared.QuinReplay then shared.QuinReplay.toggle() end
	task.defer(refresh)
end)

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
			if shared.DebugDock then shared.DebugDock.open("Inspect") end
			refresh()
		end
	end
end)

-- The Inspect tab follows the Quin while the game is stepped, and the dot the cursor's lock
local since = 0
RunService.Heartbeat:Connect(function(dt)
	since += dt
	if since < 0.2 then return end
	since = 0
	refresh()
end)
refresh()

-- Test handle (a Studio test run has its own shared): Inspect:Invoke(quinName?) -> what went to
-- the Inspect tab
local inspect = Instance.new("BindableFunction")
inspect.Name = "Inspect"
inspect.OnInvoke = function(name)
	if name then
		for _, model in ipairs(CollectionService:GetTagged("Quin")) do
			if model.Name == name then select(model) break end
		end
	end
	local sent
	local dock = shared.DebugDock
	local real = dock and dock.setInspect
	if dock then dock.setInspect = function(data) sent = data real(data) end end
	refresh()
	if dock then dock.setInspect = real end
	local rows = {}
	for _, row in ipairs(sent and sent.rows or {}) do table.insert(rows, row.text) end
	local lastRow = sent and sent.rows and sent.rows[#sent.rows]
	return { bar = bar.Visible, title = sent and sent.title, info = sent and sent.info, clips = sent and sent.clips,
		rows = #rows, lastRows = table.concat(rows, "\n", math.max(1, #rows - 5)),
		report = lastRow and sent.report and sent.report(lastRow.t) }
end
inspect.Parent = script
