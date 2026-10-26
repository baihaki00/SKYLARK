--// WardrobeClient.client.lua
-- Dress a Quin (PlayerMenu > MY QUINS > WARDROBE, or shared.OpenWardrobe(slot)): the Quin in its
-- idle on the left (drag to turn), the slots in the middle, the items of the chosen slot on the
-- right (only what fits its gender), tuck buttons for tops. SAVE keeps the outfit on the Quin
-- (remote ArenaNetwork.QuinWardrobe "set"); it wears it at every spawn. RANDOM EACH FIGHT clears
-- it: the Quin then dresses at random each spawn. The rules (a dress covers the bottom, a hat
-- swaps the hair to its hat hair, a helmet hides the hair) are QuinWardrobe.resolve's.
-- Test hook: player attribute WardrobeOpen (the slot shown).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local QuinCore = ReplicatedStorage:WaitForChild("QuinCore")
local QuinPreview = require(QuinCore:WaitForChild("QuinPreview"))
local QuinWardrobe = require(QuinCore:WaitForChild("Modules"):WaitForChild("QuinWardrobe"))
local remote = ReplicatedStorage:WaitForChild("ArenaNetwork"):WaitForChild("QuinWardrobe", 30)

local W, H = 960, 600
local C_BG = Color3.fromRGB(15, 18, 26)
local C_CARD = Color3.fromRGB(22, 27, 38)
local C_STROKE = Color3.fromRGB(38, 48, 68)
local C_AMBER = Color3.fromRGB(255, 180, 50)
local C_GREEN = Color3.fromRGB(0, 230, 120)
local C_RED = Color3.fromRGB(255, 60, 80)
local C_TEXT = Color3.fromRGB(240, 245, 255)
local C_MUTED = Color3.fromRGB(130, 145, 170)

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
    new("UICorner", { Parent = inst, CornerRadius = UDim.new(0, r) })
end

local function label(parent, props)
    props.Parent = parent
    props.BackgroundTransparency = 1
    props.Font = props.Font or Enum.Font.Gotham
    props.TextColor3 = props.TextColor3 or C_TEXT
    props.TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Left
    props.TextTruncate = props.TextTruncate or Enum.TextTruncate.AtEnd
    return new("TextLabel", props)
end

local function button(parent, text, props)
    props.Parent = parent
    props.Text = text
    props.Font = props.Font or Enum.Font.GothamBold
    props.TextSize = props.TextSize or 12
    props.TextColor3 = props.TextColor3 or C_TEXT
    props.BackgroundColor3 = props.BackgroundColor3 or C_CARD
    props.AutoButtonColor = true
    local b = new("TextButton", props)
    corner(b, 7)
    return b
end

-- ============================================================================
-- WINDOW
-- ============================================================================

local gui = new("ScreenGui", { Name = "WardrobeUI", Parent = playerGui, ResetOnSpawn = false, DisplayOrder = 80, Enabled = false, IgnoreGuiInset = true })
-- (opaque: the player menu under it showed through at 0.02)
local window = new("Frame", { Name = "Window", Parent = gui, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(W, H), BackgroundColor3 = C_BG })
corner(window, 12)
new("UIStroke", { Parent = window, Color = C_AMBER, Thickness = 1.5 })
local fitScale = new("UIScale", { Parent = window })
local function fit()
    local view = Workspace.CurrentCamera and Workspace.CurrentCamera.ViewportSize or Vector2.new(W, H)
    fitScale.Scale = math.min(1, (view.X - 40) / W, (view.Y - 40) / H)
end
fit()
if Workspace.CurrentCamera then
    Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fit)
end
local title = label(window, { Position = UDim2.fromOffset(18, 14), Size = UDim2.fromOffset(600, 20), Font = Enum.Font.GothamBold, TextSize = 16, TextColor3 = C_AMBER, Text = "WARDROBE" })
local closeButton = button(window, "X", { Name = "WardrobeClose", Position = UDim2.fromOffset(W - 44, 12), Size = UDim2.fromOffset(28, 28) })

