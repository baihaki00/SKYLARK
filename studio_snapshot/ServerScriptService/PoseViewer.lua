--// PoseViewer.lua
-- Test mode: compare an animation clip as authored with what the game draws.
--
-- On the MovementTestArena's clear floor it puts
--   * the male and the female rig side by side, playing the clip in place with no game layers
--     (no foot solver, look-at, tilt: the clip exactly as authored on each rig);
--   * one live Quin walking up and down on its normal locomotion, with every game layer on;
-- and a label over each: clip name, asset id, time and frame (30 fps); on the live Quin also
-- the clip's blend weight and play rate. Find a frame that looks wrong on the live Quin and
-- compare it with the same frame on the raw rigs: wrong only on the live one means a game
-- layer, wrong on both means the clip (or how it lands on that rig).
--
-- Start: Quin Manager menu (M) > TEST MODES, or GameCommand "pose_viewer" with "Male" /
-- "Female", or (Studio tools) Workspace attribute DevCommand = "pose_viewer:Male".
-- Controls (Workspace attributes, Properties panel):
--   PoseViewerSpeed   playback speed of the raw rigs (default 0.25)
--   PoseViewerPaused  freeze the raw rigs
--   PoseViewerFrame   hold the raw rigs on this frame (-1 = play)
-- It ends when another mode starts (CurrentMode changes or its live Quin is cleared away).
-- The live Quin walks on DevGoal, which Main honours in Studio and while this mode runs.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local QuinSpawner = require(ServerScriptService:WaitForChild("QuinSpawner"))
local AnimationConfig = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("AnimationConfig"))

local PoseViewer = {}

local MODE_NAME = "PoseViewer"
local FOLDER_NAME = "PoseViewer"
local FRAME_RATE = 30 -- frames per second the clips were exported at

-- MovementTestArena clear floor (x -660..-460, z 440..560)
local FLOOR_Y = 2
local LANE_START = Vector3.new(-610, FLOOR_Y + 3, 500)
local LANE_END = Vector3.new(-510, FLOOR_Y + 3, 500)
local RIG_SPOTS = { Vector3.new(-562, 0, 488), Vector3.new(-550, 0, 488) } -- male, female
local VIEWER_SPOT = Vector3.new(-556, FLOOR_Y + 6, 468)

local RIG_COLORS = {
	QuinMale = Color3.fromRGB(120, 200, 255),
	QuinFemale = Color3.fromRGB(255, 160, 210),
}
local LIVE_COLOR = Color3.fromRGB(255, 230, 120)

local session = 0

-- "Movement.WalkConfident" -> asset id digits
local function clipId(path)
	-- (the entries are reached through AnimationConfig.get: indexing the module by category found nothing)
	local entry = AnimationConfig.get(path)
	return entry and entry.id and tostring(entry.id):match("%d+") or nil
end

local function makeLabel(adornee, color)
	local gui = Instance.new("BillboardGui")
	gui.Name = "PoseViewerLabel"
	gui.Size = UDim2.fromOffset(340, 66)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 6.2, 0)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.Adornee = adornee
	gui.Parent = adornee
	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundColor3 = Color3.new(0, 0, 0)
	text.BackgroundTransparency = 0.25
	text.TextColor3 = color
	text.Font = Enum.Font.Code
	text.TextSize = 15
	text.TextWrapped = true
	text.Parent = gui
	return text
end

-- A template rig, anchored, standing on the floor, playing the clip held at time 0
local function spawnRawRig(templateName, spot, folder, id)
	local template = ReplicatedStorage:WaitForChild("QuinType"):FindFirstChild(templateName)
	if not template then return nil end
	local model = template:Clone()
	model.Name = "Viewer_" .. templateName
	model.Parent = folder
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart")
	local standHeight = humanoid.HipHeight + root.Size.Y / 2
	-- facing -X: its left side is toward the viewer spot
	model:PivotTo(CFrame.new(spot + Vector3.new(0, FLOOR_Y + standHeight, 0)) * CFrame.Angles(0, math.rad(90), 0))
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Anchored = true
		end
	end
	local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator", humanoid)
	local animation = Instance.new("Animation")
	animation.AnimationId = "rbxassetid://" .. id
	local track = animator:LoadAnimation(animation)
	track.Looped = true
	track:Play(0)
	track:AdjustSpeed(0)
	return { name = templateName, track = track, label = makeLabel(root, RIG_COLORS[templateName]) }
end

local function frameOf(time)
	return math.floor(time * FRAME_RATE + 0.5)
end

function PoseViewer.stop()
	session += 1
	local folder = Workspace:FindFirstChild(FOLDER_NAME)
	if folder then
		folder:Destroy()
	end
	if Workspace:GetAttribute("CurrentMode") == MODE_NAME then
		Workspace:SetAttribute("CurrentMode", nil)
	end
