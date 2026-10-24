--// MatchResultsClient.client.lua
-- What your Quins did and what it paid (SkylarkPayouts, ArenaSystemOrchestrator):
--   * the HUD on the glass of your preparation room (only yours, only on your machine), down its
--     right side: the phase and time, MY QUINS (health, condition, live MatchScore; after the match
--     its result and pay), who is still standing, your round's score and pay, and a feed of what
--     happens (KOs, knockdowns, fighters down, the pay). HIDE / HUD switches it;
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

local lastResult = nil -- the latest MatchResult, shown on the HUD until the next round
local hudShown = true

-- The glass is 38 x 15 studs: 1520 x 600 here. Everything hugs the right edge, the left stays clear
-- for watching the fight. Panels (owner's sketch): the phase chip, MY QUINS, standing, my score,
-- and the feed along the bottom.
local boardGui = new("SurfaceGui", {
    Name = "PrepStatsBoard", Parent = playerGui, Enabled = false, ResetOnSpawn = false,
    SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud, PixelsPerStud = 40, LightInfluence = 0,
    ZOffset = 1, ClipsDescendants = true,
})
local hud = new("Frame", { Name = "Board", Parent = boardGui, BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) })

local function bracket(parent)
    -- holographic corner brackets
    for _, c in ipairs({ { 0, 0 }, { 1, 0 }, { 0, 1 }, { 1, 1 } }) do
        local ax, ay = c[1], c[2]
        new("Frame", { Parent = parent, BorderSizePixel = 0, BackgroundColor3 = C_CYAN, AnchorPoint = Vector2.new(ax, ay),
            Position = UDim2.fromScale(ax, ay), Size = UDim2.fromOffset(18, 3) })
        new("Frame", { Parent = parent, BorderSizePixel = 0, BackgroundColor3 = C_CYAN, AnchorPoint = Vector2.new(ax, ay),
            Position = UDim2.fromScale(ax, ay), Size = UDim2.fromOffset(3, 18) })
    end
end

-- right: offset from the glass's right edge; the panel's home is kept for its slide-in
local function panel(name, right, y, w, h, header)
    local p = new("Frame", {
        Name = name, Parent = hud, BackgroundColor3 = C_BG, BackgroundTransparency = 0.5, BorderSizePixel = 0,
        AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -right, 0, y), Size = UDim2.fromOffset(w, h),
    })
    corner(p, 4)
    new("UIStroke", { Parent = p, Color = C_CYAN, Thickness = 1.5, Transparency = 0.55 })
    bracket(p)
    if header then
        label(p, { Name = "Header", Position = UDim2.fromOffset(16, 8), Size = UDim2.fromOffset(w - 32, 18), Font = Enum.Font.GothamBold,
            TextSize = 14, TextColor3 = C_CYAN, TextTransparency = 0.15, Text = header })
    end
    p:SetAttribute("Home", p.Position)
    return p
end

-- 1. the phase chip (top, left of MY QUINS)
local chip = panel("PhaseChip", 410, 24, 240, 84)
local chipPhase = label(chip, { Position = UDim2.fromOffset(16, 10), Size = UDim2.fromOffset(150, 18), Font = Enum.Font.GothamBold, TextSize = 14, TextColor3 = C_CYAN })
local chipTime = label(chip, { Position = UDim2.fromOffset(16, 30), Size = UDim2.fromOffset(150, 44), Font = Enum.Font.GothamBlack, TextSize = 38 })
local hideButton = new("TextButton", {
    Name = "HideStats", Parent = chip, Text = "HIDE", Font = Enum.Font.GothamBold, TextSize = 13, TextColor3 = C_TEXT,
    BackgroundColor3 = C_CARD, BackgroundTransparency = 0.3, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 12), Size = UDim2.fromOffset(58, 26),
})
corner(hideButton, 4)

