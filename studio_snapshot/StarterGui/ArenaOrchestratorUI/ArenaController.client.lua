--// ArenaController.client.lua
-- Client UI & Event Controller for Arena System Orchestrator

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

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
togglePill.Text = "🏟️ Arena System [O]"
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
titleLbl.Text = "🏟️ ARENA SYSTEM ORCHESTRATOR"
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

-- Content Container
local content = Instance.new("Frame")
content.Name = "Content"
content.Size = UDim2.new(1, -40, 1, -145)
content.Position = UDim2.new(0, 20, 0, 72)
content.BackgroundTransparency = 1
content.Parent = mainWindow

-- Left Column (Game Modes & Timing Knobs)
local leftCol = Instance.new("ScrollingFrame")
leftCol.Name = "LeftColumn"
leftCol.Size = UDim2.new(0, 430, 1, 0)
leftCol.BackgroundTransparency = 1
leftCol.ScrollBarThickness = 4
leftCol.ScrollBarImageColor3 = C_CYAN
leftCol.CanvasSize = UDim2.new(0, 0, 0, 620)
leftCol.Parent = content

local leftLayout = Instance.new("UIListLayout")
leftLayout.Padding = UDim.new(0, 12)
leftLayout.SortOrder = Enum.SortOrder.LayoutOrder
leftLayout.Parent = leftCol

-- Section 1: Game Modes
local modeSecHeader = Instance.new("TextLabel")
modeSecHeader.Size = UDim2.new(1, 0, 0, 20)
modeSecHeader.BackgroundTransparency = 1
modeSecHeader.Font = Enum.Font.GothamBold
modeSecHeader.TextSize = 12
modeSecHeader.TextColor3 = C_CYAN
modeSecHeader.TextXAlignment = Enum.TextXAlignment.Left
modeSecHeader.Text = "SELECT GAME MODE"
modeSecHeader.LayoutOrder = 1
modeSecHeader.Parent = leftCol

local modeCardsContainer = Instance.new("Frame")
modeCardsContainer.Size = UDim2.new(1, 0, 0, 240)
modeCardsContainer.BackgroundTransparency = 1
modeCardsContainer.LayoutOrder = 2
modeCardsContainer.Parent = leftCol

local modeLayout = Instance.new("UIListLayout")
modeLayout.Padding = UDim.new(0, 8)
modeLayout.SortOrder = Enum.SortOrder.LayoutOrder
modeLayout.Parent = modeCardsContainer

local modeCardButtons = {}

