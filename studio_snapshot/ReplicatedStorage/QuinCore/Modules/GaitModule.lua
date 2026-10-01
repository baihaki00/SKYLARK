--// GaitModule.lua
-- Tier 1 base locomotion for every Quin (player pilot and AI alike).
--
-- 1. Ground gait: a synchronized 1D blend space over Walk -> Jog -> Run driven by the
--    Quin's real planar velocity. Each clip has a measured authored ground speed (how
--    fast its planted foot travels at 1.0x) and a measured left-foot plant phase. The
--    group advances one canonical phase (0 = left foot plant) at
--        cadence = speed / sum(weight_i * strideDistance_i)
--    and every clip plays at cadence * clipLength, aligned to its own plant phase, so
--    the three clips land the same foot together and the feet do not skate.
-- 2. Ground contract: ground loops never play while the Quin is jumping or falling.
--    Once airborne past a short grace period the ground loops are released and the
--    Fall pose covers the body until landing.
-- 3. Lifetime contract: the gait is state-governed (README Tier 1). If no driver has
--    updated it for GAIT_ORPHAN_TIME (the state stopped moving the Quin), the loops are
--    released to the idle floor instead of running in place.
-- 4. Base-layer fill: whenever the body moves on the ground under its own drive and no
--    other Movement-priority clip owns the legs, the gait follows real velocity regardless
--    of which state is active. States add overlays on top; they never leave the base layer
--    empty, so a moving Quin never shows the idle pose (no shuffling).
-- Single Source of Truth for tuning: ReplicatedStorage.QuinCore.CombatConfig (Gait_*)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local QuinCore = ReplicatedStorage:WaitForChild("QuinCore")
local CombatConfig = require(QuinCore:WaitForChild("CombatConfig"))
local AnimationConfig = require(QuinCore:WaitForChild("AnimationConfig"))
local AnimationModule = require(QuinCore:WaitForChild("Modules"):WaitForChild("AnimationModule"))

local GaitModule = {}

local FALL_PATH = "Movement.Fall"

-- Blend-space clips in ascending speed order
local CLIPS = {
	{ path = "Movement.WalkConfident", speedKey = "Gait_WalkAuthoredSpeed", speed = 6.90, plantKey = "Gait_WalkPlantPhase", plant = 0.31 },
	{ path = "Movement.Jog", speedKey = "Gait_JogAuthoredSpeed", speed = 9.03, plantKey = "Gait_JogPlantPhase", plant = 0.34 },
	{ path = "Movement.Run", speedKey = "Gait_RunAuthoredSpeed", speed = 29.9, plantKey = "Gait_RunPlantPhase", plant = 0.46 },
}

local RATE_DEADBAND = 0.015
local WEIGHT_DEADBAND = 0.02
local PHASE_TOLERANCE = 0.06
local START_FADE = 0.15
local AIR_GRACE = 0.12 -- seconds airborne before ground loops are released (ignores tiny hops)
local GAIT_ORPHAN_TIME = 0.35 -- seconds without a driver before the gait is released
local LAUNCH_WINDOW = 0.3 -- after a deliberate jump the Humanoid can still read Running for a frame or two
local AUTO_DRIVE_INTERVAL = 0.05 -- base-layer fill rate (20 Hz per Quin)
local AUTO_DRIVE_MIN_SPEED = 1.5 -- studs/s of planar motion before the base layer is filled
local SPEED_FOLLOW_RATE = 25 -- 1/s; how tightly the gait speed follows the measured velocity
local STANDSTILL_SPEED = 0.4 -- studs/s below which the Quin is standing: no ground loop plays at all
-- States that own the whole body (reactions, scripted flight) or select their own
-- locomotion clips (Circling strafes) are never filled automatically.
local AUTO_DRIVE_EXCLUDED_STATES = {
	Knockback = true, Recovery = true, Death = true, WallRun = true, Airborne = true,
	MidAirClash = true, BeamStruggle = true, ProjectileJump = true, ProjectileFight = true,
	-- (Circling was excluded for its strafe clips; hasForeignLocomotion already keeps the fill
	-- off while one plays, and without the fill a Circling Quin between strafes moved in the
	-- fight stance - or in no pose at all)
}

