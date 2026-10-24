--// PrepRoomClient.client.lua
-- The preparation rooms on this player's machine (ArenaPrepRoom on the server):
--   * doors: solid for this player unless they may enter (the room's owner, a friend, or let in);
--     the Knock prompt shows only on doors this player may not open;
--   * knocks: the owner gets "Let in / No"; notices from the rooms show as notifications;
--   * the PrepRoomTerminal:
--       BINOCULARS: a free camera held by hand (a slight shake) that flies only within a box in
--       front of the room's glass (WASD, Space / C up and down, Shift faster), hold the right mouse
--       button to look, the wheel zooms smoothly;
--       QUIN 1 / QUIN 2: your OWN Quins only, followed in 3rd person (the Spectator HUD's view:
--       right mouse orbits, wheel distance) or through their eyes (POV); the VIEW button switches;
--       the live event stats (time, both teams, your Quins). Backspace or X leaves it.
--       PLAN: each of your Quins' plan for the round (stance, target, role: QuinPlans on the
--       server), only while the room is open; how much it follows shows on its card.
--     While a terminal is in use the Spectator HUD and the spectate camera are limited to your own
--     Quins too (shared.SpectateFilter, read by QuinDebugHUD and SmoothCamera).

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
local MIN_FOV = 5
local LOOK_SENSITIVITY = 0.25
local BINO_SPEED = 24 -- studs/s (Shift: x2.5)
local BINO_BOX = { forward = 70, side = 60, down = 25, up = 45 } -- how far the binoculars fly from the glass
local SHAKE_DEG = 0.12 -- hand shake at no zoom (grows with the zoom)

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
    if player:GetAttribute("SkylarkRole") == "Admin" then
        return true -- (admins go through any door: SkylarkRoles)
    end
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
local hintLabel = label(gui, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 0.88, -6), Size = UDim2.fromOffset(700, 14), TextXAlignment = Enum.TextXAlignment.Center, TextSize = 11, TextColor3 = C_MUTED, Text = "" })

-- Mode buttons (top)
local bar = new("Frame", { Name = "ModeBar", Parent = gui, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 14), Size = UDim2.fromOffset(740, 34), BackgroundTransparency = 1 })
new("UIListLayout", { Parent = bar, FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0, 8) })
local function barButton(name, text, width)
    local b = new("TextButton", { Name = name, Parent = bar, Text = text, Font = Enum.Font.GothamBold, TextSize = 12, TextColor3 = C_TEXT, BackgroundColor3 = C_BG, BackgroundTransparency = 0.1, Size = UDim2.fromOffset(width, 34) })
    corner(b, 8)
    new("UIStroke", { Parent = b, Color = C_STROKE, Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border })
    return b
end
local binoButton = barButton("BinoButton", "BINOCULARS", 120)
local quinButtons = { barButton("Quin1Button", "MY QUIN 1", 110), barButton("Quin2Button", "MY QUIN 2", 110) }
local viewButton = barButton("ViewButton", "VIEW: 3RD PERSON", 150)
local planButton = barButton("PlanButton", "PLAN", 90)
local exitButton = barButton("ExitButton", "X", 40)

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
-- using = { terminal, room, mode = "bino" | 1 | 2, view = "third" | "pov", camera state per mode }
local using = nil
local lookHeld = false

local function isMine(model)
    return model:GetAttribute("OwnerUserId") == player.UserId
end

local function myQuins()
    local list = {}
    local qs = Workspace:FindFirstChild("QuinServer")
    if qs then
        for _, q in ipairs(qs:GetChildren()) do
            if q:IsA("Model") and isMine(q) then
                table.insert(list, q)
            end
        end
    end
    table.sort(list, function(a, b)
        return a.Name < b.Name
    end)
    return list
end

local function aliveRoot(quin)
    local hum = quin and quin:FindFirstChildOfClass("Humanoid")
    local root = quin and quin:FindFirstChild("HumanoidRootPart")
    if hum and root and hum.Health > 0 then
        return root
    end
    return nil
end

local function headCFrame(quin, root)
    local head = nil
    for _, d in ipairs(quin:GetDescendants()) do
        if d:IsA("Bone") and (d.Name == "Head" or d.Name:sub(-5) == ":Head") then
            head = d
            break
        end
    end
    local pos = head and head.TransformedWorldCFrame.Position or (root.Position + Vector3.new(0, 3, 0))
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

