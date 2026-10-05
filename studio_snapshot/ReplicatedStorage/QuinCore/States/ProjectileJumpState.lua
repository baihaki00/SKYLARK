--// ProjectileJumpState.lua
-- The rocket jump: launch, fly, and come down on the target (or on a point, see aimAtPoint).
-- Styles (attribute JumpStyle; every one ends in the same Impact):
--   1  Arc        one ballistic arc straight onto the target, no dive
--   2  High dive  launch 310-410 studs up, then dive at the target
--   3  Double     a second jump in mid-air, then a faster dive
--   4  Sidestep   high launch, a dive off to one side, then the dive at the target
--   5  Swoop      high launch, then a curved (Bezier) swoop onto the target
--   6  Combo      a sequence of jumps and sideways dives, then a faster dive
--   7  Rocket     high launch and the fastest dive
--   8  Intercept  straight up at an enemy that is in the air, tracking it (AirInterceptModule
--                 asks for it; it is not in the random pool). Meeting it starts a mid-air
--                 clash; if the enemy comes down first, the jump turns into a dive on it.
-- The dive speed is CombatConfig.ProjectileJump_SlamSpeed, and a dive holds it from its first
-- frame to the floor: a turn in the air (styles 4 and 6) is a dive leg like the last one (boom,
-- vapour cone, flying clip, head first) that goes straight into the next leg with no stop, and
-- the swoop is flown along its curve at that one speed.
local DebugDraw = require(game:GetService("ReplicatedStorage"):WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("DebugDraw"))
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")
local CollectionService = game:GetService("CollectionService")

local AudioModule = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("AudioModule"))
local VfxModule = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("VfxModule"))
local TargetingModule = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("TargetingModule"))
local AnimationIds = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("AnimationIds"))
local AnimationConfig = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("AnimationConfig"))
local AnimationModule = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("AnimationModule"))
local KnockbackModule = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("KnockbackModule"))
local CombatConfig = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("CombatConfig"))
local SpatialModule = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("SpatialModule"))
local ImpulseModule = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("ImpulseModule"))
local RunService = game:GetService("RunService")

local ProjectileJumpState = { name = "ProjectileJump" }

local Config = {
	JumpPowerMin = 350,
	JumpPowerMax = 400,
	DashExecuteTimeMin = 2.0,
	DashExecuteTimeMax = 2.5,

	MultiJumpPowerMin = 200,
	MultiJumpPowerMax = 250,
	MultiJumpGapTimeMin = 0.75,
	MultiJumpGapTimeMax = 1.25,
	MultiJumpDashTimeMin = 0.75,
	MultiJumpDashTimeMax = 1.25,

	SlamSpeed = CombatConfig.ProjectileJump_SlamSpeed or 480,
	StrafeDistanceMin = 150,
	StrafeDistanceMax = 300,
	CurveAggressiveness = 1,
	ArcSpeedXZ = 100,

	MultiJumpForwardSpeedMin = 100,
	MultiJumpForwardSpeedMax = 200,
	MultiJumpSideSpeedMin = -200,
	MultiJumpSideSpeedMax = 200,

	ComboGapTimeMin = 0.3,
	ComboGapTimeMax = 0.6,

	-- New Bezier Settings
	BezierArcHeightBase = 50,
	BezierLateralBendBase = 40,
	SlamSpeedMultiplier = 1.15
}

local INTERCEPT_STYLE = 8
local INTERCEPT_TIMEOUT = 2.5 -- seconds of pursuit in the air before it dives instead

-- Styles whose dive gets the SlamSpeedMultiplier
local FAST_DIVE_STYLES = { [3] = true, [6] = true, [7] = true }

local function getFloat(min, max)
	return min + math.random() * (max - min)
end

-- Math Helpers for Style 5
local function calculateLowestY(Y0, Y2, ArcHeight)
	if ArcHeight == 0 then return math.min(Y0, Y2) end
	local tLowest = 0.5 - (Y0 - Y2) / (4 * ArcHeight)
	if tLowest >= 0.0 and tLowest <= 1.0 then
		local midY = (Y0 + Y2) / 2
		local P1Y = midY + ArcHeight
		return ((1 - tLowest)^2 * Y0) + (2 * (1 - tLowest) * tLowest * P1Y) + (tLowest^2 * Y2)
	else
		return math.min(Y0, Y2)
	end
end

local function isCurveSafe(P0, P1, P2, fighter, target)
	local segments = 10
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = {fighter, target}

	local prevPoint = P0
	for i = 1, segments do
		local t = i / segments
		local nextPoint = ((1 - t)^2 * P0) + (2 * (1 - t) * t * P1) + (t^2 * P2)
		local dir = nextPoint - prevPoint
		local dist = dir.Magnitude
		if dist > 0.01 then
			local hit = workspace:Spherecast(prevPoint, 2, dir.Unit * dist, params)
			if hit then return false end
		end
		prevPoint = nextPoint
	end
	return true
end

