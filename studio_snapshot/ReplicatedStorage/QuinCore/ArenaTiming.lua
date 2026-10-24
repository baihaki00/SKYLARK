--// ArenaTiming.lua
-- The timing of an event block, in one place: when prebooking and the walk-in desk open and close,
-- when the last round may start, and how long each round's phases last. Read by ArenaRegistration
-- (the desk, the boards), SkylarkScheduleService (auto rounds), ArenaSchedule.matchFor (a round's
-- phase durations), and the ARENA MENU [DEBUG] (ArenaBlockMenu.client), which changes them live.
--
-- Times are clock seconds: real seconds at 1x (1 SST hour = 1200).
-- A value changed in the menu is a Workspace attribute "ArenaTiming_<Key>", so every script and
-- every client sees it at once; it lasts for the session only (Play stops, the defaults are back).
-- Bake a value in by changing DEFAULTS (the menu's PRINT VALUES writes them to the output).
--
--   ArenaTiming.get(key) / ArenaTiming.set(key, value)  (set: server; nil = back to the default)
--   ArenaTiming.durations()        -> phase durations for a scheduled round (FastRounds aware)
--   ArenaTiming.roundLength()      -> the longest a round can take (every phase in full)
--   ArenaTiming.markers(schedule, slot) -> { PrebookOpens, WalkInOpens, Start, LastRound,
--                                          WalkInCloses, End } clock times for that event block
--   ArenaTiming.lastRoundAt(slot) / walkInClosesAt(slot) / prebookOpensAt(schedule, slot)

local Workspace = game:GetService("Workspace")

local QuinCore = script.Parent
local SkylarkTime = require(QuinCore:WaitForChild("SkylarkTime"))
local ArenaConfig = require(QuinCore:WaitForChild("ArenaConfig"))

local ArenaTiming = {}

ArenaTiming.DEFAULTS = {
    WalkInOpensBefore = 1200, -- the walk-in desk opens this long before the event starts (20 min)
    WalkInCloseRule = "BeforeEnd", -- "BeforeEnd": WalkInClosesBeforeEnd before the block ends;
    --                                "LastRound": when no new round can start in the block
    WalkInClosesBeforeEnd = 300, -- (5 min)
    PrebookDiscount = 0.30, -- off one round's entry when booking the moment the boards open
    RoundGap = 15, -- between the end of one round and the next
    FastRounds = false, -- every round about 1.5 min (FAST below), to watch a whole block quickly
    PreparationRoom = 60, -- a scheduled round's phases (the rest: ArenaConfig.DefaultDurations)
    StadiumAnthem = 60,
    PostGame = 180,
    GameTime = 600, -- the longest a fight may run
}

-- Fast rounds: every phase short, the fight capped at a minute
ArenaTiming.FAST = {
    ArenaOpen = 2,
    ArenaGeneration = 5,
    PreparationRoom = 10,
    TeleportingQuins = 3,
    StadiumAnthem = 5,
    PreGame = 3,
    GameTime = 60,
    WinnerDetermination = 3,
    PostGame = 10,
}

local PHASE_KEYS = { "PreparationRoom", "StadiumAnthem", "PostGame", "GameTime" }

local PREFIX = "ArenaTiming_"

function ArenaTiming.get(key)
    local v = Workspace:GetAttribute(PREFIX .. key)
    if v == nil then
        return ArenaTiming.DEFAULTS[key]
    end
    return v
end

function ArenaTiming.set(key, value)
    if ArenaTiming.DEFAULTS[key] == nil then
        return false
    end
    if value == ArenaTiming.DEFAULTS[key] then
        value = nil
    end
    Workspace:SetAttribute(PREFIX .. key, value)
    return true
end

function ArenaTiming.reset()
    for key in pairs(ArenaTiming.DEFAULTS) do
        Workspace:SetAttribute(PREFIX .. key, nil)
    end
end

-- The phase durations a scheduled (or quick) round runs with
function ArenaTiming.durations()
    if ArenaTiming.get("FastRounds") then
        return table.clone(ArenaTiming.FAST)
    end
    local d = table.clone(ArenaConfig.DefaultDurations)
    for _, key in ipairs(PHASE_KEYS) do
        d[key] = ArenaTiming.get(key)
    end
    return d
end

function ArenaTiming.roundLength()
    local total = 0
    for _, seconds in pairs(ArenaTiming.durations()) do
        total += seconds
    end
    return total
end

-- Clock seconds per real second for "real" margins (a paused clock counts as 1x)
local function scale()
    local rate = SkylarkTime.rate()
    return rate > 0 and rate or 1
end

-- The last moment a new round may start: it must be able to finish inside the block
function ArenaTiming.lastRoundAt(slot)
    return slot.EndsAt - ArenaTiming.roundLength() * scale()
end

function ArenaTiming.walkInClosesAt(slot)
    if ArenaTiming.get("WalkInCloseRule") == "LastRound" then
        return ArenaTiming.lastRoundAt(slot)
    end
    return slot.EndsAt - ArenaTiming.get("WalkInClosesBeforeEnd") * scale()
end

-- The boards open for an event when the event before it ends
function ArenaTiming.prebookOpensAt(schedule, slot)
    local t = slot.StartsAt - 1
    for _ = 1, #schedule.DAILY do
        local before = schedule.slotAt(t)
        if before.Kind == "Event" then
            return before.EndsAt
        end
        t = before.StartsAt - 1
    end
    return slot.StartsAt - ArenaTiming.get("WalkInOpensBefore")
end

function ArenaTiming.markers(schedule, slot)
    return {
        PrebookOpens = ArenaTiming.prebookOpensAt(schedule, slot),
        WalkInOpens = slot.StartsAt - ArenaTiming.get("WalkInOpensBefore"),
        Start = slot.StartsAt,
        LastRound = ArenaTiming.lastRoundAt(slot),
        WalkInCloses = ArenaTiming.walkInClosesAt(slot),
        End = slot.EndsAt,
    }
end

-- The event block entries are for now: the one on, else the next one
function ArenaTiming.targetEvent(schedule, t)
    t = t or SkylarkTime.now()
    local slot = schedule.slotAt(t)
    if slot.Kind == "Event" then
        return slot
    end
    return schedule.nextEvent(t)
end

-- "12m 30s (11:00 SST)", or "at 11:00 SST (clock paused)"
function ArenaTiming.untilText(t)
    local at = SkylarkTime.formatHours(SkylarkTime.info(t).Hours) .. " SST"
    local real = SkylarkTime.realSecondsUntil(t)
    if not real then
        return "at " .. at .. " (clock paused)"
    end
    real = math.max(0, math.floor(real))
    -- a countdown ticks: seconds under an hour
    local text = (real < 3600 and real >= 60) and string.format("%dm %02ds", real // 60, real % 60) or SkylarkTime.formatDuration(real)
    return text .. " (" .. at .. ")"
end

-- What a player can do at an arena's terminals now, and when the rest opens (clients: the
-- terminal prompts and windows). `phase` is the round's (Workspace ArenaPhase).
--   { walkIn = { open, event, reason }, prebook = { open, event, reason },
--     spectate = { open, reason }, live = event on now or nil }
function ArenaTiming.describe(schedule, phase, t)
    t = t or SkylarkTime.now()
    local out = {}
    local target = ArenaTiming.targetEvent(schedule, t)
    local live = target and t >= target.StartsAt and t < target.EndsAt and target or nil
    out.live = live

    -- walk-in: the event on now, or the next
    local walkIn = { event = target, open = false }
    if target then
        local m = ArenaTiming.markers(schedule, target)
        if t < m.WalkInOpens then
            walkIn.reason = "Opens in " .. ArenaTiming.untilText(m.WalkInOpens)
        elseif t < m.WalkInCloses then
            walkIn.open = true
        else
            local nextEvent = schedule.nextEvent(t)
            walkIn.event = nextEvent
            walkIn.reason = nextEvent and string.format("Closed for this event. Next: %s, opens in %s", nextEvent.Name,
                ArenaTiming.untilText(ArenaTiming.markers(schedule, nextEvent).WalkInOpens)) or "Closed for this event"
        end
    else
        walkIn.reason = "No event on the schedule"
    end
    out.walkIn = walkIn

    -- prebook: for the next event that hasn't started (while one is live, the one after it)
    local pre = live and schedule.nextEvent(t) or target
    local prebook = { event = pre, open = false }
    if pre then
        local opensAt = ArenaTiming.prebookOpensAt(schedule, pre)
        if t < opensAt then
            prebook.reason = string.format("Prebook for %s opens in %s", pre.Name, ArenaTiming.untilText(opensAt))
        elseif t < pre.StartsAt then
            prebook.open = true
            prebook.reason = "Closes in " .. ArenaTiming.untilText(pre.StartsAt)
        end
    else
        prebook.reason = "No event on the schedule"
    end
    out.prebook = prebook

    -- spectate: seats are sold while a round runs
    local spectate = { open = phase ~= nil and phase ~= "IDLE" }
    if not spectate.open then
        if live then
            spectate.reason = "Seats open when the next round starts"
        elseif target then
            spectate.reason = string.format("No round on. %s starts in %s", target.Name, ArenaTiming.untilText(target.StartsAt))
        else
            spectate.reason = "No round on"
        end
    end
    out.spectate = spectate
    return out
end

return ArenaTiming
