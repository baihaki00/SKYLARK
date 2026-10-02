--// ArenaController.client.lua
-- Client UI & Event Controller for Arena System Orchestrator

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")

local player = Players.LocalPlayer
local QuinCore = ReplicatedStorage:WaitForChild("QuinCore")
local ArenaConfig = require(QuinCore:WaitForChild("ArenaConfig"))

local ArenaNetwork = ReplicatedStorage:WaitForChild("ArenaNetwork")
local StartMatchFunc = ArenaNetwork:WaitForChild("StartMatch")
local StopMatchEvent = ArenaNetwork:WaitForChild("StopMatch")
local SkipPhaseEvent = ArenaNetwork:WaitForChild("SkipPhase")
local UpdateTogglesEvent = ArenaNetwork:WaitForChild("UpdateToggles")
local StateReplication = ArenaNetwork:WaitForChild("StateReplication")
local UpdateAudioSettings = ArenaNetwork:FindFirstChild("UpdateAudioSettings")
if not UpdateAudioSettings then
    UpdateAudioSettings = Instance.new("RemoteEvent")
    UpdateAudioSettings.Name = "UpdateAudioSettings"
    UpdateAudioSettings.Parent = ArenaNetwork
end

local screenGui = script.Parent
screenGui.DisplayOrder = 100
screenGui.ResetOnSpawn = false

-- Color Palette
local C_BG       = Color3.fromRGB(15, 18, 26)
local C_CARD     = Color3.fromRGB(22, 27, 38)
local C_CARD_SEL = Color3.fromRGB(28, 36, 52)
local C_STROKE   = Color3.fromRGB(38, 48, 68)
local C_CYAN     = Color3.fromRGB(0, 220, 255)
local C_AMBER    = Color3.fromRGB(255, 180, 50)
local C_GREEN    = Color3.fromRGB(0, 230, 120)
local C_RED      = Color3.fromRGB(255, 60, 80)
local C_TEXT     = Color3.fromRGB(240, 245, 255)
local C_MUTED    = Color3.fromRGB(130, 145, 170)

-- State
local isWindowOpen = false
local selectedMode = "TeamBattle"
local selectedTeamSize = 4
local selectedTrack = "365"
local selectedAnthem = "ANTHEM1"
local selectedInTrack = "ts - butterflyeffect live"
local selectedPostTrack = "Bai - Tenggelam (feat. Kurt Haikal) MAXIMUS2"

local activeToggles = table.clone(ArenaConfig.DefaultToggles)
local activeDurations = table.clone(ArenaConfig.DefaultDurations)

-- Utility helpers
local function applyCorner(inst, radius)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, radius)
    c.Parent = inst
    return c
end

local function applyStroke(inst, color, thickness)
    local s = Instance.new("UIStroke")
    s.Color = color or C_STROKE
    s.Thickness = thickness or 1
    s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    s.Parent = inst
    return s
end

-- ============================================================================
-- 1. FLOATING TOGGLE PILL (DOCKED BOTTOM-RIGHT STACK: Y = -157)
-- ============================================================================
local togglePill = Instance.new("TextButton")
togglePill.Name = "ArenaTogglePill"
togglePill.Size = UDim2.new(0, 180, 0, 36)
togglePill.AnchorPoint = Vector2.new(1, 1)
togglePill.Position = UDim2.new(1, -20, 1, -157)
togglePill.BackgroundColor3 = Color3.fromRGB(18, 22, 30)
togglePill.BackgroundTransparency = 0.15
togglePill.TextColor3 = Color3.fromRGB(240, 245, 255)
togglePill.Font = Enum.Font.GothamBold
togglePill.TextSize = 12
togglePill.Text = "Arena System [O]"
togglePill.Visible = true
togglePill.Parent = screenGui
applyCorner(togglePill, 18)
local pillStroke = applyStroke(togglePill, C_CYAN, 1.5)
pillStroke.Transparency = 0.35

togglePill.MouseEnter:Connect(function()
    TweenService:Create(togglePill, TweenInfo.new(0.2), { BackgroundTransparency = 0.05 }):Play()
    TweenService:Create(pillStroke, TweenInfo.new(0.2), { Transparency = 0.1 }):Play()
end)

togglePill.MouseLeave:Connect(function()
    TweenService:Create(togglePill, TweenInfo.new(0.2), { BackgroundTransparency = 0.15 }):Play()
    TweenService:Create(pillStroke, TweenInfo.new(0.2), { Transparency = 0.35 }):Play()
end)

-- ============================================================================
-- 2. MAIN WINDOW
-- ============================================================================
local mainWindow = Instance.new("Frame")
mainWindow.Name = "ArenaMainWindow"
mainWindow.Size = UDim2.new(0, 920, 0, 620)
mainWindow.AnchorPoint = Vector2.new(0.5, 0.5)
mainWindow.Position = UDim2.new(0.5, 0, 0.5, 0)
mainWindow.BackgroundColor3 = C_BG
mainWindow.BackgroundTransparency = 0.04
mainWindow.Visible = false
mainWindow.ClipsDescendants = true
mainWindow.Active = true
mainWindow.Parent = screenGui
applyCorner(mainWindow, 16)
applyStroke(mainWindow, C_CYAN, 1.5)

-- Top Header
local header = Instance.new("Frame")
header.Name = "Header"
header.Size = UDim2.new(1, 0, 0, 60)
header.BackgroundColor3 = Color3.fromRGB(12, 15, 22)
header.BorderSizePixel = 0
header.Parent = mainWindow
applyCorner(header, 16)

local titleLbl = Instance.new("TextLabel")
titleLbl.Size = UDim2.new(0, 450, 0, 28)
titleLbl.Position = UDim2.new(0, 20, 0, 10)
titleLbl.BackgroundTransparency = 1
titleLbl.Font = Enum.Font.GothamBold
titleLbl.TextSize = 17
titleLbl.TextColor3 = C_CYAN
titleLbl.TextXAlignment = Enum.TextXAlignment.Left
titleLbl.Text = "ARENA SYSTEM ORCHESTRATOR"
titleLbl.Parent = header

