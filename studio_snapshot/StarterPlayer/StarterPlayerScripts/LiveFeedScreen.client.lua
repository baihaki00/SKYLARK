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
    RingRadius = 80,             -- studs (the 120-stud globe's surface is at 60: a close band, Universal-globe style)
    RingTilt = 18,               -- degrees the ring leans off level (owner: Universal Studios globe look)
    -- "Coin dancing on a table": the lean's direction travels round the globe while the lean
    -- itself breathes between RingTiltMin and RingTiltMax (capped so the ticker stays readable)
    RingTiltMin = 6,
    RingTiltMax = 18,
    RingPrecessSpeed = 0.35,     -- radians per second the high side travels round
    RingTiltPulseSpeed = 0.45,   -- radians per second of the lean breathing in and out
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
    GlobeHoverAmp = 1.75,        -- studs either way: 3.5 studs of travel for ArenaGlobe (owner: 3-4 studs, slower)
    GlobeHoverSpeed = 0.3,
    ScreenHoverAmp = 1.75,       -- studs either way for ArenaScreen
    ScreenHoverSpeed = 0.34,

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
-- The globe and the screen are looked up lazily: with StreamingEnabled they are often not loaded
-- when this script starts, and a reference taken then stayed nil (the hover never moved them;
-- only the ring this script builds itself moved)
local arenaScreen = nil
local arenaGlobe = nil
local initialScreenCFrame = CFrame.new(-39, 235.34, -106)
local initialGlobePosition = ArenaRibbonConfig.GlobeCenter
local globeLight = nil

-- The globe starts invisible until the holograms are switched on
local function setupGlobe(globe)
    globe.Material = Enum.Material.ForceField
    globe.Color = ArenaRibbonConfig.ColorCyan
    globe.Transparency = Workspace:GetAttribute("ArenaHologramsActive") == true and 0.45 or 1.0
    globe.CanCollide = false
    globe.CastShadow = false

    globeLight = globe:FindFirstChild("HoloLight")
    if not globeLight then
        globeLight = Instance.new("PointLight")
        globeLight.Name = "HoloLight"
        globeLight.Color = ArenaRibbonConfig.ColorCyanGlow
        globeLight.Range = 220
        globeLight.Brightness = Workspace:GetAttribute("ArenaHologramsActive") == true and 2.0 or 0.0
        globeLight.Shadows = false
        globeLight.Parent = globe
    end
end

local function resolveHologramParts()
    if not (arenaOne and arenaOne.Parent) then
        local root = Workspace:FindFirstChild("argoniaonion")
        arenaOne = root and root:FindFirstChild("ArenaOne")
    end
    if not arenaOne then return end
    if not (arenaScreen and arenaScreen.Parent) then
        local screen = arenaOne:FindFirstChild("ArenaScreen")
        if screen then
            arenaScreen = screen
            initialScreenCFrame = screen.CFrame
        end
    end
    if not (arenaGlobe and arenaGlobe.Parent) then
        local globe = arenaOne:FindFirstChild("ArenaGlobe")
        if globe then
            arenaGlobe = globe
            initialGlobePosition = globe.Position
            setupGlobe(globe)
        end
    end
end
resolveHologramParts()

-- Glitch (hologram boot / shutdown): while active the globe and ring jitter sideways in steps
local glitchUntil = 0
local glitchOffset = Vector3.zero
local nextGlitchStep = 0

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
                -- glitch-on: two or three quick blinks before the panel holds
                for _ = 1, math.random(2, 3) do
                    p.band.Transparency = ArenaRibbonConfig.BandTransparency
                    task.wait(0.03 + math.random() * 0.04)
                    if token ~= ringToken then return end
                    p.band.Transparency = 0.85
                    task.wait(0.03 + math.random() * 0.05)
                    if token ~= ringToken then return end
                end
                local info = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
                TweenService:Create(p.band, info, { Transparency = ArenaRibbonConfig.BandTransparency }):Play()
                TweenService:Create(p.topTrim, info, { Transparency = ArenaRibbonConfig.TrimTransparency }):Play()
                TweenService:Create(p.bottomTrim, info, { Transparency = ArenaRibbonConfig.TrimTransparency }):Play()
                setRingTextTransparency(p, 0, 0.5)
            end)
        else
            -- glitch-off: a random blink, then out
            p.band.Transparency = (math.random() < 0.5) and 0.05 or 0.8
            local info = TweenInfo.new(0.25 + math.random() * 0.25)
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
        resolveHologramParts()
        if arenaGlobe then
            local globe = arenaGlobe
            globe.Material = Enum.Material.ForceField
            globe.Color = ArenaRibbonConfig.ColorCyan
            globe.Transparency = 0.95
            if globeLight then
                globeLight.Enabled = true
                globeLight.Brightness = 0.5
            end
            -- Holographic boot: stuttering flickers, colour tears and sideways jitter, then it settles
            glitchUntil = os.clock() + 0.9
            task.spawn(function()
                local steps = { 0.2, 0.9, 0.35, 0.8, 0.1, 0.7, 0.3, 0.95, 0.25, 0.6 }
                for k, transparency in ipairs(steps) do
                    if not isHologramsVisible then return end
                    globe.Transparency = transparency
                    globe.Color = (k % 3 == 0) and Color3.fromRGB(235, 250, 255)
                        or (k % 4 == 0) and Color3.fromRGB(150, 110, 255) or ArenaRibbonConfig.ColorCyan
                    if globeLight then globeLight.Brightness = (1 - transparency) * 4 end
                    task.wait(0.03 + math.random() * 0.06)
                end
                if not isHologramsVisible then return end
                globe.Color = ArenaRibbonConfig.ColorCyan
                TweenService:Create(globe, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Transparency = 0.45 }):Play()
                if globeLight then
                    TweenService:Create(globeLight, TweenInfo.new(0.35), { Brightness = 2.0 }):Play()
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
            -- Holographic shutdown: a burst of flickers and jitter, then it cuts out
            local globe = arenaGlobe
            glitchUntil = os.clock() + 0.5
            task.spawn(function()
                for _, transparency in ipairs({ 0.2, 0.85, 0.3, 0.95, 0.5, 1.0 }) do
                    if isHologramsVisible then return end
                    globe.Transparency = transparency
                    globe.Color = (math.random() < 0.3) and Color3.fromRGB(235, 250, 255) or ArenaRibbonConfig.ColorCyan
                    if globeLight then globeLight.Brightness = (1 - transparency) * 3 end
                    task.wait(0.04 + math.random() * 0.05)
                end
                globe.Color = ArenaRibbonConfig.ColorCyan
                globe.Transparency = 1.0
                if globeLight then globeLight.Brightness = 0 end
            end)
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

