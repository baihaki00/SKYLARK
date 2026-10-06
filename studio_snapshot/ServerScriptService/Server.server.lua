--// Server.server.lua
-- Central server bootstrapper: loads and initializes core server services
print("[Server] Initializing QuinCore server services...")

local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

local QuinSpawner = require(ServerScriptService:WaitForChild("QuinSpawner"))
local QuinRosterService = require(ServerScriptService:WaitForChild("QuinRosterService"))
local BattleSimulationHarness = require(ServerScriptService:WaitForChild("BattleSimulationHarness"))

-- Isolate spectator dummy characters near SpawnLocation so they do not interfere with simulation
-- Robust SpawnLocation locator (recursive search across ArenaOne and Workspace)
local function findSpawnLocation()
	local arenaOne = Workspace:FindFirstChild("argoniaonion") and Workspace.argoniaonion:FindFirstChild("ArenaOne")
	if arenaOne and arenaOne:FindFirstChild("SpawnLocation") then
		return arenaOne.SpawnLocation
	end
	return Workspace:FindFirstChild("SpawnLocation", true) or Workspace:FindFirstChildOfClass("SpawnLocation")
end

local function setupPlayerCharacter(player)
	local function onCharacter(char)
		local hrp = char:WaitForChild("HumanoidRootPart", 5)
		if hrp then
			hrp.Anchored = false
			pcall(function()
				hrp:SetNetworkOwner(player)
			end)
		end
	end

	player.CharacterAdded:Connect(onCharacter)
	if player.Character then
		task.spawn(onCharacter, player.Character)
	end
end

for _, p in ipairs(Players:GetPlayers()) do
	setupPlayerCharacter(p)
end
Players.PlayerAdded:Connect(setupPlayerCharacter)

-- ============================================================
-- BATTLE SIMULATION SPEED CONTROLLER (Default: 1.0x)
-- ============================================================
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

-- Default to 1.0x speed
Workspace:SetAttribute("GameSpeedMultiplier", 1.0)

local speedEvent = ReplicatedStorage:FindFirstChild("GameSpeedEvent")
if not speedEvent then
	speedEvent = Instance.new("RemoteEvent")
	speedEvent.Name = "GameSpeedEvent"
	speedEvent.Parent = ReplicatedStorage
end

speedEvent.OnServerEvent:Connect(function(player, newSpeed)
	local val = math.clamp(tonumber(newSpeed) or 1.0, 1.0, 10.0)
	Workspace:SetAttribute("GameSpeedMultiplier", val)
	print(string.format("[GameSpeed] Simulation speed set to %.1fx by %s", val, player and player.Name or "Server"))
end)

-- ============================================================
-- PLAYER QUIN POSSESSION CONTROLLER (Play As Quin)
-- ============================================================
local QuinCore = ReplicatedStorage:WaitForChild("QuinCore")
local HitboxModule = require(QuinCore:WaitForChild("Modules"):WaitForChild("HitboxModule"))
local DamageModule = require(QuinCore:WaitForChild("Modules"):WaitForChild("DamageModule"))
local KnockbackModule = require(QuinCore:WaitForChild("Modules"):WaitForChild("KnockbackModule"))

local quinControlFunction = ReplicatedStorage:FindFirstChild("PlayerQuinControlFunction")
if not quinControlFunction then
	quinControlFunction = Instance.new("RemoteFunction")
	quinControlFunction.Name = "PlayerQuinControlFunction"
	quinControlFunction.Parent = ReplicatedStorage
end