-- scatterAngle is rolled once per jump: re-rolling it on every update moved the landing spot
-- 5-25 studs each tick, so a diving Quin kept re-aiming between scattered points near the ground.
local function calculateCombatAimPoint(rootPart, targetHRP, dashSpeed, humanoid, scatterAngle, precise)
	local targetPos = targetHRP.Position
	local targetVel = targetHRP.AssemblyLinearVelocity
	local flatTargetVel = Vector3.new(targetVel.X, 0, targetVel.Z)

	-- Dynamic arrival time for lead interception
	local currentDist = (targetPos - rootPart.Position).Magnitude
	local speed = dashSpeed or Config.SlamSpeed or 500
	local tArrival = math.clamp(currentDist / speed, 0.04, 0.40)

	-- First-order lead position (where the moving target will be upon dive arrival)
	local leadPos = targetPos + (flatTargetVel * tArrival)

	-- Approach vector on XZ plane
	local toLeadFlat = Vector3.new(leadPos.X - rootPart.Position.X, 0, leadPos.Z - rootPart.Position.Z)
	local approachDir = toLeadFlat.Magnitude > 0.01 and toLeadFlat.Unit or rootPart.CFrame.LookVector

	-- Arena floor altitude at the landing point
	local groundY = targetPos.Y
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = {rootPart.Parent, targetHRP.Parent}
	-- (all the way down: a 35-stud ray found nothing under an airborne target or a tall
	-- platform, the aim fell back to the target's own height and the dive went up at it)
	rayParams.FilterDescendantsInstances = {rootPart.Parent, targetHRP.Parent, Workspace:FindFirstChild("QuinServer")}
	rayParams.RespectCanCollide = true
	local floorRay = DebugDraw.raycast(rootPart, leadPos + Vector3.new(0, 10, 0), Vector3.new(0, -1000, 0), rayParams)
	if floorRay then
		groundY = floorRay.Position.Y + (humanoid and humanoid.HipHeight or 2.0) + (rootPart.Size.Y / 2)
	end

	-- Striking landing spot with organic clamped trajectory scatter (Sections 42 & 43)
	-- smashes are not 100% laser-guided; landing has a 5 to 25 studs scatter (clamped strictly <= 30)
	local jumpDist = (leadPos - rootPart.Position).Magnitude
	local scatterDist = math.clamp(jumpDist * 0.12, 5.0, 25.0)
	local randAngle = scatterAngle or (math.random() * math.pi * 2)
	local scatterOffset = Vector3.new(math.cos(randAngle), 0, math.sin(randAngle)) * scatterDist

	local landingSpot = leadPos - (approachDir * 4.5) + scatterOffset
	if precise then
		landingSpot = leadPos -- a jump to a spot (a platform) lands on the spot
	end
	landingSpot = Vector3.new(landingSpot.X, groundY, landingSpot.Z)

	return landingSpot, approachDir, groundY
end

-- Arena containment. Mid-air strafes cover 150-300 studs and the jump drifts another couple of
-- hundred; from most of the arena that carried the jumper over the wall, where the out-of-bounds
-- safety net teleported it back to the centre.
local ARENA_MARGIN = 30

-- Distance available along flatDir before the arena margin
local function arenaRoom(position, flatDir)
	local bounds = SpatialModule.getArenaBounds()
	local room = math.huge
	local function limit(p, d, center, half)
		if d > 0.001 then
			room = math.min(room, (center + half - ARENA_MARGIN - p) / d)
		elseif d < -0.001 then
			room = math.min(room, (center - half + ARENA_MARGIN - p) / d)
		end
	end
	limit(position.X, flatDir.X, bounds.center.X, bounds.halfX)
	limit(position.Z, flatDir.Z, bounds.center.Z, bounds.halfZ)
	return math.max(room, 0)
end

-- Sideways strafe: a random side, flipped and shortened as needed to stay inside the arena
local function pickStrafe(rootPart)
	local right = rootPart.CFrame.RightVector
	local dir = Vector3.new(right.X, 0, right.Z)
	dir = (dir.Magnitude > 0.01 and dir.Unit or Vector3.new(1, 0, 0)) * (math.random() > 0.5 and 1 or -1)
	local dist = getFloat(Config.StrafeDistanceMin, Config.StrafeDistanceMax)
	local room = arenaRoom(rootPart.Position, dir)
	if room < dist then
		local otherRoom = arenaRoom(rootPart.Position, -dir)
		if otherRoom > room then
			dir, room = -dir, otherRoom
		end
	end
	return dir, math.min(dist, room)
end

-- Removes the outward part of a horizontal velocity once the position is past the margin
local function containVelocity(position, velocity)
	local bounds = SpatialModule.getArenaBounds()
	local x, z = velocity.X, velocity.Z
	local dx, dz = position.X - bounds.center.X, position.Z - bounds.center.Z
	if math.abs(dx) > bounds.halfX - ARENA_MARGIN and dx * x > 0 then x = 0 end
	if math.abs(dz) > bounds.halfZ - ARENA_MARGIN and dz * z > 0 then z = 0 end
	return Vector3.new(x, velocity.Y, z)
end

local stateData = {}

local POINT_TARGET_NAME = "PJ_PointTarget"

local POINT_REQUEST_LIFETIME = 0.3 -- seconds: the jump must start on the tick that asked for it

local pointRequests = setmetatable({}, { __mode = "k" }) -- fighter -> { position, time }

-- Send a Quin on a projectile jump to a spot instead of at an enemy (a platform to get onto).
-- The caller then returns this state. The jump is a single arc that lands on the spot itself.
-- If the state machine does not take the transition on that tick, the request lapses.
function ProjectileJumpState.aimAtPoint(fighter, position)
	pointRequests[fighter] = { position = position, time = os.clock() }
end

-- The stand-in target for a jump to a spot: the flight code aims at a Model's root, so a spot
-- is given one, at the height the jumper's root will be when standing there
local function createPointTarget(position, humanoid, rootPart)
	local marker = Instance.new("Part")
	marker.Name = "Marker"
	marker.Size = Vector3.new(1, 1, 1)
	marker.Anchored = true
	marker.CanCollide = false
	marker.CanQuery = false
	marker.CanTouch = false
	marker.Transparency = 1
	marker.Position = position + Vector3.new(0, humanoid.HipHeight + rootPart.Size.Y / 2, 0)
	local standIn = Instance.new("Model")
	standIn.Name = POINT_TARGET_NAME
	marker.Parent = standIn
	standIn.PrimaryPart = marker
	standIn.Parent = Workspace
	return standIn
end

local function cleanupMovers(hrp)
	for _, child in ipairs(hrp:GetChildren()) do
		if child.Name == "PJ_Velocity" or child.Name == "PJ_Gyro" or child.Name == "PJ_Align" or child.Name == "PJ_Att" or child.Name == "PJ_LinearVelocity" then
			child:Destroy()
		elseif child.Name == "RocketTrail" then
			child.Enabled = false
			Debris:AddItem(child, child.Lifetime)
		elseif child.Name == "RocketTrailAtt0" or child.Name == "RocketTrailAtt1" then
			Debris:AddItem(child, 2)
		end
	end
end

local function spawnVisualizerNode(position)
	if not workspace:GetAttribute("ProjectileVisualizerEnabled") then return end
	local part = Instance.new("Part")
	part.Size = Vector3.new(1, 1, 1)
	part.Anchored = true
	part.CanCollide = false
	part.Material = Enum.Material.Neon
	part.Color = Color3.new(0, 1, 1)
	part.Position = position
	part.Parent = Workspace
	Debris:AddItem(part, 5)
end

-- How far the root is above its standing height over whatever floor is directly below it
-- (math.huge with no floor below). Only collidable geometry counts: other Quins and effect parts
-- (shockwave rings, trails, dust) drifting under a jumper are not floor.
local function heightAboveStand(rootPart, humanoid)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { rootPart.Parent, Workspace:FindFirstChild("QuinServer") }
	params.RespectCanCollide = true
	local hit = DebugDraw.raycast(rootPart, rootPart.Position + Vector3.new(0, 2, 0), Vector3.new(0, -1000, 0), params)
	if not hit then return math.huge end
	local standY = hit.Position.Y + (humanoid.HipHeight or 2.0) + (rootPart.Size.Y / 2)
	return rootPart.Position.Y - standY
end

-- Set-down latch: once the per-frame guard has started setting a falling body down onto the
-- floor, nothing else may re-aim the mover until it touches. A 10 Hz update landing on that same
-- frame re-applied full slam speed (~600 studs/s), the body punched 4-7 studs into the floor and
-- the Humanoid sprang it back up ~5 studs: the dive "bob". Live A/B: Workspace attribute PJSetDownLatch.
local SET_DOWN_MAX_TIME = 0.3 -- seconds; past this the latch lets go (something blocked the body)
local function setDownLatched(data)
	local switch = Workspace:GetAttribute("PJSetDownLatch")
	local on = switch == true or (switch == nil and CombatConfig.ProjectileJump_SetDownLatch ~= false)
	return on and data.settingDown == true and not data.touchedDown
		and os.clock() - (data.settingDownAt or 0) < SET_DOWN_MAX_TIME
end

-- Set-down snap (pass 22E, see the touchdown guard). Live A/B: Workspace attribute PJSetDownSnap;
-- off falls back to the velocity set-down with the latch above.
local function setDownSnapOn()
	local switch = Workspace:GetAttribute("PJSetDownSnap")
	return switch == true or (switch == nil and CombatConfig.ProjectileJump_SetDownSnap ~= false)
end

-- Tracks come from the shared per-humanoid cache (a fresh LoadAnimation per jump leaked a
-- track on the Animator every time)
local function playAnim(humanoid, id)
	if not id then return nil end
	local track = AnimationModule.getTrack(humanoid, id)
	if track then
		track:Play(0.1)
	end
	return track
end

local function stopAnim(track)
	if track then track:Stop(0.2) end
end

-- Projectile jump kits (AnimationConfig.Registry.ProjectileJump): a jump picks one
local KITS = {
	{ name = "Ninja", jump = "ProjectileJump.NinjaJump", loop = "ProjectileJump.NinjaAirLoop" },
	{ name = "Standard", jump = "ProjectileJump.StandardJump", loop = "ProjectileJump.StandardAirLoop" },
}

local function playClip(humanoid, path, looped)
	local entry = AnimationConfig.get(path)
	local track = entry and AnimationModule.getTrack(humanoid, entry.id)
	if track then
		track.Priority = Enum.AnimationPriority.Action3
		track.Looped = looped == true
		track:Play(entry.fadeTime or 0.1, 1, entry.speed or 1)
	end
	return track
end

-- The arc jump's other look: one smack-down clip over the whole jump (AnimationConfig
-- Attacks.Specials.ProceduralSmackDown, in place). Its markers: ProjectileJump (takeoff) 0.53 s,
-- BodyLanding 1.20 s, end 2.73 s. It starts at the takeoff; the airborne part is stretched or
-- squeezed every frame so the BodyLanding frame meets the touchdown, and the rest plays at normal
-- speed as the landing (RecoveryState carries it on instead of a landing clip).
local SMACK_PATH = "Attacks.Specials.ProceduralSmackDown"
local SMACK_TAKEOFF = 0.53
local SMACK_LANDING = 1.2

