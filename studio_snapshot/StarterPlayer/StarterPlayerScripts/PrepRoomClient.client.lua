--// PrepRoomClient.client.lua
-- The preparation rooms on this player's machine (ArenaPrepRoom on the server):
--   * doors: solid for this player unless they may enter (the room's owner, a friend, or let in);
--     the Knock prompt shows only on doors this player may not open;
--   * knocks: the owner gets "Let in / No"; notices from the rooms show as notifications;
--   * the PrepRoomTerminal: futuristic binoculars from the room's glass (hold the right mouse
--     button to look, wheel to zoom), the point of view of your OWN Quins only (no one else's),
--     and the live event stats (time, both teams, your Quins). Backspace or X leaves it.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local StarterGui = game:GetService("StarterGui")
local ProximityPromptService = game:GetService("ProximityPromptService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera
local ArenaNetwork = ReplicatedStorage:WaitForChild("ArenaNetwork")
local remote = ArenaNetwork:WaitForChild("PrepRoom", 30)
local StateReplication = ArenaNetwork:WaitForChild("StateReplication", 30)

local BASE_FOV = 70
local MIN_FOV = 6
local LOOK_SENSITIVITY = 0.25

-- Colour palette (the Arena System panel's)
local C_BG = Color3.fromRGB(15, 18, 26)
local C_CARD = Color3.fromRGB(22, 27, 38)
local C_STROKE = Color3.fromRGB(38, 48, 68)
local C_CYAN = Color3.fromRGB(0, 220, 255)
local C_AMBER = Color3.fromRGB(255, 180, 50)
local C_GREEN = Color3.fromRGB(0, 230, 120)
local C_RED = Color3.fromRGB(255, 60, 80)
local C_TEXT = Color3.fromRGB(240, 245, 255)
local C_MUTED = Color3.fromRGB(130, 145, 170)
local TEAM_COLORS = { TeamAlpha = Color3.fromRGB(0, 170, 255), TeamBeta = Color3.fromRGB(255, 80, 80) }

local function notify(title, text, duration, buttons, callback)
    pcall(function()
        local data = { Title = title, Text = text, Duration = duration or 5 }
        if buttons then
            data.Button1, data.Button2, data.Callback = buttons[1], buttons[2], callback
        end
        StarterGui:SetCore("SendNotification", data)
    end)
end

-- ============================================================================
-- ROOMS AND DOORS
-- ============================================================================

local roomModels = {}
for _, d in ipairs(Workspace:GetDescendants()) do
    if d.Name == "PrepRoom" and d:IsA("Model") then
        table.insert(roomModels, d)
    end
end

local function mayEnter(model)
    local allowed = model:GetAttribute("PrepAllowed")
    return type(allowed) == "string" and allowed:find("," .. player.UserId .. ",", 1, true) ~= nil
end

local function refreshDoors()
    for _, model in ipairs(roomModels) do
        local door = model:FindFirstChild("Door")
        local owned = model:GetAttribute("PrepOwner") ~= nil
        local may = mayEnter(model)
        if door then
            door.CanCollide = not may -- (on this machine only: the server keeps it open for NPC owners)
            local knock = door:FindFirstChild("DoorPrompt")
            if knock then
                knock.Enabled = owned and not may
            end
        end
        for _, d in ipairs(model:GetChildren()) do
            local tp = d.Name == "PrepRoomTerminal" and d:FindFirstChild("TerminalPrompt")
            if tp then
                tp.Enabled = may
            end
        end
    end
end

if remote then
    remote.OnClientEvent:Connect(function(kind, a, b)
        if kind == "notice" then
            notify("Preparation Room", a)
        elseif kind == "knock" then
            local answer = Instance.new("BindableFunction")
            answer.OnInvoke = function(button)
                remote:FireServer("knockReply", b, button == "Let in")
                answer:Destroy()
            end
            notify("Knock knock", a .. " wants to come into your room.", 15, { "Let in", "No" }, answer)
        end
    end)
end

-- ============================================================================
-- TERMINAL
-- ============================================================================

local latest = {} -- StateReplication's last snapshot
if StateReplication then
    StateReplication.OnClientEvent:Connect(function(snap)
        if type(snap) == "table" then
            latest = snap
        end
    end)
end

local gui = Instance.new("ScreenGui")
gui.Name = "PrepTerminalUI"
gui.ResetOnSpawn = false
gui.DisplayOrder = 70
gui.IgnoreGuiInset = true
gui.Enabled = false
gui.Parent = player:WaitForChild("PlayerGui")

local function new(className, props)
    local inst = Instance.new(className)
    for k, v in pairs(props) do
        if k ~= "Parent" then
            inst[k] = v
        end
    end
    inst.Parent = props.Parent
    return inst
end

local function corner(inst, r)
    new("UICorner", { CornerRadius = UDim.new(0, r), Parent = inst })
end

local function label(parent, props)
    props.Parent = parent
    props.BackgroundTransparency = 1
    props.Font = props.Font or Enum.Font.Gotham
    props.TextColor3 = props.TextColor3 or C_TEXT
    props.TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Left
    return new("TextLabel", props)
end

-- Binocular frame: dark edges, cyan corner brackets, a reticle, the zoom
for _, edge in ipairs({
    { UDim2.new(0, 0, 0, 0), UDim2.new(1, 0, 0.08, 0), 0 },
    { UDim2.new(0, 0, 0.92, 0), UDim2.new(1, 0, 0.08, 0), 180 },
}) do
    local f = new("Frame", { Parent = gui, Position = edge[1], Size = edge[2], BackgroundColor3 = Color3.new(0, 0, 0), BorderSizePixel = 0, BackgroundTransparency = 0.15 })
    new("UIGradient", { Parent = f, Rotation = 90 + edge[3], Transparency = NumberSequence.new(0, 1) })
end
local reticle = new("Frame", { Parent = gui, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(46, 46), BackgroundTransparency = 1 })
new("UIStroke", { Parent = reticle, Color = C_CYAN, Thickness = 1.5, Transparency = 0.3 })
corner(reticle, 23)
new("Frame", { Parent = gui, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(4, 4), BackgroundColor3 = C_CYAN, BorderSizePixel = 0 })
for i, pos in ipairs({ Vector2.new(0.08, 0.12), Vector2.new(0.92, 0.12), Vector2.new(0.08, 0.88), Vector2.new(0.92, 0.88) }) do
    local b = new("Frame", { Parent = gui, AnchorPoint = pos, Position = UDim2.fromScale(pos.X, pos.Y), Size = UDim2.fromOffset(40, 40), BackgroundTransparency = 1 })
    local horiz = new("Frame", { Parent = b, Size = UDim2.new(1, 0, 0, 2), BackgroundColor3 = C_CYAN, BorderSizePixel = 0 })
    local vert = new("Frame", { Parent = b, Size = UDim2.new(0, 2, 1, 0), BackgroundColor3 = C_CYAN, BorderSizePixel = 0 })
    if pos.Y > 0.5 then
        horiz.Position = UDim2.new(0, 0, 1, -2)
    end
    if pos.X > 0.5 then
        vert.Position = UDim2.new(1, -2, 0, 0)
    end
end
local zoomLabel = label(gui, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.5, 34), Size = UDim2.fromOffset(200, 16), TextXAlignment = Enum.TextXAlignment.Center, Font = Enum.Font.GothamBold, TextSize = 12, TextColor3 = C_CYAN, Text = "" })
local viewLabel = label(gui, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.12, 6), Size = UDim2.fromOffset(500, 18), TextXAlignment = Enum.TextXAlignment.Center, Font = Enum.Font.GothamBold, TextSize = 14, TextColor3 = C_CYAN, Text = "" })
label(gui, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 0.88, -6), Size = UDim2.fromOffset(600, 14), TextXAlignment = Enum.TextXAlignment.Center, TextSize = 11, TextColor3 = C_MUTED, Text = "Hold right mouse to look  •  wheel to zoom  •  Backspace to leave" })

