--// ArenaRegistration.lua
-- Entering the arena's events with your own Quins, at an Arena Terminal, and the fair queue that
-- seats the rounds.
--
--   * Walk up to an Arena Terminal (the Workspace parts named "ArenaTerminal"; each gets a
--     ProximityPrompt) and register for the event window: the one on now, or the next one in its
--     last 20 minutes before it opens. Entry closes 5 real minutes before the window ends.
--     You register once and stay in the queue for every round of that window; when the window
--     ends the entries are cleared.
--   * How many Quins: the window's PerPlayer (ArenaSchedule): 2 in the 16v16 battles, entered
--     together (same team), 1 otherwise.
--   * Fair queue: each round, the players who have sat out the most rounds go first, then who
--     registered first. Every player in that order gets their first Quin seated before anyone
--     gets a second. Seated: back to 0. Not seated: +1, so you are first next time.
--   * Empty seats are filled by the arena's own Quins (NPQs), so a round never waits for players.
--   * Entry fee: SkylarkPayouts.ENTRY_FEE per Quin, paid when it is seated for a round (not when
--     you register): a Quin you can't pay for sits that round out. The orchestrator pays out at
--     the winner and refunds a round stopped before it.
--
-- The Arena System Orchestrator calls pickRound when the preparation room opens (the Quins and
-- their owners go to the pads: ArenaPrepRoom) and roundOver when the match ends.
--
-- State the clients read: Workspace ArenaRegOpen / ArenaRegWindow / ArenaRegKind ("Live" /
-- "Soon") / ArenaRegStartsAt / ArenaRegEndsAt / ArenaRegClosesAt / ArenaRegPerPlayer /
-- ArenaEntrants / ArenaRoundSeats; each Player ArenaEntered / ArenaEntrySlots ("1,3") /
-- ArenaQueuePos / ArenaSatOut / ArenaInRound.
-- Remote: ArenaNetwork.ArenaEntry (RemoteFunction) "roster" | "register", {slots} | "withdraw".

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local QuinCore = ReplicatedStorage:WaitForChild("QuinCore")
local SkylarkTime = require(QuinCore:WaitForChild("SkylarkTime"))
local ArenaSchedule = require(QuinCore:WaitForChild("ArenaSchedule"))
local QuinRosterService = require(ServerScriptService:WaitForChild("QuinRosterService"))
local Payouts = require(ServerScriptService:WaitForChild("SkylarkPayouts"))
local QuinCare = require(ServerScriptService:WaitForChild("QuinCare"))

local Registration = {}

local OPENS_BEFORE = SkylarkTime.HOUR -- Skylark seconds before a window that entry opens (20 real min)
local CLOSES_BEFORE_END = 5 * 60 -- real seconds before the window ends that entry closes
local TERMINAL_RANGE = 16 -- studs: register only at a terminal

local entries = {} -- [userId] = { player, slots = {..}, registeredAt, satOut }
local windowKey = nil -- the event window the entries are for
local windowSlot = nil

-- ============================================================================
-- ARENA TERMINALS
-- ============================================================================

local function terminals()
    local list = {}
    for _, part in ipairs(Workspace:GetDescendants()) do
        if part.Name == "ArenaTerminal" and part:IsA("BasePart") then
            table.insert(list, part)
        end
    end
    return list
end

for _, terminal in ipairs(terminals()) do
    terminal.Anchored = true -- (they were loose parts and could be knocked over)
    if not terminal:FindFirstChild("ArenaTerminalPrompt") then
        local prompt = Instance.new("ProximityPrompt")
        prompt.Name = "ArenaTerminalPrompt"
        prompt.ActionText = "Register Quins"
        prompt.ObjectText = "Arena Terminal"
        prompt.HoldDuration = 0
        prompt.MaxActivationDistance = 12
        prompt.RequiresLineOfSight = false
        prompt.Parent = terminal
    end
end

local function nearTerminal(player)
    local character = player.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
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

-- ============================================================================
-- QUEUE
-- ============================================================================

