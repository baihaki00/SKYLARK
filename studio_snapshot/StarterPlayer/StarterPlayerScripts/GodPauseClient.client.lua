--// GodPauseClient.client.lua
-- The god pause (owner 2026-10-28): one button, PAUSE / PLAY (F4). PAUSE freezes the real game
-- (QuinCore Modules/GameFreeze) and opens the scrubber (QuinReplay) to go back through what led
-- up to it; PLAY closes the scrubber and the game carries on from the pause. While paused the
-- cameras still fly (B) and a click on a Quin inspects it (the debug menu's Inspect tab; the dot
-- in the middle aims when the cursor is locked). If nothing was recorded yet the pause still
-- works, and the inspector here reads the live (frozen) Quin instead.
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


local function isAdmin()
	return player:GetAttribute("SkylarkRole") == "Admin"
end

local escape = QuinTimeline.escape

----------------------------------------------------------------------------------------
-- UI: one button at the top (owner 2026-10-28: "buttons: PAUSE/PLAY ... we already have the
-- scrubber"); the scrubber sits under it while paused (QuinReplay).
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

local pauseButton = button("PAUSE [F4]", 130)

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
	-- (the selected Quin everywhere: the menu's cards, the debug scope, the 3D overlays)
	if model then
		shared.SpectatedQuin = model
		_G.SpectatedQuin = model
		Workspace:SetAttribute("SpectatedQuin", model.Name)
	end
end

-- The clicked Quin, to the menu's Inspect tab: what it is doing and why, the clips held on it
-- (weight, where in the clip, the speed it had), its changes (the flight recorder, QuinRecorder)
-- with each one's before / after and report (QuinTimeline)
local function sendInspect()
	local dock = shared.DebugDock
	if not dock then return end
	if not selected or not selected.Parent then
		dock.setInspect({ source = "paused", title = "Paused", info = "Click a Quin to see what it is doing and why  ·  B flies  ·  middle mouse frees the cursor", rows = {} })
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
		source = "paused",
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
	bar.Visible = isAdmin()
	pauseButton.Text = frozen and "PLAY [F4]" or "PAUSE [F4]"
	pauseButton.BackgroundColor3 = frozen and Color3.fromRGB(30, 140, 100) or Color3.fromRGB(32, 40, 58)
	stroke.Color = frozen and Color3.fromRGB(60, 170, 255) or Color3.fromRGB(40, 50, 70)
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
		-- the scrubber, up to this moment
		if isAdmin() and shared.QuinReplay then shared.QuinReplay.open() end
		if isAdmin() and shared.DebugDock then shared.DebugDock.open("Inspect") end
		-- start on the Quin being watched
		local watched = Workspace:GetAttribute("SpectatedQuin")
		if not selected and type(watched) == "string" and watched ~= "" then
			for _, model in ipairs(CollectionService:GetTagged("Quin")) do
				if model.Name == watched then select(model) break end
			end
		end
	else
		frozenAt = nil
		if shared.QuinReplay then shared.QuinReplay.close() end
	end
	refresh()
end)
player:GetAttributeChangedSignal("SkylarkRole"):Connect(refresh)

----------------------------------------------------------------------------------------
-- Input
----------------------------------------------------------------------------------------
pauseButton.MouseButton1Click:Connect(function()
	GameFreeze.request("toggle")
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if UserInputService:GetFocusedTextBox() or not isAdmin() then return end
	if input.KeyCode == Enum.KeyCode.F4 then
		GameFreeze.request("toggle")
		return
	end
	if not GameClock.frozen() or replayOpen() then return end
	if input.UserInputType == Enum.UserInputType.MouseButton1 and not processed then
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
