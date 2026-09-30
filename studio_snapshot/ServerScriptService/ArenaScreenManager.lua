--// ArenaScreenManager.lua
-- Authoritative controller for double-sided stadium jumbotron (ArenaScreen) in ArenaOne

local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")

local ArenaScreen = {}

local screenPart = nil
local surfaceGuis = {}
local activeAnnouncementThread = nil

local function findScreen()
    local arenaOne = Workspace:FindFirstChild("argoniaonion") and Workspace.argoniaonion:FindFirstChild("ArenaOne")
    screenPart = arenaOne and arenaOne:FindFirstChild("ArenaScreen")
    surfaceGuis = {}
    if screenPart then
        for _, c in ipairs(screenPart:GetChildren()) do
            if c:IsA("SurfaceGui") then
                table.insert(surfaceGuis, c)
            end
        end
    end
    return screenPart
end

local function ensureGuiComponents(gui)
    local mf = gui:FindFirstChild("MainFrame")
    if not mf then return nil, nil, nil end
    
    local title = mf:FindFirstChild("Title")
    local sub = mf:FindFirstChild("SubTitle")
    if not sub then
        sub = Instance.new("TextLabel")
        sub.Name = "SubTitle"
        sub.Size = UDim2.new(1, -40, 0, 45)
        sub.Position = UDim2.new(0, 20, 0, 75)
        sub.BackgroundTransparency = 1
        sub.TextColor3 = Color3.fromRGB(0, 220, 255)
        sub.Font = Enum.Font.GothamBold
        sub.TextSize = 28
        sub.TextStrokeTransparency = 0.5
        sub.TextStrokeColor3 = Color3.new(0, 0, 0)
        sub.Parent = mf
    end
    
    local annFrame = mf:FindFirstChild("AnnouncementFrame")
    if not annFrame then
        annFrame = Instance.new("Frame")
        annFrame.Name = "AnnouncementFrame"
        annFrame.Size = UDim2.new(0.92, 0, 0.16, 0)
        annFrame.Position = UDim2.new(0.04, 0, 0.22, 0)
        annFrame.BackgroundColor3 = Color3.fromRGB(10, 14, 22)
        annFrame.BackgroundTransparency = 0.15
        annFrame.Visible = false
        annFrame.Parent = mf
        
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 8)
        corner.Parent = annFrame
        
        local stroke = Instance.new("UIStroke")
        stroke.Name = "FrameStroke"
        stroke.Color = Color3.fromRGB(0, 220, 255)
        stroke.Thickness = 2
        stroke.Parent = annFrame
        
        local tag = Instance.new("TextLabel")
        tag.Name = "Tag"
        tag.Size = UDim2.new(1, -20, 0, 22)
        tag.Position = UDim2.new(0, 12, 0, 6)
        tag.BackgroundTransparency = 1
        tag.Font = Enum.Font.GothamBlack
        tag.TextSize = 16
        tag.TextColor3 = Color3.fromRGB(0, 220, 255)
        tag.TextXAlignment = Enum.TextXAlignment.Left
        tag.Text = "🎙️ ARIA // STADIUM ANNOUNCER"
        tag.Parent = annFrame
        
        local body = Instance.new("TextLabel")
        body.Name = "Body"
        body.Size = UDim2.new(1, -24, 0, 56)
        body.Position = UDim2.new(0, 12, 0, 28)
        body.BackgroundTransparency = 1
        body.Font = Enum.Font.GothamBold
        body.TextSize = 22
        body.TextColor3 = Color3.fromRGB(245, 250, 255)
        body.TextXAlignment = Enum.TextXAlignment.Left
        body.TextWrapped = true
        body.Text = ""
        body.Parent = annFrame
    end
    
    return title, sub, annFrame
end

function ArenaScreen.init()
    findScreen()
    for _, gui in ipairs(surfaceGuis) do
        ensureGuiComponents(gui)
    end
    print(string.format("[ArenaScreenManager] Connected to ArenaScreen with %d SurfaceGuis.", #surfaceGuis))
end

function ArenaScreen.setEnabled(enabled)
    findScreen()
    for _, gui in ipairs(surfaceGuis) do
        gui.Enabled = enabled
    end
end

function ArenaScreen.setTitle(titleText, subtitleText)
    findScreen()
    for _, gui in ipairs(surfaceGuis) do
        local title, sub = ensureGuiComponents(gui)
        if title and title:IsA("TextLabel") then
            title.Text = titleText or "ARENA ONE"
        end
        if sub and sub:IsA("TextLabel") then
            sub.Text = subtitleText or ""
        end
    end
end

function ArenaScreen.displayAnnouncement(text, duration, speakerTag, color)
    duration = duration or 4.0
    speakerTag = speakerTag or "🎙️ ARIA // STADIUM ANNOUNCER"
    color = color or Color3.fromRGB(0, 220, 255)
    
    findScreen()
    for _, gui in ipairs(surfaceGuis) do
        local _, _, annFrame = ensureGuiComponents(gui)
        if annFrame then
            local tag = annFrame:FindFirstChild("Tag")
            local body = annFrame:FindFirstChild("Body")
            local stroke = annFrame:FindFirstChild("FrameStroke")
            
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
            
            annFrame.Visible = true
            annFrame.BackgroundTransparency = 0.15
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
        local annFrame = mf and mf:FindFirstChild("AnnouncementFrame")
        if annFrame then
            annFrame.Visible = false
        end
    end
end

function ArenaScreen.updateHealthBars(alphaHp, alphaMax, betaHp, betaMax, alphaAlive, betaAlive)
    findScreen()
    for _, gui in ipairs(surfaceGuis) do
        local mf = gui:FindFirstChild("MainFrame")
        if mf then
            local alphaContainer = mf:FindFirstChild("TeamAlpha")
            if alphaContainer then
                local fill = alphaContainer:FindFirstChild("Fill")
                local label = alphaContainer:FindFirstChild("Label")
                local ratio = alphaMax > 0 and math.clamp(alphaHp / alphaMax, 0, 1) or 0
                if fill then
                    TweenService:Create(fill, TweenInfo.new(0.2), { Size = UDim2.new(ratio, 0, 1, 0) }):Play()
                end
                if label and label:IsA("TextLabel") then
                    label.Text = string.format("ALPHA: %d/%d (Alive: %d)", math.floor(alphaHp), math.floor(alphaMax), alphaAlive or 0)
                end
            end
            
            local betaContainer = mf:FindFirstChild("TeamBeta")
            if betaContainer then
                local fill = betaContainer:FindFirstChild("Fill")
                local label = betaContainer:FindFirstChild("Label")
                local ratio = betaMax > 0 and math.clamp(betaHp / betaMax, 0, 1) or 0
                if fill then
                    TweenService:Create(fill, TweenInfo.new(0.2), { Size = UDim2.new(ratio, 0, 1, 0) }):Play()
                end
                if label and label:IsA("TextLabel") then
                    label.Text = string.format("BETA: %d/%d (Alive: %d)", math.floor(betaHp), math.floor(betaMax), betaAlive or 0)
                end
            end
        end
    end
end

function ArenaScreen.showWinner(winnerText, details)
    findScreen()
    ArenaScreen.setTitle("🏆 " .. tostring(winnerText):upper() .. " 🏆", details or "MATCH CONCLUDED")
    ArenaScreen.displayAnnouncement(string.format("CHAMPION OF ARENA ONE: %s", tostring(winnerText):upper()), 6.0, "🏆 VICTORY CEREMONY", Color3.fromRGB(255, 215, 0))
end

ArenaScreen.init()

return ArenaScreen
