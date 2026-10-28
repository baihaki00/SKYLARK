--// SkylarkRoles.server.lua
-- Two clear ways to be in the game (owner, 2026-10-23):
--   Player: a normal Roblox player. Doors follow the room rule, the arena barrier keeps them out,
--     and the Quin HUD, spectate keys, free cameras, drones and debug panels are off: Quins are
--     watched through a preparation room terminal only.
--   Admin: everything. Walks through any door and the arena barrier, and has every HUD and key.
-- The role is the player attribute "SkylarkRole" ("Player" / "Admin"), set here and read by the
-- barrier (ArenaBarrier), the doors (ArenaPrepRoom, PrepRoomClient) and every admin script
-- (SkylarkRoleClient and the key handlers). Everyone joins as a Player; "Play As Admin" asks for
-- Admin, "Play As Roblox Player" goes back. Who may be Admin: anyone in Studio, the place's
-- creator (or rank 254+ in a creator group), and user ids in Workspace attribute SkylarkAdmins
-- ("123,456"). They carry the attribute "SkylarkCanAdmin" (the role buttons show only for them).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local remote = ReplicatedStorage:FindFirstChild("SkylarkRole")
if not remote then
    remote = Instance.new("RemoteEvent")
    remote.Name = "SkylarkRole"
    remote.Parent = ReplicatedStorage
end

local function canAdmin(player)
    if RunService:IsStudio() then
        return true
    end
    if game.CreatorType == Enum.CreatorType.User and player.UserId == game.CreatorId then
        return true
    end
    if game.CreatorType == Enum.CreatorType.Group then
        local ok, rank = pcall(function()
            return player:GetRankInGroup(game.CreatorId)
        end)
        if ok and rank >= 254 then
            return true
        end
    end
    local list = Workspace:GetAttribute("SkylarkAdmins")
    return type(list) == "string" and ("," .. list:gsub("%s", "") .. ","):find("," .. player.UserId .. ",", 1, true) ~= nil
end

-- For now (owner 2026-10-28, "spawn me as admin everytime I enter the game"): in Studio everyone
-- joins as Admin. Workspace JoinAsPlayer = true: join as a Player again (to test the player side).
local function joinRole(player)
    if RunService:IsStudio() and Workspace:GetAttribute("JoinAsPlayer") ~= true and canAdmin(player) then
        return "Admin"
    end
    return "Player"
end

Players.PlayerAdded:Connect(function(player)
    player:SetAttribute("SkylarkCanAdmin", canAdmin(player))
    player:SetAttribute("SkylarkRole", joinRole(player))
end)
for _, player in ipairs(Players:GetPlayers()) do
    player:SetAttribute("SkylarkCanAdmin", canAdmin(player))
    if player:GetAttribute("SkylarkRole") == nil then
        player:SetAttribute("SkylarkRole", joinRole(player))
    end
end

remote.OnServerEvent:Connect(function(player, role)
    if role == "Admin" and player:GetAttribute("SkylarkCanAdmin") == true then
        player:SetAttribute("SkylarkRole", "Admin")
    elseif role == "Player" then
        player:SetAttribute("SkylarkRole", "Player")
    end
end)
