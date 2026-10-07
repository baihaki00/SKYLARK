--// PilotedState.lua
-- A player's Quin (Player Quin match mode): this state stands where the AI's own decisions would
-- (Idle / Chase / Retreat / Fight ...). It reads the player's input (Modules/PilotInput) and does
-- what those states do with the same calls:
--   moving      LocomotionModule.steer + GaitModule (the AI's acceleration, turning, gait)
--               free: the body faces where it goes; engaged (an enemy within EngageRange and the
--               player not running): it faces that enemy and moves with footwork (back = steps
--               back, sideways = circles; the gait picks strafe or backwards from the motion)
--   lock        (design doc 5.7: lock = attention) the player fixes the Quin's focus on one enemy:
--               Lock takes the nearest threat in view (or lets go), LockNext moves to the next.
--               Locked, the Quin is engaged with that enemy at any range unless running, and its
--               strikes go at it. The lock lets go when the enemy dies or is out of LockRange.
--   standing    LocomotionModule.brake
--   (PlayerQuin.ClientMovement, on by default: moving, standing, jumping, dashing and sliding run on
--   the player's machine instead, which owns the body while it is in this state, as in Play As
--   Quin: PilotInput.giveBody / reclaimBody, StarterPlayerScripts.PilotClient. This state keeps
--   the rest: strikes, guard, the lock, the squared-up facing, projectile jumps.)
--   strike      FightState.throwStrike (the combo, clip, marker timing, contact and outcome of
--               an AI strike), turned to the target with FightState.faceTarget first
--   guard       IsGuarding and the block clip, as an AI guard (DamageModule reads IsGuarding)
--   dash, slide, jump   LocomotionModule.dash / slide / jump (a jump let go early is cut short)
--   projectile jump     ProjectileJumpState, the AI's own: style 1 (an arc onto the aimed spot or
--                       Quin) or style 2 (a high launch; the player dives when they choose, at
--                       where they aim then, ProjectileJumpState reads PilotInput.takeDive). The
--                       body's cost (mana) applies; the AI's cooldown is its own judgement and
--                       is not a player's limit.
-- Getting hit is the same as for any Quin: Main hands the body to Knockback, Recovery and Death
-- and back to this state afterwards (Main: PILOT_STATES).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local QuinCore = ReplicatedStorage:WaitForChild("QuinCore")
local Modules = QuinCore:WaitForChild("Modules")
local CombatConfig = require(QuinCore:WaitForChild("CombatConfig"))
local AnimationModule = require(Modules:WaitForChild("AnimationModule"))
local LocomotionModule = require(Modules:WaitForChild("LocomotionModule"))
local GaitModule = require(Modules:WaitForChild("GaitModule"))
local PilotInput = require(Modules:WaitForChild("PilotInput"))
local RuntimeTracer = require(Modules:WaitForChild("RuntimeTracer"))
local SpatialModule = require(Modules:WaitForChild("SpatialModule"))

local PilotedState = { name = "Piloted", tickInterval = 1 / 30 }

local pilotData = setmetatable({}, { __mode = "k" })

local function cfg(key, default)
	local t = CombatConfig.PlayerQuin
	local v = t and t[key]
	if v == nil then return default end
	return v
end

local function fightState()
	return require(script.Parent:WaitForChild("FightState"))
end

local function flat(v) return Vector3.new(v.X, 0, v.Z) end
local projectileJump -- (below)
local nearestEnemy, nextEnemy -- (below)

-- The nearest living enemy within `range` on about the same level, or nil
function nearestEnemy(fighter, rootPart, range)
	local folder = Workspace:FindFirstChild("QuinServer")
	if not folder then return nil end
	local team = fighter:GetAttribute("Team")
	local best, bestDist = nil, range
	for _, enemy in ipairs(folder:GetChildren()) do
		local hum = enemy:FindFirstChildOfClass("Humanoid")
		local root = enemy:FindFirstChild("HumanoidRootPart")
		if enemy ~= fighter and hum and root and hum.Health > 0 and (team == nil or enemy:GetAttribute("Team") ~= team)
			and enemy:GetAttribute("CurrentState") ~= "Death" and math.abs(root.Position.Y - rootPart.Position.Y) < 6 then
			local d = flat(root.Position - rootPart.Position).Magnitude
			if d < bestDist then
				best, bestDist = enemy, d
			end
		end
	end
	return best
end