-- 2. MY QUINS (the big one)
local quinsPanel = panel("MyQuins", 24, 24, 370, 236, "MY QUINS")
local rows = {}
for i = 1, 2 do
    local y = 34 + (i - 1) * 100
    local card = new("Frame", { Parent = quinsPanel, BackgroundTransparency = 1, Position = UDim2.fromOffset(16, y), Size = UDim2.fromOffset(338, 92), Visible = false })
    local name = label(card, { Position = UDim2.fromOffset(0, 0), Size = UDim2.fromOffset(240, 24), Font = Enum.Font.GothamBold, TextSize = 19 })
    local score = label(card, { Position = UDim2.fromOffset(230, 0), Size = UDim2.fromOffset(108, 26), Font = Enum.Font.GothamBlack, TextSize = 24, TextColor3 = C_AMBER, TextXAlignment = Enum.TextXAlignment.Right })
    local info = label(card, { Position = UDim2.fromOffset(0, 26), Size = UDim2.fromOffset(338, 20), TextSize = 14, TextColor3 = C_MUTED })
    local track = new("Frame", { Parent = card, BackgroundColor3 = C_STROKE, BackgroundTransparency = 0.3, BorderSizePixel = 0, Position = UDim2.fromOffset(0, 52), Size = UDim2.fromOffset(338, 10) })
    local fill = new("Frame", { Parent = track, BackgroundColor3 = C_GREEN, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1) })
    -- condition: a thin second bar
    local condTrack = new("Frame", { Parent = card, BackgroundColor3 = C_STROKE, BackgroundTransparency = 0.3, BorderSizePixel = 0, Position = UDim2.fromOffset(0, 66), Size = UDim2.fromOffset(338, 4) })
    local condFill = new("Frame", { Parent = condTrack, BackgroundColor3 = C_CYAN, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1) })
    local pay = label(card, { Position = UDim2.fromOffset(0, 72), Size = UDim2.fromOffset(338, 18), TextSize = 13, TextColor3 = C_MUTED })
    rows[i] = { card = card, name = name, score = score, info = info, fill = fill, condFill = condFill, pay = pay }
end
local noQuins = label(quinsPanel, { Position = UDim2.fromOffset(16, 40), Size = UDim2.fromOffset(338, 20), TextSize = 14, TextColor3 = C_MUTED, Text = "" })

-- 3. standing (Alpha vs Beta)
local standPanel = panel("Standing", 24, 276, 290, 78, "STANDING")
local standText = label(standPanel, { Position = UDim2.fromOffset(16, 30), Size = UDim2.fromOffset(258, 38), Font = Enum.Font.GothamBlack, TextSize = 24, RichText = true, TextTruncate = Enum.TextTruncate.None })

-- 4. my score and pay
local scorePanel = panel("MyScore", 24, 370, 290, 78, "MY ROUND")
local scoreText = label(scorePanel, { Position = UDim2.fromOffset(16, 28), Size = UDim2.fromOffset(258, 26), Font = Enum.Font.GothamBold, TextSize = 20 })
local scoreSub = label(scorePanel, { Position = UDim2.fromOffset(16, 54), Size = UDim2.fromOffset(258, 18), TextSize = 13, TextColor3 = C_MUTED })

-- 5. the feed (bottom, wide): newest at the bottom, each fades after FEED_LIFE
local FEED_LIFE, FEED_MAX = 6, 4
local feed = new("Frame", {
    Name = "Feed", Parent = hud, BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 1),
    Position = UDim2.new(1, -24, 1, -20), Size = UDim2.fromOffset(640, 4 * 34),
})
new("UIListLayout", { Parent = feed, Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder, VerticalAlignment = Enum.VerticalAlignment.Bottom, HorizontalAlignment = Enum.HorizontalAlignment.Right })

local TweenService = game:GetService("TweenService")
local feedOrder = 0

local function notify(text, color)
    feedOrder += 1
    local items = {}
    for _, c in ipairs(feed:GetChildren()) do
        if c:IsA("Frame") then
            table.insert(items, c)
        end
    end
    table.sort(items, function(a, b)
        return a.LayoutOrder < b.LayoutOrder
    end)
    for i = 1, #items - FEED_MAX + 1 do
        items[i]:Destroy()
    end
    local item = new("Frame", { Name = "Note" .. feedOrder, Parent = feed, LayoutOrder = feedOrder, BackgroundColor3 = C_BG, BackgroundTransparency = 0.45, BorderSizePixel = 0, Size = UDim2.fromOffset(640, 30) })
    corner(item, 3)
    new("Frame", { Parent = item, BorderSizePixel = 0, BackgroundColor3 = color or C_CYAN, Size = UDim2.fromOffset(4, 30) })
    local t = label(item, { Position = UDim2.fromOffset(16, 0), Size = UDim2.fromOffset(616, 30), TextSize = 16, TextColor3 = color or C_TEXT, Text = text, TextTransparency = 1 })
    TweenService:Create(t, TweenInfo.new(0.25), { TextTransparency = 0 }):Play()
    task.delay(FEED_LIFE, function()
        if item.Parent then
            TweenService:Create(item, TweenInfo.new(0.6), { BackgroundTransparency = 1 }):Play()
            TweenService:Create(t, TweenInfo.new(0.6), { TextTransparency = 1 }):Play()
            task.wait(0.7)
            item:Destroy()
        end
    end)
end