local VIEW_W, VIEW_H = 300, H - 120
-- the backdrop is its own frame behind the preview: a UIGradient on the ViewportFrame itself
-- tints the Quin too (it made the body grey and dull)
local backdrop = new("Frame", { Name = "Backdrop", Parent = window, Position = UDim2.fromOffset(18, 50), Size = UDim2.fromOffset(VIEW_W, VIEW_H), BackgroundColor3 = Color3.new(1, 1, 1) })
corner(backdrop, 8)
new("UIGradient", { Parent = backdrop, Rotation = 90, Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, Color3.fromRGB(92, 102, 124)),
    ColorSequenceKeypoint.new(0.75, Color3.fromRGB(58, 66, 84)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(40, 46, 60)),
}) })
local view = new("ViewportFrame", { Name = "Preview", Parent = window, Position = UDim2.fromOffset(18, 50), Size = UDim2.fromOffset(VIEW_W, VIEW_H), BackgroundTransparency = 1 })
label(view, { Position = UDim2.new(0, 0, 1, -22), Size = UDim2.new(1, 0, 0, 16), TextSize = 11, TextColor3 = C_MUTED, TextXAlignment = Enum.TextXAlignment.Center, Text = "drag to turn" })

local SLOT_X, SLOT_W = 332, 170
local slotList = new("Frame", { Name = "Slots", Parent = window, Position = UDim2.fromOffset(SLOT_X, 50), Size = UDim2.fromOffset(SLOT_W, VIEW_H), BackgroundTransparency = 1 })
new("UIListLayout", { Parent = slotList, SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 4) })

local ITEM_X = SLOT_X + SLOT_W + 14
local ITEM_W = W - ITEM_X - 18
local itemsHead = label(window, { Position = UDim2.fromOffset(ITEM_X, 50), Size = UDim2.fromOffset(ITEM_W, 18), Font = Enum.Font.GothamBold, TextSize = 13, TextColor3 = C_AMBER, Text = "" })
local items = new("ScrollingFrame", { Name = "Items", Parent = window, Position = UDim2.fromOffset(ITEM_X, 74), Size = UDim2.fromOffset(ITEM_W, VIEW_H - 74), BackgroundTransparency = 1, BorderSizePixel = 0,
    ScrollBarThickness = 4, ScrollBarImageColor3 = C_STROKE, AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new() })
new("UIGridLayout", { Parent = items, SortOrder = Enum.SortOrder.LayoutOrder, CellSize = UDim2.fromOffset(math.floor((ITEM_W - 18) / 3), 40), CellPadding = UDim2.fromOffset(6, 6) })
local variantRow = new("Frame", { Name = "Variants", Parent = window, Position = UDim2.fromOffset(ITEM_X, 50 + VIEW_H - 0), Size = UDim2.fromOffset(ITEM_W, 0), BackgroundTransparency = 1 })

local status = label(window, { Position = UDim2.fromOffset(18, H - 58), Size = UDim2.fromOffset(300, 16), TextSize = 12, TextColor3 = C_MUTED, Text = "" })
local note = label(window, { Position = UDim2.fromOffset(18, H - 38), Size = UDim2.fromOffset(300, 16), TextSize = 11, TextColor3 = C_MUTED, Text = "Clothes are free while the shop is being built." })
local BW = 150
local saveButton = button(window, "SAVE", { Name = "WardrobeSave", Position = UDim2.fromOffset(W - 18 - BW, H - 58), Size = UDim2.fromOffset(BW, 40), BackgroundColor3 = C_AMBER, TextColor3 = C_BG, TextSize = 14 })
local randomEachButton = button(window, "RANDOM EACH FIGHT", { Name = "WardrobeRandomEach", Position = UDim2.fromOffset(W - 18 - BW * 2 - 8, H - 58), Size = UDim2.fromOffset(BW, 40) })
local rollButton = button(window, "ROLL A LOOK", { Name = "WardrobeRoll", Position = UDim2.fromOffset(W - 18 - BW * 3 - 16, H - 58), Size = UDim2.fromOffset(BW, 40) })
local clearButton = button(window, "UNDRESS", { Name = "WardrobeClear", Position = UDim2.fromOffset(W - 18 - BW * 4 - 24, H - 58), Size = UDim2.fromOffset(BW - 30, 40) })

-- ============================================================================
-- STATE
-- ============================================================================

local quinSlot = nil -- the roster slot being dressed
local gender = "Male"
local work = {} -- the outfit being made: [slot] = "SKU" or "SKU:V"
local savedRandom = false -- the Quin has no saved outfit (dresses at random)
local dirty = false
local cat = {}
local currentSlot = "Top"
local preview = nil
local yaw = 200

local function nameOf(entry)
    local acc, v = QuinWardrobe.lookup(entry)
    if not acc then
        return nil
    end
    local vn = QuinWardrobe.VARIANT_NAMES[v]
    return acc:GetAttribute("DisplayName") .. ((vn and vn ~= "") and (" (" .. vn .. ")") or "")
