--// ChaseState/Climb.lua
-- A chase after a target up high: met in the air (AirInterceptModule), climbed to by stepping
-- stones, or jumped on to from the rim of its top (the run-up and jump), with patience.
-- Returns the next state, or nil when there is nothing to climb (the chase goes on).
-- (Cut out of ChaseState.update as it was: QuinCore audit 2026-10-27, step 7.)

local GameClock = require(game:GetService("ReplicatedStorage"):WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("GameClock")) -- (the game's clock: a freeze stops it)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TargetingModule = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("TargetingModule"))
local CombatConfig = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("CombatConfig"))
local PlatformCatalogue = require(game:GetService("ReplicatedStorage"):WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("PlatformCatalogue"))
local TraversalModule = require(game:GetService("ReplicatedStorage"):WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("TraversalModule"))
local AirInterceptModule = require(game:GetService("ReplicatedStorage"):WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("AirInterceptModule"))
local LocomotionModule = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("LocomotionModule"))
local GaitModule = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("GaitModule"))
local RuntimeTracer = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("RuntimeTracer"))
local NavigationModule = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("NavigationModule"))
local States = require(game:GetService("ReplicatedStorage"):WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("States")) -- (every state by name)

local Facing = require(game:GetService("ReplicatedStorage"):WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("Facing")) -- (turning on the spot)

local Climb = {}

