--// ArenaTerminalQueue.lua
-- The lines at an arena's terminals: NPC owners (ArenaRegistration's pool) walk in from the spawn,
-- join the shortest line at the right kind of terminal (walk-in: "ArenaTerminal", prebook:
-- "ArenaPrebookTerminal"), wait their turn talking to their neighbours (OwnerChatter "queue") or
-- muttering, spend a few seconds at the terminal, and only then register (onServed, given by
-- ArenaRegistration: "in" / "full" / "closed"). Then they hang around near the terminals a while
-- and walk back out to the spawn, gone. A bumped owner (a player took the place) says so and leaves.
--
-- A line stands on the terminal's queue platforms (placed in Studio: a group holding one
-- "QueuePlatformTrigger", the front spot, right at the terminal, and the "QueuePlatform"s behind it):
-- the trigger is spot 1, then the platforms nearest first. More people than platforms wait beside
-- the last one. A terminal with no platforms gets a line running back from its face toward the spawn.
--
-- The "Arena Receptionist" behind a terminal (the nearest within CLERK_RANGE) serves its line out
-- loud: "Next, please!" when the front moves up, a word with each NPC owner, and how it went.
-- (Players get their own private conversation: NpcDialog on their machine, ArenaEntry.client.)
--
-- Players and the line (Workspace ArenaQueueSkip, the DEBUG tab):
--   * on (the default): players skip it. A player at a terminal is served at once: the NPC owner at
--     the front waits ("Go ahead.") until the player steps away.
--   * off: a player stepping onto a line's platforms (or near a terminal without them) joins the
--     end of its line, and may register only at the front (Queue.mayUse; player attributes
--     TerminalQueuePos, 1 = your turn, and TerminalQueueKind). Walking away leaves the line.
-- Workspace ArenaQueueBodies: what's going on, for the DEBUG tab.
--
--   Queue.available(kind)                   -> bodies may come (terminals exist, under the cap)
--   Queue.arrive(name, kind, onServed)      -> an NPC owner walks in and queues (false: no body)
--   Queue.bump(name) / Queue.clear()        -> one gives up their place / everyone leaves now
--   Queue.mayUse(player, kind)              -> true | false, ahead (nil: not in line)

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ArenaNpcOwners = require(script.Parent:WaitForChild("ArenaNpcOwners"))
local OwnerChatter = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("OwnerChatter"))
local body = ArenaNpcOwners.body

local Queue = {}

local SPACING = 3.2 -- studs between people in line
local SERVE = { 4, 8 } -- seconds at the terminal
local HANG = { 15, 40 } -- seconds around the terminals after
local MAX_BODIES = 30
local PLAYER_AT = 12 -- studs: a player this close to a terminal is using it (its prompt reaches 12)
local JOIN_RANGE = 12 -- (players in line) this close to a terminal: join its line
local LEAVE_RANGE = 18 -- this far from the line's terminal (beyond the line's end): out of it

local PLATFORM_RANGE = 14 -- studs: a trigger this close to a terminal is its line's front
local ON_SPOT = 2.6 -- studs (flat) from a platform's centre: standing on it
local CLERK_RANGE = 12 -- studs: the receptionist serving a terminal

