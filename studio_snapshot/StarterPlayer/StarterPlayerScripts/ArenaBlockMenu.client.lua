--// ArenaBlockMenu.client.lua
-- ARENA MENU [DEBUG]: test an event block without waiting, and tune its timing live.
-- Opened from an arena terminal's chooser (ArenaEntry: shown with F8, and always in the Roblox
-- Player role for testers); shared.OpenArenaBlockMenu() opens it. Studio or admins only (the
-- server checks: ArenaBlockDebug).
--   * TIMELINE of the block entries are for now (ArenaTiming.markers): prebook, walk-in and the
--     event as lanes, the six moments marked (SST time, offset from the start at 1x, time left),
--     and a NOW line;
--   * what is open right now: prebook, walk-in, new rounds, the round's phase;
--   * JUMP to 10 real seconds before each moment; SET CLOCK to a typed SST time, or move it by
--     1 / 5 real minutes; the clock (pause, 1x, 10x, 60x), Auto Events,
--     Fast Rounds (every round about 1.5 min), QUICK MATCH, skip a phase, stop the round;
--   * TIMINGS (ArenaTiming), changed live for this session: RESET, and PRINT VALUES writes them
--     to the output to bake in.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local QuinCore = ReplicatedStorage:WaitForChild("QuinCore")
local SkylarkTime = require(QuinCore:WaitForChild("SkylarkTime"))
local ArenaTiming = require(QuinCore:WaitForChild("ArenaTiming"))
local SkylarkArenas = require(QuinCore:WaitForChild("SkylarkArenas"))
local net = ReplicatedStorage:WaitForChild("ArenaNetwork")
local remote = net:WaitForChild("ArenaBlockDebug", 30)
local entryRemote = net:WaitForChild("ArenaEntry", 30)

local ARENA = SkylarkArenas.current()
local SCHEDULE = ARENA.Schedule

local W, H = 920, 776

local C_BG = Color3.fromRGB(15, 18, 26)
local C_CARD = Color3.fromRGB(22, 27, 38)
local C_STROKE = Color3.fromRGB(38, 48, 68)
local C_CYAN = Color3.fromRGB(0, 220, 255)
local C_AMBER = Color3.fromRGB(255, 180, 50)
local C_GREEN = Color3.fromRGB(0, 230, 120)
local C_RED = Color3.fromRGB(255, 60, 80)
local C_TEXT = Color3.fromRGB(240, 245, 255)
local C_MUTED = Color3.fromRGB(130, 145, 170)
local C_SEL = Color3.fromRGB(70, 55, 20)

local function new(className, props)
    local inst = Instance.new(className)
    for k, v in pairs(props) do
        if k ~= "Parent" then
            inst[k] = v
        end
    end
    inst.Parent = props.Parent
    return inst
end

local function corner(inst, r)
    new("UICorner", { Parent = inst, CornerRadius = UDim.new(0, r) })
end

local function label(parent, props)
    props.Parent = parent
    props.BackgroundTransparency = 1
    props.Font = props.Font or Enum.Font.Gotham
    props.TextColor3 = props.TextColor3 or C_TEXT
    props.TextSize = props.TextSize or 12
    props.TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Left
    props.TextTruncate = props.TextTruncate or Enum.TextTruncate.AtEnd
    return new("TextLabel", props)
end

local function button(parent, text, x, y, w, h, name)
    local b = new("TextButton", { Name = name or "Button", Parent = parent, Text = text, Font = Enum.Font.GothamBold, TextSize = 11, TextWrapped = true,
        TextColor3 = C_TEXT, BackgroundColor3 = C_CARD, AutoButtonColor = true, Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(w, h) })
    corner(b, 6)
    new("UIStroke", { Parent = b, Color = C_STROKE, Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border })
    return b
end

