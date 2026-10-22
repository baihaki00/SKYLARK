--// ArenaPrepRoom.lua
-- The preparation room: the Workspace parts named "PreparationRoom" (32 pads on the arena walls,
-- 16 on each side, two floors). When a round's entrants are picked (ArenaRegistration.pickRound,
-- at the PREPARATION_ROOM phase) each player gets a pad on their team's side: their Quins stand on
-- it, idle, and the player is teleported there to be with them. When the Quins deploy, the same
-- models move into the arena (moveToArena), so the Quin you watched in the room is the one that
-- fights; the player stays on the pad, which looks over the arena. When the match ends the
-- players go back to the arena entrance (the SpawnLocation by the Arena Terminals).
-- The side nearer the TeamAlpha spawn is Alpha's; FFA alternates sides.

local Workspace = game:GetService("Workspace")
local ServerScriptService = game:GetService("ServerScriptService")

local QuinSpawner = require(ServerScriptService:WaitForChild("QuinSpawner"))

local PrepRoom = {}

local QUIN_SPACING = 8 -- studs between a player's Quins on the pad
local occupied = {} -- [player] = pad

local function padTop(pad)
    return pad.Position.Y + pad.Size.Y / 2
end

-- Pads by side, nearest the arena first-floor-first, ordered along the wall
local function padsBySide()
    local alphaSpawn = QuinSpawner.getSpawnPositions()[1] or Vector3.new(1, 0, 0)
    local alpha, beta = {}, {}
    for _, part in ipairs(Workspace:GetChildren()) do
        if part.Name == "PreparationRoom" and part:IsA("BasePart") then
            if math.sign(part.Position.X) == math.sign(alphaSpawn.X) then
                table.insert(alpha, part)
            else
                table.insert(beta, part)
            end
        end
    end
    local function order(a, b)
        if math.abs(a.Position.Y - b.Position.Y) > 5 then
            return a.Position.Y < b.Position.Y
        end
        return a.Position.Z > b.Position.Z
    end
    table.sort(alpha, order)
    table.sort(beta, order)
    return { TeamAlpha = alpha, TeamBeta = beta }
end

-- Where on a pad: the Quins along the arena-facing edge, the player behind them
local function arenaSide(pad)
    return Vector3.new(-math.sign(pad.Position.X), 0, 0) -- (the arena is round x = 0)
end

local function teleportPlayer(player, cf)
    local character = player.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    if root then
        character:PivotTo(cf)
        root.AssemblyLinearVelocity = Vector3.zero
    end
end

-- Seat the round's entrants ({ player, quin, team } from ArenaRegistration.pickRound): each player
-- on a free pad of their side with their Quins. Sets entry.model / entry.standOffset.
function PrepRoom.open(entrants)
    PrepRoom.close(false)
    local pads = padsBySide()
    local used = { TeamAlpha = 0, TeamBeta = 0 }
    local byPlayer, order = {}, {}
    for _, e in ipairs(entrants) do
        if not byPlayer[e.player] then
            byPlayer[e.player] = {}
            table.insert(order, e.player)
        end
        table.insert(byPlayer[e.player], e)
    end
    for i, player in ipairs(order) do
        local group = byPlayer[player]
        local side = group[1].team or ((i % 2 == 1) and "TeamAlpha" or "TeamBeta")
        used[side] += 1
        local pad = pads[side][used[side]]
        if pad then
            occupied[player] = pad
            local toArena = arenaSide(pad)
            local along = Vector3.new(0, 0, 1)
            local top = padTop(pad)
            local front = Vector3.new(pad.Position.X, top, pad.Position.Z) + toArena * (pad.Size.X * 0.25)
            for k, e in ipairs(group) do
                local pos = front + along * ((k - (#group + 1) / 2) * QUIN_SPACING) + Vector3.new(0, 3, 0)
                local q = QuinSpawner.spawn(e.quin, pos, e.team, nil, pos + toArena * 20)
                if q then
                    q:SetAttribute("IsInert", true)
                    q:SetAttribute("ForceState", "Idle")
                    q:SetAttribute("CurrentState", "Idle")
                    q:SetAttribute("OwnerUserId", player.UserId)
                    q:SetAttribute("OwnerName", player.Name)
                    q:SetAttribute("InPrepRoom", true)
                    e.model = q
                    e.standOffset = q:GetPivot().Position.Y - top
                end
            end
            local back = Vector3.new(pad.Position.X, top + 4, pad.Position.Z) - toArena * (pad.Size.X * 0.2)
            teleportPlayer(player, CFrame.lookAt(back, back + toArena))
            player:SetAttribute("ArenaPrepPad", pad:GetFullName())
        else
            warn(string.format("[ArenaPrepRoom] No free pad on %s's side for %s", side, player.Name))
        end
    end
end

-- Move a Quin that waited in the room to `position` in the arena, standing at its own height
function PrepRoom.moveToArena(model, position, standOffset)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    local exclude = { model }
    local quinServer = Workspace:FindFirstChild("QuinServer")
    if quinServer then
        table.insert(exclude, quinServer)
    end
    params.FilterDescendantsInstances = exclude
    local floorY = position.Y - 3
    local hit = Workspace:Raycast(position + Vector3.new(0, 12, 0), Vector3.new(0, -60, 0), params)
    if hit then
        floorY = hit.Position.Y
    end
    model:PivotTo(CFrame.new(position.X, floorY + (standOffset or 5), position.Z))
    model:SetAttribute("InPrepRoom", nil)
    local root = model:FindFirstChild("HumanoidRootPart")
    if root then
        root.AssemblyLinearVelocity = Vector3.zero
    end
end

-- Match over: everyone back to the arena entrance (sendHome false: just forget the pads)
function PrepRoom.close(sendHome)
    local spawn = Workspace:FindFirstChildWhichIsA("SpawnLocation", true)
    for player, _ in pairs(occupied) do
        player:SetAttribute("ArenaPrepPad", nil)
        if sendHome ~= false and spawn and player.Parent then
            local offset = Vector3.new(math.random(-6, 6), 4, math.random(-6, 6))
            teleportPlayer(player, CFrame.new(spawn.Position + offset))
        end
    end
    occupied = {}
end

return PrepRoom
