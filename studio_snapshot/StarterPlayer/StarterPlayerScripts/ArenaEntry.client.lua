--// ArenaEntry.client.lua
-- Entering the arena's events (ArenaRegistration on the server), under the Skylark clock:
--   * the entry bar: closed / ENTER <event> / registered, place in the queue / your Quin fights;
--   * click it for the entry panel: pick one of your Quins, Register or Withdraw, the queue rules.
-- Everything shown comes from attributes the server keeps (Workspace ArenaReg*, Player Arena*).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local QuinCore = ReplicatedStorage:WaitForChild("QuinCore")
local SkylarkTime = require(QuinCore:WaitForChild("SkylarkTime"))
local entryRemote = ReplicatedStorage:WaitForChild("ArenaNetwork"):WaitForChild("ArenaEntry", 30)

local gui = player:WaitForChild("PlayerGui"):WaitForChild("SkylarkClockUI", 30)
if not gui or not entryRemote then
    warn("[ArenaEntry] No clock UI or entry remote: entry bar not shown")
    return
end

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
    new("UIStroke", { Color = color or C_STROKE, Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = inst })
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
local barStroke = new("UIStroke", { Color = C_STROKE, Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = bar })
local barLabel = label(bar, { Position = UDim2.fromOffset(12, 0), Size = UDim2.new(1, -24, 1, 0), Font = Enum.Font.GothamBold, TextSize = 12, Text = "" })

-- ============================================================================
-- ENTRY PANEL (left of the clock)
-- ============================================================================

local PANEL_H = 300
local panel = new("Frame", {
    Name = "EntryPanel",
    Parent = gui,
    AnchorPoint = Vector2.new(1, 0),
    Position = UDim2.new(1, -16 - W - 8, 0, 12),
    Size = UDim2.fromOffset(W, PANEL_H),
    BackgroundColor3 = C_BG,
    BackgroundTransparency = 0.06,
    Visible = false,
})
corner(panel, 10)
stroke(panel)

label(panel, { Position = UDim2.fromOffset(14, 10), Size = UDim2.fromOffset(W - 60, 16), Font = Enum.Font.GothamBold, TextSize = 13, TextColor3 = C_AMBER, Text = "ARENA ENTRY" })
local closeButton = new("TextButton", { Parent = panel, Text = "X", Font = Enum.Font.GothamBold, TextSize = 11, TextColor3 = C_TEXT, BackgroundColor3 = C_CARD, Position = UDim2.fromOffset(W - 34, 8), Size = UDim2.fromOffset(22, 22) })
corner(closeButton, 5)
local windowLabel = label(panel, { Position = UDim2.fromOffset(14, 30), Size = UDim2.fromOffset(W - 28, 16), Font = Enum.Font.GothamBold, TextSize = 12, Text = "" })
local whenLabel = label(panel, { Position = UDim2.fromOffset(14, 46), Size = UDim2.fromOffset(W - 28, 14), TextSize = 11, TextColor3 = C_MUTED, Text = "" })
label(panel, { Position = UDim2.fromOffset(14, 68), Size = UDim2.fromOffset(W - 28, 14), Font = Enum.Font.GothamBold, TextSize = 11, TextColor3 = C_MUTED, Text = "YOUR QUIN" })

local QUIN_Y, QUIN_H = 86, 30
local quinButtons = {}
local selectedSlot = nil
local roster = {}

local actionButton = new("TextButton", { Parent = panel, Text = "REGISTER", Font = Enum.Font.GothamBold, TextSize = 13, TextColor3 = C_BG, BackgroundColor3 = C_AMBER, Position = UDim2.fromOffset(14, QUIN_Y + 4 * QUIN_H + 6), Size = UDim2.fromOffset(W - 28, 32) })
corner(actionButton, 6)
local statusLabel = label(panel, { Position = UDim2.fromOffset(14, QUIN_Y + 4 * QUIN_H + 42), Size = UDim2.fromOffset(W - 28, 14), TextSize = 11, Text = "" })
label(panel, {
    Position = UDim2.fromOffset(14, PANEL_H - 50),
    Size = UDim2.fromOffset(W - 28, 42),
    TextSize = 10,
    TextColor3 = C_MUTED,
    TextWrapped = true,
    TextTruncate = Enum.TextTruncate.None,
    TextYAlignment = Enum.TextYAlignment.Top,
    Text = "One Quin per round. Sat out a round? You go first next round. Empty seats are filled by arena Quins, so rounds never wait.",
})

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
            b.Text = string.format("  %d   %s %s  •  %s   W%d L%d", slot, q.Element or "?", q.Gender or "", q.Title or "Rookie", q.Wins, q.Losses)
            local selected = slot == selectedSlot
            b.BackgroundColor3 = selected and C_CARD_SEL or C_CARD
            b.TextColor3 = selected and C_AMBER or C_TEXT
        end
    end
end

