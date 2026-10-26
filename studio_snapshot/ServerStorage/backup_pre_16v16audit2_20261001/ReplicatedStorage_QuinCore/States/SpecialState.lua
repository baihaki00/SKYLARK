--// SpecialState.lua
-- Phase 5: Canonical Elemental Specials Engine
-- Authoritative 2-power system (Offensive + Defensive) per element across Fire, Water, Stone, Lightning, Wind
-- In accordance with Master Project Plan (Section 10) & Quin Combat Balance Bible

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")

local TargetingModule = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("TargetingModule"))
local AnimationModule = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("AnimationModule"))
local HitboxModule = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("HitboxModule"))
local KnockbackModule = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("KnockbackModule"))
local DamageModule = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("DamageModule"))
local AudioModule = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("AudioModule"))
local VfxModule = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("VfxModule"))
local AnimationIds = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("AnimationIds"))
local CombatConfig = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("CombatConfig"))
local SpatialModule = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("SpatialModule"))

local SpecialState = { name = "Special" }

local specialData = {}

-- Canonical 2-power elemental moveset
local ELEMENTAL_SPECIALS = {
	Fire = {
		Offensive = {
			name = "FlameSurge",
			type = "Offensive",
			windupDuration = 0.25,
			activeDuration = 0.35,
			recoveryDuration = 0.45,
			hitCount = 1,
			damagePerHit = 2.4, -- Scaled by DamageModule
			hitboxSize = Vector3.new(7, 6, 12),
			knockbackOnFinish = 190,
			range = 22,
			isDash = true,
			dashSpeed = 85,
			statusEffect = "Burn",
		},
		Defensive = {
			name = "HeatBurst",
			type = "Defensive",
			windupDuration = 0.20,
			activeDuration = 0.25,
			recoveryDuration = 0.50,
			hitCount = 1,
			damagePerHit = 1.8,
			hitboxSize = Vector3.new(16, 8, 16),
			knockbackOnFinish = 230,
			range = 16,
			isAoE = true,
			statusEffect = "Burn",
		},
	},

	Water = {
		Offensive = {
			name = "HydroShardBarrage",
			type = "Offensive",
			windupDuration = 0.22,
			activeDuration = 0.50,
			recoveryDuration = 0.40,
			hitCount = 3,
			damagePerHit = 1.0, -- 3 hits = 3.0 total
			hitboxSize = Vector3.new(6, 6, 18),
			knockbackOnFinish = 160,
			range = 24,
			statusEffect = "Frostbite", -- Sub-zero crystalline byproduct
		},
		Defensive = {
			name = "TidalBarrier",
			type = "Defensive",
			windupDuration = 0.15,
			activeDuration = 0.60,
			recoveryDuration = 0.40,
			hitCount = 1,
			damagePerHit = 1.5,
			hitboxSize = Vector3.new(14, 8, 14),
			knockbackOnFinish = 180,
			range = 14,
			isAoE = true,
			statusEffect = "Drench",
		},
	},

	Stone = { -- Earth
		Offensive = {
			name = "GroundFissure",
			type = "Offensive",
			windupDuration = 0.35,
			activeDuration = 0.30,
			recoveryDuration = 0.55,
			hitCount = 1,
			damagePerHit = 3.0,
			hitboxSize = Vector3.new(8, 8, 20),
			knockbackOnFinish = 210,
			range = 20,
			isVerticalLaunch = true,
			statusEffect = "Quake",
		},
		Defensive = {
			name = "StoneAegis",
			type = "Defensive",
			windupDuration = 0.15,
			activeDuration = 0.70,
			recoveryDuration = 0.35,
			hitCount = 1,
			damagePerHit = 1.2,
			hitboxSize = Vector3.new(12, 6, 12),
			knockbackOnFinish = 170,
			range = 12,
			isAoE = true,
			statusEffect = "Fortify",
		},
	},

	Lightning = { -- Electric
		Offensive = {
			name = "VoltArc",
			type = "Offensive",
			windupDuration = 0.18,
			activeDuration = 0.25,
			recoveryDuration = 0.35,
			hitCount = 1,
			damagePerHit = 2.2,
			hitboxSize = Vector3.new(8, 6, 24),
			knockbackOnFinish = 150,
			range = 25,
			isChain = true,
			statusEffect = "Shock",
		},
		Defensive = {
			name = "DischargeFlash",
			type = "Defensive",
			windupDuration = 0.12,
			activeDuration = 0.30,
			recoveryDuration = 0.40,
			hitCount = 1,
			damagePerHit = 1.6,
			hitboxSize = Vector3.new(14, 8, 14),
			knockbackOnFinish = 190,
			range = 14,
			isAoE = true,
			statusEffect = "Shock",
		},
	},

	Wind = {
		Offensive = {
			name = "GaleCutter",
			type = "Offensive",
			windupDuration = 0.20,
			activeDuration = 0.30,
			recoveryDuration = 0.35,
			hitCount = 1,
			damagePerHit = 2.5,
			hitboxSize = Vector3.new(9, 6, 26),
			knockbackOnFinish = 220,
			range = 26,
			statusEffect = "Push",
		},
		Defensive = {
			name = "DraftRepel",
			type = "Defensive",
			windupDuration = 0.12,
			activeDuration = 0.35,
			recoveryDuration = 0.40,
			hitCount = 1,
			damagePerHit = 1.4,
			hitboxSize = Vector3.new(16, 10, 16),
			knockbackOnFinish = 240,
			range = 16,
			isAoE = true,
			statusEffect = "Repel",
		},
	},
}

