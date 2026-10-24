--// ArenaRegistration.lua
-- Getting your own Quins into the arena's events, and the fair queue that seats the rounds.
-- Two ways in (owner, 2026-10-24), both for the whole event window (all its rounds):
--
--   * PREBOOK at an Arena Prebook Terminal (the Workspace parts named "ArenaPrebookTerminal", by
--     the Arena Boards around Argonia; each gets a "Prebook Quins" ProximityPrompt). The boards
--     ("ArenaBoard") only show who is booked (ArenaBoardClient). Open from the end of the event
--     before until this event starts.
--     Booking early is cheaper: up to PREBOOK_DISCOUNT off, sliding to full price at the start;
--     the price you booked at holds for every round of the event. You pick your side (the side
--     guard can turn a strong Quin away from a side that is already well ahead). A deposit of one
--     round per Quin is paid at booking and counts as that Quin's first round; a deposit never
--     used comes back in full when the event ends. Cancelling keeps CANCEL_KEEP of what is unused.
--     Prebooked Quins are seated before walk-ins, on their side.
--   * WALK-IN at an Arena Terminal (an arena worker at the venue, "Register Quins"): the event on
--     now, or the next one in its last 20 minutes before it opens, until 5 real minutes before
--     the window ends. Full price, paid each round a Quin is seated; the side is wherever there
--     is room.
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
-- ArenaSatOut / ArenaInRound / ArenaPrebooked / ArenaPrebookSide.
-- Remote: ArenaNetwork.ArenaEntry (RemoteFunction) "roster" | "register", {slots} | "withdraw" |
-- "prebook", { slots = {..}, side = "TeamAlpha" | "TeamBeta" } | "cancel" | "board" |
-- "quick" (DEBUG, Studio or admins: QUICK MATCH on the terminal, F8 shows it. Moves the clock
-- into the next 16v16 Team Battles window if it isn't in one, enters your Quins and starts a round now).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local QuinCore = ReplicatedStorage:WaitForChild("QuinCore")
local SkylarkTime = require(QuinCore:WaitForChild("SkylarkTime"))
local ArenaSchedule = require(QuinCore:WaitForChild("ArenaSchedule"))
local Temperament = require(QuinCore.Modules:WaitForChild("Temperament"))
local QuinRosterService = require(ServerScriptService:WaitForChild("QuinRosterService"))
local Payouts = require(ServerScriptService:WaitForChild("SkylarkPayouts"))
local QuinCare = require(ServerScriptService:WaitForChild("QuinCare"))

local Registration = {}

local OPENS_BEFORE = SkylarkTime.HOUR -- Skylark seconds before a window that the walk-in desk opens (20 real min)
local CLOSES_BEFORE_END = 5 * 60 -- real seconds before the window ends that the walk-in desk closes
local TERMINAL_RANGE = 16 -- studs: walk in only at a terminal
local PREBOOK_RANGE = 16 -- studs: prebook only at a prebook terminal
local PREBOOK_DISCOUNT = 0.30 -- off the entry when booking the moment the boards open
local CANCEL_KEEP = 0.25 -- of an unused deposit, kept when a prebook is cancelled
local GUARD_AHEAD = 1.15 -- a side this much stronger than the other (plus one owner's booking) is "ahead"

local entries = {} -- [userId] = { player, slots, registeredAt, satOut, prebook?, side?, rate?, credit = { [slot] = SC } }
local windowKey = nil -- the event the entries are for
local windowSlot = nil
local windowKind = nil -- "Live" | "Soon" (walk-in desk open) | "Booking" (boards only)
local boardVersion = 0

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
    return math.floor(Payouts.ENTRY_FEE * (1 - PREBOOK_DISCOUNT * early) + 0.5)
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
        e.player:SetAttribute("ArenaPrebookSide", e.side)
    end
    Workspace:SetAttribute("ArenaEntrants", #list)
    boardVersion += 1
    Workspace:SetAttribute("ArenaPrebookVersion", boardVersion) -- (the boards redraw)
end

local function clearPlayer(player)
    player:SetAttribute("ArenaEntered", false)
    player:SetAttribute("ArenaEntrySlots", nil)
    player:SetAttribute("ArenaQueuePos", nil)
    player:SetAttribute("ArenaSatOut", nil)
    player:SetAttribute("ArenaPrebooked", nil)
    player:SetAttribute("ArenaPrebookSide", nil)
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
    publish()
end

-- The event entries are for: the one on now, else the next one (boards; the walk-in desk too in
-- its last 20 minutes)
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
    return nextEvent, nextEvent.StartsAt - t <= OPENS_BEFORE and "Soon" or "Booking"
end

-- The walk-in desk closes 5 real minutes before the window ends (never while the clock is paused)
local function closesAt(slot)
    return slot.EndsAt - CLOSES_BEFORE_END * math.max(SkylarkTime.rate(), 0)
end

local function entryOpen()
    return windowSlot ~= nil and windowKind ~= "Booking" and SkylarkTime.now() < closesAt(windowSlot)
end

local function prebookOpen()
    return windowSlot ~= nil and windowKind ~= "Live" and SkylarkTime.now() < windowSlot.StartsAt
end

-- When the boards opened for this event: the end of the event before it
local function prebookOpensAt(slot)
    local t = slot.StartsAt - 1
    for _ = 1, #ArenaSchedule.DAILY do
        local before = ArenaSchedule.slotAt(t)
        if before.Kind == "Event" then
            return before.EndsAt
        end
        t = before.StartsAt - 1
    end
    return slot.StartsAt - OPENS_BEFORE
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
        end
    end
    windowKind = kind
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
    if seats == 0 or not windowKey or slot.Key ~= windowKey or not next(entries) then
        return {}
    end
    local perTeam = mode == "FFA" and seats or (mode == "1vs1" and 1 or teamSize)
    local perPlayer = ArenaSchedule.perPlayer(windowSlot)
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
        table.insert(entrants, { player = e.player, quin = quin, team = team, paid = price })
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
    publish()
    print(string.format("[ArenaRegistration] %s: %d of %d seats to players' Quins, %d arena Quins fill the rest",
        windowSlot and windowSlot.Name or "Round", #entrants, seats, seats - #entrants))
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

local function register(player, slots)
    refreshWindow()
    if not windowKey or windowKind == "Booking" then
        return false, "The desk opens 20 minutes before each event. Prebook early at an Arena Prebook Terminal."
    end
    if not entryOpen() then
        return false, "Entry for " .. windowSlot.Name .. " has closed."
    end
    if not nearTerminal(player) then
        return false, "Register at an Arena Terminal."
    end
    if player:GetAttribute("SpectateSeat") then -- (spectate the event or take part, not both)
        return false, "You hold a seat this round. Register when it ends."
    end
    local existing = entries[player.UserId]
    if existing and existing.prebook then
        return false, "You're prebooked for " .. windowSlot.Name .. ". Change it at an Arena Prebook Terminal."
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
    else
        entries[player.UserId] = { player = player, slots = chosen, registeredAt = os.clock(), satOut = 0 }
    end
    publish()
    return true, string.format("Entered %s with %d Quin%s. Entry %d SC per Quin, paid each round they fight.",
        windowSlot.Name, #chosen, #chosen > 1 and "s" or "", Payouts.ENTRY_FEE)
end

-- Each side's prebooked strength (walk-ins have no side until they are seated)
local function sideStrength(except)
    local sum, count = { TeamAlpha = 0, TeamBeta = 0 }, { TeamAlpha = 0, TeamBeta = 0 }
    for userId, e in pairs(entries) do
        if e.prebook and e.side and userId ~= except then
            for _, s in ipairs(e.slots) do
                local q = QuinRosterService.getQuinInSlot(e.player, s)
                if q then
                    sum[e.side] += strength(q)
                    count[e.side] += 1
                end
            end
        end
    end
    return sum, count
end

local function prebook(player, request)
    refreshWindow()
    request = type(request) == "table" and request or {}
    if not prebookOpen() then
        return false, windowKind == "Live" and (windowSlot.Name .. " has started: the boards open again when it ends. Walk in at an Arena Terminal.")
            or "Prebooking is closed."
    end
    if not nearPrebookTerminal(player) then
        return false, "Prebook at an Arena Prebook Terminal."
    end
    local side = request.side
    if side ~= "TeamAlpha" and side ~= "TeamBeta" then
        return false, "Pick a side."
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
        prebook = true, side = side, rate = rate, credit = credit,
    }
    publish()
    return true, string.format("Prebooked %s for %s with %d Quin%s at %d SC a round (%d%% off). Deposit %d SC paid.",
        side == "TeamAlpha" and "Alpha" or "Beta", windowSlot.Name, #chosen, #chosen > 1 and "s" or "", rate,
        math.floor((1 - rate / Payouts.ENTRY_FEE) * 100 + 0.5), rate * #chosen)
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
local function boardView()
    refreshWindow()
    local sides = { TeamAlpha = {}, TeamBeta = {} }
    local sum = { TeamAlpha = 0, TeamBeta = 0 }
    local walkIns = 0
    for _, e in ipairs(ordered()) do
        if e.prebook and e.side then
            local owner = { Name = e.player.DisplayName, Quins = {} }
            for _, s in ipairs(e.slots) do
                local q = QuinRosterService.getQuinInSlot(e.player, s)
                if q then
                    local record = q.BattleRecord or {}
                    local revealed = {}
                    for _, h in ipairs(QuinCare.knownHabits(q)) do
                        table.insert(revealed, h.Name .. " " .. h.Band)
                    end
                    sum[e.side] += strength(q)
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
            end
            table.insert(sides[e.side], owner)
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

-- QUICK MATCH (debug): a 16v16 round now, with your Quins in it, from any role
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
    if not nearTerminal(player) then
        return false, "Use an Arena Terminal."
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
        local ok, msg = register(player, slots)
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
        return boardView()
    elseif action == "quick" then
        return quickMatch(player, value)
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

task.spawn(function()
    while true do
        refreshWindow()
        task.wait(0.5)
    end
end)

Registration.queue = function()
    local out = {}
    for pos, e in ipairs(ordered()) do
        table.insert(out, { pos = pos, name = e.player.Name, slots = e.slots, satOut = e.satOut, prebook = e.prebook, side = e.side, rate = e.rate })
    end
    return out
end

return Registration