local states = {} -- [humanoid] = per-Quin gait state

local function smoothstep(edge0, edge1, x)
	local t = math.clamp((x - edge0) / math.max(edge1 - edge0, 1e-3), 0, 1)
	return t * t * (3 - 2 * t)
end

local function wrappedPhaseDelta(a, b)
	local d = (a - b) % 1
	if d > 0.5 then d -= 1 end
	return d
end

local function isActive(track)
	return track ~= nil and track.IsPlaying and track.WeightTarget > 0
end

local function getState(humanoid)
	local st = states[humanoid]
	if not st then
		st = { speed = 0, rates = {}, weights = {}, airTime = 0, entryPhase = nil, lastDriven = 0, launchUntil = 0 }
		states[humanoid] = st
		humanoid.Destroying:Once(function()
			states[humanoid] = nil
		end)
	end
	return st
end

local function clipIds()
	local ids = {}
	for _, clip in ipairs(CLIPS) do
		local entry = AnimationConfig.get(clip.path)
		if entry and entry.id then ids[entry.id] = true end
	end
	return ids
end

local function isAirborneState(humanoid)
	local s = humanoid:GetState()
	return s == Enum.HumanoidStateType.Freefall or s == Enum.HumanoidStateType.Jumping
end

-- A full-body locomotion action (slide, dash) owns the body while it runs
local function hasLocomotionAction(humanoid)
	local model = humanoid.Parent
	return model ~= nil and model:GetAttribute("LocomotionAction") ~= nil
end

-- Weights for Walk / Jog / Run at a given planar speed
local function blendWeights(speed)
	local walkEnd = CombatConfig.Gait_WalkToJogStart or 7.5
	local jogFull = CombatConfig.Gait_WalkToJogEnd or 10.0
	local jogEnd = CombatConfig.Gait_JogToRunStart or 11.0
	local runFull = CombatConfig.Gait_JogToRunEnd or 18.0
	local toJog = smoothstep(walkEnd, jogFull, speed)
	local toRun = smoothstep(jogEnd, runFull, speed)
	return { 1 - toJog, toJog * (1 - toRun), toRun }
end

-- Base locomotion owns the Movement tier while it drives: clear any lingering
-- Movement-priority clip (strafe, arc run, fall) left behind by the previous state.
local function clearForeignMovementTracks(humanoid, own)
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then return end
	for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
		if not own[track] and track.Priority == Enum.AnimationPriority.Movement then
			track:Stop(START_FADE)
		end
	end
end

local function trackPhase(track, plant)
	if not isActive(track) or track.Length <= 0 then return nil end
	return ((track.TimePosition % track.Length) / track.Length - plant) % 1
end

local function releaseGroundLoops(humanoid, fade)
	local st = states[humanoid]
	for _, clip in ipairs(CLIPS) do
		AnimationModule.stop(humanoid, clip.path, fade)
	end
	if st then
		st.rates, st.weights = {}, {}
	end
end

-- Airborne cover: release every ground loop and hold the Fall pose underneath any
-- airborne action clip (jump, vault, knockback) that plays at a higher priority.
local function applyAirborne(humanoid)
	local groundIds = clipIds()
	local animator = humanoid:FindFirstChildOfClass("Animator")
	local fallEntry = AnimationConfig.get(FALL_PATH)
	if animator then
		for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
			local id = track.Animation and track.Animation.AnimationId
			local isFall = fallEntry and id == fallEntry.id
			local isGroundLoop = groundIds[id] or (track.Looped and track.Priority == Enum.AnimationPriority.Movement and not isFall)
			if isGroundLoop and track.WeightTarget > 0 then
				track:Stop(0.12)
			end
		end
	end
	local st = states[humanoid]
	if st then st.rates, st.weights = {}, {} end
	local fall = AnimationModule.getTrack(humanoid, FALL_PATH)
	if fall and not isActive(fall) then
		fall.Priority = Enum.AnimationPriority.Movement
		fall.Looped = true
		fall:Play(0.15, 1, (fallEntry and fallEntry.speed) or 1)
	end
