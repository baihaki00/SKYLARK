--// QuinReplay.client.lua
-- The pause timeline (owner 2026-10-28: "buttons: PAUSE/PLAY ... we already have the scrubber ...
-- when I replay the scrubber the game stops where I last pause it"). PAUSE (F4, GodPauseClient)
-- freezes the real game and opens this: the timeline of the flight recorder (QuinRecorder) up to
-- the moment of the pause. Drag the scrubber back to see any moment before it: the real Quins are
-- hidden on this machine and ghost copies, posed from the recording, take their place. PLAY
-- closes it and the real game carries on from the pause, wherever the scrubber was left.
-- The ghosts carry the labels as they were at the scrubber's moment (state tag, PointTag,
-- InterestTag, debug values), and the 3D overlays draw from the recording too (overlay()).
--
--   timeline  click or drag to scrub; coloured by the followed Quin's state, ticks where its
--             clips started (white) and its task / tactics changed (gold)
--   , and .   one recorded frame back / forward
--   click a Quin (or its card on the debug menu) to follow it and inspect it (the debug menu's
--   Inspect tab); click the ground to stop following. Right mouse drag orbits round it, the wheel
--   zooms.
--
-- Studio, Admins only.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

if not RunService:IsStudio() then return end

local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera
local QuinTimeline = require(script.Parent:WaitForChild("QuinTimeline"))

local STATE_COLORS = {
	Idle = Color3.fromRGB(110, 120, 140), Chase = Color3.fromRGB(240, 170, 60), Fight = Color3.fromRGB(230, 70, 70),
	Circling = Color3.fromRGB(120, 200, 255), Retreat = Color3.fromRGB(160, 120, 255), Knockback = Color3.fromRGB(255, 90, 200),
	Recovery = Color3.fromRGB(200, 150, 200), ProjectileJump = Color3.fromRGB(90, 230, 160), MidAirClash = Color3.fromRGB(255, 230, 90),
	Special = Color3.fromRGB(255, 255, 255), Dead = Color3.fromRGB(40, 40, 40),
}
local MARK_ATTRIBUTES = { Task = true, TacticalState = true, PaceGear = true, ObstacleAwareness = true, JumpKind = true }

local function stateColor(state)
	if STATE_COLORS[state] then return STATE_COLORS[state] end
	local hash = 0
	for i = 1, #tostring(state) do hash = (hash * 31 + string.byte(tostring(state), i)) % 360 end
	return Color3.fromHSV(hash / 360, 0.5, 0.85)
end

----------------------------------------------------------------------------------------
-- State
----------------------------------------------------------------------------------------
local open = false
local recording -- the snapshot being replayed
local ghosts = {} -- name -> { model, parts = {index -> part}, bones = {index -> bone}, boneParentIndex, root }
local ghostFolder
local cursor, startT, endT = 0, 0, 0
local playing, speed = false, 1
local live = false -- glued to the newest frame (opened, or "Live" pressed, at 1x)
local followed -- Quin name
local followOffset
local hiddenGuis = {} -- real BillboardGuis switched off while open
local lastDrawn = nil -- the cursor the ghosts were last posed at

----------------------------------------------------------------------------------------
-- Ghosts
----------------------------------------------------------------------------------------
-- (the welds and joints stay: a mesh is skinned by the bones of its own assembly, so a ghost cut
-- into loose parts draws its body and clothes in the bind pose)
local STRIP = { "Script", "LocalScript", "ModuleScript", "Animator", "AlignPosition", "AlignOrientation",
	"VectorForce", "LinearVelocity", "AngularVelocity", "BodyMover", "BillboardGui", "Sound", "ForceField", "Highlight" }

local function resolve(model, path)
	local node = model
	for name in string.gmatch(path, "[^%.]+") do
		node = node and node:FindFirstChild(name)
	end
	return node
end