-- "1h 05m" / "4m 20s" / "35s" from seconds
local function dur(seconds)
    seconds = math.floor(math.abs(seconds) + 0.5)
    if seconds >= 3600 then
        return string.format("%dh %02dm", seconds // 3600, (seconds % 3600) // 60)
    elseif seconds >= 60 then
        return seconds % 60 == 0 and string.format("%dm", seconds // 60) or string.format("%dm %02ds", seconds // 60, seconds % 60)
    end
    return seconds .. "s"
end

local function sst(t)
    return SkylarkTime.formatHours(SkylarkTime.info(t).Hours)
end

-- ============================================================================
-- WINDOW
-- ============================================================================

local gui = new("ScreenGui", { Name = "ArenaBlockDebugUI", Parent = player:WaitForChild("PlayerGui"), ResetOnSpawn = false, DisplayOrder = 75, Enabled = false, IgnoreGuiInset = true })
local window = new("Frame", { Name = "Window", Parent = gui, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(W, H),
    BackgroundColor3 = C_BG, BackgroundTransparency = 0.03 })
corner(window, 12)
new("UIStroke", { Parent = window, Color = C_AMBER, Thickness = 1.5 })
local fitScale = new("UIScale", { Parent = window })
local function fit()
    local view = Workspace.CurrentCamera and Workspace.CurrentCamera.ViewportSize or Vector2.new(W, H)
    fitScale.Scale = math.min(1, (view.X - 40) / W, (view.Y - 40) / H)
end
fit()
if Workspace.CurrentCamera then
    Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fit)
end

label(window, { Position = UDim2.fromOffset(20, 14), Size = UDim2.fromOffset(500, 20), Font = Enum.Font.GothamBlack, TextSize = 16, TextColor3 = C_AMBER, Text = "ARENA MENU  [DEBUG]" })
local closeButton = button(window, "X", W - 46, 12, 28, 28, "Close")
local eventLabel = label(window, { Position = UDim2.fromOffset(20, 40), Size = UDim2.fromOffset(W - 80, 18), Font = Enum.Font.GothamBold, TextSize = 14, Text = "" })
local clockLabel = label(window, { Position = UDim2.fromOffset(20, 60), Size = UDim2.fromOffset(W - 40, 16), TextColor3 = C_MUTED, Text = "" })

-- ============================================================================
-- TIMELINE
-- ============================================================================

local MARKERS = {
    -- (labels above or below the lanes, the end ones on a second row: those moments sit close)
    { key = "PrebookOpens", name = "PREBOOK OPENS", color = C_CYAN, top = true },
    { key = "WalkInOpens", name = "WALK-IN OPENS", color = C_GREEN, top = false },
    { key = "Start", name = "EVENT STARTS", color = C_AMBER, top = true },
    { key = "LastRound", name = "LAST ROUND START", color = C_AMBER, top = false },
    { key = "WalkInCloses", name = "WALK-IN CLOSES", color = C_GREEN, top = true },
    { key = "End", name = "BLOCK ENDS", color = C_AMBER, top = false, row2 = true },
}

local timeline = new("Frame", { Parent = window, Position = UDim2.fromOffset(20, 86), Size = UDim2.fromOffset(W - 40, 212), BackgroundColor3 = C_CARD })
corner(timeline, 8)
local LANE_X = 96
local BAR_W = W - 40 - LANE_X - 24
local LANE_Y, LANE_H = 66, 10
local LANES = {
    { name = "PREBOOK", color = C_CYAN },
    { name = "WALK-IN", color = C_GREEN },
    { name = "EVENT", color = C_AMBER },
}
local laneFills = {}
for i, lane in ipairs(LANES) do
    local y = LANE_Y + (i - 1) * (LANE_H + 4)
    label(timeline, { Position = UDim2.fromOffset(14, y - 3), Size = UDim2.fromOffset(LANE_X - 20, LANE_H + 6), Font = Enum.Font.GothamBold, TextSize = 10, TextColor3 = lane.color, Text = lane.name })
    local track = new("Frame", { Parent = timeline, Position = UDim2.fromOffset(LANE_X, y), Size = UDim2.fromOffset(BAR_W, LANE_H), BackgroundColor3 = C_BG, BorderSizePixel = 0 })
    corner(track, 3)
    laneFills[i] = new("Frame", { Parent = track, Size = UDim2.fromScale(0, 1), BackgroundColor3 = lane.color, BackgroundTransparency = 0.35, BorderSizePixel = 0 })
    corner(laneFills[i], 3)
end
local LANES_BOTTOM = LANE_Y + #LANES * (LANE_H + 4) - 4

local markerParts = {}
for i, m in ipairs(MARKERS) do
    local top = m.top
    local tick = new("Frame", { Parent = timeline, AnchorPoint = Vector2.new(0.5, 0), Size = UDim2.fromOffset(2, LANES_BOTTOM - LANE_Y + 12 + (m.row2 and 44 or 0)),
        BackgroundColor3 = m.color, BorderSizePixel = 0, ZIndex = 2 })
    local text = label(timeline, { AnchorPoint = Vector2.new(0.5, 0), Size = UDim2.fromOffset(150, 42), TextSize = 10, TextXAlignment = Enum.TextXAlignment.Center,
        TextTruncate = Enum.TextTruncate.None, TextWrapped = true, TextYAlignment = top and Enum.TextYAlignment.Bottom or Enum.TextYAlignment.Top, RichText = true, Text = "" })
    markerParts[i] = { tick = tick, text = text, top = top, row2 = m.row2 }
end
local nowLine = new("Frame", { Parent = timeline, AnchorPoint = Vector2.new(0.5, 0), Size = UDim2.fromOffset(2, LANES_BOTTOM - LANE_Y + 20), BackgroundColor3 = C_TEXT, BorderSizePixel = 0, ZIndex = 3 })
local nowText = label(nowLine, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 0, -1), Size = UDim2.fromOffset(40, 12), Font = Enum.Font.GothamBold, TextSize = 10,
    TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 3, Text = "NOW" })

