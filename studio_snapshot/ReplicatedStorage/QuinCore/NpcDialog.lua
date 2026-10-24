--// NpcDialog.lua (client only)
-- Talking to an NPC: what they say in a big speech bubble over their head (typed out, only you see
-- it), the menu (what you can do with them) and the choices on the right of the screen. The camera
-- is never touched (owner, 2026-10-25): you keep your own view, your own body in it, and can move.
-- One for every NPC you deal with: the Arena Receptionist (ArenaEntry.client), and later the
-- Trainer, the Quin Specialist and the rest.
--
--   local d = NpcDialog.open(model, { name = "Receptionist", onClose = fn })  -> the dialog (closes any other)
--   d:say(text)                     -> types it into the bubble; returns once it's shown
--   d:choose(text, options)         -> says text, shows options { { id, text, primary? } } on the menu
--                                      side, yields: the picked id (nil if the dialog closed)
--   d:place(frame)                  -> puts a GUI frame (a menu) on the menu side until the dialog closes
--   d:close()                       -> menus back where they were; onClose()
--   d.open                          -> still open?
--   NpcDialog.current()             -> the dialog open now, or nil

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TextService = game:GetService("TextService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer

local NpcDialog = {}
NpcDialog.__index = NpcDialog

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

function NpcDialog.current()
    return currentDialog
end

function NpcDialog.open(model, options)
    options = options or {}
    if currentDialog then
        currentDialog:close()
    end
    local head = model and model:FindFirstChild("Head")
    if not head then
        return nil
    end
    local self = setmetatable({ open = true, model = model, head = head, placed = {}, onClose = options.onClose }, NpcDialog)
    currentDialog = self

    -- (the camera, your body and your controls are left alone: you see the NPC as you stand)
    local gui = new("ScreenGui", { Name = "NpcDialogUI", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 5, Parent = player:WaitForChild("PlayerGui") })
    self.gui = gui

    -- the bubble over the NPC's head (follows it on screen, kept off the menu side)
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
        if not onScreen then -- (they're behind you or off the edge: the bubble waits on the left)
            point = Vector3.new(BUBBLE_W / 2 + 40, size.Y * 0.4, 0)
        end
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
    if self.onClose then
        task.spawn(self.onClose)
    end
end

return NpcDialog