-- The enemy a strike goes at: the nearest within reach, favouring the one in the direction the
-- player is pushing (or facing). nil: the strike goes at the air.
local function strikeTarget(fighter, rootPart, input)
	local folder = Workspace:FindFirstChild("QuinServer")
	if not folder then return nil end
	local aim = input.move.Magnitude > 0.1 and input.move or flat(rootPart.CFrame.LookVector)
	aim = aim.Magnitude > 0.01 and aim.Unit or Vector3.new(0, 0, -1)
	local team = fighter:GetAttribute("Team")
	local reach = cfg("StrikeLockRange", 12)
	local best, bestScore = nil, math.huge
	for _, enemy in ipairs(folder:GetChildren()) do
		local hum = enemy:FindFirstChildOfClass("Humanoid")
		local root = enemy:FindFirstChild("HumanoidRootPart")
		if enemy ~= fighter and hum and root and hum.Health > 0 and (team == nil or enemy:GetAttribute("Team") ~= team) then
			local offset = flat(root.Position - rootPart.Position)
			local distance = offset.Magnitude
			if distance <= reach and math.abs(root.Position.Y - rootPart.Position.Y) < 6 then
				local dot = distance > 0.01 and offset.Unit:Dot(aim) or 1
				local score = distance * (1.6 - dot) -- (one ahead counts as closer than one behind)
				if score < bestScore then
					best, bestScore = enemy, score
				end
			end
		end
	end
	return best
end

local function setGuard(fighter, humanoid, data, held)
	if held then
		fighter:SetAttribute("IsGuarding", true)
		local track = AnimationModule.playConfig(humanoid, "Reactions.Block", 1.0, Enum.AnimationPriority.Action4, false)
		data.guardTrack = track
		-- the block clip is a raise: held on its guard frame while the button is held
		task.delay(cfg("GuardHoldAfter", 0.15), function()
			if data.guardTrack == track and track and track.IsPlaying then
				track:AdjustSpeed(0)
			end
		end)
	else
		fighter:SetAttribute("IsGuarding", false)
		if data.guardTrack then
			data.guardTrack:Stop(0.15)
			data.guardTrack = nil
		end
	end
end

local function strike(fighter, humanoid, rootPart, data, input)
	local target = strikeTarget(fighter, rootPart, input)
	-- (locked, the strike goes at the locked enemy when it is within reach)
	local lockRoot = data.lock and data.lock:FindFirstChild("HumanoidRootPart")
	if lockRoot and flat(lockRoot.Position - rootPart.Position).Magnitude <= cfg("StrikeLockRange", 12) then
		target = data.lock
	end
	local targetRoot = target and target:FindFirstChild("HumanoidRootPart")
	if targetRoot then
		fightState().faceTarget(rootPart, targetRoot, data)
	end
	-- (the same energy cost per strike as an AI strike)
	fighter:SetAttribute("Energy", math.max(0, (fighter:GetAttribute("Energy") or 100) - (CombatConfig.EnergyDrain_Attack or 2)))
	fighter:SetAttribute("LastActivityTime", os.clock())
	fighter:SetAttribute("CurrentIdleStance", "Ready")
	fightState().throwStrike(fighter, humanoid, rootPart, target, "Light", data)
end

