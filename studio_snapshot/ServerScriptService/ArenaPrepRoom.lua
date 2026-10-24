--// ArenaPrepRoom.lua
-- The preparation rooms: the Workspace models named "PrepRoom" (in the PrepRoomCopies groups:
-- 8 rooms x 2 floors on each side of the arena). Each holds a PrepRoomQuinSpawn, PrepRoomTerminals,
-- chairs (Seats), the PreparationRoomGlass that looks over the arena, a Door and a hallway.
--
--   * When a round's entrants are picked (ArenaRegistration.pickRound + ArenaNpcOwners.fillRound,
--     at the PREPARATION_ROOM phase), every owner (player or NPC owner) gets a room on their team's
--     side: their Quins stand on the PrepRoomQuinSpawn, idle, and the owner is put in the room.
--     When the Quins deploy, the same models move into the arena (moveToArena).
--   * Room rule: same-team rooms are on the same side. A room's door lets in its owner, the owner's
--     friends, and whoever the owner lets in: anyone else can Knock (the door's prompt) and the
--     owner gets Let in / No (NPC owners answer for themselves). The door is solid only on the
--     machines of players who may not enter (PrepRoomClient); the server also walks intruders
--     back out to the hallway.
--   * When all of an owner's Quins are down, the owner is sent back into the game (players to the
--     arena entrance, NPC owners walk out) a few seconds later.
--   * Match over: everyone back to the entrance, the NPC owners leave, the rooms are free again.
--
-- Rooms publish (attributes on the PrepRoom model): PrepOwner (name), PrepOwnerUserId (players),
-- PrepTeam, PrepAllowed (",id,id," of the players who may enter).
-- Remote ArenaNetwork.PrepRoom: server -> client "knock", name, userId | "notice", text;
-- client -> server "knockReply", userId, allow | "plan", quin model name, { Stance, Target, Role }
-- (QuinPlans; answered with "plan", ok, text).

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local QuinSpawner = require(ServerScriptService:WaitForChild("QuinSpawner"))
local ArenaNpcOwners = require(ServerScriptService:WaitForChild("ArenaNpcOwners"))
local QuinPlans = require(ServerScriptService:WaitForChild("QuinPlans"))
local QuinCare = require(ServerScriptService:WaitForChild("QuinCare"))
local Temperament = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("Temperament"))
local HttpService = game:GetService("HttpService")

local PrepRoom = {}

local QUIN_SPACING = 7 -- studs between an owner's Quins on the spawn
local RELEASE_DELAY = 6 -- seconds after an owner's last Quin falls
local NPC_LET_IN_CHANCE = 0.6

local rooms = nil -- built once from the Workspace
local rng = Random.new()
local active = {} -- [room] = { owner, ownerName, isNpc, team, models = {}, allowed = {[userId]=true}, releasing }

-- ============================================================================
-- ROOMS
-- ============================================================================

local function buildRoom(model)
    local room = { model = model, seats = {}, terminals = {} }
    for _, d in ipairs(model:GetDescendants()) do
        if d:IsA("Seat") then
            table.insert(room.seats, d)
        elseif d.Name == "PrepRoomTerminal" and d:IsA("BasePart") then
            table.insert(room.terminals, d)
        elseif d.Name == "PrepRoomQuinSpawn" then
            room.spawn = d
        elseif d.Name == "PreparationRoomGround" then
            room.ground = d
        elseif d.Name == "PreparationRoomGlass" then
            room.glass = d
        elseif d.Name == "Door" and d:IsA("BasePart") then
            room.door = d
        elseif d.Name == "PreparationRoomHallWay" then
            room.hallway = d
        end
    end
    if not (room.spawn and room.ground and room.door) then
        warn("[ArenaPrepRoom] Room missing parts (PrepRoomQuinSpawn / PreparationRoomGround / Door): " .. model:GetFullName())
        return nil
    end
    local center = room.ground.Position
    room.side = center.X >= 0 and 1 or -1
    room.toArena = Vector3.new(-room.side, 0, 0) -- (the arena is round x = 0)
    room.floorY = room.ground.Position.Y + room.ground.Size.Y / 2
    room.center = Vector3.new(center.X, room.floorY, center.Z)
    -- the door stays open for NPC owners; each player's machine closes it to them (PrepRoomClient)
    room.door.CanCollide = false
    room.doorInside = Vector3.new(room.door.Position.X, room.floorY, room.door.Position.Z) + room.toArena * 3
    room.doorHall = Vector3.new(room.door.Position.X, room.floorY, room.door.Position.Z) - room.toArena * 6
    return room
