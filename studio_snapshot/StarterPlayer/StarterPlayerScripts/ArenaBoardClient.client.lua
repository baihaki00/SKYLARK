--// ArenaBoardClient.client.lua
-- The Arena Boards and Arena Prebook Terminals around Argonia (ArenaRegistration: prebook):
--   * each board's faces show the next event's prebook board: the event, when booking closes,
--     today's price, and each side's owners with their Quins under them (record, condition band,
--     Bond band, the habits fights have revealed; never their plans), with each side's strength;
--   * a prebook terminal's "Prebook Quins" prompt opens the booking dialog (PrebookUI): pick your
--     Quins and a side, see the price and the deposit, book; or see your booking and cancel it.
-- (Tests: set the player's PrebookOpen attribute to true.)

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ProximityPromptService = game:GetService("ProximityPromptService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local QuinCore = ReplicatedStorage:WaitForChild("QuinCore")
local SkylarkTime = require(QuinCore:WaitForChild("SkylarkTime"))
local entryRemote = ReplicatedStorage:WaitForChild("ArenaNetwork"):WaitForChild("ArenaEntry", 60)

local C_BG = Color3.fromRGB(15, 18, 26)
local C_CARD = Color3.fromRGB(22, 27, 38)
local C_STROKE = Color3.fromRGB(38, 48, 68)
local C_CYAN = Color3.fromRGB(0, 220, 255)
local C_AMBER = Color3.fromRGB(255, 180, 50)
local C_GREEN = Color3.fromRGB(0, 230, 120)
local C_RED = Color3.fromRGB(255, 60, 80)
local C_TEXT = Color3.fromRGB(240, 245, 255)
local C_MUTED = Color3.fromRGB(130, 145, 170)
local SIDE_COLOR = { TeamAlpha = C_CYAN, TeamBeta = C_AMBER }

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
    new("UICorner", { Parent = inst, CornerRadius = UDim.new(0, r or 8) })
end

local function label(parent, props)
    local t = {
        Parent = parent, BackgroundTransparency = 1, Font = Enum.Font.Gotham, TextSize = 14,
        TextColor3 = C_TEXT, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
    }
    for k, v in pairs(props) do
        t[k] = v
    end
    return new("TextLabel", t)
end

local function button(parent, name, text, props)
    local t = {
        Name = name, Parent = parent, Text = text, Font = Enum.Font.GothamBold, TextSize = 14, TextColor3 = C_TEXT,
        BackgroundColor3 = C_CARD, AutoButtonColor = true,
    }
    for k, v in pairs(props) do
        t[k] = v
    end
    local b = new("TextButton", t)
    corner(b, 6)
    new("UIStroke", { Parent = b, Color = C_STROKE, Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border })
    return b
end

-- "12:00 SST  •  1h 12m left" (just the Skylark time while the clock is paused)
local function closesAt(t)
    if not t then
        return "--:--"
    end
    local text = SkylarkTime.formatHours(SkylarkTime.info(t).Hours) .. " SST"
    local s = SkylarkTime.realSecondsUntil(t)
    if s then
        text ..= "  •  " .. SkylarkTime.formatDuration(s) .. " left"
    end
    return text
end

local function boards()
    local list = {}
    for _, d in ipairs(Workspace:GetDescendants()) do
        if d.Name == "ArenaBoard" and d:IsA("BasePart") then
            table.insert(list, d)
        end
    end
    return list
end

local view = nil -- the last "board" from the server

-- ============================================================================
-- THE BOARD FACES
-- ============================================================================

local PPS = 25 -- pixels per stud: a 36 x 23 board is 900 x 575
local screens = {} -- { gui, header, status, price, columns = { TeamAlpha = frame, TeamBeta = frame }, bars, foot }

local function buildScreen(board, face)
    local gui = new("SurfaceGui", {
        Name = "ArenaBoardScreen", Parent = playerGui, Adornee = board, Face = face, ResetOnSpawn = false,
        SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud, PixelsPerStud = PPS, LightInfluence = 0, ClipsDescendants = true,
    })
    local root = new("Frame", { Parent = gui, BackgroundColor3 = C_BG, Size = UDim2.fromScale(1, 1), BorderSizePixel = 0 })
    new("UIPadding", { Parent = root, PaddingLeft = UDim.new(0, 24), PaddingRight = UDim.new(0, 24), PaddingTop = UDim.new(0, 16), PaddingBottom = UDim.new(0, 12) })
    local header = label(root, { Size = UDim2.new(1, 0, 0, 40), Font = Enum.Font.GothamBlack, TextSize = 36, TextColor3 = C_CYAN, Text = "ARENA BOARD" })
    local status = label(root, { Position = UDim2.fromOffset(0, 44), Size = UDim2.new(0.6, 0, 0, 24), Font = Enum.Font.GothamBold, TextSize = 20 })
    local price = label(root, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 6), Size = UDim2.new(0.4, 0, 0, 30), Font = Enum.Font.GothamBlack,
        TextSize = 26, TextColor3 = C_AMBER, TextXAlignment = Enum.TextXAlignment.Right })
    local priceSub = label(root, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 40), Size = UDim2.new(0.4, 0, 0, 22), TextSize = 16,
        TextColor3 = C_MUTED, TextXAlignment = Enum.TextXAlignment.Right })
    local columns, bars = {}, {}
    for i, side in ipairs({ "TeamAlpha", "TeamBeta" }) do
        local col = new("Frame", { Parent = root, BackgroundColor3 = C_CARD, BorderSizePixel = 0,
            Position = UDim2.new((i - 1) * 0.5, i == 1 and 0 or 8, 0, 78), Size = UDim2.new(0.5, -8, 1, -114) })
        corner(col, 8)
        new("UIStroke", { Parent = col, Color = SIDE_COLOR[side], Thickness = 2, Transparency = 0.4 })
        label(col, { Position = UDim2.fromOffset(14, 8), Size = UDim2.new(1, -28, 0, 26), Font = Enum.Font.GothamBlack, TextSize = 24,
            TextColor3 = SIDE_COLOR[side], Text = side == "TeamAlpha" and "ALPHA" or "BETA" })
        local track = new("Frame", { Parent = col, BackgroundColor3 = C_STROKE, BorderSizePixel = 0, Position = UDim2.fromOffset(14, 38), Size = UDim2.new(1, -28, 0, 6) })
        bars[side] = new("Frame", { Parent = track, BackgroundColor3 = SIDE_COLOR[side], BorderSizePixel = 0, Size = UDim2.fromScale(0.5, 1) })
        local list = new("Frame", { Name = "List", Parent = col, BackgroundTransparency = 1, Position = UDim2.fromOffset(14, 52), Size = UDim2.new(1, -28, 1, -58), ClipsDescendants = true })
        new("UIListLayout", { Parent = list, Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder })
        columns[side] = list
    end
    local foot = label(root, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 24), TextSize = 17, TextColor3 = C_MUTED })
    table.insert(screens, { board = board, gui = gui, header = header, status = status, price = price, priceSub = priceSub, columns = columns, bars = bars, foot = foot })
