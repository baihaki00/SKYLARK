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
local NavigationModule = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("NavigationModule"))
local GaitModule = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("GaitModule"))

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
		-- A committed, occasional move: cornered again inside the cooldown, the Quin just fights
		if now - (data.lastDesperateCounterTime or 0) >= (CombatConfig.Combat_DesperateCounterCooldown or 6.0) then
			data.lastDesperateCounterTime = now
			return "desperate_counter"
		end
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
			-- A bold Quin with the energy for it goes up to meet the jumper instead
			local canJump = CombatConfig.EnableProjectileJump ~= false and fighter:GetAttribute("EnableProjectileJump") ~= false
				and (fighter:GetAttribute("Energy") or 100) >= (CombatConfig.ProjectileJumpMinEnergy or 35)
			if canJump and math.random() < aggression * (CombatConfig.Combat_MeetJumpChance or 0.5) then
				return "answer_jump"
			end
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

-- The cornered counter-strike resolves its hit like a combo finisher
local DESPERATE_COUNTER_MOVE = { name = "DesperateCounter", knockback = 35, isFinisher = true }

-- Footing consequence of a landed strike. A flinch needs nothing here: DamageModule.apply has
-- already slid the victim back on its feet.
local function applyHitOutcome(rootPart, hitModel, moveData, outcome)
	local hitRoot = hitModel:FindFirstChild("HumanoidRootPart")
	if not hitRoot or outcome == DamageModule.Outcome.Flinch then return end

	local away = rootPart.CFrame.LookVector
	AudioModule.playSlam(hitRoot.Position)
	hitModel:SetAttribute("ForceState", "Knockback")
	if outcome == DamageModule.Outcome.AirKnockback then
		hitModel:SetAttribute("KnockbackType", "air")
		local force = math.max(moveData.knockback, CombatConfig.Combat_LaunchMinForce or 60) * 1.5
		KnockbackModule.applyKnockback(hitModel, away, force)
	else
		hitModel:SetAttribute("KnockbackType", "ground")
		local minStuds = CombatConfig.Combat_GroundKnockbackMinStuds or 10
		local maxStuds = CombatConfig.Combat_GroundKnockbackMaxStuds or 18
		KnockbackModule.applyGroundSkid(hitModel, away, minStuds + math.random() * (maxStuds - minStuds), CombatConfig.Combat_GroundKnockbackTime or 0.6)
	end
end

