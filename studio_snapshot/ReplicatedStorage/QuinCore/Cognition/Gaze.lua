--// Cognition.Gaze
-- Where the Quin's head points, up or down. Quins have no eyes (mannequin heads): the head
-- is the sensor. Sight has a vertical field of view around this
-- pitch (Senses), so what is high above - a jumper, a Quin on a platform - or far below a
-- platform is only seen when the Quin is looking that way:
--   following  it watches its target wherever the target goes
--   resting    level on the ground; down over the edge when it stands on high ground
--   glance     a short look at something that happened (owner 2026-10-27: never a mindless
--              look at the sky): a Quin high overhead nearby (a jumper, a duel, a dive - it hears
--              it) draws the head to it, more surely for aware Quins; mid-chase only an enemy
--              does, mid-fight nothing does. On high ground it also looks down over the edge.
-- While it glances up it does not see what is level with it: looking has a price.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local QuinCore = ReplicatedStorage:WaitForChild("QuinCore")
local CombatConfig = require(QuinCore:WaitForChild("CombatConfig"))
local SpatialModule = require(QuinCore:WaitForChild("Modules"):WaitForChild("SpatialModule"))
local PlatformCatalogue = require(QuinCore:WaitForChild("Modules"):WaitForChild("PlatformCatalogue"))

local Gaze = {}

-- States in which a Quin has no attention to spare for looking around
local ENGAGED_STATES = { Fight = true, Knockback = true, Recovery = true, ProjectileJump = true, MidAirClash = true, Special = true, BeamStruggle = true }
-- States busy with a fight: only an enemy overhead is worth a look
local ACTIVE_STATES = { Chase = true, Circling = true, Retreat = true }

local Workspace = game:GetService("Workspace")

local function gcfg(cfg, key, default)
	local v = cfg[key]
	if v == nil then return default end
	return v
end

-- Between looks down over the edge of high ground (more often for aware Quins)
local function nextEdgeDelay(quinModel, cfg)
	local awareness = quinModel:GetAttribute("Pers_Awareness") or 0.65
	local interval = cfg.GazeGlanceIntervalMax + (cfg.GazeGlanceIntervalMin - cfg.GazeGlanceIntervalMax) * awareness
	return interval * (0.7 + math.random() * 0.6)
end

-- The nearest Quin high overhead within hearing (nil: nothing up there). activeOnly: enemies only
local function overheadCue(quinModel, eye, targetName, cfg, activeOnly)
	local folder = Workspace:FindFirstChild("QuinServer")
	if not folder then return nil end
	local myTeam = quinModel:GetAttribute("Team") or "None"
	local range, height = gcfg(cfg, "GazeCueRange", 160), gcfg(cfg, "GazeCueHeight", 15)
	local best, bestDist
	for _, other in ipairs(folder:GetChildren()) do
		if other ~= quinModel and other.Name ~= targetName then
			local root = other:FindFirstChild("HumanoidRootPart")
			local hum = other:FindFirstChildOfClass("Humanoid")
			if root and hum and hum.Health > 0 then
				local offset = root.Position - eye
				local flatDist = Vector3.new(offset.X, 0, offset.Z).Magnitude
				local team = other:GetAttribute("Team") or "None"
				local enemy = myTeam == "None" or team ~= myTeam
				if offset.Y > height and flatDist < range and (enemy or not activeOnly) and (not bestDist or flatDist < bestDist) then
					best, bestDist = other, flatDist
				end
			end
		end
	end
	return best
end

