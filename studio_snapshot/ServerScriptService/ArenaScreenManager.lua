--// ArenaScreenManager.lua
-- Single Source of Truth for Argonia ArenaOne Double-Sided Stadium Jumbotron
-- Styled strictly with official Skylark Isles Palette (Argonia Gold, Midnight Navy, Steel Blue, Marble Ivory)
-- V3 Architecture: Full-Screen Multi-Scene Broadcast System, Full-Screen Transitions (Wipe & Glitch),
-- Zero Emojis, Modular Crests, Non-Overlapping Lower-Third Alerts, Holographic Boot & 14-Stud Authoritative Hovering

local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local ArenaScreen = {}

local screenPart = nil
local surfaceGuis = {}
local activeAnnouncementThread = nil
local isHologramActive = false
local currentActiveScene = "Scene_Open"

-- Official Skylark Isles Palette
local C_BG       = Color3.fromRGB(10, 18, 30)    -- Deep Midnight / Abyssal Navy (#0A121E)
local C_CARD     = Color3.fromRGB(18, 30, 48)    -- Elevated Card Navy
local C_CARD_IN  = Color3.fromRGB(8, 14, 24)     -- Sunken Container Navy
local C_GOLD     = Color3.fromRGB(212, 175, 55)  -- Argonia Gold (#D4AF37)
local C_STEEL    = Color3.fromRGB(65, 90, 119)   -- Steel Sky Blue (#415A77)
local C_IVORY    = Color3.fromRGB(234, 230, 223) -- Marble Ivory (#EAE6DF)
local C_MUTED    = Color3.fromRGB(138, 155, 174) -- Muted Sky Blue
local C_ALPHA    = Color3.fromRGB(0, 210, 255)   -- Radiant Skyline Cyan (Team Alpha)
local C_CYAN     = Color3.fromRGB(0, 210, 255)   -- Electric Broadcast Cyan
local C_BETA     = Color3.fromRGB(255, 56, 92)   -- Crimson Ember (Team Beta)

local function applyCorner(inst, radius)
    local c = inst:FindFirstChildOfClass("UICorner") or Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, radius)
    c.Parent = inst
    return c
end

local function applyStroke(inst, color, thickness)
    local s = inst:FindFirstChildOfClass("UIStroke") or Instance.new("UIStroke")
    s.Color = color or C_STEEL
    s.Thickness = thickness or 1.5
    s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    s.Parent = inst
    return s
end

local function findScreen()
    local arenaOne = Workspace:FindFirstChild("argoniaonion") and Workspace.argoniaonion:FindFirstChild("ArenaOne")
    screenPart = arenaOne and arenaOne:FindFirstChild("ArenaScreen")
    surfaceGuis = {}
    if screenPart then
        screenPart.Transparency = 1 -- Physical invisible plane
        for _, c in ipairs(screenPart:GetChildren()) do
            if c:IsA("SurfaceGui") then
                table.insert(surfaceGuis, c)
            end
        end
    end
    return screenPart
end

local function formatTimer(seconds)
    if type(seconds) ~= "number" or seconds < 0 then
        return "--:--"
    end
    if seconds <= 5 and seconds > 0 then
        return string.format("%d", seconds)
    end
    local mins = math.floor(seconds / 60)
    local secs = math.floor(seconds % 60)
    return string.format("%02d:%02d", mins, secs)
end

-- ============================================================================
-- FULL-SCREEN BROADCAST SCENE BUILDER
-- ============================================================================

local function buildGuiLayout(gui)
    gui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
    gui.CanvasSize = Vector2.new(1920, 1115)
    gui.LightInfluence = 0.0
    gui.AlwaysOnTop = false
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    gui.ClipsDescendants = true

    local tracker = gui:FindFirstChild("TrackerScript")
    if tracker then
        tracker.Disabled = true
        tracker:Destroy()
    end

    local mf = gui:FindFirstChild("MainFrame")
    if not mf then
        mf = Instance.new("Frame")
        mf.Name = "MainFrame"
        mf.Parent = gui
    end
    mf:ClearAllChildren()
    mf.Size = UDim2.new(1, 0, 1, 0)
    mf.Position = UDim2.new(0, 0, 0, 0)
    mf.BackgroundColor3 = C_BG
    mf.BackgroundTransparency = 0.04
    mf.BorderSizePixel = 0
    mf.Visible = isHologramActive
    applyCorner(mf, 24)
    applyStroke(mf, C_GOLD, 5)

    -- Persistent Top Branding Strip across all scenes
    local topHeader = Instance.new("Frame")
    topHeader.Name = "TopHeader"
    topHeader.Size = UDim2.new(1, -60, 0, 75)
    topHeader.Position = UDim2.new(0, 30, 0, 20)
    topHeader.BackgroundColor3 = C_CARD
    topHeader.Parent = mf
    applyCorner(topHeader, 16)
    applyStroke(topHeader, C_GOLD, 2)

    local brandLbl = Instance.new("TextLabel")
    brandLbl.Name = "BrandLabel"
    brandLbl.Size = UDim2.new(0, 520, 1, 0)
    brandLbl.Position = UDim2.new(0, 30, 0, 0)
    brandLbl.BackgroundTransparency = 1
    brandLbl.Font = Enum.Font.GothamBlack
    brandLbl.TextSize = 28
    brandLbl.TextColor3 = C_GOLD
    brandLbl.TextXAlignment = Enum.TextXAlignment.Left
    brandLbl.Text = "SKYLARK ISLES // ARENA ONE"
    brandLbl.Parent = topHeader

    local phaseBadge = Instance.new("Frame")
    phaseBadge.Name = "PhaseBadge"
    phaseBadge.Size = UDim2.new(0, 480, 0, 50)
    phaseBadge.AnchorPoint = Vector2.new(0.5, 0.5)
    phaseBadge.Position = UDim2.new(0.5, 0, 0.5, 0)
    phaseBadge.BackgroundColor3 = C_CARD_IN
    phaseBadge.Parent = topHeader
    applyCorner(phaseBadge, 12)
    applyStroke(phaseBadge, C_CYAN, 2)

    local phaseBadgeLbl = Instance.new("TextLabel")
    phaseBadgeLbl.Name = "BadgeLabel"
    phaseBadgeLbl.Size = UDim2.new(1, 0, 1, 0)
    phaseBadgeLbl.BackgroundTransparency = 1
    phaseBadgeLbl.Font = Enum.Font.GothamBlack
    phaseBadgeLbl.TextSize = 24
    phaseBadgeLbl.TextColor3 = C_CYAN
    phaseBadgeLbl.Text = "[ ARENA STANDBY ]"
    phaseBadgeLbl.Parent = phaseBadge

    local broadcastStatus = Instance.new("TextLabel")
    broadcastStatus.Name = "BroadcastStatus"
    broadcastStatus.Size = UDim2.new(0, 420, 1, 0)
    broadcastStatus.Position = UDim2.new(1, -450, 0, 0)
    broadcastStatus.BackgroundTransparency = 1
    broadcastStatus.Font = Enum.Font.GothamBold
    broadcastStatus.TextSize = 22
    broadcastStatus.TextColor3 = C_MUTED
    broadcastStatus.TextXAlignment = Enum.TextXAlignment.Right
    broadcastStatus.Text = "● STADIUM BROADCAST LIVE"
    broadcastStatus.Parent = topHeader

    -- Scene Container (1920 x 900)
    local sceneContainer = Instance.new("Frame")
    sceneContainer.Name = "SceneContainer"
    sceneContainer.Size = UDim2.new(1, -60, 1, -190)
    sceneContainer.Position = UDim2.new(0, 30, 0, 110)
    sceneContainer.BackgroundTransparency = 1
    sceneContainer.ClipsDescendants = true
    sceneContainer.Parent = mf

    -- ========================================================================
    -- 1. SCENE: ARENA_OPEN (Grand Opening Scene)
    -- ========================================================================
    local sOpen = Instance.new("Frame")
    sOpen.Name = "Scene_ArenaOpen"
    sOpen.Size = UDim2.new(1, 0, 1, 0)
    sOpen.BackgroundTransparency = 1
    sOpen.Visible = (currentActiveScene == "Scene_ArenaOpen")
    sOpen.Parent = sceneContainer

    local openHeroTitle = Instance.new("TextLabel")
    openHeroTitle.Name = "HeroTitle"
    openHeroTitle.Size = UDim2.new(1, 0, 0, 110)
    openHeroTitle.Position = UDim2.new(0, 0, 0, 40)
    openHeroTitle.BackgroundTransparency = 1
    openHeroTitle.Font = Enum.Font.GothamBlack
    openHeroTitle.TextSize = 92
    openHeroTitle.TextColor3 = C_IVORY
    openHeroTitle.Text = "ARENA ONE // GATES OPEN"
    openHeroTitle.Parent = sOpen

    local openSub = Instance.new("TextLabel")
    openSub.Name = "HeroSub"
    openSub.Size = UDim2.new(1, 0, 0, 50)
    openSub.Position = UDim2.new(0, 0, 0, 160)
    openSub.BackgroundTransparency = 1
    openSub.Font = Enum.Font.GothamBold
    openSub.TextSize = 36
    openSub.TextColor3 = C_GOLD
    openSub.Text = "AUTHORITATIVE TOURNAMENT COMBAT • PREPARING ARENA MATCH"
    openSub.Parent = sOpen

    local openTimerBox = Instance.new("Frame")
    openTimerBox.Name = "TimerBox"
    openTimerBox.Size = UDim2.new(0, 680, 0, 240)
    openTimerBox.AnchorPoint = Vector2.new(0.5, 0)
    openTimerBox.Position = UDim2.new(0.5, 0, 0, 260)
    openTimerBox.BackgroundColor3 = C_CARD
    openTimerBox.Parent = sOpen
    applyCorner(openTimerBox, 24)
    applyStroke(openTimerBox, C_GOLD, 4)

    local openTimerLbl = Instance.new("TextLabel")
    openTimerLbl.Name = "TimerLabel"
    openTimerLbl.Size = UDim2.new(1, 0, 0, 160)
    openTimerLbl.Position = UDim2.new(0, 0, 0, 12)
    openTimerLbl.BackgroundTransparency = 1
    openTimerLbl.Font = Enum.Font.GothamBlack
    openTimerLbl.TextSize = 135
    openTimerLbl.TextColor3 = C_GOLD
    openTimerLbl.Text = "02:00"
    openTimerLbl.Parent = openTimerBox

    local openTimerSub = Instance.new("TextLabel")
    openTimerSub.Name = "TimerSub"
    openTimerSub.Size = UDim2.new(1, 0, 0, 40)
    openTimerSub.Position = UDim2.new(0, 0, 0, 180)
    openTimerSub.BackgroundTransparency = 1
    openTimerSub.Font = Enum.Font.GothamBold
    openTimerSub.TextSize = 24
    openTimerSub.TextColor3 = C_MUTED
    openTimerSub.Text = "TIME TO COMBAT COMMENCEMENT"
    openTimerSub.Parent = openTimerBox

    local openFooterDesc = Instance.new("TextLabel")
    openFooterDesc.Name = "FooterDesc"
    openFooterDesc.Size = UDim2.new(1, 0, 0, 40)
    openFooterDesc.Position = UDim2.new(0, 0, 1, -90)
    openFooterDesc.BackgroundTransparency = 1
    openFooterDesc.Font = Enum.Font.GothamBold
    openFooterDesc.TextSize = 26
    openFooterDesc.TextColor3 = C_MUTED
    openFooterDesc.Text = "ALL SPECTATORS TAKE SEATS • ARIA SOUND ENGINE ONLINE"
    openFooterDesc.Parent = sOpen

    -- ========================================================================
    -- 2. SCENE: ARENA_GENERATION (Sector Configuration Scene)
    -- ========================================================================
    local sGen = Instance.new("Frame")
    sGen.Name = "Scene_ArenaGeneration"
    sGen.Size = UDim2.new(1, 0, 1, 0)
    sGen.BackgroundTransparency = 1
    sGen.Visible = (currentActiveScene == "Scene_ArenaGeneration")
    sGen.Parent = sceneContainer

    local genHeroTitle = Instance.new("TextLabel")
    genHeroTitle.Name = "HeroTitle"
    genHeroTitle.Size = UDim2.new(1, 0, 0, 100)
    genHeroTitle.Position = UDim2.new(0, 0, 0, 50)
    genHeroTitle.BackgroundTransparency = 1
    genHeroTitle.Font = Enum.Font.GothamBlack
    genHeroTitle.TextSize = 84
    genHeroTitle.TextColor3 = C_CYAN
    genHeroTitle.Text = "SECTOR ARCHITECTURE GENERATION"
    genHeroTitle.Parent = sGen

    local genHeroSub = Instance.new("TextLabel")
    genHeroSub.Name = "HeroSub"
    genHeroSub.Size = UDim2.new(1, 0, 0, 45)
    genHeroSub.Position = UDim2.new(0, 0, 0, 160)
    genHeroSub.BackgroundTransparency = 1
    genHeroSub.Font = Enum.Font.GothamBold
    genHeroSub.TextSize = 32
    genHeroSub.TextColor3 = C_IVORY
    genHeroSub.Text = "CONFIGURING COMBAT PLATFORMS & TACTICAL BARRIERS"
    genHeroSub.Parent = sGen

    local genProgressBg = Instance.new("Frame")
    genProgressBg.Name = "ProgressBg"
    genProgressBg.Size = UDim2.new(0, 1000, 0, 60)
    genProgressBg.AnchorPoint = Vector2.new(0.5, 0)
    genProgressBg.Position = UDim2.new(0.5, 0, 0, 280)
    genProgressBg.BackgroundColor3 = C_CARD_IN
    genProgressBg.Parent = sGen
    applyCorner(genProgressBg, 16)
    applyStroke(genProgressBg, C_CYAN, 3)

    local genFill = Instance.new("Frame")
    genFill.Name = "Fill"
    genFill.Size = UDim2.new(0.85, 0, 1, 0)
    genFill.BackgroundColor3 = C_CYAN
    genFill.BorderSizePixel = 0
    genFill.Parent = genProgressBg
    applyCorner(genFill, 14)

    local genTimerLbl = Instance.new("TextLabel")
    genTimerLbl.Name = "TimerLabel"
    genTimerLbl.Size = UDim2.new(1, 0, 0, 100)
    genTimerLbl.Position = UDim2.new(0, 0, 0, 390)
    genTimerLbl.BackgroundTransparency = 1
    genTimerLbl.Font = Enum.Font.GothamBlack
    genTimerLbl.TextSize = 90
    genTimerLbl.TextColor3 = C_GOLD
    genTimerLbl.Text = "00:10"
    genTimerLbl.Parent = sGen

    -- ========================================================================
    -- 3. SCENE: PREPARATION_ROOM (Staging Backrooms Scene)
    -- ========================================================================
    local sPrep = Instance.new("Frame")
    sPrep.Name = "Scene_PreparationRoom"
    sPrep.Size = UDim2.new(1, 0, 1, 0)
    sPrep.BackgroundTransparency = 1
    sPrep.Visible = (currentActiveScene == "Scene_PreparationRoom")
    sPrep.Parent = sceneContainer

    local prepTitle = Instance.new("TextLabel")
    prepTitle.Name = "HeroTitle"
    prepTitle.Size = UDim2.new(1, 0, 0, 80)
    prepTitle.Position = UDim2.new(0, 0, 0, 20)
    prepTitle.BackgroundTransparency = 1
    prepTitle.Font = Enum.Font.GothamBlack
    prepTitle.TextSize = 72
    prepTitle.TextColor3 = C_IVORY
    prepTitle.Text = "GLADIATOR PREPARATION ROOM"
    prepTitle.Parent = sPrep

    local prepSub = Instance.new("TextLabel")
    prepSub.Name = "HeroSub"
    prepSub.Size = UDim2.new(1, 0, 0, 40)
    prepSub.Position = UDim2.new(0, 0, 0, 105)
    prepSub.BackgroundTransparency = 1
    prepSub.Font = Enum.Font.GothamBold
    prepSub.TextSize = 28
    prepSub.TextColor3 = C_MUTED
    prepSub.Text = "FIGHTERS CALIBRATING IN BACKROOMS • ZERO COMBATANTS ON FIELD"
    prepSub.Parent = sPrep

    -- Left Pod: Alpha Staging
    local alphaPod = Instance.new("Frame")
    alphaPod.Name = "AlphaPod"
    alphaPod.Size = UDim2.new(0.38, 0, 0, 400)
    alphaPod.Position = UDim2.new(0, 20, 0, 170)
    alphaPod.BackgroundColor3 = C_CARD
    alphaPod.Parent = sPrep
    applyCorner(alphaPod, 20)
    applyStroke(alphaPod, C_ALPHA, 3)

    local aPodHead = Instance.new("TextLabel")
    aPodHead.Size = UDim2.new(1, -40, 0, 60)
    aPodHead.Position = UDim2.new(0, 20, 0, 20)
    aPodHead.BackgroundTransparency = 1
    aPodHead.Font = Enum.Font.GothamBlack
    aPodHead.TextSize = 42
    aPodHead.TextColor3 = C_ALPHA
    aPodHead.Text = "SQUAD ALPHA"
    aPodHead.Parent = alphaPod

    local aPodStatus = Instance.new("TextLabel")
    aPodStatus.Size = UDim2.new(1, -40, 0, 40)
    aPodStatus.Position = UDim2.new(0, 20, 0, 90)
    aPodStatus.BackgroundTransparency = 1
    aPodStatus.Font = Enum.Font.GothamBold
    aPodStatus.TextSize = 28
    aPodStatus.TextColor3 = C_IVORY
    aPodStatus.Text = "STATUS: STAGING LOCK-IN"
    aPodStatus.Parent = alphaPod

    local aPodDesc = Instance.new("TextLabel")
    aPodDesc.Size = UDim2.new(1, -40, 0, 140)
    aPodDesc.Position = UDim2.new(0, 20, 0, 150)
    aPodDesc.BackgroundTransparency = 1
    aPodDesc.Font = Enum.Font.Gotham
    aPodDesc.TextSize = 22
    aPodDesc.TextColor3 = C_MUTED
    aPodDesc.TextWrapped = true
    aPodDesc.Text = "Elemental Attunement Complete\nFormation Telemetry Synchronized\nStanding by for deployment dispatch"
    aPodDesc.Parent = alphaPod

    -- Center Timer: 30s Countdown
    local prepTimerBox = Instance.new("Frame")
    prepTimerBox.Name = "TimerBox"
    prepTimerBox.Size = UDim2.new(0.20, 0, 0, 260)
    prepTimerBox.AnchorPoint = Vector2.new(0.5, 0)
    prepTimerBox.Position = UDim2.new(0.5, 0, 0, 230)
    prepTimerBox.BackgroundColor3 = C_CARD_IN
    prepTimerBox.Parent = sPrep
    applyCorner(prepTimerBox, 20)
    applyStroke(prepTimerBox, C_GOLD, 3)

    local prepTimerLbl = Instance.new("TextLabel")
    prepTimerLbl.Name = "TimerLabel"
    prepTimerLbl.Size = UDim2.new(1, 0, 0, 150)
    prepTimerLbl.Position = UDim2.new(0, 0, 0, 20)
    prepTimerLbl.BackgroundTransparency = 1
    prepTimerLbl.Font = Enum.Font.GothamBlack
    prepTimerLbl.TextSize = 100
    prepTimerLbl.TextColor3 = C_GOLD
    prepTimerLbl.Text = "00:30"
    prepTimerLbl.Parent = prepTimerBox

    local prepTimerSub = Instance.new("TextLabel")
    prepTimerSub.Size = UDim2.new(1, 0, 0, 40)
    prepTimerSub.Position = UDim2.new(0, 0, 0, 180)
    prepTimerSub.BackgroundTransparency = 1
    prepTimerSub.Font = Enum.Font.GothamBold
    prepTimerSub.TextSize = 20
    prepTimerSub.TextColor3 = C_MUTED
    prepTimerSub.Text = "PREPARATION TIME"
    prepTimerSub.Parent = prepTimerBox

    -- Right Pod: Beta Staging
    local betaPod = Instance.new("Frame")
    betaPod.Name = "BetaPod"
    betaPod.Size = UDim2.new(0.38, 0, 0, 400)
    betaPod.Position = UDim2.new(0.62, -20, 0, 170)
    betaPod.BackgroundColor3 = C_CARD
    betaPod.Parent = sPrep
    applyCorner(betaPod, 20)
    applyStroke(betaPod, C_BETA, 3)

    local bPodHead = Instance.new("TextLabel")
    bPodHead.Size = UDim2.new(1, -40, 0, 60)
    bPodHead.Position = UDim2.new(0, 20, 0, 20)
    bPodHead.BackgroundTransparency = 1
    bPodHead.Font = Enum.Font.GothamBlack
    bPodHead.TextSize = 42
    bPodHead.TextColor3 = C_BETA
    bPodHead.Text = "SQUAD BETA"
    bPodHead.Parent = betaPod

    local bPodStatus = Instance.new("TextLabel")
    bPodStatus.Size = UDim2.new(1, -40, 0, 40)
    bPodStatus.Position = UDim2.new(0, 20, 0, 90)
    bPodStatus.BackgroundTransparency = 1
    bPodStatus.Font = Enum.Font.GothamBold
    bPodStatus.TextSize = 28
    bPodStatus.TextColor3 = C_IVORY
    bPodStatus.Text = "STATUS: STAGING LOCK-IN"
    bPodStatus.Parent = betaPod

    local bPodDesc = Instance.new("TextLabel")
    bPodDesc.Size = UDim2.new(1, -40, 0, 140)
    bPodDesc.Position = UDim2.new(0, 20, 0, 150)
    bPodDesc.BackgroundTransparency = 1
    bPodDesc.Font = Enum.Font.Gotham
    bPodDesc.TextSize = 22
    bPodDesc.TextColor3 = C_MUTED
    bPodDesc.TextWrapped = true
    bPodDesc.Text = "Elemental Attunement Complete\nFormation Telemetry Synchronized\nStanding by for deployment dispatch"
    bPodDesc.Parent = betaPod

    -- ========================================================================
    -- 4. SCENE: TELEPORTING_QUINS (Deployment Alert Scene)
    -- ========================================================================
    local sTeleport = Instance.new("Frame")
    sTeleport.Name = "Scene_Teleporting"
    sTeleport.Size = UDim2.new(1, 0, 1, 0)
    sTeleport.BackgroundTransparency = 1
    sTeleport.Visible = (currentActiveScene == "Scene_Teleporting")
    sTeleport.Parent = sceneContainer

    local teleHead = Instance.new("TextLabel")
    teleHead.Name = "HeroTitle"
    teleHead.Size = UDim2.new(1, 0, 0, 110)
    teleHead.Position = UDim2.new(0, 0, 0, 60)
    teleHead.BackgroundTransparency = 1
    teleHead.Font = Enum.Font.GothamBlack
    teleHead.TextSize = 88
    teleHead.TextColor3 = C_CYAN
    teleHead.Text = "DEPLOYMENT TELEPORTATION ACTIVE"
    teleHead.Parent = sTeleport

    local teleSub = Instance.new("TextLabel")
    teleSub.Name = "HeroSub"
    teleSub.Size = UDim2.new(1, 0, 0, 50)
    teleSub.Position = UDim2.new(0, 0, 0, 180)
    teleSub.BackgroundTransparency = 1
    teleSub.Font = Enum.Font.GothamBold
    teleSub.TextSize = 38
    teleSub.TextColor3 = C_GOLD
    teleSub.Text = "MATERIALIZING QUIN FIGHTERS AT COMBAT STATIONS"
    teleSub.Parent = sTeleport

    local teleTimerBox = Instance.new("Frame")
    teleTimerBox.Name = "TimerBox"
    teleTimerBox.Size = UDim2.new(0, 500, 0, 200)
    teleTimerBox.AnchorPoint = Vector2.new(0.5, 0)
    teleTimerBox.Position = UDim2.new(0.5, 0, 0, 300)
    teleTimerBox.BackgroundColor3 = C_CARD
    teleTimerBox.Parent = sTeleport
    applyCorner(teleTimerBox, 20)
    applyStroke(teleTimerBox, C_CYAN, 4)

    local teleTimerLbl = Instance.new("TextLabel")
    teleTimerLbl.Name = "TimerLabel"
    teleTimerLbl.Size = UDim2.new(1, 0, 0, 130)
    teleTimerLbl.Position = UDim2.new(0, 0, 0, 15)
    teleTimerLbl.BackgroundTransparency = 1
    teleTimerLbl.Font = Enum.Font.GothamBlack
    teleTimerLbl.TextSize = 110
    teleTimerLbl.TextColor3 = C_CYAN
    teleTimerLbl.Text = "00:05"
    teleTimerLbl.Parent = teleTimerBox

    local teleTimerSub = Instance.new("TextLabel")
    teleTimerSub.Size = UDim2.new(1, 0, 0, 35)
    teleTimerSub.Position = UDim2.new(0, 0, 0, 145)
    teleTimerSub.BackgroundTransparency = 1
    teleTimerSub.Font = Enum.Font.GothamBold
    teleTimerSub.TextSize = 22
    teleTimerSub.TextColor3 = C_MUTED
    teleTimerSub.Text = "FIELD MATERIALIZATION PROTOCOL"
    teleTimerSub.Parent = teleTimerBox

    -- ========================================================================
    -- 5. SCENE: STADIUM_ANTHEM (Ceremonial Hymn Scene)
    -- ========================================================================
    local sAnthem = Instance.new("Frame")
    sAnthem.Name = "Scene_StadiumAnthem"
    sAnthem.Size = UDim2.new(1, 0, 1, 0)
    sAnthem.BackgroundTransparency = 1
    sAnthem.Visible = (currentActiveScene == "Scene_StadiumAnthem")
    sAnthem.Parent = sceneContainer

    local anthemTitle = Instance.new("TextLabel")
    anthemTitle.Name = "HeroTitle"
    anthemTitle.Size = UDim2.new(1, 0, 0, 95)
    anthemTitle.Position = UDim2.new(0, 0, 0, 30)
    anthemTitle.BackgroundTransparency = 1
    anthemTitle.Font = Enum.Font.GothamBlack
    anthemTitle.TextSize = 82
    anthemTitle.TextColor3 = C_GOLD
    anthemTitle.Text = "THE ARENA ONE ANTHEM"
    anthemTitle.Parent = sAnthem

    local anthemSub = Instance.new("TextLabel")
    anthemSub.Name = "HeroSub"
    anthemSub.Size = UDim2.new(1, 0, 0, 45)
    anthemSub.Position = UDim2.new(0, 0, 0, 135)
    anthemSub.BackgroundTransparency = 1
    anthemSub.Font = Enum.Font.GothamBold
    anthemSub.TextSize = 32
    anthemSub.TextColor3 = C_IVORY
    anthemSub.Text = "ARIA VOCALS & PERCUSSION EMITTING LIVE FROM THE ARENA GLOBE"
    anthemSub.Parent = sAnthem

    -- Visualizer Bars Container
    local vizContainer = Instance.new("Frame")
    vizContainer.Name = "Visualizer"
    vizContainer.Size = UDim2.new(0, 800, 0, 140)
    vizContainer.AnchorPoint = Vector2.new(0.5, 0)
    vizContainer.Position = UDim2.new(0.5, 0, 0, 220)
    vizContainer.BackgroundTransparency = 1
    vizContainer.Parent = sAnthem

    local vizLayout = Instance.new("UIListLayout")
    vizLayout.FillDirection = Enum.FillDirection.Horizontal
    vizLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    vizLayout.VerticalAlignment = Enum.VerticalAlignment.Center
    vizLayout.Padding = UDim.new(0, 14)
    vizLayout.Parent = vizContainer

    for i = 1, 16 do
        local bar = Instance.new("Frame")
        bar.Name = "Bar_" .. i
        bar.Size = UDim2.new(0, 24, 0, 30 + (i % 5) * 20)
        bar.BackgroundColor3 = (i % 2 == 1) and C_GOLD or C_CYAN
        bar.BorderSizePixel = 0
        bar.Parent = vizContainer
        applyCorner(bar, 12)
    end

    local anthemTimerLbl = Instance.new("TextLabel")
    anthemTimerLbl.Name = "TimerLabel"
    anthemTimerLbl.Size = UDim2.new(1, 0, 0, 110)
    anthemTimerLbl.Position = UDim2.new(0, 0, 0, 390)
    anthemTimerLbl.BackgroundTransparency = 1
    anthemTimerLbl.Font = Enum.Font.GothamBlack
    anthemTimerLbl.TextSize = 95
    anthemTimerLbl.TextColor3 = C_GOLD
    anthemTimerLbl.Text = "00:60"
    anthemTimerLbl.Parent = sAnthem

    local anthemHymn = Instance.new("TextLabel")
    anthemHymn.Size = UDim2.new(1, 0, 0, 40)
    anthemHymn.Position = UDim2.new(0, 0, 1, -80)
    anthemHymn.BackgroundTransparency = 1
    anthemHymn.Font = Enum.Font.GothamBold
    anthemHymn.TextSize = 26
    anthemHymn.TextColor3 = C_MUTED
    anthemHymn.Text = "HONOR THE ARENA • GLORY TO THE VALIANT • DESTINY FORGED IN SKY"
    anthemHymn.Parent = sAnthem

    -- ========================================================================
    -- 6. SCENE: PRE_GAME (Massive Hero 5-4-3-2-1 Countdown Scene)
    -- ========================================================================
    local sPreGame = Instance.new("Frame")
    sPreGame.Name = "Scene_PreGame"
    sPreGame.Size = UDim2.new(1, 0, 1, 0)
    sPreGame.BackgroundTransparency = 1
    sPreGame.Visible = (currentActiveScene == "Scene_PreGame")
    sPreGame.Parent = sceneContainer

    local pgHeroNum = Instance.new("TextLabel")
    pgHeroNum.Name = "HeroNumber"
    pgHeroNum.Size = UDim2.new(1, 0, 0, 350)
    pgHeroNum.Position = UDim2.new(0, 0, 0.5, -200)
    pgHeroNum.BackgroundTransparency = 1
    pgHeroNum.Font = Enum.Font.GothamBlack
    pgHeroNum.TextSize = 260
    pgHeroNum.TextColor3 = C_GOLD
    pgHeroNum.Text = "5"
    pgHeroNum.Parent = sPreGame

    local pgHeroStatus = Instance.new("TextLabel")
    pgHeroStatus.Name = "HeroStatus"
    pgHeroStatus.Size = UDim2.new(1, 0, 0, 70)
    pgHeroStatus.Position = UDim2.new(0, 0, 0.5, 150)
    pgHeroStatus.BackgroundTransparency = 1
    pgHeroStatus.Font = Enum.Font.GothamBlack
    pgHeroStatus.TextSize = 48
    pgHeroStatus.TextColor3 = C_IVORY
    pgHeroStatus.Text = "STAND BY FOR ENGAGEMENT"
    pgHeroStatus.Parent = sPreGame

    local droneAlert = Instance.new("TextLabel")
    droneAlert.Name = "DroneAlert"
    droneAlert.Size = UDim2.new(1, 0, 0, 45)
    droneAlert.Position = UDim2.new(0, 0, 1, -60)
    droneAlert.BackgroundTransparency = 1
    droneAlert.Font = Enum.Font.GothamBold
    droneAlert.TextSize = 28
    droneAlert.TextColor3 = C_CYAN
    droneAlert.Text = "ARENA DRONES LAUNCHED • LIVE SPECTATOR FEEDS ONLINE"
    droneAlert.Parent = sPreGame

    -- ========================================================================
    -- 7. SCENE: IN_GAME (Full Combat Scoreboard Scene)
    -- ========================================================================
    local sCombat = Instance.new("Frame")
    sCombat.Name = "Scene_InGame"
    sCombat.Size = UDim2.new(1, 0, 1, 0)
    sCombat.BackgroundTransparency = 1
    sCombat.Visible = (currentActiveScene == "Scene_InGame")
    sCombat.Parent = sceneContainer

    -- Team Alpha Card (Left, Massive 840x550)
    local alphaCard = Instance.new("Frame")
    alphaCard.Name = "TeamAlphaCard"
    alphaCard.Size = UDim2.new(0.5, -90, 0, 520)
    alphaCard.Position = UDim2.new(0, 0, 0, 20)
    alphaCard.BackgroundColor3 = C_CARD
    alphaCard.Parent = sCombat
    applyCorner(alphaCard, 24)
    applyStroke(alphaCard, C_ALPHA, 3.5)

    local alphaCrest = Instance.new("ImageLabel")
    alphaCrest.Name = "TeamAlphaCrest"
    alphaCrest.Size = UDim2.new(0, 90, 0, 90)
    alphaCrest.Position = UDim2.new(1, -120, 0, 30)
    alphaCrest.BackgroundTransparency = 1
    alphaCrest.ImageColor3 = C_ALPHA
    alphaCrest.ScaleType = Enum.ScaleType.Fit
    alphaCrest.Image = ""
    alphaCrest.Parent = alphaCard

    local alphaHead = Instance.new("TextLabel")
    alphaHead.Name = "Header"
    alphaHead.Size = UDim2.new(1, -150, 0, 70)
    alphaHead.Position = UDim2.new(0, 35, 0, 35)
    alphaHead.BackgroundTransparency = 1
    alphaHead.Font = Enum.Font.GothamBlack
    alphaHead.TextSize = 58
    alphaHead.TextColor3 = C_ALPHA
    alphaHead.TextXAlignment = Enum.TextXAlignment.Left
    alphaHead.Text = "TEAM ALPHA"
    alphaHead.Parent = alphaCard

    local alphaAlive = Instance.new("TextLabel")
    alphaAlive.Name = "Alive"
    alphaAlive.Size = UDim2.new(0.5, 0, 0, 50)
    alphaAlive.Position = UDim2.new(0, 35, 0, 125)
    alphaAlive.BackgroundTransparency = 1
    alphaAlive.Font = Enum.Font.GothamBlack
    alphaAlive.TextSize = 42
    alphaAlive.TextColor3 = C_IVORY
    alphaAlive.TextXAlignment = Enum.TextXAlignment.Left
    alphaAlive.Text = "ALIVE: 0"
    alphaAlive.Parent = alphaCard

    local alphaHp = Instance.new("TextLabel")
    alphaHp.Name = "HpLabel"
    alphaHp.Size = UDim2.new(0.5, -35, 0, 50)
    alphaHp.Position = UDim2.new(0.5, 0, 0, 125)
    alphaHp.BackgroundTransparency = 1
    alphaHp.Font = Enum.Font.GothamBold
    alphaHp.TextSize = 36
    alphaHp.TextColor3 = C_MUTED
    alphaHp.TextXAlignment = Enum.TextXAlignment.Right
    alphaHp.Text = "HP: 0 / 0 (100%)"
    alphaHp.Parent = alphaCard

    local aBarBg = Instance.new("Frame")
    aBarBg.Name = "HealthBarBg"
    aBarBg.Size = UDim2.new(1, -70, 0, 110)
    aBarBg.Position = UDim2.new(0, 35, 0, 200)
    aBarBg.BackgroundColor3 = C_CARD_IN
    aBarBg.Parent = alphaCard
    applyCorner(aBarBg, 20)
    applyStroke(aBarBg, C_STEEL, 2.5)

    local aFill = Instance.new("Frame")
    aFill.Name = "Fill"
    aFill.Size = UDim2.new(1, 0, 1, 0)
    aFill.BackgroundColor3 = C_ALPHA
    aFill.BorderSizePixel = 0
    aFill.Parent = aBarBg
    applyCorner(aFill, 18)

    local aSub = Instance.new("TextLabel")
    aSub.Name = "SubTag"
    aSub.Size = UDim2.new(1, -70, 0, 50)
    aSub.Position = UDim2.new(0, 35, 0, 350)
    aSub.BackgroundTransparency = 1
    aSub.Font = Enum.Font.GothamBold
    aSub.TextSize = 28
    aSub.TextColor3 = C_STEEL
    aSub.TextXAlignment = Enum.TextXAlignment.Left
    aSub.Text = "PRIMARY SQUAD • AUTHORITATIVE SECTOR ALPHA"
    aSub.Parent = alphaCard

    -- VS Center Circle
    local vsBox = Instance.new("Frame")
    vsBox.Name = "VsBox"
    vsBox.Size = UDim2.new(0, 140, 0, 140)
    vsBox.AnchorPoint = Vector2.new(0.5, 0.5)
    vsBox.Position = UDim2.new(0.5, 0, 0.42, 0)
    vsBox.BackgroundColor3 = C_CARD_IN
    vsBox.Parent = sCombat
    applyCorner(vsBox, 70)
    applyStroke(vsBox, C_GOLD, 4)

    local vsLbl = Instance.new("TextLabel")
    vsLbl.Name = "VsLabel"
    vsLbl.Size = UDim2.new(1, 0, 1, 0)
    vsLbl.BackgroundTransparency = 1
    vsLbl.Font = Enum.Font.GothamBlack
    vsLbl.TextSize = 62
    vsLbl.TextColor3 = C_GOLD
    vsLbl.Text = "VS"
    vsLbl.Parent = vsBox

    local combatTimerLbl = Instance.new("TextLabel")
    combatTimerLbl.Name = "TimerLabel"
    combatTimerLbl.Size = UDim2.new(0, 240, 0, 50)
    combatTimerLbl.AnchorPoint = Vector2.new(0.5, 0)
    combatTimerLbl.Position = UDim2.new(0.5, 0, 0.65, 0)
    combatTimerLbl.BackgroundTransparency = 1
    combatTimerLbl.Font = Enum.Font.GothamBlack
    combatTimerLbl.TextSize = 44
    combatTimerLbl.TextColor3 = C_GOLD
    combatTimerLbl.Text = "10:00"
    combatTimerLbl.Parent = sCombat

    -- Team Beta Card (Right, Massive 840x550)
    local betaCard = Instance.new("Frame")
    betaCard.Name = "TeamBetaCard"
    betaCard.Size = UDim2.new(0.5, -90, 0, 520)
    betaCard.Position = UDim2.new(0.5, 90, 0, 20)
    betaCard.BackgroundColor3 = C_CARD
    betaCard.Parent = sCombat
    applyCorner(betaCard, 24)
    applyStroke(betaCard, C_BETA, 3.5)

    local betaCrest = Instance.new("ImageLabel")
    betaCrest.Name = "TeamBetaCrest"
    betaCrest.Size = UDim2.new(0, 90, 0, 90)
    betaCrest.Position = UDim2.new(1, -120, 0, 30)
    betaCrest.BackgroundTransparency = 1
    betaCrest.ImageColor3 = C_BETA
    betaCrest.ScaleType = Enum.ScaleType.Fit
    betaCrest.Image = ""
    betaCrest.Parent = betaCard

    local betaHead = Instance.new("TextLabel")
    betaHead.Name = "Header"
    betaHead.Size = UDim2.new(1, -150, 0, 70)
    betaHead.Position = UDim2.new(0, 35, 0, 35)
    betaHead.BackgroundTransparency = 1
    betaHead.Font = Enum.Font.GothamBlack
    betaHead.TextSize = 58
    betaHead.TextColor3 = C_BETA
    betaHead.TextXAlignment = Enum.TextXAlignment.Left
    betaHead.Text = "TEAM BETA"
    betaHead.Parent = betaCard

    local betaAlive = Instance.new("TextLabel")
    betaAlive.Name = "Alive"
    betaAlive.Size = UDim2.new(0.5, 0, 0, 50)
    betaAlive.Position = UDim2.new(0, 35, 0, 125)
    betaAlive.BackgroundTransparency = 1
    betaAlive.Font = Enum.Font.GothamBlack
    betaAlive.TextSize = 42
    betaAlive.TextColor3 = C_IVORY
    betaAlive.TextXAlignment = Enum.TextXAlignment.Left
    betaAlive.Text = "ALIVE: 0"
    betaAlive.Parent = betaCard

    local betaHp = Instance.new("TextLabel")
    betaHp.Name = "HpLabel"
    betaHp.Size = UDim2.new(0.5, -35, 0, 50)
    betaHp.Position = UDim2.new(0.5, 0, 0, 125)
    betaHp.BackgroundTransparency = 1
    betaHp.Font = Enum.Font.GothamBold
    betaHp.TextSize = 36
    betaHp.TextColor3 = C_MUTED
    betaHp.TextXAlignment = Enum.TextXAlignment.Right
    betaHp.Text = "HP: 0 / 0 (100%)"
    betaHp.Parent = betaCard

    local bBarBg = Instance.new("Frame")
    bBarBg.Name = "HealthBarBg"
    bBarBg.Size = UDim2.new(1, -70, 0, 110)
    bBarBg.Position = UDim2.new(0, 35, 0, 200)
    bBarBg.BackgroundColor3 = C_CARD_IN
    bBarBg.Parent = betaCard
    applyCorner(bBarBg, 20)
    applyStroke(bBarBg, C_STEEL, 2.5)

    local bFill = Instance.new("Frame")
    bFill.Name = "Fill"
    bFill.Size = UDim2.new(1, 0, 1, 0)
    bFill.BackgroundColor3 = C_BETA
    bFill.BorderSizePixel = 0
    bFill.Parent = bBarBg
    applyCorner(bFill, 18)

    local bSub = Instance.new("TextLabel")
    bSub.Name = "SubTag"
    bSub.Size = UDim2.new(1, -70, 0, 50)
    bSub.Position = UDim2.new(0, 35, 0, 350)
    bSub.BackgroundTransparency = 1
    bSub.Font = Enum.Font.GothamBold
    bSub.TextSize = 28
    bSub.TextColor3 = C_STEEL
    bSub.TextXAlignment = Enum.TextXAlignment.Left
    bSub.Text = "OPPOSING SQUAD • AUTHORITATIVE SECTOR BETA"
    bSub.Parent = betaCard

    -- ========================================================================
    -- 8. SCENE: WINNER_DETERMINATION (Royal Victory Ceremony Scene)
    -- ========================================================================
    local sWinner = Instance.new("Frame")
    sWinner.Name = "Scene_Winner"
    sWinner.Size = UDim2.new(1, 0, 1, 0)
    sWinner.BackgroundTransparency = 1
    sWinner.Visible = (currentActiveScene == "Scene_Winner")
    sWinner.Parent = sceneContainer

    local winCeremony = Instance.new("TextLabel")
    winCeremony.Name = "CeremonyTitle"
    winCeremony.Size = UDim2.new(1, 0, 0, 60)
    winCeremony.Position = UDim2.new(0, 0, 0, 40)
    winCeremony.BackgroundTransparency = 1
    winCeremony.Font = Enum.Font.GothamBlack
    winCeremony.TextSize = 44
    winCeremony.TextColor3 = C_GOLD
    winCeremony.Text = "ARGONIA ARENA ONE • VICTORY CEREMONY"
    winCeremony.Parent = sWinner

    local winChampion = Instance.new("TextLabel")
    winChampion.Name = "HeroTitle"
    winChampion.Size = UDim2.new(1, 0, 0, 140)
    winChampion.Position = UDim2.new(0, 0, 0, 130)
    winChampion.BackgroundTransparency = 1
    winChampion.Font = Enum.Font.GothamBlack
    winChampion.TextSize = 110
    winChampion.TextColor3 = C_IVORY
    winChampion.Text = "CHAMPION: TEAM ALPHA"
    winChampion.Parent = sWinner

    local winDetails = Instance.new("TextLabel")
    winDetails.Name = "HeroSub"
    winDetails.Size = UDim2.new(1, 0, 0, 60)
    winDetails.Position = UDim2.new(0, 0, 0, 300)
    winDetails.BackgroundTransparency = 1
    winDetails.Font = Enum.Font.GothamBold
    winDetails.TextSize = 36
    winDetails.TextColor3 = C_MUTED
    winDetails.Text = "SURVIVORS RECORDED • MATCH RECORD SEALED"
    winDetails.Parent = sWinner

    -- ========================================================================
    -- FULL-SCREEN TRANSITION CURTAIN (Wipes across 1920x1115 on Scene Changes)
    -- ========================================================================
    local curtain = Instance.new("Frame")
    curtain.Name = "TransitionCurtain"
    curtain.Size = UDim2.new(1, 0, 1, 0)
    curtain.Position = UDim2.new(-1, 0, 0, 0)
    curtain.BackgroundColor3 = Color3.fromRGB(8, 14, 24)
    curtain.BorderSizePixel = 0
    curtain.ZIndex = 50
    curtain.Parent = mf

    local curtainStroke = Instance.new("UIStroke")
    curtainStroke.Color = C_GOLD
    curtainStroke.Thickness = 6
    curtainStroke.Parent = curtain

    local curtainGlow = Instance.new("Frame")
    curtainGlow.Name = "EdgeGlow"
    curtainGlow.Size = UDim2.new(0, 12, 1, 0)
    curtainGlow.Position = UDim2.new(1, -12, 0, 0)
    curtainGlow.BackgroundColor3 = C_CYAN
    curtainGlow.BorderSizePixel = 0
    curtainGlow.Parent = curtain

    -- Lower Broadcast Ticker
    local ticker = Instance.new("Frame")
    ticker.Name = "BroadcastTicker"
    ticker.Size = UDim2.new(1, -60, 0, 65)
    ticker.Position = UDim2.new(0, 30, 1, -85)
    ticker.BackgroundColor3 = C_CARD_IN
    ticker.Parent = mf
    applyCorner(ticker, 14)
    applyStroke(ticker, C_STEEL, 1.5)

    local tickerTag = Instance.new("TextLabel")
    tickerTag.Name = "Tag"
    tickerTag.Size = UDim2.new(0, 340, 1, 0)
    tickerTag.Position = UDim2.new(0, 25, 0, 0)
    tickerTag.BackgroundTransparency = 1
    tickerTag.Font = Enum.Font.GothamBlack
    tickerTag.TextSize = 22
    tickerTag.TextColor3 = C_GOLD
    tickerTag.TextXAlignment = Enum.TextXAlignment.Left
    tickerTag.Text = "ARIA // STADIUM BROADCAST"
    tickerTag.Parent = ticker

    local tickerDivider = Instance.new("Frame")
    tickerDivider.Size = UDim2.new(0, 2, 0.7, 0)
    tickerDivider.Position = UDim2.new(0, 375, 0.15, 0)
    tickerDivider.BackgroundColor3 = C_STEEL
    tickerDivider.BorderSizePixel = 0
    tickerDivider.Parent = ticker

    local tickerBody = Instance.new("TextLabel")
    tickerBody.Name = "Body"
    tickerBody.Size = UDim2.new(1, -400, 1, 0)
    tickerBody.Position = UDim2.new(0, 395, 0, 0)
    tickerBody.BackgroundTransparency = 1
    tickerBody.Font = Enum.Font.GothamBold
    tickerBody.TextSize = 24
    tickerBody.TextColor3 = C_IVORY
    tickerBody.TextXAlignment = Enum.TextXAlignment.Left
    tickerBody.TextTruncate = Enum.TextTruncate.AtEnd
    tickerBody.Text = "ARGONIA ARENA ONE • SPECTATOR BROADCAST ONLINE"
    tickerBody.Parent = ticker
end

-- ============================================================================
-- FULL-SCREEN SCENE TRANSITION CONTROLLER (Wipe + Glitch)
-- ============================================================================

function ArenaScreen.transitionToScene(sceneName)
    if currentActiveScene == sceneName then return end
    local oldSceneName = currentActiveScene
    currentActiveScene = sceneName
    
    findScreen()
    for _, gui in ipairs(surfaceGuis) do
        local mf = gui:FindFirstChild("MainFrame")
        local curtain = mf and mf:FindFirstChild("TransitionCurtain")
        local container = mf and mf:FindFirstChild("SceneContainer")
        
        if curtain and container then
            -- Full-screen curtain wipe from left to center
            curtain.Position = UDim2.new(-1, 0, 0, 0)
            local wipeIn = TweenService:Create(curtain, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
                Position = UDim2.new(0, 0, 0, 0)
            })
            wipeIn:Play()
            
            wipeIn.Completed:Connect(function()
                -- Switch active scene visibility
                for _, s in ipairs(container:GetChildren()) do
                    if s:IsA("Frame") then
                        s.Visible = (s.Name == sceneName)
                    end
                end
                
                -- Wipe curtain off to the right
                local wipeOut = TweenService:Create(curtain, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
                    Position = UDim2.new(1, 0, 0, 0)
                })
                wipeOut:Play()
                wipeOut.Completed:Connect(function()
                    curtain.Position = UDim2.new(-1, 0, 0, 0)
                end)
            end)
        else
            -- Fallback instant switch
            if container then
                for _, s in ipairs(container:GetChildren()) do
                    if s:IsA("Frame") then
                        s.Visible = (s.Name == sceneName)
                    end
                end
            end
        end
    end
    print(string.format("[ArenaScreenManager] Full-Screen Transition: %s -> %s", oldSceneName, sceneName))
end

function ArenaScreen.init()
    findScreen()
    for _, gui in ipairs(surfaceGuis) do
        buildGuiLayout(gui)
    end
    print(string.format("[ArenaScreenManager] Connected and built %d SurfaceGuis with Full-Screen Scenes on ArenaScreen.", #surfaceGuis))
end

function ArenaScreen.setEnabled(enabled)
    findScreen()
    for _, gui in ipairs(surfaceGuis) do
        gui.Enabled = enabled
    end
end

-- Holographic Boot Controller
function ArenaScreen.setHologramActive(active)
    isHologramActive = (active == true)
    findScreen()
    for _, gui in ipairs(surfaceGuis) do
        local mf = gui:FindFirstChild("MainFrame")
        if mf then
            if isHologramActive then
                mf.Visible = true
                task.spawn(function()
                    mf.BackgroundTransparency = 0.8
                    task.wait(0.08)
                    mf.BackgroundTransparency = 0.2
                    task.wait(0.06)
                    mf.BackgroundTransparency = 0.6
                    task.wait(0.08)
                    TweenService:Create(mf, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
                        BackgroundTransparency = 0.04
                    }):Play()
                end)
            else
                TweenService:Create(mf, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
                    BackgroundTransparency = 1.0
                }):Play()
                task.delay(0.42, function()
                    if not isHologramActive and mf then
                        mf.Visible = false
                    end
                end)
            end
        end
    end
    print(string.format("[ArenaScreenManager] Hologram state updated: %s", tostring(isHologramActive)))
end

function ArenaScreen.isHologramActive()
    return isHologramActive
end

-- Update phase sequence, title, subtitle & live countdown timer
function ArenaScreen.setSequence(phaseName, titleText, subtitleText, timeRemaining)
    findScreen()
    local timerText = formatTimer(timeRemaining)
    local badgeText = string.format("[ %s ]", tostring(phaseName or "ARENA"):upper():gsub("_", " "))
    
    -- Map phaseName to dedicated full-screen scene
    local targetScene = "Scene_ArenaOpen"
    if phaseName == "ARENA_OPEN" then
        targetScene = "Scene_ArenaOpen"
    elseif phaseName == "ARENA_GENERATION" then
        targetScene = "Scene_ArenaGeneration"
    elseif phaseName == "PREPARATION_ROOM" then
        targetScene = "Scene_PreparationRoom"
    elseif phaseName == "TELEPORTING_QUINS" then
        targetScene = "Scene_Teleporting"
    elseif phaseName == "STADIUM_ANTHEM" then
        targetScene = "Scene_StadiumAnthem"
    elseif phaseName == "PRE_GAME" then
        targetScene = "Scene_PreGame"
    elseif phaseName == "IN_GAME" then
        targetScene = "Scene_InGame"
    elseif phaseName == "WINNER_DETERMINATION" then
        targetScene = "Scene_Winner"
    elseif phaseName == "POST_GAME" or phaseName == "IDLE" then
        targetScene = "Scene_ArenaOpen"
    end
    
    ArenaScreen.transitionToScene(targetScene)
    
    for _, gui in ipairs(surfaceGuis) do
        local mf = gui:FindFirstChild("MainFrame")
        if mf then
            local topHeader = mf:FindFirstChild("TopHeader")
            local badge = topHeader and topHeader:FindFirstChild("PhaseBadge")
            local badgeLbl = badge and badge:FindFirstChild("BadgeLabel")
            if badgeLbl then
                badgeLbl.Text = badgeText
            end
            
            local container = mf:FindFirstChild("SceneContainer")
            local scene = container and container:FindFirstChild(targetScene)
            if scene then
                local hTitle = scene:FindFirstChild("HeroTitle")
                local hSub = scene:FindFirstChild("HeroSub")
                local tLbl = scene:FindFirstChild("TimerLabel") or (scene:FindFirstChild("TimerBox") and scene.TimerBox:FindFirstChild("TimerLabel"))
                
                if hTitle and titleText then hTitle.Text = titleText end
                if hSub and subtitleText then hSub.Text = subtitleText end
                if tLbl and timerText then tLbl.Text = timerText end
                
                -- Pre-Game Hero Countdown numeral
                if targetScene == "Scene_PreGame" then
                    local heroNum = scene:FindFirstChild("HeroNumber")
                    local shown = timeRemaining and math.max(1, math.floor(timeRemaining))
                    if heroNum and shown and heroNum.Text ~= tostring(shown) then -- (refreshed 4x/s: pulse only on a new number)
                        heroNum.Text = tostring(shown)
                        -- Shockwave pulse
                        heroNum.TextSize = 310
                        TweenService:Create(heroNum, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
                            TextSize = 250
                        }):Play()
                    end
                end
            end
        end
    end