local subTitleLbl = Instance.new("TextLabel")
subTitleLbl.Size = UDim2.new(0, 500, 0, 18)
subTitleLbl.Position = UDim2.new(0, 20, 0, 34)
subTitleLbl.BackgroundTransparency = 1
subTitleLbl.Font = Enum.Font.Gotham
subTitleLbl.TextSize = 11
subTitleLbl.TextColor3 = C_MUTED
subTitleLbl.TextXAlignment = Enum.TextXAlignment.Left
subTitleLbl.Text = "Argonia ArenaOne • Authoritative Match Lifecycle & Arena Control"
subTitleLbl.Parent = header

local phaseBadge = Instance.new("TextLabel")
phaseBadge.Name = "PhaseBadge"
phaseBadge.Size = UDim2.new(0, 180, 0, 28)
phaseBadge.Position = UDim2.new(1, -240, 0, 16)
phaseBadge.BackgroundColor3 = Color3.fromRGB(24, 30, 42)
phaseBadge.TextColor3 = C_GREEN
phaseBadge.Font = Enum.Font.GothamBold
phaseBadge.TextSize = 12
phaseBadge.Text = "● IDLE"
phaseBadge.Parent = header
applyCorner(phaseBadge, 14)
applyStroke(phaseBadge, Color3.fromRGB(45, 55, 75), 1)

local closeBtn = Instance.new("TextButton")
closeBtn.Name = "CloseBtn"
closeBtn.Size = UDim2.new(0, 36, 0, 36)
closeBtn.Position = UDim2.new(1, -48, 0, 12)
closeBtn.BackgroundColor3 = Color3.fromRGB(25, 30, 42)
closeBtn.TextColor3 = C_TEXT
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 15
closeBtn.Text = "✕"
closeBtn.Parent = header
applyCorner(closeBtn, 18)

closeBtn.MouseButton1Click:Connect(function()
    toggleWindow(false)
end)

-- Window Dragging Logic with Position Memory
do
    local isDragging = false
    local dragStart = Vector3.zero
    local startPos = UDim2.new()

    local function handleDragStart(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            isDragging = true
            dragStart = input.Position
            startPos = mainWindow.Position
        end
    end

    header.InputBegan:Connect(handleDragStart)
    titleLbl.InputBegan:Connect(handleDragStart)
    subTitleLbl.InputBegan:Connect(handleDragStart)

    UserInputService.InputChanged:Connect(function(input)
        if isDragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local delta = input.Position - dragStart
            mainWindow.Position = UDim2.new(
                startPos.X.Scale,
                startPos.X.Offset + delta.X,
                startPos.Y.Scale,
                startPos.Y.Offset + delta.Y
            )
        end
    end)

    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            isDragging = false
        end
    end)
end

-- ============================================================================
-- 3. TWO-COLUMN INTERIOR BODY
-- ============================================================================
local content = Instance.new("Frame")
content.Name = "Content"
content.Size = UDim2.new(1, -40, 1, -150)
content.Position = UDim2.new(0, 20, 0, 70)
content.BackgroundTransparency = 1
content.Parent = mainWindow

-- Left Column: Match Setup (Modes, Team Size, Durations)
local leftCol = Instance.new("ScrollingFrame")
leftCol.Name = "LeftColumn"
leftCol.Size = UDim2.new(0, 425, 1, 0)
leftCol.Position = UDim2.new(0, 0, 0, 0)
leftCol.BackgroundTransparency = 1
leftCol.ScrollBarThickness = 4
leftCol.ScrollBarImageColor3 = C_CYAN
leftCol.AutomaticCanvasSize = Enum.AutomaticSize.Y
leftCol.CanvasSize = UDim2.new(0, 0, 0, 0)
leftCol.Parent = content

local leftLayout = Instance.new("UIListLayout")
leftLayout.Padding = UDim.new(0, 12)
leftLayout.Parent = leftCol

-- Section 1: Match Mode Selector
local modeSecHeader = Instance.new("TextLabel")
modeSecHeader.Size = UDim2.new(1, 0, 0, 20)
modeSecHeader.BackgroundTransparency = 1
modeSecHeader.Font = Enum.Font.GothamBold
modeSecHeader.TextSize = 12
modeSecHeader.TextColor3 = C_CYAN
modeSecHeader.TextXAlignment = Enum.TextXAlignment.Left
modeSecHeader.Text = "MATCH MODE"
modeSecHeader.Parent = leftCol

local modeContainer = Instance.new("Frame")
modeContainer.Size = UDim2.new(1, 0, 0, 42)
modeContainer.BackgroundColor3 = C_CARD
modeContainer.Parent = leftCol
applyCorner(modeContainer, 10)
applyStroke(modeContainer, C_STROKE, 1)

local modeLayout = Instance.new("UIListLayout")
modeLayout.FillDirection = Enum.FillDirection.Horizontal
modeLayout.Padding = UDim.new(0, 6)
modeLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
modeLayout.VerticalAlignment = Enum.VerticalAlignment.Center
modeLayout.Parent = modeContainer

local modeButtons = {}
local modes = {
    { id = "TeamBattle", name = "Team Battle" },
    { id = "1vs1",       name = "1 vs 1 Duel" },
    { id = "FFA",        name = "Free For All" },
}

for _, m in ipairs(modes) do
    local btn = Instance.new("TextButton")
    btn.Name = "Mode_" .. m.id
    btn.Size = UDim2.new(0, 128, 0, 32)
    btn.BackgroundColor3 = (selectedMode == m.id) and C_CARD_SEL or Color3.fromRGB(18, 22, 32)
    btn.TextColor3 = (selectedMode == m.id) and C_CYAN or C_MUTED
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 11
    btn.Text = m.name
    btn.Parent = modeContainer
    applyCorner(btn, 8)
    local stroke = applyStroke(btn, (selectedMode == m.id) and C_CYAN or C_STROKE, 1)

    btn.MouseButton1Click:Connect(function()
        selectedMode = m.id
        for id, b in pairs(modeButtons) do
            local isSel = (id == selectedMode)
            b.btn.BackgroundColor3 = isSel and C_CARD_SEL or Color3.fromRGB(18, 22, 32)
            b.btn.TextColor3 = isSel and C_CYAN or C_MUTED
            b.stroke.Color = isSel and C_CYAN or C_STROKE
        end
    end)

    modeButtons[m.id] = { btn = btn, stroke = stroke }
end

