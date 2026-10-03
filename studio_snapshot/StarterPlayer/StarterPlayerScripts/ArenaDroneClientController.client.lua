--// ArenaDroneClientController.client.lua
-- Client-side camera controller & UI selector for live Arena Drones

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local QuinCore = ReplicatedStorage:WaitForChild("QuinCore")
local DroneTrajectories = require(QuinCore:WaitForChild("ArenaDroneTrajectories"))

local ArenaNetwork = ReplicatedStorage:WaitForChild("ArenaNetwork")
local DroneEvent = ArenaNetwork:WaitForChild("DroneEvent")

-- State
local activeDrone = nil -- nil (Freefly), "Cinematic", "ArenaFootage", "LiveAerial"
local flightStartTime = 0
local isFlying = false
local currentSpeed = 0
local lastPos = nil
local lastTime = os.clock()

local DRONE_ORDER = { "Cinematic", "ArenaFootage", "LiveAerial", "CombatChase", "SkylineOrbit" }
local DRONE_INFO = {
    Cinematic = {
        Index = 1,
        Name = "CAM 1: ARENA CINEMATIC",
        ShortName = "1: Cinematic",
        Color = Color3.fromRGB(0, 255, 120),
        Desc = "360 Stadium Sweep & Combat Traversal"
    },
    ArenaFootage = {
        Index = 2,
        Name = "CAM 2: ARENA BROADCAST",
        ShortName = "2: Broadcast",
        Color = Color3.fromRGB(255, 60, 60),
        Desc = "Agile FPV Flight & Banking Turns"
    },
    LiveAerial = {
        Index = 3,
        Name = "CAM 3: AERIAL 360",
        ShortName = "3: Aerial 360",
        Color = Color3.fromRGB(0, 200, 255),
        Desc = "Top-Angle Full Arena Observation"
    },
    CombatChase = {
        Index = 4,
        Name = "CAM 4: COMBAT CHASE",
        ShortName = "4: Combat Chase",
        Color = Color3.fromRGB(255, 170, 0),
        Desc = "Close Quin Combat Chasing Camera"
    },
    SkylineOrbit = {
        Index = 5,
        Name = "CAM 5: SKYLINE ORBIT",
        ShortName = "5: Skyline Orbit",
        Color = Color3.fromRGB(220, 80, 255),
        Desc = "High-Altitude Perimeter Orbital Cam"
    },
}

local isOutro = false
local outroStartTime = 0

-- Remote Synchronization
DroneEvent.OnClientEvent:Connect(function(action, data)
    if action == "Launch" then
        isFlying = true
        isOutro = false
        flightStartTime = data and data.StartTime or os.clock()
        print("[ArenaDroneClient] Drones launched into flight at countdown T-4.")
    elseif action == "Outro" then
        isOutro = true
        outroStartTime = data and data.OutroStartTime or os.clock()
        print("[ArenaDroneClient] Drones initiating jet outro climb sequence.")
    elseif action == "Reset" then
        isFlying = false
        isOutro = false
        flightStartTime = 0
        outroStartTime = 0
        print("[ArenaDroneClient] Drones reset to standby 600 studs above ArenaGround.")
    end
end)

-- UI Construction
local playerGui = player:WaitForChild("PlayerGui")
local droneScreenGui = Instance.new("ScreenGui")
droneScreenGui.Name = "ArenaDroneUI"
droneScreenGui.ResetOnSpawn = false
droneScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
droneScreenGui.Parent = playerGui

local function applyCorner(inst, radius)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, radius)
    c.Parent = inst
    return c
end

local function applyStroke(inst, color, thickness)
    local s = Instance.new("UIStroke")
    s.Color = color or Color3.fromRGB(38, 48, 68)
    s.Thickness = thickness or 1
    s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    s.Parent = inst
    return s
end

-- ============================================================================
-- 1. FLOATING DOCKED PILL (DOCKED ABOVE ARENA SYSTEM AT Y = -202)
-- ============================================================================
local dronePill = Instance.new("TextButton")
dronePill.Name = "DroneTogglePill"
dronePill.Size = UDim2.new(0, 180, 0, 36)
dronePill.AnchorPoint = Vector2.new(1, 1)
dronePill.Position = UDim2.new(1, -20, 1, -202)
dronePill.BackgroundColor3 = Color3.fromRGB(18, 22, 30)
dronePill.BackgroundTransparency = 0.15
dronePill.TextColor3 = Color3.fromRGB(240, 245, 255)
dronePill.Font = Enum.Font.GothamBold
dronePill.TextSize = 12
dronePill.Text = "🚁 Drone Cameras [V]"
dronePill.Parent = droneScreenGui
applyCorner(dronePill, 18)
local pillStroke = applyStroke(dronePill, Color3.fromRGB(0, 220, 255), 1.5)
pillStroke.Transparency = 0.35

