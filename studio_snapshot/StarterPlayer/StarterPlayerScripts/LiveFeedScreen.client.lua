--// ArenaHologramClientController.client.lua
-- Repurposed from LiveFeedScreen for Argonia ArenaOne Production-Grade Stadium Experience
-- Controls: 
-- 1. 360° Orbital Ribbon Board Ring (ArenaGlobeRing) with Double-Sided SurfaceGuis (100% visible 360°)
-- 2. Colossal Scale: 95-stud radius, 36-stud height, 32 smooth polygon panels, 96pt-120pt stadium typography
-- 3. Holographic Materialization at T+5s of ARENA_OPEN (Starts 100% invisible, glitched ForceField ignition)
-- 4. Majestic 60 FPS Anti-Gravity Hovering: 14.0 studs for ArenaScreen & 10.0 studs for ArenaGlobe
-- 5. Dynamic Left-to-Right Roll Oscillation & Continuous Yaw Rotation for ArenaGlobeRing
-- 6. Contextual Ad Campaign Switching, Animated Transitions & Dynamic Lighting Adaptation

local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- ============================================================================
-- ⚙️ BAI'S PRODUCTION-GRADE STADIUM CONFIGURATION TABLE
-- Tuned for the Colossal 600x600 Stud Argonia Arena Colosseum
-- ============================================================================
local ArenaRibbonConfig = {
    -- Globe & Ring Geometry
    GlobeCenter = Vector3.new(-0.5, 370, -411),
    RingRadius = 95,            -- Radius of orbital halo (Diameter 190 studs framing 100-stud globe)
    RingHeight = 36,            -- Colossal height of each ribbon panel (studs)
    PanelCount = 32,            -- 32 polygon panels for ultra-smooth circular curvature
    PanelThickness = 1.0,       -- Sturdy physical panel thickness (studs)
    TrimHeight = 1.4,           -- Height of top & bottom glowing neon trim bars (studs)
    
    -- Majestic Kinematic Movement
    YawRotationSpeed = 0.15,     -- Radians per second of continuous orbital yaw rotation
    RollOscillationAmp = 7.5,   -- Degrees of left-to-right gyro tilting (±7.5°)
    RollOscillationSpeed = 0.45, -- Frequency of left-to-right tilting
    GlobeHoverAmp = 10.0,       -- Studs of slow vertical float for ArenaGlobe (±10 studs)
    GlobeHoverSpeed = 0.48,     -- Frequency of vertical float for ArenaGlobe (~13s period)
    ScreenHoverAmp = 14.0,      -- Studs of majestic anti-gravity float for ArenaScreen (±14 studs)
    ScreenHoverSpeed = 0.58,    -- Frequency of vertical float for ArenaScreen (~11s period)
    
    -- Display & Typography
    CanvasWidth = 1920,
    CanvasHeight = 600,
    AdRotationInterval = 8.0,   -- Seconds per advertisement slide
    MarqueeSpeed = 120,         -- Pixels per second horizontal marquee text scroll
    TransitionType = "Wipe",    -- Default transition: "Wipe", "Fade", "Slide", or "Flash"
    
    -- Production Stadium Color Palette
    ColorBg = Color3.fromRGB(8, 14, 24),
    ColorBgDark = Color3.fromRGB(4, 8, 16),
    ColorGold = Color3.fromRGB(212, 175, 55),
    ColorGoldBright = Color3.fromRGB(255, 215, 0),
    ColorCyan = Color3.fromRGB(0, 210, 255),
    ColorCyanGlow = Color3.fromRGB(80, 230, 255),
    ColorText = Color3.fromRGB(245, 250, 255),
    ColorMuted = Color3.fromRGB(155, 185, 220),
    
    -- Contextual Advertising Campaigns per Match Phase
    Campaigns = {
        DEFAULT = {
            { Title = "ARGONIA GUILD SYNDICATE", Sub = "THE AUTHORITATIVE ORDER OF CHAMPIONS", Tag = "OFFICIAL PARTNER" },
            { Title = "SKYLARK EXPEDITIONS", Sub = "EXPLORE THE UNCHARTED FLOATING REALMS", Tag = "STADIUM SPONSOR" },
            { Title = "AETHERIUM FORGEWORKS", Sub = "MASTERWORK WEAPONRY & CELESTIAL CRAFTS", Tag = "FOUNDRY GUILD" },
            { Title = "CELESTIAL BLADEWORKS", Sub = "FORGED IN STORM • TEMPERED IN SKY", Tag = "EQUIPMENT ORDER" },
        },
        ARENA_OPEN = {
            { Title = "WELCOME TO ARENA ONE", Sub = "GATES HAVE OPENED • TOURNAMENT PROTOCOLS ENGAGED", Tag = "STADIUM NOTICE" },
            { Title = "COLOSSEUM LIVE FEED ACTIVE", Sub = "SPECTATOR CAMERAS & ORBITAL DRONES DEPLOYED", Tag = "BROADCAST" },
            { Title = "ARGONIA CHAMPIONSHIP", Sub = "PRESTIGE • HONOR • CONQUEST • GLORY", Tag = "TOURNAMENT" },
        },
        ARENA_GENERATION = {
            { Title = "TERRAIN MATRIX FORMING", Sub = "PROCEDURAL SECTOR ARCHITECTURE SYNTHESIZING", Tag = "SYSTEM TELEMETRY" },
            { Title = "SECTOR BLUEPRINTS VERIFIED", Sub = "FLOATING OBSTACLES & HAZARD GRIDS ALIGNED", Tag = "ARCHITECTURE" },
        },
        PREPARATION_ROOM = {
            { Title = "GLADIATOR STAGING PODS ACTIVE", Sub = "FIGHTERS AT READY STATIONS IN BACKROOM CHAMBERS", Tag = "STAGING PROTOCOL" },
            { Title = "TACTICAL BRIEFING COMMENCED", Sub = "ELEMENTAL ATTUNEMENT & FORMATION ANALYSIS", Tag = "WAR ROOM" },
        },
        TELEPORTING_QUINS = {
            { Title = "DISPATCH PROTOCOL ACTIVE", Sub = "TELEPORTATION MATRICES CONVERGING ON ARENA SECTORS", Tag = "HIGH ALERT" },
            { Title = "WARRIORS ON FIELD", Sub = "SECTOR ALPHA AND SECTOR BETA READY FOR ENTRY", Tag = "DEPLOYMENT" },
        },
        STADIUM_ANTHEM = {
            { Title = "ALL RISE FOR THE ARENA ONE ANTHEM", Sub = "CEREMONIAL VOCALS & ACOUSTIC VISUALIZATION", Tag = "CEREMONY" },
            { Title = "SOLEMN ARENA HYMN", Sub = "A SYMPHONY OF GLORY BEFORE THE CLASH", Tag = "ANTHEM" },
            { Title = "THE SKYLARK LEGACY", Sub = "WHERE CHAMPIONS ASCEND AND LEGENDS ARE FORGED", Tag = "TRADITION" },
        },
        PRE_GAME = {
            { Title = "ENGAGEMENT IMMINENT", Sub = "COMBAT COUNTDOWN RUNNING • STAND BY FOR BATTLE", Tag = "BATTLE STATIONS" },
            { Title = "AUTHORITATIVE ARENA RULES", Sub = "PHYSICAL SIMULATION COMBAT PROTOCOLS ENGAGED", Tag = "COMBAT READINESS" },
        },
        IN_GAME = {
            { Title = "COMBAT IN PROGRESS", Sub = "SECTOR ALPHA SQUAD VS SECTOR BETA SQUAD", Tag = "LIVE ENGAGEMENT" },
            { Title = "CLASH OF THE QUINS", Sub = "WATCH SQUAD ACTIONS, TACTICAL READS & IMPACTS", Tag = "SPECTATOR CAM" },
            { Title = "PURE SPECTACLE", Sub = "DYNAMIC MOMENTUM • WEIGHT • ELEMENTAL COLLISION", Tag = "SKY ARENA" },
        },
        WINNER_DETERMINATION = {
            { Title = "VICTORY ACHIEVED", Sub = "ALL HAIL THE SUPREME CHAMPIONS OF ARENA ONE", Tag = "VICTORY CEREMONY" },
            { Title = "A MEMORABLE CONQUEST", Sub = "RECORDED FOREVER IN THE ARCHIVES OF ARGONIA", Tag = "LEGACY" },
        },
    }
}

