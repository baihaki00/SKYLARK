local RunService = game:GetService("RunService")

-- The "true" tells Roblox to search inside ALL folders and subfolders in workspace
local TestingBox5 = workspace:FindFirstChild("MOVINGPLATFORM", true)

TestingBox5.Anchored = false

local centerPos = TestingBox5.Position
local radius = 10 -- Distance from center (in studs)
local speed = 1.5 -- Radians per second (lower = slower)
local angle = 0

local attachment = Instance.new("Attachment", TestingBox5)

-- 1. Keeps the platform flat and prevents it from tipping or spinning
local alignOrientation = Instance.new("AlignOrientation")
alignOrientation.Mode = Enum.OrientationAlignmentMode.OneAttachment
alignOrientation.Attachment0 = attachment
alignOrientation.CFrame = TestingBox5.CFrame.Rotation
alignOrientation.RigidityEnabled = true
alignOrientation.Parent = TestingBox5

-- 2. Pulls the platform smoothly along the circular path
local alignPosition = Instance.new("AlignPosition")
alignPosition.Mode = Enum.PositionAlignmentMode.OneAttachment
alignPosition.Attachment0 = attachment
alignPosition.MaxForce = math.huge
alignPosition.MaxVelocity = math.huge
alignPosition.Responsiveness = 50 -- Higher = tighter tracking
alignPosition.Position = centerPos + Vector3.new(radius, 0, 0)
alignPosition.Parent = TestingBox5

-- 3. Update the target position along a horizontal circle (X and Z)
RunService.PreSimulation:Connect(function(deltaTime)
	angle += speed * deltaTime

	local offsetX = math.cos(angle) * radius
	local offsetZ = math.sin(angle) * radius

	-- Change (offsetX, 0, offsetZ) to (offsetX, offsetZ, 0) for a vertical Ferris wheel!
	alignPosition.Position = centerPos + Vector3.new(offsetX, 0, offsetZ)
end)