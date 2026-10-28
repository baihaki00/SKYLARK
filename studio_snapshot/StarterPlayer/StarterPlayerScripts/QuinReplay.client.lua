--// QuinReplay.client.lua
-- The replay (debugger step 3, owner 2026-10-28): F6 shows the fight through the flight recorder
-- (QuinRecorder) on this machine only, so it can be slowed down, paused or scrubbed back while the
-- game itself goes on as it is (the server and everyone else never see any of it). The real Quins
-- are hidden here and ghost copies take their place, posed from the recording, which keeps growing
-- while the replay is open: it opens live, 0.5x falls behind and watches the fight go on slowed,
-- "Live" catches up again. Close shows the real Quins again.
--
--   F6        open / close
--   X         play / pause          , and .   one frame back / forward
--   speeds    0.1x 0.3x 0.5x 1x (buttons)
--   timeline  click or drag to scrub; coloured by the followed Quin's state, ticks where its
--             clips started (white) and its task / tactics changed (gold)
--   click a ghost to follow it (the camera keeps its offset; the wheel zooms); "Free camera" lets
--   the usual cameras fly (B). While following, the cursor is free (SmoothCamera); in the free
--   camera the middle mouse button (or L) frees it for the buttons.
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

local SPEEDS = { 0.1, 0.3, 0.5, 1 }
local STATE_COLORS = {
	Idle = Color3.fromRGB(110, 120, 140), Chase = Color3.fromRGB(240, 170, 60), Fight = Color3.fromRGB(230, 70, 70),
	Circling = Color3.fromRGB(120, 200, 255), Retreat = Color3.fromRGB(160, 120, 255), Knockback = Color3.fromRGB(255, 90, 200),
	Recovery = Color3.fromRGB(200, 150, 200), ProjectileJump = Color3.fromRGB(90, 230, 160), MidAirClash = Color3.fromRGB(255, 230, 90),
	Special = Color3.fromRGB(255, 255, 255), Dead = Color3.fromRGB(40, 40, 40),
}
local MARK_ATTRIBUTES = { Task = true, TacticalState = true, PaceGear = true, ObstacleAwareness = true, JumpKind = true }
-- shown in the info line, in this order
local INFO_ATTRIBUTES = { "CurrentState", "TacticalState", "Task", "TaskWhy", "PaceGear", "PaceWhy", "CurrentTarget", "LookMode", "ReactionType", "ObstacleAwareness" }

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

	local ghost = { model = copy, parts = {}, placed = {}, motors = {}, bones = {}, boneParent = {}, root = copy:FindFirstChild("HumanoidRootPart") }
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

local panel = Instance.new("Frame")
panel.AnchorPoint = Vector2.new(0.5, 1)
panel.Position = UDim2.new(0.5, 0, 1, -12)
panel.Size = UDim2.new(0, 820, 0, 172)
panel.BackgroundColor3 = Color3.fromRGB(10, 12, 18)
panel.BackgroundTransparency = 0.12
panel.BorderSizePixel = 0
panel.Parent = gui
Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 8)
local panelStroke = Instance.new("UIStroke", panel)
panelStroke.Color = Color3.fromRGB(255, 200, 60)
panelStroke.Transparency = 0.4

local function button(text, x, width, color)
	local b = Instance.new("TextButton")
	b.Position = UDim2.new(0, x, 0, 8)
	b.Size = UDim2.new(0, width, 0, 24)
	b.BackgroundColor3 = color or Color3.fromRGB(32, 40, 58)
	b.TextColor3 = Color3.fromRGB(235, 240, 255)
	b.Font = Enum.Font.GothamBold
	b.TextSize = 11
	b.Text = text
	b.AutoButtonColor = true
	b.Parent = panel
	Instance.new("UICorner", b).CornerRadius = UDim.new(0, 4)
	return b
end

local title = Instance.new("TextLabel")
title.Position = UDim2.new(0, 10, 0, 8)
title.Size = UDim2.new(0, 70, 0, 24)
title.BackgroundTransparency = 1
title.Font = Enum.Font.GothamBlack
title.TextSize = 12
title.TextColor3 = Color3.fromRGB(255, 200, 60)
title.TextXAlignment = Enum.TextXAlignment.Left
title.Text = "REPLAY"
title.Parent = panel

local playButton = button("▶ Play [X]", 76, 84, Color3.fromRGB(30, 140, 100))
local backButton = button("◀ [,]", 164, 44)
local forwardButton = button("[.] ▶", 212, 44)
local speedButtons = {}
for i, s in ipairs(SPEEDS) do
	speedButtons[s] = button(s .. "x", 262 + (i - 1) * 44, 40)
