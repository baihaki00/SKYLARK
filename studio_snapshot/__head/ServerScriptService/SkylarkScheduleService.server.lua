--// SkylarkScheduleService.server.lua
-- Runs the Skylark clock (SkylarkTime) and the arena schedule (ArenaSchedule) on the server, and
-- ties them to the arena:
--   * publishes the current slot (Workspace attributes ArenaSlot / ArenaSlotKind / ArenaSlotEndsAt)
--     and fires shared.SkylarkSchedule.SlotChanged, so any system can follow the schedule;
--   * announces each new slot on the arena screen;
--   * Auto Events (Workspace attribute SkylarkAutoEvents): while an event window is open, starts a
--     round through the Arena System Orchestrator whenever the arena is idle. A round only starts
--     if it can finish inside the window; one in progress when the window closes plays out.
--     Off by default in Studio (manual testing keeps the arena), on in live servers.
--   * debug time for the owner (ArenaNetwork.SkylarkTimeDebug, Studio or the place's creator):
--     leave real time, pause, speed up, scrub to any moment, back to real time.
--     The clock-panel buttons send these; the Workspace attribute SkylarkTimeCommand works the
--     same from Studio's command bar ("set 18", "shift 1200", "rate 60", "real").
--
-- Day cycle lighting (Workspace attribute SkylarkDayCycle) is drawn on each client
-- (SkylarkClock.client); the server only holds the switch.

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local RunService = game:GetService("RunService")

local QuinCore = ReplicatedStorage:WaitForChild("QuinCore")
local SkylarkTime = require(QuinCore:WaitForChild("SkylarkTime"))
local ArenaSchedule = require(QuinCore:WaitForChild("ArenaSchedule"))
local ArenaConfig = require(QuinCore:WaitForChild("ArenaConfig"))
local ArenaScreen = require(ServerScriptService:WaitForChild("ArenaScreenManager"))

local ROUND_GAP = 15 -- real seconds between the end of one round and the next
local ANNOUNCE_MAX_RATE = 60 -- no slot announcements while scrubbing faster than this
local MAX_RATE = 7200

local SLOT_COLORS = {
    Event = Color3.fromRGB(255, 180, 50),
    Open = Color3.fromRGB(0, 220, 255),
    Closing = Color3.fromRGB(180, 140, 255),
    Rest = Color3.fromRGB(130, 145, 170),
}

if Workspace:GetAttribute("SkylarkDayCycle") == nil then
    Workspace:SetAttribute("SkylarkDayCycle", true)
end
if Workspace:GetAttribute("SkylarkAutoEvents") == nil then
    Workspace:SetAttribute("SkylarkAutoEvents", not RunService:IsStudio())
end

-- ============================================================================
-- DEBUG TIME
-- ============================================================================

local function setOverride(t, rate)
    rate = math.clamp(rate, 0, MAX_RATE)
    Workspace:SetAttribute("SkylarkTimeOverride", SkylarkTime.encodeOverride(t, Workspace:GetServerTimeNow(), rate))
end

local function applyCommand(action, value)
    if action == "real" then
        Workspace:SetAttribute("SkylarkTimeOverride", nil)
    elseif action == "set" and tonumber(value) then -- an absolute Skylark timestamp
        setOverride(tonumber(value), SkylarkTime.rate())
    elseif action == "hour" and tonumber(value) then -- Skylark hour 0-24 of the current day
        setOverride(SkylarkTime.info().DayStart + (tonumber(value) % 24) * SkylarkTime.HOUR, SkylarkTime.rate())
    elseif action == "shift" and tonumber(value) then -- Skylark seconds forward (negative: back)
        setOverride(SkylarkTime.now() + tonumber(value), SkylarkTime.rate())
    elseif action == "rate" and tonumber(value) then
        setOverride(SkylarkTime.now(), tonumber(value))
    elseif action == "daycycle" then
        Workspace:SetAttribute("SkylarkDayCycle", value == true or value == "on")
    elseif action == "autoevents" then
        Workspace:SetAttribute("SkylarkAutoEvents", value == true or value == "on")
    else
        return false
    end
    return true
end

local function mayDebug(player)
    return RunService:IsStudio() or (game.CreatorType == Enum.CreatorType.User and player.UserId == game.CreatorId)
end

local ArenaNetwork = ReplicatedStorage:FindFirstChild("ArenaNetwork")
if not ArenaNetwork then
    ArenaNetwork = Instance.new("Folder")
    ArenaNetwork.Name = "ArenaNetwork"
    ArenaNetwork.Parent = ReplicatedStorage
end
local debugRemote = ArenaNetwork:FindFirstChild("SkylarkTimeDebug")
if not debugRemote then
    debugRemote = Instance.new("RemoteEvent")
    debugRemote.Name = "SkylarkTimeDebug"
    debugRemote.Parent = ArenaNetwork
end

debugRemote.OnServerEvent:Connect(function(player, action, value)
    if not mayDebug(player) or type(action) ~= "string" then
        return
    end
    applyCommand(action, value)
end)

-- Command bar: workspace:SetAttribute("SkylarkTimeCommand", "hour 18")
Workspace:GetAttributeChangedSignal("SkylarkTimeCommand"):Connect(function()
    local cmd = Workspace:GetAttribute("SkylarkTimeCommand")
    if type(cmd) ~= "string" or cmd == "" then
        return
    end
    Workspace:SetAttribute("SkylarkTimeCommand", nil)
    local action, value = cmd:match("^(%S+)%s*(.*)$")
    if not applyCommand(action and action:lower() or "", value) then
        warn("[SkylarkSchedule] Unknown time command: " .. cmd)
    end
end)

-- ============================================================================
-- SCHEDULE -> ARENA
-- ============================================================================

local SlotChanged = Instance.new("BindableEvent")

-- Longest a round can take (real seconds), from the default phase durations
local function roundLength()
    local total = 0
    for _, seconds in pairs(ArenaConfig.DefaultDurations) do
        total += seconds
    end
    return total
end
local ROUND_LENGTH = roundLength()

local currentKey = nil
local windowRound = 0
local idleSince = os.clock()
local autoRunning = false -- the round now in the arena was started by the schedule

local function orchestrator()
    return shared.ArenaOrchestrator
end

local function onSlot(slot)
    currentKey = slot.Key
    windowRound = 0
    Workspace:SetAttribute("ArenaSlot", slot.Name)
    Workspace:SetAttribute("ArenaSlotKind", slot.Kind)
    Workspace:SetAttribute("ArenaSlotEndsAt", slot.EndsAt)
    print(string.format("[SkylarkSchedule] %s %s SST: %s (%s)", SkylarkTime.WEEKDAYS[slot.Weekday],
        SkylarkTime.formatHours(slot.From), slot.Name, slot.Kind))
    SlotChanged:Fire(slot)
    if SkylarkTime.rate() <= ANNOUNCE_MAX_RATE then
        local text = string.upper(slot.Name) .. (slot.Tagline and (" // " .. string.upper(slot.Tagline)) or "")
        pcall(ArenaScreen.displayAnnouncement, text, 6, "SKYLARK SCHEDULE", SLOT_COLORS[slot.Kind])
    end
end

local function tryAutoRound(slot)
    local orch = orchestrator()
    if not orch or Workspace:GetAttribute("SkylarkAutoEvents") ~= true or slot.Kind ~= "Event" then
        return
    end
    local phase = orch.getPhase()
    if phase ~= "IDLE" then
        idleSince = os.clock()
        return
    end
    if autoRunning then -- the last scheduled round has ended
        autoRunning = false
        idleSince = os.clock()
    end
    if os.clock() - idleSince < ROUND_GAP then
        return
    end
    -- only if the round fits in what is left of the window (always while the clock is paused)
    local left = SkylarkTime.realSecondsUntil(slot.EndsAt)
    if left and left < ROUND_LENGTH then
        return
    end
    windowRound += 1
    local settings = ArenaSchedule.matchFor(slot, windowRound)
    print(string.format("[SkylarkSchedule] %s round %d: %s, team size %s", slot.Name, windowRound,
        tostring(settings.Mode), tostring(settings.TeamSize)))
    local ok = orch.startMatch(settings)
    if ok then
        autoRunning = true
    end
end

task.spawn(function()
    while true do
        local slot = ArenaSchedule.slotAt(SkylarkTime.now())
        if slot.Key ~= currentKey then
            onSlot(slot)
        end
        local ok, err = pcall(tryAutoRound, slot)
        if not ok then
            warn("[SkylarkSchedule] Auto round failed: " .. tostring(err))
        end
        task.wait(0.5)
    end
end)

shared.SkylarkSchedule = {
    now = SkylarkTime.now,
    info = SkylarkTime.info,
    slot = function()
        return ArenaSchedule.slotAt(SkylarkTime.now())
    end,
    nextEvent = function()
        return ArenaSchedule.nextEvent(SkylarkTime.now())
    end,
    command = applyCommand,
    SlotChanged = SlotChanged.Event,
}

print(string.format("[SkylarkSchedule] Ready. SST %s, %s, %s day %d. Auto events %s.",
    SkylarkTime.formatHours(SkylarkTime.info().Hours), SkylarkTime.info().WeekdayName,
    SkylarkTime.info().Season, SkylarkTime.info().SeasonDay,
    Workspace:GetAttribute("SkylarkAutoEvents") and "on" or "off"))
