--// Cognition.Gaze
-- Where the Quin's head points, up or down. Quins have no eyes (mannequin heads): the head
-- is the sensor. Sight has a vertical field of view around this
-- pitch (Senses), so what is high above - a jumper, a Quin on a platform - or far below a
-- platform is only seen when the Quin is looking that way:
--   following  it watches its target wherever the target goes
--   resting    level on the ground; down over the edge when it stands on high ground
--   glance     every few seconds (more often for aware Quins, never mid-fight) a short look
--              at the sky; from high ground, alternately at the sky and at the ground
-- While it glances up it does not see what is level with it: looking has a price.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local QuinCore = ReplicatedStorage:WaitForChild("QuinCore")
local CombatConfig = require(QuinCore:WaitForChild("CombatConfig"))
local SpatialModule = require(QuinCore:WaitForChild("Modules"):WaitForChild("SpatialModule"))
local PlatformCatalogue = require(QuinCore:WaitForChild("Modules"):WaitForChild("PlatformCatalogue"))

local Gaze = {}

-- States in which a Quin has no attention to spare for looking around
local ENGAGED_STATES = { Fight = true, Knockback = true, Recovery = true, ProjectileJump = true, MidAirClash = true, Special = true, BeamStruggle = true }

local function nextGlanceDelay(quinModel, cfg)
	local awareness = quinModel:GetAttribute("Pers_Awareness") or 0.65
	local interval = cfg.GazeGlanceIntervalMax + (cfg.GazeGlanceIntervalMin - cfg.GazeGlanceIntervalMax) * awareness
	return interval * (0.7 + math.random() * 0.6)
end

-- Returns { pitch = degrees (up positive), mode = "following" | "resting" | "glance", onHighGround }
function Gaze.update(board, quinModel, rootPart, targetModel, now)
	local cfg = CombatConfig.Cognition
	local gaze = board.gaze
	if not gaze then
		gaze = { pitch = 0, mode = "resting", glanceUntil = 0, glancePitch = 0, nextGlance = now + nextGlanceDelay(quinModel, cfg), lookedUpLast = false }
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

	if now >= gaze.nextGlance and not ENGAGED_STATES[quinModel:GetAttribute("CurrentState") or ""] then
		gaze.nextGlance = now + nextGlanceDelay(quinModel, cfg)
		gaze.glanceUntil = now + cfg.GazeGlanceDuration
		if onHighGround and gaze.lookedUpLast then
			gaze.glancePitch = cfg.GazeDownPitch
			gaze.lookedUpLast = false
		else
			gaze.glancePitch = cfg.GazeSkyPitch
			gaze.lookedUpLast = true
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
	return gaze
end

return Gaze
