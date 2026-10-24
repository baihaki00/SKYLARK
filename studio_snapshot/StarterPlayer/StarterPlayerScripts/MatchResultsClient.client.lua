--// MatchResultsClient.client.lua
-- What your Quins did and what it paid (SkylarkPayouts, ArenaSystemOrchestrator):
--   * the STATS board on the glass of your preparation room (only yours, only on your machine):
--     the event's phase and time, then each of your Quins with its health and live performance
--     score (its MatchScore attribute), and after the match its result and pay. HIDE / STATS
--     switches it (remembered for the session);
--   * the RESULTS card when the winner is decided (ArenaNetwork.MatchResult): each Quin's score
--     part by part, its pay, the entry fee, the net and your balance.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local ArenaNetwork = ReplicatedStorage:WaitForChild("ArenaNetwork")
local StateReplication = ArenaNetwork:WaitForChild("StateReplication", 30)
local resultRemote = ArenaNetwork:WaitForChild("MatchResult", 60)

local C_BG = Color3.fromRGB(15, 18, 26)
local C_CARD = Color3.fromRGB(22, 27, 38)
local C_STROKE = Color3.fromRGB(38, 48, 68)
local C_CYAN = Color3.fromRGB(0, 220, 255)
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
    new("UICorner", { Parent = inst, CornerRadius = UDim.new(0, r or 8) })
end

local function label(parent, props)
    local t = {
        Parent = parent, BackgroundTransparency = 1, Font = Enum.Font.Gotham, TextSize = 14,
        TextColor3 = C_TEXT, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
    }
    for k, v in pairs(props) do
        t[k] = v
    end
    return new("TextLabel", t)
end

local function sc(n)
    local s = tostring(math.floor(math.abs(n)))
    s = s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
    return (n < 0 and "-" or "") .. s
end

local function signed(n)
    return (n >= 0 and "+" or "-") .. sc(math.abs(n))
end

local function temperamentText(t)
    return t == "FreeSpirit" and "Free Spirit" or (t or "")
end

-- ============================================================================
-- THE STATS BOARD ON YOUR ROOM'S GLASS
-- ============================================================================

local latest = {}
if StateReplication then
    StateReplication.OnClientEvent:Connect(function(snap)
        if type(snap) == "table" then
            latest = snap
        end
    end)
end

local lastResult = nil -- the latest MatchResult, shown on the board until the next round
local boardShown = true

local boardGui = new("SurfaceGui", {
    Name = "PrepStatsBoard", Parent = playerGui, Enabled = false, ResetOnSpawn = false,
    SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud, PixelsPerStud = 40, LightInfluence = 0,
    ZOffset = 1, ClipsDescendants = true,
})
local board = new("Frame", {
    Name = "Board", Parent = boardGui, BackgroundColor3 = C_BG, BackgroundTransparency = 0.25,
    AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 30), Size = UDim2.fromOffset(560, 380),
})
corner(board, 14)
new("UIStroke", { Parent = board, Color = C_CYAN, Thickness = 2, Transparency = 0.3 })
local boardTitle = label(board, { Position = UDim2.fromOffset(20, 14), Size = UDim2.fromOffset(400, 28), Font = Enum.Font.GothamBold, TextSize = 24, TextColor3 = C_CYAN, Text = "MY QUINS" })
local boardPhase = label(board, { Position = UDim2.fromOffset(20, 46), Size = UDim2.fromOffset(520, 22), TextSize = 18, TextColor3 = C_MUTED, Text = "" })
local hideButton = new("TextButton", {
    Name = "HideStats", Parent = board, Text = "HIDE", Font = Enum.Font.GothamBold, TextSize = 16, TextColor3 = C_TEXT,
    BackgroundColor3 = C_CARD, Position = UDim2.fromOffset(460, 14), Size = UDim2.fromOffset(84, 32),
})
corner(hideButton, 8)
local rows = {}
for i = 1, 2 do
    local y = 80 + (i - 1) * 120
    local card = new("Frame", { Parent = board, BackgroundColor3 = C_CARD, Position = UDim2.fromOffset(16, y), Size = UDim2.fromOffset(528, 110), Visible = false })
    corner(card, 10)
    local name = label(card, { Position = UDim2.fromOffset(14, 10), Size = UDim2.fromOffset(330, 26), Font = Enum.Font.GothamBold, TextSize = 20 })
    local score = label(card, { Position = UDim2.fromOffset(344, 8), Size = UDim2.fromOffset(170, 30), Font = Enum.Font.GothamBlack, TextSize = 26, TextColor3 = C_AMBER, TextXAlignment = Enum.TextXAlignment.Right })
    local info = label(card, { Position = UDim2.fromOffset(14, 40), Size = UDim2.fromOffset(500, 22), TextSize = 16, TextColor3 = C_MUTED })
    local track = new("Frame", { Parent = card, BackgroundColor3 = C_STROKE, Position = UDim2.fromOffset(14, 70), Size = UDim2.fromOffset(500, 14) })
    corner(track, 7)
    local fill = new("Frame", { Parent = track, BackgroundColor3 = C_GREEN, Size = UDim2.fromScale(1, 1) })
    corner(fill, 7)
    local pay = label(card, { Position = UDim2.fromOffset(14, 86), Size = UDim2.fromOffset(500, 20), TextSize = 15, TextColor3 = C_GREEN })
    rows[i] = { card = card, name = name, score = score, info = info, fill = fill, pay = pay }
