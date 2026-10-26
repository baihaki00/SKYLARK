--// QuinWardrobePacer.client.lua (was QuinWardrobeLOD)
-- Every Quin wears its clothes from start to finish (owner, 2026-10-26: no undressing far Quins).
-- What this script does is the "buffering": it builds the clothes out of sight, then shows each
-- Quin fully dressed at once, so nobody is seen half-wrapped or flickering at the match start.
--   - a worn item arrives with its wrap on and is switched off (and hidden) here at once, before
--     anything is built (a wrap the SERVER sent off and this client switched on was often never
--     drawn, so the server always sends it on);
--   - QUINS_PER_TICK Quins a tick, nearest the camera first (the player's own Quin first of all),
--     get their wraps switched on while still hidden (a Quin's wraps are rebuilt whenever one of
--     its items switches on, so a whole Quin at a time);
--   - REVEAL seconds later, its clothes are shown.
-- Benchmark (2026-10-26, Studio, 16v16, fixed wide view): wraps are the client's biggest cost,
-- ~14 ms of render CPU a frame for 32 dressed Quins (all wraps off 74-78 fps, on 28-34). The real
-- fix is clothes baked as skinned meshes (no wraps at all): see CLOTHING_PIPELINE.md section 15.
-- Workspace attribute WardrobePacerOff = true: everything switched on at once, nothing hidden
-- (for comparisons). Readout: player attribute WardrobePacerStats = "shown/building/waiting".

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer

local QUINS_PER_TICK = 2
local TICK = 0.25
local REVEAL = 0.75 -- seconds a Quin's clothes build out of sight
local TAG = "QuinWear"

-- (plain tables, swept each tick: a weak table keyed by Instances loses entries while the
-- Instances still exist - their Lua handles are collected)
local built = {} -- [accessory] = true once its wrap is switched on here
local revealAt = {} -- [model] = os.clock() when its clothes are shown
local shownAt = {} -- [model] = true once shown

local function quins()
    local list = {}
    for _, name in ipairs({ "QuinServer", "PlayerCostumes" }) do
        local folder = Workspace:FindFirstChild(name)
        if folder then
            for _, m in ipairs(folder:GetChildren()) do
                if m:IsA("Model") and m:GetAttribute("Wearing") ~= nil then
                    table.insert(list, m)
                end
            end
        end
    end
    return list
end

local function items(m)
    local list = {}
    for _, acc in ipairs(m:GetChildren()) do
        if acc:IsA("Accessory") and acc:GetAttribute(TAG) then
            table.insert(list, acc)
        end
    end
    return list
end

local function setVisible(acc, visible)
    for _, d in ipairs(acc:GetDescendants()) do
        if d:IsA("BasePart") then
            d.LocalTransparencyModifier = visible and 0 or 1
        end
    end
end

-- switch on every wrap of this Quin not yet on (hidden); true if any was
local function build(m)
    local any = false
    for _, acc in ipairs(items(m)) do
        if not built[acc] then
            built[acc] = true
            any = true
            for _, d in ipairs(acc:GetDescendants()) do
                if d:IsA("WrapLayer") then
                    d.Enabled = true
                end
            end
        end
    end
    return any
end

local function tick()
    for acc in pairs(built) do
        if not acc.Parent then
            built[acc] = nil
        end
    end
    for m in pairs(revealAt) do
        if not m.Parent then
            revealAt[m] = nil
            shownAt[m] = nil
        end
    end
    local camera = Workspace.CurrentCamera
    local eye = camera and camera.CFrame.Position or Vector3.zero
    local all = Workspace:GetAttribute("WardrobePacerOff")
    local rate = all and math.huge or QUINS_PER_TICK
    local now = os.clock()

    local ranked = {}
    for _, m in ipairs(quins()) do
        local root = m.PrimaryPart or m:FindFirstChild("HumanoidRootPart")
        local d = root and (root.Position - eye).Magnitude or math.huge
        if m:GetAttribute("IsCostume") then
            d = -1 -- (the player's own Quin first)
        end
        table.insert(ranked, { m = m, d = d })
    end
    table.sort(ranked, function(a, b)
        return a.d < b.d
    end)

    local nShown, nBuilding, nWaiting = 0, 0, 0
    for _, e in ipairs(ranked) do
        local m = e.m
        local pending = false
        for _, acc in ipairs(items(m)) do
            if not built[acc] then
                pending = true
                break
            end
        end
        if pending then
            if rate > 0 then
                rate -= 1
                build(m)
                revealAt[m] = now + (all and 0 or REVEAL)
                shownAt[m] = nil
            else
                nWaiting += 1
            end
        end
        if revealAt[m] and not shownAt[m] then
            if now >= revealAt[m] then
                for _, acc in ipairs(items(m)) do
                    setVisible(acc, true)
                end
                shownAt[m] = true
            else
                nBuilding += 1
            end
        end
        if shownAt[m] then
            nShown += 1
        end
    end
    player:SetAttribute("WardrobePacerStats", ("%d/%d/%d"):format(nShown, nBuilding, nWaiting))
end

-- an item arrives: its wrap off and hidden until the tick builds its Quin
local function arrived(d)
    local acc = d:FindFirstAncestorOfClass("Accessory")
    if not (acc and acc:GetAttribute(TAG)) or built[acc] then
        return
    end
    if d:IsA("BasePart") then
        d.LocalTransparencyModifier = 1
    elseif d:IsA("WrapLayer") then
        d.Enabled = false
    end
    local m = acc.Parent
    if m and shownAt[m] then
        shownAt[m] = nil -- (a new item on a shown Quin: build and reveal it again)
    end
end

local function watch(folder)
    if folder:IsA("Folder") and (folder.Name == "QuinServer" or folder.Name == "PlayerCostumes") then
        folder.DescendantAdded:Connect(arrived)
        for _, d in ipairs(folder:GetDescendants()) do
            arrived(d)
        end
    end
end
Workspace.ChildAdded:Connect(watch)
for _, c in ipairs(Workspace:GetChildren()) do
    watch(c)
end

while true do
    local ok, err = pcall(tick)
    if not ok then
        warn("[QuinWardrobePacer] " .. tostring(err))
    end
    task.wait(TICK)
end