-- ============================================================================
-- SYSTEM REFERENCES & INITIALIZATION
-- ============================================================================
local arenaOne = Workspace:WaitForChild("argoniaonion", 15) and Workspace.argoniaonion:WaitForChild("ArenaOne", 15)
local arenaScreen = arenaOne and arenaOne:FindFirstChild("ArenaScreen")
local arenaGlobe = arenaOne and arenaOne:FindFirstChild("ArenaGlobe")

local initialScreenCFrame = arenaScreen and arenaScreen.CFrame or CFrame.new(-39, 235.34, -106)
local initialGlobePosition = arenaGlobe and arenaGlobe.Position or ArenaRibbonConfig.GlobeCenter

-- Force authoritatively invisible initial state for ArenaGlobe
local globeLight = nil
if arenaGlobe then
    arenaGlobe.Material = Enum.Material.ForceField
    arenaGlobe.Color = ArenaRibbonConfig.ColorCyan
    arenaGlobe.Transparency = 1.0
    arenaGlobe.CanCollide = false
    arenaGlobe.CastShadow = false
    
    -- Inner holographic light source (starts disabled)
    globeLight = arenaGlobe:FindFirstChild("HoloLight")
    if not globeLight then
        globeLight = Instance.new("PointLight")
        globeLight.Name = "HoloLight"
        globeLight.Color = ArenaRibbonConfig.ColorCyanGlow
        globeLight.Range = 220
        globeLight.Brightness = 0.0
        globeLight.Shadows = false
        globeLight.Parent = arenaGlobe
    end