-- Mode buttons (top)
local bar = new("Frame", { Parent = gui, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 14), Size = UDim2.fromOffset(470, 34), BackgroundTransparency = 1 })
new("UIListLayout", { Parent = bar, FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0, 8) })
local function barButton(text, width)
    local b = new("TextButton", { Parent = bar, Text = text, Font = Enum.Font.GothamBold, TextSize = 12, TextColor3 = C_TEXT, BackgroundColor3 = C_BG, BackgroundTransparency = 0.1, Size = UDim2.fromOffset(width, 34) })
    corner(b, 8)
    new("UIStroke", { Parent = b, Color = C_STROKE, Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border })
    return b
end
local binoButton = barButton("BINOCULARS", 120)
local quinButtons = { barButton("MY QUIN 1", 110), barButton("MY QUIN 2", 110) }
local exitButton = barButton("X", 40)

-- Stats (right)
local stats = new("Frame", { Parent = gui, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -24, 0.5, 0), Size = UDim2.fromOffset(250, 250), BackgroundColor3 = C_BG, BackgroundTransparency = 0.12 })
corner(stats, 10)
new("UIStroke", { Parent = stats, Color = C_CYAN, Thickness = 1, Transparency = 0.5 })
local statTitle = label(stats, { Position = UDim2.fromOffset(14, 10), Size = UDim2.fromOffset(222, 16), Font = Enum.Font.GothamBold, TextSize = 13, TextColor3 = C_AMBER, Text = "EVENT" })
local statPhase = label(stats, { Position = UDim2.fromOffset(14, 28), Size = UDim2.fromOffset(222, 14), TextSize = 11, TextColor3 = C_MUTED, Text = "" })
local teamRows = {}
for i, team in ipairs({ "TeamAlpha", "TeamBeta" }) do
    local y = 52 + (i - 1) * 40
    local name = label(stats, { Position = UDim2.fromOffset(14, y), Size = UDim2.fromOffset(222, 14), Font = Enum.Font.GothamBold, TextSize = 11, TextColor3 = TEAM_COLORS[team], Text = "" })
    local track = new("Frame", { Parent = stats, Position = UDim2.fromOffset(14, y + 18), Size = UDim2.fromOffset(222, 8), BackgroundColor3 = C_CARD, BorderSizePixel = 0 })
    corner(track, 4)
    local fill = new("Frame", { Parent = track, Size = UDim2.fromScale(1, 1), BackgroundColor3 = TEAM_COLORS[team], BorderSizePixel = 0 })
    corner(fill, 4)
    teamRows[team] = { name = name, fill = fill }