end

local function drive(track, weight, rate, st, key, startPhase)
	weight = math.max(weight, 0.001) -- keep the track alive so the sync group never loses phase
	if not isActive(track) then
		track.Priority = Enum.AnimationPriority.Movement
		track.Looped = true
		track:Play(START_FADE, weight, rate)
		if startPhase and track.Length > 0 then
			track.TimePosition = startPhase * track.Length
		end
		st.weights[key], st.rates[key] = weight, rate
		return
	end
	if math.abs(weight - (st.weights[key] or -1)) > WEIGHT_DEADBAND then
		track:AdjustWeight(weight, 0.1)
		st.weights[key] = weight
	end
	if math.abs(rate - (st.rates[key] or -1)) > RATE_DEADBAND then
		track:AdjustSpeed(rate)
		st.rates[key] = rate
	end
end

-- Drive the blend space from the root's actual planar velocity.
-- Safe to call every frame from any driver; it will not play ground loops in the air
-- or underneath an active locomotion action (slide, dash).
function GaitModule.update(humanoid, rootPart, dt)
	if not humanoid or not humanoid.Parent or not rootPart or not rootPart.Parent then return nil end
	dt = math.clamp(dt or 1 / 60, 0, 0.25)
	local st = getState(humanoid)
	-- Several drivers (state + base-layer fill) may call in the same frame: drive once
	if os.clock() - st.lastDriven < 0.015 then return nil end

	if isAirborneState(humanoid) then
		if st.airTime >= AIR_GRACE then
			applyAirborne(humanoid)
		end
		return nil
	end
	if hasLocomotionAction(humanoid) or os.clock() < st.launchUntil then return nil end

	local tracks = {}
	local own = {}
	for i, clip in ipairs(CLIPS) do
		tracks[i] = AnimationModule.getTrack(humanoid, clip.path)
		if not tracks[i] then return nil end
		own[tracks[i]] = true
	end

	st.lastDriven = os.clock()
	local vel = rootPart.AssemblyLinearVelocity
	local planarSpeed = Vector3.new(vel.X, 0, vel.Z).Magnitude
	-- Light smoothing filters contact-solver noise. The rate has to keep up with a sprint start
	-- (80 studs/s^2): at 12 the legs trailed the body by ~8 studs/s through every acceleration.
	st.speed += (planarSpeed - st.speed) * (1 - math.exp(-SPEED_FOLLOW_RATE * dt))
	local speed = st.speed

	local weights = blendWeights(speed)
	local lens, plants = {}, {}
	local cycleDistance = 0
	local lead = 1
	for i, clip in ipairs(CLIPS) do
		local len = tracks[i].Length > 0 and tracks[i].Length or AnimationModule.getRawLength(clip.path)
		lens[i] = len
		plants[i] = CombatConfig[clip.plantKey] or clip.plant
		cycleDistance += weights[i] * (CombatConfig[clip.speedKey] or clip.speed) * len
		if weights[i] > weights[lead] then lead = i end
	end

	local minRate = CombatConfig.Gait_MinPlayRate or 0.60
	local maxRate = CombatConfig.Gait_MaxPlayRate or 1.45
	local cadence = speed / math.max(cycleDistance, 0.01)
	cadence = math.clamp(cadence, minRate / lens[lead], maxRate / lens[lead])

	-- Fade the whole gait layer over the idle pose near standstill
	local locoWeight = smoothstep(STANDSTILL_SPEED, CombatConfig.Gait_IdleBlendSpeed or 3.0, speed)

	local anyActive = false
	for _, track in ipairs(tracks) do
		if isActive(track) then anyActive = true break end
	end
	if speed < STANDSTILL_SPEED then
		-- Standing: the legs belong to the idle pose, not to a loop stepping in place
		if anyActive then
			releaseGroundLoops(humanoid, 0.2)
		end
		AnimationModule.ensureBaseIdle(humanoid)
		return nil
	end
	if not anyActive then
		clearForeignMovementTracks(humanoid, own)
	end
	if locoWeight < 0.999 then
		AnimationModule.ensureBaseIdle(humanoid)
	end

	-- Canonical phase: the dominant live clip leads; a fresh start uses the handed-off
	-- entry phase (e.g. from a slide exit) or the previous phase-locked cycle.
	local phase = trackPhase(tracks[lead], plants[lead])
	if not phase then
		for i = 1, #CLIPS do
			phase = phase or trackPhase(tracks[i], plants[i])
		end
	end
	if not phase then
		phase = st.entryPhase or AnimationModule.getGaitPhase(humanoid)
	end
	st.entryPhase = nil

	for i, track in ipairs(tracks) do
		local clipPhase = (phase + plants[i]) % 1
		drive(track, weights[i] * locoWeight, cadence * lens[i], st, i, clipPhase)
		if i ~= lead and isActive(track) and track.Length > 0 then
			local current = (track.TimePosition % track.Length) / track.Length
			if math.abs(wrappedPhaseDelta(clipPhase, current)) > PHASE_TOLERANCE then
				track.TimePosition = clipPhase * track.Length
			end
		end
	end

	return {
		speed = speed,
		weights = weights,
		locoWeight = locoWeight,
		cadence = cadence,
		phase = phase,
	}