end

local ringModel = nil
local ringPanels = {}

local isHologramsVisible = false
local currentPhase = "IDLE"
local currentAdIndex = 1
local adTimer = 0
local yawAngle = 0

-- UI Helpers
local function applyCorner(inst, radius)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, radius)
    c.Parent = inst
    return c
end

local function applyStroke(inst, color, thickness)
    local s = Instance.new("UIStroke")
    s.Color = color or ArenaRibbonConfig.ColorGold
    s.Thickness = thickness or 2.0
    s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    s.Parent = inst
    return s
end

-- ============================================================================
-- DOUBLE-SIDED 360° RIBBON RING GENERATOR
-- Constructs 32 smooth polygon panels with outer AND inner SurfaceGuis
-- ============================================================================
local function createSurfaceGuiFace(parentPart, faceNormal, faceName)
    local sg = Instance.new("SurfaceGui")
    sg.Name = "RibbonGui_" .. faceName
    sg.Face = faceNormal
    sg.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
    sg.CanvasSize = Vector2.new(ArenaRibbonConfig.CanvasWidth, ArenaRibbonConfig.CanvasHeight)
    sg.LightInfluence = 0.0
    sg.AlwaysOnTop = false
    sg.ClipsDescendants = true
    sg.Adornee = parentPart
    sg.Parent = parentPart
    
    -- Main Container Frame
    local rootFrame = Instance.new("Frame")
    rootFrame.Name = "Root"
    rootFrame.Size = UDim2.new(1, 0, 1, 0)
    rootFrame.BackgroundColor3 = ArenaRibbonConfig.ColorBg
    rootFrame.BackgroundTransparency = 1.0 -- Starts hidden for holographic boot
    rootFrame.BorderSizePixel = 0
    rootFrame.Parent = sg
    applyCorner(rootFrame, 12)
    local rootStroke = applyStroke(rootFrame, ArenaRibbonConfig.ColorGold, 3.0)
    rootStroke.Transparency = 1.0
    
    -- Background Radial/Linear Accent Lines
    local bgGlow = Instance.new("Frame")
    bgGlow.Name = "BgGlow"
    bgGlow.Size = UDim2.new(1, 0, 1, 0)
    bgGlow.BackgroundColor3 = ArenaRibbonConfig.ColorCyan
    bgGlow.BackgroundTransparency = 0.94
    bgGlow.BorderSizePixel = 0
    bgGlow.Parent = rootFrame
    
    -- 1. TOP MARQUEE STRIP (Continuous Stadium Ticker)
    local marqueeFrame = Instance.new("Frame")
    marqueeFrame.Name = "MarqueeStrip"
    marqueeFrame.Size = UDim2.new(1, -36, 0, 100)
    marqueeFrame.Position = UDim2.new(0, 18, 0, 18)
    marqueeFrame.BackgroundColor3 = ArenaRibbonConfig.ColorBgDark
    marqueeFrame.BackgroundTransparency = 0.25
    marqueeFrame.ClipsDescendants = true
    marqueeFrame.Parent = rootFrame
    applyCorner(marqueeFrame, 8)
    applyStroke(marqueeFrame, ArenaRibbonConfig.ColorCyan, 2.0)
    
    local marqueeLbl = Instance.new("TextLabel")
    marqueeLbl.Name = "MarqueeLabel"
    marqueeLbl.Size = UDim2.new(3, 0, 1, 0)
    marqueeLbl.Position = UDim2.new(0, 0, 0, 0)
    marqueeLbl.BackgroundTransparency = 1
    marqueeLbl.Font = Enum.Font.GothamBlack
    marqueeLbl.TextSize = 48
    marqueeLbl.TextColor3 = ArenaRibbonConfig.ColorGoldBright
    marqueeLbl.TextXAlignment = Enum.TextXAlignment.Left
    marqueeLbl.Text = "★ ARGONIA ARENA ONE ★ TOURNAMENT BROADCAST ★ PRESTIGE COMBAT ★ HIGH DEFINITION LIVE FEED ★ HONOR • GLORY • DESTINY ★ "
    marqueeLbl.Parent = marqueeFrame
    
    -- 2. CENTRAL ADVERTISEMENT CONTAINER (Massive Production Typography)
    local adContainer = Instance.new("Frame")
    adContainer.Name = "AdContainer"
    adContainer.Size = UDim2.new(1, -36, 0, 440)
    adContainer.Position = UDim2.new(0, 18, 0, 136)
    adContainer.BackgroundColor3 = ArenaRibbonConfig.ColorBgDark
    adContainer.BackgroundTransparency = 0.35
    adContainer.ClipsDescendants = true
    adContainer.Parent = rootFrame
    applyCorner(adContainer, 10)
    applyStroke(adContainer, ArenaRibbonConfig.ColorGold, 2.5)
    
    -- Category Badge Capsule
    local tagLbl = Instance.new("TextLabel")
    tagLbl.Name = "TagLabel"
    tagLbl.Size = UDim2.new(0, 360, 0, 52)
    tagLbl.Position = UDim2.new(0, 32, 0, 24)
    tagLbl.BackgroundColor3 = Color3.fromRGB(15, 36, 60)
    tagLbl.Font = Enum.Font.GothamBlack
    tagLbl.TextSize = 28
    tagLbl.TextColor3 = ArenaRibbonConfig.ColorCyanGlow
    tagLbl.Text = "OFFICIAL PARTNER"
    tagLbl.Parent = adContainer
    applyCorner(tagLbl, 8)
    applyStroke(tagLbl, ArenaRibbonConfig.ColorCyan, 1.8)
    
    -- Colossal Headline Title (100pt Stadium Scale)
    local titleLbl = Instance.new("TextLabel")
    titleLbl.Name = "TitleLabel"
    titleLbl.Size = UDim2.new(1, -64, 0, 190)
    titleLbl.Position = UDim2.new(0, 32, 0, 92)
    titleLbl.BackgroundTransparency = 1
    titleLbl.Font = Enum.Font.GothamBlack
    titleLbl.TextSize = 100
    titleLbl.TextColor3 = ArenaRibbonConfig.ColorText
    titleLbl.TextXAlignment = Enum.TextXAlignment.Left
    titleLbl.TextTruncate = Enum.TextTruncate.AtEnd
    titleLbl.Text = "ARGONIA GUILD SYNDICATE"
    titleLbl.Parent = adContainer
    
    local titleStroke = Instance.new("UIStroke")
    titleStroke.Color = Color3.fromRGB(0, 0, 0)
    titleStroke.Thickness = 4.0
    titleStroke.Parent = titleLbl
    
    -- Subtitle / Tagline (46pt Stadium Scale)
    local subLbl = Instance.new("TextLabel")
    subLbl.Name = "SubLabel"
    subLbl.Size = UDim2.new(1, -64, 0, 90)
    subLbl.Position = UDim2.new(0, 32, 0, 300)
    subLbl.BackgroundTransparency = 1
    subLbl.Font = Enum.Font.GothamBold
    subLbl.TextSize = 46
    subLbl.TextColor3 = ArenaRibbonConfig.ColorMuted
    subLbl.TextXAlignment = Enum.TextXAlignment.Left
    subLbl.TextTruncate = Enum.TextTruncate.AtEnd
    subLbl.Text = "THE AUTHORITATIVE ORDER OF CHAMPIONS"
    subLbl.Parent = adContainer
    
    -- Animated Transition Overlay
    local flashOverlay = Instance.new("Frame")
    flashOverlay.Name = "FlashOverlay"
    flashOverlay.Size = UDim2.new(1, 0, 1, 0)
    flashOverlay.BackgroundColor3 = Color3.new(1, 1, 1)
    flashOverlay.BackgroundTransparency = 1.0
    flashOverlay.BorderSizePixel = 0
    flashOverlay.ZIndex = 15
    flashOverlay.Parent = adContainer
    
    return {
        gui = sg,
        rootFrame = rootFrame,
        rootStroke = rootStroke,
        adContainer = adContainer,
        titleLabel = titleLbl,
        subLabel = subLbl,
        tagLabel = tagLbl,
        marqueeLabel = marqueeLbl,
        flashOverlay = flashOverlay,
    }
