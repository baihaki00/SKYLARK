--// DebugSwitches
-- The Studio debug labels and probes that used to be Workspace attributes typed by hand, as live
-- switches in the Spectator HUD (QuinDebugHUD). The server owns the attributes (the code that
-- reads them runs there); a client asks through DebugSwitchEvent and only an Admin is heard.
-- Switching a label off also takes down the labels already drawn.

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local QuinCore = ReplicatedStorage:WaitForChild("QuinCore")

local DebugSwitches = {}

-- attribute, label in the HUD, label instances to clear when switched off
DebugSwitches.List = {
	{ attribute = "PointDebug", label = "Pointing labels", tags = { "PointTag" } },
	{ attribute = "InterestDebug", label = "Interest labels", tags = { "InterestTag" } },
	{ attribute = "TacticalDebugEnabled", label = "Tactical prints" },
	{ attribute = "LookDebug", label = "Look prints" },
	{ attribute = "GaitDebug", label = "Gait prints" },
	{ attribute = "FootDebug", label = "Foot prints" },
}

local byAttribute = {}
for _, switch in ipairs(DebugSwitches.List) do
	byAttribute[switch.attribute] = switch
end

function DebugSwitches.isOn(attribute)
	return Workspace:GetAttribute(attribute) == true
end

local function event()
	return QuinCore:WaitForChild("DebugSwitchEvent")
end

if RunService:IsServer() then
	if not QuinCore:FindFirstChild("DebugSwitchEvent") then
		local remote = Instance.new("RemoteEvent")
		remote.Name = "DebugSwitchEvent"
		remote.Parent = QuinCore
	end
	event().OnServerEvent:Connect(function(player, attribute, value)
		local switch = byAttribute[attribute]
		if not switch or player:GetAttribute("SkylarkRole") ~= "Admin" then return end
		local on = value == true
		Workspace:SetAttribute(attribute, on or nil)
		if not on and switch.tags then
			for _, instance in ipairs(Workspace:GetDescendants()) do
				if instance:IsA("BillboardGui") and table.find(switch.tags, instance.Name) then
					instance:Destroy()
				end
			end
		end
	end)
else
	function DebugSwitches.request(attribute, value)
		event():FireServer(attribute, value == true)
	end
end

return DebugSwitches
