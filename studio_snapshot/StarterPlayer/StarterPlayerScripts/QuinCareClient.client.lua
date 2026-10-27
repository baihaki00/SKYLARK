--// QuinCareClient.client.lua
-- The dialog at the three care stations (QuinCare on the server, ArenaNetwork.QuinCare):
--   * Quin Workshop: each Quin's condition, what a repair costs, how long free rest takes;
--   * Quin Trainer: pick a habit, up or down, and a session (Short / Normal / Long);
--   * Quin Specialist: what you know of each habit (Low / Mid / High, its drift, what you train),
--     and an appraisal for what you don't.
-- Opens from the station's prompt. (Tests: set the player's QuinCareOpen attribute to Workshop,
-- Trainer or Specialist.)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ProximityPromptService = game:GetService("ProximityPromptService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local remote = ReplicatedStorage:WaitForChild("ArenaNetwork"):WaitForChild("QuinCare", 60)

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
        Name = name, Parent = parent, Text = text, Font = Enum.Font.GothamBold, TextSize = 13, TextColor3 = C_TEXT,
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

local function minutes(realSeconds)
    local m = math.ceil((realSeconds or 0) / 60)
    if m >= 60 then
        return string.format("%dh %02dm", m // 60, m % 60)
    end
    return m .. " min"
end

-- ============================================================================
-- THE DIALOG
-- ============================================================================

local gui = new("ScreenGui", { Name = "QuinCareUI", Parent = playerGui, ResetOnSpawn = false, DisplayOrder = 85, Enabled = false })
local card = new("Frame", {
    Name = "CareCard", Parent = gui, BackgroundColor3 = C_BG, BackgroundTransparency = 0.04,
    AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(560, 440),
})
corner(card, 12)
local stroke = new("UIStroke", { Parent = card, Color = C_CYAN, Thickness = 1.5 })
local title = label(card, { Position = UDim2.fromOffset(18, 14), Size = UDim2.fromOffset(400, 22), Font = Enum.Font.GothamBold, TextSize = 18, TextColor3 = C_CYAN })
local balanceLabel = label(card, { Position = UDim2.fromOffset(300, 14), Size = UDim2.fromOffset(200, 22), TextSize = 14, TextColor3 = C_AMBER, TextXAlignment = Enum.TextXAlignment.Right })
local closeButton = button(card, "CareClose", "X", { Position = UDim2.fromOffset(514, 12), Size = UDim2.fromOffset(30, 26) })
local subtitle = label(card, { Position = UDim2.fromOffset(18, 38), Size = UDim2.fromOffset(524, 16), TextSize = 12, TextColor3 = C_MUTED })

-- left: your Quins
local quinList = new("Frame", { Name = "CareQuins", Parent = card, BackgroundTransparency = 1, Position = UDim2.fromOffset(18, 64), Size = UDim2.fromOffset(170, 320) })
new("UIListLayout", { Parent = quinList, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder })
-- right: what the station does
local panel = new("Frame", { Name = "CarePanel", Parent = card, BackgroundColor3 = C_CARD, Position = UDim2.fromOffset(200, 64), Size = UDim2.fromOffset(342, 320) })
corner(panel, 8)
local status = label(card, { Name = "CareStatus", Position = UDim2.fromOffset(18, 394), Size = UDim2.fromOffset(524, 32), TextSize = 13, TextWrapped = true, TextTruncate = Enum.TextTruncate.None })

local station = nil -- "Workshop" | "Trainer" | "Specialist"
local data = nil -- the last "list"
local selectedSlot = nil
local pick = { habit = nil, dir = 1, session = "Normal", tab = "Habits", drill = nil }
local HABITS = { "Aggression", "RiskTolerance", "DashPreference", "RetreatTendency", "TargetPersistence",
    "Protectiveness", "MobilityPreference", "SpecialPreference", "Confidence", "Awareness" }
local NAMES = { Aggression = "Aggression", RiskTolerance = "Risk", DashPreference = "Dash", RetreatTendency = "Retreat",
    TargetPersistence = "Focus", Protectiveness = "Protect", MobilityPreference = "Mobility",
    SpecialPreference = "Special", Confidence = "Confidence", Awareness = "Awareness" }

local refresh -- (forward)

local function selected()
    for _, q in ipairs(data and data.Quins or {}) do
        if q.Slot == selectedSlot then
            return q
        end
    end
    return nil
end

local function busyText(q)
    if not q.Busy then
        return nil
    end
    if q.Busy.Kind == "Training" then
        return string.format("Training %s %s  •  %s left", q.Busy.Habit or "", q.Busy.Dir == 1 and "up" or "down", minutes(q.Busy.Left))
    elseif q.Busy.Kind == "Drill" then
        return string.format("Drilling %s  •  %s left", q.Busy.Drill or "", minutes(q.Busy.Left))
    end
    return string.format("In the Workshop  •  %s left", minutes(q.Busy.Left))
end

local function clear(frame)
    for _, c in ipairs(frame:GetChildren()) do
        if not c:IsA("UIListLayout") and not c:IsA("UICorner") then
            c:Destroy()
        end
    end
end

local function act(...)
    status.Text = "..."
    status.TextColor3 = C_MUTED
    local ok, msg = remote:InvokeServer(...)
    status.Text = tostring(msg or "")
    status.TextColor3 = ok and C_GREEN or C_RED
    refresh(true)
end

local function drawWorkshop(q)
    label(panel, { Position = UDim2.fromOffset(14, 12), Size = UDim2.fromOffset(314, 22), Font = Enum.Font.GothamBold, TextSize = 16,
        Text = string.format("Condition %d%%", q.Condition) })
    local bar = new("Frame", { Parent = panel, BackgroundColor3 = C_STROKE, Position = UDim2.fromOffset(14, 40), Size = UDim2.fromOffset(314, 10) })
    corner(bar, 4)
    local fill = new("Frame", { Parent = bar, BackgroundColor3 = q.Condition >= 60 and C_GREEN or C_AMBER, Size = UDim2.fromScale(q.Condition / 100, 1) })
    corner(fill, 4)
    local fights = 0.75 + 0.25 * q.Condition / 100
    label(panel, { Position = UDim2.fromOffset(14, 58), Size = UDim2.fromOffset(314, 60), TextSize = 12, TextColor3 = C_MUTED, TextWrapped = true,
        TextTruncate = Enum.TextTruncate.None, TextYAlignment = Enum.TextYAlignment.Top,
        Text = string.format("It fights at %d%% of its health and energy. Fights wear it down; rest brings it back for free (+5%% a Skylark hour), the Workshop at once for SC.", math.floor(fights * 100 + 0.5)) })
    local y = 124
    local busy = busyText(q)
    if busy then
        label(panel, { Position = UDim2.fromOffset(14, y), Size = UDim2.fromOffset(314, 20), TextColor3 = C_AMBER, Text = busy })
        return
    end
    if q.Condition >= 100 then
        label(panel, { Position = UDim2.fromOffset(14, y), Size = UDim2.fromOffset(314, 20), TextColor3 = C_GREEN, Text = "In full condition." })
        return
    end
    label(panel, { Position = UDim2.fromOffset(14, y), Size = UDim2.fromOffset(314, 20), Text = "Free rest: full in " .. minutes(q.RestFullIn) })
    button(panel, "CareRepair", string.format("REPAIR TO 100%%  •  %d SC  •  10 min", q.RepairCost), {
        Position = UDim2.fromOffset(14, y + 32), Size = UDim2.fromOffset(314, 36), BackgroundColor3 = C_AMBER, TextColor3 = C_BG,
    }).MouseButton1Click:Connect(function()
        act("repair", q.Slot)
    end)
end

-- HABITS | DRILLS along the top of the Trainer
local function trainerTabs()
    for i, tab in ipairs({ "Habits", "Drills" }) do
        local on = pick.tab == tab
        button(panel, "Tab" .. tab, string.upper(tab), {
            Position = UDim2.fromOffset(14 + (i - 1) * 160, 6), Size = UDim2.fromOffset(152, 22), TextSize = 12,
            BackgroundColor3 = on and C_CYAN or C_BG, TextColor3 = on and C_BG or C_TEXT,
        }).MouseButton1Click:Connect(function()
            pick.tab = tab
            refresh(false)
        end)
    end
end

local function sessionButtons(y)
    for i, name in ipairs({ "Short", "Normal", "Long" }) do
        local s = data.Sessions[name]
        local on = pick.session == name
        button(panel, "Session" .. name, string.format("%s  %dh  %d SC", name, s.hours, s.cost), {
            Position = UDim2.fromOffset(14 + (i - 1) * 106, y), Size = UDim2.fromOffset(100, 26), TextSize = 11,
            BackgroundColor3 = on and C_CYAN or C_BG, TextColor3 = on and C_BG or C_TEXT,
        }).MouseButton1Click:Connect(function()
            pick.session = name
            refresh(false)
        end)
    end
end

local function drawDrills(q)
    local busy = busyText(q)
    local max = data.DrillMax or 10
    for i, d in ipairs(data.DrillList or {}) do
        local level = (q.Drills or {})[d.key] or 0
        local on = pick.drill == d.key
        local y = 36 + (i - 1) * 38
        button(panel, "Drill_" .. d.key, string.format("%s  %.1f / %d", d.key, level, max), {
            Position = UDim2.fromOffset(14, y), Size = UDim2.fromOffset(130, 30), TextSize = 12,
            BackgroundColor3 = on and C_CYAN or C_BG, TextColor3 = on and C_BG or C_TEXT,
        }).MouseButton1Click:Connect(function()
            pick.drill = d.key
            refresh(false)
        end)
        local bar = new("Frame", { Parent = panel, BackgroundColor3 = C_STROKE, Position = UDim2.fromOffset(152, y + 4), Size = UDim2.fromOffset(176, 6) })
        corner(bar, 3)
        corner(new("Frame", { Parent = bar, BackgroundColor3 = C_GREEN, Size = UDim2.fromScale(math.clamp(level / max, 0, 1), 1) }), 3)
        label(panel, { Position = UDim2.fromOffset(152, y + 12), Size = UDim2.fromOffset(176, 16), TextSize = 11, TextColor3 = C_MUTED, Text = d.text })
    end
    sessionButtons(196)
    label(panel, { Position = UDim2.fromOffset(14, 228), Size = UDim2.fromOffset(314, 40), TextSize = 11, TextWrapped = true,
        TextTruncate = Enum.TextTruncate.None, TextColor3 = busy and C_AMBER or C_MUTED, TextYAlignment = Enum.TextYAlignment.Top,
        Text = busy or string.format("Bond %d (more bond, more from a session)  •  condition %d%%, a session costs it 5%%. Every Quin starts equal; drills add a little.", q.Bond, q.Condition) })
    local level = pick.drill and (q.Drills or {})[pick.drill] or 0
    local ready = pick.drill ~= nil and not busy and level < max
    button(panel, "CareDrill", ready and string.format("DRILL %s", string.upper(pick.drill)) or (pick.drill and level >= max and "AS FAR AS IT GOES" or "PICK A DRILL"), {
        Position = UDim2.fromOffset(14, 276), Size = UDim2.fromOffset(314, 34), BackgroundColor3 = ready and C_AMBER or C_STROKE, TextColor3 = C_BG,
    }).MouseButton1Click:Connect(function()
        if ready then
            act("drill", q.Slot, pick.drill, pick.session)
        end
    end)
end

local function drawTrainer(q)
    trainerTabs()
    if pick.tab == "Drills" then
        drawDrills(q)
        return
    end
    local busy = busyText(q)
    -- habits, two columns
    for i, habit in ipairs(HABITS) do
        local col, row = (i - 1) % 2, (i - 1) // 2
        local on = pick.habit == habit
        button(panel, "Habit_" .. habit, NAMES[habit], {
            Position = UDim2.fromOffset(14 + col * 160, 34 + row * 30), Size = UDim2.fromOffset(152, 26), TextSize = 12,
            BackgroundColor3 = on and C_CYAN or C_BG, TextColor3 = on and C_BG or C_TEXT,
        }).MouseButton1Click:Connect(function()
            pick.habit = habit
            refresh(false)
        end)
    end
    -- direction
    for i, dir in ipairs({ 1, -1 }) do
        local on = pick.dir == dir
        button(panel, dir == 1 and "DirUp" or "DirDown", dir == 1 and "UP" or "DOWN", {
            Position = UDim2.fromOffset(14 + (i - 1) * 160, 190), Size = UDim2.fromOffset(152, 26),
            BackgroundColor3 = on and C_CYAN or C_BG, TextColor3 = on and C_BG or C_TEXT,
        }).MouseButton1Click:Connect(function()
            pick.dir = dir
            refresh(false)
        end)
    end
    -- session
    sessionButtons(224)
    label(panel, { Position = UDim2.fromOffset(14, 254), Size = UDim2.fromOffset(314, 16), TextSize = 11, TextColor3 = busy and C_AMBER or C_MUTED,
        Text = busy or string.format("Bond %d  •  cond %d%%, -5%% a session  •  1 Skylark h = 20 min", q.Bond, q.Condition) })
    local ready = pick.habit ~= nil and not busy
    button(panel, "CareTrain", ready and string.format("TRAIN %s %s", string.upper(NAMES[pick.habit]), pick.dir == 1 and "UP" or "DOWN") or "PICK A HABIT", {
        Position = UDim2.fromOffset(14, 276), Size = UDim2.fromOffset(314, 34), BackgroundColor3 = ready and C_AMBER or C_STROKE, TextColor3 = C_BG,
    }).MouseButton1Click:Connect(function()
        if ready then
            act("train", q.Slot, pick.habit, pick.dir, pick.session)
        end
    end)
end

local function drawSpecialist(q)
    label(panel, { Position = UDim2.fromOffset(14, 10), Size = UDim2.fromOffset(314, 18), TextSize = 12, TextColor3 = C_MUTED,
        Text = string.format("%d fights  •  fights show its strongest habits from 10 on", q.Battles) })
    for i, h in ipairs(q.Habits) do
        local y = 32 + (i - 1) * 22
        label(panel, { Position = UDim2.fromOffset(14, y), Size = UDim2.fromOffset(110, 20), TextSize = 13, Text = h.Name })
        local text = h.Band or "?"
        if h.Trend then
            text ..= h.Trend > 0 and "  ^" or "  v"
        end
        label(panel, { Position = UDim2.fromOffset(124, y), Size = UDim2.fromOffset(90, 20), Font = Enum.Font.GothamBold, TextSize = 13,
            TextColor3 = h.Band == "High" and C_GREEN or (h.Band == "Low" and C_RED or (h.Band and C_TEXT or C_MUTED)), Text = text })
        local note = h.Source == "appraisal" and "appraisal" or (h.Source == "fights" and "seen in fights" or "")
        if h.Training then
            note ..= (note ~= "" and "  •  " or "") .. (h.Training > 0 and "training up" or "training down")
        end
        label(panel, { Position = UDim2.fromOffset(214, y), Size = UDim2.fromOffset(120, 20), TextSize = 11, TextColor3 = C_MUTED, Text = note })
    end
    local when = q.AppraisedAt and data.Now and math.floor((data.Now - q.AppraisedAt) / 1200) or nil
    button(panel, "CareAppraise", string.format("APPRAISE  •  %d SC%s", data.AppraiseCost,
        when and string.format("  (last: %dh ago)", when) or ""), {
        Position = UDim2.fromOffset(14, 260), Size = UDim2.fromOffset(314, 34), BackgroundColor3 = C_AMBER, TextColor3 = C_BG,
    }).MouseButton1Click:Connect(function()
        act("appraise", q.Slot)
    end)
    label(panel, { Position = UDim2.fromOffset(14, 298), Size = UDim2.fromOffset(314, 16), TextSize = 11, TextColor3 = C_MUTED,
        Text = "A reading is true the day it's made. Habits drift." })
end

local function draw()
    clear(quinList)
    clear(panel)
    if not data then
        return
    end
    balanceLabel.Text = string.format("%d SC", data.Balance or 0)
    if #data.Quins == 0 then
        status.Text = "You have no Quins."
        return
    end
    if not selected() then
        selectedSlot = data.Quins[1].Slot
    end
    for i, q in ipairs(data.Quins) do
        local on = q.Slot == selectedSlot
        local b = button(quinList, "CareQuin" .. q.Slot, "", {
            LayoutOrder = i, Size = UDim2.fromOffset(170, 50), BackgroundColor3 = on and C_STROKE or C_CARD,
        })
        label(b, { Position = UDim2.fromOffset(10, 6), Size = UDim2.fromOffset(150, 18), Font = Enum.Font.GothamBold, TextSize = 13,
            Text = string.format("Quin #%s  %s", q.Tag, q.Temperament or "") })
        label(b, { Position = UDim2.fromOffset(10, 26), Size = UDim2.fromOffset(150, 16), TextSize = 11,
            TextColor3 = q.Busy and C_AMBER or (q.Condition >= 60 and C_GREEN or C_AMBER),
            Text = q.Busy and (q.Busy.Kind == "Training" and "Training" or "In the Workshop") or string.format("Condition %d%%", q.Condition) })
        b.MouseButton1Click:Connect(function()
            selectedSlot = q.Slot
            refresh(false)
        end)
    end
    local q = selected()
    if station == "Workshop" then
        drawWorkshop(q)
    elseif station == "Trainer" then
        drawTrainer(q)
    else
        drawSpecialist(q)
    end
end

refresh = function(fetch)
    if fetch or not data then
        local ok, result = pcall(function()
            return remote:InvokeServer("list")
        end)
        if ok and type(result) == "table" then
            data = result
        end
    end
    draw()
end

local TITLES = {
    Workshop = { "QUIN WORKSHOP", "Repairs: a worn Quin fights worn." },
    Trainer = { "QUIN TRAINER", "Sessions push one habit up or down. Fights pull less against what you train." },
    Specialist = { "QUIN SPECIALIST", "What its habits are now." },
}

local function open(kind)
    if not TITLES[kind] then
        return
    end
    station = kind
    title.Text = TITLES[kind][1]
    subtitle.Text = TITLES[kind][2]
    stroke.Color = kind == "Workshop" and C_AMBER or C_CYAN
    status.Text = ""
    gui.Enabled = true
    refresh(true)
end

local function close()
    gui.Enabled = false
    station = nil
    player:SetAttribute("QuinCareOpen", nil)
end

closeButton.MouseButton1Click:Connect(close)

ProximityPromptService.PromptTriggered:Connect(function(prompt)
    if prompt.Name == "QuinCarePrompt" then
        open(prompt:GetAttribute("Station"))
    end
end)

player:GetAttributeChangedSignal("QuinCareOpen"):Connect(function()
    local kind = player:GetAttribute("QuinCareOpen")
    if kind then
        open(kind)
    end
end)

-- timers tick while it's open
task.spawn(function()
    while true do
        task.wait(5)
        if gui.Enabled then
            refresh(true)
        end
    end
end)