end

local function constructRibbonRing()
    if ringModel then
        ringModel:Destroy()
    end
    ringPanels = {}
    
    ringModel = Instance.new("Model")
    ringModel.Name = "ArenaGlobeRibbonRing_Client"
    ringModel.Parent = Workspace
    
    local panelCount = ArenaRibbonConfig.PanelCount
    local radius = ArenaRibbonConfig.RingRadius
    local height = ArenaRibbonConfig.RingHeight
    local thickness = ArenaRibbonConfig.PanelThickness
    local trimHeight = ArenaRibbonConfig.TrimHeight
    
    -- Chord width per polygon segment with slight overlap
    local angleStep = (math.pi * 2) / panelCount
    local chordWidth = 2 * radius * math.sin(angleStep * 0.5) * 1.03
    
    for i = 1, panelCount do
        local angle = (i - 1) * angleStep
        
        -- Main Ribbon Structural Panel
        local part = Instance.new("Part")
        part.Name = string.format("RibbonPanel_%02d", i)
        part.Size = Vector3.new(chordWidth, height, thickness)
        part.Material = Enum.Material.SmoothPlastic
        part.Color = ArenaRibbonConfig.ColorBg
        part.Transparency = 1.0 -- Starts hidden for holographic boot
        part.Anchored = true
        part.CanCollide = false
        part.CanTouch = false
        part.CanQuery = false
        part.CastShadow = false
        part.Parent = ringModel
        
        -- Top Neon Architectural Trim Rail (Electric Cyan)
        local topTrim = Instance.new("Part")
        topTrim.Name = "TopTrim"
        topTrim.Size = Vector3.new(chordWidth * 1.02, trimHeight, thickness * 1.15)
        topTrim.Material = Enum.Material.Neon
        topTrim.Color = ArenaRibbonConfig.ColorCyan
        topTrim.Transparency = 1.0 -- Starts hidden
        topTrim.Anchored = true
        topTrim.CanCollide = false
        topTrim.CanTouch = false
        topTrim.CastShadow = false
        topTrim.Parent = ringModel
        
        -- Bottom Neon Architectural Trim Rail (Argonia Gold)
        local bottomTrim = Instance.new("Part")
        bottomTrim.Name = "BottomTrim"
        bottomTrim.Size = Vector3.new(chordWidth * 1.02, trimHeight, thickness * 1.15)
        bottomTrim.Material = Enum.Material.Neon
        bottomTrim.Color = ArenaRibbonConfig.ColorGold
        bottomTrim.Transparency = 1.0 -- Starts hidden
        bottomTrim.Anchored = true
        bottomTrim.CanCollide = false
        bottomTrim.CanTouch = false
        bottomTrim.CastShadow = false
        bottomTrim.Parent = ringModel
        
        -- 🌟 DOUBLE-SIDED MOUNTING:
        -- Front face = Outward facing (toward outer stadium stands)
        -- Back face = Inward facing (toward arena center & colosseum stands across)
        local outerData = createSurfaceGuiFace(part, Enum.NormalId.Front, "Outer")
        local innerData = createSurfaceGuiFace(part, Enum.NormalId.Back, "Inner")
        
        table.insert(ringPanels, {
            part = part,
            topTrim = topTrim,
            bottomTrim = bottomTrim,
            outer = outerData,
            inner = innerData,
            relativeAngle = angle,
        })
    end
    
    print(string.format("[ArenaHologramClient] Successfully constructed %d-panel Double-Sided 360° Ribbon Ring (Radius: %d, Height: %d).", 
        #ringPanels, radius, height))
end

-- ============================================================================
-- SEQUENTIAL AD ROTATION WITH ANIMATED TRANSITIONS (Wipe, Fade, Slide, Flash)
-- Applied simultaneously to both Outer and Inner display faces
-- ============================================================================
local function getActiveAds()
    return ArenaRibbonConfig.Campaigns[currentPhase] or ArenaRibbonConfig.Campaigns.DEFAULT
end

local function applyFaceTransition(faceData, adData, transitionType)
    local container = faceData.adContainer
    local title = faceData.titleLabel
    local sub = faceData.subLabel
    local tag = faceData.tagLabel
    local flash = faceData.flashOverlay
    
    transitionType = transitionType or ArenaRibbonConfig.TransitionType
    
    if transitionType == "Flash" then
        flash.BackgroundColor3 = Color3.new(1, 1, 1)
        flash.BackgroundTransparency = 0.1
        title.Text = adData.Title
        sub.Text = adData.Sub
        tag.Text = adData.Tag
        TweenService:Create(flash, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
            BackgroundTransparency = 1.0
        }):Play()
    elseif transitionType == "Fade" then
        local t1 = TweenService:Create(title, TweenInfo.new(0.25), { TextTransparency = 1.0 })
        local t2 = TweenService:Create(sub, TweenInfo.new(0.25), { TextTransparency = 1.0 })
        t1:Play(); t2:Play()
        task.delay(0.26, function()
            title.Text = adData.Title
            sub.Text = adData.Sub
            tag.Text = adData.Tag
            TweenService:Create(title, TweenInfo.new(0.3), { TextTransparency = 0 }):Play()
            TweenService:Create(sub, TweenInfo.new(0.3), { TextTransparency = 0 }):Play()
        end)
    elseif transitionType == "Slide" then
        local outTween = TweenService:Create(container, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
            Position = UDim2.new(-1, 0, 0, 136)
        })
        outTween:Play()
        task.delay(0.26, function()
            title.Text = adData.Title
            sub.Text = adData.Sub
            tag.Text = adData.Tag
            container.Position = UDim2.new(1, 0, 0, 136)
            TweenService:Create(container, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
                Position = UDim2.new(0, 18, 0, 136)
            }):Play()
        end)
    else -- "Wipe" (Production Horizontal Wipe)
        flash.BackgroundColor3 = ArenaRibbonConfig.ColorBgDark
        flash.BackgroundTransparency = 0.0
        flash.Size = UDim2.new(0, 0, 1, 0)
        flash.Position = UDim2.new(0, 0, 0, 0)
        local wipeIn = TweenService:Create(flash, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
            Size = UDim2.new(1, 0, 1, 0)
        })
        wipeIn:Play()
        task.delay(0.23, function()
            title.Text = adData.Title
            sub.Text = adData.Sub
            tag.Text = adData.Tag
            flash.Position = UDim2.new(1, 0, 0, 0)
            local wipeOut = TweenService:Create(flash, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
                Position = UDim2.new(0, 0, 0, 0),
                Size = UDim2.new(0, 0, 1, 0)
            })
            wipeOut:Play()
        end)
    end