end

local drawScreens -- (forward)

-- (the place streams: a board gets its screens when it streams in, and loses them when it goes)
local function addBoard(board)
    for _, s in ipairs(screens) do
        if s.board == board then
            return
        end
    end
    -- both big faces: a 1-stud-thick board's faces are Right and Left
    local thin = board.Size.X <= math.min(board.Size.Y, board.Size.Z) and "X" or "Z"
    if thin == "X" then
        buildScreen(board, Enum.NormalId.Right)
        buildScreen(board, Enum.NormalId.Left)
    else
        buildScreen(board, Enum.NormalId.Front)
        buildScreen(board, Enum.NormalId.Back)
    end
    if drawScreens then
        pcall(drawScreens)
    end
end

local function dropBoard(board)
    for i = #screens, 1, -1 do
        if screens[i].board == board then
            screens[i].gui:Destroy()
            table.remove(screens, i)
        end
    end
end

for _, board in ipairs(boards()) do
    addBoard(board)
end
Workspace.DescendantAdded:Connect(function(d)
    if d.Name == "ArenaBoard" and d:IsA("BasePart") then
        addBoard(d)
    end
end)
Workspace.DescendantRemoving:Connect(function(d)
    if d.Name == "ArenaBoard" and d:IsA("BasePart") then
        dropBoard(d)
    end
end)

