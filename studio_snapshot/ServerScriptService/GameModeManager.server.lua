--// GameModeManager.server.lua
-- Controls game modes: FreeForAll, TeamBattle, Deathmatch, Tournament
-- Players are SPECTATORS watching Quins fight

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local CombatConfig = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("CombatConfig"))

local ServerScriptService = game:GetService("ServerScriptService")
local QuinSpawner = require(ServerScriptService:WaitForChild("QuinSpawner"))
local PoseViewer = require(ServerScriptService:WaitForChild("PoseViewer"))

local GameModeManager = {}
_G.GameModeManager = GameModeManager
shared.GameModeManager = GameModeManager

-- State
local currentMode = "None"
local roundActive = false
local scores = {} -- team/player -> kills
local roundNumber = 0
local totalRounds = CombatConfig.TournamentRounds or 3

-- Available Quin types
local ALL_TYPES = {"Male", "Female"}

-- Listen for eliminations
local elimEvent = ReplicatedStorage:FindFirstChild("QuinEliminated")
if not elimEvent then
	elimEvent = Instance.new("BindableEvent")
	elimEvent.Name = "QuinEliminated"
	elimEvent.Parent = ReplicatedStorage
end

-- Status event for UI
local statusEvent = ReplicatedStorage:FindFirstChild("GameStatus")
if not statusEvent then
	statusEvent = Instance.new("RemoteEvent")
	statusEvent.Name = "GameStatus"
	statusEvent.Parent = ReplicatedStorage
end

local Players = game:GetService("Players")

local function broadcastStatus(message)
	print("[GameMode] " .. message)
	statusEvent:FireAllClients(message)
end

local function showCountdown()
	local screenPart = Workspace:FindFirstChild("argoniaonion") and Workspace.argoniaonion:FindFirstChild("Screen")
	local gui = screenPart and screenPart:FindFirstChild("CountdownGui")
	
	if screenPart and not gui then
		gui = Instance.new("SurfaceGui")
		gui.Name = "CountdownGui"
		gui.Adornee = screenPart
		gui.Face = Enum.NormalId.Front
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 50
		gui.Parent = screenPart
		
		local label = Instance.new("TextLabel")
		label.Name = "Label"
		label.Size = UDim2.new(1, 0, 1, 0)
		label.BackgroundTransparency = 1
		label.TextColor3 = Color3.fromRGB(255, 50, 50)
		label.TextStrokeColor3 = Color3.new(0, 0, 0)
		label.TextStrokeTransparency = 0
		label.TextScaled = true
		label.Font = Enum.Font.GothamBlack
		label.Parent = gui
	end
	
	local function setText(text)
		if gui and gui:FindFirstChild("Label") then
			gui.Label.Text = text
		end
		broadcastStatus(text)
	end

	setText("3") task.wait(1)
	setText("2") task.wait(1)
	setText("1") task.wait(1)
	setText("FIGHT!") task.wait(1)
	setText("")
end

local function countAlive(teamTag)
	local count = 0
	for _, quin in ipairs(CollectionService:GetTagged("Quin")) do
		if quin.Parent then
			local hum = quin:FindFirstChildOfClass("Humanoid")
			if hum and hum.Health > 0 then
				if teamTag then
					if quin:GetAttribute("Team") == teamTag then
						count = count + 1
					end
				else
					count = count + 1
				end
			end
		end
	end
	return count
end

local function getAliveQuins(teamTag)
	local list = {}
	for _, quin in ipairs(CollectionService:GetTagged("Quin")) do
		if quin.Parent then
			local hum = quin:FindFirstChildOfClass("Humanoid")
			if hum and hum.Health > 0 then
				if teamTag then
					if quin:GetAttribute("Team") == teamTag then
						table.insert(list, quin)
					end
				else
					table.insert(list, quin)
				end
			end
		end
	end
	return list
end

