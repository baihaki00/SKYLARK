--// BeamStruggleState.lua
-- Phase 12 Spectacle: Dynamic Anime Beam Struggle & Power Clash State Machine
-- Features:
-- 1. Power-Up wind-up phase (0.5s - 0.85s) with charging stance, ground tremor, and inward gathering auras.
-- 2. Staggered beam ignition with organic execution / reaction delay (0.04s - 0.12s).
-- 3. Dynamic back-and-forth tug-of-war rope tie-breaker driven by continuous -2 mana drain and -5 mana tactical surges.
-- 4. Fatal breach resolution: losing beam collapses, winning beam pierces through, dealing 55 damage and ~25 studs knockback.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")

local AnimationModule = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("AnimationModule"))
local AudioModule = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("AudioModule"))
local VfxModule = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("VfxModule"))
local KnockbackModule = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("KnockbackModule"))
local DamageModule = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("DamageModule"))
local TargetingModule = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("TargetingModule"))
local SpatialModule = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("SpatialModule"))
local CombatConfig = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("CombatConfig"))
local BattleEventSystem = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("BattleEventSystem"))

local BeamStruggleState = { name = "BeamStruggle" }
local struggleData = {}

-- Canonical Pentagonal Elemental Advantage Cycle (+35% push force)
-- Water -> Fire -> Wind -> Stone -> Lightning -> Water
local ELEMENTAL_ADVANTAGE = {
	Water = "Fire",
	Fire = "Wind",
	Wind = "Stone",
	Stone = "Lightning",
	Lightning = "Water",
}

-- Aliases
ELEMENTAL_ADVANTAGE.Ice = "Fire"
ELEMENTAL_ADVANTAGE.Earth = "Lightning"
ELEMENTAL_ADVANTAGE.Electric = "Water"

local function getElementalMultiplier(attackerElem, defenderElem)
	attackerElem = (attackerElem == "Ice" and "Water") or (attackerElem == "Earth" and "Stone") or (attackerElem == "Electric" and "Lightning") or attackerElem
	defenderElem = (defenderElem == "Ice" and "Water") or (defenderElem == "Earth" and "Stone") or (defenderElem == "Electric" and "Lightning") or defenderElem

	if ELEMENTAL_ADVANTAGE[attackerElem] == defenderElem then
		return CombatConfig.BeamStruggle_ElemAdvantageMult or 1.35
	elseif ELEMENTAL_ADVANTAGE[defenderElem] == attackerElem then
		return 1.0 / (CombatConfig.BeamStruggle_ElemAdvantageMult or 1.35)
	end
	return 1.0
end

local function cleanupPhysicsMovers(rootPart)
	for _, child in ipairs(rootPart:GetChildren()) do
		if child.Name == "BeamStruggle_AntiGrav" or child.Name == "BeamStruggle_Att" or child.Name == "BeamStruggle_Gyro" then
			child:Destroy()
		end
	end
end

