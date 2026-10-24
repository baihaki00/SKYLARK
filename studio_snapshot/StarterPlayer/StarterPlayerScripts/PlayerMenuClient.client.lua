--// PlayerMenuClient.client.lua
-- The player menu (G, or the MENU button under the SC pill): what you own and what's coming, shown
-- only. Actions stay at their stations (Workshop, Trainer, Arena Terminal).
--   MY QUINS   a card per slot, left to right: the Quin itself standing in its idle (QuinPreview:
--              drag to turn it), tag, temperament, gender, title, W/L and streak, condition, Bond,
--              status (Ready / In repair / Training / Entered / Fighting now), the habits revealed
--              (QuinCare "list"); empty and locked slots greyed. Cards update in place.
--   SCHEDULE   today's arena day (ArenaSchedule) in SST, with your entry or prebook marked.
--   WALLET     SC and the last changes this session (SkylarkWallet, remote ArenaNetwork.WalletLog).
--   LAST MATCH this session's last results (MatchResultsClient shares them), and the full card.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local QuinCore = ReplicatedStorage:WaitForChild("QuinCore")
local SkylarkTime = require(QuinCore:WaitForChild("SkylarkTime"))
local ArenaSchedule = require(QuinCore:WaitForChild("ArenaSchedule"))
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
label(window, { Position = UDim2.fromOffset(18, H - 26), Size = UDim2.fromOffset(W - 36, 16), TextSize = 11, TextColor3 = C_MUTED, Text = "G opens and closes this menu  •  repair at the Workshop, train at the Trainer, enter at an Arena Terminal" })

local TABS = { "MY QUINS", "SCHEDULE", "WALLET", "LAST MATCH" }
local tabButtons = {}
local current = "MY QUINS"
local tabW = (W - 36 - 3 * 8) / 4
for i, name in ipairs(TABS) do
    local b = new("TextButton", { Name = "Tab" .. name:gsub(" ", ""), Parent = window, Text = name, Font = Enum.Font.GothamBold, TextSize = 12, TextColor3 = C_TEXT, BackgroundColor3 = C_CARD, Position = UDim2.fromOffset(18 + (i - 1) * (tabW + 8), 46), Size = UDim2.fromOffset(tabW, 30) })
    corner(b, 7)
    tabButtons[name] = b
end

local content = new("ScrollingFrame", { Name = "Content", Parent = window, Position = UDim2.fromOffset(18, 86), Size = UDim2.fromOffset(W - 36, H - 120), BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 4, ScrollBarImageColor3 = C_STROKE, AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new() })
new("UIListLayout", { Parent = content, SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 8) })

local order = 0
local function clear()
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

local function drawSchedule()
    local now = SkylarkTime.now()
    local info = SkylarkTime.info(now)
    local entryWindow = player:GetAttribute("ArenaEntered") and Workspace:GetAttribute("ArenaRegWindow")
    local prebookEvent = player:GetAttribute("ArenaPrebooked") and Workspace:GetAttribute("ArenaPrebookEvent")
    line(string.format("%s  •  %s day %d  •  SST %s", info.WeekdayName or "", info.Season or "", info.SeasonDay or 0, SkylarkTime.formatHours(info.Hours)),
        { Font = Enum.Font.GothamBold, TextSize = 13, TextColor3 = C_MUTED })
    local function drawDay(day, title)
        line(title, { Font = Enum.Font.GothamBold, TextSize = 12, TextColor3 = C_CYAN, height = 20 })
        for _, slot in ipairs(ArenaSchedule.day(day)) do
            if slot.EndsAt > now then
                local live = now >= slot.StartsAt
                local isEvent = slot.Kind == "Event"
                local mine = isEvent and (slot.Name == entryWindow and live or slot.Name == prebookEvent and not live)
                local f = card(44, live and C_AMBER or (mine and C_GREEN or nil))
                label(f, { Position = UDim2.fromOffset(14, 0), Size = UDim2.fromOffset(110, 44), Font = Enum.Font.GothamBold, TextSize = 13, TextColor3 = live and C_AMBER or C_TEXT,
                    Text = string.format("%s-%s", SkylarkTime.formatHours(slot.From), SkylarkTime.formatHours(slot.To)) })
                label(f, { Position = UDim2.fromOffset(130, 5), Size = UDim2.fromOffset(300, 18), Font = isEvent and Enum.Font.GothamBold or Enum.Font.Gotham, TextSize = 13,
                    TextColor3 = isEvent and C_TEXT or C_MUTED, Text = slot.Name .. (slot.Tagline and ("  •  " .. slot.Tagline) or "") })
                local when = live and string.format("LIVE  •  ends in %s", duration(SkylarkTime.realSecondsUntil(slot.EndsAt) or 0))
                    or string.format("starts in %s", duration(SkylarkTime.realSecondsUntil(slot.StartsAt) or 0))
                if SkylarkTime.rate() <= 0 then
                    when = live and "LIVE  •  clock paused" or "clock paused"
                end
                label(f, { Position = UDim2.fromOffset(130, 23), Size = UDim2.fromOffset(300, 16), TextSize = 11, TextColor3 = C_MUTED, Text = when })
                if mine then
                    label(f, { Position = UDim2.fromOffset(W - 240, 0), Size = UDim2.fromOffset(190, 44), Font = Enum.Font.GothamBold, TextSize = 12, TextColor3 = C_GREEN,
                        TextXAlignment = Enum.TextXAlignment.Right, Text = live and "YOU'RE ENTERED" or "PREBOOKED" })
                end
            end
        end
    end
    drawDay(info.Day, "TODAY")
    drawDay(info.Day + 1, "TOMORROW")
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

local DRAW = { ["MY QUINS"] = drawQuins, SCHEDULE = drawSchedule, WALLET = drawWallet, ["LAST MATCH"] = drawMatch }

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

local function setOpen(open)
    gui.Enabled = open
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

-- the MENU button under the SC pill (SkylarkClockUI, ArenaEntry)
task.spawn(function()
    local clock = playerGui:WaitForChild("SkylarkClockUI", 30)
    if not clock then
        return
    end
    local b = new("TextButton", { Name = "MenuButton", Parent = clock, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -150, 0, 160), Size = UDim2.fromOffset(100, 26),
        Text = "MENU  (G)", Font = Enum.Font.GothamBold, TextSize = 12, TextColor3 = C_AMBER, BackgroundColor3 = C_BG, BackgroundTransparency = 0.12 })
    corner(b, 8)
    new("UIStroke", { Parent = b, Color = C_STROKE, Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border })
    b.MouseButton1Click:Connect(function()
        setOpen(not gui.Enabled)
    end)
end)

-- open: timers tick every second, the data comes again every 5 s
task.spawn(function()
    local n = 0
    while true do
        task.wait(1)
        if gui.Enabled then
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
