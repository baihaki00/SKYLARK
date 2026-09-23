--// CirclingState.lua
-- The Standoff. Tension builds before a massive strike.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")

local TargetingModule = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("TargetingModule"))
local AnimationModule = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("AnimationModule"))
local AnimationIds = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("AnimationIds"))
local CombatConfig = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("CombatConfig"))
local SpatialModule = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("SpatialModule"))
local LocomotionModule = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("LocomotionModule"))
local RuntimeTracer = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("RuntimeTracer"))
local BattleEventSystem = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("BattleEventSystem"))

local CirclingState = { name = "Circling" }

-- ==========================================
-- 🛠️ ANIMATION TEST MODE CONFIGURATION 🛠️
-- ==========================================
local TEST_MODE_ACTIVE = false -- Set to true to make them circle infinitely for debugging
local STRAFE_RADIUS = 30.0    -- The ideal distance they try to maintain while circling
local INWARD_PULL = 0.6       -- How strongly they pull inwards (0.0 = perfect circle, 1.0 = spiral inwards)
local FACE_SPEED = 0.7        -- How fast they rotate to face each other (0.1 = slow, 1.0 = instant)
local STRAFE_SPEED_MULT = 0.41 -- Physical speed multiplier (1.0 = sprint speed, 0.4 = walk)
-- ==========================================

local circlingData = {}

function CirclingState.enter(fighter, humanoid, rootPart)
	local dir = math.random() > 0.5 and 1 or -1
	local tensionRoll = math.random()
	local tension = "walk"
	if tensionRoll > 0.8 then tension = "run"
	elseif tensionRoll < 0.3 then tension = "tired" end

	local aggression = fighter:GetAttribute("Pers_Aggression") or 0.6
	local mobility = fighter:GetAttribute("Pers_MobilityPreference") or 0.6
	local confidence = fighter:GetAttribute("Pers_Confidence") or 0.6

	-- Personality-driven duration and radius
	local duration = 3.0
	local idealRadius = STRAFE_RADIUS
	if aggression > 0.70 then
		idealRadius = 16.0 + math.random() * 6.0 -- Tight circle (16 - 22)
		duration = 1.4 + math.random() * 1.2    -- Quick snap (1.4 - 2.6s)
	elseif aggression < 0.45 or confidence < 0.45 then
		idealRadius = 28.0 + math.random() * 8.0 -- Wide standoff (28 - 36)
		duration = 3.5 + math.random() * 2.0    -- Long standoff (3.5 - 5.5s)
	else
		idealRadius = 22.0 + math.random() * 8.0
		duration = 2.2 + math.random() * 1.8
	end

	local now = tick()
	circlingData[fighter] = {
		enterTime = now,
		duration = duration,
		direction = dir,
		tension = tension,
		hasSnapped = false,
		currentAnim = nil,
		idealRadius = idealRadius,
		nextFeintTime = now + (1.2 + math.random() * 1.6),
	}
	
	RuntimeTracer.checkpoint(fighter, string.format("Enter Circling (Tension=%s)", tension))
	
	AnimationModule.stop(humanoid, AnimationIds.Run)
	AnimationModule.stop(humanoid, AnimationIds.Jump)
	AnimationModule.stop(humanoid, AnimationIds.Fall)
	AnimationModule.stopCategory(humanoid, "Attacks", 0)
	AnimationModule.stopCategory(humanoid, "Reactions", 0)
	
	-- Strict Exclusivity: Immediately halt any lingering tracks with priority higher than Movement (Action, Action2, Action3, Action4)
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if animator then
		for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
			if track.Priority ~= Enum.AnimationPriority.Idle and track.Priority ~= Enum.AnimationPriority.Movement then
				track:Stop(0)
			end
		end
	end
	
	-- Pick animation
	local animId = AnimationIds.StrafeRightWalk
	if dir == 1 then -- Right
		if tension == "run" then animId = AnimationIds.StrafeRightRun
		elseif tension == "walk" then animId = AnimationIds.StrafeRightWalk
		else animId = AnimationIds.StrafeRightTired end
	else -- Left
		if tension == "run" then animId = AnimationIds.StrafeLeftRun
		elseif tension == "walk" then animId = AnimationIds.StrafeLeftWalk
		else animId = AnimationIds.StrafeLeftTired end
	end
	
	circlingData[fighter].currentAnim = animId
	
	local speed = fighter:GetAttribute("Speed") or 40
	if tension == "run" then
		humanoid.WalkSpeed = speed * 0.6
	elseif tension == "walk" then
		humanoid.WalkSpeed = speed * STRAFE_SPEED_MULT
	else
		humanoid.WalkSpeed = speed * 0.2
	end
	
	-- Prevent Roblox from auto-rotating so we can control facing manually without jitter
	humanoid.AutoRotate = false
	
	local alignOri = rootPart:FindFirstChild("CirclingGyro")
	if not alignOri then
		alignOri = Instance.new("AlignOrientation")
		alignOri.Name = "CirclingGyro"
		alignOri.Mode = Enum.OrientationAlignmentMode.OneAttachment
		local att = rootPart:FindFirstChild("RootAttachment") or Instance.new("Attachment", rootPart)
		att.Name = "RootAttachment"
		alignOri.Attachment0 = att
		alignOri.RigidityEnabled = false
		alignOri.Responsiveness = 15 -- Gentle, physics-friendly rotation (was 40 -> caused spin-in-place fighting MoveTo)
		alignOri.MaxTorque = 100000 -- Reduced from 1e6 to stop the AlignOrientation from whipping the rootPart around
		alignOri.CFrame = rootPart.CFrame
		alignOri.Parent = rootPart
	end
	
	-- Play guard/idle animation
	AnimationModule.play(humanoid, animId, Enum.AnimationPriority.Movement, true, 1.0, 0.3)