-- ============================================================================
-- STATUS, JUMPS, CLOCK
-- ============================================================================

local chips = {}
local CHIP_W = (W - 40 - 3 * 8) / 4
for i = 1, 4 do
    local chip = new("Frame", { Parent = window, Position = UDim2.fromOffset(20 + (i - 1) * (CHIP_W + 8), 308), Size = UDim2.fromOffset(CHIP_W, 30), BackgroundColor3 = C_CARD })
    corner(chip, 6)
    chips[i] = label(chip, { Position = UDim2.fromOffset(10, 0), Size = UDim2.new(1, -20, 1, 0), Font = Enum.Font.GothamBold, TextSize = 11, TextXAlignment = Enum.TextXAlignment.Center, Text = "" })
end

label(window, { Position = UDim2.fromOffset(20, 348), Size = UDim2.fromOffset(400, 14), Font = Enum.Font.GothamBold, TextSize = 11, TextColor3 = C_CYAN, Text = "JUMP TO  (10 real seconds before)" })
local JUMP_W = (W - 40 - 5 * 8) / 6
local jumpButtons = {}
for i, m in ipairs(MARKERS) do
    jumpButtons[i] = button(window, m.name, 20 + (i - 1) * (JUMP_W + 8), 366, JUMP_W, 32, "Jump" .. m.key)
    jumpButtons[i].TextColor3 = m.color
end

label(window, { Position = UDim2.fromOffset(20, 410), Size = UDim2.fromOffset(400, 14), Font = Enum.Font.GothamBold, TextSize = 11, TextColor3 = C_CYAN, Text = "CLOCK AND ROUNDS" })
local CLOCK_ITEMS = {
    { "PAUSE", "rate", 0 }, { "1x", "rate", 1 }, { "10x", "rate", 10 }, { "60x", "rate", 60 },
    { "AUTO EVENTS", "autoevents" }, { "FAST ROUNDS", "fast" }, { "QUICK MATCH", "quick" }, { "SKIP PHASE", "skip" }, { "STOP ROUND", "stop" },
}
local CLOCK_W = (W - 40 - 8 * 8) / 9
local clockButtons = {}
for i, item in ipairs(CLOCK_ITEMS) do
    clockButtons[i] = button(window, item[1], 20 + (i - 1) * (CLOCK_W + 8), 428, CLOCK_W, 32, "Clock" .. item[1]:gsub(" ", ""))
end

-- set the clock: a typed SST time, or a few real minutes either way
label(window, { Position = UDim2.fromOffset(20, 470), Size = UDim2.fromOffset(150, 32), Font = Enum.Font.GothamBold, TextSize = 11, TextColor3 = C_CYAN, Text = "SET CLOCK  (SST)" })
local timeBox = new("TextBox", { Name = "ClockInput", Parent = window, Position = UDim2.fromOffset(150, 470), Size = UDim2.fromOffset(90, 32), BackgroundColor3 = C_BG,
    Font = Enum.Font.GothamBold, TextSize = 14, TextColor3 = C_TEXT, PlaceholderText = "14:30", PlaceholderColor3 = C_MUTED, Text = "", ClearTextOnFocus = true })
