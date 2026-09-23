--// AnimationModule.lua
-- Centralized animation loading, playback, and priority layering
-- Caches tracks per humanoid to prevent memory leaks
-- Single Source of Truth: ReplicatedStorage.QuinCore.AnimationConfig

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AnimationModule = {}

-- Cache: animationTracks[humanoid][animId] = AnimationTrack
local animationTracks = {}

-- Verified track lengths (seconds) to eliminate 0-length race conditions on initial frame
local KNOWN_TRACK_LENGTHS = {
	["rbxassetid://109837817595150"] = 3.867, -- Movement.Idle / Reactions.Block
	["rbxassetid://109090784752055"] = 0.467, -- Movement.Run
	["rbxassetid://133182359318358"] = 0.500, -- Movement.Dash
	["rbxassetid://74552125029304"]  = 1.033, -- Movement.WalkConfident (Legacy)
	["rbxassetid://117985748552966"] = 1.033, -- Movement.WalkConfident / WalkThug
	["rbxassetid://85622241844167"]  = 0.933, -- Movement.Jump
	["rbxassetid://79340771026707"]  = 0.767, -- Movement.Fall
	["rbxassetid://88475997278069"]  = 2.567, -- Movement.FallAirKnockback
	["rbxassetid://113219639247452"] = 0.833, -- Attacks.Punches.Punch1 / Uppercut / Specials
	["rbxassetid://79937990476934"]  = 1.000, -- Attacks.Punches.CrossLeft
	["rbxassetid://99362983788110"]  = 1.000, -- Attacks.Punches.CrossRight
	["rbxassetid://135206101877204"] = 1.200, -- Attacks.Punches.Hook
	["rbxassetid://84162023451491"]  = 1.167, -- Attacks.Kicks.HighKick
	["rbxassetid://71573540671127"]  = 1.133, -- Attacks.Kicks.LowKick
	["rbxassetid://87872094663324"]  = 0.933, -- Attacks.Kicks.PowerKick / Special1
	["rbxassetid://89487629068473"]  = 1.233, -- Attacks.Kicks.WheelDrive / Slam
	["rbxassetid://83869147275692"]  = 1.367, -- Reactions.HitLight / Reactions.Knockback
	["rbxassetid://82096408080514"]  = 1.300, -- Reactions.HitHeavy
	["rbxassetid://79207866638803"]  = 3.200, -- Reactions.GetUpGround
	["rbxassetid://82291519563301"]  = 1.033, -- Strafe.StrafeRightWalk
	["rbxassetid://71421932655009"]  = 1.033, -- Strafe.StrafeLeftWalk
	["rbxassetid://107962284182266"] = 0.667, -- Strafe.StrafeRightRun
	["rbxassetid://123318024844911"] = 0.667, -- Strafe.StrafeLeftRun
	["rbxassetid://110691224052109"] = 1.467, -- Strafe.StrafeRightTired
	["rbxassetid://91032818959845"]  = 1.467, -- Strafe.StrafeLeftTired
	["rbxassetid://81580688159305"]  = 1.000, -- Reactions.BlockFront
	["rbxassetid://71555510097974"]  = 1.000, -- Reactions.BlockLeft
	["rbxassetid://81446994688965"]  = 1.000, -- Reactions.BlockRight
	["rbxassetid://80496269227852"]  = 1.500, -- Reactions.Death
	["rbxassetid://122802842451487"] = 1.600, -- Reactions.DeathOnTheSpot
	["rbxassetid://129355316172688"] = 0.800, -- Movement.RunTurn180
	["rbxassetid://113556439462127"] = 0.900, -- Movement.IdleToRun1
	["rbxassetid://113571639405597"] = 0.900, -- Movement.IdleToRun2
	["rbxassetid://89227245782124"]  = 0.850, -- Movement.ArcRun30Rear
	["rbxassetid://80583167665730"]  = 1.100, -- Movement.FallStraight
	["rbxassetid://100662167599815"] = 1.000, -- Parkour.SkidOverOB
	["rbxassetid://90546747503310"]  = 0.950, -- Parkour.ProceduralJump1
	["rbxassetid://73976796270777"]  = 1.100, -- Parkour.ProceduralSlide1
	["rbxassetid://101210294612380"] = 1.100, -- Parkour.ProceduralSlide2
	["rbxassetid://131563762426355"] = 0.900, -- Tactics.ProceduralEvade1
	["rbxassetid://135253684509200"] = 0.900, -- Tactics.ProceduralEvade2
	["rbxassetid://131344167080457"] = 1.200, -- Reactions.KnockdownBehind
	["rbxassetid://131548528642488"] = 1.400, -- Attacks.Specials.ProceduralSmackDown
	["rbxassetid://136234480688142"] = 1.100, -- Parkour.LandingSoft
	["rbxassetid://110436967972328"] = 1.250, -- Parkour.LandingHard
	["rbxassetid://140160268770373"] = 1.350, -- Parkour.LandingSuperHero
	["rbxassetid://128158227118276"] = 1.800, -- Reactions.GetUpBackSlow
	["rbxassetid://95406088712190"]  = 1.000, -- Reactions.GetUpBackFast
	["rbxassetid://108624065264351"] = 1.200, -- Reactions.GetUpFromCrouch
	["rbxassetid://98616724907377"]  = 1.000, -- Awareness.LookingBehind
}

