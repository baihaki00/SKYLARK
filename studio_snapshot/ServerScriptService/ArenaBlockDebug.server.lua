--// ArenaBlockDebug.server.lua
-- The server side of the ARENA MENU [DEBUG] (ArenaBlockMenu.client, opened from an arena terminal):
-- test an event block without waiting, and tune its timing live.
-- Remote ArenaNetwork.ArenaBlockDebug (RemoteFunction), Studio or admins (SkylarkCanAdmin) only:
--   "jump", marker      the clock to 10 real seconds before a marker of the block entries are for
--                       now (ArenaTiming.markers: PrebookOpens / WalkInOpens / Start / LastRound /
--                       WalkInCloses / End); a paused clock starts at 1x
--   "rate", n           clock speed (0 pauses)
--   "autoevents", bool  scheduled rounds on / off
--   "set", { key, value }  an ArenaTiming value for this session ("reset" = all defaults)
--   "print"             the current values to the output, as ArenaTiming.DEFAULTS lines
--   "skip" / "stop"     the round's current phase / the whole round
-- Quick match stays on ArenaEntry ("quick"): the menu calls it there.

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local QuinCore = ReplicatedStorage:WaitForChild("QuinCore")
local SkylarkTime = require(QuinCore:WaitForChild("SkylarkTime"))
local ArenaSchedule = require(QuinCore:WaitForChild("ArenaSchedule"))
local ArenaTiming = require(QuinCore:WaitForChild("ArenaTiming"))

local JUMP_LEAD = 10 -- real seconds before the marker

-- What each value may be set to
local LIMITS = {
    WalkInOpensBefore = { 0, 7200 },
    WalkInClosesBeforeEnd = { 0, 3600 },
    PrebookDiscount = { 0, 0.9 },
    RoundGap = { 0, 300 },
    PreparationRoom = { 5, 600 },
    StadiumAnthem = { 1, 300 },
    PostGame = { 5, 900 },
    GameTime = { 30, 1800 },
}

local function allowed(player)
    return RunService:IsStudio() or player:GetAttribute("SkylarkCanAdmin") == true
end

local function schedule()
    return shared.SkylarkSchedule
end

local function setValue(key, value)
    if key == "WalkInCloseRule" then
        return ArenaTiming.set(key, value == "LastRound" and "LastRound" or "BeforeEnd")
    elseif key == "FastRounds" then
        return ArenaTiming.set(key, value == true)
    end
    local limits = LIMITS[key]
    local n = tonumber(value)
    if not limits or not n then
        return false
    end
    return ArenaTiming.set(key, math.clamp(n, limits[1], limits[2]))
end

local function printValues()
    local keys = {}
    for key in pairs(ArenaTiming.DEFAULTS) do
        table.insert(keys, key)
    end
    table.sort(keys)
    local lines = { "[ArenaBlockDebug] ArenaTiming values now (paste into ArenaTiming.DEFAULTS):" }
    for _, key in ipairs(keys) do
        local v = ArenaTiming.get(key)
        local text = type(v) == "string" and string.format("%q", v) or tostring(v)
        local changed = v ~= ArenaTiming.DEFAULTS[key] and "  -- changed" or ""
        table.insert(lines, string.format("    %s = %s,%s", key, text, changed))
    end
    print(table.concat(lines, "\n"))
end

local function handle(player, action, value)
    if not allowed(player) then
        return false, "The arena menu is a debug tool."
    end
    local sched = schedule()
    if not sched then
        return false, "The schedule isn't ready."
    end
    if action == "jump" then
        local slot = ArenaTiming.targetEvent(ArenaSchedule)
        local markers = slot and ArenaTiming.markers(ArenaSchedule, slot)
        local at = markers and markers[value]
        if not at then
            return false, "No such moment."
        end
        if SkylarkTime.rate() <= 0 then
            sched.command("rate", 1)
        end
        sched.command("set", at - JUMP_LEAD * SkylarkTime.rate())
        return true, string.format("Clock: %ds before %s", JUMP_LEAD, tostring(value))
    elseif action == "rate" then
        return sched.command("rate", tonumber(value) or 1)
    elseif action == "autoevents" then
        return sched.command("autoevents", value == true)
    elseif action == "set" and type(value) == "table" then
        return setValue(value[1], value[2])
    elseif action == "reset" then
        ArenaTiming.reset()
        return true
    elseif action == "print" then
        printValues()
        return true, "Printed to the output"
    elseif action == "skip" or action == "stop" then
        local orch = shared.ArenaOrchestrator
        if not orch then
            return false, "The arena isn't ready."
        end
        if action == "skip" then
            orch.skipPhase()
        else
            orch.stopMatch()
        end
        return true
    end
    return false, "Unknown request"
end

local net = ReplicatedStorage:FindFirstChild("ArenaNetwork")
if not net then
    net = Instance.new("Folder")
    net.Name = "ArenaNetwork"
    net.Parent = ReplicatedStorage
end
local remote = net:FindFirstChild("ArenaBlockDebug") or Instance.new("RemoteFunction")
remote.Name = "ArenaBlockDebug"
remote.OnServerInvoke = function(player, action, value)
    local ok, result, message = pcall(handle, player, action, value)
    if not ok then
        warn("[ArenaBlockDebug] " .. tostring(result))
        return false, "Error: " .. tostring(result)
    end
    return result, message
end
remote.Parent = net