corner(timeBox, 6)
new("UIStroke", { Parent = timeBox, Color = C_AMBER, Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border })
local setTimeButton = button(window, "SET", 248, 470, 60, 32, "SetClock")
setTimeButton.TextColor3 = C_AMBER
local SHIFTS = { { "-5m", -300 }, { "-1m", -60 }, { "+1m", 60 }, { "+5m", 300 } }
local shiftButtons = {}
for i, item in ipairs(SHIFTS) do
    shiftButtons[i] = button(window, item[1], 324 + (i - 1) * 68, 470, 60, 32, "Shift" .. item[1])
end
label(window, { Position = UDim2.fromOffset(324 + 4 * 68 + 8, 470), Size = UDim2.fromOffset(W - 20 - (324 + 4 * 68 + 8), 32), TextSize = 11, TextColor3 = C_MUTED,
    Text = "real minutes (1 real min = 3 SST min)  •  type HH:MM and press SET or Enter" })

-- ============================================================================
-- TIMINGS
-- ============================================================================

label(window, { Position = UDim2.fromOffset(20, 514), Size = UDim2.fromOffset(600, 14), Font = Enum.Font.GothamBold, TextSize = 11, TextColor3 = C_CYAN,
    Text = "TIMINGS  (this session only: real time at 1x, SST in brackets)" })

-- kind: "min" (seconds shown as minutes), "sec", "pct", "rule"
local ROWS = {
    { key = "WalkInOpensBefore", name = "Walk-in opens before start", kind = "min", step = 300 },
    { key = "WalkInCloseRule", name = "Walk-in closes", kind = "rule" },
    { key = "WalkInClosesBeforeEnd", name = "  close margin before block end", kind = "min", step = 60 },
    { key = "PrebookDiscount", name = "Prebook discount (earliest)", kind = "pct", step = 0.05 },
    { key = "RoundGap", name = "Gap between rounds", kind = "sec", step = 5 },
    { key = "PreparationRoom", name = "Prep room", kind = "sec", step = 10, phase = true },
    { key = "StadiumAnthem", name = "Anthem", kind = "sec", step = 10, phase = true },
    { key = "PostGame", name = "Post-game", kind = "sec", step = 30, phase = true },
    { key = "GameTime", name = "Longest fight", kind = "sec", step = 60, phase = true },
}
local COL_W = (W - 40 - 16) / 2
local ROW_H = 34
local rowParts = {}
for i, row in ipairs(ROWS) do
    local col = (i - 1) // 5
    local r = (i - 1) % 5
    local f = new("Frame", { Parent = window, Position = UDim2.fromOffset(20 + col * (COL_W + 16), 534 + r * (ROW_H + 4)), Size = UDim2.fromOffset(COL_W, ROW_H), BackgroundColor3 = C_CARD })
    corner(f, 6)
    label(f, { Position = UDim2.fromOffset(12, 0), Size = UDim2.fromOffset(200, ROW_H), TextSize = 12, Text = row.name })
    local value = label(f, { Position = UDim2.fromOffset(208, 0), Size = UDim2.fromOffset(COL_W - 208 - 76, ROW_H), Font = Enum.Font.GothamBold, TextSize = 12, TextColor3 = C_AMBER, Text = "" })
    local parts = { value = value }
    if row.kind == "rule" then
        parts.toggle = button(f, "SWITCH", COL_W - 72, 4, 64, ROW_H - 8, "Switch")
    else
        parts.minus = button(f, "-", COL_W - 72, 4, 30, ROW_H - 8, "Minus")
        parts.plus = button(f, "+", COL_W - 38, 4, 30, ROW_H - 8, "Plus")
    end
    rowParts[i] = parts
