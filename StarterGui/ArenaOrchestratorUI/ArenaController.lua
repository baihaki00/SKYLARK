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
local selectedTrack = "Bai - Skycastle Parade"
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

fastBtn.MouseButton1Click:Connect(function()
    for k, v in pairs(ArenaConfig.FastTestDurations) do
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
rightCol.CanvasSize = UDim2.new(0, 0, 0, 620)
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
    { key = "ProceduralMusic",   label = "Arena Music (Pre-Game & Post-Game)" },
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

-- Section 4: Music Playlists
local musicSecHeader = Instance.new("TextLabel")
musicSecHeader.Size = UDim2.new(1, 0, 0, 20)
musicSecHeader.BackgroundTransparency = 1
musicSecHeader.Font = Enum.Font.GothamBold
musicSecHeader.TextSize = 12
musicSecHeader.TextColor3 = C_CYAN
musicSecHeader.TextXAlignment = Enum.TextXAlignment.Left
musicSecHeader.Text = "PRE-GAME MUSIC PLAYLIST (ArenaOpen -> PreGame)"
musicSecHeader.LayoutOrder = 3
musicSecHeader.Parent = rightCol

local playlistContainer = Instance.new("Frame")
playlistContainer.Size = UDim2.new(1, 0, 0, 160)
playlistContainer.BackgroundColor3 = C_CARD
playlistContainer.LayoutOrder = 4
playlistContainer.Parent = rightCol
applyCorner(playlistContainer, 10)
applyStroke(playlistContainer, C_STROKE, 1)

local plScroll = Instance.new("ScrollingFrame")
plScroll.Size = UDim2.new(1, -12, 1, -12)
plScroll.Position = UDim2.new(0, 6, 0, 6)
plScroll.BackgroundTransparency = 1
plScroll.ScrollBarThickness = 3
plScroll.ScrollBarImageColor3 = C_CYAN
plScroll.CanvasSize = UDim2.new(0, 0, 0, #ArenaConfig.PreGamePlaylist * 28)
plScroll.Parent = playlistContainer

local plLayout = Instance.new("UIListLayout")
plLayout.Padding = UDim.new(0, 4)
plLayout.Parent = plScroll

local trackButtons = {}

local function updateTrackButtons()
    for name, item in pairs(trackButtons) do
        local sel = (selectedTrack == name)
        item.btn.BackgroundColor3 = sel and Color3.fromRGB(35, 48, 68) or Color3.fromRGB(20, 24, 34)
        item.stroke.Color = sel and C_CYAN or C_STROKE
        item.title.TextColor3 = sel and C_CYAN or C_TEXT
    end
end

for _, track in ipairs(ArenaConfig.PreGamePlaylist) do
    local tBtn = Instance.new("TextButton")
    tBtn.Size = UDim2.new(1, -6, 0, 24)
    tBtn.BackgroundColor3 = (selectedTrack == track.Name) and Color3.fromRGB(35, 48, 68) or Color3.fromRGB(20, 24, 34)
    tBtn.Text = ""
    tBtn.Parent = plScroll
    applyCorner(tBtn, 4)
    local tStroke = applyStroke(tBtn, (selectedTrack == track.Name) and C_CYAN or C_STROKE, 1)
    
    local tLbl = Instance.new("TextLabel")
    tLbl.Size = UDim2.new(1, -60, 1, 0)
    tLbl.Position = UDim2.new(0, 8, 0, 0)
    tLbl.BackgroundTransparency = 1
    tLbl.Font = Enum.Font.Gotham
    tLbl.TextSize = 10
    tLbl.TextColor3 = (selectedTrack == track.Name) and C_CYAN or C_TEXT
    tLbl.TextXAlignment = Enum.TextXAlignment.Left
    tLbl.Text = "🎵 " .. track.Name
    tLbl.Parent = tBtn
    
    local sLbl = Instance.new("TextLabel")
    sLbl.Size = UDim2.new(0, 50, 1, 0)
    sLbl.Position = UDim2.new(1, -55, 0, 0)
    sLbl.BackgroundTransparency = 1
    sLbl.Font = Enum.Font.Gotham
    sLbl.TextSize = 9
    sLbl.TextColor3 = C_MUTED
    sLbl.TextXAlignment = Enum.TextXAlignment.Right
    sLbl.Text = track.Style
    sLbl.Parent = tBtn
    
    tBtn.MouseButton1Click:Connect(function()
        selectedTrack = track.Name
        updateTrackButtons()
    end)
    
    trackButtons[track.Name] = { btn = tBtn, stroke = tStroke, title = tLbl }
end

-- Post-Game Music Header
local postSecHeader = Instance.new("TextLabel")
postSecHeader.Size = UDim2.new(1, 0, 0, 20)
postSecHeader.BackgroundTransparency = 1
postSecHeader.Font = Enum.Font.GothamBold
postSecHeader.TextSize = 12
postSecHeader.TextColor3 = C_CYAN
postSecHeader.TextXAlignment = Enum.TextXAlignment.Left
postSecHeader.Text = "POST-GAME MUSIC (Arena Closure - 3 Minutes)"
postSecHeader.LayoutOrder = 5
postSecHeader.Parent = rightCol

local postContainer = Instance.new("Frame")
postContainer.Size = UDim2.new(1, 0, 0, 75)
postContainer.BackgroundColor3 = C_CARD
postContainer.LayoutOrder = 6
postContainer.Parent = rightCol
applyCorner(postContainer, 10)
applyStroke(postContainer, C_STROKE, 1)

local postScroll = Instance.new("ScrollingFrame")
postScroll.Size = UDim2.new(1, -12, 1, -12)
postScroll.Position = UDim2.new(0, 6, 0, 6)
postScroll.BackgroundTransparency = 1
postScroll.ScrollBarThickness = 3
postScroll.ScrollBarImageColor3 = C_CYAN
postScroll.CanvasSize = UDim2.new(0, 0, 0, #ArenaConfig.PostGamePlaylist * 28)
postScroll.Parent = postContainer

local postLayout = Instance.new("UIListLayout")
postLayout.Padding = UDim.new(0, 4)
postLayout.Parent = postScroll

local postTrackButtons = {}

local function updatePostTrackButtons()
    for name, item in pairs(postTrackButtons) do
        local sel = (selectedPostTrack == name)
        item.btn.BackgroundColor3 = sel and Color3.fromRGB(35, 48, 68) or Color3.fromRGB(20, 24, 34)
        item.stroke.Color = sel and C_CYAN or C_STROKE
        item.title.TextColor3 = sel and C_CYAN or C_TEXT
    end
end

for _, track in ipairs(ArenaConfig.PostGamePlaylist) do
    local tBtn = Instance.new("TextButton")
    tBtn.Size = UDim2.new(1, -6, 0, 24)
    tBtn.BackgroundColor3 = (selectedPostTrack == track.Name) and Color3.fromRGB(35, 48, 68) or Color3.fromRGB(20, 24, 34)
    tBtn.Text = ""
    tBtn.Parent = postScroll
    applyCorner(tBtn, 4)
    local tStroke = applyStroke(tBtn, (selectedPostTrack == track.Name) and C_CYAN or C_STROKE, 1)
    
    local tLbl = Instance.new("TextLabel")
    tLbl.Size = UDim2.new(1, -60, 1, 0)
    tLbl.Position = UDim2.new(0, 8, 0, 0)
    tLbl.BackgroundTransparency = 1
    tLbl.Font = Enum.Font.Gotham
    tLbl.TextSize = 10
    tLbl.TextColor3 = (selectedPostTrack == track.Name) and C_CYAN or C_TEXT
    tLbl.TextXAlignment = Enum.TextXAlignment.Left
    tLbl.Text = "🎵 " .. track.Name
    tLbl.Parent = tBtn
    
    local sLbl = Instance.new("TextLabel")
    sLbl.Size = UDim2.new(0, 50, 1, 0)
    sLbl.Position = UDim2.new(1, -55, 0, 0)
    sLbl.BackgroundTransparency = 1
    sLbl.Font = Enum.Font.Gotham
    sLbl.TextSize = 9
    sLbl.TextColor3 = C_MUTED
    sLbl.TextXAlignment = Enum.TextXAlignment.Right
    sLbl.Text = track.Style
    sLbl.Parent = tBtn
    
    tBtn.MouseButton1Click:Connect(function()
        selectedPostTrack = track.Name
        updatePostTrackButtons()
    end)
    
    postTrackButtons[track.Name] = { btn = tBtn, stroke = tStroke, title = tLbl }
end

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