local function createModeCard(id, title, desc, subPills)
    local card = Instance.new("Frame")
    card.Size = UDim2.new(1, -6, 0, subPills and 68 or 50)
    card.BackgroundColor3 = (selectedMode == id) and C_CARD_SEL or C_CARD
    card.Parent = modeCardsContainer
    applyCorner(card, 10)
    local s = applyStroke(card, (selectedMode == id) and C_CYAN or C_STROKE, (selectedMode == id) and 1.5 or 1)
    
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, 0, 0, 36)
    btn.BackgroundTransparency = 1
    btn.Text = ""
    btn.Parent = card
    
    local tLbl = Instance.new("TextLabel")
    tLbl.Size = UDim2.new(0, 220, 0, 20)
    tLbl.Position = UDim2.new(0, 12, 0, 8)
    tLbl.BackgroundTransparency = 1
    tLbl.Font = Enum.Font.GothamBold
    tLbl.TextSize = 13
    tLbl.TextColor3 = (selectedMode == id) and C_CYAN or C_TEXT
    tLbl.TextXAlignment = Enum.TextXAlignment.Left
    tLbl.Text = title
    tLbl.Parent = card
    
    local dLbl = Instance.new("TextLabel")
    dLbl.Size = UDim2.new(1, -24, 0, 14)
    dLbl.Position = UDim2.new(0, 12, 0, 28)
    dLbl.BackgroundTransparency = 1
    dLbl.Font = Enum.Font.Gotham
    dLbl.TextSize = 10
    dLbl.TextColor3 = C_MUTED
    dLbl.TextXAlignment = Enum.TextXAlignment.Left
    dLbl.Text = desc
    dLbl.Parent = card
    
    local pillContainer = nil
    if subPills then
        pillContainer = Instance.new("Frame")
        pillContainer.Size = UDim2.new(1, -24, 0, 22)
        pillContainer.Position = UDim2.new(0, 12, 0, 44)
        pillContainer.BackgroundTransparency = 1
        pillContainer.Parent = card
        
        local pLayout = Instance.new("UIListLayout")
        pLayout.FillDirection = Enum.FillDirection.Horizontal
        pLayout.Padding = UDim.new(0, 6)
        pLayout.Parent = pillContainer
        
        for _, pInfo in ipairs(subPills) do
            local pBtn = Instance.new("TextButton")
            pBtn.Size = UDim2.new(0, pInfo.width or 44, 0, 20)
            local isPillSel = (selectedTeamSize == pInfo.count)
            pBtn.BackgroundColor3 = isPillSel and C_CYAN or Color3.fromRGB(30, 38, 52)
            pBtn.TextColor3 = isPillSel and Color3.new(0, 0, 0) or C_TEXT
            pBtn.Font = Enum.Font.GothamBold
            pBtn.TextSize = 10
            pBtn.Text = pInfo.label
            pBtn.Parent = pillContainer
            applyCorner(pBtn, 4)
            
            pBtn.MouseButton1Click:Connect(function()
                selectedMode = id
                selectedTeamSize = pInfo.count
                updateModeCards()
            end)
        end
    end
    
    btn.MouseButton1Click:Connect(function()
        selectedMode = id
        if id == "1vs1" then selectedTeamSize = 1
        elseif id == "FFA" then selectedTeamSize = 8
        elseif id == "GrandArena" then selectedTeamSize = 8 end
        updateModeCards()
    end)
    
    modeCardButtons[id] = { card = card, stroke = s, title = tLbl, id = id }
end

createModeCard("1vs1", "1 vs 1 Sparring / Duel", "Direct 2-Quin standoff in the center ring")
createModeCard("FFA", "Free-For-All (FFA)", "Chaotic multi-Quin survival", {
    { label = "4 Quin", count = 4, width = 50 },
    { label = "8 Quin", count = 8, width = 50 },
    { label = "16 Quin", count = 16, width = 55 },
})
createModeCard("TeamBattle", "Team Battle (Alpha vs Beta)", "Coordinated squad combat across arena", {
    { label = "2 vs 2", count = 2, width = 50 },
    { label = "4 vs 4", count = 4, width = 50 },
    { label = "8 vs 8", count = 8, width = 50 },
    { label = "16 vs 16", count = 16, width = 58 },
})
createModeCard("GrandArena", "Grand Arena 8vs8 [Future Implementation]", "Procedural terrain & multi-tier vertical hurdles")

function updateModeCards()
    for id, item in pairs(modeCardButtons) do
        local sel = (selectedMode == id)
        item.card.BackgroundColor3 = sel and C_CARD_SEL or C_CARD
        item.stroke.Color = sel and C_CYAN or C_STROKE
        item.stroke.Thickness = sel and 1.5 or 1
        item.title.TextColor3 = sel and C_CYAN or C_TEXT
    end
end

-- Section 2: Timing Configuration (Editable inputs)
local timeSecHeader = Instance.new("TextLabel")
timeSecHeader.Size = UDim2.new(1, 0, 0, 20)
timeSecHeader.BackgroundTransparency = 1
timeSecHeader.Font = Enum.Font.GothamBold
timeSecHeader.TextSize = 12
timeSecHeader.TextColor3 = C_CYAN
timeSecHeader.TextXAlignment = Enum.TextXAlignment.Left
timeSecHeader.Text = "TIMING CONFIGURATION (SECONDS)"
timeSecHeader.LayoutOrder = 3
timeSecHeader.Parent = leftCol

local timeGrid = Instance.new("Frame")
timeGrid.Size = UDim2.new(1, 0, 0, 245)
timeGrid.BackgroundColor3 = C_CARD
timeGrid.LayoutOrder = 4
timeGrid.Parent = leftCol
applyCorner(timeGrid, 10)
applyStroke(timeGrid, C_STROKE, 1)

