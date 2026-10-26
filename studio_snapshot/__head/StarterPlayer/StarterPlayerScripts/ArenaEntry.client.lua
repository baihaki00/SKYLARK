--// ArenaEntry.client.lua
-- Entering an arena's events (ArenaRegistration on the server). Everything is named for the arena
-- (SkylarkArenas.current(): today Argonia Arena), never "the arena": Skylark will have more.
--   * your entry state: closed / open at the arena's terminals / entered and your place in the
--     queue / your Quins fight this round. Shared as shared.ArenaEntryStatus { Arena, Text, Color,
--     Active } for the player menu's SCHEDULE (and the MENU button's dot); no HUD bar of its own;
--   * the arena's terminal (its ProximityPrompt). The prompt always shows and says the state
--     ("Register Quins" / "Spectate" / "Opens in 12m 30s"); in the chooser a closed choice is
--     greyed with why and when it opens (ArenaTiming.describe), and can't be picked;
--   * the terminal opens on two choices: SPECTATE (left: pick a side
--     and a seat, Normal 100 SC or VIP 300 SC: SkylarkSpectate) and REGISTER QUIN (pick your Quins,
--     up to the event's limit: 2 in the 16v16 battles; Register, change them or Withdraw).
--     It closes when you walk away from the terminal;
--   * your Skylark Coin (SC): a pill on the Skylark clock's top bar (TopBar, LayoutOrder 2);
--   * ARENA MENU [DEBUG] (shown with F8 in any role, and always in the Roblox Player role for
--     testers): opens the block test menu (ArenaBlockMenu.client: timeline, jumps, live timings,
--     QUICK MATCH).
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
local ArenaTiming = require(QuinCore:WaitForChild("ArenaTiming"))
local SCHEDULE = ARENA.Schedule
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
    return ArenaTiming.untilText(t)
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

local PW = 440
local QUIN_Y, QUIN_H = 100, 40
local ROOM_Y = QUIN_Y + 4 * QUIN_H + 6 -- (the prep room row)
local ACTION_Y = ROOM_Y + 84
local PH = ACTION_Y + 152
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

label(popup, { Position = UDim2.fromOffset(16, 12), Size = UDim2.fromOffset(PW - 90, 20), Font = Enum.Font.GothamBold, TextSize = 16, TextColor3 = C_AMBER, Text = string.upper(ARENA.Name) .. " TERMINAL" })
local closeButton = new("TextButton", { Parent = popup, Text = "X", Font = Enum.Font.GothamBold, TextSize = 12, TextColor3 = C_TEXT, BackgroundColor3 = C_CARD, Position = UDim2.fromOffset(PW - 38, 10), Size = UDim2.fromOffset(26, 26) })
corner(closeButton, 6)
local windowLabel = label(popup, { Position = UDim2.fromOffset(16, 40), Size = UDim2.fromOffset(PW - 32, 20), Font = Enum.Font.GothamBold, TextSize = 15, Text = "" })
local whenLabel = label(popup, { Position = UDim2.fromOffset(16, 62), Size = UDim2.fromOffset(PW - 32, 16), TextSize = 12, TextColor3 = C_MUTED, Text = "" })
local pickLabel = label(popup, { Position = UDim2.fromOffset(16, 82), Size = UDim2.fromOffset(PW - 32, 14), Font = Enum.Font.GothamBold, TextSize = 12, TextColor3 = C_MUTED, Text = "" })

local registerBack = new("TextButton", { Parent = popup, Text = "<", Font = Enum.Font.GothamBold, TextSize = 12, TextColor3 = C_TEXT, BackgroundColor3 = C_CARD, Position = UDim2.fromOffset(PW - 72, 10), Size = UDim2.fromOffset(26, 26) })
corner(registerBack, 6)
local actionButton = new("TextButton", { Name = "ActionBtn", Parent = popup, Text = "REGISTER", Font = Enum.Font.GothamBold, TextSize = 14, TextColor3 = C_BG, BackgroundColor3 = C_AMBER, Position = UDim2.fromOffset(16, ACTION_Y), Size = UDim2.fromOffset(PW - 32, 38) })
corner(actionButton, 7)
local withdrawButton = new("TextButton", { Name = "WithdrawBtn", Parent = popup, Text = "WITHDRAW", Font = Enum.Font.GothamBold, TextSize = 12, TextColor3 = C_RED, BackgroundColor3 = C_CARD, Position = UDim2.fromOffset(16, ACTION_Y + 44), Size = UDim2.fromOffset(PW - 32, 28), Visible = false })
corner(withdrawButton, 6)
local statusLabel = label(popup, { Name = "Status", Position = UDim2.fromOffset(16, ACTION_Y + 78), Size = UDim2.fromOffset(PW - 32, 32), TextSize = 12,
    TextWrapped = true, TextTruncate = Enum.TextTruncate.None, TextYAlignment = Enum.TextYAlignment.Top, Text = "" })
label(popup, {
    Position = UDim2.fromOffset(16, PH - 40),
    Size = UDim2.fromOffset(PW - 32, 32),
    TextSize = 11,
    TextColor3 = C_MUTED,
    TextWrapped = true,
    TextTruncate = Enum.TextTruncate.None,
    TextYAlignment = Enum.TextYAlignment.Top,
    Text = "Sat out a round? You go first next round. Your Quins fight on the same side. Empty seats are filled by arena Quins.",
})

local roster = {}
local selected = {} -- [slot] = order picked
local wishRoom = nil -- the prep room wished for (1-16 on your side), nil = any

-- PREP ROOM: 1-16 in two rows; your side is set when you're seated, so it's room N on that side
local roomLabel = label(popup, { Position = UDim2.fromOffset(16, ROOM_Y), Size = UDim2.fromOffset(PW - 32, 14), Font = Enum.Font.GothamBold, TextSize = 12, TextColor3 = C_MUTED, Text = "" })
local roomButtons = {}
local ROOM_W = (PW - 32 - 7 * 6) / 8
for n = 1, 16 do
    local b = new("TextButton", {
        Name = "Room" .. n, Parent = popup, Text = tostring(n), Font = Enum.Font.GothamBold, TextSize = 13,
        TextColor3 = C_TEXT, BackgroundColor3 = C_CARD,
        Position = UDim2.fromOffset(16 + ((n - 1) % 8) * (ROOM_W + 6), ROOM_Y + 20 + math.floor((n - 1) / 8) * 30),
        Size = UDim2.fromOffset(ROOM_W, 26),
    })
    corner(b, 6)
    roomButtons[n] = b
end
local function refreshRooms()
    for n, b in ipairs(roomButtons) do
        local on = wishRoom == n
        b.BackgroundColor3 = on and C_AMBER or C_CARD
        b.TextColor3 = on and C_BG or C_TEXT
    end
    roomLabel.Text = wishRoom and string.format("PREP ROOM %d ON YOUR SIDE  (TAKEN: THE NEAREST FREE)", wishRoom) or "PREP ROOM  •  ANY FREE ROOM  (PICK ONE TO ASK FOR IT)"
end
for n, b in ipairs(roomButtons) do
    b.MouseButton1Click:Connect(function()
        if Workspace:GetAttribute("ArenaRegOpen") ~= true then
            return
        end
        wishRoom = wishRoom ~= n and n or nil -- (again: any room)
        refreshRooms()
    end)
end
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
        TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextColor3 = C_TEXT,
        BackgroundColor3 = C_CARD,
        Position = UDim2.fromOffset(16, QUIN_Y + (slot - 1) * QUIN_H),
        Size = UDim2.fromOffset(PW - 32, QUIN_H - 5),
        Visible = false,
    })
    corner(b, 6)
    b.MouseButton1Click:Connect(function()
        if Workspace:GetAttribute("ArenaRegOpen") ~= true then
            return
        end
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
    wishRoom = player:GetAttribute("ArenaRoomWish")
    refreshQuinButtons()
    refreshRooms()
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
        Name = name or "Button", Parent = parent, Text = text, Font = Enum.Font.GothamBold, TextSize = 13, TextWrapped = true,
        TextColor3 = textColor or C_TEXT, BackgroundColor3 = color or C_CARD,
        Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(w, h),
    })
    corner(b, 8)
    return b
