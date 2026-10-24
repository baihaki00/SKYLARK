--// NpcDialog.lua (client only)
-- Talking to an NPC: the camera comes round in front of the NPC, slid to their left and looking
-- straight ahead (the way they face), so they stand in the middle of the left half of the screen,
-- facing front, with what they say in a big speech bubble over their head; the menu (what you can
-- do with them) is on the right half. The NPC never turns. Anyone standing between the camera and
-- the NPC (a queue, passers-by) is hidden on your screen while it's open. Only you see it. The player's own body is hidden and stands
-- still while it's open.
-- One for every NPC you deal with: the Arena Receptionist (ArenaEntry.client), and later the
-- Trainer, the Quin Specialist and the rest.
--
--   local d = NpcDialog.open(model, { name = "Receptionist", onClose = fn })  -> the dialog (closes any other)
--   d:say(text)                     -> types it into the bubble; returns once it's shown
--   d:choose(text, options)         -> says text, shows options { { id, text, primary? } } on the menu
--                                      side, yields: the picked id (nil if the dialog closed)
--   d:place(frame)                  -> puts a GUI frame (a menu) on the menu side until the dialog closes
--   d:close()                       -> camera, body and menus back as they were; onClose()
--   d.open                          -> still open?
--   NpcDialog.current()             -> the dialog open now, or nil

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TextService = game:GetService("TextService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer

local NpcDialog = {}
NpcDialog.__index = NpcDialog

local DISTANCE = 24 -- studs in front of the NPC: far back with a long lens, so they and their desk
local FOV = 22 --     are seen almost straight on even though the camera is slid to the side
local RISE = 1.6 -- studs the camera sits above their head
local NPC_X = 0.25 -- (scale) where the NPC stands across the screen: the middle of the left half
local MENU_X = 0.72 -- (scale) the centre of the menu side
local BUBBLE_W = 380
local TYPE_SPEED = 55 -- characters a second

local C_BUBBLE = Color3.fromRGB(250, 250, 252)
local C_INK = Color3.fromRGB(20, 24, 34)
local C_NAME = Color3.fromRGB(255, 180, 50)
local C_BG = Color3.fromRGB(15, 18, 26)
local C_CARD = Color3.fromRGB(22, 27, 38)
local C_STROKE = Color3.fromRGB(38, 48, 68)
local C_TEXT = Color3.fromRGB(240, 245, 255)

local currentDialog = nil

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

local function corner(inst, radius)
    new("UICorner", { CornerRadius = UDim.new(0, radius), Parent = inst })
end

local function flat(v)
    return Vector3.new(v.X, 0, v.Z)
end

local function controls()
    local ok, module = pcall(function()
        return require(player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule"))
    end)
    return ok and module and module:GetControls() or nil
end

local function setBodyHidden(hidden)
    local character = player.Character
    if not character then
        return
    end
    for _, d in ipairs(character:GetDescendants()) do
        if d:IsA("BasePart") or d:IsA("Decal") then
            d.LocalTransparencyModifier = hidden and 1 or 0
        end
    end
end

function NpcDialog.current()
    return currentDialog
end

function NpcDialog.open(model, options)
    options = options or {}
    if currentDialog then
        currentDialog:close()
    end
    local head = model and model:FindFirstChild("Head")
    local camera = Workspace.CurrentCamera
    if not head or not camera then
        return nil
    end
    local self = setmetatable({ open = true, model = model, head = head, placed = {}, onClose = options.onClose }, NpcDialog)
    currentDialog = self

    -- the camera: in front of the NPC (the way they face; toward you if they face nowhere), looking
    -- straight back along it, slid sideways just enough to put them at NPC_X across the screen
    local myRoot = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
    local npcRoot = model:FindFirstChild("HumanoidRootPart") or head
    local toMe = flat(npcRoot.CFrame.LookVector)
    if toMe.Magnitude < 0.5 and myRoot then
        toMe = flat(myRoot.Position - npcRoot.Position)
    end
    toMe = toMe.Magnitude > 0.01 and toMe.Unit or Vector3.new(0, 0, 1)
    local forward = -toMe
    local right = forward:Cross(Vector3.yAxis).Unit
    local viewport = camera.ViewportSize
    local aspect = viewport.Y > 0 and viewport.X / viewport.Y or 16 / 9
    local across = DISTANCE * (0.5 - NPC_X) * 2 * math.tan(math.rad(FOV / 2)) * aspect
    local camPos = head.Position + toMe * DISTANCE + right * across + Vector3.new(0, RISE, 0)
    local goal = CFrame.lookAt(camPos, camPos + forward * 10 - Vector3.new(0, 0.95, 0))
    -- (the space between the camera and the NPC: people in it are hidden)
    local mid = (camPos + head.Position) / 2
    self.between = { cframe = CFrame.lookAt(mid, head.Position), size = Vector3.new(8, 10, (camPos - head.Position).Magnitude - 2) }
    self.hidden = {}
    self.saved = { type = camera.CameraType, subject = camera.CameraSubject, fov = camera.FieldOfView }
    camera.CameraType = Enum.CameraType.Scriptable
    -- (held every frame, last of all: other camera scripts can't pull it away)
    local from, fromFov, t0 = camera.CFrame, camera.FieldOfView, os.clock()
    self.cameraKey = "NpcDialogCamera_" .. tostring(t0)
    local params = OverlapParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = { model, player.Character }
    local lastScan = 0
    RunService:BindToRenderStep(self.cameraKey, Enum.RenderPriority.Last.Value, function()
        if os.clock() - lastScan > 0.3 then
            lastScan = os.clock()
            for _, part in ipairs(Workspace:GetPartBoundsInBox(self.between.cframe, self.between.size, params)) do
                local who = part:FindFirstAncestorOfClass("Model")
                if who and not self.hidden[who] and who:FindFirstChildOfClass("Humanoid") then
                    self.hidden[who] = true
                end
            end
        end
        for who in pairs(self.hidden) do
            for _, d in ipairs(who:GetDescendants()) do
                if d:IsA("BasePart") or d:IsA("Decal") then
                    d.LocalTransparencyModifier = 1
                end
            end
        end
        local view = Workspace.CurrentCamera
        local a = math.clamp((os.clock() - t0) / 0.6, 0, 1)
        a = 1 - (1 - a) * (1 - a)
        view.CameraType = Enum.CameraType.Scriptable
        view.CFrame = from:Lerp(goal, a)
        view.FieldOfView = fromFov + (FOV - fromFov) * a
    end)
    self.controls = controls()
    if self.controls then
        self.controls:Disable()
    end
    local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
    if hum then
        hum:Move(Vector3.zero)
    end
    setBodyHidden(true)

    -- the bubble over the NPC's head (follows it on screen, kept on the left half)
    local gui = new("ScreenGui", { Name = "NpcDialogUI", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 5, Parent = player:WaitForChild("PlayerGui") })
    self.gui = gui
    local bubble = new("Frame", { Name = "Bubble", Parent = gui, AnchorPoint = Vector2.new(0.5, 1), Size = UDim2.fromOffset(BUBBLE_W, 90), BackgroundColor3 = C_BUBBLE, Visible = false, ZIndex = 2 })
    corner(bubble, 22)
    new("UIStroke", { Color = C_INK, Thickness = 2, Parent = bubble })
    -- (the tail: a turned square behind the bubble, its lower half showing as the point)
    local tail = new("Frame", { Name = "Tail", Parent = gui, AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(20, 20), Rotation = 45, BackgroundColor3 = C_BUBBLE, BorderSizePixel = 0, ZIndex = 1, Visible = false })
    new("UIStroke", { Color = C_INK, Thickness = 2, Parent = tail })
    local nameTag = new("TextLabel", { Name = "NameTag", Parent = bubble, BackgroundColor3 = C_INK, Position = UDim2.fromOffset(18, -12), Size = UDim2.fromOffset(150, 24), Font = Enum.Font.GothamBold, TextSize = 13, TextColor3 = C_NAME, Text = options.name or model.Name, ZIndex = 3 })
    corner(nameTag, 8)
    nameTag.Size = UDim2.fromOffset(nameTag.TextBounds.X + 24, 24)
    local text = new("TextLabel", { Name = "Text", Parent = bubble, BackgroundTransparency = 1, Position = UDim2.fromOffset(20, 20), Size = UDim2.new(1, -40, 1, -32),
        Font = Enum.Font.GothamMedium, TextSize = 18, TextColor3 = C_INK, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, Text = "", ZIndex = 2 })
    self.bubble, self.text = bubble, text

    -- the menu side: the choices (placed menus go there too)
    local choices = new("Frame", { Name = "Choices", Parent = gui, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(MENU_X, 0.5), Size = UDim2.fromOffset(340, 10), BackgroundTransparency = 1, Visible = false })
    new("UIListLayout", { Parent = choices, Padding = UDim.new(0, 10), HorizontalAlignment = Enum.HorizontalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder })
    self.choices = choices

    self.follow = RunService.RenderStepped:Connect(function()
        if not self.head.Parent then
            self:close()
            return
        end
        local view = Workspace.CurrentCamera
        local point, onScreen = view:WorldToViewportPoint(self.head.Position + Vector3.new(0, 1.4, 0))
        local size = view.ViewportSize
        local x = math.clamp(point.X, BUBBLE_W / 2 + 16, math.max(BUBBLE_W / 2 + 16, size.X * 0.5 - BUBBLE_W / 2))
        local y = math.clamp(point.Y, bubble.AbsoluteSize.Y + 24, size.Y - 20)
        bubble.Position = UDim2.fromOffset(x, y)
        tail.Position = UDim2.fromOffset(math.clamp(point.X, x - BUBBLE_W / 2 + 30, x + BUBBLE_W / 2 - 30), y)
        tail.Visible = onScreen and bubble.Visible
    end)
    self.respawn = player.CharacterAdded:Connect(function()
        self:close()
    end)
    return self
end

-- Type a line into the bubble; returns once it's all shown
function NpcDialog:say(line)
    if not self.open then
        return
    end
    self.saying = (self.saying or 0) + 1
    local mine = self.saying
    self.bubble.Visible = true
    -- size the bubble for the whole line first, so it doesn't grow as it types
    self.text.Text = line
    self.text.MaxVisibleGraphemes = 0
    local bounds = TextService:GetTextSize(line, self.text.TextSize, self.text.Font, Vector2.new(BUBBLE_W - 40, 1000))
    local height = math.max(70, bounds.Y + 40)
    self.bubble.Size = UDim2.fromOffset(BUBBLE_W, height)
    local total = utf8.len(line) or #line
    local shown = 0
    while self.open and self.saying == mine and shown < total do
        shown = math.min(total, shown + math.max(1, math.floor(TYPE_SPEED * task.wait())))
        self.text.MaxVisibleGraphemes = shown
    end
    if self.open and self.saying == mine then
        self.text.MaxVisibleGraphemes = -1
    end
end

-- Say something and offer choices on the menu side; yields: the picked id (nil if closed)
function NpcDialog:choose(line, options)
    if not self.open then
        return nil
    end
    for _, c in ipairs(self.choices:GetChildren()) do
        if c:IsA("GuiButton") then
            c:Destroy()
        end
    end
    local hidden = {}
    for frame in pairs(self.placed) do -- (the choices take the menu side for now)
        if frame.Visible then
            hidden[frame] = true
            frame.Visible = false
        end
    end
    local picked = Instance.new("BindableEvent")
    local result = nil
    for i, option in ipairs(options) do
        local b = new("TextButton", {
            Name = "Choice_" .. tostring(option.id), Parent = self.choices, LayoutOrder = i, Size = UDim2.fromOffset(340, 52),
            BackgroundColor3 = option.primary and C_NAME or C_CARD, TextColor3 = option.primary and C_BG or C_TEXT,
            Font = Enum.Font.GothamBold, TextSize = 15, TextWrapped = true, Text = option.text, AutoButtonColor = true,
        })
        corner(b, 10)
        new("UIStroke", { Color = option.primary and C_NAME or C_STROKE, Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = b })
        b.MouseButton1Click:Connect(function()
            result = option.id
            picked:Fire()
        end)
    end
    self.choices.Size = UDim2.fromOffset(340, #options * 62)
    self.choices.Visible = false
    self.pickedEvent = picked
    task.spawn(function()
        self:say(line)
        if self.open then
            self.choices.Visible = true
        end
    end)
    picked.Event:Wait()
    self.pickedEvent = nil
    picked:Destroy()
    if self.open then
        self.choices.Visible = false
        for frame in pairs(hidden) do
            frame.Visible = true
        end
    end
    return result
end

-- A menu on the menu side while the dialog is open (put back where it was on close)
function NpcDialog:place(frame)
    if not self.open or self.placed[frame] then
        return
    end
    self.placed[frame] = { anchor = frame.AnchorPoint, position = frame.Position }
    frame.AnchorPoint = Vector2.new(0.5, 0.5)
    frame.Position = UDim2.fromScale(MENU_X, 0.5)
end

function NpcDialog:close()
    if not self.open then
        return
    end
    self.open = false
    if currentDialog == self then
        currentDialog = nil
    end
    if self.follow then
        self.follow:Disconnect()
    end
    if self.cameraKey then
        RunService:UnbindFromRenderStep(self.cameraKey)
    end
    for who in pairs(self.hidden or {}) do
        for _, d in ipairs(who:GetDescendants()) do
            if d:IsA("BasePart") or d:IsA("Decal") then
                d.LocalTransparencyModifier = 0
            end
        end
    end
    if self.respawn then
        self.respawn:Disconnect()
    end
    if self.pickedEvent then
        self.pickedEvent:Fire()
    end
    for frame, was in pairs(self.placed) do
        frame.AnchorPoint = was.anchor
        frame.Position = was.position
    end
    self.placed = {}
    if self.gui then
        self.gui:Destroy()
    end
    local camera = Workspace.CurrentCamera
    if camera then
        camera.CameraType = self.saved.type or Enum.CameraType.Custom
        camera.CameraSubject = self.saved.subject or camera.CameraSubject
        camera.FieldOfView = self.saved.fov or 70
    end
    if self.controls then
        self.controls:Enable()
    end
    setBodyHidden(false)
    if self.onClose then
        task.spawn(self.onClose)
    end
end

return NpcDialog