end
label(stats, { Position = UDim2.fromOffset(14, 138), Size = UDim2.fromOffset(222, 14), Font = Enum.Font.GothamBold, TextSize = 11, TextColor3 = C_MUTED, Text = "YOUR QUINS" })
local myRows = {}
for i = 1, 2 do
    local y = 156 + (i - 1) * 42
    local name = label(stats, { Position = UDim2.fromOffset(14, y), Size = UDim2.fromOffset(222, 14), TextSize = 11, Text = "" })
    local track = new("Frame", { Parent = stats, Position = UDim2.fromOffset(14, y + 18), Size = UDim2.fromOffset(222, 8), BackgroundColor3 = C_CARD, BorderSizePixel = 0 })
    corner(track, 4)
    local fill = new("Frame", { Parent = track, Size = UDim2.fromScale(1, 1), BackgroundColor3 = C_GREEN, BorderSizePixel = 0 })
    corner(fill, 4)
    myRows[i] = { name = name, track = track, fill = fill }
end

-- ---- state ----
local using = nil -- { terminal, room, mode = "bino" | 1 | 2, yaw, pitch, fov, savedWalk, savedJump }
local lookHeld = false

local function myQuins()
    local list = {}
    local qs = Workspace:FindFirstChild("QuinServer")
    if qs then
        for _, q in ipairs(qs:GetChildren()) do
            if q:IsA("Model") and q:GetAttribute("OwnerUserId") == player.UserId then
                table.insert(list, q)
            end
        end
    end
    table.sort(list, function(a, b)
        return a.Name < b.Name
    end)
    return list
