--// ArenaCrowdNpcs.server.lua
-- A crowd of Roblox avatars on the stands (the ArenaOne parts named "CrowdArea"), moving with the
-- procedural crowd sound (ArenaCrowdManager):
--   * every crowd reaction (Crowd.Reacted) reaches the avatars of the sections that made it: cheers
--     and roars -> cheering, waving, jumping (big moments: jumping again and again, dancing);
--     groans, gasps and disappointment -> pointing, standing stunned;
--   * each avatar belongs to the nearest crowd section, so it backs that section's team;
--   * while the fight is on, a few avatars move all the time, more as their team's excitement
--     rises; between matches the stands idle, with the odd wave;
--   * the winner: its sections celebrate (jumps, dances), the others slump.
--
-- Stress test: Workspace attributes CrowdNpcCount (default 200; up to every spot on the stands)
-- and CrowdNpcs (false: none). Changing either rebuilds the crowd. Workspace CrowdNpcActive shows
-- how many are standing.
-- They are cheap avatars: root anchored, no physics state machine, nothing collides or is queried;
-- animations run through NpcAnimator.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ServerStorage = game:GetService("ServerStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local Crowd = require(ServerScriptService:WaitForChild("ArenaCrowdManager"))
local NpcAnimator = require(ServerScriptService:WaitForChild("NpcAnimator"))

local DEFAULT_COUNT = 200
local SPACING = 3.4 -- studs between avatars on the stands
local VARIANTS = 16 -- looks built once, then cloned
local SPAWN_BATCH = 25 -- avatars placed per frame
local ARENA_CENTER = Vector3.new(0, 0, -438)

local SKIN = {
    Color3.fromRGB(255, 220, 190), Color3.fromRGB(234, 184, 146), Color3.fromRGB(198, 134, 94),
    Color3.fromRGB(141, 85, 54), Color3.fromRGB(94, 60, 40), Color3.fromRGB(245, 205, 170),
}
local CLOTH = {
    Color3.fromRGB(30, 34, 46), Color3.fromRGB(180, 40, 50), Color3.fromRGB(40, 90, 170),
    Color3.fromRGB(230, 230, 235), Color3.fromRGB(60, 130, 80), Color3.fromRGB(240, 180, 40),
    Color3.fromRGB(110, 60, 150), Color3.fromRGB(90, 90, 95), Color3.fromRGB(200, 120, 60),
    Color3.fromRGB(0, 170, 255), Color3.fromRGB(255, 80, 80),
}

local rng = Random.new()
local templates = nil -- { { model, rootAboveFloor } }
local crowd = {} -- { model, root, home (CFrame), section, busyUntil }
local buildToken = 0

local folder = Workspace:FindFirstChild("ArenaCrowdNpcs") or Instance.new("Folder")
folder.Name = "ArenaCrowdNpcs"
folder.Parent = Workspace

local function pick(list)
    return list[rng:NextInteger(1, #list)]
end

-- ============================================================================
-- LOOKS
-- ============================================================================

local function buildTemplates()
    if templates then
        return templates
    end
    templates = {}
    local store = Instance.new("Folder")
    store.Name = "CrowdNpcTemplates"
    store.Parent = ServerStorage
    for i = 1, VARIANTS do
        local desc = Instance.new("HumanoidDescription")
        local skin = pick(SKIN)
        desc.HeadColor, desc.LeftArmColor, desc.RightArmColor = skin, skin, skin
        desc.TorsoColor = pick(CLOTH)
        local legs = pick(CLOTH)
        desc.LeftLegColor, desc.RightLegColor = legs, legs
        local ok, model = pcall(function()
            return Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
        end)
        if ok and model then
            model.Name = "CrowdNpc" .. i
            local hum = model:FindFirstChildOfClass("Humanoid")
            hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
            hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
            hum.EvaluateStateMachine = false
            hum.BreakJointsOnDeath = false
            local animate = model:FindFirstChild("Animate")
            if animate then
                animate:Destroy()
            end
            for _, part in ipairs(model:GetDescendants()) do
                if part:IsA("BasePart") then
                    part.CanCollide = false
                    part.CanTouch = false
                    part.CanQuery = false
                    part.CastShadow = false
                    part.Massless = true
                end
            end
            local root = model:FindFirstChild("HumanoidRootPart")
            root.Anchored = true
            local cf, size = model:GetBoundingBox()
            model.Parent = store
            table.insert(templates, { model = model, rootAboveFloor = root.Position.Y - (cf.Y - size.Y / 2) })
        else
            warn("[ArenaCrowdNpcs] Could not build a crowd look: " .. tostring(model))
        end
    end
    return templates
end

-- ============================================================================
-- SPOTS ON THE STANDS
-- ============================================================================

local function spots()
    local list = {}
    local arena = Workspace:FindFirstChild("argoniaonion") and Workspace.argoniaonion:FindFirstChild("ArenaOne")
    for _, part in ipairs(arena and arena:GetDescendants() or {}) do
        if part.Name == "CrowdArea" and part:IsA("BasePart") then
            local cf, s = part.CFrame, part.Size
            local ext = (cf.RightVector * s.X):Abs() + (cf.UpVector * s.Y):Abs() + (cf.LookVector * s.Z):Abs()
            local top = part.Position.Y + ext.Y / 2
            local nx, nz = math.floor((ext.X - 2) / SPACING), math.floor((ext.Z - 2) / SPACING)
            for ix = 0, nx - 1 do
                for iz = 0, nz - 1 do
                    local x = part.Position.X - ext.X / 2 + 1 + (ix + 0.5) * SPACING + rng:NextNumber(-0.6, 0.6)
                    local z = part.Position.Z - ext.Z / 2 + 1 + (iz + 0.5) * SPACING + rng:NextNumber(-0.6, 0.6)
                    table.insert(list, Vector3.new(x, top, z))
                end
            end
        end
    end
    for i = #list, 2, -1 do
        local j = rng:NextInteger(1, i)
        list[i], list[j] = list[j], list[i]
    end
    return list
end

local function nearestSection(position, sections)
    local best, bestD = 1, math.huge
    for i, s in ipairs(sections) do
        local d = (Vector3.new(s.center.X, 0, s.center.Z) - Vector3.new(position.X, 0, position.Z)).Magnitude
        if d < bestD then
            best, bestD = i, d
        end
    end
    return best
end

local function clear()
    crowd = {}
    folder:ClearAllChildren()
    Workspace:SetAttribute("CrowdNpcActive", 0)
end

local function build()
    buildToken += 1
    local token = buildToken
    clear()
    if Workspace:GetAttribute("CrowdNpcs") == false then
        return
    end
    local count = tonumber(Workspace:GetAttribute("CrowdNpcCount")) or DEFAULT_COUNT
    local looks = buildTemplates()
    if #looks == 0 then
        return
    end
    local places = spots()
    count = math.min(count, #places)
    local sections = Crowd.getSections()
    local started = os.clock()
    for i = 1, count do
        if token ~= buildToken then
            return
        end
        local look = pick(looks)
        local p = places[i]
        local npc = look.model:Clone()
        local pos = Vector3.new(p.X, p.Y + look.rootAboveFloor, p.Z)
        local home = CFrame.lookAt(pos, Vector3.new(ARENA_CENTER.X, pos.Y, ARENA_CENTER.Z))
        npc:PivotTo(home)
        npc.Parent = folder
        NpcAnimator.attach(npc)
        table.insert(crowd, {
            model = npc,
            root = npc.HumanoidRootPart,
            home = npc.HumanoidRootPart.CFrame,
            section = #sections > 0 and nearestSection(p, sections) or nil,
            busyUntil = 0,
        })
        if i % SPAWN_BATCH == 0 then
            Workspace:SetAttribute("CrowdNpcActive", #crowd)
            RunService.Heartbeat:Wait()
        end
    end
    Workspace:SetAttribute("CrowdNpcActive", #crowd)
    print(string.format("[ArenaCrowdNpcs] %d crowd avatars on the stands (%d spots) in %.1f s", #crowd, #places, os.clock() - started))
end

-- ============================================================================
-- MOVES
-- ============================================================================

local HOP_UP = TweenInfo.new(0.17, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local HOP_DOWN = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

local function hop(e, times, height)
    task.spawn(function()
        for _ = 1, times do
            if not e.model.Parent then
                return
            end
            local h = (height or 2.2) * rng:NextNumber(0.75, 1.25)
            local up = TweenService:Create(e.root, HOP_UP, { CFrame = e.home + Vector3.new(0, h, 0) })
            up:Play()
            up.Completed:Wait()
            local down = TweenService:Create(e.root, HOP_DOWN, { CFrame = e.home })
            down:Play()
            down.Completed:Wait()
            task.wait(rng:NextNumber(0.05, 0.25))
        end
    end)
end

local function isPositive(category)
    return category:find("Cheer") or category:find("Roar") or category:find("Applause") or category:find("Celebration")
end

local function isNegative(category)
    return category:find("Groan") or category:find("Gasp") or category:find("Disappointment") or category:find("Boo") or category:find("Shock")
end

-- One avatar's answer to a reaction
local function respond(e, category, major)
    local now = os.clock()
    if now < e.busyUntil then
        return
    end
    if category:find("Celebration") then
        e.busyUntil = now + 7
        hop(e, rng:NextInteger(3, 6), 2.6)
        NpcAnimator.emote(e.model, pick({ "cheer", "dance1", "dance2", "dance3", "cheer" }), 7)
    elseif isPositive(category) then
        e.busyUntil = now + (major and 3.5 or 2)
        if category:find("Applause") then
            NpcAnimator.emote(e.model, pick({ "wave", "cheer" }), 2.5)
        else
            NpcAnimator.emote(e.model, pick({ "cheer", "cheer", "wave", "point" }), major and 3 or 2)
            if major or rng:NextNumber() < 0.45 then
                hop(e, major and rng:NextInteger(1, 3) or 1, major and 2.4 or 1.6)
            end
        end
    elseif isNegative(category) then
        e.busyUntil = now + 2.5
        if category:find("Disappointment") or category:find("Groan") then
            if rng:NextNumber() < 0.4 then
                NpcAnimator.emote(e.model, "point", 2) -- (booing the call)
            else
                NpcAnimator.stopEmote(e.model)
            end
        else
            NpcAnimator.stopEmote(e.model) -- (a gasp: stunned still)
        end
    end
end

Crowd.Reacted:Connect(function(team, category, major)
    if #crowd == 0 or type(category) ~= "string" then
        return
    end
    local sections = Crowd.getSections()
    local chance = major and 0.85 or (isPositive(category) and 0.35 or 0.25)
    for _, e in ipairs(crowd) do
        local s = e.section and sections[e.section]
        if (team == nil or (s and s.team == team)) and rng:NextNumber() < chance then
            task.delay(rng:NextNumber(0, major and 0.5 or 0.8), respond, e, category, major)
        end
    end
end)

-- The stands are never quite still: during the fight more of them move as their team gets excited
task.spawn(function()
    while true do
        task.wait(1)
        if #crowd > 0 then
            local phase = Workspace:GetAttribute("CrowdPhase")
            local fighting = phase == "IN_GAME"
            local excitement = fighting and (Crowd.getState().Excitement or {}) or {}
            local sections = fighting and Crowd.getSections() or {}
            local tries = math.max(1, math.floor(#crowd * (fighting and 0.04 or 0.01)))
            for _ = 1, tries do
                local e = crowd[rng:NextInteger(1, #crowd)]
                local s = e.section and sections[e.section]
                local level = s and (excitement[s.team] or excitement.Neutral) or 0.2
                if rng:NextNumber() < (fighting and (0.3 + level) or 0.5) and os.clock() >= e.busyUntil then
                    e.busyUntil = os.clock() + 2.5
                    if fighting then
                        NpcAnimator.emote(e.model, pick({ "cheer", "point", "wave" }), 2)
                        if level > 0.6 and rng:NextNumber() < 0.5 then
                            hop(e, 1, 1.6)
                        end
                    else
                        NpcAnimator.emote(e.model, pick({ "wave", "laugh", "point" }), 2.5)
                    end
                end
            end
        end
    end
end)

Workspace:GetAttributeChangedSignal("CrowdNpcCount"):Connect(function()
    task.defer(build)
end)
Workspace:GetAttributeChangedSignal("CrowdNpcs"):Connect(function()
    task.defer(build)
end)

task.defer(build)