-- Section 2: Team Size Selector
local sizeSecHeader = Instance.new("TextLabel")
sizeSecHeader.Size = UDim2.new(1, 0, 0, 20)
sizeSecHeader.BackgroundTransparency = 1
sizeSecHeader.Font = Enum.Font.GothamBold
sizeSecHeader.TextSize = 12
sizeSecHeader.TextColor3 = C_CYAN
sizeSecHeader.TextXAlignment = Enum.TextXAlignment.Left
sizeSecHeader.Text = "TEAM SIZE (PER SQUAD)"
sizeSecHeader.Parent = leftCol

local sizeContainer = Instance.new("Frame")
sizeContainer.Size = UDim2.new(1, 0, 0, 42)
sizeContainer.BackgroundColor3 = C_CARD
sizeContainer.Parent = leftCol
applyCorner(sizeContainer, 10)
applyStroke(sizeContainer, C_STROKE, 1)

local sizeLayout = Instance.new("UIListLayout")
sizeLayout.FillDirection = Enum.FillDirection.Horizontal
sizeLayout.Padding = UDim.new(0, 6)
sizeLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
sizeLayout.VerticalAlignment = Enum.VerticalAlignment.Center
sizeLayout.Parent = sizeContainer

local sizeButtons = {}
local sizes = { 1, 2, 4, 8, 16 }

for _, sz in ipairs(sizes) do
    local btn = Instance.new("TextButton")
    btn.Name = "Size_" .. sz
    btn.Size = UDim2.new(0, 74, 0, 32)
    btn.BackgroundColor3 = (selectedTeamSize == sz) and C_CARD_SEL or Color3.fromRGB(18, 22, 32)
    btn.TextColor3 = (selectedTeamSize == sz) and C_CYAN or C_MUTED
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 12
    btn.Text = sz .. "v" .. sz
    btn.Parent = sizeContainer
    applyCorner(btn, 8)
    local stroke = applyStroke(btn, (selectedTeamSize == sz) and C_CYAN or C_STROKE, 1)

    btn.MouseButton1Click:Connect(function()
        selectedTeamSize = sz
        for sVal, b in pairs(sizeButtons) do
            local isSel = (sVal == selectedTeamSize)
            b.btn.BackgroundColor3 = isSel and C_CARD_SEL or Color3.fromRGB(18, 22, 32)
            b.btn.TextColor3 = isSel and C_CYAN or C_MUTED
            b.stroke.Color = isSel and C_CYAN or C_STROKE
        end
    end)

    sizeButtons[sz] = { btn = btn, stroke = stroke }
end

-- Section 3: Phase Durations
local durSecHeader = Instance.new("TextLabel")
durSecHeader.Size = UDim2.new(1, 0, 0, 20)
durSecHeader.BackgroundTransparency = 1
durSecHeader.Font = Enum.Font.GothamBold
durSecHeader.TextSize = 12
durSecHeader.TextColor3 = C_CYAN
durSecHeader.TextXAlignment = Enum.TextXAlignment.Left
durSecHeader.Text = "PHASE TIMING (SECONDS)"
durSecHeader.Parent = leftCol

local durContainer = Instance.new("Frame")
durContainer.Size = UDim2.new(1, 0, 0, 215)
durContainer.BackgroundColor3 = C_CARD
durContainer.Parent = leftCol
applyCorner(durContainer, 10)
applyStroke(durContainer, C_STROKE, 1)

local durLayout = Instance.new("UIListLayout")
durLayout.Padding = UDim.new(0, 4)
durLayout.Parent = durContainer

local durPad = Instance.new("UIPadding")
durPad.PaddingTop = UDim.new(0, 8)
durPad.PaddingBottom = UDim.new(0, 8)
durPad.PaddingLeft = UDim.new(0, 12)
durPad.PaddingRight = UDim.new(0, 12)
durPad.Parent = durContainer

local durationRows = {
    { key = "ArenaOpen",            name = "1. Arena Open",            default = 10 },
    { key = "ArenaGeneration",      name = "2. Arena Generation",      default = 10 },
    { key = "PreparationRoom",      name = "3. Preparation Room",      default = 30 },
    { key = "TeleportingQuins",     name = "4. Teleport Quins",        default = 5 },
    { key = "StadiumAnthem",        name = "5. Stadium Anthem (Fixed)",default = 60 },
    { key = "GameTime",             name = "6. Game Time Limit",       default = 600 },
    { key = "WinnerDetermination",  name = "7. Victory Ceremony",     default = 8 },
    { key = "PostGame",             name = "8. Post-Game Exit",        default = 180 },
}

for _, d in ipairs(durationRows) do
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, 0, 0, 22)
    row.BackgroundTransparency = 1
    row.Parent = durContainer

    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(0.65, 0, 1, 0)
    lbl.BackgroundTransparency = 1
    lbl.Font = Enum.Font.Gotham
    lbl.TextSize = 11
    lbl.TextColor3 = C_TEXT
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Text = d.name
    lbl.Parent = row

    local tb = Instance.new("TextBox")
    tb.Size = UDim2.new(0.35, 0, 1, 0)
    tb.Position = UDim2.new(0.65, 0, 0, 0)
    tb.BackgroundColor3 = Color3.fromRGB(15, 18, 26)
    tb.TextColor3 = C_CYAN
    tb.Font = Enum.Font.GothamBold
    tb.TextSize = 11
    tb.Text = tostring(activeDurations[d.key] or d.default)
    tb.ClearTextOnFocus = false
    tb.Parent = row
    applyCorner(tb, 4)
    applyStroke(tb, C_STROKE, 1)

    tb.FocusLost:Connect(function()
        local val = tonumber(tb.Text)
        if val and val > 0 then
            activeDurations[d.key] = math.floor(val)
            tb.Text = tostring(activeDurations[d.key])
        else
            tb.Text = tostring(activeDurations[d.key] or d.default)
        end
    end)
end

-- Right Column: Toggles & Music Playlists
local rightCol = Instance.new("ScrollingFrame")
rightCol.Name = "RightColumn"
rightCol.Size = UDim2.new(0, 440, 1, 0)
rightCol.Position = UDim2.new(0, 445, 0, 0)
rightCol.BackgroundTransparency = 1
rightCol.ScrollBarThickness = 4
rightCol.ScrollBarImageColor3 = C_CYAN
rightCol.AutomaticCanvasSize = Enum.AutomaticSize.Y
rightCol.CanvasSize = UDim2.new(0, 0, 0, 0)
rightCol.Parent = content

local rightLayout = Instance.new("UIListLayout")
rightLayout.Padding = UDim.new(0, 10)
rightLayout.Parent = rightCol

