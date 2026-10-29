--// FightState.lua
-- Core combat state: AI decision engine, combo execution, hit detection
-- Dragon Ball Sparking Zero / Genos inspired
-- Single Source of Truth: ReplicatedStorage.QuinCore.AnimationConfig

local GameClock = require(game:GetService("ReplicatedStorage"):WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("GameClock")) -- (the game's clock: a freeze stops it)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")
local CollectionService = game:GetService("CollectionService")
local QuinRoster = require(game:GetService("ReplicatedStorage"):WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("QuinRoster")) -- (GetTagged("Quin") once a frame, shared)

local TargetingModule = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("TargetingModule"))
local AnimationModule = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("AnimationModule"))
local HitboxModule = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("HitboxModule"))
local KnockbackModule = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("KnockbackModule"))
local Spacing = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("Spacing")) -- (where a strike stops)
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
local Reach = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("Reach"))
local Instinct = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("Instinct"))
local Drives = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("Drives"))
local Rhythm = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("Rhythm"))
local HitStop = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("HitStop"))
local GaitModule = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("GaitModule"))
local StrikeMarkers = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("StrikeMarkers"))
local Evasion = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("Evasion"))
local RunService = game:GetService("RunService")
local Pers = require(game:GetService("ReplicatedStorage"):WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("Pers")) -- (personality reads + defaults, one place)
local States = require(game:GetService("ReplicatedStorage"):WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("States")) -- (every state by name)
local StateRequest = require(game:GetService("ReplicatedStorage"):WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("StateRequest")) -- (asking a Quin to change state)
local Facing = require(game:GetService("ReplicatedStorage"):WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("Facing")) -- (the turner a state holds: body claim)
-- Its parts (child modules): one strike start to finish, and what to do next
local Strike = require(script:WaitForChild("Strike"))
local Decide = require(script:WaitForChild("Decide"))
local decideAction = Decide.action
local getLiveAttacks = Strike.liveAttacks
local applyHitOutcome = Strike.applyHitOutcome
local executeAttack = Strike.execute

local function findModelByName(name)
	local m = QuinRoster.byName(name)
	return m and m:FindFirstChild("HumanoidRootPart") and m or nil
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

-- The cornered counter-strike resolves its hit like a combo finisher
local DESPERATE_COUNTER_MOVE = { name = "DesperateCounter", knockback = 35, isFinisher = true }

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
	GameClock.delay((windupUntil - now) + 0.2 / speedMult, function()
		if fighter.Parent and fighter:GetAttribute("IsGuarding") == true then
			fighter:SetAttribute("IsGuarding", false)
		end
	end)
end

-- Chance to guard the next strike of a combo the Quin is caught in (defensive Quins more often)
local function comboBreakChance(fighter)
	local defense = Pers.get(fighter, "DefensePreference")
	return (CombatConfig.Combat_ComboBreakChance or 0.25) * (0.5 + defense)
end

-- Chance to guard a strike seen coming while the Quin is between its own attacks
local function reactiveGuardChance(fighter)
	local aggression = Pers.get(fighter, "Aggression")
	return (fighter:GetAttribute("BlockChance") or 0.25) * (1.2 - aggression * 0.5)
end

-- Turn the body to face a target with the fight's facing (Modules/Facing, held as "Fight").
-- Used by the fight loop and by a player's Quin (PilotedState). Not across a height difference of
-- 5 studs or more.
-- Stepping back off the line (owner 2026-10-28, movement step 5): its own step back from the
-- opponent goes back and to one side, not straight back - a fighter gives ground off the line
-- of the next punch. Still facing its opponent. The side holds a while (no zig-zag), keeps any
-- sideways motion the body already has, and the angle is a leaning: a careful Quin angles off
-- more, a pressing one gives ground more straight. Workspace or Quin BackAngleOff: straight back.
function FightState.backStepDir(fighter, rootPart, data, awayFlat, now)
	if workspace:GetAttribute("BackAngleOff") == true or fighter:GetAttribute("BackAngleOff") == true then
		return awayFlat
	end
	local side = Vector3.new(-awayFlat.Z, 0, awayFlat.X)
	local back = data.backAngle
	if not back or now >= back.untilT then
		local lateral = rootPart.AssemblyLinearVelocity:Dot(side)
		local sign = math.abs(lateral) > 3 and math.sign(lateral) or (back and back.sign or (math.random() < 0.5 and -1 or 1))
		if back and math.abs(lateral) <= 3 and math.random() < 0.3 then sign = -sign end -- (now and then the other way)
		local careful = 1 - Pers.get(fighter, "Aggression")
		back = { sign = sign, deg = 18 + 22 * careful + math.random() * 10, untilT = now + 1.2 + math.random() * 1.4 }
		data.backAngle = back
	end
	local a = math.rad(back.deg)
	return (awayFlat * math.cos(a) + side * (back.sign * math.sin(a))).Unit
end