end

-- Backward compatibility for orchestrator setTitle calls
function ArenaScreen.setTitle(titleText, subtitleText)
    findScreen()
    for _, gui in ipairs(surfaceGuis) do
        local mf = gui:FindFirstChild("MainFrame")
        local container = mf and mf:FindFirstChild("SceneContainer")
        local scene = container and container:FindFirstChild(currentActiveScene)
        if scene then
            local t = scene:FindFirstChild("HeroTitle")
            local s = scene:FindFirstChild("HeroSub")
            if t and titleText then t.Text = titleText end
            if s and subtitleText then s.Text = subtitleText end
        end
    end
end

-- Comprehensive Match State synchronization
function ArenaScreen.updateMatchState(phase, timeRemaining, alphaHp, alphaMax, betaHp, betaMax, alphaAlive, betaAlive)
    ArenaScreen.setSequence(phase, nil, nil, timeRemaining)
    ArenaScreen.updateHealthBars(alphaHp, alphaMax, betaHp, betaMax, alphaAlive, betaAlive)
end

-- Health bars & alive counters
function ArenaScreen.updateHealthBars(alphaHp, alphaMax, betaHp, betaMax, alphaAlive, betaAlive)
    findScreen()
    alphaHp = math.max(0, tonumber(alphaHp) or 0)
    alphaMax = math.max(0, tonumber(alphaMax) or 0)
    betaHp = math.max(0, tonumber(betaHp) or 0)
    betaMax = math.max(0, tonumber(betaMax) or 0)
    
    local alphaRatio = (alphaMax > 0) and math.clamp(alphaHp / alphaMax, 0, 1) or 0
    local betaRatio = (betaMax > 0) and math.clamp(betaHp / betaMax, 0, 1) or 0
    
    for _, gui in ipairs(surfaceGuis) do
        local mf = gui:FindFirstChild("MainFrame")
        local container = mf and mf:FindFirstChild("SceneContainer")
        local combat = container and container:FindFirstChild("Scene_InGame")
        if combat then
            -- Team Alpha
            local alphaCard = combat:FindFirstChild("TeamAlphaCard")
            if alphaCard then
                local alive = alphaCard:FindFirstChild("Alive")
                local hpLbl = alphaCard:FindFirstChild("HpLabel")
                local barBg = alphaCard:FindFirstChild("HealthBarBg")
                local fill = barBg and barBg:FindFirstChild("Fill")
                
                if alive then
                    alive.Text = string.format("ALIVE: %d", alphaAlive or 0)
                end
                if hpLbl then
                    hpLbl.Text = string.format("HP: %d / %d (%d%%)", math.floor(alphaHp), math.floor(alphaMax), math.floor(alphaRatio * 100))
                end
                if fill then
                    TweenService:Create(fill, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
                        Size = UDim2.new(alphaRatio, 0, 1, 0)
                    }):Play()
                end
            end
            
            -- Team Beta
            local betaCard = combat:FindFirstChild("TeamBetaCard")
            if betaCard then
                local alive = betaCard:FindFirstChild("Alive")
                local hpLbl = betaCard:FindFirstChild("HpLabel")
                local barBg = betaCard:FindFirstChild("HealthBarBg")
                local fill = barBg and barBg:FindFirstChild("Fill")
                
                if alive then
                    alive.Text = string.format("ALIVE: %d", betaAlive or 0)
                end
                if hpLbl then
                    hpLbl.Text = string.format("HP: %d / %d (%d%%)", math.floor(betaHp), math.floor(betaMax), math.floor(betaRatio * 100))
                end
                if fill then
                    TweenService:Create(fill, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
                        Size = UDim2.new(betaRatio, 0, 1, 0)
                    }):Play()
                end
            end
        end
    end