local function smooth(rate, dt)
    return 1 - math.exp(-rate * dt)
end

-- In POV the Quin's own body is hidden on this screen (its head would block the view)
local hiddenQuin = nil
local function hideQuin(quin)
    if hiddenQuin == quin then
        return
    end
    if hiddenQuin then
        for _, d in ipairs(hiddenQuin:GetDescendants()) do
            if d:IsA("BasePart") then
                d.LocalTransparencyModifier = 0
            end
        end
    end
    hiddenQuin = quin
    if quin then
        for _, d in ipairs(quin:GetDescendants()) do
            if d:IsA("BasePart") then
                d.LocalTransparencyModifier = 1
            end
        end
    end
end

local function setMode(mode)
    hideQuin(nil)
    using.mode = mode
    using.yaw, using.pitch = 0, -8
    using.sYaw, using.sPitch = 0, -8
    if mode == "bino" then
        using.fov = 40
        using.pos = nil -- (back to the glass)
    else
        using.fov = BASE_FOV
        local root = aliveRoot(myQuins()[mode])
        local look = root and root.CFrame.LookVector or Vector3.new(0, 0, -1)
        using.orbitYaw = math.deg(math.atan2(-look.X, -look.Z))
        using.orbitPitch = -14
        using.dist, using.sDist = 16, 16
        using.focus = nil
        using.povCF = nil
    end
end

local function stopUsing()
    if not using then
        return
    end
    local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
    if hum then
        hum.WalkSpeed = using.savedWalk or 16
        hum.JumpPower = using.savedJump or 50
        hum.JumpHeight = using.savedJumpHeight or 7.2
    end
    hideQuin(nil)
    using = nil
    gui.Enabled = false
    shared.TerminalCameraCFrame = nil
    shared.SpectateFilter = nil
    shared.SpectatedQuin = nil
    _G.SpectatedQuin = nil
    Workspace:SetAttribute("SpectatedQuin", "")
    if shared.SetSpectatorMode then
        shared.SetSpectatorMode("DEFAULT") -- (walking again)
    end
    camera.FieldOfView = BASE_FOV
    UserInputService.MouseBehavior = Enum.MouseBehavior.Default
end

local function startUsing(terminal)
    local room = terminal:FindFirstAncestor("PrepRoom")
    if not room then
        return
    end
    local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
    using = { terminal = terminal, room = room, view = "third", sFov = camera.FieldOfView }
    if hum then
        using.savedWalk, using.savedJump, using.savedJumpHeight = hum.WalkSpeed, hum.JumpPower, hum.JumpHeight
        hum.WalkSpeed, hum.JumpPower, hum.JumpHeight = 0, 0, 0 -- (WASD / Space fly the binoculars)
    end
    -- the Spectator HUD and the spectate camera: own Quins only while here
    shared.SpectateFilter = isMine
    local spec = shared.SpectatedQuin or _G.SpectatedQuin
    if spec and not isMine(spec) then
        shared.SpectatedQuin, _G.SpectatedQuin = nil, nil
        Workspace:SetAttribute("SpectatedQuin", "")
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
        if using and aliveRoot(myQuins()[i]) then
            setMode(i)
        end
    end)
end
viewButton.MouseButton1Click:Connect(function()
    if using then
        using.view = using.view == "third" and "pov" or "third"
        if using.mode ~= "bino" then
            setMode(using.mode)
        end
    end
end)
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
    if not using or input.UserInputType ~= Enum.UserInputType.MouseWheel then
        return
    end
    local zoomIn = input.Position.Z > 0
    if using.mode ~= "bino" and using.view == "third" then
        using.dist = math.clamp(using.dist * (zoomIn and 0.85 or 1.18), 6, 45)
    else
        using.fov = math.clamp(using.fov * (zoomIn and 0.82 or 1.22), MIN_FOV, BASE_FOV)
    end
end)

local function hpText(hum)
    return string.format("%d / %d", math.max(0, math.floor(hum.Health)), math.floor(hum.MaxHealth))
end

