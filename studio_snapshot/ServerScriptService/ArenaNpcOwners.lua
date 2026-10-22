--// ArenaNpcOwners.lua
-- Simulated Quin owners: some of the seats the arena fills with its own Quins go to NPC owners,
-- so the preparation rooms are lived in like a full server.
--
--   * fillRound (the orchestrator, after ArenaRegistration.pickRound): the seats players left empty
--     go to NPC owners (share: Workspace attribute ArenaNpcShare, default 1 = all of them), one
--     owner per free room on that side first, so every room is lived in; seats beyond the rooms
--     become owners' second Quins (up to the event's limit). Real players are always seated first.
--   * Each NPC owner is a Roblox avatar (random colours, a name tag) put in their room
--     (ArenaPrepRoom). Most of the time (~70%) they stand at the glass watching the fight (turned
--     to their own Quin while it fights); otherwise they sit on the chairs, stroll, use the
--     terminals, or visit another owner's room on the same side and floor: friends walk in, others
--     knock and are let in (or not), and then host and guest stand side by side at the glass
--     talking the fight over (speech bubbles, pointing) like two managers. Talk is a discussion
--     (OwnerChatter: one topic, 4 to 7 turns, the other answers; pre-game, live and post-game
--     topics), shown with the same bubbles as the stands (NpcChatBubbles: near the camera only). They walk with
--     PathfindingService round chairs, terminals and door frames, and after a stroll turn to the
--     glass or the room, never a wall. When their Quins are down they sit, then leave; when the
--     match ends they walk out and are gone.
--   * Off: Workspace attribute ArenaNpcOwners = false.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PhysicsService = game:GetService("PhysicsService")
local PathfindingService = game:GetService("PathfindingService")
local Debris = game:GetService("Debris")

local QuinCore = ReplicatedStorage:WaitForChild("QuinCore")
local QuinInstance = require(QuinCore:WaitForChild("Modules"):WaitForChild("QuinInstance"))
local NpcAnimator = require(script.Parent:WaitForChild("NpcAnimator"))
local AvatarTidy = require(script.Parent:WaitForChild("AvatarTidy"))
local OwnerChatter = require(QuinCore:WaitForChild("OwnerChatter"))

-- (speech goes to every machine, which shows it as a chat bubble when near: NpcChatBubbles)
local sayRemote = ReplicatedStorage:FindFirstChild("NpcSay")
if not sayRemote then
    sayRemote = Instance.new("RemoteEvent")
    sayRemote.Name = "NpcSay"
    sayRemote.Parent = ReplicatedStorage
end

local NpcOwners = {}

local NPC_SHARE = 1 -- of the empty seats (Workspace attribute ArenaNpcShare overrides)
local WALK_SPEED = { 8, 11 } -- (a stroll: the walk animation, never the run)

