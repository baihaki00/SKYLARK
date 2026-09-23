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
	
	rootPart:SetNetworkOwner(nil) -- Server owns movement
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
	Special = require(statesFolder:WaitForChild("SpecialState")),
	Death = require(statesFolder:WaitForChild("DeathState")),
	ProjectileJump = require(statesFolder:WaitForChild("ProjectileJumpState")),
	MidAirClash = require(statesFolder:WaitForChild("MidAirClashState")),
	ProjectileFight = require(statesFolder:WaitForChild("ProjectileFightState")),
	Interception = require(statesFolder:WaitForChild("InterceptionState")),
	ReEntry = require(statesFolder:WaitForChild("ReEntryState")),
	WallRun = require(statesFolder:WaitForChild("WallRunState")),
	LeaderShowdown = require(statesFolder:WaitForChild("LeaderShowdownState")),
	BeamStruggle = require(statesFolder:WaitForChild("BeamStruggleState")),
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
local GHOSTMODE = true

local currentState = States.Idle
local previousState = nil

-- Init State
Quin:SetAttribute("CurrentState", currentState.name)
if Quin:GetAttribute("Energy") == nil then
	Quin:SetAttribute("Energy", CombatConfig.MaxEnergy or 100)
end
if currentState.enter then
	currentState.enter(Quin, humanoid, rootPart)
end