-- (hidden: only a small tab stays on the glass)
local showButton = new("TextButton", {
    Name = "ShowStats", Parent = boardGui, Text = "HUD", Font = Enum.Font.GothamBold, TextSize = 16, TextColor3 = C_CYAN,
    BackgroundColor3 = C_BG, BackgroundTransparency = 0.4, AnchorPoint = Vector2.new(1, 0),
    Position = UDim2.new(1, -24, 0, 24), Size = UDim2.fromOffset(90, 36), Visible = false,
})
corner(showButton, 4)

-- panels slide in from the right
local function slideIn()
    for i, p in ipairs({ chip, quinsPanel, standPanel, scorePanel }) do
        local home = p:GetAttribute("Home")
        p.Position = home + UDim2.fromOffset(60, 0)
        TweenService:Create(p, TweenInfo.new(0.35 + i * 0.06, Enum.EasingStyle.Quint), { Position = home }):Play()
    end
end

local function setShown(shown)
    hudShown = shown
    hud.Visible = shown
    showButton.Visible = not shown
    if shown then
        slideIn()
    end
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

local function fighters()
    local list = {}
    local qs = Workspace:FindFirstChild("QuinServer")
    if qs then
        for _, q in ipairs(qs:GetChildren()) do
            if q:IsA("Model") and q:FindFirstChildOfClass("Humanoid") then
                table.insert(list, q)
            end
        end
    end
    return list
end

local function myQuins()
    local list = {}
    for _, q in ipairs(fighters()) do
        if q:GetAttribute("OwnerUserId") == player.UserId and q:GetAttribute("Team") ~= "Defeated" then
            table.insert(list, q)
        end
    end
    table.sort(list, function(a, b)
        return a.Name < b.Name
    end)
    return list
end

local function tagOf(q)
    return (q:GetAttribute("QuinId") or "Q_????"):sub(3, 6)
end

-- what changed since last look: the feed's stories
local seen = {} -- [model] = { alive, kills, knocked, knockNoteAt }
local KNOCK_NOTE_GAP = 10 -- (knockdowns are frequent: one note per Quin per this many seconds)
local function watchFeed()
    for _, q in ipairs(fighters()) do
        local hum = q:FindFirstChildOfClass("Humanoid")
        local mine = q:GetAttribute("OwnerUserId") == player.UserId
        local alive = hum.Health > 0 and q:GetAttribute("Team") ~= "Defeated"
        local kills = q:GetAttribute("Match_Kills") or 0
        local knocked = q:GetAttribute("Match_KnockedDown") or 0
        local s = seen[q]
        if s then
            if mine and kills > s.kills then
                notify(string.format("KO  •  Quin #%s took one out", tagOf(q)), C_GREEN)
            end
            if mine and knocked > s.knocked and alive and os.clock() - (s.knockNoteAt or -99) > KNOCK_NOTE_GAP then
                s.knockNoteAt = os.clock()
                notify(string.format("Quin #%s knocked down", tagOf(q)), C_AMBER)
            end
            if s.alive and not alive then
                if mine then
                    notify(string.format("Quin #%s is down", tagOf(q)), C_RED)
                else
                    local side = q:GetAttribute("Team") == "TeamBeta" and "Beta" or (q:GetAttribute("Team") == "TeamAlpha" and "Alpha" or "")
                    notify(string.format("%s lost a fighter", side ~= "" and side or "A side"), C_MUTED)
                end
            end
        end
        seen[q] = { alive = alive, kills = kills, knocked = knocked, knockNoteAt = s and s.knockNoteAt }
    end
    for q in pairs(seen) do
        if not q.Parent then
            seen[q] = nil
        end
    end
end

