--// FightState.lua
-- Core combat state: AI decision engine, combo execution, hit detection
-- Dragon Ball Sparking Zero / Genos inspired
-- Single Source of Truth: ReplicatedStorage.QuinCore.AnimationConfig

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")
local CollectionService = game:GetService("CollectionService")

local TargetingModule = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("TargetingModule"))
local AnimationModule = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("AnimationModule"))
local HitboxModule = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("HitboxModule"))
local KnockbackModule = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("KnockbackModule"))
local ComboModule = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("ComboModule"))
local DamageModule = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("DamageModule"))
local AudioModule = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("AudioModule"))
local AnimationIds = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("AnimationIds"))
local AnimationConfig = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("AnimationConfig"))
local CombatConfig = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("CombatConfig"))
local RuntimeTracer = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("RuntimeTracer"))
local SpatialModule = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("SpatialModule"))
local LocomotionModule = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("LocomotionModule"))

-- Dynamic combat animation pools: directly hot-swappable via AnimationConfig!
local function getLiveAttacks()
	local punches = {}
	if AnimationConfig.Registry.Attacks and AnimationConfig.Registry.Attacks.Punches then
		for _, v in pairs(AnimationConfig.Registry.Attacks.Punches) do
			table.insert(punches, v)
		end
	end
	local kicks = {}
	if AnimationConfig.Registry.Attacks and AnimationConfig.Registry.Attacks.Kicks then
		for _, v in pairs(AnimationConfig.Registry.Attacks.Kicks) do
			table.insert(kicks, v)
		end
	end
	return punches, kicks
end

local function findModelByName(name)
	if not name or name == "" then return nil end
	local quinServer = workspace:FindFirstChild("QuinServer") or workspace
	local m = quinServer:FindFirstChild(name) or workspace:FindFirstChild(name)
	if m and m:IsA("Model") and m:FindFirstChild("HumanoidRootPart") then
		return m
	end
	for _, tag in ipairs(CollectionService:GetTagged("Quin")) do
		if tag.Name == name and tag:FindFirstChild("HumanoidRootPart") then
			return tag
		end
	end
	return nil
end

local FightState = { name = "Fight" }

-- Per-fighter combat data
local fightData = {}

local function getData(fighter)
	if not fightData[fighter] then
		fightData[fighter] = {
			lastAttackTime = 0,
			lastDecisionTime = 0,
			currentAction = nil,
			actionEndTime = 0,
			attackFinishTime = 0,
			lastSpecialTime = 0,
		}
	end
	return fightData[fighter]
end

