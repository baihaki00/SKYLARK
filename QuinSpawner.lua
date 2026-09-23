--// QuinSpawner.server.lua
-- Spawns Quins from QuinType templates into the arena
-- Applies stats from QuinData, tags them, applies Element appearance & FX, inserts Main script

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local QuinCore = ReplicatedStorage:WaitForChild("QuinCore")
local QuinData = require(QuinCore:WaitForChild("QuinData"))
local CombatConfig = require(QuinCore:WaitForChild("CombatConfig"))
local ElementData = require(QuinCore:WaitForChild("ElementData"))
local QuinInstance = require(QuinCore:WaitForChild("Modules"):WaitForChild("QuinInstance"))
local FXService = require(QuinCore:WaitForChild("Modules"):WaitForChild("FXService"))

local QuinSpawner = {}

-- Get spawn positions from QuinSpawn parts in Workspace (recursive search)
function QuinSpawner.getSpawnPositions()
	local positions = {}
	for _, desc in ipairs(Workspace:GetDescendants()) do
		if desc.Name == "QuinSpawn" and desc:IsA("BasePart") then
			table.insert(positions, desc.Position + Vector3.new(0, 5, 0))
		end
	end

	-- Fallback if no QuinSpawn parts are found
	if #positions == 0 then
		warn("[QuinSpawner] No 'QuinSpawn' parts found in Workspace. Using default center map spawn.")
		positions = {
			Vector3.new(0, 50, 0),
			Vector3.new(15, 50, 0)
		}
	elseif #positions == 1 then
		table.insert(positions, positions[1] + Vector3.new(15, 0, 0))
	end

	return positions
end

-- Get expanded/scattered spawn positions for team battles
local function getExpandedSpawnPositions()
	local positions = QuinSpawner.getSpawnPositions()
	local expanded = {}
	for _, pos in ipairs(positions) do
		table.insert(expanded, pos)
	end
	for _, pos in ipairs(positions) do
		local offset = Vector3.new(math.random(-5, 5), 0, math.random(-5, 5))
		table.insert(expanded, pos + offset)
	end
	return expanded
end

-- Apply QuinData stats as attributes on the model
local function applyStats(model, typeName)
	local stats = QuinData.getStats(typeName)
	for statName, value in pairs(stats) do
		if type(value) == "number" or type(value) == "string" or type(value) == "boolean" then
			model:SetAttribute(statName, value)
		end
	end
	model:SetAttribute("QuinType", typeName)
	model:SetAttribute("SuperMeter", 0)
	model:SetAttribute("Energy", CombatConfig.MaxEnergy or 100)
	model:SetAttribute("MaxEnergy", CombatConfig.MaxEnergy or 100)

	-- Apply health to humanoid
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.MaxHealth = stats.Health or 1000
		humanoid.Health = stats.Health or 1000
		humanoid.WalkSpeed = stats.Speed or 60
		humanoid.JumpPower = stats.JumpPower or 50
	end
end

-- Spawn a single Quin with either a QuinInstance OR typeName
function QuinSpawner.spawn(typeNameOrInstance, position, teamTag, optionalElement, faceTargetPosition)
	local quinInstance = nil
	local typeName = "TypeA"

	if type(typeNameOrInstance) == "table" and typeNameOrInstance.QuinId then
		quinInstance = typeNameOrInstance
		typeName = quinInstance.Type or "TypeA"
	else
		typeName = tostring(typeNameOrInstance or "TypeA")
		local element = optionalElement or ElementData.getRandomElement()
		quinInstance = QuinInstance.create({
			Type = typeName,
			Element = element,
			OwnerId = "SERVER",
		})
	end

	local QuinTypeFolder = ReplicatedStorage:WaitForChild("QuinType")
	local template = QuinTypeFolder:FindFirstChild("Quin" .. typeName)
	if not template then
		warn("[QuinSpawner] Template not found: Quin" .. typeName)
		return nil
	end

	local clone = template:Clone()
	clone.Name = string.format("Quin_%s_%s", quinInstance.Type, quinInstance.QuinId:sub(-4))

	-- Ensure it goes into a server folder
	local serverFolder = Workspace:FindFirstChild("QuinServer")
	if not serverFolder then
		serverFolder = Instance.new("Folder")
		serverFolder.Name = "QuinServer"
		serverFolder.Parent = Workspace
	end

	-- Position and orient: face opponent directly if target provided
	if faceTargetPosition then
		clone:PivotTo(CFrame.lookAt(position, Vector3.new(faceTargetPosition.X, position.Y, faceTargetPosition.Z)))
	else
		clone:PivotTo(CFrame.new(position))
	end

	-- Apply chassis stats from QuinData
	applyStats(clone, typeName)

	-- Attach persistent QuinInstance identity, personality, and records
	QuinInstance.attachToModel(quinInstance, clone)

	-- Team
	if teamTag then
		clone:SetAttribute("Team", teamTag)
	end

	-- Tags
	CollectionService:AddTag(clone, "Quin")
	CollectionService:AddTag(clone, "AI_Fighter")
	if teamTag then
		CollectionService:AddTag(clone, teamTag)
	end

	-- Insert Main script (clone from QuinCore)
	local mainScript = ReplicatedStorage:WaitForChild("QuinCore"):FindFirstChild("Main")
	if mainScript then
		local mainClone = mainScript:Clone()
		mainClone.Parent = clone
		mainClone.Disabled = false
	end

	-- Parent last (after all setup)
	clone.Parent = serverFolder

	-- Dynamically apply data-driven Element visual identity
	FXService.applyElementAppearance(clone, quinInstance.Element)

	-- Set network owner to server
	local rootPart = clone:FindFirstChild("HumanoidRootPart")
	if rootPart then
		task.defer(function()
			pcall(function()
				rootPart:SetNetworkOwner(nil)
			end)
		end)
	end

	-- Play spawn elemental FX
	FXService.play(clone, "Spawn")

	print(string.format("[QuinSpawner] Spawned %s (%s | %s | %s) at %s", 
		clone.Name, quinInstance.QuinId, quinInstance.Type, quinInstance.Element, tostring(position)))
	return clone