end
-- the 10th cell: what a round adds up to
local lengthCell = new("Frame", { Parent = window, Position = UDim2.fromOffset(20 + COL_W + 16, 534 + 4 * (ROW_H + 4)), Size = UDim2.fromOffset(COL_W, ROW_H), BackgroundColor3 = C_BG })
corner(lengthCell, 6)
new("UIStroke", { Parent = lengthCell, Color = C_STROKE, Thickness = 1 })
local lengthLabel = label(lengthCell, { Position = UDim2.fromOffset(12, 0), Size = UDim2.new(1, -24, 1, 0), TextSize = 11, TextColor3 = C_MUTED, Text = "" })

local resetButton = button(window, "RESET ALL", 20, H - 46, 120, 30, "Reset")
local printButton = button(window, "PRINT VALUES", 148, H - 46, 130, 30, "Print")
local statusLabel = label(window, { Position = UDim2.fromOffset(292, H - 46), Size = UDim2.fromOffset(W - 312, 30), TextSize = 12, Text = "" })

-- ============================================================================
-- DRAW
-- ============================================================================

local function setStatus(text, color)
    statusLabel.Text = text or ""
    statusLabel.TextColor3 = color or C_MUTED
end

local function chip(i, text, color)
    chips[i].Text = text
    chips[i].TextColor3 = color
end

local function valueText(row)
    local v = ArenaTiming.get(row.key)
    if row.kind == "rule" then
        return v == "LastRound" and "no round can start" or "margin before end"
    elseif row.kind == "pct" then
        return string.format("%d%%", math.floor(v * 100 + 0.5))
    elseif row.kind == "min" then
        return string.format("%s  (SST %s)", dur(v), dur(v * 3))
    end
    local text = dur(v)
    if row.phase and ArenaTiming.get("FastRounds") then
        text ..= string.format("   fast: %s", dur(ArenaTiming.FAST[row.key] or v))
    end
    return text
end

