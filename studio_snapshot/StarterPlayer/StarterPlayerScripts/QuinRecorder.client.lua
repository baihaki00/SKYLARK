--// QuinRecorder.client.lua
-- The flight recorder (debugger step 2, owner 2026-10-28): silently keeps the last few seconds of
-- the Quin being spectated (Workspace SpectatedQuin), on this machine only, so the replay can show
-- it again slowed down or frame by frame while the real fight carries on untouched.
--
-- Each frame (30 a second, read after the body is drawn): the world pose of every part and bone,
-- the clips playing (name, weight, speed, time), velocity and the humanoid state. Beside the
-- frames, every attribute change of the Quin and every clip start, with the time it happened -
-- the state transitions the replay marks on its timeline.
--
-- Studio, Admins only. Read through shared.QuinRecorder:
--   .snapshot()  -> the recording (frames oldest first, events, base = attributes at its start,
--                   part/bone names, quin name)
--   .stats()     -> a one-line summary
-- (or script.Query:Invoke("snapshot" | "stats"))
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

-- The recording
local quin, parts, bones, animator, humanoid, root
local frames, events = {}, {}
local base = {} -- attribute -> value at the start of the recording
local connections = {}
local lastFrameAt = 0

local function now() return os.clock() end

-- Drop the first n entries of a list in place
local function dropFront(list, n)
	if n <= 0 then return end
	local count = #list
	table.move(list, n + 1, count, 1)
	for i = count - n + 1, count do list[i] = nil end
end

local function trim()
	local cutoff = now() - seconds()
	local drop = 0
	while frames[drop + 1] and frames[drop + 1].t < cutoff do drop += 1 end
	dropFront(frames, drop)
	-- attribute changes that fall off the front become the state the recording starts in
	local dropEvents = 0
	while events[dropEvents + 1] and events[dropEvents + 1].t < cutoff do
		local event = events[dropEvents + 1]
		if event.kind == "attr" then base[event.name] = event.value end
		dropEvents += 1
	end
	dropFront(events, dropEvents)
end

local function stop()
	for _, connection in ipairs(connections) do connection:Disconnect() end
	connections = {}
	quin, parts, bones, animator, humanoid, root = nil, nil, nil, nil, nil, nil
	frames, events, base = {}, {}, {}
end

local function watch(model)
	stop()
	if not model then return end
	quin = model
	root = model:FindFirstChild("HumanoidRootPart")
	humanoid = model:FindFirstChildWhichIsA("Humanoid")
	animator = humanoid and humanoid:FindFirstChildWhichIsA("Animator")
	parts, bones = {}, {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			table.insert(parts, d)
		elseif d:IsA("Bone") then
			table.insert(bones, d)
		end
	end
	table.insert(connections, model.AttributeChanged:Connect(function(name)
		table.insert(events, { t = now(), kind = "attr", name = name, value = model:GetAttribute(name) })
	end))
	if animator then
		table.insert(connections, animator.AnimationPlayed:Connect(function(track)
			table.insert(events, { t = now(), kind = "clip", name = clipName(track), looped = track.Looped })
		end))
	end
	base = model:GetAttributes() -- the state before the first change
end

local function record()
	if not quin or not quin.Parent then return end
	local t = now()
	if t - lastFrameAt < 1 / hz() then return end
	lastFrameAt = t
	local frame = { t = t, parts = table.create(#parts), bones = table.create(#bones), clips = {} }
	for i, part in ipairs(parts) do
		frame.parts[i] = part.CFrame
	end
	for i, bone in ipairs(bones) do
		frame.bones[i] = bone.TransformedWorldCFrame
	end
	if animator then
		for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
			if track.WeightCurrent > 0.01 then
				table.insert(frame.clips, {
					name = clipName(track),
					weight = track.WeightCurrent,
					speed = track.Speed,
					time = track.TimePosition,
					length = track.Length,
				})
			end
		end
		table.sort(frame.clips, function(a, b) return a.weight > b.weight end)
	end
	if root then frame.velocity = root.AssemblyLinearVelocity end
	if humanoid then frame.humanoidState = humanoid:GetState().Name end
	table.insert(frames, frame)
	trim()
end

local function findQuin(name)
	if type(name) ~= "string" or name == "" then return nil end
	for _, model in ipairs(CollectionService:GetTagged("Quin")) do
		if model.Name == name then return model end
	end
	return nil
end

local function allowed()
	return player:GetAttribute("SkylarkRole") == "Admin" and Workspace:GetAttribute("RecorderOff") ~= true
end

local function sync()
	local target = allowed() and findQuin(Workspace:GetAttribute("SpectatedQuin")) or nil
	if target ~= quin then watch(target) end
end
Workspace:GetAttributeChangedSignal("SpectatedQuin"):Connect(sync)
Workspace:GetAttributeChangedSignal("RecorderOff"):Connect(sync)
player:GetAttributeChangedSignal("SkylarkRole"):Connect(sync)
sync()

-- After the camera, so the pose read is the one drawn this frame (procedural layers included)
RunService:BindToRenderStep("QuinRecorder", Enum.RenderPriority.Camera.Value + 2, function()
	if quin and not quin.Parent then
		sync() -- the Quin was removed; drop it (or pick up a new one with the same name)
	end
	record()
end)

shared.QuinRecorder = {
	snapshot = function()
		if not quin then return nil end
		local partNames, boneNames = {}, {}
		for i, part in ipairs(parts) do partNames[i] = part:GetFullName():sub(#quin:GetFullName() + 2) end
		for i, bone in ipairs(bones) do boneNames[i] = bone:GetFullName():sub(#quin:GetFullName() + 2) end
		return {
			quin = quin,
			quinName = quin.Name,
			partNames = partNames,
			boneNames = boneNames,
			frames = table.clone(frames),
			events = table.clone(events),
			base = table.clone(base),
		}
	end,
	stats = function()
		if not quin then return "not recording (spectate a Quin)" end
		local span = #frames > 1 and (frames[#frames].t - frames[1].t) or 0
		return ("%s: %d frames over %.1f s, %d events, %d parts, %d bones"):format(
			quin.Name, #frames, span, #events, #parts, #bones)
	end,
}

-- The same from outside this script (a test run in Studio has its own shared): Query:Invoke("stats")
local query = Instance.new("BindableFunction")
query.Name = "Query"
query.OnInvoke = function(what)
	return shared.QuinRecorder[what or "stats"]()
end
query.Parent = script