-- Aliases
ELEMENTAL_SPECIALS.Ice = ELEMENTAL_SPECIALS.Water
ELEMENTAL_SPECIALS.Earth = ELEMENTAL_SPECIALS.Stone
ELEMENTAL_SPECIALS.Electric = ELEMENTAL_SPECIALS.Lightning

-- Select appropriate special move based on element, class, and tactical pressure
local function pickSpecialMove(fighter)
	local element = fighter:GetAttribute("Element") or "Fire"
	local moves = ELEMENTAL_SPECIALS[element] or ELEMENTAL_SPECIALS.Fire

	local hum = fighter:FindFirstChildOfClass("Humanoid")
	local hpRatio = hum and (hum.Health / hum.MaxHealth) or 1.0
	local isCornered = fighter:GetAttribute("IsCornered")
	local focusCount = fighter:GetAttribute("FocusCount") or 0
	local threatZone = fighter:GetAttribute("ThreatZone")

	-- If low health, cornered, or focused by 2+ enemies, trigger defensive special
	local preferDefensive = (hpRatio < 0.35) or (isCornered == true) or (focusCount >= 2) or (threatZone == "Rear")
	if preferDefensive then
		return moves.Defensive
	else
		return moves.Offensive
	end
end

function SpecialState.enter(fighter, humanoid, rootPart)
	local move = pickSpecialMove(fighter)
	
	-- Energy drain
	local energy = fighter:GetAttribute("Energy") or 100
	local drain = CombatConfig.EnergyDrain_Special or 30
	fighter:SetAttribute("Energy", math.max(0, energy - drain))
	
	local speedMult = workspace:GetAttribute("GameSpeedMultiplier") or 1.0

	specialData[fighter] = {
		enterTime = tick(),
		move = move,
		phase = "windup",
		hitsDealt = 0,
		lastHitTime = 0,
		speedMult = speedMult,
	}
	
	humanoid.WalkSpeed = 0
	fighter:SetAttribute("CurrentSpecial", move.name)
	
	-- Windup animation
	if move.type == "Defensive" then
		AnimationModule.playConfig(humanoid, "Reactions.Block", 1.2, Enum.AnimationPriority.Action4)
		fighter:SetAttribute("IsGuarding", true)
	else
		AnimationModule.playConfig(humanoid, "Attacks.Special.Special1", 1.0, Enum.AnimationPriority.Action4)
	end