for slot = 1, 4 do
    local b = new("TextButton", {
        Parent = panel,
        Text = "",
        Font = Enum.Font.Gotham,
        TextSize = 11,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextColor3 = C_TEXT,
        BackgroundColor3 = C_CARD,
        Position = UDim2.fromOffset(14, QUIN_Y + (slot - 1) * QUIN_H),
        Size = UDim2.fromOffset(W - 28, QUIN_H - 4),
        Visible = false,
    })
    corner(b, 5)
    b.MouseButton1Click:Connect(function()
        selectedSlot = slot
        refreshQuinButtons()
    end)
    quinButtons[slot] = b
end

local function loadRoster()
    local ok, result = pcall(function()
        return entryRemote:InvokeServer("roster")
    end)
    roster = ok and type(result) == "table" and result or {}
    selectedSlot = player:GetAttribute("ArenaEntrySlot") or selectedSlot or (roster[1] and roster[1].Slot)
    refreshQuinButtons()
end

local function setStatus(text, color)
    statusLabel.Text = text or ""
    statusLabel.TextColor3 = color or C_TEXT
end

actionButton.MouseButton1Click:Connect(function()
    local entered = player:GetAttribute("ArenaEntered") == true
    local enteredSlot = player:GetAttribute("ArenaEntrySlot")
    local ok, result, message
    if entered and selectedSlot == enteredSlot then
        ok, result, message = pcall(function()
            return entryRemote:InvokeServer("withdraw")
        end)
    else
        ok, result, message = pcall(function()
            return entryRemote:InvokeServer("register", selectedSlot)
        end)
    end
    if ok then
        setStatus(message, result and C_GREEN or C_RED)
    else
        setStatus("Could not reach the arena", C_RED)
    end
end)

bar.MouseButton1Click:Connect(function()
    panel.Visible = not panel.Visible
    if panel.Visible then
        setStatus("")
        loadRoster()
    end
end)
closeButton.MouseButton1Click:Connect(function()
    panel.Visible = false
end)

-- ============================================================================
-- STATE
-- ============================================================================

local function untilText(t)
    local real = SkylarkTime.realSecondsUntil(t)
    if real then
        return SkylarkTime.formatDuration(real)
    end
    return SkylarkTime.formatDuration((t - SkylarkTime.now()) / SkylarkTime.HOUR * 3600) .. " SST"
end

local function update()
    local open = Workspace:GetAttribute("ArenaRegOpen") == true
    local window = Workspace:GetAttribute("ArenaRegWindow")
    local kind = Workspace:GetAttribute("ArenaRegKind")
    local startsAt = Workspace:GetAttribute("ArenaRegStartsAt")
    local endsAt = Workspace:GetAttribute("ArenaRegEndsAt")
    local entered = player:GetAttribute("ArenaEntered") == true
    local inRound = player:GetAttribute("ArenaInRound") == true
    local pos = player:GetAttribute("ArenaQueuePos")
    local satOut = player:GetAttribute("ArenaSatOut") or 0
    local entrants = Workspace:GetAttribute("ArenaEntrants") or 0

    if inRound then
        barLabel.Text = "YOUR QUIN FIGHTS THIS ROUND"
        barLabel.TextColor3 = C_AMBER
        barStroke.Color = C_AMBER
    elseif entered then
        barLabel.Text = satOut > 0 and string.format("ENTERED  •  #%d  •  first next round", pos or 0)
            or string.format("ENTERED  •  #%d of %d in queue", pos or 0, entrants)
        barLabel.TextColor3 = C_GREEN
        barStroke.Color = C_GREEN
    elseif open then
        barLabel.Text = string.format("ENTER  %s  >", string.upper(window or "EVENT"))
        barLabel.TextColor3 = C_AMBER
        barStroke.Color = C_STROKE
    else
        barLabel.Text = "ENTRY CLOSED  •  opens 20m before events"
        barLabel.TextColor3 = C_MUTED
        barStroke.Color = C_STROKE
    end

    if panel.Visible then
        windowLabel.Text = open and string.upper(window or "") or "NO EVENT OPEN"
        if open and kind == "Live" and endsAt then
            whenLabel.Text = string.format("Live now  •  %s left  •  %d entered", untilText(endsAt), entrants)
        elseif open and startsAt then
            whenLabel.Text = string.format("Starts in %s  •  %d entered", untilText(startsAt), entrants)
        else
            whenLabel.Text = "Entry opens 20 minutes before each event"
        end
        local enteredSlot = player:GetAttribute("ArenaEntrySlot")
        if entered and selectedSlot == enteredSlot then
            actionButton.Text = "WITHDRAW"
            actionButton.BackgroundColor3 = C_CARD
            actionButton.TextColor3 = C_RED
        else
            actionButton.Text = entered and "SWITCH TO THIS QUIN" or "REGISTER"
            actionButton.BackgroundColor3 = open and C_AMBER or C_CARD
            actionButton.TextColor3 = open and C_BG or C_MUTED
        end
    end
end

player:GetAttributeChangedSignal("ArenaInRound"):Connect(function()
    if player:GetAttribute("ArenaInRound") == true then
        pcall(function()
            StarterGui:SetCore("SendNotification", {
                Title = "You're in!",
                Text = "Your Quin is in the preparation room for this round.",
                Duration = 6,
            })
        end)
    end
end)

local last = 0
RunService.RenderStepped:Connect(function()
    if os.clock() - last >= 0.25 then
        last = os.clock()
        update()
    end
end)
