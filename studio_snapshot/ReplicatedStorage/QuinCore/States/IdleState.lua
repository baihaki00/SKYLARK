--// IdleState.lua
-- Guard stance idle, detects enemies (Quins, not players)
-- Single Source of Truth: ReplicatedStorage.QuinCore.AnimationConfig

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TargetingModule = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("TargetingModule"))
local AnimationModule = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("AnimationModule"))
local CombatConfig = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("CombatConfig"))
local LocomotionModule = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("LocomotionModule"))
local GaitModule = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("GaitModule"))
local Cognition = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Cognition"))
local Pace = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("Pace"))
local NavigationModule = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("NavigationModule"))

local IdleState = { name = "Idle" }

local idleData = {}
-- The spot it is walking to for a job, kept across states: when it was told of it (it looks
-- first, then goes), and whether it has got there (it stays put until the spot really moves)
local jobData = setmetatable({}, { __mode = "k" })

function IdleState.enter(fighter, humanoid, rootPart)
	LocomotionModule.brake(fighter, humanoid, rootPart, 0.05)
	-- Mid-combat this state is a 0.15-0.25s target-switch beat: the body keeps decelerating
	-- through the brake (see update) instead of stopping dead and pushing off again.
	if not (workspace:GetAttribute("MatchStarted") == true or fighter:GetAttribute("InCombat") == true) then
		humanoid.WalkSpeed = 0
	end
	-- The base idle floor picks the stance (default / ready / fight); forcing the default
	-- idle here swapped the stance clip on every pass through this state.
	AnimationModule.ensureBaseIdle(humanoid)

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
	-- The base idle is the permanent pose floor and is never stopped here: stopping it left
	-- the rig with no pose underneath for a few frames on every Idle -> Chase.
	local gyro = rootPart and rootPart:FindFirstChild("IdleGyro")
	if gyro then gyro:Destroy() end
	if humanoid then humanoid.AutoRotate = true end
	idleData[fighter] = nil
end

