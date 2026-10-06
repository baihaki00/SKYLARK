--// HitStop.lua
-- Impact as timing (QUIN_CREATURE_DESIGN.md phase 6: the Madhouse layer). On a landed strike both
-- bodies' action clips hold for a moment (the strike at full extension, the hit taken at its first
-- frame), then run on. Heavier hits hold longer. No effect, no flash: a beat of stillness that
-- makes the contact read.
--   duration = Impact_HitStopBase + Impact_HitStopHeavyExtra x weight (0 light .. 1 heavy)
-- Only Action-priority tracks hold (strikes and reactions), not the gait or the idle.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CombatConfig = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("CombatConfig"))

local HitStop = {}

local HELD = {
	[Enum.AnimationPriority.Action] = true, [Enum.AnimationPriority.Action2] = true,
	[Enum.AnimationPriority.Action3] = true, [Enum.AnimationPriority.Action4] = true,
}

local function hold(model, seconds)
	local humanoid = model and model:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if not animator then return end
	local held = {}
	for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
		if HELD[track.Priority] and track.Speed > 0 then
			table.insert(held, { track = track, speed = track.Speed })
			track:AdjustSpeed(0)
		end
	end
	if #held == 0 then return end
	task.delay(seconds, function()
		for _, h in ipairs(held) do
			-- (only if nothing else has set its speed meanwhile)
			if h.track.IsPlaying and h.track.Speed == 0 then
				h.track:AdjustSpeed(h.speed)
			end
		end
	end)
end

-- A landed strike: weight 0 (a jab) .. 1 (a heavy kick, a finisher). Returns the hold in seconds
-- (0 when off), so the attacker's own timing can wait for its clip.
function HitStop.apply(attacker, victim, weight)
	if CombatConfig.Impact_HitStop == false then return 0 end
	if workspace:GetAttribute("Ablate_HitStop") and game:GetService("RunService"):IsStudio() then return 0 end
	local seconds = (CombatConfig.Impact_HitStopBase or 0.045) + (CombatConfig.Impact_HitStopHeavyExtra or 0.06) * math.clamp(weight or 0, 0, 1)
	hold(attacker, seconds)
	hold(victim, seconds)
	return seconds
end

return HitStop