end

-- options: { gender = "Male" | "Female", clip = "Movement.WalkConfident", speed = 7.5, player = Player }
function PoseViewer.start(options)
	options = options or {}
	PoseViewer.stop()
	session += 1
	local mySession = session

	local gender = options.gender == "Female" and "Female" or "Male"
	local clipPath = options.clip or "Movement.WalkConfident"
	local id = clipId(clipPath)
	if not id then
		warn("[PoseViewer] unknown clip " .. tostring(clipPath))
		return
	end
	local walkSpeed = options.speed or 7.5

	QuinSpawner.cleanAll()
	Workspace:SetAttribute("CurrentMode", MODE_NAME)
	Workspace:SetAttribute("MatchStarted", true)
	Workspace:SetAttribute("PoseViewerSpeed", Workspace:GetAttribute("PoseViewerSpeed") or 0.25)
	Workspace:SetAttribute("PoseViewerPaused", false)
	Workspace:SetAttribute("PoseViewerFrame", -1)

	local folder = Instance.new("Folder")
	folder.Name = FOLDER_NAME
	folder.Parent = Workspace

	local rigs = {}
	for index, templateName in ipairs({ "QuinMale", "QuinFemale" }) do
		local rig = spawnRawRig(templateName, RIG_SPOTS[index], folder, id)
		if rig then
			table.insert(rigs, rig)
		end
	end

	local live = QuinSpawner.spawn(gender, LANE_START, "TeamAlpha")
	if live then
		live.Name = "PoseViewer_Live"
		live:SetAttribute("EnableProjectileJump", false)
	end
	local liveLabel = live and makeLabel(live:FindFirstChild("HumanoidRootPart"), LIVE_COLOR)

	local viewer = options.player or Players:GetPlayers()[1]
	if viewer and viewer.Character then
		viewer.Character:PivotTo(CFrame.lookAt(VIEWER_SPOT, VIEWER_SPOT + Vector3.new(0, 0, 1)))
	end

	task.spawn(function()
		local rawTime = 0
		local goal = LANE_END
		-- (it also ends when its live Quin is gone: the other modes clear the arena but do not all
		-- set CurrentMode, and the raw rigs stayed standing in the next match)
		while session == mySession and folder.Parent and Workspace:GetAttribute("CurrentMode") == MODE_NAME
			and (live == nil or live.Parent ~= nil) do
			local dt = RunService.Heartbeat:Wait()

			-- Raw rigs: the clip at the chosen time, frame or speed
			local hold = Workspace:GetAttribute("PoseViewerFrame") or -1
			for _, rig in ipairs(rigs) do
				local length = rig.track.Length
				if length > 0 then
					if hold >= 0 then
						rawTime = (hold / FRAME_RATE) % length
					elseif not Workspace:GetAttribute("PoseViewerPaused") then
						rawTime = (rawTime + dt * (Workspace:GetAttribute("PoseViewerSpeed") or 0.25)) % length
					end
					rig.track.TimePosition = rawTime
					rig.label.Text = string.format("%s (raw clip, no game layers)\n%s  id %s\nt = %.3f s   frame %d / %d",
						rig.name, clipPath, id, rawTime, frameOf(rawTime), frameOf(length))
				end
			end

			-- Live Quin: up and down the lane on its own locomotion
			if live and live.Parent then
				local root = live:FindFirstChild("HumanoidRootPart")
				if root and (Vector3.new(root.Position.X, 0, root.Position.Z) - Vector3.new(goal.X, 0, goal.Z)).Magnitude < 6 then
					goal = goal == LANE_END and LANE_START or LANE_END
				end
				live:SetAttribute("DevGoalSpeed", walkSpeed)
				live:SetAttribute("DevGoal", goal)

				local track
				local animator = live:FindFirstChildOfClass("Humanoid") and live:FindFirstChildOfClass("Humanoid"):FindFirstChildOfClass("Animator")
				for _, playing in ipairs(animator and animator:GetPlayingAnimationTracks() or {}) do
					if playing.Animation and playing.Animation.AnimationId:find(id, 1, true) then
						track = playing
					end
				end
				if track then
					liveLabel.Text = string.format("LIVE %s %s (game, all layers)\n%s  id %s  weight %.2f\nt = %.3f s   frame %d / %d   rate %.2f",
						live.Name, gender, clipPath, id, track.WeightCurrent, track.TimePosition, frameOf(track.TimePosition), frameOf(track.Length), track.Speed)
				else
					liveLabel.Text = string.format("LIVE %s %s - %s not playing", live.Name, gender, clipPath)
				end
			end
		end
		if session == mySession then
			PoseViewer.stop()
		end
	end)
end

return PoseViewer
