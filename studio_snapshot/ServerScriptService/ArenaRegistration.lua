--// ArenaRegistration.lua
-- Getting your own Quins into the arena's events, and the fair queue that seats the rounds.
-- Two ways in (owner, 2026-10-24), both for the whole event window (all its rounds):
--
--   * PREBOOK at an Arena Prebook Terminal (the Workspace parts named "ArenaPrebookTerminal", by
--     the Arena Boards around Argonia; each gets a "Prebook Quins" ProximityPrompt). The boards
--     ("ArenaBoard") only show who is booked (ArenaBoardClient). Open from the end of the event
--     before until this event starts.
--     Booking early is cheaper: up to ArenaTiming PrebookDiscount off, sliding to full price at the start;
--     the price you booked at holds for every round of the event. You pick your side (the side
--     guard can turn a strong Quin away from a side that is already well ahead). A deposit of one
--     round per Quin is paid at booking and counts as that Quin's first round; a deposit never
--     used comes back in full when the event ends. Cancelling keeps CANCEL_KEEP of what is unused.
--     Prebooked Quins are seated before walk-ins, on their side.
--   * WALK-IN at an Arena Terminal (an arena worker at the venue, "Register Quins"): the event on
--     now, or the next one from ArenaTiming WalkInOpensBefore (20 min) before it opens, until the
--     close rule (WalkInCloseRule: 5 real minutes before the window ends, or when no new round can
--     start). All live-tunable in the ARENA MENU [DEBUG]. Full price, paid each round a Quin is seated.
--     The side is set when you register: the lighter one (players' and NPC prebooks' Quins), so the
--     receptionist can send you to your side's prep rooms at once ("goprep"); NPC owners walking in
--     fill the other side at seating, which evens it out.
--
--   * BE THERE (owner, 2026-10-25): a registered owner must be inside the arena's grounds (a circle
--     round its ArenaGround, BOUNDARY_MARGIN beyond its edge: Workspace ArenaBoundaryCentre /
--     ArenaBoundaryRadius) when each round starts, and stay while the event is on. Before the event
--     you may roam; outside when a round's entrants are picked, or outside LEAVE_GRACE seconds while
--     it's live, and your entry is gone (a prebook's unused deposit too; walk-ins pay per round, so
--     nothing). Quins already fighting finish their round. Player ArenaOutside (true) / ArenaLeaveIn
--     (seconds left) for the warning on their screen.
--
--   * How many Quins: the window's PerPlayer (ArenaSchedule): 2 in the 16v16 battles, entered
--     together (same team), 1 otherwise.
--   * Fair queue: prebooked first; then the players who have sat out the most rounds, then who
--     entered first. Every player in that order gets their first Quin seated before anyone gets a
--     second. Seated: back to 0. Not seated: +1, so you are first next time.
--   * Empty seats are filled by the arena's own Quins (NPQs), so a round never waits for players.
--   * A Quin you can't pay for, or a busy one (QuinCare: Workshop, training), sits that round
--     out. The orchestrator pays out at the winner and refunds a round stopped before it.
--
-- The Arena System Orchestrator calls pickRound when the preparation room opens (the Quins and
-- their owners go to the pads: ArenaPrepRoom) and roundOver when the match ends.
--
-- State the clients read: Workspace ArenaRegOpen / ArenaRegWindow / ArenaRegKind ("Live" /
-- "Soon") / ArenaRegStartsAt / ArenaRegEndsAt / ArenaRegClosesAt / ArenaRegPerPlayer (the
-- walk-in desk) and ArenaPrebookOpen / ArenaPrebookEvent / ArenaPrebookOpensAt /
-- ArenaPrebookStartsAt / ArenaPrebookRate / ArenaPrebookVersion (the boards) / ArenaEntrants /
-- ArenaRoundSeats; each Player ArenaEntered / ArenaEntrySlots ("1,3") / ArenaQueuePos /
-- ArenaSatOut / ArenaInRound / ArenaPrebooked / ArenaPrebookSide / ArenaSide (prebook or walk-in).
-- Remote: ArenaNetwork.ArenaEntry (RemoteFunction) "roster" | "register", { slots = {..}, room = n } |
-- "withdraw" | "prebook", { slots = {..}, side = "TeamAlpha" | "TeamBeta", room = n } | "cancel" | "board" |
-- "goprep" (entered, at a terminal: off to your side's prep room hallway now) |
-- (room: the prep room wished for, 1-16 on the owner's side, nil = any; ArenaPrepRoom seats it.
-- A prebook's room is a claim: no other prebook on that side may take it. A walk-in's is a wish.)
-- "quick" (DEBUG, Studio or admins: QUICK MATCH in the ARENA MENU [DEBUG]. Moves the clock
-- into the next 16v16 Team Battles window if it isn't in one, enters your Quins and starts a round now).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local QuinCore = ReplicatedStorage:WaitForChild("QuinCore")
local SkylarkTime = require(QuinCore:WaitForChild("SkylarkTime"))
local ArenaSchedule = require(QuinCore:WaitForChild("ArenaSchedule"))
local ARENA_NAME = require(QuinCore:WaitForChild("SkylarkArenas")).current().Name
local TERMINAL = "an " .. ARENA_NAME .. " terminal"
local PREBOOK_TERMINAL = "an " .. ARENA_NAME .. " prebook terminal"
local Temperament = require(QuinCore.Modules:WaitForChild("Temperament"))
local QuinRosterService = require(ServerScriptService:WaitForChild("QuinRosterService"))
local Payouts = require(ServerScriptService:WaitForChild("SkylarkPayouts"))
local QuinCare = require(ServerScriptService:WaitForChild("QuinCare"))
local ArenaTiming = require(QuinCore:WaitForChild("ArenaTiming"))
local ArenaNpcOwners = require(ServerScriptService:WaitForChild("ArenaNpcOwners"))
local TerminalQueue = require(ServerScriptService:WaitForChild("ArenaTerminalQueue"))

local Registration = {}

local TERMINAL_RANGE = 16 -- studs: walk in only at a terminal
local PREBOOK_RANGE = 16 -- studs: prebook only at a prebook terminal
local CANCEL_KEEP = 0.25 -- of an unused deposit, kept when a prebook is cancelled
local GUARD_AHEAD = 1.15 -- a side this much stronger than the other (plus one owner's booking) is "ahead"
local BOUNDARY_MARGIN = 250 -- studs beyond the arena ground's edge: still inside the arena's grounds
local LEAVE_GRACE = 10 -- seconds outside while the event is live before the entry is gone

local entries = {} -- [userId] = { player, slots, registeredAt, satOut, prebook?, side?, rate?, credit = { [slot] = SC } }
local windowKey = nil -- the event the entries are for
local windowSlot = nil
local windowKind = nil -- "Live" | "Soon" (walk-in desk open) | "Booking" (boards only)
local boardVersion = 0

-- NPC OWNERS IN THE QUEUE: when an event's boards open, a pool of NPC owners (ArenaNpcOwners.newOwner)
-- is made for it, each with an arrival time: ~40% prebook (a side by the same strength rule, shown
-- on the boards), the rest walk in once the desk opens. Arriving, one registers if the event still
-- has seats for its Quins (players' and NPC owners' Quins counted), else it doesn't get in. They are
-- real entries: the same owners fill the prep rooms round after round. Players always come first:
-- they are seated before any NPC owner, and a player registering into a full event bumps the
-- newest NPC owner (walk-ins before prebooks). Off: Workspace ArenaNpcOwners = false (they leave).
-- Arriving, they walk in and queue at the terminals (ArenaTerminalQueue) and register when served;
-- an arrival more than NPC_CATCHUP real seconds late (the clock was moved) registers at once.
local npcEntries = {} -- { npc = { name, quins }, prebook, side, registeredAt } in arrival order
local npcPending = {} -- { npc, at (clock time), prebook } still to arrive
local NPC_PREBOOK_SHARE = 0.4
local NPC_SPARE = 4 -- Quins in the pool beyond the seats (the late ones find it full)
local NPC_CATCHUP = 90 -- real seconds
local npcRng = Random.new()
local buildNpcPool, npcTick, makeRoomForPlayers -- (below)

-- ============================================================================
-- ARENA TERMINALS (walk-in) AND ARENA BOARDS (prebook)
-- ============================================================================

local function partsNamed(name)
    local list = {}
    for _, part in ipairs(Workspace:GetDescendants()) do
        if part.Name == name and part:IsA("BasePart") then
            table.insert(list, part)
        end
    end
    return list
end

local function terminals()
    return partsNamed("ArenaTerminal")
end

local function prebookTerminals()
    return partsNamed("ArenaPrebookTerminal")
end

local function addPrompt(part, name, action, object, distance)
    if not part:FindFirstChild(name) then
        local prompt = Instance.new("ProximityPrompt")
        prompt.Name = name
        prompt.ActionText = action
        prompt.ObjectText = object
        prompt.HoldDuration = 0
        prompt.MaxActivationDistance = distance
        prompt.RequiresLineOfSight = false
        prompt.Parent = part
    end
end

for _, terminal in ipairs(terminals()) do
    terminal.Anchored = true -- (they were loose parts and could be knocked over)
    addPrompt(terminal, "ArenaTerminalPrompt", "Register Quins", "Arena Terminal", 12)
end
for _, terminal in ipairs(prebookTerminals()) do
    terminal.Anchored = true
    addPrompt(terminal, "ArenaPrebookPrompt", "Prebook Quins", "Arena Prebook", 12)
end

local function rootOf(player)
    local character = player.Character
    return character and character:FindFirstChild("HumanoidRootPart")
end

local function nearTerminal(player)
    local root = rootOf(player)
    if not root then
        return false
    end
    for _, terminal in ipairs(terminals()) do
        if (terminal.Position - root.Position).Magnitude <= TERMINAL_RANGE then
            return true
        end
    end
    return false
end

local function nearPrebookTerminal(player)
    local root = rootOf(player)
    if not root then
        return false
    end
    for _, terminal in ipairs(prebookTerminals()) do
        if (terminal.Position - root.Position).Magnitude <= PREBOOK_RANGE then
            return true
        end
    end
    return false
end

-- ============================================================================
-- STRENGTH (worked out only from what the board shows) AND PRICE
-- ============================================================================

local function band(v, low, high, names)
    return v < low and names[1] or (v >= high and names[3] or names[2])
end

-- One Quin's strength, 10..100: its record (smoothed), its condition, its Bond
local function strength(quin)
    local record = quin.BattleRecord or {}
    local winRate = ((record.Wins or 0) + 1) / ((record.Battles or 0) + 2)
    return 10 + 40 * winRate + 30 * QuinCare.condition(quin) / 100 + 20 * math.clamp((quin.Bond or 0) / 100, 0, 1)
end

-- The price of one round for a prebook made now
local function prebookRate()
    if not windowSlot then
        return Payouts.ENTRY_FEE
    end
    local opensAt = windowSlot.PrebookOpensAt or windowSlot.StartsAt
    local span = math.max(1, windowSlot.StartsAt - opensAt)
    local early = math.clamp((windowSlot.StartsAt - SkylarkTime.now()) / span, 0, 1)
    return math.floor(Payouts.ENTRY_FEE * (1 - ArenaTiming.get("PrebookDiscount") * early) + 0.5)
end

-- ============================================================================
-- QUEUE
-- ============================================================================

local function ordered()
    local list = {}
    for _, e in pairs(entries) do
        table.insert(list, e)
    end
    table.sort(list, function(a, b)
        if (a.prebook == true) ~= (b.prebook == true) then
            return a.prebook == true
        end
        if a.satOut ~= b.satOut then
            return a.satOut > b.satOut
        end
        return a.registeredAt < b.registeredAt
    end)
    return list
end

local function publish()
    local list = ordered()
    for pos, e in ipairs(list) do
        local slots = {}
        for _, s in ipairs(e.slots) do
            table.insert(slots, tostring(s))
        end
        e.player:SetAttribute("ArenaEntered", true)
        e.player:SetAttribute("ArenaEntrySlots", table.concat(slots, ","))
        e.player:SetAttribute("ArenaQueuePos", pos)
        e.player:SetAttribute("ArenaSatOut", e.satOut)
        e.player:SetAttribute("ArenaPrebooked", e.prebook == true)
        e.player:SetAttribute("ArenaPrebookSide", e.prebook and e.side or nil)
        e.player:SetAttribute("ArenaSide", e.side)
        e.player:SetAttribute("ArenaRoomWish", e.room)
    end
    Workspace:SetAttribute("ArenaEntrants", #list)
    boardVersion += 1
    Workspace:SetAttribute("ArenaPrebookVersion", boardVersion) -- (the boards redraw)
end

-- A prep room number, 1-16, or nil (any)
local ROOMS_PER_SIDE = 16
local function roomWish(v)
    v = tonumber(v)
    if not v or v ~= math.floor(v) or v < 1 or v > ROOMS_PER_SIDE then
        return nil
    end
    return v
end

local function clearPlayer(player)
    player:SetAttribute("ArenaRoomWish", nil)
    player:SetAttribute("ArenaEntered", false)
    player:SetAttribute("ArenaEntrySlots", nil)
    player:SetAttribute("ArenaQueuePos", nil)
    player:SetAttribute("ArenaSatOut", nil)
    player:SetAttribute("ArenaPrebooked", nil)
    player:SetAttribute("ArenaPrebookSide", nil)
    player:SetAttribute("ArenaSide", nil)
    player:SetAttribute("ArenaOutside", nil)
    player:SetAttribute("ArenaLeaveIn", nil)
end

local function unusedCredit(e)
    local total = 0
    for _, amount in pairs(e.credit or {}) do
        total += amount
    end
    return total
end

-- The event is over: a deposit never used comes back in full
local function clearAll()
    for _, e in pairs(entries) do
        local unused = unusedCredit(e)
        if unused > 0 then
            Payouts.refund(e.player, unused, "Prebook deposit back (not seated)")
        end
        clearPlayer(e.player)
    end
    entries = {}
    npcEntries, npcPending = {}, {}
    TerminalQueue.clear()
    publish()
end

-- The event entries are for: the one on now, else the next one (boards; the walk-in desk too from
-- WalkInOpensBefore)
local function targetWindow()
    local t = SkylarkTime.now()
    local slot = ArenaSchedule.slotAt(t)
    if slot.Kind == "Event" then
        return slot, "Live"
    end
    local nextEvent = ArenaSchedule.nextEvent(t)
    if not nextEvent then
        return nil
    end
    return nextEvent, nextEvent.StartsAt - t <= ArenaTiming.get("WalkInOpensBefore") and "Soon" or "Booking"
end

-- The walk-in desk closes by ArenaTiming's close rule
local function closesAt(slot)
    return ArenaTiming.walkInClosesAt(slot)
end

local function entryOpen()
    return windowSlot ~= nil and windowKind ~= "Booking" and SkylarkTime.now() < closesAt(windowSlot)
end

local function prebookOpen()
    return windowSlot ~= nil and windowKind ~= "Live" and SkylarkTime.now() < windowSlot.StartsAt
end

-- When the boards opened for this event: the end of the event before it
local function prebookOpensAt(slot)
    return ArenaTiming.prebookOpensAt(ArenaSchedule, slot)
end

local function refreshWindow()
    local slot, kind = targetWindow()
    local key = slot and slot.Key
    if key ~= windowKey then
        if next(entries) then
            print(string.format("[ArenaRegistration] Event over: %d entries cleared", Workspace:GetAttribute("ArenaEntrants") or 0))
        end
        clearAll()
        windowKey = key
        windowSlot = slot
        if slot then
            slot.PrebookOpensAt = prebookOpensAt(slot)
            buildNpcPool(slot)
        end
    end
    windowKind = kind
    -- Before the walk-in desk opens only prebooks can stand (walk-ins left over from a clock set back)
    if kind == "Booking" then
        local dropped = false
        for userId, e in pairs(entries) do
            if not e.prebook then
                entries[userId] = nil
                clearPlayer(e.player)
                dropped = true
            end
        end
        for i = #npcEntries, 1, -1 do
            if not npcEntries[i].prebook then
                table.remove(npcEntries, i)
                dropped = true
            end
        end
        if dropped then
            publish()
        end
    end
    local walkIn = slot and kind ~= "Booking"
    Workspace:SetAttribute("ArenaRegOpen", entryOpen())
    Workspace:SetAttribute("ArenaRegWindow", walkIn and slot.Name or nil)
    Workspace:SetAttribute("ArenaRegKind", walkIn and kind or nil)
    Workspace:SetAttribute("ArenaRegStartsAt", walkIn and slot.StartsAt or nil)
    Workspace:SetAttribute("ArenaRegEndsAt", walkIn and slot.EndsAt or nil)
    Workspace:SetAttribute("ArenaRegClosesAt", walkIn and closesAt(slot) or nil)
    Workspace:SetAttribute("ArenaRegPerPlayer", ArenaSchedule.perPlayer(slot))
    local open = prebookOpen()
    Workspace:SetAttribute("ArenaPrebookOpen", open)
    Workspace:SetAttribute("ArenaPrebookEvent", slot and slot.Name or nil)
    Workspace:SetAttribute("ArenaPrebookOpensAt", slot and slot.PrebookOpensAt or nil)
    Workspace:SetAttribute("ArenaPrebookStartsAt", slot and slot.StartsAt or nil)
    Workspace:SetAttribute("ArenaPrebookRate", open and prebookRate() or nil)
end

-- ============================================================================
-- ROUNDS (called by the Arena System Orchestrator)
-- ============================================================================

local function ArenaNetworkFolder()
    return ReplicatedStorage:FindFirstChild("ArenaNetwork") or ReplicatedStorage
end

local function notice(player, text)
    local remote = ArenaNetworkFolder():FindFirstChild("PrepRoom")
    if remote then
        remote:FireClient(player, "notice", text)
    end
end

local function seatsFor(mode, teamSize)
    if mode == "FFA" then
        return math.max(2, teamSize)
    elseif mode == "1vs1" then
        return 2
    elseif mode == "TeamBattle" then
        return teamSize * 2
    end
    return 0 -- (Player Quin modes: the pilot's own match)
end

-- The Quins seated in this round: { player, quin, team, paid } each (team nil in FFA); a player's
-- Quins are on the same side. Only while the event the entries are for is live, so a test match
-- before an event leaves the queue alone.
function Registration.pickRound(mode, teamSize)
    refreshWindow()
    local slot = ArenaSchedule.slotAt(SkylarkTime.now())
    local seats = seatsFor(mode, teamSize)
    Workspace:SetAttribute("ArenaRoundSeats", seats)
    if seats == 0 or not windowKey or slot.Key ~= windowKey or (not next(entries) and #npcEntries == 0) then
        return {}
    end
    local perTeam = mode == "FFA" and seats or (mode == "1vs1" and 1 or teamSize)
    local perPlayer = ArenaSchedule.perPlayer(windowSlot)
    for _, e in ipairs(ordered()) do -- (not inside the arena's grounds as the round starts: out)
        if not Registration.insideArena(e.player) then
            Registration.dropAbsent(e, string.format("You weren't inside %s when the round started: your entry for %s is gone.", ARENA_NAME, windowSlot.Name))
        end
    end
    local queue = ordered()
    local entrants = {}
    local teamCount = { TeamAlpha = 0, TeamBeta = 0 }
    local sideOf = {}

    local function seat(e, slotIndex)
        if #entrants >= seats then
            return false
        end
        local quin = QuinRosterService.getQuinInSlot(e.player, slotIndex)
        if not quin then
            return false
        end
        local team = nil
        if mode ~= "FFA" then
            team = sideOf[e] or e.side
            if not team then -- (walk-in: the side with fewer seated Quins; the owner's next Quin joins it)
                team = teamCount.TeamAlpha <= teamCount.TeamBeta and "TeamAlpha" or "TeamBeta"
            end
            if teamCount[team] >= perTeam then
                return false
            end
        end
        local tag = quin.QuinId and quin.QuinId:sub(3, 6) or "?"
        if QuinCare.isBusy(quin) then -- (in the Workshop or training: it sits this round out, free)
            notice(e.player, string.format("Quin #%s sits this round out: busy (%s).", tag, quin.Busy.Kind))
            return false
        end
        local price = e.rate or Payouts.ENTRY_FEE
        if e.credit and (e.credit[slotIndex] or 0) > 0 then
            e.credit[slotIndex] = nil -- (its prebook deposit pays this round)
        else
            local paid, why = Payouts.chargeEntry(e.player, tag, price)
            if not paid then
                notice(e.player, string.format("Quin #%s sits this round out: %s", tag, tostring(why)))
                return false
            end
        end
        if team then
            sideOf[e] = team
            teamCount[team] += 1
        end
        table.insert(entrants, { player = e.player, quin = quin, team = team, paid = price, room = e.room })
        return true
    end

    -- first Quins in queue order, then second Quins in the same order
    local seated = {}
    for pass = 1, perPlayer do
        for _, e in ipairs(queue) do
            local slotIndex = e.slots[pass]
            if slotIndex and (pass == 1 or seated[e]) and seat(e, slotIndex) then
                seated[e] = true
            end
        end
    end
    for _, e in ipairs(queue) do
        if seated[e] then
            e.satOut = 0
            e.player:SetAttribute("ArenaInRound", true)
        else
            e.satOut += 1
        end
    end
    local playerQuins = #entrants

    -- then the NPC owners in the queue, after every player: prebooks on their sides, walk-ins
    -- strongest first, each to the side that will be weaker (its Quins plus its empty seats at ~55)
    local sum = { TeamAlpha = 0, TeamBeta = 0 }
    for _, en in ipairs(entrants) do
        if en.team then
            sum[en.team] += strength(en.quin)
        end
    end
    local function seatNpc(ne, team)
        local owner = { name = ne.npc.name, npc = true, team = team } -- (a fresh one each round: the prep room gives it a body)
        for _, q in ipairs(ne.npc.quins) do
            if #entrants >= seats or (team and teamCount[team] >= perTeam) then
                break
            end
            table.insert(entrants, { npc = owner, quin = q, team = team })
            if team then
                teamCount[team] += 1
                sum[team] += strength(q)
            end
        end
    end
    local npcPrebooks, npcWalkIns = {}, {}
    for _, ne in ipairs(npcEntries) do
        table.insert(ne.prebook and npcPrebooks or npcWalkIns, ne)
    end
    for _, ne in ipairs(npcPrebooks) do
        seatNpc(ne, mode ~= "FFA" and (ne.side or "TeamAlpha") or nil)
    end
    local power = {}
    for _, ne in ipairs(npcWalkIns) do
        power[ne] = 0
        for _, q in ipairs(ne.npc.quins) do
            power[ne] += strength(q)
        end
    end
    table.sort(npcWalkIns, function(a, b)
        return power[a] > power[b]
    end)
    for _, ne in ipairs(npcWalkIns) do
        if #entrants >= seats then
            break
        end
        local team = nil
        if mode ~= "FFA" then
            local roomA, roomB = perTeam - teamCount.TeamAlpha, perTeam - teamCount.TeamBeta
            if roomA <= 0 and roomB <= 0 then
                break
            end
            team = roomA <= 0 and "TeamBeta" or (roomB <= 0 and "TeamAlpha"
                or ((sum.TeamAlpha + roomA * 55 <= sum.TeamBeta + roomB * 55) and "TeamAlpha" or "TeamBeta"))
        end
        seatNpc(ne, team)
    end

    publish()
    print(string.format("[ArenaRegistration] %s: %d of %d seats to players' Quins, %d to NPC owners in the queue, %d left for arena Quins",
        windowSlot and windowSlot.Name or "Round", playerQuins, seats, #entrants - playerQuins, seats - #entrants))
    return entrants
end

function Registration.roundOver()
    for _, player in ipairs(Players:GetPlayers()) do
        player:SetAttribute("ArenaInRound", nil)
    end
end

-- ============================================================================
-- PLAYER REQUESTS
-- ============================================================================

local function rosterSummary(player)
    local roster = QuinRosterService.getRoster(player)
    local list = {}
    for slot = 1, roster.UnlockedSlots do
        local q = roster.Slots[slot]
        if q then
            local record = q.BattleRecord or {}
            table.insert(list, {
                Slot = slot,
                Tag = q.QuinId and q.QuinId:sub(3, 6) or "?",
                Gender = q.Gender,
                Title = q.Titles and q.Titles.Current or nil,
                Wins = record.Wins or 0,
                Losses = record.Losses or 0,
                Condition = math.floor(QuinCare.condition(q) + 0.5),
                Busy = q.Busy and q.Busy.Kind or nil,
            })
        end
    end
    return list
end

local function chooseSlots(player, slots)
    if type(slots) ~= "table" then
        slots = { slots }
    end
    local perPlayer = ArenaSchedule.perPlayer(windowSlot)
    local chosen, seen = {}, {}
    for _, s in ipairs(slots) do
        s = tonumber(s)
        if s and not seen[s] and #chosen < perPlayer and QuinRosterService.getQuinInSlot(player, s) then
            seen[s] = true
            table.insert(chosen, s)
        end
    end
    return chosen
end

local sideStrength -- (below)

-- A walk-in's side: the lighter one, if it has places left for these Quins (none in FFA)
local function walkInSide(player, quins)
    local m = windowSlot and windowSlot.Match
    if not m or m.Mode == "FFA" then
        return nil
    end
    local perTeam = m.Mode == "TeamBattle" and (m.TeamSize or 1) or 1
    local sum, count = sideStrength(player.UserId)
    local side = sum.TeamAlpha <= sum.TeamBeta and "TeamAlpha" or "TeamBeta"
    local other = side == "TeamAlpha" and "TeamBeta" or "TeamAlpha"
    if count[side] + quins > perTeam and count[other] + quins <= perTeam then
        side = other
    end
    return side
end

local function register(player, slots, anywhere, room) -- (anywhere: the debug quick match)
    refreshWindow()
    if type(slots) == "table" and slots.slots then -- ({ slots, room } from a terminal)
        room = slots.room
        slots = slots.slots
    end
    room = roomWish(room)
    if not windowKey or windowKind == "Booking" then
        return false, string.format("The desk opens %d minutes before each event. Prebook early at " .. PREBOOK_TERMINAL .. ".",
            math.floor(ArenaTiming.get("WalkInOpensBefore") / 60 + 0.5))
    end
    if not entryOpen() then
        return false, "Entry for " .. windowSlot.Name .. " has closed."
    end
    if not anywhere and not nearTerminal(player) then
        return false, "Register at " .. TERMINAL .. "."
    end
    if not anywhere then
        local mayUse, ahead = TerminalQueue.mayUse(player, "walkin")
        if not mayUse then
            return false, ahead and string.format("Wait your turn: %d ahead of you in line.", ahead) or "Join the line at the terminal."
        end
    end
    if player:GetAttribute("SpectateSeat") then -- (spectate the event or take part, not both)
        return false, "You hold a seat this round. Register when it ends."
    end
    local existing = entries[player.UserId]
    if existing and existing.prebook then
        return false, "You're prebooked for " .. windowSlot.Name .. ". Change it at " .. PREBOOK_TERMINAL .. "."
    end
    local chosen = chooseSlots(player, slots)
    if #chosen == 0 then
        return false, "Pick one of your Quins."
    end
    if (Payouts.balance(player) or 0) < Payouts.ENTRY_FEE then
        return false, string.format("Entry is %d SC per Quin each round. You have %d SC.", Payouts.ENTRY_FEE, Payouts.balance(player) or 0)
    end
    if existing then
        existing.slots = chosen -- (changing your Quins keeps your place in the queue)
        existing.room = room
    else
        entries[player.UserId] = { player = player, slots = chosen, registeredAt = os.clock(), satOut = 0, room = room,
            side = walkInSide(player, #chosen) }
    end
    makeRoomForPlayers()
    publish()
    local side = entries[player.UserId].side
    return true, string.format("Entered %s with %d Quin%s%s. Entry %d SC per Quin, paid each round they fight.",
        windowSlot.Name, #chosen, #chosen > 1 and "s" or "", side and (" on " .. (side == "TeamAlpha" and "Alpha" or "Beta")) or "", Payouts.ENTRY_FEE)
end

-- Each side's strength so far: players' Quins (prebooked, and walk-ins: they get a side when they
-- register) and NPC prebooks' (NPC walk-ins get theirs at seating)
function sideStrength(except)
    local sum, count = { TeamAlpha = 0, TeamBeta = 0 }, { TeamAlpha = 0, TeamBeta = 0 }
    for userId, e in pairs(entries) do
        if e.side and userId ~= except then
            for _, s in ipairs(e.slots) do
                local q = QuinRosterService.getQuinInSlot(e.player, s)
                if q then
                    sum[e.side] += strength(q)
                    count[e.side] += 1
                end
            end
        end
    end
    for _, ne in ipairs(npcEntries) do
        if ne.prebook and ne.side then
            for _, q in ipairs(ne.npc.quins) do
                sum[ne.side] += strength(q)
                count[ne.side] += 1
            end
        end
    end
    return sum, count
end

local function prebook(player, request)
    refreshWindow()
    request = type(request) == "table" and request or {}
    if not prebookOpen() then
        return false, windowKind == "Live" and (windowSlot.Name .. " has started: the boards open again when it ends. Walk in at " .. TERMINAL .. ".")
            or "Prebooking is closed."
    end
    if not nearPrebookTerminal(player) then
        return false, "Prebook at " .. PREBOOK_TERMINAL .. "."
    end
    local mayUse, ahead = TerminalQueue.mayUse(player, "prebook")
    if not mayUse then
        return false, ahead and string.format("Wait your turn: %d ahead of you in line.", ahead) or "Join the line at the terminal."
    end
    local side = request.side
    if side ~= "TeamAlpha" and side ~= "TeamBeta" then
        return false, "Pick a side."
    end
    local room = roomWish(request.room)
    if room then -- (a prebook claims its room on that side)
        for userId, e in pairs(entries) do
            if userId ~= player.UserId and e.prebook and e.side == side and e.room == room then
                return false, string.format("Room %d on %s is booked. Pick another room.", room, side == "TeamAlpha" and "Alpha" or "Beta")
            end
        end
    end
    local existing = entries[player.UserId]
    if existing and existing.prebook then
        return false, "You're already prebooked. Cancel first to change it."
    end
    local chosen = chooseSlots(player, request.slots)
    if #chosen == 0 then
        return false, "Pick one of your Quins."
    end
    for _, s in ipairs(chosen) do
        local q = QuinRosterService.getQuinInSlot(player, s)
        if QuinCare.isBusy(q) and q.Busy.Until > windowSlot.StartsAt then
            return false, string.format("Quin #%s is busy until after the event starts.", q.QuinId:sub(3, 6))
        end
    end
    -- the side guard: a side well ahead takes only Quins below its average
    local sum, count = sideStrength(player.UserId)
    local other = side == "TeamAlpha" and "TeamBeta" or "TeamAlpha"
    local mine = 0
    for _, s in ipairs(chosen) do
        mine += strength(QuinRosterService.getQuinInSlot(player, s))
    end
    local average = count[side] > 0 and sum[side] / count[side] or 0
    local oneQuin = count[side] + count[other] > 0 and (sum[side] + sum[other]) / (count[side] + count[other]) or 55
    -- (ahead before this booking, with one owner's booking of leeway)
    local ahead = sum[side] > sum[other] * GUARD_AHEAD + oneQuin * ArenaSchedule.perPlayer(windowSlot)
    if ahead and mine / #chosen >= average then
        return false, string.format("%s is well ahead already. Book %s instead, or wait for it to even out.",
            side == "TeamAlpha" and "Alpha" or "Beta", other == "TeamAlpha" and "Alpha" or "Beta")
    end
    -- the deposit: one round per Quin at today's price
    local rate = prebookRate()
    local credit = {}
    for i, s in ipairs(chosen) do
        local tag = QuinRosterService.getQuinInSlot(player, s).QuinId:sub(3, 6)
        local ok, why = Payouts.chargeEntry(player, tag, rate, "Prebook deposit")
        if not ok then
            for paidSlot, amount in pairs(credit) do
                Payouts.refund(player, amount, "Prebook deposit back")
                credit[paidSlot] = nil
            end
            return false, tostring(why)
        end
        credit[s] = rate
    end
    entries[player.UserId] = {
        player = player, slots = chosen, registeredAt = os.clock(), satOut = existing and existing.satOut or 0,
        prebook = true, side = side, rate = rate, credit = credit, room = room,
    }
    makeRoomForPlayers()
    publish()
    return true, string.format("Prebooked %s for %s with %d Quin%s at %d SC a round (%d%% off). Deposit %d SC paid.",
        side == "TeamAlpha" and "Alpha" or "Beta", windowSlot.Name, #chosen, #chosen > 1 and "s" or "", rate,
        math.floor((1 - rate / Payouts.ENTRY_FEE) * 100 + 0.5), rate * #chosen)
end

-- Entered and at a terminal: off to your side's prep rooms now, outside the room you wished for
-- (or Room 1). The rooms open when the round starts; you're put inside then.
local function goToPrep(player)
    refreshWindow()
    local e = entries[player.UserId]
    if not e or not windowKey or windowKind == "Booking" then
        return false, "You're not entered in an event that's on soon."
    end
    if not nearTerminal(player) then
        return false, "Ask at " .. TERMINAL .. "."
    end
    local PrepRoom = require(ServerScriptService:WaitForChild("ArenaPrepRoom"))
    local side = PrepRoom.sideOf(e.side or "TeamAlpha")
    local wish = e.room or 1
    local best = nil
    for _, room in ipairs(PrepRoom.rooms()) do
        if room.side == side and (not best or math.abs(room.number - wish) < math.abs(best.number - wish)) then
            best = room
        end
    end
    local root = rootOf(player)
    if not best or not root then
        return false, "The prep rooms aren't ready."
    end
    local spot = best.doorHall + Vector3.new(0, 4, 0)
    player.Character:PivotTo(CFrame.lookAt(spot, Vector3.new(best.door.Position.X, spot.Y, best.door.Position.Z)))
    root.AssemblyLinearVelocity = Vector3.zero
    return true, string.format("Room %d", best.number)
end

-- Leaving an event: a prebook keeps CANCEL_KEEP of its unused deposit
local function withdraw(player)
    local e = entries[player.UserId]
    if not e then
        return true, "Withdrawn"
    end
    local unused = unusedCredit(e)
    local back = math.floor(unused * (1 - CANCEL_KEEP))
    if back > 0 then
        Payouts.refund(player, back, "Prebook cancelled")
    end
    entries[player.UserId] = nil
    clearPlayer(player)
    publish()
    if e.prebook then
        return true, unused > 0 and string.format("Prebook cancelled: %d SC of your %d SC deposit back.", back, unused) or "Prebook cancelled."
    end
    return true, "Withdrawn"
end

-- What the boards show: each side's owners and their Quins (never their plans)
-- The rooms prebooks have claimed, per side ([n] = true), except `except`'s own
local function takenRooms(except)
    local taken = { TeamAlpha = {}, TeamBeta = {} }
    for userId, e in pairs(entries) do
        if e.prebook and e.side and e.room and userId ~= except then
            taken[e.side][tostring(e.room)] = true
        end
    end
    return taken
end

local function boardView(player)
    refreshWindow()
    local sides = { TeamAlpha = {}, TeamBeta = {} }
    local sum = { TeamAlpha = 0, TeamBeta = 0 }
    local walkIns = 0
    local function addQuin(owner, side, q)
        local record = q.BattleRecord or {}
        local revealed = {}
        for _, h in ipairs(QuinCare.knownHabits(q)) do
            table.insert(revealed, h.Name .. " " .. h.Band)
        end
        sum[side] += strength(q)
        table.insert(owner.Quins, {
            Tag = q.QuinId:sub(3, 6),
            Temperament = Temperament.displayName(q.Temperament or ""),
            Wins = record.Wins or 0,
            Losses = record.Losses or 0,
            Condition = band(QuinCare.condition(q), 50, 80, { "Battered", "Worn", "Fresh" }),
            Bond = band(q.Bond or 0, 30, 70, { "New", "Close", "Bonded" }),
            Revealed = revealed,
        })
    end
    for _, e in ipairs(ordered()) do
        if e.prebook and e.side then
            local owner = { Name = e.player.DisplayName, Quins = {} }
            for _, s in ipairs(e.slots) do
                local q = QuinRosterService.getQuinInSlot(e.player, s)
                if q then
                    addQuin(owner, e.side, q)
                end
            end
            table.insert(sides[e.side], owner)
        else
            walkIns += 1
        end
    end
    for _, ne in ipairs(npcEntries) do
        if ne.prebook and ne.side then
            local owner = { Name = ne.npc.name, Quins = {} }
            for _, q in ipairs(ne.npc.quins) do
                addQuin(owner, ne.side, q)
            end
            table.insert(sides[ne.side], owner)
        else
            walkIns += 1
        end
    end
    return {
        Event = windowSlot and windowSlot.Name or nil,
        Open = prebookOpen(),
        Live = windowKind == "Live",
        StartsAt = windowSlot and windowSlot.StartsAt or nil,
        OpensAt = windowSlot and windowSlot.PrebookOpensAt or nil,
        Rate = prebookRate(),
        Fee = Payouts.ENTRY_FEE,
        PerPlayer = ArenaSchedule.perPlayer(windowSlot),
        Alpha = sides.TeamAlpha,
        Beta = sides.TeamBeta,
        Strength = { Alpha = math.floor(sum.TeamAlpha), Beta = math.floor(sum.TeamBeta) },
        WalkIns = walkIns,
        TakenRooms = takenRooms(player and player.UserId),
    }
end

local ArenaNetwork = ReplicatedStorage:FindFirstChild("ArenaNetwork")
if not ArenaNetwork then
    ArenaNetwork = Instance.new("Folder")
    ArenaNetwork.Name = "ArenaNetwork"
    ArenaNetwork.Parent = ReplicatedStorage
end
local entryRemote = ArenaNetwork:FindFirstChild("ArenaEntry")
if not entryRemote then
    entryRemote = Instance.new("RemoteFunction")
    entryRemote.Name = "ArenaEntry"
    entryRemote.Parent = ArenaNetwork
end

-- QUICK MATCH (debug, the ARENA MENU): a 16v16 round now, with your Quins in it, from any role and
-- anywhere
local function isTeamBattle(slot)
    local m = slot and slot.Match
    return m ~= nil and m.Mode == "TeamBattle" and m.TeamSize == 16
end

local function quickMatch(player, slots)
    if not (RunService:IsStudio() or player:GetAttribute("SkylarkCanAdmin") == true) then
        return false, "Quick match is a debug tool."
    end
    local orch, schedule = shared.ArenaOrchestrator, shared.SkylarkSchedule
    if not orch or not schedule then
        return false, "The arena isn't ready."
    end
    if orch.getPhase() ~= "IDLE" then
        return false, "A match is on. Wait for it to end."
    end
    local slot = ArenaSchedule.slotAt(SkylarkTime.now())
    if not isTeamBattle(slot) then -- (into the next Team Battles window, a minute after it opens)
        for _ = 1, 32 do
            slot = ArenaSchedule.nextSlot(slot)
            if isTeamBattle(slot) then
                break
            end
        end
        if not isTeamBattle(slot) then
            return false, "No Team Battles on the schedule."
        end
        schedule.command("set", slot.StartsAt + 60)
    end
    refreshWindow()
    local existing = entries[player.UserId]
    if not (existing and existing.prebook) then
        if type(slots) ~= "table" or #slots == 0 then
            slots = existing and existing.slots or {}
            if #slots == 0 then
                for _, q in ipairs(rosterSummary(player)) do
                    table.insert(slots, q.Slot)
                end
            end
        end
        local ok, msg = register(player, slots, true, existing and existing.room)
        if not ok then
            return false, msg
        end
    end
    local settings = ArenaSchedule.matchFor(slot, 1)
    local started = orch.startMatch(settings, player)
    if not started then
        return false, "The match didn't start."
    end
    print(string.format("[ArenaRegistration] Quick match (debug) for %s: %s", player.Name, slot.Name))
    return true, "Quick match: " .. slot.Name .. ". Off to your preparation room."
end

entryRemote.OnServerInvoke = function(player, action, value)
    if action == "roster" then
        return rosterSummary(player)
    elseif action == "register" then
        return register(player, value)
    elseif action == "withdraw" or action == "cancel" then
        return withdraw(player)
    elseif action == "prebook" then
        return prebook(player, value)
    elseif action == "board" then
        return boardView(player)
    elseif action == "quick" then
        return quickMatch(player, value)
    elseif action == "goprep" then
        return goToPrep(player)
    end
    return false, "Unknown request"
end

Players.PlayerRemoving:Connect(function(player)
    local e = entries[player.UserId]
    if e then
        local unused = unusedCredit(e) -- (left before using it: it comes back, as if never seated)
        if unused > 0 then
            Payouts.refund(player, unused, "Prebook deposit back (left)")
        end
        entries[player.UserId] = nil
        publish()
    end
end)

-- ============================================================================
-- BE THERE: the arena's grounds
-- ============================================================================

local boundaryCentre, boundaryRadius = nil, nil
local function boundary()
    if not boundaryCentre then
        local ground = Workspace:FindFirstChild("ArenaGround", true)
        if ground and ground:IsA("BasePart") then
            boundaryCentre = ground.Position
            boundaryRadius = math.max(ground.Size.X, ground.Size.Z) / 2 + BOUNDARY_MARGIN
            Workspace:SetAttribute("ArenaBoundaryCentre", boundaryCentre)
            Workspace:SetAttribute("ArenaBoundaryRadius", boundaryRadius)
        end
    end
    return boundaryCentre, boundaryRadius
end

-- Inside the arena's grounds (no body right now, e.g. respawning: counted as inside)
function Registration.insideArena(player)
    local centre, radius = boundary()
    local root = rootOf(player)
    if not centre or not root then
        return true
    end
    local d = root.Position - centre
    return Vector3.new(d.X, 0, d.Z).Magnitude <= radius
end

-- Not there: the entry is gone (a prebook's unused deposit with it)
function Registration.dropAbsent(e, text)
    if entries[e.player.UserId] ~= e then
        return
    end
    entries[e.player.UserId] = nil
    clearPlayer(e.player)
    publish()
    notice(e.player, text)
    print(string.format("[ArenaRegistration] %s left %s's grounds: entry for %s dropped", e.player.Name, ARENA_NAME, windowSlot and windowSlot.Name or "?"))
end

task.spawn(function()
    while true do
        task.wait(1)
        boundary() -- (published for the DEBUG ring even before anyone registers)
        for _, e in pairs(entries) do
            local inside = Registration.insideArena(e.player)
            e.player:SetAttribute("ArenaOutside", (not inside) or nil)
            if not inside and windowKind == "Live" then
                e.outSince = e.outSince or os.clock()
                local left = LEAVE_GRACE - (os.clock() - e.outSince)
                if left <= 0 then
                    Registration.dropAbsent(e, string.format("You left %s while %s was on: your entry is gone.", ARENA_NAME, windowSlot and windowSlot.Name or "the event"))
                else
                    e.player:SetAttribute("ArenaLeaveIn", math.ceil(left))
                end
            else
                e.outSince = nil
                e.player:SetAttribute("ArenaLeaveIn", nil)
            end
        end
    end
end)

-- ============================================================================
-- NPC OWNERS IN THE QUEUE
-- ============================================================================

local function eventSeats(slot)
    local m = slot and slot.Match
    return m and seatsFor(m.Mode, m.TeamSize or 1) or 0
end

local function quinsIn()
    local n = 0
    for _, e in pairs(entries) do
        n += #e.slots
    end
    for _, ne in ipairs(npcEntries) do
        n += #ne.npc.quins
    end
    return n
end

-- The pool for an event: owners enough for its seats and a few more, each with an arrival time
-- (fromNow: switched on mid-event, so they arrive over the next minute)
buildNpcPool = function(slot, fromNow)
    npcEntries, npcPending = {}, {}
    local seats = eventSeats(slot)
    if seats == 0 or not ArenaNpcOwners.enabled() then
        return
    end
    local perPlayer = ArenaSchedule.perPlayer(slot)
    local m = ArenaTiming.markers(ArenaSchedule, slot)
    local quins = 0
    while quins < seats + NPC_SPARE do
        local npc = ArenaNpcOwners.newOwner(perPlayer)
        quins += #npc.quins
        local prebook = npcRng:NextNumber() < NPC_PREBOOK_SHARE
        local from, to
        if fromNow then
            from = SkylarkTime.now()
            to = from + 60 * math.max(SkylarkTime.rate(), 1)
        elseif prebook then
            from, to = m.PrebookOpens, math.max(m.PrebookOpens, slot.StartsAt - 60)
        else
            from, to = m.WalkInOpens, slot.StartsAt + 0.15 * (slot.EndsAt - slot.StartsAt)
        end
        table.insert(npcPending, { npc = npc, prebook = prebook, at = from + npcRng:NextNumber() * math.max(0, to - from) })
    end
    table.sort(npcPending, function(a, b)
        return a.at < b.at
    end)
end

-- A player in: if the event's seats are over-full, the newest NPC owners give up their places
-- (walk-ins before prebooks)
makeRoomForPlayers = function()
    local seats = eventSeats(windowSlot)
    if seats == 0 then
        return
    end
    for _, wantPrebook in ipairs({ false, true }) do
        for i = #npcEntries, 1, -1 do
            if quinsIn() <= seats then
                return
            end
            local ne = npcEntries[i]
            if (ne.prebook == true) == wantPrebook then
                table.remove(npcEntries, i)
                TerminalQueue.bump(ne.npc.name)
                print(string.format("[ArenaRegistration] %s gives up their place to a player", ne.npc.name))
            end
        end
    end
end

-- The prebooked Quins on a side (players' and NPC owners')
local function prebookedOn(side)
    local n = 0
    for _, e in pairs(entries) do
        if e.prebook and e.side == side then
            n += #e.slots
        end
    end
    for _, ne in ipairs(npcEntries) do
        if ne.prebook and ne.side == side then
            n += #ne.npc.quins
        end
    end
    return n
end

-- An NPC owner at the front of a line (or arriving late): registers if they still can.
-- "in" | "full" | "closed"
local npcPoolKey = nil -- (the event the pool is for: a served owner from an older one doesn't count)
local function registerNpc(p, kind, poolKey)
    if poolKey ~= npcPoolKey or not ArenaNpcOwners.enabled() then
        return "closed"
    end
    local seats = eventSeats(windowSlot)
    local perTeam = windowSlot and windowSlot.Match and windowSlot.Match.Mode == "TeamBattle" and (windowSlot.Match.TeamSize or 1) or seats
    if quinsIn() + #p.npc.quins > seats then
        return "full"
    end
    local now = SkylarkTime.now()
    if kind == "prebook" then
        if not prebookOpen() then
            return "closed"
        end
        -- a side by the board rule: the weaker one, if it has prebook places left
        local sum = sideStrength(nil)
        local side = sum.TeamAlpha <= sum.TeamBeta and "TeamAlpha" or "TeamBeta"
        local other = side == "TeamAlpha" and "TeamBeta" or "TeamAlpha"
        if prebookedOn(side) + #p.npc.quins > perTeam then
            side = other
        end
        if prebookedOn(side) + #p.npc.quins > perTeam then
            return "full"
        end
        table.insert(npcEntries, { npc = p.npc, prebook = true, side = side, registeredAt = now })
    else
        if not entryOpen() then
            return "closed"
        end
        table.insert(npcEntries, { npc = p.npc, prebook = false, registeredAt = now })
    end
    boardVersion += 1
    Workspace:SetAttribute("ArenaPrebookVersion", boardVersion) -- (the boards redraw)
    return "in"
end

npcTick = function()
    if not ArenaNpcOwners.enabled() then
        if #npcEntries > 0 or #npcPending > 0 then -- (switched off: they leave)
            npcEntries, npcPending = {}, {}
            TerminalQueue.clear()
            boardVersion += 1
            Workspace:SetAttribute("ArenaPrebookVersion", boardVersion)
        end
        Workspace:SetAttribute("ArenaNpcQueue", nil)
        return
    end
    if windowSlot and #npcEntries == 0 and #npcPending == 0 then -- (switched on again mid-event)
        buildNpcPool(windowSlot, true)
    end
    npcPoolKey = windowKey
    local now = SkylarkTime.now()
    local rate = math.max(SkylarkTime.rate(), 1)
    while npcPending[1] and npcPending[1].at <= now do
        local p = table.remove(npcPending, 1)
        -- which terminal: the prebook one while booking is open (if they meant to), else the desk
        local kind = (p.prebook and prebookOpen()) and "prebook" or (entryOpen() and "walkin" or nil)
        if kind then -- (else the desk is closed: they don't come)
            local late = (now - p.at) / rate > NPC_CATCHUP
            local key = windowKey
            if late or not TerminalQueue.available(kind)
                or not TerminalQueue.arrive(p.npc.name, kind, function()
                    return registerNpc(p, kind, key)
                end) then
                registerNpc(p, kind, key)
            end
        end
    end
    local prebooked, quins = 0, 0
    for _, ne in ipairs(npcEntries) do
        prebooked += ne.prebook and 1 or 0
        quins += #ne.npc.quins
    end
    Workspace:SetAttribute("ArenaNpcQueue", string.format("%d NPC owners entered (%d prebooked), %d Quins  •  %d arriving",
        #npcEntries, prebooked, quins, #npcPending))
end

task.spawn(function()
    while true do
        refreshWindow()
        npcTick()
        task.wait(0.5)
    end
end)

Registration.strength = strength -- (ArenaNpcOwners deals the arena's Quins by it)

Registration.queue = function()
    local out = {}
    for pos, e in ipairs(ordered()) do
        table.insert(out, { pos = pos, name = e.player.Name, slots = e.slots, satOut = e.satOut, prebook = e.prebook, side = e.side, rate = e.rate })
    end
    for _, ne in ipairs(npcEntries) do
        table.insert(out, { pos = #out + 1, name = ne.npc.name, npc = true, quins = #ne.npc.quins, prebook = ne.prebook, side = ne.side })
    end
    return out
end

return Registration