local NAMES = {
    "NovaRider", "Kestrel_88", "IronVow", "PixelMonk", "Saffron", "BlueTalon", "Moth_and_Ember",
    "Gearwright", "Lumen", "OkiDoki", "Rook", "TidalGrin", "Vesper", "ZeroFuse", "Ashgrove",
    "CobaltKid", "Marrow", "Juno_Q", "Patchwork", "Starling", "Hollowpoint", "Ember_Lark",
    "Quill", "Basalt", "Fennec", "Glint", "Harbor", "Inkwell", "Jubilee", "Kitebird",
    "Lanternfish", "Mireille", "Nox_7", "Orrery", "Pebblestep", "Quasar_Q", "Ravenwood", "Sablecat",
    "Thistle", "Umbra", "Velvetine", "Wrenfield", "Xylo", "Yarrow", "Zephyrine", "Bramble",
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

-- The server keeps every NPC's body. Sitting welds it to the anchored seat; standing up gives the
-- body back to automatic ownership and Roblox hands it to the nearest player, whose machine then
-- walks it into the doors it keeps closed for that player (and plays it badly). Re-claimed often.
task.spawn(function()
    while true do
        task.wait(0.5)
        for _, m in ipairs(folder:GetChildren()) do
            local root = m:FindFirstChild("HumanoidRootPart")
            if root and not root.Anchored then
                pcall(function()
                    if root:GetNetworkOwner() ~= nil then
                        root:SetNetworkOwner(nil)
                    end
                end)
            end
        end
    end
end)

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
    local share = tonumber(Workspace:GetAttribute("ArenaNpcShare")) or NPC_SHARE
    local added = 0
    -- owners for `team` (nil: FFA) in up to `rooms` rooms, holding `npcSeats` Quins between them
    local function addOwners(team, npcSeats, rooms)
        local owners = math.min(rooms, npcSeats)
        local extra = math.min(npcSeats - owners, owners * (perPlayer - 1))
        for i = 1, owners do
            nameIndex = nameIndex % #NAMES + 1
            local npc = { name = NAMES[nameIndex], npc = true, team = team }
            for _ = 1, (i <= extra) and 2 or 1 do
                local quin = QuinInstance.create({ Type = "Standard", OwnerId = "NPC_" .. npc.name })
                table.insert(entrants, { npc = npc, quin = quin, team = team })
                added += 1
            end
        end
    end
    if mode == "FFA" then
        local free = math.max(0, seats - #entrants)
        addOwners(nil, math.floor(free * share + 0.5), roomsLeft.TeamAlpha + roomsLeft.TeamBeta)
    else
        for _, team in ipairs({ "TeamAlpha", "TeamBeta" }) do
            local free = math.max(0, perTeam - teamCount[team])
            addOwners(team, math.floor(free * share + 0.5), roomsLeft[team])
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
    AvatarTidy.blockHands(model)
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
    NpcAnimator.attach(model, { moving = true })
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
    return npc.model and npc.model.Parent and npc.alive and not npc.leaving
end

-- (walking out: only the leaving walk moves them)
local function canMove(npc, exiting)
    if exiting then
        return npc.model and npc.model.Parent ~= nil
    end
    return alive(npc)
end

local function humanoid(npc)
    return npc.model and npc.model:FindFirstChildOfClass("Humanoid")
end

local function rootOf(npc)
    return npc.model and npc.model:FindFirstChild("HumanoidRootPart")
end

-- Out of a chair first (the seat weld goes with Sit = false; the jump lifts the body clear)
local function standUp(npc)
    local hum = humanoid(npc)
    if hum and hum.SeatPart then
        hum.Sit = false
        hum.Jump = true
        task.wait(0.5)
    end
end

-- Straight there; false if it stalls (something in the way) or times out. `passBy`: an on-the-way
-- point, done as soon as it is near (the walk flows on into the next one, no stop and restart)
local function moveStraight(npc, point, timeout, exiting, passBy)
    local hum = humanoid(npc)
    if not hum or hum.Health <= 0 then
        return false
    end
    local reached = false
    local conn = hum.MoveToFinished:Connect(function(r)
        reached = r
    end)
    local start = os.clock()
    local lastPos, stalledSince = nil, nil
    hum:MoveTo(point)
    while canMove(npc, exiting) and not reached and os.clock() - start < (timeout or 7) do
        local root = rootOf(npc)
        if root then
            if (Vector3.new(root.Position.X, point.Y, root.Position.Z) - point).Magnitude < (passBy and 3 or 1.5) then
                reached = true
                break
            end
            if lastPos and (root.Position - lastPos).Magnitude < 0.15 then
                stalledSince = stalledSince or os.clock()
                if os.clock() - stalledSince > 0.8 then
                    break
                end
            else
                stalledSince = nil
            end
            lastPos = root.Position
        end
        task.wait(0.05)
    end
    conn:Disconnect()
    return reached
end

-- Walk there round chairs, terminals, walls and door frames (PathfindingService; the doors
-- themselves are open on the server), straight if no path is found
local function walkTo(npc, point, timeout, exiting)
    standUp(npc)
    local root = rootOf(npc)
    if not root or not canMove(npc, exiting) then
        return false
    end
    if (root.Position - point).Magnitude < 5 then
        return moveStraight(npc, point, timeout or 4, exiting)
    end
    local path = PathfindingService:CreatePath({ AgentRadius = 1.5, AgentHeight = 5, AgentCanJump = false, AgentCanClimb = false, WaypointSpacing = 4 })
    local ok = pcall(function()
        path:ComputeAsync(root.Position, point)
    end)
    if ok and path.Status == Enum.PathStatus.Success then
        local waypoints = path:GetWaypoints()
        for i = 2, #waypoints do
            if not canMove(npc, exiting) then
                return false
            end
            if not moveStraight(npc, waypoints[i].Position, 4, exiting, i < #waypoints) then
                break
            end
        end
        return moveStraight(npc, point, 3, exiting)
    end
    return moveStraight(npc, point, timeout, exiting)
end

local function face(npc, target)
    local root = rootOf(npc)
    if root and target then
        local p = root.Position
        local flat = Vector3.new(target.X, p.Y, target.Z)
        if (flat - p).Magnitude > 0.5 then
            root.CFrame = CFrame.lookAt(p, flat)
        end
    end
end

-- Stand a while (looking at lookAt() if given); a guest arriving cuts it short
local function idle(npc, seconds, lookAt)
    local untilT = os.clock() + seconds
    while alive(npc) and os.clock() < untilT and not npc.guest do
        if lookAt then
            face(npc, lookAt())
        end
        task.wait(rng:NextNumber(0.8, 2.0))
    end
end

-- A chat bubble over the head: every machine near enough shows it (the stands' bubbles)
local function say(npc, text)
    local head = npc.model and npc.model:FindFirstChild("Head")
    if head then
        sayRemote:FireAllClients(head, text)
    end
end

local function teamOf(npc)
    return npc.team or (npc.room and npc.room.npc and npc.room.npc.team)
end

-- Two talk a topic over: one says something, the other answers a moment later, back and forth
-- (OwnerChatter). Yields until it's done; false if either is already in a conversation.
local function converse(a, b, context)
    if a.talking or b.talking or not (a.model and b.model) then
        return false
    end
    local phase = OwnerChatter.phaseOf(Workspace:GetAttribute("CrowdPhase"))
    local turns = OwnerChatter.conversation(phase, context, rng, teamOf(a))
    a.talking, b.talking = true, true
    task.wait(rng:NextNumber(0.2, 0.7))
    for _, t in ipairs(turns) do
        if not (a.alive and b.alive and a.model and b.model and a.model.Parent and b.model.Parent) then
            break
        end
        local speaker, listener = t.who == 1 and a or b, t.who == 1 and b or a
        say(speaker, t.text)
        local roll = rng:NextNumber()
        if roll < 0.18 then
            NpcAnimator.emote(speaker.model, pick({ "point", "wave", "cheer" }), 1.6)
        elseif roll < 0.3 then
            NpcAnimator.emote(listener.model, "laugh", 1.4)
        end
        -- (time to read it, then the other answers)
        task.wait(math.clamp(#t.text * 0.05, 1.8, 3.6) + rng:NextNumber(0, 0.8))
    end
    a.talking, b.talking = false, false
    return true
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

-- Out over the arena: their own Quin while it fights, else straight out of the glass
local function outThere(npc, room)
    return function()
        local root = rootOf(npc)
        local here = root and root.Position or room.center
        return ownQuinPosition(npc) or (here + room.toArena * 60)
    end
end

-- ============================================================================
-- VISITS: knocking, friends, two managers at the window
-- ============================================================================

local friendships = {} -- "A|B" -> true / false, decided the first time they meet

local function friends(a, b)
    local key = a.name < b.name and (a.name .. "|" .. b.name) or (b.name .. "|" .. a.name)
    if friendships[key] == nil then
        friendships[key] = rng:NextNumber() < 0.5
    end
    return friendships[key]
end

local MANAGER_LINES = {
    "Watch their left side.", "Ours is tiring. Look at the footwork.", "Pull back, pull back...",
    "That one's reckless.", "Patience. Let them come.", "Next round we go aggressive.",
    "See that dodge?!", "Their big one is the threat.", "Keep them apart, keep them apart.",
    "Nice! Nice!", "Too slow on the guard.", "They're baiting us.", "Told you. Told you!",
    "Count the hits, not the swings.", "Two on one, go!", "Ugh. Sloppy.",
}
local KNOCK_REPLIES_NO = { "Not now, I'm busy.", "Come back later.", "Sorry, focusing." }

-- Two at the glass, side by side, looking out at the fight and talking it over
local function discuss(npc, partner, room, spot, seconds, opener)
    walkTo(npc, spot)
    local untilT = os.clock() + seconds
    local look = outThere(npc, room)
    local nextTalk = os.clock() + (opener and rng:NextNumber(1, 2.5) or math.huge)
    while alive(npc) and os.clock() < untilT and partner.alive do
        face(npc, look())
        if os.clock() >= nextTalk and not npc.talking and not partner.talking then
            nextTalk = os.clock() + rng:NextNumber(2, 5)
            task.spawn(converse, npc, partner, "glass")
        end
        task.wait(0.5)
    end
    while npc.talking and alive(npc) do
        task.wait(0.3) -- (let the last word be said)
    end
end

-- Through the door, along the hallway, to another owner's door; in if friends or let in
local function visit(npc, room)
    local others = npc.visitable and npc.visitable() or {}
    if #others == 0 then
        return false
    end
    local target = pick(others)
    local host = target.npc
    if not host or not host.alive or host.guest or host.visiting then
        return false
    end
    target.Api = room.Api
    npc.visiting = true
    local front = target.doorHall + (target.doorInside - target.doorHall).Unit * 2.5
    local reached = walkTo(npc, room.doorInside) and walkTo(npc, room.doorHall) and walkTo(npc, front, 14)
    if reached and alive(npc) and host.alive then
        face(npc, target.door.Position)
        local welcome = friends(npc, host)
        if not welcome then
            say(npc, "*knock knock*")
            task.wait(rng:NextNumber(1.5, 2.5))
            welcome = rng:NextNumber() < 0.65 and not host.guest
            if not welcome then
                say(host, pick(KNOCK_REPLIES_NO))
                task.wait(1.5)
            end
        end
        if welcome and host.alive and not host.guest then
            -- the host comes to the glass; the guest stands beside them
            local base = room.Api.windowPoint(target)
            local along = Vector3.new(0, 0, base.Z > target.center.Z and -1 or 1)
            host.guest = { npc = npc, spot = base, seconds = rng:NextNumber(16, 30) }
            say(host, friends(npc, host) and pick({ "Hey! Get in here.", "Perfect timing.", "Come, look at this." }) or "Alright, come in.")
            walkTo(npc, target.doorInside)
            discuss(npc, host, target, base + along * 2.8, host.guest.seconds, false)
            if alive(npc) then
                say(npc, pick({ "Good luck out there.", "Talk later.", "Ours is up next, gotta go." }))
            end
            host.guest = nil
        end
    end
    -- home again
    if alive(npc) then
        walkTo(npc, target.doorHall, 14)
        walkTo(npc, room.doorHall, 14)
        walkTo(npc, room.doorInside)
        walkTo(npc, room.Api.randomPoint(room, 4))
    end
    npc.visiting = false
    return true
end

-- ============================================================================
-- THE DAY IN THE ROOM
-- ============================================================================

local ACTIONS = {
    -- name, weight before the fight, weight during it (the glass ~70% of the time)
    { "window", 7, 8 },
    { "sit", 1.2, 0.8 },
    { "wander", 0.6, 0.3 },
    { "terminal", 0.5, 0.4 },
    { "visit", 1.0, 1.2 },
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
    return "window"
end

local function act(npc, action)
    local room = npc.room
    local Api = room.Api
    if action == "wander" then
        walkTo(npc, Api.randomPoint(room, 4))
        -- (then turned to something: the glass, or into the room; never left facing a wall)
        local look = rng:NextNumber() < 0.6 and outThere(npc, room) or function()
            return room.center
        end
        idle(npc, rng:NextNumber(2, 4), look)
    elseif action == "sit" and #room.seats > 0 then
        local seat = pick(room.seats)
        if not seat.Occupant then
            walkTo(npc, seat.Position)
            local hum = humanoid(npc)
            if hum and not seat.Occupant and alive(npc) then
                seat:Sit(hum)
            end
            idle(npc, rng:NextNumber(6, 14))
            standUp(npc)
        end
    elseif action == "window" then
        walkTo(npc, Api.windowPoint(room))
        if Workspace:GetAttribute("MatchStarted") == true and rng:NextNumber() < 0.5 then
            task.delay(rng:NextNumber(1, 4), function()
                if alive(npc) and not npc.guest then
                    NpcAnimator.emote(npc.model, pick({ "cheer", "cheer", "point", "wave" }), rng:NextNumber(2, 4))
                end
            end)
        end
        idle(npc, rng:NextNumber(6, 16), outThere(npc, room))
    elseif action == "terminal" and #room.terminals > 0 then
        local t = pick(room.terminals)
        local toward = (room.center - t.Position) * Vector3.new(1, 0, 1)
        local spot = Vector3.new(t.Position.X, room.floorY, t.Position.Z) + (toward.Magnitude > 0 and toward.Unit * 3 or Vector3.zero)
        walkTo(npc, spot)
        idle(npc, rng:NextNumber(3, 6), function()
            return t.Position
        end)
    elseif action == "visit" then
        if not visit(npc, room) then
            act(npc, "window")
        end
    end
end

local function run(npc)
    task.wait(rng:NextNumber(0, 2))
    while alive(npc) and not npc.leaving do
        if npc.guest then
            -- a guest at the door: to the glass together
            local g = npc.guest
            discuss(npc, g.npc, npc.room, g.spot, g.seconds, true)
            npc.guest = nil
        elseif quinsDown(npc) then
            act(npc, "sit") -- (their Quins are out: a sit to take it in; ArenaPrepRoom sends them off soon)
        else
            act(npc, chooseAction())
        end
        task.wait(rng:NextNumber(0.3, 1.0))
    end
end

-- ============================================================================
-- FRIENDS: every owner's room (players' too) gets a few NPC friends
-- ============================================================================
-- Some are in the room when it opens; the rest turn up in the hallway later and knock: an NPC
-- owner lets friends in, a player owner gets the "Let in / No" (ArenaPrepRoom's knock). Inside
-- they watch at the glass beside the owner, sit, chat, and step out into the hallway and back.

local FRIEND_LINES = {
    "Your Quin looks sharp today.", "Ooh, that was close!", "Go go go!", "Is that one ours?",
    "This is intense.", "I'll be right back.", "Did you train it like that?", "Get 'em!!",
    "No way it's still standing.", "Snacks after this?",
}

-- Someone near this friend at the glass to talk to: the owner (an NPC) or another friend
local function glassPartner(npc, room)
    local root = rootOf(npc)
    if not root then
        return nil
    end
    local options = {}
    local near = { table.unpack(room.friends or {}) }
    if room.npc then
        table.insert(near, room.npc)
    end
    for _, other in ipairs(near) do
        local r = other and other ~= npc and other.alive and not other.talking and rootOf(other)
        if r and (r.Position - root.Position).Magnitude < 14 then
            table.insert(options, other)
        end
    end
    return #options > 0 and pick(options) or nil
end

local function friendGlass(npc, room)
    walkTo(npc, room.Api.windowPoint(room))
    local untilT = os.clock() + rng:NextNumber(8, 18)
    local look = function()
        local root = rootOf(npc)
        local host = room.npc
        local q = host and ownQuinPosition(host)
        return q or ((root and root.Position or room.center) + room.toArena * 60)
    end
    while alive(npc) and os.clock() < untilT do
        face(npc, look())
        local roll = rng:NextNumber()
        if roll < 0.14 and not npc.talking then
            local partner = glassPartner(npc, room)
            if partner then
                task.spawn(converse, npc, partner, "glass")
            end
        elseif roll < 0.17 and not npc.talking then
            say(npc, pick(FRIEND_LINES))
            NpcAnimator.emote(npc.model, pick({ "cheer", "cheer", "point", "wave" }), 2)
        end
        task.wait(rng:NextNumber(0.8, 1.6))
    end
end

local function friendStepOut(npc, room)
    -- out into the hallway for a bit, then back in (friends are always let back in)
    if not (walkTo(npc, room.doorInside) and walkTo(npc, room.doorHall)) then
        return
    end
    local along = Vector3.new(0, 0, rng:NextNumber() < 0.5 and -1 or 1)
    walkTo(npc, room.doorHall + along * rng:NextNumber(8, 30), 10)
    idle(npc, rng:NextNumber(3, 8), function()
        return (rootOf(npc) and rootOf(npc).Position or room.doorHall) + along * 10
    end)
    walkTo(npc, room.doorHall, 10)
    walkTo(npc, room.doorInside)
    walkTo(npc, room.Api.randomPoint(room, 4))
end

-- Hallway groups: friends gather in rings of a few, facing each other, talking
local HALL_GROUP_MAX = 6
local HALL_LINES = {
    "You seen the new arena layout?", "My cousin got a Quin last week.", "Haha no way.",
    "Bro, that round was insane.", "Who's your pick tonight?", "I'm starving.", "Wait, is that ours?",
    "Okay okay, listen...", "Nah, Beta's got this.", "Alpha all the way!", "LOL", "Shhh, listen.",
    "Did you hear that crowd?", "Next season I'm entering.", "Where's the workshop again?",
}
local hallGroups = {} -- "side:floor" -> { { center, members = {} } }

local function hallSpot(room, z)
    local hall = room.hallway
    local x = hall and hall.Position.X or room.doorHall.X
    return Vector3.new(x, room.floorY, z)
end

local function joinHallGroup(npc, room)
    local key = room.side .. ":" .. math.floor(room.floorY)
    local list = hallGroups[key] or {}
    hallGroups[key] = list
    for _, g in ipairs(list) do
        if #g.members < HALL_GROUP_MAX and (g.center - room.doorHall).Magnitude < 90 and rng:NextNumber() < 0.9 then
            table.insert(g.members, npc)
            return g, list
        end
    end
    local z = room.doorHall.Z + (rng:NextNumber() < 0.5 and -1 or 1) * rng:NextNumber(4, 36)
    local g = { center = hallSpot(room, z), members = { npc } }
    table.insert(list, g)
    return g, list
end

local function leaveHallGroup(npc, g, list)
    local i = table.find(g.members, npc)
    if i then
        table.remove(g.members, i)
    end
    if #g.members == 0 then
        local j = table.find(list, g)
        if j then
            table.remove(list, j)
        end
    end
end

local function homeAgain(npc, room)
    walkTo(npc, room.doorHall, 14)
    walkTo(npc, room.doorInside)
    walkTo(npc, room.Api.randomPoint(room, 4))
end

local function hallHangout(npc, room)
    if not (walkTo(npc, room.doorInside) and walkTo(npc, room.doorHall)) then
        return
    end
    local g, list = joinHallGroup(npc, room)
    local angle = rng:NextNumber(0, math.pi * 2)
    local spot = g.center + Vector3.new(math.cos(angle) * 2.2, 0, math.sin(angle) * 3)
    walkTo(npc, spot, 14)
    local untilT = os.clock() + rng:NextNumber(10, 28)
    while alive(npc) and os.clock() < untilT do
        face(npc, g.speaker and g.speaker ~= npc and rootOf(g.speaker) and rootOf(g.speaker).Position or g.center)
        local roll = rng:NextNumber()
        if roll < 0.16 and not g.talking and not npc.talking then
            local others = {}
            for _, m in ipairs(g.members) do
                if m ~= npc and m.alive and not m.talking and rootOf(m) then
                    table.insert(others, m)
                end
            end
            if #others > 0 then
                g.talking = true
                g.speaker = npc
                task.spawn(function()
                    converse(npc, pick(others), "hall")
                    g.talking, g.speaker = false, nil
                end)
            elseif roll < 0.05 then
                say(npc, pick(HALL_LINES)) -- (alone for now: a word to nobody in particular)
            end
        elseif roll < 0.2 and not npc.talking then
            NpcAnimator.emote(npc.model, pick({ "laugh", "point", "wave" }), 2)
        end
        task.wait(rng:NextNumber(0.8, 1.6))
    end
    while npc.talking and alive(npc) do
        task.wait(0.3)
    end
    leaveHallGroup(npc, g, list)
    if alive(npc) then
        homeAgain(npc, room)
    end
end

-- Knocking on another room's door along the hallway (a player's room: they get asked)
local function knockAround(npc, room)
    local others = npc.neighbours and npc.neighbours() or {}
    if #others == 0 or not npc.knock then
        return hallHangout(npc, room)
    end
    local target = pick(others)
    if not (walkTo(npc, room.doorInside) and walkTo(npc, room.doorHall)) then
        return
    end
    local front = target.doorHall + (target.doorInside - target.doorHall).Unit * 2.5
    if not walkTo(npc, front, 14) then
        return homeAgain(npc, room)
    end
    face(npc, target.door.Position)
    say(npc, "*knock knock*")
    local answered, allowed = false, false
    npc.knock(target, npc.name, function(allow)
        answered, allowed = true, allow
    end, true)
    local waitUntil = os.clock() + 18
    while alive(npc) and not answered and os.clock() < waitUntil do
        task.wait(0.3)
    end
    if alive(npc) and allowed then
        say(npc, pick({ "Hey! Mind if I watch from here?", "Nice room!", "Who's winning?" }))
        target.Api = room.Api
        walkTo(npc, target.doorInside)
        walkTo(npc, room.Api.windowPoint(target))
        idle(npc, rng:NextNumber(8, 16), function()
            local root = rootOf(npc)
            return (root and root.Position or target.center) + target.toArena * 60
        end)
        walkTo(npc, target.doorInside)
        walkTo(npc, target.doorHall)
    elseif alive(npc) then
        say(npc, pick({ "Guess not.", "Okay, okay.", "Rude." }))
        task.wait(1)
    end
    if alive(npc) then
        homeAgain(npc, room)
    end
end

local function runFriend(npc)
    local room = npc.room
    task.wait(rng:NextNumber(0, 1.5))
    while alive(npc) do
        local roll = rng:NextNumber()
        if roll < 0.28 then
            friendGlass(npc, room)
        elseif roll < 0.36 then
            act(npc, "sit")
        elseif roll < 0.76 then
            hallHangout(npc, room) -- (the hallway is where the dorm life is)
        elseif roll < 0.88 then
            knockAround(npc, room)
        elseif roll < 0.92 then
            friendStepOut(npc, room)
        else
            -- over to the owner for a word (an NPC owner), or a stroll
            local host = room.npc
            local hostRoot = host and alive(host) and rootOf(host)
            if hostRoot then
                walkTo(npc, hostRoot.Position + Vector3.new(rng:NextNumber(-3, 3), 0, rng:NextNumber(-3, 3)))
                face(npc, hostRoot.Position)
                if not converse(npc, host, "glass") then
                    say(npc, pick(FRIEND_LINES))
                    idle(npc, rng:NextNumber(3, 6), function()
                        return hostRoot.Position
                    end)
                end
            else
                act(npc, "wander")
            end
        end
        task.wait(rng:NextNumber(0.3, 1.0))
    end
end

-- Friends for a room: 0 to ArenaNpcFriendsMax (default 5). knock(room, name, callback(allow),
-- stranger) asks a room's owner; neighbours() lists the other occupied rooms along the hallway.
function NpcOwners.addFriends(room, Api, knock, neighbours)
    if not enabled() then
        return
    end
    room.Api = Api
    room.friendToken = (room.friendToken or 0) + 1
    local token = room.friendToken
    room.friends = {}
    local maxFriends = tonumber(Workspace:GetAttribute("ArenaNpcFriendsMax")) or 5
    local count = rng:NextNumber() < 0.12 and 0 or rng:NextInteger(1, math.max(1, maxFriends))
    for _ = 1, count do
        nameIndex = nameIndex % #NAMES + 1
        local npc = { name = NAMES[nameIndex], npc = true, friend = true, room = room, alive = true, quins = {},
            knock = knock, neighbours = neighbours }
        table.insert(room.friends, npc)
        if rng:NextNumber() < 0.5 then
            -- already in the room with the owner
            local spot = Api.randomPoint(room, 4) + Vector3.new(0, 3, 0)
            npc.model = makeAvatar(npc, CFrame.lookAt(spot, spot + room.toArena))
            if npc.model then
                task.spawn(runFriend, npc)
            end
        else
            -- turns up later in the hallway and knocks
            task.delay(rng:NextNumber(8, 45), function()
                if room.friendToken ~= token or not npc.alive then
                    return
                end
                local along = Vector3.new(0, 0, rng:NextNumber() < 0.5 and -1 or 1)
                local start = room.doorHall + along * rng:NextNumber(18, 40) + Vector3.new(0, 3, 0)
                npc.model = makeAvatar(npc, CFrame.lookAt(start, room.doorHall + Vector3.new(0, 3, 0)))
                if not npc.model then
                    return
                end
                local front = room.doorHall + (room.doorInside - room.doorHall).Unit * 2.5
                if not walkTo(npc, front, 14) then
                    return
                end
                face(npc, room.door.Position)
                say(npc, "*knock knock*")
                knock(room, npc.name, function(allow)
                    if not alive(npc) then
                        return
                    end
                    if allow then
                        say(npc, pick({ "Heyyy!", "Made it!", "Did I miss anything?" }))
                        walkTo(npc, room.doorInside)
                        task.spawn(runFriend, npc)
                    else
                        say(npc, "Oh... ok.")
                        task.wait(1.2)
                        walkTo(npc, room.doorHall + along * 40, 14)
                        NpcOwners.leave(npc, false)
                    end
                end)
            end)
        end
    end
end

function NpcOwners.removeFriends(room, walkOut)
    room.friendToken = (room.friendToken or 0) + 1
    for _, npc in ipairs(room.friends or {}) do
        if npc.model then
            NpcOwners.leave(npc, walkOut)
        else
            npc.alive = false
        end
    end
    room.friends = nil
end

-- Put an NPC owner in their room (ArenaPrepRoom.open). `visitable()` lists rooms to visit.
function NpcOwners.enterRoom(npc, room, quins, Api, visitable)
    room.Api = Api
    room.npc = npc -- (visitors find their host)
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

-- Done (all Quins down, or the match is over): walk out of the door (round the furniture), then gone
function NpcOwners.leave(npc, walkOut)
    if not npc.alive or npc.leaving then
        return
    end
    npc.leaving = true -- (the room's loop stops; alive stays true while they walk out)
    if npc.room and npc.room.npc == npc and not npc.friend then
        npc.room.npc = nil
    end
    local model = npc.model
    if not model then
        npc.alive = false
        return
    end
    if walkOut and npc.room then
        task.spawn(function()
            local room = npc.room
            task.wait(0.6) -- (the room loop and any visit notice and stop)
            walkTo(npc, room.doorInside, 8, true)
            walkTo(npc, room.doorHall + (room.doorHall - room.doorInside).Unit * 4, 6, true)
            npc.alive = false
            model:Destroy()
        end)
    else
        npc.alive = false
        model:Destroy()
    end
end

function NpcOwners.clearAll()
    for _, m in ipairs(folder:GetChildren()) do
        m:Destroy()
    end
end

return NpcOwners
