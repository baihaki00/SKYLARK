--// JumpLog.lua
-- Team coordination step 5 (owner 2026-10-27: "creatures obsessed with jumping ... I want quins
-- to be intentional"): every jump, leap and dash says why. A Quin's last one is published as
-- attributes (JumpKind, JumpReason, JumpAt) for the debug HUD; counts per kind and reason are kept
-- on ServerStorage.JumpLog (attributes "<kind>__<reason>", never replicated) so a probe can read
-- jumps per minute and find the ones with no reason ("?").
--   JumpLog.mark(fighter, kind, reason)
--   JumpLog.why(fighter) - the reason a caller set (attribute JumpWhy) and clears it
--   JumpLog.reset() - clears the counts (a probe starts a window)

local GameClock = require(game:GetService("ReplicatedStorage"):WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("GameClock")) -- (the game's clock: a freeze stops it)
local ServerStorage = game:GetService("ServerStorage")
local RunService = game:GetService("RunService")

local JumpLog = {}

local function store()
	local folder = ServerStorage:FindFirstChild("JumpLog")
	if not folder then
		folder = Instance.new("Configuration")
		folder.Name = "JumpLog"
		folder:SetAttribute("Since", GameClock.now())
		folder.Parent = ServerStorage
	end
	return folder
end

function JumpLog.mark(fighter, kind, reason)
	if not RunService:IsServer() or not fighter then return end
	reason = (reason and reason ~= "") and reason or "?"
	fighter:SetAttribute("JumpKind", kind)
	fighter:SetAttribute("JumpReason", reason)
	fighter:SetAttribute("JumpAt", GameClock.tick())
	-- (attribute names take letters, digits and _ only: "Dash__dash_to_close_the_gap")
	local folder = store()
	local key = (kind .. "__" .. reason):gsub("[^%w_]", "_"):sub(1, 100)
	-- (a count never breaks the jump it counts)
	pcall(function()
		folder:SetAttribute(key, (folder:GetAttribute(key) or 0) + 1)
	end)
end

-- The reason the caller gave just before (Quin attribute JumpWhy), taken so a later jump does
-- not reuse it
function JumpLog.why(fighter)
	local why = fighter and fighter:GetAttribute("JumpWhy")
	if why then fighter:SetAttribute("JumpWhy", nil) end
	return why
end

function JumpLog.reset()
	local folder = ServerStorage:FindFirstChild("JumpLog")
	if folder then folder:Destroy() end
	store()
end

return JumpLog