local function playSmackDown(humanoid)
	local entry = AnimationConfig.get(SMACK_PATH)
	local track = entry and AnimationModule.getTrack(humanoid, entry.id)
	if track then
		track.Priority = Enum.AnimationPriority.Action3
		track.Looped = false
		track:Play(0.08, 1, 1)
		if track.Length > 0 then
			track.TimePosition = SMACK_TAKEOFF
		end
	end
	return track
end

-- The dive: the flying clip, head first along the path
local function playDiveAnim(humanoid)
	return playClip(humanoid, "ProjectileJump.DiveFly", true)
end

-- A dive only ever goes down. Re-aimed at 480+ studs/s toward a target above (one in the air, on
-- a higher platform) it went up past it, then down, then up again.
local function diveDirection(offset, fallback)
	local flat = Vector3.new(offset.X, 0, offset.Z)
	local y = math.min(offset.Y, -0.3 * math.max(flat.Magnitude, 1))
	local dir = Vector3.new(offset.X, y, offset.Z)
	return dir.Magnitude > 0.001 and dir.Unit or fallback
end

local function switchPhase(data, newPhase)
	data.phase = newPhase
	data.phaseTime = tick()
	if data.fighter then
		data.fighter:SetAttribute("PJPhase", newPhase) -- for the debug HUD and probes
	end
end

local function targetPartOf(target)
	return target:FindFirstChild("HumanoidRootPart") or target.PrimaryPart or target:FindFirstChildWhichIsA("BasePart")
end

local FULL_FORCE = Vector3.new(math.huge, math.huge, math.huge)

-- Phases flown as a dive: head first along the path
local DIVE_PHASES = { Dash = true, Strafe = true, ComboStrafe = true }

local function diveSpeed(data)
	local speedMult = workspace:GetAttribute("GameSpeedMultiplier") or 1.0
	return Config.SlamSpeed * (FAST_DIVE_STYLES[data.style] and Config.SlamSpeedMultiplier or 1) * speedMult
end

-- Every leg of a dive opens the same way: the boom and the vapour cone, in the flying clip
local function diveEffects(data, humanoid, rootPart)
	if not data.diving then
		stopAnim(data.animTrack)
		data.animTrack = playDiveAnim(humanoid)
		data.diving = true
	end
	AudioModule.playSonicBoom(rootPart.Position)
	VfxModule.createVaporCone(rootPart, 0.5)
end

local function setDive(data, humanoid, rootPart, lv, velocity, phase)
	lv.MaxAxesForce = FULL_FORCE
	lv.VectorVelocity = velocity
	rootPart.AssemblyLinearVelocity = velocity
	switchPhase(data, phase)
	diveEffects(data, humanoid, rootPart)
end

-- The turn in the air: a dive off to one side, slightly downhill. The per-frame guard in enter
-- ends it on time and goes straight into what follows.
local function startTurnLeg(data, humanoid, rootPart, lv, phase)
	local side, distance = pickStrafe(rootPart)
	local speed = diveSpeed(data)
	local direction = (side - Vector3.yAxis * (CombatConfig.ProjectileJump_TurnLegSlope or 0.2)).Unit
	data.legDuration = distance / speed
	setDive(data, humanoid, rootPart, lv, direction * speed, phase)
end

-- The last leg: at the target (the Dash phase re-aims it as the target moves)
local function startFinalDive(data, humanoid, rootPart, lv)
	local targetPart = data.target and targetPartOf(data.target)
	if not targetPart then return end
	local speed = diveSpeed(data)
	local aimPoint = calculateCombatAimPoint(rootPart, targetPart, speed, humanoid, data.scatterAngle, data.precise)
	local direction = diveDirection(aimPoint - rootPart.Position, rootPart.CFrame.LookVector)
	setDive(data, humanoid, rootPart, lv, direction * speed, "Dash")
end

-- The swoop's curve (quadratic Bezier P0, P1, P2) and its direction of travel at t
local function curvePoint(data, t)
	return ((1 - t)^2 * data.P0) + (2 * (1 - t) * t * data.P1) + (t^2 * data.P2)
end

local function curveTangent(data, t)
	return 2 * (1 - t) * (data.P1 - data.P0) + 2 * t * (data.P2 - data.P1)
end

local CURVE_PULL = 4 -- per second: how firmly a body off the swoop's curve is drawn back onto it

-- Combo (style 6): the next action of the sequence
local function comboNext(data, humanoid, rootPart, lv)
	local action = data.comboSequence[data.comboIndex]
	if action == "Jump" then
		if data.diving then
			-- out of a dive leg into a jump: back to the airborne loop
			stopAnim(data.animTrack)
			data.animTrack = playClip(humanoid, data.kit.loop, true)
			data.diving, data.inAirLoop = false, true
		end
		lv.MaxAxesForce = Vector3.zero
		local jumpPower = math.random(Config.MultiJumpPowerMin, Config.MultiJumpPowerMax)
		local forwardVec = rootPart.CFrame.LookVector
		local rightVec = rootPart.CFrame.RightVector
		local forwardSpeed = math.random(Config.MultiJumpForwardSpeedMin, Config.MultiJumpForwardSpeedMax)
		local sideSpeed = math.random(Config.MultiJumpSideSpeedMin, Config.MultiJumpSideSpeedMax)
		local driftVelocity = (forwardVec * forwardSpeed) + (rightVec * sideSpeed)

		rootPart.AssemblyLinearVelocity = Vector3.new(driftVelocity.X, jumpPower, driftVelocity.Z)

		AudioModule.playJumpUp(rootPart.Position)
		VfxModule.createLaunchShockwave(rootPart)
		if data.comboIndex == 1 then
			VfxModule.createRocketTrail(rootPart)
			VfxModule.shakeScreen(rootPart.Position, 500, 8)
		end

		data.comboGapTime = getFloat(Config.ComboGapTimeMin, Config.ComboGapTimeMax)
		switchPhase(data, "ComboWait")
	elseif action == "Strafe" then
		startTurnLeg(data, humanoid, rootPart, lv, "ComboStrafe")
	elseif action == "Dash" then
		startFinalDive(data, humanoid, rootPart, lv)
	end
end