local KNOWN_NAMES = {
	["rbxassetid://109837817595150"] = "Idle",
	["rbxassetid://109090784752055"] = "Run",
	["rbxassetid://133182359318358"] = "Dash",
	["rbxassetid://74552125029304"]  = "WalkConfident",
	["rbxassetid://117985748552966"] = "WalkThug",
	["rbxassetid://85622241844167"]  = "Jump",
	["rbxassetid://79340771026707"]  = "Fall",
	["rbxassetid://88475997278069"]  = "FallAirKnockback",
	["rbxassetid://113219639247452"] = "Punch1",
	["rbxassetid://79937990476934"]  = "CrossLeft",
	["rbxassetid://99362983788110"]  = "CrossRight",
	["rbxassetid://135206101877204"] = "Hook",
	["rbxassetid://84162023451491"]  = "HighKick",
	["rbxassetid://71573540671127"]  = "LowKick",
	["rbxassetid://87872094663324"]  = "PowerKick",
	["rbxassetid://89487629068473"]  = "WheelDrive",
	["rbxassetid://83869147275692"]  = "HitLight",
	["rbxassetid://82096408080514"]  = "HitHeavy",
	["rbxassetid://79207866638803"]  = "GetUpGround",
	["rbxassetid://82291519563301"]  = "StrafeRightWalk",
	["rbxassetid://71421932655009"]  = "StrafeLeftWalk",
	["rbxassetid://107962284182266"] = "StrafeRightRun",
	["rbxassetid://123318024844911"] = "StrafeLeftRun",
	["rbxassetid://110691224052109"] = "StrafeRightTired",
	["rbxassetid://91032818959845"]  = "StrafeLeftTired",
	["rbxassetid://81580688159305"]  = "BlockFront",
	["rbxassetid://71555510097974"]  = "BlockLeft",
	["rbxassetid://81446994688965"]  = "BlockRight",
	["rbxassetid://80496269227852"]  = "Death",
	["rbxassetid://122802842451487"] = "DeathOnTheSpot",
	["rbxassetid://129355316172688"] = "RunTurn180",
	["rbxassetid://113556439462127"] = "IdleToRun1",
	["rbxassetid://113571639405597"] = "IdleToRun2",
	["rbxassetid://89227245782124"]  = "ArcRun30Rear",
	["rbxassetid://80583167665730"]  = "FallStraight",
	["rbxassetid://100662167599815"] = "SkidOverOB",
	["rbxassetid://90546747503310"]  = "ProceduralJump1",
	["rbxassetid://73976796270777"]  = "ProceduralSlide1",
	["rbxassetid://101210294612380"] = "ProceduralSlide2",
	["rbxassetid://131563762426355"] = "ProceduralEvade1",
	["rbxassetid://135253684509200"] = "ProceduralEvade2",
	["rbxassetid://131344167080457"] = "KnockdownBehind",
	["rbxassetid://131548528642488"] = "ProceduralSmackDown",
	["rbxassetid://136234480688142"] = "LandingSoft",
	["rbxassetid://110436967972328"] = "LandingHard",
	["rbxassetid://140160268770373"] = "LandingSuperHero",
	["rbxassetid://128158227118276"] = "GetUpBackSlow",
	["rbxassetid://95406088712190"]  = "GetUpBackFast",
	["rbxassetid://108624065264351"] = "GetUpFromCrouch",
	["rbxassetid://98616724907377"]  = "LookingBehind",
}