local function makeGhost(name, track)
	local model = track.model
	if not model or not model.Parent then return nil end
	local archivable = {}
	for _, d in ipairs(model:GetDescendants()) do
		archivable[d] = d.Archivable
		d.Archivable = true
	end
	local wasArchivable = model.Archivable
	model.Archivable = true
	local copy = model:Clone()
	model.Archivable = wasArchivable
	for d, value in pairs(archivable) do d.Archivable = value end
	if not copy then return nil end

	for _, tag in ipairs(CollectionService:GetTags(copy)) do CollectionService:RemoveTag(copy, tag) end
	for _, d in ipairs(copy:GetDescendants()) do
		for _, tag in ipairs(CollectionService:GetTags(d)) do CollectionService:RemoveTag(d, tag) end
		for _, class in ipairs(STRIP) do
			if d:IsA(class) then d:Destroy() break end
		end
	end
	-- parts held by a joint follow the root; the root and any loose part are placed from the recording
	local jointed = {}
	for _, d in ipairs(copy:GetDescendants()) do
		if d:IsA("JointInstance") or d:IsA("WeldConstraint") or d:IsA("RigidConstraint") then
			local a = d:IsA("RigidConstraint") and d.Attachment0 and d.Attachment0.Parent or d.Part0
			local b = d:IsA("RigidConstraint") and d.Attachment1 and d.Attachment1.Parent or d.Part1
			if a and b then jointed[a] = true jointed[b] = true end
		end
	end
	for _, d in ipairs(copy:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = d.Name == "HumanoidRootPart" or not jointed[d]
			d.CanCollide = false
			d.CanTouch = false
			d.CanQuery = d.Transparency < 1 or d.Name == "HumanoidRootPart"
			d.LocalTransparencyModifier = 0
		elseif d:IsA("Humanoid") then
			d.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
			d.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
			d.PlatformStand = true
		end
	end
	copy.Name = name
	copy:SetAttribute("ReplayGhost", true)

	local ghost = { model = copy, parts = {}, placed = {}, motors = {}, bones = {}, boneParent = {}, root = copy:FindFirstChild("HumanoidRootPart"),
		labels = {} } -- (path -> { gui, texts }: the recorded labels, rebuilt on the ghost; poseLabels)
	local partIndex = {}
	for i, path in ipairs(track.partNames) do
		local part = resolve(copy, path)
		if part and part:IsA("BasePart") then
			ghost.parts[i] = part
			partIndex[part] = i
			if part.Anchored then ghost.placed[i] = part end
		end
	end
	-- the animated joints (the root Motor6D): their Transform rebuilds the recorded offset
	for _, d in ipairs(copy:GetDescendants()) do
		if d:IsA("Motor6D") and partIndex[d.Part0] and partIndex[d.Part1] then
			table.insert(ghost.motors, { motor = d, i0 = partIndex[d.Part0], i1 = partIndex[d.Part1] })
		end
	end
	local boneIndex = {}
	for i, path in ipairs(track.boneNames) do
		local bone = resolve(copy, path)
		if bone and bone:IsA("Bone") then
			ghost.bones[i] = bone
			boneIndex[bone] = i
		end
	end
	-- a bone's parent: another recorded bone (its index) or the part it hangs from (minus its index)
	for i, bone in pairs(ghost.bones) do
		ghost.boneParent[i] = boneIndex[bone.Parent] or (partIndex[bone.Parent] and -partIndex[bone.Parent])
	end
	local highlight = Instance.new("Highlight")
	highlight.FillTransparency = 1
	highlight.OutlineTransparency = 1
	highlight.OutlineColor = Color3.fromRGB(255, 230, 90)
	highlight.Parent = copy
	ghost.highlight = highlight
	return ghost
end

local function clearGhosts()
	if ghostFolder then ghostFolder:Destroy() end
	ghostFolder, ghosts = nil, {}
end

----------------------------------------------------------------------------------------
-- Posing
----------------------------------------------------------------------------------------
local function framesAround(t)
	local frames = recording.frames
	local lo, hi = 1, #frames
	if t <= frames[1].t then return frames[1], frames[1], 0 end
	if t >= frames[hi].t then return frames[hi], frames[hi], 0 end
	while hi - lo > 1 do
		local mid = (lo + hi) // 2
		if frames[mid].t <= t then lo = mid else hi = mid end
	end
	local a, b = frames[lo], frames[hi]
	return a, b, (t - a.t) / math.max(b.t - a.t, 1e-6)
end

local function poseGhosts(t)
	local a, b, alpha = framesAround(t)
	for name, ghost in pairs(ghosts) do
		local poseA, poseB = a.quins[name], b.quins[name]
		if not poseA then poseA, alpha = poseB, 0 end
		if not poseA then
			ghost.model.Parent = nil
		else
			poseB = poseB or poseA
			ghost.model.Parent = ghostFolder
			local partWorld = {}
			for i in pairs(ghost.parts) do
				local ca, cb = poseA.parts[i], poseB.parts[i]
				if ca then partWorld[i] = cb and ca:Lerp(cb, alpha) or ca end
			end
			for i, part in pairs(ghost.placed) do
				if partWorld[i] then part.CFrame = partWorld[i] end
			end
			for _, joint in ipairs(ghost.motors) do
				local p0, p1 = partWorld[joint.i0], partWorld[joint.i1]
				if p0 and p1 then
					joint.motor.Transform = joint.motor.C0:Inverse() * p0:Inverse() * p1 * joint.motor.C1
				end
			end
			local world = {}
			for i, bone in pairs(ghost.bones) do
				local ca, cb = poseA.bones[i], poseB.bones[i]
				if ca then world[i] = cb and ca:Lerp(cb, alpha) or ca end
			end
			for i, bone in pairs(ghost.bones) do
				local target = world[i]
				if target then
					local parent = ghost.boneParent[i]
					local parentWorld
					if type(parent) == "number" then
						parentWorld = parent > 0 and world[parent] or partWorld[-parent]
					end
					if parentWorld then
						bone.Transform = (parentWorld * bone.CFrame):Inverse() * target
					end
				end
			end
		end
	end
end

-- The labels over each ghost as they were at time t (QuinRecorder: each label's state, and a copy
-- of it to rebuild it from). A label that did not exist then is switched off.
local function ghostLabel(ghost, track, path)
	local held = ghost.labels[path]
	if held and held.gui.Parent then return held end
	local template = track.labelTemplates and track.labelTemplates[path]
	local parent = resolve(ghost.model, path:match("^(.*)%.[^%.]+$") or "")
	if not template or not parent then return nil end
	local gui = template:Clone()
	-- (one pointed at a part of the real Quin points at the ghost's)
	local adornee = template.Adornee
	if adornee and track.model and adornee:IsDescendantOf(track.model) then
		gui.Adornee = resolve(ghost.model, adornee:GetFullName():sub(#track.model:GetFullName() + 2))
	end
	local texts = {}
	for _, d in ipairs(gui:GetDescendants()) do
		if d:IsA("TextLabel") or d:IsA("TextButton") or d:IsA("TextBox") then table.insert(texts, d) end
	end
	gui.Parent = parent
	held = { gui = gui, texts = texts }
	ghost.labels[path] = held
	return held
end

local function poseLabels(t)
	for name, ghost in pairs(ghosts) do
		local track = recording.tracks[name]
		if track and track.labelBase then
			local states = table.clone(track.labelBase)
			for _, event in ipairs(track.labelEvents) do
				if event.t > t then break end
				states[event.path] = event.state or nil
			end
			for path, held in pairs(ghost.labels) do
				if not states[path] then held.gui.Enabled = false end
			end
			for path, state in pairs(states) do
				local held = ghostLabel(ghost, track, path)
				if held then
					held.gui.Enabled = state.enabled
					for i, label in ipairs(held.texts) do
						if state.texts[i] ~= nil and label.Text ~= state.texts[i] then label.Text = state.texts[i] end
						if state.visible and state.visible[i] ~= nil then label.Visible = state.visible[i] end
					end
				end
			end
		end
	end
end

-- The followed Quin's pose and attributes at time t
local function poseAt(name, t)
	local a = framesAround(t)
	return a.quins[name]
end

local function attributesAt(name, t)
	local track = recording.tracks[name]
	if not track then return {} end
	local values = table.clone(track.base)
	for _, event in ipairs(track.events) do
		if event.t > t then break end
		if event.kind == "attr" then values[event.name] = event.value end
	end
	return values
end

----------------------------------------------------------------------------------------
-- Hiding the real Quins (this machine only)
----------------------------------------------------------------------------------------
local function hideReal(hidden)
	for _, model in ipairs(CollectionService:GetTagged("Quin")) do
		if model:GetAttribute("ReplayGhost") then continue end
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") then
				d.LocalTransparencyModifier = hidden and 1 or 0
			elseif hidden and d:IsA("BillboardGui") and d.Enabled then
				d.Enabled = false
				hiddenGuis[d] = true
			end
		end
	end
	if not hidden then
		for gui in pairs(hiddenGuis) do
			if gui.Parent then gui.Enabled = true end
		end
		hiddenGuis = {}
	end
end

----------------------------------------------------------------------------------------
-- UI
----------------------------------------------------------------------------------------
local gui = Instance.new("ScreenGui")
gui.Name = "QuinReplayUI"
gui.ResetOnSpawn = false
gui.DisplayOrder = 50
gui.Enabled = false
gui.Parent = player:WaitForChild("PlayerGui")

-- (under the PAUSE / PLAY bar, GodPauseClient: only the scrubber and what it shows; the followed
-- Quin's state, clips and changes go to the debug menu's Inspect tab, QuinDebugHUD)
local REPLAY_GOLD = Color3.fromRGB(255, 200, 60)

local panel = Instance.new("Frame")
panel.AnchorPoint = Vector2.new(0.5, 0)
panel.Position = UDim2.new(0.5, 0, 0, 46)
panel.Size = UDim2.new(0, 900, 0, 62)
panel.BackgroundColor3 = Color3.fromRGB(10, 12, 18)
panel.BackgroundTransparency = 0.12
panel.BorderSizePixel = 0
panel.Active = true -- (the wheel over it does not reach the camera)
panel.Parent = gui
Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 8)
local panelStroke = Instance.new("UIStroke", panel)
panelStroke.Color = Color3.fromRGB(60, 170, 255)
panelStroke.Transparency = 0.4

-- Timeline
local bar = Instance.new("TextButton")
bar.Text = ""
bar.AutoButtonColor = false
bar.Position = UDim2.new(0, 10, 0, 8)
bar.Size = UDim2.new(1, -20, 0, 26)
bar.BackgroundColor3 = Color3.fromRGB(24, 28, 40)
bar.BorderSizePixel = 0
bar.ClipsDescendants = true
bar.Parent = panel
local segments = Instance.new("Folder")
segments.Parent = bar
local playhead = Instance.new("Frame")
playhead.Size = UDim2.new(0, 2, 1, 0)
playhead.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
playhead.BorderSizePixel = 0
playhead.ZIndex = 5
playhead.Parent = bar

-- under the timeline: whose it is, where the cursor is, what the colours and ticks mean
local timeLabel = Instance.new("TextLabel")
timeLabel.Position = UDim2.new(0, 10, 0, 36)
timeLabel.Size = UDim2.new(1, -20, 0, 22)
timeLabel.BackgroundTransparency = 1
timeLabel.Font = Enum.Font.SourceSans
timeLabel.TextSize = 14
timeLabel.RichText = true
timeLabel.TextXAlignment = Enum.TextXAlignment.Left
timeLabel.TextColor3 = Color3.fromRGB(200, 210, 230)
timeLabel.Parent = panel

local function fraction(t)
	return (t - startT) / math.max(endT - startT, 1e-6)
end

local function drawTimeline()
	segments:ClearAllChildren()
	if not followed or not recording.tracks[followed] then return end
	local track = recording.tracks[followed]
	local width = bar.AbsoluteSize.X
	local function segment(from, to, state)
		local f = Instance.new("Frame")
		f.Position = UDim2.new(fraction(from), 0, 0, 0)
		f.Size = UDim2.new(fraction(to) - fraction(from), 0, 0.62, 0)
		f.BackgroundColor3 = stateColor(state)
		f.BorderSizePixel = 0
		f.Parent = segments
		-- (named only where the name fits)
		if (fraction(to) - fraction(from)) * width > #tostring(state) * 7 + 8 then
			local l = Instance.new("TextLabel")
			l.Size = UDim2.fromScale(1, 1)
			l.BackgroundTransparency = 1
			l.Font = Enum.Font.SourceSansBold
			l.TextSize = 13
			l.TextColor3 = Color3.new(0, 0, 0)
			l.Text = tostring(state)
			l.Parent = f
		end
	end
	local state, since = track.base.CurrentState, startT
	for _, event in ipairs(track.events) do
		if event.kind == "attr" and event.name == "CurrentState" and event.t >= startT then
			segment(since, event.t, state)
			state, since = event.value, event.t
		end
	end
	segment(since, endT, state)
	for _, event in ipairs(track.events) do
		local isClip = event.kind == "clip"
		if (isClip or (event.kind == "attr" and MARK_ATTRIBUTES[event.name])) and event.t >= startT and event.t <= endT then
			local tick = Instance.new("Frame")
			tick.Position = UDim2.new(fraction(event.t), 0, isClip and 0.62 or 0.81, 0)
			tick.Size = UDim2.new(0, 1, 0.19, 0)
			tick.BackgroundColor3 = isClip and Color3.new(1, 1, 1) or REPLAY_GOLD
			tick.BorderSizePixel = 0
			tick.Parent = segments
		end
	end
end

local function refreshButtons()
	for name, ghost in pairs(ghosts) do
		ghost.highlight.OutlineTransparency = name == followed and 0 or 1
	end
end

local openedAt = 0 -- the recorder time the replay opened: the changes are timed from it
local dockSince = 0
local dockPending = false -- (a throttled update still owed to the Inspect tab)

-- The followed Quin, to the Inspect tab (QuinTimeline): its state and clips at the cursor and its
-- changes; a change's before / after and report; picking one moves the cursor there
local function inspectData()
	if not followed then
		return { source = "paused", title = "Paused", info = "Click a Quin to see what it is doing and why; drag the scrubber to go back in time.", rows = {} }
	end
	local name, frames = followed, recording.frames
	local track = recording.tracks[name]
	local pose = QuinTimeline.poseAt(frames, name, cursor)
	return {
		source = "paused",
		title = name,
		info = ("<font color='#AAAAAA'>%+.2f s</font>  "):format(cursor - openedAt)
			.. QuinTimeline.stateLine(QuinTimeline.attributesAt(track, cursor), pose, true, "#FFC83C"),
		clips = QuinTimeline.clipsLine(pose, true),
		rows = QuinTimeline.rows(track, openedAt),
		cursor = cursor, -- (the list follows the scrubber)
		pick = function(t) return QuinTimeline.card(track, frames, name, t, openedAt, true) end,
		report = function(t) return QuinTimeline.card(track, frames, name, t, openedAt, false) end,
		onPick = function(t)
			cursor = math.clamp(t, startT, endT)
			playing, live = false, false
			refreshButtons()
		end,
	}
end

local function refreshInfo(force)
	playhead.Position = UDim2.new(fraction(cursor), -1, 0, 0)
	local when = endT - cursor < 1e-3 and "<b>at the pause</b>" or ("<b>%.2f s before the pause</b>"):format(endT - cursor)
	timeLabel.Text = followed
		and ("<b>%s</b>  ·  %s  ·  colour = its state  ·  white tick = a clip starts  ·  gold tick = task / tactics change  ·  drag to scrub"):format(QuinTimeline.escape(followed), when)
		or (when .. "  ·  drag to scrub  ·  click a Quin to follow it: the timeline shows its states and clips")
	-- (a few times a second: the rows are rebuilt only when they change)
	local now = os.clock()
	if not force and now - dockSince < 0.15 then
		dockPending = true
		return
	end
	dockSince, dockPending = now, false
	if shared.DebugDock then shared.DebugDock.setInspect(inspectData()) end
end

----------------------------------------------------------------------------------------
-- Camera
----------------------------------------------------------------------------------------
-- The followed Quin is the selected Quin everywhere (the menu's cards, the debug scope, the 3D
-- overlays): Workspace SpectatedQuin / shared.SpectatedQuin, as a card click sets them
local function selectQuin(name)
	local real
	for _, model in ipairs(CollectionService:GetTagged("Quin")) do
		if model.Name == name then real = model break end
	end
	shared.SpectatedQuin = real
	_G.SpectatedQuin = real
	Workspace:SetAttribute("SpectatedQuin", real and name or "")
end

local function follow(name)
	followed = name
	selectQuin(name)
	local ghost = name and ghosts[name]
	if ghost and ghost.root then
		local offset = camera.CFrame.Position - ghost.root.Position
		if offset.Magnitude > 60 or offset.Magnitude < 4 then
			local back = -ghost.root.CFrame.LookVector
			offset = Vector3.new(back.X, 0, back.Z).Unit * 16 + Vector3.new(0, 7, 0)
		end
		followOffset = offset
	else
		followOffset = nil
		shared.ReplayCameraCFrame = nil
	end
	drawTimeline()
	refreshButtons()
	refreshInfo(true)
end

-- (owner 2026-10-28: orbit round the followed Quin) right mouse drag turns the camera round it;
-- the height stays between just above the ground and nearly overhead. Read each frame from the
-- cursor's place: with a free cursor the input events carry no movement
local lastOrbitAt
local function orbit()
	if not (followOffset and UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)) then
		lastOrbitAt = nil
		return
	end
	local at = UserInputService:GetMouseLocation()
	local delta = UserInputService:GetMouseDelta()
	if delta.Magnitude < 1e-3 then delta = lastOrbitAt and (at - lastOrbitAt) or Vector2.zero end
	lastOrbitAt = at
	if delta.Magnitude < 1e-3 then return end
	local distance = followOffset.Magnitude
	local flat = Vector3.new(followOffset.X, 0, followOffset.Z)
	local yaw = math.atan2(flat.X, flat.Z) - delta.X * 0.006
	local pitch = math.clamp(math.atan2(followOffset.Y, flat.Magnitude) + delta.Y * 0.006, math.rad(-5), math.rad(80))
	followOffset = Vector3.new(math.sin(yaw) * math.cos(pitch), math.sin(pitch), math.cos(yaw) * math.cos(pitch)) * distance
end

local function updateCamera()
	orbit()
	local ghost = followed and ghosts[followed]
	if not (ghost and followOffset and ghost.root and ghost.model.Parent) then
		shared.ReplayCameraCFrame = nil
		return
	end
	local focus = ghost.root.Position + Vector3.new(0, 1.5, 0)
	shared.ReplayCameraCFrame = CFrame.lookAt(focus + followOffset, focus)
end

----------------------------------------------------------------------------------------
-- Open / close
----------------------------------------------------------------------------------------
local failedGhosts = {} -- Quin names whose ghost could not be made (gone before it was needed)

-- A ghost for every Quin in the recording (new Quins appear while it is open)
local function addGhosts()
	for name, track in pairs(recording.tracks) do
		if not ghosts[name] and failedGhosts[track] == nil then
			local ghost = makeGhost(name, track)
			failedGhosts[track] = ghost == nil
			if ghost then
				ghosts[name] = ghost
				ghost.model.Parent = ghostFolder
			end
		end
	end
end

local function syncBounds()
	local frames = recording.frames
	if #frames == 0 then return end
	startT, endT = frames[1].t, frames[#frames].t
	cursor = math.clamp(cursor, startT, endT)
end

local function load()
	local recorder = shared.QuinRecorder
	local buffer = recorder and recorder.live()
	if not buffer or #buffer.frames < 2 then
		warn("[QuinReplay] Nothing recorded yet (the recorder runs for Admins while Quins are out).")
		return false
	end
	clearGhosts()
	failedGhosts = {}
	recording = buffer
	shared.QuinRecorderHold = true -- (nothing being watched falls off the front while open)
	ghostFolder = Instance.new("Folder")
	ghostFolder.Name = "QuinReplayGhosts"
	ghostFolder.Parent = Workspace
	addGhosts()
	-- open at the pause, still, on the Quin being watched
	cursor = math.huge
	syncBounds()
	lastDrawn = nil
	playing, speed, live = false, 1, false
	openedAt = endT
	local watched = Workspace:GetAttribute("SpectatedQuin")
	poseGhosts(cursor)
	poseLabels(cursor)
	follow(ghosts[watched] and watched or nil)
	return true
end

local function allowedToOpen()
	return player:GetAttribute("SkylarkRole") == "Admin"
end

local function setOpen(value)
	if value == open then return end
	if value then
		if not load() then return end
		open = true
		gui.Enabled = true
		hideReal(true)
		if shared.DebugDock then shared.DebugDock.open("Inspect") end
		refreshInfo(true)
	else
		open = false
		gui.Enabled = false
		hideReal(false)
		clearGhosts()
		recording, followed, followOffset = nil, nil, nil
		shared.ReplayCameraCFrame = nil
		shared.QuinRecorderHold = nil
		if shared.DebugDock then shared.DebugDock.setInspect(nil) end
	end
end

-- What the 3D overlays (RuntimeVisualizer.updateReplay) draw while paused: each ghost as a view at
-- the cursor (its posed root, the velocity, health and attributes recorded then) and the server's
-- drawings that were on screen at that moment. nil when closed: the overlays draw the live game.
local function overlay()
	if not open or not recording or #recording.frames == 0 then return nil end
	local frame = framesAround(cursor)
	local function view(name)
		local ghost, pose = ghosts[name], frame.quins[name]
		if not (ghost and pose and ghost.root and ghost.model.Parent) then return nil end
		local attributes = attributesAt(name, cursor)
		local targetName = attributes.CurrentTarget or attributes.TargetQuin
		local target = type(targetName) == "string" and ghosts[targetName]
		return {
			name = name,
			root = ghost.root,
			velocity = pose.velocity or Vector3.zero,
			health = pose.health or 0,
			attr = function(key)
				if key == "Energy" then return pose.energy end
				if key == "LastSeenTargetPosition" then return pose.lastSeen end
				return attributes[key]
			end,
			targetRoot = target and target.model.Parent and target.root or nil,
			targetName = targetName,
			exclude = { ghostFolder },
		}
	end
	local names = {}
	for name in pairs(ghosts) do table.insert(names, name) end
	local primitives = {}
	for _, drawn in ipairs(recording.drawings or {}) do
		if drawn.t > cursor then break end
		for _, primitive in ipairs(drawn.batch) do
			if drawn.t + (primitive[6] or 0.2) > cursor then table.insert(primitives, primitive) end
		end
	end
	return { view = view, names = names, spectated = followed, primitives = primitives }
end

-- (PAUSE opens it, PLAY closes it: GodPauseClient)
shared.QuinReplay = {
	open = function() if allowedToOpen() then setOpen(true) end end,
	atPause = function() return not open or not recording or endT - cursor < 1e-3 end,
	overlay = overlay,
	close = function() setOpen(false) end,
	isOpen = function() return open end,
}

local function step(frames)
	if not recording then return end
	playing = false
	local list = recording.frames
	-- the nearest recorded frame in that direction
	local index = 1
	for i, frame in ipairs(list) do
		if frame.t <= cursor + 1e-6 then index = i end
	end
	if frames < 0 and list[index].t >= cursor - 1e-6 then index -= 1 elseif frames > 0 then index += 1 end
	index = math.clamp(index, 1, #list)
	cursor = list[index].t
	refreshButtons()
end

----------------------------------------------------------------------------------------
-- Input
----------------------------------------------------------------------------------------
local function allowed()
	return player:GetAttribute("SkylarkRole") == "Admin"
end

local scrubbing = false
local function scrubTo(x)
	local f = math.clamp((x - bar.AbsolutePosition.X) / bar.AbsoluteSize.X, 0, 1)
	cursor = startT + f * (endT - startT)
	playing = false
	refreshButtons()
end
bar.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		scrubbing = true
		scrubTo(input.Position.X)
	end
end)
UserInputService.InputChanged:Connect(function(input, processed)
	if scrubbing and input.UserInputType == Enum.UserInputType.MouseMovement then
		scrubTo(input.Position.X)
	elseif open and followOffset and input.UserInputType == Enum.UserInputType.MouseWheel and not processed
		and not (shared.PointerOverMenu and shared.PointerOverMenu()) then
		followOffset = followOffset * (input.Position.Z > 0 and 0.88 or 1.14)
	end
end)

-- A Quin picked on the debug menu's cards (QuinDebugHUD: Workspace SpectatedQuin) is followed here
-- too while paused: the cards move this camera, not only the usual one
Workspace:GetAttributeChangedSignal("SpectatedQuin"):Connect(function()
	if not open then return end
	local name = Workspace:GetAttribute("SpectatedQuin")
	if type(name) == "string" and ghosts[name] and name ~= followed then follow(name) end
end)
UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then scrubbing = false end
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if UserInputService:GetFocusedTextBox() then return end
	if not open then return end
	if input.KeyCode == Enum.KeyCode.Comma then
		step(-1)
	elseif input.KeyCode == Enum.KeyCode.Period then
		step(1)
	elseif input.UserInputType == Enum.UserInputType.MouseButton1 and not processed and ghostFolder then
		-- click a Quin to follow it, the ground to stop following
		local at = UserInputService:GetMouseLocation()
		local ray = camera:ViewportPointToRay(at.X, at.Y)
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Include
		params.FilterDescendantsInstances = { ghostFolder }
		local hit = Workspace:Raycast(ray.Origin, ray.Direction * 1000, params)
		local model = hit and hit.Instance:FindFirstAncestorWhichIsA("Model")
		while model and model.Parent ~= ghostFolder do model = model.Parent end
		follow(model and model.Name or nil)
	end
end)

----------------------------------------------------------------------------------------
-- Run
----------------------------------------------------------------------------------------
local housekeeping = 0
RunService:BindToRenderStep("QuinReplay", Enum.RenderPriority.Camera.Value - 1, function(dt)
	if not open then return end
	if not allowed() then setOpen(false) return end
	if live and (not playing or speed ~= 1) then live = false end
	if playing then cursor += dt * speed end
	if live then cursor = math.huge end
	syncBounds() -- (at the live edge, playing stays live)
	housekeeping += dt
	if housekeeping > 0.5 then
		housekeeping = 0
		addGhosts()
		drawTimeline()
		refreshButtons()
	end
	if cursor ~= lastDrawn or playing then
		poseGhosts(cursor)
		poseLabels(cursor)
		refreshInfo()
		lastDrawn = cursor
	elseif dockPending then
		refreshInfo()
	end
	hideReal(true) -- (re-applied: other scripts reset the transparency modifier, new Quins appear)
	updateCamera()
end)

-- (for the test handle: the labels shown on the followed ghost, and what the overlays would draw)
local function labelSummary()
	local ghost = followed and ghosts[followed]
	if not ghost then return nil end
	local out = {}
	for path, held in pairs(ghost.labels) do
		local texts = {}
		for _, label in ipairs(held.texts) do
			if label.Text ~= "" and label.Visible then table.insert(texts, label.Text) end
		end
		table.insert(out, ("%s %s: %s"):format(path, held.gui.Enabled and "on" or "off", table.concat(texts, " / ")))
	end
	return table.concat(out, " | ")
end

local function overlaySummary()
	local data = overlay()
	if not data then return nil end
	local v = data.spectated and data.view(data.spectated)
	return ("%d server primitives; followed: %s"):format(#data.primitives,
		v and ("%s energy %s target %s"):format(tostring(v.attr("CurrentState")), tostring(v.attr("Energy")), tostring(v.targetName)) or "none")
end

-- Test handle (a Studio test run has its own shared): Control:Invoke("open" | "close" | "state", arg)
local control = Instance.new("BindableFunction")
control.Name = "Control"
control.OnInvoke = function(what, arg)
	if what == "open" then setOpen(true) elseif what == "close" then setOpen(false)
	elseif what == "follow" then follow(arg)
	elseif what == "seek" then cursor = startT + (arg or 0) * (endT - startT) playing = false
	elseif what == "play" then speed = arg or speed playing = true
	elseif what == "live" then cursor, playing, speed, live = endT, true, 1, true end
	local count = 0
	for _ in pairs(ghosts) do count += 1 end
	local data = open and recording and inspectData()
	local lastRow = data and data.rows[#data.rows]
	return { open = open, ghosts = count, followed = followed, cursor = cursor - startT, span = endT - startT,
		info = data and data.info, clips = data and data.clips, rows = data and #data.rows,
		report = lastRow and data.report and data.report(lastRow.t),
		followOffset = followOffset and tostring(followOffset), camera = shared.ReplayCameraCFrame ~= nil,
		labels = labelSummary(), overlay = overlaySummary() }
end
control.Parent = script
