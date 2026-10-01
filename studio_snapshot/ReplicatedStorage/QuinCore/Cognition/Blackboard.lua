--// Cognition.Blackboard
-- What one Quin currently holds in its head: the latest result of every cognition layer.
-- States and decision code read from here instead of querying the world themselves.
--   percepts    this tick's sensed Quins (Senses)
--   attention   ranked focus list and capacity (Attention)
--   tracks      remembered Quins by model (Memory)
--   contacts    { allies, enemies } the Quin knows about right now (Memory)
--   self        own condition (SelfAwareness)
--   environment retreat room, platforms (EnvironmentAwareness)
--   situation   tactical summary (SituationAwareness)

local Blackboard = {}

local boards = setmetatable({}, { __mode = "k" })

function Blackboard.get(quinModel)
	local board = boards[quinModel]
	if not board then
		board = { tracks = {}, contacts = { allies = {}, enemies = {} }, history = {} }
		boards[quinModel] = board
	end
	return board
end

-- nil when the Quin has not been through the pipeline yet
function Blackboard.peek(quinModel)
	return boards[quinModel]
end

return Blackboard
