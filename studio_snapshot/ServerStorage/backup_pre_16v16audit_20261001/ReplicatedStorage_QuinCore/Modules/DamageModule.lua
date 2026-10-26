--// DamageModule.lua
-- Calculates and applies damage between fighters
-- Handles crits, defense, combo scaling, super meter, causal guarding, and hitstop

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local AudioModule = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("AudioModule"))
local AnimationModule = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("AnimationModule"))
local KnockbackModule = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("KnockbackModule"))
local VfxModule = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("VfxModule"))
local AnimationIds = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("AnimationIds"))
local CombatConfig = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("CombatConfig"))
local BattleEventSystem = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("BattleEventSystem"))

local DamageModule = {}

-- Calculate damage
function DamageModule.calculate(attackerModel, targetModel, comboStep, damageMultiplier)
	local baseDamage = attackerModel:GetAttribute("Damage") or 10
	local attackSpeed = attackerModel:GetAttribute("AttackSpeed") or 1.0
	local critChance = attackerModel:GetAttribute("CriticalHitChance") or 0.1
	local defense = targetModel:GetAttribute("Defense") or 0
	
	-- Combo scaling: +10% per combo step
	local comboBonus = 1.0 + ((comboStep or 1) - 1) * 0.10
	
	-- Crit roll
	local isCrit = math.random() < critChance
	local critMultiplier = isCrit and 2.0 or 1.0
	
	-- Final calc
	local finalDamage = baseDamage * (damageMultiplier or 1.0) * comboBonus * critMultiplier * attackSpeed

	-- Phase 12 Spectacle: AuraSurge offensive boost
	if (attackerModel:GetAttribute("AuraSurgeUntil") or 0) > tick() then
		finalDamage = finalDamage * 1.20
	end

	-- Phase 12 Spectacle: Vulnerability penalty if target is showboating (aura farming)
	if targetModel:GetAttribute("IsAuraFarming") == true then
		finalDamage = finalDamage * (CombatConfig.AuraFarm_VulnerabilityMultiplier or 1.15)
	end

	finalDamage = math.max(finalDamage - defense, 1) -- min 1 damage
	finalDamage = math.floor(finalDamage + 0.5)
	
	return {
		damage = finalDamage,
		isCrit = isCrit,
		comboStep = comboStep,
		comboBonus = comboBonus,
	}
end