local function fillColumn(list, owners)
    for _, c in ipairs(list:GetChildren()) do
        if not c:IsA("UIListLayout") then
            c:Destroy()
        end
    end
    local order = 0
    for _, owner in ipairs(owners) do
        order += 1
        label(list, { LayoutOrder = order, Size = UDim2.new(1, 0, 0, 28), Font = Enum.Font.GothamBold, TextSize = 22, Text = owner.Name })
        for _, q in ipairs(owner.Quins) do
            order += 1
            local revealed = #q.Revealed > 0 and ("  •  " .. table.concat(q.Revealed, ", ")) or ""
            label(list, { LayoutOrder = order, Size = UDim2.new(1, 0, 0, 22), TextSize = 17, TextColor3 = C_MUTED,
                Text = string.format("    #%s %s  •  W%d L%d  •  %s  •  %s%s", q.Tag, q.Temperament, q.Wins, q.Losses, q.Condition, q.Bond, revealed) })
        end
    end
    if order == 0 then
        label(list, { Size = UDim2.new(1, 0, 0, 20), TextSize = 15, TextColor3 = C_MUTED, Text = "No prebookings yet" })
    end
end

drawScreens = function()
    local v = view
    for _, s in ipairs(screens) do
        if not v or not v.Event then
            s.header.Text = "ARENA BOARD"
            s.status.Text = "No event ahead"
            s.price.Text = ""
            s.priceSub.Text = ""
        else
            s.header.Text = string.upper(v.Event)
            if v.Open then
                s.status.Text = "PREBOOK OPEN  •  closes " .. closesAt(v.StartsAt)
                s.status.TextColor3 = C_GREEN
                s.price.Text = string.format("%d SC a round", v.Rate)
                s.priceSub.Text = v.Rate < v.Fee and string.format("%d%% off now  •  full price %d at the start", math.floor((1 - v.Rate / v.Fee) * 100 + 0.5), v.Fee) or "Full price"
            else
                s.status.Text = v.Live and "LIVE NOW  •  walk in at an Arena Terminal" or "PREBOOK CLOSED"
                s.status.TextColor3 = v.Live and C_AMBER or C_MUTED
                s.price.Text = ""
                s.priceSub.Text = ""
            end
            fillColumn(s.columns.TeamAlpha, v.Alpha)
            fillColumn(s.columns.TeamBeta, v.Beta)
            local a, b = v.Strength.Alpha, v.Strength.Beta
            local total = math.max(1, a + b)
            s.bars.TeamAlpha.Size = UDim2.fromScale(a + b > 0 and a / total or 0.5, 1)
            s.bars.TeamBeta.Size = UDim2.fromScale(a + b > 0 and b / total or 0.5, 1)
            s.foot.Text = string.format("Up to %d Quin%s per owner  •  booking early is cheaper  •  prebook at the Arena Prebook Terminal%s",
                v.PerPlayer, v.PerPlayer > 1 and "s" or "", v.WalkIns > 0 and string.format("  •  %d walk-in%s", v.WalkIns, v.WalkIns > 1 and "s" or "") or "")
        end
    end
end

local function fetch()
    local ok, result = pcall(function()
        return entryRemote:InvokeServer("board")
    end)
    if ok and type(result) == "table" then
        view = result
    end
end

local drawnVersion = nil
task.spawn(function()
    local lastFetch = 0
    while true do
        local version = Workspace:GetAttribute("ArenaPrebookVersion")
        if version ~= drawnVersion or os.clock() - lastFetch > 15 then
            drawnVersion = version
            lastFetch = os.clock()
            fetch()
            pcall(drawScreens)
        else
            for _, s in ipairs(screens) do -- (the countdown ticks)
                if view and view.Open then
                    s.status.Text = "PREBOOK OPEN  •  closes " .. closesAt(view.StartsAt)
                end
            end
        end
        task.wait(1)
    end
end)