local LOCOMOTION_OVERLAY_IDS = {
	["rbxassetid://85622241844167"] = true, -- Jump / VaultObstacle
	["rbxassetid://79340771026707"] = true, -- Fall
	["rbxassetid://80583167665730"] = true, -- FallStraight
	["rbxassetid://88475997278069"] = true, -- FallAirKnockback
	["rbxassetid://83869147275692"] = true, -- BrakingStop / Slide
	["rbxassetid://129355316172688"] = true, -- RunTurn180 / Turn180Pivot
	["rbxassetid://89227245782124"] = true, -- ArcRun30Rear
	["rbxassetid://113556439462127"] = true, -- IdleToRun1 / StartSprint
	["rbxassetid://113571639405597"] = true, -- IdleToRun2
	["rbxassetid://136234480688142"] = true, -- LandingSoft / LedgeDropLanding
	["rbxassetid://110436967972328"] = true, -- LandingHard
	["rbxassetid://140160268770373"] = true, -- LandingSuperHero
	["rbxassetid://90546747503310"] = true, -- ProceduralJump1
	["rbxassetid://73976796270777"] = true, -- ProceduralSlide1
	["rbxassetid://101210294612380"] = true, -- ProceduralSlide2
	["rbxassetid://100662167599815"] = true, -- SkidOverOB
	["rbxassetid://98616724907377"] = true, -- RearThreatGlance / LookingBehind
}