-- AI Decision Engine
local function decideAction(fighter, target, distance, data)
	local isLastStand = fighter:GetAttribute("LastStandMode") == true
	local aggression = fighter:GetAttribute("Aggression") or 0.7
	if isLastStand then
		aggression = math.min(1.0, aggression + (CombatConfig.LastStandAggressionBonus or 0.50))
	end
	local specialPref = fighter:GetAttribute("SpecialPreference") or 0.3
	local specialCooldown = fighter:GetAttribute("SpecialCooldown") or 8
	local now = tick()
	
	-- Can we use a special?
	local canSpecial = (now - data.lastSpecialTime) >= specialCooldown
	
	-- PHASE 3: Cornered beast desperate counter-strike (set by CirclingState/ChaseState/RetreatState when cornered or Last Stand)
	local isDesperateCounter = fighter:GetAttribute("DesperateCounter")
	if isDesperateCounter then
		fighter:SetAttribute("DesperateCounter", nil) -- Consume the flag
		return "desperate_counter"
	end
	
	-- If we are in the middle of a combo, immediately continue it!
	local currentComboStep = ComboModule.getComboStep(fighter)
	if currentComboStep > 0 then
		return "light"
	end
	
	-- MELEE DEFENSE REACTION: If target is actively winding up an attack in close range
	local targetAttacking = target:GetAttribute("Attacking")
	local targetWindupUntil = target:GetAttribute("AttackWindupUntil") or 0
	if targetAttacking and now < targetWindupUntil and distance <= 9 then
		local lastReaction = fighter:GetAttribute("LastReactionTime") or 0
		if now - lastReaction > 0.5 then
			fighter:SetAttribute("LastReactionTime", now)
			local blockChance = fighter:GetAttribute("BlockChance") or 0.25
			local dodgeChance = fighter:GetAttribute("DodgeChance") or 0.15
			local roll = math.random()
			if roll < blockChance * (1.2 - aggression * 0.5) then
				return "block"
			elseif roll < (blockChance + dodgeChance) * (1.2 - aggression * 0.5) then
				return "dodge"
			end
		end
	end

	-- DEFENSE MATRIX: If target is doing a Projectile Jump at us!
	local targetState = target:GetAttribute("CurrentState")
	if targetState == "ProjectileJump" then
		local lastReaction = fighter:GetAttribute("LastReactionTime") or 0
		if now - lastReaction > 1.5 then
			fighter:SetAttribute("LastReactionTime", now)
			local reactionRoll = math.random()
			if reactionRoll < 0.55 then
				return "block"
			else
				return "dodge"
			end
		end
	end
	
	-- REAR THREAT / DIRECTIONAL AWARENESS REACTION (Phase 2)
	local isUnderRearThreat = fighter:GetAttribute("IsUnderRearThreat")
	local rearDist = fighter:GetAttribute("ClosestRearThreatDist") or 999
	local rearCriticalRange = CombatConfig.RearThreatCriticalRange or 10.0
	if isUnderRearThreat and rearDist > 0 and rearDist <= rearCriticalRange then
		local speedMult = workspace:GetAttribute("GameSpeedMultiplier") or 1.0
		local lastRearReaction = fighter:GetAttribute("LastRearReactionTime") or 0
		local rearCooldown = 1.8 / speedMult
		if (now - lastRearReaction) >= rearCooldown then
			fighter:SetAttribute("LastRearReactionTime", now)
			local awareness = fighter:GetAttribute("Pers_Awareness") or 0.65
			local occupiedQuadrants = fighter:GetAttribute("OccupiedQuadrants") or 1
			local isBeingBullied = fighter:GetAttribute("BeingBullied")
			local defensePref = fighter:GetAttribute("Pers_DefensePreference") or 0.5
			
			-- In heavy multi-quadrant surround (>= 3 quadrants) or high defense focus: backstep slide to break pinch
			if occupiedQuadrants >= (CombatConfig.SurroundedQuadrantThreshold or 3) or (isBeingBullied and defensePref > 0.55) then
				return "rear_backstep"
			elseif math.random() < awareness then
				-- Aware fighter executes 180° snap pivot to face and counter the rear ambusher!
				return "rear_turn_counter"
			end
		end
	end

	local roll = math.random()
	
	-- Dodge/Block (defensive personalities)
	local dodgeChance = fighter:GetAttribute("DodgeChance") or 0.08
	if roll < dodgeChance * (1 - aggression) then
		return "dodge"
	end
	
	-- Dash attack (gap closer)
	local dashMin = CombatConfig.DashMinDistance or 10
	local dashMax = CombatConfig.DashMaxDistance or 28
	local minDashMana = CombatConfig.DashMinEnergy or 20
	local lastDash = fighter:GetAttribute("LastDashTime") or 0
	local speedMult = workspace:GetAttribute("GameSpeedMultiplier") or 1.0
	local dashCooldown = 8.0 / speedMult
	local isDashOnCooldown = (now - lastDash) < dashCooldown
	local energy = fighter:GetAttribute("Energy") or 100
	if not isDashOnCooldown and energy >= minDashMana and distance >= dashMin and distance <= dashMax and roll < (CombatConfig.DashAttackChance or 0.15) then
		return "dash"
	end
	
	-- Heavy attack (less frequent, more damage)
	if roll < 0.20 + aggression * 0.1 then
		return "heavy"
	end
	
	-- Light combo (default)
	return "light"
end

