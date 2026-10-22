--// SkylarkTime.lua
-- Skylark Standard Time (SST), the one clock the whole game reads (server and clients alike).
--
--   1 Skylark day  = 8 real hours (3 Skylark days per real day), pinned to UTC: everyone everywhere
--                    sees the same clock. Days begin at 00:00, 08:00 and 16:00 UTC.
--   1 Skylark hour = 20 real minutes.
--   1 Skylark week = 7 Skylark days (56 real hours).
--   1 season       = 3 Skylark weeks = 21 Skylark days = exactly 1 real week (Monday 00:00 UTC).
--   1 year         = Spring, Summer, Fall, Winter = 4 real weeks.
--
-- Debug time (the owner's "Sims cheat"): the server can lift the clock off real time. While the
-- Workspace attribute SkylarkTimeOverride is set ("base|anchor|rate"), Skylark time is
--   base + (server time - anchor) * rate
-- so it can be paused (rate 0), sped up, or set to any moment. Cleared, the clock is real again.
-- One attribute, so a client never reads half of a change. Set through SkylarkScheduleService.

local Workspace = game:GetService("Workspace")

local SkylarkTime = {}

SkylarkTime.DAY = 8 * 3600 -- real seconds per Skylark day
SkylarkTime.HOUR = SkylarkTime.DAY / 24 -- 1200: real seconds per Skylark hour
SkylarkTime.SEASON_DAYS = 21
SkylarkTime.YEAR_DAYS = 84

-- Skylark day 0: Monday 2026-10-19 00:00 UTC, the first day of Spring, Year 1
SkylarkTime.EPOCH = 1792368000

SkylarkTime.WEEKDAYS = { "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun" }
SkylarkTime.WEEKDAY_NAMES = { "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday" }
SkylarkTime.SEASONS = { "Spring", "Summer", "Fall", "Winter" }

SkylarkTime.PERIODS = {
    { From = 0, To = 6, Name = "Rest", Tagline = "The city never truly sleeps" },
    { From = 6, To = 12, Name = "Morning", Tagline = "New day, new challengers" },
    { From = 12, To = 18, Name = "Midday", Tagline = "All paths cross here" },
    { From = 18, To = 24, Name = "Night", Tagline = "Where legends rise" },
}

local OVERRIDE_ATTR = "SkylarkTimeOverride"

-- The override as numbers, or nil when the clock runs on real time
function SkylarkTime.override()
    local raw = Workspace:GetAttribute(OVERRIDE_ATTR)
    if type(raw) ~= "string" then
        return nil
    end
    local base, anchor, rate = raw:match("^([%-%d%.]+)|([%-%d%.]+)|([%-%d%.]+)$")
    base, anchor, rate = tonumber(base), tonumber(anchor), tonumber(rate)
    if not (base and anchor and rate) then
        return nil
    end
    return base, anchor, rate
end

function SkylarkTime.encodeOverride(base, anchor, rate)
    return string.format("%.3f|%.3f|%.4f", base, anchor, rate)
end

function SkylarkTime.isDebug()
    return SkylarkTime.override() ~= nil
end

-- Clock speed: Skylark seconds per real second (1 on real time, 0 when paused)
function SkylarkTime.rate()
    local _, _, rate = SkylarkTime.override()
    return rate or 1
end

-- Now, as a Unix-style timestamp on the Skylark clock (real UTC time unless debug time is on)
function SkylarkTime.now()
    local real = Workspace:GetServerTimeNow()
    local base, anchor, rate = SkylarkTime.override()
    if not base then
        return real
    end
    return base + (real - anchor) * rate
end

-- Real seconds until Skylark time `t` at the current clock speed (nil while paused)
function SkylarkTime.realSecondsUntil(t)
    local rate = SkylarkTime.rate()
    if rate <= 0 then
        return nil
    end
    return (t - SkylarkTime.now()) / rate
end

function SkylarkTime.dayStart(day)
    return SkylarkTime.EPOCH + day * SkylarkTime.DAY
end

-- Everything about a moment on the Skylark clock (default: now)
function SkylarkTime.info(t)
    t = t or SkylarkTime.now()
    local s = t - SkylarkTime.EPOCH
    local day = math.floor(s / SkylarkTime.DAY)
    local hours = (s - day * SkylarkTime.DAY) / SkylarkTime.HOUR -- 0 .. 24
    local seasonIndex = math.floor(day / SkylarkTime.SEASON_DAYS) % 4 + 1
    local period = SkylarkTime.PERIODS[1]
    for _, p in ipairs(SkylarkTime.PERIODS) do
        if hours >= p.From and hours < p.To then
            period = p
        end
    end
    local weekday = day % 7 + 1
    return {
        Time = t,
        Day = day,
        DayStart = SkylarkTime.dayStart(day),
        Hours = hours,
        Hour = math.floor(hours),
        Minute = math.floor((hours % 1) * 60),
        Weekday = weekday,
        WeekdayName = SkylarkTime.WEEKDAY_NAMES[weekday],
        Week = math.floor(day / 7),
        SeasonIndex = seasonIndex,
        Season = SkylarkTime.SEASONS[seasonIndex],
        SeasonDay = day % SkylarkTime.SEASON_DAYS + 1,
        SeasonProgress = (day % SkylarkTime.SEASON_DAYS + hours / 24) / SkylarkTime.SEASON_DAYS,
        Year = math.floor(day / SkylarkTime.YEAR_DAYS) + 1,
        Period = period.Name,
        Tagline = period.Tagline,
    }
end

-- "14:20" from Skylark hours
function SkylarkTime.formatHours(hours)
    hours = hours % 24
    return string.format("%02d:%02d", math.floor(hours), math.floor((hours % 1) * 60))
end

-- "1h 12m" / "42m" / "35s" from real seconds
function SkylarkTime.formatDuration(seconds)
    if not seconds then
        return "paused"
    end
    seconds = math.max(0, math.floor(seconds))
    local h, m = math.floor(seconds / 3600), math.floor(seconds % 3600 / 60)
    if h > 0 then
        return string.format("%dh %02dm", h, m)
    elseif m > 0 then
        return string.format("%dm", m)
    end
    return string.format("%ds", seconds)
end

return SkylarkTime