-- Quick Selector Flyout Menu
local flyoutMenu = Instance.new("Frame")
flyoutMenu.Name = "DroneFlyoutMenu"
flyoutMenu.Size = UDim2.new(0, 220, 0, 230)
flyoutMenu.AnchorPoint = Vector2.new(1, 1)
flyoutMenu.Position = UDim2.new(1, -20, 1, -245)
flyoutMenu.BackgroundColor3 = Color3.fromRGB(15, 18, 26)
flyoutMenu.BackgroundTransparency = 0.08
flyoutMenu.Visible = false
flyoutMenu.Parent = droneScreenGui
applyCorner(flyoutMenu, 12)
applyStroke(flyoutMenu, Color3.fromRGB(0, 220, 255), 1.5)

local flyoutLayout = Instance.new("UIListLayout")
flyoutLayout.Padding = UDim.new(0, 5)
flyoutLayout.Parent = flyoutMenu

local flyoutPad = Instance.new("UIPadding")
flyoutPad.PaddingTop = UDim.new(0, 8)
flyoutPad.PaddingBottom = UDim.new(0, 8)
flyoutPad.PaddingLeft = UDim.new(0, 10)
flyoutPad.PaddingRight = UDim.new(0, 10)
flyoutPad.Parent = flyoutMenu

local optionButtons = {}

-- The drone being watched through hides its own trail, body, light and tag for this viewer:
-- its trail streamed across its own view
local DRONE_MODEL_NAMES = {
    Cinematic = "ArenaDroneCinematic", ArenaFootage = "ArenaDroneArenaFootage", LiveAerial = "ArenaDroneLiveAerialFootage",
    CombatChase = "ArenaDroneCombatChase", SkylineOrbit = "ArenaDroneSkylineOrbit",
}
local hiddenDrone = nil -- { model, saved = { [instance] = value } }
local function showOwnDrone()
    if not hiddenDrone then return end
    for inst, value in pairs(hiddenDrone.saved) do
        if inst.Parent then
            if inst:IsA("BasePart") then inst.LocalTransparencyModifier = value
            else inst.Enabled = value end
        end
    end
    hiddenDrone = nil
end
local function hideOwnDrone(droneKey)
    showOwnDrone()
    local root = workspace:FindFirstChild("argoniaonion")
    local arenaOne = root and root:FindFirstChild("ArenaOne")
    local model = droneKey and arenaOne and arenaOne:FindFirstChild(DRONE_MODEL_NAMES[droneKey] or "")
    if not model then return end
    hiddenDrone = { model = model, saved = {} }
    for _, d in ipairs(model:GetDescendants()) do
        if d:IsA("BasePart") then
            hiddenDrone.saved[d] = d.LocalTransparencyModifier
            d.LocalTransparencyModifier = 1
        elseif d:IsA("Trail") or d:IsA("Light") or d:IsA("BillboardGui") then
            hiddenDrone.saved[d] = d.Enabled
            d.Enabled = false
        end
    end
end

local function setDroneMode(droneKey)
    activeDrone = droneKey
    hideOwnDrone(activeDrone)
    if workspace:GetAttribute("SelectedDrone") ~= (activeDrone or "") then
        workspace:SetAttribute("SelectedDrone", activeDrone or "")
    end
    
    if activeDrone then
        local info = DRONE_INFO[activeDrone]
        dronePill.Text = string.format("🚁 %s [V]", info.ShortName)
        dronePill.TextColor3 = info.Color
        pillStroke.Color = info.Color
    else
        dronePill.Text = "🚁 Drone Cameras [V]"
        dronePill.TextColor3 = Color3.fromRGB(240, 245, 255)
        pillStroke.Color = Color3.fromRGB(0, 220, 255)
        shared.CameraOverrideCFrame = nil
    end
    
    -- Update flyout highlight
    for key, btn in pairs(optionButtons) do
        local isSel = (activeDrone == key) or (not activeDrone and key == "Off")
        btn.BackgroundColor3 = isSel and Color3.fromRGB(30, 42, 60) or Color3.fromRGB(20, 25, 35)
    end
