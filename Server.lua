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
local function isolateSpectatorPlayer(player)
	player.CharacterAdded:Connect(function(char)
		if char:GetAttribute("QuinType") or char:GetAttribute("IsPlayerControlled") or CollectionService:HasTag(char, "Quin") then
			return -- Never isolate active Quin characters
		end
		task.wait(0.1)
		local hrp = char:WaitForChild("HumanoidRootPart", 5)
		local hum = char:FindFirstChildOfClass("Humanoid")
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

		-- 1. Try to find requested or existing living Quin in QuinServer
		if targetQuinName and quinServer then
			targetQuin = quinServer:FindFirstChild(targetQuinName)
		end
		if not targetQuin and quinServer then
			for _, child in ipairs(quinServer:GetChildren()) do
				local hum = child:FindFirstChildOfClass("Humanoid")
				if child:IsA("Model") and child:FindFirstChild("HumanoidRootPart") and (not hum or hum.Health > 0) and not child:GetAttribute("IsPlayerControlled") then
					targetQuin = child
					break
				end
			end
		end

		-- Calculate target spawn CFrame using SpawnLocation in Workspace
		local spawnLocation = Workspace:FindFirstChildOfClass("SpawnLocation") or Workspace:FindFirstChild("SpawnLocation") or Workspace:FindFirstChild("PLAYERSPAWN")
		local targetCFrame
		if spawnLocation and spawnLocation:IsA("BasePart") then
			targetCFrame = spawnLocation.CFrame * CFrame.new(0, spawnLocation.Size.Y / 2 + 3.5, 0)
		else
			targetCFrame = CFrame.new(182.5, 5.5, 468.5)
		end

		-- Clean up any dead quins previously controlled by this player, or reuse living one
		if quinServer then
			for _, child in ipairs(quinServer:GetChildren()) do
				if child:GetAttribute("ControllingPlayer") == player.Name then
					local hum = child:FindFirstChildOfClass("Humanoid")
					if hum and hum.Health <= 0 then
						child:Destroy()
					else
						targetQuin = child
					end
				end
			end
		end

		-- 2. If no living Quin exists in arena, spawn a clean one at SpawnLocation
		if not targetQuin then
			targetQuin = QuinSpawner.spawn("TypeA", targetCFrame.Position, "Team1", "Fire")
		end

		if targetQuin then
			local root = targetQuin:FindFirstChild("HumanoidRootPart")
			if root then
				root.Anchored = false
				targetQuin:PivotTo(targetCFrame)
				root.AssemblyLinearVelocity = Vector3.zero
				root.AssemblyAngularVelocity = Vector3.zero
			end
			targetQuin:SetAttribute("IsPlayerControlled", true)
			targetQuin:SetAttribute("ControllingPlayer", player.Name)

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
			print(string.format("[Server] Player %s possessed %s as Character at %s (NetworkOwner granted)", player.Name, targetQuin.Name, tostring(targetCFrame.Position)))
			return targetQuin
		end
		return nil

	elseif action == "Release" then
		pcall(function()
			player.ReplicationFocus = nil
		end)
		player.Character = nil
		local quinServer = Workspace:FindFirstChild("QuinServer")
		if quinServer then
			for _, child in ipairs(quinServer:GetChildren()) do
				if child:GetAttribute("ControllingPlayer") == player.Name or child.Name == targetQuinName then
					child:SetAttribute("IsPlayerControlled", false)
					child:SetAttribute("ControllingPlayer", nil)
					local root = child:FindFirstChild("HumanoidRootPart")
					if root then
						pcall(function()
							root:SetNetworkOwner(nil)
						end)
					end
					print(string.format("[Server] Player %s released %s (NetworkOwner reverted to Server)", player.Name, child.Name))
				end
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

