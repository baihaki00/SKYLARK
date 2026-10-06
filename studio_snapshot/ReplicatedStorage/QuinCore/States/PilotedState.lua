--// PilotedState.lua
-- A player's Quin (Player Quin match mode): this state stands where the AI's own decisions would
-- (Idle / Chase / Retreat / Fight ...). It reads the player's input (Modules/PilotInput) and does
-- what those states do with the same calls:
--   moving      LocomotionModule.steer + GaitModule (the AI's acceleration, turning, gait)
--               free: the body faces where it goes; engaged (an enemy within EngageRange and the
--               player not running): it faces that enemy and moves with footwork (back = steps
--               back, sideways = circles; the gait picks strafe or backwards from the motion)
--   standing    LocomotionModule.brake
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

-- The nearest living enemy within `range` on about the same level, or nil
local function nearestEnemy(fighter, rootPart, range)
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
		-- at a spot: no further than the jump's reach, on something to stand on, in the arena
		local offset = flat(pj.point - rootPart.Position)
		local spot = pj.point
		if offset.Magnitude > maxRange then
			spot = Vector3.new(rootPart.Position.X, pj.point.Y, rootPart.Position.Z) + offset.Unit * maxRange
		end
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { Workspace:FindFirstChild("QuinServer") }
		params.RespectCanCollide = true
		local ground = Workspace:Raycast(spot + Vector3.new(0, 40, 0), Vector3.new(0, -120, 0), params)
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
	AnimationModule.ensureBaseIdle(humanoid)
	RuntimeTracer.checkpoint(fighter, "Enter Piloted (player input)")
end

function PilotedState.exit(fighter, humanoid, rootPart)
	local data = pilotData[fighter]
	if data then setGuard(fighter, humanoid, data, false) end
	fighter:SetAttribute("IsStrafing", nil)
	fighter:SetAttribute("PilotFocus", nil)
	local gyro = rootPart and rootPart:FindFirstChild("FightGyro")
	if gyro then gyro:Destroy() end
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
		elseif not striking and not guarding then
			local dir = move.Magnitude > 0.1 and move.Unit or flat(rootPart.CFrame.LookVector).Unit
			if action == "Dash" then
				LocomotionModule.dash(fighter, humanoid, rootPart, rootPart.Position + dir * cfg("DashDistance", 35), cfg("DashDistance", 35))
			elseif action == "Slide" then
				LocomotionModule.slide(fighter, humanoid, rootPart, dir)
			elseif action == "Jump" then
				local v = rootPart.AssemblyLinearVelocity
				local hSpeed = flat(v).Magnitude
				LocomotionModule.jump(fighter, humanoid, rootPart, cfg("JumpHeight", 11), hSpeed > 2 and hSpeed or 0, "free")
			end
		end
		if action == "JumpRelease" then
			LocomotionModule.cutJump(fighter, humanoid, rootPart)
		end
	end

	-- Projectile jump (from the ground)
	local pj = PilotInput.takeProjectileJump(fighter)
	if pj and not striking and not guarding and LocomotionModule.isOnGround(rootPart, humanoid) then
		local next = projectileJump(fighter, humanoid, rootPart, pj)
		if next then return next end
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
	local focus = (input.pace ~= "run") and nearestEnemy(fighter, rootPart, cfg("EngageRange", 16)) or nil
	local focusRoot = focus and focus:FindFirstChild("HumanoidRootPart")
	if (focus and focus.Name or nil) ~= fighter:GetAttribute("PilotFocus") then
		fighter:SetAttribute("PilotFocus", focus and focus.Name or nil)
	end
	local engaged = focusRoot ~= nil and humanoid.FloorMaterial ~= Enum.Material.Air

	-- Movement
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
			if not humanoid.AutoRotate then humanoid.AutoRotate = true end -- (a state before may have left it off)
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
