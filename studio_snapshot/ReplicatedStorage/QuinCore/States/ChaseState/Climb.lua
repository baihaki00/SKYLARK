--// ChaseState/Climb.lua
-- A chase after a target up high: met in the air (AirInterceptModule), climbed to by stepping
-- stones, or jumped on to from the rim of its top (the run-up and jump), with patience.
-- Returns the next state, or nil when there is nothing to climb (the chase goes on).
-- (Cut out of ChaseState.update as it was: QuinCore audit 2026-10-27, step 7.)

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

local Climb = {}

function Climb.update(fighter, humanoid, rootPart, data, target, targetHRP, inShowdown)
	-- Vertical gap awareness: target is perched on high ground
	local verticalGap = targetHRP.Position.Y - rootPart.Position.Y
	local lastPJ = fighter:GetAttribute("LastPositioningJumpTime") or 0 -- tick() timestamp
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
	data.jumpClimbSince = jumpable and (data.jumpClimbSince or tick()) or nil
	local jumpFirst = jumpable and tick() - data.jumpClimbSince < (CombatConfig.HighGround_ClimbPatience or 5)
	local stoneClimb = not jumpFirst and (verticalGap >= (CombatConfig.Nav_StoneMinClimb or 8)
		or (verticalGap >= 2 and not NavigationModule.isReachable(rootPart, targetHRP)))
	if not inShowdown and stoneClimb and LocomotionModule.isOnGround(rootPart, humanoid) and not LocomotionModule.isSliding(fighter) then
		local stone = NavigationModule.nextStone(fighter, rootPart, targetHRP, 2)
		if stone then
			fighter:SetAttribute("ObstacleAwareness", string.format("Stepping stone: %.0f up, %.0f across", stone.rise, stone.hop))
			-- (owner 2026-10-27: tone the stone hops down - one every StoneHopCooldown, not 0.6 s)
			if tick() - (fighter:GetAttribute("LastStoneHopTime") or 0) >= (CombatConfig.Nav_StoneHopCooldown or 2.5) then
				fighter:SetAttribute("LastStoneHopTime", tick())
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
					require(game:GetService("ReplicatedStorage"):WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("AirDash")).noteJump(fighter, stone.point)
					return States.Chase
				end
				-- a wide stone it is only not lined up with: it turns to it and jumps, no spot hop
				if wideTop and not lined and toStone.Magnitude > 0.1 then
					fighter:SetAttribute("LastStoneHopTime", 0)
					LocomotionModule.steer(fighter, humanoid, rootPart, stone.point, 16.0, 0.1)
					return States.Chase
				end
				fighter:SetAttribute("LastProjectileJumpTime", tick())
				fighter:SetAttribute("JumpWhy", "spot hop to a stepping stone (it is up high)") -- (JumpLog, team step 5)
				local ProjectileJumpState = States.ProjectileJump
				ProjectileJumpState.aimAtPoint(fighter, stone.point)
				return ProjectileJumpState
			end
			LocomotionModule.brake(fighter, humanoid, rootPart, 0.1)
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
			if problem == "TooClose" and toEdge.Magnitude > 0.1 then
				fighter:SetAttribute("ObstacleAwareness", "Backing off for a run-up")
				LocomotionModule.steer(fighter, humanoid, rootPart, rootPart.Position - toEdge.Unit * 14, 24.0, 0.05)
				GaitModule.update(humanoid, rootPart, 0.1)
				return States.Chase
			end
			local facingEdge = toEdge.Magnitude > 0.1 and rootPart.CFrame.LookVector:Dot(toEdge.Unit) > 0.85
			if solution and facingEdge and energy >= climbEnergyCost and (tick() - lastPJ) >= 2.0 and canLeave then
				fighter:SetAttribute("ObstacleAwareness", "High-Ground Intercept Jump")
				fighter:SetAttribute("JumpWhy", "jump up to it on high ground") -- (JumpLog, team step 5)
				if LocomotionModule.jump(fighter, humanoid, rootPart, solution.height, solution.speed, "jump") then
					-- (where it means to land, so a jump coming down short can dash on to it)
					require(game:GetService("ReplicatedStorage"):WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("AirDash")).noteJump(fighter, edge + toEdge.Unit * (depth or 4))
					fighter:SetAttribute("LastPositioningJumpTime", tick())
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
				and (tick() - lastProjectileJump) >= cooldown
				and flatDistToTgt <= (CombatConfig.ProjectileJumpMaxDistance or 800) then
				fighter:SetAttribute("LastProjectileJumpTime", tick())
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