-- Returns { pitch = degrees (up positive), mode = "following" | "resting" | "glance", onHighGround }
function Gaze.update(board, quinModel, rootPart, targetModel, now)
	local cfg = CombatConfig.Cognition
	local gaze = board.gaze
	if not gaze then
		gaze = { pitch = 0, mode = "resting", glanceUntil = 0, glancePitch = 0, nextGlance = now, edgeAt = now + nextEdgeDelay(quinModel, cfg) }
		board.gaze = gaze
	end

	local platform = PlatformCatalogue.under(rootPart.Position, 12)
	local onHighGround = platform ~= nil and platform.heightAboveArenaFloor >= cfg.GazeHighGround

	local pitch = onHighGround and cfg.GazeDownPitch or 0
	local mode = "resting"

	-- Its target, where it believes the target is
	local targetName = targetModel and targetModel.Name or quinModel:GetAttribute("CurrentTarget")
	if targetName and targetName ~= "" then
		for _, contact in ipairs(board.contacts.enemies) do
			if contact.model.Name == targetName then
				local offset = contact.position - SpatialModule.getEyePosition(rootPart)
				if offset.Magnitude > 1 then
					pitch = math.clamp(math.deg(math.asin(math.clamp(offset.Y / offset.Magnitude, -1, 1))), -cfg.GazeMaxPitch, cfg.GazeMaxPitch)
					mode = "following"
				end
				break
			end
		end
	end

	local state = quinModel:GetAttribute("CurrentState") or ""
	-- Team coordination step 4: a Quin that takes on a job for an ally (rescue, cut off, flank,
	-- join) first glances at that ally, so the intent can be read (TargetingModule PackIntent)
	local intentAt = quinModel:GetAttribute("PackIntentAt")
	if intentAt and intentAt ~= gaze.intentAt then
		gaze.intentAt = intentAt
		local ally = not ENGAGED_STATES[state] and now >= gaze.glanceUntil and gcfg(cfg, "GazeIntentGlance", true)
			and (workspace:FindFirstChild("QuinServer") or workspace):FindFirstChild(quinModel:GetAttribute("PackIntentAlly") or "")
		local aRoot = ally and ally:FindFirstChild("HumanoidRootPart")
		if aRoot then
			local offset = aRoot.Position - SpatialModule.getEyePosition(rootPart)
			if offset.Magnitude > 1 then
				gaze.glanceAt = ally
				gaze.glancePitch = math.clamp(math.deg(math.asin(math.clamp(offset.Y / offset.Magnitude, -1, 1))), -cfg.GazeMaxPitch, cfg.GazeMaxPitch)
				gaze.glanceUntil = now + cfg.GazeGlanceDuration
				gaze.nextGlance = gaze.glanceUntil + gcfg(cfg, "GazeCueCheck", 0.4)
			end
		end
	end
	-- Callouts: the one that shouts looks at what it called; one that hears may look that way
	local call = board.called and board.called.at ~= gaze.calledAt and board.called
	local heard = board.heard and board.heard.at ~= gaze.heardAt and board.heard
	if call then gaze.calledAt = call.at end
	if heard then gaze.heardAt = heard.at end
	local lookAt = call and call.enemy
		or (heard and math.random() < gcfg(cfg, "CalloutGlanceChance", 0.6) and heard.enemy)
	local lRoot = lookAt and not ENGAGED_STATES[state] and now >= gaze.glanceUntil and lookAt:FindFirstChild("HumanoidRootPart")
	if lRoot then
		local offset = lRoot.Position - SpatialModule.getEyePosition(rootPart)
		if offset.Magnitude > 1 then
			gaze.glanceAt = lookAt
			gaze.glancePitch = math.clamp(math.deg(math.asin(math.clamp(offset.Y / offset.Magnitude, -1, 1))), -cfg.GazeMaxPitch, cfg.GazeMaxPitch)
			gaze.glanceUntil = now + cfg.GazeGlanceDuration
			gaze.nextGlance = gaze.glanceUntil + gcfg(cfg, "GazeCueCheck", 0.4)
		end
	end
	if ENGAGED_STATES[state] then
		gaze.glanceUntil = 0 -- a fight takes the head back at once
	elseif now >= gaze.nextGlance and now >= gaze.glanceUntil then
		gaze.nextGlance = now + gcfg(cfg, "GazeCueCheck", 0.4)
		local eye = SpatialModule.getEyePosition(rootPart)
		local active = ACTIVE_STATES[state] == true
		local cue = overheadCue(quinModel, eye, targetName, cfg, active)
		gaze.cues = gaze.cues or setmetatable({}, { __mode = "k" })
		if cue and now >= (gaze.cues[cue] or 0) then
			gaze.cues[cue] = now + gcfg(cfg, "GazeCueCooldown", 5)
			local awareness = quinModel:GetAttribute("Pers_Awareness") or 0.65
			local chance = (gcfg(cfg, "GazeCueChanceBase", 0.25) + gcfg(cfg, "GazeCueChanceAwareness", 0.6) * awareness) * (active and gcfg(cfg, "GazeCueActiveShare", 0.5) or 1)
			if math.random() < chance then
				local offset = cue.HumanoidRootPart.Position - eye
				gaze.glanceAt = cue
				gaze.glancePitch = math.clamp(math.deg(math.asin(math.clamp(offset.Y / offset.Magnitude, -1, 1))), -cfg.GazeMaxPitch, cfg.GazeMaxPitch)
				gaze.glanceUntil = now + cfg.GazeGlanceDuration
				gaze.nextGlance = gaze.glanceUntil + gcfg(cfg, "GazeCueCheck", 0.4)
			end
		elseif onHighGround and not active and now >= (gaze.edgeAt or 0) then
			-- standing on high ground: now and then a look down over the edge
			gaze.edgeAt = now + nextEdgeDelay(quinModel, cfg)
			gaze.glanceAt = nil
			gaze.glancePitch = cfg.GazeDownPitch
			gaze.glanceUntil = now + cfg.GazeGlanceDuration
		end
	end
	if now < gaze.glanceUntil then
		pitch = gaze.glancePitch
		mode = "glance"
	end

	gaze.pitch = pitch
	gaze.mode = mode
	gaze.onHighGround = onHighGround
	-- Published for the head (LookController) and the debug overlay
	if math.abs((quinModel:GetAttribute("GazePitch") or 0) - pitch) >= 3 then
		quinModel:SetAttribute("GazePitch", math.round(pitch))
	end
	if quinModel:GetAttribute("GazeMode") ~= mode then
		quinModel:SetAttribute("GazeMode", mode)
	end
	-- the Quin it glanced at (up at one overhead, or at the ally it helps): the head looks at it
	local at = mode == "glance" and gaze.glanceAt and gaze.glanceAt.Parent and gaze.glanceAt.Name or nil
	if quinModel:GetAttribute("GazeAt") ~= at then
		quinModel:SetAttribute("GazeAt", at)
	end
	return gaze
end

return Gaze
