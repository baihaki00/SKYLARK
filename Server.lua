--// Server.server.lua
-- Central server bootstrapper: loads and initializes core server services
print("[Server] Initializing QuinCore server services...")

local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local QuinSpawner = require(ServerScriptService:WaitForChild("QuinSpawner"))
local QuinRosterService = require(ServerScriptService:WaitForChild("QuinRosterService"))
local BattleSimulationHarness = require(ServerScriptService:WaitForChild("BattleSimulationHarness"))

-- Isolate spectator players to high altitude (Y = 600) so they do not interfere with simulation
local function isolateSpectatorPlayer(player)
	player.CharacterAdded:Connect(function(char)
		task.wait(0.1)
		local hrp = char:WaitForChild("HumanoidRootPart", 5)
		local hum = char:FindFirstChildOfClass("Humanoid")
		if hrp then
			hrp.Anchored = true
			hrp.CFrame = CFrame.new(0, 600, 0)
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
			local hrp = player.Character:WaitForChild("HumanoidRootPart", 5)
			if hrp then
				hrp.Anchored = true
				hrp.CFrame = CFrame.new(0, 600, 0)
			end
			for _, part in ipairs(player.Character:GetDescendants()) do
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

		-- 1. Try to find requested or existing Quin in QuinServer
		if targetQuinName and quinServer then
			targetQuin = quinServer:FindFirstChild(targetQuinName)
		end
		if not targetQuin and quinServer then
			for _, child in ipairs(quinServer:GetChildren()) do
				if child:IsA("Model") and child:FindFirstChild("HumanoidRootPart") and not child:GetAttribute("IsPlayerControlled") then
					targetQuin = child
					break
				end
			end
		end

		-- 2. If no Quin exists in arena, spawn a clean one at map center
		if not targetQuin then
			local spawnPos = Vector3.new(0, 7.5, 0)
			targetQuin = QuinSpawner.spawn("TypeA", spawnPos, "Team1", "Fire")
		end

		if targetQuin then
			local root = targetQuin:FindFirstChild("HumanoidRootPart")
			if root then
				pcall(function()
					root:SetNetworkOwner(player)
				end)
			end
			targetQuin:SetAttribute("IsPlayerControlled", true)
			targetQuin:SetAttribute("ControllingPlayer", player.Name)
			print(string.format("[Server] Player %s possessed %s (NetworkOwner granted)", player.Name, targetQuin.Name))
			return targetQuin
		end
		return nil

	elseif action == "Release" then
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
		return true
	end
	return nil
end

print("[Server] All QuinCore server services initialized successfully. Default speed: 1.0x")