end
local boardTotal = label(board, { Position = UDim2.fromOffset(20, 330), Size = UDim2.fromOffset(520, 34), Font = Enum.Font.GothamBold, TextSize = 20, Text = "" })

-- (hidden: only a small tab stays on the glass)
local showButton = new("TextButton", {
    Name = "ShowStats", Parent = boardGui, Text = "STATS", Font = Enum.Font.GothamBold, TextSize = 18, TextColor3 = C_CYAN,
    BackgroundColor3 = C_BG, BackgroundTransparency = 0.25, AnchorPoint = Vector2.new(0.5, 0),
    Position = UDim2.new(0.5, 0, 0, 30), Size = UDim2.fromOffset(120, 40), Visible = false,
})
corner(showButton, 10)

local function setShown(shown)
    boardShown = shown
    board.Visible = shown
    showButton.Visible = not shown
end
hideButton.MouseButton1Click:Connect(function()
    setShown(false)
end)
showButton.MouseButton1Click:Connect(function()
    setShown(true)
end)

local function myRoom()
    for _, d in ipairs(Workspace:GetDescendants()) do
        if d.Name == "PrepRoom" and d:IsA("Model") and d:GetAttribute("PrepOwnerUserId") == player.UserId then
            return d
        end
    end
    return nil
end

-- the glass face that looks into the room
local function faceInto(glass, room)
    local ground = room:FindFirstChild("PreparationRoomGround")
    local inward = ground and (ground.Position - glass.Position) * Vector3.new(1, 0, 1) or Vector3.new(math.sign(glass.Position.X), 0, 0)
    inward = inward.Magnitude > 0.01 and inward.Unit or Vector3.new(1, 0, 0)
    local best, bestDot = Enum.NormalId.Front, -2
    for _, face in ipairs(Enum.NormalId:GetEnumItems()) do
        local dot = glass.CFrame:VectorToWorldSpace(Vector3.FromNormalId(face)):Dot(inward)
        if dot > bestDot then
            best, bestDot = face, dot
        end
    end
    return best
end

local function myQuins()
    local list = {}
    local qs = Workspace:FindFirstChild("QuinServer")
    if qs then
        for _, q in ipairs(qs:GetChildren()) do
            if q:IsA("Model") and q:GetAttribute("OwnerUserId") == player.UserId and q:GetAttribute("Team") ~= "Defeated" then
                table.insert(list, q)
            end
        end
    end
    table.sort(list, function(a, b)
        return a.Name < b.Name
    end)
    return list
end

local roomCache, roomCheckedAt = nil, 0

