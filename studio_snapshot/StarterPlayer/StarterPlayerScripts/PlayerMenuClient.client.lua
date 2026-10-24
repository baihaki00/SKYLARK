--// PlayerMenuClient.client.lua
-- The player menu (G, the MENU button on the top bar, or click the clock): what you own and what's
-- coming, shown only. Actions stay at their stations (Workshop, Trainer, an arena's terminal).
--   MY QUINS   a card per slot, left to right: the Quin itself standing in its idle (QuinPreview:
--              drag to turn it), tag, temperament, gender, title, W/L and streak, condition, Bond,
--              status (Ready / In repair / Training / Entered / Fighting now), the habits revealed
--              (QuinCare "list"); empty and locked slots greyed. Cards update in place.
--   SCHEDULE   a section per arena (SkylarkArenas): what it runs now and next, your entry there
--              (shared.ArenaEntryStatus from ArenaEntry), its day strip, today and tomorrow in SST
--              with your entry or prebook marked, and the week's events. The HUD clock shows only
--              the time: everything about arenas is here.
--   WALLET     SC and the last changes this session (SkylarkWallet, remote ArenaNetwork.WalletLog).
--   LAST MATCH this session's last results (MatchResultsClient shares them), and the full card.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local QuinCore = ReplicatedStorage:WaitForChild("QuinCore")
local SkylarkTime = require(QuinCore:WaitForChild("SkylarkTime"))
local SkylarkArenas = require(QuinCore:WaitForChild("SkylarkArenas"))
local QuinPreview = require(QuinCore:WaitForChild("QuinPreview"))
local net = ReplicatedStorage:WaitForChild("ArenaNetwork")
local careRemote = net:WaitForChild("QuinCare", 30)
local walletRemote = net:WaitForChild("WalletLog", 30)

local KEY = Enum.KeyCode.G
local W, H = 1080, 680 -- (scaled down to fit a small screen)

local C_BG = Color3.fromRGB(15, 18, 26)
local C_CARD = Color3.fromRGB(22, 27, 38)
local C_STROKE = Color3.fromRGB(38, 48, 68)
local C_CYAN = Color3.fromRGB(0, 220, 255)
local C_AMBER = Color3.fromRGB(255, 180, 50)
local C_GREEN = Color3.fromRGB(0, 230, 120)
local C_RED = Color3.fromRGB(255, 60, 80)
local C_TEXT = Color3.fromRGB(240, 245, 255)
local C_MUTED = Color3.fromRGB(130, 145, 170)
local C_CARD_SEL = Color3.fromRGB(28, 36, 52)
local KIND_COLORS = { Event = C_AMBER, Open = C_CYAN, Closing = Color3.fromRGB(180, 140, 255), Rest = Color3.fromRGB(90, 100, 125) }

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
    props.TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Left
    props.TextTruncate = props.TextTruncate or Enum.TextTruncate.AtEnd
    return new("TextLabel", props)
end

local function sc(n)
    local s = tostring(math.floor(math.abs(n or 0)))
    while true do
        local k
        s, k = s:gsub("^(%d+)(%d%d%d)", "%1,%2")
        if k == 0 then
            break
        end
    end
    return s
end

local function duration(seconds)
    seconds = math.max(0, math.floor(seconds or 0))
    if seconds >= 3600 then
        return string.format("%dh %02dm", seconds // 3600, (seconds % 3600) // 60)
    elseif seconds >= 60 then
        return string.format("%dm %02ds", seconds // 60, seconds % 60)
    end
    return seconds .. "s"
end

-- ============================================================================
-- WINDOW
-- ============================================================================

local gui = new("ScreenGui", { Name = "PlayerMenuUI", Parent = playerGui, ResetOnSpawn = false, DisplayOrder = 70, Enabled = false, IgnoreGuiInset = true })
local window = new("Frame", { Name = "Window", Parent = gui, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(W, H), BackgroundColor3 = C_BG, BackgroundTransparency = 0.04 })
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
label(window, { Position = UDim2.fromOffset(18, 14), Size = UDim2.fromOffset(300, 20), Font = Enum.Font.GothamBold, TextSize = 16, TextColor3 = C_AMBER, Text = "PLAYER MENU" })
local headerRight = label(window, { Position = UDim2.fromOffset(W - 330, 16), Size = UDim2.fromOffset(270, 18), Font = Enum.Font.GothamBold, TextSize = 13, TextColor3 = C_AMBER, TextXAlignment = Enum.TextXAlignment.Right, Text = "" })
local closeButton = new("TextButton", { Name = "MenuClose", Parent = window, Text = "X", Font = Enum.Font.GothamBold, TextSize = 12, TextColor3 = C_TEXT, BackgroundColor3 = C_CARD, Position = UDim2.fromOffset(W - 44, 12), Size = UDim2.fromOffset(28, 28) })
corner(closeButton, 6)
label(window, { Position = UDim2.fromOffset(18, H - 26), Size = UDim2.fromOffset(W - 36, 16), TextSize = 11, TextColor3 = C_MUTED, Text = "G opens and closes this menu  •  repair at the Workshop, train at the Trainer, enter at an arena's terminals" })

-- DEBUG: every debug tool in one place (the arena menu, the debug buttons), for testers only:
-- in Studio, or an admin (SkylarkCanAdmin)
local TABS = { "MY QUINS", "SCHEDULE", "WALLET", "LAST MATCH", "DEBUG" }
local tabButtons = {}
local current = "MY QUINS"
local function tester()
    return RunService:IsStudio() or player:GetAttribute("SkylarkCanAdmin") == true
end
for _, name in ipairs(TABS) do
    local b = new("TextButton", { Name = "Tab" .. name:gsub(" ", ""), Parent = window, Text = name, Font = Enum.Font.GothamBold, TextSize = 12, TextColor3 = name == "DEBUG" and C_AMBER or C_TEXT, BackgroundColor3 = C_CARD, Size = UDim2.fromOffset(100, 30) })
    corner(b, 7)
    tabButtons[name] = b
end
local function layoutTabs()
    local shown = {}
    for _, name in ipairs(TABS) do
        local on = name ~= "DEBUG" or tester()
        tabButtons[name].Visible = on
        if on then
            table.insert(shown, name)
        end
    end
    local tabW = (W - 36 - (#shown - 1) * 8) / #shown
    for i, name in ipairs(shown) do
        tabButtons[name].Position = UDim2.fromOffset(18 + (i - 1) * (tabW + 8), 46)
        tabButtons[name].Size = UDim2.fromOffset(tabW, 30)
    end
    if current == "DEBUG" and not tester() then
        current = "MY QUINS"
    end
end
layoutTabs()
player:GetAttributeChangedSignal("SkylarkCanAdmin"):Connect(layoutTabs)

local content = new("ScrollingFrame", { Name = "Content", Parent = window, Position = UDim2.fromOffset(18, 86), Size = UDim2.fromOffset(W - 36, H - 120), BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 4, ScrollBarImageColor3 = C_STROKE, AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new() })
new("UIListLayout", { Parent = content, SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 8) })

local order = 0
local function clear()
    if shared.UnmountArenaBlockMenu then -- (the arena menu is lent to the DEBUG tab: give it back first)
        shared.UnmountArenaBlockMenu()
    end
    for _, c in ipairs(content:GetChildren()) do
        if c:IsA("GuiObject") then
            c:Destroy()
        end
    end
    order = 0
end

local function card(height, strokeColor)
    order += 1
    local f = new("Frame", { Parent = content, LayoutOrder = order, Size = UDim2.new(1, -8, 0, height), BackgroundColor3 = C_CARD })
    corner(f, 8)
    if strokeColor then
        new("UIStroke", { Parent = f, Color = strokeColor, Thickness = 1, Transparency = 0.4 })
    end
    return f
end

local function line(text, props)
    order += 1
    props = props or {}
    props.LayoutOrder = order
    props.Size = UDim2.new(1, -8, 0, props.height or 18)
    props.height = nil
    props.Text = text
    props.TextSize = props.TextSize or 13
    return label(content, props)
end

-- ============================================================================
-- MY QUINS
-- ============================================================================

local care = nil -- (the last QuinCare "list", and when it came)
local careAt = 0

local function fetchCare()
    if not careRemote then
        return
    end
    local ok, result = pcall(function()
        return careRemote:InvokeServer("list")
    end)
    if ok and type(result) == "table" then
        care, careAt = result, os.clock()
    end
end

local function enteredSlots()
    local list = {}
    for s in string.gmatch(player:GetAttribute("ArenaEntrySlots") or "", "%d+") do
        list[tonumber(s)] = true
    end
    return list
end

local function conditionBand(c)
    return c >= 70 and "Fresh" or (c >= 40 and "Worn" or "Battered")
end

local function bondBand(b)
    return b >= 60 and "Bonded" or (b >= 25 and "Close" or "New")
end

local function statusOf(q, entered)
    local since = os.clock() - careAt
    if q.Busy then
        local left = math.max(0, (q.Busy.Left or 0) - since)
        if q.Busy.Kind == "Repair" then
            return string.format("In repair  •  %s left", duration(left)), C_AMBER
        end
        return string.format("Training %s  •  %s left", q.Busy.Habit or "", duration(left)), C_AMBER
    end
    if entered[q.Slot] then
        if player:GetAttribute("ArenaInRound") then
            return "Fighting this round", C_RED
        end
        return player:GetAttribute("ArenaPrebooked") and "Prebooked" or "Entered", C_GREEN
    end
    return "Ready", C_GREEN
end

local GAP = 12
local SLOTS = 4
local CARD_W = math.floor((W - 36 - (SLOTS - 1) * GAP) / SLOTS)
local CARD_H = H - 120
local VIEW_H = 300

local quinsRow = new("Frame", { Name = "QuinsRow", Parent = window, Position = UDim2.fromOffset(18, 86), Size = UDim2.fromOffset(W - 36, CARD_H), BackgroundTransparency = 1, Visible = false })
local quinsLoading = label(quinsRow, { Size = UDim2.fromScale(1, 1), TextSize = 14, TextColor3 = C_MUTED, TextXAlignment = Enum.TextXAlignment.Center, Text = "Loading your Quins..." })
local quinCards = {} -- [slot] = the card's parts

local function quinCard(slot)
    local c = {}
    c.frame = new("Frame", { Name = "QuinCard" .. slot, Parent = quinsRow, Position = UDim2.fromOffset((slot - 1) * (CARD_W + GAP), 0), Size = UDim2.fromOffset(CARD_W, CARD_H), BackgroundColor3 = C_CARD })
    corner(c.frame, 10)
    c.stroke = new("UIStroke", { Parent = c.frame, Color = C_STROKE, Thickness = 1.5, Transparency = 0.3 })
    c.view = new("ViewportFrame", { Name = "Preview", Parent = c.frame, Position = UDim2.fromOffset(8, 8), Size = UDim2.fromOffset(CARD_W - 16, VIEW_H), BackgroundColor3 = Color3.new(1, 1, 1) })
    corner(c.view, 8)
    new("UIGradient", { Parent = c.view, Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(52, 62, 86), Color3.fromRGB(16, 20, 30)) })
    c.slotTag = label(c.frame, { Position = UDim2.fromOffset(18, 14), Size = UDim2.fromOffset(120, 16), Font = Enum.Font.GothamBold, TextSize = 11, TextColor3 = C_MUTED, ZIndex = 3, Text = "SLOT " .. slot })
    c.big = label(c.frame, { Position = UDim2.fromOffset(8, 8), Size = UDim2.fromOffset(CARD_W - 16, VIEW_H), Font = Enum.Font.GothamBold, TextSize = 18, TextColor3 = C_MUTED, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 3, Text = "" })
    local strip = new("Frame", { Parent = c.frame, Position = UDim2.fromOffset(CARD_W - 140, 14), Size = UDim2.fromOffset(126, 22), BackgroundColor3 = C_BG, BackgroundTransparency = 0.25, BorderSizePixel = 0, ZIndex = 3 })
    corner(strip, 11)
    c.strip = strip
    c.status = label(strip, { Size = UDim2.fromScale(1, 1), Font = Enum.Font.GothamBold, TextSize = 11, TextTruncate = Enum.TextTruncate.AtEnd, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 4, Text = "" })
    local y = VIEW_H + 16
    c.name = label(c.frame, { Position = UDim2.fromOffset(14, y), Size = UDim2.fromOffset(CARD_W - 28, 22), Font = Enum.Font.GothamBold, TextSize = 18, Text = "" })
    c.temper = label(c.frame, { Position = UDim2.fromOffset(14, y + 24), Size = UDim2.fromOffset(CARD_W - 28, 18), Font = Enum.Font.GothamBold, TextSize = 14, TextColor3 = C_AMBER, Text = "" })
    c.info = label(c.frame, { Position = UDim2.fromOffset(14, y + 44), Size = UDim2.fromOffset(CARD_W - 28, 16), TextSize = 12, TextColor3 = C_MUTED, Text = "" })
    c.record = label(c.frame, { Position = UDim2.fromOffset(14, y + 62), Size = UDim2.fromOffset(CARD_W - 28, 16), TextSize = 12, Text = "" })
    local function bar(at)
        local text = label(c.frame, { Position = UDim2.fromOffset(14, at), Size = UDim2.fromOffset(CARD_W - 28, 14), Font = Enum.Font.GothamBold, TextSize = 11, TextColor3 = C_MUTED, Text = "" })
        local track = new("Frame", { Parent = c.frame, Position = UDim2.fromOffset(14, at + 17), Size = UDim2.fromOffset(CARD_W - 28, 6), BackgroundColor3 = C_STROKE, BorderSizePixel = 0 })
        corner(track, 3)
        local fill = new("Frame", { Parent = track, Size = UDim2.fromScale(0, 1), BorderSizePixel = 0, BackgroundColor3 = C_GREEN })
        corner(fill, 3)
        return { text = text, track = track, fill = fill }
    end
    c.cond = bar(y + 88)
    c.bond = bar(y + 118)
    c.habits = label(c.frame, { Position = UDim2.fromOffset(14, y + 150), Size = UDim2.fromOffset(CARD_W - 28, CARD_H - y - 160), TextSize = 12, TextWrapped = true,
        TextTruncate = Enum.TextTruncate.None, TextYAlignment = Enum.TextYAlignment.Top, Text = "" })
    -- drag the Quin to turn it
    c.yaw = 200
    local dragging, lastX = false, 0
    c.view.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging, lastX = true, input.Position.X
        end
    end)
    c.view.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)
    UserInputService.InputEnded:Connect(function(input) -- (released outside the card)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if dragging and c.preview and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            c.yaw += (input.Position.X - lastX) * 0.8 -- (Delta stays zero for a free mouse)
            lastX = input.Position.X
            c.preview.setYaw(c.yaw)
        end
    end)
    return c
end

local function setPreview(c, q)
    local key = q and (q.Tag .. ":" .. tostring(q.Gender)) or nil
    if c.previewKey == key then
        return
    end
    if c.preview then
        c.preview.destroy()
        c.preview = nil
    end
    c.previewKey = key
    if q then
        c.yaw = 200
        c.preview = QuinPreview.mount(c.view, { Gender = q.Gender })
    end
end

local function drawQuins()
    quinsLoading.Visible = care == nil
    if not care then
        return
    end
    local entered = enteredSlots()
    local bySlot = {}
    for _, q in ipairs(care.Quins or {}) do
        bySlot[q.Slot] = q
    end
    for slot = 1, SLOTS do
        local c = quinCards[slot] or quinCard(slot)
        quinCards[slot] = c
        local q = bySlot[slot]
        local locked = slot > (care.Unlocked or 2)
        setPreview(c, (not locked) and q or nil)
        local shown = q ~= nil and not locked
        for _, part in ipairs({ c.name, c.temper, c.info, c.record, c.habits, c.strip, c.cond.text, c.cond.track, c.bond.text, c.bond.track }) do
            part.Visible = shown
        end
        c.frame.BackgroundTransparency = shown and 0 or 0.5
        if not shown then
            c.big.Text = locked and "LOCKED" or "EMPTY SLOT"
            c.stroke.Color = C_STROKE
        else
            c.big.Text = ""
            local status, statusColor = statusOf(q, entered)
            c.status.Text = status
            c.status.TextColor3 = statusColor
            c.stroke.Color = statusColor
            c.name.Text = "Quin #" .. q.Tag
            c.temper.Text = q.Temperament or ""
            c.info.Text = string.format("%s  •  %s", q.Gender or "?", q.Title or "Rookie")
            local streak = (q.Streak or 0) >= 2 and string.format("  •  %d-win streak", q.Streak) or ""
            c.record.Text = string.format("W%d  L%d%s", q.Wins or 0, q.Losses or 0, streak)
            local cond = q.Condition or 100
            c.cond.text.Text = string.format("CONDITION  %d%%  %s", cond, conditionBand(cond))
            c.cond.fill.Size = UDim2.fromScale(math.clamp(cond / 100, 0, 1), 1)
            c.cond.fill.BackgroundColor3 = cond >= 70 and C_GREEN or (cond >= 40 and C_AMBER or C_RED)
            local bond = q.Bond or 0
            c.bond.text.Text = string.format("BOND  %d  %s", bond, bondBand(bond))
            c.bond.fill.Size = UDim2.fromScale(math.clamp(bond / 100, 0, 1), 1)
            c.bond.fill.BackgroundColor3 = C_CYAN
            local known = {}
            for _, h in ipairs(q.Habits or {}) do
                if h.Band then
                    table.insert(known, h.Name .. " " .. h.Band .. (h.Trend == 1 and " ↑" or (h.Trend == -1 and " ↓" or "")))
                end
            end
            c.habits.TextColor3 = #known > 0 and C_CYAN or C_MUTED
            c.habits.Text = #known > 0 and ("KNOWN HABITS\n" .. table.concat(known, ", "))
                or "Habits unknown: fights reveal them, or an appraisal at the Quin Specialist"
        end
    end
end

-- ============================================================================
-- SCHEDULE
-- ============================================================================

-- How long until Skylark time `t`: real time at the clock's speed; Skylark hours while paused
local function untilText(t)
    local real = SkylarkTime.realSecondsUntil(t)
    if real then
        return duration(real)
    end
    return SkylarkTime.formatDuration((t - SkylarkTime.now()) / SkylarkTime.HOUR * 3600) .. " SST"
end

local function drawArena(arena, now, info)
    local schedule = arena.Schedule
    local debugOn = SkylarkTime.isDebug()
    local slot = schedule.slotAt(now)
    local nextEvent = schedule.nextEvent(now)

    -- what it runs now and next, your entry, the day strip
    local head = card(112, C_AMBER)
    label(head, { Position = UDim2.fromOffset(16, 10), Size = UDim2.fromOffset(400, 22), Font = Enum.Font.GothamBlack, TextSize = 17, TextColor3 = C_AMBER, Text = string.upper(arena.Name) })
    local status = arena.Live and shared.ArenaEntryStatus
    if status and status.Arena == arena.Id and status.Text ~= "" then
        label(head, { Position = UDim2.fromOffset(W - 470, 10), Size = UDim2.fromOffset(420, 22), Font = Enum.Font.GothamBold, TextSize = 12, TextColor3 = status.Color or C_TEXT,
            TextXAlignment = Enum.TextXAlignment.Right, Text = status.Text })
    elseif not arena.Live then
        label(head, { Position = UDim2.fromOffset(W - 470, 10), Size = UDim2.fromOffset(420, 22), TextSize = 12, TextColor3 = C_MUTED, TextXAlignment = Enum.TextXAlignment.Right, Text = "Not on this server" })
    end
    local left = untilText(slot.EndsAt)
    local nowText
    if slot.Kind == "Event" then
        nowText = string.format("LIVE  %s%s  •  %s left", string.upper(slot.Name), slot.Tagline and ("  •  " .. slot.Tagline) or "", left)
    elseif slot.Kind == "Rest" then
        nowText = string.format("REST  •  no events, open for training and spectating  •  %s left", left)
    else
        nowText = string.format("%s%s  •  %s left", string.upper(slot.Name), slot.Tagline and ("  •  " .. slot.Tagline) or "", left)
    end
    label(head, { Position = UDim2.fromOffset(16, 36), Size = UDim2.fromOffset(W - 80, 20), Font = Enum.Font.GothamBold, TextSize = 14,
        TextColor3 = slot.Kind == "Rest" and C_MUTED or KIND_COLORS[slot.Kind], Text = nowText })
    label(head, { Position = UDim2.fromOffset(16, 58), Size = UDim2.fromOffset(W - 80, 16), TextSize = 12, TextColor3 = C_MUTED,
        Text = nextEvent and string.format("Next event: %s in %s", nextEvent.Name, untilText(nextEvent.StartsAt)) or "" })
    local stripW = W - 36 - 8 - 32
    local strip = new("Frame", { Parent = head, Position = UDim2.fromOffset(16, 84), Size = UDim2.fromOffset(stripW, 10), BackgroundColor3 = C_BG, BorderSizePixel = 0 })
    corner(strip, 3)
    for _, entry in ipairs(schedule.DAILY) do
        new("Frame", { Parent = strip, Position = UDim2.new(entry.From / 24, 1, 0, 1), Size = UDim2.new((entry.To - entry.From) / 24, -2, 1, -2),
            BackgroundColor3 = KIND_COLORS[entry.Kind], BackgroundTransparency = 0.35, BorderSizePixel = 0 })
    end
    new("Frame", { Parent = strip, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(info.Hours / 24, 0, 0.5, 0), Size = UDim2.fromOffset(2, 16), BackgroundColor3 = C_TEXT, BorderSizePixel = 0, ZIndex = 2 })
    for h = 0, 24, 6 do
        label(head, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(16 + stripW * h / 24, 96), Size = UDim2.fromOffset(30, 12), TextSize = 10, TextColor3 = C_MUTED,
            TextXAlignment = Enum.TextXAlignment.Center, Text = string.format("%02d", h) })
    end

    -- today and tomorrow
    local entered = status and status.Arena == arena.Id
    local entryWindow = entered and player:GetAttribute("ArenaEntered") and Workspace:GetAttribute("ArenaRegWindow")
    local prebookEvent = entered and player:GetAttribute("ArenaPrebooked") and Workspace:GetAttribute("ArenaPrebookEvent")
    local function drawDay(day, title)
        line(title, { Font = Enum.Font.GothamBold, TextSize = 12, TextColor3 = C_CYAN, height = 20 })
        for _, daySlot in ipairs(schedule.day(day)) do
            if daySlot.EndsAt > now then
                local live = now >= daySlot.StartsAt
                local isEvent = daySlot.Kind == "Event"
                local mine = isEvent and (daySlot.Name == entryWindow and live or daySlot.Name == prebookEvent and not live)
                local f = card(44, live and C_AMBER or (mine and C_GREEN or nil))
                new("Frame", { Parent = f, Size = UDim2.new(0, 3, 1, 0), BorderSizePixel = 0, BackgroundColor3 = KIND_COLORS[daySlot.Kind] })
                label(f, { Position = UDim2.fromOffset(14, 0), Size = UDim2.fromOffset(110, 44), Font = Enum.Font.GothamBold, TextSize = 13, TextColor3 = live and C_AMBER or C_TEXT,
                    Text = string.format("%s-%s", SkylarkTime.formatHours(daySlot.From), SkylarkTime.formatHours(daySlot.To)) })
                label(f, { Position = UDim2.fromOffset(130, 5), Size = UDim2.fromOffset(420, 18), Font = isEvent and Enum.Font.GothamBold or Enum.Font.Gotham, TextSize = 13,
                    TextColor3 = isEvent and C_TEXT or C_MUTED, Text = daySlot.Name .. (daySlot.Tagline and ("  •  " .. daySlot.Tagline) or "") })
                local yourTime = debugOn and "" or ("  •  " .. DateTime.fromUnixTimestamp(math.floor(daySlot.StartsAt)):FormatLocalTime("HH:mm", "en-us") .. " your time")
                local when = live and string.format("LIVE  •  ends in %s", untilText(daySlot.EndsAt)) or string.format("starts in %s%s", untilText(daySlot.StartsAt), yourTime)
                label(f, { Position = UDim2.fromOffset(130, 23), Size = UDim2.fromOffset(420, 16), TextSize = 11, TextColor3 = C_MUTED, Text = when })
                if mine then
                    label(f, { Position = UDim2.fromOffset(W - 240, 0), Size = UDim2.fromOffset(190, 44), Font = Enum.Font.GothamBold, TextSize = 12, TextColor3 = C_GREEN,
                        TextXAlignment = Enum.TextXAlignment.Right, Text = live and "YOU'RE ENTERED" or "PREBOOKED" })
                end
            end
        end
    end
    drawDay(info.Day, "TODAY")
    drawDay(info.Day + 1, "TOMORROW")

    -- the week's events
    local events = {}
    for index, entry in ipairs(schedule.DAILY) do
        if entry.Kind == "Event" then
            table.insert(events, { index = index, entry = entry })
        end
    end
    if #events == 0 then
        return
    end
    line("THIS WEEK", { Font = Enum.Font.GothamBold, TextSize = 12, TextColor3 = C_CYAN, height = 20 })
    local LABEL_W, ROW = 100, 40
    local week = card(28 + #events * ROW + 8)
    local colW = math.floor((W - 36 - 8 - 28 - LABEL_W) / 7)
    for d = 1, 7 do
        label(week, { Position = UDim2.fromOffset(14 + LABEL_W + (d - 1) * colW, 6), Size = UDim2.fromOffset(colW - 4, 18), Font = Enum.Font.GothamBold, TextSize = 11,
            TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = d == info.Weekday and C_AMBER or C_MUTED, Text = SkylarkTime.WEEKDAYS[d] })
    end
    local slotNow = schedule.slotAt(now)
    for r, e in ipairs(events) do
        local y = 28 + (r - 1) * ROW
        label(week, { Position = UDim2.fromOffset(14, y), Size = UDim2.fromOffset(LABEL_W - 8, ROW - 4), Font = Enum.Font.GothamBold, TextSize = 11, TextColor3 = C_MUTED,
            Text = string.format("%s-%s", SkylarkTime.formatHours(e.entry.From), SkylarkTime.formatHours(e.entry.To)) })
        for d = 1, 7 do
            local isNow = d == info.Weekday and slotNow.Index == e.index
            local cell = new("TextLabel", { Parent = week, Position = UDim2.fromOffset(14 + LABEL_W + (d - 1) * colW, y), Size = UDim2.fromOffset(colW - 4, ROW - 4),
                BackgroundColor3 = isNow and Color3.fromRGB(70, 55, 20) or (d == info.Weekday and C_CARD_SEL or C_BG), BorderSizePixel = 0, Font = Enum.Font.Gotham, TextSize = 11,
                TextWrapped = true, TextColor3 = isNow and C_AMBER or C_TEXT, Text = schedule.EVENTS[e.entry.Slot][d].Name })
            corner(cell, 4)
        end
    end
end

local function drawSchedule()
    local now = SkylarkTime.now()
    local info = SkylarkTime.info(now)
    local paused = SkylarkTime.isDebug() and SkylarkTime.rate() <= 0
    line(string.format("%s  •  %s day %d, Year %d  •  SST %s%s", info.WeekdayName or "", info.Season or "", info.SeasonDay or 0, info.Year or 1,
        SkylarkTime.formatHours(info.Hours), paused and "  •  clock paused (debug)" or ""), { Font = Enum.Font.GothamBold, TextSize = 13, TextColor3 = C_MUTED })
    for _, arena in ipairs(SkylarkArenas.list()) do
        drawArena(arena, now, info)
    end
    line("1 Skylark day = 8 real hours  •  events run rounds all window long  •  Rest stops events, not the arena", { TextSize = 11, TextColor3 = C_MUTED })
end

-- ============================================================================
-- WALLET
-- ============================================================================

local walletLog = nil

local function fetchWallet()
    if not walletRemote then
        return
    end
    local ok, result = pcall(function()
        return walletRemote:InvokeServer()
    end)
    if ok and type(result) == "table" then
        walletLog = result
    end
end

local function drawWallet()
    local f = card(56, C_AMBER)
    label(f, { Position = UDim2.fromOffset(14, 0), Size = UDim2.fromOffset(300, 56), Font = Enum.Font.GothamBlack, TextSize = 24, TextColor3 = C_AMBER,
        Text = "SC  " .. sc(player:GetAttribute("SC") or 0) })
    label(f, { Position = UDim2.fromOffset(W - 330, 0), Size = UDim2.fromOffset(280, 56), TextSize = 11, TextColor3 = C_MUTED, TextXAlignment = Enum.TextXAlignment.Right,
        Text = "Skylark Coin: earned in the arena, never sold" })
    line("THIS SESSION", { Font = Enum.Font.GothamBold, TextSize = 12, TextColor3 = C_CYAN, height = 20 })
    if not walletLog or #walletLog == 0 then
        line("No SC in or out yet this session.", { TextColor3 = C_MUTED })
        return
    end
    for _, e in ipairs(walletLog) do
        local row = card(30)
        label(row, { Position = UDim2.fromOffset(14, 0), Size = UDim2.fromOffset(60, 30), TextSize = 11, TextColor3 = C_MUTED, Text = os.date("%H:%M", e.t) })
        label(row, { Position = UDim2.fromOffset(74, 0), Size = UDim2.fromOffset(360, 30), TextSize = 12, Text = e.reason })
        label(row, { Position = UDim2.fromOffset(W - 260, 0), Size = UDim2.fromOffset(100, 30), Font = Enum.Font.GothamBold, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Right,
            TextColor3 = e.amount >= 0 and C_GREEN or C_RED, Text = (e.amount >= 0 and "+" or "-") .. sc(e.amount) })
        label(row, { Position = UDim2.fromOffset(W - 150, 0), Size = UDim2.fromOffset(100, 30), TextSize = 11, TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = C_MUTED,
            Text = sc(e.balance) })
    end
end

-- ============================================================================
-- LAST MATCH
-- ============================================================================

local function drawMatch()
    local r = shared.LastMatch
    if not r then
        line("No match yet this session. Your Quins' results show here after a round.", { TextColor3 = C_MUTED, height = 20 })
        return
    end
    line("MATCH  •  " .. tostring(r.Winner or ""), { Font = Enum.Font.GothamBold, TextSize = 15, height = 22 })
    line(tostring(r.Reason or ""), { TextSize = 12, TextColor3 = C_MUTED })
    for _, q in ipairs(r.Quins or {}) do
        local good = q.Outcome == "Win"
        local f = card(44, good and C_GREEN or (q.Outcome == "Loss" and C_RED or nil))
        label(f, { Position = UDim2.fromOffset(14, 0), Size = UDim2.fromOffset(360, 44), Font = Enum.Font.GothamBold, TextSize = 13,
            TextColor3 = good and C_GREEN or (q.Outcome == "Loss" and C_RED or C_TEXT),
            Text = string.format("Quin #%s  •  %s%s", q.Tag, string.upper(q.Outcome or ""), q.Survived and "  •  survived" or "") })
        label(f, { Position = UDim2.fromOffset(W - 300, 0), Size = UDim2.fromOffset(250, 44), Font = Enum.Font.GothamBold, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Right,
            TextColor3 = C_AMBER, Text = string.format("%d / 1000  •  %s SC", q.Score or 0, sc(q.Pay)) })
    end
    line(string.format("Entry -%s SC  •  Earned +%s SC", sc(r.Fee), sc(r.Earned)), { TextSize = 13, height = 20 })
    line(string.format("NET %s%s SC", (r.Net or 0) >= 0 and "+" or "-", sc(r.Net)), { Font = Enum.Font.GothamBlack, TextSize = 18, height = 24,
        TextColor3 = (r.Net or 0) >= 0 and C_GREEN or C_RED })
    if shared.ShowMatchCard then
        order += 1
        local b = new("TextButton", { Name = "OpenMatchCard", Parent = content, LayoutOrder = order, Text = "OPEN THE FULL RESULTS CARD", Font = Enum.Font.GothamBold, TextSize = 12,
            TextColor3 = C_BG, BackgroundColor3 = C_AMBER, Size = UDim2.new(1, -8, 0, 32) })
        corner(b, 8)
        b.MouseButton1Click:Connect(function()
            gui.Enabled = false
            shared.ShowMatchCard(r)
        end)
    end
end

-- ============================================================================
-- SHOW / HIDE
-- ============================================================================

-- DEBUG: the switches, then the arena menu itself (ArenaBlockMenu.client lends its window)
local function drawDebug()
    local tools = card(204, C_AMBER)
    label(tools, { Position = UDim2.fromOffset(16, 10), Size = UDim2.fromOffset(300, 18), Font = Enum.Font.GothamBold, TextSize = 14, TextColor3 = C_AMBER, Text = "DEBUG TOOLS" })
    label(tools, { Position = UDim2.fromOffset(16, 32), Size = UDim2.fromOffset(520, 16), TextSize = 12, TextColor3 = C_MUTED,
        Text = "Testers only (Studio or admins). Role now: " .. tostring(player:GetAttribute("SkylarkRole") or "?") })
    local on = player:GetAttribute("ShowDebugButtons") == true
    local f8 = new("TextButton", { Name = "DebugButtonsToggle", Parent = tools, Position = UDim2.new(1, -276, 0, 14), Size = UDim2.fromOffset(260, 36),
        Text = "DEBUG BUTTONS (F8):  " .. (on and "ON" or "OFF"), Font = Enum.Font.GothamBold, TextSize = 12,
        BackgroundColor3 = on and C_AMBER or C_BG, TextColor3 = on and C_BG or C_TEXT })
    corner(f8, 7)
    f8.MouseButton1Click:Connect(function()
        player:SetAttribute("ShowDebugButtons", not on or nil)
        shared.OpenPlayerMenu("DEBUG") -- (draws the tab again)
    end)
    -- NPC owners in the event's queue (ArenaRegistration): the switch and what they're doing
    local npcOn = Workspace:GetAttribute("ArenaNpcOwners") ~= false
    label(tools, { Position = UDim2.fromOffset(16, 66), Size = UDim2.fromOffset(700, 16), Font = Enum.Font.GothamBold, TextSize = 12, TextColor3 = C_TEXT,
        Text = "NPC OWNERS  •  " .. (npcOn and (Workspace:GetAttribute("ArenaNpcQueue") or "no event") or "off: the arena's own Quins fill empty seats") })
    label(tools, { Position = UDim2.fromOffset(16, 84), Size = UDim2.fromOffset(700, 16), TextSize = 11, TextColor3 = C_MUTED,
        Text = "They prebook and walk in like players; players are always seated first and bump the newest NPC owner." })
    local npcButton = new("TextButton", { Name = "NpcOwnersToggle", Parent = tools, Position = UDim2.new(1, -276, 0, 62), Size = UDim2.fromOffset(260, 36),
        Text = "NPC OWNERS:  " .. (npcOn and "ON" or "OFF"), Font = Enum.Font.GothamBold, TextSize = 12,
        BackgroundColor3 = npcOn and C_AMBER or C_BG, TextColor3 = npcOn and C_BG or C_TEXT })
    corner(npcButton, 7)
    npcButton.MouseButton1Click:Connect(function()
        local remote = net:FindFirstChild("ArenaBlockDebug")
        if remote then
            pcall(function()
                remote:InvokeServer("npcowners", not npcOn)
            end)
        end
        shared.OpenPlayerMenu("DEBUG")
    end)
    -- the lines at the terminals (ArenaTerminalQueue): who's in them, and do players skip them
    local skipOn = Workspace:GetAttribute("ArenaQueueSkip") ~= false
    label(tools, { Position = UDim2.fromOffset(16, 112), Size = UDim2.fromOffset(700, 16), Font = Enum.Font.GothamBold, TextSize = 12, TextColor3 = C_TEXT,
        Text = "TERMINAL LINES  •  " .. tostring(Workspace:GetAttribute("ArenaQueueBodies") or "none") })
    label(tools, { Position = UDim2.fromOffset(16, 130), Size = UDim2.fromOffset(700, 16), TextSize = 11, TextColor3 = C_MUTED,
        Text = skipOn and "Players skip the line: at a terminal you're served first, the NPC owner at the front waits."
            or "Players queue: walk up to a terminal to join its line; you can register only at the front." })
    local skipButton = new("TextButton", { Name = "QueueSkipToggle", Parent = tools, Position = UDim2.new(1, -276, 0, 108), Size = UDim2.fromOffset(260, 36),
        Text = "PLAYERS SKIP NPC QUEUE:  " .. (skipOn and "ON" or "OFF"), Font = Enum.Font.GothamBold, TextSize = 12,
        BackgroundColor3 = skipOn and C_AMBER or C_BG, TextColor3 = skipOn and C_BG or C_TEXT })
    corner(skipButton, 7)
    skipButton.MouseButton1Click:Connect(function()
        local remote = net:FindFirstChild("ArenaBlockDebug")
        if remote then
            pcall(function()
                remote:InvokeServer("queueskip", not skipOn)
            end)
        end
        shared.OpenPlayerMenu("DEBUG")
    end)
    -- the arena's grounds (ArenaRegistration: registered owners must be inside): draw the ring
    local ringOn = player:GetAttribute("ShowArenaBoundary") == true
    local radius = Workspace:GetAttribute("ArenaBoundaryRadius")
    label(tools, { Position = UDim2.fromOffset(16, 160), Size = UDim2.fromOffset(700, 16), Font = Enum.Font.GothamBold, TextSize = 12, TextColor3 = C_TEXT,
        Text = "ARENA GROUNDS  •  " .. (radius and string.format("a circle of %d studs round the arena ground", math.floor(radius + 0.5)) or "no ArenaGround found")
            .. (player:GetAttribute("ArenaOutside") and "  •  YOU'RE OUTSIDE" or "") })
    label(tools, { Position = UDim2.fromOffset(16, 178), Size = UDim2.fromOffset(700, 16), TextSize = 11, TextColor3 = C_MUTED,
        Text = "Registered owners must be inside when each round starts, and stay while the event is on." })
    local ringButton = new("TextButton", { Name = "BoundaryToggle", Parent = tools, Position = UDim2.new(1, -276, 0, 156), Size = UDim2.fromOffset(260, 36),
        Text = "SHOW ARENA GROUNDS:  " .. (ringOn and "ON" or "OFF"), Font = Enum.Font.GothamBold, TextSize = 12,
        BackgroundColor3 = ringOn and C_AMBER or C_BG, TextColor3 = ringOn and C_BG or C_TEXT })
    corner(ringButton, 7)
    ringButton.MouseButton1Click:Connect(function()
        player:SetAttribute("ShowArenaBoundary", not ringOn or nil) -- (ArenaEntry.client draws it, on this machine only)
        shared.OpenPlayerMenu("DEBUG")
    end)
    order += 1
    local holder = new("Frame", { Name = "ArenaMenuHolder", Parent = content, LayoutOrder = order, Size = UDim2.fromOffset(920, 776), BackgroundTransparency = 1 })
    if shared.MountArenaBlockMenu then
        shared.MountArenaBlockMenu(holder)
    else
        holder.Size = UDim2.new(1, -8, 0, 30)
        label(holder, { Size = UDim2.fromScale(1, 1), TextSize = 13, TextColor3 = C_RED, Text = "The arena menu isn't loaded" })
    end
end

local DRAW = { ["MY QUINS"] = drawQuins, SCHEDULE = drawSchedule, WALLET = drawWallet, ["LAST MATCH"] = drawMatch, DEBUG = drawDebug }

local function redraw()
    if not gui.Enabled then
        return
    end
    local y = content.CanvasPosition
    clear()
    local quinsTab = current == "MY QUINS"
    quinsRow.Visible = quinsTab -- (the cards stay built: their Quins keep standing in their idle)
    content.Visible = not quinsTab
    for name, b in pairs(tabButtons) do
        local on = name == current
        b.BackgroundColor3 = on and C_AMBER or C_CARD
        b.TextColor3 = on and C_BG or C_TEXT
    end
    headerRight.Text = "SC " .. sc(player:GetAttribute("SC") or 0)
    DRAW[current]()
    content.CanvasPosition = y
end

local function refresh()
    if current == "MY QUINS" then
        fetchCare()
    elseif current == "WALLET" then
        fetchWallet()
    end
    redraw()
end

-- The scroll wheel belongs to the menu while it's open: Roblox's own camera is held at its distance
-- (SmoothCamera's camera ignores the wheel under any menu itself)
local heldZoom = nil -- { min, max } to give back
local function holdZoom(hold)
    if hold and not heldZoom then
        local camera = Workspace.CurrentCamera
        local distance = camera and (camera.CFrame.Position - camera.Focus.Position).Magnitude or player.CameraMaxZoomDistance
        heldZoom = { player.CameraMinZoomDistance, player.CameraMaxZoomDistance }
        distance = math.clamp(distance, heldZoom[1], heldZoom[2])
        player.CameraMaxZoomDistance = distance
        player.CameraMinZoomDistance = distance
    elseif not hold and heldZoom then
        player.CameraMinZoomDistance = heldZoom[1]
        player.CameraMaxZoomDistance = heldZoom[2]
        heldZoom = nil
    end
end

local function setOpen(open)
    gui.Enabled = open
    holdZoom(open)
    if open then
        content.CanvasPosition = Vector2.zero
        task.spawn(refresh)
    end
end

for name, b in pairs(tabButtons) do
    b.MouseButton1Click:Connect(function()
        current = name
        content.CanvasPosition = Vector2.zero
        task.spawn(refresh)
    end)
end
closeButton.MouseButton1Click:Connect(function()
    setOpen(false)
end)

UserInputService.InputBegan:Connect(function(input, processed)
    if processed or UserInputService:GetFocusedTextBox() then
        return
    end
    if input.KeyCode == KEY then
        setOpen(not gui.Enabled)
    end
end)

-- other scripts open it on a tab (the clock opens SCHEDULE)
shared.OpenPlayerMenu = function(tab)
    if tab and DRAW[tab] and (tab ~= "DEBUG" or tester()) then
        current = tab
    end
    setOpen(true)
end
shared.ClosePlayerMenu = function()
    setOpen(false)
end

-- the MENU button on the top bar (SkylarkClockUI.TopBar, LayoutOrder 1). Its dot: you're entered,
-- prebooked or fighting somewhere (shared.ArenaEntryStatus.Active): the details are in SCHEDULE.
local menuDot = nil
task.spawn(function()
    local clock = playerGui:WaitForChild("SkylarkClockUI", 30)
    local bar = clock and clock:WaitForChild("TopBar", 30)
    if not bar then
        return
    end
    local b = new("TextButton", { Name = "MenuButton", Parent = bar, LayoutOrder = 1, Size = UDim2.fromOffset(110, 44),
        Text = "MENU  (G)", Font = Enum.Font.GothamBold, TextSize = 13, TextColor3 = C_AMBER, BackgroundColor3 = C_BG, BackgroundTransparency = 0.12 })
    corner(b, 22)
    new("UIStroke", { Parent = b, Color = C_STROKE, Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border })
    menuDot = new("Frame", { Name = "Dot", Parent = b, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(1, -10, 0, 10), Size = UDim2.fromOffset(10, 10),
        BackgroundColor3 = C_GREEN, BorderSizePixel = 0, Visible = false })
    corner(menuDot, 5)
    b.MouseButton1Click:Connect(function()
        setOpen(not gui.Enabled)
    end)
end)

-- open: timers tick every second, the data comes again every 5 s
task.spawn(function()
    local n = 0
    while true do
        task.wait(1)
        if menuDot then
            local st = shared.ArenaEntryStatus
            menuDot.Visible = st ~= nil and st.Active == true
            menuDot.BackgroundColor3 = st and st.Color or C_GREEN
        end
        if gui.Enabled and current ~= "DEBUG" then -- (the arena menu ticks by itself)
            n += 1
            if n % 5 == 0 then
                refresh()
            elseif current == "MY QUINS" or current == "SCHEDULE" then -- (their timers)
                redraw()
            end
        end
    end
end)
player:GetAttributeChangedSignal("SC"):Connect(function()
    if gui.Enabled and current == "WALLET" then
        task.spawn(refresh)
    end
end)

-- test hook: player attribute PlayerMenuOpen (true / tab name) opens it
player:GetAttributeChangedSignal("PlayerMenuOpen"):Connect(function()
    local v = player:GetAttribute("PlayerMenuOpen")
    if v == nil then
        return
    end
    player:SetAttribute("PlayerMenuOpen", nil)
    if type(v) == "string" and DRAW[v] then
        current = v
    end
    setOpen(v ~= false)
end)
