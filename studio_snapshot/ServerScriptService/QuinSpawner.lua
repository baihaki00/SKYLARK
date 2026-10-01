--// QuinSpawner.server.lua
-- Spawns Quins from QuinType templates into the arena
-- Applies stats from QuinData, tags them, applies Element appearance & FX, inserts Main script

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local QuinCore = ReplicatedStorage:WaitForChild("QuinCore")
local QuinData = require(QuinCore:WaitForChild("QuinData"))
local CombatConfig = require(QuinCore:WaitForChild("CombatConfig"))
local ElementData = require(QuinCore:WaitForChild("ElementData"))
local QuinInstance = require(QuinCore:WaitForChild("Modules"):WaitForChild("QuinInstance"))
local FXService = require(QuinCore:WaitForChild("Modules"):WaitForChild("FXService"))
local LocomotionModule = require(QuinCore:WaitForChild("Modules"):WaitForChild("LocomotionModule"))

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

-- Physical body (README Rule 1: physics != visuals). The visible skinned mesh must not be the
-- collision body: its auto-generated collision shape differs per mesh and the mesh dips below
-- the floor, so on some templates (QuinFemale) it drags on the ground and pins the Humanoid.
-- The Humanoid floats the root at HipHeight; a dedicated invisible CollisionBody, welded to the
-- root and starting just above the floor, blocks walls and other Quins without floor contact.
local COLLISION_BODY_SIZE = Vector3.new(2.4, 6.8, 1.8)
local COLLISION_BODY_FLOOR_CLEARANCE = 0.5