end

-- A deliberate launch (jump, vault): release the ground loops now and keep them off
-- until the Humanoid reports the flight, so the launch clip owns the body at takeoff.
function GaitModule.notifyLaunch(humanoid)
	if not humanoid then return end
	getState(humanoid).launchUntil = os.clock() + LAUNCH_WINDOW
	releaseGroundLoops(humanoid, 0.1)
end

-- Canonical gait phase (0 = left foot plant) the next gait start should resume at
function GaitModule.setEntryPhase(humanoid, canonicalPhase)
	if not humanoid then return end
	getState(humanoid).entryPhase = canonicalPhase
end

-- Fade the base gait out (idle stays underneath)
function GaitModule.stop(humanoid, fadeOut)
	if not humanoid then return end
	releaseGroundLoops(humanoid, fadeOut or 0.2)
end

function GaitModule.isActive(humanoid)
	if not humanoid then return false end
	for _, clip in ipairs(CLIPS) do
		if isActive(AnimationModule.getExistingTrack(humanoid, clip.path)) then return true end
	end
	return false
end

-- True while a non-gait Movement-priority clip (strafe, arc run, scripted walk) owns the legs
function GaitModule.hasForeignLocomotion(humanoid)
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if not animator then return false end
	local gaitIds = clipIds()
	local fallEntry = AnimationConfig.get(FALL_PATH)
	for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
		if track.Priority == Enum.AnimationPriority.Movement and track.WeightTarget > 0 then
			local id = track.Animation and track.Animation.AnimationId
			if not gaitIds[id] and not (fallEntry and id == fallEntry.id) then
				return true
			end
		end
	end
	return false
end

function GaitModule.isAirborne(humanoid)
	local st = humanoid and states[humanoid]
	return st ~= nil and st.airTime >= AIR_GRACE
end

-- Enforce the ground contract every frame for one Quin, on the side that owns its
-- animation (server for AI, owning client for a piloted Quin). `shouldHandle` returns
-- false while the other side owns the Quin. Returns the connection.
local CONTRACT_EXEMPT_STATES = { WallRun = true, Death = true }

-- Clips loaded ahead of first use so the first slide / jump / fall never starts on an
-- unloaded track (an unloaded track reports IsPlaying = false and Length = 0).
local PRELOAD_PATHS = { "Movement.WalkConfident", "Movement.Jog", "Movement.Run", FALL_PATH, "Movement.Slide", "Movement.StopRun", "Movement.Jump" }

