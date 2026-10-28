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
-- Studio, Admins: QuinCore.GameFreezeEvent:FireServer("toggle" | "freeze" | "resume" | "step", seconds).
-- "step" lets the frozen game run for that long (one frame: 1/60) and freezes it again; while it
-- steps (Workspace GameStepping) the clients leave the sounds and particles held.
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

-- The speed a held clip had before the freeze (nil: not held)
function GameFreeze.heldSpeed(track)
	return heldTracks[track]
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
				-- (a body moved by physics and then anchored never sends that last move to the
				-- clients - after a one-frame step none of them showed it moving. A written CFrame
				-- is sent, so the frozen picture is where the server has the body; 0.001 studs, as
				-- writing the same CFrame again is not sent)
				root.CFrame += Vector3.new(0, 0.001, 0)
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

	local stepping = false
	function GameFreeze.step(seconds)
		if stepping or not GameClock.frozen() then return end
		stepping = true
		Workspace:SetAttribute("GameStepping", true)
		GameFreeze.resume()
		-- (from the next physics step: the resume can land after this frame's, and a one-frame
		-- step then ran no physics at all - 0 of 32 Quins moved)
		RunService.PreSimulation:Wait()
		local ran = 0
		repeat ran += RunService.Heartbeat:Wait() until ran >= seconds - 1e-3
		GameFreeze.freeze()
		Workspace:SetAttribute("GameStepping", nil)
		stepping = false
	end

	if not QuinCore:FindFirstChild("GameFreezeEvent") then
		local remote = Instance.new("RemoteEvent")
		remote.Name = "GameFreezeEvent"
		remote.Parent = QuinCore
	end
	QuinCore.GameFreezeEvent.OnServerEvent:Connect(function(player, action, seconds)
		if not RunService:IsStudio() or player:GetAttribute("SkylarkRole") ~= "Admin" then return end
		if action == "step" then
			GameFreeze.step(math.clamp(tonumber(seconds) or 1 / 60, 1 / 60, 1))
			return
		end
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
		if Workspace:GetAttribute("GameStepping") then
			-- (a step: the clips run for it, the sounds and particles stay held)
			if frozen then holdClips() else releaseClips() end
			return
		end
		if frozen then freezeHere() else resumeHere() end
	end)
	if GameClock.frozen() then freezeHere() end

	function GameFreeze.request(action, seconds)
		QuinCore:WaitForChild("GameFreezeEvent"):FireServer(action or "toggle", seconds)
	end
end

GameFreeze.frozen = GameClock.frozen

return GameFreeze