-- === GHOSTMODE: Hide server AI visuals ===
if GHOSTMODE then
	for _, part in ipairs(Quin:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Transparency = 1
			part.CastShadow = false
		elseif part:IsA("Decal") or part:IsA("Texture") then
			part.Transparency = 1
		end
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

-- === FOOTSTEP GENERATOR (ANIMATION MARKER DRIVEN) ===
local FOOTSTEP_BASE_VOLUME = 0.01   -- Adjust to taste
local FOOTSTEP_MIN_VOLUME = 0.005   -- Adjust to taste
local FOOTSTEP_MAX_VOLUME = 0.02    -- Adjust to taste

-- IDs that should throttle footstep pacing (longer cooldown between steps)
local SLOW_PACE_IDS = {
	["rbxassetid://123318024844911"] = true,
	["rbxassetid://107962284182266"] = true,
}
local SLOW_PACE_COOLDOWN = 0.35 -- seconds between footsteps for these IDs

local function setupFootstepEvents(hum)
	local animator = hum:FindFirstChildOfClass("Animator") or hum:WaitForChild("Animator", 5)
	if not animator then return end

	local lastFootstepTime = 0

	-- Listen for any animation playing
	animator.AnimationPlayed:Connect(function(track)
		-- Listen for the "Footstep" marker on this specific track
		track:GetMarkerReachedSignal("Footstep"):Connect(function()
			local animId = track.Animation and track.Animation.AnimationId or ""
			local now = os.clock()

			-- Throttle pacing for specific IDs
			if SLOW_PACE_IDS[animId] then
				if (now - lastFootstepTime) < SLOW_PACE_COOLDOWN then
					return -- skip, too soon
				end
			end
			lastFootstepTime = now

			local speed = hum.Parent.PrimaryPart.AssemblyLinearVelocity.Magnitude
			local volume = math.clamp(FOOTSTEP_BASE_VOLUME, FOOTSTEP_MIN_VOLUME, FOOTSTEP_MAX_VOLUME)
			AudioModule.playFootstep(hum.Parent, volume)
		end)
	end)
end

task.spawn(function()
	if enableAI and humanoid then
		setupFootstepEvents(humanoid)
	end
end)

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
		
		local success, err = pcall(function()
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
		end)
		if not success then
			stateGui.Text = "[ STATE: " .. (Quin:GetAttribute("CurrentState") or "None") .. " ]"
			warn("Debug UI error:", err)
		end
		
		task.wait(0.03)
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
		-- === Arena Safety Net & Cinematic Re-Entry ===
		if rootPart then
			-- === Leader Showdown Authoritative Ring Enforcement ===
			local showdownRole = Quin:GetAttribute("LeaderShowdownRole")
			if showdownRole == "Duelist" then
				local LeaderShowdownSystem = require(QuinCore:WaitForChild("Modules"):WaitForChild("LeaderShowdownSystem"))
				LeaderShowdownSystem.constrainToRing(rootPart)
			end

			local isOob = SpatialModule.isOutOfBounds(rootPart)
			local curStateName = currentState and currentState.name or ""

			if isOob and curStateName ~= "ReEntry" and curStateName ~= "Death" then
				local pos = rootPart.Position
				local bounds = SpatialModule.getArenaBounds()
				if math.abs(pos.X) > (bounds.halfX + 80) or math.abs(pos.Z) > (bounds.halfZ + 80) or pos.Y < -5 then
					print(string.format("[SafetyNet] %s in deep void/fallen (%.1f, %.1f, %.1f) - emergency teleport to arena.", Quin.Name, pos.X, pos.Y, pos.Z))
					Quin:PivotTo(CFrame.new(bounds.center.X, 7.5, bounds.center.Z))
					rootPart.AssemblyLinearVelocity = Vector3.zero
					Quin:SetAttribute("OobGroundedTime", 0)
				else
					-- Not tumbling in severe knockback
					local isTumbling = (curStateName == "Knockback") or (math.abs(rootPart.AssemblyLinearVelocity.Y) > 35)
					if not isTumbling then
						local oobTime = (Quin:GetAttribute("OobGroundedTime") or 0) + 0.1
						Quin:SetAttribute("OobGroundedTime", oobTime)
						if oobTime >= 1.0 then
							print(string.format("[SafetyNet] %s outside arena for %.1fs - triggering Cinematic ReEntry!", Quin.Name, oobTime))
							Quin:SetAttribute("ForceState", "ReEntry")
							Quin:SetAttribute("OobGroundedTime", 0)
						end
					end
				end
			else
				Quin:SetAttribute("OobGroundedTime", 0)
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
			local sdRole = Quin:GetAttribute("LeaderShowdownRole")
			local isShowdownSpectator = (sdRole == "PerimeterGuard" or sdRole == "Transition")
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
				local isShowdown = (workspace:GetAttribute("LeaderShowdownActive") == true) or (Quin:GetAttribute("LeaderShowdownRole") ~= nil)
				local isAirState = (currentState.name == "Knockback" or currentState.name == "Airborne"
					or currentState.name == "ProjectileJump"
					or currentState.name == "MidAirClash" or currentState.name == "BeamStruggle"
					or currentState.name == "Recovery"
					or currentState.name == "ReEntry" or currentState.name == "LeaderShowdown")
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
						if flatDist < 3.5 and yDiff > 2.0 and yDiff < 10 then
							local pushDir = Vector3.new(oPos.X - myPos.X, 0, oPos.Z - myPos.Z)
							if pushDir.Magnitude < 0.01 then
								pushDir = Vector3.new(math.random() - 0.5, 0, math.random() - 0.5)
							end
							pushDir = pushDir.Unit
							oHRP:PivotTo(CFrame.new(oPos + pushDir * 3.5))
							oHRP.AssemblyLinearVelocity = Vector3.new(pushDir.X * 40, 12, pushDir.Z * 40)
						end
					end
				end
			end
		end

		-- === Tactical Perception & Emergent Decision Layer ===
		local showdownRole = Quin:GetAttribute("LeaderShowdownRole")
		local isShowdownPerimeter = (showdownRole == "PerimeterGuard" or showdownRole == "Transition")
		local isBeamStruggling = (currentState.name == "BeamStruggle")

		if not isShowdownPerimeter and not isBeamStruggling and rootPart and humanoid.Health > 0 then
			local tacticalContext = TacticalPerception.evaluate(Quin)
			if tacticalContext then
				-- 1. Utility-based target selection & switching
				local oldTargetName = Quin:GetAttribute("CurrentTarget")
				local selectedTarget, targetScore, targetReason = TargetingModule.selectTarget(Quin, tacticalContext)
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
				local isMeleeCommitted = (currentState.name == "Fight" or currentState.name == "Special")
				local nowClock = os.clock()

				if bestAction == "Retreat" and isMeleeCommitted and showdownRole ~= "Duelist" then
					local lastBreakoff = Quin:GetAttribute("LastRetreatBreakoff") or 0
					if (nowClock - lastBreakoff) >= (CombatConfig.RetreatBreakoffCooldown or 3.0) then
						Quin:SetAttribute("LastRetreatBreakoff", nowClock)
						Quin:SetAttribute("ForceState", "Retreat")
						RuntimeTracer.checkpoint(Quin, "Decision: Retreat (break off melee)")
					end
				elseif bestAction == "Pursue" and (currentState.name == "Idle" or currentState.name == "Recovery") then
					if distToTgt > (CombatConfig.PursueEngageDistance or 20.0) then
						Quin:SetAttribute("ForceState", "Chase")
						RuntimeTracer.checkpoint(Quin, "Decision: Pursue (chase target)")
					end
				end

				-- 4. Emit emergent battle events telemetry
				BattleEventSystem.checkEvents(Quin, tacticalContext)
			end
		end

		-- Handle forced states from external forces (e.g., getting hit or LeaderShowdown)
		local forceStateStr = Quin:GetAttribute("ForceState")
		if isShowdownPerimeter then
			if currentState.name ~= "LeaderShowdown" then
				forceStateStr = "LeaderShowdown"
			else
				forceStateStr = nil
				Quin:SetAttribute("ForceState", nil)
			end
		elseif not forceStateStr and Quin:GetAttribute("CurrentState") == "LeaderShowdown" and currentState.name ~= "LeaderShowdown" then
			forceStateStr = "LeaderShowdown"
		elseif not forceStateStr and showdownRole == "Duelist" and Quin:GetAttribute("CurrentState") == "Fight" and currentState.name == "LeaderShowdown" then
			forceStateStr = "Fight"
		end

		local forceState = nil
		if forceStateStr and States[forceStateStr] then
			forceState = States[forceStateStr]
			Quin:SetAttribute("ForceState", nil)
		end
		
		local newState = forceState
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

		if isShowdownPerimeter and newState and newState.name ~= "LeaderShowdown" then
			newState = States.LeaderShowdown
		end
		
		if newState and newState ~= currentState then
			RuntimeTracer.checkpoint(Quin, string.format("Transition: %s → %s", currentState.name, newState.name))
			if workspace:GetAttribute("Debug_StateLabels") then
				print(string.format("[%s] State changed: %s â†’ %s", Quin.Name, currentState.name, newState.name))
			end

			if currentState.exit then
				currentState.exit(Quin, humanoid, rootPart)
			end
			
			if newState.enter then
				newState.enter(Quin, humanoid, rootPart)
			end

			Quin:SetAttribute("CurrentState", newState.name)
			previousState = currentState
			currentState = newState
		end

		-- OOB Safety: If they somehow clip through the floor or get launched out, just kill them so the spawner replaces them
		if rootPart.Position.Y < workspace.FallenPartsDestroyHeight + 50 then
			humanoid.Health = 0
		end

		local speedMult = workspace:GetAttribute("GameSpeedMultiplier") or 1.0
		task.wait(math.clamp(0.1 / speedMult, 0.015, 0.1))
	end
end)
