--// GodPauseClient.client.lua
-- The god pause button (owner 2026-10-28): F4 or the pill at the top freezes the real game and
-- resumes it where it was (QuinCore Modules/GameFreeze). While frozen the cameras still fly
-- (B, the spectator camera) so the frozen fight can be walked round. Studio, Admins only.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

if not RunService:IsStudio() then return end

local player = Players.LocalPlayer
local Modules = ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules")
local GameClock = require(Modules:WaitForChild("GameClock"))
local GameFreeze = require(Modules:WaitForChild("GameFreeze")) -- (also starts this machine's side)

local gui = Instance.new("ScreenGui")
gui.Name = "GodPauseUI"
gui.ResetOnSpawn = false
gui.DisplayOrder = 60
gui.Parent = player:WaitForChild("PlayerGui")

local pill = Instance.new("TextButton")
pill.AnchorPoint = Vector2.new(0.5, 0)
pill.Position = UDim2.new(0.5, 0, 0, 10)
pill.Size = UDim2.new(0, 150, 0, 30)
pill.Font = Enum.Font.GothamBold
pill.TextSize = 12
pill.BorderSizePixel = 0
pill.Parent = gui
Instance.new("UICorner", pill).CornerRadius = UDim.new(0, 15)
local stroke = Instance.new("UIStroke", pill)
stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
stroke.Thickness = 1.5

local function refresh()
	local frozen = GameClock.frozen()
	pill.Visible = player:GetAttribute("SkylarkRole") == "Admin"
	pill.Text = frozen and "▶  RESUME  [F4]" or "||  FREEZE  [F4]"
	pill.BackgroundColor3 = frozen and Color3.fromRGB(60, 170, 255) or Color3.fromRGB(18, 22, 30)
	pill.TextColor3 = frozen and Color3.new(0, 0, 0) or Color3.fromRGB(235, 240, 255)
	stroke.Color = frozen and Color3.new(1, 1, 1) or Color3.fromRGB(60, 170, 255)
end
refresh()
GameClock.changed:Connect(refresh)
player:GetAttributeChangedSignal("SkylarkRole"):Connect(refresh)

pill.MouseButton1Click:Connect(function()
	GameFreeze.request("toggle")
end)
UserInputService.InputBegan:Connect(function(input)
	if input.KeyCode ~= Enum.KeyCode.F4 or UserInputService:GetFocusedTextBox() then return end
	if player:GetAttribute("SkylarkRole") == "Admin" then GameFreeze.request("toggle") end
end)
