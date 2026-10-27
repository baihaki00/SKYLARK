--// StateRequest.lua
-- How anything outside a Quin's current state tells it to change state: a hit sends the victim into
-- Knockback, a clash pulls the partner up, the brain orders a chase. One request waits at a time
-- (the ForceState attribute); Main takes it at the start of the Quin's next tick.
--   StateRequest.ask(quin, "Knockback", StateRequest.HIT, "why")  -> true if it now waits
--   StateRequest.take(quin) -> name, why   (Main; clears it)
-- A request waits unless something more important is already waiting: a social order or the
-- brain can no longer write over a Knockback set between ticks (before, the last write won, and a
-- Quin that had been hit walked on instead of flying back).
-- (Match control - ArenaSystemOrchestrator, LanternSiege, GameModeManager - still writes ForceState
-- directly: it always wins, as before.)

local StateRequest = {
	HIT = 90,       -- struck, tackled, smashed: Knockback
	CLASH = 80,     -- pulled into a mid-air clash
	REENTRY = 70,   -- off the arena floor / stuck in the air: back in
	GETUP = 60,     -- down on the ground: Recovery
	FOLLOW = 40,    -- its own move continues in another state (a launch into Airborne)
	COUNTER = 30,   -- a block turned into an immediate counter
	SOCIAL = 20,    -- the social layer sends it after someone
	BRAIN = 10,     -- the brain's own orders (idle, retreat, chase)
}

local States -- (loaded on first use: States requires every state, and states require this)

function StateRequest.ask(quin, stateName, priority, why)
	priority = priority or StateRequest.BRAIN
	local waiting = quin:GetAttribute("ForceState")
	if waiting ~= nil and waiting ~= "" and (quin:GetAttribute("ForceStatePriority") or 50) > priority then
		return false
	end
	quin:SetAttribute("ForceStatePriority", priority)
	quin:SetAttribute("ForceStateWhy", why)
	quin:SetAttribute("ForceState", stateName)
	return true
end

-- The waiting request, cleared. A name that is no state (a test mode long gone) is dropped with a warn.
function StateRequest.take(quin)
	local name = quin:GetAttribute("ForceState")
	if name == nil then return nil end
	local why = quin:GetAttribute("ForceStateWhy")
	quin:SetAttribute("ForceState", nil)
	quin:SetAttribute("ForceStatePriority", nil)
	quin:SetAttribute("ForceStateWhy", nil)
	if name == "" then return nil end
	States = States or require(script.Parent:WaitForChild("States"))
	if not States.has(name) then
		warn(string.format("[StateRequest] %s: no state named %s (dropped)", quin.Name, tostring(name)))
		return nil
	end
	return name, why
end

return StateRequest
