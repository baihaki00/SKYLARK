--// IdleState.lua
-- Guard stance idle, detects enemies (Quins, not players)
-- Single Source of Truth: ReplicatedStorage.QuinCore.AnimationConfig

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TargetingModule = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("TargetingModule"))
local AnimationModule = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("AnimationModule"))
local CombatConfig = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("CombatConfig"))
local LocomotionModule = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("LocomotionModule"))

local IdleState = { name = "Idle" }

local idleData = {}

function IdleState.enter(fighter, humanoid, rootPart)
	LocomotionModule.brake(fighter, humanoid, rootPart, 0.05)
	humanoid.WalkSpeed = 0
	AnimationModule.playConfig(humanoid, "Movement.Idle")

	local aggression = fighter:GetAttribute("Pers_Aggression") or 0.6
	local confidence = fighter:GetAttribute("Pers_Confidence") or 0.6

	local isMatchInProgress = (workspace:GetAttribute("MatchStarted") == true)
	local inCombat = (fighter:GetAttribute("InCombat") == true)
	local speedMult = workspace:GetAttribute("GameSpeedMultiplier") or 1.0
	local energy = fighter:GetAttribute("Energy") or 100
	local reactionDelay = 1.5 / speedMult
	local openingAction = "Run"

	if isMatchInProgress or inCombat then
		-- Mid-combat survey: quick micro-pause (0.15s - 0.25s) with fluid stance, NEVER freezing WalkSpeed to 0
		reactionDelay = (math.random(15, 25) / 100) / speedMult
		openingAction = "Run"
	else
		-- Calculate individual reaction delay upon match start (3 distinct cinematic Avengers waves)
		-- Wave 1: Berserkers / Vanguard explode out immediately (0.0s - 0.4s) into dashes/sprints
		-- Wave 2: Main assault force charges after 1.2s - 2.0s with athletic sprint
		-- Wave 3: Heavy anchors & strategists hold stance for 2.8s - 4.2s, then stride forward confidently
		if aggression > 0.72 then
			reactionDelay = (math.random() * 0.4) / speedMult
			local roll = math.random()
			if roll < 0.45 and energy >= (CombatConfig.DashMinEnergy or 20) then
				openingAction = "Dash"
			else
				openingAction = "Run"
			end
		elseif aggression < 0.48 or confidence < 0.45 then
			reactionDelay = (2.8 + math.random() * 1.4) / speedMult
			openingAction = "ConfidentWalk"
		else
			reactionDelay = (1.2 + math.random() * 0.8) / speedMult
			openingAction = (math.random() > 0.25) and "Run" or "ConfidentWalk"
		end
	end

	idleData[fighter] = {
		reactionDelay = reactionDelay,
		openingAction = openingAction,
		matchStartTime = nil,
		isMidCombat = (isMatchInProgress or inCombat),
	}
end

function IdleState.exit(fighter, humanoid, rootPart)
	AnimationModule.stopConfig(humanoid, "Movement.Idle")
	local gyro = rootPart and rootPart:FindFirstChild("IdleGyro")
	if gyro then gyro:Destroy() end
	idleData[fighter] = nil
end

function IdleState.update(fighter, humanoid, rootPart, DEBUG)
	-- Showdown perimeter spectators must never enter idle or seek targets
	local showdownRole = fighter:GetAttribute("LeaderShowdownRole")
	if showdownRole == "PerimeterGuard" or showdownRole == "Transition" then
		return require(script.Parent:WaitForChild("LeaderShowdownState"))
	end

	-- Energy recovery while idle
	local energy = fighter:GetAttribute("Energy") or 100
	local recovery = (CombatConfig.EnergyRecovery_Idle or 8) * 0.1
	fighter:SetAttribute("Energy", math.min(CombatConfig.MaxEnergy or 100, energy + recovery))
	
	if game:GetService("Workspace"):GetAttribute("MatchStarted") == false then
		humanoid.WalkSpeed = 0
		local data = idleData[fighter]
		if data then data.matchStartTime = nil end
		return IdleState
	end

	local data = idleData[fighter]
	if not data then
		data = { reactionDelay = 0.2, openingAction = "Run", matchStartTime = tick(), isMidCombat = true }
		idleData[fighter] = data
	end

	if not data.matchStartTime then
		data.matchStartTime = tick()
	end

	-- Staged Reaction Delay (Avengers opening cadence only when NOT in active combat)
	local timeSinceStart = tick() - data.matchStartTime
	if timeSinceStart < data.reactionDelay then
		if not data.isMidCombat then
			humanoid.WalkSpeed = 0
		end
		return IdleState
	end

	local target, distance = TargetingModule.getNearest(rootPart, CombatConfig.ChaseRange or 1000)
	
	if target then
		local targetHRP = target:FindFirstChild("HumanoidRootPart")
		if targetHRP then
			-- Smooth face target via AlignOrientation (Authoritative physics torque, zero CFrame snapping)
			local lookCF = CFrame.lookAt(rootPart.Position, Vector3.new(targetHRP.Position.X, rootPart.Position.Y, targetHRP.Position.Z))
			local gyro = rootPart:FindFirstChild("IdleGyro")
			if not gyro then
				gyro = Instance.new("AlignOrientation")
				gyro.Name = "IdleGyro"
				gyro.Mode = Enum.OrientationAlignmentMode.OneAttachment
				local att = rootPart:FindFirstChild("RootAttachment") or Instance.new("Attachment", rootPart)
				att.Name = "RootAttachment"
				gyro.Attachment0 = att
				gyro.RigidityEnabled = false
				gyro.Responsiveness = 15
				gyro.MaxTorque = 100000
				gyro.CFrame = rootPart.CFrame
				gyro.Parent = rootPart
			end
			gyro.CFrame = lookCF
		end
		
		TargetingModule.setTarget(fighter, target)
		
		-- Execute unique opening action if available (unblocked by arena spawn distance)
		if data.openingAction == "ProjectileJump" and CombatConfig.EnableProjectileJump then
			data.openingAction = nil
			return require(script.Parent:WaitForChild("ProjectileJumpState"))
		elseif data.openingAction == "Dash" then
			data.openingAction = nil
			if targetHRP then
				LocomotionModule.dash(fighter, humanoid, rootPart, targetHRP.Position, distance)
			end
			return require(script.Parent:WaitForChild("ChaseState"))
		elseif data.openingAction == "ConfidentWalk" then
			data.openingAction = nil
			fighter:SetAttribute("InitialPacingOverride", "ConfidentWalk")
			return require(script.Parent:WaitForChild("ChaseState"))
		end

		local combatRange = CombatConfig.CombatRange or 8
		if distance > combatRange * 2.5 then
			if DEBUG then print("[Idle] Enemy detected, chasing") end
			return require(script.Parent:WaitForChild("ChaseState"))
		elseif distance > combatRange * 1.2 then
			if DEBUG then print("[Idle] Enemy at standoff, circling") end
			return require(script.Parent:WaitForChild("CirclingState"))
		else
			if DEBUG then print("[Idle] Enemy in range, fighting") end
			return require(script.Parent:WaitForChild("FightState"))
		end
	end
	
	humanoid.WalkSpeed = 0
	humanoid:MoveTo(rootPart.Position)
	return IdleState
end

return IdleState
