local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local character = player.CharacterAdded:Wait()
local humanoid = character:WaitForChild("Humanoid")
local rootPart = character:WaitForChild("HumanoidRootPart")

-- Track previous Y velocity to detect hard landings
local lastVelocityY = 0

-- Damping settings
local landingThreshold = -10    -- Minimum falling speed to count as "hard landing"
local dampingSpeed = 0.1        -- How fast to reduce Y velocity (smaller = smoother)
local bounceFactor = 0.3      -- Small reverse bounce factor

-- Function to apply smooth landing damping
local function smoothLanding()
	local velocity = rootPart.AssemblyLinearVelocity
	local currentY = velocity.Y

	-- Detect hard landing
	if lastVelocityY < landingThreshold and (currentY > 0 or humanoid:GetState() == Enum.HumanoidStateType.Landed) then
		-- Smoothly reduce Y velocity and add a tiny natural bounce
		local targetY = 0
		local newY = currentY + (targetY - currentY) * dampingSpeed + (-currentY * bounceFactor)
		rootPart.AssemblyLinearVelocity = Vector3.new(velocity.X, newY, velocity.Z)
	end

	lastVelocityY = currentY
end

-- Connect to Heartbeat for real-time velocity checks
local connection = RunService.Heartbeat:Connect(function()
	-- Apply smooth landing damping
	smoothLanding()

	-- Optional: smooth falling for more natural weight
	if humanoid:GetState() == Enum.HumanoidStateType.Freefall then
		local vel = rootPart.AssemblyLinearVelocity
		rootPart.AssemblyLinearVelocity = vel:Lerp(vel * Vector3.new(1, 0.95, 1), 0.05)
	end
end)

-- Reconnect on respawn
player.CharacterAdded:Connect(function(newChar)
	character = newChar
	humanoid = newChar:WaitForChild("Humanoid")
	rootPart = newChar:WaitForChild("HumanoidRootPart")
	lastVelocityY = 0
end)
