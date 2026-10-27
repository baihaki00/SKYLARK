--// States.lua
-- Every state by its name, one table for all of QuinCore: `return States.Chase` instead of
-- `return require(script.Parent:WaitForChild("ChaseState"))`. A state is loaded the first time it
-- is asked for (states name each other, so they cannot all require each other at the top).
-- A name with no state behind it is an error at once, naming it - before, a typo was an error only
-- when that line ran, and Main's pcall turned it into Idle with a warn.
--   States.Chase          the state module (error if there is none)
--   States.has(name)      true if `name` is a state (or an alias)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local folder = ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("States")

-- Old names other scripts still send (GameModeManager's test duel)
local ALIASES = {
	Test = "Idle",
}

local States = {}

local function moduleFor(name)
	return type(name) == "string" and folder:FindFirstChild((ALIASES[name] or name) .. "State") or nil
end

function States.has(name)
	return moduleFor(name) ~= nil
end

setmetatable(States, {
	__index = function(self, name)
		local module = moduleFor(name)
		if not module then
			error("[States] no state named " .. tostring(name), 2)
		end
		local state = require(module)
		rawset(self, name, state)
		return state
	end,
})

return States
