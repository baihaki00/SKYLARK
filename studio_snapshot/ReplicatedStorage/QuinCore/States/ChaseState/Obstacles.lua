--// ChaseState/Obstacles.lua
-- What lies between a chaser and its target, and the move it takes for it: an obstacle ahead
-- (vault, step over, steer round), a gap to slide under, a wall to run along, high ground to
-- take, a platform to get down from, a face it is stuck against.
-- Returns: next state (or nil), the steer round an obstacle, the way down off a platform, and
-- whether it walks now.
-- (Cut out of ChaseState.update as it was: QuinCore audit 2026-10-27, step 7.)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local CombatConfig = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("CombatConfig"))
local SpatialModule = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("SpatialModule"))
local PlatformCatalogue = require(game:GetService("ReplicatedStorage"):WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("PlatformCatalogue"))
local TraversalModule = require(game:GetService("ReplicatedStorage"):WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("TraversalModule"))
local LocomotionModule = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("LocomotionModule"))
local GaitModule = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("GaitModule"))
local Pers = require(game:GetService("ReplicatedStorage"):WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("Pers")) -- (personality reads + defaults, one place)
local States = require(game:GetService("ReplicatedStorage"):WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("States")) -- (every state by name)
local JumpHandler = LocomotionModule

local Obstacles = {}