-- ======================================
-- ======================================
-- 1 VS 1 SPARRING MATCH
-- ======================================
function GameModeManager.start1v1SparringMatch()
	currentMode = "1v1Sparring"
	roundActive = true
	scores = {TeamAlpha = 0, TeamBeta = 0}
	
	QuinSpawner.cleanAll()
	Workspace:SetAttribute("MatchStarted", false)
	
	-- Spawn in the center sparring ring, 30 studs apart facing each other
	local p1 = Vector3.new(-15, 7.5, 0)
	local p2 = Vector3.new(15, 7.5, 0)
	
	local quinA = QuinSpawner.spawn("TypeA", p1, "TeamAlpha")
	local quinB = QuinSpawner.spawn("TypeB", p2, "TeamBeta")
	
	task.wait(0.1) -- Let them spawn
	
	-- Face each other directly
	if quinA and quinA.PrimaryPart and quinB and quinB.PrimaryPart then
		local posA = quinA.PrimaryPart.Position
		local posB = quinB.PrimaryPart.Position
		quinA.PrimaryPart.CFrame = CFrame.lookAt(posA, Vector3.new(posB.X, posA.Y, posB.Z))
		quinB.PrimaryPart.CFrame = CFrame.lookAt(posB, Vector3.new(posA.X, posB.Y, posA.Z))
	end
	
	-- Set initial Idle state and lock targets
	if quinA and quinB then
		quinA:SetAttribute("CurrentState", "Idle")
		quinB:SetAttribute("CurrentState", "Idle")
		quinA:SetAttribute("TargetQuin", quinB.Name)
		quinB:SetAttribute("TargetQuin", quinA.Name)
		quinA:SetAttribute("CurrentTarget", quinB.Name)
		quinB:SetAttribute("CurrentTarget", quinA.Name)
	end
	
	broadcastStatus("1 vs 1 Sparring Match: Get Ready!")
	showCountdown()
	Workspace:SetAttribute("MatchStarted", true)
	
	-- Monitor for round end
	task.spawn(function()
		while roundActive do
			task.wait(1)
			local alphaAlive = countAlive("TeamAlpha")
			local betaAlive = countAlive("TeamBeta")
			
			if alphaAlive == 0 and betaAlive == 0 then
				roundActive = false
				broadcastStatus("DRAW! Both fighters eliminated!")
			elseif alphaAlive == 0 then
				roundActive = false
				broadcastStatus("TEAM BETA WINS!")
			elseif betaAlive == 0 then
				roundActive = false
				broadcastStatus("TEAM ALPHA WINS!")
			end
		end
	end)
end

