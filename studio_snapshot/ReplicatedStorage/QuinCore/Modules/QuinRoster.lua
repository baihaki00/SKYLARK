--// QuinRoster.lua
-- Every Quin (CollectionService tag "Quin"), fetched once a frame and shared. The AI asked
-- CollectionService:GetTagged("Quin") hundreds of times a second in a 16v16, each call a new
-- 32-entry table (27 ms of server time a second, benchmark 2026-10-26: performance plan step B).
--   QuinRoster.all() -> the list. READ ONLY: every caller this frame gets the same table.
--                       (an empty list is a fresh table, so a caller may fill its own fallback)
-- A Quin removed this frame can still be listed until the next frame: callers check .Parent and
-- Health as they did with GetTagged.
-- (Refreshed by game time, not by tag signals: a connection made in a module dies with the Quin
-- whose Main first required it - quincore-shared-loop-ownership.)

local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

local QuinRoster = {}

local TAG = "Quin"
local list = {}
local listTime = -1

function QuinRoster.all()
	local now = Workspace.DistributedGameTime
	if now ~= listTime then
		listTime = now
		list = CollectionService:GetTagged(TAG)
	end
	if #list == 0 then
		return {}
	end
	return list
end

return QuinRoster
