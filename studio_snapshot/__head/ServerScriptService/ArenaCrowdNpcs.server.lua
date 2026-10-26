--// ArenaCrowdNpcs.server.lua
-- The NPC crowd on the stands (the ArenaOne parts named "CrowdArea": the bench rows), the server's
-- half. The avatars live only on each player's machine (StarterPlayerScripts.ArenaCrowdClient):
-- the server builds the looks once (ReplicatedStorage.CrowdNpcTemplates), lays out the stands
-- (where each avatar stands, which look, which crowd section, which bench row) and passes on what
-- the procedural crowd (ArenaCrowdManager) does, so a crowd of thousands costs the server nothing.
--
-- Looks: real Roblox avatars (random public users' outfits: clothes, hair, hats), so the stands are
-- not rows of the same default figure; bare default avatars are skipped, and plain coloured ones
-- stand in if the avatar service cannot be reached. Every look is rebuilt with classic joints:
-- Roblox's avatars join limbs and accessories with physics constraints (AnimationConstraint,
-- RigidConstraint) that wake the solver for every limb whenever a body moves; Motor6Ds and Welds
-- keep each avatar one rigid anchored body. Layered clothing needs those constraints and is left off.
--
--   Remote ArenaNetwork.CrowdNpcs (server -> clients):
--     "layout", version                      -- the stands changed: ask for the layout again
--     "react", team, category, major, teams  -- a crowd reaction (teams: each section's team)
--     "mood", excitement, teams              -- once a second while the fight is on
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

local DEFAULT_COUNT = 1000
local SPACING = 3.4 -- studs between avatars on the stands
local LOOKS = 90 -- different avatars
local LOOK_WORKERS = 12 -- avatar lookups at once
local LOOK_ATTEMPTS = 1500 -- random users tried at most (most are undressed or gone)
local RARE_ACCESSORIES = { "hook" } -- looks wearing these come up rarely (owner: the pirate hook hand)
local RARE_WEIGHT = 0.12
local USER_ID_RANGE = { 20000000, 4000000000 }

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

local function finishLook(model, index)
    model.Name = "CrowdLook" .. index
    local root = model:FindFirstChild("HumanoidRootPart")
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
    rebuildJoints(model)
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
    return ok and model and finishLook(model, index) or nil
end

-- A random user's avatar, if it wears a real shirt and pants (owner: everyone clothed; Roblox
-- fills in empty Shirt / Pants objects, so the clothes' templates are what is checked). Each look
-- gets its own height and build, so the stands are not all one size.
local function userLook(index)
    local userId = rng:NextInteger(USER_ID_RANGE[1], USER_ID_RANGE[2])
    local ok, desc = pcall(function()
        return Players:GetHumanoidDescriptionFromUserId(userId)
    end)
    if not ok or not desc then
        return nil
    end
    if desc.Shirt == 0 or desc.Pants == 0 then
        return nil
    end
    local tall = rng:NextNumber() < 0.12 and rng:NextNumber(0.78, 0.88) or rng:NextNumber(0.9, 1.14)
    desc.HeightScale = math.clamp(desc.HeightScale * tall, 0.7, 1.2)
    desc.WidthScale = math.clamp(desc.WidthScale * rng:NextNumber(0.9, 1.1), 0.7, 1.05)
    desc.DepthScale = math.clamp(desc.DepthScale * rng:NextNumber(0.92, 1.08), 0.7, 1.05)
    desc.HeadScale = math.clamp(desc.HeadScale * rng:NextNumber(0.94, 1.06), 0.9, 1.05)
    local dressed = desc.HatAccessory ~= "" or desc.HairAccessory ~= "" or desc.Shirt ~= 0 or desc.GraphicTShirt ~= 0
    if not dressed then
        return nil
    end
    local built, model = pcall(function()
        return Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
    end)
    if not built or not model then
        return nil
    end
    finishLook(model, index)
    -- (layered clothing is left off: an avatar dressed only in it would stand there bare)
    local shirt, pants = model:FindFirstChildOfClass("Shirt"), model:FindFirstChildOfClass("Pants")
    if not (shirt and shirt.ShirtTemplate ~= "" and pants and pants.PantsTemplate ~= "") then
        model:Destroy()
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
    local attempts, active = 0, 0
    for _ = 1, LOOK_WORKERS do
        active += 1
        task.spawn(function()
            while #templates < LOOKS and attempts < LOOK_ATTEMPTS do
                attempts += 1
                local look = userLook(#templates + 1)
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
    local real = #templates
    while #templates < 8 do -- (the avatar service unreachable: plain looks)
        local look = plainLook(#templates + 1)
        if not look then
            break
        end
        table.insert(templates, look)
        look.Parent = store
    end
    store.Parent = ReplicatedStorage
    print(string.format("[ArenaCrowdNpcs] %d crowd looks (%d real avatars from %d tries) in %.1f s", #templates, real, attempts, os.clock() - started))
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

task.spawn(function()
    while true do
        task.wait(1)
        if #layout > 0 and Workspace:GetAttribute("CrowdPhase") == "IN_GAME" then
            remote:FireAllClients("mood", Crowd.getState().Excitement, sectionTeams())
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