local PART_NAME = { walkin = "ArenaTerminal", prebook = "ArenaPrebookTerminal" }
local CLERK = {
    next = { "Next, please!", "Next!", "Next in line, please.", "Who's next?" },
    greet = { "Hello! Registering tonight?", "Hi there. Entering your Quins?", "Welcome! Which Quins today?", "Next for the event? Go ahead." },
    ["in"] = { "Thank you! Good luck out there.", "You're in. Thank you!", "All set. Good luck tonight!", "Thank you, enjoy the event." },
    full = { "Sorry, every seat's taken.", "I'm sorry, we're full.", "No seats left, I'm afraid." },
    closed = { "Sorry, entry has just closed.", "I'm afraid entry's closed now." },
}
local ANSWER = { "Yes, both of mine please.", "Just the one tonight.", "Yes please. Same as always.", "Yep. Put me down.", "Two Quins, please." }
local AFTER_YOU = { "Go ahead.", "After you.", "Oh, you first.", "No rush, go on." }
local RESULT = {
    ["in"] = { "Done. We're in!", "Registered. Let's go.", "Got a place!", "That's us in." },
    full = { "Full? You're kidding.", "No seats left...", "Missed it. Next time.", "Full already?" },
    closed = { "Closed? Already?", "Too late, it shut.", "Great, it closed on me." },
}
local BUMPED = { "A player took my place. I'll watch from the stands.", "Bumped by a player. Stands it is.", "Lost my place. Fine, I'll watch." }

local rng = Random.new()
local lines = {} -- [terminal part] = { kind, part, dir, base, spots, clerk, members = { { npc } | { player } }, front }
local bodies = {} -- [npc] = true (npc = { name, model, alive, state = "line" | "hang" | "leaving" })