end

local function createFlyoutOption(key, label, color)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, 0, 0, 30)
    btn.BackgroundColor3 = (not activeDrone and key == "Off") and Color3.fromRGB(30, 42, 60) or Color3.fromRGB(20, 25, 35)
    btn.Text = ""
    btn.Parent = flyoutMenu
    applyCorner(btn, 6)
    local s = applyStroke(btn, color or Color3.fromRGB(45, 55, 75), 1)
    
    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1, -10, 1, 0)
    lbl.Position = UDim2.new(0, 8, 0, 0)
    lbl.BackgroundTransparency = 1
    lbl.Font = Enum.Font.GothamBold
    lbl.TextSize = 11
    lbl.TextColor3 = color or Color3.fromRGB(220, 230, 245)
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Text = label
    lbl.Parent = btn
    
    btn.MouseButton1Click:Connect(function()
        if key == "Off" then
            setDroneMode(nil)
        else
            setDroneMode(key)
        end
        flyoutMenu.Visible = false
    end)
    
    optionButtons[key] = btn
end

createFlyoutOption("Cinematic", "🚁 1: Cinematic Drone", Color3.fromRGB(0, 255, 120))
createFlyoutOption("ArenaFootage", "📹 2: Broadcast Drone", Color3.fromRGB(255, 80, 80))
createFlyoutOption("LiveAerial", "🛰️ 3: Aerial 360 Drone", Color3.fromRGB(0, 200, 255))
createFlyoutOption("CombatChase", "⚡ 4: Combat Chase Drone", Color3.fromRGB(255, 170, 0))
createFlyoutOption("SkylineOrbit", "🌌 5: Skyline Orbit Drone", Color3.fromRGB(220, 80, 255))
createFlyoutOption("Off", "🎥 Freefly Spectator [R]", Color3.fromRGB(150, 170, 200))

dronePill.MouseButton1Click:Connect(function()
    flyoutMenu.Visible = not flyoutMenu.Visible
end)

-- ============================================================================
-- 2. LIVE BROADCAST TELEMETRY OVERLAY HUD
-- ============================================================================
local telemetryHUD = Instance.new("Frame")
telemetryHUD.Name = "TelemetryHUD"
telemetryHUD.Size = UDim2.new(1, 0, 1, 0)
telemetryHUD.BackgroundTransparency = 1
telemetryHUD.Visible = false
telemetryHUD.Parent = droneScreenGui

-- Top Bar
local topBar = Instance.new("Frame")
topBar.Size = UDim2.new(0, 420, 0, 36)
topBar.Position = UDim2.new(0, 25, 0, 20)
topBar.BackgroundColor3 = Color3.fromRGB(12, 15, 22)
topBar.BackgroundTransparency = 0.2
topBar.Parent = telemetryHUD
applyCorner(topBar, 8)
local topStroke = applyStroke(topBar, Color3.fromRGB(0, 255, 120), 1.5)

local recDot = Instance.new("Frame")
recDot.Size = UDim2.new(0, 10, 0, 10)
recDot.Position = UDim2.new(0, 14, 0.5, -5)
recDot.BackgroundColor3 = Color3.fromRGB(255, 40, 40)
recDot.Parent = topBar
applyCorner(recDot, 5)

local recLbl = Instance.new("TextLabel")
recLbl.Size = UDim2.new(0, 40, 1, 0)
recLbl.Position = UDim2.new(0, 30, 0, 0)
recLbl.BackgroundTransparency = 1
recLbl.Font = Enum.Font.GothamBlack
recLbl.TextSize = 11
recLbl.TextColor3 = Color3.fromRGB(255, 80, 80)
recLbl.TextXAlignment = Enum.TextXAlignment.Left
recLbl.Text = "REC"
recLbl.Parent = topBar