-- Cyclical locomotion tracks whose gait cycle phase is synchronized across transitions
local PHASE_LOCKED_TRACK_IDS = {
	["rbxassetid://109090784752055"] = true, -- Movement.Run
	["rbxassetid://74552125029304"]  = true, -- Movement.WalkConfident
	["rbxassetid://117985748552966"] = true, -- Movement.WalkThug
	["rbxassetid://89227245782124"]  = true, -- Movement.ArcRun30Rear / Left / Right
	["rbxassetid://123318024844911"] = true, -- Strafe.StrafeLeftRun
	["rbxassetid://107962284182266"] = true, -- Strafe.StrafeRightRun
	["rbxassetid://71421932655009"]  = true, -- Strafe.StrafeLeftWalk
	["rbxassetid://82291519563301"]  = true, -- Strafe.StrafeRightWalk
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
local function getTrack(humanoid, animId)
	if not humanoid or not animId or animId == "" then return nil end
	local animator = ensureAnimator(humanoid)
	
	if not animationTracks[humanoid] then
		animationTracks[humanoid] = {}
	end
	
	if not animationTracks[humanoid][animId] then
		local anim = Instance.new("Animation")
		anim.AnimationId = animId
		local track = animator and animator:LoadAnimation(anim) or humanoid:LoadAnimation(anim)
		animationTracks[humanoid][animId] = track
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
	local entry = ac and ac.get("Movement.Idle")
	if not entry or not entry.id or entry.id == "" then return nil end

	local track = getTrack(humanoid, entry.id)
	if not track then return nil end

	track.Priority = Enum.AnimationPriority.Idle
	track.Looped = true

	if not track.IsPlaying then
		track:Play(entry.fadeTime or 0.2, 1, entry.speed or 1.0)
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

	return AnimationModule.play(humanoid, entry.id, prio, looped, finalSpeed, fadeTime, overlay)
end

-- Stop using a configuration dotPath
function AnimationModule.stopConfig(humanoid, dotPath, fadeOut)
	local ac = getAnimationConfig()
	local entry = ac and ac.get(dotPath)
	if entry and entry.id then
		AnimationModule.stop(humanoid, entry.id, fadeOut or entry.fadeTime or 0.15)
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
		if idsToStop[animId] and track.IsPlaying then
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
		if track.IsPlaying and (LOCOMOTION_OVERLAY_IDS[animId] or track:GetAttribute("IsLocomotionOverlay")) then
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
			animId = entry.id
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
	if PHASE_LOCKED_TRACK_IDS[animId] and animationTracks[humanoid] then
		for otherId, otherTrack in pairs(animationTracks[humanoid]) do
			if otherId ~= animId and otherTrack.IsPlaying and PHASE_LOCKED_TRACK_IDS[otherId] then
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
				elseif newPrioVal == Enum.AnimationPriority.Movement.Value and LOCOMOTION_OVERLAY_IDS[otherId] then
					-- Locomotion base running/walking resuming: clear any finished or lingering locomotion overlays (vaults, turns, slides, braking stops)
					otherTrack:Stop(fadeIn or 0.1)
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
		if track.IsPlaying and PHASE_LOCKED_TRACK_IDS[id] then
			local len = track.Length > 0 and track.Length or 0.8
			return (track.TimePosition % len) / len
		end
	end
	return 0
end

-- Stop a specific animation
function AnimationModule.stop(humanoid, animIdOrPath, fadeOut)
	if not animationTracks[humanoid] then return end
	local animId = animIdOrPath
	if type(animIdOrPath) == "string" and animIdOrPath:find("%.") then
		local ac = getAnimationConfig()
		local entry = ac and ac.get(animIdOrPath)
		if entry and entry.id then animId = entry.id end
	end
	local track = animationTracks[humanoid][animId]
	if track and track.IsPlaying then
		track:Stop(fadeOut or 0.15)
		local rt = getRuntimeTracer()
		if rt and humanoid and humanoid.Parent then
			local animName = resolveAnimFriendlyName(animIdOrPath)
			rt.checkpoint(humanoid.Parent, "StopTrack: " .. animName, 2)
		end
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
		if idsToStop[animId] and track.IsPlaying then
			track:Stop(fadeOut or 0.15)
		end
	end
end

-- Check if a specific animation is playing
function AnimationModule.isPlaying(humanoid, animIdOrPath)
	if not animationTracks[humanoid] then return false end
	local animId = animIdOrPath
	if type(animIdOrPath) == "string" and animIdOrPath:find("%.") then
		local ac = getAnimationConfig()
		local entry = ac and ac.get(animIdOrPath)
		if entry and entry.id then animId = entry.id end
	end
	local track = animationTracks[humanoid][animId]
	return track and track.IsPlaying
end

-- Query true effective duration in seconds (Length / speed)
function AnimationModule.getEffectiveDuration(humanoid, animIdOrPath, runtimeMultiplier)
	local animId = animIdOrPath
	local baseSpeed = 1.0
	if type(animIdOrPath) == "string" and animIdOrPath:find("%.") then
		local ac = getAnimationConfig()
		local entry = ac and ac.get(animIdOrPath)
		if entry and entry.id then
			animId = entry.id
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
function AnimationModule.applyHitStop(humanoid, duration)
	if not humanoid or not animationTracks[humanoid] then return end
	
	local playingTracks = {}
	for _, track in pairs(animationTracks[humanoid]) do
		if track.IsPlaying then
			playingTracks[track] = track.Speed
			track:AdjustSpeed(0)
		end
	end
	
	task.delay(duration, function()
		if not humanoid or not humanoid.Parent then return end
		for track, origSpeed in pairs(playingTracks) do
			if track.IsPlaying then
				track:AdjustSpeed(origSpeed)
			end
		end
	end)
end

-- Get the raw track (for .Stopped events etc)
function AnimationModule.getTrack(humanoid, animIdOrPath)
	local animId = animIdOrPath
	if type(animIdOrPath) == "string" and animIdOrPath:find("%.") then
		local ac = getAnimationConfig()
		local entry = ac and ac.get(animIdOrPath)
		if entry and entry.id then animId = entry.id end
	end
	return getTrack(humanoid, animId)
end

-- Return an already loaded track without allocating a new one
function AnimationModule.getExistingTrack(humanoid, animIdOrPath)
	local animId = animIdOrPath
	if type(animIdOrPath) == "string" and animIdOrPath:find("%.") then
		local ac = getAnimationConfig()
		local entry = ac and ac.get(animIdOrPath)
		if entry and entry.id then animId = entry.id end
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
