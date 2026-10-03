--// AnimationModule.lua
-- Centralized animation loading, playback, and priority layering
-- Caches tracks per humanoid to prevent memory leaks
-- Single Source of Truth: ReplicatedStorage.QuinCore.AnimationConfig

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AnimationModule = {}

-- Cache: animationTracks[humanoid][animId] = AnimationTrack
local animationTracks = {}

-- Clip lengths in seconds, measured on the Quin rig for every clip in AnimationConfig. Used only
-- until a track reports its own Length (an unloaded track reports 0). Regenerate when a clip changes.
local KNOWN_TRACK_LENGTHS = {
	["rbxassetid://84162023451491"] = 1.167, -- Attacks.Kicks.HighKick
	["rbxassetid://71573540671127"] = 1.133, -- Attacks.Kicks.LowKick
	["rbxassetid://87872094663324"] = 0.933, -- Attacks.Kicks.PowerKick, Attacks.Special.Special1, Attacks.Specials.RivalFinisher
	["rbxassetid://89487629068473"] = 1.233, -- Attacks.Kicks.WheelDrive, Attacks.Special.Slam
	["rbxassetid://79937990476934"] = 1.000, -- Attacks.Punches.CrossLeft
	["rbxassetid://99362983788110"] = 1.000, -- Attacks.Punches.CrossRight
	["rbxassetid://135206101877204"] = 1.200, -- Attacks.Punches.Hook, Tactics.DesperateCounter
	["rbxassetid://113219639247452"] = 0.833, -- Attacks.Punches.Punch1, Attacks.Punches.Uppercut, Attacks.Specials.Slam, Attacks.Specials.SlamImpact, Attacks.Specials.Special1, Attacks.Specials.Uppercut
	["rbxassetid://109837817595150"] = 3.867, -- Attacks.Specials.BeamStruggle, Idles.CombatIdle, Idles.FightIdle, Idles.SurveyIdle, Transition.AssessTarget
	["rbxassetid://71743026406362"] = 2.733, -- Attacks.Specials.ProceduralSmackDown
	["rbxassetid://79207866638803"] = 3.200, -- Attacks.Specials.SlamRecovery, Reactions.GetUpGround
	["rbxassetid://98616724907377"] = 4.033, -- Awareness.LookingBehind, Awareness.RearThreatGlance
	["rbxassetid://129355316172688"] = 0.667, -- Awareness.Turn180Pivot, Movement.RunTurn180, Movement.RunTurn180Left, Movement.RunTurn180Right, Movement.RunTurn90Left, Movement.RunTurn90Right
	["rbxassetid://81038616654818"] = 8.333, -- Idles.DefaultIdle, Movement.Idle
	["rbxassetid://123350689285769"] = 1.950, -- Idles.ReadyStance
	["rbxassetid://89227245782124"] = 0.767, -- Movement.ArcRun30Rear, Movement.ArcRun30RearLeft, Movement.ArcRun30RearRight
	["rbxassetid://83869147275692"] = 1.367, -- Movement.BrakingStop, Reactions.HitLight, Reactions.Knockback
	["rbxassetid://133182359318358"] = 0.100, -- Movement.Dash
	["rbxassetid://79340771026707"] = 0.767, -- Movement.Fall
	["rbxassetid://88475997278069"] = 2.567, -- Movement.FallAirKnockback, Reactions.FallAirKnockback, Reactions.KnockbackAir, Reactions.SlammedDown
	["rbxassetid://80583167665730"] = 1.567, -- Movement.FallStraight
	["rbxassetid://113571639405597"] = 0.800, -- Movement.IdleToRun1, Movement.IdleToRun2, Movement.StartRun, Movement.StartSprint
	["rbxassetid://91301995989516"] = 0.833, -- Movement.Jog
	["rbxassetid://85622241844167"] = 0.933, -- Movement.Jump, Parkour.VaultObstacle
	["rbxassetid://109090784752055"] = 0.467, -- Movement.Run
	["rbxassetid://115642161658755"] = 1.533, -- Movement.Slide
	["rbxassetid://89237107000987"] = 0.900, -- Movement.StopRun
	["rbxassetid://117985748552966"] = 1.033, -- Movement.WalkConfident, Movement.WalkThug
	["rbxassetid://110436967972328"] = 1.250, -- Parkour.LandingHard
	["rbxassetid://136234480688142"] = 1.667, -- Parkour.LandingSoft, Parkour.LedgeDropLanding
	["rbxassetid://94804914683754"] = 0.883, -- Parkour.LandingSuperHero
	["rbxassetid://90546747503310"] = 3.700, -- Parkour.ProceduralJump1
	["rbxassetid://73976796270777"] = 1.533, -- Parkour.ProceduralSlide1
	["rbxassetid://101210294612380"] = 1.433, -- Parkour.ProceduralSlide2
	["rbxassetid://82934009896094"] = 1.200, -- Parkour.SkidOverOB
	["rbxassetid://81580688159305"] = 1.000, -- Reactions.Block, Reactions.BlockFront
	["rbxassetid://71555510097974"] = 1.000, -- Reactions.BlockLeft
	["rbxassetid://81446994688965"] = 1.000, -- Reactions.BlockRight
	["rbxassetid://80496269227852"] = 4.667, -- Reactions.Death, Reactions.DeathCollapse
	["rbxassetid://122802842451487"] = 4.500, -- Reactions.DeathOnTheSpot
	["rbxassetid://95406088712190"] = 2.033, -- Reactions.GetUpBackFast
	["rbxassetid://128158227118276"] = 8.267, -- Reactions.GetUpBackSlow
	["rbxassetid://108624065264351"] = 2.767, -- Reactions.GetUpFromCrouch
	["rbxassetid://82096408080514"] = 1.300, -- Reactions.HitHeavy
	["rbxassetid://131344167080457"] = 2.533, -- Reactions.KnockdownBehind
	["rbxassetid://123318024844911"] = 0.667, -- Strafe.StrafeLeftRun
	["rbxassetid://91032818959845"] = 1.467, -- Strafe.StrafeLeftTired
	["rbxassetid://71421932655009"] = 1.033, -- Strafe.StrafeLeftWalk, Tactics.RetreatBackstep
	["rbxassetid://107962284182266"] = 0.667, -- Strafe.StrafeRightRun
	["rbxassetid://110691224052109"] = 1.467, -- Strafe.StrafeRightTired
	["rbxassetid://82291519563301"] = 1.033, -- Strafe.StrafeRightWalk
	["rbxassetid://131563762426355"] = 2.500, -- Tactics.ProceduralEvade1
	["rbxassetid://135253684509200"] = 3.700, -- Tactics.ProceduralEvade2
}

