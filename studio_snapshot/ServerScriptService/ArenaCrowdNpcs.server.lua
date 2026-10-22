--// ArenaCrowdNpcs.server.lua
-- The NPC crowd on the stands (the ArenaOne parts named "CrowdArea": the bench rows), the server's
-- half. The avatars live only on each player's machine (StarterPlayerScripts.ArenaCrowdClient):
-- the server builds the looks once (ReplicatedStorage.CrowdNpcTemplates), lays out the stands
-- (where each avatar stands, which look, which crowd section, which bench row) and passes on what
-- the procedural crowd (ArenaCrowdManager) does, so a crowd of thousands costs the server nothing.
--
-- Looks: real Roblox outfits mixed (a pool of dressed users' avatar descriptions; each look takes
-- its shirt, pants, hair, hat, glasses, face and so on from different users, on a random skin,
-- at its own height), so no two look alike; plain coloured ones stand in if the avatar service
-- cannot be reached. Clothes are also painted on (a texture that fails to load leaves no one bare);
-- the claw-shaped default hands become plain blocks (AvatarTidy). Every look is rebuilt with classic joints:
-- Roblox's avatars join limbs and accessories with physics constraints (AnimationConstraint,
-- RigidConstraint) that wake the solver for every limb whenever a body moves; Motor6Ds and Welds
-- keep each avatar one rigid anchored body. Layered clothing needs those constraints and is left off.
--
--   Remote ArenaNetwork.CrowdNpcs (server -> clients):
--     "layout", version                      -- the stands changed: ask for the layout again
--     "react", team, category, major, teams  -- a crowd reaction (teams: each section's team)
--     "mood", excitement, teams, chantTeam   -- once a second while the fight is on
--     "wave", startServerTime, startAngle, degreesPerSecond -- a Mexican wave round the stands
--   RemoteFunction ArenaNetwork.CrowdNpcLayout -> version, { {x, y, z, look, section, axis, from, to}, ... }
--     (axis 1 = the bench row runs along X, 3 = along Z; from/to = the row's ends on that axis)
--
-- Stress test: Workspace attributes CrowdNpcCount (default 1000; up to every spot on the stands)
-- and CrowdNpcs (false: none). Changing either relays the stands out.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Crowd = require(ServerScriptService:WaitForChild("ArenaCrowdManager"))
local AvatarTidy = require(ServerScriptService:WaitForChild("AvatarTidy"))

local DEFAULT_COUNT = 1000
local SPACING = 3.4 -- studs between avatars on the stands
local LOOKS = 90 -- different avatars
local LOOK_WORKERS = 12 -- avatar lookups at once
local LOOK_ATTEMPTS = 1500 -- random users tried at most (most are undressed or gone)
local RARE_ACCESSORIES = { "hook" } -- looks wearing these come up rarely (owner: the pirate hook hand)
local RARE_WEIGHT = 0.12
local USER_ID_RANGE = { 100000, 1500000000 } -- (older accounts: more of them dressed up)
local STARTER_KEEP = 0.2 -- share of starter-only users (hair, nothing else) kept in the pool
local MAX_HEIGHT = 9 -- studs (a look taller than this is a giant accessory: left out)
local SHOES = Color3.fromRGB(35, 32, 30)

local SKIN = {
    Color3.fromRGB(255, 220, 190), Color3.fromRGB(234, 184, 146), Color3.fromRGB(198, 134, 94),
    Color3.fromRGB(141, 85, 54), Color3.fromRGB(94, 60, 40), Color3.fromRGB(245, 205, 170),
}
local CLOTH = {
    Color3.fromRGB(30, 34, 46), Color3.fromRGB(180, 40, 50), Color3.fromRGB(40, 90, 170),
    Color3.fromRGB(230, 230, 235), Color3.fromRGB(60, 130, 80), Color3.fromRGB(240, 180, 40),
    Color3.fromRGB(110, 60, 150), Color3.fromRGB(90, 90, 95), Color3.fromRGB(200, 120, 60),
}

local rng = Random.new()
local templates = {}
local layout = {}
local version = 0

local net = ReplicatedStorage:FindFirstChild("ArenaNetwork") or Instance.new("Folder")
net.Name = "ArenaNetwork"
net.Parent = ReplicatedStorage
local remote = net:FindFirstChild("CrowdNpcs") or Instance.new("RemoteEvent")
remote.Name = "CrowdNpcs"
remote.Parent = net
local layoutFunction = net:FindFirstChild("CrowdNpcLayout") or Instance.new("RemoteFunction")
layoutFunction.Name = "CrowdNpcLayout"
layoutFunction.Parent = net

local function pick(list)
    return list[rng:NextInteger(1, #list)]
end

-- ============================================================================
-- LOOKS
-- ============================================================================

-- Classic joints, no physics: AnimationConstraint -> Motor6D, RigidConstraint -> Weld
local function rebuildJoints(model)
    for _, accessory in ipairs(model:GetChildren()) do
        if accessory:IsA("Accessory") and accessory:FindFirstChildWhichIsA("WrapLayer", true) then
            accessory:Destroy() -- (layered clothing)
        end
    end
    for _, joint in ipairs(model:GetDescendants()) do
        local a0 = (joint:IsA("AnimationConstraint") or joint:IsA("RigidConstraint")) and joint.Attachment0
        local a1 = a0 and joint.Attachment1
        if a0 and a1 and a0.Parent and a1.Parent then
            local j = Instance.new(joint:IsA("AnimationConstraint") and "Motor6D" or "Weld")
            j.Name = joint.Name
            j.Part0 = a0.Parent
            j.Part1 = a1.Parent
            j.C0 = a0.CFrame
            j.C1 = a1.CFrame
            j.Parent = joint.Parent
        end
    end
    for _, d in ipairs(model:GetDescendants()) do
        if d:IsA("Constraint") or d:IsA("NoCollisionConstraint") or d:IsA("WrapTarget") or d:IsA("WrapLayer")
            or d:IsA("FaceControls") then
            d:Destroy()
        end
    end
end

-- Clothes painted on: the torso and upper arms in a shirt colour, the legs in a pants colour, dark
-- shoes. A classic shirt or pants texture still shows over them; one that fails to load (deleted
-- or moderated clothing) no longer leaves the avatar standing there bare.
local CLOTH_ZONE = {
    UpperTorso = "shirt", LowerTorso = "pants", LeftUpperArm = "shirt", RightUpperArm = "shirt",
    LeftUpperLeg = "pants", RightUpperLeg = "pants", LeftLowerLeg = "pants", RightLowerLeg = "pants",
    LeftFoot = "shoes", RightFoot = "shoes",
}
local function paintClothes(model)
    local colors = { shirt = pick(CLOTH), pants = pick(CLOTH), shoes = SHOES }
    for name, zone in pairs(CLOTH_ZONE) do
        local part = model:FindFirstChild(name)
        if part and part:IsA("BasePart") then
            part.Color = colors[zone]
        end
    end
end

local function finishLook(model, index, scale)
    model.Name = "CrowdLook" .. index
    local root = model:FindFirstChild("HumanoidRootPart")
    rebuildJoints(model)
    AvatarTidy.blockHands(model)
    paintClothes(model)
    if scale and math.abs(scale - 1) > 0.01 then
        model:ScaleTo(scale) -- (each look its own height: the description's scales barely showed)
    end
    local cf, size = model:GetBoundingBox()
    -- (the floor under the feet: the legs' bottom, not a hat's brim)
    local lowest = math.huge
    for _, name in ipairs({ "LeftFoot", "RightFoot" }) do
        local foot = model:FindFirstChild(name)
        if foot then
            lowest = math.min(lowest, foot.Position.Y - foot.Size.Y / 2)
        end
    end
    if lowest == math.huge then
        lowest = cf.Y - size.Y / 2
    end
    model:SetAttribute("RootAboveFloor", root.Position.Y - lowest)
    model:SetAttribute("Height", size.Y)
    for _, d in ipairs(model:GetDescendants()) do
        if d:IsA("BasePart") then
            d.CanCollide = false
            d.CanTouch = false
            d.CanQuery = false
            d.CastShadow = false
            d.Massless = true
            d.Anchored = d == root
        elseif d:IsA("Script") or d:IsA("LocalScript") or d:IsA("HumanoidDescription") then
            d:Destroy()
        end
    end
    local hum = model:FindFirstChildOfClass("Humanoid")
    if hum then
        hum:Destroy()
    end
    local controller = Instance.new("AnimationController")
    Instance.new("Animator").Parent = controller
    controller.Parent = model
    model.PrimaryPart = root
    return model
end

local function plainLook(index)
    local desc = Instance.new("HumanoidDescription")
    local skin = pick(SKIN)
    desc.HeadColor, desc.LeftArmColor, desc.RightArmColor = skin, skin, skin
    desc.TorsoColor = pick(CLOTH)
    local legs = pick(CLOTH)
    desc.LeftLegColor, desc.RightLegColor = legs, legs
    local ok, model = pcall(function()
        return Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
    end)
    return ok and model and finishLook(model, index, rng:NextNumber(0.85, 1.15)) or nil
end

-- ---------------------------------------------------------------------------
-- Mixed looks: real users' outfits recombined. Most Roblox accounts wear a starter outfit, so
-- whole avatars made the stands look generic (owner); instead a pool of dressed users' avatar
-- descriptions is gathered, and each look takes its shirt from one user, its pants from another,
-- its hair, hat, glasses, neck and back items and face from others, on a random skin tone.
-- ---------------------------------------------------------------------------

local POOL_SIZE = 150 -- dressed users' descriptions gathered
local SLOTS = {
    -- description field, chance a look takes one from the pool
    { "HairAccessory", 0.95 }, { "HatAccessory", 0.45 }, { "FaceAccessory", 0.3 },
    { "NeckAccessory", 0.2 }, { "BackAccessory", 0.15 }, { "ShouldersAccessory", 0.1 },
    { "WaistAccessory", 0.1 }, { "FrontAccessory", 0.1 },
}

local function starterOnly(desc)
    local custom = false
    for _, field in ipairs({ "HatAccessory", "FaceAccessory", "NeckAccessory", "BackAccessory", "ShouldersAccessory", "WaistAccessory", "FrontAccessory" }) do
        if desc[field] ~= "" then
            custom = true
        end
    end
    return not custom
end

-- A random user's description, if they wear a shirt and pants
local function fetchDescription()
    local userId = rng:NextInteger(USER_ID_RANGE[1], USER_ID_RANGE[2])
    local ok, desc = pcall(function()
        return Players:GetHumanoidDescriptionFromUserId(userId)
    end)
    if not ok or not desc or desc.Shirt == 0 or desc.Pants == 0 then
        return nil
    end
    if starterOnly(desc) and rng:NextNumber() > STARTER_KEEP then
        return nil
    end
    return desc
end

-- An item for `field` from the pool, rare ones first: an item's chance falls with how many users in
-- the pool wear it (Roblox's starter hairs, caps and shades are everywhere; they made the stands
-- look the same). Accessory fields hold comma-separated ids: one id is taken.
local itemCounts = {} -- field -> { id -> users wearing it }
local function countItems(pool)
    itemCounts = {}
    for _, d in ipairs(pool) do
        for _, field in ipairs({ "Shirt", "Pants", "GraphicTShirt", "Face", "HairAccessory", "HatAccessory", "FaceAccessory",
            "NeckAccessory", "BackAccessory", "ShouldersAccessory", "WaistAccessory", "FrontAccessory" }) do
            local v = d[field]
            if v ~= "" and v ~= 0 then
                itemCounts[field] = itemCounts[field] or {}
                if type(v) == "string" then
                    for id in v:gmatch("%d+") do
                        itemCounts[field][id] = (itemCounts[field][id] or 0) + 1
                    end
                else
                    itemCounts[field][v] = (itemCounts[field][v] or 0) + 1
                end
            end
        end
    end
end

-- (and an item already worn by earlier looks is less likely again: the picks spread over everything)
local itemUsed = {} -- id -> looks wearing it so far
local function pickFrom(pool, field)
    local counts = itemCounts[field]
    if not counts then
        return nil
    end
    local function weight(id, c)
        local used = itemUsed[id] or 0
        return 1 / (c * (1 + used) ^ 2)
    end
    local total = 0
    for id, c in pairs(counts) do
        total += weight(id, c)
    end
    local roll = rng:NextNumber(0, total)
    for id, c in pairs(counts) do
        roll -= weight(id, c)
        if roll <= 0 then
            itemUsed[id] = (itemUsed[id] or 0) + 1
            return id
        end
    end
    return nil
end

-- One look: pieces from several users
local function mixedLook(pool, index)
    local desc = Instance.new("HumanoidDescription")
    local skin = pick(SKIN)
    desc.HeadColor, desc.TorsoColor = skin, skin
    desc.LeftArmColor, desc.RightArmColor, desc.LeftLegColor, desc.RightLegColor = skin, skin, skin, skin
    local outfit = pool[rng:NextInteger(1, #pool)]
    desc.Shirt = rng:NextNumber() < 0.5 and outfit.Shirt or (tonumber(pickFrom(pool, "Shirt")) or outfit.Shirt)
    desc.Pants = rng:NextNumber() < 0.5 and outfit.Pants or (tonumber(pickFrom(pool, "Pants")) or outfit.Pants)
    desc.GraphicTShirt = rng:NextNumber() < 0.3 and (tonumber(pickFrom(pool, "GraphicTShirt")) or 0) or 0
    desc.Face = tonumber(pickFrom(pool, "Face")) or 0
    for _, slot in ipairs(SLOTS) do
        if rng:NextNumber() < slot[2] then
            local v = pickFrom(pool, slot[1])
            if v then
                desc[slot[1]] = v
            end
        end
    end
    local built, model = pcall(function()
        return Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
    end)
    if not built or not model then
        return nil
    end
    -- heights: mostly 0.88-1.12, some small, some tall
    local roll = rng:NextNumber()
    local scale = roll < 0.12 and rng:NextNumber(0.7, 0.82) or (roll > 0.9 and rng:NextNumber(1.15, 1.3) or rng:NextNumber(0.88, 1.12))
    finishLook(model, index, scale)
    if (model:GetAttribute("Height") or 0) > MAX_HEIGHT * scale then
        model:Destroy() -- (a giant accessory)
        return nil
    end
    local weight = 1
    for _, accessory in ipairs(model:GetChildren()) do
        if accessory:IsA("Accessory") then
            for _, word in ipairs(RARE_ACCESSORIES) do
                if accessory.Name:lower():find(word) then
                    weight = RARE_WEIGHT
                end
            end
        end
    end
    model:SetAttribute("Weight", weight)
    return model
end

local function buildTemplates()
    local store = ReplicatedStorage:FindFirstChild("CrowdNpcTemplates")
    if store then
        store:Destroy()
    end
    store = Instance.new("Folder")
    store.Name = "CrowdNpcTemplates"
    local started = os.clock()
    -- 1. the pool of dressed users
    local pool, attempts, active = {}, 0, 0
    for _ = 1, LOOK_WORKERS do
        active += 1
        task.spawn(function()
            while #pool < POOL_SIZE and attempts < LOOK_ATTEMPTS do
                attempts += 1
                local desc = fetchDescription()
                if desc and #pool < POOL_SIZE then
                    table.insert(pool, desc)
                end
            end
            active -= 1
        end)
    end
    while active > 0 do
        task.wait(0.2)
    end
    -- 2. the looks, mixed from it (rare items first)
    countItems(pool)
    itemUsed = {}
    if #pool >= 5 then
        local tries = 0
        for _ = 1, LOOK_WORKERS do
            active += 1
            task.spawn(function()
                while #templates < LOOKS and tries < LOOKS * 3 do
                    tries += 1
                    local look = mixedLook(pool, #templates + 1)
                    if look and #templates < LOOKS then
                        table.insert(templates, look)
                        look.Name = "CrowdLook" .. #templates
                        look.Parent = store
                    elseif look then
                        look:Destroy()
                    end
                end
                active -= 1
            end)
        end
        while active > 0 do
            task.wait(0.2)
        end
    end
    local mixed = #templates
    while #templates < 8 do -- (the avatar service unreachable: plain looks)
        local look = plainLook(#templates + 1)
        if not look then
            break
        end
        table.insert(templates, look)
        look.Parent = store
    end
    store.Parent = ReplicatedStorage
    print(string.format("[ArenaCrowdNpcs] %d crowd looks (%d mixed from %d dressed users, %d tries) in %.1f s",
        #templates, mixed, #pool, attempts, os.clock() - started))
end

-- ============================================================================
-- THE STANDS
-- ============================================================================

local function nearestSection(x, z, sections)
    local best, bestD = 1, math.huge
    for i, s in ipairs(sections) do
        local d = (s.center.X - x) ^ 2 + (s.center.Z - z) ^ 2
        if d < bestD then
            best, bestD = i, d
        end
    end
    return best
end

local function relayout()
    version += 1
    layout = {}
    if Workspace:GetAttribute("CrowdNpcs") ~= false and #templates > 0 then
        local spots = {}
        local arena = Workspace:FindFirstChild("argoniaonion") and Workspace.argoniaonion:FindFirstChild("ArenaOne")
        for _, part in ipairs(arena and arena:GetDescendants() or {}) do
            if part.Name == "CrowdArea" and part:IsA("BasePart") then
                local cf, s = part.CFrame, part.Size
                local ext = (cf.RightVector * s.X):Abs() + (cf.UpVector * s.Y):Abs() + (cf.LookVector * s.Z):Abs()
                local top = part.Position.Y + ext.Y / 2
                local axis = ext.X >= ext.Z and 1 or 3 -- (the row runs along its long side)
                local from = (axis == 1 and part.Position.X - ext.X / 2 or part.Position.Z - ext.Z / 2) + 1.5
                local to = (axis == 1 and part.Position.X + ext.X / 2 or part.Position.Z + ext.Z / 2) - 1.5
                local nx, nz = math.max(1, math.floor((ext.X - 1) / SPACING)), math.max(1, math.floor((ext.Z - 1) / SPACING))
                for ix = 0, nx - 1 do
                    for iz = 0, nz - 1 do
                        local x = part.Position.X - ext.X / 2 + (ix + 0.5) * (ext.X / nx) + rng:NextNumber(-0.5, 0.5)
                        local z = part.Position.Z - ext.Z / 2 + (iz + 0.5) * (ext.Z / nz) + rng:NextNumber(-0.5, 0.5)
                        table.insert(spots, { Vector3.new(x, top, z), axis, from, to })
                    end
                end
            end
        end
        for i = #spots, 2, -1 do
            local j = rng:NextInteger(1, i)
            spots[i], spots[j] = spots[j], spots[i]
        end
        local count = math.min(tonumber(Workspace:GetAttribute("CrowdNpcCount")) or DEFAULT_COUNT, #spots)
        local sections = Crowd.getSections()
        local totalWeight = 0
        for _, t in ipairs(templates) do
            totalWeight += t:GetAttribute("Weight") or 1
        end
        local function pickLook()
            local roll = rng:NextNumber(0, totalWeight)
            for i, t in ipairs(templates) do
                roll -= t:GetAttribute("Weight") or 1
                if roll <= 0 then
                    return i
                end
            end
            return #templates
        end
        for i = 1, count do
            local p, axis, from, to = spots[i][1], spots[i][2], spots[i][3], spots[i][4]
            local look = pickLook()
            local y = p.Y + templates[look]:GetAttribute("RootAboveFloor")
            table.insert(layout, {
                math.floor(p.X * 10) / 10, math.floor(y * 100) / 100, math.floor(p.Z * 10) / 10,
                look, #sections > 0 and nearestSection(p.X, p.Z, sections) or 0,
                axis, math.floor(from * 10) / 10, math.floor(to * 10) / 10,
            })
        end
        print(string.format("[ArenaCrowdNpcs] Stands laid out: %d crowd avatars (of %d spots), drawn on each player's machine", count, #spots))
    end
    Workspace:SetAttribute("CrowdNpcActive", #layout)
    remote:FireAllClients("layout", version)
end

layoutFunction.OnServerInvoke = function()
    return version, layout
end

-- ============================================================================
-- THE PROCEDURAL CROWD -> THE AVATARS
-- ============================================================================

local function sectionTeams()
    local teams = {}
    for i, s in ipairs(Crowd.getSections()) do
        teams[i] = s.team
    end
    return teams
end

Crowd.Reacted:Connect(function(team, category, major)
    if #layout > 0 and type(category) == "string" then
        remote:FireAllClients("react", team, category, major, sectionTeams())
    end
end)

-- Once a second in the fight: the mood (excitement, each section's team, the team being chanted
-- for), and every 35-60 s a Mexican wave round the stands (every client runs the same wave: it
-- starts at a server time and angle)
task.spawn(function()
    local nextWave = os.clock() + rng:NextNumber(20, 35)
    while true do
        task.wait(1)
        if #layout > 0 and Workspace:GetAttribute("CrowdPhase") == "IN_GAME" then
            local state = Crowd.getState()
            local chant = state.Chant and (state.ChantUntil or 0) > 0 and state.Chant or nil
            remote:FireAllClients("mood", state.Excitement, sectionTeams(), chant)
            if os.clock() >= nextWave then
                nextWave = os.clock() + rng:NextNumber(35, 60)
                remote:FireAllClients("wave", Workspace:GetServerTimeNow() + 0.5, rng:NextNumber(0, 360), rng:NextNumber(80, 110))
            end
        else
            nextWave = math.max(nextWave, os.clock() + 20)
        end
    end
end)

Workspace:GetAttributeChangedSignal("CrowdNpcCount"):Connect(relayout)
Workspace:GetAttributeChangedSignal("CrowdNpcs"):Connect(relayout)

local old = Workspace:FindFirstChild("ArenaCrowdNpcs")
if old then
    old:Destroy() -- (an earlier version stood the avatars on the server)
end

task.spawn(function()
    buildTemplates()
    relayout()
end)
