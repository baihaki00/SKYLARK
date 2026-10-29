--// FightState/Strike.lua
-- One strike, start to finish: which punch or kick (what it learned of this opponent in this
-- fight), the clip and the owner's markers, the tell, the step in, contact on every frame of the
-- window, and what became of it (landed, blocked, dodged, whiffed; the footing it costs the
-- victim). FightState.throwStrike calls it for the AI and the player alike.
-- (Moved out of FightState as it was: QuinCore audit 2026-10-27, step 7.)

local GameClock = require(game:GetService("ReplicatedStorage"):WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("GameClock")) -- (the game's clock: a freeze stops it)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
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
local LocomotionModule = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("LocomotionModule"))
local HitStop = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("HitStop"))
local StrikeMarkers = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("StrikeMarkers"))
local RunService = game:GetService("RunService")
local StateRequest = require(game:GetService("ReplicatedStorage"):WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("StateRequest")) -- (asking a Quin to change state)

local Strike = {}

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

-- Footing consequence of a landed strike. A flinch needs nothing here: DamageModule.apply has
-- already slid the victim back on its feet.
-- How hard an air knockback throws, by the weight of the hit (owner 2026-10-29: "scale it"). The
-- floor (Combat_LaunchMinForce 60) x 1.5, x 1.5 again in applyKnockback put every launch over the
-- 110 studs/s cap: a jab threw a body as far as a finisher, 86 studs (median of 55 in a 16v16).
-- Now the move's knockback (ComboModule: Jab 18 .. PowerPunch 105, OverheadSlam 126) sets the
-- launch speed between Knockback_LightLaunch and Knockback_HeavyLaunch, a crit or a hit from behind
-- counting Knockback_CritWeight heavier. The upward part stays min(speed, 75): a jab ~20 studs,
-- an uppercut ~38, a finisher the full ~80. Switch: Knockback_ScaleByHit = false.
local function launchForce(moveData, damageInfo)
	local knockback = moveData.knockback or 0
	if CombatConfig.Knockback_ScaleByHit == false then
		return math.max(knockback, CombatConfig.Combat_LaunchMinForce or 60) * 1.5
	end
	local light, heavy = CombatConfig.Knockback_LightForce or 18, CombatConfig.Knockback_HeavyForce or 105
	local weight = math.clamp((knockback - light) / (heavy - light), 0, 1)
	if damageInfo and (damageInfo.isCrit or damageInfo.isBackAttack) then
		weight = math.min(weight + (CombatConfig.Knockback_CritWeight or 0.25), 1)
	end
	local slow, fast = CombatConfig.Knockback_LightLaunch or 45, CombatConfig.Knockback_HeavyLaunch or 110
	return (slow + (fast - slow) * weight) / 1.5 -- (applyKnockback launches at force x 1.5)
end

local function applyHitOutcome(rootPart, hitModel, moveData, outcome, damageInfo)
	local hitRoot = hitModel:FindFirstChild("HumanoidRootPart")
	if not hitRoot or outcome == DamageModule.Outcome.Flinch then return end

	local away = rootPart.CFrame.LookVector
	AudioModule.playSlam(hitRoot.Position)
	StateRequest.ask(hitModel, "Knockback", StateRequest.HIT, "struck")
	if outcome == DamageModule.Outcome.AirKnockback then
		hitModel:SetAttribute("KnockbackType", "air")
		KnockbackModule.applyKnockback(hitModel, away, launchForce(moveData, damageInfo))
		hitModel:SetAttribute("LaunchMove", moveData.name) -- (probes)
	else
		hitModel:SetAttribute("KnockbackType", "ground")
		local minStuds = CombatConfig.Combat_GroundKnockbackMinStuds or 10
		local maxStuds = CombatConfig.Combat_GroundKnockbackMaxStuds or 18
		KnockbackModule.applyGroundSkid(hitModel, away, minStuds + math.random() * (maxStuds - minStuds), CombatConfig.Combat_GroundKnockbackTime or 0.6)
	end
end