-- Display names for trace output (first AnimationConfig path that uses the asset)
local KNOWN_NAMES = {
	["rbxassetid://84162023451491"] = "HighKick",
	["rbxassetid://71573540671127"] = "LowKick",
	["rbxassetid://87872094663324"] = "PowerKick",
	["rbxassetid://89487629068473"] = "WheelDrive",
	["rbxassetid://79937990476934"] = "CrossLeft",
	["rbxassetid://99362983788110"] = "CrossRight",
	["rbxassetid://135206101877204"] = "Hook",
	["rbxassetid://113219639247452"] = "Punch1",
	["rbxassetid://109837817595150"] = "BeamStruggle",
	["rbxassetid://71743026406362"] = "ProceduralSmackDown",
	["rbxassetid://79207866638803"] = "SlamRecovery",
	["rbxassetid://98616724907377"] = "LookingBehind",
	["rbxassetid://129355316172688"] = "Turn180Pivot",
	["rbxassetid://81038616654818"] = "DefaultIdle",
	["rbxassetid://123350689285769"] = "ReadyStance",
	["rbxassetid://89227245782124"] = "ArcRun30Rear",
	["rbxassetid://83869147275692"] = "BrakingStop",
	["rbxassetid://133182359318358"] = "Dash",
	["rbxassetid://79340771026707"] = "Fall",
	["rbxassetid://88475997278069"] = "FallAirKnockback",
	["rbxassetid://80583167665730"] = "FallStraight",
	["rbxassetid://113571639405597"] = "IdleToRun1",
	["rbxassetid://91301995989516"] = "Jog",
	["rbxassetid://85622241844167"] = "Jump",
	["rbxassetid://109090784752055"] = "Run",
	["rbxassetid://115642161658755"] = "Slide",
	["rbxassetid://89237107000987"] = "StopRun",
	["rbxassetid://117985748552966"] = "WalkConfident",
	["rbxassetid://110436967972328"] = "LandingHard",
	["rbxassetid://136234480688142"] = "LandingSoft",
	["rbxassetid://94804914683754"] = "LandingSuperHero",
	["rbxassetid://90546747503310"] = "ProceduralJump1",
	["rbxassetid://73976796270777"] = "ProceduralSlide1",
	["rbxassetid://101210294612380"] = "ProceduralSlide2",
	["rbxassetid://82934009896094"] = "SkidOverOB",
	["rbxassetid://81580688159305"] = "Block",
	["rbxassetid://71555510097974"] = "BlockLeft",
	["rbxassetid://81446994688965"] = "BlockRight",
	["rbxassetid://80496269227852"] = "Death",
	["rbxassetid://122802842451487"] = "DeathOnTheSpot",
	["rbxassetid://95406088712190"] = "GetUpBackFast",
	["rbxassetid://128158227118276"] = "GetUpBackSlow",
	["rbxassetid://108624065264351"] = "GetUpFromCrouch",
	["rbxassetid://82096408080514"] = "HitHeavy",
	["rbxassetid://131344167080457"] = "KnockdownBehind",
	["rbxassetid://123318024844911"] = "StrafeLeftRun",
	["rbxassetid://91032818959845"] = "StrafeLeftTired",
	["rbxassetid://71421932655009"] = "StrafeLeftWalk",
	["rbxassetid://107962284182266"] = "StrafeRightRun",
	["rbxassetid://110691224052109"] = "StrafeRightTired",
	["rbxassetid://82291519563301"] = "StrafeRightWalk",
	["rbxassetid://131563762426355"] = "ProceduralEvade1",
	["rbxassetid://135253684509200"] = "ProceduralEvade2",
}

-- Clip groups are declared by AnimationConfig path and resolved to asset ids on use, so a
-- hot-swapped clip stays in its group (hard-coded id lists had drifted out of date).