end

-- Lower Ticker Announcement
function ArenaScreen.displayAnnouncement(text, duration, speakerTag, color)
    duration = duration or 4.0
    speakerTag = speakerTag or "ARIA // STADIUM BROADCAST"
    color = color or C_GOLD
    
    findScreen()
    for _, gui in ipairs(surfaceGuis) do
        local mf = gui:FindFirstChild("MainFrame")
        local ticker = mf and mf:FindFirstChild("BroadcastTicker")
        if ticker then
            local tag = ticker:FindFirstChild("Tag")
            local body = ticker:FindFirstChild("Body")
            local stroke = ticker:FindFirstChildOfClass("UIStroke")
            
            if tag then
                tag.Text = speakerTag
                tag.TextColor3 = color
            end
            if stroke then
                stroke.Color = color
            end
            if body then
                body.Text = text
            end
        end
    end
    
    if activeAnnouncementThread then
        task.cancel(activeAnnouncementThread)
    end
    if duration > 0 then
        activeAnnouncementThread = task.delay(duration, function()
            ArenaScreen.clearAnnouncement()
        end)
    end
end

function ArenaScreen.clearAnnouncement()
    findScreen()
    for _, gui in ipairs(surfaceGuis) do
        local mf = gui:FindFirstChild("MainFrame")
        local ticker = mf and mf:FindFirstChild("BroadcastTicker")
        if ticker then
            local body = ticker:FindFirstChild("Body")
            if body then
                body.Text = "ARGONIA ARENA ONE • SPECTATOR BROADCAST ONLINE"
            end
        end
    end
end

function ArenaScreen.showWinner(winnerText, details)
    findScreen()
    ArenaScreen.transitionToScene("Scene_Winner")
    for _, gui in ipairs(surfaceGuis) do
        local mf = gui:FindFirstChild("MainFrame")
        local container = mf and mf:FindFirstChild("SceneContainer")
        local win = container and container:FindFirstChild("Scene_Winner")
        if win then
            local t = win:FindFirstChild("HeroTitle")
            local s = win:FindFirstChild("HeroSub")
            if t then t.Text = string.format("CHAMPION: %s", tostring(winnerText):upper()) end
            if s then s.Text = details or "MATCH CONCLUDED • VICTORY ACHIEVED" end
        end
    end
    ArenaScreen.displayAnnouncement(string.format("CHAMPION OF ARENA ONE: %s", tostring(winnerText):upper()), 6.0, "VICTORY CEREMONY", C_GOLD)
end

ArenaScreen.init()

return ArenaScreen