end
local latestButton = button("Live", 442, 70)
local freeButton = button("Free camera", 516, 86)
local closeButton = button("Close [F6]", 732, 78, Color3.fromRGB(120, 40, 40))

local timeLabel = Instance.new("TextLabel")
timeLabel.Position = UDim2.new(0, 606, 0, 8)
timeLabel.Size = UDim2.new(0, 122, 0, 24)
timeLabel.BackgroundTransparency = 1
timeLabel.Font = Enum.Font.Code
timeLabel.TextSize = 12
timeLabel.TextColor3 = Color3.fromRGB(220, 230, 255)
timeLabel.Parent = panel

-- Timeline
local bar = Instance.new("TextButton")
bar.Text = ""
bar.AutoButtonColor = false
bar.Position = UDim2.new(0, 10, 0, 40)
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
local infoLine = infoLabel(72, 46, 12, Color3.fromRGB(235, 240, 255))
local clipLine = infoLabel(122, 44, 11, Color3.fromRGB(170, 200, 255))

-- Recent changes beside the panel
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

local function escape(text)
	return (tostring(text):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

local function fraction(t)
	return (t - startT) / math.max(endT - startT, 1e-6)
end

local function drawTimeline()
	segments:ClearAllChildren()
	if not followed or not recording.tracks[followed] then return end
	local track = recording.tracks[followed]
	local function segment(from, to, state)
		local f = Instance.new("Frame")
		f.Position = UDim2.new(fraction(from), 0, 0, 0)
		f.Size = UDim2.new(fraction(to) - fraction(from), 0, 0.62, 0)
		f.BackgroundColor3 = stateColor(state)
		f.BorderSizePixel = 0
		f.Parent = segments
		if to - from > (endT - startT) * 0.05 then
			local l = Instance.new("TextLabel")
			l.Size = UDim2.fromScale(1, 1)
			l.BackgroundTransparency = 1
			l.Font = Enum.Font.GothamBold
			l.TextSize = 10
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
			tick.Size = UDim2.new(0, 1, isClip and 0.19 or 0.19, 0)
			tick.BackgroundColor3 = isClip and Color3.new(1, 1, 1) or Color3.fromRGB(255, 200, 60)
			tick.BorderSizePixel = 0
			tick.Parent = segments
		end
	end
end

local function refreshButtons()
	playButton.Text = playing and "|| Pause [X]" or "▶ Play [X]"
	for s, b in pairs(speedButtons) do
		b.BackgroundColor3 = s == speed and Color3.fromRGB(255, 200, 60) or Color3.fromRGB(32, 40, 58)
		b.TextColor3 = s == speed and Color3.new(0, 0, 0) or Color3.fromRGB(235, 240, 255)
	end
	freeButton.Text = followed and "Free camera" or "Click a Quin"
	for name, ghost in pairs(ghosts) do
		ghost.highlight.OutlineTransparency = name == followed and 0 or 1
	end
end

local function refreshInfo()
	playhead.Position = UDim2.new(fraction(cursor), -1, 0, 0)
	timeLabel.Text = live and "LIVE" or ("%.2f s behind"):format(endT - cursor)
	if not followed then
		infoLine.Text = "Click a Quin to follow it and see its state, clips and changes."
		clipLine.Text = ""
		changes.Visible = false
		return
	end
	local values = attributesAt(followed, cursor)
	local pose = poseAt(followed, cursor)
	local parts = { ("<b>%s</b>"):format(escape(followed)) }
	for _, key in ipairs(INFO_ATTRIBUTES) do
		local v = values[key]
		if v ~= nil and v ~= "" then table.insert(parts, ("%s <font color='#FFC83C'>%s</font>"):format(key, escape(v))) end
	end
	if pose then
		if pose.humanoidState then table.insert(parts, "Humanoid " .. pose.humanoidState) end
		if pose.velocity then table.insert(parts, ("speed %.1f"):format(Vector3.new(pose.velocity.X, 0, pose.velocity.Z).Magnitude)) end
	end
	infoLine.Text = table.concat(parts, "  ·  ")
	local clips = {}
	for _, clip in ipairs(pose and pose.clips or {}) do
		table.insert(clips, ("%s <font color='#FFFFFF'>%.2f</font> (x%.2f, %.2f/%.2fs)"):format(escape(clip.name), clip.weight, clip.speed, clip.time, clip.length))
	end
	clipLine.Text = #clips > 0 and ("Clips: " .. table.concat(clips, "  ·  ")) or "Clips: none"
	-- the last changes up to the cursor
	local track = recording.tracks[followed]
	local lines = {}
	for _, event in ipairs(track and track.events or {}) do
		if event.t > cursor then break end
		local when = ("%+.2f"):format(event.t - cursor)
		if event.kind == "clip" then
			table.insert(lines, ("<font color='#AAAAAA'>%s</font> ▶ clip %s"):format(when, escape(event.name)))
		elseif event.name ~= "Mind" and (type(event.value) == "string" or type(event.value) == "boolean") then
			-- (only what switches: numbers drift every few frames and the *At/*Until are clocks)
			table.insert(lines, ("<font color='#AAAAAA'>%s</font> %s → <font color='#FFC83C'>%s</font>"):format(when, escape(event.name), escape(event.value)))
		end
	end
	local from = math.max(1, #lines - 29)
	changes.Text = table.concat(lines, "\n", from, #lines)
	changes.Visible = true
end

----------------------------------------------------------------------------------------
-- Camera
----------------------------------------------------------------------------------------
local function follow(name)
	followed = name
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
	refreshInfo()
end

local function updateCamera()
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
	-- open live, playing, on the Quin being watched
	cursor = math.huge
	syncBounds()
	lastDrawn = nil
	playing, speed, live = true, 1, true
	local watched = Workspace:GetAttribute("SpectatedQuin")
	poseGhosts(cursor)
	follow(ghosts[watched] and watched or nil)
	return true
end

local function setOpen(value)
	if value == open then return end
	if value then
		if not load() then return end
		open = true
		gui.Enabled = true
		hideReal(true)
	else
		open = false
		gui.Enabled = false
		hideReal(false)
		clearGhosts()
		recording, followed, followOffset = nil, nil, nil
		shared.ReplayCameraCFrame = nil
		shared.QuinRecorderHold = nil
	end
end

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

playButton.MouseButton1Click:Connect(function()
	playing = not playing
	refreshButtons()
end)
backButton.MouseButton1Click:Connect(function() step(-1) end)
forwardButton.MouseButton1Click:Connect(function() step(1) end)
for s, b in pairs(speedButtons) do
	b.MouseButton1Click:Connect(function()
		speed = s
		refreshButtons()
	end)
end
latestButton.MouseButton1Click:Connect(function()
	cursor = endT
	playing, speed, live = true, 1, true
	refreshButtons()
end)
freeButton.MouseButton1Click:Connect(function() follow(nil) end)
closeButton.MouseButton1Click:Connect(function() setOpen(false) end)

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
UserInputService.InputChanged:Connect(function(input)
	if scrubbing and input.UserInputType == Enum.UserInputType.MouseMovement then
		scrubTo(input.Position.X)
	elseif open and followOffset and input.UserInputType == Enum.UserInputType.MouseWheel then
		followOffset = followOffset * (input.Position.Z > 0 and 0.88 or 1.14)
	end
end)
UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then scrubbing = false end
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if UserInputService:GetFocusedTextBox() then return end
	if input.KeyCode == Enum.KeyCode.F6 and allowed() then
		setOpen(not open)
		return
	end
	if not open then return end
	if input.KeyCode == Enum.KeyCode.X then
		playing = not playing
		refreshButtons()
	elseif input.KeyCode == Enum.KeyCode.Comma then
		step(-1)
	elseif input.KeyCode == Enum.KeyCode.Period then
		step(1)
	elseif input.UserInputType == Enum.UserInputType.MouseButton1 and not processed and ghostFolder then
		-- click a ghost to follow it
		local at = UserInputService:GetMouseLocation()
		local ray = camera:ViewportPointToRay(at.X, at.Y)
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Include
		params.FilterDescendantsInstances = { ghostFolder }
		local hit = Workspace:Raycast(ray.Origin, ray.Direction * 1000, params)
		local model = hit and hit.Instance:FindFirstAncestorWhichIsA("Model")
		while model and model.Parent ~= ghostFolder do model = model.Parent end
		if model then follow(model.Name) end
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
	end
	if cursor ~= lastDrawn or playing then
		poseGhosts(cursor)
		refreshInfo()
		lastDrawn = cursor
	end
	hideReal(true) -- (re-applied: other scripts reset the transparency modifier, new Quins appear)
	updateCamera()
end)

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
	return { open = open, ghosts = count, followed = followed, cursor = cursor - startT, span = endT - startT,
		info = infoLine.Text, clips = clipLine.Text, changes = changes.Text }
end
control.Parent = script