end

local function headCFrame(quin)
    local best = nil
    for _, d in ipairs(quin:GetDescendants()) do
        if d:IsA("Bone") and (d.Name == "Head" or d.Name:sub(-5) == ":Head") then
            best = d
            break
        end
    end
    local root = quin:FindFirstChild("HumanoidRootPart")
    if not root then
        return nil
    end
    local pos = best and best.TransformedWorldCFrame.Position or (root.Position + Vector3.new(0, 3, 0))
    return CFrame.new(pos + root.CFrame.LookVector * 0.8 + Vector3.new(0, 0.3, 0)) * root.CFrame.Rotation
end

local function glassEye(room)
    local glass = room:FindFirstChild("PreparationRoomGlass")
    local ground = room:FindFirstChild("PreparationRoomGround")
    local toArena = Vector3.new(-math.sign((ground or glass).Position.X), 0, 0)
    local floorY = ground and (ground.Position.Y + ground.Size.Y / 2) or glass.Position.Y
    local base = glass and glass.Position or ground.Position
    return Vector3.new(base.X, floorY + 7, base.Z) - toArena * 1.5, toArena
end

local function setMode(mode)
    using.mode = mode
    using.yaw, using.pitch = 0, -8
    using.fov = mode == "bino" and 40 or BASE_FOV
end

local function stopUsing()
    if not using then
        return
    end
    local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
    if hum then
        hum.WalkSpeed = using.savedWalk or 16
        hum.JumpPower = using.savedJump or 50
    end
    using = nil
    gui.Enabled = false
    shared.TerminalCameraCFrame = nil
    camera.FieldOfView = BASE_FOV
    UserInputService.MouseBehavior = Enum.MouseBehavior.Default
end

local function startUsing(terminal)
    local room = terminal:FindFirstAncestor("PrepRoom")
    if not room then
        return
    end
    local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
    using = { terminal = terminal, room = room }
    if hum then
        using.savedWalk, using.savedJump = hum.WalkSpeed, hum.JumpPower
        hum.WalkSpeed, hum.JumpPower = 0, 0
    end
    setMode("bino")
    gui.Enabled = true
end

binoButton.MouseButton1Click:Connect(function()
    if using then
        setMode("bino")
    end
end)
for i, b in ipairs(quinButtons) do
    b.MouseButton1Click:Connect(function()
        if using and myQuins()[i] then
            setMode(i)
        end
    end)
end
exitButton.MouseButton1Click:Connect(stopUsing)

ProximityPromptService.PromptTriggered:Connect(function(prompt)
    if prompt.Name == "TerminalPrompt" and not using then
        startUsing(prompt.Parent)
    end
end)

UserInputService.InputBegan:Connect(function(input, gp)
    if not using then
        return
    end
    if input.UserInputType == Enum.UserInputType.MouseButton2 then
        lookHeld = true
    elseif input.KeyCode == Enum.KeyCode.Backspace and not gp then
        stopUsing()
    end
end)
UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton2 then
        lookHeld = false
    end
end)
UserInputService.InputChanged:Connect(function(input)
    if using and input.UserInputType == Enum.UserInputType.MouseWheel then
        using.fov = math.clamp(using.fov * (input.Position.Z > 0 and 0.85 or 1.18), MIN_FOV, BASE_FOV)
    end
end)

local function hpText(hum)
    return string.format("%d / %d", math.max(0, math.floor(hum.Health)), math.floor(hum.MaxHealth))
end