end

function CirclingState.exit(fighter, humanoid, rootPart)
	RuntimeTracer.checkpoint(fighter, "Exit Circling")
	local data = circlingData[fighter]
	if data and data.currentAnim then
		AnimationModule.stop(humanoid, data.currentAnim, 0.15)
	end
	humanoid.AutoRotate = true
	local alignOri = rootPart:FindFirstChild("CirclingGyro")
	if alignOri then alignOri:Destroy() end
	circlingData[fighter] = nil
end

function CirclingState.update(fighter, humanoid, rootPart, DEBUG)
	-- Showdown perimeter spectators must never circle
	local showdownRole = fighter:GetAttribute("LeaderShowdownRole")
	if showdownRole == "PerimeterGuard" or showdownRole == "Transition" then
		return require(script.Parent:WaitForChild("LeaderShowdownState"))
	end

	-- Showdown Ring Containment & Jump Suppression
	local inShowdown = (workspace:GetAttribute("LeaderShowdownActive") == true) or (showdownRole ~= nil)
	if inShowdown then
		humanoid.UseJumpPower = true
		humanoid.JumpPower = 0
		humanoid.JumpHeight = 0
		local LeaderShowdownSystem = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("LeaderShowdownSystem"))
		LeaderShowdownSystem.constrainToRing(rootPart)
	end

	local data = circlingData[fighter]
	if not data then return require(script.Parent:WaitForChild("FightState")) end

	-- Prone / Cockroach protection: if flat on ground, immediately recover
	local upY = rootPart.CFrame.UpVector.Y
	if upY < 0.6 and SpatialModule.isGrounded(rootPart) then
		fighter:SetAttribute("KnockbackType", "hard_ground")
		return require(script.Parent:WaitForChild("RecoveryState"))
	end
	
	-- Mana / Energy recovery while pacing & circling
	local speedMult = workspace:GetAttribute("GameSpeedMultiplier") or 1.0
	local energy = fighter:GetAttribute("Energy") or 100
	local recovery = (CombatConfig.EnergyRecovery_Walk or 15) * 0.1 * speedMult
	fighter:SetAttribute("Energy", math.min(CombatConfig.MaxEnergy or 100, energy + recovery))
	
	local target, distance = TargetingModule.getNearest(rootPart, CombatConfig.ChaseRange)
	
	if not target or not target:FindFirstChild("HumanoidRootPart") then
		return require(script.Parent:WaitForChild("IdleState"))
	end
	
	local targetHRP = target:FindFirstChild("HumanoidRootPart")
	local targetState = target:GetAttribute("CurrentState")
	
	-- Continuous track exclusivity: ensure only strafe and background idle can play
	if data.currentAnim and not AnimationModule.isPlaying(humanoid, data.currentAnim) then
		AnimationModule.play(humanoid, data.currentAnim, Enum.AnimationPriority.Movement, true, 1.0, 0.2)
	end
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if animator then
		for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
			if track.Priority ~= Enum.AnimationPriority.Idle and track.Priority ~= Enum.AnimationPriority.Movement then
				track:Stop(0)
			end
		end
	end
	
	-- Snap condition 0: Opponent broke the standoff to fight!
	if targetState == "Fight" or targetState == "Dash" or targetState == "Special" then
		if DEBUG then print("[Circling] Opponent attacked! FIGHT!") end
		return require(script.Parent:WaitForChild("FightState"))
	end
	
	-- Snap condition 1: Time's up!
	-- Snap condition 2: Enemy got too close (below minimum circling range)
	-- Snap condition 3: Enemy moved too far away
	local minCircleRange = (CombatConfig.CombatRange or 8) * 0.7
	local maxCircleRange = (CombatConfig.CombatRange or 8) * 4.5 -- Increased to allow wider circling
	local isTargetDown = (targetState == "Knockback" or targetState == "Airborne")
	
	if not TEST_MODE_ACTIVE and not isTargetDown then
		if (tick() - data.enterTime) >= data.duration or distance < minCircleRange or distance > maxCircleRange then
			if not data.hasSnapped then
				data.hasSnapped = true
				if DEBUG then print("[Circling] Tension snapped! FIGHT!") end
				
				-- 50% chance to burst dash, then fight
				local dashMin = CombatConfig.DashMinDistance or 10
				local dashMax = CombatConfig.DashMaxDistance or 28
				if math.random() > 0.5 and distance >= dashMin and distance <= dashMax and targetHRP then
					LocomotionModule.dash(fighter, humanoid, rootPart, targetHRP.Position, distance)
				end
				return require(script.Parent:WaitForChild("FightState"))
			end
		end
	end

	local now = tick()
	local mobility = fighter:GetAttribute("Pers_MobilityPreference") or 0.6

	-- Dynamic Strafe Reversals & Martial Arts Feints (Agile fighters change strafe direction)
	if data.nextFeintTime and now >= data.nextFeintTime and not isTargetDown then
		if mobility > 0.58 and math.random() < 0.65 then
			data.direction = -data.direction
			local oldAnim = data.currentAnim
			local newAnim = (data.direction == 1)
				and ((data.tension == "run") and AnimationIds.StrafeRightRun or ((data.tension == "walk") and AnimationIds.StrafeRightWalk or AnimationIds.StrafeRightTired))
				or ((data.tension == "run") and AnimationIds.StrafeLeftRun or ((data.tension == "walk") and AnimationIds.StrafeLeftWalk or AnimationIds.StrafeLeftTired))
			data.currentAnim = newAnim
			if oldAnim and oldAnim ~= newAnim then
				AnimationModule.stop(humanoid, oldAnim, 0.15)
				AnimationModule.play(humanoid, newAnim, Enum.AnimationPriority.Movement, true, 1.0, 0.2)
			end
			data.nextFeintTime = now + (1.6 + math.random() * 2.2)
			BattleEventSystem.emit("FeintStrafe", { Model = fighter, TargetName = target.Name })
		else
			data.nextFeintTime = now + (2.0 + math.random() * 2.0)
		end
	end
	
	-- Circling Math (Strafe around target)
	local toTarget = (targetHRP.Position - rootPart.Position)
	local rightVector = toTarget:Cross(Vector3.new(0, 1, 0)).Unit * data.direction
	
	-- Stay roughly at ideal circling distance (scaled by personality)
	local idealDistance = isTargetDown and 25.0 or (data.idealRadius or STRAFE_RADIUS)
	local distanceError = math.clamp((distance - idealDistance) * 0.1, -1.0, 1.0)
	local inwardVector = toTarget.Unit * distanceError
	
	local moveDirection = (rightVector + inwardVector).Unit

	-- Tactical Flanking (Pincer Maneuver): if an ally is already engaging the target in front, flank around
	local myTeam = fighter:GetAttribute("Team")
	if myTeam then
		local forwardDir = targetHRP.CFrame.LookVector
		local toMe = (rootPart.Position - targetHRP.Position).Unit
		if forwardDir:Dot(toMe) > 0.2 then
			local allyCountInFront = 0
			for _, otherQuin in ipairs(game:GetService("CollectionService"):GetTagged("Quin")) do
				if otherQuin ~= fighter and otherQuin:GetAttribute("Team") == myTeam and otherQuin.Parent then
					local oHRP = otherQuin:FindFirstChild("HumanoidRootPart")
					if oHRP and (oHRP.Position - targetHRP.Position).Magnitude < 20 then
						local allyToTarget = (oHRP.Position - targetHRP.Position).Unit
						if forwardDir:Dot(allyToTarget) > 0.2 then
							allyCountInFront = allyCountInFront + 1
						end
					end
				end
			end
			if allyCountInFront >= 1 then
				local flankOffset = rightVector * 1.5 - forwardDir * 0.8
				moveDirection = (moveDirection + flankOffset.Unit * 0.85).Unit
			end
		end
	end

	local centerPull = SpatialModule.getArenaCenterPull(rootPart)

	-- Tactical state modulation (Disengagement / Rescue / Reposition)
	local tacticalState = fighter:GetAttribute("TacticalState")
	if tacticalState == "RETREATING" then
		-- Phase 3: Intelligent Safe Haven Retreat using radial evaluation
		local CollectionService = game:GetService("CollectionService")
		local myTeam = fighter:GetAttribute("Team")
		local enemies = {}
		local allies = {}
		for _, quin in ipairs(CollectionService:GetTagged("Quin")) do
			if quin ~= fighter and quin.Parent and quin:FindFirstChild("HumanoidRootPart") then
				local qTeam = quin:GetAttribute("Team")
				local qHum = quin:FindFirstChildOfClass("Humanoid")
				if qHum and qHum.Health > 0 then
					if qTeam ~= myTeam then
						table.insert(enemies, quin)
					else
						table.insert(allies, quin)
					end
				end
			end
		end

		local retreatResult = SpatialModule.getSafeRetreatDirection(rootPart, enemies, allies, CombatConfig)
		local safeDir = retreatResult.direction
		local retreatScore = retreatResult.score
		local isCornered = retreatResult.isCornered

		fighter:SetAttribute("RetreatScore", math.round(retreatScore * 100) / 100)
		fighter:SetAttribute("IsCornered", isCornered)

		if isCornered then
			-- Cornered beast: no safe retreat available
			local aggression = fighter:GetAttribute("Pers_Aggression") or 0.6
			local corneredThreshold = CombatConfig.CorneredCounterThreshold or 0.65
			local meleeRange = (CombatConfig.CombatRange or 8) * 2.0
			if aggression >= corneredThreshold and distance <= meleeRange then
				-- Aggressive fighter in melee proximity: desperate counter-strike instead of futile retreat
				fighter:SetAttribute("DesperateCounter", true)
				return require(script.Parent:WaitForChild("FightState"))
			end
			-- Less aggressive or enemy too far: still try to move in best available direction
		end

		-- Blend safe haven direction with slight inward pull to maintain circling feel
		moveDirection = (safeDir * 1.5 + (centerPull.Magnitude > 0.1 and centerPull.Unit or Vector3.zero) * 0.3).Unit
	elseif tacticalState == "RESCUING" then
		local distAllyName = fighter:GetAttribute("DistressedAllyName")
		if distAllyName and distAllyName ~= "" then
			local dAlly = workspace:FindFirstChild(distAllyName) or (workspace:FindFirstChild("QuinServer") and workspace.QuinServer:FindFirstChild(distAllyName))
			if dAlly and dAlly:FindFirstChild("HumanoidRootPart") then
				local toAlly = (dAlly.HumanoidRootPart.Position - rootPart.Position).Unit
				moveDirection = (toAlly * 1.4 + rightVector * 0.4).Unit
			end
		end
	end
	
	-- Edge detection & Center Bias
	local nearEdge, awayDir = SpatialModule.isNearArenaEdge(rootPart, 15) -- Increased edge detection range
	if nearEdge then
		moveDirection = (moveDirection + awayDir * 1.5).Unit
	end
	
	if centerPull.Magnitude > 0.1 then
		moveDirection = (moveDirection + centerPull.Unit * 0.6).Unit
	end
	
	humanoid:MoveTo(rootPart.Position + moveDirection * 5)
	
	-- Energy recovery during circling
	local energy = fighter:GetAttribute("Energy") or 100
	local recovery = (CombatConfig.EnergyRecovery_Walk or 4) * 0.1
	fighter:SetAttribute("Energy", math.min(CombatConfig.MaxEnergy or 100, energy + recovery))
	
	-- Face the target smoothly via AlignOrientation instead of teleporting CFrame
	local lookCF = CFrame.lookAt(rootPart.Position, Vector3.new(targetHRP.Position.X, rootPart.Position.Y, targetHRP.Position.Z))
	local alignOri = rootPart:FindFirstChild("CirclingGyro")
	if alignOri then
		alignOri.CFrame = lookCF
	else
		rootPart.CFrame = rootPart.CFrame:Lerp(lookCF, FACE_SPEED)
	end
	
	return CirclingState
end

return CirclingState