-- Start a projectile jump at what the player aims at. Returns the state to go to, or nil.
function projectileJump(fighter, humanoid, rootPart, pj)
	if CombatConfig.EnableProjectileJump == false then return nil end
	local energy = fighter:GetAttribute("Energy") or 0
	if energy < (CombatConfig.ProjectileJumpMinEnergy or 35) then
		fighter:SetAttribute("PilotNote", "Not enough mana for a projectile jump")
		return nil
	end
	local maxRange = cfg("ProjectileJumpRange", CombatConfig.ProjectileJumpMaxDistance or 90)
	local ProjectileJumpState = require(script.Parent:WaitForChild("ProjectileJumpState"))
	local team = fighter:GetAttribute("Team")
	local targetRoot = pj.target and pj.target:FindFirstChild("HumanoidRootPart")
	local targetHum = pj.target and pj.target:FindFirstChildOfClass("Humanoid")
	if targetRoot and targetHum and targetHum.Health > 0 and pj.target ~= fighter
		and (team == nil or pj.target:GetAttribute("Team") ~= team)
		and flat(targetRoot.Position - rootPart.Position).Magnitude <= maxRange then
		-- at a Quin
		local value = fighter:FindFirstChild("ProjectileTarget")
		if not value then
			value = Instance.new("ObjectValue")
			value.Name = "ProjectileTarget"
			value.Parent = fighter
		end
		value.Value = pj.target
		fighter:SetAttribute("JumpStyle", pj.style)
	else
		-- at a spot: the crosshair's point, read as where the player wants to be. No nearer than
		-- ProjectileJumpMinRange (aimed at its own feet it launched and came down on the spot), no
		-- further than the jump's reach, on something to stand on, in the arena. The ground is looked
		-- for from above the aim: aimed high (a platform top, a far wall, the sky: the aim's point
		-- was up in the air and the old 120-stud look down from it found nothing) it finds the top
		-- or the floor under it.
		local origin = rootPart.Position
		local offset = flat(pj.point - origin)
		local dir = offset.Magnitude > 1 and offset.Unit or flat(rootPart.CFrame.LookVector).Unit
		local reach = math.clamp(offset.Magnitude, cfg("ProjectileJumpMinRange", 25), maxRange)
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { Workspace:FindFirstChild("QuinServer") }
		params.RespectCanCollide = true
		local function groundAt(distance)
			local spot = Vector3.new(origin.X, 0, origin.Z) + dir * distance
			local top = math.max(pj.point.Y, origin.Y) + 60
			return Workspace:Raycast(Vector3.new(spot.X, top, spot.Z), Vector3.new(0, -(top - origin.Y) - 200, 0), params)
		end
		local ground = groundAt(reach)
		-- (aimed at a wall's face, the look from above finds the wall's top: land in front of it)
		if ground and ground.Position.Y > pj.point.Y + 6 then
			ground = groundAt(math.max(reach - 5, 0))
		end
		if not ground or SpatialModule.isOutOfBounds({ Position = ground.Position }, 4) then
			fighter:SetAttribute("PilotNote", "Nowhere to land there")
			return nil
		end
		ProjectileJumpState.aimAtPoint(fighter, ground.Position, pj.style)
		fighter:SetAttribute("JumpStyle", pj.style)
	end
	fighter:SetAttribute("PilotNote", nil)
	return ProjectileJumpState
end