-- What each Quin remembers of each opponent within a fight: how its punches and kicks fared
-- (design doc phase 4: learning within a fight). attacker -> { [opponent name] = { punch = {n, stopped}, kick = {...} } }
local strikeMemory = setmetatable({}, { __mode = "k" })

local function isKick(entry)
	return entry and entry.name and entry.name:find("Kick") ~= nil
end

-- The strike, chosen as an answer (design doc phase 4) rather than rolled:
--   the opponent is open (its own strike just missed): the fastest, a punch
--   the opponent is guarding: a kick (heavier, and from further out)
--   the gap is at the edge of reach: a kick
--   and away from whatever this opponent has been stopping (blocked or dodged)
-- Then any clip of that kind. Returns the clip entry and the reason (StrikeAnswer, for probes).
local function chooseStrike(fighter, target, distance, punches, kicks)
	if CombatConfig.Answers_Enabled == false or not target or #punches == 0 or #kicks == 0 then
		local pool = (math.random() > 0.5 and #punches > 0) and punches or kicks
		if #pool == 0 then pool = punches end
		return pool[math.random(1, math.max(#pool, 1))], nil
	end
	local wPunch, wKick, reason = 1, 1, nil
	local now = GameClock.tick()
	if target:GetAttribute("StrikeResult") == "Whiff" and now - (target:GetAttribute("StrikeEndAt") or 0) < (CombatConfig.Answers_OpenWindow or 0.6) then
		wPunch *= CombatConfig.Answers_PunishWeight or 3
		reason = "punish"
	end
	if target:GetAttribute("IsGuarding") == true then
		wKick *= CombatConfig.Answers_GuardWeight or 2.5
		reason = reason or "guard"
	end
	if distance and distance > (CombatConfig.Answers_ReachDistance or 7) then
		wKick *= CombatConfig.Answers_ReachWeight or 1.8
		reason = reason or "reach"
	end
	local memory = strikeMemory[fighter] and strikeMemory[fighter][target.Name]
	if memory then
		for kind, record in pairs(memory) do
			local stopRate = (record.stopped + 1) / (record.n + 2)
			if kind == "punch" then wPunch *= (1.25 - stopRate) else wKick *= (1.25 - stopRate) end
		end
	end
	-- Then each clip on its own: where would it land? A clip whose limb would pass over the
	-- target's head or under its feet (a punch at a body standing a platform below) is a poor
	-- choice, so it is weighted down, not ruled out (Answers_HeightAware = false: kind, then any clip)
	local myRoot = fighter:FindFirstChild("HumanoidRootPart")
	local theirRoot = target:FindFirstChild("HumanoidRootPart")
	if CombatConfig.Answers_HeightAware == false or not myRoot or not theirRoot then
		local useKick = math.random() * (wPunch + wKick) < wKick
		local pool = useKick and kicks or punches
		return pool[math.random(1, #pool)], reason or (memory and "learned" or nil)
	end
	local low = CombatConfig.Answers_BodyBelow or -3.0
	local high = CombatConfig.Answers_BodyAbove or 2.5
	local floor = CombatConfig.Answers_OffBodyWeight or 0.08
	local rise = myRoot.Position.Y - theirRoot.Position.Y
	local choices, total, bestFit = {}, 0, 0
	for _, kind in ipairs({ { punches, wPunch / #punches }, { kicks, wKick / #kicks } }) do
		for _, entry in ipairs(kind[1]) do
			local fit = 1
			if entry.height then
				local land = rise + entry.height
				local off = math.max(low - land, land - high, 0)
				fit = math.max(1 - off / 1.5, floor)
			end
			bestFit = math.max(bestFit, fit)
			local w = kind[2] * fit
			total += w
			table.insert(choices, { entry, w })
		end
	end
	local roll = math.random() * total
	local picked = choices[#choices][1]
	for _, c in ipairs(choices) do
		roll -= c[2]
		if roll <= 0 then picked = c[1] break end
	end
	if bestFit < 1 or math.abs(rise) > 1.5 then reason = reason or "height" end
	return picked, reason or (memory and "learned" or nil)
end

local function remember(fighter, target, entry, result)
	if not target then return end
	local byOpponent = strikeMemory[fighter]
	if not byOpponent then
		byOpponent = {}
		strikeMemory[fighter] = byOpponent
	end
	local memory = byOpponent[target.Name]
	if not memory then
		memory = {}
		byOpponent[target.Name] = memory
	end
	local kind = isKick(entry) and "kick" or "punch"
	local record = memory[kind] or { n = 0, stopped = 0 }
	record.n += 1
	if result == "Blocked" or result == "Dodged" then record.stopped += 1 end
	memory[kind] = record
end

local function executeAttack(fighter, humanoid, rootPart, target, moveData, data, DEBUG)
	-- (target may be nil: a player's Quin can strike at the air; no step-in then)
	local targetHRP = target and target:FindFirstChild("HumanoidRootPart")
	if target and not targetHRP then return 0.5, 0.35 end
	-- (out of a full run the strike takes the momentum: the stop-run plant is cut short)
	LocomotionModule.cutStopRun(fighter, humanoid)
	local energy = fighter:GetAttribute("Energy") or 100
	local fatigueScale = energy < (CombatConfig.FatigueThreshold or 25) and (CombatConfig.Fatigue_StrikeSpeed or 0.85) or 1.0 -- (owner 2026-10-27: 0.65 looked too slow and weak)
	
	-- Dynamic animation resolution: directly reads live hot-swapped configuration!
	local punches, kicks = getLiveAttacks()
	local targetDistance = targetHRP and (targetHRP.Position - rootPart.Position).Magnitude or nil
	local chosen, answerReason = chooseStrike(fighter, target, targetDistance, punches, kicks)
	local animData = chosen or { id = AnimationIds.Punches[1], speed = 1.3, fadeTime = 0.01, impactRatio = 0.35, cancelRatio = 0.70 }
	fighter:SetAttribute("StrikeAnswer", answerReason) -- (probes, mind panel)
	fighter:SetAttribute("StrikeKind", isKick(chosen) and "kick" or "punch") -- (probes)

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
	-- The owner's markers in the clip (Modules/StrikeMarkers): contact is checked on every frame
	-- from HitStart to HitEnd, and the Quin is free to act and move at Recover. A clip without
	-- them (or not read yet): one check at impactRatio, free at cancelRatio, done at the clip's end.
	local markers = CombatConfig.Combat_UseStrikeMarkers ~= false and StrikeMarkers.get(animData.id) or nil
	local impactDelay, windowEnd, cancelDelay, finishDelay
	if markers then
		impactDelay = markers.hitStart / playSpeed
		windowEnd = markers.hitEnd / playSpeed
		cancelDelay = (markers.recover or rawLength * cancelRatio) / playSpeed
		finishDelay = cancelDelay
	else
		impactDelay = effectiveDuration * impactRatio
		windowEnd = impactDelay
		cancelDelay = effectiveDuration * cancelRatio
		finishDelay = effectiveDuration
	end
	fighter:SetAttribute("StrikeTiming", markers and "markers" or "ratios") -- (debug HUD, probes)
	-- which part of the body the clip drives (AnimationConfig channel): an arms-only strike leaves
	-- the legs to the footwork (FightState does not plant them; the client's feet keep planting)
	fighter:SetAttribute("StrikeChannel", animData.channel or "Body")

	-- Set telegraphing attributes for causal defense (impact window driven by config)
	local now = GameClock.tick()
	fighter:SetAttribute("Attacking", true)
	local windupUntil = now + impactDelay
	fighter:SetAttribute("AttackWindupUntil", windupUntil)
	-- The tell: when this strike can first be read (the Windup marker), and what it is
	-- (Modules/Instinct answers it after the defender's own reaction time)
	local tellDelay = (markers and markers.windup) and math.min(markers.windup / playSpeed, impactDelay) or impactDelay * 0.4
	fighter:SetAttribute("StrikeTellAt", now + tellDelay)
	fighter:SetAttribute("StrikeLow", animData.name and animData.name:find("Low") ~= nil or nil)
	-- (which limb: a left is slipped to the right, a right to the left: Modules/Evasion)
	local limbSide = animData.name and (animData.name:find("Left") and "Left" or animData.name:find("Right") and "Right") or nil
	fighter:SetAttribute("StrikeSide", limbSide)
	-- The strike is over at its finish: then Attacking goes false, unless a newer strike has begun
	-- (its own AttackWindupUntil). A hit-stop moves the finish on (HitStop): the clear waits for it.
	-- (It compared GameClock.tick() with attackFinishTime once, at the original finish: after a hit-stop had
	-- moved the finish, that check failed and Attacking stayed true until the next strike.)
	local function strikeOver()
		if not fighter.Parent or fighter:GetAttribute("AttackWindupUntil") ~= windupUntil then return end
		local remaining = (data.attackFinishTime or 0) - GameClock.tick()
		if remaining > 0.01 and remaining < 1 then
			GameClock.delay(remaining, strikeOver)
			return
		end
		fighter:SetAttribute("Attacking", false)
	end
	GameClock.delay(finishDelay, strikeOver)
		
	-- Step into the strike with momentum, but only as far as the gap: the attacker closes to
	-- striking distance and never drives into (or through) its target
	local lungeSpeed = CombatConfig.Combat_LungeMaxSpeed or 60
	local lungeTime = math.min(effectiveDuration * 0.4, 0.35)
	-- (where this clip's limb lands in the target's body: AnimationConfig reach, Modules/Spacing
	-- holds the attacker there for the whole strike, whatever else moves it)
	local stopDistance = Spacing.strikeStopGap(animData.reach)
	fighter:SetAttribute("StrikeStopGap", stopDistance)
	-- The step goes toward where the target will be at impact (its velocity, Combat_StrikeLead
	-- ahead), not along the body's facing toward where it was
	local function stepIn(timeLeft)
		if not (fighter.Parent and targetHRP and targetHRP.Parent) then return end
		local tv = targetHRP.AssemblyLinearVelocity
		local aim = targetHRP.Position + Vector3.new(tv.X, 0, tv.Z) * timeLeft * (CombatConfig.Combat_StrikeLead or 0.6)
		local offset = Vector3.new(aim.X - rootPart.Position.X, 0, aim.Z - rootPart.Position.Z)
		local room = offset.Magnitude - stopDistance
		if room > 0.25 then
			KnockbackModule.applyLunge(fighter, offset.Unit, lungeSpeed, math.clamp(timeLeft, 0.08, lungeTime), room)
		end
	end
	stepIn(impactDelay)
	-- ...and again halfway through the wind-up, at a target that kept moving
	if CombatConfig.Combat_StrikeTracking ~= false then
		GameClock.delay(impactDelay * 0.5, function()
			if fighter:GetAttribute("AttackWindupUntil") == windupUntil and fighter:GetAttribute("StrikeInterrupted") ~= windupUntil then
				stepIn(impactDelay * 0.5)
			end
		end)
	end

	-- Punch sound (precisely synchronized with strike apex)
	local soundPart = fighter:FindFirstChild("Sounds")
	if soundPart then
		local punch = soundPart:FindFirstChild("punch1")
		if punch then
			GameClock.delay(math.max(0, impactDelay - 0.04), function()
				punch.Volume = 0.15
				punch.PlaybackSpeed = math.random(18, 26) / 10
				punch:Play()
			end)
		end
	end
	
	-- Contact: checked from the start of the window on every frame until it closes (one check
	-- when the clip has no markers). Each body is struck once; the window closes early once the
	-- target itself has been met (hit, blocked or dodged).
	local struck = {}
	local landed = false
	local result = "Whiff"

	-- (the box is wider and longer than any limb: a body in it counts only once this clip's limb
	-- can get there, its reach plus the body's radius and a little slack; a fist that stops a stud
	-- short is a whiff, not a hit. Fight programme step 3)
	local contactRange = (CombatConfig.Hits_ContactCheck ~= false and animData.reach)
		and animData.reach + (CombatConfig.Spacing_TargetRadius or 0.72) + (CombatConfig.Hits_ContactSlack or 0.6) or nil
	-- (and only where the limb lands in the body's height, with nothing solid between the two
	-- chests: hits went through a box's edge to a Quin 7 studs below. Fight_StrikeHeightCheck)
	local heightParams
	local function inReach(hitModel)
		local body = hitModel:FindFirstChild("HumanoidRootPart")
		if body and CombatConfig.Fight_StrikeHeightCheck ~= false then
			local land = rootPart.Position.Y + (animData.height or 0)
			local slack = CombatConfig.Hits_HeightSlack or 1.0
			if land < body.Position.Y + (CombatConfig.Answers_BodyBelow or -3) - slack
				or land > body.Position.Y + (CombatConfig.Answers_BodyAbove or 2.5) + slack then
				return false
			end
			if not heightParams then
				heightParams = RaycastParams.new()
				heightParams.FilterType = Enum.RaycastFilterType.Exclude
				heightParams.RespectCanCollide = true
			end
			heightParams.FilterDescendantsInstances = { fighter, hitModel, workspace:FindFirstChild("QuinServer") }
			local chest = Vector3.new(0, 1, 0)
			local offset = (body.Position + chest) - (rootPart.Position + chest)
			if offset.Magnitude > 0.5 and workspace:Raycast(rootPart.Position + chest, offset, heightParams) then
				return false
			end
		end
		local r = contactRange and body
		if not r then return true end
		local d = r.Position - rootPart.Position
		return Vector3.new(d.X, 0, d.Z).Magnitude <= contactRange
	end
	-- Where on the body it lands: the clip's height (AnimationConfig) against the target's root, so
	-- a punch to someone below is a head shot and a kick to someone above takes the legs
	local function zoneOf(hitModel)
		local r = CombatConfig.Hits_Zones ~= false and animData.height and hitModel:FindFirstChild("HumanoidRootPart")
		if not r then return nil end
		local above = rootPart.Position.Y + animData.height - r.Position.Y
		if above >= (CombatConfig.Hits_HeadAbove or 1.5) then return "Head" end
		if above < (CombatConfig.Hits_LegsBelow or -1.0) then return "Legs" end
		return "Body"
	end

	local function check()
		local hitModels = HitboxModule.castInFront(rootPart, moveData.hitboxSize, Vector3.new(0, 0, -3), fighter)
		for _, hitModel in ipairs(hitModels) do
			if not struck[hitModel] and inReach(hitModel) then
				struck[hitModel] = true
				local damageInfo = DamageModule.calculate(fighter, hitModel, moveData.step, moveData.damageMultiplier)
				damageInfo.isFinisher = moveData.isFinisher
				damageInfo.zone = zoneOf(hitModel)
				local applied, isKill, status = DamageModule.apply(fighter, hitModel, damageInfo)

				if status == "Blocked" or status == "Dodged" then
					if not landed then result = status end
					if DEBUG then print("[Fight] Combo broken by " .. status .. "!") end
					ComboModule.resetCombo(fighter)
					data.lastAttackTime = GameClock.tick() + 0.3 -- Stagger them slightly
				elseif applied then
					landed = true
					result = "Hit"
					-- where in its clip the strike connected: clients draw this clip ~0.1 s behind,
					-- and bring the fist up to here so the body does not fly before it arrives
					-- (AIGhostHandler.syncStrikeContact)
					if track then
						fighter:SetAttribute("StrikeContactClip", animData.id)
						fighter:SetAttribute("StrikeContactPos", track.TimePosition)
						fighter:SetAttribute("StrikeContactAt", GameClock.tick())
					end
					-- the contact holds a beat (Modules/HitStop): kicks, finishers and crits longer
					local held = HitStop.apply(fighter, hitModel, (isKick(animData) and 0.6 or 0.15) + ((moveData.isFinisher or damageInfo.isCrit) and 0.4 or 0))
					-- (its clip reaches Recover that much later: so does its freedom)
					data.actionEndTime = (data.actionEndTime or 0) + held
					data.attackFinishTime = (data.attackFinishTime or 0) + held
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
							CombatConfig.LaunchVerticalForce or 8,
							CombatConfig.LaunchHorizontalForce or 224)
						StateRequest.ask(hitModel, "Knockback", StateRequest.HIT, "struck")
						if DEBUG then print("[Fight] LAUNCH! -> Airborne pursuit") end
					else
						applyHitOutcome(rootPart, hitModel, moveData, DamageModule.resolveOutcome(fighter, hitModel, moveData, damageInfo), damageInfo)
					end
				end
			end
		end
	end

	-- The window is over: what became of this strike
	local function conclude()
		fighter:SetAttribute("StrikeEndAt", GameClock.tick())
		remember(fighter, target, animData, result)
		-- A strike that connects with nothing ends the chain: the next attack opens a new combo
		-- instead of throwing the finisher at empty air
		if not landed then
			ComboModule.resetCombo(fighter)
		end
		-- Strike telemetry (HUD / audits): what became of this strike
		if result == "Whiff" and next(struck) == nil then
			local tHRP = target and target:FindFirstChild("HumanoidRootPart")
			fighter:SetAttribute("StrikeMissDist", tHRP and math.floor((tHRP.Position - rootPart.Position).Magnitude * 10) / 10 or -1)
			-- (swinging at air costs balance: a Quin that keeps whiffing is open to the next blow)
			DamageModule.wearPosture(fighter, CombatConfig.Posture_WhiffCost or 6)
		end
		fighter:SetAttribute("StrikeResult", result)
		fighter:SetAttribute("StrikeSeq", (fighter:GetAttribute("StrikeSeq") or 0) + 1)
		-- A whiff recovers quickly: the follow-through is cut and the Quin can move and strike
		-- again (whiffed clips used to play out in full: 0.6-1 s of swinging at air)
		local recover = CombatConfig.Combat_WhiffRecovery
		if result == "Whiff" and recover then
			GameClock.delay(recover * 0.5, function()
				if fighter.Parent and fighter:GetAttribute("AttackWindupUntil") == windupUntil then
					AnimationModule.stopCategory(humanoid, "Attacks", recover)
				end
			end)
			GameClock.delay(recover, function()
				-- (the strike is over: defenders and the HUD stop reading it as an attack)
				if fighter.Parent and fighter:GetAttribute("AttackWindupUntil") == windupUntil then
					fighter:SetAttribute("Attacking", false)
				end
			end)
			local until_ = GameClock.tick() + recover
			data.actionEndTime = math.min(data.actionEndTime or until_, until_)
			data.attackFinishTime = math.min(data.attackFinishTime or until_, until_)
		end
	end

	GameClock.delay(impactDelay, function()
		if not fighter.Parent or (target and not target.Parent) then return end
		-- Hit while winding up: the strike never comes out and the chain is broken
		-- (also when the Quin was knocked or forced out of its fight before the blow: no strike
		-- may land from a body showing a hit reaction)
		if fighter:GetAttribute("StrikeInterrupted") == windupUntil or fighter:GetAttribute("CurrentState") ~= "Fight" then
			ComboModule.resetCombo(fighter)
			fighter:SetAttribute("StrikeResult", "Interrupted")
			fighter:SetAttribute("StrikeSeq", (fighter:GetAttribute("StrikeSeq") or 0) + 1)
			return
		end
		check()
		local span = windowEnd - impactDelay
		if span <= 0 or struck[target] then
			conclude()
			return
		end
		local opened = GameClock.now()
		local conn
		conn = RunService.Heartbeat:Connect(function()
			if GameClock.frozen() then return end -- (god pause: GameFreeze holds the game)
			-- (the window also closes when the Quin is knocked out of its fight or dies mid-swing)
			local stillSwinging = fighter.Parent and humanoid.Health > 0 and fighter:GetAttribute("CurrentState") == "Fight"
			if stillSwinging then
				check()
			end
			if not stillSwinging or struck[target] or GameClock.now() - opened >= span then
				conn:Disconnect()
				conclude()
			end
		end)
	end)

	return finishDelay, cancelDelay
end

Strike.liveAttacks = getLiveAttacks
Strike.applyHitOutcome = applyHitOutcome
Strike.execute = executeAttack

return Strike
