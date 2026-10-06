--// AI_Main.server.lua
-- Server-side: Handles FSM logic, AI death, state sync, and health display

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local Quin = script.Parent
local humanoid = Quin:FindFirstChildOfClass("Humanoid")
local rootPart = Quin:FindFirstChild("HumanoidRootPart")

-- Wait for attributes to load (from Spawner)
task.wait(0.1)

Quin.PrimaryPart = rootPart
if rootPart then
	-- Disable physics tripping so they don't look like cockroaches when they collide
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Physics, false)
	
	if not Quin:GetAttribute("IsPlayerControlled") then
		rootPart:SetNetworkOwner(nil) -- Server owns movement
	end
end

-- === DATA & CONFIG ===
local QuinCore = ReplicatedStorage:WaitForChild("QuinCore")
local CombatConfig = require(QuinCore:WaitForChild("CombatConfig"))
local QuinData = require(QuinCore:WaitForChild("QuinData"))
local AudioModule = require(QuinCore:WaitForChild("Modules"):WaitForChild("AudioModule"))
local SpatialModule = require(QuinCore:WaitForChild("Modules"):WaitForChild("SpatialModule"))
local TacticalPerception = require(QuinCore:WaitForChild("Modules"):WaitForChild("TacticalPerception"))
local DecisionSystem = require(QuinCore:WaitForChild("Modules"):WaitForChild("DecisionSystem"))
local BattleEventSystem = require(QuinCore:WaitForChild("Modules"):WaitForChild("BattleEventSystem"))
local TargetingModule = require(QuinCore:WaitForChild("Modules"):WaitForChild("TargetingModule"))
local RuntimeTracer = require(QuinCore:WaitForChild("Modules"):WaitForChild("RuntimeTracer"))
local LocomotionModule = require(QuinCore:WaitForChild("Modules"):WaitForChild("LocomotionModule"))
local GaitModule = require(QuinCore:WaitForChild("Modules"):WaitForChild("GaitModule"))
local SocialSystem = require(QuinCore:WaitForChild("Modules"):WaitForChild("SocialSystem"))
local HeadroomAwareness = require(QuinCore:WaitForChild("Modules"):WaitForChild("HeadroomAwareness"))
local ArenaTrespass = require(QuinCore:WaitForChild("Modules"):WaitForChild("ArenaTrespass"))
local EdgeAwareness = require(QuinCore:WaitForChild("Modules"):WaitForChild("EdgeAwareness"))
local Cognition = require(QuinCore:WaitForChild("Cognition"))

-- States in which a Quin stands on the ground by its own choice (and so needs room to stand)
-- States in which a Quin is not in control of itself: it does not pick a new target in them
-- (measured: 22 % of all target changes happened knocked down or in mid-jump, where it cannot act
-- on the choice and comes out of it turned to someone else)
local NO_RETARGET_STATES = { Knockback = true, Recovery = true, ProjectileJump = true, MidAirClash = true, Airborne = true, WallRun = true }
local STANDING_STATES = { Idle = true, Fight = true, Circling = true, Chase = true, Retreat = true, Overwatch = true }
-- A Quin piloted by a player (PilotedBy, Player Quin match mode) takes its decisions from the
-- player (PilotedState); only what happens to its body is left to the states every Quin has
local PILOT_STATES = { Piloted = true, Knockback = true, Recovery = true, Death = true, ReEntry = true,
	ProjectileJump = true, MidAirClash = true } -- (a jump it chose; a clash it met in the air)
local function isPiloted() return Quin:GetAttribute("PilotedBy") ~= nil end
SocialSystem.start() -- the social layer (pack leaders, respect customs, arena events)

-- === STATE MODULES ===
local statesFolder = QuinCore:WaitForChild("States") 
local States = {
	Idle = require(statesFolder:WaitForChild("IdleState")),
	Chase = require(statesFolder:WaitForChild("ChaseState")),
	Circling = require(statesFolder:WaitForChild("CirclingState")),
	Fight = require(statesFolder:WaitForChild("FightState")),
	Airborne = require(statesFolder:WaitForChild("AirborneState")),
	Knockback = require(statesFolder:WaitForChild("KnockbackState")),
	Recovery = require(statesFolder:WaitForChild("RecoveryState")),
	Retreat = require(statesFolder:WaitForChild("RetreatState")),
	Overwatch = require(statesFolder:WaitForChild("OverwatchState")),
	Special = require(statesFolder:WaitForChild("SpecialState")),
	Death = require(statesFolder:WaitForChild("DeathState")),
	ProjectileJump = require(statesFolder:WaitForChild("ProjectileJumpState")),
	MidAirClash = require(statesFolder:WaitForChild("MidAirClashState")),
	ProjectileFight = require(statesFolder:WaitForChild("ProjectileFightState")),
	Interception = require(statesFolder:WaitForChild("InterceptionState")),
	ReEntry = require(statesFolder:WaitForChild("ReEntryState")),
	WallRun = require(statesFolder:WaitForChild("WallRunState")),
	BeamStruggle = require(statesFolder:WaitForChild("BeamStruggleState")),
	Piloted = require(statesFolder:WaitForChild("PilotedState")),
}