-- Temporary locomotion overlays (turns, vaults, slides, stops, falls, landings)
local LOCOMOTION_OVERLAY_PATHS = {
	"Movement.Slide", "Movement.StartRun", "Movement.StopRun", "Movement.Jump", "Movement.Fall",
	"Movement.FallStraight", "Movement.FallAirKnockback", "Movement.RunTurn180", "Movement.ArcRun30Rear",
	"Parkour.LandingSoft", "Parkour.LandingHard", "Parkour.LandingSuperHero", "Parkour.ProceduralJump1",
	"Parkour.ProceduralSlide1", "Parkour.ProceduralSlide2", "Parkour.SkidOverOB", "Awareness.RearThreatGlance",
}

-- Cyclical locomotion clips whose gait phase is carried across a transition between them
local PHASE_LOCKED_PATHS = {
	"Movement.WalkConfident", "Movement.Jog", "Movement.Run", "Movement.ArcRun30Rear",
	"Strafe.StrafeLeftWalk", "Strafe.StrafeRightWalk", "Strafe.StrafeLeftRun", "Strafe.StrafeRightRun",
}

local function resolveAnimFriendlyName(animIdOrPath)
	local str = tostring(animIdOrPath or "")
	if KNOWN_NAMES[str] then return KNOWN_NAMES[str] end
	local num = str:match("%d+")
	if num and KNOWN_NAMES["rbxassetid://" .. num] then
		return KNOWN_NAMES["rbxassetid://" .. num]
	end
	return str:gsub("^.*%.", "")
end

-- Lazy-load AnimationConfig to avoid circular dependencies during initialization
local _AnimationConfig = nil
local function getAnimationConfig()
	if not _AnimationConfig then
		local qc = ReplicatedStorage:FindFirstChild("QuinCore")
		if qc and qc:FindFirstChild("AnimationConfig") then
			local ok, mod = pcall(function() return require(qc.AnimationConfig) end)
			if ok and type(mod) == "table" then
				_AnimationConfig = mod
			end
		end
	end
	return _AnimationConfig
end

-- Asset-id sets for the clip groups above, rebuilt at most once a second
local groupCache = {}
local function clipGroup(paths)
	local cached = groupCache[paths]
	if cached and os.clock() - cached.builtAt < 1.0 then
		return cached.ids
	end
	local ac = getAnimationConfig()
	local ids = {}
	if ac then
		for _, path in ipairs(paths) do
			local entry = ac.get(path)
			if entry and entry.id then ids[entry.id] = true end
		end
		groupCache[paths] = { ids = ids, builtAt = os.clock() }
	end
	return ids
end

-- Lazy-load RuntimeTracer for execution logging
local _RuntimeTracer = nil
local function getRuntimeTracer()
	if not _RuntimeTracer then
		local qc = ReplicatedStorage:FindFirstChild("QuinCore")
		if qc and qc:FindFirstChild("Modules") and qc.Modules:FindFirstChild("RuntimeTracer") then
			local ok, mod = pcall(function() return require(qc.Modules.RuntimeTracer) end)
			if ok and type(mod) == "table" then
				_RuntimeTracer = mod
			end
		end
	end
	return _RuntimeTracer
end

-- Lazy-load AudioModule to directly wire animation markers to authoritative audio
local _AudioModule = nil
local function getAudioModule()
	if not _AudioModule then
		local qc = ReplicatedStorage:FindFirstChild("QuinCore")
		if qc and qc:FindFirstChild("Modules") and qc.Modules:FindFirstChild("AudioModule") then
			local ok, mod = pcall(function() return require(qc.Modules.AudioModule) end)
			if ok and type(mod) == "table" then
				_AudioModule = mod
			end
		end
	end
	return _AudioModule
end

-- Lazy-load VfxModule the same way (footprints on the Footstep marker)
local _VfxModule = nil
local function getVfxModule()
	if not _VfxModule then
		local qc = ReplicatedStorage:FindFirstChild("QuinCore")
		if qc and qc:FindFirstChild("Modules") and qc.Modules:FindFirstChild("VfxModule") then
			local ok, mod = pcall(function() return require(qc.Modules.VfxModule) end)
			if ok and type(mod) == "table" then
				_VfxModule = mod
			end
		end
	end
	return _VfxModule
end

local FOOTSTEP_MIN_WEIGHT = 0.35 -- blend weight below which a clip's Footstep markers are silent