-- Ankle and toe joints sit this far above the sole (matches the foot IK's ankle height)
local ANKLE_ABOVE_SOLE = 0.46
local TOE_ABOVE_SOLE = 0.14

-- Distance from the root's centre down to the soles in the rig's bind pose, or nil without foot bones
local function soleDepthBelowRoot(model, hrp)
	local depth = nil
	local function consider(boneName, aboveSole)
		local bone = model:FindFirstChild(boneName, true)
		if bone and bone:IsA("Bone") then
			local below = -hrp.CFrame:PointToObjectSpace(bone.WorldPosition).Y + aboveSole
			depth = math.max(depth or below, below)
		end
	end
	consider("mixamorig:LeftFoot", ANKLE_ABOVE_SOLE)
	consider("mixamorig:RightFoot", ANKLE_ABOVE_SOLE)
	consider("mixamorig:LeftToeBase", TOE_ABOVE_SOLE)
	consider("mixamorig:RightToeBase", TOE_ABOVE_SOLE)
	return depth
end

local function buildPhysicsBody(model)
	local hrp = model:FindFirstChild("HumanoidRootPart")
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not hrp or not humanoid then return end

	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") and part ~= hrp then
			part.CanCollide = false -- visual / utility parts stay hittable (CanQuery) but never collide
		end
	end

	-- Utility parts (e.g. "Sounds") belong on the root, not offset to the side of the body
	local sounds = model:FindFirstChild("Sounds")
	if sounds and sounds:IsA("BasePart") then
		local welds = {}
		for _, w in ipairs(sounds:GetChildren()) do
			if w:IsA("WeldConstraint") then w.Enabled = false; table.insert(welds, w) end
		end
		sounds.CFrame = hrp.CFrame
		for _, w in ipairs(welds) do w.Enabled = true end
	end

	-- Stand the rig on its own soles. The clips put the planted foot ~5.4 studs below the root
	-- (measured), while a HipHeight of 3.8 floated the root 5.1 above the floor: every planted
	-- foot sat 0.3 studs inside the ground. HipHeight now comes from the rig's leg length.
	local soleDepth = soleDepthBelowRoot(model, hrp)
	if soleDepth then
		humanoid.HipHeight = soleDepth - hrp.Size.Y / 2
	end

	local existing = model:FindFirstChild("CollisionBody")
	if existing then existing:Destroy() end
	local rootAboveFloor = hrp.Size.Y / 2 + humanoid.HipHeight
	local body = Instance.new("Part")
	body.Name = "CollisionBody"
	body.Size = COLLISION_BODY_SIZE
	body.Transparency = 1
	body.CanCollide = true
	body.CanQuery = false
	body.CanTouch = false
	body.Massless = true
	body.CastShadow = false
	-- Dead contact: no restitution, low friction. With default material properties a knocked
	-- down Quin bounced off the floor two or three times (-50 -> +26 studs/s) before settling,
	-- and bodies dragged on each other when brushing past.
	body.CustomPhysicalProperties = PhysicalProperties.new(0.7, 0.2, 0, 1, 100)
	body.CFrame = hrp.CFrame * CFrame.new(0, -rootAboveFloor + COLLISION_BODY_FLOOR_CLEARANCE + COLLISION_BODY_SIZE.Y / 2, 0)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = hrp
	weld.Part1 = body
	weld.Parent = body
	body.Parent = model
end

-- Spawn a single Quin with either a QuinInstance OR typeName/gender
-- options.costume = true spawns a player costume instead of a fighter: no "Quin" /
-- "AI_Fighter" / team tags, no AI Main script, parented to options.parent. Tournament
-- systems (targeting, orchestrator counts, cleanAll, AI) find fighters by tag or by the
-- QuinServer folder, so a costume is invisible to all of them.
function QuinSpawner.spawn(typeNameOrInstance, position, teamTag, optionalElement, faceTargetPosition, options)
	options = options or {}
	local isCostume = options.costume == true
	if isCostume then
		teamTag = nil
	end
	local quinInstance = nil
	local selectedGender = nil

	if type(typeNameOrInstance) == "table" and typeNameOrInstance.QuinId then
		quinInstance = typeNameOrInstance
		selectedGender = quinInstance.Gender or (math.random() > 0.5 and "Female" or "Male")
	else
		local raw = tostring(typeNameOrInstance or "")
		if raw == "Female" or raw == "QuinFemale" then
			selectedGender = "Female"
		elseif raw == "Male" or raw == "QuinMale" then
			selectedGender = "Male"
		else
			-- Simplified: 50/50 randomized between male and female Quins
			selectedGender = (math.random() > 0.5 and "Female" or "Male")
		end

		local element = optionalElement or ElementData.getRandomElement()
		quinInstance = QuinInstance.create({
			Type = "Standard",
			Gender = selectedGender,
			Element = element,
			OwnerId = "SERVER",
		})
	end

	local QuinTypeFolder = ReplicatedStorage:WaitForChild("QuinType")
	local template

	-- Templates live in ReplicatedStorage.QuinType only. They used to be taken from rigs standing
	-- in the Workspace: live, unanimated, unanchored bodies that the physics engine moved around
	-- in a T-pose where spectators could see them.
	template = QuinTypeFolder:FindFirstChild(selectedGender == "Female" and "QuinFemale" or "QuinMale")

	if not template then
		warn("[QuinSpawner] Template not found for: " .. tostring(selectedGender))
		return nil
	end

	local clone = template:Clone()
	-- The Animator multiplies every clip's bone translation by the model's scale factor. A rig
	-- left at an import scale (QuinFemale was at 0.044) loses all hip travel: get-ups, slides
	-- and landings then play at standing height. Templates must be scale-1 models.
	if math.abs(clone:GetScale() - 1) > 0.001 then
		warn(string.format("[QuinSpawner] Template %s has model scale %.3f; animation translation will be scaled by it. Rebuild it as a scale-1 Model.", template:GetFullName(), clone:GetScale()))
	end
	clone.Name = string.format("Quin_%s_%s", selectedGender, quinInstance.QuinId:sub(-4))

	-- Crucial Rig Sanitation: Ensure RootJoint Part0 and Part1 are strictly internal to the clone
	local hrp = clone:FindFirstChild("HumanoidRootPart")
	local surf = clone:FindFirstChild("Alpha_Surface") or clone:FindFirstChild("Beta_Surface") or clone:FindFirstChildWhichIsA("MeshPart")
	if hrp and surf then
		local rj = hrp:FindFirstChild("RootJoint")
		if rj then
			rj.Part0 = hrp
			rj.Part1 = surf
		end
		clone.PrimaryPart = hrp
	end
	buildPhysicsBody(clone)

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

	-- Apply unified fair baseline stats from QuinData
	applyStats(clone, "Standard")

	-- Attach persistent QuinInstance identity, personality, and records
	QuinInstance.attachToModel(quinInstance, clone)
	clone:SetAttribute("Gender", selectedGender)

	-- Team
	if teamTag then
		clone:SetAttribute("Team", teamTag)
	end

	-- Initial stance & movement state: BY DEFAULT IDLE_DEFAULT
	clone:SetAttribute("CurrentIdleStance", "Default")
	clone:SetAttribute("LastActivityTime", os.clock())
	clone:SetAttribute("IsMoving", false)

	if isCostume then
		-- Player costume: outside the tournament entirely (no tags, no AI)
		clone:SetAttribute("IsCostume", true)
		clone:SetAttribute("IsPlayerControlled", true)
	else
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
	end

	-- Parent last (after all setup)
	clone.Parent = (isCostume and options.parent) or serverFolder

	-- Dynamically apply data-driven Element visual identity
	FXService.applyElementAppearance(clone, quinInstance.Element)

	-- Set network owner to server & silence default Roblox character sounds
	local rootPart = clone:FindFirstChild("HumanoidRootPart")
	if rootPart then
		task.defer(function()
			if not clone:GetAttribute("IsPlayerControlled") then
				pcall(function()
					rootPart:SetNetworkOwner(nil)
				end)
			end
		end)

		-- Suppress default Roblox character sounds so QuinCore.AudioModule has total authority
		local DEFAULT_ROBLOX_SOUNDS = {
			Running = true, Jumping = true, Landing = true, Freefalling = true,
			Climbing = true, Died = true, Swimming = true, GettingUp = true, Splash = true
		}
		for _, desc in ipairs(clone:GetDescendants()) do
			if desc:IsA("Sound") and DEFAULT_ROBLOX_SOUNDS[desc.Name] then
				desc:Destroy()
			end
		end
		rootPart.ChildAdded:Connect(function(child)
			if child:IsA("Sound") and DEFAULT_ROBLOX_SOUNDS[child.Name] then
				task.defer(function()
					pcall(function() child:Destroy() end)
				end)
			end
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
		typeNames = { "Male", "Female" }
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
		typeNames = { "Male", "Female" }
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

		-- Alternate male and female across the formation for balanced 50/50 visual presence
		local teamGender = (i % 2 == 0) and "Female" or "Male"

		-- Each spawned fighter faces the opponent directly
		local quin = QuinSpawner.spawn(teamGender, spawnPos, teamTag, nil, enemyCenter)
		if quin then
			table.insert(spawned, quin)
		end
	end

	print(string.format("[QuinSpawner] Spawned team %s: %d fighters facing opponent (scatter: 10-15 studs)", teamTag or "None", #spawned))
	return spawned
end

-- Clear all spawned AI Quins from the arena
function QuinSpawner.cleanAll()
	local serverFolder = Workspace:FindFirstChild("QuinServer")
	if serverFolder then
		for _, child in ipairs(serverFolder:GetChildren()) do
			LocomotionModule.cleanup(child)
			child:Destroy()
		end
	end

	for _, quin in ipairs(CollectionService:GetTagged("AI_Fighter")) do
		if quin.Parent and quin.Parent.Name == "QuinServer" then
			LocomotionModule.cleanup(quin)
			quin:Destroy()
		end
	end

	local ghostFolder = Workspace:FindFirstChild("QuinGhost")
	if ghostFolder then
		ghostFolder:ClearAllChildren()
	end

	local LSS = _G.LeaderShowdownSystem or shared.LeaderShowdownSystem
	if LSS then
		LSS.reset()
	end

	print("[QuinSpawner] Cleaned all AI fighters from arena (player character untouched)")
end

_G.QuinSpawner = QuinSpawner
shared.QuinSpawner = QuinSpawner

return QuinSpawner