local timeRows = {
    { key = "ArenaOpen", label = "Arena Open (Fanfare & ARIA)", val = activeDurations.ArenaOpen },
    { key = "ArenaGeneration", label = "Arena Generation", val = activeDurations.ArenaGeneration },
    { key = "PreparationRoom", label = "Preparation Room (Staging)", val = activeDurations.PreparationRoom },
    { key = "TeleportingQuins", label = "Teleport Quins (To Combat Area)", val = activeDurations.TeleportingQuins },
    { key = "PreGame", label = "Pre-Game (5-4-3-2-1 Countdown)", val = activeDurations.PreGame },
    { key = "GameTime", label = "Game Time (Max Combat)", val = activeDurations.GameTime },
    { key = "PostGame", label = "Arena Closure (Spectator Exit - 3M)", val = activeDurations.PostGame },
}

local durationInputs = {}

local tLayout = Instance.new("UIListLayout")
tLayout.Padding = UDim.new(0, 4)
tLayout.Parent = timeGrid

local tPad = Instance.new("UIPadding")
tPad.PaddingTop = UDim.new(0, 8)
tPad.PaddingLeft = UDim.new(0, 10)
tPad.PaddingRight = UDim.new(0, 10)
tPad.Parent = timeGrid

for _, r in ipairs(timeRows) do
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, 0, 0, 24)
    row.BackgroundTransparency = 1
    row.Parent = timeGrid
    
    local rLbl = Instance.new("TextLabel")
    rLbl.Size = UDim2.new(1, -75, 1, 0)
    rLbl.BackgroundTransparency = 1
    rLbl.Font = Enum.Font.Gotham
    rLbl.TextSize = 11
    rLbl.TextColor3 = C_TEXT
    rLbl.TextXAlignment = Enum.TextXAlignment.Left
    rLbl.Text = r.label
    rLbl.Parent = row
    
    local box = Instance.new("TextBox")
    box.Size = UDim2.new(0, 65, 1, -2)
    box.Position = UDim2.new(1, -65, 0, 1)
    box.BackgroundColor3 = Color3.fromRGB(15, 18, 25)
    box.TextColor3 = C_AMBER
    box.Font = Enum.Font.GothamBold
    box.TextSize = 11
    box.Text = tostring(r.val)
    box.ClearTextOnFocus = false
    box.Parent = row
    applyCorner(box, 4)
    applyStroke(box, C_STROKE, 1)
    
    box.FocusLost:Connect(function()
        local num = tonumber(box.Text)
        if num and num > 0 then
            activeDurations[r.key] = num
        else
            box.Text = tostring(activeDurations[r.key])
        end
    end)
    durationInputs[r.key] = box
end

-- Preset Timing Buttons
local presetRow = Instance.new("Frame")
presetRow.Size = UDim2.new(1, 0, 0, 26)
presetRow.Position = UDim2.new(0, 0, 1, -30)
presetRow.BackgroundTransparency = 1
presetRow.Parent = timeGrid

local stdBtn = Instance.new("TextButton")
stdBtn.Size = UDim2.new(0.5, -4, 0, 22)
stdBtn.BackgroundColor3 = Color3.fromRGB(30, 38, 52)
stdBtn.TextColor3 = C_TEXT
stdBtn.Font = Enum.Font.GothamBold
stdBtn.TextSize = 10
stdBtn.Text = "Standard Timings (3M Post)"
stdBtn.Parent = presetRow
applyCorner(stdBtn, 4)

local fastBtn = Instance.new("TextButton")
fastBtn.Size = UDim2.new(0.5, -4, 0, 22)
fastBtn.Position = UDim2.new(0.5, 4, 0, 0)
fastBtn.BackgroundColor3 = Color3.fromRGB(45, 38, 25)
fastBtn.TextColor3 = C_AMBER
fastBtn.Font = Enum.Font.GothamBold
fastBtn.TextSize = 10
fastBtn.Text = "⚡ Fast Test Preset"
fastBtn.Parent = presetRow
applyCorner(fastBtn, 4)
applyStroke(fastBtn, C_AMBER, 1)

stdBtn.MouseButton1Click:Connect(function()
    for k, v in pairs(ArenaConfig.DefaultDurations) do
        activeDurations[k] = v
        if durationInputs[k] then durationInputs[k].Text = tostring(v) end
    end
end)

