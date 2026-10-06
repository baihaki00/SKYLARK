--// PilotInput.lua
-- What a player asks of the Quin they pilot (Player Quin match mode). Only the inputs differ from
-- an AI Quin: the body, its states (PilotedState in place of the AI's decisions; Knockback,
-- Recovery and Death as for every Quin), its locomotion and its strikes are the AI's own.
--
-- The client (StarterPlayerScripts.PilotClient) sends, over the RemoteEvent ReplicatedStorage.PilotInput:
--   "move", direction (flat Vector3, zero to stop), pace ("walk" | "jog" | "run")
--   "guard", held (boolean)
--   "action", name ("Strike" | "Dash" | "Slide" | "Jump" | "JumpRelease")
--   "pj", style (1 arc | 2 high launch), aim point (Vector3), aimed Quin's name (or nil)
--   "dive", aim point, aimed Quin's name (or nil): dive now (a style 2 projectile jump)
--   "look", yaw, pitch (degrees): where the player's view points (published on the Quin as
--           PilotLookYaw / PilotLookPitch: its head looks there for every other client)
-- A Quin is piloted by the player whose UserId is in its PilotedBy attribute; input for any
-- other Quin is ignored. The server owns the body throughout (no network ownership change).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local PilotInput = {}

local ACTIONS = { Strike = true, Dash = true, Slide = true, Jump = true, JumpRelease = true }
local PJ_STYLES = { [1] = true, [2] = true }
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

-- An aim from the client: a point, and the Quin under the crosshair (resolved to a model here)
local function readAim(point, targetName)
	if typeof(point) ~= "Vector3" or point.X ~= point.X or point.Y ~= point.Y or point.Z ~= point.Z or point.Magnitude > 1e5 then
		return nil
	end
	local folder = Workspace:FindFirstChild("QuinServer")
	local target = type(targetName) == "string" and folder and folder:FindFirstChild(targetName) or nil
	return { point = point, target = target, at = os.clock() }
end

-- The projectile jump asked for (style, point, target), once; nil if none (or older than 0.5 s)
function PilotInput.takeProjectileJump(quin)
	local s = stateFor(quin)
	local pj = s.pj
	s.pj = nil
	if pj and os.clock() - pj.at <= 0.5 then return pj end
	return nil
end

-- The dive asked for (point, target), once; nil if none (or older than 0.5 s)
function PilotInput.takeDive(quin)
	local s = inputs[quin]
	local dive = s and s.dive
	if s then s.dive = nil end
	if dive and os.clock() - dive.at <= 0.5 then return dive end
	return nil
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
	local function handle(quin, kind, a, b, c)
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
		elseif kind == "pj" then
			local aim = PJ_STYLES[a] and readAim(b, c)
			if aim then
				aim.style = a
				s.pj = aim
			end
		elseif kind == "dive" then
			s.dive = readAim(a, b)
		elseif kind == "look" then
			if type(a) == "number" and type(b) == "number" and a == a and b == b then
				quin:SetAttribute("PilotLookYaw", math.round(a))
				quin:SetAttribute("PilotLookPitch", math.round(math.clamp(b, -89, 89)))
			end
		end
	end
	remote.OnServerEvent:Connect(function(player, kind, a, b, c)
		local quin = PilotInput.quinOf(player)
		if quin then handle(quin, kind, a, b, c) end
	end)

	-- Studio test hook: Workspace attribute PilotTestInput = JSON {"kind":..., "a":..., "b":...,
	-- "c":...} drives the first piloted Quin through the same handler as a player's input (vectors
	-- as [x, y, z]). For tests without a keyboard (MCP), e.g.
	--   {"kind":"move","a":[0,0,-1],"b":"run"}   {"kind":"action","a":"Jump"}   {"kind":"pj","a":2,"b":[0,10,-500]}
	if game:GetService("RunService"):IsStudio() then
		Workspace:GetAttributeChangedSignal("PilotTestInput"):Connect(function()
			local raw = Workspace:GetAttribute("PilotTestInput")
			if type(raw) ~= "string" or raw == "" then return end
			Workspace:SetAttribute("PilotTestInput", nil)
			local ok, msg = pcall(function() return game:GetService("HttpService"):JSONDecode(raw) end)
			if not ok or type(msg) ~= "table" then return end
			local function arg(v)
				if type(v) == "table" and #v == 3 then return Vector3.new(v[1], v[2], v[3]) end
				return v
			end
			local folder = Workspace:FindFirstChild("QuinServer")
			for _, quin in ipairs(folder and folder:GetChildren() or {}) do
				if quin:GetAttribute("PilotedBy") then
					handle(quin, msg.kind, arg(msg.a), arg(msg.b), arg(msg.c))
					break
				end
			end
		end)
	end
end

return PilotInput