-- Section 3: Feature Toggles
local togSecHeader = Instance.new("TextLabel")
togSecHeader.Size = UDim2.new(1, 0, 0, 20)
togSecHeader.BackgroundTransparency = 1
togSecHeader.Font = Enum.Font.GothamBold
togSecHeader.TextSize = 12
togSecHeader.TextColor3 = C_CYAN
togSecHeader.TextXAlignment = Enum.TextXAlignment.Left
togSecHeader.Text = "SYSTEM TOGGLES"
togSecHeader.LayoutOrder = 1
togSecHeader.Parent = rightCol

local togglesContainer = Instance.new("Frame")
togglesContainer.Size = UDim2.new(1, 0, 0, 175)
togglesContainer.BackgroundColor3 = C_CARD
togglesContainer.LayoutOrder = 2
togglesContainer.Parent = rightCol
applyCorner(togglesContainer, 10)
applyStroke(togglesContainer, C_STROKE, 1)

local togLayout = Instance.new("UIListLayout")
togLayout.Padding = UDim.new(0, 3)
togLayout.Parent = togglesContainer

local togPad = Instance.new("UIPadding")
togPad.PaddingTop = UDim.new(0, 6)
togPad.PaddingBottom = UDim.new(0, 6)
togPad.PaddingLeft = UDim.new(0, 12)
togPad.PaddingRight = UDim.new(0, 12)
togPad.Parent = togglesContainer

local toggleDefs = {
    { key = "Announcer",         name = "ARIA Stadium Announcer" },
    { key = "ProceduralMusic",   name = "Stadium Audio & Playlists" },
    { key = "ProceduralTerrain", name = "Procedural Terrain Obstacles" },
    { key = "Fireworks",         name = "Atmospheric Fireworks Show" },
    { key = "Drones",            name = "Spectator Camera Drones" },
    { key = "Screen",            name = "3D Arena Screen Jumbotron" },
    { key = "TimerPreGame",      name = "Pre-Game 5s Countdown Timer" },
}

local checkboxWidgets = {}

for _, cDef in ipairs(toggleDefs) do
    local row = Instance.new("TextButton")
    row.Size = UDim2.new(1, 0, 0, 20)
    row.BackgroundTransparency = 1
    row.Text = ""
    row.Parent = togglesContainer

    local box = Instance.new("Frame")
    box.Size = UDim2.new(0, 14, 0, 14)
    box.Position = UDim2.new(0, 0, 0.5, -7)
    box.BackgroundColor3 = activeToggles[cDef.key] and C_CYAN or Color3.fromRGB(15, 18, 26)
    box.Parent = row
    applyCorner(box, 3)
    local bStroke = applyStroke(box, C_CYAN, 1)

    local checkMark = Instance.new("TextLabel")
    checkMark.Size = UDim2.new(1, 0, 1, 0)
    checkMark.BackgroundTransparency = 1
    checkMark.Font = Enum.Font.GothamBold
    checkMark.TextSize = 10
    checkMark.TextColor3 = Color3.fromRGB(10, 15, 25)
    checkMark.Text = activeToggles[cDef.key] and "✓" or ""
    checkMark.Parent = box

    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1, -22, 1, 0)
    lbl.Position = UDim2.new(0, 22, 0, 0)
    lbl.BackgroundTransparency = 1
    lbl.Font = Enum.Font.Gotham
    lbl.TextSize = 11
    lbl.TextColor3 = C_TEXT
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Text = cDef.name
    lbl.Parent = row

    row.MouseButton1Click:Connect(function()
        activeToggles[cDef.key] = not activeToggles[cDef.key]
        local isChecked = activeToggles[cDef.key]
        box.BackgroundColor3 = isChecked and C_CYAN or Color3.fromRGB(15, 18, 26)
        checkMark.Text = isChecked and "✓" or ""
        UpdateTogglesEvent:FireServer(activeToggles)
    end)
    
    checkboxWidgets[cDef.key] = { box = box, check = checkMark, stroke = bStroke }
end

-- ============================================================================
-- Section 4: Developer Debug Audio Acoustics & Mixing
-- ============================================================================
local acousticSecHeader = Instance.new("TextLabel")
acousticSecHeader.Size = UDim2.new(1, 0, 0, 20)
acousticSecHeader.BackgroundTransparency = 1
acousticSecHeader.Font = Enum.Font.GothamBold

acousticSecHeader.TextSize = 12
acousticSecHeader.TextColor3 = C_CYAN
acousticSecHeader.TextXAlignment = Enum.TextXAlignment.Left
acousticSecHeader.Text = "AUDIO ACOUSTICS (MIXING DEBUG)"
acousticSecHeader.LayoutOrder = 3
acousticSecHeader.Parent = rightCol

local acousticsContainer = Instance.new("Frame")
acousticsContainer.Size = UDim2.new(1, 0, 0, 215)
acousticsContainer.BackgroundColor3 = C_CARD
acousticsContainer.LayoutOrder = 4
acousticsContainer.Parent = rightCol
applyCorner(acousticsContainer, 10)
applyStroke(acousticsContainer, C_STROKE, 1)

local acLayout = Instance.new("UIListLayout")
acLayout.Padding = UDim.new(0, 2)
acLayout.Parent = acousticsContainer

local acPad = Instance.new("UIPadding")
acPad.PaddingTop = UDim.new(0, 8)
acPad.PaddingBottom = UDim.new(0, 8)
acPad.PaddingLeft = UDim.new(0, 12)
acPad.PaddingRight = UDim.new(0, 12)
acPad.Parent = acousticsContainer

local speakerGrp = game:GetService("SoundService"):FindFirstChild("ArenaSpeakerGroup")
local revEffect = speakerGrp and speakerGrp:FindFirstChildOfClass("ReverbSoundEffect")
local ariaChan = speakerGrp and speakerGrp:FindFirstChild("ArenaAriaChannel")
local musicChan = speakerGrp and speakerGrp:FindFirstChild("ArenaMusicChannel")

local acousticState = {
    Volume = speakerGrp and speakerGrp.Volume or 1.0,
    ReverbDecay = revEffect and revEffect.DecayTime or 3.5,
    ReverbWet = revEffect and revEffect.WetLevel or 2.0,
    AriaVoice = ariaChan and ariaChan.Volume or 1.2,
    Music = musicChan and musicChan.Volume or 0.85,
}