end

local chooser = panel("TerminalChooser", 190)
label(chooser, { Position = UDim2.fromOffset(16, 12), Size = UDim2.fromOffset(PW - 60, 20), Font = Enum.Font.GothamBold, TextSize = 16, TextColor3 = C_AMBER, Text = string.upper(ARENA.Name) .. " TERMINAL" })
local chooserClose = button(chooser, "X", PW - 38, 10, 26, 26, nil, nil, "CloseBtn")
local chooserEvent = label(chooser, { Position = UDim2.fromOffset(16, 40), Size = UDim2.fromOffset(PW - 32, 16), TextSize = 12, TextColor3 = C_MUTED, Text = "" })
local half = (PW - 32 - 10) / 2
local spectateChoice = button(chooser, "SPECTATE\n\nWatch from the stands\nor a VIP box", 16, 66, half, 140, C_CARD, C_TEXT, "SpectateChoice")
stroke(spectateChoice, C_GREEN)
local registerChoice = button(chooser, "REGISTER QUIN\n\nEnter your Quins\nfor this event", 16 + half + 10, 66, half, 140, C_CARD, C_TEXT, "RegisterChoice")
stroke(registerChoice, C_AMBER)
local quickButton = button(chooser, "ARENA MENU  [DEBUG]", 16, 218, PW - 32, 32, C_CARD, C_AMBER, "ArenaMenuBtn")
stroke(quickButton, C_AMBER).Transparency = 0.5
quickButton.TextSize = 11
local quickStatus = label(chooser, { Position = UDim2.fromOffset(16, 254), Size = UDim2.fromOffset(PW - 32, 14), TextSize = 11, Text = "" })
-- Shown with F8 (debug buttons), and always to a tester in the Roblox Player role (Play As Roblox
-- Player in Studio, or an admin playing as a player): that's where quick matches get run from.
local function refreshQuick()
    local tester = RunService:IsStudio() or player:GetAttribute("SkylarkCanAdmin") == true
    local on = player:GetAttribute("ShowDebugButtons") == true or (tester and player:GetAttribute("SkylarkRole") == "Player")
    quickButton.Visible = on
    quickStatus.Visible = on
    chooser.Size = UDim2.fromOffset(PW, on and 278 or 224)
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