quinControlFunction.OnServerInvoke = function(player, action, targetQuinName)
	if action == "Possess" then
		-- Play As Quin is a costume: always the player's own Quin, spawned at the spawn
		-- location outside the tournament. It never takes over or removes a match fighter,
		-- carries no team or AI, and is invisible to targeting and the orchestrator.
		local costumeFolder = Workspace:FindFirstChild("PlayerCostumes")
		if not costumeFolder then
			costumeFolder = Instance.new("Folder")
			costumeFolder.Name = "PlayerCostumes"
			costumeFolder.Parent = Workspace
		end

		-- One costume per player: replace any previous one
		for _, child in ipairs(costumeFolder:GetChildren()) do
			if child:GetAttribute("ControllingPlayer") == player.Name then
				child:Destroy()
			end
		end

		-- Wear the look of the requested / spectated fighter if one was named (read only)
		local costumeGender, costumeElement = nil, nil
		if targetQuinName and targetQuinName ~= "" then
			local quinServer = Workspace:FindFirstChild("QuinServer")
			local source = quinServer and quinServer:FindFirstChild(targetQuinName)
			if source then
				costumeGender = source:GetAttribute("Gender")
				costumeElement = source:GetAttribute("Element")
			end
		end

		local spawnLocation = findSpawnLocation()
		local spawnCFrame = (spawnLocation and spawnLocation:IsA("BasePart"))
			and (spawnLocation.CFrame * CFrame.new(0, spawnLocation.Size.Y / 2 + 3.5, 0))
			or CFrame.new(161, 147.5, -752.5)
		local costume = QuinSpawner.spawn(costumeGender or "Male", spawnCFrame.Position, nil, costumeElement, nil, { costume = true, parent = costumeFolder })
		if not costume then
			return nil
		end
		costume.Name = "Costume_" .. player.Name
		costume:SetAttribute("ControllingPlayer", player.Name)

		local root = costume:FindFirstChild("HumanoidRootPart")
		local hum = costume:FindFirstChildOfClass("Humanoid")
		if hum then
			-- Same humanoid states the fighter AI (Main) disables
			hum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
			hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
			hum:SetStateEnabled(Enum.HumanoidStateType.Physics, false)
		end
		if root then
			root.Anchored = false
			root.AssemblyLinearVelocity = Vector3.zero
			root.AssemblyAngularVelocity = Vector3.zero
		end

		-- Assign as player.Character so the client native character controller simulates movement
		player.Character = costume
		if root then
			pcall(function()
				root:SetNetworkOwner(player)
			end)
			pcall(function()
				player.ReplicationFocus = root
			end)
		end
		print(string.format("[Server] Player %s wearing costume %s", player.Name, costume.Name))
		return costume

	elseif action == "Attack" then
		-- Combat attack from player-controlled Quin
		local char = player.Character
		if char and char:GetAttribute("IsPlayerControlled") == true and char:GetAttribute("ControllingPlayer") == player.Name then
			local root = char:FindFirstChild("HumanoidRootPart")
			local hum = char:FindFirstChildOfClass("Humanoid")
			if root and hum and hum.Health > 0 then
				local step = tonumber(targetQuinName) or 1
				local hitModels = HitboxModule.castInFront(root, Vector3.new(7, 6, 7), Vector3.new(0, 0, -3.5), char)
				local myTeam = char:GetAttribute("Team")
				for _, hitModel in ipairs(hitModels) do
					local targetTeam = hitModel:GetAttribute("Team")
					if not myTeam or not targetTeam or myTeam ~= targetTeam then
						local dmgInfo = DamageModule.calculate(char, hitModel, step, 1.0)
						DamageModule.apply(char, hitModel, dmgInfo)
						local hitRoot = hitModel:FindFirstChild("HumanoidRootPart")
						if hitRoot then
							local knockDir = (hitRoot.Position - root.Position).Unit + Vector3.new(0, 0.35, 0)
							KnockbackModule.apply(hitModel, knockDir, 38, 0.4)
						end
					end
				end
				return true
			end
		end
		return false

	elseif action == "Release" then
		pcall(function()
			player.ReplicationFocus = nil
		end)
		player.Character = nil
		-- The costume belongs to this player only; nothing in the tournament is touched
		local costumeFolder = Workspace:FindFirstChild("PlayerCostumes")
		if costumeFolder then
			for _, child in ipairs(costumeFolder:GetChildren()) do
				if child:GetAttribute("ControllingPlayer") == player.Name then
					child:Destroy()
				end
			end
		end
		pcall(function()
			player:LoadCharacter()
		end)
		print(string.format("[Server] Player %s took off their costume", player.Name))
		return true
	end
	return nil
end

Players.PlayerRemoving:Connect(function(player)
	local costumeFolder = Workspace:FindFirstChild("PlayerCostumes")
	if costumeFolder then
		for _, child in ipairs(costumeFolder:GetChildren()) do
			if child:GetAttribute("ControllingPlayer") == player.Name then
				child:Destroy()
			end
		end
	end
end)

print("[Server] All QuinCore server services initialized successfully. Default speed: 1.0x")