local function updateBoard()
    if os.clock() - roomCheckedAt > 2 then
        roomCheckedAt = os.clock()
        roomCache = myRoom()
    end
    local room = roomCache
    local glass = room and room:FindFirstChild("PreparationRoomGlass")
    if not glass then
        boardGui.Enabled = false
        return
    end
    if boardGui.Adornee ~= glass then
        boardGui.Adornee = glass
        boardGui.Face = faceInto(glass, room)
    end
    boardGui.Enabled = true
    local phase = tostring(latest.Phase or Workspace:GetAttribute("ArenaPhase") or "IDLE")
    if phase == "PREPARATION_ROOM" then
        lastResult = nil -- (a new round)
    end
    boardPhase.Text = string.format("%s  •  %ds", phase:gsub("_", " "), latest.TimeRemaining or 0)

    if lastResult then
        boardTitle.Text = "RESULTS  •  " .. tostring(lastResult.Winner or "")
        for i, row in ipairs(rows) do
            local q = lastResult.Quins[i]
            row.card.Visible = q ~= nil
            if q then
                row.name.Text = string.format("Quin #%s  %s", q.Tag, temperamentText(q.Temperament))
                row.score.Text = tostring(q.Score)
                row.info.Text = string.format("%s%s  •  %d damage  •  %d KO", string.upper(q.Outcome), q.Survived and ", still standing" or "", q.Damage or 0, q.KOs or 0)
                row.info.TextColor3 = q.Outcome == "Win" and C_GREEN or (q.Outcome == "Loss" and C_RED or C_MUTED)
                row.fill.Size = UDim2.fromScale(math.clamp(q.Score / 1000, 0, 1), 1)
                row.fill.BackgroundColor3 = C_AMBER
                row.pay.Text = "Earned " .. signed(q.Pay) .. " SC" .. (q.Condition and string.format("  •  condition %d%% -> %d%%", q.ConditionBefore or 100, q.Condition) or "")
            end
        end
        boardTotal.Text = string.format("Entry -%s  •  Earned +%s  •  Net %s SC", sc(lastResult.Fee), sc(lastResult.Earned), signed(lastResult.Net))
        boardTotal.TextColor3 = lastResult.Net >= 0 and C_GREEN or C_RED
        return
    end

    boardTitle.Text = "MY QUINS"
    local mine = myQuins()
    for i, row in ipairs(rows) do
        local q = mine[i]
        local hum = q and q:FindFirstChildOfClass("Humanoid")
        row.card.Visible = q ~= nil and hum ~= nil
        if q and hum then
            local tag = (q:GetAttribute("QuinId") or "Q_????"):sub(3, 6)
            local down = hum.Health <= 0
            row.name.Text = string.format("Quin #%s  %s", tag, q:GetAttribute("Temperament") or "")
            row.score.Text = tostring(q:GetAttribute("MatchScore") or 0)
            row.info.Text = string.format("%s  •  %s  •  %d / %d", q:GetAttribute("Team") == "TeamBeta" and "Beta" or "Alpha",
                down and "DOWN" or tostring(q:GetAttribute("CurrentState") or "Idle"), math.max(0, math.floor(hum.Health)), math.floor(hum.MaxHealth))
            row.info.TextColor3 = down and C_RED or C_MUTED
            local ratio = math.clamp(hum.Health / math.max(1, hum.MaxHealth), 0, 1)
            row.fill.Size = UDim2.fromScale(ratio, 1)
            row.fill.BackgroundColor3 = ratio > 0.35 and C_GREEN or C_AMBER
            row.pay.Text = string.format("Live score (out of 1000; the win adds 100 at the end)  •  condition %d%%", q:GetAttribute("Condition") or 100)
            row.pay.TextColor3 = C_MUTED
        end
    end
    boardTotal.Text = ""
end

task.spawn(function()
    while true do
        pcall(updateBoard)
        task.wait(0.25)
    end
end)

-- ============================================================================
-- THE RESULTS CARD
-- ============================================================================