-- Wire animation marker reached signals to AudioModule exactly once per loaded track instance
local function wireTrackAudio(humanoid, track, animId)
	if not humanoid or not track then return end
	local fighter = humanoid.Parent

	-- Footstep marker (Run, Walk, Strafe, ArcRun, etc.)
	track:GetMarkerReachedSignal("Footstep"):Connect(function(side)
		-- Only a clip that is carrying the legs speaks. The gait keeps its other clips (jog,
		-- run, strafes) running in step at near-zero weight for blending, and their markers
		-- fire too: every step sounded twice, about 0.16 s apart.
		if track.WeightCurrent < FOOTSTEP_MIN_WEIGHT then return end
		local audio = getAudioModule()
		if audio and audio.playFootstep and fighter and fighter.Parent then
			local hrp = fighter:FindFirstChild("HumanoidRootPart")
			local speed = hrp and hrp.AssemblyLinearVelocity.Magnitude or 16
			local vol = speed > 25 and 0.45 or 0.35
			audio.playFootstep(fighter, vol)
		end
		local vfx = getVfxModule()
		if vfx and fighter and fighter.Parent then
			vfx.createFootprint(fighter, side) -- marker parameter "Left" / "Right" when the clip has it
		end
	end)

	-- 180 Turn Footstep marker
	track:GetMarkerReachedSignal("Footstep180"):Connect(function()
		local audio = getAudioModule()
		if audio and audio.playFootstep and fighter and fighter.Parent then
			audio.playFootstep(fighter, 0.40)
		end
	end)

	-- Landing impact marker (LandingSoft, LandingHard, LandingSuperHero, etc.)
	track:GetMarkerReachedSignal("Landing"):Connect(function()
		local audio = getAudioModule()
		if audio and audio.playFallOnGround and fighter and fighter.Parent then
			local hrp = fighter:FindFirstChild("HumanoidRootPart")
			if hrp then
				audio.playFallOnGround(hrp.Position)
			end
		end
	end)

	-- Jump launch marker (if present on any jump animation)
	track:GetMarkerReachedSignal("Jump"):Connect(function()
		local audio = getAudioModule()
		if audio and audio.playJump and fighter and fighter.Parent then
			audio.playJump(fighter, 0.5)
		end
	end)

	-- Projectile jump marker
	track:GetMarkerReachedSignal("ProjectileJump"):Connect(function()
		local audio = getAudioModule()
		if audio and audio.playJumpUp and fighter and fighter.Parent then
			local hrp = fighter:FindFirstChild("HumanoidRootPart")
			if hrp then
				audio.playJumpUp(hrp.Position)
			end
		end
	end)
end

-- Get or create an Animator on the humanoid
local function ensureAnimator(humanoid)
	if not humanoid then return nil end
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end
	return animator
end

-- Get or load a track
-- A config entry may ask for its own track ("id#trackKey") when it shares an asset with another
-- entry: SurveyIdle (one-shot, Action2) and FightIdle/CombatIdle (looped idle) are one asset, and
-- with one cached track per id, playing the survey turned the fight idle into a one-shot - when
-- it ended nothing was posed (single-frame T-poses in Circling).
local function trackIdFor(entry)
	if entry and entry.trackKey then
		return entry.id .. "#" .. entry.trackKey
	end
	return entry and entry.id
end

local function getTrack(humanoid, animId)
	if not humanoid or not animId or animId == "" then return nil end
	local animator = ensureAnimator(humanoid)
	
	if not animationTracks[humanoid] then
		animationTracks[humanoid] = {}
	end
	
	if not animationTracks[humanoid][animId] then
		local assetId = animId:match("^([^#]+)") or animId
		local anim = Instance.new("Animation")
		anim.AnimationId = assetId
		local track = animator and animator:LoadAnimation(anim) or humanoid:LoadAnimation(anim)
		animationTracks[humanoid][animId] = track

		-- Wire animation audio markers directly to AudioModule ONCE upon track loading!
		wireTrackAudio(humanoid, track, assetId)
	end
	
	return animationTracks[humanoid][animId]
end

-- Retrieve track raw length with fallback to known database
function AnimationModule.getRawLength(animId)
	if not animId then return 0.7 end
	if KNOWN_TRACK_LENGTHS[animId] then
		return KNOWN_TRACK_LENGTHS[animId]
	end
	-- If dotPath was given
	if type(animId) == "string" and animId:find("%.") then
		local ac = getAnimationConfig()
		local entry = ac and ac.get(animId)
		if entry and entry.id and KNOWN_TRACK_LENGTHS[entry.id] then
			return KNOWN_TRACK_LENGTHS[entry.id]
		end
	end
	return 0.7
end

