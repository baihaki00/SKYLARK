--// ArenaRegistration.lua
-- Entering the arena's events with your own Quin, and the fair queue that seats the rounds.
--
--   * Registration is for an event WINDOW (ArenaSchedule): it opens one Skylark hour (20 real
--     minutes) before the window and lasts all window long. You register once; you stay in the
--     queue for every round of that window. When the window ends, the entries are cleared.
--   * One Quin per player per round (the roster slot you chose).
--   * Fair queue: at each round the seats go to the players who have sat out the most rounds,
--     then to who registered first. Seated: back to 0. Not seated: +1, so you are first next time.
--     Nobody waits more than one round while the queue is shorter than the seats.
--   * Empty seats are filled by the arena's own Quins (NPQs), so a round never waits for players.
--
-- The Arena System Orchestrator calls pickRound when the preparation room opens (the chosen Quins
-- "calibrate in the backrooms" there) and roundOver when the match ends.
--
-- State the clients read (no polling): Workspace ArenaRegOpen / ArenaRegWindow / ArenaRegKind
-- ("Live" / "Soon") / ArenaRegStartsAt / ArenaRegEndsAt / ArenaEntrants / ArenaRoundSeats;
-- each Player ArenaEntered / ArenaEntrySlot / ArenaQueuePos / ArenaSatOut / ArenaInRound.
-- Remote: ArenaNetwork.ArenaEntry (RemoteFunction) "roster" | "register", slot | "withdraw".

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local QuinCore = ReplicatedStorage:WaitForChild("QuinCore")
local SkylarkTime = require(QuinCore:WaitForChild("SkylarkTime"))
local ArenaSchedule = require(QuinCore:WaitForChild("ArenaSchedule"))
local QuinRosterService = require(ServerScriptService:WaitForChild("QuinRosterService"))

local Registration = {}

local OPENS_BEFORE = SkylarkTime.HOUR -- Skylark seconds before a window that entry opens

local entries = {} -- [userId] = { player, slot, registeredAt, satOut }
local windowKey = nil -- the event window the entries are for
local windowSlot = nil

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
        e.player:SetAttribute("ArenaEntered", true)
        e.player:SetAttribute("ArenaEntrySlot", e.slot)
        e.player:SetAttribute("ArenaQueuePos", pos)
        e.player:SetAttribute("ArenaSatOut", e.satOut)
    end
    Workspace:SetAttribute("ArenaEntrants", #list)
end

local function clearPlayer(player)
    player:SetAttribute("ArenaEntered", false)
    player:SetAttribute("ArenaEntrySlot", nil)
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

-- The window entry is open for: the event on now, or the next one if it opens soon
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
    Workspace:SetAttribute("ArenaRegOpen", slot ~= nil)
    Workspace:SetAttribute("ArenaRegWindow", slot and slot.Name or nil)
    Workspace:SetAttribute("ArenaRegKind", kind)
    Workspace:SetAttribute("ArenaRegStartsAt", slot and slot.StartsAt or nil)
    Workspace:SetAttribute("ArenaRegEndsAt", slot and slot.EndsAt or nil)
end

-- ============================================================================
-- ROUNDS (called by the Arena System Orchestrator)
-- ============================================================================

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

-- The players seated in this round: { player, quin, team } (team nil in FFA). Only while the
-- window the entries are for is live, so a test match before a window leaves the queue alone.
function Registration.pickRound(mode, teamSize)
    refreshWindow()
    local slot = ArenaSchedule.slotAt(SkylarkTime.now())
    local seats = seatsFor(mode, teamSize)
    Workspace:SetAttribute("ArenaRoundSeats", seats)
    if seats == 0 or not windowKey or slot.Key ~= windowKey or not next(entries) then
        return {}
    end
    local entrants = {}
    for _, e in ipairs(ordered()) do
        local quin = #entrants < seats and QuinRosterService.getQuinInSlot(e.player, e.slot)
        if quin then
            local team = nil
            if mode ~= "FFA" then
                team = (#entrants % 2 == 0) and "TeamAlpha" or "TeamBeta" -- (alternating: the sides stay even)
            end
            table.insert(entrants, { player = e.player, quin = quin, team = team })
            e.satOut = 0
            e.player:SetAttribute("ArenaInRound", true)
        else
            e.satOut += 1
        end
    end
    publish()
    print(string.format("[ArenaRegistration] %s: %d of %d seats to players, %d arena Quins fill the rest",
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
                QuinId = q.QuinId,
                Gender = q.Gender,
                Element = q.Element,
                Title = q.Titles and q.Titles.Current or nil,
                Wins = record.Wins or 0,
                Losses = record.Losses or 0,
            })
        end
    end
    return list
end

local function register(player, slot)
    refreshWindow()
    if not windowKey then
        return false, "Entry is closed: it opens 20 minutes before the next event."
    end
    slot = tonumber(slot)
    if not slot or not QuinRosterService.getQuinInSlot(player, slot) then
        return false, "Pick one of your Quins."
    end
    local existing = entries[player.UserId]
    if existing then
        existing.slot = slot -- (switching Quin keeps your place in the queue)
    else
        entries[player.UserId] = { player = player, slot = slot, registeredAt = os.clock(), satOut = 0 }
    end
    publish()
    return true, "Entered " .. tostring(windowSlot and windowSlot.Name)
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

-- (test hooks for Studio / the flow probe)
Registration.register = register
Registration.withdraw = withdraw
Registration.queue = function()
    local out = {}
    for pos, e in ipairs(ordered()) do
        table.insert(out, { pos = pos, name = e.player.Name, slot = e.slot, satOut = e.satOut })
    end
    return out
end

return Registration