-- Backing off for a run-up, committed (both climbs use it: the jump onto a perched target's top
-- below, and ChaseState/Obstacles' high-ground climb). Out to a spot fixed when it starts, then
-- it turns to face the rim on that spot, then the run-up is the caller's again. Re-decided every
-- tick, it backed off facing away, turned round running at the rim, was too close again and
-- backed off: it spun in place (owner, 2026-10-29), with "Going round" and the other branches
-- taking turns in between. Returns true while it is still backing off or turning.
-- (RunUp_Committed = false: the old tick-by-tick back-off)
function Climb.runUpBackOff(fighter, humanoid, rootPart, data, edge)
	if CombatConfig.RunUp_Committed == false then
		if not edge then return false end
		local toEdge = Vector3.new(edge.X - rootPart.Position.X, 0, edge.Z - rootPart.Position.Z)
		if toEdge.Magnitude < 0.1 then return false end
		fighter:SetAttribute("ObstacleAwareness", "Backing off for a run-up")
		LocomotionModule.steer(fighter, humanoid, rootPart, rootPart.Position - toEdge.Unit * 14, 24.0, 0.05)
		GaitModule.update(humanoid, rootPart, 0.1)
		return true
	end
	local now = GameClock.tick()
	local r = data.runUpBack
	if r and (now > r.giveUp or not fighter.Parent) then
		data.runUpBack = nil
		Facing.drop(rootPart, "Idle")
		r = nil
	end
	if not r then
		if not edge then return false end
		local toEdge = Vector3.new(edge.X - rootPart.Position.X, 0, edge.Z - rootPart.Position.Z)
		if toEdge.Magnitude < 0.1 then return false end
		r = {
			spot = rootPart.Position - toEdge.Unit * (CombatConfig.RunUp_BackOffStuds or 14),
			edge = edge,
			giveUp = now + (CombatConfig.RunUp_BackOffMaxTime or 4),
		}
		data.runUpBack = r
		fighter:SetAttribute("RunUpBackOffs", (fighter:GetAttribute("RunUpBackOffs") or 0) + 1) -- (probes)
	end
	local toSpot = Vector3.new(r.spot.X - rootPart.Position.X, 0, r.spot.Z - rootPart.Position.Z)
	local toEdge = Vector3.new(r.edge.X - rootPart.Position.X, 0, r.edge.Z - rootPart.Position.Z)
	if not r.turning and toSpot.Magnitude > 2 then
		fighter:SetAttribute("ObstacleAwareness", "Backing off for a run-up")
		LocomotionModule.steer(fighter, humanoid, rootPart, r.spot, math.clamp(toSpot.Magnitude * 2, 10, 22), 0.05)
	else
		r.turning = true
		if toEdge.Magnitude > 0.1 and rootPart.CFrame.LookVector:Dot(toEdge.Unit) < 0.9 then
			fighter:SetAttribute("ObstacleAwareness", "Turning to the run-up")
			LocomotionModule.brake(fighter, humanoid, rootPart, 0.05)
			local gyro = Facing.hold(rootPart, "Idle")
			if gyro then
				gyro.CFrame = CFrame.lookAt(Vector3.zero, toEdge.Unit)
			end
		else
			-- facing the rim from far enough out: the caller's run-up and jump from here
			data.runUpBack = nil
			Facing.drop(rootPart, "Idle")
			return false
		end
	end
	GaitModule.update(humanoid, rootPart, 0.1)
	return true
end

function Climb.update(fighter, humanoid, rootPart, data, target, targetHRP, inShowdown)
	-- A back-off for a run-up already under way is seen through first
	if data.runUpBack and Climb.runUpBackOff(fighter, humanoid, rootPart, data, nil) then
		return States.Chase
	end
	-- Vertical gap awareness: target is perched on high ground
	local verticalGap = targetHRP.Position.Y - rootPart.Position.Y
	local lastPJ = fighter:GetAttribute("LastPositioningJumpTime") or 0 -- GameClock.tick() timestamp
	local flatDistToTgt = Vector3.new(targetHRP.Position.X - rootPart.Position.X, 0, targetHRP.Position.Z - rootPart.Position.Z).Magnitude

	-- An enemy it has seen high in the air may be met up there
	if not inShowdown and not humanoid.Jump and humanoid:GetState() ~= Enum.HumanoidStateType.Freefall then
		local jumper = AirInterceptModule.consider(fighter, rootPart)
		if jumper then
			AirInterceptModule.commit(fighter, jumper)
			RuntimeTracer.checkpoint(fighter, "Chase: going up after a jumper")
			fighter:SetAttribute("JumpWhy", "after a jumper in the sky") -- (JumpLog, team step 5)
			return States.ProjectileJump
		end
	end

	-- Perched means standing on something up there. A target that is merely in the air (jumping,
	-- knocked up) comes back down by itself; treating it as high ground sent a projectile jump
	-- after every jumper.
	local targetHumanoid = target:FindFirstChildOfClass("Humanoid")
	local targetPerched = targetHumanoid ~= nil and targetHumanoid.FloorMaterial ~= Enum.Material.Air
		and not targetHumanoid.PlatformStand

	-- Climb to a target above through stepping stones (NavigationModule.nextStone): a precise
	-- hop onto the next surface that brings it closer, then the next from there. Running jumps
	-- onto small tops carried their speed straight off the far side, so these are spot jumps.
	-- (a smaller climb too when it cannot simply walk up: the last 7 studs from one high stone to
	-- the target's ran it straight off the stone)
	-- A top within a jump's reach is jumped on to (the run-up and jump further down); the
	-- stones are for what is higher, or when that jump has not come off for
	-- HighGround_ClimbPatience seconds. (The stones came first for any climb of 8 studs or more,
	-- so the jump was never taken for those: 67 spot hops to 4 jumps up in a 96 s match.)
	local jumpable = targetPerched and verticalGap >= (CombatConfig.HighGround_InterceptJumpMinReach or 8.0)
		and verticalGap <= (CombatConfig.Jump_MaxReach or 25.0)
	data.jumpClimbSince = jumpable and (data.jumpClimbSince or GameClock.tick()) or nil
	local jumpFirst = jumpable and GameClock.tick() - data.jumpClimbSince < (CombatConfig.HighGround_ClimbPatience or 5)
	local stoneClimb = not jumpFirst and (verticalGap >= (CombatConfig.Nav_StoneMinClimb or 8)
		or (verticalGap >= 2 and not (NavigationModule.isReachable(rootPart, targetHRP) and NavigationModule.canStrikeAt(rootPart, targetHRP))))
	if not inShowdown and stoneClimb and LocomotionModule.isOnGround(rootPart, humanoid) and not LocomotionModule.isSliding(fighter) then
		local stone = NavigationModule.nextStone(fighter, rootPart, targetHRP, 2)
		if stone then
			fighter:SetAttribute("ObstacleAwareness", string.format("Stepping stone: %.0f up, %.0f across", stone.rise, stone.hop))
			-- (owner 2026-10-27: tone the stone hops down - one every StoneHopCooldown, not 0.6 s)
			if GameClock.tick() - (fighter:GetAttribute("LastStoneHopTime") or 0) >= (CombatConfig.Nav_StoneHopCooldown or 2.5) then
				fighter:SetAttribute("LastStoneHopTime", GameClock.tick())
				-- A stone it is facing, within a jump's reach and range, and wide enough to land
				-- a running jump on, is simply jumped on to; the spot hop (a projectile arc) is
				-- for the rest: too high, too far, a small top, or not lined up.
				local toStone = Vector3.new(stone.point.X - rootPart.Position.X, 0, stone.point.Z - rootPart.Position.Z)
				local wideTop = math.min(stone.part.Size.X, stone.part.Size.Z) >= (CombatConfig.Nav_StoneJumpMinWidth or 10)
				local lined = toStone.Magnitude > 0.1 and rootPart.CFrame.LookVector:Dot(toStone.Unit) > 0.85
				local jumpTo = wideTop and lined
					and TraversalModule.solveJumpOnto(stone.rise, math.max(stone.hop - 3, 1), CombatConfig.Jump_MaxReach or 25.0, 3)
				fighter:SetAttribute("JumpWhy", "jump to a stepping stone (it is up high)") -- (JumpLog, team step 5)
				if jumpTo and LocomotionModule.jump(fighter, humanoid, rootPart, jumpTo.height, jumpTo.speed, "jump") then
					fighter:SetAttribute("ObstacleAwareness", string.format("Jump to a stone: %.0f up, %.0f across", stone.rise, stone.hop))
					fighter:SetAttribute("StoneJumps", (fighter:GetAttribute("StoneJumps") or 0) + 1) -- (probes)
					NavigationModule.noteStoneTry(fighter, stone.part)
					require(game:GetService("ReplicatedStorage"):WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("AirDash")).noteJump(fighter, stone.point)
					return States.Chase
				end
				-- a wide stone it is only not lined up with: it turns to it and jumps, no spot hop
				if wideTop and not lined and toStone.Magnitude > 0.1 then
					fighter:SetAttribute("LastStoneHopTime", 0)
					LocomotionModule.steer(fighter, humanoid, rootPart, stone.point, 16.0, 0.1)
					return States.Chase
				end
				fighter:SetAttribute("LastProjectileJumpTime", GameClock.tick())
				fighter:SetAttribute("JumpWhy", "spot hop to a stepping stone (it is up high)") -- (JumpLog, team step 5)
				local ProjectileJumpState = States.ProjectileJump
				ProjectileJumpState.aimAtPoint(fighter, stone.point)
				NavigationModule.noteStoneTry(fighter, stone.part)
				fighter:SetAttribute("StoneHops", (fighter:GetAttribute("StoneHops") or 0) + 1) -- (probes)
				return ProjectileJumpState
			end
			-- Between hops it works its way to the stone and lines up with it, instead of standing
			-- still until the next hop is due (a Quin stood at speed 0 in Chase, "Stepping stone:
			-- 40 up, 38 across", for the whole cooldown). Close enough, it waits facing it.
			local toStone = Vector3.new(stone.point.X - rootPart.Position.X, 0, stone.point.Z - rootPart.Position.Z)
			if toStone.Magnitude > (CombatConfig.Nav_StoneWaitGap or 8) then
				LocomotionModule.steer(fighter, humanoid, rootPart, stone.point, math.clamp(toStone.Magnitude, 10, 20), 0.1)
			else
				LocomotionModule.brake(fighter, humanoid, rootPart, 0.1)
			end
			GaitModule.update(humanoid, rootPart, 0.1)
			return States.Chase
		end
	end

	if not inShowdown and targetPerched and verticalGap >= (CombatConfig.HighGround_InterceptJumpMinReach or 8.0) then
		local energy = fighter:GetAttribute("Energy") or 100
		local climbEnergyCost = CombatConfig.HighGround_InterceptJumpEnergyCost or 20

		local canLeave = not humanoid.Jump and humanoid:GetState() ~= Enum.HumanoidStateType.Freefall
		if verticalGap <= (CombatConfig.Jump_MaxReach or 25.0) then
			-- Within a jump's reach. The jump is solved for the platform's edge: it needs a
			-- run-up (too close and the feet hit the lip, too far and they fall short), so the
			-- Quin backs off or closes in until the jump works, then takes it.
			local platform = PlatformCatalogue.under(targetHRP.Position)
			local edge = platform and PlatformCatalogue.nearestTopPoint(platform, rootPart.Position, 0) or targetHRP.Position
			local toEdge = Vector3.new(edge.X - rootPart.Position.X, 0, edge.Z - rootPart.Position.Z)
			local depth = platform and PlatformCatalogue.landingDepth(platform, edge, rootPart.Position) or nil
			local solution, problem = TraversalModule.solveJumpOnto(verticalGap, toEdge.Magnitude, CombatConfig.Jump_MaxReach or 25.0, depth)
			if problem == "TooClose" and toEdge.Magnitude > 0.1 and Climb.runUpBackOff(fighter, humanoid, rootPart, data, edge) then
				return States.Chase
			end
			local facingEdge = toEdge.Magnitude > 0.1 and rootPart.CFrame.LookVector:Dot(toEdge.Unit) > 0.85
			if solution and facingEdge and energy >= climbEnergyCost and (GameClock.tick() - lastPJ) >= 2.0 and canLeave then
				fighter:SetAttribute("ObstacleAwareness", "High-Ground Intercept Jump")
				fighter:SetAttribute("JumpWhy", "jump up to it on high ground") -- (JumpLog, team step 5)
				if LocomotionModule.jump(fighter, humanoid, rootPart, solution.height, solution.speed, "jump") then
					-- (where it means to land, so a jump coming down short can dash on to it)
					require(game:GetService("ReplicatedStorage"):WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("AirDash")).noteJump(fighter, edge + toEdge.Unit * (depth or 4))
					fighter:SetAttribute("LastPositioningJumpTime", GameClock.tick())
					fighter:SetAttribute("Energy", energy - climbEnergyCost)
					return States.Chase
				end
			end
			-- A jump that works from here but is not lined up yet (it has just backed off, or
			-- the last jump was a moment ago): it runs at the edge, and goes when it is. (It
			-- fell through to the vantage rule below, which walked it away from the platform:
			-- 21 run-ups and no jump in a 97 s match.)
			if solution and jumpFirst and energy >= climbEnergyCost and canLeave then
				fighter:SetAttribute("ObstacleAwareness", "Run-up for a jump")
				LocomotionModule.steer(fighter, humanoid, rootPart, edge, math.max(solution.speed, 24.0), 0.05)
				GaitModule.update(humanoid, rootPart, 0.1)
				return States.Chase
			end
		elseif canLeave then
			-- Higher than any jump: the projectile jump is the way up to a target on a platform
			local lastProjectileJump = fighter:GetAttribute("LastProjectileJumpTime") or 0
			local cooldown = (CombatConfig.ProjectileJump_Cooldown or 14.0) / (workspace:GetAttribute("GameSpeedMultiplier") or 1.0)
			if CombatConfig.EnableProjectileJump ~= false and fighter:GetAttribute("EnableProjectileJump") ~= false
				and energy >= (CombatConfig.ProjectileJumpMinEnergy or 40)
				and (GameClock.tick() - lastProjectileJump) >= cooldown
				and flatDistToTgt <= (CombatConfig.ProjectileJumpMaxDistance or 800) then
				fighter:SetAttribute("LastProjectileJumpTime", GameClock.tick())
				fighter:SetAttribute("ObstacleAwareness", "Projectile jump to target on high ground")
				local stylePool = { 1, 1, 2, 3, 4, 5, 5, 6, 7 }
				fighter:SetAttribute("JumpStyle", stylePool[math.random(1, #stylePool)])
				TargetingModule.setTarget(fighter, target, "State")
				fighter:SetAttribute("JumpWhy", "rocket to it on high ground") -- (JumpLog, team step 5)
				return States.ProjectileJump
			end
		end

		-- If standing directly underneath the platform (< 16 studs flat), back up to maintain vantage LoS
		-- Back away from the platform to a spot straight out from the target (fixed while it moves
		-- out along that line). It used to be set from the body's own facing every tick (22 behind,
		-- 8 right), so turning towards it moved it: Quins under a perched target ran in circles
		-- on the spot. Out there it watches, creeping in, until a way up opens.
		local vantage = CombatConfig.HighGround_VantageDistance or 24
		local outOfJumpReach = verticalGap > (CombatConfig.Jump_MaxReach or 25.0)
		-- (not while it is working at the jump up: the jump's run-up starts closer than this)
		if (flatDistToTgt < 16.0 and not jumpFirst) or (outOfJumpReach and flatDistToTgt < vantage) then
			local away = Vector3.new(rootPart.Position.X - targetHRP.Position.X, 0, rootPart.Position.Z - targetHRP.Position.Z)
			if away.Magnitude < 1 then
				local saved = fighter:GetAttribute("VantageDir")
				if typeof(saved) ~= "Vector3" then
					local a = math.random() * math.pi * 2
					saved = Vector3.new(math.cos(a), 0, math.sin(a))
					fighter:SetAttribute("VantageDir", saved)
				end
				away = saved
			end
			fighter:SetAttribute("ObstacleAwareness", "Positioning for High-Ground Vantage")
			if flatDistToTgt < 16.0 then
				local vantageTarget = Vector3.new(targetHRP.Position.X, rootPart.Position.Y, targetHRP.Position.Z) + away.Unit * vantage
				LocomotionModule.steer(fighter, humanoid, rootPart, vantageTarget, 20.0, 0.05)
			else
				-- (a slow creep towards it keeps the body turned to the target)
				LocomotionModule.steer(fighter, humanoid, rootPart, Vector3.new(targetHRP.Position.X, rootPart.Position.Y, targetHRP.Position.Z), 2.0, 0.05)
			end
			return States.Chase
		end
	end
	return nil
end

return Climb