-- PLAN (left): one card per Quin; the choices are the model's Plan attributes (the server sets them)
local PLAN_ROWS = {
    { key = "Stance", attr = "PlanStance", options = { "Aggressive", "Balanced", "Defensive" }, default = "Balanced" },
    { key = "Target", attr = "PlanTarget", options = { "Own pick", "Weakest", "Strongest", "Defend" }, default = "Own pick" },
    { key = "Role", attr = "PlanRole", options = { "Free", "Striker", "Guard", "Hunter" }, default = "Free" },
}
local planPanel = new("Frame", { Name = "PlanPanel", Parent = gui, AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 24, 0.5, 0), Size = UDim2.fromOffset(372, 470), BackgroundColor3 = C_BG, BackgroundTransparency = 0.08, Visible = false })
corner(planPanel, 10)
new("UIStroke", { Parent = planPanel, Color = C_AMBER, Thickness = 1, Transparency = 0.4 })
label(planPanel, { Position = UDim2.fromOffset(14, 10), Size = UDim2.fromOffset(344, 18), Font = Enum.Font.GothamBold, TextSize = 14, TextColor3 = C_AMBER, Text = "PLAN FOR THIS ROUND" })
local planSub = label(planPanel, { Name = "PlanSub", Position = UDim2.fromOffset(14, 30), Size = UDim2.fromOffset(344, 14), TextSize = 11, TextColor3 = C_MUTED, Text = "" })
local planStatus = label(planPanel, { Name = "PlanStatus", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 14, 1, -10), Size = UDim2.fromOffset(344, 30), TextSize = 11, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, TextColor3 = C_GREEN, Text = "" })
local planCards = {}
for i = 1, 2 do
    local card = new("Frame", { Name = "PlanCard" .. i, Parent = planPanel, Position = UDim2.fromOffset(10, 52 + (i - 1) * 182), Size = UDim2.fromOffset(352, 174), BackgroundColor3 = C_CARD, BorderSizePixel = 0 })
    corner(card, 8)
    local c = { card = card, buttons = {} }
    c.title = label(card, { Position = UDim2.fromOffset(10, 6), Size = UDim2.fromOffset(332, 16), Font = Enum.Font.GothamBold, TextSize = 12, Text = "" })
    c.follow = label(card, { Position = UDim2.fromOffset(10, 22), Size = UDim2.fromOffset(332, 14), TextSize = 11, TextColor3 = C_MUTED, TextTruncate = Enum.TextTruncate.AtEnd, Text = "" })
    for r, row in ipairs(PLAN_ROWS) do
        local y = 42 + (r - 1) * 42
        label(card, { Position = UDim2.fromOffset(10, y), Size = UDim2.fromOffset(100, 12), Font = Enum.Font.GothamBold, TextSize = 10, TextColor3 = C_MUTED, Text = string.upper(row.key) })
        c.buttons[row.key] = {}
        local w = math.floor((332 - (#row.options - 1) * 4) / #row.options)
        for o, option in ipairs(row.options) do
            local b = new("TextButton", { Name = "Plan" .. i .. row.key .. option:gsub(" ", ""), Parent = card, Text = option, Font = Enum.Font.GothamBold, TextSize = 11, TextColor3 = C_TEXT, BackgroundColor3 = C_BG, Position = UDim2.fromOffset(10 + (o - 1) * (w + 4), y + 14), Size = UDim2.fromOffset(w, 24) })
            corner(b, 6)
            c.buttons[row.key][option] = b
        end
    end
    planCards[i] = c
end

local function planOpen()
    return Workspace:GetAttribute("ArenaPhase") == "PREPARATION_ROOM"
end

local function refreshPlan()
    planButton.TextColor3 = planPanel.Visible and C_AMBER or C_TEXT
    if not planPanel.Visible then
        return
    end
    local open = planOpen()
    planSub.Text = open and string.format("Set before the Quins deploy  •  locks in %ds", latest.TimeRemaining or 0)
        or "Locked: plans are set while your room is open."
    local mine = myQuins()
    for i, c in ipairs(planCards) do
        local q = mine[i]
        c.card.Visible = q ~= nil
        if q then
            local bond = q:GetAttribute("Bond") or 0
            c.title.Text = string.format("%s  •  %s  •  Bond %d", q.Name, tostring(q:GetAttribute("Temperament") or "?"), bond)
            local follow = q:GetAttribute("PlanFollow")
            local clash = q:GetAttribute("PlanClash")
            c.follow.Text = clash and string.format("Against its nature (%s): follows %d%%, hesitates", clash, math.floor((follow or 0) * 100 + 0.5))
                or follow and string.format("Follows about %d%% of the plan", math.floor(follow * 100 + 0.5))
                or string.format("No plan: fights its own way  •  would follow %d%%", math.floor((0.4 + 0.6 * math.clamp(bond / 100, 0, 1)) * 100 + 0.5))
            c.follow.TextColor3 = clash and C_AMBER or C_MUTED
            for _, row in ipairs(PLAN_ROWS) do
                local picked = q:GetAttribute(row.attr) or row.default
                for option, b in pairs(c.buttons[row.key]) do
                    local on = option == picked
                    b.BackgroundColor3 = on and C_AMBER or C_BG
                    b.TextColor3 = on and C_BG or (open and C_TEXT or C_MUTED)
                end
            end
        end
    end
end

for i, c in ipairs(planCards) do
    for _, row in ipairs(PLAN_ROWS) do
        for option, b in pairs(c.buttons[row.key]) do
            b.MouseButton1Click:Connect(function()
                local q = myQuins()[i]
                if not q or not planOpen() or not remote then
                    return
                end
                local plan = {}
                for _, other in ipairs(PLAN_ROWS) do
                    plan[other.key] = q:GetAttribute(other.attr) or other.default
                end
                plan[row.key] = option
                remote:FireServer("plan", q.Name, plan)
            end)
        end
    end
end
planButton.MouseButton1Click:Connect(function()
    planPanel.Visible = not planPanel.Visible
    planStatus.Text = ""
    refreshPlan()
end)
if remote then
    remote.OnClientEvent:Connect(function(kind, ok, text)
        if kind == "plan" then
            planStatus.Text = tostring(text or "")
            planStatus.TextColor3 = ok and C_GREEN or C_RED
        end
    end)
end

local function updateStats()
    refreshPlan()
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
    viewButton.Text = using.view == "third" and "VIEW: 3RD PERSON" or "VIEW: POV" -- (always there: the bar never shifts)
    viewButton.TextColor3 = using.mode == "bino" and C_MUTED or C_TEXT
end

-- BINOCULARS: a hand-held camera that flies only within the box in front of the glass
local function binocularCFrame(dt)
    local origin, toArena = glassEye(using.room)
    local right = toArena:Cross(Vector3.yAxis)
    using.pos = using.pos or origin
    using.sYaw += (using.yaw - using.sYaw) * smooth(12, dt)
    using.sPitch += (using.pitch - using.sPitch) * smooth(12, dt)
    local rot = CFrame.lookAt(Vector3.zero, toArena) * CFrame.Angles(0, math.rad(using.sYaw), 0) * CFrame.Angles(math.rad(using.sPitch), 0, 0)
    -- fly: WASD along the view, Space / C up and down, Shift faster
    if UserInputService:GetFocusedTextBox() == nil then
        local move = Vector3.zero
        if UserInputService:IsKeyDown(Enum.KeyCode.W) then move += rot.LookVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.S) then move -= rot.LookVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.D) then move += rot.RightVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.A) then move -= rot.RightVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.Space) then move += Vector3.yAxis end
        if UserInputService:IsKeyDown(Enum.KeyCode.C) then move -= Vector3.yAxis end
        if move.Magnitude > 0 then
            local speed = BINO_SPEED * (UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) and 2.5 or 1)
            using.pos += move.Unit * speed * dt
        end
    end
    -- the box: out over the arena, along the wall, a little down and further up
    local o = using.pos - origin
    local f = math.clamp(o:Dot(toArena), 0, BINO_BOX.forward)
    local sd = math.clamp(o:Dot(right), -BINO_BOX.side, BINO_BOX.side)
    local up = math.clamp(o.Y, -BINO_BOX.down, BINO_BOX.up)
    using.pos = origin + toArena * f + right * sd + Vector3.new(0, up, 0)
    -- a hand holding them: a slow wander that shows more the more it is zoomed
    local t = os.clock()
    local amp = SHAKE_DEG * (1 + 0.35 * (BASE_FOV / using.sFov - 1))
    local shake = CFrame.Angles(math.rad(math.noise(t * 0.8, 3.7) * amp * 2), math.rad(math.noise(t * 0.8, 9.1) * amp * 2), math.rad(math.noise(t * 0.5, 5.3) * amp))
    return CFrame.new(using.pos) * rot * shake