-- The next enemy after `current` by distance within `range` (any height), wrapping round
function nextEnemy(fighter, rootPart, range, current)
	local folder = Workspace:FindFirstChild("QuinServer")
	if not folder then return nil end
	local team = fighter:GetAttribute("Team")
	local list = {}
	for _, enemy in ipairs(folder:GetChildren()) do
		local hum = enemy:FindFirstChildOfClass("Humanoid")
		local root = enemy:FindFirstChild("HumanoidRootPart")
		if enemy ~= fighter and hum and root and hum.Health > 0 and (team == nil or enemy:GetAttribute("Team") ~= team) then
			local d = (root.Position - rootPart.Position).Magnitude
			if d <= range then table.insert(list, { enemy, d }) end
		end
	end
	if #list == 0 then return nil end
	table.sort(list, function(a, b) return a[2] < b[2] end)
	for i, entry in ipairs(list) do
		if entry[1] == current then
			return list[i % #list + 1][1]
		end
	end
	return list[1][1]
end

function PilotedState.enter(fighter, humanoid, rootPart)
	pilotData[fighter] = {
		lastAttackTime = 0,
		actionEndTime = 0,
		attackFinishTime = 0,
		lastClock = os.clock(),
	}
	-- (facing is the steer's, as for an AI Quin: with AutoRotate off and no facing of its own the
	-- steer reads the body as strafing and keeps its facing, so it walked backwards and sideways)
	humanoid.AutoRotate = true
	fighter:SetAttribute("IsStrafing", nil)
	fighter:SetAttribute("CurrentIdleStance", "Ready")
	if cfg("ClientMovement", true) and PilotInput.giveBody(fighter) then
		-- the player's machine plays the legs from here (gait, idle, jump, fall): the server's
		-- own are let go so the two do not stack
		GaitModule.stop(humanoid, 0.15)
		local animator = humanoid:FindFirstChildOfClass("Animator")
		for _, track in ipairs(animator and animator:GetPlayingAnimationTracks() or {}) do
			if track.Priority == Enum.AnimationPriority.Idle or track.Priority == Enum.AnimationPriority.Movement then
				track:Stop(0.2)
			end
		end
	else
		AnimationModule.ensureBaseIdle(humanoid)
	end
	RuntimeTracer.checkpoint(fighter, "Enter Piloted (player input)")
end

function PilotedState.exit(fighter, humanoid, rootPart)
	local data = pilotData[fighter]
	if data then setGuard(fighter, humanoid, data, false) end
	fighter:SetAttribute("IsStrafing", nil)
	fighter:SetAttribute("PilotFocus", nil)
	fighter:SetAttribute("PilotLocked", nil)
	local gyro = rootPart and rootPart:FindFirstChild("FightGyro")
	if gyro then gyro:Destroy() end
	PilotInput.reclaimBody(fighter) -- (the states after this one are the server's to move)
	pilotData[fighter] = nil
end

function PilotedState.update(fighter, humanoid, rootPart)
	local data = pilotData[fighter]
	if not data then
		PilotedState.enter(fighter, humanoid, rootPart)
		data = pilotData[fighter]
	end
	local clock = os.clock()
	local dt = math.clamp(clock - data.lastClock, 1 / 120, 0.1)
	data.lastClock = clock
	local now = tick()

	local input = PilotInput.get(fighter)
	-- (a client that stopped sending is not left running in a straight line)
	local move = (clock - input.at) < cfg("InputTimeout", 1.0) and input.move or Vector3.zero
	local striking = fighter:GetAttribute("Attacking") == true and now < (data.attackFinishTime or 0)
	local busy = now < (data.actionEndTime or 0)
	-- The player's machine moving the body? (Taken back by a hit that did not end this state, it
	-- is handed back after a moment.)
	local clientMoves = fighter:GetAttribute("PilotClientMoves") == true
	if not clientMoves and cfg("ClientMovement", true)
		and clock - (fighter:GetAttribute("PilotReclaimedAt") or 0) > cfg("ReclaimHold", 0.6) then
		clientMoves = PilotInput.giveBody(fighter)
	end

	-- Guard: held while the button is held, never in the middle of its own strike
	local guarding = fighter:GetAttribute("IsGuarding") == true
	if input.guard and not guarding and not striking then
		setGuard(fighter, humanoid, data, true)
		guarding = true
	elseif not input.guard and guarding then
		setGuard(fighter, humanoid, data, false)
		guarding = false
	end

	-- Actions. A strike asked for while the last one is still going is kept for a moment and
	-- thrown as soon as the Quin is free (at Recover): a chain of clicks becomes the combo.
	for _, action in ipairs(PilotInput.takeActions(fighter)) do
		if action == "Strike" then
			data.strikeAskedAt = clock
		elseif not striking and not guarding and not clientMoves then
			local dir = move.Magnitude > 0.1 and move.Unit or flat(rootPart.CFrame.LookVector).Unit
			if action == "Dash" then
				LocomotionModule.dash(fighter, humanoid, rootPart, rootPart.Position + dir * cfg("DashDistance", 35), cfg("DashDistance", 35))
			elseif action == "Slide" then
				LocomotionModule.slide(fighter, humanoid, rootPart, dir)
			elseif action == "Jump" then
				data.jumpAskedAt, data.jumpLetGo = clock, false -- (taken below)
			end
		end
		if action == "JumpRelease" and clientMoves then
			-- (the player's machine cuts its own jump)
		elseif action == "JumpRelease" then
			if data.jumpAskedAt then data.jumpLetGo = true end -- (not off the ground yet: cut once it is)
			LocomotionModule.cutJump(fighter, humanoid, rootPart)
		elseif action == "Lock" then
			if data.lock then
				data.lock = nil
			else
				data.lock = nearestEnemy(fighter, rootPart, cfg("LockRange", 120))
			end
		elseif action == "LockNext" then
			data.lock = nextEnemy(fighter, rootPart, cfg("LockRange", 120), data.lock)
		end
	end

	-- Jump. Kept for a moment (JumpBuffer) until it can be taken: pressed just before a landing, or
	-- while the feet were settling from the last one, it went nowhere
	if data.jumpAskedAt then
		if clock - data.jumpAskedAt > cfg("JumpBuffer", 0.15) or striking or guarding then
			data.jumpAskedAt = nil
		else
			local hSpeed = flat(rootPart.AssemblyLinearVelocity).Magnitude
			if LocomotionModule.jump(fighter, humanoid, rootPart, cfg("JumpHeight", 11), hSpeed > 2 and hSpeed or 0, "free") then
				data.jumpAskedAt = nil
				if data.jumpLetGo then
					task.delay(0.05, function()
						LocomotionModule.cutJump(fighter, humanoid, rootPart)
					end)
				end
			end
		end
	end

	-- Projectile jump (from the ground)
	local pj = PilotInput.takeProjectileJump(fighter)
	if pj and not striking and not guarding and LocomotionModule.isOnGround(rootPart, humanoid) then
		local next = projectileJump(fighter, humanoid, rootPart, pj)
		if next then return next end
	elseif pj then
		fighter:SetAttribute("PilotNote", (striking or guarding) and "Busy: no projectile jump mid-strike or guard"
			or "Projectile jumps start from the ground")
	end
	if data.strikeAskedAt and not guarding then
		if clock - data.strikeAskedAt > cfg("StrikeBuffer", 0.35) then
			data.strikeAskedAt = nil
		elseif not busy and not LocomotionModule.isSliding(fighter) then
			data.strikeAskedAt = nil
			strike(fighter, humanoid, rootPart, data, { move = move })
			striking = true
		end
	end

	-- Engaged or free (design doc 5.8): facing the nearest enemy close by, unless running
	-- (squared up, it stays engaged a little further out than it engages: no flicker at the edge)
	local range = cfg("EngageRange", 16) + (fighter:GetAttribute("IsStrafing") and cfg("EngageRelease", 4) or 0)
	-- (a lock holds while its enemy lives and is within LockRange)
	if data.lock then
		local hum = data.lock:FindFirstChildOfClass("Humanoid")
		local root = data.lock:FindFirstChild("HumanoidRootPart")
		if not (data.lock.Parent and hum and hum.Health > 0 and root and (root.Position - rootPart.Position).Magnitude <= cfg("LockRange", 120)) then
			data.lock = nil
		end
	end
	if (data.lock ~= nil) ~= (fighter:GetAttribute("PilotLocked") == true) then
		fighter:SetAttribute("PilotLocked", data.lock ~= nil or nil)
	end
	local focus = (input.pace ~= "run") and (data.lock or nearestEnemy(fighter, rootPart, range)) or nil
	local focusRoot = focus and focus:FindFirstChild("HumanoidRootPart")
	if (focus and focus.Name or nil) ~= fighter:GetAttribute("PilotFocus") then
		fighter:SetAttribute("PilotFocus", focus and focus.Name or nil)
	end
	local engaged = focusRoot ~= nil and humanoid.FloorMaterial ~= Enum.Material.Air

	-- Movement
	if clientMoves then
		-- The player's machine moves the body. Squared up to an enemy, the facing is still this
		-- state's (the fight gyro, a constraint the owner's physics carries out); running free,
		-- the gyro goes and the steer there faces the run.
		if engaged then
			fightState().faceTarget(rootPart, focusRoot, data)
			fighter:SetAttribute("IsStrafing", true)
			if humanoid.AutoRotate then humanoid.AutoRotate = false end
		else
			if fighter:GetAttribute("IsStrafing") then fighter:SetAttribute("IsStrafing", nil) end
			if not striking then
				local gyro = rootPart:FindFirstChild("FightGyro")
				if gyro then gyro:Destroy() end
			end
		end
		fighter:SetAttribute("IsMoving", move.Magnitude > 0.1)
		if move.Magnitude > 0.1 then fighter:SetAttribute("LastActivityTime", clock) end
		return PilotedState
	end
	if engaged and not LocomotionModule.isSliding(fighter) then
		-- squared up to it, whether moving or not
		fightState().faceTarget(rootPart, focusRoot, data)
		fighter:SetAttribute("IsStrafing", true)
		if humanoid.AutoRotate then humanoid.AutoRotate = false end -- (its facing is the fight gyro's)
	elseif fighter:GetAttribute("IsStrafing") then
		fighter:SetAttribute("IsStrafing", nil)
	end
	if LocomotionModule.isSliding(fighter) then
		-- (a committed slide owns the body until it hands back to the gait)
	elseif striking or guarding then
		LocomotionModule.brake(fighter, humanoid, rootPart, dt)
	elseif move.Magnitude > 0.1 then
		if not engaged then
			-- free: the body turns with its run, not with the strike's facing gyro
			local gyro = rootPart:FindFirstChild("FightGyro")
			if gyro then gyro:Destroy() end
			-- (the steer owns the facing while it moves the body: it turns AutoRotate off for its
			-- own facing and back on when it lets go. Turning it on here every tick made the two fight)
		end
		local speed
		if input.pace == "run" then
			speed = fighter:GetAttribute("Speed") or CombatConfig.Player_RunSpeed or 40
		elseif input.pace == "walk" then
			speed = CombatConfig.Player_WalkSpeed or 7.5
		else
			speed = CombatConfig.Player_JogSpeed or 12
		end
		fighter:SetAttribute("IsMoving", true)
		fighter:SetAttribute("LastActivityTime", clock)
		LocomotionModule.steer(fighter, humanoid, rootPart, rootPart.Position + move.Unit * 15, speed, dt)
		GaitModule.update(humanoid, rootPart, dt)
	else
		fighter:SetAttribute("IsMoving", false)
		LocomotionModule.brake(fighter, humanoid, rootPart, dt)
		if now >= (data.attackFinishTime or 0) and not guarding then
			AnimationModule.ensureBaseIdle(humanoid)
		end
	end

	return PilotedState
end

return PilotedState
