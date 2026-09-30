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

local function isolateSpectatorPlayer(player)
	player.CharacterAdded:Connect(function(char)
		if char:GetAttribute("QuinType") or char:GetAttribute("IsPlayerControlled") or CollectionService:HasTag(char, "Quin") then
			return -- Never isolate active Quin characters
		end
		task.wait(0.1)
		local hrp = char:WaitForChild("HumanoidRootPart", 5)
		local hum = char:FindFirstChildOfClass("Humanoid")
		local spawnObj = findSpawnLocation()
		local isoCF = spawnObj and (spawnObj.CFrame + Vector3.new(0, 15, 0)) or CFrame.new(161, 159, -752.5)
		if hrp then
			hrp.Anchored = true
			hrp.CFrame = isoCF
		end
		for _, part in ipairs(char:GetDescendants()) do
			if part:IsA("BasePart") then
				part.CanCollide = false
				part.Transparency = 1
				part.CastShadow = false
			end
		end
		if hum then
			hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		end
	end)
	if player.Character then
		task.spawn(function()
			local char = player.Character
			if char:GetAttribute("QuinType") or char:GetAttribute("IsPlayerControlled") or CollectionService:HasTag(char, "Quin") then
				return
			end
			local hrp = char:WaitForChild("HumanoidRootPart", 5)
			local spawnObj = Workspace:FindFirstChildOfClass("SpawnLocation") or Workspace:FindFirstChild("SpawnLocation")
			local isoCF = spawnObj and (spawnObj.CFrame + Vector3.new(0, 15, 0)) or CFrame.new(182.5, 20, 468.5)
			if hrp then
				hrp.Anchored = true
				hrp.CFrame = isoCF
			end
			for _, part in ipairs(char:GetDescendants()) do
				if part:IsA("BasePart") then
					part.CanCollide = false
					part.Transparency = 1
					part.CastShadow = false
				end
			end
		end)
	end
end

for _, p in ipairs(Players:GetPlayers()) do
	isolateSpectatorPlayer(p)
end
Players.PlayerAdded:Connect(isolateSpectatorPlayer)

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
		local quinServer = Workspace:FindFirstChild("QuinServer")
		local targetQuin = nil
		local wasNewlySpawned = false

		-- Clean up any dead quins previously controlled by this player
		if quinServer then
			for _, child in ipairs(quinServer:GetChildren()) do
				if child:GetAttribute("ControllingPlayer") == player.Name then
					local hum = child:FindFirstChildOfClass("Humanoid")
					if hum and hum.Health <= 0 then
						child:Destroy()
					end
				end
			end
		end

		-- 1. Try to find explicitly requested Quin by name (e.g. from Spectator HUD)
		if targetQuinName and targetQuinName ~= "" then
			if quinServer then
				targetQuin = quinServer:FindFirstChild(targetQuinName)
			end
			if not targetQuin then
				for _, q in ipairs(CollectionService:GetTagged("Quin")) do
					if q.Name == targetQuinName then
						targetQuin = q
						break
					end
				end
			end
			if targetQuin then
				local hum = targetQuin:FindFirstChildOfClass("Humanoid")
				if hum and hum.Health <= 0 then
					targetQuin = nil
				end
			end
		end

		-- 2. If no specific target requested, pick any living Quin in the arena
		if not targetQuin and quinServer then
			for _, child in ipairs(quinServer:GetChildren()) do
				local hum = child:FindFirstChildOfClass("Humanoid")
				if child:IsA("Model") and child:FindFirstChild("HumanoidRootPart") and hum and hum.Health > 0 and not child:GetAttribute("IsPlayerControlled") then
					targetQuin = child
					break
				end
			end
		end

		-- Fallback to any tagged living Quin in Workspace
		if not targetQuin then
			for _, q in ipairs(CollectionService:GetTagged("Quin")) do
				local hum = q:FindFirstChildOfClass("Humanoid")
				if hum and hum.Health > 0 and not q:GetAttribute("IsPlayerControlled") then
					targetQuin = q
					break
				end
			end
		end

		-- 3. ONLY if NO living Quins exist anywhere in arena/workspace, spawn a fallback test Quin
		if not targetQuin then
			local spawnLocation = findSpawnLocation()
			local targetCFrame
			if spawnLocation and spawnLocation:IsA("BasePart") then
				targetCFrame = spawnLocation.CFrame * CFrame.new(0, spawnLocation.Size.Y / 2 + 3.5, 0)
			else
				targetCFrame = CFrame.new(161, 147.5, -752.5)
			end
			targetQuin = QuinSpawner.spawn("TypeA", targetCFrame.Position, "TeamAlpha", "Fire")
			wasNewlySpawned = true
		end

		if targetQuin then
			local root = targetQuin:FindFirstChild("HumanoidRootPart")
			if root then
				root.Anchored = false
				-- CRITICAL: NEVER teleport an existing arena fighter! Keep its combat position in the arena!
				if wasNewlySpawned then
					local spawnLocation = findSpawnLocation()
					local targetCFrame = spawnLocation and (spawnLocation.CFrame * CFrame.new(0, spawnLocation.Size.Y / 2 + 3.5, 0)) or CFrame.new(161, 147.5, -752.5)
					targetQuin:PivotTo(targetCFrame)
					root.AssemblyLinearVelocity = Vector3.zero
					root.AssemblyAngularVelocity = Vector3.zero
				end
			end
			targetQuin:SetAttribute("IsPlayerControlled", true)
			targetQuin:SetAttribute("ControllingPlayer", player.Name)

			-- Stop server animations so client player controller has exclusive authoritative animation control
			local hum = targetQuin:FindFirstChildOfClass("Humanoid")
			local animator = hum and hum:FindFirstChildOfClass("Animator")
			if animator then
				for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
					track:Stop(0)
				end
			end

			-- Assign as player.Character so client native character controller simulates movement
			player.Character = targetQuin
			if root then
				pcall(function()
					root:SetNetworkOwner(player)
				end)
			end
			pcall(function()
				player.ReplicationFocus = root
			end)
			print(string.format("[Server] Player %s possessed %s (Existing in arena: %s)", player.Name, targetQuin.Name, tostring(not wasNewlySpawned)))
			return targetQuin
		end
		return nil

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
		local quinServer = Workspace:FindFirstChild("QuinServer")
		local releasedModel = nil
		local function releaseModel(child)
			if child:GetAttribute("ControllingPlayer") == player.Name or child.Name == targetQuinName then
				child:SetAttribute("IsPlayerControlled", false)
				child:SetAttribute("ControllingPlayer", nil)
				local root = child:FindFirstChild("HumanoidRootPart")
				if root then
					pcall(function()
						root:SetNetworkOwner(nil)
					end)
				end
				releasedModel = child
				print(string.format("[Server] Player %s released %s (AI resumed, NetworkOwner reverted to Server)", player.Name, child.Name))
			end
		end
		if quinServer then
			for _, child in ipairs(quinServer:GetChildren()) do
				releaseModel(child)
			end
		end
		for _, q in ipairs(CollectionService:GetTagged("Quin")) do
			if q ~= releasedModel then
				releaseModel(q)
			end
		end
		pcall(function()
			player:LoadCharacter()
		end)
		return true
	end
	return nil
end

print("[Server] All QuinCore server services initialized successfully. Default speed: 1.0x")
