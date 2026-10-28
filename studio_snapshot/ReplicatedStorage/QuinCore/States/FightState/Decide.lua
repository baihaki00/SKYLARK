--// FightState/Decide.lua
-- What a fighter does next when nothing else has decided it (a special, the cornered counter,
-- a combo going on, a reaction to a wind-up, a jump at it or a threat behind, a dodge or block,
-- a dash in, a heavy or a light). Its defensive branch runs only with Instinct off (ablation):
-- Instinct answers strikes otherwise.
-- (Moved out of FightState as it was: QuinCore audit 2026-10-27, step 7.)

local GameClock = require(game:GetService("ReplicatedStorage"):WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("GameClock")) -- (the game's clock: a freeze stops it)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ComboModule = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("ComboModule"))
local CombatConfig = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("CombatConfig"))
local Instinct = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("Instinct"))
local Pers = require(game:GetService("ReplicatedStorage"):WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("Pers")) -- (personality reads + defaults, one place)

local Decide = {}

-- AI Decision Engine
local function decideAction(fighter, target, distance, data)
	local isLastStand = fighter:GetAttribute("LastStandMode") == true
	-- (its own personality: this read "Aggression" / "SpecialPreference", which nothing writes,
	-- so every Quin fought at 0.7 and 0.3 whatever it was like)
	local aggression = Pers.get(fighter, "Aggression")
	if isLastStand then
		aggression = math.min(1.0, aggression + (CombatConfig.LastStandAggressionBonus or 0.50))
	end
	local specialPref = Pers.get(fighter, "SpecialPreference")
	local specialCooldown = fighter:GetAttribute("SpecialCooldown") or 8
	local now = GameClock.tick()
	
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
	if targetAttacking and now < targetWindupUntil and distance <= 9 and not Instinct.enabled() then
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
				and (fighter:GetAttribute("Energy") or 100) >= (CombatConfig.ProjectileJumpMinEnergy or 40)
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
			local awareness = Pers.get(fighter, "Awareness")
			local occupiedQuadrants = fighter:GetAttribute("OccupiedQuadrants") or 1
			local isBeingBullied = fighter:GetAttribute("BeingBullied")
			local defensePref = Pers.get(fighter, "DefensePreference")
			
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
	local dashMin = CombatConfig.DashMinDistance or 15
	local dashMax = CombatConfig.DashMaxDistance or 60
	local minDashMana = CombatConfig.DashMinEnergy or 25
	local lastDash = fighter:GetAttribute("LastDashTime") or 0
	local speedMult = workspace:GetAttribute("GameSpeedMultiplier") or 1.0
	local dashCooldown = 8.0 / speedMult
	local isDashOnCooldown = (now - lastDash) < dashCooldown
	local energy = fighter:GetAttribute("Energy") or 100
	if not isDashOnCooldown and energy >= minDashMana and distance >= dashMin and distance <= dashMax and roll < (CombatConfig.DashAttackChance or 0.20) then
		return "dash"
	end
	
	-- Heavy attack (less frequent, more damage)
	if roll < 0.20 + aggression * 0.1 then
		return "heavy"
	end
	
	-- Light combo (default)
	return "light"
end

Decide.action = decideAction

return Decide
