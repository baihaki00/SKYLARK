--// ArenaSchedule.lua
-- The Argonia arena schedule (D:\SKYLARK\ARENA SCHEDULE.png) on the Skylark clock (SkylarkTime).
--
-- Every Skylark day has the same shape; the event in each event slot changes with the weekday.
-- An event slot is a WINDOW of repeating rounds, not one match: while it is open, a new round
-- starts whenever the arena is free (SkylarkScheduleService, when Auto Events is on), so a player
-- who arrives mid-window waits one round at most.
-- Rest stops official events only: the arena stays open for training and spectating.
--
-- `Match` is what a round hands the Arena System Orchestrator (ArenaSystemOrchestrator.startMatch).
-- `Sizes` rotates the team size round by round (brackets: 1v1, 2v2, 4v4, 8v8 until the bracket
-- ladder exists). 20v20 is on the sheet; the arena runs 16v16 for now.
-- `PerPlayer`: how many of their Quins a player may enter together (ArenaRegistration); 2 in the
-- 16v16 battles, 1 otherwise. A round's phase durations come from ArenaTiming (the preparation
-- room gets a full minute; the ARENA MENU [DEBUG] can change them live or make rounds fast).

local SkylarkTime = require(script.Parent:WaitForChild("SkylarkTime"))
local ArenaTiming = require(script.Parent:WaitForChild("ArenaTiming"))

local ArenaSchedule = {}

ArenaSchedule.DAILY = {
    { From = 0, To = 6, Kind = "Rest", Name = "Rest", Tagline = "Rest. Prepare. Return." },
    { From = 6, To = 10, Kind = "Event", Slot = "Brackets" },
    { From = 10, To = 12, Kind = "Open", Name = "Open Arena", Tagline = "Training / FFA" },
    { From = 12, To = 16, Kind = "Event", Slot = "TeamBattles" },
    { From = 16, To = 18, Kind = "Open", Name = "Open Arena", Tagline = "Training / Spectate" },
    { From = 18, To = 22, Kind = "Event", Slot = "Night" },
    { From = 22, To = 24, Kind = "Closing", Name = "Closing / Aftermath", Tagline = "Social, spectate" },
}

local BRACKETS = { Mode = "TeamBattle", Sizes = { 1, 2, 4, 8 } }
local TEAM = { Mode = "TeamBattle", TeamSize = 16, PerPlayer = 2 }
local TEAM_TERRAIN = { Mode = "TeamBattle", TeamSize = 16, PerPlayer = 2, Toggles = { ProceduralTerrain = true } }

-- Event slots by weekday (1 = Monday ... 7 = Sunday)
ArenaSchedule.EVENTS = {
    Brackets = {
        [1] = { Name = "Brackets", Tagline = "Ranked / Casual", Match = BRACKETS },
        [2] = { Name = "Brackets", Tagline = "Ranked / Casual", Match = BRACKETS },
        [3] = { Name = "Brackets", Tagline = "Ranked / Casual", Match = BRACKETS },
        [4] = { Name = "Brackets", Tagline = "Ranked / Casual", Match = BRACKETS },
        [5] = { Name = "Brackets", Tagline = "Ranked / Casual", Match = BRACKETS },
        [6] = { Name = "Special Brackets", Tagline = "Event qualification", Match = BRACKETS },
        [7] = { Name = "Championship Qualification", Tagline = "Earn your place", Match = BRACKETS },
    },
    TeamBattles = {
        [1] = { Name = "Team Battles", Tagline = "16v16", Match = TEAM },
        [2] = { Name = "Team Battles", Tagline = "16v16", Match = TEAM },
        [3] = { Name = "Team Battles", Tagline = "16v16", Match = TEAM },
        [4] = { Name = "Team Battles", Tagline = "16v16", Match = TEAM },
        [5] = { Name = "Team Battles (Featured)", Tagline = "16v16", Match = TEAM },
        [6] = { Name = "Special Event", Tagline = "Large scale", Match = TEAM_TERRAIN },
        [7] = { Name = "Team Championship", Tagline = "16v16", Match = TEAM },
    },
    Night = {
        [1] = { Name = "Champion's Night", Tagline = "Ranked showcase", Match = { Mode = "TeamBattle", TeamSize = 8 } },
        [2] = { Name = "FFA Night", Tagline = "Every Quin for itself", Match = { Mode = "FFA", TeamSize = 16 } },
        [3] = { Name = "Rivalry Night", Tagline = "Featured matches", Match = { Mode = "TeamBattle", TeamSize = 8 } },
        [4] = { Name = "Team War", Tagline = "Large team battles", Match = TEAM },
        [5] = { Name = "Grand Arena", Tagline = "The weekly major", Match = TEAM_TERRAIN },
        [6] = { Name = "Special Event", Tagline = "Unique rules", Match = TEAM_TERRAIN },
        [7] = { Name = "Championship Night", Tagline = "Semifinals to finals", Match = TEAM },
    },
}