function BeamStruggleState.enter(fighter, humanoid, rootPart)
	humanoid.WalkSpeed = 0
	cleanupPhysicsMovers(rootPart)

	local isGrounded = SpatialModule.isGrounded(rootPart)

	-- Identify partner
	local targetName = fighter:GetAttribute("TargetQuin")
	local target = nil
	if targetName and targetName ~= "" then
		local serverFolder = Workspace:FindFirstChild("QuinServer") or Workspace
		target = serverFolder:FindFirstChild(targetName)
	end
	if not target then
		target, _ = TargetingModule.getNearest(rootPart, 80)
	end

	local role = "Leader"
	local partnerFighter = target
	local elemA = fighter:GetAttribute("Element") or "Fire"

	local powerUpDur = math.random(55, 80) / 100
	local reactionDelay = math.random(4, 12) / 100

	if target and target:IsA("Model") then
		local targetHRP = target:FindFirstChild("HumanoidRootPart")
		if targetHRP then
			if target:GetAttribute("BeamStruggleRole") == "Leader" and target:GetAttribute("BeamStrugglePartner") == fighter.Name then
				role = "Follower"
				powerUpDur = target:GetAttribute("ClashPowerUpDur") or powerUpDur
				reactionDelay = target:GetAttribute("ClashReactionDelay") or reactionDelay
			else
				role = "Leader"
				fighter:SetAttribute("BeamStruggleRole", "Leader")
				fighter:SetAttribute("BeamStrugglePartner", target.Name)
				target:SetAttribute("BeamStruggleRole", "Follower")
				target:SetAttribute("BeamStrugglePartner", fighter.Name)
				target:SetAttribute("ForceState", "BeamStruggle")

				-- Timing configurations
				fighter:SetAttribute("ClashPowerUpDur", powerUpDur)
				fighter:SetAttribute("ClashReactionDelay", reactionDelay)

				-- Initial clash geometry
				local midPos = (rootPart.Position + targetHRP.Position) / 2
				local flatDiff = Vector2.new(targetHRP.Position.X - rootPart.Position.X, targetHRP.Position.Z - rootPart.Position.Z)
				local initAngle = math.atan2(flatDiff.Y, flatDiff.X)
				local distance = flatDiff.Magnitude

				fighter:SetAttribute("ClashCenterX", midPos.X)
				fighter:SetAttribute("ClashCenterY", midPos.Y)
				fighter:SetAttribute("ClashCenterZ", midPos.Z)
				fighter:SetAttribute("ClashAngle", initAngle)
				fighter:SetAttribute("ClashDist", distance)
				fighter:SetAttribute("ClashNodeOffset", 0.0) -- Normalized [-1, +1]
				fighter:SetAttribute("ClashPhase", "PowerUp")
			end
		end
	end

	-- Authoritative Mid-Air Gravity Bypass (Deterministic airborne suspension)
	if not isGrounded then
		humanoid.PlatformStand = true
		rootPart.Anchored = true
	end

	-- Channeling / Power-Up Stance
	AnimationModule.playConfig(humanoid, "Attacks.Specials.BeamStruggle", 1.0, Enum.AnimationPriority.Action4)

	-- Phase 1: Power-up charge gathering VFX
	local chargeVfx = VfxModule.createChargePowerUpVfx(rootPart, powerUpDur, elemA)

	fighter:SetAttribute("CurrentState", "BeamStruggle")
	fighter:SetAttribute("StruggleSubPhase", "PowerUp")
	rootPart.AssemblyLinearVelocity = Vector3.zero

	struggleData[fighter] = {
		startTime = tick(),
		role = role,
		partner = partnerFighter,
		isGrounded = isGrounded,
		startY = rootPart.Position.Y,
		clashNode = nil,
		vfxHandle = nil,
		chargeVfx = chargeVfx,
		powerUpDur = powerUpDur,
		reactionDelay = reactionDelay,
		beamsSpawned = false,
		followerIgnited = false,
		lastDrainTime = tick(),
		lastDecisionTime = tick(),
		lastShakeTime = tick(),
		lastObservedPartnerSurge = 0,
		resolved = false,
	}

	-- Telemetry
	BattleEventSystem.emit("BEAM_STRUGGLE_START", {
		QuinId = fighter:GetAttribute("QuinId") or fighter.Name,
		Model = fighter,
		TargetName = partnerFighter and partnerFighter.Name or "Unknown",
		Element = elemA,
		Extra = string.format("Role: %s | PowerUpDur: %.2fs | ReactionDelay: %.2fs", role, powerUpDur, reactionDelay)
	})
end