end

-- QUIN, 3rd person: the Spectator HUD's follow camera, round your own Quin
local function thirdPersonCFrame(root, dt)
    local focusTarget = root.Position + Vector3.new(0, 3, 0)
    using.focus = using.focus and using.focus:Lerp(focusTarget, smooth(10, dt)) or focusTarget
    using.sDist += (using.dist - using.sDist) * smooth(8, dt)
    using.orbitPitch = math.clamp(using.orbitPitch, -70, 30)
    local rot = CFrame.Angles(0, math.rad(using.orbitYaw), 0) * CFrame.Angles(math.rad(using.orbitPitch), 0, 0)
    local pos = using.focus - rot.LookVector * using.sDist
    if pos.Y < using.focus.Y - 2.5 then
        pos = Vector3.new(pos.X, using.focus.Y - 2.5, pos.Z)
    end
    return CFrame.lookAt(pos, using.focus)
end

-- QUIN, POV: through its eyes
local function povCFrame(quin, root, dt)
    using.yaw = math.clamp(using.yaw, -70, 70)
    using.sYaw += (using.yaw - using.sYaw) * smooth(12, dt)
    using.sPitch += (using.pitch - using.sPitch) * smooth(12, dt)
    local target = headCFrame(quin, root) * CFrame.Angles(0, math.rad(using.sYaw), 0) * CFrame.Angles(math.rad(using.sPitch + 8), 0, 0)
    using.povCF = using.povCF and using.povCF:Lerp(target, smooth(18, dt)) or target
    return using.povCF
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
    local me = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
    if not me or (me.Position - using.terminal.Position).Magnitude > 14 then
        stopUsing()
        return
    end
    if lookHeld then
        local delta = UserInputService:GetMouseDelta()
        local scale = LOOK_SENSITIVITY * (using.sFov / BASE_FOV)
        if using.mode ~= "bino" and using.view == "third" then
            using.orbitYaw -= delta.X * LOOK_SENSITIVITY
            using.orbitPitch -= delta.Y * LOOK_SENSITIVITY
        else
            using.yaw -= delta.X * scale
            using.pitch = math.clamp(using.pitch - delta.Y * scale, -70, 35)
        end
        UserInputService.MouseBehavior = Enum.MouseBehavior.LockCurrentPosition
    else
        UserInputService.MouseBehavior = Enum.MouseBehavior.Default
    end

    local cf
    if using.mode == "bino" then
        cf = binocularCFrame(dt)
        viewLabel.Text = "BINOCULARS"
        hintLabel.Text = "WASD fly  •  Space / C up, down  •  hold right mouse to look  •  wheel to zoom  •  Backspace to leave"
    else
        local q = myQuins()[using.mode]
        local root = aliveRoot(q)
        if not root then
            viewLabel.Text = "QUIN DOWN: back to binoculars"
            setMode("bino")
            return
        end
        if using.view == "third" then
            hideQuin(nil)
            cf = thirdPersonCFrame(root, dt)
            hintLabel.Text = "Hold right mouse to orbit  •  wheel for distance  •  Backspace to leave"
        else
            hideQuin(q)
            cf = povCFrame(q, root, dt)
            hintLabel.Text = "Hold right mouse to look  •  wheel to zoom  •  Backspace to leave"
        end
        viewLabel.Text = string.format("MY QUIN %d  •  %s", using.mode, using.view == "third" and "3RD PERSON" or "POV")
    end
    using.sFov += (using.fov - using.sFov) * smooth(6, dt) -- (a smooth zoom)
    shared.TerminalCameraCFrame = cf
    camera.FieldOfView = using.sFov
    zoomLabel.Text = string.format("x%.1f", BASE_FOV / using.sFov)
    if now - lastStats > 0.25 then
        lastStats = now
        updateStats()
    end
end)