end

local function rotateAds(forced)
    local ads = getActiveAds()
    if #ads == 0 then return end
    
    currentAdIndex = (currentAdIndex % #ads) + 1
    local nextAd = ads[currentAdIndex]
    
    local transitions = { "Wipe", "Fade", "Slide", "Flash" }
    local chosenTransition = forced and "Flash" or transitions[((currentAdIndex - 1) % #transitions) + 1]
    
    for _, p in ipairs(ringPanels) do
        applyFaceTransition(p.outer, nextAd, chosenTransition)
        applyFaceTransition(p.inner, nextAd, chosenTransition)
    end
end

-- ============================================================================
-- HOLOGRAPHIC BOOT-UP / ACTIVATION SEQUENCE
-- Materializes ArenaGlobe and the Double-Sided Ribbon Ring at T+5s of ARENA_OPEN
-- ============================================================================
local function setHologramsVisible(visible)
    if isHologramsVisible == visible then return end
    isHologramsVisible = visible
    
    if visible then
        print("[ArenaHologramClient] ✨ Initiating Colossal Holographic Boot Sequence (T+5s)...")
        
        -- 1. ArenaGlobe ForceField Materialization with Glitch Flicker
        if arenaGlobe then
            arenaGlobe.Material = Enum.Material.ForceField
            arenaGlobe.Color = ArenaRibbonConfig.ColorCyan
            arenaGlobe.Transparency = 0.95
            
            if globeLight then
                globeLight.Enabled = true
                globeLight.Brightness = 0.5
            end
            
            task.spawn(function()
                task.wait(0.05); arenaGlobe.Transparency = 0.15; if globeLight then globeLight.Brightness = 3.5 end
                task.wait(0.06); arenaGlobe.Transparency = 0.75; if globeLight then globeLight.Brightness = 1.0 end
                task.wait(0.05); arenaGlobe.Transparency = 0.25; if globeLight then globeLight.Brightness = 2.8 end
                task.wait(0.08)
                TweenService:Create(arenaGlobe, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
                    Transparency = 0.45
                }):Play()
                if globeLight then
                    TweenService:Create(globeLight, TweenInfo.new(0.4), { Brightness = 2.0 }):Play()
                end
            end)
        end
        
        -- 2. Ring Panels & Neon Trims Staggered Holographic Ignition
        for i, p in ipairs(ringPanels) do
            local delayTime = (i - 1) * 0.015 -- Staggered wave around the ring perimeter
            task.delay(delayTime, function()
                p.part.Transparency = 0.7
                p.topTrim.Transparency = 0.4
                p.bottomTrim.Transparency = 0.4
                p.outer.rootFrame.BackgroundTransparency = 0.7
                p.inner.rootFrame.BackgroundTransparency = 0.7
                p.outer.rootStroke.Transparency = 0.7
                p.inner.rootStroke.Transparency = 0.7
                
                task.wait(0.05)
                p.part.Transparency = 0.1
                p.topTrim.Transparency = 0.0
                p.bottomTrim.Transparency = 0.0
                p.outer.rootFrame.BackgroundTransparency = 0.1
                p.inner.rootFrame.BackgroundTransparency = 0.1
                
                task.wait(0.06)
                p.part.Transparency = 0.5
                p.outer.rootFrame.BackgroundTransparency = 0.5
                
                task.wait(0.05)
                TweenService:Create(p.part, TweenInfo.new(0.3), { Transparency = 0.15 }):Play()
                TweenService:Create(p.topTrim, TweenInfo.new(0.3), { Transparency = 0.0 }):Play()
                TweenService:Create(p.bottomTrim, TweenInfo.new(0.3), { Transparency = 0.0 }):Play()
                TweenService:Create(p.outer.rootFrame, TweenInfo.new(0.3), { BackgroundTransparency = 0.05 }):Play()
                TweenService:Create(p.inner.rootFrame, TweenInfo.new(0.3), { BackgroundTransparency = 0.05 }):Play()
                TweenService:Create(p.outer.rootStroke, TweenInfo.new(0.3), { Transparency = 0.0 }):Play()
                TweenService:Create(p.inner.rootStroke, TweenInfo.new(0.3), { Transparency = 0.0 }):Play()
            end)
        end
        
        -- Flash in active ads cleanly
        rotateAds(true)
    else
        print("[ArenaHologramClient] Holograms entering powered-down standby.")
        if arenaGlobe then
            TweenService:Create(arenaGlobe, TweenInfo.new(0.4), { Transparency = 1.0 }):Play()
            if globeLight then
                TweenService:Create(globeLight, TweenInfo.new(0.4), { Brightness = 0.0 }):Play()
            end
        end
        for _, p in ipairs(ringPanels) do
            TweenService:Create(p.part, TweenInfo.new(0.35), { Transparency = 1.0 }):Play()
            TweenService:Create(p.topTrim, TweenInfo.new(0.35), { Transparency = 1.0 }):Play()
            TweenService:Create(p.bottomTrim, TweenInfo.new(0.35), { Transparency = 1.0 }):Play()
            TweenService:Create(p.outer.rootFrame, TweenInfo.new(0.35), { BackgroundTransparency = 1.0 }):Play()
            TweenService:Create(p.inner.rootFrame, TweenInfo.new(0.35), { BackgroundTransparency = 1.0 }):Play()
            TweenService:Create(p.outer.rootStroke, TweenInfo.new(0.35), { Transparency = 1.0 }):Play()
            TweenService:Create(p.inner.rootStroke, TweenInfo.new(0.35), { Transparency = 1.0 }):Play()
        end
    end
end

-- ============================================================================
-- DYNAMIC BRIGHTNESS & LIGHTING ADAPTATION
-- Adjusts surface illumination for day/night match conditions
-- ============================================================================
local function updateLightingAdaptation()
    local clock = Lighting.ClockTime
    local isNight = (clock < 6 or clock > 18)
    local targetInfluence = isNight and 0.0 or 0.12
    
    for _, p in ipairs(ringPanels) do
        if p.outer and p.outer.gui then p.outer.gui.LightInfluence = targetInfluence end
        if p.inner and p.inner.gui then p.inner.gui.LightInfluence = targetInfluence end
    end
end

-- ============================================================================
-- 60 FPS RENDER STEP SIMULATION LOOP
-- Colossal anti-gravity float, yaw rotation, roll gyro tilt & marquee scroll
-- ============================================================================
local marqueeOffset = 0

local function onRenderStep(dt)
    local t = os.clock()
    
    -- 1. ArenaScreen Majestic Anti-Gravity Float (14 studs amplitude for 600x600 colosseum scale)
    if arenaScreen and arenaScreen.Parent then
        local screenYOffset = math.sin(t * ArenaRibbonConfig.ScreenHoverSpeed) * ArenaRibbonConfig.ScreenHoverAmp
        arenaScreen.CFrame = initialScreenCFrame + Vector3.new(0, screenYOffset, 0)
    end
    
    -- 2. ArenaGlobe Majestic Vertical Hover (10 studs amplitude)
    local globeYOffset = math.cos(t * ArenaRibbonConfig.GlobeHoverSpeed) * ArenaRibbonConfig.GlobeHoverAmp
    local currentGlobePos = initialGlobePosition + Vector3.new(0, globeYOffset, 0)
    if arenaGlobe and arenaGlobe.Parent then
        arenaGlobe.CFrame = CFrame.new(currentGlobePos)
    end
    
    -- 3. ArenaGlobeRing Kinematics (Yaw rotation + Gyroscopic Left-to-Right Roll tilt ±7.5°)
    yawAngle = yawAngle + (ArenaRibbonConfig.YawRotationSpeed * dt)
    local rollAngle = math.rad(ArenaRibbonConfig.RollOscillationAmp) * math.sin(t * ArenaRibbonConfig.RollOscillationSpeed)
    
    local ringCenterCFrame = CFrame.new(currentGlobePos) 
        * CFrame.Angles(0, yawAngle, 0) 
        * CFrame.Angles(0, 0, rollAngle)
    
    local radius = ArenaRibbonConfig.RingRadius
    local trimHalfHeight = (ArenaRibbonConfig.RingHeight * 0.5) + (ArenaRibbonConfig.TrimHeight * 0.5)
    local upVec = ringCenterCFrame.UpVector
    
    for _, p in ipairs(ringPanels) do
        if p.part and p.part.Parent then
            local panelAngle = p.relativeAngle
            local relX = math.cos(panelAngle) * radius
            local relZ = math.sin(panelAngle) * radius
            local localPos = Vector3.new(relX, 0, relZ)
            
            local worldPos = ringCenterCFrame:PointToWorldSpace(localPos)
            local lookDir = (worldPos - ringCenterCFrame.Position).Unit
            
            -- Orientation: Panel faces OUTWARD from globe center
            local panelCF = CFrame.lookAt(worldPos, worldPos + lookDir, upVec)
            p.part.CFrame = panelCF
            
            -- Position Neon Architectural Trims at Top and Bottom edges
            if p.topTrim and p.topTrim.Parent then
                p.topTrim.CFrame = panelCF * CFrame.new(0, trimHalfHeight, 0)
            end
            if p.bottomTrim and p.bottomTrim.Parent then
                p.bottomTrim.CFrame = panelCF * CFrame.new(0, -trimHalfHeight, 0)
            end
        end
    end
    
    -- 4. Marquee Horizontal Scrolling (Synchronized across all panels)
    marqueeOffset = (marqueeOffset - (ArenaRibbonConfig.MarqueeSpeed * dt)) % ArenaRibbonConfig.CanvasWidth
    for _, p in ipairs(ringPanels) do
        if p.outer and p.outer.marqueeLabel then
            p.outer.marqueeLabel.Position = UDim2.new(0, marqueeOffset, 0, 0)
        end
        if p.inner and p.inner.marqueeLabel then
            p.inner.marqueeLabel.Position = UDim2.new(0, marqueeOffset, 0, 0)
        end
    end
    
    -- 5. Sequential Ad Timer
    if isHologramsVisible then
        adTimer = adTimer + dt
        if adTimer >= ArenaRibbonConfig.AdRotationInterval then
            adTimer = 0
            rotateAds(false)
        end
    end
end

-- ============================================================================
-- STATE REPLICATION & ATTRIBUTE LISTENERS
-- ============================================================================
local ArenaNetwork = ReplicatedStorage:WaitForChild("ArenaNetwork", 15)
local StateReplication = ArenaNetwork and ArenaNetwork:WaitForChild("StateReplication", 15)

if StateReplication then
    StateReplication.OnClientEvent:Connect(function(snap)
        if not snap then return end
        
        if snap.Phase and snap.Phase ~= currentPhase then
            local oldPhase = currentPhase
            currentPhase = snap.Phase
            print(string.format("[ArenaHologramClient] Phase changed: %s -> %s", oldPhase, currentPhase))
            
            if currentPhase == "IDLE" then
                setHologramsVisible(false)
            end
            
            -- Synchronized perimeter ad change on phase switch
            rotateAds(true)
        end
    end)
end

-- Listen for authoritative Hologram activation attribute (set by orchestrator at T+5s of ARENA_OPEN)
Workspace:GetAttributeChangedSignal("ArenaHologramsActive"):Connect(function()
    local active = Workspace:GetAttribute("ArenaHologramsActive") == true
    setHologramsVisible(active)
end)

-- Initial check of hologram attribute
if Workspace:GetAttribute("ArenaHologramsActive") == true then
    setHologramsVisible(true)
end

-- ============================================================================
-- INITIALIZATION
-- ============================================================================
constructRibbonRing()
updateLightingAdaptation()
Lighting:GetPropertyChangedSignal("ClockTime"):Connect(updateLightingAdaptation)
RunService.RenderStepped:Connect(onRenderStep)

print("[ArenaHologramClientController] Initialized successfully. Double-Sided 360° Ribbon Ring & Hologram Controller Online.")
