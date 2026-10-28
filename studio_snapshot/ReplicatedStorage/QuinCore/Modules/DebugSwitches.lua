--// DebugSwitches
-- The Studio debug labels and probes that used to be Workspace attributes typed by hand, as live
-- switches in the Spectator HUD (QuinDebugHUD). The server owns the attributes (the code that
-- reads them runs there); a client asks through DebugSwitchEvent and only an Admin is heard.
-- Switching a label off also takes down the labels already drawn.
--
-- Scope (owner 2026-10-28: "this quin / all quin"): Workspace DebugScopeQuin names the one Quin the
-- labels and prints are for (the HUD sets it to the selected Quin); unset, every Quin. The code
-- that draws or prints checks it (DebugSwitches.inScope, or the same test inline).
-- The Look / Gait / Foot switches write a value on the Quin that the HUD shows as a label over its
-- head (QuinDebugHUD); Tactical prints go to the Output.

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local QuinCore = ReplicatedStorage:WaitForChild("QuinCore")

local DebugSwitches = {}

-- attribute, label in the HUD, label instances to clear when switched off
DebugSwitches.List = {
	{ attribute = "PointDebug", label = "Pointing labels", tags = { "PointTag" } },
	{ attribute = "InterestDebug", label = "Interest labels", tags = { "InterestTag" } },
	{ attribute = "LookDebug", label = "Look reason labels" },
	{ attribute = "GaitDebug", label = "Gait side labels" },
	{ attribute = "FootDebug", label = "Foot plant labels" },
	{ attribute = "TacticalDebugEnabled", label = "Tactical prints (Output)" },
}

DebugSwitches.SCOPE = "DebugScopeQuin"

function DebugSwitches.inScope(model)
	local scope = Workspace:GetAttribute(DebugSwitches.SCOPE)
	return scope == nil or (model ~= nil and model.Name == scope)
end

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
		if attribute == DebugSwitches.SCOPE then
			if player:GetAttribute("SkylarkRole") ~= "Admin" then return end
			Workspace:SetAttribute(DebugSwitches.SCOPE, type(value) == "string" and value or nil)
			-- (the labels already over Quins now out of scope come down)
			for _, instance in ipairs(Workspace:GetDescendants()) do
				if instance:IsA("BillboardGui") and (instance.Name == "PointTag" or instance.Name == "InterestTag") then
					local model = instance:FindFirstAncestorWhichIsA("Model")
					if not DebugSwitches.inScope(model) then instance:Destroy() end
				end
			end
			return
		end
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

	-- the one Quin's name, or nil for every Quin
	function DebugSwitches.requestScope(name)
		event():FireServer(DebugSwitches.SCOPE, name)
	end
end

return DebugSwitches