local function executeAttack(fighter, humanoid, rootPart, target, moveData, data, DEBUG)
	local targetHRP = target:FindFirstChild("HumanoidRootPart")
	if not targetHRP then return 0.5, 0.35 end
	
	local dist = (targetHRP.Position - rootPart.Position).Magnitude
	local energy = fighter:GetAttribute("Energy") or 100
	local fatigueScale = energy < (CombatConfig.FatigueThreshold or 25) and 0.65 or 1.0
	
	-- Dynamic animation resolution: directly reads live hot-swapped configuration!
	local punches, kicks = getLiveAttacks()
	local pool = (math.random() > 0.5 and #punches > 0) and punches or kicks
	if #pool == 0 then pool = punches end
	local animData = (#pool > 0) and pool[math.random(1, #pool)] or { id = AnimationIds.Punches[1], speed = 1.3, fadeTime = 0.01, impactRatio = 0.35, cancelRatio = 0.70 }

	local playSpeed = math.max((fighter:GetAttribute("AttackSpeed") or 1.0) * (animData.speed or 1.0) * fatigueScale, 0.01)
	local fadeTime = animData.fadeTime or 0.01
	local prio = Enum.AnimationPriority[animData.priority or "Action4"] or Enum.AnimationPriority.Action4
	local impactRatio = animData.impactRatio or 0.35
	local cancelRatio = animData.cancelRatio or 0.75

	-- Play track cleanly (preserves underlying base idle)
	local track = AnimationModule.play(humanoid, animData.id, prio, false, playSpeed, fadeTime)
	
	-- Determine true effective track duration
	local rawLength = (track and track.Length > 0 and track.Length) or AnimationModule.getRawLength(animData.id) or moveData.duration or 0.7
	local effectiveDuration = rawLength / playSpeed
	local impactDelay = effectiveDuration * impactRatio
	local cancelDelay = effectiveDuration * cancelRatio

	-- Set telegraphing attributes for causal defense (impact window driven by config)
	local now = tick()
	fighter:SetAttribute("Attacking", true)
	fighter:SetAttribute("AttackWindupUntil", now + impactDelay)
	task.delay(effectiveDuration, function()
		if fighter.Parent and tick() >= (data.attackFinishTime or 0) then
			fighter:SetAttribute("Attacking", false)
		end
	end)
		
	-- Overshoot Lunge (Slide forward with momentum)
	local lungeSpeed = 20 + (moveData.step * 7)
	if moveData.isLaunch or moveData.knockback >= 40 then lungeSpeed = 45 end
	
	-- Prevent lunging past the target if already very close ("Kissing" fix)
	if dist < 7.5 then
		lungeSpeed = lungeSpeed * 0.35
	end
	
	local lungeTime = math.min(effectiveDuration * 0.4, 0.35)
	KnockbackModule.applyLunge(fighter, rootPart.CFrame.LookVector, lungeSpeed, lungeTime)
	
	-- Punch sound (precisely synchronized with strike apex)
	local soundPart = fighter:FindFirstChild("Sounds")
	if soundPart then
		local punch = soundPart:FindFirstChild("punch1")
		if punch then
			task.delay(math.max(0, impactDelay - 0.04), function()
				punch.Volume = 0.15
				punch.PlaybackSpeed = math.random(18, 26) / 10
				punch:Play()
			end)
		end
	end
	
	-- Hit detection at exact impact frame
	task.delay(impactDelay, function()
		if not fighter.Parent or not target.Parent then return end
		local hitModels = HitboxModule.castInFront(rootPart, moveData.hitboxSize, Vector3.new(0, 0, -3), fighter)
		
		for _, hitModel in ipairs(hitModels) do
			local damageInfo = DamageModule.calculate(fighter, hitModel, moveData.step, moveData.damageMultiplier)
			local applied, isKill, status = DamageModule.apply(fighter, hitModel, damageInfo)
			
			if status == "Blocked" or status == "Dodged" then
				if DEBUG then print("[Fight] Combo broken by " .. status .. "!") end
				ComboModule.resetCombo(fighter)
				data.lastAttackTime = tick() + 0.3 -- Stagger them slightly
			elseif applied then
				if DEBUG then
					print(string.format("[Fight] %s -> %s: %s (DMG=%d%s, Combo=%d)",
						fighter.Name, hitModel.Name, moveData.name,
						damageInfo.damage, damageInfo.isCrit and " CRIT!" or "",
						moveData.step))
				end
				
				if moveData.isLaunch then
					-- LAUNCH: Send them flying up!
					AudioModule.playSlam(hitModel:FindFirstChild("HumanoidRootPart").Position)
					
					KnockbackModule.applyLaunch(hitModel, 
						CombatConfig.LaunchVerticalForce or 120,
						CombatConfig.LaunchHorizontalForce or 20)
					
					hitModel:SetAttribute("ForceState", "Knockback")
					if DEBUG then print("[Fight] LAUNCH! -> Airborne pursuit") end
				elseif moveData.knockback > 0 then
					local kbDuration = math.clamp(0.2 + (moveData.knockback / 300), 0.2, 0.8)
					
					if moveData.knockback >= 40 then
						AudioModule.playSlam(hitModel:FindFirstChild("HumanoidRootPart").Position)
						local kbDir = rootPart.CFrame.LookVector
						hitModel:SetAttribute("ForceState", "Knockback")
						hitModel:SetAttribute("KnockbackType", "air")
						KnockbackModule.applyKnockback(hitModel, kbDir, moveData.knockback * 1.5, kbDuration * 1.2)
						if DEBUG then print("[Fight] Air Knockback Finisher!") end
					else
						-- LIGHT COMBO MICRO-KNOCKBACK:
						local kbDir = rootPart.CFrame.LookVector
						KnockbackModule.applyMicroKnockback(hitModel, kbDir, moveData.knockback)
					end
				end
			end
		end
	end)

	return effectiveDuration, cancelDelay
end

function FightState.enter(fighter, humanoid, rootPart)
	RuntimeTracer.checkpoint(fighter, "Enter FightState")
	humanoid.WalkSpeed = 0
	AnimationModule.stop(humanoid, AnimationIds.Run, 0.2)
	AnimationModule.stop(humanoid, AnimationIds.Fall, 0.2)
	AnimationModule.stop(humanoid, AnimationIds.Jump, 0.2)
	AnimationModule.playConfig(humanoid, "Movement.Idle", 1.0, Enum.AnimationPriority.Idle, true)
end

function FightState.exit(fighter, humanoid, rootPart)
	RuntimeTracer.checkpoint(fighter, "Exit FightState")
	fightData[fighter] = nil
	ComboModule.resetCombo(fighter)
	fighter:SetAttribute("Attacking", false)
	-- Cleanly stop any attack or hit reaction tracks so they do not linger into subsequent states (e.g. CirclingState)
	AnimationModule.stopCategory(humanoid, "Attacks", 0.1)
	AnimationModule.stopCategory(humanoid, "Reactions", 0.1)
	-- Do NOT hard stop Idle; let Idle blend smoothly with whichever state takes over
end

function FightState.update(fighter, humanoid, rootPart, DEBUG)
	-- Showdown perimeter spectators must never fight
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

	local data = getData(fighter)
	local now = tick()
	
	-- Check forced state change (from being hit, disengaging, or tactical override)
	local forcedState = fighter:GetAttribute("ForceState")
	if forcedState then
		fighter:SetAttribute("ForceState", nil)
		local targetStateModule = script.Parent:FindFirstChild(forcedState .. "State")
		if targetStateModule then
			return require(targetStateModule)
		end
	end

	-- Prone / Cockroach protection: if flat on ground, immediately recover
	local upY = rootPart.CFrame.UpVector.Y
	if upY < 0.6 and SpatialModule.isGrounded(rootPart) then
		fighter:SetAttribute("KnockbackType", "hard_ground")
		return require(script.Parent:WaitForChild("RecoveryState"))
	end
	
	-- Check hit stun
	local stunEndTime = fighter:GetAttribute("StunEndTime") or 0
	if now < stunEndTime then
		humanoid.WalkSpeed = 0
		rootPart.AssemblyLinearVelocity = Vector3.new(0, rootPart.AssemblyLinearVelocity.Y, 0)
		return FightState
	end

	-- IMMEDIATE COUNTER ATTACK (Riposte following successful block)
	if fighter:GetAttribute("ImmediateCounter") == true then
		local counterTargetName = fighter:GetAttribute("ImmediateCounterTarget")
		local counterTarget = findModelByName(counterTargetName)
		if counterTarget and counterTarget:FindFirstChild("HumanoidRootPart") then
			fighter:SetAttribute("ImmediateCounter", nil)
			fighter:SetAttribute("IsGuarding", false)
			data.currentAction = nil
			data.actionEndTime = 0
			
			local cTargetHRP = counterTarget.HumanoidRootPart
			local lookCF = CFrame.lookAt(rootPart.Position, Vector3.new(cTargetHRP.Position.X, rootPart.Position.Y, cTargetHRP.Position.Z))
			rootPart.CFrame = lookCF
			
			data.currentAction = "immediate_counter"
			data.lastAttackTime = now
			
			local speedMult = workspace:GetAttribute("GameSpeedMultiplier") or 1.0
			local counterDuration = 0.45 / speedMult
			data.actionEndTime = now + (0.28 / speedMult)
			data.attackFinishTime = now + counterDuration
			
			-- Play snappy counter punch/kick animation
			local punches, kicks = getLiveAttacks()
			local animData = (punches and #punches > 0 and punches[1]) or { id = AnimationIds.Punches[1], speed = 1.3, fadeTime = 0.02, impactRatio = 0.25, cancelRatio = 0.60 }
			local playSpeed = math.max((fighter:GetAttribute("AttackSpeed") or 1.0) * (animData.speed or 1.3) * 1.25, 0.01)
			AnimationModule.play(humanoid, animData.id, Enum.AnimationPriority.Action4, false, playSpeed, 0.02)
			
			-- Forward lunge slide towards counter target
			local lungeDir = (cTargetHRP.Position - rootPart.Position)
			local lungeFlat = Vector3.new(lungeDir.X, 0, lungeDir.Z)
			if lungeFlat.Magnitude > 0.01 then
				KnockbackModule.applyLunge(fighter, lungeFlat.Unit, 32, 0.22)
			end
			
			-- Sound
			local soundPart = fighter:FindFirstChild("Sounds")
			if soundPart and soundPart:FindFirstChild("punch1") then
				soundPart.punch1.PlaybackSpeed = 2.2
				soundPart.punch1:Play()
			end
			
			-- Hit telegraph & strike execution
			local impactDelay = (animData.impactRatio or 0.25) * (counterDuration / playSpeed)
			fighter:SetAttribute("Attacking", true)
			fighter:SetAttribute("AttackWindupUntil", now + impactDelay)
			
			task.delay(impactDelay, function()
				if not fighter.Parent or not counterTarget.Parent then return end
				fighter:SetAttribute("Attacking", false)
				local hitModels = HitboxModule.castInFront(rootPart, Vector3.new(7, 6, 9), Vector3.new(0, 0, -4.5), fighter)
				for _, hitModel in ipairs(hitModels) do
					local damageInfo = DamageModule.calculate(fighter, hitModel, 1, 1.25)
					local applied, isKill, status = DamageModule.apply(fighter, hitModel, damageInfo)
					if applied then
						local hitHRP = hitModel:FindFirstChild("HumanoidRootPart")
						if hitHRP then
							AudioModule.playImpact(hitHRP.Position, false)
						end
						KnockbackModule.applyMicroKnockback(hitModel, rootPart.CFrame.LookVector, 14)
					end
				end
			end)
			
			return FightState
		end
	end
	
	-- If our previously engaged target died or was destroyed, enter Idle
	if data.lastEngagedTarget and not TargetingModule.isValid(data.lastEngagedTarget) then
		if DEBUG then print(string.format("[Fight] %s defeated their target! Entering Idle survey.", fighter.Name)) end
		data.lastEngagedTarget = nil
		return require(script.Parent:WaitForChild("IdleState"))
	end

	-- Find target
	local prevTargetName = fighter:GetAttribute("CurrentTarget")
	local target, distance = TargetingModule.getNearest(rootPart, CombatConfig.ChaseRange)
	
	if not TargetingModule.isValid(target) then
		if DEBUG then print("[Fight] Target lost/defeated -> Idle") end
		return require(script.Parent:WaitForChild("IdleState"))
	end
	
	local targetHRP = target:FindFirstChild("HumanoidRootPart")
	if not targetHRP then
		return require(script.Parent:WaitForChild("IdleState"))
	end

	data.lastEngagedTarget = target

	-- Target Transition Buffer: If our previous target was defeated/lost and next opponent is not directly in melee range,
	-- enter Idle to breathe, survey, and re-orient rather than snapping instantly across arena.
	if prevTargetName and prevTargetName ~= "" and prevTargetName ~= target.Name and distance > (CombatConfig.CombatRange or 8) * 1.5 then
		if DEBUG then print(string.format("[Fight] Target changed (%s -> %s, dist=%.1f) -> Idle survey", tostring(prevTargetName), target.Name, distance)) end
		return require(script.Parent:WaitForChild("IdleState"))
	end
	
	-- DO NOT attack downed opponents!
	local targetState = target:GetAttribute("CurrentState")
	if targetState == "Knockback" or targetState == "Airborne" then
		if DEBUG then print("[Fight] Opponent is down! Entering standoff.") end
		return require(script.Parent:WaitForChild("CirclingState"))
	end
	
	-- Early exit for Projectile Jumps (tactical aerial leap, strictly gated by mana & cooldown)
	local forcedAction = fighter:GetAttribute("ForceAction")
	local roll = math.random()
	local pjEnabled = not inShowdown and (CombatConfig.EnableProjectileJump ~= false) and (fighter:GetAttribute("EnableProjectileJump") ~= false)
	local minDist = CombatConfig.ProjectileJumpMinDistance or 25
	local maxDist = CombatConfig.ProjectileJumpMaxDistance or 90
	local minPJMana = CombatConfig.ProjectileJumpMinEnergy or 35
	local lastPJ = fighter:GetAttribute("LastProjectileJumpTime") or 0
	local speedMult = workspace:GetAttribute("GameSpeedMultiplier") or 1.0
	local aggression = fighter:GetAttribute("Pers_Aggression") or 0.6
	local pjCooldown = ((aggression > 0.7) and 14.0 or 18.0) / speedMult
	local isPJOnCooldown = (now - lastPJ) < pjCooldown
	local energy = fighter:GetAttribute("Energy") or 100
	local pjChance = fighter:GetAttribute("ProjectileJumpChance") or 0.08

	if not inShowdown and (forcedAction == "projectile_jump" or (pjEnabled and not isPJOnCooldown and energy >= minPJMana and distance >= minDist and distance <= maxDist and roll < pjChance)) then
		fighter:SetAttribute("LastProjectileJumpTime", now)
		fighter:SetAttribute("ForceAction", nil)
		data.currentAction = "projectile_jump"
		data.actionEndTime = now + (0.5 / speedMult)
		
		local forcedStyle = fighter:GetAttribute("ForceJumpStyle")
		fighter:SetAttribute("JumpStyle", forcedStyle or math.random(1, 7))
		
		local targetVal = fighter:FindFirstChild("ProjectileTarget")
		if not targetVal then
			targetVal = Instance.new("ObjectValue")
			targetVal.Name = "ProjectileTarget"
			targetVal.Parent = fighter
		end
		targetVal.Value = target
		
		return require(script.Parent:WaitForChild("ProjectileJumpState"))
	end
	
	-- Too far? Chase
	if distance > (CombatConfig.CombatRange or 7) * 2.5 then
		if DEBUG then print("[Fight] Target too far -> Chase") end
		return require(script.Parent:WaitForChild("ChaseState"))
	end
	
	-- Face target smoothly
	local yDiff = math.abs(targetHRP.Position.Y - rootPart.Position.Y)
	if yDiff < 5 then
		local lookCF = CFrame.lookAt(rootPart.Position, Vector3.new(targetHRP.Position.X, rootPart.Position.Y, targetHRP.Position.Z))
		rootPart.CFrame = rootPart.CFrame:Lerp(lookCF, 0.5)
	end
	
	-- Distance management
	local idealRange = CombatConfig.CombatRange or 8
	if distance > idealRange + 1.5 then
		local dir = (targetHRP.Position - rootPart.Position).Unit
		humanoid.WalkSpeed = fighter:GetAttribute("Speed") or 40
		humanoid:MoveTo(rootPart.Position + dir * 5)
		
		if not AnimationModule.isPlaying(humanoid, AnimationIds.Run) then
			AnimationModule.playConfig(humanoid, "Movement.Run", 1.0, Enum.AnimationPriority.Movement, false)
		end
	elseif distance < (CombatConfig.Melee_SweetSpotMin or 4.5) then
		-- Point blank overlap: smooth physics micro-slide with momentum continuity
		LocomotionModule.brake(fighter, humanoid, rootPart)
		local awayDir = (rootPart.Position - targetHRP.Position)
		local awayFlat = Vector3.new(awayDir.X, 0, awayDir.Z)
		if awayFlat.Magnitude > 0.01 then
			KnockbackModule.applySlide(fighter, awayFlat.Unit, CombatConfig.Melee_SlideSpeed or 10, 0.12)
		end
	else
		-- Inside the combat sweet spot: hold stance firmly with momentum continuity
		LocomotionModule.brake(fighter, humanoid, rootPart)
	end
	
	local speedMult = workspace:GetAttribute("GameSpeedMultiplier") or 1.0

	-- Currently executing an action? (Respects dynamic cancel window)
	if data.currentAction and now < data.actionEndTime then
		return FightState
	end

	-- Attack cooldown
	local minCooldown = CombatConfig.AttackCooldownMin or 0.5
	local maxCooldown = CombatConfig.AttackCooldownMax or 1.5
	local attackSpeed = fighter:GetAttribute("AttackSpeed") or 1.0
	
	local cooldown = 0
	local currentComboStep = ComboModule.getComboStep(fighter)
	if currentComboStep > 0 then
		cooldown = 0.05 / speedMult -- Fast combo chaining immediately at cancel window!
	else
		cooldown = (minCooldown + math.random() * (maxCooldown - minCooldown)) / (attackSpeed * speedMult)
	end
	
	if (now - data.lastAttackTime) < cooldown then
		-- Maintain base idle stance during recovery / cooldown
		if now >= (data.attackFinishTime or 0) then
			AnimationModule.ensureBaseIdle(humanoid)
		end
		return FightState
	end
	
	-- DECIDE ACTION
	local action = decideAction(fighter, target, distance, data)
	data.lastAttackTime = now
	
	-- Energy drain per attack
	local energy = fighter:GetAttribute("Energy") or 100
	local drain = CombatConfig.EnergyDrain_Attack or 2
	fighter:SetAttribute("Energy", math.max(0, energy - drain))
	energy = fighter:GetAttribute("Energy") or 0
	
	-- If fatigued, force light attacks only
	if energy < (CombatConfig.FatigueThreshold or 25) then
		if action == "heavy" or action == "special" or action == "dash" then
			action = "light"
		end
	end
	
	if action == "light" then
		local moveData = ComboModule.nextAttack(fighter, "Light")
		if moveData then
			data.currentAction = "light"
			local attackDuration, cancelDelay = executeAttack(fighter, humanoid, rootPart, target, moveData, data, DEBUG)
			data.actionEndTime = now + (cancelDelay / speedMult)
			data.attackFinishTime = now + (attackDuration / speedMult)
			
			-- Check for launch transition
			if moveData.isLaunch then
				task.delay((attackDuration + 0.05) / speedMult, function()
					if fighter.Parent and fighter:GetAttribute("CurrentState") == "Fight" then
						fighter:SetAttribute("ForceState", "Airborne")
					end
				end)
			end
		end
		
	elseif action == "heavy" then
		local moveData = ComboModule.nextAttack(fighter, "Heavy")
		if moveData then
			data.currentAction = "heavy"
			local attackDuration, cancelDelay = executeAttack(fighter, humanoid, rootPart, target, moveData, data, DEBUG)
			data.actionEndTime = now + (cancelDelay / speedMult)
			data.attackFinishTime = now + (attackDuration / speedMult)
		end
		
	elseif action == "dash" then
		data.currentAction = "dash"
		data.actionEndTime = now + (0.5 / speedMult)
		data.attackFinishTime = now + (0.5 / speedMult)
		if targetHRP then
			LocomotionModule.dash(fighter, humanoid, rootPart, targetHRP.Position, distance)
		end
		return FightState
		
	elseif action == "anticipate" then
		data.currentAction = "anticipate"
		data.actionEndTime = now + (0.3 / speedMult)
		data.attackFinishTime = now + (0.3 / speedMult)
		AnimationModule.playConfig(humanoid, "Awareness.RearThreatGlance", 1.0, Enum.AnimationPriority.Action2, false)
		return FightState
		
	elseif action == "block" then
		data.currentAction = "block"
		data.actionEndTime = now + (0.45 / speedMult)
		data.attackFinishTime = now + (0.45 / speedMult)
		fighter:SetAttribute("IsGuarding", true)
		AnimationModule.playConfig(humanoid, "Reactions.Block", 1.0, Enum.AnimationPriority.Action4, false)
		task.delay(0.45 / speedMult, function()
			if fighter.Parent and fighter:GetAttribute("IsGuarding") == true then
				fighter:SetAttribute("IsGuarding", false)
			end
		end)
		return FightState
		
	elseif action == "dodge" then
		data.currentAction = "dodge"
		data.actionEndTime = now + 0.35
		data.attackFinishTime = now + 0.35
		local soundPart = fighter:FindFirstChild("Sounds")
		if soundPart and soundPart:FindFirstChild("swish") then
			soundPart.swish.Volume = 0.3
			soundPart.swish:Play()
		end
		local awayDir = (rootPart.Position - targetHRP.Position)
		local awayFlat = Vector3.new(awayDir.X, 0, awayDir.Z)
		if awayFlat.Magnitude > 0.01 then
			KnockbackModule.applySlide(fighter, awayFlat.Unit, 35, 0.25)
		end
		return FightState
		
	elseif action == "special" then
		data.lastSpecialTime = now
		data.currentAction = "special"
		data.actionEndTime = now + 1.0
		data.attackFinishTime = now + 1.0
		return require(script.Parent:WaitForChild("SpecialState"))
		
	elseif action == "rear_turn_counter" then
		data.currentAction = "rear_turn_counter"
		data.actionEndTime = now + (0.35 / speedMult)
		data.attackFinishTime = now + (0.35 / speedMult)
		
		local rearThreatName = fighter:GetAttribute("ClosestRearThreat")
		local rearThreatModel = findModelByName(rearThreatName)
		if rearThreatModel and rearThreatModel:FindFirstChild("HumanoidRootPart") then
			local rHRP = rearThreatModel.HumanoidRootPart
			local turnLook = CFrame.lookAt(rootPart.Position, Vector3.new(rHRP.Position.X, rootPart.Position.Y, rHRP.Position.Z))
			rootPart.CFrame = turnLook
			AnimationModule.playConfig(humanoid, "Awareness.Turn180Pivot", 1.5, Enum.AnimationPriority.Action4, false)
			
			fighter:SetAttribute("CurrentTarget", rearThreatModel.Name)
			fighter:SetAttribute("TargetQuin", rearThreatModel.Name)
			data.lastEngagedTarget = rearThreatModel.Name
			
			local awareness = fighter:GetAttribute("Pers_Awareness") or 0.65
			if math.random() < (0.3 + awareness * 0.4) then
				fighter:SetAttribute("IsGuarding", true)
				task.delay(0.35 / speedMult, function()
					if fighter.Parent then fighter:SetAttribute("IsGuarding", false) end
				end)
			end
		end
		return FightState
		
	elseif action == "rear_backstep" then
		data.currentAction = "rear_backstep"
		data.actionEndTime = now + (0.35 / speedMult)
		data.attackFinishTime = now + (0.35 / speedMult)
		
		AnimationModule.playConfig(humanoid, "Tactics.RetreatBackstep", 1.3, Enum.AnimationPriority.Action3, false)
		
		local awayTarget = (rootPart.Position - targetHRP.Position)
		local awayFlat = Vector3.new(awayTarget.X, 0, awayTarget.Z)
		local slideDir = (awayFlat.Magnitude > 0.01) and awayFlat.Unit or -rootPart.CFrame.LookVector
		KnockbackModule.applySlide(fighter, slideDir, 36, 0.25)
		
		return FightState
		
	elseif action == "desperate_counter" then
		-- Phase 3: Cornered beast spinning counter-strike to carve breathing room
		data.currentAction = "desperate_counter"
		data.actionEndTime = now + (0.55 / speedMult)
		data.attackFinishTime = now + (0.55 / speedMult)
		data.lastAttackTime = now
		
		-- Play desperate counter animation (fast hook or wheel kick)
		AnimationModule.playConfig(humanoid, "Tactics.DesperateCounter", 1.35, Enum.AnimationPriority.Action4, false)
		
		-- Damage telegraph
		fighter:SetAttribute("Attacking", true)
		fighter:SetAttribute("AttackWindupUntil", now + 0.22 / speedMult)
		task.delay(0.55 / speedMult, function()
			if fighter.Parent then
				fighter:SetAttribute("Attacking", false)
			end
		end)
		
		-- Forward lunge slide to carve space from the cluster
		local lungeDir = rootPart.CFrame.LookVector
		KnockbackModule.applySlide(fighter, Vector3.new(lungeDir.X, 0, lungeDir.Z), 30, 0.2)
		
		-- Apply hitbox for the counter-strike
		local hitboxSize = Vector3.new(7, 5, 7) -- Wide arc
		local hitboxOffset = Vector3.new(0, 0, -3.5)
		local hitModels = HitboxModule.castInFront(rootPart, hitboxSize, hitboxOffset, fighter)
		for _, hitModel in ipairs(hitModels) do
			-- Counter-strike: 1.3x damage multiplier, step 1 (standalone hit)
			local damageInfo = DamageModule.calculate(fighter, hitModel, 1, 1.3)
			local applied, isKill, status = DamageModule.apply(fighter, hitModel, damageInfo)
			if applied then
				-- Strong knockback to carve breathing room
				local kbDir = rootPart.CFrame.LookVector
				KnockbackModule.applyKnockback(hitModel, kbDir, 35, 0.4)
				hitModel:SetAttribute("ForceState", "Knockback")
			end
		end
		
		-- After counter, briefly guard
		task.delay(0.3 / speedMult, function()
			if fighter.Parent then
				fighter:SetAttribute("IsGuarding", true)
				task.delay(0.4 / speedMult, function()
					if fighter.Parent then fighter:SetAttribute("IsGuarding", false) end
				end)
			end
		end)
		
		return FightState
	end

	local fs = fighter:GetAttribute("ForceState")
	if fs then
		fighter:SetAttribute("ForceState", nil)
		if fs == "Knockback" then
			return require(script.Parent:WaitForChild("KnockbackState"))
		elseif fs == "Airborne" then
			return require(script.Parent:WaitForChild("AirborneState"))
		elseif fs == "ProjectileFight" then
			return require(script.Parent:WaitForChild("ProjectileFightState"))
		end
	end
	
	return FightState
end

function FightState.exit(fighter, humanoid, rootPart)
	fightData[fighter] = nil
end

return FightState