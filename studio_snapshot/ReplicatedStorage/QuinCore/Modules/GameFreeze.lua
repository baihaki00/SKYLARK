--// GameFreeze
-- God pause (owner 2026-10-28): freezes the real game - every Quin where it is, mid-step,
-- mid-strike, mid-air - and on resume each carries on from that moment as if nothing happened.
--
-- Server: the game clock stops (GameClock: Workspace GameFrozen / GameFrozenAt / GameFrozenTotal),
-- so the Quins' thinking, timers and per-frame loops stop; each Quin's root is anchored where it
-- is, its velocity kept for the resume; every clip playing on it is held (speed 0). Clients: the
-- sounds pause and particles stop in the air; the bodies keep their drawn pose (AIGhostHandler
-- edits the pose with no time passing).
--
-- Studio, Admins: QuinCore.GameFreezeEvent:FireServer("toggle" | "freeze" | "resume").
-- (Not frozen: the match and mode timers that are not on GameClock, and loose physics parts.)

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local QuinCore = ReplicatedStorage:WaitForChild("QuinCore")
local GameClock = require(QuinCore:WaitForChild("Modules"):WaitForChild("GameClock"))

local GameFreeze = {}

local function animatorOf(model)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	return humanoid and humanoid:FindFirstChildOfClass("Animator")
end

-- Held clips: track -> its speed before the freeze (shared by both sides)
local heldTracks = {}
local playedConnections = {}

-- (a clip already at speed 0 - held by the server before this machine saw the freeze, or
-- stopped on purpose - is left alone, so a resume never sets a clip to 0)
local function hold(track)
	if heldTracks[track] == nil and track.Speed ~= 0 then
		heldTracks[track] = track.Speed
		track:AdjustSpeed(0)
	end
end

local function holdClips()
	for _, model in ipairs(CollectionService:GetTagged("Quin")) do
		local animator = animatorOf(model)
		if animator then
			for _, track in ipairs(animator:GetPlayingAnimationTracks()) do hold(track) end
			-- (a clip started while frozen is held too)
			table.insert(playedConnections, animator.AnimationPlayed:Connect(hold))
		end
	end
end

local function releaseClips()
	for _, connection in ipairs(playedConnections) do connection:Disconnect() end
	playedConnections = {}
	for track, speed in pairs(heldTracks) do
		if track.IsPlaying then track:AdjustSpeed(speed) end
	end
	heldTracks = {}
end

if RunService:IsServer() then
	local bodies = {} -- root -> { anchored, linear, angular }

	function GameFreeze.freeze()
		if GameClock.frozen() then return end
		Workspace:SetAttribute("GameFrozenAt", Workspace:GetServerTimeNow())
		for _, model in ipairs(CollectionService:GetTagged("Quin")) do
			local root = model:FindFirstChild("HumanoidRootPart")
			if root and not bodies[root] then
				bodies[root] = {
					anchored = root.Anchored,
					linear = root.AssemblyLinearVelocity,
					angular = root.AssemblyAngularVelocity,
				}
				root.Anchored = true
			end
		end
		holdClips()
		Workspace:SetAttribute("GameFrozen", true)
	end

	function GameFreeze.resume()
		if not GameClock.frozen() then return end
		local at = Workspace:GetAttribute("GameFrozenAt") or Workspace:GetServerTimeNow()
		Workspace:SetAttribute("GameFrozenTotal", (Workspace:GetAttribute("GameFrozenTotal") or 0) + (Workspace:GetServerTimeNow() - at))
		for root, saved in pairs(bodies) do
			if root.Parent then
				root.Anchored = saved.anchored
				if not saved.anchored then
					root.AssemblyLinearVelocity = saved.linear
					root.AssemblyAngularVelocity = saved.angular
				end
			end
		end
		bodies = {}
		releaseClips()
		Workspace:SetAttribute("GameFrozenAt", nil)
		Workspace:SetAttribute("GameFrozen", false)
	end

	if not QuinCore:FindFirstChild("GameFreezeEvent") then
		local remote = Instance.new("RemoteEvent")
		remote.Name = "GameFreezeEvent"
		remote.Parent = QuinCore
	end
	QuinCore.GameFreezeEvent.OnServerEvent:Connect(function(player, action)
		if not RunService:IsStudio() or player:GetAttribute("SkylarkRole") ~= "Admin" then return end
		if action == "freeze" or (action == "toggle" and not GameClock.frozen()) then
			GameFreeze.freeze()
		elseif action == "resume" or action == "toggle" then
			GameFreeze.resume()
		end
	end)
else
	-- Client: sounds and particles (they run on this machine); the clips the server holds come
	-- here held, the ones this machine plays are held here
	local pausedSounds = {}
	local frozenEmitters = {}

	local function freezeHere()
		for _, root in ipairs({ Workspace, game:GetService("SoundService") }) do
			for _, d in ipairs(root:GetDescendants()) do
				if d:IsA("Sound") and d.IsPlaying then
					d:Pause()
					pausedSounds[d] = true
				elseif d:IsA("ParticleEmitter") and d.TimeScale > 0 then
					frozenEmitters[d] = d.TimeScale
					d.TimeScale = 0
				end
			end
		end
		holdClips()
	end

	local function resumeHere()
		for sound in pairs(pausedSounds) do
			if sound.Parent then sound:Resume() end
		end
		pausedSounds = {}
		for emitter, scale in pairs(frozenEmitters) do
			if emitter.Parent then emitter.TimeScale = scale end
		end
		frozenEmitters = {}
		releaseClips()
	end

	GameClock.changed:Connect(function(frozen)
		if frozen then freezeHere() else resumeHere() end
	end)
	if GameClock.frozen() then freezeHere() end

	function GameFreeze.request(action)
		QuinCore:WaitForChild("GameFreezeEvent"):FireServer(action or "toggle")
	end
end

GameFreeze.frozen = GameClock.frozen

return GameFreeze
