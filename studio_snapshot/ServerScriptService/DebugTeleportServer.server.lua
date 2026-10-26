--// DebugTeleportServer.server.lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local event = ReplicatedStorage:WaitForChild("DebugTeleportEvent")

event.OnServerEvent:Connect(function(player, targetPos)
	if typeof(targetPos) ~= "Vector3" then return end
	
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if hrp then
		-- Pre-stream the target area to avoid client streaming delay
		pcall(function()
			player:RequestStreamAroundAsync(targetPos, 3)
		end)
		
		char:PivotTo(CFrame.new(targetPos))
		hrp.AssemblyLinearVelocity = Vector3.zero
		hrp.AssemblyAngularVelocity = Vector3.zero
	end
end)