-- What a Quin does while its opponent is down (the downed branch in update): weights, not rules.
-- Returns the reaction ("press", "hold", "circle", "switch") and, for a switch, the new enemy.
function FightState.downedReaction(fighter, rootPart, target, distance)
	local aggression = Pers.get(fighter, "Aggression")
	local confidence = Pers.get(fighter, "Confidence")
	local mobility = Pers.get(fighter, "MobilityPreference")
	local weights = {
		press = (0.3 + aggression * 0.9 + confidence * 0.4) * (distance < 18 and 1 or 0.4),
		hold = 0.35 + (1 - aggression) * 0.6 + (1 - mobility) * 0.3,
		circle = 0.3 + mobility * 0.8,
	}
	-- another enemy still on its feet close by: the knockdown is a chance to turn on it
	local switchTo
	for _, e in ipairs(TargetingModule.getEnemiesInRange(rootPart, CombatConfig.Fight_DownedSwitchRange or 30)) do
		local st = e.model:GetAttribute("CurrentState")
		if e.model ~= target and st ~= "Knockback" and st ~= "Airborne" and st ~= "Recovery"
			and e.model:GetAttribute("IsInert") ~= true then
			switchTo = e.model
			weights.switch = 0.4 + aggression * 0.8
			break
		end
	end
	local total = 0
	for _, w in pairs(weights) do total += w end
	local roll = math.random() * total
	for _, name in ipairs({ "press", "hold", "circle", "switch" }) do
		local w = weights[name]
		if w then
			roll -= w
			if roll <= 0 then return name, switchTo end
		end
	end
	return "circle", switchTo
end

function FightState.faceTarget(rootPart, targetHRP, data)
	-- Through its own strike, up to the strike's cancel point, the body keeps the line it threw
	-- the strike along: it turns after the Quin it struck at no faster than Fight_StrikeTurnRate,
	-- and never after a new target. (Owner's bookmarks 2026-10-29: the gyro followed the current
	-- target at full speed, so a body whipped round 450-730 deg/s mid-punch, the hit box in front
	-- of it swung onto a Quin behind, and the knockback went along the swung facing.)
	-- Switch: Fight_StrikeFacingLock = false.
	local now = GameClock.tick()
	if data and data.strikeAim and (data.currentAction == "light" or data.currentAction == "heavy") and now < (data.actionEndTime or 0) then
		local struck = data.strikeAimAt
		if struck and struck.Parent then
			local to = Vector3.new(struck.Position.X - rootPart.Position.X, 0, struck.Position.Z - rootPart.Position.Z)
			if to.Magnitude > 0.5 then
				to = to.Unit
				local maxTurn = math.rad(CombatConfig.Fight_StrikeTurnRate or 180) * math.clamp(now - (data.strikeAimT or now), 0, 0.25)
				local angle = math.acos(math.clamp(data.strikeAim:Dot(to), -1, 1))
				if angle <= maxTurn then
					data.strikeAim = to
				else
					local sign = data.strikeAim:Cross(to).Y >= 0 and 1 or -1
					data.strikeAim = CFrame.Angles(0, sign * maxTurn, 0):VectorToWorldSpace(data.strikeAim).Unit
				end
			end
		end
		data.strikeAimT = now
		Facing.hold(rootPart, "Fight").CFrame = CFrame.lookAt(rootPart.Position, rootPart.Position + data.strikeAim)
		return
	end
	local yDiff = math.abs(targetHRP.Position.Y - rootPart.Position.Y)
	if yDiff >= 5 then return end
	local lookCF = CFrame.lookAt(rootPart.Position, Vector3.new(targetHRP.Position.X, rootPart.Position.Y, targetHRP.Position.Z))
	local alignOri = Facing.hold(rootPart, "Fight")
	-- The rear-turn counter stiffens the gyro for its turn; it used to stay stiff for the
	-- rest of the fight
	if data and data.currentAction ~= "rear_turn_counter" and alignOri.Responsiveness ~= 22 then
		alignOri.Responsiveness = 22
	end
	alignOri.CFrame = lookCF
end

