--// SkylarkSpectate.server.lua
-- Watching a round from a seat, bought at an Arena Terminal (Spectate; the other choice is Register
-- Quin: ArenaRegistration). SKYLARK_ECONOMY_DESIGN.md:
--   * Pick a side (Alpha / Beta) and a seat: Normal (100 SC, the side's stands) or VIP (300 SC,
--     one of the side's VIP boxes). Paid from the wallet (SkylarkWallet).
--   * A ticket lasts the round (Workspace ArenaRound) and ends at IDLE. Asking again for the same
--     seat takes you back to it for free; Normal -> VIP on the same side pays the difference.
--   * VIP boxes: only VIP ticket holders of that side (and Admins) may be inside: the door is solid
--     for everyone else (SpectateClient) and anyone inside without one is walked out to the
--     hallway. Their terminals (VipTerminalPrompt) give the drone cameras and the free-fly camera,
--     only while inside the box (SpectateClient asks "vip" here; SkylarkRoleClient allows them).
-- Player attributes the clients read: SpectateSeat ("Normal" / "VIP"), SpectateSide ("TeamAlpha" /
-- "TeamBeta"). Remote: ArenaNetwork.Spectate (RemoteFunction) "buy", side, seat | "vip".

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Wallet = require(ServerScriptService:WaitForChild("SkylarkWallet"))
local PrepRoom = require(ServerScriptService:WaitForChild("ArenaPrepRoom"))

local PRICES = { Normal = 100, VIP = 300 }
local TERMINAL_RANGE = 16

local rng = Random.new()
local tickets = {} -- [userId] = { side, seat, round, box }

local arena = Workspace:WaitForChild("argoniaonion"):WaitForChild("ArenaOne")
local ground = arena:FindFirstChild("ArenaGround")
local CENTER = ground and ground.Position or Vector3.new(0, 0, -438)

-- ============================================================================
-- PLACES
-- ============================================================================

local stands = {} -- the CrowdArea benches
local boxes = {} -- { model, center, size, cf, ground, hallway, door, side }
for _, d in ipairs(arena:GetDescendants()) do
    if d.Name == "CrowdArea" and d:IsA("BasePart") then
        table.insert(stands, d)
    elseif d.Name == "VipBox" and d:IsA("Model") then
        local cf, size = d:GetBoundingBox()
        local box = {
            model = d,
            cf = cf,
            size = size,
            ground = d:FindFirstChild("PreparationRoomGround"),
            hallway = d:FindFirstChild("PreparationRoomHallWay"),
            door = d:FindFirstChild("Door"),
            x = cf.Position.X,
        }
        if box.door then
            box.door.CanCollide = false -- (each player's machine makes it solid for them: SpectateClient)
        end
        for _, t in ipairs(d:GetDescendants()) do
            if t.Name == "PrepRoomTerminal" and t:IsA("BasePart") and not t:FindFirstChild("VipTerminalPrompt") then
                local prompt = Instance.new("ProximityPrompt")
                prompt.Name = "VipTerminalPrompt"
                prompt.ActionText = "Cameras"
                prompt.ObjectText = "VIP Terminal"
                prompt.HoldDuration = 0
                prompt.MaxActivationDistance = 8
                prompt.RequiresLineOfSight = false
                prompt.Parent = t
            end
        end
        table.insert(boxes, box)
    end
end
print(string.format("[SkylarkSpectate] %d stand benches, %d VIP boxes", #stands, #boxes))

local function sideSign(team)
    return PrepRoom.sideOf(team)
end

local function standSpot(team)
    local sign = sideSign(team)
    local mine, total = {}, 0
    for _, part in ipairs(stands) do
        if (part.Position.X >= 0 and 1 or -1) == sign then
            local length = math.max(part.Size.X, part.Size.Z)
            table.insert(mine, { part = part, length = length })
            total += length
        end
    end
    if #mine == 0 then
        return nil
    end
    local roll = rng:NextNumber(0, total)
    local chosen = mine[#mine]
    for _, m in ipairs(mine) do
        roll -= m.length
        if roll <= 0 then
            chosen = m
            break
        end
    end
    local part = chosen.part
    local alongX = part.Size.X >= part.Size.Z
    local half = (alongX and part.Size.X or part.Size.Z) / 2 - 3
    local offset = rng:NextNumber(-half, half)
    local pos = part.Position + (alongX and Vector3.new(offset, 0, 0) or Vector3.new(0, 0, offset))
        + Vector3.new(0, part.Size.Y / 2 + 3.5, 0)
    return CFrame.lookAt(pos, Vector3.new(CENTER.X, pos.Y, CENTER.Z))
end

-- Inside the box itself: over its floor (not the hallway in front of its door), under its roof
local function insideBox(box, position)
    local g = box.ground
    if not g then
        return false
    end
    local localPos = g.CFrame:PointToObjectSpace(position)
    return math.abs(localPos.X) <= g.Size.X / 2 and math.abs(localPos.Z) <= g.Size.Z / 2
        and localPos.Y > 0 and localPos.Y < 16
end

local function boxOf(position)
    for _, box in ipairs(boxes) do
        if insideBox(box, position) then
            return box
        end
    end
    return nil
end

local function boxesFor(team)
    local sign = sideSign(team)
    local list = {}
    for _, box in ipairs(boxes) do
        if (box.x >= 0 and 1 or -1) == sign then
            table.insert(list, box)
        end
    end
    return list
end

local function vipSpot(team)
    -- the side's emptiest box
    local best, bestCount = nil, math.huge
    for _, box in ipairs(boxesFor(team)) do
        local count = 0
        for _, t in pairs(tickets) do
            if t.box == box then
                count += 1
            end
        end
        if count < bestCount then
            best, bestCount = box, count
        end
    end
    if not best or not best.ground then
        return nil
    end
    local g = best.ground
    local pos = g.Position + Vector3.new(rng:NextNumber(-3, 3), g.Size.Y / 2 + 3.5, rng:NextNumber(-6, 6))
    return CFrame.lookAt(pos, Vector3.new(CENTER.X, pos.Y, pos.Z)), best
end

local function teleport(player, cf)
    local character = player.Character
    if character and character.PrimaryPart then
        character:PivotTo(cf)
        character.PrimaryPart.AssemblyLinearVelocity = Vector3.zero
    end
end

-- ============================================================================
-- TICKETS
-- ============================================================================

local function publish(player)
    local t = tickets[player.UserId]
    player:SetAttribute("SpectateSeat", t and t.seat or nil)
    player:SetAttribute("SpectateSide", t and t.side or nil)
end

local function arenaOn()
    local phase = Workspace:GetAttribute("ArenaPhase")
    return phase ~= nil and phase ~= "IDLE"
end

local function nearTerminal(player)
    local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
    if not root then
        return false
    end
    for _, part in ipairs(Workspace:GetDescendants()) do
        if part.Name == "ArenaTerminal" and part:IsA("BasePart") and (part.Position - root.Position).Magnitude <= TERMINAL_RANGE then
            return true
        end
    end
    return false
end

local function buy(player, side, seat)
    if side ~= "TeamAlpha" and side ~= "TeamBeta" then
        return false, "Pick a side"
    end
    if not PRICES[seat] then
        return false, "Pick a seat"
    end
    if not arenaOn() then
        return false, "No match on. Seats open when the arena opens."
    end
    if not nearTerminal(player) then
        return false, "Use an Arena Terminal"
    end
    if player:GetAttribute("ArenaEntered") == true then -- (spectate the event or take part, not both)
        return false, "Your Quins are in this event. Watch them from your prep room."
    end
    local round = Workspace:GetAttribute("ArenaRound") or 0
    local old = tickets[player.UserId]
    if old and old.round ~= round then
        old = nil
    end
    local price = PRICES[seat]
    if old and old.side == side then
        if old.seat == seat or (old.seat == "VIP" and seat == "Normal") then
            price = 0 -- (back to a seat you already have)
        else
            price = PRICES[seat] - PRICES[old.seat] -- (an upgrade)
        end
    end
    local cf, box
    if seat == "VIP" then
        cf, box = vipSpot(side)
    else
        cf = standSpot(side)
    end
    if not cf then
        return false, "No seats on that side"
    end
    if price > 0 then
        local ok, result = Wallet.spend(player, price, seat .. " seat " .. side)
        if not ok then
            return false, result
        end
    end
    tickets[player.UserId] = { side = side, seat = (old and old.side == side and old.seat == "VIP") and "VIP" or seat, round = round, box = box or (old and old.box) }
    publish(player)
    teleport(player, cf)
    local where = seat == "VIP" and "VIP box" or "stands"
    return true, price > 0 and string.format("Paid %d SC. Enjoy the fight from the %s!", price, where)
        or ("Back to your seat in the " .. where)
end

local function vipAccess(player)
    if player:GetAttribute("SkylarkRole") == "Admin" then
        return true
    end
    local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
    local t = tickets[player.UserId]
    local box = root and boxOf(root.Position)
    if not (box and t and t.seat == "VIP") then
        return false
    end
    return (box.x >= 0 and 1 or -1) == sideSign(t.side)
end

local ArenaNetwork = ReplicatedStorage:WaitForChild("ArenaNetwork")
local remote = ArenaNetwork:FindFirstChild("Spectate")
if not remote then
    remote = Instance.new("RemoteFunction")
    remote.Name = "Spectate"
    remote.Parent = ArenaNetwork
end
local busy = {}
remote.OnServerInvoke = function(player, action, a, b)
    if busy[player] then
        return false, "One moment..."
    end
    busy[player] = true
    local ok, result, message = pcall(function()
        if action == "buy" then
            return buy(player, a, b)
        elseif action == "vip" then
            return vipAccess(player)
        end
        return false, "Unknown request"
    end)
    busy[player] = nil
    if not ok then
        warn("[SkylarkSpectate] " .. tostring(result))
        return false, "Something went wrong"
    end
    return result, message
end

-- The round is over: tickets end
Workspace:GetAttributeChangedSignal("ArenaPhase"):Connect(function()
    if Workspace:GetAttribute("ArenaPhase") == "IDLE" then
        tickets = {}
        for _, player in ipairs(Players:GetPlayers()) do
            publish(player)
        end
    end
end)

Players.PlayerRemoving:Connect(function(player)
    tickets[player.UserId] = nil
end)

-- VIP boxes: no ticket for this side's box, out to the hallway
task.spawn(function()
    while true do
        task.wait(1)
        -- (whose box is whose, for the doors on each player's machine)
        local alphaSign = sideSign("TeamAlpha")
        for _, box in ipairs(boxes) do
            box.model:SetAttribute("VipTeam", (box.x >= 0 and 1 or -1) == alphaSign and "TeamAlpha" or "TeamBeta")
        end
        for _, player in ipairs(Players:GetPlayers()) do
            local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
            local box = root and boxOf(root.Position)
            if box and player:GetAttribute("SkylarkRole") ~= "Admin" then
                local t = tickets[player.UserId]
                local mine = t and t.seat == "VIP" and (box.x >= 0 and 1 or -1) == sideSign(t.side)
                if not mine and box.hallway then
                    teleport(player, CFrame.new(box.hallway.Position + Vector3.new(0, 4, 0)))
                end
            end
        end
    end
end)
