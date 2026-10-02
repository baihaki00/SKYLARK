--// JoinCameraCover (ReplicatedFirst)
-- On join the first frames render before the character exists: the camera has no subject and
-- sits at Roblox's default spot looking at the world origin (0, 9, 4) for ~0.3 s, then snaps
-- to the character - a flash of some other view. The screen stays black from the first frame
-- until the camera is on the character, then fades in.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local FADE_TIME = 0.25
local TIMEOUT = 15 -- never hold the screen black longer than this

local player = Players.LocalPlayer
local gui = Instance.new("ScreenGui")
gui.Name = "JoinCameraCover"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.DisplayOrder = 10000

local cover = Instance.new("Frame")
cover.Size = UDim2.fromScale(1, 1)
cover.BackgroundColor3 = Color3.new(0, 0, 0)
cover.BorderSizePixel = 0
cover.Parent = gui
gui.Parent = player:WaitForChild("PlayerGui")

local function cameraOnCharacter()
	local camera = workspace.CurrentCamera
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local subject = camera and camera.CameraSubject
	return root ~= nil and subject ~= nil and subject:IsDescendantOf(character)
		and (camera.CFrame.Position - root.Position).Magnitude < 60
end

local started = os.clock()
while not cameraOnCharacter() and os.clock() - started < TIMEOUT do
	RunService.RenderStepped:Wait()
end
RunService.RenderStepped:Wait() -- one settled frame on the character

local fade = TweenService:Create(cover, TweenInfo.new(FADE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = 1 })
fade.Completed:Once(function()
	gui:Destroy()
end)
fade:Play()