-- Aliases for backwards compatibility / absorbed micro-actions
States.Slide = States.Chase
States.Dash = States.Chase
States.Test = States.Idle
States.AuraFarm = States.Circling
States.PositioningJump = States.Chase
States.TargetTransition = States.Idle
States.ProjectileJumpRecovery = States.Recovery
States.Anticipate = States.Fight
States.TestEnd = States.Idle

-- === REMOTE EVENT (STATE SYNC) ===
local StateSyncEvent = ReplicatedStorage:FindFirstChild("AI_StateSync")
if not StateSyncEvent then
	StateSyncEvent = Instance.new("RemoteEvent")
	StateSyncEvent.Name = "AI_StateSync"
	StateSyncEvent.Parent = ReplicatedStorage
end

-- === SETTINGS ===
local enableAI = true

-- Render-mode boundary for the direct-authoritative presentation migration.
-- Direct is the default; set Workspace.QuinRenderMode to "Ghost" to roll back
-- to the legacy cloned presentation path during validation.
local renderMode = workspace:GetAttribute("QuinRenderMode")
if renderMode ~= "Ghost" and renderMode ~= "Direct" then
	renderMode = "Direct"
	workspace:SetAttribute("QuinRenderMode", renderMode)
end
local GHOSTMODE = renderMode == "Ghost"
Quin:SetAttribute("QuinRenderMode", renderMode)

local currentState = States.Idle
local previousState = nil
local stateStartTime = os.clock()

-- Init State
Quin:SetAttribute("CurrentState", currentState.name)
if Quin:GetAttribute("Energy") == nil then
	Quin:SetAttribute("Energy", CombatConfig.MaxEnergy or 100)
end
if not Quin:GetAttribute("IsPlayerControlled") and currentState.enter then
	currentState.enter(Quin, humanoid, rootPart)
end

-- Ground contract for every state: ground loops (walk/jog/run/strafe) never play in the
-- air; the Fall pose covers the body until touchdown. The piloting client enforces it
-- while a player owns this Quin.
GaitModule.bindGroundContract(Quin, humanoid, rootPart, function()
	return Quin:GetAttribute("IsPlayerControlled") ~= true
end)

-- If this Quin becomes possessed by a human player, immediately kill server animation tracks
Quin:GetAttributeChangedSignal("IsPlayerControlled"):Connect(function()
	if Quin:GetAttribute("IsPlayerControlled") == true then
		local animMod = require(QuinCore:WaitForChild("Modules"):WaitForChild("AnimationModule"))
		animMod.stopAll(humanoid, 0)
		local animator = humanoid:FindFirstChildOfClass("Animator")
		if animator then
			for _, t in ipairs(animator:GetPlayingAnimationTracks()) do
				t:Stop(0)
			end
		end
	end
end)