function ProjectileJumpState.enter(fighter, humanoid, rootPart)
	humanoid.PlatformStand = true
	cleanupMovers(rootPart)

	-- Select across all 7 projectile jump styles (Style 1 Parabolic, Style 5 Bezier, etc.)
	local style = fighter:GetAttribute("JumpStyle")
	-- An interception is for the tick that asked for it; left over from a jump that never
	-- started, it is not a style for an ordinary jump
	if style == INTERCEPT_STYLE and os.clock() - (fighter:GetAttribute("LastInterceptTime") or 0) > POINT_REQUEST_LIFETIME then
		style = nil
	end
	if not style then
		local styles = { 1, 1, 2, 3, 4, 5, 5, 6, 7 }
		style = styles[math.random(1, #styles)]
		fighter:SetAttribute("JumpStyle", style)
	end

	local targetVal = fighter:FindFirstChild("ProjectileTarget")
	local target = targetVal and targetVal.Value
	local pointRequest = pointRequests[fighter]
	pointRequests[fighter] = nil
	if pointRequest and os.clock() - pointRequest.time <= POINT_REQUEST_LIFETIME then
		target = createPointTarget(pointRequest.position, humanoid, rootPart)
		style = 1
		fighter:SetAttribute("JumpStyle", style)
	end
	if targetVal then
		-- A request is for one jump: left in place, the next jump started without one
		-- (from Chase) flew at whatever the previous jump was aimed at
		targetVal.Value = nil
	end
	if target and not target.Parent then
		target = nil
	end
	if not target then
		local currentTgt = fighter:GetAttribute("CurrentTarget") or fighter:GetAttribute("TargetQuin")
		if currentTgt then
			target = workspace:FindFirstChild(currentTgt) or (workspace:FindFirstChild("QuinServer") and workspace.QuinServer:FindFirstChild(currentTgt))
		end
	end
	if not target then
		target, _ = TargetingModule.getNearest(rootPart, CombatConfig.ChaseRange or 1000)
	end

	local CombatConfig = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("CombatConfig"))
	local energy = fighter:GetAttribute("Energy") or 100
	-- (a hop onto a spot, a stepping stone, is a short traversal jump, not the big attack)
	local drain = (target and target.Name == POINT_TARGET_NAME) and (CombatConfig.EnergyDrain_PointJump or 8)
		or (CombatConfig.EnergyDrain_ProjectileJump or 40)
	fighter:SetAttribute("EnergyAtActionStart", energy)
	fighter:SetAttribute("Energy", math.max(0, energy - drain))

	stateData[fighter] = {
		phase = "Init",
		style = style,
		target = target,
		startTime = tick(),
		phaseTime = tick(),
		jumpCount = 1,
		startPos = rootPart.Position,
		apexPos = nil,
		curveVelocity = nil,
		scatterAngle = math.random() * math.pi * 2,
		precise = target ~= nil and target.Name == POINT_TARGET_NAME,
		touchedDown = false,
		animTrack = nil,
		kit = KITS[math.random(1, #KITS)],
		fighter = fighter,
	}
	fighter:SetAttribute("PJPhase", "Init")
	local starting = stateData[fighter]
	if style == 1 and not starting.precise and math.random() < (CombatConfig.ProjectileJump_SmackDownChance or 0.5) then
		starting.smackDown = true
		starting.kit = nil -- no airborne loop: the one clip covers the flight
		starting.animTrack = playSmackDown(humanoid)
	else
		starting.animTrack = playClip(humanoid, starting.kit.jump, false)
	end

	AudioModule.playJumpUp(rootPart.Position)

	local att = Instance.new("Attachment")
	att.Name = "PJ_Att"
	att.Parent = rootPart

	local lv = Instance.new("LinearVelocity")
	lv.Name = "PJ_LinearVelocity"
	lv.Attachment0 = att
	lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	-- Per-axis limits: every phase below switches the mover on and off through MaxAxesForce.
	-- In the default mode that property is ignored and the mover pushes with MaxForce (1000),
	-- which left the dive to gravity and the arc short of its target.
	lv.ForceLimitMode = Enum.ForceLimitMode.PerAxis
	lv.MaxAxesForce = Vector3.new(math.huge, math.huge, math.huge)
	lv.VectorVelocity = Vector3.zero
	lv.Parent = rootPart

	local ao = Instance.new("AlignOrientation")
	ao.Name = "PJ_Align"
	ao.Mode = Enum.OrientationAlignmentMode.OneAttachment
	ao.Attachment0 = att
	ao.MaxTorque = 1e7
	ao.Responsiveness = 40
	ao.CFrame = rootPart.CFrame
	ao.Parent = rootPart

	-- Per-frame guard. The state itself updates at 10 Hz; at these speeds (150-1500 studs/s)
	-- that is 15-150 studs per update, so the things that must be exact run every frame:
	-- the end of a strafe, arena containment, and touchdown.
	local data = stateData[fighter]
	data.guardConn = RunService.Heartbeat:Connect(function(dt)
		if stateData[fighter] ~= data or not rootPart.Parent or not lv.Parent then
			data.guardConn:Disconnect()
			return
		end
		if data.touchedDown then return end

		-- The speed it comes in at (the landing slide carries its horizontal part). Not taken
		-- once the body is being set down: those last frames are driven straight down.
		local flightVelocity = rootPart.AssemblyLinearVelocity
		if flightVelocity.Magnitude > 30 and data.phase ~= "Impact" and not data.settingDown then
			data.arrivalVelocity = flightVelocity
		end

		-- A turn leg ends on its frame and goes straight into what follows, still at dive speed.
		-- (It used to be stopped here and wait for the next 10 Hz update to start the dive: the
		-- body hung at zero speed in between, or kept the leg's speed when the update came first.)
		if (data.phase == "Strafe" or data.phase == "ComboStrafe") and tick() - data.phaseTime >= data.legDuration then
			if data.phase == "ComboStrafe" then
				data.comboIndex += 1
				comboNext(data, humanoid, rootPart, lv)
			else
				startFinalDive(data, humanoid, rootPart, lv)
			end
		end

		-- The swoop follows its curve at one speed. (It was timed by an ease curve, fast - slow -
		-- fast: measured 1280 studs/s off the top, about 100 through the middle, 600 at the end.)
		if data.phase == "Dash" and data.curveT then
			local tangent = curveTangent(data, data.curveT)
			if tangent.Magnitude > 0.001 then
				data.curveT = math.min(1, data.curveT + data.curveSpeed * dt / tangent.Magnitude)
				local pull = (curvePoint(data, data.curveT) - rootPart.Position) * CURVE_PULL
				lv.MaxAxesForce = FULL_FORCE
				lv.VectorVelocity = (tangent.Unit * data.curveSpeed + pull).Unit * data.curveSpeed
			end
		end

		-- The intercept is steered every frame: at 480 studs/s a 10 Hz re-aim moved it ~50 studs
		-- between corrections, more than the contact distance, so it flew past the jumper.
		-- On contact it holds there and the next update starts the clash.
		if data.phase == "Intercept" and not data.interceptContact then
			local enemyRoot = data.target and data.target:FindFirstChild("HumanoidRootPart")
			if enemyRoot then
				local gap = enemyRoot.Position - rootPart.Position
				if gap.Magnitude <= (CombatConfig.Intercept_ContactDistance or 15) then
					data.interceptContact = true
					lv.MaxAxesForce = Vector3.new(math.huge, math.huge, math.huge)
					lv.VectorVelocity = Vector3.zero
				else
					local speed = data.interceptSpeed or Config.SlamSpeed
					local lead = math.clamp(gap.Magnitude / speed, 0, 0.5)
					local offset = enemyRoot.Position + enemyRoot.AssemblyLinearVelocity * lead - rootPart.Position
					if offset.Magnitude > 0.001 then
						lv.MaxAxesForce = Vector3.new(math.huge, math.huge, math.huge)
						lv.VectorVelocity = offset.Unit * speed
					end
				end
			end
		end

		-- Hold the flight inside the arena (both the ballistic drift and the mover's target)
		rootPart.AssemblyLinearVelocity = containVelocity(rootPart.Position, rootPart.AssemblyLinearVelocity)
		if lv.MaxAxesForce.X > 0 then
			lv.VectorVelocity = containVelocity(rootPart.Position, lv.VectorVelocity)
		end

		-- The body faces along its flight (it used to only turn about the vertical, staying
		-- upright whatever the path): the upright launch and airborne clips tilt forward into a
		-- climb; the dive (flying clip, a horizontal pose) points head first along the path and
		-- flares back upright over the last ~25 studs so it lands on its feet.
		local flightVel = rootPart.AssemblyLinearVelocity
		local flatFlight = Vector3.new(flightVel.X, 0, flightVel.Z)
		if flightVel.Magnitude > 15 and not data.settingDown then
			local bodyLook = rootPart.CFrame.LookVector
			local flatDir = flatFlight.Magnitude > 1 and flatFlight.Unit
				or (Vector3.new(bodyLook.X, 0, bodyLook.Z).Magnitude > 0.01 and Vector3.new(bodyLook.X, 0, bodyLook.Z).Unit)
				or Vector3.new(0, 0, -1)
			local look
			if DIVE_PHASES[data.phase] then
				local gap = heightAboveStand(rootPart, humanoid)
				local headFirst = math.clamp((gap - 6) / 25, 0, 1)
				look = flatDir:Lerp(flightVel.Unit, headFirst)
			else
				local elevation = math.atan2(flightVel.Y, math.max(flatFlight.Magnitude, 0.001))
				local tilt = elevation > 0 and math.clamp(math.pi / 2 - elevation, 0, 0.6) or 0.2
				look = flatDir * math.cos(tilt) - Vector3.yAxis * math.sin(tilt)
			end
			if look.Magnitude > 0.01 then
				ao.CFrame = CFrame.lookAt(rootPart.Position, rootPart.Position + look)
			end
		end

		-- Smack-down timing: the clip's flight part ends exactly at touchdown, whatever the arc
		if data.smackDown and data.animTrack and data.animTrack.IsPlaying and data.phase ~= "Init" then
			local track = data.animTrack
			if track.Length > 0 and track.TimePosition < SMACK_TAKEOFF - 0.05 then
				track.TimePosition = SMACK_TAKEOFF -- the asset was still loading at launch
			end
			local gap = heightAboveStand(rootPart, humanoid)
			local vy = rootPart.AssemblyLinearVelocity.Y
			local g = workspace.Gravity
			local toLand = gap < math.huge and (vy + math.sqrt(math.max(vy * vy + 2 * g * math.max(gap, 0), 0))) / g or 1
			local left = SMACK_LANDING - track.TimePosition
			track:AdjustSpeed(left > 0.02 and math.clamp(left / math.max(toLand, 0.05), 0.15, 2.5) or 0)
		end

		-- Touchdown: the body used to hit the floor first and lie sliding on it until the next
		-- update noticed. On contact the mover is held still and Impact follows.
		local fallSpeed = -rootPart.AssemblyLinearVelocity.Y
		if setDownSnapOn() then
			-- Set-down snap: once the floor is within the next frame's travel the body is placed
			-- on it at standing height and touchdown is taken there and then. Velocity set-downs
			-- ("cover exactly the rest of the way") overshot whenever the next physics frame ran
			-- longer than the last, and a 10 Hz update could re-apply slam speed on the same frame:
			-- the body punched 2-7 studs into the floor and the Humanoid sprang it back up (the
			-- dive "bob"). The jump is at most one frame of travel, unseen at these speeds.
			if fallSpeed >= 20 and data.phase ~= "Init" then
				local vel = rootPart.AssemblyLinearVelocity
				local standOffset = (humanoid.HipHeight or 2.0) + rootPart.Size.Y / 2
				local standPos
				-- A floor rising into the path (a low dive crossing onto a platform): the straight-down
				-- probe only sees it once the body is inside it, so the feet probe along the flight too
				local params = RaycastParams.new()
				params.FilterType = Enum.RaycastFilterType.Exclude
				params.FilterDescendantsInstances = { fighter, Workspace:FindFirstChild("QuinServer") }
				params.RespectCanCollide = true
				local feet = rootPart.Position - Vector3.new(0, standOffset, 0)
				local hit = Workspace:Raycast(feet, vel * dt * 1.5, params)
				if hit and hit.Normal.Y > 0.5 then
					standPos = hit.Position + Vector3.new(0, standOffset, 0)
				else
					local gap = heightAboveStand(rootPart, humanoid)
					if gap <= math.max(fallSpeed * dt * 1.5, 1.0) then
						standPos = rootPart.Position - Vector3.new(0, gap, 0)
					end
				end
				if standPos then
					rootPart.CFrame = rootPart.CFrame.Rotation + standPos
					rootPart.AssemblyLinearVelocity = Vector3.zero
					lv.MaxAxesForce = Vector3.new(math.huge, math.huge, math.huge)
					lv.VectorVelocity = Vector3.zero
					data.touchedDown = true
				end
			end
			return
		end
		local latched = setDownLatched(data)
		if fallSpeed >= 20 or latched then
			local gap = heightAboveStand(rootPart, humanoid)
			if gap <= 1.0 then
				data.touchedDown = true
				lv.MaxAxesForce = Vector3.new(math.huge, math.huge, math.huge)
				lv.VectorVelocity = Vector3.zero
			elseif gap <= fallSpeed * dt * 1.5 or latched then
				-- The floor is within the next frame's travel: cover exactly the rest of the way
				-- (stopping here left a fast dive hanging up to a dozen studs in the air)
				lv.MaxAxesForce = Vector3.new(math.huge, math.huge, math.huge)
				lv.VectorVelocity = Vector3.new(0, -gap / math.max(dt, 1 / 240), 0)
				if not data.settingDown then
					data.settingDownAt = os.clock()
				end
				data.settingDown = true
			end
		end
	end)
end

function ProjectileJumpState.exit(fighter, humanoid, rootPart)
	rootPart.AssemblyLinearVelocity = Vector3.zero
	rootPart.AssemblyAngularVelocity = Vector3.zero
	humanoid.PlatformStand = false
	cleanupMovers(rootPart)
	local exiting = stateData[fighter]
	if exiting then
		if exiting.precise and exiting.target then
			exiting.target:Destroy()
		end
		if exiting.guardConn then exiting.guardConn:Disconnect() end
		stopAnim(exiting.animTrack)
	end
	fighter:SetAttribute("LastProjectileJumpTime", tick())
	fighter:SetAttribute("JumpStyle", nil)
	fighter:SetAttribute("PJPhase", nil)
	stateData[fighter] = nil
end

function ProjectileJumpState.update(fighter, humanoid, rootPart, DEBUG)
	local data = stateData[fighter]
	if not data then return require(script.Parent:WaitForChild("IdleState")) end

	local target = data.target
	if not target then
		return require(script.Parent:WaitForChild("FightState"))
	end
	local targetPosPart = target:FindFirstChild("HumanoidRootPart") or target.PrimaryPart or target:FindFirstChildWhichIsA("BasePart")
	if not targetPosPart then
		return require(script.Parent:WaitForChild("FightState"))
	end

	local targetPos = targetPosPart.Position
	local now = tick()
	local timeInPhase = now - data.phaseTime

	local lv = rootPart:FindFirstChild("PJ_LinearVelocity") or rootPart:FindFirstChild("PJ_Velocity")
	local ao = rootPart:FindFirstChild("PJ_Align") or rootPart:FindFirstChild("PJ_Gyro")
	if not lv or not ao then return require(script.Parent:WaitForChild("FightState")) end

	-- After the launch clip: the kit's airborne loop until the dive (or the landing) takes over
	if data.kit and not data.inAirLoop and not data.diving and data.phase ~= "Impact" then
		local launch = data.animTrack
		if not launch or not launch.IsPlaying or (launch.Length > 0 and launch.TimePosition >= launch.Length * 0.92) then
			data.inAirLoop = true
			data.animTrack = playClip(humanoid, data.kit.loop, true)
		end
	end

	if not data.lastNodePos or (rootPart.Position - data.lastNodePos).Magnitude > 5 then
		spawnVisualizerNode(rootPart.Position)
		data.lastNodePos = rootPart.Position
	end

	local distToTarget = (targetPos - rootPart.Position).Magnitude
	local gravity = workspace.Gravity
	local standGap = heightAboveStand(rootPart, humanoid) -- height above standing level on the floor below

	-- Stall guard and hard cap: a driven phase that has stopped moving (caught on an edge or an
	-- overhang the probes missed), or a jump that has run far too long, comes down now
	if data.phase ~= "Impact" and data.phase ~= "Init" then
		local stallTime = CombatConfig.ProjectileJump_StallTime or 0.4
		data.trail = data.trail or {}
		table.insert(data.trail, { now, rootPart.Position })
		while #data.trail > 1 and now - data.trail[1][1] > stallTime do
			table.remove(data.trail, 1)
		end
		local driven = data.phase == "Dash" or data.phase == "Arcing" or data.phase == "Strafe"
			or data.phase == "ComboStrafe" or data.phase == "Intercept"
		local oldest = data.trail[1]
		local stalled = driven and timeInPhase > stallTime and now - oldest[1] >= stallTime * 0.75
			and (rootPart.Position - oldest[2]).Magnitude < (CombatConfig.ProjectileJump_StallDistance or 1.5)
		local overtime = now - data.startTime > (CombatConfig.ProjectileJump_MaxStateTime or 8)
		if (stalled or overtime) and not (data.phase == "Intercept" and data.interceptContact) then
			fighter:SetAttribute("PJGuard", stalled and "Stalled" or "Overtime")
			switchPhase(data, "Impact")
		end
	end

	if data.touchedDown and data.phase ~= "Impact" then
		switchPhase(data, "Impact")
	end
	if setDownLatched(data) then
		return ProjectileJumpState -- the guard is setting the body down this frame (see setDownLatched)
	end


	local speedMult = workspace:GetAttribute("GameSpeedMultiplier") or 1.0

	-- Two jumpers that come together in the air clash there, whatever phase either is in.
	-- (Checked only at impact, a clash needed the target to still be airborne when the jump
	-- ended: it practically never happened.)
	if data.phase ~= "Init" and not data.precise and standGap >= (CombatConfig.MidAirClash_MinHeight or 12)
		and target:GetAttribute("CurrentState") == "ProjectileJump"
		and distToTarget <= (CombatConfig.MidAirClash_TriggerDistance or 40) then
		fighter:SetAttribute("ClashWith", target.Name)
		return require(script.Parent:WaitForChild("MidAirClashState"))
	end

	if data.phase == "Init" then
		if data.style == 1 then
			-- The arc is not steered after launch, so it is thrown at where a moving target will
			-- be when it comes down (one pass: flight time from the present distance)
			if not data.precise then
				local targetVelocity = targetPosPart.AssemblyLinearVelocity
				local flatGap = Vector3.new(targetPos.X - rootPart.Position.X, 0, targetPos.Z - rootPart.Position.Z).Magnitude
				local flightGuess = flatGap / (math.clamp(flatGap / 1.8, 120, 260) * speedMult)
				targetPos += Vector3.new(targetVelocity.X, 0, targetVelocity.Z) * flightGuess
				-- A target in the air (an interception): where it will be up there. Rising or
				-- falling freely it follows gravity; diving it keeps its speed. Never below
				-- the jumper's own level.
				local targetHumanoid = target:FindFirstChildOfClass("Humanoid")
				if targetHumanoid and targetHumanoid.PlatformStand then
					local drop = targetVelocity.Y > -80 and 0.5 * gravity * flightGuess ^ 2 or 0
					local predictedY = targetPos.Y + targetVelocity.Y * flightGuess - drop
					targetPos = Vector3.new(targetPos.X, math.max(predictedY, rootPart.Position.Y), targetPos.Z)
				end
			end
			local dir = (targetPos - rootPart.Position)
			dir = Vector3.new(dir.X, 0, dir.Z)
			local dist = dir.Magnitude

			do
				local arcSpeed = math.clamp(dist / 1.8, 120, 260) * speedMult
				local timeToTarget = math.max(0.05, dist / arcSpeed)
				-- A hop onto a spot close by flew at the arc's 120 studs/s floor (a 12-stud hop
				-- in a tenth of a second): it takes a jump's time instead
				if data.precise then
					timeToTarget = math.max(timeToTarget, 0.35 + dist / 90)
					arcSpeed = dist / timeToTarget
				end
				-- A target above the jumper is reached on the way down: the flight has to last
				-- longer than the rise alone, or the arc goes up through the platform it stands on
				local rise = targetPos.Y - rootPart.Position.Y
				if rise > 0 then
					timeToTarget = math.max(timeToTarget, math.sqrt(2 * rise / gravity) * 1.35 + 0.2)
					arcSpeed = dist / timeToTarget
				end
				local requiredY = (targetPos.Y - rootPart.Position.Y + 0.5 * gravity * timeToTarget^2) / timeToTarget
				lv.MaxAxesForce = Vector3.new(math.huge, 0, math.huge)
				local safeDir = dist > 0.001 and dir.Unit or Vector3.new(1,0,0) -- PREVENT NAN
				lv.VectorVelocity = safeDir * arcSpeed
				rootPart.AssemblyLinearVelocity = Vector3.new(0, requiredY, 0)

			end

			VfxModule.createRocketTrail(rootPart)
			VfxModule.createLaunchShockwave(rootPart)
			VfxModule.shakeScreen(rootPart.Position, 500, 8)

			switchPhase(data, "Arcing")

		elseif data.style == INTERCEPT_STYLE then
			VfxModule.createRocketTrail(rootPart)
			VfxModule.createLaunchShockwave(rootPart)
			VfxModule.shakeScreen(rootPart.Position, 500, 8)
			AudioModule.playSonicBoom(rootPart.Position)
			data.interceptSpeed = Config.SlamSpeed * speedMult
			switchPhase(data, "Intercept")

		elseif data.style == 6 then
			local combos
			if math.random() > 0.5 then
				combos = {"Jump", "Jump", "Strafe", "Strafe", "Dash"}
			else
				combos = {"Jump", "Strafe", "Jump", "Strafe", "Dash"}
			end
			data.comboSequence = combos
			data.comboIndex = 1
			comboNext(data, humanoid, rootPart, lv)

		else
			local jumpPower
			if data.style == 3 then
				jumpPower = math.random(Config.MultiJumpPowerMin, Config.MultiJumpPowerMax)
				data.multiJumpGapTime = getFloat(Config.MultiJumpGapTimeMin, Config.MultiJumpGapTimeMax)
				data.multiJumpDashTime = getFloat(Config.MultiJumpDashTimeMin, Config.MultiJumpDashTimeMax)
			else
				jumpPower = math.random(Config.JumpPowerMin, Config.JumpPowerMax)
			end

			local yDiff = targetPos.Y - rootPart.Position.Y
			local discriminant = jumpPower^2 - 2 * gravity * yDiff
			local timeOfFlight = 1
			if discriminant > 0 then
				timeOfFlight = (jumpPower + math.sqrt(discriminant)) / gravity
			end

			data.jumpTime = timeOfFlight

			if data.style == 3 then
				data.dashExactTime = data.multiJumpGapTime + data.multiJumpDashTime
			else
				local dashExec = getFloat(Config.DashExecuteTimeMin, Config.DashExecuteTimeMax)
				data.dashExactTime = math.min(dashExec, timeOfFlight - 0.2)
			end

			lv.MaxAxesForce = Vector3.zero
			local forwardVec = rootPart.CFrame.LookVector
			local rightVec = rootPart.CFrame.RightVector
			local forwardSpeed, sideSpeed
			if data.style == 3 then
				forwardSpeed = math.random(Config.MultiJumpForwardSpeedMin, Config.MultiJumpForwardSpeedMax)
				sideSpeed = math.random(Config.MultiJumpSideSpeedMin, Config.MultiJumpSideSpeedMax)
			else
				forwardSpeed = math.random(30, 60)
				sideSpeed = math.random(-40, 40)
			end
			local driftVelocity = (forwardVec * forwardSpeed) + (rightVec * sideSpeed)
			rootPart.AssemblyLinearVelocity = Vector3.new(driftVelocity.X, jumpPower, driftVelocity.Z)

			VfxModule.createRocketTrail(rootPart)
			VfxModule.createLaunchShockwave(rootPart)
			VfxModule.shakeScreen(rootPart.Position, 500, 8) 
			switchPhase(data, "AirborneTimer")
		end

	elseif data.phase == "Intercept" then
		-- A straight line at where the airborne enemy will be, steered every frame by the guard
		-- in enter. Contact starts a mid-air clash with it whatever it is doing up there (a
		-- jumper, a Quin thrown up by a hit); MidAirClashState decides how it ends.
		local targetHumanoid = target:FindFirstChildOfClass("Humanoid")
		local targetAirborne = targetHumanoid ~= nil and targetHumanoid.Health > 0
			and (targetHumanoid.PlatformStand or targetHumanoid.FloorMaterial == Enum.Material.Air)
		local targetClashing = target:GetAttribute("CurrentState") == "MidAirClash"
		if data.interceptContact and targetAirborne and not targetClashing then
			fighter:SetAttribute("ClashWith", target.Name)
			fighter:SetAttribute("InterceptHits", (fighter:GetAttribute("InterceptHits") or 0) + 1)
			return require(script.Parent:WaitForChild("MidAirClashState"))
		-- (below the interceptor it is coming down past it: the line would point at the floor)
		elseif not targetAirborne or targetClashing or timeInPhase > INTERCEPT_TIMEOUT
			or targetPos.Y < rootPart.Position.Y - 5 then
			-- It came down (or got away): dive on it like any other jump
			data.interceptContact = false
			data.style = 2
			data.dashExactTime = 0
			switchPhase(data, "AirborneTimer")
		end

	elseif data.phase == "Arcing" then
		if rootPart.AssemblyLinearVelocity.Magnitude > 1 then
			local lookDir = rootPart.AssemblyLinearVelocity
			local flatLook = Vector3.new(lookDir.X, 0, lookDir.Z)
			if flatLook.Magnitude > 0.5 then
				ao.CFrame = CFrame.lookAt(rootPart.Position, rootPart.Position + flatLook)
			end
		end

		local isFalling = rootPart.AssemblyLinearVelocity.Y <= 0
		local isNearGround = standGap <= 2
		local reachedTarget = distToTarget < (data.precise and 5 or 15)
		if reachedTarget or (timeInPhase > 0.25 and isFalling and isNearGround) then
			switchPhase(data, "Impact")
		end

	elseif data.phase == "ComboWait" then
		if timeInPhase >= data.comboGapTime then
			data.comboIndex = data.comboIndex + 1
			comboNext(data, humanoid, rootPart, lv)
		end

		if distToTarget < 15 or (standGap <= 2 and rootPart.AssemblyLinearVelocity.Y < 0) then
			switchPhase(data, "Impact")
		end

	elseif data.phase == "AirborneTimer" then
		local timeSinceJump = now - data.startTime
		local heightAboveTarget = rootPart.Position.Y - targetPos.Y
		local isFalling = rootPart.AssemblyLinearVelocity.Y < 0

		if data.style == 3 and data.jumpCount < 2 and timeSinceJump >= data.multiJumpGapTime then
			data.jumpCount = 2
			local midAirJumpPower = math.random(Config.MultiJumpPowerMin, Config.MultiJumpPowerMax)

			local forwardVec = rootPart.CFrame.LookVector
			local rightVec = rootPart.CFrame.RightVector
			local forwardSpeed = math.random(Config.MultiJumpForwardSpeedMin, Config.MultiJumpForwardSpeedMax)
			local sideSpeed = math.random(Config.MultiJumpSideSpeedMin, Config.MultiJumpSideSpeedMax)
			local driftVelocity = (forwardVec * forwardSpeed) + (rightVec * sideSpeed)

			rootPart.AssemblyLinearVelocity = Vector3.new(driftVelocity.X, midAirJumpPower, driftVelocity.Z)
			AudioModule.playJumpUp(rootPart.Position)
			VfxModule.createLaunchShockwave(rootPart)
		end

		if timeSinceJump >= data.dashExactTime or (isFalling and heightAboveTarget <= 60) then
			if data.style == 4 then
				startTurnLeg(data, humanoid, rootPart, lv, "Strafe")
			elseif data.style == 5 then
				-- Pre-calculate Bezier with combat offset landing point
				data.P0 = rootPart.Position
				data.P2 = calculateCombatAimPoint(rootPart, targetPosPart, Config.SlamSpeed * speedMult, humanoid, data.scatterAngle, data.precise)

				local arcHeight = Config.BezierArcHeightBase
				local lowestY = calculateLowestY(data.P0.Y, data.P2.Y, arcHeight)
				if lowestY < 0 then
					arcHeight = math.max(0, arcHeight - math.abs(lowestY))
				end

				local midPoint = (data.P0 + data.P2) / 2
				local dirXZ = Vector3.new(data.P2.X - data.P0.X, 0, data.P2.Z - data.P0.Z).Unit
				if dirXZ.Magnitude == 0 then dirXZ = Vector3.new(1,0,0) end
				local rightDir = Vector3.new(dirXZ.Z, 0, -dirXZ.X) -- Perpendicular

				local latBend = Config.BezierLateralBendBase * (math.random() > 0.5 and 1 or -1)
				data.P1 = midPoint + Vector3.new(0, arcHeight, 0) + (rightDir * latBend)

				if not isCurveSafe(data.P0, data.P1, data.P2, fighter, target) then
					latBend = latBend * -1
					data.P1 = midPoint + Vector3.new(0, arcHeight, 0) + (rightDir * latBend)
					if not isCurveSafe(data.P0, data.P1, data.P2, fighter, target) then
						data.P1 = midPoint + Vector3.new(0, arcHeight, 0)
					end
				end

				data.curveT = 0
				data.curveSpeed = diveSpeed(data)
				setDive(data, humanoid, rootPart, lv, curveTangent(data, 0).Unit * data.curveSpeed, "Dash")
			else
				startFinalDive(data, humanoid, rootPart, lv)
			end
			return ProjectileJumpState
		end

		if distToTarget < 15 or (standGap <= 2 and rootPart.AssemblyLinearVelocity.Y < 0) then
			switchPhase(data, "Impact")
		end

	elseif data.phase == "Dash" then
		if data.curveT then
			-- The swoop (steered every frame by the guard in enter). A wall in its path ends it
			-- here, like the straight dive below; floors are the touchdown guard's.
			local rayParams = RaycastParams.new()
			rayParams.FilterType = Enum.RaycastFilterType.Exclude
			rayParams.FilterDescendantsInstances = {fighter, target}
			local ahead = lv.VectorVelocity * (CombatConfig.ProjectileJump_DashWallProbeTime or 0.15)
			local hit = ahead.Magnitude > 0.01 and DebugDraw.raycast(rootPart, rootPart.Position, ahead, rayParams)
			if hit and math.abs(hit.Normal.Y) < 0.5 then
				data.wallNormal = hit.Normal
				switchPhase(data, "Impact")
				return ProjectileJumpState
			end

			if data.curveT >= 1 or distToTarget < 15 or (data.curveT > 0.4 and standGap <= 2) then
				switchPhase(data, "Impact")
			end

		else
			lv.MaxAxesForce = Vector3.new(math.huge, math.huge, math.huge)
			local dashSpeed = diveSpeed(data)
			local aimPoint, approachDir, groundY = calculateCombatAimPoint(rootPart, targetPosPart, dashSpeed, humanoid, data.scatterAngle, data.precise)
			local offset = aimPoint - rootPart.Position
			local dir = diveDirection(offset, rootPart.CFrame.LookVector)
			-- A wall in the dive line ends the dive here (Impact drops the body down beside it).
			-- With no check the mover pressed the body into the wall face with unlimited force:
			-- it never reached its aim nor the ground, and hung on the wall.
			local wallParams = RaycastParams.new()
			wallParams.FilterType = Enum.RaycastFilterType.Exclude
			wallParams.FilterDescendantsInstances = { fighter, target }
			local probe = dashSpeed * (CombatConfig.ProjectileJump_DashWallProbeTime or 0.15) + 2
			local wallHit = DebugDraw.raycast(rootPart, rootPart.Position, dir * probe, wallParams)
			if wallHit and math.abs(wallHit.Normal.Y) < 0.5 then
				data.wallNormal = wallHit.Normal
				switchPhase(data, "Impact")
				return ProjectileJumpState
			end
			lv.VectorVelocity = dir * dashSpeed
			-- (the body's facing in a dive is the per-frame guard's, head first along the path)

			local isFalling = rootPart.AssemblyLinearVelocity.Y <= 0
			local isNearGround = standGap <= 2.5
			local reachedAim = offset.Magnitude < 10
			if reachedAim or (timeInPhase > 0.12 and isFalling and isNearGround) then
				switchPhase(data, "Impact")
			end
		end

	elseif data.phase == "Impact" then

		-- Detect MidAir Clash
		local targetState = target:GetAttribute("CurrentState")
		-- (a target standing on a high platform is not in the air: this used to test its height
		-- above the world origin, so reaching a Quin on a platform started an air brawl)
		-- (a target already clashing with someone else is not joined: three-way clashes)
		if not data.precise and (targetState == "ProjectileJump" or targetState == "Airborne") and distToTarget <= 35 then
			fighter:SetAttribute("ClashWith", target.Name)
			return require(script.Parent:WaitForChild("MidAirClashState"))
		end

		-- Impact reached while still airborne (target within reach, path blocked): drop the rest
		-- of the way at slam speed. The per-frame watcher stops the body at the floor; placing
		-- it there directly was a visible snap of up to ~30 studs.
		if not data.touchedDown and standGap > 3 and standGap < math.huge then
			lv.MaxAxesForce = Vector3.new(math.huge, math.huge, math.huge)
			-- (a dive stopped by a wall eases off it on the way down instead of dragging on the face)
			local offWall = data.wallNormal and Vector3.new(data.wallNormal.X, 0, data.wallNormal.Z) * 6 or Vector3.zero
			-- (capped so one 60 Hz frame never carries it past the floor: from ~8 studs up a full
			-- slam-speed frame travelled 9 and sank the body into the ground)
			local dropSpeed = math.min(Config.SlamSpeed * Config.SlamSpeedMultiplier, standGap * 60)
			lv.VectorVelocity = Vector3.new(0, -dropSpeed, 0) + offWall
			return ProjectileJumpState
		end

		-- STOP all mover forces immediately
		cleanupMovers(rootPart)
		rootPart.AssemblyLinearVelocity = Vector3.zero
		rootPart.AssemblyAngularVelocity = Vector3.zero

		-- 1. Firmly plant feet on the floor below (never floating, never skull stacking). The old
		-- 25-stud probe missed the floor from higher up and fell back to the target's height,
		-- which teleported a jumper that reached Impact in the air straight down to it.
		local finalY = rootPart.Position.Y
		if standGap < math.huge then
			finalY = rootPart.Position.Y - standGap
		elseif targetPosPart then
			finalY = targetPosPart.Position.Y
		end

		-- 2. Spatial de-penetration: ensure clean 4.5 studs combat separation
		local targetHRP = target:FindFirstChild("HumanoidRootPart")
		local jumperPos = Vector3.new(rootPart.Position.X, finalY, rootPart.Position.Z)
		if targetHRP then
			local flatDiff = Vector3.new(jumperPos.X - targetHRP.Position.X, 0, jumperPos.Z - targetHRP.Position.Z)
			local flatDist = flatDiff.Magnitude
			
			if flatDist < 4.0 then
				-- Jumper is too close / overlapping: resolve along approach angle to 4.5 studs
				local pushDir = flatDist > 0.01 and flatDiff.Unit or -targetHRP.CFrame.LookVector
				jumperPos = Vector3.new(targetHRP.Position.X + pushDir.X * 4.5, finalY, targetHRP.Position.Z + pushDir.Z * 4.5)
				-- Apply light arrival wind-pressure micro-push on target (4 studs)
				KnockbackModule.applyMicroKnockback(target, -pushDir, 4.0)
			end
			
			-- 3. Eye-to-eye alignment: both face each other horizontally
			rootPart.CFrame = CFrame.lookAt(jumperPos, Vector3.new(targetHRP.Position.X, finalY, targetHRP.Position.Z))
			-- The target is not rotated from here any more: writing its CFrame from another Quin's
			-- state flipped it up to 180 degrees in one frame, whatever it was doing (mid-swing,
			-- knocked down, airborne). Its own state turns it to face the new threat.
		else
			rootPart.CFrame = CFrame.new(jumperPos)
		end

		-- 3b. Landing slide: the horizontal part of the arrival speed carries the body on along
		-- the ground and friction brings it to a stop (a vertical dive stops dead, a shallow one
		-- skids). Never into the target it landed in front of, and barely on a chosen spot.
		local arrival = data.arrivalVelocity
		local flatArrival = arrival and Vector3.new(arrival.X, 0, arrival.Z) or Vector3.zero
		if flatArrival.Magnitude > 1 then
			local slideDir = flatArrival.Unit
			local slideDistance = math.min(flatArrival.Magnitude * (CombatConfig.ProjectileJump_LandingSlideFactor or 0.03),
				data.precise and (CombatConfig.ProjectileJump_LandingSlidePreciseMax or 2) or (CombatConfig.ProjectileJump_LandingSlideMax or 14))
			if targetHRP then
				local toTarget = Vector3.new(targetHRP.Position.X - jumperPos.X, 0, targetHRP.Position.Z - jumperPos.Z)
				if toTarget.Magnitude > 0.1 and slideDir:Dot(toTarget.Unit) > 0.5 then
					slideDistance = math.min(slideDistance, math.max(toTarget.Magnitude - 4.5, 0))
				end
			end
			if slideDistance >= 1 then
				local slideDuration = CombatConfig.ProjectileJump_LandingSlideDuration or 0.5
				KnockbackModule.applySlide(fighter, slideDir, ImpulseModule.speedForDistance(slideDistance, slideDuration, "friction", 0.05),
					slideDuration, { friction = true, endRatio = 0.05 })
				VfxModule.createGroundMark(rootPart, slideDir, slideDistance, 1.2, 3)
				local smoke = VfxModule.createSlideSmoke(rootPart)
				-- The client lays the body back against the slide while this is set
				fighter:SetAttribute("LandingSlide", true)
				task.delay(slideDuration, function()
					VfxModule.stopSlideSmoke(smoke)
					if fighter.Parent then fighter:SetAttribute("LandingSlide", nil) end
				end)
			end
		end

		-- 4. Clean foot-strike audio and subtle ground dust (no generic explosions)
		AudioModule.playFallOnGround(rootPart.Position)
		AudioModule.playSlam(rootPart.Position)
		-- Ground impact: crack, dust and earth clods (no debris parts or neon ring); a hop onto a
		-- spot only kicks up a little dust
		local elem = fighter:GetAttribute("Element") or "Fire"
		local arrivalSpeed = data.arrivalVelocity and data.arrivalVelocity.Magnitude or 200
		local impactStrength = data.precise and 0.3 or math.clamp(arrivalSpeed / 250, 0.55, 1)
		VfxModule.createLandingImpact(jumperPos, impactStrength, elem)
		if not data.precise then
			VfxModule.shakeScreen(rootPart.Position, 400, 8)
		end

		-- 5. Slam Shockwave & Target Stumble (Phase 5.2)
		-- (a hop onto a spot is not a slam: no shockwave)
		local shockRadius = data.precise and 0 or (CombatConfig.SlamShockwaveRadius or CombatConfig.SlamImpactRadius or 14)
		local stumbleForce = CombatConfig.SlamStumbleForce or 90
		local stumbleDuration = CombatConfig.SlamStumbleDuration or 0.35
		for _, other in ipairs(CollectionService:GetTagged("Quin")) do
			if other ~= fighter and other.Parent then
				local oHRP = other:FindFirstChild("HumanoidRootPart")
				local oHum = other:FindFirstChildOfClass("Humanoid")
				if oHRP and oHum and oHum.Health > 0 then
					local oDist = (oHRP.Position - jumperPos).Magnitude
					if oDist <= shockRadius then
						local awayDir = oHRP.Position - jumperPos
						if awayDir.Magnitude < 0.01 then
							awayDir = -rootPart.CFrame.LookVector
						else
							awayDir = awayDir.Unit
						end
						local falloff = 1 - (oDist / shockRadius)
						KnockbackModule.applyGroundKnockback(other, awayDir, stumbleForce * (0.5 + 0.5 * falloff), stumbleDuration)
						other:SetAttribute("ImpactTime", workspace:GetServerTimeNow())
						other:SetAttribute("ImpactDir", awayDir)
						other:SetAttribute("ImpactMag", math.clamp(0.4 + 0.6 * falloff, 0.3, 1.0))
						other:SetAttribute("ImpactType", "SLAM")
						local oState = other:GetAttribute("CurrentState")
						if oState ~= "Knockback" and oState ~= "Death" and oState ~= "Airborne" then
							other:SetAttribute("ForceState", "Knockback")
							other:SetAttribute("KnockbackType", "ground")
						end
					end
				end
			end
		end

		-- 6. Route into dedicated slam recovery pipeline (Phase 5.1)
		if data.smackDown and data.animTrack and data.animTrack.IsPlaying then
			-- The smack-down's own landing carries on (RecoveryState waits for it)
			local track = data.animTrack
			if track.TimePosition < SMACK_LANDING then
				track.TimePosition = SMACK_LANDING
			end
			track:AdjustSpeed(1)
			fighter:SetAttribute("LandingClipPath", SMACK_PATH)
			fighter:SetAttribute("LandingClipRemaining", math.max(track.Length - track.TimePosition, 0.3))
			data.animTrack = nil -- not stopped by exit
		else
			stopAnim(data.animTrack)
		end
		AnimationModule.stop(humanoid, AnimationIds.Dash, 0.05)
		fighter:SetAttribute("KnockbackType", data.precise and "traversal_landing" or "slam_landing")

		return require(script.Parent:WaitForChild("RecoveryState"))
	end

	return ProjectileJumpState
end

return ProjectileJumpState