-- ============================================================================
-- THE PREBOOK DIALOG
-- ============================================================================

local gui = new("ScreenGui", { Name = "PrebookUI", Parent = playerGui, ResetOnSpawn = false, DisplayOrder = 85, Enabled = false })
local card = new("Frame", {
    Name = "PrebookCard", Parent = gui, BackgroundColor3 = C_BG, BackgroundTransparency = 0.04,
    AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(520, 420),
})
corner(card, 12)
new("UIStroke", { Parent = card, Color = C_CYAN, Thickness = 1.5 })
local title = label(card, { Position = UDim2.fromOffset(18, 14), Size = UDim2.fromOffset(440, 22), Font = Enum.Font.GothamBold, TextSize = 18, TextColor3 = C_CYAN, Text = "PREBOOK" })
local closeButton = button(card, "PrebookClose", "X", { Position = UDim2.fromOffset(474, 12), Size = UDim2.fromOffset(30, 26) })
local subtitle = label(card, { Position = UDim2.fromOffset(18, 38), Size = UDim2.fromOffset(484, 16), TextSize = 12, TextColor3 = C_MUTED })
local body = new("Frame", { Name = "PrebookBody", Parent = card, BackgroundTransparency = 1, Position = UDim2.fromOffset(18, 64), Size = UDim2.fromOffset(484, 300) })
local status = label(card, { Name = "PrebookStatus", Position = UDim2.fromOffset(18, 376), Size = UDim2.fromOffset(484, 34), TextSize = 13, TextWrapped = true, TextTruncate = Enum.TextTruncate.None })

local roster = nil
local picked = {} -- [slot] = true
local pickedSide = nil

local refresh -- (forward)

local function clearBody()
    for _, c in ipairs(body:GetChildren()) do
        c:Destroy()
    end
end

local function drawBooked()
    label(body, { Size = UDim2.fromOffset(484, 22), Font = Enum.Font.GothamBold, TextSize = 16, TextColor3 = C_GREEN,
        Text = string.format("You're prebooked on %s.", player:GetAttribute("ArenaPrebookSide") == "TeamBeta" and "BETA" or "ALPHA") })
    label(body, { Position = UDim2.fromOffset(0, 28), Size = UDim2.fromOffset(484, 60), TextSize = 13, TextColor3 = C_MUTED, TextWrapped = true,
        TextTruncate = Enum.TextTruncate.None, TextYAlignment = Enum.TextYAlignment.Top,
        Text = "Your Quins are seated first, on your side, every round of the event. A deposit you never use comes back when the event ends. Cancelling keeps 25% of what's unused." })
    button(body, "PrebookCancel", "CANCEL PREBOOK", { Position = UDim2.fromOffset(0, 100), Size = UDim2.fromOffset(484, 36), BackgroundColor3 = C_RED }).MouseButton1Click:Connect(function()
        status.Text = "..."
        local ok, msg = entryRemote:InvokeServer("cancel")
        status.Text = tostring(msg or "")
        status.TextColor3 = ok and C_GREEN or C_RED
        refresh()
    end)
end