GameModeManager.startTestMode = GameModeManager.start1v1SparringMatch
function GameModeManager.startFreeForAll(quinCount)
	quinCount = quinCount or 8
	currentMode = "FreeForAll"
	roundActive = true
	scores = {}
	
	QuinSpawner.cleanAll()
	Workspace:SetAttribute("MatchStarted", false)
	
	-- Spawn random types
	local types = {}
	for i = 1, quinCount do
		table.insert(types, ALL_TYPES[math.random(1, #ALL_TYPES)])
	end
	
	QuinSpawner.spawnTeam(types, nil, quinCount)
	showCountdown()
	Workspace:SetAttribute("MatchStarted", true)
	
	-- Monitor for winner
	task.spawn(function()
		while roundActive do
			task.wait(1)
			local alive = countAlive()
			if alive <= 1 then
				roundActive = false
				-- Find winner
				for _, quin in ipairs(CollectionService:GetTagged("Quin")) do
					local hum = quin:FindFirstChildOfClass("Humanoid")
					if hum and hum.Health > 0 then
						broadcastStatus("WINNER: " .. quin.Name .. " (" .. (quin:GetAttribute("QuinType") or "?") .. ")!")
						break
					end
				end
				if alive == 0 then
					broadcastStatus("DRAW! All fighters eliminated!")
				end
			end
		end
	end)
end

-- ======================================
-- TEAM BATTLE
-- ======================================
function GameModeManager.startTeamBattle(teamSize)
	teamSize = teamSize or CombatConfig.DefaultTeamSize or 4
	currentMode = "TeamBattle"
	roundActive = true
	scores = {TeamAlpha = 0, TeamBeta = 0}
	
	QuinSpawner.cleanAll()
	Workspace:SetAttribute("MatchStarted", false)
	
	-- Team Alpha: TypeA and TypeC (speed-focused)
	local alphaTypes = {}
	for i = 1, teamSize do
		table.insert(alphaTypes, i % 2 == 0 and "TypeA" or "TypeC")
	end
	
	-- Team Beta: TypeB and TypeD (power-focused)
	local betaTypes = {}
	for i = 1, teamSize do
		table.insert(betaTypes, i % 2 == 0 and "TypeB" or "TypeD")
	end
	
	local positions = QuinSpawner.getSpawnPositions()
	local pos1 = positions[1] or Vector3.new(158, 2.05, -167)
	local pos2 = positions[2] or Vector3.new(-137, 2.05, 205)

	QuinSpawner.spawnTeam(alphaTypes, "TeamAlpha", teamSize, 1, pos2)
	task.wait(0.2)
	QuinSpawner.spawnTeam(betaTypes, "TeamBeta", teamSize, 2, pos1)
	
	showCountdown()
	Workspace:SetAttribute("MatchStarted", true)
	
	-- Monitor
	task.spawn(function()
		while roundActive do
			task.wait(1)
			local alphaAlive = countAlive("TeamAlpha")
			local betaAlive = countAlive("TeamBeta")
			
			-- (Leader showdowns and respect customs now emerge from the Quins: SocialSystem)

			if alphaAlive == 0 and betaAlive == 0 then
				roundActive = false
				broadcastStatus("DRAW! Both teams eliminated!")
			elseif alphaAlive == 0 then
				roundActive = false
				broadcastStatus("TEAM BETA WINS! (" .. betaAlive .. " survivors)")
			elseif betaAlive == 0 then
				roundActive = false
				broadcastStatus("TEAM ALPHA WINS! (" .. alphaAlive .. " survivors)")
			end
		end
	end)
end

-- ======================================
-- TOURNAMENT (Bracket 1v1)
-- ======================================
function GameModeManager.startTournament()
	currentMode = "Tournament"
	roundNumber = 0
	
	QuinSpawner.cleanAll()
	broadcastStatus("TOURNAMENT MODE - 1v1 Bracket")
	
	-- Create bracket: 8 fighters
	local bracket = {}
	for i = 1, 8 do
		table.insert(bracket, ALL_TYPES[((i - 1) % #ALL_TYPES) + 1])
	end
	
	-- Shuffle bracket
	for i = #bracket, 2, -1 do
		local j = math.random(1, i)
		bracket[i], bracket[j] = bracket[j], bracket[i]
	end
	
	task.spawn(function()
		local survivors = bracket
		local roundNum = 1
		
		while #survivors > 1 do
			broadcastStatus("ROUND " .. roundNum .. " - " .. #survivors .. " fighters remaining")
			task.wait(3)
			
			local nextRound = {}
			
			for i = 1, #survivors, 2 do
				if i + 1 > #survivors then
					-- Bye round
					table.insert(nextRound, survivors[i])
					broadcastStatus(survivors[i] .. " gets a BYE!")
				else
					local typeA = survivors[i]
					local typeB = survivors[i + 1]
					
					broadcastStatus("MATCH: " .. typeA .. " vs " .. typeB)
					QuinSpawner.cleanAll()
					task.wait(1)
					
					Workspace:SetAttribute("MatchStarted", false)
					
					-- Spawn the two fighters
					local positions = QuinSpawner.getSpawnPositions()
					
					QuinSpawner.spawn(typeA, positions[1], "FighterA")
					QuinSpawner.spawn(typeB, positions[2], "FighterB")
					
					showCountdown()
					Workspace:SetAttribute("MatchStarted", true)
					
					-- Wait for winner
					local winner = nil
					while not winner do
						task.wait(0.5)
						local aAlive = countAlive("FighterA")
						local bAlive = countAlive("FighterB")
						
						if aAlive == 0 and bAlive == 0 then
							-- Draw: pick random
							winner = math.random() > 0.5 and typeA or typeB
							broadcastStatus("DRAW! " .. winner .. " advances by coin flip!")
						elseif aAlive == 0 then
							winner = typeB
							broadcastStatus(typeB .. " WINS!")
						elseif bAlive == 0 then
							winner = typeA
							broadcastStatus(typeA .. " WINS!")
						end
					end
					
					table.insert(nextRound, winner)
					task.wait(3) -- pause between matches
				end
			end
			
			survivors = nextRound
			roundNum = roundNum + 1
		end
		
		if #survivors == 1 then
			broadcastStatus("TOURNAMENT CHAMPION: " .. survivors[1] .. "! 🏆")
		end
		
		QuinSpawner.cleanAll()
		currentMode = "None"
	end)
end

-- ======================================
-- TEST MODE (Animation Diagnostic)
-- ======================================
function GameModeManager.startTestMode()
	currentMode = "TestMode"
	roundActive = true
	QuinSpawner.cleanAll()
	
	local positions = QuinSpawner.getSpawnPositions()
	
	local quinA = QuinSpawner.spawn("TypeA", positions[1], "TeamAlpha")
	local quinB = QuinSpawner.spawn("TypeB", positions[2], "TeamBeta")
	
	task.wait(0.1) -- Let them spawn
	
	-- Face each other
	if quinA and quinA.PrimaryPart and quinB and quinB.PrimaryPart then
		quinA.PrimaryPart.CFrame = CFrame.lookAt(quinA.PrimaryPart.Position, Vector3.new(quinB.PrimaryPart.Position.X, quinA.PrimaryPart.Position.Y, quinB.PrimaryPart.Position.Z))
		quinB.PrimaryPart.CFrame = CFrame.lookAt(quinB.PrimaryPart.Position, Vector3.new(quinA.PrimaryPart.Position.X, quinB.PrimaryPart.Position.Y, quinA.PrimaryPart.Position.Z))
	end
	
	-- Disable AI temporarily while counting down (they will just idle)
	if quinA then quinA:SetAttribute("CurrentState", "Idle") end
	if quinB then quinB:SetAttribute("CurrentState", "Idle") end
	
	showCountdown()
	
	-- Force them into TestState
	if quinA then quinA:SetAttribute("ForceState", "Test") end
	if quinB then quinB:SetAttribute("ForceState", "Test") end
end

function GameModeManager.start1v1SparringMatch()
	return GameModeManager.startTeamBattle(1)
end

-- ======================================
-- PROJECTILE JUMP TEST MODE
-- ======================================
function GameModeManager.startJumpProjectileTestMode(styleNumber)
	currentMode = "JumpTestMode"
	roundActive = true
	QuinSpawner.cleanAll()
	Workspace:SetAttribute("MatchStarted", false)
	
	local spawnPart = Workspace:FindFirstChild("QuinSpawnJump", true) or Workspace:FindFirstChild("QuinSpawn", true)
	local spawnPos = spawnPart and spawnPart.Position or Vector3.new(0, 10, -50)
	
	local dummy = Workspace:FindFirstChild("TrainingDummy", true) or Workspace:FindFirstChild("Dummy", true)
	if not dummy then
		local dummyPos = spawnPos + Vector3.new(0, 0, 75)
		dummy = QuinSpawner.spawn("TypeB", dummyPos, "TeamBeta")
		if dummy then
			dummy.Name = "TrainingTarget_Quin"
			local dHum = dummy:FindFirstChildOfClass("Humanoid")
			if dHum then
				dHum.WalkSpeed = 0
				dHum.Health = 99999
			end
			dummy:SetAttribute("ForceState", "Idle")
		end
	end
	
	local quin = QuinSpawner.spawn("TypeA", spawnPos + Vector3.new(0, 5, 0), "TeamAlpha")
	task.wait(1.0)
	
	if quin and dummy then
		quin:SetAttribute("JumpStyle", styleNumber)
		quin:SetAttribute("ForceState", "ProjectileJump")
		
		local targetVal = quin:FindFirstChild("ProjectileTarget")
		if not targetVal then
			targetVal = Instance.new("ObjectValue")
			targetVal.Name = "ProjectileTarget"
			targetVal.Parent = quin
		end
		targetVal.Value = dummy
		
		Workspace:SetAttribute("CurrentMode", "JumpTestMode")
		broadcastStatus("Testing Jump Style " .. tostring(styleNumber))
	end
	
	Workspace:SetAttribute("MatchStarted", true)
end

-- ======================================
-- PROJECTILE FIGHT TEST MODE (DYNAMIC)
-- ======================================
function GameModeManager.startProjectileFightScene(scenario)
	currentMode = "ProjectileFight"
	roundActive = true
	QuinSpawner.cleanAll()
	Workspace:SetAttribute("MatchStarted", false)
	
	local positions = QuinSpawner.getSpawnPositions()
	
	local quinA = QuinSpawner.spawn("TypeA", positions[1], "TeamAlpha")
	
	task.wait(0.1) 
	
	if quinA then quinA:SetAttribute("CurrentState", "Idle") end
	
	Workspace:SetAttribute("CurrentMode", "ProjectileFight")
	broadcastStatus("Clean Slate: Single Quin Spawned")
	showCountdown()
	Workspace:SetAttribute("MatchStarted", true)
	
	if quinA then 
		quinA:SetAttribute("ForceState", "CleanSlate")
	end
end

function GameModeManager.startTestAnimationMode()
	currentMode = "AnimationLab"
	roundActive = false
	QuinSpawner.cleanAll()
	Workspace:SetAttribute("CurrentMode", "AnimationLab")
	Workspace:SetAttribute("MatchStarted", false)
	Workspace:SetAttribute("NormalCombatActive", false)

	task.wait(0.2)
	local p1 = Vector3.new(0, 7.5, 0)

	local quinA = QuinSpawner.spawn("TypeA", p1, "TeamAlpha")

	if quinA then
		quinA.Name = "QuinA_Tester"

		task.wait(0.1)
		local hrpA = quinA:FindFirstChild("HumanoidRootPart")
		if hrpA then
			hrpA.CFrame = CFrame.new(0, 7.5, 0)
			hrpA.AssemblyLinearVelocity = Vector3.zero
			hrpA.AssemblyAngularVelocity = Vector3.zero
		end

		local humA = quinA:FindFirstChildOfClass("Humanoid")
		if humA then
			humA.WalkSpeed = 0
			humA.AutoRotate = false
			humA.Health = 1000
		end

		quinA:SetAttribute("IsInert", true)
		quinA:SetAttribute("IsTester", true)
		quinA:SetAttribute("InCombat", false)
		quinA:SetAttribute("TargetQuin", nil)
		quinA:SetAttribute("CurrentTarget", nil)
		quinA:SetAttribute("CurrentState", "Idle")
		quinA:SetAttribute("ForceState", "Idle")
	end
	broadcastStatus("Animation Lab Mode: Single inert tester rig (QuinA_Tester) ready.")
end

function GameModeManager.startCleanSlateJumpState()
	currentMode = "ProjectileFight"
	roundActive = true
	QuinSpawner.cleanAll()
	Workspace:SetAttribute("MatchStarted", false)

	local positions = QuinSpawner.getSpawnPositions()

	local quinA = QuinSpawner.spawn("TypeA", positions[1], "TeamAlpha")

	task.wait(0.1) 

	if quinA then quinA:SetAttribute("CurrentState", "Idle") end

	Workspace:SetAttribute("CurrentMode", "CleanSlateJumpState")
	broadcastStatus("Clean Slate: Single Quin Spawned")
	showCountdown()
	Workspace:SetAttribute("MatchStarted", true)

	if quinA then 
		quinA:SetAttribute("ForceState", "CleanSlate")
	end
end

function GameModeManager.startMidAirClashMode()
	currentMode = "MidAirClashTest"
	roundActive = true
	QuinSpawner.cleanAll()
	Workspace:SetAttribute("MatchStarted", false)
	
	task.wait(0.2)
	local positions = QuinSpawner.getSpawnPositions()
	local base = positions[1] or Vector3.new(0, 10, 0)
	local p1 = base + Vector3.new(0, 35, -15)
	local p2 = base + Vector3.new(0, 35, 15)
	
	local quinA = QuinSpawner.spawn("TypeA", p1, "TeamAlpha")
	local quinB = QuinSpawner.spawn("TypeB", p2, "TeamBeta")
	
	if quinA and quinB then
		quinA.Name = "QuinA_Aerial"
		quinB.Name = "QuinB_Aerial"
		
		local hrpA = quinA:FindFirstChild("HumanoidRootPart")
		local hrpB = quinB:FindFirstChild("HumanoidRootPart")
		if hrpA and hrpB then
			hrpA.CFrame = CFrame.lookAt(p1, p2)
			hrpB.CFrame = CFrame.lookAt(p2, p1)
			hrpA.AssemblyLinearVelocity = Vector3.zero
			hrpB.AssemblyLinearVelocity = Vector3.zero
		end
		
		quinA:SetAttribute("TargetQuin", quinB.Name)
		quinB:SetAttribute("TargetQuin", quinA.Name)
		
		quinA:SetAttribute("ForceState", "MidAirClash")
		quinB:SetAttribute("ForceState", "MidAirClash")
		
		Workspace:SetAttribute("CurrentMode", "MidAirClashTest")
		broadcastStatus("Mid-Air Clash Duel Started!")
	end
	Workspace:SetAttribute("MatchStarted", true)
end

-- Test mode: the walk clip raw on the male and female rigs beside a live Quin walking on every
-- game layer, frame-labelled (ServerScriptService.PoseViewer). gender = "Male" | "Female".
function GameModeManager.startPoseViewer(gender, player)
	currentMode = "PoseViewer"
	roundActive = false
	gender = gender == "Female" and "Female" or "Male"
	PoseViewer.start({ gender = gender, player = player })
	broadcastStatus("Pose Viewer: raw walk clip (male, female) beside a live " .. gender .. " Quin")
end

-- Test mode: four Quins cross an obstacle course in step, each with a different layer on top of
-- the same clips (animation only, basic IK, foot placement, engine parts). The scene is built on
-- the client by Workspace.IKLab.IKLabDemo while CurrentMode is "IKLab".
function GameModeManager.startIKLab()
	currentMode = "IKLab"
	roundActive = false
	QuinSpawner.cleanAll()
	Workspace:SetAttribute("CurrentMode", "IKLab")
	Workspace:SetAttribute("MatchStarted", true)
	broadcastStatus("IK Lab: animation only vs IK layers, side by side")
end

function GameModeManager.startMovementTestInArena()
	currentMode = "MovementTestArena"
	roundActive = true
	QuinSpawner.cleanAll()
	Workspace:SetAttribute("CurrentMode", "MovementTestArena")
	Workspace:SetAttribute("MatchStarted", true)
	
	task.wait(0.2)
	-- The course's own checkpoints (the arena was moved; fixed coordinates spawned the Quins
	-- off the ground)
	local course = Workspace:FindFirstChild("MovementTestArena")
	local c1 = course and course:FindFirstChild("runandjumpcheckpoint1", true)
	local c2 = course and course:FindFirstChild("runandjumpcheckpoint2", true)
	local p1 = c1 and (c1.Position + Vector3.new(0, 5, 0)) or Vector3.new(418, 7, 122)
	local p2 = c2 and (c2.Position + Vector3.new(0, 5, 0)) or Vector3.new(412, 7, 592)
	
	local quinA = QuinSpawner.spawn("TypeA", p1, "TeamAlpha")
	local quinB = QuinSpawner.spawn("TypeB", p2, "TeamBeta")
	
	if quinA and quinB then
		quinA.Name = "QuinA_Runner"
		quinB.Name = "QuinB_Target"
		
		task.wait(0.1)
		local hrpA = quinA:FindFirstChild("HumanoidRootPart")
		local hrpB = quinB:FindFirstChild("HumanoidRootPart")
		if hrpA and hrpB then
			hrpA.CFrame = CFrame.lookAt(hrpA.Position, Vector3.new(hrpB.Position.X, hrpA.Position.Y, hrpB.Position.Z))
			hrpB.CFrame = CFrame.lookAt(hrpB.Position, Vector3.new(hrpA.Position.X, hrpB.Position.Y, hrpA.Position.Z))
			hrpA.AssemblyLinearVelocity = Vector3.zero
			hrpB.AssemblyLinearVelocity = Vector3.zero
		end
		
		local humB = quinB:FindFirstChildOfClass("Humanoid")
		if humB then
			humB.WalkSpeed = 0
			humB.Health = 99999
		end
		
		quinB:SetAttribute("IsSparringPartner", true)
		quinB:SetAttribute("ForceState", "Idle")
		-- A fixed finish line: WalkSpeed 0 alone did not hold it (its states raise the speed
		-- again), so the runner ended up chasing it round the maze instead of running the course
		if hrpB then
			hrpB.Anchored = true
		end
		quinB:SetAttribute("EnableProjectileJump", false)
		
		-- Configure QuinA to sprint towards QuinB across progressive hurdles
		quinA:SetAttribute("TargetQuin", "QuinB_Target")
		quinA:SetAttribute("CurrentTarget", "QuinB_Target")
		quinA:SetAttribute("InitialPacingOverride", "ContinuousSprint")
		quinA:SetAttribute("ForceState", "Chase")
		quinA:SetAttribute("EnableProjectileJump", false) -- Pure locomotion hurdle test
	end
	
	broadcastStatus("Movement Test Arena Started: QuinA sprinting across hurdle course towards checkpoint 2.")
end

-- ======================================
-- COMMANDS (via chat or remote)
-- ======================================
local commandEvent = ReplicatedStorage:FindFirstChild("GameCommand")
if not commandEvent then
	commandEvent = Instance.new("RemoteEvent")
	commandEvent.Name = "GameCommand"
	commandEvent.Parent = ReplicatedStorage
end

commandEvent.OnServerEvent:Connect(function(player, command, arg1)
	print("[GameMode] Command from " .. player.Name .. ": " .. tostring(command))
	
	if command == "ffa" then
		GameModeManager.startFreeForAll(tonumber(arg1) or 8)
	elseif command == "1v1" or command == "sparring" then
		GameModeManager.start1v1SparringMatch()
	elseif command == "team" then
		GameModeManager.startTeamBattle(tonumber(arg1) or 4)
	elseif command == "midair_clash" or command == "midair_clash_test" then
		GameModeManager.startMidAirClashMode()
	elseif command == "movement_test" or command == "arena_movement_test" then
		GameModeManager.startMovementTestInArena()
	elseif command == "pose_viewer" then
		GameModeManager.startPoseViewer(arg1, player)
	elseif command == "ik_lab" then
		GameModeManager.startIKLab()
	elseif command == "tournament" then
		GameModeManager.startTournament()
	elseif command == "jump_test" then
		GameModeManager.startJumpProjectileTestMode(tonumber(arg1) or 1)
	elseif command == "projectile_fight" then
		GameModeManager.startProjectileFightScene(arg1)
	elseif command == "toggle_visualizer" then
		Workspace:SetAttribute("ProjectileVisualizerEnabled", arg1)
		print("[GameMode] Visualizer toggled: ", arg1)
	elseif command == "clean" then
		QuinSpawner.cleanAll()
		currentMode = "None"
		roundActive = false
		Workspace:SetAttribute("CurrentMode", "None")
		broadcastStatus("Arena cleared")
	elseif command == "clean_slate_jump" then
		QuinSpawner.cleanAll()
		task.wait(0.1)
		local pos = QuinSpawner.getSpawnPositions()[1]
		local quin = QuinSpawner.spawn("TypeA", pos, "TeamAlpha")
		task.wait(0.1)
		if quin then
			quin:SetAttribute("ForceState", "CleanSlate")
			print("[GameMode] CleanSlate forced on " .. quin.Name)
		end
	elseif command == "deterministic_scenario" then
		QuinSpawner.cleanAll()
		task.wait(0.1)
		
		local config = arg1 or {}
		local positions = QuinSpawner.getSpawnPositions()
		
		local quinA = QuinSpawner.spawn("TypeA", positions[1], "TeamAlpha")
		local quinB = QuinSpawner.spawn("TypeA", positions[2], "TeamBeta")
		
		task.wait(0.1)
		
		if quinA and quinB then
			quinA.Name = "QuinA_Leader"
			quinB.Name = "QuinB_Follower"
			
			quinA:SetAttribute("IsLeader", true)
			quinB:SetAttribute("IsLeader", false)
			
			quinA:SetAttribute("TargetQuin", quinB.Name)
			quinB:SetAttribute("TargetQuin", quinA.Name)
			
			quinA:SetAttribute("DeterministicAction", config.LeaderAction)
			quinB:SetAttribute("DeterministicIntercept", config.InterceptType)
			quinB:SetAttribute("DeterministicOutcome", config.Outcome)
			quinB:SetAttribute("DeterministicWinner", config.Winner)
			
			quinA:SetAttribute("ForceState", "ProjectileFight")
			quinB:SetAttribute("ForceState", "Interception")
			
			print("[GameMode] Deterministic Scenario Started")
		end
	end
end)

-- ======================================
-- AUTO-START CONFIGURATION
-- ======================================
local GAME_MODE = 0 -- 0: Inactive on default Play (do nothing)

task.delay(3, function()
	if GAME_MODE == 0 or not GAME_MODE then
		-- Do nothing on default Play as requested
		return
	elseif GAME_MODE == 1 then
		broadcastStatus("Auto-starting Jump Projectile Test Mode...")
		GameModeManager.startJumpProjectileTestMode(1)
		
	elseif GAME_MODE == 2 then
		broadcastStatus("Auto-starting 1v1 Animation Diagnostic...")
		GameModeManager.startTestMode()
		
	elseif GAME_MODE == 3 then
		broadcastStatus("Auto-starting Team Battle...")
		GameModeManager.startTeamBattle(1)
		
	elseif GAME_MODE == 4 then
		broadcastStatus("Auto-starting Free For All...")
		GameModeManager.startFreeForAll(4)
		
	elseif GAME_MODE == 5 then
		broadcastStatus("Auto-starting Tournament...")
		GameModeManager.startTournament()
		
	elseif GAME_MODE == 6 then
		broadcastStatus("Auto-starting Projectile Fight Scene...")
		GameModeManager.startProjectileFightScene("1-Quin Projectile")
	elseif GAME_MODE == 7 then
		broadcastStatus("Auto-starting Clean Slate Jumping State...")
		GameModeManager.startCleanSlateJumpState()
	elseif GAME_MODE == 8 then
		broadcastStatus("Auto-starting Movement Test Arena Mode...")
		GameModeManager.startMovementTestInArena()
	end
end)

-- Studio testing: tools that cannot fire GameCommand from a client (the Studio MCP) set
-- Workspace attribute DevCommand = "movement_test" | "team:16" | "ffa:8" | "pose_viewer:Male" | "ik_lab". Studio only.
if game:GetService("RunService"):IsStudio() then
	Workspace:GetAttributeChangedSignal("DevCommand"):Connect(function()
		local raw = Workspace:GetAttribute("DevCommand")
		if type(raw) ~= "string" or raw == "" then return end
		Workspace:SetAttribute("DevCommand", nil)
		local command, arg = raw:match("^([^:]+):?(.*)$")
		if command == "movement_test" then
			GameModeManager.startMovementTestInArena()
		elseif command == "team" then
			GameModeManager.startTeamBattle(tonumber(arg) or 4)
		elseif command == "ffa" then
			GameModeManager.startFreeForAll(tonumber(arg) or 8)
		elseif command == "pose_viewer" then
			GameModeManager.startPoseViewer(arg)
		elseif command == "ik_lab" then
			GameModeManager.startIKLab()
		end
	end)
end

_G.GameModeManager = GameModeManager
print("[GameModeManager] Ready. Modes: ffa, team, tournament")
