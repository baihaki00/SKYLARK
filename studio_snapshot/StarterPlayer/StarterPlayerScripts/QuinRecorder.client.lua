--// QuinRecorder.client.lua
-- The flight recorder (debugger step 2, owner 2026-10-28): silently keeps the last few seconds of
-- the whole fight - every Quin - on this machine only, so the replay can show it again slowed
-- down or frame by frame while the real fight carries on untouched.
--
-- Each frame (RecorderHz a second, read after the bodies are drawn), for every Quin: the world
-- pose of every part and bone, the clips playing (name, weight, speed, time), velocity and the
-- humanoid state. Beside the frames, each Quin's attribute changes (the noisy per-frame ones left
-- out, NOISY) and clip starts, with the time they happened - the state transitions the replay
-- marks on its timeline. And what the pause view draws over them as it was at the time: every
-- label on a Quin (each BillboardGui's text and whether it shows, with a copy to rebuild it from)
-- and the server's 3D debug drawings (DebugDraw batches, as they arrived).
--
-- Studio, Admins only. Read through shared.QuinRecorder:
--   .snapshot()  -> { frames = { { t, quins = { [name] = pose } } } oldest first,
--                     tracks = { [name] = { model, partNames, boneNames, events, base,
--                                labelBase, labelEvents, labelTemplates } },
--                     drawings = { { t, batch } } }
--   .live()      -> the same, not copied: the replay reads it as it grows
--   .stats()     -> a one-line summary
-- (or script.Query:Invoke("stats"))
-- Workspace RecorderOff = true stops it; RecorderSeconds / RecorderHz change the length and rate.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

if not RunService:IsStudio() then return end

local player = Players.LocalPlayer
local AnimationConfig = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("AnimationConfig"))

local function seconds() return Workspace:GetAttribute("RecorderSeconds") or 15 end
local function hz() return Workspace:GetAttribute("RecorderHz") or 30 end

-- Attributes that change every frame: in the pose already, or not a transition
local NOISY = {
	LookYaw = true, LookPitch = true, GazePitch = true, ReactionPitch = true, ReactionRoll = true,
	LastActivityTime = true, ObjectiveUntil = true, ObjectiveGoTo = true, PacingVelocity = true,
	LastSeenTargetPosition = true, TackleView = true, SteerIntent = true, Energy = true,
}

-- Animation id -> registry path ("Attacks.Kicks.LowKickRight"), so the clips read by name
local clipNames = {}
local function indexClips(node, path)
	for key, value in pairs(node) do
		if type(value) == "table" then
			local here = path and (path .. "." .. tostring(key)) or tostring(key)
			if type(value.id) == "string" then
				local number = value.id:match("%d+")
				if number and not clipNames[number] then clipNames[number] = here end
			else
				indexClips(value, here)
			end
		end
	end
end
indexClips(AnimationConfig.Registry or {}, nil)

local function clipName(track)
	local animation = track.Animation
	local number = animation and animation.AnimationId:match("%d+")
	if number and clipNames[number] then return clipNames[number] end
	if animation and animation.Name ~= "Animation" then return animation.Name end
	if track.Name ~= "Animation" then return track.Name end
	return number and ("id " .. number) or "?"
end

local function now() return os.clock() end

-- Drop the first n entries of a list in place
local function dropFront(list, n)
	if n <= 0 then return end
	local count = #list
	table.move(list, n + 1, count, 1)
	for i = count - n + 1, count do list[i] = nil end
end

-- The recording
local frames = {}
local tracks = {} -- Quin name -> track (kept after the Quin is gone, until its frames fall off)
local drawings = {} -- { t, batch }: the server's 3D debug drawings (DebugDraw), as they arrived
local recording = false
local lastFrameAt = 0