local resultsGui = new("ScreenGui", { Name = "MatchResultsUI", Parent = playerGui, ResetOnSpawn = false, DisplayOrder = 80, Enabled = false })
local card = new("Frame", {
    Name = "ResultsCard", Parent = resultsGui, BackgroundColor3 = C_BG, BackgroundTransparency = 0.04,
    AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(460, 400),
})
corner(card, 12)
new("UIStroke", { Parent = card, Color = C_AMBER, Thickness = 1.5 })
local cardTitle = label(card, { Position = UDim2.fromOffset(18, 14), Size = UDim2.fromOffset(380, 22), Font = Enum.Font.GothamBold, TextSize = 17, TextColor3 = C_AMBER, Text = "MATCH RESULTS" })
local cardSub = label(card, { Position = UDim2.fromOffset(18, 38), Size = UDim2.fromOffset(424, 16), TextSize = 12, TextColor3 = C_MUTED, Text = "" })
local closeButton = new("TextButton", { Name = "ResultsClose", Parent = card, Text = "OK", Font = Enum.Font.GothamBold, TextSize = 13, TextColor3 = C_BG, BackgroundColor3 = C_AMBER, Position = UDim2.fromOffset(18, 352), Size = UDim2.fromOffset(424, 32) })
corner(closeButton, 8)
closeButton.MouseButton1Click:Connect(function()
    resultsGui.Enabled = false
end)
local body = new("Frame", { Parent = card, BackgroundTransparency = 1, Position = UDim2.fromOffset(18, 62), Size = UDim2.fromOffset(424, 280) })

local function showResults(r)
    for _, c in ipairs(body:GetChildren()) do
        c:Destroy()
    end
    cardTitle.Text = "MATCH RESULTS  •  " .. tostring(r.Winner or "")
    cardSub.Text = tostring(r.Reason or "")
    local y = 0
    for _, q in ipairs(r.Quins) do
        local good = q.Outcome == "Win"
        label(body, { Position = UDim2.fromOffset(0, y), Size = UDim2.fromOffset(300, 18), Font = Enum.Font.GothamBold, TextSize = 14,
            Text = string.format("Quin #%s  %s  •  %s%s", q.Tag, temperamentText(q.Temperament), string.upper(q.Outcome),
                q.Condition and string.format("  •  %d%% -> %d%%", q.ConditionBefore or 100, q.Condition) or ""),
            TextColor3 = good and C_GREEN or (q.Outcome == "Loss" and C_RED or C_TEXT) })
        label(body, { Position = UDim2.fromOffset(300, y), Size = UDim2.fromOffset(124, 18), Font = Enum.Font.GothamBold, TextSize = 14,
            TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = C_AMBER, Text = string.format("%d / 1000", q.Score) })
        y += 20
        local parts = {}
        for _, p in ipairs(r.Parts or {}) do
            table.insert(parts, string.format("%s %d/%d", p.key, q.Parts[p.key] or 0, p.max))
        end
        label(body, { Position = UDim2.fromOffset(0, y), Size = UDim2.fromOffset(424, 30), TextSize = 11, TextColor3 = C_MUTED,
            TextWrapped = true, TextTruncate = Enum.TextTruncate.None, Text = table.concat(parts, "  •  ") })
        y += 32
        local lines = {}
        for _, l in ipairs(q.Lines or {}) do
            table.insert(lines, string.format("%s %s", l[1], signed(l[2])))
        end
        label(body, { Position = UDim2.fromOffset(0, y), Size = UDim2.fromOffset(424, 16), TextSize = 12, TextColor3 = C_TEXT,
            Text = table.concat(lines, "  •  ") .. string.format("   =  %s SC", signed(q.Pay)) })
        y += 26
    end
    y += 6
    label(body, { Position = UDim2.fromOffset(0, y), Size = UDim2.fromOffset(424, 18), TextSize = 13,
        Text = string.format("Entry  -%s SC     Earned  +%s SC", sc(r.Fee), sc(r.Earned)) })
    y += 22
    label(body, { Position = UDim2.fromOffset(0, y), Size = UDim2.fromOffset(424, 24), Font = Enum.Font.GothamBlack, TextSize = 20,
        TextColor3 = r.Net >= 0 and C_GREEN or C_RED, Text = string.format("NET %s SC", signed(r.Net)) })
    y += 28
    label(body, { Position = UDim2.fromOffset(0, y), Size = UDim2.fromOffset(424, 16), TextSize = 12, TextColor3 = C_MUTED,
        Text = string.format("Balance %s SC", sc(r.Balance or 0)) })
    resultsGui.Enabled = true
end

if resultRemote then
    resultRemote.OnClientEvent:Connect(function(r)
        if type(r) == "table" and type(r.Quins) == "table" then
            lastResult = r
            showResults(r)
        end
    end)
end
