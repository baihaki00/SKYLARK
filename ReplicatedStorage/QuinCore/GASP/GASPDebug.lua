--// GASPDebug.lua
-- Unreal Engine 5.8 GASP Telemetry HUD & 3D Trajectory Visualizer for QuinCore
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local AssetMap = require(script.Parent:WaitForChild("GASPAssetMap"))

local GASPDebug = {}
GASPDebug.__index = GASPDebug

local visualsFolder = nil
local trajectorySpheres = {}
local stoppingDisc = nil
local velocityArrow = nil
local intentArrow = nil

local telemetryGui = nil
local labels = {}
local isVisible = false

function GASPDebug.snapshot(fighter)
    if not fighter then return nil end
    if AssetMap.Enabled ~= true then
        return {
            state = "LegacyFallback",
            clip = "Legacy AnimationConfig",
            score = nil,
            phase = 0,
            position = fighter.PrimaryPart and fighter.PrimaryPart.Position or nil,
            velocity = fighter.PrimaryPart and fighter.PrimaryPart.AssemblyLinearVelocity or nil,
        }
    end
    return {
        state = fighter:GetAttribute("GASPState") or "Inactive",
        clip = fighter:GetAttribute("GASPClip") or "None",
        score = fighter:GetAttribute("GASPSelectionScore"),
        phase = fighter:GetAttribute("GASPPhase") or 0,
        position = fighter.PrimaryPart and fighter.PrimaryPart.Position or nil,
        velocity = fighter.PrimaryPart and fighter.PrimaryPart.AssemblyLinearVelocity or nil,
    }
end

local function getOrCreateVisualsFolder()
    if visualsFolder and visualsFolder.Parent then return visualsFolder end
    local existing = Workspace:FindFirstChild("GASP_TrajectoryVisuals")
    if existing then
        visualsFolder = existing
    else
        visualsFolder = Instance.new("Folder")
        visualsFolder.Name = "GASP_TrajectoryVisuals"
        visualsFolder.Parent = Workspace
    end
    return visualsFolder
end

function GASPDebug.initWorldVisuals(samplesCount)
    samplesCount = samplesCount or 6
    local folder = getOrCreateVisualsFolder()
    folder:ClearAllChildren()
    trajectorySpheres = {}

    for i = 1, samplesCount do
        local sphere = Instance.new("Part")
        sphere.Name = "Node_" .. i
        sphere.Shape = Enum.PartType.Ball
        sphere.Size = Vector3.new(0.45, 0.45, 0.45)
        sphere.Material = Enum.Material.Neon
        sphere.Color = Color3.fromRGB(0, 220, 255)
        sphere.Anchored = true
        sphere.CanCollide = false
        sphere.CanQuery = false
        sphere.CanTouch = false
        sphere.CastShadow = false
        sphere.Transparency = 0.2
        sphere.Parent = folder
        table.insert(trajectorySpheres, sphere)
    end

    stoppingDisc = Instance.new("Part")
    stoppingDisc.Name = "StoppingMarker"
    stoppingDisc.Shape = Enum.PartType.Cylinder
    stoppingDisc.Size = Vector3.new(0.08, 1.8, 1.8)
    stoppingDisc.Material = Enum.Material.Neon
    stoppingDisc.Color = Color3.fromRGB(255, 60, 60)
    stoppingDisc.Anchored = true
    stoppingDisc.CanCollide = false
    stoppingDisc.CanQuery = false
    stoppingDisc.CanTouch = false
    stoppingDisc.CastShadow = false
    stoppingDisc.Transparency = 0.4
    stoppingDisc.Parent = folder

    velocityArrow = Instance.new("Part")
    velocityArrow.Name = "VelocityVector"
    velocityArrow.Shape = Enum.PartType.Cylinder
    velocityArrow.Size = Vector3.new(0.15, 0.15, 2.0)
    velocityArrow.Material = Enum.Material.Neon
    velocityArrow.Color = Color3.fromRGB(0, 255, 120)
    velocityArrow.Anchored = true
    velocityArrow.CanCollide = false
    velocityArrow.CanQuery = false
    velocityArrow.CanTouch = false
    velocityArrow.CastShadow = false
    velocityArrow.Transparency = 0.3
    velocityArrow.Parent = folder