local function draw()
    local now = SkylarkTime.now()
    local info = SkylarkTime.info(now)
    local rate = SkylarkTime.rate()
    local slot = ArenaTiming.targetEvent(SCHEDULE, now)
    local phase = Workspace:GetAttribute("ArenaPhase") or "IDLE"
    local auto = Workspace:GetAttribute("SkylarkAutoEvents") == true
    local fast = ArenaTiming.get("FastRounds") == true
    clockLabel.Text = string.format("Clock %s SST, %s  •  %s  •  Auto events %s  •  Fast rounds %s  •  Phase %s  •  Round %s",
        SkylarkTime.formatHours(info.Hours), info.WeekdayName, rate == 0 and "PAUSED" or (rate .. "x"), auto and "ON" or "OFF", fast and "ON" or "OFF",
        phase, tostring(Workspace:GetAttribute("ArenaWindowRound") or "-"))
    if not slot then
        eventLabel.Text = string.upper(ARENA.Name) .. "  •  no event on the schedule"
        return
    end
    local live = now >= slot.StartsAt and now < slot.EndsAt
    eventLabel.Text = string.format("%s  •  %s%s  •  %s-%s SST  •  %s", string.upper(ARENA.Name), slot.Name, slot.Tagline and (" " .. slot.Tagline) or "",
        SkylarkTime.formatHours(slot.From), SkylarkTime.formatHours(slot.To), live and "LIVE" or "NEXT")
    eventLabel.TextColor3 = live and C_AMBER or C_TEXT

    -- the timeline
    local m = ArenaTiming.markers(SCHEDULE, slot)
    local from = math.min(m.PrebookOpens, m.WalkInOpens, m.LastRound)
    local to = m.End
    local span = math.max(1, to - from)
    from -= span * 0.03
    to += span * 0.03
    span = to - from
    local function x(t)
        return LANE_X + math.clamp((t - from) / span, 0, 1) * BAR_W
    end
    local function lane(i, a, b)
        local x1, x2 = x(a) - LANE_X, x(b) - LANE_X
        laneFills[i].Position = UDim2.fromOffset(x1, 0)
        laneFills[i].Size = UDim2.new(0, math.max(0, x2 - x1), 1, 0)
    end
    lane(1, m.PrebookOpens, m.Start)
    lane(2, m.WalkInOpens, math.max(m.WalkInOpens, m.WalkInCloses))
    lane(3, m.Start, m.End)
    for i, marker in ipairs(MARKERS) do
        local t = m[marker.key]
        local parts = markerParts[i]
        local px = x(t)
        parts.tick.Position = UDim2.fromOffset(px, LANE_Y - 6)
        parts.text.Position = UDim2.fromOffset(math.clamp(px, 75, W - 40 - 75), parts.top and LANE_Y - 50 or LANES_BOTTOM + 10 + (parts.row2 and 44 or 0))
        local offset = t - slot.StartsAt
        local left = SkylarkTime.realSecondsUntil(t)
        local when = t <= now and "passed" or (left and ("in " .. dur(left)) or "clock paused")
        parts.text.Text = string.format('<b><font color="#%s">%s</font></b>\n%s SST  •  %s%s\n%s', marker.color:ToHex(), marker.name, sst(t),
            offset < 0 and "-" or "+", dur(offset), when)
    end
    nowLine.Position = UDim2.fromOffset(x(now), LANE_Y - 10)
    nowText.Text = (now < from and "< NOW") or (now > to and "NOW >") or "NOW"

    -- what is open
    local prebookOpen = Workspace:GetAttribute("ArenaPrebookOpen") == true
    local walkInOpen = Workspace:GetAttribute("ArenaRegOpen") == true
    chip(1, "PREBOOK  " .. (prebookOpen and "OPEN" or "CLOSED"), prebookOpen and C_CYAN or C_MUTED)
    chip(2, "WALK-IN  " .. (walkInOpen and "OPEN" or "CLOSED"), walkInOpen and C_GREEN or C_MUTED)
    if not auto then
        chip(3, "NEW ROUNDS  OFF (auto events)", C_MUTED)
    elseif not live then
        chip(3, "NEW ROUNDS  when the event starts", C_MUTED)
    elseif now > m.LastRound then
        chip(3, "NEW ROUNDS  none left this block", C_RED)
    else
        chip(3, "NEW ROUNDS  can start", C_GREEN)
    end
    chip(4, "ROUND  " .. (phase == "IDLE" and "none running" or phase), phase == "IDLE" and C_MUTED or C_AMBER)

    -- buttons that show a state
    for i, item in ipairs(CLOCK_ITEMS) do
        local on = (item[2] == "rate" and rate == item[3]) or (item[2] == "autoevents" and auto) or (item[2] == "fast" and fast)
        clockButtons[i].BackgroundColor3 = on and C_SEL or C_CARD
        clockButtons[i].TextColor3 = on and C_AMBER or (item[2] == "stop" and C_RED or C_TEXT)
    end

    -- timings
    for i, row in ipairs(ROWS) do
        local parts = rowParts[i]
        parts.value.Text = valueText(row)
        local changed = ArenaTiming.get(row.key) ~= ArenaTiming.DEFAULTS[row.key]
        parts.value.TextColor3 = changed and C_AMBER or C_TEXT
    end
    local roundLen = ArenaTiming.roundLength()
    local gap = ArenaTiming.get("RoundGap")
    local blockLen = slot.EndsAt - slot.StartsAt
    local atLeast = math.max(0, math.floor((blockLen - roundLen) / (roundLen + gap)) + 1)
    lengthLabel.Text = string.format("A round: up to %s  •  this block fits at least %d", dur(roundLen), atLeast)
end

-- ============================================================================
-- ACTIONS
-- ============================================================================

local function send(action, value, okText)
    if not remote then
        setStatus("No arena debug remote", C_RED)
        return
    end
    local ok, result, message = pcall(function()
        return remote:InvokeServer(action, value)
    end)
    if ok and result then
        setStatus(message or okText or "Done", C_GREEN)
    else
        setStatus(ok and (message or "Refused") or "Could not reach the server", C_RED)
    end
    draw()
end

for i, m in ipairs(MARKERS) do
    jumpButtons[i].MouseButton1Click:Connect(function()
        send("jump", m.key)
    end)
end