local function updateStats()
    statTitle.Text = string.upper(Workspace:GetAttribute("ArenaSlot") or "ARENA ONE")
    statPhase.Text = string.format("%s  •  %ds", tostring(latest.Phase or "IDLE"):gsub("_", " "), latest.TimeRemaining or 0)
    for team, row in pairs(teamRows) do
        local isAlpha = team == "TeamAlpha"
        local hp, max = latest[isAlpha and "AlphaHp" or "BetaHp"] or 0, latest[isAlpha and "AlphaMax" or "BetaMax"] or 0
        local alive = latest[isAlpha and "AlphaAlive" or "BetaAlive"] or 0
        row.name.Text = string.format("%s  •  %d standing", isAlpha and "TEAM ALPHA" or "TEAM BETA", alive)
        row.fill.Size = UDim2.fromScale(max > 0 and math.clamp(hp / max, 0, 1) or 0, 1)
    end
    local mine = myQuins()
    for i, row in ipairs(myRows) do
        local q = mine[i]
        local hum = q and q:FindFirstChildOfClass("Humanoid")
        row.name.Visible, row.track.Visible = q ~= nil, q ~= nil
        quinButtons[i].Visible = q ~= nil
        if q and hum then
            local down = hum.Health <= 0
            row.name.Text = string.format("%s  •  %s  •  %s", q:GetAttribute("Team") == "TeamBeta" and "Beta" or "Alpha",
                down and "DOWN" or tostring(q:GetAttribute("CurrentState") or "Idle"), hpText(hum))
            row.name.TextColor3 = down and C_RED or C_TEXT
            row.fill.Size = UDim2.fromScale(math.clamp(hum.Health / math.max(1, hum.MaxHealth), 0, 1), 1)
            row.fill.BackgroundColor3 = hum.Health / math.max(1, hum.MaxHealth) > 0.35 and C_GREEN or C_AMBER
        end
    end
    binoButton.TextColor3 = using.mode == "bino" and C_CYAN or C_TEXT
    for i, b in ipairs(quinButtons) do
        b.TextColor3 = using.mode == i and C_CYAN or C_TEXT
    end
end

local lastStats, lastDoors = 0, 0
RunService:BindToRenderStep("PrepTerminalCamera", Enum.RenderPriority.Camera.Value - 1, function(dt)
    local now = os.clock()
    if now - lastDoors > 0.5 then
        lastDoors = now
        refreshDoors()
    end
    if not using then
        return
    end
    -- walked or was sent away from the terminal: done
    local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
    if not root or (root.Position - using.terminal.Position).Magnitude > 14 then
        stopUsing()
        return
    end
    if lookHeld then
        local delta = UserInputService:GetMouseDelta()
        local scale = LOOK_SENSITIVITY * (using.fov / BASE_FOV)
        using.yaw = using.yaw - delta.X * scale
        using.pitch = math.clamp(using.pitch - delta.Y * scale, -70, 35)
        UserInputService.MouseBehavior = Enum.MouseBehavior.LockCurrentPosition
    else
        UserInputService.MouseBehavior = Enum.MouseBehavior.Default
    end

    local cf
    if using.mode == "bino" then
        local eye, toArena = glassEye(using.room)
        using.yaw = math.clamp(using.yaw, -75, 75)
        local base = CFrame.lookAt(eye, eye + toArena)
        cf = base * CFrame.Angles(0, math.rad(using.yaw), 0) * CFrame.Angles(math.rad(using.pitch), 0, 0)
        viewLabel.Text = "BINOCULARS"
    else
        local q = myQuins()[using.mode]
        local hum = q and q:FindFirstChildOfClass("Humanoid")
        local head = q and hum and hum.Health > 0 and headCFrame(q)
        if head then
            using.yaw = math.clamp(using.yaw, -70, 70)
            cf = head * CFrame.Angles(0, math.rad(using.yaw), 0) * CFrame.Angles(math.rad(using.pitch + 8), 0, 0)
            viewLabel.Text = string.format("MY QUIN %d  •  %s", using.mode, q.Name)
        else
            viewLabel.Text = "QUIN DOWN: back to binoculars"
            setMode("bino")
            return
        end
    end
    shared.TerminalCameraCFrame = cf
    camera.FieldOfView = using.fov
    zoomLabel.Text = string.format("x%.1f", BASE_FOV / using.fov)
    if now - lastStats > 0.25 then
        lastStats = now
        updateStats()
    end
end)