local function applyAcousticLocally()
    local grp = game:GetService("SoundService"):FindFirstChild("ArenaSpeakerGroup")
    if grp then
        grp.Volume = acousticState.Volume
        local rev = grp:FindFirstChildOfClass("ReverbSoundEffect")
        if rev then
            rev.DecayTime = acousticState.ReverbDecay
            rev.WetLevel = acousticState.ReverbWet
        end
        local aChan = grp:FindFirstChild("ArenaAriaChannel")
        if aChan then
            aChan.Volume = acousticState.AriaVoice
        end
        local mChan = grp:FindFirstChild("ArenaMusicChannel")
        if mChan then
            mChan.Volume = acousticState.Music
        end
    end
    UpdateAudioSettings:FireServer(acousticState)
end

local function createSliderRow(labelPrefix, key, minVal, maxVal, defaultVal, formatStr, unit, step)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, 0, 0, 39)
    row.BackgroundTransparency = 1
    row.Parent = acousticsContainer

    local topRow = Instance.new("Frame")
    topRow.Size = UDim2.new(1, 0, 0, 16)
    topRow.BackgroundTransparency = 1
    topRow.Parent = row

    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(0.65, 0, 1, 0)
    lbl.BackgroundTransparency = 1
    lbl.Font = Enum.Font.GothamBold
    lbl.TextSize = 10
    lbl.TextColor3 = C_TEXT
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Text = labelPrefix
    lbl.Parent = topRow

    local valLbl = Instance.new("TextLabel")
    valLbl.Size = UDim2.new(0.35, 0, 1, 0)
    valLbl.Position = UDim2.new(0.65, 0, 0, 0)
    valLbl.BackgroundTransparency = 1
    valLbl.Font = Enum.Font.GothamBold
    valLbl.TextSize = 10
    valLbl.TextColor3 = C_CYAN
    valLbl.TextXAlignment = Enum.TextXAlignment.Right
    valLbl.Text = string.format(formatStr .. "%s", acousticState[key] or defaultVal, unit or "")
    valLbl.Parent = topRow

    local trackBtn = Instance.new("TextButton")
    trackBtn.Name = "TrackBtn"
    trackBtn.Size = UDim2.new(1, 0, 0, 16)
    trackBtn.Position = UDim2.new(0, 0, 0, 18)
    trackBtn.BackgroundTransparency = 1
    trackBtn.Text = ""
    trackBtn.AutoButtonColor = false
    trackBtn.Parent = row

    local trackBg = Instance.new("Frame")
    trackBg.Name = "TrackBg"
    trackBg.Size = UDim2.new(1, 0, 0, 6)
    trackBg.Position = UDim2.new(0, 0, 0.5, -3)
    trackBg.BackgroundColor3 = Color3.fromRGB(24, 32, 46)
    trackBg.BorderSizePixel = 0
    trackBg.Parent = trackBtn
    applyCorner(trackBg, 3)

    local initialRatio = math.clamp(((acousticState[key] or defaultVal) - minVal) / (maxVal - minVal), 0, 1)

    local fill = Instance.new("Frame")
    fill.Name = "Fill"
    fill.Size = UDim2.new(initialRatio, 0, 1, 0)
    fill.BackgroundColor3 = C_CYAN
    fill.BorderSizePixel = 0
    fill.Parent = trackBg
    applyCorner(fill, 3)

    local knob = Instance.new("Frame")
    knob.Name = "Knob"
    knob.Size = UDim2.new(0, 14, 0, 14)
    knob.AnchorPoint = Vector2.new(0.5, 0.5)
    knob.Position = UDim2.new(initialRatio, 0, 0.5, 0)
    knob.BackgroundColor3 = Color3.fromRGB(245, 250, 255)
    knob.Parent = trackBtn
    applyCorner(knob, 7)
    applyStroke(knob, C_CYAN, 1.5)

    local isDragging = false

    local function updateFromPos(xPos)
        local absPos = trackBg.AbsolutePosition.X
        local absSize = trackBg.AbsoluteSize.X
        if absSize <= 0 then return end
        local r = math.clamp((xPos - absPos) / absSize, 0, 1)
        local rawVal = minVal + r * (maxVal - minVal)
        if step and step > 0 then
            rawVal = math.floor(rawVal / step + 0.5) * step
            r = math.clamp((rawVal - minVal) / (maxVal - minVal), 0, 1)
        end
        acousticState[key] = rawVal
        fill.Size = UDim2.new(r, 0, 1, 0)
        knob.Position = UDim2.new(r, 0, 0.5, 0)
        valLbl.Text = string.format(formatStr .. "%s", rawVal, unit or "")
        applyAcousticLocally()
    end

    trackBtn.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            isDragging = true
            updateFromPos(input.Position.X)
        end
    end)

    trackBtn.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            isDragging = false
        end
    end)

    UserInputService.InputChanged:Connect(function(input)
        if isDragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            updateFromPos(input.Position.X)
        end
    end)

    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            isDragging = false
        end
    end)
end

-- 5 Sliders per Bai's Directive (Echo Removed):
createSliderRow("Master Volume",     "Volume",      0.0, 2.0,  1.0,  "%.2f", "x", 0.05)
createSliderRow("ARIA Voice Vol",    "AriaVoice",   0.0, 2.0,  1.2,  "%.2f", "x", 0.05)
createSliderRow("Music Channel",     "Music",       0.0, 2.0,  0.85, "%.2f", "x", 0.05)
createSliderRow("Reverb Decay",      "ReverbDecay", 0.1, 10.0, 3.5,  "%.1f", "s", 0.1)
createSliderRow("Reverb Wetness",    "ReverbWet",  -20.0, 15.0, 2.0, "%.1f", "dB", 0.5)

-- ============================================================================
-- Section 5: Music Playlists & Stadium Anthem Selection
-- ============================================================================
local musicHeaderRow = Instance.new("Frame")
musicHeaderRow.Size = UDim2.new(1, 0, 0, 24)
musicHeaderRow.BackgroundTransparency = 1
musicHeaderRow.LayoutOrder = 5
musicHeaderRow.Parent = rightCol

local musicSecHeader = Instance.new("TextLabel")
musicSecHeader.Size = UDim2.new(1, -95, 1, 0)
musicSecHeader.BackgroundTransparency = 1
musicSecHeader.Font = Enum.Font.GothamBold
musicSecHeader.TextSize = 12
musicSecHeader.TextColor3 = C_CYAN
musicSecHeader.TextXAlignment = Enum.TextXAlignment.Left
musicSecHeader.Text = "ARENA MUSIC PLAYLISTS (FOLDER-BASED)"
musicSecHeader.Parent = musicHeaderRow