local lastResolve = 0
local function onRenderStep(dt)
    local t = os.clock()
    if t - lastResolve > 1 then
        lastResolve = t
        resolveHologramParts()
    end
    if t < glitchUntil then
        if t >= nextGlitchStep then
            nextGlitchStep = t + 0.03 + math.random() * 0.05
            glitchOffset = (math.random() < 0.6) and Vector3.new((math.random() - 0.5) * 3, (math.random() - 0.5) * 0.6, (math.random() - 0.5) * 3) or Vector3.zero
        end
    else
        glitchOffset = Vector3.zero
    end

    if arenaScreen and arenaScreen.Parent then
        local screenYOffset = math.sin(t * ArenaRibbonConfig.ScreenHoverSpeed) * ArenaRibbonConfig.ScreenHoverAmp
        arenaScreen.CFrame = initialScreenCFrame + Vector3.new(0, screenYOffset, 0)
    end

    local globeYOffset = math.cos(t * ArenaRibbonConfig.GlobeHoverSpeed) * ArenaRibbonConfig.GlobeHoverAmp
    local globePos = initialGlobePosition + Vector3.new(0, globeYOffset, 0) + glitchOffset
    if arenaGlobe and arenaGlobe.Parent then
        arenaGlobe.CFrame = CFrame.new(globePos)
    end

    if #ringPanels == 0 then return end
    yawAngle = (yawAngle + ArenaRibbonConfig.YawRotationSpeed * dt) % (math.pi * 2)
    tickerScroll = (tickerScroll + ArenaRibbonConfig.TickerSpeed * dt) % ringPixels

    -- the ring rides the globe's hover, tilted like the Universal globe's ring, turning slowly
    local tiltMin = ArenaRibbonConfig.RingTiltMin or ArenaRibbonConfig.RingTilt or 0
    local tiltMax = math.max(tiltMin, ArenaRibbonConfig.RingTiltMax or ArenaRibbonConfig.RingTilt or 0)
    local tiltDeg = tiltMin + (tiltMax - tiltMin) * (0.5 + 0.5 * math.sin(t * ArenaRibbonConfig.RingTiltPulseSpeed))
    local leanDir = t * ArenaRibbonConfig.RingPrecessSpeed
    local leanAxis = Vector3.new(math.cos(leanDir), 0, math.sin(leanDir))
    local center = CFrame.new(globePos) * CFrame.fromAxisAngle(leanAxis, math.rad(tiltDeg)) * CFrame.Angles(0, yawAngle, 0)
    local radius = ArenaRibbonConfig.RingRadius
    local trimOffset = ArenaRibbonConfig.RingHeight * 0.5 + ArenaRibbonConfig.TrimHeight * 0.5
    local count = #ringPanels

    for _, p in ipairs(ringPanels) do
        local localPos = Vector3.new(math.cos(p.angle) * radius, 0, math.sin(p.angle) * radius)
        local worldPos = center:PointToWorldSpace(localPos)
        local outward = (worldPos - center.Position).Unit
        local cf = CFrame.lookAt(worldPos, worldPos + outward, center.UpVector)
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
