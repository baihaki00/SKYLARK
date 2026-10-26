--// QuinWardrobeService.server.lua
-- The owner dresses their Quins (PlayerMenu > MY QUINS > WARDROBE). The outfit is saved on the
-- QuinInstance (Outfit) and worn at every spawn (QuinSpawner -> QuinWardrobe.dressSpawn); a Quin
-- with no outfit wears a random one each spawn. Remote ArenaNetwork.QuinWardrobe:
--   "get", slot          -> true, { Gender, Outfit (nil = random) }
--   "set", slot, outfit  -> true, msg   (outfit nil or {} = back to random; entries checked by
--                                        QuinWardrobe.clean: real items, right slot, right fit)
-- A Quin of that id standing in the world is re-dressed at once.
-- (Clothes are free for now: the shop, prices and owned copies come later - CLOTHING_PIPELINE.md.)

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local QuinCore = ReplicatedStorage:WaitForChild("QuinCore")
local QuinWardrobe = require(QuinCore.Modules:WaitForChild("QuinWardrobe"))
local QuinDataStoreService = require(QuinCore.Modules:WaitForChild("QuinDataStoreService"))
local QuinRosterService = require(ServerScriptService:WaitForChild("QuinRosterService"))

local function markDirty(quin)
    local _, userId = QuinDataStoreService.findQuinById(quin.QuinId)
    if userId and QuinDataStoreService.markDirty then
        QuinDataStoreService.markDirty(userId)
    end
end

local function redressLive(quin)
    for _, m in ipairs(Workspace:GetDescendants()) do
        if m:IsA("Model") and m:GetAttribute("QuinId") == quin.QuinId then
            if type(quin.Outfit) == "table" and next(quin.Outfit) then
                QuinWardrobe.dress(m, quin.Outfit)
            else
                QuinWardrobe.dress(m, QuinWardrobe.random(m:GetAttribute("Gender") or quin.Gender or "Male"))
            end
        end
    end
end

local function get(player, slot)
    local quin = QuinRosterService.getQuinInSlot(player, tonumber(slot) or 0)
    if not quin then
        return false, "No Quin in that slot."
    end
    return true, { Gender = quin.Gender or "Male", Outfit = quin.Outfit, QuinId = quin.QuinId }
end

local function set(player, slot, outfit)
    local quin = QuinRosterService.getQuinInSlot(player, tonumber(slot) or 0)
    if not quin then
        return false, "No Quin in that slot."
    end
    local clean = QuinWardrobe.clean(outfit, quin.Gender or "Male")
    quin.Outfit = next(clean) and clean or nil
    markDirty(quin)
    redressLive(quin)
    return true, quin.Outfit and ("Quin #" .. quin.QuinId:sub(3, 6) .. " will wear this.")
        or ("Quin #" .. quin.QuinId:sub(3, 6) .. " will dress at random.")
end

local ArenaNetwork = ReplicatedStorage:WaitForChild("ArenaNetwork")
local remote = ArenaNetwork:FindFirstChild("QuinWardrobe")
if not remote then
    remote = Instance.new("RemoteFunction")
    remote.Name = "QuinWardrobe"
    remote.Parent = ArenaNetwork
end
local busyRequest = {}
remote.OnServerInvoke = function(player, action, a, b)
    if busyRequest[player] then
        return false, "One moment..."
    end
    busyRequest[player] = true
    local ok, r1, r2 = pcall(function()
        if action == "get" then
            return get(player, a)
        elseif action == "set" then
            return set(player, a, b)
        end
        return false, "Unknown request"
    end)
    busyRequest[player] = nil
    if not ok then
        warn("[QuinWardrobe] " .. tostring(r1))
        return false, "Something went wrong"
    end
    return r1, r2
end

Players.PlayerRemoving:Connect(function(player)
    busyRequest[player] = nil
end)