local reloadMusicBtn = Instance.new("TextButton")
reloadMusicBtn.Size = UDim2.new(0, 90, 1, -2)
reloadMusicBtn.Position = UDim2.new(1, -90, 0, 1)
reloadMusicBtn.BackgroundColor3 = Color3.fromRGB(30, 42, 60)
reloadMusicBtn.TextColor3 = C_CYAN
reloadMusicBtn.Font = Enum.Font.GothamBold
reloadMusicBtn.TextSize = 10
reloadMusicBtn.Text = "Reload"
reloadMusicBtn.Parent = musicHeaderRow
applyCorner(reloadMusicBtn, 4)
applyStroke(reloadMusicBtn, C_CYAN, 1)

local function scanAnthemTracks()
    local tracks = {}
    local arenaOne = Workspace:FindFirstChild("argoniaonion") and Workspace.argoniaonion:FindFirstChild("ArenaOne")
    local folder = arenaOne and arenaOne:FindFirstChild("Anthem")
    local seen = {}
    if folder then
        for _, s in ipairs(folder:GetChildren()) do
            if s:IsA("Sound") then
                local prefix = string.match(s.Name, "^([%a%d]+)_") or s.Name
                if not seen[prefix] then
                    seen[prefix] = true
                    table.insert(tracks, {
                        Name = prefix .. " (Multi-Stem)",
                        Prefix = prefix
                    })
                end
            end
        end
    end
    if #tracks == 0 then
        table.insert(tracks, { Name = "ANTHEM1 (Multi-Stem)", Prefix = "ANTHEM1" })
    end
    return tracks
end

local function scanFolderTracks(folderName)
    local tracks = {}
    if folderName == "FantasyMusic" then return tracks end

    local arenaOne = Workspace:FindFirstChild("argoniaonion") and Workspace.argoniaonion:FindFirstChild("ArenaOne")
    local musicFolder = arenaOne and arenaOne:FindFirstChild("Music")
    local folder = musicFolder and musicFolder:FindFirstChild(folderName)
    
    if folder then
        for _, s in ipairs(folder:GetChildren()) do
            if s:IsA("Sound") then
                table.insert(tracks, {
                    Name = s.Name,
                    SoundId = s.SoundId
                })
            end
        end
    end
    table.sort(tracks, function(a, b) return a.Name < b.Name end)
    return tracks
end

-- Pre-Game Container
local preSecLbl = Instance.new("TextLabel")
preSecLbl.Size = UDim2.new(1, 0, 0, 16)
preSecLbl.BackgroundTransparency = 1
preSecLbl.Font = Enum.Font.GothamBold
preSecLbl.TextSize = 10
preSecLbl.TextColor3 = C_MUTED
preSecLbl.TextXAlignment = Enum.TextXAlignment.Left
preSecLbl.Text = "PRE-GAME MUSIC (PreGameMusic/)"
preSecLbl.LayoutOrder = 6
preSecLbl.Parent = rightCol

local preContainer = Instance.new("Frame")
preContainer.Size = UDim2.new(1, 0, 0, 85)
preContainer.BackgroundColor3 = C_CARD
preContainer.LayoutOrder = 7
preContainer.Parent = rightCol
applyCorner(preContainer, 8)
applyStroke(preContainer, C_STROKE, 1)

local preScroll = Instance.new("ScrollingFrame")
preScroll.Size = UDim2.new(1, -8, 1, -8)
preScroll.Position = UDim2.new(0, 4, 0, 4)
preScroll.BackgroundTransparency = 1
preScroll.ScrollBarThickness = 3
preScroll.ScrollBarImageColor3 = C_CYAN
preScroll.Parent = preContainer

-- Stadium Anthem Container
local anthemSecLbl = Instance.new("TextLabel")
anthemSecLbl.Size = UDim2.new(1, 0, 0, 16)
anthemSecLbl.BackgroundTransparency = 1
anthemSecLbl.Font = Enum.Font.GothamBold
anthemSecLbl.TextSize = 10
anthemSecLbl.TextColor3 = C_AMBER
anthemSecLbl.TextXAlignment = Enum.TextXAlignment.Left
anthemSecLbl.Text = "STADIUM ANTHEM (Anthem/)"
anthemSecLbl.LayoutOrder = 8
anthemSecLbl.Parent = rightCol

local anthemContainer = Instance.new("Frame")
anthemContainer.Size = UDim2.new(1, 0, 0, 65)
anthemContainer.BackgroundColor3 = C_CARD
anthemContainer.LayoutOrder = 9
anthemContainer.Parent = rightCol
applyCorner(anthemContainer, 8)
applyStroke(anthemContainer, C_STROKE, 1)

local anthemScroll = Instance.new("ScrollingFrame")
anthemScroll.Size = UDim2.new(1, -8, 1, -8)
anthemScroll.Position = UDim2.new(0, 4, 0, 4)
anthemScroll.BackgroundTransparency = 1
anthemScroll.ScrollBarThickness = 3
anthemScroll.ScrollBarImageColor3 = C_AMBER
anthemScroll.Parent = anthemContainer

-- In-Game Container
local inSecLbl = Instance.new("TextLabel")
inSecLbl.Size = UDim2.new(1, 0, 0, 16)
inSecLbl.BackgroundTransparency = 1
inSecLbl.Font = Enum.Font.GothamBold
inSecLbl.TextSize = 10
inSecLbl.TextColor3 = C_MUTED
inSecLbl.TextXAlignment = Enum.TextXAlignment.Left
inSecLbl.Text = "IN-GAME COMBAT MUSIC (InGameMusic/)"
inSecLbl.LayoutOrder = 10
inSecLbl.Parent = rightCol

local inContainer = Instance.new("Frame")
inContainer.Size = UDim2.new(1, 0, 0, 85)
inContainer.BackgroundColor3 = C_CARD
inContainer.LayoutOrder = 11
inContainer.Parent = rightCol
applyCorner(inContainer, 8)
applyStroke(inContainer, C_STROKE, 1)

local inScroll = Instance.new("ScrollingFrame")
inScroll.Size = UDim2.new(1, -8, 1, -8)
inScroll.Position = UDim2.new(0, 4, 0, 4)
inScroll.BackgroundTransparency = 1
inScroll.ScrollBarThickness = 3
inScroll.ScrollBarImageColor3 = C_CYAN
inScroll.Parent = inContainer