local safeFastTestDurations = {
    ArenaOpen = 3,
    ArenaGeneration = 6,
    PreparationRoom = 13, -- 11.65s guide plays in full without truncation!
    TeleportingQuins = 6,  -- 4.60s announcement plays in full!
    PreGame = 5,           -- 4.68s countdown plays in full!
    GameTime = 20,
    WinnerDetermination = 8, -- 1s delay + Congratulations + Team Wins plays in full!
    PostGame = 20,
}

fastBtn.MouseButton1Click:Connect(function()
    for k, v in pairs(safeFastTestDurations) do
        activeDurations[k] = v
        if durationInputs[k] then durationInputs[k].Text = tostring(v) end
    end
end)

-- ============================================================================
-- 3. RIGHT COLUMN (CHECKBOXES & MUSIC PLAYLISTS)
-- ============================================================================
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
rightLayout.Padding = UDim.new(0, 12)
rightLayout.SortOrder = Enum.SortOrder.LayoutOrder
rightLayout.Parent = rightCol

local togSecHeader = Instance.new("TextLabel")
togSecHeader.Size = UDim2.new(1, 0, 0, 20)
togSecHeader.BackgroundTransparency = 1
togSecHeader.Font = Enum.Font.GothamBold
togSecHeader.TextSize = 12
togSecHeader.TextColor3 = C_CYAN
togSecHeader.TextXAlignment = Enum.TextXAlignment.Left
togSecHeader.Text = "ARENA FIELD TOGGLES & MECHANICS"
togSecHeader.LayoutOrder = 1
togSecHeader.Parent = rightCol

local togglesContainer = Instance.new("Frame")
togglesContainer.Size = UDim2.new(1, 0, 0, 230)
togglesContainer.BackgroundColor3 = C_CARD
togglesContainer.LayoutOrder = 2
togglesContainer.Parent = rightCol
applyCorner(togglesContainer, 10)
applyStroke(togglesContainer, C_STROKE, 1)

local togLayout = Instance.new("UIListLayout")
togLayout.Padding = UDim.new(0, 2)
togLayout.Parent = togglesContainer

local togPad = Instance.new("UIPadding")
togPad.PaddingTop = UDim.new(0, 6)
togPad.PaddingLeft = UDim.new(0, 10)
togPad.PaddingRight = UDim.new(0, 10)
togPad.Parent = togglesContainer

local checkboxDefinitions = {
    { key = "Announcer",         label = "Arena Announcer (ARIA Stadium Voice & Subtitles)" },
    { key = "TimerPreGame",      label = "Timer (Pre-game Countdown)" },
    { key = "Screen",            label = "Screen (Dual Jumbotron SurfaceGuis)" },
    { key = "Referee",           label = "Referee", isStub = true },
    { key = "Fireworks",         label = "Fireworks (Opening & Winner Shows)" },
    { key = "ProceduralMusic",   label = "Arena Music (Pre-Game, In-Game & Post-Game)" },
    { key = "CrowdFX",           label = "Procedural Crowd FX", isStub = true },
    { key = "ProceduralTerrain", label = "Procedural Terrain/Obstacles (Off = Edit parts)" },
}

local checkboxWidgets = {}

