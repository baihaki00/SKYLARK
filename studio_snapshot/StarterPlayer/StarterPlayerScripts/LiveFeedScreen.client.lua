--// ArenaHologramClientController.client.lua (LiveFeedScreen)
-- Client presentation of the ArenaOne holograms:
-- 1. ArenaGlobe: ForceField hologram that boots when the orchestrator sets ArenaHologramsActive
--    (T+5s of ARENA_OPEN), with a slow anti-gravity hover. ArenaScreen hovers too.
-- 2. Ribbon ring around the globe: one continuous stadium LED band. A single ticker message
--    scrolls around the whole ring (every panel shows its own slice of it, on both faces), so it
--    reads like one board rather than 32 copies of a squeezed advert. It sweeps on 1s after the
--    globe, and its message follows the match phase.

local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local TextService = game:GetService("TextService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- ============================================================================
-- CONFIGURATION
-- ============================================================================
local ArenaRibbonConfig = {
    GlobeCenter = Vector3.new(-0.5, 370, -411),

    -- Ring geometry
    RingRadius = 95,             -- studs (frames the 100-stud globe)
    RingHeight = 12,             -- studs of LED band
    PanelCount = 48,             -- polygon panels (more = rounder)
    PanelThickness = 0.6,
    TrimHeight = 0.5,            -- neon rails along the top and bottom edges
    PixelsPerStud = 14,          -- LED resolution (the canvas matches the panel: nothing is stretched;
                                 -- TextSize tops out at 100, so this sets how tall the text can be)

    -- Motion
    RingDelay = 1.0,             -- seconds after the globe before the ring comes up
    RingSweepTime = 0.8,         -- seconds for the light-up to travel round the ring
    YawRotationSpeed = 0.04,     -- radians per second of slow orbital turn
    TickerSpeed = 110,           -- pixels per second of ticker scroll
    GlobeHoverAmp = 10.0,        -- studs of vertical float for ArenaGlobe
    GlobeHoverSpeed = 0.48,
    ScreenHoverAmp = 14.0,       -- studs of vertical float for ArenaScreen
    ScreenHoverSpeed = 0.58,

    -- Look
    TextSizeRatio = 0.62,        -- ticker text height as a share of the band
    Font = Enum.Font.GothamBlack,
    Separator = "      •      ", -- (GothamBlack has no ✦: it drew as an empty box)
    ColorBand = Color3.fromRGB(6, 12, 22),
    ColorText = Color3.fromRGB(245, 236, 205),
    ColorCyan = Color3.fromRGB(0, 210, 255),
    ColorCyanGlow = Color3.fromRGB(80, 230, 255),
    ColorGold = Color3.fromRGB(212, 175, 55),
    BandTransparency = 0.08,
    TrimTransparency = 0.1,

    -- Ticker messages per match phase
    Messages = {
        DEFAULT = { "ARGONIA ARENA ONE", "ARGONIA GUILD SYNDICATE", "SKYLARK EXPEDITIONS", "AETHERIUM FORGEWORKS" },
        ARENA_OPEN = { "WELCOME TO ARENA ONE", "GATES ARE OPEN", "ARGONIA CHAMPIONSHIP" },
        ARENA_GENERATION = { "ARENA GENERATION", "SECTOR ARCHITECTURE FORMING", "HAZARD GRIDS ALIGNED" },
        PREPARATION_ROOM = { "PREPARATION ROOM", "FIGHTERS CALIBRATING", "TACTICAL BRIEFING" },
        TELEPORTING_QUINS = { "DEPLOYMENT", "QUINS ENTERING THE ARENA", "SECTOR ALPHA • SECTOR BETA" },
        STADIUM_ANTHEM = { "ALL RISE FOR THE ARENA ONE ANTHEM", "THE SKYLARK LEGACY" },
        PRE_GAME = { "ENGAGEMENT IMMINENT", "STAND BY FOR BATTLE" },
        IN_GAME = { "COMBAT IN PROGRESS", "SECTOR ALPHA VS SECTOR BETA", "CLASH OF THE QUINS" },
        WINNER_DETERMINATION = { "VICTORY", "ALL HAIL THE CHAMPIONS OF ARENA ONE" },
        POST_GAME = { "THANK YOU FOR ATTENDING", "ARENA ONE IS CLOSING", "SAFE TRAVELS" },
    },
}

-- ============================================================================
-- REFERENCES
-- ============================================================================
local arenaOne = Workspace:WaitForChild("argoniaonion", 15) and Workspace.argoniaonion:WaitForChild("ArenaOne", 15)
local arenaScreen = arenaOne and arenaOne:FindFirstChild("ArenaScreen")
local arenaGlobe = arenaOne and arenaOne:FindFirstChild("ArenaGlobe")

local initialScreenCFrame = arenaScreen and arenaScreen.CFrame or CFrame.new(-39, 235.34, -106)
local initialGlobePosition = arenaGlobe and arenaGlobe.Position or ArenaRibbonConfig.GlobeCenter

-- The globe starts invisible until the holograms are switched on
local globeLight = nil
if arenaGlobe then
    arenaGlobe.Material = Enum.Material.ForceField
    arenaGlobe.Color = ArenaRibbonConfig.ColorCyan
    arenaGlobe.Transparency = 1.0
    arenaGlobe.CanCollide = false
    arenaGlobe.CastShadow = false

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
local panelPixels = 0          -- width of one panel in ticker pixels
local ringPixels = 0           -- the whole ring in ticker pixels
local tickerLoop = 1           -- pixels between repeats of the message (divides the ring exactly)
local tickerScroll = 0
local textSize = 100

local isHologramsVisible = false
local ringToken = 0            -- cancels a pending ring light-up when the holograms go off
local currentPhase = "IDLE"
local yawAngle = 0

-- ============================================================================
-- RIBBON RING
-- ============================================================================
local function messageFor(phase)
    local list = ArenaRibbonConfig.Messages[phase] or ArenaRibbonConfig.Messages.DEFAULT
    return table.concat(list, ArenaRibbonConfig.Separator) .. ArenaRibbonConfig.Separator
end

-- One face: a clipping window holding enough copies of the ticker to cover it while scrolling
local function createFace(part, face, copies)
    local gui = Instance.new("SurfaceGui")
    gui.Name = "Ticker_" .. face.Name
    gui.Face = face
    gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
    gui.PixelsPerStud = ArenaRibbonConfig.PixelsPerStud
    gui.LightInfluence = 0
    gui.Brightness = 1.4
    gui.ClipsDescendants = true
    gui.Adornee = part
    gui.Parent = part

    local labels = {}
    for c = 1, copies do
        local label = Instance.new("TextLabel")
        label.Name = "Ticker" .. c
        label.BackgroundTransparency = 1
        label.AnchorPoint = Vector2.new(0, 0.5)
        label.Position = UDim2.new(0, 0, 0.5, 0)
        label.Size = UDim2.new(0, tickerLoop, 0, textSize * 1.2)
        label.Font = ArenaRibbonConfig.Font
        label.TextSize = textSize
        label.TextColor3 = ArenaRibbonConfig.ColorText
        label.TextXAlignment = Enum.TextXAlignment.Left
        label.TextTransparency = 1
        label.Text = ""
        label.Parent = gui
        table.insert(labels, label)
    end
    return { gui = gui, labels = labels }
end

local function measure(text, size)
    return TextService:GetTextSize(text, size, ArenaRibbonConfig.Font, Vector2.new(1e6, size * 2)).X
end

local function setTickerText(text)
    -- The message repeats a whole number of times round the ring and its size is fitted so the
    -- repeats join up (with a fixed size the last repeat left up to a message-length gap)
    local baseSize = math.min(100, math.floor(ArenaRibbonConfig.RingHeight * ArenaRibbonConfig.PixelsPerStud * ArenaRibbonConfig.TextSizeRatio))
    local width = math.max(measure(text, baseSize), 1)
    local repeats = math.max(1, math.ceil(ringPixels / width))
    if ringPixels / repeats / width < 0.75 then
        repeats = math.max(1, repeats - 1) -- shrinking that far reads worse than a small gap
    end
    tickerLoop = ringPixels / repeats
    textSize = math.min(baseSize, math.floor(baseSize * tickerLoop / width))
    while textSize > 20 and measure(text, textSize) > tickerLoop do
        textSize -= 1
    end
    for _, p in ipairs(ringPanels) do
        for _, face in ipairs({ p.outer, p.inner }) do
            for _, label in ipairs(face.labels) do
                label.Text = text
                label.TextSize = textSize
                label.Size = UDim2.new(0, tickerLoop, 0, textSize * 1.2)
            end
        end
    end
end

local function constructRibbonRing()
    if ringModel then
        ringModel:Destroy()
    end
    ringPanels = {}

    ringModel = Instance.new("Model")
    ringModel.Name = "ArenaGlobeRibbonRing_Client"
    ringModel.Parent = Workspace

    local count = ArenaRibbonConfig.PanelCount
    local radius = ArenaRibbonConfig.RingRadius
    local height = ArenaRibbonConfig.RingHeight
    local angleStep = (math.pi * 2) / count
    local chord = 2 * radius * math.sin(angleStep * 0.5)

    panelPixels = chord * ArenaRibbonConfig.PixelsPerStud
    ringPixels = panelPixels * count
    textSize = math.floor(height * ArenaRibbonConfig.PixelsPerStud * ArenaRibbonConfig.TextSizeRatio)
    tickerLoop = ringPixels

    local function makePart(name, size, material, color)
        local part = Instance.new("Part")
        part.Name = name
        part.Size = size
        part.Material = material
        part.Color = color
        part.Transparency = 1
        part.Anchored = true
        part.CanCollide = false
        part.CanTouch = false
        part.CanQuery = false
        part.CastShadow = false
        part.Parent = ringModel
        return part
    end

    for i = 1, count do
        -- (a hair wider than the chord so neighbouring panels meet without a seam)
        local band = makePart(string.format("Band_%02d", i), Vector3.new(chord + 0.06, height, ArenaRibbonConfig.PanelThickness),
            Enum.Material.SmoothPlastic, ArenaRibbonConfig.ColorBand)
        local trimSize = Vector3.new(chord + 0.06, ArenaRibbonConfig.TrimHeight, ArenaRibbonConfig.PanelThickness * 1.2)
        local topTrim = makePart("TopTrim", trimSize, Enum.Material.Neon, ArenaRibbonConfig.ColorCyan)
        local bottomTrim = makePart("BottomTrim", trimSize, Enum.Material.Neon, ArenaRibbonConfig.ColorGold)

        -- Copies needed to always cover a panel while the ticker scrolls
        local copies = math.max(2, math.ceil(panelPixels / 200) + 2)
        table.insert(ringPanels, {
            index = i,
            angle = (i - 1) * angleStep,
            band = band,
            topTrim = topTrim,
            bottomTrim = bottomTrim,
            outer = createFace(band, Enum.NormalId.Front, copies), -- toward the stands
            inner = createFace(band, Enum.NormalId.Back, copies),  -- toward the arena floor
        })
    end
    setTickerText(messageFor(currentPhase))
end

local function setRingTextTransparency(p, value, time)
    for _, face in ipairs({ p.outer, p.inner }) do
        for _, label in ipairs(face.labels) do
            if time and time > 0 then
                TweenService:Create(label, TweenInfo.new(time), { TextTransparency = value }):Play()
            else
                label.TextTransparency = value
            end
        end
    end
end

local function showRing(visible)
    ringToken += 1
    local token = ringToken
    local count = #ringPanels
    for _, p in ipairs(ringPanels) do
        if visible then
            -- light-up sweep round the ring
            task.delay(((p.index - 1) / count) * ArenaRibbonConfig.RingSweepTime, function()
                if token ~= ringToken then return end
                local info = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
                TweenService:Create(p.band, info, { Transparency = ArenaRibbonConfig.BandTransparency }):Play()
                TweenService:Create(p.topTrim, info, { Transparency = ArenaRibbonConfig.TrimTransparency }):Play()
                TweenService:Create(p.bottomTrim, info, { Transparency = ArenaRibbonConfig.TrimTransparency }):Play()
                setRingTextTransparency(p, 0, 0.5)
            end)
        else
            local info = TweenInfo.new(0.4)
            TweenService:Create(p.band, info, { Transparency = 1 }):Play()
            TweenService:Create(p.topTrim, info, { Transparency = 1 }):Play()
            TweenService:Create(p.bottomTrim, info, { Transparency = 1 }):Play()
            setRingTextTransparency(p, 1, 0.4)
        end
    end
end

-- New phase: the ticker fades out, takes the phase's message and fades back in
local function changeTicker(phase)
    local text = messageFor(phase)
    if not isHologramsVisible then
        setTickerText(text)
        return
    end
    for _, p in ipairs(ringPanels) do
        setRingTextTransparency(p, 1, 0.3)
    end
    local token = ringToken
    task.delay(0.32, function()
        if token ~= ringToken then return end
        setTickerText(text)
        for _, p in ipairs(ringPanels) do
            setRingTextTransparency(p, 0, 0.4)
        end
    end)
end

-- ============================================================================
-- HOLOGRAM BOOT: globe now, ring RingDelay later
-- ============================================================================
local function setHologramsVisible(visible)
    if isHologramsVisible == visible then return end
    isHologramsVisible = visible

    if visible then
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
                TweenService:Create(arenaGlobe, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Transparency = 0.45 }):Play()
                if globeLight then
                    TweenService:Create(globeLight, TweenInfo.new(0.4), { Brightness = 2.0 }):Play()
                end
            end)
        end
        ringToken += 1
        local token = ringToken
        task.delay(ArenaRibbonConfig.RingDelay, function()
            if token == ringToken and isHologramsVisible then
                showRing(true)
            end
        end)
    else
        if arenaGlobe then
            TweenService:Create(arenaGlobe, TweenInfo.new(0.4), { Transparency = 1.0 }):Play()
            if globeLight then
                TweenService:Create(globeLight, TweenInfo.new(0.4), { Brightness = 0.0 }):Play()
            end
        end
        showRing(false)
    end