end

function SpecialState.exit(fighter, humanoid, rootPart)
	fighter:SetAttribute("IsGuarding", false)
	fighter:SetAttribute("CurrentSpecial", nil)
	specialData[fighter] = nil
	local speed = fighter:GetAttribute("Speed") or 40
	humanoid.WalkSpeed = speed
end

function SpecialState.update(fighter, humanoid, rootPart, DEBUG)
	local data = specialData[fighter]
	if not data then
		return require(script.Parent:WaitForChild("FightState"))
	end

	-- Prone guard: if knocked flat, recover
	local upY = rootPart.CFrame.UpVector.Y
	if upY < 0.6 and SpatialModule.isGrounded(rootPart) then
		fighter:SetAttribute("KnockbackType", "hard_ground")
		return require(script.Parent:WaitForChild("RecoveryState"))
	end
	
	local elapsed = tick() - data.enterTime
	local move = data.move
	local target, distance = TargetingModule.getNearest(rootPart, move.range * 2)
	local speedMult = data.speedMult or 1.0
	
	-- Face target smoothly during windup
	if target and data.phase == "windup" then
		local tHRP = target:FindFirstChild("HumanoidRootPart")
		if tHRP then
			local look = CFrame.lookAt(rootPart.Position, Vector3.new(tHRP.Position.X, rootPart.Position.Y, tHRP.Position.Z))
			rootPart.CFrame = rootPart.CFrame:Lerp(look, 0.4)
		end
	end
	
	-- PHASE 1: Windup -> Active
	if data.phase == "windup" then
		if elapsed >= (move.windupDuration / speedMult) then
			data.phase = "active"
			data.phaseStartTime = tick()
			
			-- Dash forward for offensive gap-closers
			if move.isDash then
				local dashDir = rootPart.CFrame.LookVector
				KnockbackModule.applySlide(fighter, dashDir, move.dashSpeed, move.activeDuration / speedMult)
				VfxModule.createVaporCone(rootPart, move.activeDuration / speedMult)
				AudioModule.playDash(rootPart.Position)
			end
			
			-- Radial burst effects for AoE / Defensive specials
			if move.isAoE then
				VfxModule.createShockwave(rootPart, move.range * 2, 0.6 / speedMult)
				AudioModule.playSlam(rootPart.Position)
			end
			
			if move.type == "Defensive" then
				AnimationModule.playConfig(humanoid, "Attacks.Special.Slam", 1.2, Enum.AnimationPriority.Action4)
			else
				AnimationModule.playConfig(humanoid, "Attacks.Special.Special1", 1.3, Enum.AnimationPriority.Action4)
			end
			
			if DEBUG then print(string.format("[%s] Special ACTIVE: %s (%s)", fighter.Name, move.name, move.type)) end
		end
		return SpecialState
	end
	
	-- PHASE 2: Active Hit Detection
	if data.phase == "active" then
		-- Phase 12 Spectacle: Dynamic Anime Beam Struggle Collision Detection
		if move.type == "Offensive" and target and target.Parent then
			local tHRP = target:FindFirstChild("HumanoidRootPart")
			local tHum = target:FindFirstChildOfClass("Humanoid")
			if tHRP and tHum and tHum.Health > 0 then
				local tState = target:GetAttribute("CurrentState")
				local tSpecial = target:GetAttribute("CurrentSpecial")
				if (tState == "Special" and tSpecial) or target:GetAttribute("ForceState") == "BeamStruggle" then
					local dist = (tHRP.Position - rootPart.Position).Magnitude
					if dist <= (CombatConfig.BeamStruggle_ClashRange or 80.0) then
						local myLook = rootPart.CFrame.LookVector
						local theirLook = tHRP.CFrame.LookVector
						-- Facing each other in direct line of fire
						if myLook:Dot(theirLook) <= -0.30 then
							fighter:SetAttribute("TargetQuin", target.Name)
							fighter:SetAttribute("ForceState", "BeamStruggle")
							target:SetAttribute("TargetQuin", fighter.Name)
							target:SetAttribute("ForceState", "BeamStruggle")
							return require(script.Parent:WaitForChild("BeamStruggleState"))
						end
					end
				end
			end
		end

		local phaseElapsed = tick() - data.phaseStartTime
		local effectiveActive = move.activeDuration / speedMult
		
		-- Hit interval
		local hitInterval = effectiveActive / math.max(1, move.hitCount)
		if data.hitsDealt < move.hitCount and (tick() - data.lastHitTime) >= hitInterval then
			data.lastHitTime = tick()
			data.hitsDealt = data.hitsDealt + 1
			
			local hitModels
			if move.isAoE then
				hitModels = HitboxModule.castAoE(rootPart.Position, move.hitboxSize.X / 2, fighter)
			else
				hitModels = HitboxModule.castInFront(rootPart, move.hitboxSize, Vector3.new(0, 0, -move.hitboxSize.Z * 0.4), fighter)
			end
			
			for _, hitModel in ipairs(hitModels) do
				local dmgInfo = DamageModule.calculate(fighter, hitModel, data.hitsDealt, move.damagePerHit)
				DamageModule.apply(fighter, hitModel, dmgInfo)
				
				-- Apply status effect byproducts (e.g. Frostbite slow for Water)
				if move.statusEffect == "Frostbite" then
					local h = hitModel:FindFirstChildOfClass("Humanoid")
					if h then
						local baseSpd = hitModel:GetAttribute("Speed") or 40
						h.WalkSpeed = math.max(16, baseSpd * 0.75)
						task.delay(1.5 / speedMult, function()
							if hitModel.Parent and h then h.WalkSpeed = baseSpd end
						end)
					end
				end
			end
		end
		
		-- Active phase completes -> transition to Recovery
		if phaseElapsed >= effectiveActive then
			data.phase = "recovery"
			data.phaseStartTime = tick()
			
			-- Apply knockback launch to remaining nearby opponents
			local finalHits
			if move.isAoE then
				finalHits = HitboxModule.castAoE(rootPart.Position, move.hitboxSize.X / 2 + 3, fighter)
			else
				finalHits = HitboxModule.castInFront(rootPart, move.hitboxSize * 1.3, Vector3.new(0, 0, -4), fighter)
			end

			for _, hitModel in ipairs(finalHits) do
				local hHRP = hitModel:FindFirstChild("HumanoidRootPart")
				if hHRP then
					local awayDir = (hHRP.Position - rootPart.Position)
					local dir = (awayDir.Magnitude > 0.1) and awayDir.Unit or rootPart.CFrame.LookVector
					if move.isVerticalLaunch then
						dir = (dir + Vector3.new(0, 0.8, 0)).Unit
					end
					KnockbackModule.applyKnockback(hitModel, dir, move.knockbackOnFinish, 0.35)
					hitModel:SetAttribute("ForceState", "Knockback")
				end
			end
			
			if DEBUG then print(string.format("[%s] Special FINISHED: %s (%d hits)", fighter.Name, move.name, data.hitsDealt)) end
		end
		return SpecialState
	end
	
	-- PHASE 3: Recovery
	if data.phase == "recovery" then
		local phaseElapsed = tick() - data.phaseStartTime
		if phaseElapsed >= (move.recoveryDuration / speedMult) then
			local t, d = TargetingModule.getNearest(rootPart, CombatConfig.CombatRange or 8)
			if t and d <= (CombatConfig.CombatRange or 8) * 1.5 then
				return require(script.Parent:WaitForChild("FightState"))
			else
				return require(script.Parent:WaitForChild("ChaseState"))
			end
		end
		return SpecialState
	end
	
	return SpecialState
end

return SpecialState
