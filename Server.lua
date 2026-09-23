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

print("[Server] All QuinCore server services initialized successfully. Default speed: 1.0x")