end

-- ============================================================================
-- LIGHTING
-- ============================================================================
local function updateLightingAdaptation()
    local clock = Lighting.ClockTime
    local isNight = (clock < 6 or clock > 18)
    for _, p in ipairs(ringPanels) do
        p.outer.gui.Brightness = isNight and 1.0 or 1.4
        p.inner.gui.Brightness = isNight and 1.0 or 1.4
    end
end

-- ============================================================================
-- PER-FRAME: hover, ring placement, ticker scroll
-- ============================================================================
local function placeTicker(face, stripStart)
    -- stripStart: where this panel's left edge sits along the ring's ticker strip
    local offset = (stripStart + tickerScroll) % tickerLoop
    for c, label in ipairs(face.labels) do
        label.Position = UDim2.new(0, -offset + (c - 1) * tickerLoop, 0.5, 0)
    end
end

local function onRenderStep(dt)
    local t = os.clock()

    if arenaScreen and arenaScreen.Parent then
        local screenYOffset = math.sin(t * ArenaRibbonConfig.ScreenHoverSpeed) * ArenaRibbonConfig.ScreenHoverAmp
        arenaScreen.CFrame = initialScreenCFrame + Vector3.new(0, screenYOffset, 0)
    end

    local globeYOffset = math.cos(t * ArenaRibbonConfig.GlobeHoverSpeed) * ArenaRibbonConfig.GlobeHoverAmp
    local globePos = initialGlobePosition + Vector3.new(0, globeYOffset, 0)
    if arenaGlobe and arenaGlobe.Parent then
        arenaGlobe.CFrame = CFrame.new(globePos)
    end

    if #ringPanels == 0 then return end
    yawAngle = (yawAngle + ArenaRibbonConfig.YawRotationSpeed * dt) % (math.pi * 2)
    tickerScroll = (tickerScroll + ArenaRibbonConfig.TickerSpeed * dt) % ringPixels

    local center = CFrame.new(globePos) * CFrame.Angles(0, yawAngle, 0)
    local radius = ArenaRibbonConfig.RingRadius
    local trimOffset = ArenaRibbonConfig.RingHeight * 0.5 + ArenaRibbonConfig.TrimHeight * 0.5
    local count = #ringPanels

    for _, p in ipairs(ringPanels) do
        local localPos = Vector3.new(math.cos(p.angle) * radius, 0, math.sin(p.angle) * radius)
        local worldPos = center:PointToWorldSpace(localPos)
        local outward = (worldPos - center.Position).Unit
        local cf = CFrame.lookAt(worldPos, worldPos + outward, Vector3.yAxis)
        p.band.CFrame = cf
        p.topTrim.CFrame = cf * CFrame.new(0, trimOffset, 0)
        p.bottomTrim.CFrame = cf * CFrame.new(0, -trimOffset, 0)

        if isHologramsVisible then
            -- Seen from outside, the next panel round is to the viewer's left; from inside, to
            -- the right. Each face takes its slice so the message reads on continuously.
            placeTicker(p.outer, (count - p.index) * panelPixels)
            placeTicker(p.inner, (p.index - 1) * panelPixels)
        end
    end
end

-- ============================================================================
-- STATE
-- ============================================================================
local ArenaNetwork = ReplicatedStorage:WaitForChild("ArenaNetwork", 15)
local StateReplication = ArenaNetwork and ArenaNetwork:WaitForChild("StateReplication", 15)

constructRibbonRing()
updateLightingAdaptation()
Lighting:GetPropertyChangedSignal("ClockTime"):Connect(updateLightingAdaptation)

if StateReplication then
    StateReplication.OnClientEvent:Connect(function(snap)
        if not snap or not snap.Phase or snap.Phase == currentPhase then return end
        currentPhase = snap.Phase
        if currentPhase == "IDLE" then
            setHologramsVisible(false)
        end
        changeTicker(currentPhase)
    end)
end

Workspace:GetAttributeChangedSignal("ArenaHologramsActive"):Connect(function()
    setHologramsVisible(Workspace:GetAttribute("ArenaHologramsActive") == true)
end)
if Workspace:GetAttribute("ArenaHologramsActive") == true then
    setHologramsVisible(true)
end

RunService.RenderStepped:Connect(onRenderStep)

print("[ArenaHologramClient] Ribbon ring ready (continuous ticker, ring follows the globe by 1s).")