local function relativeName(instance, model)
	return instance:GetFullName():sub(#model:GetFullName() + 2)
end

-- Labels: every BillboardGui on a Quin (the state tag, PointTag, InterestTag, the debug values).
-- A label's state is whether it shows and the text and visibility of each of its text objects, in
-- order (they often share a name). Kept apart from the events, so the Inspect list is not flooded by text.
local function isText(d)
	return d:IsA("TextLabel") or d:IsA("TextButton") or d:IsA("TextBox")
end

local function labelState(entry)
	local texts, visible = {}, {}
	for i, label in ipairs(entry.texts) do
		texts[i] = label.Text
		visible[i] = label.Visible
	end
	return { enabled = entry.gui.Enabled, texts = texts, visible = visible }
end

local function unwatchLabel(entry)
	for _, connection in ipairs(entry.connections) do connection:Disconnect() end
	table.clear(entry.connections)
end

local function watchLabel(track, gui, initial)
	if track.labels[gui] or not gui:IsDescendantOf(track.model) then return end
	local entry = { gui = gui, path = relativeName(gui, track.model), texts = {}, connections = {} }
	track.labels[gui] = entry
	local function changed()
		table.insert(track.labelEvents, { t = now(), path = entry.path, state = labelState(entry) })
	end
	-- (its text objects and a copy to rebuild it from: again when its contents change)
	local function relist()
		unwatchLabel(entry)
		table.clear(entry.texts)
		for _, d in ipairs(gui:GetDescendants()) do
			if isText(d) then
				table.insert(entry.texts, d)
				table.insert(entry.connections, d:GetPropertyChangedSignal("Text"):Connect(changed))
				table.insert(entry.connections, d:GetPropertyChangedSignal("Visible"):Connect(changed))
			end
		end
		local archivable = gui.Archivable
		gui.Archivable = true
		track.labelTemplates[entry.path] = gui:Clone()
		gui.Archivable = archivable
		table.insert(entry.connections, gui:GetPropertyChangedSignal("Enabled"):Connect(changed))
		table.insert(entry.connections, gui.DescendantAdded:Connect(function(d)
			if isText(d) then task.defer(function() relist() changed() end) end
		end))
		table.insert(entry.connections, gui.AncestryChanged:Connect(function()
			if gui:IsDescendantOf(track.model) then return end
			unwatchLabel(entry)
			track.labels[gui] = nil
			table.insert(track.labelEvents, { t = now(), path = entry.path, state = false })
		end))
	end
	relist()
	if initial then
		track.labelBase[entry.path] = labelState(entry)
	else
		changed()
	end
end

local function dropTrack(track)
	for _, connection in ipairs(track.connections) do connection:Disconnect() end
	for _, entry in pairs(track.labels) do unwatchLabel(entry) end
end

local function addQuin(model)
	if not recording or (tracks[model.Name] and tracks[model.Name].model == model) then return end
	local old = tracks[model.Name]
	if old then dropTrack(old) end
	local humanoid = model:FindFirstChildWhichIsA("Humanoid")
	local track = {
		model = model,
		root = model:FindFirstChild("HumanoidRootPart"),
		humanoid = humanoid,
		animator = humanoid and humanoid:FindFirstChildWhichIsA("Animator"),
		parts = {}, bones = {}, partNames = {}, boneNames = {},
		events = {},
		base = model:GetAttributes(), -- the state before the first change
		connections = {},
		labels = {}, -- BillboardGui -> entry (watchLabel)
		labelBase = {}, -- path -> state before the first label change
		labelEvents = {}, -- { t, path, state (false: gone) }
		labelTemplates = {}, -- path -> a copy of the label to rebuild it from
	}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			table.insert(track.parts, d)
			table.insert(track.partNames, relativeName(d, model))
		elseif d:IsA("Bone") then
			table.insert(track.bones, d)
			table.insert(track.boneNames, relativeName(d, model))
		end
	end
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BillboardGui") then watchLabel(track, d, true) end
	end
	-- Parts and bones still streaming in are added as they arrive (at the end of the lists, so the
	-- frames already kept stay valid). A Quin first seen half-streamed was recorded without its arm
	-- bones, and its ghost in the pause view held its arms in the bind pose.
	table.insert(track.connections, model.DescendantAdded:Connect(function(d)
		if d:IsA("BasePart") then
			table.insert(track.parts, d)
			table.insert(track.partNames, relativeName(d, model))
		elseif d:IsA("Bone") then
			table.insert(track.bones, d)
			table.insert(track.boneNames, relativeName(d, model))
		elseif d:IsA("BillboardGui") then
			task.defer(watchLabel, track, d, false) -- (its text arrives with it)
		end
	end))
	table.insert(track.connections, model.AttributeChanged:Connect(function(name)
		if NOISY[name] then return end
		table.insert(track.events, { t = now(), kind = "attr", name = name, value = model:GetAttribute(name) })
	end))
	if track.animator then
		table.insert(track.connections, track.animator.AnimationPlayed:Connect(function(animationTrack)
			table.insert(track.events, { t = now(), kind = "clip", name = clipName(animationTrack), looped = animationTrack.Looped })
		end))
	end
	tracks[model.Name] = track
end

local function clear()
	for _, track in pairs(tracks) do dropTrack(track) end
	frames, tracks, drawings = {}, {}, {}
end

local function trim()
	-- (while the replay is open the buffer holds up to RecorderHoldSeconds, so what is being
	-- watched slowed down or paused does not fall off the front)
	local cutoff = now() - (shared.QuinRecorderHold and (Workspace:GetAttribute("RecorderHoldSeconds") or 120) or seconds())
	local drop = 0
	while frames[drop + 1] and frames[drop + 1].t < cutoff do drop += 1 end
	dropFront(frames, drop)
	drop = 0
	while drawings[drop + 1] and drawings[drop + 1].t < cutoff do drop += 1 end
	dropFront(drawings, drop)
	for name, track in pairs(tracks) do
		-- changes that fall off the front become the state the recording starts in
		local dropEvents = 0
		while track.events[dropEvents + 1] and track.events[dropEvents + 1].t < cutoff do
			local event = track.events[dropEvents + 1]
			if event.kind == "attr" then track.base[event.name] = event.value end
			dropEvents += 1
		end
		dropFront(track.events, dropEvents)
		local dropLabels = 0
		while track.labelEvents[dropLabels + 1] and track.labelEvents[dropLabels + 1].t < cutoff do
			local event = track.labelEvents[dropLabels + 1]
			track.labelBase[event.path] = event.state or nil
			dropLabels += 1
		end
		dropFront(track.labelEvents, dropLabels)
		if not track.model.Parent and (track.lastSeen or 0) < cutoff then
			dropTrack(track)
			tracks[name] = nil
		end
	end
end

local function poseOf(track)
	local pose = { parts = table.create(#track.parts), bones = table.create(#track.bones), clips = {} }
	for i, part in ipairs(track.parts) do
		pose.parts[i] = part.CFrame
	end
	for i, bone in ipairs(track.bones) do
		pose.bones[i] = bone.TransformedWorldCFrame
	end
	if track.animator then
		for _, animationTrack in ipairs(track.animator:GetPlayingAnimationTracks()) do
			if animationTrack.WeightCurrent > 0.01 then
				table.insert(pose.clips, {
					name = clipName(animationTrack),
					weight = animationTrack.WeightCurrent,
					speed = animationTrack.Speed,
					time = animationTrack.TimePosition,
					length = animationTrack.Length,
				})
			end
		end
		table.sort(pose.clips, function(a, b) return a.weight > b.weight end)
	end
	if track.root then pose.velocity = track.root.AssemblyLinearVelocity end
	if track.humanoid then
		pose.humanoidState = track.humanoid:GetState().Name
		pose.health = track.humanoid.Health
	end
	-- (per-frame values left out of the attribute changes, NOISY: the overhead label and the
	-- last-seen layer of the 3D overlay read them)
	pose.energy = track.model:GetAttribute("Energy")
	pose.lastSeen = track.model:GetAttribute("LastSeenTargetPosition")
	return pose
end

local lastCost = 0
local function record()
	local t = now()
	if t - lastFrameAt < 1 / hz() then return end
	lastFrameAt = t
	local frame = { t = t, quins = {} }
	for name, track in pairs(tracks) do
		if track.model.Parent then
			frame.quins[name] = poseOf(track)
			track.lastSeen = t
		end
	end
	table.insert(frames, frame)
	trim()
	lastCost = os.clock() - t
end

local function allowed()
	return player:GetAttribute("SkylarkRole") == "Admin" and Workspace:GetAttribute("RecorderOff") ~= true
end

local function sync()
	local should = allowed()
	if should == recording then return end
	recording = should
	clear()
	if recording then
		for _, model in ipairs(CollectionService:GetTagged("Quin")) do addQuin(model) end
	end
end
-- (the client's DebugDraw draws these live; kept here so the pause view can draw them again)
ReplicatedStorage.QuinCore:WaitForChild("DebugDrawEvent").OnClientEvent:Connect(function(batch)
	if recording and Workspace:GetAttribute("GameFrozen") ~= true and type(batch) == "table" then
		table.insert(drawings, { t = now(), batch = batch })
	end
end)
CollectionService:GetInstanceAddedSignal("Quin"):Connect(function(model)
	task.defer(addQuin, model) -- (its parts and bones stream in with it)
end)
Workspace:GetAttributeChangedSignal("RecorderOff"):Connect(sync)
player:GetAttributeChangedSignal("SkylarkRole"):Connect(sync)
sync()

-- After the camera, so the pose read is the one drawn this frame (procedural layers included)
RunService:BindToRenderStep("QuinRecorder", Enum.RenderPriority.Camera.Value + 2, function()
	-- (nothing moves while the game is frozen - GameFreeze - so no frames are kept then)
	if recording and Workspace:GetAttribute("GameFrozen") ~= true then record() end
end)

shared.QuinRecorder = {
	snapshot = function()
		local copy = {}
		for name, track in pairs(tracks) do
			copy[name] = {
				model = track.model,
				partNames = track.partNames,
				boneNames = track.boneNames,
				events = table.clone(track.events),
				base = table.clone(track.base),
				labelBase = table.clone(track.labelBase),
				labelEvents = table.clone(track.labelEvents),
				labelTemplates = track.labelTemplates,
			}
		end
		return { frames = table.clone(frames), tracks = copy, drawings = table.clone(drawings) }
	end,
	-- a clip's name in the animation registry (the tracks are all called "Animation")
	clipName = clipName,
	-- the live buffer itself (not a copy: it grows and is trimmed as the fight goes on)
	live = function()
		return { frames = frames, tracks = tracks, drawings = drawings }
	end,
	stats = function()
		if not recording then return "not recording" end
		local quins, poses = 0, 0
		for _, track in pairs(tracks) do
			quins += 1
			poses += #track.bones + #track.parts
		end
		local span = #frames > 1 and (frames[#frames].t - frames[1].t) or 0
		return ("%d Quins (%d poses a frame): %d frames over %.1f s, last frame took %.2f ms, Lua memory %d MB"):format(
			quins, poses, #frames, span, lastCost * 1000, math.floor(collectgarbage("count") / 1024))
	end,
}

-- Bug bookmarks (owner 2026-10-29): N marks "something is wrong right now". The last
-- BookmarkSeconds (6) of the spectated Quin (or the one nearest the middle of the screen) become a
-- short text report: where it stands and on what, a timeline every 0.1 s (state, speed, fall
-- speed, facing, turn rate, humanoid state, clips) and every change with its time. Kept in
-- script.Bookmarks as StringValues "1", "2", ... so Claude reads them straight from the running
-- game: say "bookmark 3", nothing to copy. (Gone when the test stops.)
local UserInputService = game:GetService("UserInputService")
local bookmarks = Instance.new("Folder")
bookmarks.Name = "Bookmarks"
bookmarks.Parent = script

local function short(v)
	if typeof(v) == "Vector3" then return ("(%.0f, %.0f, %.0f)"):format(v.X, v.Y, v.Z) end
	if type(v) == "number" then return ("%.4g"):format(v) end
	if type(v) == "string" and #v > 60 then return v:sub(1, 60) .. "..." end
	return tostring(v)
end

local function bookmarkQuin()
	local model = shared.SpectatedQuin or _G.SpectatedQuin
	if model and tracks[model.Name] then return model end
	local camera = Workspace.CurrentCamera
	local mid = camera.ViewportSize / 2
	local best, bestGap = nil, math.huge
	for _, track in pairs(tracks) do
		if track.root and track.model.Parent then
			local point, onScreen = camera:WorldToViewportPoint(track.root.Position)
			local gap = (Vector2.new(point.X, point.Y) - mid).Magnitude
			if onScreen and gap < bestGap then best, bestGap = track.model, gap end
		end
	end
	return best
end

-- Changes the report leaves out: bookkeeping that moves all the time and says nothing about
-- the bug (a score ticking, a point of interest drifting a stud, the time something happened)
local REPORT_NOISE = { MatchScore = true, InterestPos = true, EscapeFeasibility = true, OccupiedQuadrants = true }
local function reportNoise(event)
	if REPORT_NOISE[event.name] then return true end
	return type(event.value) == "number" and (event.name:sub(-2) == "At" or event.name:sub(-5) == "Until" or event.name:sub(-5) == "Since")
end

-- The report on one Quin between two recorder times (t0, t1); `comment` is the owner's note
-- (a range marked on the pause timeline, QuinReplay). Saved as the next bookmark; returns its number.
local function report(name, t0, t1, comment)
	local track = tracks[name]
	if not track then return nil end
	local model = track.model
	local number = #bookmarks:GetChildren() + 1
	local lines = {}
	local function add(line) table.insert(lines, line) end
	add(("BOOKMARK %d: %s, %.1f s at %s (t = seconds before the end of the range)"):format(number, name, t1 - t0, os.date("%H:%M:%S")))
	if comment and comment ~= "" then add("OWNER'S NOTE: " .. comment) end
	-- where it was at the end of the range, and its target
	local rootIndex = table.find(track.partNames, "HumanoidRootPart")
	local lastPose, lastFrame
	for _, frame in ipairs(frames) do
		if frame.t > t1 then break end
		if frame.quins[name] then lastPose, lastFrame = frame.quins[name], frame end
	end
	local rootCF = lastPose and rootIndex and lastPose.parts[rootIndex]
	if rootCF then
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		-- (the list is built first: inserting into FilterDescendantsInstances changes a copy)
		params.FilterDescendantsInstances = { model, Workspace:FindFirstChild("QuinReplayGhosts") }
		local floor = Workspace:Raycast(rootCF.Position, Vector3.new(0, -8, 0), params)
		add("at " .. short(rootCF.Position) .. " on " .. (floor and floor.Instance:GetFullName() or "nothing (in the air)"))
	end
	-- the attributes as they stood when the range opens
	local state = table.clone(track.base)
	local events = track.events
	local index = 1
	while events[index] and events[index].t < t0 do
		if events[index].kind == "attr" then state[events[index].name] = events[index].value end
		index += 1
	end
	local startTarget = state.CurrentTarget
	local targetLine = #lines + 1 -- (filled in once the end of the range is known)
	add("")
	add(("AT START: State %s | Task %s | Target %s | Obstacle %s | Pace %s"):format(short(state.CurrentState), short(state.Task),
		short(state.CurrentTarget), short(state.ObstacleAwareness), short(state.PaceGear)))
	add("TIMELINE (0.1 s): t | state | speed | vy | facing | turn deg/s | humanoid | clips (weight time/length xspeed)")
	local lastT, lastYaw = -math.huge, nil
	for _, frame in ipairs(frames) do
		if frame.t > t1 then break end
		while events[index] and events[index].t <= frame.t do
			if events[index].kind == "attr" then state[events[index].name] = events[index].value end
			index += 1
		end
		local pose = frame.quins[name]
		if frame.t >= t0 and pose and frame.t - lastT >= 0.095 then
			local yaw
			local cf = rootIndex and pose.parts[rootIndex]
			if cf then
				local look = cf.LookVector
				yaw = math.deg(math.atan2(-look.X, -look.Z))
			end
			local turn = (yaw and lastYaw) and ((yaw - lastYaw + 180) % 360 - 180) / (frame.t - lastT) or 0
			local v = pose.velocity or Vector3.zero
			local clips = {}
			for i = 1, math.min(#pose.clips, 3) do
				local c = pose.clips[i]
				table.insert(clips, ("%s %.2f %.2f/%.2f x%.2f"):format(c.name, c.weight, c.time, c.length, c.speed))
			end
			add(("%6.2f | %s | %4.1f | %5.1f | %4.0f | %5.0f | %s | %s"):format(frame.t - t1, short(state.CurrentState),
				Vector3.new(v.X, 0, v.Z).Magnitude, v.Y, yaw or 0, turn, pose.humanoidState or "?", table.concat(clips, ", ")))
			lastT, lastYaw = frame.t, yaw
		end
	end
	-- its target at the end of the range (and the one it started with, if that changed)
	while events[index] and events[index].t <= t1 do
		if events[index].kind == "attr" then state[events[index].name] = events[index].value end
		index += 1
	end
	local targetName = state.CurrentTarget
	local target = type(targetName) == "string" and tracks[targetName]
	local targetIndex = target and table.find(target.partNames, "HumanoidRootPart")
	local targetPose = target and lastFrame and lastFrame.quins[targetName]
	local targetText = "target at the end: " .. short(targetName)
	if targetPose and targetIndex and targetPose.parts[targetIndex] then
		targetText ..= " at " .. short(targetPose.parts[targetIndex].Position)
	end
	if startTarget ~= targetName then
		targetText ..= " (it started on " .. short(startTarget) .. ")"
	end
	lines[targetLine] = targetText
	add("CHANGES (timestamps, MatchScore, InterestPos, EscapeFeasibility, OccupiedQuadrants left out):")
	for _, event in ipairs(events) do
		if event.t >= t0 and event.t <= t1 and not (event.kind == "attr" and reportNoise(event)) then
			add(("%6.2f %s"):format(event.t - t1, event.kind == "clip" and ("clip " .. event.name) or (event.name .. " = " .. short(event.value))))
		end
	end
	local value = Instance.new("StringValue")
	value.Name = tostring(number)
	value.Value = table.concat(lines, "\n")
	value:SetAttribute("Quin", name)
	value:SetAttribute("Comment", comment)
	value.Parent = bookmarks
	print(("[QuinRecorder] bookmark %d saved: %s, %d lines (tell Claude \"bookmark %d\")"):format(number, name, #lines, number))
	return number
end

-- N: the last BookmarkSeconds of the spectated Quin (or the one nearest the middle of the screen)
local function bookmark()
	local model = bookmarkQuin()
	if not (model and tracks[model.Name]) then return nil end
	-- (paused, the recorder stops: the range ends at its last frame, not at the clock)
	local t1 = frames[#frames] and math.min(now(), frames[#frames].t) or now()
	local number = report(model.Name, t1 - (Workspace:GetAttribute("BookmarkSeconds") or 6), t1)
	pcall(function()
		game:GetService("StarterGui"):SetCore("SendNotification", { Title = "Bookmark " .. number, Text = model.Name .. ": the last 6 s are saved", Duration = 3 })
	end)
	return number
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed or input.KeyCode ~= Enum.KeyCode.N or UserInputService:GetFocusedTextBox() then return end
	if recording then bookmark() end
end)
shared.QuinRecorder.bookmark = bookmark
shared.QuinRecorder.report = report -- (QuinReplay: a range marked on the pause timeline)

-- The same from outside this script (a test run in Studio has its own shared): Query:Invoke("stats")
local query = Instance.new("BindableFunction")
query.Name = "Query"
query.OnInvoke = function(what)
	return shared.QuinRecorder[what or "stats"]()
end
query.Parent = script