local roomCache, roomCheckedAt = nil, 0
local lastPhase = nil

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
    local first = not boardGui.Enabled
    boardGui.Enabled = true
    if first and hudShown then
        slideIn()
    end
    local phase = tostring(latest.Phase or Workspace:GetAttribute("ArenaPhase") or "IDLE")
    if phase ~= lastPhase then
        if phase == "PREPARATION_ROOM" then
            lastResult = nil -- (a new round)
        end
        if phase == "IN_GAME" then
            notify("The fight is on", C_CYAN)
        end
        lastPhase = phase
    end
    local left = math.floor(math.max(0, latest.TimeRemaining or 0))
    chipPhase.Text = (phase:gsub("_", " "))
    chipTime.Text = string.format("%d:%02d", left // 60, left % 60)
    if phase == "IN_GAME" then
        watchFeed()
    end

    -- standing
    local alpha, beta = 0, 0
    for _, q in ipairs(fighters()) do
        local hum = q:FindFirstChildOfClass("Humanoid")
        if hum.Health > 0 then
            if q:GetAttribute("Team") == "TeamAlpha" then
                alpha += 1
            elseif q:GetAttribute("Team") == "TeamBeta" then
                beta += 1
            end
        end
    end
    standText.Text = string.format('<font color="#00DCFF">ALPHA %d</font>  <font color="#828FAA">vs</font>  <font color="#FFB432">BETA %d</font>', alpha, beta)

    if lastResult then
        quinsPanel.Header.Text = "RESULTS  •  " .. tostring(lastResult.Winner or "")
        noQuins.Text = ""
        for i, row in ipairs(rows) do
            local q = lastResult.Quins[i]
            row.card.Visible = q ~= nil
            if q then
                row.name.Text = string.format("#%s  %s", q.Tag, temperamentText(q.Temperament))
                row.score.Text = tostring(q.Score)
                row.info.Text = string.format("%s%s  •  %d dmg  •  %d KO", string.upper(q.Outcome), q.Survived and ", standing" or "", q.Damage or 0, q.KOs or 0)
                row.info.TextColor3 = q.Outcome == "Win" and C_GREEN or (q.Outcome == "Loss" and C_RED or C_MUTED)
                row.fill.Size = UDim2.fromScale(math.clamp(q.Score / 1000, 0, 1), 1)
                row.fill.BackgroundColor3 = C_AMBER
                row.condFill.Size = UDim2.fromScale(math.clamp((q.Condition or 100) / 100, 0, 1), 1)
                row.pay.Text = string.format("Earned %s SC  •  condition %d%% -> %d%%", signed(q.Pay), q.ConditionBefore or 100, q.Condition or 100)
                row.pay.TextColor3 = C_MUTED
            end
        end
        scorePanel.Header.Text = "MY ROUND"
        scoreText.Text = string.format("NET %s SC", signed(lastResult.Net))
        scoreText.TextColor3 = lastResult.Net >= 0 and C_GREEN or C_RED
        scoreSub.Text = string.format("Entry -%s  •  Earned +%s  •  Balance %s", sc(lastResult.Fee), sc(lastResult.Earned), sc(lastResult.Balance or 0))
        return
    end

    quinsPanel.Header.Text = "MY QUINS"
    local mine = myQuins()
    local total = 0
    noQuins.Text = #mine == 0 and "None of your Quins on the field." or ""
    for i, row in ipairs(rows) do
        local q = mine[i]
        local hum = q and q:FindFirstChildOfClass("Humanoid")
        row.card.Visible = q ~= nil and hum ~= nil
        if q and hum then
            local down = hum.Health <= 0
            local score = q:GetAttribute("MatchScore") or 0
            total += score
            row.name.Text = string.format("#%s  %s", tagOf(q), q:GetAttribute("Temperament") or "")
            row.score.Text = tostring(score)
            row.info.Text = string.format("%s  •  %s  •  %d / %d", q:GetAttribute("Team") == "TeamBeta" and "Beta" or "Alpha",
                down and "DOWN" or tostring(q:GetAttribute("CurrentState") or "Idle"), math.max(0, math.floor(hum.Health)), math.floor(hum.MaxHealth))
            row.info.TextColor3 = down and C_RED or C_MUTED
            local ratio = math.clamp(hum.Health / math.max(1, hum.MaxHealth), 0, 1)
            row.fill.Size = UDim2.fromScale(ratio, 1)
            row.fill.BackgroundColor3 = ratio > 0.35 and C_GREEN or C_AMBER
            local cond = q:GetAttribute("Condition") or 100
            row.condFill.Size = UDim2.fromScale(math.clamp(cond / 100, 0, 1), 1)
            row.pay.Text = string.format("Condition %d%%  •  live score out of 1000", cond)
            row.pay.TextColor3 = C_MUTED
        end
    end
    scoreText.Text = string.format("Score %d", total)
    scoreText.TextColor3 = C_AMBER
    -- (an estimate: taking part + performance; win and still-standing bonuses come at the end)
    scoreSub.Text = #mine > 0 and string.format("About +%d SC so far, before bonuses", #mine * 30 + math.floor(total * 0.2)) or ""
end

-- the result lands: the feed tells the pay
local function hudResult(r)
    notify(string.format("%s wins  •  %s", tostring(r.Winner or ""), tostring(r.Reason or "")), C_CYAN)
    for _, q in ipairs(r.Quins) do
        notify(string.format("Quin #%s %s  •  score %d  •  %s SC", q.Tag, string.upper(q.Outcome), q.Score, signed(q.Pay)),
            q.Outcome == "Win" and C_GREEN or C_AMBER)
    end
    notify(string.format("Net %s SC", signed(r.Net)), r.Net >= 0 and C_GREEN or C_RED)
end

task.spawn(function()
    while true do
        local ok, err = pcall(updateBoard)
        if not ok then
            warn("[MatchResultsClient] " .. tostring(err))
        end
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
            pcall(hudResult, r)
        end
    end)
end