-- Apply damage to target
function DamageModule.apply(attackerModel, targetModel, damageInfo)
	local targetHum = targetModel:FindFirstChildOfClass("Humanoid")
	local attackerHum = attackerModel:FindFirstChildOfClass("Humanoid")
	if not targetHum or targetHum.Health <= 0 then return false end

	-- LEADER SHOWDOWN SACRED SPECTATOR IMMUNITY (Respect & Anti-Bullying)
	local attackerRole = attackerModel:GetAttribute("LeaderShowdownRole")
	local targetRole = targetModel:GetAttribute("LeaderShowdownRole")
	local isShowdownActive = (workspace:GetAttribute("LeaderShowdownActive") == true) or (attackerRole ~= nil) or (targetRole ~= nil)

	if isShowdownActive then
		-- Spectators and transitions are completely immune and cannot deal or receive damage
		if attackerRole == "PerimeterGuard" or attackerRole == "Transition" or targetRole == "PerimeterGuard" or targetRole == "Transition" then
			return false, false, "ProtectedSpectator"
		end
		-- In an active showdown, only Duelist vs Duelist exchanges are permitted
		if attackerRole ~= "Duelist" or targetRole ~= "Duelist" then
			return false, false, "ShowdownUnauthorized"
		end
	end
	
	local isKnocked = targetModel:GetAttribute("CurrentState") == "Knockback" or targetModel:GetAttribute("CurrentState") == "Airborne"
	local hrp = targetModel:FindFirstChild("HumanoidRootPart")
	local attackerHRP = attackerModel:FindFirstChild("HumanoidRootPart")

	-- CAUSAL DEFENSE: Check if defender is actively guarding when the strike lands
	if not isKnocked and targetModel:GetAttribute("IsGuarding") == true then
		-- Directional check: convert attacker position into defender local space
		local blockAnimPath = "Reactions.BlockFront"
		local isBehind = false
		if hrp and attackerHRP then
			local localPos = hrp.CFrame:PointToObjectSpace(attackerHRP.Position)
			-- In local space: -Z is front, +Z is back, -X is left, +X is right
			if localPos.Z > 0.5 then
				-- ATTACK FROM BEHIND: Guard is bypassed! Flanking punishes defender!
				isBehind = true
			elseif localPos.Z < 0 and math.abs(localPos.X) <= math.abs(localPos.Z) * 0.85 then
				blockAnimPath = "Reactions.BlockFront"
			elseif localPos.X < 0 then
				blockAnimPath = "Reactions.BlockLeft"
			else
				blockAnimPath = "Reactions.BlockRight"
			end
		end

		if not isBehind then
			-- Roll success vs failure
			local blockChance = targetModel:GetAttribute("BlockChance") or 0.70
			local isSuccess = math.random() < blockChance

			if isSuccess then
				-- Play block impact sound
				if hrp then
					AudioModule.playImpact(hrp.Position, false)
				end

				-- Play directional block reaction animation
				AnimationModule.playConfig(targetHum, blockAnimPath, 1.25, Enum.AnimationPriority.Action4, false)

				-- Slide backward slightly from the blocked impact
				if hrp and attackerHRP then
					local awayDir = (hrp.Position - attackerHRP.Position).Unit
					KnockbackModule.applyMicroKnockback(targetModel, awayDir, 4.0)
				end

				-- Trigger Immediate Counter-Attack
				targetModel:SetAttribute("ImmediateCounter", true)
				targetModel:SetAttribute("ImmediateCounterTarget", attackerModel.Name)
				targetModel:SetAttribute("ForceState", "Fight")

				return false, false, "Blocked"
			else
				-- Guard failed! Clear guard and let strike apply full damage & flinch
				targetModel:SetAttribute("IsGuarding", false)
			end
		else
			-- Flanked from behind! Break guard immediately and mark vulnerable
			targetModel:SetAttribute("IsGuarding", false)
			damageInfo.isBackAttack = true
		end
	end
	
	targetHum:TakeDamage(damageInfo.damage)
	
	local isHeavy = damageInfo.damage > (attackerModel:GetAttribute("Damage") or 10) * 1.5
	
	-- Posture System & Accumulated Damage
	local posture = targetModel:GetAttribute("Posture") or 100
	local postureDamage = isHeavy and 25 or 8
	if damageInfo.isBackAttack then
		postureDamage = math.floor(postureDamage * 1.5)
	end
	posture = posture - postureDamage
	
	if posture <= 0 then
		-- GUARD BREAK!
		posture = 100
		
		-- Force them into a heavy stagger instead of a knockdown recovery
		if hrp and attackerHRP then
			local dir = (hrp.Position - attackerHRP.Position).Unit
			KnockbackModule.applySlide(targetModel, dir, 45, 0.5)
			targetModel:SetAttribute("StunEndTime", tick() + 1.2) -- Massive stun
			AudioModule.playSlam(hrp.Position)
		end
	end
	targetModel:SetAttribute("Posture", posture)
	
	-- Audio Hook
	if hrp then
		AudioModule.playImpact(hrp.Position, isHeavy)
	end
	
	-- Hit Stop (Freeze Frames) & Replicated Visual Reactions
	if attackerHum and targetHum and hrp and attackerHRP then
		local hitStopDuration = isHeavy and 0.08 or 0.05
		
		-- Replicate hitstop timestamp to client visual ghosts
		local serverTime = workspace:GetServerTimeNow()
		attackerModel:SetAttribute("HitStopUntil", serverTime + hitStopDuration)
		targetModel:SetAttribute("HitStopUntil", serverTime + hitStopDuration)
		
		AnimationModule.applyHitStop(attackerHum, hitStopDuration)
		AnimationModule.applyHitStop(targetHum, hitStopDuration)
		
		-- Micro Knockback (flinching/giving ground, scales with combo step to match attacker lunge)
		local pushDir = (hrp.Position - attackerHRP.Position).Unit
		local pushAmount = 3.0 + ((damageInfo.comboStep or 1) * 1.5)
		if isHeavy then pushAmount = pushAmount + 2.5 end
		KnockbackModule.applyMicroKnockback(targetModel, pushDir, pushAmount)

		-- Procedural Combat Reaction Telemetry (replicated to visual ghost)
		targetModel:SetAttribute("ImpactTime", serverTime)
		targetModel:SetAttribute("ImpactDir", pushDir)
		targetModel:SetAttribute("ImpactMag", math.clamp(pushAmount / 10, 0.2, 1.0))
		targetModel:SetAttribute("ImpactType", isHeavy and "HEAVY" or "LIGHT")
		
		-- Hit Stun Duration
		local stunDuration = isHeavy and 0.5 or 0.35
		targetModel:SetAttribute("StunEndTime", tick() + stunDuration)
		
		-- Hit Animation Overlay (Action3 so it never cancels the defender's own attack track;
		-- during a simultaneous exchange both jabs now play out instead of being wiped by the flinch)
		if not isKnocked then
			local hitAnims = AnimationIds.Hits
			if hitAnims and #hitAnims > 0 then
				local randHit = hitAnims[math.random(1, #hitAnims)]
				AnimationModule.play(targetHum, randHit, Enum.AnimationPriority.Action3, false, 1.0, 0.05, false)
			end
		end
		
		-- Stylized Hit VFX
		if CombatConfig.VfxStylizedHits and hrp and attackerHRP then
			local hitPos = hrp.Position + (attackerHRP.Position - hrp.Position).Unit * 1.5
			VfxModule.createStylizedHit(hitPos, isHeavy, attackerModel:GetAttribute("Element") or "Fire")
		end
	end
	
	-- Super meter gain for attacker
	local currentSuper = attackerModel:GetAttribute("SuperMeter") or 0
	local superGain = attackerModel:GetAttribute("SuperGainPerHit") or 5
	local maxSuper = attackerModel:GetAttribute("SuperMeterMax") or 100
	attackerModel:SetAttribute("SuperMeter", math.min(currentSuper + superGain, maxSuper))
	
	-- Super meter gain for target (taking damage builds meter)
	local tCurrentSuper = targetModel:GetAttribute("SuperMeter") or 0
	local tSuperGain = targetModel:GetAttribute("SuperGainOnTakeDamage") or 8
	local tMaxSuper = targetModel:GetAttribute("SuperMeterMax") or 100
	targetModel:SetAttribute("SuperMeter", math.min(tCurrentSuper + tSuperGain, tMaxSuper))
	
	-- Track Attacker Identity and Match Combat Stats (Phase 11 Persistence)
	local attackerQuinId = attackerModel:GetAttribute("QuinId")
	if attackerQuinId then
		targetModel:SetAttribute("LastAttackerQuinId", attackerQuinId)
		targetModel:SetAttribute("LastAttackerName", attackerModel.Name)

		local curDmg = attackerModel:GetAttribute("MatchDamageDealt") or 0
		attackerModel:SetAttribute("MatchDamageDealt", curDmg + damageInfo.damage)
	end

	-- Check kill & Phase 12 Spectacle: Rival Finisher
	local isKill = targetHum.Health <= 0
	if isKill then
		if attackerQuinId then
			local curKills = attackerModel:GetAttribute("MatchKills") or 0
			attackerModel:SetAttribute("MatchKills", curKills + 1)
		end

		-- Check if target is a designated rival
		local primaryRival = attackerModel:GetAttribute("PrimaryRivalId")
		local targetQuinId = targetModel:GetAttribute("QuinId")
		local isRival = (primaryRival and targetQuinId and primaryRival == targetQuinId) or (targetModel:GetAttribute("LastRivalTarget") == attackerModel.Name)

		-- Categorize death type: OnTheSpot (fatal finisher, heavy decisive hit, rival kill, or executed while down) vs Standard
		local attackerState = attackerModel:GetAttribute("CurrentState") or ""
		local targetState = targetModel:GetAttribute("CurrentState") or ""
		local isDecisiveBlow = damageInfo.isFinisher 
			or (damageInfo.damage >= 25) 
			or (attackerState == "Special") 
			or (targetState == "Knockback") 
			or (targetState == "Recovery") 
			or (targetState == "Stun")

		if isRival or isDecisiveBlow then
			targetModel:SetAttribute("DeathType", "OnTheSpot")
		else
			targetModel:SetAttribute("DeathType", "Standard")
		end

		if isRival and attackerHRP and hrp then
			-- 1. Play placeholder finisher animation on attacker
			if AnimationIds.RivalFinisher and attackerHum then
				AnimationModule.play(attackerHum, AnimationIds.RivalFinisher, Enum.AnimationPriority.Action4, false, 1.15, 0.05, false)
			end

			-- 2. Physical weighted ~20 stud knockback on the rival
			local awayDir = (hrp.Position - attackerHRP.Position)
			local pushUnit = (awayDir.Magnitude > 0.1) and awayDir.Unit or attackerHRP.CFrame.LookVector
			local kbForce = CombatConfig.RivalFinisher_KnockbackForce or 140.0
			local kbDur = CombatConfig.RivalFinisher_KnockbackDuration or 0.40
			KnockbackModule.applyKnockback(targetModel, pushUnit + Vector3.new(0, 0.2, 0), kbForce, kbDur)
			targetModel:SetAttribute("KnockbackType", "hard_ground")

			-- 3. Crisp impact sound and visual feedback
			VfxModule.createFinisherImpact(hrp.Position, attackerModel:GetAttribute("Element") or "Fire")
			AudioModule.playSlam(hrp.Position)

			-- 4. Emit RIVAL_FINISHER battle event
			BattleEventSystem.emit("RIVAL_FINISHER", {
				Attacker = attackerModel,
				Target = targetModel,
				QuinId = attackerQuinId or attackerModel.Name,
				TargetName = targetModel.Name,
				Element = attackerModel:GetAttribute("Element") or "Fire",
				Extra = "Decisive Rival Finisher Executed"
			})

			-- Attacker confidence surge
			local curConf = attackerModel:GetAttribute("Pers_Confidence") or 0.6
			attackerModel:SetAttribute("Pers_Confidence", math.min(1.0, curConf + 0.20))
		end
	end

	return true, isKill, "Hit"
end

return DamageModule