for _, cDef in ipairs(checkboxDefinitions) do
    local row = Instance.new("TextButton")
    row.Size = UDim2.new(1, 0, 0, 25)
    row.BackgroundTransparency = 1
    row.Text = ""
    row.Parent = togglesContainer
    
    local box = Instance.new("Frame")
    box.Size = UDim2.new(0, 16, 0, 16)
    box.Position = UDim2.new(0, 0, 0.5, -8)
    local isChecked = activeToggles[cDef.key] == true
    box.BackgroundColor3 = isChecked and C_CYAN or Color3.fromRGB(25, 30, 42)
    box.Parent = row
    applyCorner(box, 4)
    local bStroke = applyStroke(box, isChecked and C_CYAN or C_STROKE, 1)
    
    local checkMark = Instance.new("TextLabel")
    checkMark.Size = UDim2.new(1, 0, 1, 0)
    checkMark.BackgroundTransparency = 1
    checkMark.TextColor3 = Color3.new(0, 0, 0)
    checkMark.Font = Enum.Font.GothamBold
    checkMark.TextSize = 11
    checkMark.Text = isChecked and "✓" or ""
    checkMark.Parent = box
    
    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1, -28, 1, 0)
    lbl.Position = UDim2.new(0, 24, 0, 0)
    lbl.BackgroundTransparency = 1
    lbl.Font = Enum.Font.Gotham
    lbl.TextSize = 11
    lbl.TextColor3 = cDef.isStub and C_MUTED or C_TEXT
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Text = cDef.isStub and (cDef.label .. "  [Later]") or cDef.label
    lbl.Parent = row
    
    if not cDef.isStub then
        row.MouseButton1Click:Connect(function()
            activeToggles[cDef.key] = not activeToggles[cDef.key]
            local checked = activeToggles[cDef.key]
            box.BackgroundColor3 = checked and C_CYAN or Color3.fromRGB(25, 30, 42)
            bStroke.Color = checked and C_CYAN or C_STROKE
            checkMark.Text = checked and "✓" or ""
            UpdateTogglesEvent:FireServer(activeToggles)
        end)
    end
    
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
acPad.PaddingTop = UDim.new(0, 5)
acPad.PaddingLeft = UDim.new(0, 10)
acPad.PaddingRight = UDim.new(0, 10)
acPad.Parent = acousticsContainer

local SoundService = game:GetService("SoundService")
local speakerGrp = SoundService:FindFirstChild("ArenaSpeakerGroup")
local revEffect = speakerGrp and speakerGrp:FindFirstChildOfClass("ReverbSoundEffect")
local echoEffect = speakerGrp and speakerGrp:FindFirstChildOfClass("EchoSoundEffect")

local acousticState = {
    Volume = speakerGrp and speakerGrp.Volume or 1.0,
    ReverbDecay = revEffect and revEffect.DecayTime or 4.28,
    ReverbWet = revEffect and revEffect.WetLevel or 6.0,
    ReverbDry = revEffect and revEffect.DryLevel or 2.0,
    ReverbDensity = revEffect and revEffect.Density or 1.0,
    EchoDelay = echoEffect and echoEffect.Delay or 1.0,
    EchoFeedback = echoEffect and echoEffect.Feedback or 0.12,
    EchoWet = echoEffect and echoEffect.WetLevel or 8.2,
    EchoDry = echoEffect and echoEffect.DryLevel or -45.8,
}

local function applyAcousticLocally()
    local grp = SoundService:FindFirstChild("ArenaSpeakerGroup")
    if grp then
        grp.Volume = acousticState.Volume
        local rev = grp:FindFirstChildOfClass("ReverbSoundEffect")
        if rev then
            rev.DecayTime = acousticState.ReverbDecay
            rev.WetLevel = acousticState.ReverbWet
            rev.DryLevel = acousticState.ReverbDry
            rev.Density = acousticState.ReverbDensity
        end
        local echo = grp:FindFirstChildOfClass("EchoSoundEffect")
        if echo then
            echo.Delay = acousticState.EchoDelay
            echo.Feedback = acousticState.EchoFeedback
            echo.WetLevel = acousticState.EchoWet
            echo.DryLevel = acousticState.EchoDry
        end
    end
    UpdateAudioSettings:FireServer(acousticState)
end