-- Throw the next strike of the combo ("Light" | "Heavy"): the move, the clip, the marker timing,
-- the contact and its outcome. The fight loop's strikes and a player's Quin's strikes
-- (PilotedState) both come through here; `data` carries the timing (lastAttackTime,
-- actionEndTime, attackFinishTime). Returns the move, or nil when there is none.
function FightState.throwStrike(fighter, humanoid, rootPart, target, weight, data, DEBUG)
	local moveData = ComboModule.nextAttack(fighter, weight or "Light")
	if not moveData then return nil end
	Rhythm.noteStrike(fighter) -- (the fight's tempo: Modules/Rhythm)
	local now = GameClock.tick()
	local speedMult = workspace:GetAttribute("GameSpeedMultiplier") or 1.0
	data.currentAction = (weight == "Heavy") and "heavy" or "light"
	-- (the line the strike is thrown along: the body's facing now; faceTarget holds it)
	local look = Vector3.new(rootPart.CFrame.LookVector.X, 0, rootPart.CFrame.LookVector.Z)
	if CombatConfig.Fight_StrikeFacingLock ~= false and look.Magnitude > 0.01 then
		data.strikeAim, data.strikeAimT = look.Unit, now
		data.strikeAimAt = target and target:FindFirstChild("HumanoidRootPart")
	else
		data.strikeAim = nil
	end
	local attackDuration, cancelDelay = executeAttack(fighter, humanoid, rootPart, target, moveData, data, DEBUG)
	data.actionEndTime = now + (cancelDelay / speedMult)
	data.attackFinishTime = now + (attackDuration / speedMult)
	return moveData, attackDuration
end

function FightState.enter(fighter, humanoid, rootPart)
	RuntimeTracer.checkpoint(fighter, "Enter FightState")
	fighter:SetAttribute("EngagedSince", GameClock.now()) -- (Rhythm: a long quiet while engaged)
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
	fighter:SetAttribute("LastActivityTime", GameClock.now())
	-- Cleanly stop any attack or hit reaction tracks so they do not linger into subsequent states (e.g. CirclingState)
	AnimationModule.stopCategory(humanoid, "Attacks", 0.1)
	AnimationModule.stopCategory(humanoid, "Reactions", 0.1)
	Facing.drop(rootPart, "Fight")
	-- Do NOT hard stop Idle; let Idle blend smoothly with whichever state takes over
end

function FightState.update(fighter, humanoid, rootPart, DEBUG)
	-- Respect-custom spectators must never fight
	local showdownRole = fighter:GetAttribute("RespectRole")
	if require(game:GetService("ReplicatedStorage").QuinCore.Modules.SocialSystem).standsDown(fighter) then
		return States.Idle -- (spectators stand and watch)
	end

	-- Respect-custom standoff: nobody strikes until one of them breaks it
	if fighter:GetAttribute("SocialStandoff") then
		return States.Circling
	end

	-- Respect-custom duel: kept on the ceremony space, no jumping away
	local inShowdown = (showdownRole == "Duelist") -- (a respect-custom duel)
	if inShowdown then
		humanoid.UseJumpPower = true
		humanoid.JumpPower = 0
		humanoid.JumpHeight = 0
		require(game:GetService("ReplicatedStorage").QuinCore.Modules.SocialSystem).constrainToCeremony(rootPart)
	end

	local data = getData(fighter)
	local now = GameClock.tick()
	
	-- Check forced state change (from being hit, disengaging, or tactical override)
	local forcedState = StateRequest.take(fighter)
	if forcedState then
		return States[forcedState]
	end

	-- Prone / Cockroach protection: if flat on ground, immediately recover
	local upY = rootPart.CFrame.UpVector.Y
	if upY < 0.6 and SpatialModule.isGrounded(rootPart) then
		fighter:SetAttribute("KnockbackType", "hard_ground")
		return States.Recovery
	end
	
	-- Check hit stun
	local stunEndTime = fighter:GetAttribute("StunEndTime") or 0
	if now < stunEndTime then
		-- Hard but continuous stop: the drive drops to zero within ~0.15s. Zeroing the velocity
		-- on every tick froze a running body in one frame and kept cancelling the hit push,
		-- which showed as a stutter during the flinch.
		humanoid.WalkSpeed = math.max(0, humanoid.WalkSpeed - 30)
		if not Instinct.enabled() then -- (with Instinct on, the reflexes answer strikes: Modules/Instinct)
			tryRaiseGuard(fighter, humanoid, data, now, findModelByName(fighter:GetAttribute("LastAttackerName")), comboBreakChance(fighter))
		end
		return FightState
	end

	-- A focused dash or a quick evade has the body (Modules/Evasion): nothing else steers it
	if Evasion.busy(fighter) then
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
			local facingGyro = Facing.get(rootPart, "Fight")
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
				-- (only as far as the punch's own gap: Modules/Spacing)
				local room = lungeFlat.Magnitude - Spacing.strikeStopGap(animData.reach)
				if room > 0.25 then
					KnockbackModule.applyLunge(fighter, lungeFlat.Unit, 32, 0.22, room)
				end
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
			
			local counterWindup = now + impactDelay
			GameClock.delay(impactDelay, function()
				if not fighter.Parent or not counterTarget.Parent then return end
				fighter:SetAttribute("Attacking", false)
				-- (hit or knocked out of the fight while winding up: the riposte never comes out)
				if fighter:GetAttribute("StrikeInterrupted") == counterWindup or fighter:GetAttribute("CurrentState") ~= "Fight" then return end
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
	local target, distance = TargetingModule.getCommittedTarget(fighter, rootPart, (CombatConfig.ChaseRange or 800) * 1.5)
	
	if not target then
		-- No current valid committed target, or target died/escaped: acquire nearest candidate
		target, distance = TargetingModule.getNearest(rootPart, CombatConfig.ChaseRange)
		if target then
			TargetingModule.setTarget(fighter, target)
			data.lastEngagedTarget = target
			-- If next target is beyond close combat range, transition to Chase or Circling, NEVER mid-combat Idle!
			if distance > (CombatConfig.CombatRange or 8.2) * 1.8 then
				return States.Chase
			end
		else
			-- No enemies exist anywhere in arena
			TargetingModule.clearTarget(fighter)
			data.lastEngagedTarget = nil
			return States.Idle
		end
	else
		data.lastEngagedTarget = target
	end

	local targetHRP = target:FindFirstChild("HumanoidRootPart")
	if not targetHRP then
		return States.Chase
	end

	-- A downed or recovering opponent is not struck. What to do meanwhile is the Quin's own call,
	-- made once per knockdown and leaned by its temperament and the moment (downedReaction):
	-- stand over it, hold its ground, circle it, or turn on another enemy still on its feet.
	-- (Before: always Circling, so every knockdown read the same. Fight_DownedChoice = false.)
	local targetState = target:GetAttribute("CurrentState")
	if targetState == "Knockback" or targetState == "Airborne" or targetState == "Recovery" or target:GetAttribute("GetUpProtection") == true then
		if CombatConfig.Fight_DownedChoice == false then
			return States.Circling
		end
		-- (picked again after Fight_DownedRepick seconds: a choice left from an earlier knockdown,
		-- made while it was in another state, does not carry over)
		if data.downedTarget ~= target or now - (data.downedAt or 0) > (CombatConfig.Fight_DownedRepick or 3) then
			data.downedTarget, data.downedAt = target, now
			data.downedReaction, data.downedSwitchTo = FightState.downedReaction(fighter, rootPart, target, distance)
			fighter:SetAttribute("DownedReaction", data.downedReaction)
			RuntimeTracer.checkpoint(fighter, "Opponent down: " .. data.downedReaction)
		end
		local reaction = data.downedReaction
		if reaction == "switch" and data.downedSwitchTo and data.downedSwitchTo.Parent then
			TargetingModule.setTarget(fighter, data.downedSwitchTo, "DownedSwitch")
			data.downedSwitchTo = nil
			return States.Chase
		elseif reaction ~= "press" and reaction ~= "hold" then
			return States.Circling
		end
		-- press / hold: it stays in the fight, facing the body, without striking
		local locoDt = math.clamp(now - (data.lastLocoTime or (now - 0.05)), 1 / 60, 0.25)
		data.lastLocoTime = now
		FightState.faceTarget(rootPart, targetHRP, data)
		local gap = CombatConfig.Fight_DownedPressGap or 6
		if reaction == "press" and distance > gap + 1 then
			LocomotionModule.steer(fighter, humanoid, rootPart, targetHRP.Position, math.clamp((distance - gap) * 3 + 6, 8, 22), locoDt)
		else
			LocomotionModule.brake(fighter, humanoid, rootPart, locoDt)
		end
		GaitModule.update(humanoid, rootPart, locoDt)
		return FightState
	end
	if data.downedTarget then
		data.downedTarget, data.downedReaction, data.downedSwitchTo = nil, nil, nil
		fighter:SetAttribute("DownedReaction", nil)
	end
	
	-- Early exit for Projectile Jumps (tactical aerial leap, strictly gated by mana & cooldown)
	local forcedAction = fighter:GetAttribute("ForceAction")
	local roll = math.random()
	local pjEnabled = not inShowdown and (CombatConfig.EnableProjectileJump ~= false) and (fighter:GetAttribute("EnableProjectileJump") ~= false)
	local minDist = CombatConfig.ProjectileJumpMinDistance or 25
	local maxDist = CombatConfig.ProjectileJumpMaxDistance or 800
	local minPJMana = CombatConfig.ProjectileJumpMinEnergy or 40
	local lastPJ = fighter:GetAttribute("LastProjectileJumpTime") or 0
	local speedMult = workspace:GetAttribute("GameSpeedMultiplier") or 1.0
	local aggression = Pers.get(fighter, "Aggression")
	local pjCooldown = ((aggression > 0.7) and 14.0 or 18.0) / speedMult
	local isPJOnCooldown = (now - lastPJ) < pjCooldown
	local energy = fighter:GetAttribute("Energy") or 100
	local pjChance = fighter:GetAttribute("ProjectileJumpChance") or CombatConfig.ProjectileJumpChance or 0.35

	-- (team coordination step 5, owner 2026-10-27: a Quin stood in its fight and then burst into a
	-- rocket jump for no reason) the jump needs one: the target is up high, running off, or cannot
	-- be reached on foot
	local pjWhy = nil
	local tRoot = target and target:FindFirstChild("HumanoidRootPart")
	if tRoot and distance >= minDist and distance <= maxDist then
		local gap = tRoot.Position - rootPart.Position
		local flatGap = Vector3.new(gap.X, 0, gap.Z)
		local away = flatGap.Magnitude > 0.1 and tRoot.AssemblyLinearVelocity:Dot(flatGap.Unit) or 0
		if gap.Y > (CombatConfig.ProjectileJump_FightUpGap or 8) then
			pjWhy = "rocket at it: it is up high"
		elseif away > (CombatConfig.ProjectileJump_FightFleeSpeed or 14) then
			pjWhy = "rocket at it: it is running off"
		elseif not NavigationModule.isReachable(rootPart, tRoot) then
			pjWhy = "rocket at it: no way on foot"
		elseif CombatConfig.ProjectileJump_FightWithoutReason == true then
			pjWhy = "?"
		end
	end
	if not inShowdown and (forcedAction == "projectile_jump" or (pjEnabled and pjWhy and not isPJOnCooldown and energy >= minPJMana and roll < pjChance)) then
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
		
		fighter:SetAttribute("JumpWhy", forcedAction == "projectile_jump" and "forced action" or pjWhy) -- (JumpLog, team step 5)
		return States.ProjectileJump
	end
	
	-- Too far? Chase. By time when Reach is on (design doc 5.2): a target getting away is chased
	-- at once, one coming in is waited for, whatever the studs (within a hard cap either way).
	local reach = Reach.enabled() and Reach.measure(fighter, rootPart, target) or nil
	if reach then Reach.publish(fighter, reach) end
	local tooFar
	if reach then
		local combatRange = CombatConfig.CombatRange or 8.2
		tooFar = distance > combatRange * (CombatConfig.Reach_FightMaxRangeFactor or 4)
			or (distance > combatRange * 1.2 and reach.time > (CombatConfig.Reach_FightLeaveTime or 0.4))
	else
		tooFar = distance > (CombatConfig.CombatRange or 8.2) * 2.5
	end
	-- (not while its own strike is still before its cancel point: a kick thrown from a run at a
	-- target moving off was dropped half-way and the body ran off sideways - owner's bookmark 8,
	-- 2026-10-29. The strike plays out, then the chase. Switch: Fight_FinishStrike = false)
	local midStrike = CombatConfig.Fight_FinishStrike ~= false
		and (data.currentAction == "light" or data.currentAction == "heavy") and now < (data.actionEndTime or 0)
	if tooFar and not midStrike then
		if DEBUG then print("[Fight] Target too far -> Chase") end
		return States.Chase
	end

	-- Close but out of reach (a wall or a platform edge between them): Chase finds the way
	-- round. Half a second of grace so a body passing between them does not end the fight.
	-- (and close enough in height, with nothing between, for a strike to land: canStrikeAt. A
	-- target merely in the air comes back down: only one standing up there or down there counts)
	local strikeOk, strikeWhy = NavigationModule.canStrikeAt(rootPart, targetHRP)
	local targetHum = target:FindFirstChildOfClass("Humanoid")
	local targetStanding = targetHum ~= nil and targetHum.FloorMaterial ~= Enum.Material.Air
	fighter:SetAttribute("StrikeHeld", (not strikeOk) and strikeWhy or nil) -- (probes, inspect card)
	if NavigationModule.isReachable(rootPart, targetHRP) and (strikeOk or (strikeWhy ~= "wall" and not targetStanding)) then
		data.unreachableSince = nil
	else
		data.unreachableSince = data.unreachableSince or now
		if now - data.unreachableSince > 0.5 and not midStrike then
			data.unreachableSince = nil
			return States.Chase
		end
	end
	
	-- Face target smoothly via physics torque AlignOrientation (Zero CFrame snapping / yaw pop)
	FightState.faceTarget(rootPart, targetHRP, data)
	
	-- Distance management
	local idealRange = CombatConfig.CombatRange or 8.2
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
		and fighter:GetAttribute("StrikeChannel") ~= "Arms" -- (an arms-only strike: the legs keep their footwork)
	if striking then
		LocomotionModule.brake(fighter, humanoid, rootPart, locoDt)
	elseif data.closingGap then
		-- Close the gap through the shared locomotion path (acceleration, turn rate, gait).
		-- Approach pace scales with the gap so a 2-stud correction is a step, not a sprint burst.
		local maxApproach = fighter:GetAttribute("Speed") or 40
		local approachSpeed = math.clamp(8 + (distance - idealRange) * 4, 10, maxApproach)
		if CombatConfig.Flow_ArriveHot ~= false then
			-- Arriving hot (design doc phase 2: nothing resets): as fast as it can still brake
			-- from by striking range, not slowing from far out. (Entering a fight kept a third of
			-- the chase's speed: 0.27-0.46 in the Phase 0 baseline.)
			local braking = CombatConfig.Locomotion_BrakingDeceleration or 95
			approachSpeed = math.clamp(math.sqrt(2 * braking * math.max(distance - idealRange, 0)) + 6, 10, maxApproach)
		end
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
			KnockbackModule.applySlide(fighter, FightState.backStepDir(fighter, rootPart, data, awayFlat.Unit, now), CombatConfig.Melee_SlideSpeed or 10, 0.3) -- refreshed each tick; eases out once spacing is restored
			if not AnimationModule.isPlaying(humanoid, AnimationIds.RetreatBackstep) then
				AnimationModule.play(humanoid, AnimationIds.RetreatBackstep, Enum.AnimationPriority.Movement, false, 1.2, 0.1)
			end
		end
	else
		-- Inside the combat sweet spot: hold stance firmly with momentum continuity
		LocomotionModule.brake(fighter, humanoid, rootPart, locoDt)
	end
	-- An arms-only strike leaves the legs theirs: they step with whatever moves the body (the
	-- step-in, the brake) instead of standing in the fight idle while it glides
	if fighter:GetAttribute("Attacking") == true and fighter:GetAttribute("StrikeChannel") == "Arms" then
		GaitModule.update(humanoid, rootPart, locoDt)
	end
	
	-- Sideways no faster than the walk strafe can step (owner 2026-10-29, with the run strafe
	-- clips off: a body carrying its own speed sideways at 15-20 studs/s, turning to a target that
	-- moved, slid its feet under the walk strafe on 30% of Fight's walk-strafe frames). Only its
	-- own motion: a push (a hit, a knockback, a strike's lunge: ImpulseModule) is left alone.
	-- (Fight_MaxStrafeSpeed = false: no cap; back on with the run strafe clips)
	local strafeCap = CombatConfig.Fight_MaxStrafeSpeed
	if strafeCap and CombatConfig.Strafe_RunClips ~= true then
		local pushed = rootPart:FindFirstChild("ImpulseLV")
		if not (pushed and pushed.Enabled and pushed.VectorVelocity.Magnitude > 1) then
			local v = rootPart.AssemblyLinearVelocity
			local right = rootPart.CFrame.RightVector
			right = Vector3.new(right.X, 0, right.Z)
			if right.Magnitude > 0.01 then
				right = right.Unit
				local side = v:Dot(right)
				if math.abs(side) > strafeCap then
					rootPart.AssemblyLinearVelocity = v - right * (side - math.sign(side) * strafeCap)
				end
			end
		end
	end

	local speedMult = workspace:GetAttribute("GameSpeedMultiplier") or 1.0

	-- Currently executing an action? (Respects dynamic cancel window)
	if data.currentAction and now < data.actionEndTime then
		return FightState
	end

	-- Attack cooldown
	local minCooldown = CombatConfig.AttackCooldownMin or 0.2
	local maxCooldown = CombatConfig.AttackCooldownMax or 0.7
	local attackSpeed = fighter:GetAttribute("AttackSpeed") or 1.0
	
	local cooldown = 0
	local currentComboStep = ComboModule.getComboStep(fighter)
	if currentComboStep > 0 then
		cooldown = 0.05 / speedMult -- Fast combo chaining immediately at cancel window!
	else
		cooldown = (minCooldown + math.random() * (maxCooldown - minCooldown)) / (attackSpeed * speedMult)
		-- feelings press it on or hold it back (Modules/Drives)
		cooldown /= Drives.aggression(fighter)
	end
	-- The fight's tempo (Modules/Rhythm): a breath after a burst, an explosion after a long quiet
	local tempo = Rhythm.tempo(fighter, target, distance < 20)
	if tempo == "breath" and currentComboStep == 0 then
		cooldown *= CombatConfig.Rhythm_BreathCooldown or 1.8
		-- (now and then the breath is a stand-off: it circles its opponent)
		if not data.breathCircled and math.random() < (CombatConfig.Rhythm_BreathCircleChance or 0.35) then
			data.breathCircled = true
			return States.Circling
		end
	else
		data.breathCircled = nil
	end
	if tempo == "explode" then
		cooldown = 0
	end
	
	if (now - data.lastAttackTime) < cooldown then
		-- Between its own attacks the Quin can still see a strike coming and guard it
		if distance <= 9 and not Instinct.enabled() then
			tryRaiseGuard(fighter, humanoid, data, now, target, reactiveGuardChance(fighter))
		end
		-- Maintain base idle stance during recovery / cooldown
		if now >= (data.attackFinishTime or 0) then
			AnimationModule.ensureBaseIdle(humanoid)
		end
		-- (out of a dodge the counter does not wait for the cooldown)
		if not ((fighter:GetAttribute("CounterUntil") or 0) > now) then
			return FightState
		end
	end

	-- Round a guard, or after a strike was stopped: a focused dash to its side, still facing it,
	-- and the strike comes from the new angle (Modules/Evasion)
	if distance < 12 and Evasion.dashReady(fighter) and currentComboStep == 0
		and (target:GetAttribute("IsGuarding") == true or fighter:GetAttribute("StrikeResult") == "Blocked")
		and math.random() < (CombatConfig.FocusDash_OpeningChance or 0.5) then
		local toT = Vector3.new(targetHRP.Position.X - rootPart.Position.X, 0, targetHRP.Position.Z - rootPart.Position.Z)
		local side = Vector3.new(-toT.Z, 0, toT.X) * (math.random() < 0.5 and -1 or 1)
		if Evasion.focusDash(fighter, humanoid, rootPart, targetHRP, side) then
			fighter:SetAttribute("StrikeResult", nil)
			fighter:SetAttribute("CounterUntil", now + 0.5 + 0.5)
			return FightState
		end
	end

	-- DECIDE ACTION
	local action = decideAction(fighter, target, distance, data)
	-- (an explosion after a long quiet: in hard, with a dash when there is room for one, else heavy)
	if tempo == "explode" and (action == "light" or action == "dodge" or action == "block") then
		local dashOk = distance >= (CombatConfig.DashMinDistance or 15) and (fighter:GetAttribute("Energy") or 0) >= (CombatConfig.DashMinEnergy or 25)
		action = dashOk and "dash" or "heavy"
		fighter:SetAttribute("EngagedSince", GameClock.now())
	end
	-- Dodge into counter (phase 2): inside the window a dodge opened, the answer is a strike
	if (fighter:GetAttribute("CounterUntil") or 0) > now then
		fighter:SetAttribute("CounterUntil", nil)
		action = "light"
		fighter:SetAttribute("CounterAt", now) -- (probes)
	end

	-- A strike is only thrown at a target the step-in can reach. Out of reach the Quin keeps
	-- closing (the approach above) instead of swinging at air and losing its combo.
	-- (moving in fast, the strike starts a beat earlier: the lunge covers the extra gap)
	local strikeReach = CombatConfig.Combat_StrikeRange or 9.0
	if CombatConfig.Flow_ArriveHot ~= false then
		local v = rootPart.AssemblyLinearVelocity
		strikeReach += math.min(Vector3.new(v.X, 0, v.Z).Magnitude * (CombatConfig.Flow_StrikeLeadTime or 0.1), CombatConfig.Flow_StrikeLeadMax or 4)
	end
	if (action == "light" or action == "heavy") and distance > strikeReach then
		-- Step in now. The approach only restarts past idealRange + 2 (10.2), beyond the strike
		-- range (9): a Quin left 9-10 studs out neither struck nor closed, and two of them stood
		-- facing each other (21% of close fighting, up to 11 s at a time).
		data.closingGap = true
		return FightState
	end
	-- No strike that cannot land: too high, too low, or through something solid (canStrikeAt)
	if (action == "light" or action == "heavy") and not strikeOk then
		return FightState
	end
	-- ...and only once the body faces the target (the facing gyro turns it meanwhile)
	if action == "light" or action == "heavy" then
		local toTarget = Vector3.new(targetHRP.Position.X - rootPart.Position.X, 0, targetHRP.Position.Z - rootPart.Position.Z)
		local look = Vector3.new(rootPart.CFrame.LookVector.X, 0, rootPart.CFrame.LookVector.Z)
		local facing = (toTarget.Magnitude > 0.01 and look.Magnitude > 0.01) and look.Unit:Dot(toTarget.Unit) or 1
		if facing < (CombatConfig.Combat_StrikeFacingDot or 0.8) then
			data.faceWaitSince = data.faceWaitSince or now
			if now - data.faceWaitSince < (CombatConfig.Combat_StrikeFacingWait or 0.5) then
				return FightState
			end
		end
		data.faceWaitSince = nil
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
		local moveData, attackDuration = FightState.throwStrike(fighter, humanoid, rootPart, target, "Light", data, DEBUG)
		if moveData then
			-- Check for launch transition
			if moveData.isLaunch then
				GameClock.delay((attackDuration + 0.05) / speedMult, function()
					if fighter.Parent and fighter:GetAttribute("CurrentState") == "Fight" then
						StateRequest.ask(fighter, "Airborne", StateRequest.FOLLOW, "launch follow-up")
					end
				end)
			end
		end
		
	elseif action == "heavy" then
		FightState.throwStrike(fighter, humanoid, rootPart, target, "Heavy", data, DEBUG)
		
	elseif action == "dash" then
		data.currentAction = "dash"
		data.actionEndTime = now + (0.5 / speedMult)
		data.attackFinishTime = now + (0.5 / speedMult)
		if targetHRP then
			fighter:SetAttribute("JumpWhy", "fight dash") -- (JumpLog, team step 5)
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
		-- (the full-body clip only while standing; on the move the head and shoulders)
		LocomotionModule.glanceBack(fighter, humanoid, rootPart, 1.0, 0.6)
		return FightState
		
	elseif action == "block" then
		data.currentAction = "block"
		data.actionEndTime = now + (0.45 / speedMult)
		data.attackFinishTime = now + (0.45 / speedMult)
		fighter:SetAttribute("IsGuarding", true)
		AnimationModule.playConfig(humanoid, "Reactions.Block", 1.0, Enum.AnimationPriority.Action4, false)
		GameClock.delay(0.45 / speedMult, function()
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
			local slideDir = awayFlat.Unit
			if CombatConfig.Flow_DodgeCounter ~= false then
				-- A slip off the line, not only straight back: the counter comes from an angle
				-- (agile Quins slip more often)
				local mobility = Pers.get(fighter, "MobilityPreference")
				if math.random() < (CombatConfig.Flow_DodgeSlipChance or 0.5) * (0.5 + mobility) then
					local side = Vector3.new(-slideDir.Z, 0, slideDir.X) * (math.random() < 0.5 and -1 or 1)
					slideDir = (side * 0.85 + slideDir * 0.5).Unit
				end
				fighter:SetAttribute("CounterUntil", now + (CombatConfig.Flow_CounterWindow or 0.7))
			end
			-- the legs go with it (audit 2026-10-27: the dodge had no clip, a standing fight pose
			-- glided 6-9 studs): the quick evade leaning the way the body goes
			local right = rootPart.CFrame.RightVector
			local flatRight = Vector3.new(right.X, 0, right.Z)
			local lateral = flatRight.Magnitude > 0.01 and slideDir:Dot(flatRight.Unit) or 0
			local evadeClip = (lateral > 0.5 and "Tactics.QuickEvadeRight") or (lateral < -0.5 and "Tactics.QuickEvadeLeft") or "Tactics.QuickEvadeBack"
			-- A strike on its way in is leaned out of on the spot (Modules/Evasion: the clip's own
			-- ~1.4-stud sway; the strike misses while the lean is in). The clip is an in-place lean:
			-- under the old 35 studs/s slide (~8 studs) its feet skated.
			local windupUntil = target:GetAttribute("AttackWindupUntil")
			local evaded = target:GetAttribute("Attacking") == true and windupUntil and windupUntil > GameClock.tick()
				and require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("Evasion")).evade(fighter, humanoid, rootPart, target, targetHRP, windupUntil)
			if evaded then
				if evaded == "right" then
					fighter:SetAttribute("CounterUntil", GameClock.tick() + (CombatConfig.Flow_CounterWindow or 0.7) + 0.3)
				end
			else
				-- nothing coming: a short step off the line with the lean, not a skate
				AnimationModule.playConfig(humanoid, evadeClip, CombatConfig.Flow_DodgeClipSpeed or 1.2, Enum.AnimationPriority.Action3, false)
				-- (in place: the lean is the dodge, no push under it; QuickEvade_InPlace = false: the step)
				if CombatConfig.QuickEvade_InPlace == false then
					KnockbackModule.applySlide(fighter, slideDir, CombatConfig.Flow_DodgeSlideSpeed or 12, 0.25)
				else
					local v = rootPart.AssemblyLinearVelocity
					rootPart.AssemblyLinearVelocity = Vector3.new(0, v.Y, 0)
				end
			end
		end
		return FightState
		
	elseif action == "special" then
		data.lastSpecialTime = now
		data.currentAction = "special"
		data.actionEndTime = now + 1.0
		data.attackFinishTime = now + 1.0
		return States.Special
		
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
			local facingGyro = Facing.get(rootPart, "Fight")
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
			
			TargetingModule.setTarget(fighter, rearThreatModel, "RearThreat")
			data.lastEngagedTarget = rearThreatModel.Name
			
			local awareness = Pers.get(fighter, "Awareness")
			if math.random() < (0.3 + awareness * 0.4) then
				fighter:SetAttribute("IsGuarding", true)
				GameClock.delay(0.35 / speedMult, function()
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
		local slideDir = (awayFlat.Magnitude > 0.01) and FightState.backStepDir(fighter, rootPart, data, awayFlat.Unit, now) or -rootPart.CFrame.LookVector
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
		GameClock.delay(0.55 / speedMult, function()
			if fighter.Parent then
				fighter:SetAttribute("Attacking", false)
			end
		end)
		
		-- Forward lunge slide to carve space from the cluster
		local lungeDir = rootPart.CFrame.LookVector
		KnockbackModule.applySlide(fighter, Vector3.new(lungeDir.X, 0, lungeDir.Z), 30, 0.2)
		
		-- Apply hitbox for the counter-strike at the punch's impact, not on its first frame (owner
		-- 2026-10-27: Quins were knocked back with no strike seen: this hit landed the frame the clip
		-- started). Hit or knocked out of the fight while winding up, the counter never comes out.
		local windupUntil = fighter:GetAttribute("AttackWindupUntil")
		GameClock.delay(0.22 / speedMult, function()
			if not fighter.Parent or humanoid.Health <= 0 or fighter:GetAttribute("CurrentState") ~= "Fight"
				or fighter:GetAttribute("StrikeInterrupted") == windupUntil then
				return
			end
			local hitboxSize = Vector3.new(7, 5, 7) -- Wide arc
			local hitboxOffset = Vector3.new(0, 0, -3.5)
			local hitModels = HitboxModule.castInFront(rootPart, hitboxSize, hitboxOffset, fighter)
			for _, hitModel in ipairs(hitModels) do
				-- Counter-strike: 1.3x damage multiplier, step 1 (standalone hit)
				local damageInfo = DamageModule.calculate(fighter, hitModel, 1, 1.3)
				local applied = DamageModule.apply(fighter, hitModel, damageInfo)
				if applied then
					-- Carves breathing room like a finisher: knocks the victim back along the ground,
					-- or launches it by the same chance
					applyHitOutcome(rootPart, hitModel, DESPERATE_COUNTER_MOVE, DamageModule.resolveOutcome(fighter, hitModel, DESPERATE_COUNTER_MOVE, damageInfo))
				end
			end
			fighter:SetAttribute("StrikeEndAt", GameClock.tick())
		end)
		
		-- After counter, briefly guard
		GameClock.delay(0.3 / speedMult, function()
			if fighter.Parent then
				fighter:SetAttribute("IsGuarding", true)
				GameClock.delay(0.4 / speedMult, function()
					if fighter.Parent then fighter:SetAttribute("IsGuarding", false) end
				end)
			end
		end)
		
		return FightState
	end

	-- (asked during this tick: a hit, its own launch, a counter or a social order)
	local fs = StateRequest.take(fighter)
	if fs then
		return States[fs]
	end
	
	return FightState
end

return FightState