-- A choice open, or greyed with why and when (the reason under the title)
local choiceOpen = { spectate = false, register = false }
local function setChoice(b, strokeColor, title, open, text)
    -- a reason on lines: each sentence, then the SST time
    b.Text = title .. "\n\n" .. text:gsub("%. ", ".\n"):gsub(" %(", "\n(")
    b.TextColor3 = open and C_TEXT or C_MUTED
    b.BackgroundColor3 = open and C_CARD or C_BG
    b.AutoButtonColor = open
    local s = b:FindFirstChildOfClass("UIStroke")
    if s then
        s.Color = open and strokeColor or C_STROKE
    end
end

-- Spectate: a round is running, and your Quins aren't in this event.
-- Register: the walk-in desk takes entries (the server's ArenaRegOpen and the clock agree), and you
-- hold no seat. Entered at the desk: open to change your entry while the desk is open, and to
-- withdraw after it closes. Prebooked: changed at a prebook terminal only, so greyed here.
local function refreshChooser()
    local state = ArenaTiming.describe(SCHEDULE, Workspace:GetAttribute("ArenaPhase"))
    -- spectate the event or take part in it, not both
    local inEvent = player:GetAttribute("ArenaEntered") == true
    local prebooked = inEvent and player:GetAttribute("ArenaPrebooked") == true
    local watching = player:GetAttribute("SpectateSeat") ~= nil
    local walkInOpen = state.walkIn.open and Workspace:GetAttribute("ArenaRegOpen") == true
    -- (players queue like everyone else: the desk is yours only at the front of the line)
    local ahead = nil
    if Workspace:GetAttribute("ArenaQueueSkip") == false then
        local pos = player:GetAttribute("TerminalQueueKind") == "walkin" and player:GetAttribute("TerminalQueuePos")
        ahead = pos and pos - 1 or -1
        if ahead == 0 then
            ahead = nil
        end
    end
    choiceOpen.spectate = state.spectate.open and not inEvent
    choiceOpen.register = not prebooked and not (ahead and walkInOpen and not inEvent) and (inEvent or (walkInOpen and not watching))
    setChoice(spectateChoice, C_GREEN, "SPECTATE", choiceOpen.spectate,
        inEvent and "Not while your Quins\nare in this event" or (state.spectate.open and "Watch from the stands\nor a VIP box" or state.spectate.reason))
    local text
    if prebooked then
        text = "Prebooked. Change it at\n" .. ARENA.Name .. "\nprebook terminal"
    elseif inEvent then
        text = walkInOpen and "Change your Quins\nor withdraw" or "Entry is closed.\nYou can still withdraw"
    elseif watching and walkInOpen then
        text = "Not while you hold\na seat this round"
    elseif ahead and walkInOpen then
        text = ahead > 0 and string.format("Wait your turn:\n%d ahead in line", ahead) or "Join the line\nat the terminal"
    else
        text = walkInOpen and "Enter your Quins\nfor this event" or (state.walkIn.reason or "Closed")
    end
    setChoice(registerChoice, C_AMBER, inEvent and "YOUR ENTRY" or "REGISTER QUIN", choiceOpen.register, text)
    local event = state.walkIn.event
    local phase = Workspace:GetAttribute("ArenaPhase")
    local head = event and string.upper(event.Name) or "NO EVENT"
    if state.live and event == state.live then
        head ..= "  •  LIVE"
    end
    if phase and phase ~= "IDLE" then
        head ..= "  •  MATCH ON"
    elseif walkInOpen then
        head ..= "  •  WALK-IN OPEN"
    elseif state.walkIn.reason then
        head ..= "  •  WALK-IN: " .. state.walkIn.reason
    end
    chooserEvent.Text = head
end

local function showChooser(terminal)
    openTerminal = terminal
    popup.Visible = false
    spectate.Visible = false
    chooser.Visible = true
    refreshChooser()
end

spectateChoice.MouseButton1Click:Connect(function()
    if not choiceOpen.spectate then
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
    if Workspace:GetAttribute("ArenaRegOpen") ~= true then
        return
    end
    local ok, result, message = pcall(function()
        return entryRemote:InvokeServer("register", { slots = selectedList(), room = wishRoom })
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
    if not choiceOpen.register then
        return
    end
    chooser.Visible = false
    openPopup(openTerminal)
end)
quickButton.MouseButton1Click:Connect(function()
    if shared.OpenArenaBlockMenu then -- (ArenaBlockMenu.client)
        quickStatus.Text = ""
        closePopup()
        shared.OpenArenaBlockMenu()
    else
        quickStatus.Text = "The arena menu isn't loaded"
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
        entryState(string.format("ENTRY CLOSED  •  opens %dm before events", math.floor(ArenaTiming.get("WalkInOpensBefore") / 60 + 0.5)), C_MUTED, false)
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
            whenLabel.Text = string.format("Entry opens %d minutes before each event", math.floor(ArenaTiming.get("WalkInOpensBefore") / 60 + 0.5))
        end
        local limit = perPlayer()
        pickLabel.Text = limit > 1 and string.format("PICK UP TO %d QUINS (THEY FIGHT TOGETHER)", limit) or "PICK YOUR QUIN"
        actionButton.Text = not open and "ENTRY CLOSED" or (entered and "UPDATE MY ENTRY" or "REGISTER")
        actionButton.BackgroundColor3 = open and C_AMBER or C_CARD
        actionButton.TextColor3 = open and C_BG or C_MUTED
        actionButton.AutoButtonColor = open
        withdrawButton.Visible = entered
    end
end

player:GetAttributeChangedSignal("ArenaInRound"):Connect(function()
    if player:GetAttribute("ArenaInRound") == true then
        notify("You're in!", "Off to the preparation room: your Quins are waiting on your pad.")
    end
end)

-- The terminals' prompts (made by ArenaRegistration): named for the arena, and the action says
-- what you can do now, or when it opens (a local change: each player sees their own clock)
local terminalPrompts = {}
local function watchPrompt(d)
    if d:IsA("ProximityPrompt") and d.Name == "ArenaTerminalPrompt" then
        terminalPrompts[d] = true
    end
end
for _, d in ipairs(Workspace:GetDescendants()) do
    watchPrompt(d)
end
Workspace.DescendantAdded:Connect(watchPrompt)

local function refreshPrompts()
    local state = ArenaTiming.describe(SCHEDULE, Workspace:GetAttribute("ArenaPhase"))
    local entered = player:GetAttribute("ArenaEntered") == true
    local action
    local queuePos = Workspace:GetAttribute("ArenaQueueSkip") == false and player:GetAttribute("TerminalQueueKind") == "walkin"
        and player:GetAttribute("TerminalQueuePos")
    if state.walkIn.open and not entered and queuePos and queuePos > 1 then
        action = string.format("In line: %d ahead", queuePos - 1)
    elseif state.walkIn.open or entered then
        action = entered and "Your Entry" or "Register Quins"
    elseif state.spectate.open then
        action = "Spectate"
    else
        action = (state.walkIn.reason or "Closed"):gsub(" %(.-%)$", ""):gsub("^Closed for this event%. Next: [^,]+, opens", "Next opens")
    end
    for prompt in pairs(terminalPrompts) do
        if prompt.Parent then
            prompt.ObjectText = ARENA.Name .. " Terminal"
            prompt.ActionText = action
        else
            terminalPrompts[prompt] = nil
        end
    end
end

local last, lastPrompts = 0, 0
RunService.RenderStepped:Connect(function()
    if os.clock() - last >= 0.25 then
        last = os.clock()
        update()
        if chooser.Visible then
            refreshChooser()
        end
    end
    if os.clock() - lastPrompts >= 1 then
        lastPrompts = os.clock()
        refreshPrompts()
    end
end)