function BeamStruggleState.exit(fighter, humanoid, rootPart)
	rootPart.Anchored = false
	humanoid.PlatformStand = false
	cleanupPhysicsMovers(rootPart)

	local data = struggleData[fighter]
	if data then
		if data.chargeVfx and data.chargeVfx.destroy then
			data.chargeVfx.destroy()
		end
		-- If breach was initiated, preserve beams and clash node for the sustained impact surge!
		local isBreach = data.breachInitiated or (fighter:GetAttribute("StruggleSubPhase") == "Breach")
		if not isBreach then
			if data.vfxHandle and data.vfxHandle.destroy then
				data.vfxHandle.destroy()
			end
			if data.clashNode and data.clashNode.Parent then
				data.clashNode:Destroy()
			end
		else
			if data.clashNode and data.clashNode.Parent then
				Debris:AddItem(data.clashNode, 0.75)
			end
			local vfx = data.vfxHandle
			task.delay(0.75, function()
				if vfx and vfx.destroy then
					vfx.destroy()
				end
			end)
		end
	end

	fighter:SetAttribute("BeamStruggleRole", nil)
	fighter:SetAttribute("BeamStrugglePartner", nil)
	fighter:SetAttribute("ClashCenterX", nil)
	fighter:SetAttribute("ClashCenterY", nil)
	fighter:SetAttribute("ClashCenterZ", nil)
	fighter:SetAttribute("ClashAngle", nil)
	fighter:SetAttribute("ClashDist", nil)
	fighter:SetAttribute("ClashNodeOffset", nil)
	fighter:SetAttribute("ClashPhase", nil)
	fighter:SetAttribute("StruggleSubPhase", nil)
	fighter:SetAttribute("LastSurgeTick", nil)

	struggleData[fighter] = nil
	local baseSpeed = fighter:GetAttribute("Speed") or 40
	humanoid.WalkSpeed = baseSpeed
end

