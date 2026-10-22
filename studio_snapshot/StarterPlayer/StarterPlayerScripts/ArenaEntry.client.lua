--// ArenaEntry.client.lua
-- Entering the arena's events (ArenaRegistration on the server):
--   * the entry bar under the Skylark clock: closed / open at the terminals / entered and your
--     place in the queue / your Quins fight this round;
--   * the registration popup, opened at an Arena Terminal (its ProximityPrompt): pick your Quins
--     (up to the event's limit: 2 in the 16v16 battles), Register, change them or Withdraw.
--     It closes when you walk away from the terminal.
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
local entryRemote = ReplicatedStorage:WaitForChild("ArenaNetwork"):WaitForChild("ArenaEntry", 30)

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
-- ENTRY BAR (under the clock)
-- ============================================================================

local W = 256
local bar = new("TextButton", {
    Name = "EntryBar",
    Parent = gui,
    Text = "",
    AutoButtonColor = true,
    AnchorPoint = Vector2.new(1, 0),
    Position = UDim2.new(1, -16, 0, 122),
    Size = UDim2.fromOffset(W, 32),
    BackgroundColor3 = C_BG,
    BackgroundTransparency = 0.12,
})
corner(bar, 8)
local barStroke = stroke(bar)
local barLabel = label(bar, { Position = UDim2.fromOffset(12, 0), Size = UDim2.new(1, -24, 1, 0), Font = Enum.Font.GothamBold, TextSize = 12, Text = "" })

-- ============================================================================
-- REGISTRATION POPUP (an Arena Terminal)
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

label(popup, { Position = UDim2.fromOffset(16, 12), Size = UDim2.fromOffset(PW - 60, 18), Font = Enum.Font.GothamBold, TextSize = 14, TextColor3 = C_AMBER, Text = "ARENA TERMINAL" })
local closeButton = new("TextButton", { Parent = popup, Text = "X", Font = Enum.Font.GothamBold, TextSize = 12, TextColor3 = C_TEXT, BackgroundColor3 = C_CARD, Position = UDim2.fromOffset(PW - 38, 10), Size = UDim2.fromOffset(26, 26) })
corner(closeButton, 6)
local windowLabel = label(popup, { Position = UDim2.fromOffset(16, 36), Size = UDim2.fromOffset(PW - 32, 18), Font = Enum.Font.GothamBold, TextSize = 13, Text = "" })
local whenLabel = label(popup, { Position = UDim2.fromOffset(16, 54), Size = UDim2.fromOffset(PW - 32, 14), TextSize = 11, TextColor3 = C_MUTED, Text = "" })
local pickLabel = label(popup, { Position = UDim2.fromOffset(16, 74), Size = UDim2.fromOffset(PW - 32, 14), Font = Enum.Font.GothamBold, TextSize = 11, TextColor3 = C_MUTED, Text = "" })

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
            b.Text = string.format("   %s  %s Quin #%s   •   %s   •   W%d L%d", on and "[x]" or "[  ]", q.Gender or "", q.Tag, q.Title or "Rookie", q.Wins, q.Losses)
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

local function closePopup()
    popup.Visible = false
    openTerminal = nil
end

actionButton.MouseButton1Click:Connect(function()
    local ok, result, message = pcall(function()
        return entryRemote:InvokeServer("register", selectedList())
    end)
    if ok then
        setStatus(message, result and C_GREEN or C_RED)
    else
        setStatus("Could not reach the arena", C_RED)
    end
end)

withdrawButton.MouseButton1Click:Connect(function()
    local ok, _, message = pcall(function()
        return entryRemote:InvokeServer("withdraw")
    end)
    setStatus(ok and message or "Could not reach the arena", ok and C_TEXT or C_RED)
end)

closeButton.MouseButton1Click:Connect(closePopup)

ProximityPromptService.PromptTriggered:Connect(function(prompt)
    if prompt.Name == "ArenaTerminalPrompt" then
        openPopup(prompt.Parent)
    end
end)

bar.MouseButton1Click:Connect(function()
    if not popup.Visible then
        notify("Arena Terminal", "Walk up to an Arena Terminal by the arena entrance to register your Quins.")
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
        barLabel.Text = #mine > 1 and "YOUR QUINS FIGHT THIS ROUND" or "YOUR QUIN FIGHTS THIS ROUND"
        barLabel.TextColor3 = C_AMBER
        barStroke.Color = C_AMBER
    elseif entered then
        barLabel.Text = satOut > 0 and string.format("ENTERED  •  #%d  •  first next round", pos or 0)
            or string.format("ENTERED (%d)  •  #%d of %d in queue", #mine, pos or 0, entrants)
        barLabel.TextColor3 = C_GREEN
        barStroke.Color = C_GREEN
    elseif open then
        barLabel.Text = "ENTRY OPEN  •  go to an Arena Terminal" -- (the clock above names the event)
        barLabel.TextColor3 = C_AMBER
        barStroke.Color = C_STROKE
    elseif window then
        barLabel.Text = "ENTRY CLOSED FOR THIS EVENT"
        barLabel.TextColor3 = C_MUTED
        barStroke.Color = C_STROKE
    else
        barLabel.Text = "ENTRY CLOSED  •  opens 20m before events"
        barLabel.TextColor3 = C_MUTED
        barStroke.Color = C_STROKE
    end

    if popup.Visible then
        -- walked away from the terminal: close
        local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
        if openTerminal and root and (openTerminal.Position - root.Position).Magnitude > WALK_AWAY then
            closePopup()
            return
        end
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