-- Answer an incoming strike by getting the guard up in time. Rolled once per strike (keyed by
-- the attacker's wind-up), so a slow wind-up is not a string of extra chances. The guard still
-- has to hold (DamageModule); a held guard ends the attacker's chain and opens a counter.
local function tryRaiseGuard(fighter, humanoid, data, now, attacker, chance)
	if not attacker or attacker:GetAttribute("Attacking") ~= true then return end
	local windupUntil = attacker:GetAttribute("AttackWindupUntil") or 0
	if now >= windupUntil or data.guardRolledFor == windupUntil then return end
	data.guardRolledFor = windupUntil
	if math.random() >= chance then return end

	local speedMult = workspace:GetAttribute("GameSpeedMultiplier") or 1.0
	fighter:SetAttribute("IsGuarding", true)
	AnimationModule.playConfig(humanoid, "Reactions.Block", 1.0, Enum.AnimationPriority.Action4, false)
	task.delay((windupUntil - now) + 0.2 / speedMult, function()
		if fighter.Parent and fighter:GetAttribute("IsGuarding") == true then
			fighter:SetAttribute("IsGuarding", false)
		end
	end)
end

-- Chance to guard the next strike of a combo the Quin is caught in (defensive Quins more often)
local function comboBreakChance(fighter)
	local defense = fighter:GetAttribute("Pers_DefensePreference") or 0.5
	return (CombatConfig.Combat_ComboBreakChance or 0.25) * (0.5 + defense)
end

-- Chance to guard a strike seen coming while the Quin is between its own attacks
local function reactiveGuardChance(fighter)
	local aggression = fighter:GetAttribute("Pers_Aggression") or 0.6
	return (fighter:GetAttribute("BlockChance") or 0.25) * (1.2 - aggression * 0.5)
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
	local windupUntil = now + impactDelay
	fighter:SetAttribute("AttackWindupUntil", windupUntil)
	task.delay(effectiveDuration, function()
		if fighter.Parent and tick() >= (data.attackFinishTime or 0) then
			fighter:SetAttribute("Attacking", false)
		end
	end)
		
	-- Step into the strike with momentum, but only as far as the gap: the attacker closes to
	-- striking distance and never drives into (or through) its target
	local lungeSpeed = CombatConfig.Combat_LungeMaxSpeed or 60
	local lungeTime = math.min(effectiveDuration * 0.4, 0.35)
	local lungeRoom = dist - (CombatConfig.Combat_LungeStopDistance or 5.5)
	if lungeRoom > 0.25 then
		KnockbackModule.applyLunge(fighter, rootPart.CFrame.LookVector, lungeSpeed, lungeTime, lungeRoom)
	end

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
		-- Hit while winding up: the strike never comes out and the chain is broken
		if fighter:GetAttribute("StrikeInterrupted") == windupUntil then
			ComboModule.resetCombo(fighter)
			fighter:SetAttribute("StrikeResult", "Interrupted")
			fighter:SetAttribute("StrikeSeq", (fighter:GetAttribute("StrikeSeq") or 0) + 1)
			return
		end
		local hitModels = HitboxModule.castInFront(rootPart, moveData.hitboxSize, Vector3.new(0, 0, -3), fighter)
		local landed = false
		local result = "Whiff"

		for _, hitModel in ipairs(hitModels) do
			local damageInfo = DamageModule.calculate(fighter, hitModel, moveData.step, moveData.damageMultiplier)
			local applied, isKill, status = DamageModule.apply(fighter, hitModel, damageInfo)

			if status == "Blocked" or status == "Dodged" then
				result = status
				if DEBUG then print("[Fight] Combo broken by " .. status .. "!") end
				ComboModule.resetCombo(fighter)
				data.lastAttackTime = tick() + 0.3 -- Stagger them slightly
			elseif applied then
				landed = true
				result = "Hit"
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
				else
					applyHitOutcome(rootPart, hitModel, moveData, DamageModule.resolveOutcome(fighter, hitModel, moveData, damageInfo))
				end
			end
		end

		-- A strike that connects with nothing ends the chain: the next attack opens a new combo
		-- instead of throwing the finisher at empty air
		if not landed then
			ComboModule.resetCombo(fighter)
		end
		-- Strike telemetry (HUD / audits): what became of this strike
		if result == "Whiff" and #hitModels == 0 then
			local tHRP = target:FindFirstChild("HumanoidRootPart")
			fighter:SetAttribute("StrikeMissDist", tHRP and math.floor((tHRP.Position - rootPart.Position).Magnitude * 10) / 10 or -1)
		end
		fighter:SetAttribute("StrikeResult", result)
		fighter:SetAttribute("StrikeSeq", (fighter:GetAttribute("StrikeSeq") or 0) + 1)
	end)

	return effectiveDuration, cancelDelay
end

function FightState.enter(fighter, humanoid, rootPart)
	RuntimeTracer.checkpoint(fighter, "Enter FightState")
	-- Momentum continuity (Rule 3): no speed snap on entry. The distance-management
	-- brake decelerates the body while the shared gait keeps stepping (or the StopRun
	-- plant plays from a sprint), so Chase -> Fight reads as one braking motion.
	AnimationModule.stop(humanoid, AnimationIds.Fall, 0.2)
	AnimationModule.stop(humanoid, AnimationIds.Jump, 0.2)
	AnimationModule.playConfig(humanoid, "Idles.CombatIdle", 1.0, Enum.AnimationPriority.Idle, true)