-- === PRESENTATION VISIBILITY ===
-- Ghost mode hides the authoritative rig because the legacy client clone is
-- responsible for presentation. Direct mode leaves the authoritative model
-- visible and is the only mode used after migration.
if GHOSTMODE then
	for _, part in ipairs(Quin:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Transparency = 1
			part.CastShadow = false
		elseif part:IsA("Decal") or part:IsA("Texture") then
			part.Transparency = 1
		end
	end
else
	local alpha = Quin:FindFirstChild("Alpha_Surface", true) or Quin:FindFirstChild("Beta_Surface", true) or Quin:FindFirstChildWhichIsA("MeshPart", true)
	if alpha and alpha:IsA("BasePart") then
		alpha.Transparency = 0
		alpha.CastShadow = true
	end
end

-- === HEALTH BAR ===
local healthGui = Instance.new("BillboardGui")
healthGui.Size = UDim2.new(0, 150, 0, 70)
healthGui.StudsOffset = Vector3.new(0, 10, 0)
healthGui.AlwaysOnTop = true
healthGui.Parent = rootPart

local bgFrame = Instance.new("Frame")
bgFrame.Size = UDim2.new(1, 0, 0, 10)
bgFrame.Position = UDim2.new(0, 0, 1, -16)
bgFrame.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
bgFrame.BorderSizePixel = 0
bgFrame.Visible = false
bgFrame.Parent = healthGui

local hpBar = Instance.new("Frame")
hpBar.Size = UDim2.new(1, 0, 1, 0)
hpBar.BackgroundColor3 = Color3.fromRGB(80, 255, 80)
hpBar.BorderSizePixel = 0
hpBar.Parent = bgFrame

local spBgFrame = Instance.new("Frame")
spBgFrame.Size = UDim2.new(1, 0, 0, 6)
spBgFrame.Position = UDim2.new(0, 0, 1, -4)
spBgFrame.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
spBgFrame.BorderSizePixel = 0
spBgFrame.Visible = false
spBgFrame.Parent = healthGui

local spBar = Instance.new("Frame")
spBar.Size = UDim2.new(0, 0, 1, 0)
spBar.BackgroundColor3 = Color3.fromRGB(80, 200, 255)
spBar.BorderSizePixel = 0
spBar.Parent = spBgFrame

local comboGui = Instance.new("TextLabel")
comboGui.Size = UDim2.new(1, 0, 0, 15)
comboGui.Position = UDim2.new(0, 0, 1, -25)
comboGui.BackgroundTransparency = 1
comboGui.TextColor3 = Color3.fromRGB(255, 200, 0)
comboGui.TextStrokeTransparency = 0
comboGui.TextScaled = true
comboGui.Font = Enum.Font.GothamBold
comboGui.Text = ""
comboGui.Parent = healthGui

-- === DEBUG STATE LABEL ===
local stateGui = Instance.new("TextLabel")
stateGui.Size = UDim2.new(2, 0, 0, 50)
stateGui.Position = UDim2.new(-0.5, 0, 0, -35)
stateGui.BackgroundTransparency = 1
stateGui.TextColor3 = Color3.fromRGB(255, 255, 0)
stateGui.TextStrokeTransparency = 0
stateGui.TextScaled = true
stateGui.TextWrapped = true
stateGui.Font = Enum.Font.Code
stateGui.Text = "[ STATE: " .. currentState.name .. " ]"
stateGui.Visible = false -- Toggled off debug text
stateGui.Parent = healthGui

-- Note: Footstep and animation audio markers are handled authoritatively by AnimationModule on track load.

-- === DEBUG ORIENTATION VISUALIZER ===
local axisLines = {}
if rootPart then
	local function createAxisLines(part)
		local size = 3
		
		local xLine = Instance.new("LineHandleAdornment")
		xLine.Name = "Debug_X"
		xLine.Color3 = Color3.new(1, 0, 0) -- Red (Right)
		xLine.Thickness = 5
		xLine.Length = size
		xLine.CFrame = CFrame.Angles(0, math.rad(90), 0)
		xLine.Adornee = part
		xLine.AlwaysOnTop = true
		xLine.Visible = false
		xLine.Parent = part
		
		local yLine = Instance.new("LineHandleAdornment")
		yLine.Name = "Debug_Y"
		yLine.Color3 = Color3.new(0, 1, 0) -- Green (Up)
		yLine.Thickness = 5
		yLine.Length = size
		yLine.CFrame = CFrame.Angles(math.rad(-90), 0, 0)
		yLine.Adornee = part
		yLine.AlwaysOnTop = true
		yLine.Visible = false
		yLine.Parent = part
		
		local zLine = Instance.new("LineHandleAdornment")
		zLine.Name = "Debug_Z"
		zLine.Color3 = Color3.new(0, 0.5, 1) -- Blue (Forward)
		zLine.Thickness = 5
		zLine.Length = size
		zLine.CFrame = CFrame.Angles(0, math.pi, 0)
		zLine.Adornee = part
		zLine.AlwaysOnTop = true
		zLine.Visible = false
		zLine.Parent = part
		
		local center = Instance.new("SphereHandleAdornment")
		center.Name = "Debug_Center"
		center.Color3 = Color3.new(1, 1, 0) -- Yellow Center
		center.Radius = 0.5
		center.Adornee = part
		center.AlwaysOnTop = true
		center.Visible = false
		center.Parent = part
		
		table.insert(axisLines, xLine)
		table.insert(axisLines, yLine)
		table.insert(axisLines, zLine)
		table.insert(axisLines, center)
	end
	
	createAxisLines(rootPart)
end

-- === Smooth HP updater + fade effect ===
task.spawn(function()
	while enableAI and humanoid and humanoid.Parent do
		local ratio = humanoid.Health / humanoid.MaxHealth
		hpBar.Size = UDim2.new(math.clamp(ratio, 0, 1), 0, 1, 0)

		-- color logic
		if ratio <= 0.3 then
			hpBar.BackgroundColor3 = Color3.fromRGB(255, 60, 60)
		elseif ratio <= 0.6 then
			hpBar.BackgroundColor3 = Color3.fromRGB(255, 180, 60)
		else
			hpBar.BackgroundColor3 = Color3.fromRGB(80, 255, 80)
		end

		-- distance fade
		local nearestDist = math.huge
		for _, p in ipairs(Players:GetPlayers()) do
			local hrp = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
			if hrp then
				local d = (hrp.Position - rootPart.Position).Magnitude
				if d < nearestDist then
					nearestDist = d
				end
			end
		end
		local fadeDist = 100
		local alpha = math.clamp(1 - (nearestDist / fadeDist), 0.15, 1)
		
		local showBars = workspace:GetAttribute("Debug_HealthBars")
		local showLabels = workspace:GetAttribute("Debug_StateLabels")
		local showOrientation = workspace:GetAttribute("Debug_Orientation")
		
		bgFrame.Visible = showBars
		spBgFrame.Visible = showBars
		stateGui.Visible = showLabels
		comboGui.Visible = showLabels
		
		for _, line in ipairs(axisLines) do
			line.Visible = showOrientation
		end
		
		bgFrame.BackgroundTransparency = 1 - (alpha * 0.4)
		hpBar.BackgroundTransparency = 1 - alpha
		spBgFrame.BackgroundTransparency = 1 - (alpha * 0.4)
		spBar.BackgroundTransparency = 1 - alpha
		comboGui.TextTransparency = 1 - alpha
		comboGui.TextStrokeTransparency = 1 - alpha
		stateGui.TextTransparency = 1 - alpha
		stateGui.TextStrokeTransparency = 1 - alpha
		
		-- Energy bar logic
		local energy = Quin:GetAttribute("Energy") or 0
		local maxEnergy = CombatConfig.MaxEnergy or 100
		local eRatio = math.clamp(energy / maxEnergy, 0, 1)
		spBar.Size = UDim2.new(eRatio, 0, 1, 0)
		
		-- Energy bar color: cyan when healthy, red when fatigued
		if energy <= (CombatConfig.FatigueThreshold or 20) then
			spBar.BackgroundColor3 = Color3.fromRGB(255, 60, 60)
		elseif energy <= 50 then
			spBar.BackgroundColor3 = Color3.fromRGB(255, 200, 80)
		else
			spBar.BackgroundColor3 = Color3.fromRGB(80, 200, 255)
		end
		
		-- The debug label is only built while it is shown. (Built for every Quin every 0.03 s
		-- whether shown or not, it was two raycasts, a track list and a string sent to every
		-- client, 33 times a second per Quin.)
		local success, err = true, nil
		if showLabels then success, err = pcall(function()
			local anims = {}
			for _, track in ipairs(humanoid:GetPlayingAnimationTracks()) do
				if track.WeightCurrent > 0.01 then
					local id = track.Animation and track.Animation.AnimationId or "Unknown"
					local cleanId = string.match(id, "%d+") or id
					if track.Length == 0 then
						cleanId = cleanId .. "(BROKEN)"
					end
					table.insert(anims, cleanId)
				end
			end
			local animStr = #anims > 0 and table.concat(anims, ",") or "None"
			
			local speed = math.floor(humanoid.WalkSpeed)
			local yVel = rootPart and math.floor(rootPart.AssemblyLinearVelocity.Y) or 0
			local pStand = humanoid.PlatformStand
			
			local isGrounded = false
			local hitName = "NIL"
			if rootPart then
				local params = RaycastParams.new()
				params.FilterDescendantsInstances = {Quin}
				params.FilterType = Enum.RaycastFilterType.Exclude
				local result = workspace:Raycast(rootPart.Position, Vector3.new(0, -15, 0), params)
				isGrounded = result ~= nil
				hitName = result and result.Instance.Name or "NIL"
				
				-- Draw it live
				local SpatialModule = require(QuinCore:WaitForChild("Modules"):WaitForChild("SpatialModule"))
				SpatialModule.isGrounded(rootPart) -- Call just to draw
			end
			
			local kbType = Quin:GetAttribute("KnockbackType") or "none"

			local obAware = Quin:GetAttribute("ObstacleAwareness")
			local obStr = (obAware and obAware ~= "Clear") and (" | " .. obAware) or ""

			stateGui.Text = string.format("[ %s ]%s\nSpd:%d Y:%d Grd:%s (%s)\nKB:%s | %s", 
				Quin:GetAttribute("CurrentState") or "None", 
				obStr,
				speed, yVel, tostring(isGrounded), hitName, kbType, animStr)
		end) end
		if not success then
			stateGui.Text = "[ STATE: " .. (Quin:GetAttribute("CurrentState") or "None") .. " ]"
			warn("Debug UI error:", err)
		end
		
		-- (with the bars and the labels both off there is nothing to keep fresh)
		task.wait((showBars or showLabels) and 0.03 or 0.25)
	end
end)

-- //////////////////////////////////////////////////////////////////////
-- === DEATH HANDLER
-- //////////////////////////////////////////////////////////////////////
humanoid.Died:Connect(function()
	if not enableAI then return end
	enableAI = false
	print(Quin.Name .. " has died ðŸ©¸")

	healthGui.Enabled = false

	-- Clean up locomotion tracking & align movers
	LocomotionModule.cleanup(Quin)

	-- Change state to DeathState immediately
	if currentState.exit then
		currentState.exit(Quin, humanoid, rootPart)
	end
	currentState = States.Death
	Quin:SetAttribute("CurrentState", currentState.name)
	
	if currentState.enter then
		currentState.enter(Quin, humanoid, rootPart)
	end
end)

-- //////////////////////////////////////////////////////////////////////
-- === FSM LOOP
-- //////////////////////////////////////////////////////////////////////
local function broadcastStateChange(Quin, newState)
	if not Quin or not newState then return end
	StateSyncEvent:FireAllClients(Quin, newState.name)
end

task.spawn(function()
	while enableAI and Quin.Parent and humanoid.Health > 0 do
		-- === Player-Controlled Bypass ===
		-- When a human player is piloting this Quin, bypass autonomous AI decisions, FSM movement, and AI arena safety net
		if Quin:GetAttribute("IsPlayerControlled") == true then
			local speedMult = workspace:GetAttribute("GameSpeedMultiplier") or 1.0
			task.wait(math.clamp(0.05 / speedMult, 0.015, 0.05))
			continue
		end

		-- === Studio test: run laps (MovementTestArena circle course) ===
		-- With DevLapRadius / DevLapCenter set (Studio only) the Quin runs a circle on its normal
		-- locomotion (steer driver, gait, lean) instead of its states, at the speed its lateral
		-- grip allows on that radius. Clearing the attribute hands it back to the AI.
		local lapRadius = Quin:GetAttribute("DevLapRadius")
		if lapRadius and game:GetService("RunService"):IsStudio() then
			local center = Quin:GetAttribute("DevLapCenter") or rootPart.Position
			local grip = CombatConfig.Locomotion_LateralGrip or 90
			local speed = math.min(Quin:GetAttribute("DevLapSpeed") or 40, math.sqrt(grip * lapRadius) * 0.95)
			local p = rootPart.Position
			-- along the tangent, with a pull back onto the circle (aiming at a point ahead on the
			-- circle made it face the chord, 10-20 degrees off its motion)
			local radial = Vector3.new(p.X - center.X, 0, p.Z - center.Z)
			local distance = radial.Magnitude
			radial = distance > 0.1 and radial.Unit or Vector3.new(1, 0, 0)
			local tangent = Vector3.new(-radial.Z, 0, radial.X) * (Quin:GetAttribute("DevLapDirection") or 1)
			local goal = p + tangent * 10 - radial * math.clamp(distance - lapRadius, -3, 3) * 1.5
			LocomotionModule.steer(Quin, humanoid, rootPart, goal, speed, 0.05)
			GaitModule.update(humanoid, rootPart, 0.05)
			task.wait(0.05)
			continue
		end

		-- With DevGoal set (Studio, or the Pose Viewer test mode in a live server) the Quin runs at
		-- that point on its normal locomotion; a test moves the goal to make it turn (pivots,
		-- reversals) or walks it up and down (PoseViewer). Only the server sets it.
		local devGoal = Quin:GetAttribute("DevGoal")
		if devGoal and (game:GetService("RunService"):IsStudio() or workspace:GetAttribute("CurrentMode") == "PoseViewer") then
			LocomotionModule.steer(Quin, humanoid, rootPart, devGoal, Quin:GetAttribute("DevGoalSpeed") or 40, 0.1)
			GaitModule.update(humanoid, rootPart, 0.1)
			task.wait(0.1)
			continue
		end

		-- === Inert Laboratory Rig Bypass ===
		-- When marked IsInert or IsTester (without explicit combat mode active), keep Quin completely passive
		local isInert = Quin:GetAttribute("IsInert") == true
		local isTester = Quin:GetAttribute("IsTester") == true and not _G.CombatBrawlActive
		if isInert or isTester then
			humanoid.WalkSpeed = 0
			humanoid.AutoRotate = false
			if rootPart then
				rootPart.AssemblyLinearVelocity = Vector3.zero
			end
			local speedMult = workspace:GetAttribute("GameSpeedMultiplier") or 1.0
			task.wait(math.clamp(0.15 / speedMult, 0.05, 0.2))
			continue
		end

		-- === Arena Safety Net & Cinematic Re-Entry ===
		if rootPart then
			-- === Respect-custom duel: duelists stay on the ceremony space ===
			if Quin:GetAttribute("RespectRole") == "Duelist" then
				SocialSystem.constrainToCeremony(rootPart)
			end

			local curStateName = currentState and currentState.name or ""

			-- Off the arena floor (ArenaTrespass). The wall is part of the game and a Quin may be
			-- thrown out of the arena: both are allowed, both cost performance, and after a while
			-- the Quin is brought back (ReEntry) unless it has come back by itself. Only the void
			-- is not a place to be: a Quin that has fallen out of the world is put back at once.
			-- (Before: anywhere within 5 studs of the floor's edge counted as out, for 1 s.)
			if curStateName ~= "ReEntry" and curStateName ~= "Death" then
				local mustReturn = ArenaTrespass.update(Quin, rootPart, curStateName, 0.1)
				local pos = rootPart.Position
				local bounds = SpatialModule.getArenaBounds()
				if math.abs(pos.X - bounds.center.X) > (bounds.halfX + 80) or math.abs(pos.Z - bounds.center.Z) > (bounds.halfZ + 80) or pos.Y < -5 then
					print(string.format("[SafetyNet] %s in deep void/fallen (%.1f, %.1f, %.1f) - emergency teleport to arena.", Quin.Name, pos.X, pos.Y, pos.Z))
					Quin:PivotTo(CFrame.new(bounds.center.X, 7.5, bounds.center.Z))
					rootPart.AssemblyLinearVelocity = Vector3.zero
				elseif mustReturn and curStateName ~= "WallRun" and curStateName ~= "Knockback"
					and math.abs(rootPart.AssemblyLinearVelocity.Y) <= 35 then
					-- (not while it runs along the wall or is still being thrown)
					print(string.format("[Trespass] %s off the arena floor (%s) for %.1fs - re-entry", Quin.Name, tostring(Quin:GetAttribute("Trespass")), Quin:GetAttribute("TrespassTime") or 0))
					Quin:SetAttribute("ForceState", "ReEntry")
				end
			end
			
			-- === Physical Angular Velocity Governor: eliminate physics simulation freakout / 360 spinning ===
			-- Physical HRP rotation should never exceed 25 rad/s. Clamping prevents PGS solver explosions.
			if rootPart.AssemblyAngularVelocity.Magnitude > 25 then
				rootPart.AssemblyAngularVelocity = rootPart.AssemblyAngularVelocity.Unit * 25
			end

			-- Cleanup legacy UprightRecovery if present
			local oldGyro = rootPart:FindFirstChild("UprightRecovery")
			if oldGyro then oldGyro:Destroy() end
			local oldAtt = rootPart:FindFirstChild("UprightRecoveryAtt")
			if oldAtt then oldAtt:Destroy() end

			-- === Anti-Cockroach Protection: authoritative prone recovery ===
			-- If a Quin is grounded and tilted flat (upY < 0.70), force RecoveryState so it stands up
			-- instead of running/fighting while lying horizontally on the floor.
			local upY = rootPart.CFrame.UpVector.Y
			local isShowdownSpectator = SocialSystem.isSpectator(Quin)
			local isGrounded = SpatialModule.isGrounded(rootPart) or (humanoid.FloorMaterial ~= Enum.Material.Air)

			if upY < 0.70 and isGrounded and not isShowdownSpectator then
				local isRecovering = (currentState.name == "Recovery" or currentState.name == "Knockback" or currentState.name == "ReEntry")
				if not isRecovering then
					local proneTime = (Quin:GetAttribute("ProneGroundedTime") or 0) + 0.1
					Quin:SetAttribute("ProneGroundedTime", proneTime)
					if proneTime >= 0.15 then
						Quin:SetAttribute("ProneGroundedTime", 0)
						Quin:SetAttribute("KnockbackType", "hard_ground")
						Quin:SetAttribute("ForceState", "Recovery")
					end
				else
					Quin:SetAttribute("ProneGroundedTime", 0)
				end
			else
				Quin:SetAttribute("ProneGroundedTime", 0)
			end

			-- === Anti-Float Protection (stuck mid-air) ===
			do
				local isShowdown = Quin:GetAttribute("RespectRole") == "Duelist"
				local isAirState = (currentState.name == "Knockback" or currentState.name == "Airborne"
					or currentState.name == "ProjectileJump"
					or currentState.name == "MidAirClash" or currentState.name == "BeamStruggle"
					or currentState.name == "Recovery"
					or currentState.name == "ReEntry")
				if not isShowdown and not isAirState and not isGrounded and rootPart.AssemblyLinearVelocity.Magnitude < 5 then
					local floatTime = (Quin:GetAttribute("FloatTime") or 0) + 0.1
					Quin:SetAttribute("FloatTime", floatTime)
					if floatTime > 2.0 then
						print("[AntiFloat] Stuck mid-air, forcing re-entry: " .. Quin.Name)
						Quin:SetAttribute("FloatTime", 0)
						Quin:SetAttribute("ForceState", "ReEntry")
					end
				else
					Quin:SetAttribute("FloatTime", 0)
				end
			end
		end

		-- === De-stacking: prevent Quins from piling on top of each other like bricks ===
		do
			local myPos = rootPart.Position
			for _, other in ipairs(CollectionService:GetTagged("Quin")) do
				if other ~= Quin and other.Parent then
					local oHRP = other:FindFirstChild("HumanoidRootPart")
					if oHRP then
						local oPos = oHRP.Position
						local flatDist = Vector3.new(oPos.X - myPos.X, 0, oPos.Z - myPos.Z).Magnitude
						local yDiff = oPos.Y - myPos.Y
						-- 'other' is standing on top of this Quin: shove it off sideways
						-- Only a Quin actually resting on top is shoved off. One passing overhead in a
						-- jump or knockback arc is left alone: this check used to teleport it 3.5 studs,
						-- reset its facing and replace its velocity in mid-flight.
						local oHum = other:FindFirstChildOfClass("Humanoid")
						local oVel = oHRP.AssemblyLinearVelocity
						local isResting = oHum ~= nil and oHum.Health > 0 and not oHum.PlatformStand
							and math.abs(oVel.Y) < 6 and oVel.Magnitude < 12
						if isResting and flatDist < 3.5 and yDiff > 2.0 and yDiff < 10 then
							local pushDir = Vector3.new(oPos.X - myPos.X, 0, oPos.Z - myPos.Z)
							if pushDir.Magnitude < 0.01 then
								pushDir = Vector3.new(math.random() - 0.5, 0, math.random() - 0.5)
							end
							pushDir = pushDir.Unit
							oHRP.CFrame = oHRP.CFrame + pushDir * 1.5 -- keeps its facing
							oHRP.AssemblyLinearVelocity = Vector3.new(pushDir.X * 24, 8, pushDir.Z * 24)
						end
					end
				end
			end
		end


		-- === Tactical Perception & Emergent Decision Layer ===
		local showdownRole = Quin:GetAttribute("RespectRole")
		local isShowdownPerimeter = SocialSystem.standsDown(Quin) -- (stepped back for the respect custom: plans no fights)
		local isBeamStruggling = (currentState.name == "BeamStruggle")

		if not isShowdownPerimeter and not isBeamStruggling and rootPart and humanoid.Health > 0 and not isPiloted() then
			local tacticalContext = TacticalPerception.evaluate(Quin)
			if tacticalContext then
				-- 1. Utility-based target selection & switching
				local oldTargetName = Quin:GetAttribute("CurrentTarget")
				local selectedTarget, targetScore, targetReason
				if NO_RETARGET_STATES[currentState.name] then
					selectedTarget = TargetingModule.getCommittedTarget(Quin, rootPart) -- (the one it has)
				else
					selectedTarget, targetScore, targetReason = TargetingModule.selectTarget(Quin, tacticalContext)
				end
				if targetReason then
					Quin:SetAttribute("TargetReason", targetReason)
				end
				if selectedTarget then
					-- If target changed while actively in Fight state and next target is distant,
					-- enter TargetTransition to breathe, survey, and reset rather than robotic snapping
					if oldTargetName and oldTargetName ~= "" and oldTargetName ~= selectedTarget.Name and currentState.name == "Fight" then
						local sHRP = selectedTarget:FindFirstChild("HumanoidRootPart")
						local dist = sHRP and (sHRP.Position - rootPart.Position).Magnitude or 50
						if dist > (CombatConfig.CombatRange or 8) * 1.5 then
							Quin:SetAttribute("ForceState", "Idle")
						end
					end
					Quin:SetAttribute("CurrentTarget", selectedTarget.Name)
				end

				-- What it knows of its target right now, from its own contact record (Cognition:
				-- senses and memory), whatever state it is in: TargetHasLoS (it sees it) and
				-- TargetKnownBy (sight, touch, hearing, memory, report, rumour). Written here and
				-- nowhere else. (Target selection and ChaseState each wrote TargetHasLoS, and only
				-- on some paths: half the time a target was behind an obstacle it still said "seen".)
				local contact = selectedTarget and Cognition.contactFor(Quin, selectedTarget)
				local seen = contact ~= nil and contact.visible == true and contact.hasLineOfSight == true
				local knownBy = contact and (seen and "sight" or contact.channel or "memory") or nil
				if Quin:GetAttribute("TargetHasLoS") ~= seen then
					Quin:SetAttribute("TargetHasLoS", seen)
				end
				if Quin:GetAttribute("TargetKnownBy") ~= knownBy then
					Quin:SetAttribute("TargetKnownBy", knownBy)
				end
				
				-- 2. Track distressed ally for emergent rescue
				if tacticalContext.DistressedAlly then
					Quin:SetAttribute("DistressedAllyName", tacticalContext.DistressedAlly.Name)
				else
					Quin:SetAttribute("DistressedAllyName", "")
				end

				-- 3. Evaluate candidate action utilities biased by personality
				local distToTgt = (selectedTarget and selectedTarget:FindFirstChild("HumanoidRootPart"))
					and (selectedTarget.HumanoidRootPart.Position - rootPart.Position).Magnitude or 15

				local bestAction, tacticalState = DecisionSystem.evaluateAction(Quin, tacticalContext, distToTgt)
				Quin:SetAttribute("RecommendedAction", bestAction)
				Quin:SetAttribute("TacticalDecision", bestAction)

				-- 4. Decision-driven behavior override: wire the tactical decision into the FSM
				-- States a decision to retreat pulls the Quin out of: a fight, and a chase back
				-- into one (a Quin at 5% health used to flee, turn round and chase, eight times over)
				local isMeleeCommitted = (currentState.name == "Fight" or currentState.name == "Special" or currentState.name == "Chase")
				local nowClock = os.clock()

				if bestAction == "Retreat" and isMeleeCommitted and showdownRole ~= "Duelist" then
					local lastBreakoff = Quin:GetAttribute("LastRetreatBreakoff") or 0
					if (nowClock - lastBreakoff) >= (CombatConfig.RetreatBreakoffCooldown or 3.0) then
						Quin:SetAttribute("LastRetreatBreakoff", nowClock)
						Quin:SetAttribute("ForceState", "Retreat")
						RuntimeTracer.checkpoint(Quin, "Decision: Retreat (break off melee)")
					end
				elseif bestAction == "Pursue" and currentState.name == "Idle" then
					-- Recovery is not interrupted: it finishes the get-up and then picks its own next
					-- state. Forcing Chase from here cut the get-up clip after ~0.1s (prone -> sprint pop).
					if distToTgt > (CombatConfig.PursueEngageDistance or 20.0) then
						Quin:SetAttribute("ForceState", "Chase")
						RuntimeTracer.checkpoint(Quin, "Decision: Pursue (chase target)")
					end
				end

				-- 4. Emit emergent battle events telemetry
				BattleEventSystem.checkEvents(Quin, tacticalContext)
			end
		end

		-- Handle forced states from external forces (e.g., getting hit)
		local forceStateStr = Quin:GetAttribute("ForceState")

		local forceState = nil
		if forceStateStr and States[forceStateStr] then
			forceState = States[forceStateStr]
			Quin:SetAttribute("ForceState", nil)
		end
		
		local newState = forceState
		-- Under something lower than itself it cannot stand, wait or fight: it knows, and gets out
		-- to the nearest spot with room before its state does anything else (HeadroomAwareness).
		if not newState and STANDING_STATES[currentState.name] and CombatConfig.Headroom.Enabled ~= false and not isPiloted()
			and humanoid.FloorMaterial ~= Enum.Material.Air and not humanoid.PlatformStand
			and not LocomotionModule.isSliding(Quin) then
			local exit = HeadroomAwareness.exit(Quin, rootPart, humanoid)
			if exit then
				Quin:SetAttribute("LowCeiling", true)
				Quin:SetAttribute("ObstacleAwareness", "No room to stand: getting out")
				LocomotionModule.steer(Quin, humanoid, rootPart, exit, CombatConfig.Headroom.ExitSpeed, 0.1)
				GaitModule.update(humanoid, rootPart, 0.1)
				newState = currentState
			elseif Quin:GetAttribute("LowCeiling") then
				Quin:SetAttribute("LowCeiling", nil)
			end
		end
		-- At a rim with a drop beside it, it knows (NearEdge). Waiting there, or anywhere up on the
		-- arena wall, it walks in from the rim; fighting, chasing or holding high ground at an
		-- edge is its business (EdgeAwareness).
		if not newState and STANDING_STATES[currentState.name] and CombatConfig.EdgeAwareness.Enabled ~= false and not isPiloted()
			and humanoid.FloorMaterial ~= Enum.Material.Air and not humanoid.PlatformStand then
			local edge = EdgeAwareness.sense(Quin, rootPart, humanoid)
			if (edge ~= nil) ~= (Quin:GetAttribute("NearEdge") == true) then
				Quin:SetAttribute("NearEdge", edge and true or nil)
			end
			if edge and (currentState.name == "Idle" or (edge.surface.Name == "ArenaWall" and currentState.name ~= "Fight")) then
				Quin:SetAttribute("ObstacleAwareness", "At the edge: stepping in")
				local inside = rootPart.Position + edge.inward * CombatConfig.EdgeAwareness.StepIn
				LocomotionModule.steer(Quin, humanoid, rootPart, inside, CombatConfig.EdgeAwareness.StepSpeed, 0.1)
				GaitModule.update(humanoid, rootPart, 0.1)
				newState = currentState
			end
		elseif Quin:GetAttribute("NearEdge") then
			Quin:SetAttribute("NearEdge", nil)
		end
		if not newState and isPiloted() and not PILOT_STATES[currentState.name] then
			newState = States.Piloted
		end
		if not newState then
			local isDebugMode = workspace:GetAttribute("Debug_StateLabels") or false
			local ok, result = pcall(currentState.update, Quin, humanoid, rootPart, isDebugMode)
			if ok then
				newState = result
			else
				warn(string.format("[%s] State '%s' error: %s — falling back to Idle", Quin.Name, currentState.name, tostring(result)))
				newState = States.Idle
			end
		end

		
		if newState and isPiloted() and not PILOT_STATES[newState.name] then
			newState = States.Piloted
		elseif newState and not isPiloted() and newState.name == "Piloted" then
			newState = States.Idle -- (the player let go: the Quin's own decisions again)
		end
		if newState and newState ~= currentState then
			-- State Dwell Commitment Check: prevent rapid 100-300ms fluttering
			local isInterrupt = (forceState ~= nil)
				or (newState.name == "Knockback" or newState.name == "Death" or newState.name == "Recovery"
					or newState.name == "MidAirClash" or newState.name == "BeamStruggle" or newState.name == "ReEntry"
					-- committed moves lasting a second or more, gated by their own cooldowns; held
					-- back here, a hop onto a stepping stone waited 1.3 s and its spot request lapsed
					or newState.name == "ProjectileJump" or newState.name == "WallRun"
				or newState.name == "Piloted" or currentState.name == "Piloted")
			
			local dwellElapsed = os.clock() - stateStartTime
			local minDwell = 0
			if currentState.name == "Chase" then
				minDwell = CombatConfig.StateDwellMin_Chase or 0.8
			elseif currentState.name == "Retreat" then
				minDwell = CombatConfig.StateDwellMin_Retreat or 1.2
			elseif currentState.name == "Circling" then
				minDwell = CombatConfig.StateDwellMin_Circling or 1.0
			elseif currentState.name == "Fight" then
				minDwell = CombatConfig.StateDwellMin_Fight or 0.6
			end

			if isInterrupt or dwellElapsed >= minDwell then
				RuntimeTracer.checkpoint(Quin, string.format("Transition: %s → %s (dwell=%.2fs)", currentState.name, newState.name, dwellElapsed))
				if workspace:GetAttribute("Debug_StateLabels") then
					print(string.format("[%s] State changed: %s → %s (dwell=%.2fs)", Quin.Name, currentState.name, newState.name, dwellElapsed))
				end

				if currentState.exit then
					currentState.exit(Quin, humanoid, rootPart)
				end
				-- The outgoing state's steer goal must not keep driving the body into the new state
				LocomotionModule.cancelSteer(Quin)
				
				if newState.enter then
					newState.enter(Quin, humanoid, rootPart)
				end

				Quin:SetAttribute("CurrentState", newState.name)
				previousState = currentState
				currentState = newState
				stateStartTime = os.clock()
			end
		end

		-- OOB Safety: If they somehow clip through the floor or get launched out, just kill them so the spawner replaces them
		if rootPart.Position.Y < workspace.FallenPartsDestroyHeight + 50 then
			humanoid.Health = 0
		end

		local speedMult = workspace:GetAttribute("GameSpeedMultiplier") or 1.0
		-- (a state whose end has to be caught on time asks for a shorter tick: tickInterval)
		task.wait(math.clamp((currentState.tickInterval or 0.1) / speedMult, 0.015, 0.1))
	end
end)