end

function GASPDebug.initHUD(playerGui)
    if not playerGui then
        local player = Players.LocalPlayer
        playerGui = player and player:FindFirstChild("PlayerGui")
    end
    if not playerGui then return end

    local existing = playerGui:FindFirstChild("GASP_TelemetryHUD")
    if existing then existing:Destroy() end

    telemetryGui = Instance.new("ScreenGui")
    telemetryGui.Name = "GASP_TelemetryHUD"
    telemetryGui.ResetOnSpawn = false
    telemetryGui.DisplayOrder = 100

    local frame = Instance.new("Frame")
    frame.Name = "TelemetryPanel"
    frame.Size = UDim2.new(0, 260, 0, 180)
    frame.Position = UDim2.new(0, 20, 0, 80)
    frame.BackgroundColor3 = Color3.fromRGB(12, 16, 24)
    frame.BackgroundTransparency = 0.15
    frame.BorderSizePixel = 0
    frame.Parent = telemetryGui

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 8)
    corner.Parent = frame

    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(0, 180, 255)
    stroke.Thickness = 1.2
    stroke.Transparency = 0.3
    stroke.Parent = frame

    local title = Instance.new("TextLabel")
    title.Name = "Title"
    title.Size = UDim2.new(1, -16, 0, 24)
    title.Position = UDim2.new(0, 10, 0, 6)
    title.BackgroundTransparency = 1
    title.Font = Enum.Font.GothamBold
    title.TextSize = 11
    title.TextColor3 = Color3.fromRGB(0, 220, 255)
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Text = "UE5 GASP TELEMETRY // QUINCORE"
    title.Parent = frame

    local function makeRow(name, yPos, labelText)
        local lbl = Instance.new("TextLabel")
        lbl.Name = name .. "_Label"
        lbl.Size = UDim2.new(0, 75, 0, 18)
        lbl.Position = UDim2.new(0, 10, 0, yPos)
        lbl.BackgroundTransparency = 1
        lbl.Font = Enum.Font.Gotham
        lbl.TextSize = 10
        lbl.TextColor3 = Color3.fromRGB(160, 175, 195)
        lbl.TextXAlignment = Enum.TextXAlignment.Left
        lbl.Text = labelText
        lbl.Parent = frame

        local val = Instance.new("TextLabel")
        val.Name = name .. "_Val"
        val.Size = UDim2.new(1, -95, 0, 18)
        val.Position = UDim2.new(0, 85, 0, yPos)
        val.BackgroundTransparency = 1
        val.Font = Enum.Font.GothamBold
        val.TextSize = 10
        val.TextColor3 = Color3.fromRGB(240, 245, 255)
        val.TextXAlignment = Enum.TextXAlignment.Left
        val.Text = "--"
        val.Parent = frame

        labels[name] = val
    end

    makeRow("State", 32, "STATE:")
    makeRow("Speed", 52, "SPEED:")
    makeRow("Accel", 72, "ACCEL:")
    makeRow("BrakeDist", 92, "STOP DIST:")
    makeRow("Phase", 112, "GAIT PHASE:")
    makeRow("Clip", 132, "MATCH CLIP:")
    makeRow("Score", 152, "SCORE:")

    telemetryGui.Parent = playerGui
    isVisible = true
end

function GASPDebug.setVisible(visible)
    isVisible = visible
    if telemetryGui then telemetryGui.Enabled = visible end
    if visualsFolder then
        for _, child in ipairs(visualsFolder:GetChildren()) do
            child.Transparency = visible and 0.3 or 1.0
        end
    end
end

