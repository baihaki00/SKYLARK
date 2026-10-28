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

-- The same from outside this script (a test run in Studio has its own shared): Query:Invoke("stats")
local query = Instance.new("BindableFunction")
query.Name = "Query"
query.OnInvoke = function(what)
	return shared.QuinRecorder[what or "stats"]()
end
query.Parent = script