local camNameLbl = Instance.new("TextLabel")
camNameLbl.Size = UDim2.new(1, -180, 1, 0)
camNameLbl.Position = UDim2.new(0, 75, 0, 0)
camNameLbl.BackgroundTransparency = 1
camNameLbl.Font = Enum.Font.GothamBold
camNameLbl.TextSize = 11
camNameLbl.TextColor3 = Color3.fromRGB(240, 245, 255)
camNameLbl.TextXAlignment = Enum.TextXAlignment.Left
camNameLbl.Text = "CAM 1: ARENA CINEMATIC"
camNameLbl.Parent = topBar

local exitBtn = Instance.new("TextButton")
exitBtn.Size = UDim2.new(0, 85, 0, 24)
exitBtn.Position = UDim2.new(1, -95, 0.5, -12)
exitBtn.BackgroundColor3 = Color3.fromRGB(30, 35, 48)
exitBtn.TextColor3 = Color3.fromRGB(200, 215, 235)
exitBtn.Font = Enum.Font.GothamBold
exitBtn.TextSize = 10
exitBtn.Text = "✕ Freefly [R]"
exitBtn.Parent = topBar
applyCorner(exitBtn, 4)

exitBtn.MouseButton1Click:Connect(function()
    setDroneMode(nil)
end)

-- Bottom Telemetry Card
local botCard = Instance.new("Frame")
botCard.Size = UDim2.new(0, 300, 0, 40)
botCard.Position = UDim2.new(0, 25, 1, -65)
botCard.BackgroundColor3 = Color3.fromRGB(12, 15, 22)
botCard.BackgroundTransparency = 0.25
botCard.Parent = telemetryHUD
applyCorner(botCard, 8)
applyStroke(botCard, Color3.fromRGB(45, 55, 75), 1)

local altLbl = Instance.new("TextLabel")
altLbl.Size = UDim2.new(0.33, 0, 1, 0)
altLbl.Position = UDim2.new(0, 10, 0, 0)
altLbl.BackgroundTransparency = 1
altLbl.Font = Enum.Font.GothamBold
altLbl.TextSize = 11
altLbl.TextColor3 = Color3.fromRGB(0, 220, 255)
altLbl.TextXAlignment = Enum.TextXAlignment.Left
altLbl.Text = "ALT: 400m"
altLbl.Parent = botCard

local spdLbl = Instance.new("TextLabel")
spdLbl.Size = UDim2.new(0.33, 0, 1, 0)
spdLbl.Position = UDim2.new(0.35, 0, 0, 0)
spdLbl.BackgroundTransparency = 1
spdLbl.Font = Enum.Font.GothamBold
spdLbl.TextSize = 11
spdLbl.TextColor3 = Color3.fromRGB(255, 180, 50)
spdLbl.TextXAlignment = Enum.TextXAlignment.Left
spdLbl.Text = "SPD: 0 km/h"
spdLbl.Parent = botCard

local fovLbl = Instance.new("TextLabel")
fovLbl.Size = UDim2.new(0.33, 0, 1, 0)
fovLbl.Position = UDim2.new(0.70, 0, 0, 0)
fovLbl.BackgroundTransparency = 1
fovLbl.Font = Enum.Font.GothamBold
fovLbl.TextSize = 11
fovLbl.TextColor3 = Color3.fromRGB(200, 215, 235)
fovLbl.TextXAlignment = Enum.TextXAlignment.Left
fovLbl.Text = "STAB: 100%"
fovLbl.Parent = botCard

-- Blinking REC dot animation
task.spawn(function()
    while true do
        recDot.BackgroundTransparency = 0
        task.wait(0.65)
        recDot.BackgroundTransparency = 0.8
        task.wait(0.65)
    end
end)

-- ============================================================================
-- 3. HOTKEYS ([V] Cycle, [1], [2], [3] Direct, [R] Exit)
-- ============================================================================
local function cycleDrone()
    if not activeDrone then
        setDroneMode(DRONE_ORDER[1])
    else
        local curIdx = table.find(DRONE_ORDER, activeDrone) or 1
        if curIdx >= #DRONE_ORDER then
            setDroneMode(nil) -- Cycle back to freefly
        else
            setDroneMode(DRONE_ORDER[curIdx + 1])
        end
    end
end