-- Ensure baseline idle posture is running persistently at Enum.AnimationPriority.Idle
function AnimationModule.ensureBaseIdle(humanoid)
	if not humanoid or not humanoid.Parent then return nil end
	local ac = getAnimationConfig()
	local fighter = humanoid.Parent
	local now = os.clock()

	-- Check if actively fighting/in combat
	local inCombat = fighter and (
		fighter:GetAttribute("CurrentState") == "Fight"
		or fighter:GetAttribute("CurrentState") == "Circling" -- standoff keeps the fight stance (no stance swap on every Fight <-> Circling)
		or fighter:GetAttribute("InCombat") == true
		or (fighter:GetAttribute("Target") ~= nil and fighter:GetAttribute("Target") ~= "")
	)

	local dotPath = "Movement.Idle" -- Default is IDLE_DEFAULT (rbxassetid://81038616654818)

	if inCombat then
		dotPath = "Idles.FightIdle" -- IDLEFIGHT_STANCE (rbxassetid://109837817595150)
	else
		local stance = fighter and fighter:GetAttribute("CurrentIdleStance") or "Default"
		local lastActivity = fighter and fighter:GetAttribute("LastActivityTime") or now

		if stance == "Ready" then
			if (now - lastActivity) >= 5.0 then
				-- 5 seconds of inactivity elapsed with no movement/combat: relax back to Default
				fighter:SetAttribute("CurrentIdleStance", "Default")
				dotPath = "Movement.Idle" -- IDLE_DEFAULT
			else
				dotPath = "Idles.ReadyStance" -- IDLEREADY_STANCE (rbxassetid://123350689285769)
			end
		else
			dotPath = "Movement.Idle" -- IDLE_DEFAULT
		end
	end

	local entry = ac and ac.get(dotPath)
	if not entry or not entry.id or entry.id == "" then
		entry = ac and ac.get("Movement.Idle")
	end
	if not entry or not entry.id or entry.id == "" then return nil end

	-- Stop competing idle tracks
	local competingPaths = { "Movement.Idle", "Idles.ReadyStance", "Idles.FightIdle", "Idles.CombatIdle", "Idles.DefaultIdle" }
	for _, path in ipairs(competingPaths) do
		if path ~= dotPath then
			local otherEntry = ac and ac.get(path)
			if otherEntry and otherEntry.id and otherEntry.id ~= entry.id then
				AnimationModule.stop(humanoid, otherEntry.id, 0.20)
			end
		end
	end

	local track = getTrack(humanoid, entry.id)
	if not track then return nil end

	-- Stop and prune ANY other playing track (including duplicate tracks of the same ID)
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if animator then
		for _, t in ipairs(animator:GetPlayingAnimationTracks()) do
			local cachedElsewhere = false
			for _, cached in pairs(animationTracks[humanoid] or {}) do
				if cached == t then cachedElsewhere = true break end
			end
			if t ~= track and not cachedElsewhere and t.Animation and t.Animation.AnimationId == entry.id then
				t:Stop(0)
				pcall(function() t:Destroy() end)
			elseif t.Priority == Enum.AnimationPriority.Idle and t ~= track and t.IsPlaying then
				t:Stop(0.20)
			end
		end
	end

	track.Priority = Enum.AnimationPriority.Idle
	track.Looped = true

	if not track.IsPlaying or track.WeightTarget == 0 then
		track:Play(entry.fadeTime or 0.2, 1, entry.speed or 1.0)
	else
		track:AdjustSpeed(entry.speed or 1.0)
		track:AdjustWeight(1, entry.fadeTime or 0.2)
	end
	return track
end

-- Play using a configuration dotPath (Master Single Source of Truth)
function AnimationModule.playConfig(humanoid, dotPath, runtimeMultiplier, priorityOverride, overlay)
	local ac = getAnimationConfig()
	local entry = ac and ac.get(dotPath)
	if not entry or not entry.id or entry.id == "" then
		warn("[AnimationModule] Invalid or missing config entry for dotPath: " .. tostring(dotPath))
		return nil
	end

	local prio = priorityOverride or (entry.priority and Enum.AnimationPriority[entry.priority]) or Enum.AnimationPriority.Action
	local looped = entry.looped == true
	local baseSpeed = entry.speed or 1.0
	local finalSpeed = baseSpeed * (runtimeMultiplier or 1.0)
	local fadeTime = entry.fadeTime or 0.1

	-- Ensure base idle posture is active underneath any higher-priority action
	if prio ~= Enum.AnimationPriority.Idle then
		AnimationModule.ensureBaseIdle(humanoid)
	end

	return AnimationModule.play(humanoid, trackIdFor(entry), prio, looped, finalSpeed, fadeTime, overlay)
end

-- Stop using a configuration dotPath
function AnimationModule.stopConfig(humanoid, dotPath, fadeOut)
	local ac = getAnimationConfig()
	local entry = ac and ac.get(dotPath)
	if entry and entry.id then
		AnimationModule.stop(humanoid, trackIdFor(entry), fadeOut or entry.fadeTime or 0.15)
	end
end

-- Stop all tracks in a given configuration category (e.g. "Reactions", "Attacks", "Movement")
function AnimationModule.stopCategory(humanoid, category, fadeOut)
	if not humanoid or not animationTracks[humanoid] then return end
	local ac = getAnimationConfig()
	local catData = ac and ac.Registry and ac.Registry[category]
	if not catData then return end
	
	local idsToStop = {}
	local function collectIds(tbl)
		for _, v in pairs(tbl) do
			if type(v) == "table" and v.id then
				idsToStop[v.id] = true
			elseif type(v) == "table" then
				collectIds(v)
			end
		end
	end
	collectIds(catData)
	
	for animId, track in pairs(animationTracks[humanoid]) do
		-- (never the base idle: Attacks.BeamStruggle and Awareness.AssessTarget share the fight
		-- idle's asset, so stopping "Attacks" on entering Fight / Circling stopped the idle loop
		-- itself and the body showed its bind pose until the no-pose watchdog caught it)
		if idsToStop[animId] and track.IsPlaying and track.Priority ~= Enum.AnimationPriority.Idle then
			track:Stop(fadeOut or 0.15)
		end
	end
end

-- Stop all temporary locomotion overlays (turns, vaults, slides, stops, falls, landings)
-- Safely releases bone transforms so base running/walking animation cycles can execute cleanly
function AnimationModule.stopLocomotionOverlays(humanoid, fadeOut)
	if not humanoid or not animationTracks[humanoid] then return end
	local fade = fadeOut or 0.12
	for animId, track in pairs(animationTracks[humanoid]) do
		if track.IsPlaying and (clipGroup(LOCOMOTION_OVERLAY_PATHS)[animId] or track:GetAttribute("IsLocomotionOverlay")) then
			track:Stop(fade)
		end
	end
end

-- Play an animation with priority-aware layering
-- NEVER stops underlying Idle tracks to guarantee ZERO T-POSES
function AnimationModule.play(humanoid, animIdOrPath, priority, looped, speed, fadeIn, overlay)
	if not humanoid or not animIdOrPath or animIdOrPath == "" then return nil end

	local animId = animIdOrPath
	-- If a dotPath was passed, resolve it to config
	if type(animIdOrPath) == "string" and animIdOrPath:find("%.") then
		local ac = getAnimationConfig()
		local entry = ac and ac.get(animIdOrPath)
		if entry and entry.id then
			animId = trackIdFor(entry)
			priority = priority or (entry.priority and Enum.AnimationPriority[entry.priority]) or Enum.AnimationPriority.Action
			if looped == nil then looped = (entry.looped == true) end
			speed = (speed or 1.0) * (entry.speed or 1.0)
			fadeIn = fadeIn or entry.fadeTime or 0.1
		end
	end

	local track = getTrack(humanoid, animId)
	if not track then return nil end
	
	local targetPrio = priority or Enum.AnimationPriority.Action
	track.Priority = targetPrio
	track.Looped = looped or false
	
	-- Phase-Locked Gait Synchronization:
	-- When transitioning between cyclical locomotion tracks (Run <-> ArcRun <-> Strafe),
	-- capture the normalized gait phase of the retiring track so the new track can resume
	-- at the exact matching footfall phase, completely eliminating leg hitching or foot swapping.
	local activeGaitPhase = nil
	if clipGroup(PHASE_LOCKED_PATHS)[animId] and animationTracks[humanoid] then
		for otherId, otherTrack in pairs(animationTracks[humanoid]) do
			if otherId ~= animId and otherTrack.IsPlaying and clipGroup(PHASE_LOCKED_PATHS)[otherId] then
				local rawLen = otherTrack.Length > 0 and otherTrack.Length or 0.8
				activeGaitPhase = (otherTrack.TimePosition % rawLen) / rawLen
				break
			end
		end
	end

	-- Priority-aware stopping:
	-- Stop competing tracks in the same priority tier, but NEVER stop underlying Idle tracks!
	if not overlay and animationTracks[humanoid] then
		local newPrioVal = targetPrio.Value
		for otherId, otherTrack in pairs(animationTracks[humanoid]) do
			if otherId ~= animId and otherTrack.IsPlaying then
				local otherPrioVal = otherTrack.Priority.Value
				-- Do NOT stop underlying Idle unless the new track is explicitly replacing Idle
				if otherTrack.Priority == Enum.AnimationPriority.Idle and targetPrio ~= Enum.AnimationPriority.Idle then
					-- Leave Idle active in background
				elseif newPrioVal >= Enum.AnimationPriority.Action.Value and otherPrioVal >= Enum.AnimationPriority.Action.Value then
					-- Competing action (e.g. punch replacing previous punch) -> stop old action
					otherTrack:Stop(fadeIn or 0.08)
				elseif newPrioVal == Enum.AnimationPriority.Movement.Value and otherPrioVal == Enum.AnimationPriority.Movement.Value then
					-- Competing movement (e.g. walk replacing strafe) -> stop old movement
					otherTrack:Stop(fadeIn or 0.1)
				elseif newPrioVal == Enum.AnimationPriority.Movement.Value and clipGroup(LOCOMOTION_OVERLAY_PATHS)[otherId] then
					-- Locomotion base running/walking resuming: only clear finished or near-finished locomotion overlays, or lower-priority overlays
					if (not otherTrack.Looped and otherTrack.Length > 0 and otherTrack.TimePosition >= (otherTrack.Length - 0.12)) or (otherPrioVal <= Enum.AnimationPriority.Movement.Value) then
						otherTrack:Stop(fadeIn or 0.1)
					end
				elseif newPrioVal > Enum.AnimationPriority.Movement.Value and otherPrioVal == Enum.AnimationPriority.Movement.Value and otherTrack.Looped then
					-- Base locomotion loops (gait, strafe, fall) stay alive underneath an action overlay.
					-- The overlay already wins by priority; stopping the loop made the legs drop to idle
					-- and restart every time an attack, glance or turn overlay played. These loops are
					-- released by their own owners (state exit, GaitModule orphan / airborne contract).
				elseif newPrioVal >= otherPrioVal and otherTrack.Priority ~= Enum.AnimationPriority.Idle then
					-- Higher priority overriding non-idle lower track
					otherTrack:Stop(fadeIn or 0.1)
				elseif not otherTrack.Looped and otherTrack.Length > 0 and otherTrack.TimePosition >= (otherTrack.Length - 0.08) and otherTrack.Priority ~= Enum.AnimationPriority.Idle then
					-- Finished unlooped action track lingering at end pose -> stop to prevent frozen bone override
					otherTrack:Stop(fadeIn or 0.08)
				end
			end
		end
	end
	
	local speedMult = workspace:GetAttribute("GameSpeedMultiplier") or 1.0
	local baseSpeed = speed or 1.0
	track:SetAttribute("BaseTrackSpeed", baseSpeed)
	local effectiveSpeed = baseSpeed * speedMult

	if not track.IsPlaying then
		local startFade = (fadeIn or 0.1) / speedMult
		track:Play(startFade, 1, effectiveSpeed)
		if activeGaitPhase and track.Length > 0 then
			track.TimePosition = math.clamp(activeGaitPhase * track.Length, 0, track.Length)
		end
		local rt = getRuntimeTracer()
		if rt and humanoid and humanoid.Parent then
			local animName = resolveAnimFriendlyName(animIdOrPath)
			rt.checkpoint(humanoid.Parent, "PlayTrack: " .. animName, 2)
		end
	else
		track:AdjustSpeed(effectiveSpeed)
	end
	
	return track
end

-- Retrieve active normalized gait phase for testing & telemetry (0.0 to 1.0)
function AnimationModule.getGaitPhase(humanoid)
	if not humanoid or not animationTracks[humanoid] then return 0 end
	for id, track in pairs(animationTracks[humanoid]) do
		if track.IsPlaying and clipGroup(PHASE_LOCKED_PATHS)[id] then
			local len = track.Length > 0 and track.Length or 0.8
			return (track.TimePosition % len) / len
		end
	end
	return 0
end

-- Stop a specific animation
function AnimationModule.stop(humanoid, animIdOrPath, fadeOut)
	if not humanoid then return end
	local animId = animIdOrPath
	if type(animIdOrPath) == "string" and animIdOrPath:find("%.") then
		local ac = getAnimationConfig()
		local entry = ac and ac.get(animIdOrPath)
		if entry and entry.id then animId = trackIdFor(entry) end
	end
	local fade = fadeOut or 0.15
	if animationTracks[humanoid] and animationTracks[humanoid][animId] then
		local track = animationTracks[humanoid][animId]
		if track.IsPlaying then
			track:Stop(fade)
		end
	end
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if animator then
		for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
			local a = track.Animation
			if a and a.AnimationId == animId and track.IsPlaying then
				track:Stop(fade)
			end
		end
	end
	local rt = getRuntimeTracer()
	if rt and humanoid and humanoid.Parent then
		local animName = resolveAnimFriendlyName(animIdOrPath)
		rt.checkpoint(humanoid.Parent, "StopTrack: " .. animName, 2)
	end
end

-- Stop ALL action and movement tracks, but safely preserves/restores baseline Idle
function AnimationModule.stopAll(humanoid, fadeOut)
	if not animationTracks[humanoid] then return end
	for _, track in pairs(animationTracks[humanoid]) do
		if track.IsPlaying and track.Priority ~= Enum.AnimationPriority.Idle then
			track:Stop(fadeOut or 0.15)
		end
	end
	AnimationModule.ensureBaseIdle(humanoid)
end

-- Stop all playing tracks that belong to a specific config category (e.g. "Reactions")
function AnimationModule.stopCategory(humanoid, category, fadeOut)
	if not humanoid or not animationTracks[humanoid] then return end
	local ac = getAnimationConfig()
	if not ac or not ac.getAllPaths then return end
	
	local ok, all = pcall(function() return ac.getAllPaths() end)
	if not ok or type(all) ~= "table" then return end
	
	local catPrefix = category .. "."
	local idsToStop = {}
	for _, item in ipairs(all) do
		if item.path and (item.path:sub(1, #catPrefix) == catPrefix or item.category == category or item.path == category) then
			if item.entry and item.entry.id then
				idsToStop[item.entry.id] = true
			end
		end
	end
	
	for animId, track in pairs(animationTracks[humanoid]) do
		-- (never the base idle: Attacks.BeamStruggle and Awareness.AssessTarget share the fight
		-- idle's asset, so stopping "Attacks" on entering Fight / Circling stopped the idle loop
		-- itself and the body showed its bind pose until the no-pose watchdog caught it)
		if idsToStop[animId] and track.IsPlaying and track.Priority ~= Enum.AnimationPriority.Idle then
			track:Stop(fadeOut or 0.15)
		end
	end
end

-- Check if a specific animation is playing (actively weighted, not fading out)
function AnimationModule.isPlaying(humanoid, animIdOrPath)
	if not humanoid then return false end
	local animId = animIdOrPath
	if type(animIdOrPath) == "string" and animIdOrPath:find("%.") then
		local ac = getAnimationConfig()
		local entry = ac and ac.get(animIdOrPath)
		if entry and entry.id then animId = trackIdFor(entry) end
	end
	local myTrack = animationTracks[humanoid] and animationTracks[humanoid][animId]
	if myTrack and myTrack.IsPlaying and (myTrack.WeightTarget == nil or myTrack.WeightTarget > 0) then
		return true
	end
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if animator then
		for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
			local a = track.Animation
			if a and a.AnimationId == animId and track.IsPlaying and (track.WeightTarget == nil or track.WeightTarget > 0) then
				return true
			end
		end
	end
	return false
end

-- Query true effective duration in seconds (Length / speed)
function AnimationModule.getEffectiveDuration(humanoid, animIdOrPath, runtimeMultiplier)
	local animId = animIdOrPath
	local baseSpeed = 1.0
	if type(animIdOrPath) == "string" and animIdOrPath:find("%.") then
		local ac = getAnimationConfig()
		local entry = ac and ac.get(animIdOrPath)
		if entry and entry.id then
			animId = trackIdFor(entry)
			baseSpeed = entry.speed or 1.0
		end
	end

	local rawLen = 0.7
	local track = animationTracks[humanoid] and animationTracks[humanoid][animId]
	if track and track.Length > 0 then
		rawLen = track.Length
	elseif KNOWN_TRACK_LENGTHS[animId] then
		rawLen = KNOWN_TRACK_LENGTHS[animId]
	end

	local finalSpeed = math.max(baseSpeed * (runtimeMultiplier or 1.0), 0.01)
	return rawLen / finalSpeed, rawLen
end

-- Retrieve a real-time report of all active tracks on a humanoid for visual debugging
function AnimationModule.getActiveTracksReport(humanoid)
	local report = {}
	if not humanoid then return report end
	
	local ac = getAnimationConfig()
	local idToName = {}
	if ac and ac.getAllPaths then
		local ok, all = pcall(function() return ac.getAllPaths() end)
		if ok and type(all) == "table" then
			for _, item in ipairs(all) do
				if item.entry and item.entry.id then
					idToName[item.entry.id] = item.path
				end
			end
		end
	end
	
	local animator = humanoid:FindFirstChildOfClass("Animator")
	local activeTracks = animator and animator:GetPlayingAnimationTracks() or humanoid:GetPlayingAnimationTracks()
	
	for _, track in ipairs(activeTracks) do
		if track.IsPlaying and track.WeightCurrent > 0.01 then
			local animId = track.Animation and track.Animation.AnimationId or ""
			local friendlyName = idToName[animId] or animId:match("%d+$") or "Unknown"
			table.insert(report, {
				id = animId,
				name = friendlyName,
				priority = track.Priority.Name,
				speed = track.Speed,
				weight = track.WeightCurrent,
				length = track.Length,
				timePosition = track.TimePosition,
				looped = track.Looped,
			})
		end
	end
	table.sort(report, function(a, b) return a.priority < b.priority end)
	return report
end

-- Apply hit stop (freeze frames)
-- One freeze per humanoid: each track's real speed is saved once, and only the last hit stop to
-- run out restores it. Two hit stops overlapping (two hits within 50 ms) used to save speed 0 the
-- second time and "restore" it last - the strike, or the walk/run loop, then stayed frozen until
-- it ended: punches hung mid-swing for up to 4 s and legs stood still under a running body.
local hitStops = setmetatable({}, { __mode = "k" })

function AnimationModule.applyHitStop(humanoid, duration)
	if not humanoid or not animationTracks[humanoid] then return end

	local freeze = hitStops[humanoid]
	if not freeze then
		freeze = { token = 0, speeds = {} }
		hitStops[humanoid] = freeze
	end
	freeze.token += 1
	local token = freeze.token

	for _, track in pairs(animationTracks[humanoid]) do
		if track.IsPlaying and freeze.speeds[track] == nil then
			freeze.speeds[track] = track.Speed
			track:AdjustSpeed(0)
		end
	end

	task.delay(duration, function()
		if freeze.token ~= token then return end -- a later hit stop extends the freeze
		for track, originalSpeed in pairs(freeze.speeds) do
			if track.IsPlaying and track.Speed == 0 then
				track:AdjustSpeed(originalSpeed)
			end
		end
		freeze.speeds = {}
	end)
end

-- Get the raw track (for .Stopped events etc)
function AnimationModule.getTrack(humanoid, animIdOrPath)
	local animId = animIdOrPath
	if type(animIdOrPath) == "string" and animIdOrPath:find("%.") then
		local ac = getAnimationConfig()
		local entry = ac and ac.get(animIdOrPath)
		if entry and entry.id then animId = trackIdFor(entry) end
	end
	return getTrack(humanoid, animId)
end

-- Return an already loaded track without allocating a new one
function AnimationModule.getExistingTrack(humanoid, animIdOrPath)
	local animId = animIdOrPath
	if type(animIdOrPath) == "string" and animIdOrPath:find("%.") then
		local ac = getAnimationConfig()
		local entry = ac and ac.get(animIdOrPath)
		if entry and entry.id then animId = trackIdFor(entry) end
	end
	return animationTracks[humanoid] and animationTracks[humanoid][animId] or nil
end

-- Adjust playback speed of a currently playing track safely
function AnimationModule.adjustSpeed(humanoid, animIdOrPath, newSpeed)
	local track = AnimationModule.getExistingTrack(humanoid, animIdOrPath)
	if track and track.IsPlaying then
		local speedMult = workspace:GetAttribute("GameSpeedMultiplier") or 1.0
		track:SetAttribute("BaseTrackSpeed", newSpeed)
		track:AdjustSpeed(newSpeed * speedMult)
	end
end

-- Cleanup when a humanoid is destroyed
function AnimationModule.cleanup(humanoid)
	if animationTracks[humanoid] then
		for _, track in pairs(animationTracks[humanoid]) do
			track:Stop(0)
			track:Destroy()
		end
		animationTracks[humanoid] = nil
	end
end

-- Live speed adjustment for all playing tracks when speed multiplier changes
local Workspace = game:GetService("Workspace")
Workspace:GetAttributeChangedSignal("GameSpeedMultiplier"):Connect(function()
	local speedMult = Workspace:GetAttribute("GameSpeedMultiplier") or 1.0
	for hum, tracks in pairs(animationTracks) do
		if hum and hum.Parent then
			for _, tr in pairs(tracks) do
				if tr and tr.IsPlaying then
					local baseSpd = tr:GetAttribute("BaseTrackSpeed") or 1.0
					tr:AdjustSpeed(baseSpd * speedMult)
				end
			end
		end
	end
end)

return AnimationModule