end

local function worn()
    local on = {}
    for _, acc in ipairs(QuinWardrobe.resolve(work, gender)) do
        on[acc:GetAttribute("Slot")] = true
    end
    return on
end

local drawSlots, drawItems

local function changed()
    dirty = true
    if preview then
        preview.dress(work)
    end
    status.Text = "Not saved"
    status.TextColor3 = C_AMBER
    drawSlots()
    drawItems()
end

function drawSlots()
    for _, c in ipairs(slotList:GetChildren()) do
        if c:IsA("GuiObject") then
            c:Destroy()
        end
    end
    local on = worn()
    for i, slot in ipairs(QuinWardrobe.SLOTS) do
        local count = #(cat[slot] or {})
        local entry = work[slot]
        local name = entry and nameOf(entry)
        local sel = slot == currentSlot
        local b = button(slotList, "", { Name = "Slot" .. slot, LayoutOrder = i, Size = UDim2.new(1, 0, 0, 36), BackgroundColor3 = sel and C_AMBER or C_CARD })
        label(b, { Position = UDim2.fromOffset(10, 3), Size = UDim2.new(1, -16, 0, 14), Font = Enum.Font.GothamBold, TextSize = 12, TextColor3 = sel and C_BG or (count > 0 and C_TEXT or C_MUTED), Text = slot:upper() })
        local sub = name and (on[slot] and name or (name .. "  (hidden)")) or (count > 0 and "none" or "nothing yet")
        label(b, { Position = UDim2.fromOffset(10, 18), Size = UDim2.new(1, -16, 0, 14), TextSize = 11, TextColor3 = sel and C_BG or (name and (on[slot] and Color3.fromRGB(0, 220, 255) or C_RED) or C_MUTED), Text = sub })
        b.MouseButton1Click:Connect(function()
            currentSlot = slot
            items.CanvasPosition = Vector2.zero
            drawSlots()
            drawItems()
        end)
    end
end