function GASPDebug.update(fighter, rootPart, snapshot, dt)
    if not isVisible or not rootPart then return end

    local speed = snapshot.velocity and Vector3.new(snapshot.velocity.X, 0, snapshot.velocity.Z).Magnitude or 0
    local accel = snapshot.acceleration and snapshot.acceleration.Magnitude or 0
    local state = snapshot.state or "Idle"
    local clip = snapshot.clip or (snapshot.database and snapshot.database.lastSelection and snapshot.database.lastSelection.label) or "None"
    local score = snapshot.score or (snapshot.database and snapshot.database.lastSelection and snapshot.database.lastSelection.score) or -1
    local phase = snapshot.phase or 0

    if labels["State"] then
        labels["State"].Text = string.upper(state)
        if state == "Sprint" then
            labels["State"].TextColor3 = Color3.fromRGB(255, 100, 50)
        elseif state == "Run" then
            labels["State"].TextColor3 = Color3.fromRGB(0, 220, 255)
        elseif state == "Walk" then
            labels["State"].TextColor3 = Color3.fromRGB(100, 255, 140)
        elseif state == "Stop" then
            labels["State"].TextColor3 = Color3.fromRGB(255, 80, 80)
        elseif state == "Pivot" or state == "Turn" then
            labels["State"].TextColor3 = Color3.fromRGB(255, 220, 40)
        else
            labels["State"].TextColor3 = Color3.fromRGB(180, 190, 210)
        end
    end

    if labels["Speed"] then
        labels["Speed"].Text = string.format("%.1f studs/s (%.1f km/h)", speed, speed * 0.96)
    end
    if labels["Accel"] then
        labels["Accel"].Text = string.format("%.1f studs/s²", accel)
    end

    local brakingRate = 68.0
    local stopDistance = (speed * speed) / (2 * math.max(1, brakingRate))
    if labels["BrakeDist"] then
        labels["BrakeDist"].Text = string.format("%.2f studs", stopDistance)
    end

    if labels["Phase"] then
        labels["Phase"].Text = string.format("%.1f %%", (phase % 1.0) * 100)
    end
    if labels["Clip"] then
        labels["Clip"].Text = tostring(clip)
        labels["Clip"].TextColor3 = clip ~= "None" and Color3.fromRGB(120, 255, 160) or Color3.fromRGB(140, 140, 140)
    end
    if labels["Score"] then
        labels["Score"].Text = score >= 0 and string.format("%.2f", score) or "N/A (Pending Assets)"
    end

    local footY = rootPart.Position.Y - (rootPart.Size.Y * 0.5)
    local predicted = snapshot.predicted or {}

    for i, sphere in ipairs(trajectorySpheres) do
        local point = predicted[i]
        if point then
            local pos = Vector3.new(point.position.X, footY + 0.15, point.position.Z)
            sphere.Position = pos
            sphere.Transparency = 0.15 + (i * 0.08)
            local tFraction = i / #trajectorySpheres
            if speed > 24 then
                sphere.Color = Color3.fromRGB(math.floor(255 * tFraction), math.floor(180 * (1 - tFraction * 0.5)), math.floor(255 * (1 - tFraction)))
            else
                sphere.Color = Color3.fromRGB(0, 220, 255)
            end
        else
            sphere.Transparency = 1
        end
    end

    if stoppingDisc then
        if speed > 1.0 and snapshot.velocity then
            local flatVel = Vector3.new(snapshot.velocity.X, 0, snapshot.velocity.Z).Unit
            local stopPos = rootPart.Position + flatVel * stopDistance
            stopPos = Vector3.new(stopPos.X, footY + 0.05, stopPos.Z)
            stoppingDisc.CFrame = CFrame.new(stopPos) * CFrame.Angles(0, 0, math.rad(90))
            stoppingDisc.Transparency = 0.35
        else
            stoppingDisc.Transparency = 1
        end
    end

    if velocityArrow then
        if speed > 1.0 and snapshot.velocity then
            local flatVel = Vector3.new(snapshot.velocity.X, 0, snapshot.velocity.Z)
            local arrowLen = math.clamp(speed * 0.12, 1.0, 5.0)
            velocityArrow.Size = Vector3.new(0.15, arrowLen, 0.15)
            local center = rootPart.Position + flatVel.Unit * (arrowLen * 0.5)
            velocityArrow.CFrame = CFrame.lookAt(center, center + flatVel.Unit) * CFrame.Angles(math.rad(90), 0, 0)
            velocityArrow.Transparency = 0.25
        else
            velocityArrow.Transparency = 1
        end
    end
end

function GASPDebug.cleanup()
    if telemetryGui then
        telemetryGui:Destroy()
        telemetryGui = nil
    end
    if visualsFolder then
        visualsFolder:ClearAllChildren()
        visualsFolder:Destroy()
        visualsFolder = nil
    end
    trajectorySpheres = {}
    labels = {}
    isVisible = false
end

return GASPDebug

