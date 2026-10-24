--// AvatarSprint.client.lua
-- Hold Shift to sprint (60, walk 16) on your own avatar (the Roblox player walking the world, not a piloted Quin:
-- PlayerQuinController / PilotClient run their own sprint).
-- The sprint only owns WalkSpeed between the walk and sprint speeds: anything that sets it outside
-- (a prep room terminal stopping you at 0, an arena freezing players) wins, and the sprint waits
-- until the speed comes back.
-- Shift is the sprint key, so Roblox's shift-lock (also Shift) is off: StarterPlayer.EnableMouseLockOption
-- = false in the place (a LocalScript may not change it). Our cameras are scripted anyway.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local StarterPlayer = game:GetService("StarterPlayer")

local player = Players.LocalPlayer

local WALK = StarterPlayer.CharacterWalkSpeed -- (16)
local SPRINT = 60 -- (owner: fast for now, while testing the world)
local RAMP = 8 -- how fast the speed eases in and out (per second, exponential)

local function shiftHeld()
    if UserInputService:GetFocusedTextBox() then
        return false
    end
    return UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
end

RunService.Heartbeat:Connect(function(dt)
    local character = player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if not humanoid or humanoid.Health <= 0 then
        return
    end
    local speed = humanoid.WalkSpeed
    -- (walk..sprint is ours: a terminal that saved a mid-sprint speed and gives it back still eases down)
    if speed < WALK - 0.01 or speed > SPRINT + 0.01 then
        return -- someone else holds the speed: wait for it to come back
    end
    local moving = humanoid.MoveDirection.Magnitude > 0.1
    local goal = (shiftHeld() and moving) and SPRINT or WALK
    local nextSpeed = speed + (goal - speed) * (1 - math.exp(-RAMP * dt))
    if math.abs(goal - nextSpeed) < 0.05 then
        nextSpeed = goal
    end
    if nextSpeed ~= speed then
        humanoid.WalkSpeed = nextSpeed
    end
end)