function Obstacles.update(fighter, humanoid, rootPart, data, target, targetHRP, targetState, distance, now, hpRatio, confidence, inShowdown, shouldWalk)
	-- === Comprehensive OB & Obstacle Situational Awareness ===
	local obsInfo = SpatialModule.analyzeObstacleAhead(rootPart, targetHRP.Position, 22)
	local obstacleSteer = nil
	-- A lip lower than a step is walked over (it used to be "avoided": the Quin swerved,
	-- which on a narrow raised lane meant off the edge)
	if obsInfo.hasObstacle and (obsInfo.height or 99) < (CombatConfig.Locomotion_StepHeight or 1.5) then
		obsInfo = { hasObstacle = false }
	end
	if obsInfo.hasObstacle and not inShowdown then
		local isJumpSuppressed = LocomotionModule.isJumpSuppressed(fighter, humanoid)
		-- Takeoff timing: a runner leaves the ground so the top of its arc is over the obstacle,
		-- i.e. speed x time-to-apex before it (about 7 studs for a 2-stud hurdle at 40 studs/s,
		-- 12 for an 8-stud one). It used to jump as soon as the 22-stud look-ahead saw anything:
		-- a 2-stud hurdle from 19 studs out, and a taller one was refused until the Quin ran
		-- into it, stopped dead and hopped up from a standstill.
		local flatVelNow = Vector3.new(rootPart.AssemblyLinearVelocity.X, 0, rootPart.AssemblyLinearVelocity.Z)
		local speedNow = flatVelNow.Magnitude
		local faceDistance = obsInfo.hitPosition and Vector3.new(obsInfo.hitPosition.X - rootPart.Position.X, 0, obsInfo.hitPosition.Z - rootPart.Position.Z).Magnitude or 0
		local clearRise = math.clamp((obsInfo.height or 0) + 0.8, 3, 14)
		local timeToApex = math.sqrt(2 * clearRise / Workspace.Gravity)
		local takeoffDistance = math.max(2.5, speedNow * timeToApex)
		-- Thin (a hurdle, a low wall) or deep (a box, a platform): probe the top beyond the face
		local isThin = false
		if obsInfo.hitPosition and obsInfo.topSurfaceY then
			local dirFlat = (targetHRP.Position - rootPart.Position) * Vector3.new(1, 0, 1)
			dirFlat = dirFlat.Magnitude > 0.1 and dirFlat.Unit or Vector3.new(rootPart.CFrame.LookVector.X, 0, rootPart.CFrame.LookVector.Z).Unit
			local probeParams = RaycastParams.new()
			probeParams.FilterType = Enum.RaycastFilterType.Exclude
			probeParams.FilterDescendantsInstances = { fighter, Workspace:FindFirstChild("QuinServer") }
			local beyond = obsInfo.hitPosition + dirFlat * 7 + Vector3.new(0, 1, 0)
			local down = Workspace:Raycast(Vector3.new(beyond.X, obsInfo.topSurfaceY + 3, beyond.Z), Vector3.new(0, -(obsInfo.topSurfaceY + 3 - rootPart.Position.Y + 8), 0), probeParams)
			isThin = not down or down.Position.Y < obsInfo.topSurfaceY - 1.5
		end
		-- Skid-over: a low obstacle (up to SkidOver_MaxRise) is crossed in one speed vault, a
		-- hand on top, whatever its length up to SkidOver_MaxLength. The flight is sized to the
		-- length (apex over the middle, landing a stride past the far edge) and the clip is
		-- fitted to that flight (LocomotionModule "skidover").
		-- Thin obstacles too tall to skid (up to Hurdle_MaxRise high, 7 deep) are hurdled with the
		-- same solve and a little more clearance: the old hurdle peaked over the near edge and
		-- came down on top of a 3-deep, 7-tall bar.
		local skidRise, skidTakeoff, crossType, skidLength, crossHeight, crossSpeed = nil, nil, nil, nil, nil, nil
		-- Skid-over only between SkidOver_MinRise and SkidOver_MaxRise (3-5: below that the hand
		-- on top reads wrong, above it the vault is too high); everything else is a jump
		local lowEnoughToSkid = (obsInfo.height or 99) <= (CombatConfig.SkidOver_MaxRise or 5)
			and (obsInfo.height or 0) >= (CombatConfig.SkidOver_MinRise or 3)
		if obsInfo.hitPosition and obsInfo.topSurfaceY and (obsInfo.height or 99) <= (CombatConfig.Hurdle_MaxRise or 11) and speedNow >= 14 then
			local dirFlat = Vector3.new(flatVelNow.X, 0, flatVelNow.Z).Unit
			local probeParams = RaycastParams.new()
			probeParams.FilterType = Enum.RaycastFilterType.Exclude
			probeParams.FilterDescendantsInstances = { fighter, Workspace:FindFirstChild("QuinServer") }
			local length = nil
			for d = 1, lowEnoughToSkid and (CombatConfig.SkidOver_MaxLength or 16) or 7, 1.5 do
				local p = obsInfo.hitPosition + dirFlat * d
				local top = Workspace:Raycast(Vector3.new(p.X, obsInfo.topSurfaceY + 2, p.Z), Vector3.new(0, -4, 0), probeParams)
				if not top or top.Position.Y < obsInfo.topSurfaceY - 1 then
					length = d
					break
				end
			end
			skidLength = length
			if length then
				-- Apex over the middle; the arc must clear the obstacle's height (+0.8) at both
				-- edges: g/8 * (T^2 - (L/v)^2) >= h + 0.8. Takeoff and landing are each
				-- (v*T - L)/2 from the edges.
				local g = Workspace.Gravity
				local clearance = (lowEnoughToSkid or obsInfo.height < 3) and 0.8 or 1.2
				local flight = math.sqrt((length / speedNow) ^ 2 + 8 * (obsInfo.height + clearance) / g)
				local rise = g * flight * flight / 8
				if rise <= (lowEnoughToSkid and (CombatConfig.SkidOver_MaxFlightRise or 9) or 14) then
					skidRise = rise
					skidTakeoff = math.max(2, (speedNow * flight - length) / 2)
					crossType = lowEnoughToSkid and "skidover" or "hurdle"
					crossHeight = obsInfo.height + clearance

					-- Pace for the next one. A crossing lands as far past this obstacle as it took off
					-- before it, and both grow with speed; with the next obstacle close behind, a full
					-- sprint landed with no run-up left for it (0.9 studs from a 7-stud bar: a dead stop
					-- and a standing jump). A runner shortens up on the ground, before taking off: the
					-- approach speed is capped so this landing plus the next takeoff fit in the gap,
					--   v <= (2 (gap - 1) + L1 + L2) / (T1 + T2),  T = sqrt(8 (h + c) / g)
					local farEdge = obsInfo.hitPosition + dirFlat * length
					local floorY = obsInfo.topSurfaceY - obsInfo.height
					local ahead = Workspace:Raycast(Vector3.new(farEdge.X, floorY + 1.0, farEdge.Z) + dirFlat * 0.5, dirFlat * 26, probeParams)
					if data and ahead and ahead.Normal.Y < 0.3 then
						local inside = ahead.Position - Vector3.new(ahead.Normal.X, 0, ahead.Normal.Z) * 0.4
						local nextTop = Workspace:Raycast(inside + Vector3.new(0, 20, 0), Vector3.new(0, -24, 0), probeParams)
						local nextH = nextTop and (nextTop.Position.Y - floorY) or 0
						if nextH >= (CombatConfig.Locomotion_StepHeight or 1.5) and nextH <= (CombatConfig.Hurdle_MaxRise or 11) then
							local gap = (ahead.Position - farEdge):Dot(dirFlat)
							local T1 = math.sqrt(8 * (obsInfo.height + clearance) / g)
							local T2 = math.sqrt(8 * (nextH + 1.0) / g)
							local paceCap = (2 * (gap - 1) + length + 3) / (T1 + T2)
							if paceCap < speedNow + 2 then
								data.obstaclePace = math.max(paceCap, 16)
								data.obstaclePaceUntil = now + 0.6
								fighter:SetAttribute("ObstaclePace", math.floor(data.obstaclePace))
							end
						end
					end
				end
			end
		end
		local readyToJump = isThin and faceDistance <= takeoffDistance + 1
			or (not isThin and faceDistance <= 4 + speedNow * 0.16)
		-- This state updates at 10 Hz: at 40 studs/s that is 4 studs a tick, about the whole
		-- takeoff window, so the takeoff is timed to the moment (task.delay) once it falls
		-- before the next tick
		local skidLead = speedNow * 0.15
		if skidRise then
			readyToJump = faceDistance <= skidTakeoff + skidLead
		end
		if skidRise and readyToJump and not isJumpSuppressed and not humanoid.Jump and humanoid:GetState() ~= Enum.HumanoidStateType.Freefall then
			if tick() >= (fighter:GetAttribute("SkidPendingUntil") or 0) then
				local wait = math.max(0, (faceDistance - skidTakeoff) / math.max(speedNow, 1))
				fighter:SetAttribute("SkidPendingUntil", tick() + wait + 0.3)
				fighter:SetAttribute("SkidPlan", string.format("%s face %.1f takeoff %.1f wait %.2f length %.1f rise %.1f v %.0f%s",
					crossType, faceDistance, skidTakeoff, wait, skidLength or -1, skidRise, speedNow,
					crossSpeed and string.format(" (setting up the next: v %.0f)", crossSpeed) or ""))
				fighter:SetAttribute("ObstacleAwareness", crossType == "skidover" and "Skidding over" or "Hurdling")
				local facePos = obsInfo.hitPosition
				local crossDir = Vector3.new(flatVelNow.X, 0, flatVelNow.Z).Unit
				local plannedRise, plannedTakeoff, plannedLength, plannedHeight, plannedSpeed = skidRise, skidTakeoff, skidLength, crossHeight, crossSpeed
				task.delay(wait, function()
					-- Just off a landing the body can still read as airborne for a few frames; the
					-- jump would be refused and it ran into the obstacle. Wait for the ground (briefly).
					local function inAir()
						return not LocomotionModule.isOnGround(rootPart, humanoid)
					end
					local deadline = os.clock() + 0.35
					while inAir() and os.clock() < deadline do
						task.wait()
					end
					if fighter.Parent and humanoid.Health > 0 and fighter:GetAttribute("CurrentState") == "Chase"
						and not inAir() then
						local v = rootPart.AssemblyLinearVelocity
						local speed = plannedSpeed or Vector3.new(v.X, 0, v.Z).Magnitude
						local rise = plannedRise
						-- Where it really is now: a crossing planned on a landing, or a tick late,
						-- can be closer than the ideal takeoff. Then it jumps from here instead of
						-- refusing: the lowest arc that still clears both edges, found over the
						-- horizontal speeds it can shed (a shortened, steeper jump).
						local d = (facePos - rootPart.Position):Dot(crossDir)
						if d < plannedTakeoff - 0.75 then
							local g = Workspace.Gravity
							local H = plannedHeight
							local L = plannedLength or 3
							local best = nil
							if d > 0.3 then
								for hv = math.max(speed, 10), 8, -2 do
									local vy = math.max(H * hv / d + g * d / (2 * hv), H * hv / (d + L) + g * (d + L) / (2 * hv))
									if not best or vy < best.vy * 0.93 then
										best = { hv = hv, vy = vy }
									end
								end
							end
							if not best or best.vy * best.vy / (2 * g) > 14 then
								fighter:SetAttribute("SkidPlan", (fighter:GetAttribute("SkidPlan") or "") .. string.format(" TOO CLOSE d %.1f", d))
								return
							end
							rise = best.vy * best.vy / (2 * g)
							speed = best.hv
							fighter:SetAttribute("SkidPlan", (fighter:GetAttribute("SkidPlan") or "") .. string.format(" SHORT d %.1f -> v %.0f rise %.1f", d, speed, rise))
						end
						if crossType == "skidover" then
							fighter:SetAttribute("SkidObstacleHeight", plannedHeight - 0.8)
						end
						local ok = JumpHandler.performJump(humanoid, rootPart, rise, speed, crossType)
						if ok == false then
							fighter:SetAttribute("SkidPlan", (fighter:GetAttribute("SkidPlan") or "") .. " REFUSED " .. tostring(fighter:GetAttribute("JumpRejected")))
						end
					end
				end)
			end
		elseif obsInfo.canVault and not readyToJump then
			fighter:SetAttribute("ObstacleAwareness", "Approaching Obstacle")
		elseif obsInfo.canVault and isThin and not isJumpSuppressed and not humanoid.Jump and humanoid:GetState() ~= Enum.HumanoidStateType.Freefall then
			fighter:SetAttribute("ObstacleAwareness", "Hurdling")
			JumpHandler.performJump(humanoid, rootPart, clearRise, speedNow, "hurdle")
		elseif obsInfo.canVault and not isJumpSuppressed and not humanoid.Jump and humanoid:GetState() ~= Enum.HumanoidStateType.Freefall then
			local soundPart = fighter:FindFirstChild("Sounds")
			if soundPart then
				local jumpSound = soundPart:FindFirstChild("jump")
				if jumpSound then
					jumpSound.Volume = 0.08
					jumpSound.PlaybackSpeed = math.random(2.1, 2.4)
					jumpSound:Play()
				end
			end
			fighter:SetAttribute("ObstacleAwareness", obsInfo.isOB and "Parkour Vaulting OB" or "Parkour Vaulting Obstacle")
			JumpHandler.performJump(humanoid, rootPart, obsInfo.height, nil, "vault")
		else
			-- Ground pathfinding fallback: tall barrier or jumps suppressed -> steer along tangent around obstacle
			fighter:SetAttribute("ObstacleAwareness", obsInfo.isOB and "Navigating OB" or "Avoiding Obstacle")
			obstacleSteer = obsInfo.steerDirection
		end
	else
		fighter:SetAttribute("ObstacleAwareness", "Clear")
	end

	-- Slide-under: low-overhead gap ahead -> athletic SlideState
	local slideGap = SpatialModule.detectLowOverheadGap(rootPart, 18)
	local energy = fighter:GetAttribute("Energy") or 100
	local aggressionHabit = Pers.get(fighter, "Aggression")
	local dashHabit = Pers.get(fighter, "DashPreference")
	local charge = math.clamp((aggressionHabit - 0.7) / 0.25, 0, 1) * math.clamp((dashHabit - 0.6) / 0.3, 0, 1)
	local lastSlide = fighter:GetAttribute("LastSlideTime") or 0
	local slideCooldown = (CombatConfig.SlideCooldown or 8.0) - 3.0 * charge -- (a charger slides more)
	local canSlide = (now - lastSlide) >= slideCooldown and energy >= (CombatConfig.SlideMinEnergy or 12)
		and not humanoid.Jump and humanoid:GetState() ~= Enum.HumanoidStateType.Freefall

	-- Sliding under a gap is forced by the course, not a choice: no cooldown or energy gate.
	-- The clip is low from about 0.1 s to 0.9 s, so it starts when the bar is ~0.3 s away.
	if slideGap and not inShowdown and not LocomotionModule.isSliding(fighter) then
		local flatSpeed = Vector3.new(rootPart.AssemblyLinearVelocity.X, 0, rootPart.AssemblyLinearVelocity.Z).Magnitude
		if slideGap.faceDistance <= flatSpeed * 0.3 + 1.5 then
			fighter:SetAttribute("ObstacleAwareness", string.format("Sliding under a %.0f-stud gap", slideGap.gapHeight))
			fighter:SetAttribute("LastSlideTime", now)
			LocomotionModule.slide(fighter, humanoid, rootPart, nil, nil, { underGap = true })
			return States.Chase
		end
		fighter:SetAttribute("ObstacleAwareness", "Approaching a low gap")
	end

	-- Tactical Gap-Close Slide: one decision per approach, taken as the Quin comes into slide
	-- range at running speed, so the slide ends in striking distance. (It used to be re-rolled
	-- every 1.5s, and the range is crossed in under half a second, so it almost never fired.)
	if distance > 45 then
		data.slideDecided = false
	end
	-- (a tackle has to reach: the glide covers ~17 studs at a run, plus the legs' reach)
	local tackling = CombatConfig.SlideTackle_Enabled ~= false
	local slideMin = tackling and (CombatConfig.SlideTackle_StartMin or 8) or 18
	local slideMax = tackling and (CombatConfig.SlideTackle_StartMax or 19) or 35
	if canSlide and distance >= slideMin and distance <= slideMax and (data.currentSpeed or 30) >= 24 and not inShowdown then
		if not data.slideDecided then
			data.slideDecided = true
			local mobilityPref = Pers.get(fighter, "MobilityPreference")
			local slideChance = math.max(math.clamp(0.10 + 0.5 * mobilityPref, 0.10, 0.45), 0.6 * charge)
			if workspace:GetAttribute("SlideTackleAlways") and game:GetService("RunService"):IsStudio() then slideChance = 1 end -- (test switch)
			data.slideWanted = math.random() < slideChance
		end
		-- Decided to slide in: it goes as soon as its run lines up with the target (a tackle slide
		-- refuses a target too far off its line; the chase curves in, so that comes a moment later)
		if data.slideWanted then
			-- (a slide in on the target takes the legs of whoever stands in its lane: Modules/SlideTackle)
			if require(game:GetService("ReplicatedStorage"):WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("SlideTackle")).slide(fighter, humanoid, rootPart, target) > 0 then
				data.slideWanted = false
				fighter:SetAttribute("ObstacleAwareness", "Tactical Slide Gap-Close")
				fighter:SetAttribute("LastSlideTime", now)
				return States.Chase
			end
		end
	end

	-- Dynamic Wall-Running (Phase 6 Parkour): angled vertical wall traversal
	local lastWallRun = fighter:GetAttribute("LastWallRunTime") or 0
	local mobilityHabit = Pers.get(fighter, "MobilityPreference")
	local riskHabit = Pers.get(fighter, "RiskTolerance")
	local wallLover = math.clamp((mobilityHabit - 0.7) / 0.2, 0, 1) * math.clamp((riskHabit - 0.6) / 0.2, 0, 1)
	local wallRunCooldown = (CombatConfig.WallRunCooldown or 5.0) - 2.5 * wallLover
	-- (a target that takes to a wall is followed onto it: no waiting out the cooldown)
	local followingOntoWall = targetState == "WallRun"
	local canWallRun = ((now - lastWallRun) >= wallRunCooldown or followingOntoWall) and energy >= (CombatConfig.WallRunMinEnergy or 15)
		and (data.currentSpeed or 30) >= (CombatConfig.WallRunMinSpeed or 18)
		and not humanoid.Jump and humanoid:GetState() ~= Enum.HumanoidStateType.Freefall

	-- Not worth mounting a wall with the target already this close: the run would end at once
	if canWallRun and not inShowdown and distance > 22 then
		local wallSurface = SpatialModule.detectWallRunSurface(rootPart, CombatConfig.WallRunRayDistance or 4.8, CombatConfig.WallRunMinRunway or 24)
		local WallRunState = States.WallRun
		if wallSurface and WallRunState.fastEnough(rootPart, wallSurface) then
			fighter:SetAttribute("ObstacleAwareness", "Wall-Running " .. wallSurface.side)
			return WallRunState
		end
	end

	-- High-Ground Seeking: climb to a reachable overhead platform when it grants an
	-- advantage — target is above, being pressured/bullied, or critically hurt.
	local overheadPlatform = SpatialModule.findReachableOverheadPlatform(rootPart, (CombatConfig.Jump_MaxReach or 25) + 2)
	if overheadPlatform and not inShowdown and not humanoid.Jump and humanoid:GetState() ~= Enum.HumanoidStateType.Freefall then
		local lastHighGround = data.lastHighGroundJump or 0
		local targetAbove = targetHRP.Position.Y > rootPart.Position.Y + 5
		local recAction = fighter:GetAttribute("RecommendedAction")
		local beingBullied = fighter:GetAttribute("BeingBullied")
		local wantHighGround = targetAbove or recAction == "Retreat" or beingBullied or hpRatio < 0.35
		if wantHighGround and (now - lastHighGround) > 6 then
			-- The top is reached from outside its footprint, by the jump solved for its rim. (It
			-- used to jump straight up from wherever it stood: when that was under the platform
			-- it hit the underside, and tried again every 6 s.) It gives the climb a few seconds:
			-- out from under, a run-up, the jump; then it lets it be for a while.
			data.highGroundSince = data.highGroundSince or now
			local platform = PlatformCatalogue.under(overheadPlatform.position + Vector3.new(0, 0.5, 0), 2)
			local feetY = rootPart.Position.Y - (humanoid.HipHeight + rootPart.Size.Y / 2)
			local rise = overheadPlatform.topY - feetY
			local edge = platform and PlatformCatalogue.nearestTopPoint(platform, rootPart.Position, 0)
			local toEdge = edge and Vector3.new(edge.X - rootPart.Position.X, 0, edge.Z - rootPart.Position.Z)
			if not platform or now - data.highGroundSince > (CombatConfig.HighGround_ClimbPatience or 5) then
				data.lastHighGroundJump, data.highGroundSince = now, nil
			elseif toEdge.Magnitude < 1.0 then
				-- Under it: out the nearest way, with room for a run-up
				local outward = Vector3.new(rootPart.Position.X - platform.center.X, 0, rootPart.Position.Z - platform.center.Z)
				outward = outward.Magnitude > 0.5 and outward.Unit or rootPart.CFrame.LookVector
				local rim = PlatformCatalogue.nearestTopPoint(platform, platform.center + outward * 1000, 0)
				fighter:SetAttribute("ObstacleAwareness", "Under the platform: stepping out to jump")
				LocomotionModule.steer(fighter, humanoid, rootPart, Vector3.new(rim.X, rootPart.Position.Y, rim.Z) + outward * 14, 24.0, 0.05)
				GaitModule.update(humanoid, rootPart, 0.1)
				return States.Chase
			else
				local depth = PlatformCatalogue.landingDepth(platform, edge, rootPart.Position)
				local solution, problem = TraversalModule.solveJumpOnto(rise, toEdge.Magnitude, CombatConfig.Jump_MaxReach or 25.0, depth)
				if solution and rootPart.CFrame.LookVector:Dot(toEdge.Unit) > 0.85 then
					fighter:SetAttribute("ObstacleAwareness", "Climbing High Ground")
					fighter:SetAttribute("JumpWhy", "climb high ground") -- (JumpLog, team step 5)
					if LocomotionModule.jump(fighter, humanoid, rootPart, solution.height, solution.speed, "jump") then
						require(game:GetService("ReplicatedStorage"):WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("AirDash")).noteJump(fighter, edge + toEdge.Unit * (depth or 4))
						data.lastHighGroundJump, data.highGroundSince = now, nil
						return States.Chase
					end
				elseif problem == "TooHigh" then
					data.lastHighGroundJump, data.highGroundSince = now, nil
				else
					-- too close for the jump: back off for the run-up; otherwise up to the rim, facing it
					local away = problem == "TooClose" and -14 or 14
					fighter:SetAttribute("ObstacleAwareness", problem == "TooClose" and "Backing off for a run-up" or "Lining up the climb")
					LocomotionModule.steer(fighter, humanoid, rootPart, rootPart.Position + toEdge.Unit * away, 24.0, 0.05)
					GaitModule.update(humanoid, rootPart, 0.1)
					return States.Chase
				end
			end
		else
			data.highGroundSince = nil
		end
	end

	-- Self Platform Dismount (Phase 4): if THIS Quin is perched on an elevated platform,
	-- walk toward the nearest ledge biased toward the target rather than milling around.
	local platformDismountDir = nil
	local ledgeDist = 999
	local allowPlatformDrop = false
	local targetBelow = (targetHRP.Position.Y < rootPart.Position.Y - 5.0)

	local isOnPlatform, platformInfo = SpatialModule.isOnElevatedPlatform(rootPart, CombatConfig.HighGround_PerchDetectThreshold or 5.0)
	if isOnPlatform then
		data.wasOnPlatform = true
		if targetBelow then
			allowPlatformDrop = true
			platformDismountDir, ledgeDist = SpatialModule.getPlatformDismountDirection(rootPart, targetHRP.Position)
			fighter:SetAttribute("ObstacleAwareness", "Approaching Platform Ledge")

			-- Check if close enough to ledge and facing target to execute Dive-Down Leap!
			local flatDist = Vector3.new(targetHRP.Position.X - rootPart.Position.X, 0, targetHRP.Position.Z - rootPart.Position.Z).Magnitude
			local lookVec = rootPart.CFrame.LookVector
			local isFacingTarget = lookVec:Dot(platformDismountDir) > 0.15
			-- How it leaves. In a hurry it dives off at its target (below). With time on its side
			-- (sure of itself, in good health, nobody pressing it, the target well away) it walks
			-- to the ledge and steps off: a straight drop, the soft landing, and it walks on.
			local casual = confidence >= (CombatConfig.Dismount_CasualConfidence or 0.7)
				and hpRatio > 0.5
				and flatDist >= (CombatConfig.Dismount_CasualMinDistance or 18)
				and (fighter:GetAttribute("SocialUrgency") or 0) < 0.5
				and not fighter:GetAttribute("SocialHunt")
				and fighter:GetAttribute("IsUnderRearThreat") ~= true
			-- (no jump: it keeps walking and the edge does the rest; the touchdown is the ground
			-- contract's, GaitModule, which gives a walked-off straight drop the soft landing)
			if casual then
				shouldWalk = true
				fighter:SetAttribute("ObstacleAwareness", "Walking off the ledge")
			end

			-- The jump down is sized for where it wants to come down: in striking distance of its
			-- target, from wherever on the top it stands (a hop for a near target, a full arc
			-- for a far one), and always past the ledge. (It used to be one 2-stud hop of 8-14
			-- studs, taken only from close to the ledge: it walked to the rim first, and landed
			-- at the foot of the platform whatever the distance to its target. Before that it
			-- was taken from anywhere and came down on the same top, several times over.)
			local landAt = math.max(flatDist - (CombatConfig.CombatRange or 8.2) * 0.9, 6)
			local leap = TraversalModule.solveJumpDown(rootPart.Position.Y - targetHRP.Position.Y, landAt, ledgeDist,
				CombatConfig.HighGround_DiveLedgeMargin or 2.5)
			local toTarget = Vector3.new(targetHRP.Position.X - rootPart.Position.X, 0, targetHRP.Position.Z - rootPart.Position.Z)
			local facingTarget = toTarget.Magnitude > 0.1 and lookVec:Dot(toTarget.Unit) > 0.85
			local canDive = (CombatConfig.HighGround_DiveDropEnabled ~= false)
				and not humanoid.Jump
				and humanoid:GetState() ~= Enum.HumanoidStateType.Freefall
				and leap ~= nil
				and isFacingTarget and facingTarget
				and not casual

			if canDive then
				fighter:SetAttribute("ObstacleAwareness", "Ledge Dive Down")
				data.isDismountFalling = true
				data.wasOnPlatform = false
				fighter:SetAttribute("JumpWhy", "leap down after it") -- (JumpLog, team step 5)
				LocomotionModule.jump(fighter, humanoid, rootPart, leap.height, leap.speed, "leap_down", leap.flightTime)
				return States.Chase
			end
			-- (debug HUD, probes: why it has not jumped yet)
			local skip = casual and "casual" or (not leap and "ledge too far for the arc") or (not (isFacingTarget and facingTarget) and "not facing") or "in the air"
			if fighter:GetAttribute("DiveSkip") ~= skip then
				fighter:SetAttribute("DiveSkip", skip)
			end
		end
	end

	-- Vertical Obstacle Unstick (Phase 4): detect zero-progress against a vertical face
	-- and force a vertical hop instead of grinding endlessly into the wall.
	data.stuckCheckPos = data.stuckCheckPos or rootPart.Position
	data.stuckCheckTime = data.stuckCheckTime or now
	if (now - data.stuckCheckTime) >= 1.2 then
		local progress = (rootPart.Position - data.stuckCheckPos).Magnitude
		if progress < (CombatConfig.VerticalStuckThreshold or 0.8) and distance > 15 and not humanoid.Jump and humanoid:GetState() ~= Enum.HumanoidStateType.Freefall and not allowPlatformDrop then
			fighter:SetAttribute("ObstacleAwareness", "Unsticking Vertical Barrier")
			JumpHandler.performJump(humanoid, rootPart, CombatConfig.VerticalUnstickJumpHeight or 9.0, 10, "jump")
		end
		data.stuckCheckPos = rootPart.Position
		data.stuckCheckTime = now
	end
	return nil, obstacleSteer, platformDismountDir, shouldWalk
end

return Obstacles
