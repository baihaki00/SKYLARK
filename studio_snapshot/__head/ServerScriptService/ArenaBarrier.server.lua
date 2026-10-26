--// ArenaBarrier.server.lua
-- An invisible box over the arena ground that people cannot enter, so spectators and owners can
-- roam round the arena without walking into the fight: four walls on the ground's edges (the
-- sides with preparation rooms stop just inside the room glass) and a roof, BARRIER_HEIGHT studs
-- up. Only the collision group "ArenaSpectators" hits it: every player's own avatar and the NPC
-- owners. Quins (Default group), a Play As Admin costume Quin, cameras and raycasts pass through.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local PhysicsService = game:GetService("PhysicsService")

local BARRIER_HEIGHT = 600
local THICKNESS = 4
local GROUP_PEOPLE = "ArenaSpectators"
local GROUP_BARRIER = "ArenaBarrier"

for _, group in ipairs({ GROUP_PEOPLE, GROUP_BARRIER }) do
    pcall(function()
        PhysicsService:RegisterCollisionGroup(group)
    end)
end
for _, group in ipairs(PhysicsService:GetRegisteredCollisionGroups()) do
    if group.name ~= GROUP_PEOPLE then
        PhysicsService:CollisionGroupSetCollidable(GROUP_BARRIER, group.name, false)
    end
end
PhysicsService:CollisionGroupSetCollidable(GROUP_BARRIER, GROUP_PEOPLE, true)

local arena = Workspace:FindFirstChild("argoniaonion") and Workspace.argoniaonion:FindFirstChild("ArenaOne")
local ground = arena and arena:FindFirstChild("ArenaGround")
if not ground then
    warn("[ArenaBarrier] No ArenaOne.ArenaGround: no barrier")
    return
end

local top = ground.Position.Y + ground.Size.Y / 2
local minX, maxX = ground.Position.X - ground.Size.X / 2, ground.Position.X + ground.Size.X / 2
local minZ, maxZ = ground.Position.Z - ground.Size.Z / 2, ground.Position.Z + ground.Size.Z / 2

-- (the preparation rooms overhang the ground's edge: the barrier stays on the arena side of their glass)
for _, d in ipairs(Workspace:GetDescendants()) do
    if d.Name == "PreparationRoomGlass" and d:IsA("BasePart") then
        if d.Position.X > ground.Position.X then
            maxX = math.min(maxX, d.Position.X - 1)
        else
            minX = math.max(minX, d.Position.X + 1)
        end
    end
end

local folder = Instance.new("Folder")
folder.Name = "ArenaBarrier"
folder.Parent = Workspace

local function wall(name, center, size)
    local p = Instance.new("Part")
    p.Name = name
    p.Anchored = true
    p.CanCollide = true
    p.CanTouch = false
    p.CanQuery = false
    p.CastShadow = false
    p.Transparency = 1
    p.Size = size
    p.CFrame = CFrame.new(center)
    p.CollisionGroup = GROUP_BARRIER
    p.Parent = folder
end

local midX, midZ = (minX + maxX) / 2, (minZ + maxZ) / 2
local spanX, spanZ = maxX - minX, maxZ - minZ
local midY = top + BARRIER_HEIGHT / 2
wall("East", Vector3.new(maxX + THICKNESS / 2, midY, midZ), Vector3.new(THICKNESS, BARRIER_HEIGHT, spanZ + THICKNESS * 2))
wall("West", Vector3.new(minX - THICKNESS / 2, midY, midZ), Vector3.new(THICKNESS, BARRIER_HEIGHT, spanZ + THICKNESS * 2))
wall("North", Vector3.new(midX, midY, maxZ + THICKNESS / 2), Vector3.new(spanX, BARRIER_HEIGHT, THICKNESS))
wall("South", Vector3.new(midX, midY, minZ - THICKNESS / 2), Vector3.new(spanX, BARRIER_HEIGHT, THICKNESS))
wall("Roof", Vector3.new(midX, top + BARRIER_HEIGHT + THICKNESS / 2, midZ), Vector3.new(spanX + THICKNESS * 2, THICKNESS, spanZ + THICKNESS * 2))

-- Every player's own avatar is a spectator (a Play As Admin costume Quin is not)
local function tag(character)
    if character:GetAttribute("IsCostume") == true or character:GetAttribute("QuinId") then
        return
    end
    for _, part in ipairs(character:GetDescendants()) do
        if part:IsA("BasePart") then
            part.CollisionGroup = GROUP_PEOPLE
        end
    end
    character.DescendantAdded:Connect(function(part)
        if part:IsA("BasePart") then
            part.CollisionGroup = GROUP_PEOPLE
        end
    end)
end

local function onPlayer(player)
    player.CharacterAdded:Connect(function(character)
        task.defer(tag, character)
    end)
    if player.Character then
        tag(player.Character)
    end
end
Players.PlayerAdded:Connect(onPlayer)
for _, p in ipairs(Players:GetPlayers()) do
    onPlayer(p)
end

print(string.format("[ArenaBarrier] People kept out of x %.0f..%.0f, z %.0f..%.0f, up to y %.0f", minX, maxX, minZ, maxZ, top + BARRIER_HEIGHT))
