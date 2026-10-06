--// PilotInput.lua
-- What a player asks of the Quin they pilot (Player Quin match mode). Only the inputs differ from
-- an AI Quin: the body, its states (PilotedState in place of the AI's decisions; Knockback,
-- Recovery and Death as for every Quin), its locomotion and its strikes are the AI's own.
--
-- The client (StarterPlayerScripts.PilotClient) sends, over the RemoteEvent ReplicatedStorage.PilotInput:
--   "move", direction (flat Vector3, zero to stop), pace ("walk" | "jog" | "run")
--   "guard", held (boolean)
--   "action", name ("Strike" | "Dash" | "Slide" | "Jump")
-- A Quin is piloted by the player whose UserId is in its PilotedBy attribute; input for any
-- other Quin is ignored. The server owns the body throughout (no network ownership change).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local PilotInput = {}

local ACTIONS = { Strike = true, Dash = true, Slide = true, Jump = true }
local PACES = { walk = true, jog = true, run = true }
local MAX_QUEUED = 3

local inputs = setmetatable({}, { __mode = "k" }) -- Quin -> { move, pace, guard, queue, at }

local function stateFor(quin)
	local s = inputs[quin]
	if not s then
		s = { move = Vector3.zero, pace = "jog", guard = false, queue = {}, at = 0 }
		inputs[quin] = s
	end
	return s
end

-- The Quin this player pilots, or nil
function PilotInput.quinOf(player)
	local folder = Workspace:FindFirstChild("QuinServer")
	if not folder then return nil end
	for _, quin in ipairs(folder:GetChildren()) do
		if quin:GetAttribute("PilotedBy") == player.UserId then
			return quin
		end
	end
	return nil
end

-- The current input of a piloted Quin (move, pace, guard)
function PilotInput.get(quin)
	return stateFor(quin)
end

-- The actions asked for since the last call, oldest first
function PilotInput.takeActions(quin)
	local s = stateFor(quin)
	local queue = s.queue
	s.queue = {}
	return queue
end

function PilotInput.clear(quin)
	inputs[quin] = nil
end

-- Creates the RemoteEvent and listens. Called once from Server.server.lua (a script that lives
-- all session).
function PilotInput.start()
	local remote = ReplicatedStorage:FindFirstChild("PilotInput")
	if not remote then
		remote = Instance.new("RemoteEvent")
		remote.Name = "PilotInput"
		remote.Parent = ReplicatedStorage
	end
	remote.OnServerEvent:Connect(function(player, kind, a, b)
		local quin = PilotInput.quinOf(player)
		if not quin then return end
		local s = stateFor(quin)
		s.at = os.clock()
		if kind == "move" then
			if typeof(a) ~= "Vector3" or a.X ~= a.X or a.Z ~= a.Z then return end
			local flat = Vector3.new(a.X, 0, a.Z)
			s.move = flat.Magnitude > 1 and flat.Unit or flat
			if PACES[b] then s.pace = b end
		elseif kind == "guard" then
			s.guard = a == true
		elseif kind == "action" then
			if ACTIONS[a] and #s.queue < MAX_QUEUED then
				table.insert(s.queue, a)
			end
		end
	end)
end

return PilotInput