-- Post-Game Container
local postSecLbl = Instance.new("TextLabel")
postSecLbl.Size = UDim2.new(1, 0, 0, 16)
postSecLbl.BackgroundTransparency = 1
postSecLbl.Font = Enum.Font.GothamBold
postSecLbl.TextSize = 10
postSecLbl.TextColor3 = C_MUTED
postSecLbl.TextXAlignment = Enum.TextXAlignment.Left
postSecLbl.Text = "POST-GAME CLOSURE (PostGameMusic/)"
postSecLbl.LayoutOrder = 12
postSecLbl.Parent = rightCol

local postContainer = Instance.new("Frame")
postContainer.Size = UDim2.new(1, 0, 0, 65)
postContainer.BackgroundColor3 = C_CARD
postContainer.LayoutOrder = 13
postContainer.Parent = rightCol
applyCorner(postContainer, 8)
applyStroke(postContainer, C_STROKE, 1)

local postScroll = Instance.new("ScrollingFrame")
postScroll.Size = UDim2.new(1, -8, 1, -8)
postScroll.Position = UDim2.new(0, 4, 0, 4)
postScroll.BackgroundTransparency = 1
postScroll.ScrollBarThickness = 3
postScroll.ScrollBarImageColor3 = C_CYAN
postScroll.Parent = postContainer

local function populateTrackList(scrollFrame, tracks, getSelected, setSelected)
    scrollFrame:ClearAllChildren()
    local layout = Instance.new("UIListLayout")
    layout.Padding = UDim.new(0, 3)
    layout.Parent = scrollFrame

    local buttons = {}
    local function refreshVisuals()
        for name, item in pairs(buttons) do
            local sel = (getSelected() == name or getSelected() == item.prefix)
            item.btn.BackgroundColor3 = sel and Color3.fromRGB(35, 48, 68) or Color3.fromRGB(20, 24, 34)
            item.stroke.Color = sel and C_CYAN or C_STROKE
            item.lbl.TextColor3 = sel and C_CYAN or C_TEXT
        end
    end

    for _, track in ipairs(tracks) do
        local trackIdentifier = track.Prefix or track.Name
        local isSel = (getSelected() == track.Name or getSelected() == track.Prefix)
        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(1, -6, 0, 22)
        btn.BackgroundColor3 = isSel and Color3.fromRGB(35, 48, 68) or Color3.fromRGB(20, 24, 34)
        btn.Text = ""
        btn.Parent = scrollFrame
        applyCorner(btn, 4)
        local stroke = applyStroke(btn, isSel and C_CYAN or C_STROKE, 1)

        local lbl = Instance.new("TextLabel")
        lbl.Size = UDim2.new(1, -12, 1, 0)
        lbl.Position = UDim2.new(0, 8, 0, 0)
        lbl.BackgroundTransparency = 1
        lbl.Font = Enum.Font.Gotham
        lbl.TextSize = 10
        lbl.TextColor3 = isSel and C_CYAN or C_TEXT
        lbl.TextXAlignment = Enum.TextXAlignment.Left
        lbl.Text = "• " .. track.Name
        lbl.Parent = btn

        btn.MouseButton1Click:Connect(function()
            setSelected(trackIdentifier)
            refreshVisuals()
        end)

        buttons[track.Name] = { btn = btn, stroke = stroke, lbl = lbl, prefix = track.Prefix }
    end

    scrollFrame.CanvasSize = UDim2.new(0, 0, 0, #tracks * 25)
end

local function refreshAllPlaylists()
    local preTracks = scanFolderTracks("PreGameMusic")
    if #preTracks == 0 then preTracks = ArenaConfig.PreGamePlaylist end

    local inTracks = scanFolderTracks("InGameMusic")
    if #inTracks == 0 then inTracks = ArenaConfig.InGamePlaylist end

    local postTracks = scanFolderTracks("PostGameMusic")
    if #postTracks == 0 then postTracks = ArenaConfig.PostGamePlaylist end

    local anthemTracks = scanAnthemTracks()

    populateTrackList(preScroll, preTracks, function() return selectedTrack end, function(v) selectedTrack = v end)
    populateTrackList(inScroll, inTracks, function() return selectedInTrack end, function(v) selectedInTrack = v end)
    populateTrackList(postScroll, postTracks, function() return selectedPostTrack end, function(v) selectedPostTrack = v end)
    populateTrackList(anthemScroll, anthemTracks, function() return selectedAnthem end, function(v) selectedAnthem = v end)
end

reloadMusicBtn.MouseButton1Click:Connect(function()
    refreshAllPlaylists()
end)

refreshAllPlaylists()

-- ============================================================================
-- 4. BOTTOM ACTION & STATUS DOCK
-- ============================================================================
local bottomDock = Instance.new("Frame")
bottomDock.Name = "BottomDock"
bottomDock.Size = UDim2.new(1, 0, 0, 70)
bottomDock.Position = UDim2.new(0, 0, 1, -70)
bottomDock.BackgroundColor3 = Color3.fromRGB(12, 15, 22)
bottomDock.BorderSizePixel = 0
bottomDock.Parent = mainWindow
applyCorner(bottomDock, 16)

local liveStatusLbl = Instance.new("TextLabel")
liveStatusLbl.Name = "LiveStatus"
liveStatusLbl.Size = UDim2.new(0, 480, 0, 24)
liveStatusLbl.Position = UDim2.new(0, 20, 0, 12)
liveStatusLbl.BackgroundTransparency = 1
liveStatusLbl.Font = Enum.Font.GothamBold
liveStatusLbl.TextSize = 12
liveStatusLbl.TextColor3 = C_TEXT
liveStatusLbl.TextXAlignment = Enum.TextXAlignment.Left
liveStatusLbl.Text = "READY: Match Inactive"
liveStatusLbl.Parent = bottomDock

local liveSubStatus = Instance.new("TextLabel")
liveSubStatus.Name = "LiveSubStatus"
liveSubStatus.Size = UDim2.new(0, 480, 0, 18)
liveSubStatus.Position = UDim2.new(0, 20, 0, 36)
liveSubStatus.BackgroundTransparency = 1
liveSubStatus.Font = Enum.Font.Gotham
liveSubStatus.TextSize = 10
liveSubStatus.TextColor3 = C_MUTED
liveSubStatus.TextXAlignment = Enum.TextXAlignment.Left
liveSubStatus.Text = "Select mode and options, then click Start Match."
liveSubStatus.Parent = bottomDock

-- Action Buttons: Start, Stop, Skip (Zero Emojis)
local startBtn = Instance.new("TextButton")
startBtn.Name = "StartMatchBtn"
startBtn.Size = UDim2.new(0, 130, 0, 38)
startBtn.Position = UDim2.new(1, -380, 0, 16)
startBtn.BackgroundColor3 = C_GREEN
startBtn.TextColor3 = Color3.new(0, 0, 0)
startBtn.Font = Enum.Font.GothamBold
startBtn.TextSize = 12
startBtn.Text = "START MATCH"
startBtn.Parent = bottomDock
applyCorner(startBtn, 8)

local stopBtn = Instance.new("TextButton")
stopBtn.Name = "StopMatchBtn"
stopBtn.Size = UDim2.new(0, 110, 0, 38)
stopBtn.Position = UDim2.new(1, -240, 0, 16)
stopBtn.BackgroundColor3 = C_RED
stopBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
stopBtn.Font = Enum.Font.GothamBold
stopBtn.TextSize = 12
stopBtn.Text = "STOP"
stopBtn.Parent = bottomDock
applyCorner(stopBtn, 8)

local skipBtn = Instance.new("TextButton")
skipBtn.Name = "SkipPhaseBtn"
skipBtn.Size = UDim2.new(0, 100, 0, 38)
skipBtn.Position = UDim2.new(1, -120, 0, 16)
skipBtn.BackgroundColor3 = Color3.fromRGB(40, 48, 65)
skipBtn.TextColor3 = C_AMBER
skipBtn.Font = Enum.Font.GothamBold
skipBtn.TextSize = 11
skipBtn.Text = "SKIP"
skipBtn.Parent = bottomDock
applyCorner(skipBtn, 8)
applyStroke(skipBtn, C_AMBER, 1)

startBtn.MouseButton1Click:Connect(function()
    local cfg = {
        Mode = selectedMode,
        TeamSize = selectedTeamSize,
        SelectedTrack = selectedTrack,
        SelectedAnthem = selectedAnthem or "ANTHEM1",
        SelectedInTrack = selectedInTrack,
        SelectedPostTrack = selectedPostTrack,
        Toggles = activeToggles,
        Durations = activeDurations,
    }
    startBtn.Text = "STARTING..."
    task.spawn(function()
        local ok = pcall(function()
            StartMatchFunc:InvokeServer(cfg)
        end)
        startBtn.Text = "START MATCH"
    end)
end)

stopBtn.MouseButton1Click:Connect(function()
    StopMatchEvent:FireServer()
end)

skipBtn.MouseButton1Click:Connect(function()
    SkipPhaseEvent:FireServer()
end)

-- ============================================================================
-- 5. WINDOW TOGGLE & RELIABLE DUAL HOTKEY (O) BINDING
-- ============================================================================
function toggleWindow(force)
    if force ~= nil then
        isWindowOpen = force
    else
        isWindowOpen = not isWindowOpen
    end
    
    mainWindow.Visible = isWindowOpen
    togglePill.TextColor3 = isWindowOpen and C_CYAN or Color3.fromRGB(240, 245, 255)
    pillStroke.Color = isWindowOpen and C_CYAN or Color3.fromRGB(0, 200, 255)
end

togglePill.MouseButton1Click:Connect(function()
    toggleWindow()
end)

-- Reliable High-Priority Hotkey Binding via ContextActionService
local function handleToggleAction(actionName, inputState, inputObj)
    if inputState == Enum.UserInputState.Begin then
        if UserInputService:GetFocusedTextBox() then
            return Enum.ContextActionResult.Pass
        end
        toggleWindow()
        return Enum.ContextActionResult.Sink
    end
    return Enum.ContextActionResult.Pass
end

ContextActionService:BindActionAtPriority(
    "ToggleArenaOrchestratorHotKey",
    handleToggleAction,
    false,
    Enum.ContextActionPriority.High.Value,
    Enum.KeyCode.O
)

-- Fallback UserInputService listener
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if UserInputService:GetFocusedTextBox() then return end
    if input.KeyCode == Enum.KeyCode.O then
        toggleWindow()
    end
end)

