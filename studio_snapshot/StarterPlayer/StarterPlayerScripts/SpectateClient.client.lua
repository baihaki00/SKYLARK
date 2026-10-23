--// SpectateClient.client.lua
-- The player's side of the VIP boxes (SkylarkSpectate):
--   * each box's door is solid on this machine unless you hold a VIP ticket for that side (or are
--     an Admin);
--   * a VIP Terminal (VipTerminalPrompt) asks the server for camera access: inside your box it
--     sets shared.VipAccess, which lets the drone cameras (V) and the free-fly camera (B) work
--     (SkylarkRoleClient, ArenaDroneClientController, SmoothCamera). Walking out of the box ends it.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local ProximityPromptService = game:GetService("ProximityPromptService")

local player = Players.LocalPlayer
local remote = ReplicatedStorage:WaitForChild("ArenaNetwork"):WaitForChild("Spectate", 30)

local arena = Workspace:WaitForChild("argoniaonion"):WaitForChild("ArenaOne")

-- (looked up each time: the boxes stream in after this script starts)
local function boxes()
    local list = {}
    for _, d in ipairs(arena:GetChildren()) do
        if d.Name == "VipBox" and d:IsA("Model") then
            table.insert(list, { model = d, door = d:FindFirstChild("Door"), ground = d:FindFirstChild("PreparationRoomGround") })
        end
    end
    return list
end

local function notify(text)
    pcall(function()
        StarterGui:SetCore("SendNotification", { Title = "VIP Box", Text = text, Duration = 6 })
    end)
end

local function isAdmin()
    return player:GetAttribute("SkylarkRole") == "Admin"
end

local function mayEnter(box)
    return isAdmin() or (player:GetAttribute("SpectateSeat") == "VIP"
        and player:GetAttribute("SpectateSide") == box.model:GetAttribute("VipTeam"))
end

local function inside(box)
    local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
    local g = box.ground
    if not (root and g) then
        return false
    end
    local p = g.CFrame:PointToObjectSpace(root.Position)
    return math.abs(p.X) <= g.Size.X / 2 and math.abs(p.Z) <= g.Size.Z / 2 and p.Y > 0 and p.Y < 16
end

ProximityPromptService.PromptTriggered:Connect(function(prompt)
    if prompt.Name ~= "VipTerminalPrompt" or not remote then
        return
    end
    local ok, allowed = pcall(function()
        return remote:InvokeServer("vip")
    end)
    if ok and allowed then
        shared.VipAccess = true
        notify("Cameras on: V for the drone cameras, B for the free camera. They stay on while you're in the box.")
    else
        notify("The VIP cameras are for VIP ticket holders, inside their box. Buy a VIP seat at an Arena Terminal.")
    end
end)

task.spawn(function()
    while true do
        task.wait(0.5)
        local inAny = false
        for _, box in ipairs(boxes()) do
            if box.door then
                box.door.CanCollide = not mayEnter(box)
            end
            if inside(box) and mayEnter(box) then
                inAny = true
            end
        end
        if shared.VipAccess and not inAny then
            shared.VipAccess = nil -- (left the box: the cameras end)
        end
    end
end)