function IdleState.update(fighter, humanoid, rootPart, DEBUG)
	-- Respect-custom spectators must never enter idle or seek targets
	local showdownRole = fighter:GetAttribute("RespectRole")
	if require(game:GetService("ReplicatedStorage").QuinCore.Modules.SocialSystem).standsDown(fighter) then
		-- Walks where it decided to watch from, then stands and watches
		local SocialSystem = require(game:GetService("ReplicatedStorage").QuinCore.Modules.SocialSystem)
		if not SocialSystem.followMoveIntent(fighter, humanoid, rootPart, 0.1) then
			SocialSystem.watch(fighter, humanoid, rootPart, 0.1)
		end
		return IdleState
	end
	-- A place it decided to walk to (a leader's regroup, a respect custom): it goes there first
	if require(game:GetService("ReplicatedStorage").QuinCore.Modules.SocialSystem).followMoveIntent(fighter, humanoid, rootPart, 0.1) then
		return IdleState
	end

	-- Energy recovery while idle (the body does it when Body_StaminaByEffort is on: BodyStamina)
	if CombatConfig.Body_StaminaByEffort == false then
		local energy = fighter:GetAttribute("Energy") or 100
		local recovery = (CombatConfig.EnergyRecovery_Idle or 8) * 0.1
		fighter:SetAttribute("Energy", math.min(CombatConfig.MaxEnergy or 100, energy + recovery))
	end
	
	if game:GetService("Workspace"):GetAttribute("MatchStarted") == false then
		humanoid.WalkSpeed = 0
		local data = idleData[fighter]
		if data then data.matchStartTime = nil end
		return IdleState
	end

	-- A task with a place to go (TaskChoice: carry, guard, escort ...): walk there, and stand
	-- once there, unless an enemy it can see comes within reach of the job (ObjectiveEngage)
	local goTo = fighter:GetAttribute("ObjectiveGoTo")
	if typeof(goTo) == "Vector3" and workspace:GetServerTimeNow() <= (fighter:GetAttribute("ObjectiveUntil") or 0) then
		local engage = fighter:GetAttribute("ObjectiveEngage") or 16
		local threat = false
		for _, contact in ipairs(Cognition.knownEnemies(fighter) or {}) do
			if contact.visible and contact.distance <= engage then threat = true break end
		end
		if not threat then
			local job = jobData[fighter]
			local now = os.clock()
			local flat = Vector3.new(goTo.X - rootPart.Position.X, 0, goTo.Z - rootPart.Position.Z)
			-- A new spot (a new job, or the old spot moved well away): it takes it in first, head
			-- turned that way, then goes - quick for an alert Quin, slower for a dull one. Already
			-- on the move, it just bends its course.
			if not job or (Vector3.new(goTo.X, 0, goTo.Z) - Vector3.new(job.spot.X, 0, job.spot.Z)).Magnitude > 20 then
				local moving = rootPart.AssemblyLinearVelocity.Magnitude > 6
				job = { spot = goTo, arrived = false, goAt = now + ((moving or not Pace.enabled()) and 0 or Pace.reaction(fighter)) }
				jobData[fighter] = job
				if job.goAt > now then
					fighter:SetAttribute("LookPoint", goTo)
					fighter:SetAttribute("LookUntil", workspace:GetServerTimeNow() + (job.goAt - now) + 0.3)
				end
			end
			-- How fast the spot itself moves (a place beside a walking carrier): it keeps pace with it
			-- rather than running up, stopping, and running up again
			if job.spotAt and now - job.spotAt > 0.05 then
				local moved = Vector3.new(goTo.X - job.spot.X, 0, goTo.Z - job.spot.Z).Magnitude
				job.spotSpeed = (job.spotSpeed or 0) * 0.6 + (moved / (now - job.spotAt)) * 0.4
			end
			job.spot, job.spotAt = goTo, now
			local movingSpot = (job.spotSpeed or 0) > (CombatConfig.Pace_MovingSpotSpeed or 3)
			local settle = CombatConfig.Pace_SettleRadius or 3
			if job.arrived and flat.Magnitude > (CombatConfig.Pace_LeaveRadius or 7) then job.arrived = false end
			if not job.arrived and flat.Magnitude <= settle and not movingSpot then job.arrived = true end

			local face = fighter:GetAttribute("ObjectiveFace")
			local gyro = rootPart:FindFirstChild("IdleGyro")
			if job.arrived or now < job.goAt then
				LocomotionModule.brake(fighter, humanoid, rootPart, 0.1)
				AnimationModule.ensureBaseIdle(humanoid)
				-- on its post it faces the way it watches (a guard looks out, not at the Shrine), and
				-- turns to whatever it just heard behind it (Gaze: TurnTo)
				local turnTo = fighter:GetAttribute("TurnTo")
				if typeof(turnTo) == "Vector3" and workspace:GetServerTimeNow() <= (fighter:GetAttribute("TurnUntil") or 0) then
					face = turnTo
				end
				if job.arrived and typeof(face) == "Vector3" and rootPart.AssemblyLinearVelocity.Magnitude < 3 then
					if not gyro then
						gyro = Instance.new("AlignOrientation")
						gyro.Name = "IdleGyro"
						gyro.Mode = Enum.OrientationAlignmentMode.OneAttachment
						gyro.Attachment0 = rootPart:FindFirstChild("RootAttachment") or Instance.new("Attachment", rootPart)
						gyro.RigidityEnabled = false
						gyro.Responsiveness = 8
						gyro.MaxTorque = 100000
						gyro.MaxAngularVelocity = 4
						gyro.CFrame = rootPart.CFrame
						gyro.Parent = rootPart
					end
					gyro.CFrame = CFrame.lookAt(rootPart.Position, Vector3.new(face.X, rootPart.Position.Y, face.Z))
				elseif gyro then
					gyro:Destroy()
				end
			else
				if gyro then gyro:Destroy() end
				local cap = fighter:GetAttribute("ObjectiveSpeed") or 40
				local speed = cap
				if Pace.enabled() then
					speed = math.min(cap, (Pace.gear(fighter, fighter:GetAttribute("ObjectiveUrgency") or 1, fighter:GetAttribute("ObjectivePaceWhy"))))
					if movingSpot then
						speed = math.min(speed, job.spotSpeed + math.max(flat.Magnitude - settle, 0) * (CombatConfig.Pace_KeepUpGain or 0.8))
					else
						speed = Pace.arrive(speed, flat.Magnitude - settle)
					end
				end
				-- a wall between it and its spot: the way round (owner 2026-10-27, "why they just
				-- stands there": a Lantern carrier walked straight into a block, its escort behind it)
				local steerTo = Vector3.new(goTo.X, rootPart.Position.Y, goTo.Z)
				local jumpHere = false
				if now < (job.detourUntil or 0) or not NavigationModule.isClearTo(rootPart, steerTo) then
					local waypoint, jumpPoint = NavigationModule.detourWaypoint(fighter, rootPart, goTo)
					if waypoint then
						steerTo = Vector3.new(waypoint.X, rootPart.Position.Y, waypoint.Z)
						jumpHere = jumpPoint
					end
				end
				-- low cover across the way (waist high, the sweep above passes over it): hop it, and
				-- pushing on the spot a moment means something is in the way all the same: hop, and
				-- still stuck, the way round (a carrier stood against a low wall, owner 2026-10-27)
				local flatVel = Vector3.new(rootPart.AssemblyLinearVelocity.X, 0, rootPart.AssemblyLinearVelocity.Z).Magnitude
				local hopHeight = nil
				local rise = NavigationModule.lowObstacle(rootPart, humanoid, steerTo - rootPart.Position, 3 + flatVel * 0.25)
				if rise and rise >= (CombatConfig.Locomotion_StepHeight or 1.5) and rise <= (CombatConfig.Hurdle_MaxRise or 11) then
					hopHeight = rise + 2.5
				end
				-- (how far it really got since the last tick: steering writes the velocity, so a Quin
				-- shoving into a step still read as moving)
				local here = Vector3.new(rootPart.Position.X, 0, rootPart.Position.Z)
				local made = job.lastPos and (here - job.lastPos).Magnitude / math.max(now - job.lastAt, 0.03) or flatVel
				job.lastPos, job.lastAt = here, now
				if math.min(flatVel, made) < 1.5 and humanoid.MoveDirection.Magnitude > 0.5 then
					job.pushSince = job.pushSince or now
					if now - job.pushSince > 0.8 then hopHeight = hopHeight or 8 end
					if now - job.pushSince > 2 then job.detourUntil, job.pushSince = now + 4, nil end
				else
					job.pushSince = nil
				end
				if jumpHere then hopHeight = hopHeight or 7 end
				if hopHeight and now - (job.hopAt or 0) > 0.8 and LocomotionModule.isOnGround(rootPart, humanoid) then
					job.hopAt = now
					LocomotionModule.jump(fighter, humanoid, rootPart, hopHeight, math.max(flatVel, 14), "jump")
				end
				LocomotionModule.steer(fighter, humanoid, rootPart, steerTo, speed, 0.1)
			end
			GaitModule.update(humanoid, rootPart, 0.1)
			return IdleState
		end
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
		else
			LocomotionModule.brake(fighter, humanoid, rootPart, 0.1)
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
				gyro.MaxAngularVelocity = CombatConfig.Combat_FacingMaxTurnRate or 14 -- same cap as the Fight and Circling facing
				gyro.CFrame = rootPart.CFrame
				gyro.Parent = rootPart
			end
			gyro.CFrame = lookCF
		end
		
		TargetingModule.setTarget(fighter, target)
		
		-- Execute unique opening action if available (unblocked by arena spawn distance)
		if data.openingAction == "ProjectileJump" and CombatConfig.EnableProjectileJump and fighter:GetAttribute("EnableProjectileJump") ~= false then
			data.openingAction = nil
			fighter:SetAttribute("JumpWhy", "opening move") -- (JumpLog, team step 5)
			return require(script.Parent:WaitForChild("ProjectileJumpState"))
		elseif data.openingAction == "Dash" then
			data.openingAction = nil
			if targetHRP then
				fighter:SetAttribute("JumpWhy", "opening dash") -- (JumpLog, team step 5)
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