end

QuinSpawner.spawnWithInstance = QuinSpawner.spawn

-- Spawn a batch of Quins with 10-15 studs scatter, facing the opponent team directly
function QuinSpawner.spawnTeam(typeNames, teamTag, count, spawnIndex, customBasePosOrEnemyCenter, optionalEnemyCenter)
	-- Support multiple calling conventions:
	-- (1) spawnTeam(typeNamesTable, teamTag, count, spawnIndex, customBasePos, enemyCenter)
	-- (2) spawnTeam(typeNamesTable, teamTag, count, spawnIndex, enemyCenter)
	-- (3) spawnTeam(teamTag, count, spawnIndex, enemyCenter)
	local customBasePos = nil
	local enemyCenterPosition = nil

	if typeof(typeNames) == "string" and typeof(teamTag) == "number" then
		local actualTeamTag = typeNames
		local actualCount = teamTag
		local actualSpawnIndex = (typeof(count) == "number") and count or 1
		typeNames = { "TypeA", "TypeB", "TypeC", "TypeD" }
		teamTag = actualTeamTag
		count = actualCount
		spawnIndex = actualSpawnIndex
		if typeof(customBasePosOrEnemyCenter) == "Vector3" then
			customBasePos = customBasePosOrEnemyCenter
			enemyCenterPosition = optionalEnemyCenter
		end
	else
		if typeof(customBasePosOrEnemyCenter) == "Vector3" then
			customBasePos = customBasePosOrEnemyCenter
			enemyCenterPosition = optionalEnemyCenter
		end
	end

	if typeof(typeNames) == "string" then
		typeNames = { typeNames }
	elseif typeof(typeNames) ~= "table" or #typeNames == 0 then
		typeNames = { "TypeA", "TypeB", "TypeC", "TypeD" }
	end
	count = (typeof(count) == "number") and count or 1
	spawnIndex = spawnIndex or 1
	local positions = QuinSpawner.getSpawnPositions()

	local basePos = Vector3.new(0, 50, 0)
	local otherSpawnPos = Vector3.new(0, 50, 0)
	if customBasePos then
		basePos = customBasePos
		otherSpawnPos = enemyCenterPosition or Vector3.new(0, 2.0, -38)
	elseif #positions >= 2 then
		local idx = ((spawnIndex - 1) % #positions) + 1
		local otherIdx = (idx == 1) and 2 or 1
		basePos = positions[idx]
		otherSpawnPos = positions[otherIdx]
	elseif #positions == 1 then
		basePos = positions[1]
		otherSpawnPos = basePos + Vector3.new(100, 0, 0)
	end

	local enemyCenter = enemyCenterPosition or otherSpawnPos
	local flatDiff = Vector3.new(enemyCenter.X - basePos.X, 0, enemyCenter.Z - basePos.Z)
	local forwardDir = (flatDiff.Magnitude > 0.01) and flatDiff.Unit or Vector3.new(0, 0, 1)
	local rightDir = Vector3.new(-forwardDir.Z, 0, forwardDir.X)

	-- Staggered combat line: 10 to 15 studs spacing between teammates
	local spawned = {}
	local spacing = 13.0 -- 13 studs spacing (strictly within 10-15 studs requirement)
	local maxCols = math.clamp(math.ceil(math.sqrt(count * 2)), 3, 6)

	for i = 1, count do
		local typeName = typeNames[((i - 1) % #typeNames) + 1]

		local col = ((i - 1) % maxCols) - ((maxCols - 1) / 2)
		local row = math.floor((i - 1) / maxCols)

		-- Stagger alternate rows for natural scatter
		local stagger = (row % 2 == 1) and (spacing * 0.5) or 0
		local jitterX = (math.random() - 0.5) * 2.5
		local jitterZ = (math.random() - 0.5) * 2.5

		local offset = (rightDir * (col * spacing + stagger + jitterX)) - (forwardDir * (row * spacing + jitterZ))
		local spawnPos = basePos + offset

		-- Each spawned fighter faces the opponent directly
		local quin = QuinSpawner.spawn(typeName, spawnPos, teamTag, nil, enemyCenter)
		if quin then
			table.insert(spawned, quin)
		end
	end

	print(string.format("[QuinSpawner] Spawned team %s: %d fighters facing opponent (scatter: 10-15 studs)", teamTag or "None", #spawned))
	return spawned
end

-- Clear all spawned Quins
function QuinSpawner.cleanAll()
	local serverFolder = Workspace:FindFirstChild("QuinServer")
	if serverFolder then
		serverFolder:ClearAllChildren()
	end

	for _, quin in ipairs(CollectionService:GetTagged("Quin")) do
		quin:Destroy()
	end

	local ghostFolder = Workspace:FindFirstChild("QuinGhost")
	if ghostFolder then
		ghostFolder:ClearAllChildren()
	end

	local LSS = _G.LeaderShowdownSystem or shared.LeaderShowdownSystem
	if LSS then
		LSS.reset()
	end

	print("[QuinSpawner] Cleaned all Quins from arena")
end

_G.QuinSpawner = QuinSpawner
shared.QuinSpawner = QuinSpawner

return QuinSpawner