function BeamStruggleState.update(fighter, humanoid, rootPart, DEBUG)
	local data = struggleData[fighter]
	if not data then
		return require(script.Parent:WaitForChild("FightState"))
	end

	local now = tick()
	local elapsed = now - data.startTime
	local partner = data.partner

	-- Fallback if partner died or vanished
	if not partner or not partner.Parent or not partner:FindFirstChild("HumanoidRootPart") then
		return require(script.Parent:WaitForChild("FightState"))
	end

	local partnerHRP = partner.HumanoidRootPart
	local partnerHum = partner:FindFirstChildOfClass("Humanoid")
	if not partnerHum or partnerHum.Health <= 0 then
		return require(script.Parent:WaitForChild("FightState"))
	end

	local leaderModel = (data.role == "Leader") and fighter or partner
	local followerModel = (data.role == "Leader") and partner or fighter
	local speedMult = workspace:GetAttribute("GameSpeedMultiplier") or 1.0
	local powerUpDur = leaderModel:GetAttribute("ClashPowerUpDur") or data.powerUpDur or 0.65
	local reactionDelay = leaderModel:GetAttribute("ClashReactionDelay") or data.reactionDelay or 0.06

	local elemA = leaderModel:GetAttribute("Element") or "Fire"
	local elemB = followerModel:GetAttribute("Element") or "Water"

	-- ============================================================
	-- SUB-PHASE 1: POWER-UP CHARGE (0.5s - 0.85s)
	-- ============================================================
	if elapsed < powerUpDur then
		fighter:SetAttribute("StruggleSubPhase", "PowerUp")
		-- Airborne dynamic bobbing + kinetic tremor while charging
		local phaseSign = (data.role == "Leader") and 1 or -1
		local bobAmp = data.isGrounded and 0 or (CombatConfig.BeamStruggle_BobAmplitude or 0.75)
		local bobFreq = CombatConfig.BeamStruggle_BobFrequency or 3.2
		local yBob = data.isGrounded and 0 or (phaseSign * math.sin(elapsed * bobFreq) * bobAmp * 0.45)
		local shakeX = (math.random() - 0.5) * 0.10
		local shakeY = data.isGrounded and 0 or ((math.random() - 0.5) * 0.10)
		local shakeZ = (math.random() - 0.5) * 0.10
		local desiredPos = Vector3.new(rootPart.Position.X, data.startY + yBob, rootPart.Position.Z)
		rootPart.CFrame = CFrame.lookAt(desiredPos + Vector3.new(shakeX, shakeY, shakeZ), Vector3.new(partnerHRP.Position.X, desiredPos.Y, partnerHRP.Position.Z))
		rootPart.AssemblyLinearVelocity = Vector3.zero
		return BeamStruggleState
	end

	-- ============================================================
	-- SUB-PHASE 2: STAGGERED BEAM IGNITION (0.04s - 0.12s gap)
	-- ============================================================
	if data.role == "Leader" and not data.beamsSpawned then
		data.beamsSpawned = true
		leaderModel:SetAttribute("ClashPhase", "Ignition")
		fighter:SetAttribute("StruggleSubPhase", "Ignition")

		-- Create central clash node part
		local centerX = leaderModel:GetAttribute("ClashCenterX") or rootPart.Position.X
		local centerY = leaderModel:GetAttribute("ClashCenterY") or rootPart.Position.Y
		local centerZ = leaderModel:GetAttribute("ClashCenterZ") or rootPart.Position.Z
		local midPos = Vector3.new(centerX, centerY, centerZ)

		local clashNode = Instance.new("Part")
		clashNode.Name = "BeamClashNode_" .. fighter.Name
		clashNode.Shape = Enum.PartType.Ball
		clashNode.Material = Enum.Material.Neon
		clashNode.Color = Color3.fromRGB(255, 255, 255)
		clashNode.Size = Vector3.new(2.0, 2.0, 2.0)
		clashNode.Anchored = true
		clashNode.CanCollide = false
		clashNode.Position = midPos
		clashNode.Parent = Workspace

		local vfxHandle = VfxModule.createBeamStruggleVfx(rootPart, partnerHRP, clashNode, elemA, elemB)
		-- Leader beam fires first! Follower beam waits for reaction delay
		vfxHandle.setBeamEnabled(true, true)
		vfxHandle.setBeamEnabled(false, false)

		data.clashNode = clashNode
		data.vfxHandle = vfxHandle

		if DEBUG then print(string.format("[BeamStruggle] Leader ignited beam! Follower reacting in %.3fs", reactionDelay)) end
	end

	-- Follower ignition after reaction delay
	if data.role == "Leader" and data.beamsSpawned and not data.followerIgnited then
		if elapsed >= (powerUpDur + reactionDelay) then
			data.followerIgnited = true
			leaderModel:SetAttribute("ClashPhase", "TugOfWar")
			fighter:SetAttribute("StruggleSubPhase", "TugOfWar")
			partner:SetAttribute("StruggleSubPhase", "TugOfWar")

			if data.vfxHandle and data.vfxHandle.setBeamEnabled then
				data.vfxHandle.setBeamEnabled(false, true)
			end
			AudioModule.playSlam(data.clashNode and data.clashNode.Position or rootPart.Position)
			if DEBUG then print("[BeamStruggle] Counter-beam connected! Tug of war engaged.") end
		end
	end

	-- ============================================================
	-- SUB-PHASE 3: DYNAMIC TUG-OF-WAR (Continuous Mana + Tactical Surges)
	-- ============================================================
	local isTugOfWar = (elapsed >= (powerUpDur + reactionDelay))
	if isTugOfWar then
		fighter:SetAttribute("StruggleSubPhase", "TugOfWar")

		-- 1. Continuous Mana Drain: -2 mana every 0.10s
		local manaTickRate = CombatConfig.BeamStruggle_ContinuousManaTick or 0.10
		if (now - data.lastDrainTime) >= manaTickRate then
			data.lastDrainTime = now
			local energy = fighter:GetAttribute("Energy") or 100
			local drainAmt = CombatConfig.BeamStruggle_ContinuousManaDrain or 2.0
			fighter:SetAttribute("Energy", math.max(0, energy - drainAmt))
		end

		-- 2. Tactical Surge Decisions (every 0.25s - 0.40s)
		if (now - data.lastDecisionTime) >= 0.30 then
			data.lastDecisionTime = now + (math.random(-5, 5) / 100)
			local myEnergy = fighter:GetAttribute("Energy") or 0
			local myConf = fighter:GetAttribute("CurrentConfidence") or 0.5
			local nodeOffset = leaderModel:GetAttribute("ClashNodeOffset") or 0.0

			-- Positive deficit means this Quin is being pushed backward toward breach
			local myDeficit = (data.role == "Leader") and nodeOffset or -nodeOffset
			local surgeCost = CombatConfig.BeamStruggle_SurgeManaCost or 5.0
			local desperateCost = CombatConfig.BeamStruggle_DesperateBurstCost or 8.0

			local surgeDecision = "HOLD"

			if myEnergy >= desperateCost and myDeficit > 0.55 then
				-- Critical pressure: Desperate burst!
				surgeDecision = "DESPERATE"
			elseif myEnergy >= surgeCost then
				-- Strategic push: personality & class driven
				local quinType = fighter:GetAttribute("QuinType") or "TypeA"
				local surgeChance = 0.35 + (myConf * 0.25)
				if myDeficit > 0.20 then surgeChance = surgeChance + 0.30 end
				if quinType == "TypeA" then surgeChance = surgeChance + 0.15 end -- Striker aggressive push

				if math.random() < surgeChance then
					surgeDecision = "SURGE"
				end
			end

			if surgeDecision == "SURGE" then
				fighter:SetAttribute("Energy", math.max(0, myEnergy - surgeCost))
				fighter:SetAttribute("LastSurgeTick", now)
				fighter:SetAttribute("LastSurgeType", "SURGE")

				if data.role == "Leader" then
					local curOff = leaderModel:GetAttribute("ClashNodeOffset") or 0
					leaderModel:SetAttribute("ClashNodeOffset", curOff - 0.16)
					if data.vfxHandle and data.vfxHandle.triggerSurge then
						data.vfxHandle.triggerSurge(true, 0.30)
					end
				else
					local curOff = leaderModel:GetAttribute("ClashNodeOffset") or 0
					leaderModel:SetAttribute("ClashNodeOffset", curOff + 0.16)
				end
			elseif surgeDecision == "DESPERATE" then
				fighter:SetAttribute("Energy", math.max(0, myEnergy - desperateCost))
				fighter:SetAttribute("LastSurgeTick", now)
				fighter:SetAttribute("LastSurgeType", "DESPERATE")

				if data.role == "Leader" then
					local curOff = leaderModel:GetAttribute("ClashNodeOffset") or 0
					leaderModel:SetAttribute("ClashNodeOffset", curOff - 0.26)
					if data.vfxHandle and data.vfxHandle.triggerSurge then
						data.vfxHandle.triggerSurge(true, 0.35)
					end
				else
					local curOff = leaderModel:GetAttribute("ClashNodeOffset") or 0
					leaderModel:SetAttribute("ClashNodeOffset", curOff + 0.26)
				end
			end
		end

		-- Leader authoritative simulation of struggle physics & orbital movement
		if data.role == "Leader" then
			local curAngle = fighter:GetAttribute("ClashAngle") or 0
			local dist = fighter:GetAttribute("ClashDist") or 25
			local nodeOffset = fighter:GetAttribute("ClashNodeOffset") or 0.0

			-- Check if follower surged
			local partnerSurgeTick = partner:GetAttribute("LastSurgeTick") or 0
			if partnerSurgeTick > (data.lastObservedPartnerSurge or 0) then
				data.lastObservedPartnerSurge = partnerSurgeTick
				if data.vfxHandle and data.vfxHandle.triggerSurge then
					data.vfxHandle.triggerSurge(false, 0.30)
				end
			end

			local centerX = fighter:GetAttribute("ClashCenterX") or rootPart.Position.X
			local centerY = fighter:GetAttribute("ClashCenterY") or rootPart.Position.Y
			local centerZ = fighter:GetAttribute("ClashCenterZ") or rootPart.Position.Z
			local center = Vector3.new(centerX, centerY, centerZ)

			-- Dynamic Arc Rotation (Orbital Movement in Mid-Air)
			if not data.isGrounded then
				local orbitSpeed = (CombatConfig.BeamStruggle_ArcOrbitSpeed or 0.25) * speedMult
				curAngle = curAngle + (orbitSpeed * 0.03)
				fighter:SetAttribute("ClashAngle", curAngle)
			end

			-- Gradual force drift based on continuous energy ratio & element advantage
			local myEnergy = fighter:GetAttribute("Energy") or 50
			local pEnergy = partner:GetAttribute("Energy") or 50
			local myConf = fighter:GetAttribute("CurrentConfidence") or 0.6
			local pConf = partner:GetAttribute("CurrentConfidence") or 0.6

			local myMult = getElementalMultiplier(elemA, elemB)
			local pMult = getElementalMultiplier(elemB, elemA)

			local myForce = (15 + (myEnergy * 0.25) + (25 * myConf)) * myMult
			local pForce = (15 + (pEnergy * 0.25) + (25 * pConf)) * pMult

			local forceDiff = (myForce - pForce) / 100.0
			-- Drift offset slowly with force difference
			nodeOffset = math.clamp(nodeOffset - (forceDiff * 0.015 * speedMult), -0.85, 0.85)
			fighter:SetAttribute("ClashNodeOffset", nodeOffset)

			-- Update Central Clash Node Position
			local halfDist = dist / 2
			local dirUnit = Vector3.new(math.cos(curAngle), 0, math.sin(curAngle))
			local clashWorldPos = center + (dirUnit * (nodeOffset * halfDist * 0.85))

			if data.clashNode and data.clashNode.Parent then
				data.clashNode.Position = clashWorldPos
				local pulse = 2.0 + math.sin(elapsed * 18) * 0.30
				data.clashNode.Size = Vector3.new(pulse, pulse, pulse)
			end

			-- Periodic Ground Shockwave & Sparks (NO violent screen shake so viewer sees clash clearly)
			if (now - data.lastShakeTime) >= 0.30 then
				data.lastShakeTime = now
				VfxModule.createDust(clashWorldPos, 3, nil, elemA)
				if data.isGrounded then
					local groundY = data.startY - 3.8
					VfxModule.createShockwave(Vector3.new(clashWorldPos.X, groundY, clashWorldPos.Z), 14, 0.30, elemA)
				end
			end

			-- ============================================================
			-- SUB-PHASE 4: FATAL BREACH & HEAVY KNOCKBACK
			-- ============================================================
			local minDur = CombatConfig.BeamStruggle_MinDuration or 1.2
			local maxDur = CombatConfig.BeamStruggle_MaxDuration or 5.5

			local isOverpowered = (math.abs(nodeOffset) >= 0.80 and elapsed >= minDur)
			local isEnergyExhausted = ((myEnergy <= 0 or pEnergy <= 0) and elapsed >= minDur)
			local isTimeout = (elapsed >= maxDur)

			if (isOverpowered or isEnergyExhausted or isTimeout) and not data.breachInitiated then
				data.breachInitiated = true
				data.breachStartTime = now
				fighter:SetAttribute("StruggleSubPhase", "Breach")
				partner:SetAttribute("StruggleSubPhase", "Breach")

				local leaderWins = true
				if isOverpowered then
					leaderWins = (nodeOffset < 0)
				elseif isEnergyExhausted then
					leaderWins = (myEnergy > pEnergy)
				else
					leaderWins = (nodeOffset < 0)
				end

				local winner = leaderWins and fighter or partner
				local loser = leaderWins and partner or fighter
				local winElem = winner:GetAttribute("Element") or "Fire"

				data.winner = winner
				data.loser = loser
				data.leaderWins = leaderWins
				data.winElem = winElem

				if DEBUG then print(string.format("[BeamStruggle] FATAL BREACH! Winner: %s | Loser: %s", winner.Name, loser.Name)) end

				local loserHRP = loser:FindFirstChild("HumanoidRootPart")
				if loserHRP then
					-- Visual breach penetration: drives white clash sphere directly into loser's chest
					if data.vfxHandle and data.vfxHandle.triggerBreach then
						data.vfxHandle.triggerBreach(leaderWins, loserHRP)
					end

					-- Fatal damage
					local loserHum = loser:FindFirstChildOfClass("Humanoid")
					if loserHum then
						loserHum:TakeDamage(CombatConfig.BeamStruggle_FatalDamage or 55)
						loserHum.PlatformStand = false
					end

					-- CRITICAL: Restore physical simulation before applying knockback impulse
					loserHRP.Anchored = false

					-- Heavy Knockback (~25-35 studs launch)
					local awayDir = (loserHRP.Position - center).Unit
					local kbUp = data.isGrounded and 0.35 or 0.15
					KnockbackModule.applyKnockback(loser, awayDir + Vector3.new(0, kbUp, 0), CombatConfig.BeamStruggle_FatalKnockbackForce or 36.0, 0.50)
					local kbType = data.isGrounded and "hard_ground" or "air"
					loser:SetAttribute("KnockbackType", kbType)
					loser:SetAttribute("ForceState", "Knockback")
				end
			end

			-- During Breach Impact Dwell: hold winner steady while beam punches through loser
			if data.breachInitiated then
				local breachElapsed = now - data.breachStartTime
				local dwell = CombatConfig.BeamStruggle_BreachDwellTime or 0.60
				if breachElapsed < dwell then
					local winner = data.winner
					local winnerHRP = winner and winner:FindFirstChild("HumanoidRootPart")
					if winnerHRP and winnerHRP == rootPart then
						rootPart.AssemblyLinearVelocity = Vector3.zero
						local targetFacePos = Vector3.new(partnerHRP.Position.X, rootPart.Position.Y, partnerHRP.Position.Z)
						rootPart.CFrame = CFrame.lookAt(rootPart.Position, targetFacePos)
					end
					return BeamStruggleState
				else
					-- Climax complete: unanchor winner and transition to Fight
					local winner = data.winner
					local loser = data.loser
					if winner then
						local winnerHRP = winner:FindFirstChild("HumanoidRootPart")
						if winnerHRP then winnerHRP.Anchored = false end
						local winnerHum = winner:FindFirstChildOfClass("Humanoid")
						if winnerHum then winnerHum.PlatformStand = false end
						local wConf = winner:GetAttribute("Pers_Confidence") or 0.6
						winner:SetAttribute("Pers_Confidence", math.min(1.0, wConf + 0.25))
						winner:SetAttribute("ForceState", "Fight")
					end

					BattleEventSystem.emit("BEAM_STRUGGLE_CLIMAX", {
						QuinId = winner and (winner:GetAttribute("QuinId") or winner.Name) or fighter.Name,
						Model = winner,
						TargetName = loser and loser.Name or "Unknown",
						Element = data.winElem or "Fire",
						Extra = "FATAL_BREACH"
					})

					return require(script.Parent:WaitForChild("FightState"))
				end
			end
		end
	end

	-- If breach subphase is actively playing, winner holds stance and loser flies in knockback
	if leaderModel:GetAttribute("StruggleSubPhase") == "Breach" then
		if data.role == "Follower" then
			local leaderData = struggleData[leaderModel]
			if leaderData and leaderData.winner == fighter then
				local breachElapsed = now - (leaderData.breachStartTime or now)
				local dwell = CombatConfig.BeamStruggle_BreachDwellTime or 0.60
				if breachElapsed < dwell then
					rootPart.AssemblyLinearVelocity = Vector3.zero
					local targetFacePos = Vector3.new(partnerHRP.Position.X, rootPart.Position.Y, partnerHRP.Position.Z)
					rootPart.CFrame = CFrame.lookAt(rootPart.Position, targetFacePos)
					return BeamStruggleState
				else
					rootPart.Anchored = false
					humanoid.PlatformStand = false
					return require(script.Parent:WaitForChild("FightState"))
				end
			end
		end
		return BeamStruggleState
	end

	-- Locomotion & Visual Straining Loop
	local isGrounded = data.isGrounded
	local bobAmp = isGrounded and 0 or (CombatConfig.BeamStruggle_BobAmplitude or 0.75)
	local bobFreq = CombatConfig.BeamStruggle_BobFrequency or 3.2
	local shakeAmp = isGrounded and 0.22 or (CombatConfig.BeamStruggle_ShakeAmplitude or 0.20)

	-- Vertical opposite-phase aerial bobbing (seesaw strain under pressure)
	local phaseSign = (data.role == "Leader") and 1 or -1
	local yBob = isGrounded and 0 or (phaseSign * math.sin(elapsed * bobFreq) * bobAmp)

	-- Kinetic micro-shake displacement (kinetic strain under intense power)
	local shakeX = (math.random() - 0.5) * 2 * shakeAmp
	local shakeY = (math.random() - 0.5) * 2 * (shakeAmp * (isGrounded and 0.3 or 0.8))
	local shakeZ = (math.random() - 0.5) * 2 * shakeAmp
	local shakeOffset = Vector3.new(shakeX, shakeY, shakeZ)

	local curAngle = leaderModel:GetAttribute("ClashAngle") or 0
	local dist = leaderModel:GetAttribute("ClashDist") or 25
	local halfDist = dist / 2
	local nodeOffset = leaderModel:GetAttribute("ClashNodeOffset") or 0.0

	local centerX = leaderModel:GetAttribute("ClashCenterX") or rootPart.Position.X
	local centerY = leaderModel:GetAttribute("ClashCenterY") or rootPart.Position.Y
	local centerZ = leaderModel:GetAttribute("ClashCenterZ") or rootPart.Position.Z
	local center = Vector3.new(centerX, centerY, centerZ)

	local angleOffset = (data.role == "Leader") and 0 or math.pi
	local targetAngle = curAngle + angleOffset

	-- Trench / Recoil Pushback along struggle axis
	local pushbackDist = 0
	if isGrounded then
		if data.role == "Leader" and nodeOffset > 0 then
			pushbackDist = nodeOffset * 4.5
		elseif data.role == "Follower" and nodeOffset < 0 then
			pushbackDist = math.abs(nodeOffset) * 4.5
		end
		if pushbackDist > 0.4 and (now - (data.lastTrenchTime or 0)) >= 0.25 then
			data.lastTrenchTime = now
			local elem = fighter:GetAttribute("Element") or "Fire"
			VfxModule.createDust(rootPart.Position - Vector3.new(0, 2.0, 0), 2, nil, elem)
		end
	else
		-- Mid-air physical recoil: being overpowered pushes back, surging pushes forward
		local myDeficit = (data.role == "Leader") and nodeOffset or -nodeOffset
		if myDeficit > 0 then
			pushbackDist = myDeficit * 3.5
		else
			pushbackDist = myDeficit * 1.5
		end
	end

	local effectiveHalfDist = halfDist + pushbackDist
	local desiredBasePos = center + Vector3.new(math.cos(targetAngle) * effectiveHalfDist, yBob, math.sin(targetAngle) * effectiveHalfDist)

	if isGrounded then
		desiredBasePos = Vector3.new(desiredBasePos.X, data.startY, desiredBasePos.Z)
	end

	local targetFacePos = Vector3.new(partnerHRP.Position.X, desiredBasePos.Y, partnerHRP.Position.Z)
	local targetCFrame = CFrame.lookAt(desiredBasePos + shakeOffset, targetFacePos)

	rootPart.CFrame = rootPart.CFrame:Lerp(targetCFrame, 0.40)
	rootPart.AssemblyLinearVelocity = Vector3.zero

	return BeamStruggleState
end

return BeamStruggleState