end

local function allRooms()
    if rooms then
        return rooms
    end
    rooms = {}
    for _, d in ipairs(Workspace:GetDescendants()) do
        if d.Name == "PrepRoom" and d:IsA("Model") then
            local room = buildRoom(d)
            if room then
                table.insert(rooms, room)
            end
        end
    end
    -- lower floor first, then along the wall
    table.sort(rooms, function(a, b)
        if math.abs(a.floorY - b.floorY) > 5 then
            return a.floorY < b.floorY
        end
        return a.center.Z > b.center.Z
    end)
    print(string.format("[ArenaPrepRoom] %d preparation rooms", #rooms))
    return rooms
end

-- The side (+1 / -1 in X) nearest each team's spawn
local function sideOf(team)
    local spawns = QuinSpawner.getSpawnPositions()
    local alpha = spawns[1] or Vector3.new(1, 0, 0)
    local alphaSide = alpha.X >= 0 and 1 or -1
    return team == "TeamBeta" and -alphaSide or alphaSide
end

-- A point inside the room, inset from its walls
function PrepRoom.randomPoint(room, inset)
    inset = inset or 3
    local g = room.ground
    local rng = Random.new()
    local x = g.Position.X + rng:NextNumber(-1, 1) * math.max(0, g.Size.X / 2 - inset)
    local z = g.Position.Z + rng:NextNumber(-1, 1) * math.max(0, g.Size.Z / 2 - inset)
    return Vector3.new(x, room.floorY, z)
end

-- A spot at the glass, looking out over the arena
function PrepRoom.windowPoint(room)
    local p = PrepRoom.randomPoint(room, 4)
    local glassX = room.glass and room.glass.Position.X or (room.center.X + room.toArena.X * room.ground.Size.X / 2)
    return Vector3.new(glassX - room.toArena.X * 3, room.floorY, p.Z)
end

local function inside(room, position)
    local g = room.ground
    local d = position - g.Position
    return math.abs(d.X) <= g.Size.X / 2 and math.abs(d.Z) <= g.Size.Z / 2 and d.Y > -2 and d.Y < 18
end

local function publish(room, state)
    local m = room.model
    if not state then
        m:SetAttribute("PrepOwner", nil)
        m:SetAttribute("PrepOwnerUserId", nil)
        m:SetAttribute("PrepTeam", nil)
        m:SetAttribute("PrepAllowed", nil)
        return
    end
    local ids = {}
    for id in pairs(state.allowed) do
        table.insert(ids, tostring(id))
    end
    m:SetAttribute("PrepOwner", state.ownerName)
    m:SetAttribute("PrepOwnerUserId", (not state.isNpc) and state.owner.UserId or nil)
    m:SetAttribute("PrepTeam", state.team)
    m:SetAttribute("PrepAllowed", "," .. table.concat(ids, ",") .. ",")
end

-- The owner's friends in this server may come in
local function addFriends(state)
    if state.isNpc then
        return
    end
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= state.owner and not state.allowed[p.UserId] then
            local ok, isFriend = pcall(function()
                return state.owner:IsFriendsWith(p.UserId)
            end)
            if ok and isFriend then
                state.allowed[p.UserId] = true
            end
        end
    end
end

-- ============================================================================
-- NETWORK
-- ============================================================================

local ArenaNetwork = ReplicatedStorage:FindFirstChild("ArenaNetwork")
if not ArenaNetwork then
    ArenaNetwork = Instance.new("Folder")
    ArenaNetwork.Name = "ArenaNetwork"
    ArenaNetwork.Parent = ReplicatedStorage
end
local remote = ArenaNetwork:FindFirstChild("PrepRoom")
if not remote then
    remote = Instance.new("RemoteEvent")
    remote.Name = "PrepRoom"
    remote.Parent = ArenaNetwork
end

local function notice(player, text)
    if player and player.Parent then
        remote:FireClient(player, "notice", text)
    end
end

local pendingKnocks = {} -- [ownerUserId] = { [requesterUserId] = room }

local function roomOfOwner(owner)
    for room, state in pairs(active) do
        if state.owner == owner then
            return room, state
        end
    end
    return nil
end

local function onKnock(player, room)
    local state = active[room]
    if not state or state.allowed[player.UserId] then
        return
    end
    if state.isNpc then
        notice(player, string.format("You knock on %s's door...", state.ownerName))
        task.delay(1.5 + math.random() * 2, function()
            if active[room] ~= state then
                return
            end
            if math.random() < NPC_LET_IN_CHANCE then
                state.allowed[player.UserId] = true
                publish(room, state)
                notice(player, state.ownerName .. " let you in.")
            else
                notice(player, state.ownerName .. " wants to be alone.")
            end
        end)
        return
    end
    pendingKnocks[state.owner.UserId] = pendingKnocks[state.owner.UserId] or {}
    pendingKnocks[state.owner.UserId][player.UserId] = room
    remote:FireClient(state.owner, "knock", player.DisplayName, player.UserId)
    notice(player, string.format("You knock on %s's door...", state.ownerName))
end

-- An owner's NPC friend knocking (ArenaNpcOwners.addFriends): an NPC owner lets friends in; a
-- player owner is asked like any knock (negative ids tell them apart); no answer is a no
local pendingFriendKnocks = {} -- [negative id] = { owner, callback }
local friendKnockId = 0
local function friendKnock(room, name, callback, stranger)
    local state = active[room]
    if not state then
        callback(false)
        return
    end
    if state.isNpc then
        task.delay(rng:NextNumber(1, 2.5), function()
            callback(active[room] == state and (not stranger or rng:NextNumber() < 0.6))
        end)
        return
    end
    friendKnockId -= 1
    local id = friendKnockId
    pendingFriendKnocks[id] = { owner = state.owner, callback = callback }
    remote:FireClient(state.owner, "knock", stranger and name or (name .. " (your friend)"), id)
    task.delay(16, function()
        local p = pendingFriendKnocks[id]
        if p then
            pendingFriendKnocks[id] = nil
            p.callback(false)
        end
    end)
end

-- The owner's plan for one of their Quins in their room (only while the room is open)
local function setPlan(player, modelName, plan)
    local room = roomOfOwner(player)
    local state = room and active[room]
    if not state then
        return false, "Plans are set in your preparation room."
    end
    if not QuinPlans.open() then
        return false, "Plans are locked: the round has started."
    end
    for _, m in ipairs(state.models) do
        if m.Name == modelName and state.quinOf[m] then
            return QuinPlans.apply(m, state.quinOf[m], plan)
        end
    end
    return false, "That isn't one of your Quins."
end

remote.OnServerEvent:Connect(function(player, action, requesterId, allow)
    if action == "plan" then
        local ok, msg = setPlan(player, requesterId, allow)
        remote:FireClient(player, "plan", ok, msg)
        return
    end
    if action ~= "knockReply" then
        return
    end
    local friendKnockReply = type(requesterId) == "number" and pendingFriendKnocks[requesterId]
    if friendKnockReply then
        if friendKnockReply.owner == player then
            pendingFriendKnocks[requesterId] = nil
            friendKnockReply.callback(allow == true)
        end
        return
    end
    local pending = pendingKnocks[player.UserId]
    local room = pending and pending[requesterId]
    if not room then
        return
    end
    pending[requesterId] = nil
    local state = active[room]
    local requester = Players:GetPlayerByUserId(requesterId)
    if state and state.owner == player and allow == true then
        state.allowed[requesterId] = true
        publish(room, state)
        notice(requester, player.DisplayName .. " let you in.")
    else
        notice(requester, player.DisplayName .. " did not open the door.")
    end
end)

for _, room in ipairs(allRooms()) do
    local prompt = room.door:FindFirstChild("DoorPrompt") or Instance.new("ProximityPrompt")
    prompt.Name = "DoorPrompt"
    prompt.ActionText = "Knock"
    prompt.ObjectText = "Preparation Room"
    prompt.HoldDuration = 0
    prompt.MaxActivationDistance = 8
    prompt.RequiresLineOfSight = false
    prompt.Enabled = false -- (on while the room has an owner)
    prompt.Parent = room.door
    prompt.Triggered:Connect(function(player)
        onKnock(player, room)
    end)
    -- the terminals' views and stats are drawn on the player's machine (PrepRoomClient)
    for _, terminal in ipairs(room.terminals) do
        if not terminal:FindFirstChild("TerminalPrompt") then
            local tp = Instance.new("ProximityPrompt")
            tp.Name = "TerminalPrompt"
            tp.ActionText = "Use Terminal"
            tp.ObjectText = "Prep Terminal"
            tp.HoldDuration = 0
            tp.MaxActivationDistance = 6
            tp.RequiresLineOfSight = false
            tp.Parent = terminal
        end
    end
end

-- ============================================================================
-- OPEN / CLOSE
-- ============================================================================

local function teleportPlayer(player, cf)
    local character = player.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    if root then
        character:PivotTo(cf)
        root.AssemblyLinearVelocity = Vector3.zero
    end
end

local function entranceCFrame()
    local spawn = Workspace:FindFirstChildWhichIsA("SpawnLocation", true)
    local base = spawn and spawn.Position or Vector3.new(0, 10, -850)
    return CFrame.new(base + Vector3.new(math.random(-6, 6), 4, math.random(-6, 6)))
end

-- Scouting (ScoutView on the players' machines): the round's Quins per team as the ArenaBoards
-- show them, bands only; published as Workspace ScoutRoster (JSON) while the rooms are open.
local function publishRoster(entrants)
    local roster = { TeamAlpha = {}, TeamBeta = {} }
    for _, e in ipairs(entrants) do
        local q = e.quin
        if q and roster[e.team] then
            local record = q.BattleRecord or {}
            local cond = QuinCare.condition(q)
            local bond = q.Bond or 0
            local revealed = {}
            for _, h in ipairs(QuinCare.knownHabits(q)) do
                table.insert(revealed, h.Name .. " " .. h.Band)
            end
            table.insert(roster[e.team], {
                Owner = e.player and e.player.DisplayName or (e.npc and e.npc.name) or "?",
                UserId = e.player and e.player.UserId or nil,
                Npc = e.npc ~= nil or nil,
                Tag = q.QuinId:sub(3, 6),
                Temperament = Temperament.displayName(q.Temperament or ""),
                Wins = record.Wins or 0,
                Losses = (record.Battles or 0) - (record.Wins or 0),
                Cond = cond >= 80 and "Fresh" or (cond >= 50 and "Worn" or "Battered"),
                Bond = bond >= 70 and "Bonded" or (bond >= 30 and "Close" or "New"),
                Revealed = #revealed > 0 and table.concat(revealed, ", ") or nil,
                S = math.floor(10 + 40 * ((record.Wins or 0) + 1) / ((record.Battles or 0) + 2) + 30 * cond / 100 + 20 * math.clamp(bond / 100, 0, 1) + 0.5),
            })
        end
    end
    Workspace:SetAttribute("ScoutRoster", HttpService:JSONEncode(roster))
end

-- Seat the round's entrants ({ player | npc, quin, team }): each owner in a free room on their
-- team's side with their Quins. Sets entry.model / entry.standOffset.
function PrepRoom.open(entrants)
    PrepRoom.close(false)
    local free = {}
    for _, room in ipairs(allRooms()) do
        table.insert(free, room)
    end
    local function takeRoom(side)
        for i, room in ipairs(free) do
            if room.side == side then
                return table.remove(free, i)
            end
        end
        return nil
    end

    local groups, order = {}, {}
    for _, e in ipairs(entrants) do
        local owner = e.player or e.npc
        if not groups[owner] then
            groups[owner] = {}
            table.insert(order, owner)
        end
        table.insert(groups[owner], e)
    end

    for i, owner in ipairs(order) do
        local group = groups[owner]
        local team = group[1].team or ((i % 2 == 1) and "TeamAlpha" or "TeamBeta")
        local room = takeRoom(sideOf(team))
        local isNpc = group[1].npc ~= nil
        if room then
            local state = {
                owner = owner,
                ownerName = isNpc and owner.name or owner.DisplayName,
                isNpc = isNpc,
                team = team,
                models = {},
                quins = {}, -- { quin instance, team, pad position }: brought home if they lose
                home = {}, -- the defeated Quins standing back in the room
                quinOf = {}, -- [model] = its saved Quin (QuinPlans)
                allowed = {},
            }
            if not isNpc then
                state.allowed[owner.UserId] = true
                addFriends(state)
            end
            active[room] = state
            local spawn = room.spawn
            local along = math.abs(spawn.Size.Z) >= math.abs(spawn.Size.X) and Vector3.new(0, 0, 1) or Vector3.new(1, 0, 0)
            local top = spawn.Position.Y + spawn.Size.Y / 2
            for k, e in ipairs(group) do
                local pos = Vector3.new(spawn.Position.X, top + 3, spawn.Position.Z) + along * ((k - (#group + 1) / 2) * QUIN_SPACING)
                local q = QuinSpawner.spawn(e.quin, pos, e.team, nil, pos + room.toArena * 20)
                if q then
                    q:SetAttribute("IsInert", true)
                    q:SetAttribute("ForceState", "Idle")
                    q:SetAttribute("CurrentState", "Idle")
                    q:SetAttribute("OwnerName", state.ownerName)
                    q:SetAttribute("OwnerUserId", (not isNpc) and owner.UserId or nil)
                    q:SetAttribute("OwnerNpc", isNpc or nil)
                    q:SetAttribute("InPrepRoom", true)
                    state.quinOf[q] = e.quin
                    q:SetAttribute("Bond", e.quin.Bond or 0) -- (the plan card shows it)
                    local lastPlan = (not isNpc) and QuinPlans.lastFor(e.quin)
                    if lastPlan then -- (last round's plan, until the owner changes it)
                        QuinPlans.apply(q, e.quin, lastPlan)
                    end
                    e.model = q
                    e.standOffset = q:GetPivot().Position.Y - top
                    table.insert(state.models, q)
                    table.insert(state.quins, { quin = e.quin, team = e.team, pos = pos })
                end
            end
            -- the owner's friends: in already, or knocking later; they roam the hallway and other rooms
            ArenaNpcOwners.addFriends(room, PrepRoom, friendKnock, function()
                local list = {}
                for other in pairs(active) do
                    if other ~= room and other.side == room.side then -- (either floor: the stairs join them)
                        table.insert(list, other)
                    end
                end
                return list
            end)
            room.door.DoorPrompt.ObjectText = state.ownerName .. "'s room"
            room.door.DoorPrompt.Enabled = true
            publish(room, state)
            if isNpc then
                ArenaNpcOwners.enterRoom(owner, room, state.models, PrepRoom, function()
                    -- other NPC owners' rooms on the same side and floor, to visit
                    local list = {}
                    for other, s in pairs(active) do
                        if other ~= room and s.isNpc and other.side == room.side then -- (either floor: the stairs)
                            table.insert(list, other)
                        end
                    end
                    return list
                end)
            else
                local spot = Vector3.new(spawn.Position.X, room.floorY + 4, spawn.Position.Z) - room.toArena * 6
                teleportPlayer(owner, CFrame.lookAt(spot, spot + room.toArena))
                owner:SetAttribute("ArenaPrepRoom", room.model:GetFullName())
            end
        else
            warn(string.format("[ArenaPrepRoom] No free room on %s's side for %s", team, isNpc and owner.name or owner.Name))
        end
    end
    publishRoster(entrants)
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

local function releaseRoom(room, sendHome)
    local state = active[room]
    if not state then
        return
    end
    active[room] = nil
    publish(room, nil)
    room.door.DoorPrompt.Enabled = false
    for _, q in ipairs(state.home or {}) do
        if q.Parent then
            q:Destroy()
        end
    end
    ArenaNpcOwners.removeFriends(room, sendHome ~= false)
    if state.isNpc then
        ArenaNpcOwners.leave(state.owner, sendHome ~= false)
    elseif state.owner.Parent then
        state.owner:SetAttribute("ArenaPrepRoom", nil)
        if sendHome ~= false then
            teleportPlayer(state.owner, entranceCFrame())
        end
    end
    pendingKnocks[(not state.isNpc) and state.owner.UserId or 0] = nil
end

-- Match over: everyone back to the entrance (sendHome false: just free the rooms)
function PrepRoom.close(sendHome)
    for room in pairs(active) do
        releaseRoom(room, sendHome)
    end
    active = {}
    Workspace:SetAttribute("ScoutRoster", nil)
end

-- ============================================================================
-- WATCH: intruders out; an owner's Quins all down come home to the room

-- Out of the fight for good: the owner's Quins back on their room's pad, standing as losers
-- (owner: not thrown out at the gate). Not fighters any more: no Quin / AI_Fighter tags, so no
-- team counts them and no Quin targets them.
local function bringHome(room, state)
    for _, entry in ipairs(state.quins) do
        local q = QuinSpawner.spawn(entry.quin, entry.pos, "Defeated", nil, entry.pos + room.toArena * 20)
        if q then
            q:SetAttribute("IsInert", true)
            q:SetAttribute("ForceState", "Idle")
            q:SetAttribute("CurrentState", "Idle")
            q:SetAttribute("Defeated", true)
            q:SetAttribute("InPrepRoom", true)
            q:SetAttribute("OwnerName", state.ownerName)
            CollectionService:RemoveTag(q, "AI_Fighter")
            CollectionService:RemoveTag(q, "Quin")
            task.delay(1, function()
                -- (in case its own scripts tagged it again as they started)
                if q.Parent then
                    CollectionService:RemoveTag(q, "AI_Fighter")
                    CollectionService:RemoveTag(q, "Quin")
                end
            end)
            table.insert(state.home, q)
        end
    end
end
-- ============================================================================

local function quinDown(model)
    if not model or not model.Parent then
        return true
    end
    local hum = model:FindFirstChildOfClass("Humanoid")
    return not hum or hum.Health <= 0
end

task.spawn(function()
    while true do
        task.wait(1)
        local fighting = Workspace:GetAttribute("MatchStarted") == true
        for room, state in pairs(active) do
            -- intruders: walked back out to the hallway
            for _, p in ipairs(Players:GetPlayers()) do
                local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
                if root and not state.allowed[p.UserId] and p:GetAttribute("SkylarkRole") ~= "Admin" and inside(room, root.Position) then
                    teleportPlayer(p, CFrame.new(room.doorHall + Vector3.new(0, 4, 0)))
                    notice(p, "That room is " .. state.ownerName .. "'s. Knock on the door to ask.")
                end
            end
            -- all Quins down: back into the game
            if fighting and not state.releasing and #state.models > 0 then
                local allDown = true
                for _, m in ipairs(state.models) do
                    if not quinDown(m) then
                        allDown = false
                    end
                end
                if allDown then
                    state.releasing = true
                    if not state.isNpc then
                        notice(state.owner, "Your Quins are down. They'll be back in your room in a moment.")
                    end
                    task.delay(RELEASE_DELAY, function()
                        if active[room] == state then
                            bringHome(room, state)
                        end
                    end)
                end
            end
        end
    end
end)

Players.PlayerAdded:Connect(function()
    task.wait(2)
    for room, state in pairs(active) do
        addFriends(state)
        publish(room, state)
    end
end)

Players.PlayerRemoving:Connect(function(player)
    local room = roomOfOwner(player)
    if room then
        releaseRoom(room, false)
    end
end)

PrepRoom.rooms = allRooms
PrepRoom.sideOf = sideOf

-- Studio test hook: Workspace attribute PlanDevCommand = JSON { TeamAlpha = plan, TeamBeta = plan }
-- puts that plan on every Quin of the team (NPC owners' too) while the rooms are open; the reply
-- is in PlanDevResult ("TeamAlpha 16 Quins, follow 0.52, 3 clash ...")
if game:GetService("RunService"):IsStudio() then
    Workspace:GetAttributeChangedSignal("PlanDevCommand"):Connect(function()
        local raw = Workspace:GetAttribute("PlanDevCommand")
        if type(raw) ~= "string" or raw == "" then
            return
        end
        Workspace:SetAttribute("PlanDevCommand", nil)
        local ok, plans = pcall(HttpService.JSONDecode, HttpService, raw)
        if not ok or type(plans) ~= "table" then
            Workspace:SetAttribute("PlanDevResult", "bad JSON")
            return
        end
        local out = {}
        for team, plan in pairs(plans) do
            local n, follow, clash = 0, 0, 0
            for _, state in pairs(active) do
                if state.team == team then
                    for model, quin in pairs(state.quinOf) do
                        if model.Parent then
                            QuinPlans.apply(model, quin, plan)
                            n += 1
                            follow += model:GetAttribute("PlanFollow") or 0
                            clash += model:GetAttribute("PlanClash") and 1 or 0
                        end
                    end
                end
            end
            table.insert(out, string.format("%s %d Quins, follow %.2f, %d clash", team, n, follow / math.max(n, 1), clash))
        end
        Workspace:SetAttribute("PlanDevResult", table.concat(out, "; "))
    end)
end

return PrepRoom