UserInputService.InputBegan:Connect(function(input, gp)
    if gp or UserInputService:GetFocusedTextBox() then return end
    
    -- Only active if player is NOT possessing a Quin
    if shared.PlayerControlledQuin then return end
    
    if input.KeyCode == Enum.KeyCode.V then
        cycleDrone()
    elseif input.KeyCode == Enum.KeyCode.One then
        setDroneMode("Cinematic")
    elseif input.KeyCode == Enum.KeyCode.Two then
        setDroneMode("ArenaFootage")
    elseif input.KeyCode == Enum.KeyCode.Three then
        setDroneMode("LiveAerial")
    elseif input.KeyCode == Enum.KeyCode.Four then
        setDroneMode("CombatChase")
    elseif input.KeyCode == Enum.KeyCode.Five then
        setDroneMode("SkylineOrbit")
    elseif input.KeyCode == Enum.KeyCode.R and activeDrone ~= nil then
        setDroneMode(nil)
    end
end)

-- ============================================================================
-- 4. RENDERSTEP CAMERA SYNCHRONIZATION
-- ============================================================================
RunService:BindToRenderStep("ArenaDroneCameraRender", Enum.RenderPriority.Camera.Value, function(dt)
    -- If player possesses a Quin, yield drone override immediately
    if shared.PlayerControlledQuin then
        if activeDrone then
            setDroneMode(nil)
        end
        telemetryHUD.Visible = false
        shared.CameraOverrideCFrame = nil
        smoothedCameraCF = nil
        return
    end
    
    if not activeDrone then
        telemetryHUD.Visible = false
        shared.CameraOverrideCFrame = nil
        smoothedCameraCF = nil
        return
    end
    
    telemetryHUD.Visible = true
    local info = DRONE_INFO[activeDrone]
    camNameLbl.Text = info.Name
    camNameLbl.TextColor3 = info.Color
    topStroke.Color = info.Color
    
    local _, center, size, radius, minRadius = DroneTrajectories.getArenaMetrics()
    local t = (flightStartTime > 0) and (os.clock() - flightStartTime) or 0
    local outroElapsed = isOutro and (os.clock() - outroStartTime) or 0
    
    local rawDroneCF = DroneTrajectories.getDroneCFrame(activeDrone, t, isFlying, isOutro, outroElapsed, center, size, radius, minRadius)
    
    if rawDroneCF then
        if not smoothedCameraCF then
            smoothedCameraCF = (Workspace.CurrentCamera and Workspace.CurrentCamera.CFrame) or rawDroneCF
        end
        
        -- Butter-Smooth Frame-Rate Independent Exponential Damping (slerp/lerp)
        local smoothingRate = 8.5
        if activeDrone == "CombatChase" then
            smoothingRate = 9.5
        elseif activeDrone == "SkylineOrbit" or activeDrone == "LiveAerial" then
            smoothingRate = 6.0
        elseif activeDrone == "ArenaFootage" then
            smoothingRate = 8.0
        end
        
        local alpha = math.clamp(1 - math.exp(-smoothingRate * dt), 0.02, 1.0)
        smoothedCameraCF = smoothedCameraCF:Lerp(rawDroneCF, alpha)
        
        shared.CameraOverrideCFrame = smoothedCameraCF
        
        -- Butter-smooth telemetry metrics
        local now = os.clock()
        if lastPos and (now - lastTime) > 0.001 then
            local dist = (smoothedCameraCF.Position - lastPos).Magnitude
            local rawSpd = dist / (now - lastTime)
            currentSpeed = currentSpeed + (rawSpd * 1.097 - currentSpeed) * math.clamp(dt * 5.0, 0.05, 1.0)
        end
        lastPos = smoothedCameraCF.Position
        lastTime = now
        
        local altStuds = math.max(0, smoothedCameraCF.Position.Y - center.Y)
        altLbl.Text = string.format("ALT: %dm", math.floor(altStuds * 0.28))
        spdLbl.Text = string.format("SPD: %d km/h", math.floor(currentSpeed))
    end
end)

_G.SetArenaDrone = setDroneMode
shared.SetArenaDrone = setDroneMode
-- Two-way attribute synchronization for external scripts & testing
workspace:GetAttributeChangedSignal("SelectedDrone"):Connect(function()
    local val = workspace:GetAttribute("SelectedDrone")
    if val == "" or val == "Off" or val == "None" or val == nil then
        if activeDrone ~= nil then
            setDroneMode(nil)
        end
    else
        if activeDrone ~= val then
            setDroneMode(val)
        end
    end
end)

print("[ArenaDroneClientController] Initialized with V cycle hotkey and broadcast telemetry HUD.")
