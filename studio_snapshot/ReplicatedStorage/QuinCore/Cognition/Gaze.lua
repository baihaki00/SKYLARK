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
local ENGAGED_STATES = { Fight = true, Knockback = true, Recovery = true, ProjectileJump = true, MidAirClash = true, Special = true }
-- States busy with a fight: only an enemy overhead is worth a look
local ACTIVE_STATES = { Chase = true, Circling = true, Retreat = true }

local Workspace = game:GetService("Workspace")
local Pers = require(game:GetService("ReplicatedStorage"):WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("Pers")) -- (personality reads + defaults, one place)
local QuinRoster = require(game:GetService("ReplicatedStorage"):WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("QuinRoster")) -- (GetTagged("Quin") once a frame, shared)

local function gcfg(cfg, key, default)
	local v = cfg[key]
	if v == nil then return default end
	return v
end

-- Between looks down over the edge of high ground (more often for aware Quins)
local function nextEdgeDelay(quinModel, cfg)
	local awareness = Pers.get(quinModel, "Awareness")
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
			and QuinRoster.byName(quinModel:GetAttribute("PackIntentAlly"))
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
			local awareness = Pers.get(quinModel, "Awareness")
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
	-- Gestures (owner 2026-10-27): small, on the head, eyes, a nod and the stance - never a clip that
	-- takes the legs - and only for something that happened:
	--   Alert        an enemy it did not know of a moment ago comes into sight: the head goes to
	--                it, the eyes open wide, it stands ready
	--   Ready        an enemy close while it holds a place: eyes narrowed on it, ready stance
	--   Acknowledge  an ally comes up to it: a look and a nod (below, with the greet)
	-- A fight takes them all back at once.
	gaze.known = gaze.known or setmetatable({}, { __mode = "k" })
	if ENGAGED_STATES[state] then
		gaze.gesture = nil
	elseif gcfg(cfg, "Gestures", true) ~= false then
		local closest, closestDist
		for _, contact in ipairs(board.contacts.enemies or {}) do
			local m = contact.model
			if contact.visible and m then
				local fresh = now - (gaze.known[m] or -math.huge) > gcfg(cfg, "GestureForgetTime", 8)
				gaze.known[m] = now
				local d = (contact.position - rootPart.Position).Magnitude
				if fresh and not ACTIVE_STATES[state] and now >= gaze.glanceUntil and d < gcfg(cfg, "GestureAlertRange", 120) then
					gaze.glanceAt = m
					local offset = contact.position - SpatialModule.getEyePosition(rootPart)
					gaze.glancePitch = offset.Magnitude > 1 and math.clamp(math.deg(math.asin(math.clamp(offset.Y / offset.Magnitude, -1, 1))), -cfg.GazeMaxPitch, cfg.GazeMaxPitch) or 0
					gaze.glanceUntil = now + gcfg(cfg, "GazeGreetDuration", 1.2)
					gaze.nextGlance = gaze.glanceUntil + gcfg(cfg, "GazeCueCheck", 0.4)
					gaze.gesture, gaze.gestureUntil = "Alert", now + 0.9
					quinModel:SetAttribute("CurrentIdleStance", "Ready")
					quinModel:SetAttribute("LastActivityTime", now)
					-- heard or felt, not seen: it turns round to see it (the head alone leaves the
					-- eyes' cone where it was; a guard heard steps behind it and stood on)
					if contact.channel ~= "sight" then
						quinModel:SetAttribute("TurnTo", contact.position)
						quinModel:SetAttribute("TurnUntil", Workspace:GetServerTimeNow() + gcfg(cfg, "TurnToHold", 1.6))
					end
				end
				if not closestDist or d < closestDist then closest, closestDist = m, d end
			end
		end
		if state == "Idle" and closest and closestDist < gcfg(cfg, "GestureReadyRange", 35)
			and (not gaze.gesture or now >= (gaze.gestureUntil or 0)) then
			gaze.gesture, gaze.gestureUntil = "Ready", now + 0.5
			quinModel:SetAttribute("CurrentIdleStance", "Ready")
			quinModel:SetAttribute("LastActivityTime", now)
		end
	end
	if gaze.gesture and now >= (gaze.gestureUntil or 0) then gaze.gesture = nil end

	-- Standing (owner 2026-10-27: "defenders don't look at each other"), in any mode, the head has
	-- something to do, and only things it has a reason for:
	--   greet  an ally that comes up to it draws a look (it saw it come)
	--   scan   otherwise it looks, one after another, where it believes enemies are or were (its
	--          own contacts: memory, callouts), and, on a post, across the way it watches. How long
	--          it holds each look is its habit: a restless Quin looks quickly, a steady one holds.
	local still = rootPart.AssemblyLinearVelocity.Magnitude < gcfg(cfg, "GazeStandSpeed", 4)
	if still and state == "Idle" and now >= gaze.glanceUntil and gcfg(cfg, "GazeStandLooks", true) ~= false then
		local serverNow = Workspace:GetServerTimeNow()
		gaze.greeted = gaze.greeted or setmetatable({}, { __mode = "k" })
		local greet
		for _, contact in ipairs(board.contacts.allies or {}) do
			local m = contact.model
			if m and contact.position and now >= (gaze.greeted[m] or 0)
				and (contact.position - rootPart.Position).Magnitude < gcfg(cfg, "GazeGreetRange", 20) then
				local v = m:FindFirstChild("HumanoidRootPart") and m.HumanoidRootPart.AssemblyLinearVelocity or Vector3.zero
				local toMe = rootPart.Position - contact.position
				if v.Magnitude > 4 and v:Dot(toMe) > 0 then greet = m break end
				gaze.greeted[m] = now + 1 -- (standing near it already: no need to look)
			end
		end
		if greet then
			gaze.greeted[greet] = now + gcfg(cfg, "GazeGreetCooldown", 10)
			gaze.gesture, gaze.gestureUntil = "Acknowledge", now + 1.2
			quinModel:SetAttribute("NodAt", serverNow + 0.25) -- (LookController: a nod, after the look lands)
			gaze.glanceAt = greet
			gaze.glancePitch = 0
			gaze.glanceUntil = now + gcfg(cfg, "GazeGreetDuration", 1.2)
			gaze.nextGlance = gaze.glanceUntil + gcfg(cfg, "GazeCueCheck", 0.4)
			gaze.lastLook = "greet"
		elseif serverNow >= (quinModel:GetAttribute("LookUntil") or 0) then
			local points = {}
			for _, contact in ipairs(board.contacts.enemies or {}) do
				if contact.position and not contact.visible then table.insert(points, contact.position) end
			end
			local face = quinModel:GetAttribute("ObjectiveFace")
			if typeof(face) == "Vector3" then
				local out = Vector3.new(face.X - rootPart.Position.X, 0, face.Z - rootPart.Position.Z)
				if out.Magnitude > 1 then
					for _, deg in ipairs({ -45, 0, 45 }) do
						table.insert(points, rootPart.Position + CFrame.fromAxisAngle(Vector3.yAxis, math.rad(deg)):VectorToWorldSpace(out.Unit) * 40)
					end
				end
			end
			if #points > 0 then
				gaze.scanIdx = (gaze.scanIdx or 0) + 1
				if gaze.scanIdx > #points then
					gaze.scanIdx = 1
					gaze.scanCycles = (gaze.scanCycles or 0) + 1
				end
				local restless = Pers.get(quinModel, "MobilityPreference")
				local hold = gcfg(cfg, "GazeScanHoldMin", 0.9) + gcfg(cfg, "GazeScanHoldSpan", 1.6) * (1 - restless)
				quinModel:SetAttribute("LookPoint", points[gaze.scanIdx])
				quinModel:SetAttribute("LookUntil", serverNow + hold)
				gaze.lastLook = "scan"
				mode = "scan"
			end
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
	if quinModel:GetAttribute("Gesture") ~= gaze.gesture then
		quinModel:SetAttribute("Gesture", gaze.gesture)
	end
	-- the Quin it glanced at (up at one overhead, or at the ally it helps): the head looks at it
	local at = mode == "glance" and gaze.glanceAt and gaze.glanceAt.Parent and gaze.glanceAt.Name or nil
	if quinModel:GetAttribute("GazeAt") ~= at then
		quinModel:SetAttribute("GazeAt", at)
	end
	return gaze
end

return Gaze