local function drawBooking()
    local v = view
    local perPlayer = v and v.PerPlayer or 1
    label(body, { Size = UDim2.fromOffset(484, 18), Font = Enum.Font.GothamBold, TextSize = 13, TextColor3 = C_MUTED,
        Text = string.format("YOUR QUINS  (up to %d)", perPlayer) })
    local count = 0
    for slot in pairs(picked) do
        count += 1
    end
    for i, q in ipairs(roster or {}) do
        local on = picked[q.Slot] == true
        local b = button(body, "PrebookQuin" .. q.Slot, string.format("   %s  Quin #%s   •   W%d L%d   •   %d%%%s", on and "[x]" or "[  ]", q.Tag, q.Wins, q.Losses,
            q.Condition or 100, q.Busy and ("   •   busy: " .. q.Busy) or ""), {
            Position = UDim2.fromOffset(0, 22 + (i - 1) * 32), Size = UDim2.fromOffset(484, 28), TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left,
            BackgroundColor3 = on and C_STROKE or C_CARD,
        })
        b.MouseButton1Click:Connect(function()
            if picked[q.Slot] then
                picked[q.Slot] = nil
            elseif count < perPlayer then
                picked[q.Slot] = true
            end
            refresh(true)
        end)
    end
    local y = 22 + #(roster or {}) * 32 + 8
    label(body, { Position = UDim2.fromOffset(0, y), Size = UDim2.fromOffset(484, 18), Font = Enum.Font.GothamBold, TextSize = 13, TextColor3 = C_MUTED, Text = "SIDE" })
    for i, side in ipairs({ "TeamAlpha", "TeamBeta" }) do
        local on = pickedSide == side
        button(body, side == "TeamAlpha" and "PrebookAlpha" or "PrebookBeta", side == "TeamAlpha" and "ALPHA" or "BETA", {
            Position = UDim2.fromOffset((i - 1) * 246, y + 20), Size = UDim2.fromOffset(238, 30),
            BackgroundColor3 = on and SIDE_COLOR[side] or C_CARD, TextColor3 = on and C_BG or SIDE_COLOR[side],
        }).MouseButton1Click:Connect(function()
            pickedSide = side
            refresh(true)
        end)
    end
    y += 60
    local rate = v and v.Rate or 100
    label(body, { Position = UDim2.fromOffset(0, y), Size = UDim2.fromOffset(484, 34), TextSize = 13, TextWrapped = true, TextTruncate = Enum.TextTruncate.None,
        TextYAlignment = Enum.TextYAlignment.Top,
        Text = string.format("%d SC a round per Quin for the whole event. Deposit now: %d SC (counts as the first round).", rate, rate * math.max(1, count)) })
    local ready = count > 0 and pickedSide ~= nil
    button(body, "PrebookBook", ready and string.format("PREBOOK  •  %d SC", rate * count) or "PICK QUINS AND A SIDE", {
        Position = UDim2.fromOffset(0, y + 40), Size = UDim2.fromOffset(484, 36),
        BackgroundColor3 = ready and C_AMBER or C_STROKE, TextColor3 = C_BG,
    }).MouseButton1Click:Connect(function()
        if not ready then
            return
        end
        local slots = {}
        for slot in pairs(picked) do
            table.insert(slots, slot)
        end
        table.sort(slots)
        status.Text = "..."
        status.TextColor3 = C_MUTED
        local ok, msg = entryRemote:InvokeServer("prebook", { slots = slots, side = pickedSide })
        status.Text = tostring(msg or "")
        status.TextColor3 = ok and C_GREEN or C_RED
        refresh()
    end)
end

refresh = function(local_only)
    if not local_only then
        fetch()
        local ok, result = pcall(function()
            return entryRemote:InvokeServer("roster")
        end)
        if ok and type(result) == "table" then
            roster = result
        end
    end
    clearBody()
    local v = view
    title.Text = v and v.Event and ("PREBOOK  •  " .. string.upper(v.Event)) or "PREBOOK"
    subtitle.Text = v and v.Open and ("Booking closes " .. closesAt(v.StartsAt) .. ". Booking early is cheaper.")
        or (v and v.Live and "The event is live. Walk in at an Arena Terminal." or "Prebooking is closed.")
    if player:GetAttribute("ArenaPrebooked") then
        drawBooked()
    elseif v and v.Open then
        drawBooking()
    end
end

local function open()
    picked, pickedSide = {}, nil
    status.Text = ""
    gui.Enabled = true
    refresh()
end

local function close()
    gui.Enabled = false
    player:SetAttribute("PrebookOpen", nil)
end

closeButton.MouseButton1Click:Connect(close)

ProximityPromptService.PromptTriggered:Connect(function(prompt)
    if prompt.Name == "ArenaPrebookPrompt" then
        open()
    end
end)

player:GetAttributeChangedSignal("PrebookOpen"):Connect(function()
    if player:GetAttribute("PrebookOpen") then
        open()
    end
end)