end

function FightState.exit(fighter, humanoid, rootPart)
	RuntimeTracer.checkpoint(fighter, "Exit FightState")
	fightData[fighter] = nil
	ComboModule.resetCombo(fighter)
	fighter:SetAttribute("Attacking", false)
	fighter:SetAttribute("CurrentIdleStance", "Ready")
	fighter:SetAttribute("LastActivityTime", os.clock())
	-- Cleanly stop any attack or hit reaction tracks so they do not linger into subsequent states (e.g. CirclingState)
	AnimationModule.stopCategory(humanoid, "Attacks", 0.1)
	AnimationModule.stopCategory(humanoid, "Reactions", 0.1)
	local gyro = rootPart and rootPart:FindFirstChild("FightGyro")
	if gyro then gyro:Destroy() end
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
		-- Hard but continuous stop: the drive drops to zero within ~0.15s. Zeroing the velocity
		-- on every tick froze a running body in one frame and kept cancelling the hit push,
		-- which showed as a stutter during the flinch.
		humanoid.WalkSpeed = math.max(0, humanoid.WalkSpeed - 30)
		tryRaiseGuard(fighter, humanoid, data, now, findModelByName(fighter:GetAttribute("LastAttackerName")), comboBreakChance(fighter))
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
			-- Turned by the facing gyro (as the rear-turn counter is), not flipped in one frame
			local facingGyro = rootPart:FindFirstChild("FightGyro")
			if facingGyro then
				facingGyro.CFrame = lookCF
			else
				rootPart.CFrame = lookCF
			end
			
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
						KnockbackModule.applyMicroKnockback(hitModel, rootPart.CFrame.LookVector, CombatConfig.Combat_CounterSlideStuds or 4.5)
					end
				end
			end)
			
			return FightState
		end
	end
	
	-- Find or retain committed target
	local target, distance = TargetingModule.getCommittedTarget(fighter, rootPart, (CombatConfig.ChaseRange or 60) * 1.5)
	
	if not target then
		-- No current valid committed target, or target died/escaped: acquire nearest candidate
		target, distance = TargetingModule.getNearest(rootPart, CombatConfig.ChaseRange)
		if target then
			TargetingModule.setTarget(fighter, target)
			data.lastEngagedTarget = target
			-- If next target is beyond close combat range, transition to Chase or Circling, NEVER mid-combat Idle!
			if distance > (CombatConfig.CombatRange or 8) * 1.8 then
				return require(script.Parent:WaitForChild("ChaseState"))
			end
		else
			-- No enemies exist anywhere in arena
			TargetingModule.clearTarget(fighter)
			data.lastEngagedTarget = nil
			return require(script.Parent:WaitForChild("IdleState"))
		end
	else
		data.lastEngagedTarget = target
	end

	local targetHRP = target:FindFirstChild("HumanoidRootPart")
	if not targetHRP then
		return require(script.Parent:WaitForChild("ChaseState"))
	end

	-- DO NOT attack downed or recovering opponents!
	local targetState = target:GetAttribute("CurrentState")
	if targetState == "Knockback" or targetState == "Airborne" or targetState == "Recovery" or target:GetAttribute("GetUpProtection") == true then
		if DEBUG then print("[Fight] Opponent is down/recovering! Entering tactical standoff.") end
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
	local pjChance = fighter:GetAttribute("ProjectileJumpChance") or CombatConfig.ProjectileJumpChance or 0.08

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

	-- Close but out of reach (a wall or a platform edge between them): Chase finds the way
	-- round. Half a second of grace so a body passing between them does not end the fight.
	if NavigationModule.isReachable(rootPart, targetHRP) then
		data.unreachableSince = nil
	else
		data.unreachableSince = data.unreachableSince or now
		if now - data.unreachableSince > 0.5 then
			data.unreachableSince = nil
			return require(script.Parent:WaitForChild("ChaseState"))
		end
	end
	
	-- Face target smoothly via physics torque AlignOrientation (Zero CFrame snapping / yaw pop)
	local yDiff = math.abs(targetHRP.Position.Y - rootPart.Position.Y)
	if yDiff < 5 then
		local lookCF = CFrame.lookAt(rootPart.Position, Vector3.new(targetHRP.Position.X, rootPart.Position.Y, targetHRP.Position.Z))
		local alignOri = rootPart:FindFirstChild("FightGyro")
		if not alignOri then
			alignOri = Instance.new("AlignOrientation")
			alignOri.Name = "FightGyro"
			alignOri.Mode = Enum.OrientationAlignmentMode.OneAttachment
			local att = rootPart:FindFirstChild("RootAttachment") or Instance.new("Attachment", rootPart)
			att.Name = "RootAttachment"
			alignOri.Attachment0 = att
			alignOri.RigidityEnabled = false
			alignOri.Responsiveness = 22
			alignOri.MaxTorque = 60000
			-- Without a cap the body whipped round at 18-26 rad/s (over 1000 degrees/s) whenever
			-- the target changed or passed close by
			alignOri.MaxAngularVelocity = CombatConfig.Combat_FacingMaxTurnRate or 14
			alignOri.CFrame = rootPart.CFrame
			alignOri.Parent = rootPart
		end
		-- The rear-turn counter stiffens the gyro for its turn; it used to stay stiff for the
		-- rest of the fight
		if data.currentAction ~= "rear_turn_counter" and alignOri.Responsiveness ~= 22 then
			alignOri.Responsiveness = 22
		end
		alignOri.CFrame = lookCF
	end
	
	-- Distance management
	local idealRange = CombatConfig.CombatRange or 8
	local locoDt = math.clamp(now - (data.lastLocoTime or (now - 0.05)), 1 / 60, 0.25)
	data.lastLocoTime = now
	-- Hysteresis on the approach: start closing past idealRange + 2, keep closing until just
	-- outside idealRange. A single threshold flipped between step-in and brake every few ticks
	-- whenever the target shuffled around it, restarting the legs each time.
	if distance > idealRange + 2.0 then
		data.closingGap = true
	elseif distance <= idealRange + 0.3 then
		data.closingGap = false
	end
	-- Planted while its own strike plays: the punch clip owns the legs, and still being steered
	-- at up to 40 studs/s underneath it (plus the lunge) the feet glided - punches thrown on the
	-- run slid on 56-59% of frames. The strike's own lunge is the step.
	local striking = fighter:GetAttribute("Attacking") == true and now < (data.attackFinishTime or 0)
		and CombatConfig.Fight_PlantWhileStriking ~= false
	if striking then
		LocomotionModule.brake(fighter, humanoid, rootPart, locoDt)
	elseif data.closingGap then
		-- Close the gap through the shared locomotion path (acceleration, turn rate, gait).
		-- Approach pace scales with the gap so a 2-stud correction is a step, not a sprint burst.
		local maxApproach = fighter:GetAttribute("Speed") or 40
		local approachSpeed = math.clamp(8 + (distance - idealRange) * 4, 10, maxApproach)
		LocomotionModule.steer(fighter, humanoid, rootPart, targetHRP.Position, approachSpeed, locoDt)
		GaitModule.update(humanoid, rootPart, locoDt)
	elseif distance < (CombatConfig.Melee_SweetSpotMin or 4.5) then
		-- Point blank overlap: smooth physics micro-slide with momentum continuity & spacing animation
		LocomotionModule.brake(fighter, humanoid, rootPart, locoDt)
		local awayDir = (rootPart.Position - targetHRP.Position)
		local awayFlat = Vector3.new(awayDir.X, 0, awayDir.Z)
		-- Only once the body has shed its own speed: the spacing mover has full authority, so
		-- applied to a Quin still running in it reversed 40-50 studs/s in a single frame.
		local ownVel = rootPart.AssemblyLinearVelocity
		-- Not during its own strike either: backing off mid-swing and lunging on the next one
		-- rocked the body back and forth.
		if awayFlat.Magnitude > 0.01 and Vector3.new(ownVel.X, 0, ownVel.Z).Magnitude < 16 and fighter:GetAttribute("Attacking") ~= true then
			KnockbackModule.applySlide(fighter, awayFlat.Unit, CombatConfig.Melee_SlideSpeed or 10, 0.3) -- refreshed each tick; eases out once spacing is restored
			if not AnimationModule.isPlaying(humanoid, AnimationIds.RetreatBackstep) then
				AnimationModule.play(humanoid, AnimationIds.RetreatBackstep, Enum.AnimationPriority.Movement, false, 1.2, 0.1)
			end
		end
	else
		-- Inside the combat sweet spot: hold stance firmly with momentum continuity
		LocomotionModule.brake(fighter, humanoid, rootPart, locoDt)
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
		-- Between its own attacks the Quin can still see a strike coming and guard it
		if distance <= 9 then
			tryRaiseGuard(fighter, humanoid, data, now, target, reactiveGuardChance(fighter))
		end
		-- Maintain base idle stance during recovery / cooldown
		if now >= (data.attackFinishTime or 0) then
			AnimationModule.ensureBaseIdle(humanoid)
		end
		return FightState
	end
	
	-- DECIDE ACTION
	local action = decideAction(fighter, target, distance, data)

	-- A strike is only thrown at a target the step-in can reach. Out of reach the Quin keeps
	-- closing (the approach above) instead of swinging at air and losing its combo.
	if (action == "light" or action == "heavy") and distance > (CombatConfig.Combat_StrikeRange or 10.0) then
		-- Step in now. The approach only restarts past idealRange + 2 (10.2), beyond the strike
		-- range (9): a Quin left 9-10 studs out neither struck nor closed, and two of them stood
		-- facing each other (21% of close fighting, up to 11 s at a time).
		data.closingGap = true
		return FightState
	end
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
		
	elseif action == "answer_jump" then
		-- Taken up by the projectile-jump check at the top of the next tick
		fighter:SetAttribute("ForceAction", "projectile_jump")
		return FightState

	elseif action == "anticipate" then
		data.currentAction = "anticipate"
		data.actionEndTime = now + (0.3 / speedMult)
		data.attackFinishTime = now + (0.3 / speedMult)
		-- (full-body clip: on the move only the head and shoulders look back)
		local v = rootPart.AssemblyLinearVelocity
		if Vector3.new(v.X, 0, v.Z).Magnitude > 6 then
			fighter:SetAttribute("GlanceBackUntil", workspace:GetServerTimeNow() + 0.6)
		else
			AnimationModule.playConfig(humanoid, "Awareness.RearThreatGlance", 1.0, Enum.AnimationPriority.Action2, false)
		end
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
			-- Fast turn through the facing gyro instead of an instant 180 degree CFrame flip.
			local facingGyro = rootPart:FindFirstChild("FightGyro")
			if facingGyro then
				facingGyro.Responsiveness = 45
				facingGyro.CFrame = turnLook
			else
				rootPart.CFrame = turnLook
			end
			-- The pivot clip carries its own 177 degree hip rotation (see CombatConfig.Turn180PivotClipEnabled)
			if CombatConfig.Turn180PivotClipEnabled == true then
				AnimationModule.playConfig(humanoid, "Awareness.Turn180Pivot", 1.5, Enum.AnimationPriority.Action4, false)
			end
			
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
				-- Carves breathing room like a finisher: knocks the victim back along the ground,
				-- or launches it by the same chance
				applyHitOutcome(rootPart, hitModel, DESPERATE_COUNTER_MOVE, DamageModule.resolveOutcome(fighter, hitModel, DESPERATE_COUNTER_MOVE, damageInfo))
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

return FightState