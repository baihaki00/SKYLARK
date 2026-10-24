--// ArenaEntry.client.lua
-- Entering an arena's events (ArenaRegistration on the server). Everything is named for the arena
-- (SkylarkArenas.current(): today Argonia Arena), never "the arena": Skylark will have more.
--   * your entry state: closed / open at the arena's terminals / entered and your place in the
--     queue / your Quins fight this round. Shared as shared.ArenaEntryStatus { Arena, Text, Color,
--     Active } for the player menu's SCHEDULE (and the MENU button's dot); no HUD bar of its own;
--   * the arena's terminal (its ProximityPrompt) opens on two choices: SPECTATE (left: pick a side
--     and a seat, Normal 100 SC or VIP 300 SC: SkylarkSpectate) and REGISTER QUIN (pick your Quins,
--     up to the event's limit: 2 in the 16v16 battles; Register, change them or Withdraw).
--     It closes when you walk away from the terminal;
--   * your Skylark Coin (SC): a pill on the Skylark clock's top bar (TopBar, LayoutOrder 2);
--   * QUICK MATCH (a debug button: shown with F8 in any role, and always in the Roblox Player role
--     for testers): a 16v16 round now with your Quins
--     (ArenaRegistration "quick": Studio or admins).
-- Everything shown comes from attributes the server keeps (Workspace ArenaReg*, Player Arena*).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local ProximityPromptService = game:GetService("ProximityPromptService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local QuinCore = ReplicatedStorage:WaitForChild("QuinCore")
local SkylarkTime = require(QuinCore:WaitForChild("SkylarkTime"))
local ARENA = require(QuinCore:WaitForChild("SkylarkArenas")).current()
local entryRemote = ReplicatedStorage:WaitForChild("ArenaNetwork"):WaitForChild("ArenaEntry", 30)
local spectateRemote = ReplicatedStorage:WaitForChild("ArenaNetwork"):WaitForChild("Spectate", 30)

local gui = player:WaitForChild("PlayerGui"):WaitForChild("SkylarkClockUI", 30)
if not gui or not entryRemote then
    warn("[ArenaEntry] No clock UI or entry remote: entry not shown")
    return
end

local WALK_AWAY = 20 -- studs from the terminal that close the popup

-- Colour palette (the Arena System panel's)
local C_BG = Color3.fromRGB(15, 18, 26)
local C_CARD = Color3.fromRGB(22, 27, 38)
local C_CARD_SEL = Color3.fromRGB(28, 36, 52)
local C_STROKE = Color3.fromRGB(38, 48, 68)
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

local function corner(inst, radius)
    new("UICorner", { CornerRadius = UDim.new(0, radius), Parent = inst })
end

local function stroke(inst, color)
    return new("UIStroke", { Color = color or C_STROKE, Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = inst })
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

local function notify(title, text)
    pcall(function()
        StarterGui:SetCore("SendNotification", { Title = title, Text = text, Duration = 5 })
    end)
end

local function untilText(t)
    local real = SkylarkTime.realSecondsUntil(t)
    if real then
        return SkylarkTime.formatDuration(real)
    end
    return SkylarkTime.formatDuration((t - SkylarkTime.now()) / SkylarkTime.HOUR * 3600) .. " SST"
end

local function enteredSlots()
    local set, list = {}, {}
    local raw = player:GetAttribute("ArenaEntrySlots")
    if type(raw) == "string" then
        for s in raw:gmatch("%d+") do
            set[tonumber(s)] = true
            table.insert(list, tonumber(s))
        end
    end
    return set, list
end

-- ============================================================================
-- ENTRY STATE (shown in the player menu) AND THE SC PILL (top bar)
-- ============================================================================

local function entryState(text, color, active)
    shared.ArenaEntryStatus = { Arena = ARENA.Id, Text = text, Color = color, Active = active }
end
entryState("", C_MUTED, false)

local coinPill = new("Frame", {
    Name = "CoinPill",
    Parent = gui:WaitForChild("TopBar"),
    LayoutOrder = 2,
    Size = UDim2.fromOffset(130, 44),
    BackgroundColor3 = C_BG,
    BackgroundTransparency = 0.12,
})
corner(coinPill, 22)
stroke(coinPill)
local coinLabel = label(coinPill, { Position = UDim2.fromOffset(14, 0), Size = UDim2.new(1, -28, 1, 0), Font = Enum.Font.GothamBold, TextSize = 13, TextColor3 = C_AMBER, TextXAlignment = Enum.TextXAlignment.Center, Text = "SC ..." })

local function formatSC(n)
    local text = tostring(math.floor(n or 0))
    while true do
        local replaced, count = text:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
        text = replaced
        if count == 0 then
            break
        end
    end
    return text
end

local function refreshCoins()
    local sc = player:GetAttribute("SC")
    coinLabel.Text = sc and ("SC  " .. formatSC(sc)) or "SC ..."
end
player:GetAttributeChangedSignal("SC"):Connect(refreshCoins)
refreshCoins()

-- ============================================================================
-- REGISTRATION POPUP (the arena's terminal)
-- ============================================================================

local PW, PH = 340, 340
local QUIN_Y, QUIN_H = 92, 34
local popup = new("Frame", {
    Name = "TerminalPopup",
    Parent = gui,
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.fromScale(0.5, 0.5),
    Size = UDim2.fromOffset(PW, PH),
    BackgroundColor3 = C_BG,
    BackgroundTransparency = 0.04,
    Visible = false,
})
corner(popup, 12)
stroke(popup, C_AMBER)

label(popup, { Position = UDim2.fromOffset(16, 12), Size = UDim2.fromOffset(PW - 60, 18), Font = Enum.Font.GothamBold, TextSize = 14, TextColor3 = C_AMBER, Text = string.upper(ARENA.Name) .. " TERMINAL" })
local closeButton = new("TextButton", { Parent = popup, Text = "X", Font = Enum.Font.GothamBold, TextSize = 12, TextColor3 = C_TEXT, BackgroundColor3 = C_CARD, Position = UDim2.fromOffset(PW - 38, 10), Size = UDim2.fromOffset(26, 26) })
corner(closeButton, 6)
local windowLabel = label(popup, { Position = UDim2.fromOffset(16, 36), Size = UDim2.fromOffset(PW - 32, 18), Font = Enum.Font.GothamBold, TextSize = 13, Text = "" })
local whenLabel = label(popup, { Position = UDim2.fromOffset(16, 54), Size = UDim2.fromOffset(PW - 32, 14), TextSize = 11, TextColor3 = C_MUTED, Text = "" })
local pickLabel = label(popup, { Position = UDim2.fromOffset(16, 74), Size = UDim2.fromOffset(PW - 32, 14), Font = Enum.Font.GothamBold, TextSize = 11, TextColor3 = C_MUTED, Text = "" })

local registerBack = new("TextButton", { Parent = popup, Text = "<", Font = Enum.Font.GothamBold, TextSize = 12, TextColor3 = C_TEXT, BackgroundColor3 = C_CARD, Position = UDim2.fromOffset(PW - 72, 10), Size = UDim2.fromOffset(26, 26) })
corner(registerBack, 6)
local actionButton = new("TextButton", { Parent = popup, Text = "REGISTER", Font = Enum.Font.GothamBold, TextSize = 13, TextColor3 = C_BG, BackgroundColor3 = C_AMBER, Position = UDim2.fromOffset(16, QUIN_Y + 4 * QUIN_H + 8), Size = UDim2.fromOffset(PW - 32, 34) })
corner(actionButton, 7)
local withdrawButton = new("TextButton", { Parent = popup, Text = "WITHDRAW", Font = Enum.Font.GothamBold, TextSize = 11, TextColor3 = C_RED, BackgroundColor3 = C_CARD, Position = UDim2.fromOffset(16, QUIN_Y + 4 * QUIN_H + 48), Size = UDim2.fromOffset(PW - 32, 24), Visible = false })
corner(withdrawButton, 6)
local statusLabel = label(popup, { Position = UDim2.fromOffset(16, QUIN_Y + 4 * QUIN_H + 76), Size = UDim2.fromOffset(PW - 32, 14), TextSize = 11, Text = "" })
label(popup, {
    Position = UDim2.fromOffset(16, PH - 38),
    Size = UDim2.fromOffset(PW - 32, 30),
    TextSize = 10,
    TextColor3 = C_MUTED,
    TextWrapped = true,
    TextTruncate = Enum.TextTruncate.None,
    TextYAlignment = Enum.TextYAlignment.Top,
    Text = "Sat out a round? You go first next round. Your Quins fight on the same side. Empty seats are filled by arena Quins.",
})

local roster = {}
local selected = {} -- [slot] = order picked
local quinButtons = {}
local openTerminal = nil

local function perPlayer()
    return Workspace:GetAttribute("ArenaRegPerPlayer") or 1
end

local function selectedList()
    local list = {}
    for slot, order in pairs(selected) do
        table.insert(list, { slot = slot, order = order })
    end
    table.sort(list, function(a, b)
        return a.order < b.order
    end)
    local slots = {}
    for _, item in ipairs(list) do
        table.insert(slots, item.slot)
    end
    return slots
end

local function refreshQuinButtons()
    for slot = 1, 4 do
        local b = quinButtons[slot]
        local q = nil
        for _, entry in ipairs(roster) do
            if entry.Slot == slot then
                q = entry
            end
        end
        b.Visible = q ~= nil
        if q then
            local on = selected[slot] ~= nil
            b.Text = string.format("   %s  %s Quin #%s   •   %s   •   W%d L%d   •   %d%%%s", on and "[x]" or "[  ]", q.Gender or "", q.Tag,
                q.Title or "Rookie", q.Wins, q.Losses, q.Condition or 100, q.Busy and ("   •   busy: " .. q.Busy) or "")
            b.BackgroundColor3 = on and C_CARD_SEL or C_CARD
            b.TextColor3 = on and C_AMBER or C_TEXT
        end
    end
end

for slot = 1, 4 do
    local b = new("TextButton", {
        Parent = popup,
        Text = "",
        Font = Enum.Font.Gotham,
        TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextColor3 = C_TEXT,
        BackgroundColor3 = C_CARD,
        Position = UDim2.fromOffset(16, QUIN_Y + (slot - 1) * QUIN_H),
        Size = UDim2.fromOffset(PW - 32, QUIN_H - 5),
        Visible = false,
    })
    corner(b, 6)
    b.MouseButton1Click:Connect(function()
        if selected[slot] then
            selected[slot] = nil
        else
            local list = selectedList()
            if #list >= perPlayer() then -- (at the limit: the oldest pick makes way)
                selected[list[1]] = nil
            end
            selected[slot] = os.clock()
        end
        refreshQuinButtons()
    end)
    quinButtons[slot] = b
end

local function setStatus(text, color)
    statusLabel.Text = text or ""
    statusLabel.TextColor3 = color or C_TEXT
end

local function openPopup(terminal)
    openTerminal = terminal
    popup.Visible = true
    setStatus("")
    local ok, result = pcall(function()
        return entryRemote:InvokeServer("roster")
    end)
    roster = ok and type(result) == "table" and result or {}
    selected = {}
    local _, already = enteredSlots()
    for i, s in ipairs(already) do
        selected[s] = i
    end
    if not next(selected) and roster[1] then
        selected[roster[1].Slot] = 1
    end
    refreshQuinButtons()
end

-- ============================================================================
-- THE TERMINAL'S FIRST SCREEN: SPECTATE | REGISTER QUIN
-- ============================================================================

local function panel(name, height, color)
    local f = new("Frame", {
        Name = name,
        Parent = gui,
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(PW, height),
        BackgroundColor3 = C_BG,
        BackgroundTransparency = 0.04,
        Visible = false,
    })
    corner(f, 12)
    stroke(f, color or C_AMBER)
    return f
end

local function button(parent, text, x, y, w, h, color, textColor, name)
    local b = new("TextButton", {
        Name = name or "Button", Parent = parent, Text = text, Font = Enum.Font.GothamBold, TextSize = 12, TextWrapped = true,
        TextColor3 = textColor or C_TEXT, BackgroundColor3 = color or C_CARD,
        Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(w, h),
    })
    corner(b, 8)
    return b
end

local chooser = panel("TerminalChooser", 190)
label(chooser, { Position = UDim2.fromOffset(16, 12), Size = UDim2.fromOffset(PW - 60, 18), Font = Enum.Font.GothamBold, TextSize = 14, TextColor3 = C_AMBER, Text = string.upper(ARENA.Name) .. " TERMINAL" })
local chooserClose = button(chooser, "X", PW - 38, 10, 26, 26, nil, nil, "CloseBtn")
local chooserEvent = label(chooser, { Position = UDim2.fromOffset(16, 36), Size = UDim2.fromOffset(PW - 32, 16), TextSize = 11, TextColor3 = C_MUTED, Text = "" })
local half = (PW - 32 - 10) / 2
local spectateChoice = button(chooser, "SPECTATE\n\nWatch from the stands\nor a VIP box", 16, 60, half, 112, C_CARD, C_TEXT, "SpectateChoice")
stroke(spectateChoice, C_GREEN)
local registerChoice = button(chooser, "REGISTER QUIN\n\nEnter your Quins\nfor this event", 16 + half + 10, 60, half, 112, C_CARD, C_TEXT, "RegisterChoice")
stroke(registerChoice, C_AMBER)
local quickButton = button(chooser, "QUICK MATCH  •  debug: a 16v16 round now with your Quins", 16, 182, PW - 32, 30, C_CARD, C_AMBER, "QuickMatchBtn")
stroke(quickButton, C_AMBER).Transparency = 0.5
quickButton.TextSize = 11
local quickStatus = label(chooser, { Position = UDim2.fromOffset(16, 216), Size = UDim2.fromOffset(PW - 32, 14), TextSize = 11, Text = "" })
-- Shown with F8 (debug buttons), and always to a tester in the Roblox Player role (Play As Roblox
-- Player in Studio, or an admin playing as a player): that's where quick matches get run from.
local function refreshQuick()
    local tester = RunService:IsStudio() or player:GetAttribute("SkylarkCanAdmin") == true
    local on = player:GetAttribute("ShowDebugButtons") == true or (tester and player:GetAttribute("SkylarkRole") == "Player")
    quickButton.Visible = on
    quickStatus.Visible = on
    chooser.Size = UDim2.fromOffset(PW, on and 240 or 190)
end
refreshQuick()
for _, attr in ipairs({ "ShowDebugButtons", "SkylarkRole", "SkylarkCanAdmin" }) do
    player:GetAttributeChangedSignal(attr):Connect(refreshQuick)
end

-- ============================================================================
-- SPECTATE: a side and a seat
-- ============================================================================

local PRICES = { Normal = 100, VIP = 300 }
local spectate = panel("SpectatePanel", 330, C_GREEN)
label(spectate, { Position = UDim2.fromOffset(16, 12), Size = UDim2.fromOffset(PW - 100, 18), Font = Enum.Font.GothamBold, TextSize = 14, TextColor3 = C_GREEN, Text = "SPECTATE" })
local spectateBack = button(spectate, "<", PW - 72, 10, 26, 26, nil, nil, "BackBtn")
local spectateClose = button(spectate, "X", PW - 38, 10, 26, 26, nil, nil, "CloseBtn")
local balanceLabel = label(spectate, { Position = UDim2.fromOffset(16, 36), Size = UDim2.fromOffset(PW - 32, 16), Font = Enum.Font.GothamBold, TextSize = 12, TextColor3 = C_AMBER, Text = "" })
label(spectate, { Position = UDim2.fromOffset(16, 60), Size = UDim2.fromOffset(PW - 32, 14), Font = Enum.Font.GothamBold, TextSize = 11, TextColor3 = C_MUTED, Text = "SIDE" })
local alphaButton = button(spectate, "ALPHA SIDE", 16, 78, half, 34, nil, nil, "AlphaBtn")
local betaButton = button(spectate, "BETA SIDE", 16 + half + 10, 78, half, 34, nil, nil, "BetaBtn")
label(spectate, { Position = UDim2.fromOffset(16, 122), Size = UDim2.fromOffset(PW - 32, 14), Font = Enum.Font.GothamBold, TextSize = 11, TextColor3 = C_MUTED, Text = "SEAT" })
local normalButton = button(spectate, "NORMAL SEAT\n100 SC\nthe side's stands", 16, 140, half, 62, nil, nil, "NormalBtn")
local vipButton = button(spectate, "VIP SEAT\n300 SC\nVIP box: drone + free cameras", 16 + half + 10, 140, half, 62, nil, nil, "VipBtn")
local buyButton = button(spectate, "BUY SEAT", 16, 214, PW - 32, 36, C_GREEN, C_BG, "BuyBtn")
local spectateStatus = label(spectate, { Position = UDim2.fromOffset(16, 258), Size = UDim2.fromOffset(PW - 32, 28), TextSize = 11, TextWrapped = true, TextTruncate = Enum.TextTruncate.None, Text = "" })
label(spectate, {
    Position = UDim2.fromOffset(16, 290), Size = UDim2.fromOffset(PW - 32, 30), TextSize = 10, TextColor3 = C_MUTED,
    TextWrapped = true, TextTruncate = Enum.TextTruncate.None, TextYAlignment = Enum.TextYAlignment.Top,
    Text = "A seat lasts the round. Come back any time to return to it for free; Normal to VIP pays the difference.",
})

local pickSide, pickSeat = nil, nil
local function refreshSpectate()
    local mySide, mySeat = player:GetAttribute("SpectateSide"), player:GetAttribute("SpectateSeat")
    balanceLabel.Text = "YOUR SC: " .. formatSC(player:GetAttribute("SC") or 0)
        .. (mySeat and string.format("   •   TICKET: %s, %s", mySeat, mySide == "TeamAlpha" and "Alpha" or "Beta") or "")
    for _, pair in ipairs({ { alphaButton, "TeamAlpha" }, { betaButton, "TeamBeta" } }) do
        local on = pickSide == pair[2]
        pair[1].BackgroundColor3 = on and C_CARD_SEL or C_CARD
        pair[1].TextColor3 = on and C_GREEN or C_TEXT
    end
    for _, pair in ipairs({ { normalButton, "Normal" }, { vipButton, "VIP" } }) do
        local on = pickSeat == pair[2]
        pair[1].BackgroundColor3 = on and C_CARD_SEL or C_CARD
        pair[1].TextColor3 = on and C_GREEN or C_TEXT
    end
    local price = pickSeat and PRICES[pickSeat] or 0
    if pickSide and pickSeat and mySide == pickSide and mySeat then
        if mySeat == pickSeat or mySeat == "VIP" then
            price = 0
        else
            price = PRICES.VIP - PRICES.Normal
        end
    end
    local ready = pickSide ~= nil and pickSeat ~= nil
    buyButton.Text = not ready and "PICK A SIDE AND A SEAT" or (price == 0 and "GO TO MY SEAT" or string.format("BUY SEAT  •  %d SC", price))
    buyButton.BackgroundColor3 = ready and C_GREEN or C_CARD
    buyButton.TextColor3 = ready and C_BG or C_MUTED
end

alphaButton.MouseButton1Click:Connect(function() pickSide = "TeamAlpha" refreshSpectate() end)
betaButton.MouseButton1Click:Connect(function() pickSide = "TeamBeta" refreshSpectate() end)
normalButton.MouseButton1Click:Connect(function() pickSeat = "Normal" refreshSpectate() end)
vipButton.MouseButton1Click:Connect(function() pickSeat = "VIP" refreshSpectate() end)

local function closePopup()
    popup.Visible = false
    chooser.Visible = false
    spectate.Visible = false
    openTerminal = nil
end

buyButton.MouseButton1Click:Connect(function()
    if not (pickSide and pickSeat) or not spectateRemote then
        return
    end
    spectateStatus.Text = "..."
    spectateStatus.TextColor3 = C_MUTED
    local ok, result, message = pcall(function()
        return spectateRemote:InvokeServer("buy", pickSide, pickSeat)
    end)
    if ok and result then
        closePopup()
        notify("Enjoy the fight", message or "")
    else
        spectateStatus.Text = ok and (message or "Could not buy a seat") or "Could not reach " .. ARENA.Name
        spectateStatus.TextColor3 = C_RED
    end
end)

local function showChooser(terminal)
    openTerminal = terminal
    popup.Visible = false
    spectate.Visible = false
    chooser.Visible = true
    -- spectate the event or take part in it, not both
    local inEvent = player:GetAttribute("ArenaEntered") == true
    local watching = player:GetAttribute("SpectateSeat") ~= nil
    spectateChoice.Text = inEvent and "SPECTATE\n\nNot while your Quins\nare in this event" or "SPECTATE\n\nWatch from the stands\nor a VIP box"
    spectateChoice.TextColor3 = inEvent and C_MUTED or C_TEXT
    registerChoice.Text = watching and "REGISTER QUIN\n\nNot while you hold\na seat this round" or "REGISTER QUIN\n\nEnter your Quins\nfor this event"
    registerChoice.TextColor3 = watching and C_MUTED or C_TEXT
    local window = Workspace:GetAttribute("ArenaRegWindow")
    local phase = Workspace:GetAttribute("ArenaPhase")
    chooserEvent.Text = (window and string.upper(window) or "NO EVENT OPEN")
        .. ((phase and phase ~= "IDLE") and "   •   MATCH ON" or "")
end

spectateChoice.MouseButton1Click:Connect(function()
    if player:GetAttribute("ArenaEntered") == true then
        return
    end
    chooser.Visible = false
    spectate.Visible = true
    spectateStatus.Text = ""
    pickSide = player:GetAttribute("SpectateSide") or pickSide
    pickSeat = player:GetAttribute("SpectateSeat") or pickSeat
    refreshSpectate()
end)
spectateBack.MouseButton1Click:Connect(function()
    showChooser(openTerminal)
end)
spectateClose.MouseButton1Click:Connect(function()
    closePopup()
end)
chooserClose.MouseButton1Click:Connect(function()
    closePopup()
end)
for _, attr in ipairs({ "SC", "SpectateSide", "SpectateSeat" }) do
    player:GetAttributeChangedSignal(attr):Connect(function()
        if spectate.Visible then
            refreshSpectate()
        end
    end)
end

actionButton.MouseButton1Click:Connect(function()
    local ok, result, message = pcall(function()
        return entryRemote:InvokeServer("register", selectedList())
    end)
    if ok then
        setStatus(message, result and C_GREEN or C_RED)
    else
        setStatus("Could not reach " .. ARENA.Name, C_RED)
    end
end)

withdrawButton.MouseButton1Click:Connect(function()
    local ok, _, message = pcall(function()
        return entryRemote:InvokeServer("withdraw")
    end)
    setStatus(ok and message or "Could not reach " .. ARENA.Name, ok and C_TEXT or C_RED)
end)

closeButton.MouseButton1Click:Connect(closePopup)
registerBack.MouseButton1Click:Connect(function()
    showChooser(openTerminal)
end)

ProximityPromptService.PromptTriggered:Connect(function(prompt)
    if prompt.Name == "ArenaTerminalPrompt" then
        showChooser(prompt.Parent)
    end
end)
registerChoice.MouseButton1Click:Connect(function()
    chooser.Visible = false
    openPopup(openTerminal)
end)
quickButton.MouseButton1Click:Connect(function()
    quickStatus.Text = "..."
    quickStatus.TextColor3 = C_MUTED
    local _, already = enteredSlots()
    local ok, result, message = pcall(function()
        return entryRemote:InvokeServer("quick", already)
    end)
    if ok and result then
        quickStatus.Text = ""
        closePopup()
        notify("Quick match", message or "")
    else
        quickStatus.Text = ok and (message or "Could not start") or "Could not reach " .. ARENA.Name
        quickStatus.TextColor3 = C_RED
    end
end)

-- ============================================================================
-- STATE
-- ============================================================================

local function update()
    local open = Workspace:GetAttribute("ArenaRegOpen") == true
    local window = Workspace:GetAttribute("ArenaRegWindow")
    local kind = Workspace:GetAttribute("ArenaRegKind")
    local startsAt = Workspace:GetAttribute("ArenaRegStartsAt")
    local closesAt = Workspace:GetAttribute("ArenaRegClosesAt")
    local entered = player:GetAttribute("ArenaEntered") == true
    local inRound = player:GetAttribute("ArenaInRound") == true
    local pos = player:GetAttribute("ArenaQueuePos")
    local satOut = player:GetAttribute("ArenaSatOut") or 0
    local entrants = Workspace:GetAttribute("ArenaEntrants") or 0
    local _, mine = enteredSlots()

    if inRound then
        entryState(#mine > 1 and "YOUR QUINS FIGHT THIS ROUND" or "YOUR QUIN FIGHTS THIS ROUND", C_AMBER, true)
    elseif entered and player:GetAttribute("ArenaPrebooked") then
        local side = player:GetAttribute("ArenaPrebookSide") == "TeamAlpha" and "ALPHA" or "BETA"
        entryState(string.format("PREBOOKED (%d)  •  %s  •  seated first", #mine, side), C_GREEN, true)
    elseif entered then
        entryState(satOut > 0 and string.format("ENTERED  •  #%d  •  first next round", pos or 0)
            or string.format("ENTERED (%d)  •  #%d of %d in queue", #mine, pos or 0, entrants), C_GREEN, true)
    elseif open then
        entryState(string.format("ENTRY OPEN  •  register at an %s terminal", ARENA.Name), C_AMBER, false)
    elseif window then
        entryState("ENTRY CLOSED FOR THIS EVENT", C_MUTED, false)
    else
        entryState("ENTRY CLOSED  •  opens 20m before events", C_MUTED, false)
    end

    if chooser.Visible or spectate.Visible or popup.Visible then
        -- walked away from the terminal: close
        local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
        if openTerminal and root and (openTerminal.Position - root.Position).Magnitude > WALK_AWAY then
            closePopup()
            return
        end
    end
    if popup.Visible then
        windowLabel.Text = window and string.upper(window) or "NO EVENT OPEN"
        if open and kind == "Live" and closesAt then
            whenLabel.Text = string.format("Live now  •  entry closes in %s  •  %d entered", untilText(closesAt), entrants)
        elseif open and startsAt then
            whenLabel.Text = string.format("Starts in %s  •  %d entered", untilText(startsAt), entrants)
        elseif window then
            whenLabel.Text = "Entry has closed for this event"
        else
            whenLabel.Text = "Entry opens 20 minutes before each event"
        end
        local limit = perPlayer()
        pickLabel.Text = limit > 1 and string.format("PICK UP TO %d QUINS (THEY FIGHT TOGETHER)", limit) or "PICK YOUR QUIN"
        actionButton.Text = entered and "UPDATE MY ENTRY" or "REGISTER"
        actionButton.BackgroundColor3 = open and C_AMBER or C_CARD
        actionButton.TextColor3 = open and C_BG or C_MUTED
        withdrawButton.Visible = entered
    end
end

player:GetAttributeChangedSignal("ArenaInRound"):Connect(function()
    if player:GetAttribute("ArenaInRound") == true then
        notify("You're in!", "Off to the preparation room: your Quins are waiting on your pad.")
    end
end)

local last = 0
RunService.RenderStepped:Connect(function()
    if os.clock() - last >= 0.25 then
        last = os.clock()
        update()
    end
end)
