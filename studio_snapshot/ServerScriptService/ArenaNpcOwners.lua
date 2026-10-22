--// ArenaNpcOwners.lua
-- Simulated Quin owners: some of the seats the arena fills with its own Quins go to NPC owners,
-- so the preparation rooms are lived in like a full server.
--
--   * fillRound (the orchestrator, after ArenaRegistration.pickRound): of the seats players left
--     empty, about NPC_SHARE go to NPC owners with 1 or 2 Quins each (the event's limit), as many as
--     there are free rooms on that side. Real players are always seated first.
--   * Each NPC owner is a Roblox avatar (random colours, a name tag) put in their room
--     (ArenaPrepRoom). They are never still: they wander, sit on the chairs, stand at the glass
--     watching the arena (once the fight is on, turned towards their own Quin), use the terminals,
--     and visit other NPC owners' rooms on the same side and floor through the hallway. When their
--     Quins are down they sit, then leave; when the match ends they walk out and are gone.
--   * Off: Workspace attribute ArenaNpcOwners = false.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PhysicsService = game:GetService("PhysicsService")

local QuinCore = ReplicatedStorage:WaitForChild("QuinCore")
local QuinInstance = require(QuinCore:WaitForChild("Modules"):WaitForChild("QuinInstance"))

local NpcOwners = {}

local NPC_SHARE = 0.6 -- of the empty seats
local WALK_SPEED = { 10, 14 }

local NAMES = {
    "NovaRider", "Kestrel_88", "IronVow", "PixelMonk", "Saffron", "BlueTalon", "Moth_and_Ember",
    "Gearwright", "Lumen", "OkiDoki", "Rook", "TidalGrin", "Vesper", "ZeroFuse", "Ashgrove",
    "CobaltKid", "Marrow", "Juno_Q", "Patchwork", "Starling", "Hollowpoint", "Ember_Lark",
    "Quill", "Basalt", "Fennec", "Glint", "Harbor", "Inkwell", "Jubilee", "Kitebird",
}

local SKIN = {
    Color3.fromRGB(255, 220, 190), Color3.fromRGB(234, 184, 146), Color3.fromRGB(198, 134, 94),
    Color3.fromRGB(141, 85, 54), Color3.fromRGB(94, 60, 40), Color3.fromRGB(245, 205, 170),
}
local CLOTH = {
    Color3.fromRGB(30, 34, 46), Color3.fromRGB(180, 40, 50), Color3.fromRGB(40, 90, 170),
    Color3.fromRGB(230, 230, 235), Color3.fromRGB(60, 130, 80), Color3.fromRGB(240, 180, 40),
    Color3.fromRGB(110, 60, 150), Color3.fromRGB(90, 90, 95), Color3.fromRGB(200, 120, 60),
}

local folder = Workspace:FindFirstChild("ArenaNpcOwners")
if not folder then
    folder = Instance.new("Folder")
    folder.Name = "ArenaNpcOwners"
    folder.Parent = Workspace
end

local rng = Random.new()
local nameIndex = rng:NextInteger(1, #NAMES)

local function pick(list)
    return list[rng:NextInteger(1, #list)]
end

local function enabled()
    return Workspace:GetAttribute("ArenaNpcOwners") ~= false
end

-- ============================================================================
-- ROUNDS
-- ============================================================================

-- Add NPC owners' Quins to the round's entrants (in place) and return them
function NpcOwners.fillRound(entrants, mode, teamSize, perPlayer, roomsPerSide)
    if not enabled() or (mode ~= "TeamBattle" and mode ~= "FFA" and mode ~= "1vs1") then
        return entrants
    end
    local seats = mode == "FFA" and math.max(2, teamSize) or (mode == "1vs1" and 2 or teamSize * 2)
    local perTeam = mode == "FFA" and seats or (mode == "1vs1" and 1 or teamSize)
    local teamCount = { TeamAlpha = 0, TeamBeta = 0 }
    local ownersOnTeam = { TeamAlpha = {}, TeamBeta = {} }
    for _, e in ipairs(entrants) do
        if e.team then
            teamCount[e.team] += 1
            ownersOnTeam[e.team][e.player] = true
        end
    end
    local roomsLeft = {}
    for _, team in ipairs({ "TeamAlpha", "TeamBeta" }) do
        local used = 0
        for _ in pairs(ownersOnTeam[team]) do
            used += 1
        end
        roomsLeft[team] = math.max(0, (roomsPerSide or 16) - used)
    end
    local budget = math.floor((seats - #entrants) * NPC_SHARE + 0.5)
    local added = 0
    while budget > 0 do
        local team = nil
        if mode ~= "FFA" then
            team = teamCount.TeamAlpha <= teamCount.TeamBeta and "TeamAlpha" or "TeamBeta"
            if teamCount[team] >= perTeam or roomsLeft[team] <= 0 then
                team = team == "TeamAlpha" and "TeamBeta" or "TeamAlpha"
                if teamCount[team] >= perTeam or roomsLeft[team] <= 0 then
                    break
                end
            end
            roomsLeft[team] -= 1
        end
        nameIndex = nameIndex % #NAMES + 1
        local npc = { name = NAMES[nameIndex], npc = true }
        local count = math.min(budget, rng:NextNumber() < 0.55 and perPlayer or 1)
        for _ = 1, count do
            if team and teamCount[team] >= perTeam then
                break
            end
            local quin = QuinInstance.create({ Type = "Standard", OwnerId = "NPC_" .. npc.name })
            table.insert(entrants, { npc = npc, quin = quin, team = team })
            if team then
                teamCount[team] += 1
            end
            budget -= 1
            added += 1
        end
    end
    if added > 0 then
        print(string.format("[ArenaNpcOwners] %d arena seats go to NPC owners' Quins", added))
    end
    return entrants
end

-- ============================================================================
-- AVATARS
-- ============================================================================

local function ensureGroup()
    pcall(function()
        PhysicsService:RegisterCollisionGroup("ArenaSpectators")
    end)
end

local function makeAvatar(npc, cf)
    local desc = Instance.new("HumanoidDescription")
    local skin = pick(SKIN)
    desc.HeadColor, desc.LeftArmColor, desc.RightArmColor = skin, skin, skin
    desc.TorsoColor = pick(CLOTH)
    local legs = pick(CLOTH)
    desc.LeftLegColor, desc.RightLegColor = legs, legs
    local ok, model = pcall(function()
        return Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
    end)
    if not ok or not model then
        warn("[ArenaNpcOwners] Could not build an avatar: " .. tostring(model))
        return nil
    end
    model.Name = npc.name
    local hum = model:FindFirstChildOfClass("Humanoid")
    hum.DisplayName = npc.name
    hum.WalkSpeed = rng:NextNumber(WALK_SPEED[1], WALK_SPEED[2])
    hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Viewer
    hum.NameDisplayDistance = 60
    ensureGroup()
    for _, part in ipairs(model:GetDescendants()) do
        if part:IsA("BasePart") then
            part.CollisionGroup = "ArenaSpectators"
        end
    end
    model:SetAttribute("NpcOwner", true)
    model:PivotTo(cf)
    model.Parent = folder
    local root = model:FindFirstChild("HumanoidRootPart")
    if root then
        pcall(function()
            root:SetNetworkOwner(nil)
        end)
    end
    return model
end

-- ============================================================================
-- BEHAVIOUR
-- ============================================================================

local function alive(npc)
    return npc.model and npc.model.Parent and npc.alive
end

local function walkTo(npc, point, timeout)
    local hum = npc.model:FindFirstChildOfClass("Humanoid")
    if not hum or hum.Health <= 0 then
        return false
    end
    if hum.Sit then
        hum.Sit = false
        hum.Jump = true
        task.wait(0.4)
    end
    local reached = false
    local conn = hum.MoveToFinished:Connect(function(r)
        reached = r
    end)
    local start = os.clock()
    hum:MoveTo(point)
    while alive(npc) and not reached and os.clock() - start < (timeout or 7) do
        local root = npc.model:FindFirstChild("HumanoidRootPart")
        if root and (Vector3.new(root.Position.X, point.Y, root.Position.Z) - point).Magnitude < 2 then
            reached = true
        end
        task.wait(0.2)
    end
    conn:Disconnect()
    return reached
end

local function face(npc, target)
    local root = npc.model and npc.model:FindFirstChild("HumanoidRootPart")
    if root and target then
        local p = root.Position
        local flat = Vector3.new(target.X, p.Y, target.Z)
        if (flat - p).Magnitude > 0.5 then
            root.CFrame = CFrame.lookAt(p, flat)
        end
    end
end

local function idle(npc, seconds, lookAt)
    local untilT = os.clock() + seconds
    while alive(npc) and os.clock() < untilT do
        if lookAt then
            face(npc, lookAt())
        end
        task.wait(rng:NextNumber(0.8, 2.0))
    end
end

-- Through the door, along the hallway, into `target` (and the reverse with from/to swapped)
local function walkBetween(npc, from, to)
    return walkTo(npc, from.doorInside) and walkTo(npc, from.doorHall)
        and walkTo(npc, to.doorHall, 12) and walkTo(npc, to.doorInside) and walkTo(npc, to.Api.randomPoint(to, 4))
end

local function ownQuinPosition(npc)
    for _, m in ipairs(npc.quins or {}) do
        local hum = m.Parent and m:FindFirstChildOfClass("Humanoid")
        local root = m.Parent and m:FindFirstChild("HumanoidRootPart")
        if hum and hum.Health > 0 and root then
            return root.Position
        end
    end
    return nil
end

local function quinsDown(npc)
    return #(npc.quins or {}) > 0 and ownQuinPosition(npc) == nil
end

local ACTIONS = {
    -- name, weight before the fight, weight during it
    { "wander", 3, 1 },
    { "sit", 3, 2 },
    { "window", 3, 6 },
    { "terminal", 2, 2 },
    { "visit", 2, 1 },
}

local function chooseAction()
    local fighting = Workspace:GetAttribute("MatchStarted") == true
    local total = 0
    for _, a in ipairs(ACTIONS) do
        total += fighting and a[3] or a[2]
    end
    local roll = rng:NextNumber(0, total)
    for _, a in ipairs(ACTIONS) do
        roll -= fighting and a[3] or a[2]
        if roll <= 0 then
            return a[1]
        end
    end
    return "wander"
end

local function act(npc, action)
    local room = npc.room
    local Api = room.Api
    if action == "wander" then
        walkTo(npc, Api.randomPoint(room, 3))
        idle(npc, rng:NextNumber(2, 5))
    elseif action == "sit" and #room.seats > 0 then
        local seat = pick(room.seats)
        if not seat.Occupant then
            walkTo(npc, seat.Position + Vector3.new(0, 0, 0))
            local hum = npc.model:FindFirstChildOfClass("Humanoid")
            if hum and not seat.Occupant then
                seat:Sit(hum)
            end
            idle(npc, rng:NextNumber(6, 16))
            if hum then
                hum.Sit = false
                hum.Jump = true
            end
        end
    elseif action == "window" then
        walkTo(npc, Api.windowPoint(room))
        idle(npc, rng:NextNumber(5, 14), function()
            return ownQuinPosition(npc) or (npc.model:GetPivot().Position + room.toArena * 50)
        end)
    elseif action == "terminal" and #room.terminals > 0 then
        local t = pick(room.terminals)
        local toward = (room.center - t.Position) * Vector3.new(1, 0, 1)
        local spot = Vector3.new(t.Position.X, room.floorY, t.Position.Z) + (toward.Magnitude > 0 and toward.Unit * 3 or Vector3.zero)
        walkTo(npc, spot)
        idle(npc, rng:NextNumber(4, 10), function()
            return t.Position
        end)
    elseif action == "visit" then
        local others = npc.visitable and npc.visitable() or {}
        if #others > 0 then
            local target = pick(others)
            target.Api = Api
            if walkBetween(npc, room, target) then
                idle(npc, rng:NextNumber(8, 18), function()
                    return target.Api.windowPoint(target)
                end)
            end
            if alive(npc) then
                walkBetween(npc, target, room) -- (home again)
            end
        end
    end
end

local function run(npc)
    task.wait(rng:NextNumber(0, 2))
    while alive(npc) do
        if quinsDown(npc) then
            -- their Quins are out: a sit to take it in (ArenaPrepRoom sends them off soon)
            act(npc, "sit")
        else
            act(npc, chooseAction())
        end
        task.wait(rng:NextNumber(0.3, 1.2))
    end
end

-- Put an NPC owner in their room (ArenaPrepRoom.open). `visitable()` lists rooms to visit.
function NpcOwners.enterRoom(npc, room, quins, Api, visitable)
    room.Api = Api
    npc.room = room
    npc.quins = quins
    npc.visitable = visitable
    npc.alive = true
    local spot = Api.randomPoint(room, 4) + Vector3.new(0, 3, 0)
    npc.model = makeAvatar(npc, CFrame.lookAt(spot, spot + room.toArena))
    if npc.model then
        task.spawn(run, npc)
    end
end

-- Done (all Quins down, or the match is over): walk out of the door, then gone
function NpcOwners.leave(npc, walkOut)
    if not npc.alive then
        return
    end
    npc.alive = false
    local model = npc.model
    if not model then
        return
    end
    if walkOut and npc.room then
        task.spawn(function()
            local hum = model:FindFirstChildOfClass("Humanoid")
            if hum then
                hum.Sit = false
                hum:MoveTo(npc.room.doorInside)
                hum.MoveToFinished:Wait()
                hum:MoveTo(npc.room.doorHall + (npc.room.doorHall - npc.room.doorInside).Unit * 4)
                task.wait(2.5)
            end
            model:Destroy()
        end)
    else
        model:Destroy()
    end
end

function NpcOwners.clearAll()
    for _, m in ipairs(folder:GetChildren()) do
        m:Destroy()
    end
end

return NpcOwners