-- ============================================================================
-- 6. STATE REPLICATION SYNC
-- ============================================================================
StateReplication.OnClientEvent:Connect(function(snap)
    if not snap then return end
    
    local phaseColor = C_GREEN
    if snap.Phase == "IDLE" then
        phaseColor = C_MUTED
    elseif snap.Phase == "ARENA_OPEN" or snap.Phase == "ARENA_GENERATION" then
        phaseColor = C_CYAN
    elseif snap.Phase == "PREPARATION_ROOM" or snap.Phase == "TELEPORTING_QUINS" or snap.Phase == "PRE_GAME" or snap.Phase == "STADIUM_ANTHEM" then
        phaseColor = C_AMBER
    elseif snap.Phase == "IN_GAME" then
        phaseColor = C_RED
    elseif snap.Phase == "WINNER_DETERMINATION" then
        phaseColor = Color3.fromRGB(255, 215, 0)
    elseif snap.Phase == "POST_GAME" then
        phaseColor = Color3.fromRGB(150, 180, 255)
    end
    
    phaseBadge.Text = string.format("● %s (%ds)", snap.Phase, snap.TimeRemaining or 0)
    phaseBadge.TextColor3 = phaseColor
    
    if snap.Phase == "IDLE" then
        liveStatusLbl.Text = "READY: Match Inactive"
        liveSubStatus.Text = "Select mode and options, then click Start Match."
    else
        liveStatusLbl.Text = string.format("PHASE: %s • TIME LEFT: %ds", snap.Phase, snap.TimeRemaining or 0)
        liveSubStatus.Text = string.format("Alpha: %d/%d (Alive: %d)  |  Beta: %d/%d (Alive: %d)",
            math.floor(snap.AlphaHp or 0), math.floor(snap.AlphaMax or 0), snap.AlphaAlive or 0,
            math.floor(snap.BetaHp or 0), math.floor(snap.BetaMax or 0), snap.BetaAlive or 0
        )
    end
end)

print("[ArenaController] Initialized with docked pill at Y=-157 and KeyCode.O.")