for i, item in ipairs(CLOCK_ITEMS) do
    clockButtons[i].MouseButton1Click:Connect(function()
        local kind = item[2]
        if kind == "rate" then
            send("rate", item[3], "Clock " .. item[1])
        elseif kind == "autoevents" then
            send("autoevents", Workspace:GetAttribute("SkylarkAutoEvents") ~= true, "Auto events switched")
        elseif kind == "fast" then
            send("set", { "FastRounds", ArenaTiming.get("FastRounds") ~= true }, "Fast rounds switched (from the next round)")
        elseif kind == "skip" or kind == "stop" then
            send(kind, nil, kind == "skip" and "Phase skipped" or "Round stopped")
        elseif kind == "quick" then
            setStatus("Starting a quick match...", C_MUTED)
            local ok, result, message = pcall(function()
                return entryRemote:InvokeServer("quick")
            end)
            if ok and result then
                setStatus(message or "Quick match", C_GREEN)
                gui.Enabled = false
                if mounted and shared.ClosePlayerMenu then
                    shared.ClosePlayerMenu()
                end
            else
                setStatus(ok and (message or "Could not start") or "Could not reach " .. ARENA.Name, C_RED)
            end
        end
    end)
end

for i, row in ipairs(ROWS) do
    local parts = rowParts[i]
    if parts.toggle then
        parts.toggle.MouseButton1Click:Connect(function()
            send("set", { row.key, ArenaTiming.get(row.key) == "LastRound" and "BeforeEnd" or "LastRound" }, row.name .. " switched")
        end)
    else
        local function step(sign)
            send("set", { row.key, ArenaTiming.get(row.key) + sign * row.step }, row.name .. " changed")
        end
        parts.minus.MouseButton1Click:Connect(function()
            step(-1)
        end)
        parts.plus.MouseButton1Click:Connect(function()
            step(1)
        end)
    end
end

-- "14:30", "14", "1430", "9:05" -> SST hours
local function parseTime(text)
    text = (text or ""):gsub("%s", "")
    local h, m = text:match("^(%d%d?):(%d%d)$")
    if not h then
        h, m = text:match("^(%d%d)(%d%d)$")
    end
    if not h then
        h, m = text:match("^(%d%d?)$"), "0"
    end
    h, m = tonumber(h), tonumber(m)
    if not h or not m or h > 23 or m > 59 then
        return nil
    end
    return h + m / 60
end
local function setClock()
    local hours = parseTime(timeBox.Text)
    if not hours then
        setStatus("Type a time like 14:30", C_RED)
        return
    end
    send("hour", hours)
end
setTimeButton.MouseButton1Click:Connect(setClock)
timeBox.FocusLost:Connect(function(enter)
    if enter then
        setClock()
    end
end)
for i, item in ipairs(SHIFTS) do
    shiftButtons[i].MouseButton1Click:Connect(function()
        send("shift", item[2], string.format("Clock %s (real)", item[1]))
    end)
end

resetButton.MouseButton1Click:Connect(function()
    send("reset", nil, "All timings back to the defaults")
end)
printButton.MouseButton1Click:Connect(function()
    send("print")
end)
closeButton.MouseButton1Click:Connect(function()
    gui.Enabled = false
end)

-- Lent to the player menu's DEBUG tab: the window moves into the tab (full size, it scrolls there)
-- and comes back to its own screen before the tab redraws
local mounted = false
shared.MountArenaBlockMenu = function(holder)
    gui.Enabled = false
    mounted = true
    window.AnchorPoint = Vector2.zero
    window.Position = UDim2.fromOffset(0, 0)
    fitScale.Scale = 1
    closeButton.Visible = false
    window.Parent = holder
    setStatus("")
    draw()
end
shared.UnmountArenaBlockMenu = function()
    if not mounted then
        return
    end
    mounted = false
    window.Parent = gui
    window.AnchorPoint = Vector2.new(0.5, 0.5)
    window.Position = UDim2.fromScale(0.5, 0.5)
    closeButton.Visible = true
    fit()
end
-- (from the terminal: the menu opens on DEBUG; on its own screen if the menu isn't there)
shared.OpenArenaBlockMenu = function()
    if shared.OpenPlayerMenu then
        shared.OpenPlayerMenu("DEBUG")
        return
    end
    gui.Enabled = true
    setStatus("")
    draw()
end

local function showing()
    if mounted then
        local screen = window:FindFirstAncestorWhichIsA("ScreenGui")
        return screen ~= nil and screen.Enabled
    end
    return gui.Enabled
end

local last = 0
RunService.Heartbeat:Connect(function()
    if showing() and os.clock() - last > 0.25 then
        last = os.clock()
        draw()
    end
end)
