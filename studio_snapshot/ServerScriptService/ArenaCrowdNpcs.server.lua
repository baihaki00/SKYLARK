--// ArenaCrowdNpcs.server.lua
-- The NPC crowd on the stands (the ArenaOne parts named "CrowdArea"), the server's half. The
-- avatars themselves live only on each player's machine (StarterPlayerScripts.ArenaCrowdClient):
-- the server builds the looks once (ReplicatedStorage.CrowdNpcTemplates), lays out the stands
-- (where each avatar stands, which look, which crowd section) and passes on what the procedural
-- crowd (ArenaCrowdManager) does, so a crowd of thousands costs the server next to nothing.
--
--   Remote ArenaNetwork.CrowdNpcs (server -> clients):
--     "layout", version                      -- the stands changed: ask for the layout again
--     "react", team, category, major, teams  -- a crowd reaction (teams: each section's team)
--     "mood", excitement, teams              -- once a second while the fight is on
--   RemoteFunction ArenaNetwork.CrowdNpcLayout -> version, { {x, y, z, look, section}, ... }
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
local VARIANTS = 16 -- looks

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
local LIMB_ZONE = {
    Head = "skin", LeftUpperArm = "skin", LeftLowerArm = "skin", LeftHand = "skin",
    RightUpperArm = "skin", RightLowerArm = "skin", RightHand = "skin",
    UpperTorso = "torso", LowerTorso = "torso",
    LeftUpperLeg = "legs", LeftLowerLeg = "legs", LeftFoot = "legs",
    RightUpperLeg = "legs", RightLowerLeg = "legs", RightFoot = "legs",
}

local rng = Random.new()
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
-- LOOKS: R15 avatars without a Humanoid (an AnimationController animates them), colours baked
-- ============================================================================

local templates = {}
local function buildTemplates()
    local store = ReplicatedStorage:FindFirstChild("CrowdNpcTemplates")
    if store then
        store:Destroy()
    end
    store = Instance.new("Folder")
    store.Name = "CrowdNpcTemplates"
    for i = 1, VARIANTS do
        local colors = { skin = pick(SKIN), torso = pick(CLOTH), legs = pick(CLOTH) }
        local desc = Instance.new("HumanoidDescription")
        desc.HeadColor, desc.LeftArmColor, desc.RightArmColor = colors.skin, colors.skin, colors.skin
        desc.TorsoColor = colors.torso
        desc.LeftLegColor, desc.RightLegColor = colors.legs, colors.legs
        local ok, model = pcall(function()
            return Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
        end)
        if ok and model then
            model.Name = "CrowdLook" .. i
            local root = model:FindFirstChild("HumanoidRootPart")
            local cf, size = model:GetBoundingBox()
            model:SetAttribute("RootAboveFloor", root.Position.Y - (cf.Y - size.Y / 2))
            for _, d in ipairs(model:GetDescendants()) do
                if d:IsA("BasePart") then
                    local zone = LIMB_ZONE[d.Name]
                    if zone then
                        d.Color = colors[zone]
                    end
                    d.CanCollide = false
                    d.CanTouch = false
                    d.CanQuery = false
                    d.CastShadow = false
                    d.Massless = true
                    d.Anchored = d == root
                elseif d:IsA("Script") or d:IsA("LocalScript") or d:IsA("BodyColors") or d:IsA("HumanoidDescription") then
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
            model.Parent = store
            table.insert(templates, model)
        else
            warn("[ArenaCrowdNpcs] Could not build a crowd look: " .. tostring(model))
        end
    end
    store.Parent = ReplicatedStorage
end

-- ============================================================================
-- THE STANDS
-- ============================================================================

local function sectionsNow()
    return Crowd.getSections()
end

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
                local nx, nz = math.floor((ext.X - 2) / SPACING), math.floor((ext.Z - 2) / SPACING)
                for ix = 0, nx - 1 do
                    for iz = 0, nz - 1 do
                        local x = part.Position.X - ext.X / 2 + 1 + (ix + 0.5) * SPACING + rng:NextNumber(-0.6, 0.6)
                        local z = part.Position.Z - ext.Z / 2 + 1 + (iz + 0.5) * SPACING + rng:NextNumber(-0.6, 0.6)
                        table.insert(spots, Vector3.new(x, top, z))
                    end
                end
            end
        end
        for i = #spots, 2, -1 do
            local j = rng:NextInteger(1, i)
            spots[i], spots[j] = spots[j], spots[i]
        end
        local count = math.min(tonumber(Workspace:GetAttribute("CrowdNpcCount")) or DEFAULT_COUNT, #spots)
        local sections = sectionsNow()
        for i = 1, count do
            local p = spots[i]
            local look = rng:NextInteger(1, #templates)
            local y = p.Y + templates[look]:GetAttribute("RootAboveFloor")
            table.insert(layout, {
                math.floor(p.X * 10) / 10, math.floor(y * 100) / 100, math.floor(p.Z * 10) / 10,
                look, #sections > 0 and nearestSection(p.X, p.Z, sections) or 0,
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
    for i, s in ipairs(sectionsNow()) do
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

-- (an earlier version stood the avatars on the server)
local old = Workspace:FindFirstChild("ArenaCrowdNpcs")
if old then
    old:Destroy()
end

buildTemplates()
relayout()