-- ============================================================
-- STREAMING AROUND THE FLY SPECTATOR CAMERA (pass 24)
-- StreamingEnabled streams the world around each player's character. The Fly Spectator camera
-- (StarterPlayerScripts.SmoothCamera) leaves the parked avatar behind, and after a Play As Quin
-- release there is no character at all, so the client sends its camera position (~2/s) and this
-- moves an invisible anchored part there and makes it the player's ReplicationFocus.
-- nil = stream around the character again. While the player wears a Quin costume the possess
-- code above sets the focus to the costume and this leaves it alone.
-- ============================================================
do
	local cameraFocusEvent = ReplicatedStorage:FindFirstChild("CameraFocus")
	if not cameraFocusEvent then
		cameraFocusEvent = Instance.new("RemoteEvent")
		cameraFocusEvent.Name = "CameraFocus"
		cameraFocusEvent.Parent = ReplicatedStorage
	end
	local focusFolder = workspace:FindFirstChild("StreamFocus")
	if not focusFolder then
		focusFolder = Instance.new("Folder")
		focusFolder.Name = "StreamFocus"
		focusFolder.Parent = workspace
	end
	local FOCUS_LIMIT = 50000 -- studs from the origin; anything beyond is junk
	local focusParts = {}

	local function focusPart(player)
		local part = focusParts[player]
		if part and part.Parent then return part end
		part = Instance.new("Part")
		part.Name = "Focus_" .. player.UserId
		part.Size = Vector3.new(1, 1, 1)
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Transparency = 1
		part.Parent = focusFolder
		focusParts[player] = part
		return part
	end

	cameraFocusEvent.OnServerEvent:Connect(function(player, position)
		local character = player.Character
		if character and character:GetAttribute("IsCostume") == true then
			return -- playing a Quin: the costume is the focus
		end
		if typeof(position) ~= "Vector3" then
			if player.ReplicationFocus and player.ReplicationFocus == focusParts[player] then
				player.ReplicationFocus = nil
			end
			return
		end
		if position.X ~= position.X or position.Y ~= position.Y or position.Z ~= position.Z
			or position.Magnitude > FOCUS_LIMIT then
			return
		end
		local part = focusPart(player)
		part.Position = position
		if player.ReplicationFocus ~= part then
			player.ReplicationFocus = part
		end
	end)

	game:GetService("Players").PlayerRemoving:Connect(function(player)
		local part = focusParts[player]
		if part then part:Destroy() end
		focusParts[player] = nil
	end)
end

-- The mind panel (StarterPlayerScripts.QuinMindPanel): a spectator's client says which Quin it is
-- watching, and only that Quin publishes its reasoning (DecisionSystem writes its "Mind").
do
	local mindEvent = ReplicatedStorage:FindFirstChild("MindWatchEvent")
	if not mindEvent then
		mindEvent = Instance.new("RemoteEvent")
		mindEvent.Name = "MindWatchEvent"
		mindEvent.Parent = ReplicatedStorage
	end
	local watching = {} -- player -> Quin model

	local function unwatch(player)
		local model = watching[player]
		watching[player] = nil
		if not (model and model.Parent) then return end
		for _, other in pairs(watching) do
			if other == model then return end -- someone else still watches it
		end
		model:SetAttribute("MindWatched", nil)
		model:SetAttribute("Mind", nil)
	end

	mindEvent.OnServerEvent:Connect(function(player, quinName)
		unwatch(player)
		local folder = Workspace:FindFirstChild("QuinServer")
		local model = type(quinName) == "string" and folder and folder:FindFirstChild(quinName)
		if model then
			watching[player] = model
			model:SetAttribute("MindWatched", true)
		end
	end)
	Players.PlayerRemoving:Connect(unwatch)
end

-- The Quins' social layer (pack leaders, respect customs, arena events). Started here so its loop
-- belongs to a script that lives all session (Main is cloned into each Quin and dies with it).
do
	local SocialSystem = require(game:GetService("ReplicatedStorage"):WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("SocialSystem"))
	SocialSystem.start()
end

-- The loop that moves bodies for lunges, step backs, flinches and knockback skids: likewise owned
-- here, so it does not stop when the Quin whose script first used it is removed.
do
	local ImpulseModule = require(game:GetService("ReplicatedStorage"):WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("ImpulseModule"))
	ImpulseModule.start()
end

-- The timing markers in every strike clip (HitStart, HitEnd, Recover) are read now, not mid-fight
require(game:GetService("ReplicatedStorage"):WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("StrikeMarkers")).preload()

-- Every animation clip is fetched now, so none is first loaded in the middle of a move
require(game:GetService("ReplicatedStorage"):WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("AnimationModule")).preload()