function GaitModule.bindGroundContract(model, humanoid, rootPart, shouldHandle)
	if not model or not humanoid or not rootPart then return nil end
	local st = getState(humanoid)
	if not shouldHandle or shouldHandle() then
		for _, path in ipairs(PRELOAD_PATHS) do
			AnimationModule.getTrack(humanoid, path)
		end
	end
	local connection
	connection = RunService.Heartbeat:Connect(function(dt)
		if not model.Parent or not humanoid.Parent or humanoid.Health <= 0 then
			connection:Disconnect()
			return
		end
		if shouldHandle and not shouldHandle() then
			st.airTime = 0
			return
		end

		-- Never no pose: with every clip faded out (a Circling Quin between its survey and a
		-- strike) the rig showed its bind pose - the T-pose seen mid-match
		local nowCheck = os.clock()
		if nowCheck - (st.lastPoseCheck or 0) > 0.1 then
			st.lastPoseCheck = nowCheck
			local animator = humanoid:FindFirstChildOfClass("Animator")
			local posed = false
			if animator then
				for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
					if track.WeightTarget > 0.05 then
						posed = true
						break
					end
				end
			end
			if not posed and model:GetAttribute("CurrentState") ~= "Death" then
				AnimationModule.ensureBaseIdle(humanoid)
			end
		end
		if isAirborneState(humanoid) and not rootPart.Anchored then
			st.airTime += dt
			if st.airTime >= AIR_GRACE and not CONTRACT_EXEMPT_STATES[model:GetAttribute("CurrentState") or ""] then
				applyAirborne(humanoid)
			end
		else
			if st.airTime >= AIR_GRACE then
				-- Touchdown: release the Fall pose; the idle floor keeps the body posed until
				-- the active driver resumes the gait (it already has the landing speed).
				AnimationModule.stop(humanoid, FALL_PATH, 0.1)
				AnimationModule.ensureBaseIdle(humanoid)
				st.lastDriven = os.clock() -- give the driver its first frame after touchdown
			end
			st.airTime = 0

			-- Base-layer fill: self-propelled ground motion with no locomotion clip owning the legs
			local stateName = model:GetAttribute("CurrentState") or ""
			local t = os.clock()
			if t - (st.lastAuto or 0) >= AUTO_DRIVE_INTERVAL then
				local fillDt = math.clamp(t - (st.lastAuto or (t - AUTO_DRIVE_INTERVAL)), 0.016, 0.1)
				st.lastAuto = t
				if not AUTO_DRIVE_EXCLUDED_STATES[stateName] and not humanoid.PlatformStand
					and not hasLocomotionAction(humanoid) and humanoid.WalkSpeed > 0.5 then
					local v = rootPart.AssemblyLinearVelocity
					-- A live gait keeps following the real velocity down to a standstill, so a Quin
					-- that stops does not keep running in place until the orphan timer fires
					local moving = Vector3.new(v.X, 0, v.Z).Magnitude > AUTO_DRIVE_MIN_SPEED
					if (moving or GaitModule.isActive(humanoid)) and not GaitModule.hasForeignLocomotion(humanoid) then
						GaitModule.update(humanoid, rootPart, fillDt)
					end
				end
			end

			-- Orphaned gait: no state is driving it any more
			if (os.clock() - st.lastDriven) > GAIT_ORPHAN_TIME
				and not CONTRACT_EXEMPT_STATES[model:GetAttribute("CurrentState") or ""]
				and not hasLocomotionAction(humanoid)
				and GaitModule.isActive(humanoid) then
				releaseGroundLoops(humanoid, 0.25)
				AnimationModule.ensureBaseIdle(humanoid)
			end
		end
	end)
	humanoid.Destroying:Once(function()
		if connection.Connected then connection:Disconnect() end
	end)
	return connection
end

return GaitModule
