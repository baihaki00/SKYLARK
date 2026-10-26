--// DebugReadouts.lua
-- Debug-only attributes (the trace lines, retreat scores, target reasons a debug screen shows) cost
-- the same as real ones: every write is sent to every player. In a 16v16 they were ~800 of the
-- ~2800 attribute changes a second (benchmark, 2026-10-26). So they are written only while somebody
-- has a debug screen open (QuinDebugHUD's cards report it), or while Workspace attribute
-- DebugReadoutsAlways = true (Studio tools, tests).
--   server: DebugReadouts.on() -> bool; DebugReadouts.set(model, name, value) (a no-op when off)
--   client: DebugReadouts.report(open) - a debug screen opened / closed on this machine;
--           DebugReadouts.on() reads Workspace attribute DebugReadouts (set by the server)
-- Only admins (SkylarkCanAdmin) or Studio sessions can switch it on.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local DebugReadouts = {}

local IS_SERVER = RunService:IsServer()
local EVENT_NAME = "DebugReadoutsEvent"
local holder = script.Parent.Parent -- (QuinCore)

local openBy = {} -- server: [player] = true while their debug screen is open
local count = 0

function DebugReadouts.on()
	if Workspace:GetAttribute("DebugReadoutsAlways") == true then
		return true
	end
	if IS_SERVER then
		return count > 0
	end
	return Workspace:GetAttribute("DebugReadouts") == true
end

function DebugReadouts.set(model, name, value)
	if DebugReadouts.on() then
		model:SetAttribute(name, value)
	end
end

if IS_SERVER then
	local event = holder:FindFirstChild(EVENT_NAME)
	if not event then
		event = Instance.new("RemoteEvent")
		event.Name = EVENT_NAME
		event.Parent = holder
	end
	local function recount()
		count = 0
		for _ in pairs(openBy) do
			count += 1
		end
		local on = count > 0
		if (Workspace:GetAttribute("DebugReadouts") == true) ~= on then
			Workspace:SetAttribute("DebugReadouts", on or nil)
		end
	end
	event.OnServerEvent:Connect(function(player, open)
		if not (player:GetAttribute("SkylarkCanAdmin") == true or RunService:IsStudio()) then
			return
		end
		openBy[player] = open == true or nil
		recount()
	end)
	Players.PlayerRemoving:Connect(function(player)
		openBy[player] = nil
		recount()
	end)
else
	local last = nil
	function DebugReadouts.report(open)
		open = open == true
		if open == last then
			return
		end
		last = open
		task.spawn(function()
			local event = holder:WaitForChild(EVENT_NAME, 30)
			if event then
				event:FireServer(open)
			end
		end)
	end
end

return DebugReadouts