local function createAcousticRow(labelPrefix, key, step, minVal, maxVal, formatStr, unit)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, 0, 0, 21)
    row.BackgroundTransparency = 1
    row.Parent = acousticsContainer

    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1, -115, 1, 0)
    lbl.BackgroundTransparency = 1
    lbl.Font = Enum.Font.Gotham
    lbl.TextSize = 10
    lbl.TextColor3 = C_TEXT
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Text = string.format("%s: " .. formatStr .. "%s", labelPrefix, acousticState[key], unit or "")
    lbl.Parent = row

    local btnMinus = Instance.new("TextButton")
    btnMinus.Size = UDim2.new(0, 52, 1, -2)
    btnMinus.Position = UDim2.new(1, -110, 0, 1)
    btnMinus.BackgroundColor3 = Color3.fromRGB(30, 36, 50)
    btnMinus.TextColor3 = C_AMBER
    btnMinus.Font = Enum.Font.GothamBold
    btnMinus.TextSize = 10
    btnMinus.Text = "-" .. tostring(step)
    btnMinus.Parent = row
    applyCorner(btnMinus, 4)
    applyStroke(btnMinus, C_STROKE, 1)

    local btnPlus = Instance.new("TextButton")
    btnPlus.Size = UDim2.new(0, 52, 1, -2)
    btnPlus.Position = UDim2.new(1, -54, 0, 1)
    btnPlus.BackgroundColor3 = Color3.fromRGB(30, 36, 50)
    btnPlus.TextColor3 = C_CYAN
    btnPlus.Font = Enum.Font.GothamBold
    btnPlus.TextSize = 10
    btnPlus.Text = "+" .. tostring(step)
    btnPlus.Parent = row
    applyCorner(btnPlus, 4)
    applyStroke(btnPlus, C_STROKE, 1)

    btnMinus.MouseButton1Click:Connect(function()
        acousticState[key] = math.clamp(acousticState[key] - step, minVal, maxVal)
        lbl.Text = string.format("%s: " .. formatStr .. "%s", labelPrefix, acousticState[key], unit or "")
        applyAcousticLocally()
    end)

    btnPlus.MouseButton1Click:Connect(function()
        acousticState[key] = math.clamp(acousticState[key] + step, minVal, maxVal)
        lbl.Text = string.format("%s: " .. formatStr .. "%s", labelPrefix, acousticState[key], unit or "")
        applyAcousticLocally()
    end)
end

createAcousticRow("Master Vol", "Volume", 0.1, 0, 2, "%.2f", "")
createAcousticRow("Rev Decay", "ReverbDecay", 0.5, 0.1, 20, "%.2f", "s")
createAcousticRow("Rev Wet", "ReverbWet", 2.0, -80, 20, "%.1f", "dB")
createAcousticRow("Rev Dry", "ReverbDry", 2.0, -80, 20, "%.1f", "dB")
createAcousticRow("Rev Density", "ReverbDensity", 0.1, 0, 1, "%.2f", "")
createAcousticRow("Echo Delay", "EchoDelay", 0.1, 0.05, 5, "%.2f", "s")
createAcousticRow("Echo Feedback", "EchoFeedback", 0.05, 0, 1, "%.2f", "")
createAcousticRow("Echo Wet", "EchoWet", 2.0, -80, 20, "%.1f", "dB")

-- ============================================================================
-- Section 5: Dynamic Folder-Based Music Playlists (NO FantasyMusic)
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
reloadMusicBtn.Text = "🔄 Reload"
reloadMusicBtn.Parent = musicHeaderRow
applyCorner(reloadMusicBtn, 4)
applyStroke(reloadMusicBtn, C_CYAN, 1)

local function scanFolderTracks(folderName)
    local tracks = {}
    -- STRICT EXCLUSION: Never load FantasyMusic
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
    table.insert(tracks, 1, {
        Name = "ARIA_SkylarkAnthem1Procedural (3-Stem)",
        SoundId = "Anthem1"
    })
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
preContainer.Size = UDim2.new(1, 0, 0, 95)
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

-- In-Game Container
local inSecLbl = Instance.new("TextLabel")
inSecLbl.Size = UDim2.new(1, 0, 0, 16)
inSecLbl.BackgroundTransparency = 1
inSecLbl.Font = Enum.Font.GothamBold
inSecLbl.TextSize = 10
inSecLbl.TextColor3 = C_MUTED
inSecLbl.TextXAlignment = Enum.TextXAlignment.Left
inSecLbl.Text = "IN-GAME COMBAT MUSIC (InGameMusic/)"
inSecLbl.LayoutOrder = 8
inSecLbl.Parent = rightCol

local inContainer = Instance.new("Frame")
inContainer.Size = UDim2.new(1, 0, 0, 95)
inContainer.BackgroundColor3 = C_CARD
inContainer.LayoutOrder = 9
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
postSecLbl.LayoutOrder = 10
postSecLbl.Parent = rightCol