local function pick(list)
    return list[rng:NextInteger(1, #list)]
end

local function skipOn()
    return Workspace:GetAttribute("ArenaQueueSkip") ~= false
end

local function spawnPoint()
    local spawn = Workspace:FindFirstChildWhichIsA("SpawnLocation", true)
    local base = spawn and spawn.Position or Vector3.new(0, 1, -850)
    return base + Vector3.new(rng:NextNumber(-8, 8), 3, rng:NextNumber(-8, 8))
end

local function terminalsOf(kind)
    local list = {}
    for _, d in ipairs(Workspace:GetDescendants()) do
        if d.Name == PART_NAME[kind] and d:IsA("BasePart") then
            table.insert(list, d)
        end
    end
    return list
end

local function flat(v)
    return Vector3.new(v.X, 0, v.Z)
end

-- The standing points of a terminal's queue platforms, front (the trigger) first; nil if none
local function platformSpots(part)
    local trigger, best = nil, PLATFORM_RANGE
    for _, d in ipairs(Workspace:GetDescendants()) do
        if d.Name == "QueuePlatformTrigger" and d:IsA("BasePart") then
            local gap = flat(d.Position - part.Position).Magnitude
            if gap < best then
                trigger, best = d, gap
            end
        end
    end
    if not trigger then
        return nil
    end
    local pads = {}
    for _, d in ipairs(trigger.Parent:GetChildren()) do
        if d.Name == "QueuePlatform" and d:IsA("BasePart") then
            table.insert(pads, d)
        end
    end
    table.sort(pads, function(a, b)
        return (a.Position - trigger.Position).Magnitude < (b.Position - trigger.Position).Magnitude
    end)
    table.insert(pads, 1, trigger)
    local spots = {}
    for _, pad in ipairs(pads) do
        table.insert(spots, pad.Position + Vector3.new(0, pad.Size.Y / 2 + 3, 0))
    end
    return spots
end

-- The receptionist behind a terminal (a model named "Arena Receptionist"), as a speaker for body.say
local function clerkFor(part)
    local best, gap = nil, CLERK_RANGE
    for _, d in ipairs(Workspace:GetDescendants()) do
        if d.Name == "Arena Receptionist" and d:IsA("Model") and d:FindFirstChild("Head") then
            local g = flat(d:GetPivot().Position - part.Position).Magnitude
            if g < gap then
                best, gap = d, g
            end
        end
    end
    return best and { name = best.Name, model = best, alive = true } or nil
end

-- The line at a terminal: on its queue platforms, or from its face toward the spawn
local function lineFor(part, kind)
    local line = lines[part]
    if line then
        return line
    end
    local spots = platformSpots(part)
    if spots and #spots >= 2 then
        local dir = flat(spots[#spots] - spots[1])
        dir = dir.Magnitude > 0.1 and dir.Unit or Vector3.new(0, 0, -1)
        line = { kind = kind, part = part, dir = dir, base = spots[1], spots = spots, members = {}, clerk = clerkFor(part) }
        part:SetAttribute("QueueSpots", #spots)
        lines[part] = line
        return line
    end
    local look = part.CFrame.LookVector
    local dir = Vector3.new(look.X, 0, look.Z)
    dir = dir.Magnitude > 0.1 and dir.Unit or Vector3.new(0, 0, -1)
    local toSpawn = spawnPoint() - part.Position
    if dir:Dot(Vector3.new(toSpawn.X, 0, toSpawn.Z)) < 0 then
        dir = -dir
    end
    local depth = math.abs(part.CFrame:VectorToObjectSpace(dir):Dot(part.Size)) / 2
    local groundY = part.Position.Y - part.Size.Y / 2
    line = { kind = kind, part = part, dir = dir, members = {}, clerk = clerkFor(part),
        base = Vector3.new(part.Position.X, groundY + 3, part.Position.Z) + dir * (depth + 2.5) }
    lines[part] = line
    return line
end

local function slot(line, i)
    local spots = line.spots
    if not spots then
        return line.base + line.dir * ((i - 1) * SPACING)
    end
    if i <= #spots then
        return spots[i]
    end
    -- (the platforms are full: wait beside the last one, a little apart)
    local side = Vector3.new(-line.dir.Z, 0, line.dir.X)
    local k = i - #spots
    return spots[#spots] + side * 4 + line.dir * ((k - 1) * SPACING)
end

-- Standing on one of the line's platforms (or near its terminal, if it has none)
local function onLine(line, position)
    if not line.spots then
        return (position - line.part.Position).Magnitude <= JOIN_RANGE
    end
    for _, spot in ipairs(line.spots) do
        if flat(position - spot).Magnitude <= ON_SPOT and math.abs(position.Y - spot.Y) < 6 then
            return true
        end
    end
    return false
end

local function indexOf(line, test)
    for i, m in ipairs(line.members) do
        if test(m) then
            return i
        end
    end
    return nil
end

local function rootOf(model)
    return model and model:FindFirstChild("HumanoidRootPart")
end

local function bodyCount()
    local n = 0
    for _ in pairs(bodies) do
        n += 1
    end
    return n
end

-- A player at this terminal (using it): on its front platform, or close to it
local function playerAt(line)
    for _, p in ipairs(Players:GetPlayers()) do
        local root = rootOf(p.Character)
        if root then
            local front = line.spots and line.spots[1]
            if front and flat(root.Position - front).Magnitude <= ON_SPOT + 1 then
                return true
            end
            if (root.Position - line.part.Position).Magnitude <= (line.spots and 6 or PLAYER_AT) then
                return true
            end
        end
    end
    return false
end

local function gone(npc)
    npc.alive = false
    bodies[npc] = nil
    if npc.model then
        npc.model:Destroy()
        npc.model = nil
    end
end

-- Back out to the spawn, then gone
local function leave(npc)
    if npc.state == "leaving" then
        return
    end
    npc.state = "leaving"
    task.spawn(function()
        body.walkTo(npc, spawnPoint(), 60)
        gone(npc)
    end)
end

local function removeFrom(line, npc)
    local i = indexOf(line, function(m)
        return m.npc == npc
    end)
    if i then
        table.remove(line.members, i)
    end
end

-- Done at the terminal: stand around near the terminals a while (talking to another one there)
local function hangAround(npc, line)
    npc.state = "hang"
    local side = Vector3.new(-line.dir.Z, 0, line.dir.X)
    local spot = line.base + line.dir * rng:NextNumber(14, 26) + side * rng:NextNumber(-12, 12)
    body.walkTo(npc, spot, 12)
    local untilT = os.clock() + rng:NextNumber(HANG[1], HANG[2])
    while npc.alive and npc.state == "hang" and os.clock() < untilT do
        if rng:NextNumber() < 0.15 and not npc.talking then
            for other in pairs(bodies) do
                if other ~= npc and other.state == "hang" and not other.talking and other.model and npc.model
                    and (rootOf(other.model).Position - rootOf(npc.model).Position).Magnitude < 30 then
                    body.walkTo(npc, rootOf(other.model).Position + side * 3, 8)
                    body.face(npc, rootOf(other.model).Position)
                    body.face(other, rootOf(npc.model).Position)
                    body.converse(npc, other, "queue")
                    break
                end
            end
        end
        task.wait(rng:NextNumber(1.5, 3))
    end
    if npc.alive and npc.state == "hang" then
        leave(npc)
    end
end

-- One in line: move up as the line moves, talk, and at the front use the terminal
local function waitInLine(npc, member, line, onServed)
    local saidAfterYou = false
    while npc.alive and npc.state == "line" do
        local i = indexOf(line, function(m)
            return m == member
        end)
        if not i then
            break
        end
        local root = rootOf(npc.model)
        local spot = slot(line, i)
        if root and (Vector3.new(root.Position.X, spot.Y, root.Position.Z) - spot).Magnitude > 1.8 then
            body.walkTo(npc, spot, 15)
            body.face(npc, line.part.Position)
        end
        if i == 1 then
            if skipOn() and playerAt(line) then -- (players skip the line: wait for them)
                if not saidAfterYou then
                    body.say(npc, pick(AFTER_YOU))
                    saidAfterYou = true
                end
                task.wait(1)
            else
                body.face(npc, line.part.Position)
                local clerk = line.clerk
                if clerk and clerk.model.Parent then -- (a word with the receptionist)
                    task.wait(0.8)
                    body.say(clerk, pick(CLERK.greet))
                    task.wait(rng:NextNumber(1.6, 2.4))
                    if npc.alive and npc.state == "line" then
                        body.say(npc, pick(ANSWER))
                    end
                end
                task.wait(rng:NextNumber(SERVE[1], SERVE[2]))
                if not (npc.alive and npc.state == "line") then
                    break
                end
                if skipOn() and playerAt(line) then -- (a player walked up meanwhile: they go first)
                    continue
                end
                local result = onServed() or "full"
                if clerk and clerk.model.Parent then
                    body.say(clerk, pick(CLERK[result] or CLERK.full))
                    task.wait(1.4)
                end
                body.say(npc, pick(RESULT[result] or RESULT.full))
                if result == "in" then
                    body.emote(npc, "cheer", 1.5)
                end
                removeFrom(line, npc)
                if result == "in" then
                    hangAround(npc, line)
                else
                    leave(npc)
                end
                return
            end
        else
            -- waiting: now and then a word with the one ahead, or a mutter
            local ahead = line.members[i - 1] and line.members[i - 1].npc
            local roll = rng:NextNumber()
            if roll < 0.05 and ahead and not ahead.talking and not npc.talking then
                task.spawn(body.converse, npc, ahead, "queue")
            elseif roll < 0.07 and not npc.talking then
                body.say(npc, OwnerChatter.queueLine(rng))
            end
            task.wait(0.5)
        end
    end
    removeFrom(line, npc)
end

function Queue.available(kind)
    return #terminalsOf(kind) > 0 and bodyCount() < MAX_BODIES
end

-- An NPC owner walks in from the spawn and queues at the shortest line of that kind; onServed()
-- registers them when their turn comes. False: no body could be made (register them directly).
function Queue.arrive(name, kind, onServed)
    local parts = terminalsOf(kind)
    if #parts == 0 or bodyCount() >= MAX_BODIES then
        return false
    end
    local best = nil
    for _, part in ipairs(parts) do
        local line = lineFor(part, kind)
        if not best or #line.members < #best.members or (#line.members == #best.members and rng:NextNumber() < 0.5) then
            best = line
        end
    end
    local npc = { name = name, alive = true, state = "line" }
    local from = spawnPoint()
    npc.model = body.make(npc, CFrame.lookAt(from, Vector3.new(best.base.X, from.Y, best.base.Z)))
    if not npc.model then
        return false
    end
    npc.model:SetAttribute("TerminalQueue", kind)
    bodies[npc] = true
    local member = { npc = npc }
    table.insert(best.members, member)
    task.spawn(waitInLine, npc, member, best, onServed)
    return true
end

-- A player took their place: they say so and leave (if they're still around)
function Queue.bump(name)
    for npc in pairs(bodies) do
        if npc.name == name and npc.state ~= "leaving" then
            body.say(npc, pick(BUMPED))
            leave(npc)
            return
        end
    end
end

-- Everyone gone now (NPC owners switched off, or the event changed)
function Queue.clear()
    for npc in pairs(bodies) do
        gone(npc)
    end
    for _, line in pairs(lines) do
        line.members = {}
    end
    for _, p in ipairs(Players:GetPlayers()) do
        p:SetAttribute("TerminalQueuePos", nil)
        p:SetAttribute("TerminalQueueKind", nil)
    end
end

-- May this player use a terminal of this kind now? (players skip the line, or they're at its front)
function Queue.mayUse(player, kind)
    if skipOn() then
        return true
    end
    for _, line in pairs(lines) do
        if line.kind == kind then
            local i = indexOf(line, function(m)
                return m.player == player
            end)
            if i then
                return i == 1, i - 1
            end
        end
    end
    return false, nil
end

-- Players in the lines (skip off): join the line of the terminal you walk up to, leave it by
-- walking away; and what's going on, for the DEBUG tab
task.spawn(function()
    while true do
        task.wait(0.3)
        local skip = skipOn()
        for _, kind in ipairs({ "walkin", "prebook" }) do
            for _, part in ipairs(terminalsOf(kind)) do
                lineFor(part, kind)
            end
        end
        for _, p in ipairs(Players:GetPlayers()) do
            local root = rootOf(p.Character)
            local inLine, pos = nil, nil
            for _, line in pairs(lines) do
                local i = indexOf(line, function(m)
                    return m.player == p
                end)
                if i then
                    -- (off the platforms, away from your spot: out of the line; stepped aside at the front too)
                    local away = line.spots and not onLine(line, root and root.Position or Vector3.zero)
                        and (not root or flat(root.Position - slot(line, i)).Magnitude > 4)
                    local reach = LEAVE_RANGE + #line.members * SPACING
                    if skip or not root or away or (not line.spots and (root.Position - line.part.Position).Magnitude > reach) then
                        table.remove(line.members, i)
                    else
                        inLine, pos = line, i
                    end
                end
            end
            if not skip and not inLine and root then
                for _, line in pairs(lines) do
                    if onLine(line, root.Position) then
                        table.insert(line.members, { player = p })
                        inLine, pos = line, #line.members
                        break
                    end
                end
            end
            p:SetAttribute("TerminalQueuePos", pos)
            p:SetAttribute("TerminalQueueKind", inLine and inLine.kind or nil)
        end
        -- the receptionist calls the next one up when the front changes
        for _, line in pairs(lines) do
            local front = line.members[1]
            if front ~= line.front then
                if front and line.front and line.clerk and line.clerk.model.Parent then
                    body.say(line.clerk, pick(CLERK.next))
                end
                line.front = front
            end
        end
        local counts = { walkin = 0, prebook = 0 }
        for _, line in pairs(lines) do
            for _, m in ipairs(line.members) do
                if m.npc then
                    counts[line.kind] += 1
                end
            end
        end
        local around = 0
        for npc in pairs(bodies) do
            if npc.state ~= "line" then
                around += 1
            end
        end
        Workspace:SetAttribute("ArenaQueueBodies", string.format("in line: %d at the arena terminals, %d at the prebook terminals  •  %d around",
            counts.walkin, counts.prebook, around))
    end
end)

return Queue