ArenaSchedule.EVENT_SLOTS = { "Brackets", "TeamBattles", "Night" }

-- The slot of Skylark day `day` that holds Skylark hour `hours`
local function resolve(day, index)
    local entry = ArenaSchedule.DAILY[index]
    local weekday = day % 7 + 1
    local start = SkylarkTime.dayStart(day)
    local slot = {
        Kind = entry.Kind,
        Name = entry.Name,
        Tagline = entry.Tagline,
        From = entry.From,
        To = entry.To,
        Day = day,
        Weekday = weekday,
        Index = index,
        StartsAt = start + entry.From * SkylarkTime.HOUR,
        EndsAt = start + entry.To * SkylarkTime.HOUR,
        Key = day .. ":" .. index,
    }
    if entry.Slot then
        local event = ArenaSchedule.EVENTS[entry.Slot][weekday]
        slot.Slot = entry.Slot
        slot.Name = event.Name
        slot.Tagline = event.Tagline
        slot.Match = event.Match
    end
    return slot
end

function ArenaSchedule.slotAt(t)
    local info = SkylarkTime.info(t)
    for index, entry in ipairs(ArenaSchedule.DAILY) do
        if info.Hours >= entry.From and info.Hours < entry.To then
            return resolve(info.Day, index)
        end
    end
    return resolve(info.Day, #ArenaSchedule.DAILY)
end

-- The slot after `slot` (rolls into the next day)
function ArenaSchedule.nextSlot(slot)
    if slot.Index < #ArenaSchedule.DAILY then
        return resolve(slot.Day, slot.Index + 1)
    end
    return resolve(slot.Day + 1, 1)
end

-- The next event window that has not started yet
function ArenaSchedule.nextEvent(t)
    local slot = ArenaSchedule.nextSlot(ArenaSchedule.slotAt(t))
    for _ = 1, 32 do
        if slot.Kind == "Event" then
            return slot
        end
        slot = ArenaSchedule.nextSlot(slot)
    end
    return nil
end

-- All slots of Skylark day `day`
function ArenaSchedule.day(day)
    local slots = {}
    for index in ipairs(ArenaSchedule.DAILY) do
        table.insert(slots, resolve(day, index))
    end
    return slots
end

-- The match settings for round `round` (1, 2, ...) of an event window
function ArenaSchedule.matchFor(slot, round)
    local match = slot.Match
    if not match then
        return nil
    end
    local settings = {
        Mode = match.Mode,
        TeamSize = match.TeamSize,
        Toggles = match.Toggles,
        Durations = ArenaTiming.durations(),
        CutAnthem = ArenaTiming.get("FastRounds") == true, -- (fast test rounds: the anthem fits its window)
    }
    if match.Sizes then
        settings.TeamSize = match.Sizes[(round - 1) % #match.Sizes + 1]
    end
    return settings
end

-- How many Quins one player may enter in an event window
function ArenaSchedule.perPlayer(slot)
    return slot and slot.Match and slot.Match.PerPlayer or 1
end

return ArenaSchedule