local function ordered()
    local list = {}
    for _, e in pairs(entries) do
        table.insert(list, e)
    end
    table.sort(list, function(a, b)
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
    end
    Workspace:SetAttribute("ArenaEntrants", #list)
end

local function clearPlayer(player)
    player:SetAttribute("ArenaEntered", false)
    player:SetAttribute("ArenaEntrySlots", nil)
    player:SetAttribute("ArenaQueuePos", nil)
    player:SetAttribute("ArenaSatOut", nil)
end

local function clearAll()
    for _, e in pairs(entries) do
        clearPlayer(e.player)
    end
    entries = {}
    publish()
end

-- The window entry is for: the event on now, or the next one if it opens soon
local function targetWindow()
    local t = SkylarkTime.now()
    local slot = ArenaSchedule.slotAt(t)
    if slot.Kind == "Event" then
        return slot, "Live"
    end
    local nextEvent = ArenaSchedule.nextEvent(t)
    if nextEvent and nextEvent.StartsAt - t <= OPENS_BEFORE then
        return nextEvent, "Soon"
    end
    return nil
end

-- Entry closes 5 real minutes before the window ends (never while the clock is paused)
local function closesAt(slot)
    return slot.EndsAt - CLOSES_BEFORE_END * math.max(SkylarkTime.rate(), 0)
end

local function entryOpen()
    return windowSlot ~= nil and SkylarkTime.now() < closesAt(windowSlot)
end

local function refreshWindow()
    local slot, kind = targetWindow()
    local key = slot and slot.Key
    if key ~= windowKey then
        if next(entries) then
            print(string.format("[ArenaRegistration] Window over: %d entries cleared", Workspace:GetAttribute("ArenaEntrants") or 0))
        end
        clearAll()
        windowKey = key
        windowSlot = slot
    end
    Workspace:SetAttribute("ArenaRegOpen", entryOpen())
    Workspace:SetAttribute("ArenaRegWindow", slot and slot.Name or nil)
    Workspace:SetAttribute("ArenaRegKind", kind)
    Workspace:SetAttribute("ArenaRegStartsAt", slot and slot.StartsAt or nil)
    Workspace:SetAttribute("ArenaRegEndsAt", slot and slot.EndsAt or nil)
    Workspace:SetAttribute("ArenaRegClosesAt", slot and closesAt(slot) or nil)
    Workspace:SetAttribute("ArenaRegPerPlayer", ArenaSchedule.perPlayer(slot))
end

-- ============================================================================
-- ROUNDS (called by the Arena System Orchestrator)
-- ============================================================================

local function ArenaNetworkFolder()
    return ReplicatedStorage:FindFirstChild("ArenaNetwork") or ReplicatedStorage
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

-- The Quins seated in this round: { player, quin, team } each (team nil in FFA); a player's
-- Quins are on the same side. Only while the window the entries are for is live, so a test match
-- before a window leaves the queue alone.
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
            team = sideOf[e]
            if not team then -- (the side with fewer seated Quins; the owner's next Quin joins it)
                team = teamCount.TeamAlpha <= teamCount.TeamBeta and "TeamAlpha" or "TeamBeta"
            end
            if teamCount[team] >= perTeam then
                return false
            end
        end
        local tag = quin.QuinId and quin.QuinId:sub(3, 6) or "?"
        if QuinCare.isBusy(quin) then -- (in the Workshop or training: it sits this round out, free)
            local notice = ArenaNetworkFolder():FindFirstChild("PrepRoom")
            if notice then
                notice:FireClient(e.player, "notice", string.format("Quin #%s sits this round out: busy (%s).", tag, quin.Busy.Kind))
            end
            return false
        end
        local paid, why = Payouts.chargeEntry(e.player, tag)
        if not paid then
            local notice = ArenaNetworkFolder():FindFirstChild("PrepRoom")
            if notice then
                notice:FireClient(e.player, "notice", string.format("Quin #%s sits this round out: %s", tag, tostring(why)))
            end
            return false
        end
        if team then
            sideOf[e] = team
            teamCount[team] += 1
        end
        table.insert(entrants, { player = e.player, quin = quin, team = team, paid = Payouts.ENTRY_FEE })
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

local function register(player, slots)
    refreshWindow()
    if not windowKey then
        return false, "No event open: entry opens 20 minutes before each event."
    end
    if not entryOpen() then
        return false, "Entry for " .. windowSlot.Name .. " has closed."
    end
    if not nearTerminal(player) then
        return false, "Register at an Arena Terminal."
    end
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
    if #chosen == 0 then
        return false, "Pick one of your Quins."
    end
    if (Payouts.balance(player) or 0) < Payouts.ENTRY_FEE then
        return false, string.format("Entry is %d SC per Quin each round. You have %d SC.", Payouts.ENTRY_FEE, Payouts.balance(player) or 0)
    end
    local existing = entries[player.UserId]
    if existing then
        existing.slots = chosen -- (changing your Quins keeps your place in the queue)
    else
        entries[player.UserId] = { player = player, slots = chosen, registeredAt = os.clock(), satOut = 0 }
    end
    publish()
    return true, string.format("Entered %s with %d Quin%s. Entry %d SC per Quin, paid each round they fight.",
        windowSlot.Name, #chosen, #chosen > 1 and "s" or "", Payouts.ENTRY_FEE)
end

local function withdraw(player)
    if entries[player.UserId] then
        entries[player.UserId] = nil
        clearPlayer(player)
        publish()
    end
    return true, "Withdrawn"
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

entryRemote.OnServerInvoke = function(player, action, value)
    if action == "roster" then
        return rosterSummary(player)
    elseif action == "register" then
        return register(player, value)
    elseif action == "withdraw" then
        return withdraw(player)
    end
    return false, "Unknown request"
end

Players.PlayerRemoving:Connect(function(player)
    if entries[player.UserId] then
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
        table.insert(out, { pos = pos, name = e.player.Name, slots = e.slots, satOut = e.satOut })
    end
    return out
end

return Registration