local function setVariantRow(item)
    for _, c in ipairs(variantRow:GetChildren()) do
        c:Destroy()
    end
    local vs = item and item.variants or {}
    if #vs < 2 then
        variantRow.Size = UDim2.fromOffset(ITEM_W, 0)
        items.Size = UDim2.fromOffset(ITEM_W, VIEW_H - 24)
        return
    end
    items.Size = UDim2.fromOffset(ITEM_W, VIEW_H - 24 - 50)
    variantRow.Position = UDim2.fromOffset(ITEM_X, 50 + VIEW_H - 40)
    variantRow.Size = UDim2.fromOffset(ITEM_W, 40)
    local _, curV = QuinWardrobe.lookup(work[currentSlot])
    label(variantRow, { Position = UDim2.fromOffset(0, 0), Size = UDim2.fromOffset(110, 40), Font = Enum.Font.GothamBold, TextSize = 12, TextColor3 = C_MUTED, Text = "WEAR IT" })
    local bw = math.floor((ITEM_W - 110 - (#vs - 1) * 6) / #vs)
    for i, v in ipairs(vs) do
        local on = v == curV
        local b = button(variantRow, (QuinWardrobe.VARIANT_NAMES[v] or v):upper(), { Name = "Variant" .. v, Position = UDim2.fromOffset(110 + (i - 1) * (bw + 6), 0), Size = UDim2.fromOffset(bw, 40),
            BackgroundColor3 = on and C_AMBER or C_CARD, TextColor3 = on and C_BG or C_TEXT })
        b.MouseButton1Click:Connect(function()
            work[currentSlot] = v == "B" and item.sku or (item.sku .. ":" .. v)
            changed()
        end)
    end
end

function drawItems()
    for _, c in ipairs(items:GetChildren()) do
        if c:IsA("GuiObject") then
            c:Destroy()
        end
    end
    local list = cat[currentSlot] or {}
    itemsHead.Text = string.format("%s  •  %d %s", currentSlot:upper(), #list, #list == 1 and "item" or "items")
    local curAcc = QuinWardrobe.lookup(work[currentSlot])
    local curSku = curAcc and curAcc:GetAttribute("SKU")
    local none = button(items, "NONE", { Name = "ItemNone", LayoutOrder = 0, BackgroundColor3 = curSku and C_CARD or C_AMBER, TextColor3 = curSku and C_MUTED or C_BG })
    none.MouseButton1Click:Connect(function()
        work[currentSlot] = nil
        changed()
    end)
    local picked = nil
    for i, item in ipairs(list) do
        local on = item.sku == curSku
        if on then
            picked = item
        end
        local b = button(items, "", { Name = "Item" .. item.sku, LayoutOrder = i, BackgroundColor3 = on and C_AMBER or C_CARD })
        label(b, { Position = UDim2.fromOffset(8, 4), Size = UDim2.new(1, -12, 0, 16), Font = Enum.Font.GothamBold, TextSize = 12, TextColor3 = on and C_BG or C_TEXT, Text = item.name })
        label(b, { Position = UDim2.fromOffset(8, 21), Size = UDim2.new(1, -12, 0, 14), TextSize = 10, TextColor3 = on and C_BG or C_MUTED,
            Text = item.sku .. (item.fit ~= "Unisex" and ("  •  " .. item.fit) or "") })
        b.MouseButton1Click:Connect(function()
            local keepV = nil -- (switching tops keeps the tuck)
            local _, curV = QuinWardrobe.lookup(work[currentSlot])
            for _, v in ipairs(item.variants) do
                if v == curV then
                    keepV = v
                end
            end
            local v = keepV or item.variants[1]
            work[currentSlot] = v == "B" and item.sku or (item.sku .. ":" .. v)
            changed()
        end)
    end
    setVariantRow(picked)
end

-- ============================================================================
-- OPEN / SAVE
-- ============================================================================

local function mountPreview()
    if preview then
        preview.destroy()
    end
    preview = QuinPreview.mount(view, { Gender = gender, Outfit = work })
    preview.setYaw(yaw)
end

local function setOpen(open)
    gui.Enabled = open
    player:SetAttribute("WardrobeOpen", open and quinSlot or nil)
    if not open and preview then
        preview.destroy()
        preview = nil
    end
end

local function open(slot)
    if not remote then
        return
    end
    local ok, good, data = pcall(function()
        return remote:InvokeServer("get", slot)
    end)
    if not (ok and good and type(data) == "table") then
        warn("[Wardrobe] " .. tostring(ok and data or good))
        return
    end
    quinSlot = slot
    gender = data.Gender or "Male"
    savedRandom = type(data.Outfit) ~= "table" or next(data.Outfit) == nil
    work = {}
    for k, v in pairs(savedRandom and {} or data.Outfit) do
        work[k] = v
    end
    dirty = false
    cat = QuinWardrobe.catalogue(gender)
    title.Text = string.format("WARDROBE  •  Quin #%s  •  %s", tostring(data.QuinId or ""):sub(3, 6), gender)
    status.Text = savedRandom and "Dresses at random each fight" or "Saved outfit"
    status.TextColor3 = C_MUTED
    currentSlot = "Top"
    yaw = 200
    setOpen(true)
    mountPreview()
    drawSlots()
    drawItems()
end

local function save(outfit)
    local ok, good, msg = pcall(function()
        return remote:InvokeServer("set", quinSlot, outfit)
    end)
    if ok and good then
        dirty = false
        savedRandom = outfit == nil
        status.Text = msg or "Saved"
        status.TextColor3 = C_GREEN
        if shared.OpenPlayerMenu then -- (the card shows the new look)
            shared.OpenPlayerMenu("MY QUINS")

        end
    else
        status.Text = tostring(ok and msg or good)
        status.TextColor3 = C_RED
    end
end

saveButton.MouseButton1Click:Connect(function()
    save(work)
end)
randomEachButton.MouseButton1Click:Connect(function()
    work = {}
    if preview then
        preview.dress(work)
    end
    drawSlots()
    drawItems()
    save(nil)
end)
rollButton.MouseButton1Click:Connect(function()
    work = QuinWardrobe.random(gender)
    changed()
end)
clearButton.MouseButton1Click:Connect(function()
    work = {}
    changed()
end)
closeButton.MouseButton1Click:Connect(function()
    setOpen(false)
end)

-- drag the Quin to turn it
local dragging, lastX = false, 0
view.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging, lastX = true, input.Position.X
    end
end)
UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging = false
    end
end)
UserInputService.InputChanged:Connect(function(input)
    if dragging and preview and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
        yaw += (input.Position.X - lastX) * 0.8
        lastX = input.Position.X
        preview.setYaw(yaw)
    end
end)

shared.OpenWardrobe = function(slot)
    task.spawn(open, slot)
end
shared.CloseWardrobe = function()
    setOpen(false)
end