local postContainer = Instance.new("Frame")
postContainer.Size = UDim2.new(1, 0, 0, 75)
postContainer.BackgroundColor3 = C_CARD
postContainer.LayoutOrder = 11
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
            local sel = (getSelected() == name)
            item.btn.BackgroundColor3 = sel and Color3.fromRGB(35, 48, 68) or Color3.fromRGB(20, 24, 34)
            item.stroke.Color = sel and C_CYAN or C_STROKE
            item.lbl.TextColor3 = sel and C_CYAN or C_TEXT
        end
    end

    for _, track in ipairs(tracks) do
        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(1, -6, 0, 22)
        btn.BackgroundColor3 = (getSelected() == track.Name) and Color3.fromRGB(35, 48, 68) or Color3.fromRGB(20, 24, 34)
        btn.Text = ""
        btn.Parent = scrollFrame
        applyCorner(btn, 4)
        local stroke = applyStroke(btn, (getSelected() == track.Name) and C_CYAN or C_STROKE, 1)

        local lbl = Instance.new("TextLabel")
        lbl.Size = UDim2.new(1, -12, 1, 0)
        lbl.Position = UDim2.new(0, 8, 0, 0)
        lbl.BackgroundTransparency = 1
        lbl.Font = Enum.Font.Gotham
        lbl.TextSize = 10
        lbl.TextColor3 = (getSelected() == track.Name) and C_CYAN or C_TEXT
        lbl.TextXAlignment = Enum.TextXAlignment.Left
        lbl.Text = "🎵 " .. track.Name
        lbl.Parent = btn

        btn.MouseButton1Click:Connect(function()
            setSelected(track.Name)
            refreshVisuals()
        end)

        buttons[track.Name] = { btn = btn, stroke = stroke, lbl = lbl }
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

    populateTrackList(preScroll, preTracks, function() return selectedTrack end, function(v) selectedTrack = v end)
    populateTrackList(inScroll, inTracks, function() return selectedInTrack end, function(v) selectedInTrack = v end)
    populateTrackList(postScroll, postTracks, function() return selectedPostTrack end, function(v) selectedPostTrack = v end)
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

-- Action Buttons: Start, Stop, Skip
local startBtn = Instance.new("TextButton")
startBtn.Name = "StartMatchBtn"
startBtn.Size = UDim2.new(0, 130, 0, 38)
startBtn.Position = UDim2.new(1, -380, 0, 16)
startBtn.BackgroundColor3 = C_GREEN
startBtn.TextColor3 = Color3.new(0, 0, 0)
startBtn.Font = Enum.Font.GothamBold
startBtn.TextSize = 12
startBtn.Text = "▶ START MATCH"
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
stopBtn.Text = "⏹ STOP"
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
skipBtn.Text = "⏩ SKIP"
skipBtn.Parent = bottomDock
applyCorner(skipBtn, 8)
applyStroke(skipBtn, C_AMBER, 1)

startBtn.MouseButton1Click:Connect(function()
    local cfg = {
        Mode = selectedMode,
        TeamSize = selectedTeamSize,
        SelectedTrack = selectedTrack,
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
        startBtn.Text = "▶ START MATCH"
    end)
end)

stopBtn.MouseButton1Click:Connect(function()
    StopMatchEvent:FireServer()
end)

skipBtn.MouseButton1Click:Connect(function()
    SkipPhaseEvent:FireServer()
end)

-- ============================================================================
-- 5. WINDOW TOGGLE & HOTKEY (O)
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

UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    if input.KeyCode == Enum.KeyCode.O then
        toggleWindow()
    end
end)

-- ============================================================================
-- 6. STATE REPLICATION SYNC
-- ============================================================================
StateReplication.OnClientEvent:Connect(function(snap)
    if not snap then return end
    
    -- Update phase badge
    local phaseColor = C_GREEN
    if snap.Phase == "IDLE" then
        phaseColor = C_MUTED
    elseif snap.Phase == "ARENA_OPEN" or snap.Phase == "ARENA_GENERATION" then
        phaseColor = C_CYAN
    elseif snap.Phase == "PREPARATION_ROOM" or snap.Phase == "TELEPORTING_QUINS" or snap.Phase == "PRE_GAME" then
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
    
    -- Update bottom dock text
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
