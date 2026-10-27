--// Objectives.lua
-- What a mode puts on the field for Quins to fight over, as one Quin knows it (Lantern Siege,
-- brain step 4). A mode only publishes objects (Workspace.LanternSiege, built by the server's
-- LanternSiege module); the brain reads them here and weighs them in TaskChoice like any other
-- task. Nothing in the brain is scripted per mode.
--   Lantern   one glowing object. State Base (at the attackers' start), Carried, Dropped, Planted.
--   Shrines   where the attackers plant it (A, B).
-- What it knows is honest: a Lantern lying somewhere or burning in a Shrine glows for all to see;
-- one being carried is known to the attackers (it is theirs), and to a defender only where it
-- believes the carrier is (its own eyes, memory, a teammate's callout).

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local QuinCore = ReplicatedStorage:WaitForChild("QuinCore")
local Blackboard = require(QuinCore:WaitForChild("Cognition"):WaitForChild("Blackboard"))

local Objectives = {}

local function folder()
	local f = Workspace:FindFirstChild("LanternSiege")
	return f and f:GetAttribute("Live") == true and f or nil
end

function Objectives.active()
	return folder() ~= nil
end

-- nil outside a live round, else:
-- { role = "Attack" | "Defend", carrier = model|nil, iCarry = bool,
--   lantern = { state, position (nil when it can't know) },
--   shrines = { { name, position } }, planted = { shrine, position, progress 0..1, contested } | nil }
function Objectives.view(quin)
	local f = folder()
	if not f then return nil end
	local lanternPart = f:FindFirstChild("Lantern")
	if not lanternPart then return nil end
	local attackers = f:GetAttribute("Attackers")
	local role = quin:GetAttribute("Team") == attackers and "Attack" or "Defend"
	local state = lanternPart:GetAttribute("State") or "Base"
	local carrierName = lanternPart:GetAttribute("Carrier")
	local carrier = carrierName and (Workspace:FindFirstChild("QuinServer") or Workspace):FindFirstChild(carrierName) or nil

	local position = lanternPart.Position
	if state == "Carried" and role == "Defend" then
		position = nil
		local board = Blackboard.peek(quin)
		for _, contact in ipairs(board and board.contacts and board.contacts.enemies or {}) do
			if contact.model == carrier then position = contact.position break end
		end
	end

	local shrines = {}
	local shrineFolder = f:FindFirstChild("Shrines")
	for _, s in ipairs(shrineFolder and shrineFolder:GetChildren() or {}) do
		if s:IsA("BasePart") then
			table.insert(shrines, { name = s.Name, position = s.Position })
		end
	end
	table.sort(shrines, function(a, b) return a.name < b.name end)

	local planted = nil
	if state == "Planted" then
		planted = { shrine = f:GetAttribute("PlantedShrine"), position = lanternPart.Position,
			progress = f:GetAttribute("ActivateProgress") or 0, contested = f:GetAttribute("Contested") == true }
	end
	return {
		role = role, carrier = carrier, iCarry = carrier == quin,
		lantern = { state = state, position = position },
		shrines = shrines, planted = planted,
	}
end

return Objectives
