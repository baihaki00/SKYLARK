--// SkylarkClock.client.lua
-- The Skylark clock on each client:
--   * day cycle lighting: Lighting follows the Skylark hour (dawn, day, dusk, night) and the season
--     tints the picture. Switch: Workspace attribute SkylarkDayCycle (off: the place's own lighting).
--   * the top bar (right side, on the Roblox buttons' line): [TIME (admin)] [MENU] [SC] [clock].
--     The clock is the time only (SST time and period); what the arenas are doing (the slot now,
--     the next event, the day strip, the week, entry) is in the player menu's SCHEDULE, per arena:
--     click the clock to open it. ArenaEntry adds the SC pill, PlayerMenuClient the MENU button.
--   * TIME debug panel (Studio / the place's creator; the TIME button or F7): leave real time,
--     scrub the hour, jump days and seasons, pause or speed the clock, back to real time, and the
--     Day Cycle / Auto Events switches. Commands go to SkylarkScheduleService, so every client and
--     the arena see the same moment.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local QuinCore = ReplicatedStorage:WaitForChild("QuinCore")
local SkylarkTime = require(QuinCore:WaitForChild("SkylarkTime"))
local ArenaSchedule = require(QuinCore:WaitForChild("ArenaSchedule"))
local ArenaNetwork = ReplicatedStorage:WaitForChild("ArenaNetwork")
local debugRemote = ArenaNetwork:WaitForChild("SkylarkTimeDebug", 30)

local isOwner = RunService:IsStudio()
    or (game.CreatorType == Enum.CreatorType.User and player.UserId == game.CreatorId)

-- Colour palette (the Arena System panel's)
local C_BG = Color3.fromRGB(15, 18, 26)
local C_CARD = Color3.fromRGB(22, 27, 38)
local C_CARD_SEL = Color3.fromRGB(28, 36, 52)
local C_STROKE = Color3.fromRGB(38, 48, 68)
local C_CYAN = Color3.fromRGB(0, 220, 255)
local C_AMBER = Color3.fromRGB(255, 180, 50)
local C_GREEN = Color3.fromRGB(0, 230, 120)
local C_TEXT = Color3.fromRGB(240, 245, 255)
local C_MUTED = Color3.fromRGB(130, 145, 170)

local KIND_COLORS = {
    Event = C_AMBER,
    Open = C_CYAN,
    Closing = Color3.fromRGB(180, 140, 255),
    Rest = Color3.fromRGB(90, 100, 125),
}

-- ============================================================================
-- DAY CYCLE LIGHTING
-- ============================================================================
-- Keys by Skylark hour; a value left out is the place's own (authored) lighting, which is the day.

local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
local authored = {
    ClockTime = Lighting.ClockTime,
    Brightness = Lighting.Brightness,
    Ambient = Lighting.Ambient,
    OutdoorAmbient = Lighting.OutdoorAmbient,
    ExposureCompensation = Lighting.ExposureCompensation,
    AtmosphereColor = atmosphere and atmosphere.Color,
    AtmosphereDecay = atmosphere and atmosphere.Decay,
}

local NIGHT = {
    Brightness = 1.2,
    Ambient = Color3.fromRGB(55, 60, 82),
    OutdoorAmbient = Color3.fromRGB(72, 82, 118),
    ExposureCompensation = 0.15,
    AtmosphereColor = Color3.fromRGB(70, 80, 110),
    AtmosphereDecay = Color3.fromRGB(40, 46, 72),
}
local DAWN = {
    Brightness = 2.2,
    Ambient = Color3.fromRGB(105, 92, 90),
    OutdoorAmbient = Color3.fromRGB(150, 122, 112),
    AtmosphereColor = Color3.fromRGB(255, 196, 160),
    AtmosphereDecay = Color3.fromRGB(205, 130, 100),
}
local DUSK = {
    Brightness = 2.2,
    Ambient = Color3.fromRGB(115, 92, 84),
    OutdoorAmbient = Color3.fromRGB(170, 120, 100),
    AtmosphereColor = Color3.fromRGB(255, 170, 120),
    AtmosphereDecay = Color3.fromRGB(190, 100, 80),
}
local DAY = {}

local KEYS = {
    { 0, NIGHT }, { 5, NIGHT }, { 6.5, DAWN }, { 9, DAY },
    { 16.5, DAY }, { 18, DUSK }, { 19.5, NIGHT }, { 24, NIGHT },
}

local SEASON_TINT = {
    Spring = { TintColor = Color3.fromRGB(248, 255, 242), Saturation = 0.08, Contrast = 0, Brightness = 0 },
    Summer = { TintColor = Color3.fromRGB(255, 250, 236), Saturation = 0.12, Contrast = 0.04, Brightness = 0 },
    Fall = { TintColor = Color3.fromRGB(255, 236, 216), Saturation = 0.02, Contrast = 0.03, Brightness = 0 },
    Winter = { TintColor = Color3.fromRGB(236, 244, 255), Saturation = -0.15, Contrast = 0, Brightness = 0.02 },
}

local function keyValue(key, prop)
    local v = key[prop]
    if v == nil then
        v = authored[prop]
    end
    return v
end

local function blend(a, b, alpha)
    if typeof(a) == "Color3" then
        return a:Lerp(b, alpha)
    end
    return a + (b - a) * alpha
end

local function applyLighting(hours)
    local k1, k2 = KEYS[1], KEYS[2]
    for i = 1, #KEYS - 1 do
        if hours >= KEYS[i][1] and hours <= KEYS[i + 1][1] then
            k1, k2 = KEYS[i], KEYS[i + 1]
            break
        end
    end
    local span = k2[1] - k1[1]
    local alpha = span > 0 and (hours - k1[1]) / span or 0
    alpha = alpha * alpha * (3 - 2 * alpha)
    local function get(prop)
        return blend(keyValue(k1[2], prop), keyValue(k2[2], prop), alpha)
    end
    Lighting.ClockTime = hours
    Lighting.Brightness = get("Brightness")
    Lighting.Ambient = get("Ambient")
    Lighting.OutdoorAmbient = get("OutdoorAmbient")
    Lighting.ExposureCompensation = get("ExposureCompensation")
    if atmosphere and authored.AtmosphereColor then
        atmosphere.Color = get("AtmosphereColor")
        atmosphere.Decay = get("AtmosphereDecay")
    end
end

local function restoreLighting()
    Lighting.ClockTime = authored.ClockTime
    Lighting.Brightness = authored.Brightness
    Lighting.Ambient = authored.Ambient
    Lighting.OutdoorAmbient = authored.OutdoorAmbient
    Lighting.ExposureCompensation = authored.ExposureCompensation
    if atmosphere and authored.AtmosphereColor then
        atmosphere.Color = authored.AtmosphereColor
        atmosphere.Decay = authored.AtmosphereDecay
    end
end

local seasonFx = nil
local shownSeason = nil
local function applySeason(season)
    if season == shownSeason then
        return
    end
    shownSeason = season
    if not seasonFx then
        seasonFx = Instance.new("ColorCorrectionEffect")
        seasonFx.Name = "SkylarkSeason"
        seasonFx.Parent = Lighting
    end
    seasonFx.Enabled = true
    TweenService:Create(seasonFx, TweenInfo.new(1.5), SEASON_TINT[season]):Play()
end

local cycleWasOn = false
local function updateLighting(info)
    local on = Workspace:GetAttribute("SkylarkDayCycle") ~= false
    if on then
        applyLighting(info.Hours)
        applySeason(info.Season)
    elseif cycleWasOn then
        restoreLighting()
        if seasonFx then
            seasonFx.Enabled = false
        end
        shownSeason = nil
    end
    cycleWasOn = on
end

-- ============================================================================
-- UI HELPERS
-- ============================================================================

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

local function button(parent, text, x, y, w, h, onClick)
    local b = new("TextButton", {
        Parent = parent,
        Text = text,
        Font = Enum.Font.GothamBold,
        TextSize = 11,
        TextColor3 = C_TEXT,
        BackgroundColor3 = C_CARD,
        AutoButtonColor = true,
        Position = UDim2.fromOffset(x, y),
        Size = UDim2.fromOffset(w, h),
    })
    corner(b, 6)
    stroke(b)
    b.MouseButton1Click:Connect(onClick)
    return b
end

local gui = new("ScreenGui", {
    Name = "SkylarkClockUI",
    ResetOnSpawn = false,
    DisplayOrder = 60,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    Parent = player:WaitForChild("PlayerGui"),
})

-- ============================================================================
-- TOP BAR
-- ============================================================================
-- Level with the Roblox menu buttons (GuiService.TopbarInset), right-aligned. Children are laid
-- out by LayoutOrder: TIME 0, MENU 1, SC 2, clock 3 (the clock sits at the far right).

gui.ScreenInsets = Enum.ScreenInsets.None -- (placed against the topbar inset by hand)

local BAR_H = 44
local topBar = new("Frame", { Name = "TopBar", Parent = gui, AnchorPoint = Vector2.new(1, 0), Size = UDim2.fromOffset(640, BAR_H), BackgroundTransparency = 1 })
new("UIListLayout", {
    Parent = topBar,
    FillDirection = Enum.FillDirection.Horizontal,
    HorizontalAlignment = Enum.HorizontalAlignment.Right,
    VerticalAlignment = Enum.VerticalAlignment.Center,
    SortOrder = Enum.SortOrder.LayoutOrder,
    Padding = UDim.new(0, 8),
})

local WIDGET_W = 214
local widget = new("TextButton", {
    Name = "Clock",
    Parent = topBar,
    LayoutOrder = 3,
    Text = "",
    AutoButtonColor = true,
    Size = UDim2.fromOffset(WIDGET_W, BAR_H),
    BackgroundColor3 = C_BG,
    BackgroundTransparency = 0.12,
})
corner(widget, BAR_H // 2)
stroke(widget)

local timeLabel = label(widget, { Position = UDim2.fromOffset(18, 0), Size = UDim2.fromOffset(70, BAR_H), Font = Enum.Font.GothamBold, TextSize = 22, Text = "--:--" })
local periodLabel = label(widget, { Position = UDim2.fromOffset(92, 0), Size = UDim2.fromOffset(WIDGET_W - 104, BAR_H), Font = Enum.Font.GothamBold, TextSize = 12, TextColor3 = C_AMBER, Text = "SST" })

local debugBadge = label(widget, {
    AnchorPoint = Vector2.new(1, 0),
    Position = UDim2.new(1, -10, 1, 4), -- (under the clock)
    Size = UDim2.fromOffset(0, 18),
    AutomaticSize = Enum.AutomaticSize.X,
    Font = Enum.Font.GothamBold,
    TextSize = 11,
    TextColor3 = C_BG,
    TextXAlignment = Enum.TextXAlignment.Center,
    TextTruncate = Enum.TextTruncate.None,
    Text = "DEBUG TIME",
    Visible = false,
    ZIndex = 3,
})
debugBadge.BackgroundTransparency = 0
debugBadge.BackgroundColor3 = C_AMBER
corner(debugBadge, 5)
new("UIPadding", { Parent = debugBadge, PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6) })

widget.MouseButton1Click:Connect(function()
    if shared.OpenPlayerMenu then -- (PlayerMenuClient)
        shared.OpenPlayerMenu("SCHEDULE")
    end
end)

local debugPanel = nil
local barRight, barY = 12, 12
local function placeTopBar()
    local inset = GuiService.TopbarInset
    local view = Workspace.CurrentCamera and Workspace.CurrentCamera.ViewportSize or Vector2.new(1280, 720)
    barY = inset.Height > 0 and math.floor(inset.Min.Y + (inset.Height - BAR_H) / 2) or 12
    barRight = math.max(12, math.floor(view.X - inset.Max.X))
    topBar.Position = UDim2.new(1, -barRight, 0, barY)
    if debugPanel then
        debugPanel.Position = UDim2.new(1, -barRight, 0, barY + BAR_H + 30)
    end
end
placeTopBar()
GuiService:GetPropertyChangedSignal("TopbarInset"):Connect(placeTopBar)
if Workspace.CurrentCamera then
    Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(placeTopBar)
end

-- ============================================================================
-- TIME DEBUG PANEL (owner)
-- ============================================================================

local refreshDebug = function() end

local function send(action, value)
    if debugRemote then
        debugRemote:FireServer(action, value)
    end
end

if isOwner then
    local PANEL_W, INNER_W = 300, 272
    debugPanel = new("Frame", {
        Name = "TimeDebug",
        Parent = gui,
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -16, 0, 90), -- (under the top bar: placeTopBar)
        Size = UDim2.fromOffset(PANEL_W, 300),
        BackgroundColor3 = C_BG,
        BackgroundTransparency = 0.06,
        Visible = false,
    })
    corner(debugPanel, 10)
    stroke(debugPanel, C_AMBER)

    label(debugPanel, { Position = UDim2.fromOffset(14, 10), Size = UDim2.fromOffset(120, 16), Font = Enum.Font.GothamBold, TextSize = 13, TextColor3 = C_AMBER, Text = "TIME DEBUG" })
    local modeLabel = label(debugPanel, { Position = UDim2.fromOffset(130, 10), Size = UDim2.fromOffset(156, 16), Font = Enum.Font.GothamBold, TextSize = 11, TextXAlignment = Enum.TextXAlignment.Right, Text = "" })

    -- Hour slider: drag to any Skylark hour of the current day
    local track = new("TextButton", { Parent = debugPanel, Text = "", AutoButtonColor = false, Position = UDim2.fromOffset(14, 34), Size = UDim2.fromOffset(INNER_W, 26), BackgroundTransparency = 1 })
    local rail = new("Frame", { Parent = track, AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(0, 0.5), Size = UDim2.new(1, 0, 0, 8), BackgroundColor3 = C_CARD, BorderSizePixel = 0 })
    corner(rail, 4)
    for _, entry in ipairs(ArenaSchedule.DAILY) do
        new("Frame", { Parent = rail, Position = UDim2.new(entry.From / 24, 1, 0, 1), Size = UDim2.new((entry.To - entry.From) / 24, -2, 1, -2), BackgroundColor3 = KIND_COLORS[entry.Kind], BackgroundTransparency = 0.4, BorderSizePixel = 0 })
    end
    local knob = new("Frame", { Parent = track, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0, 0.5), Size = UDim2.fromOffset(10, 22), BackgroundColor3 = C_TEXT, BorderSizePixel = 0, ZIndex = 2 })
    corner(knob, 3)
    for h = 0, 24, 6 do
        label(debugPanel, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(14 + INNER_W * h / 24, 60), Size = UDim2.fromOffset(24, 12), TextSize = 10, TextColor3 = C_MUTED, TextXAlignment = Enum.TextXAlignment.Center, Text = string.format("%02d", h) })
    end

    local dragging, dragHour, lastSend = false, nil, 0
    local function hourAtX(x)
        return math.clamp((x - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 0.9999) * 24
    end
    local function dragTo(x, force)
        dragHour = hourAtX(x)
        knob.Position = UDim2.fromScale(dragHour / 24, 0.5)
        if force or os.clock() - lastSend > 0.06 then
            lastSend = os.clock()
            send("hour", dragHour)
        end
    end
    track.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragTo(input.Position.X, true)
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            dragTo(input.Position.X, false)
        end
    end)
    UserInputService.InputEnded:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then
            dragging = false
            dragTo(input.Position.X, true)
            dragHour = nil
        end
    end)

    -- A row of equal buttons across the panel
    local function row(y, items)
        local gap = 6
        local w = (INNER_W - gap * (#items - 1)) / #items
        local made = {}
        for i, item in ipairs(items) do
            made[i] = button(debugPanel, item[1], 14 + (i - 1) * (w + gap), y, w, 26, item[2])
        end
        return made
    end

    local H, D = SkylarkTime.HOUR, SkylarkTime.DAY
    row(80, {
        { "-1 DAY", function() send("shift", -D) end },
        { "-1 H", function() send("shift", -H) end },
        { "+1 H", function() send("shift", H) end },
        { "+1 DAY", function() send("shift", D) end },
    })
    row(112, {
        { "- SEASON", function() send("shift", -D * SkylarkTime.SEASON_DAYS) end },
        { "+ SEASON", function() send("shift", D * SkylarkTime.SEASON_DAYS) end },
    })
    local RATES = { 0, 1, 60, 360, 1800 }
    local rateButtons = row(144, {
        { "PAUSE", function() send("rate", 0) end },
        { "1x", function() send("rate", 1) end },
        { "60x", function() send("rate", 60) end },
        { "360x", function() send("rate", 360) end },
        { "1800x", function() send("rate", 1800) end },
    })
    row(176, {
        { "00:00", function() send("hour", 0) end },
        { "06:00", function() send("hour", 6) end },
        { "12:00", function() send("hour", 12) end },
        { "18:00", function() send("hour", 18) end },
    })
    local realButton = row(208, { { "BACK TO REAL TIME", function() send("real") end } })[1]
    local toggles = row(240, {
        { "DAY CYCLE", function() send("daycycle", Workspace:GetAttribute("SkylarkDayCycle") == false) end },
        { "AUTO EVENTS", function() send("autoevents", Workspace:GetAttribute("SkylarkAutoEvents") ~= true) end },
    })
    label(debugPanel, { Position = UDim2.fromOffset(14, 274), Size = UDim2.fromOffset(INNER_W, 14), TextSize = 10, TextColor3 = C_MUTED, Text = "F7 opens this panel  •  1 SST hour = 20 real minutes" })

    refreshDebug = function(info)
        local debugOn = SkylarkTime.isDebug()
        local rate = SkylarkTime.rate()
        if debugOn then
            modeLabel.Text = rate == 0 and "DEBUG, PAUSED" or string.format("DEBUG, %gx", rate)
            modeLabel.TextColor3 = C_AMBER
        else
            modeLabel.Text = "REAL TIME (UTC)"
            modeLabel.TextColor3 = C_GREEN
        end
        if not dragging then
            knob.Position = UDim2.fromScale(info.Hours / 24, 0.5)
        end
        for i, b in ipairs(rateButtons) do
            local selected = debugOn and rate == RATES[i]
            b.BackgroundColor3 = selected and Color3.fromRGB(70, 55, 20) or C_CARD
            b.TextColor3 = selected and C_AMBER or C_TEXT
        end
        realButton.BackgroundColor3 = debugOn and Color3.fromRGB(20, 60, 40) or C_CARD
        realButton.TextColor3 = debugOn and C_GREEN or C_MUTED
        local cycle = Workspace:GetAttribute("SkylarkDayCycle") ~= false
        local auto = Workspace:GetAttribute("SkylarkAutoEvents") == true
        toggles[1].Text = "DAY CYCLE: " .. (cycle and "ON" or "OFF")
        toggles[1].TextColor3 = cycle and C_GREEN or C_MUTED
        toggles[2].Text = "AUTO EVENTS: " .. (auto and "ON" or "OFF")
        toggles[2].TextColor3 = auto and C_GREEN or C_MUTED
    end

    local timeButton = new("TextButton", {
        Name = "TimeButton",
        Parent = topBar,
        LayoutOrder = 0,
        Text = "TIME",
        Font = Enum.Font.GothamBold,
        TextSize = 11,
        TextColor3 = C_AMBER,
        BackgroundColor3 = C_BG,
        BackgroundTransparency = 0.12,
        Size = UDim2.fromOffset(60, BAR_H),
    })
    corner(timeButton, BAR_H // 2)
    stroke(timeButton, C_AMBER)
    timeButton.MouseButton1Click:Connect(function()
        debugPanel.Visible = not debugPanel.Visible
    end)
    UserInputService.InputBegan:Connect(function(input, gameProcessed)
        if not gameProcessed and input.KeyCode == Enum.KeyCode.F7 and (shared.IsAdmin and shared.IsAdmin()) then
            debugPanel.Visible = not debugPanel.Visible
        end
    end)
    placeTopBar()
    -- (the TIME panel is an admin tool: SkylarkRoles)
    task.spawn(function()
        while timeButton.Parent do
            local admin = (shared.IsAdmin and shared.IsAdmin())
            timeButton.Visible = admin
            if not admin then
                debugPanel.Visible = false
            end
            task.wait(0.5)
        end
    end)
end

-- ============================================================================
-- PER FRAME
-- ============================================================================

local function updateWidget(info)
    timeLabel.Text = SkylarkTime.formatHours(info.Hours)
    periodLabel.Text = "SST • " .. string.upper(info.Period)
    local debugOn = SkylarkTime.isDebug()
    debugBadge.Visible = debugOn
    if debugOn then
        local rate = SkylarkTime.rate()
        debugBadge.Text = rate == 0 and "DEBUG • PAUSED" or string.format("DEBUG • %gx", rate)
    end
end

local lastLight, lastText = 0, 0
RunService.RenderStepped:Connect(function()
    local now = os.clock()
    if now - lastLight < 1 / 30 then
        return
    end
    lastLight = now
    local info = SkylarkTime.info()
    updateLighting(info)
    if now - lastText >= 0.2 then
        lastText = now
        updateWidget(info)
        if debugPanel and debugPanel.Visible then
            refreshDebug(info)
        end
    end
end)
