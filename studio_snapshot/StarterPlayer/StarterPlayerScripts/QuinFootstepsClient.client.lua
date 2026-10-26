--// QuinFootstepsClient.client.lua
-- Every Quin's footsteps (sound) and footprints (boot prints on the ground), made on this machine.
-- They used to be made on the server at each Footstep marker: a sound clone and a decal part with its
-- SurfaceGui per step, sent to every player (performance plan step B, 2026-10-26). The server's
-- animation tracks play here too and their markers fire here, so each client makes its own.
--   - only a clip carrying the legs speaks (AnimationModule.FOOTSTEP_MIN_WEIGHT, as before);
--   - steps farther than HEAR_DIST from the camera are not played (the sound fades out at 150
--     studs), footprints farther than DRAW_DIST are not drawn;
--   - a track this machine plays itself (the Quin the player pilots) is already wired by
--     AnimationModule here: skipped (AnimationModule.isWiredHere), or every step would sound twice.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Modules = ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules")
local AnimationModule = require(Modules:WaitForChild("AnimationModule"))
local AudioModule = require(Modules:WaitForChild("AudioModule"))
local VfxModule = require(Modules:WaitForChild("VfxModule"))

local MIN_WEIGHT = AnimationModule.FOOTSTEP_MIN_WEIGHT or 0.35
local HEAR_DIST = 160
local DRAW_DIST = 250
local FOLDERS = { QuinServer = true, PlayerCostumes = true }

local watched = {} -- [model] = { tracks = { [track] = true }, connections = { ... } }

local function distanceTo(fighter)
    local hrp = fighter:FindFirstChild("HumanoidRootPart")
    local camera = Workspace.CurrentCamera
    if not (hrp and camera) then
        return math.huge, nil
    end
    return (hrp.Position - camera.CFrame.Position).Magnitude, hrp
end

local function wire(fighter, entry, track)
    if entry.tracks[track] or AnimationModule.isWiredHere(track) then
        return
    end
    entry.tracks[track] = true
    table.insert(entry.connections, track:GetMarkerReachedSignal("Footstep"):Connect(function(side)
        if track.WeightCurrent < MIN_WEIGHT or not fighter.Parent then
            return
        end
        local d, hrp = distanceTo(fighter)
        if d <= HEAR_DIST then
            local speed = hrp.AssemblyLinearVelocity.Magnitude
            AudioModule.playFootstep(fighter, speed > 25 and 0.45 or 0.35)
        end
        if d <= DRAW_DIST then
            VfxModule.createFootprint(fighter, side) -- marker parameter "Left" / "Right" when the clip has it
        end
    end))
    table.insert(entry.connections, track:GetMarkerReachedSignal("Footstep180"):Connect(function()
        if fighter.Parent and distanceTo(fighter) <= HEAR_DIST then
            AudioModule.playFootstep(fighter, 0.40)
        end
    end))
end

local function unwatch(model)
    local entry = watched[model]
    if entry then
        for _, c in ipairs(entry.connections) do
            c:Disconnect()
        end
        watched[model] = nil
    end
end

local function watch(model)
    if watched[model] or not model:IsA("Model") then
        return
    end
    local entry = { tracks = {}, connections = {} }
    watched[model] = entry
    task.spawn(function()
        local humanoid = model:WaitForChild("Humanoid", 10)
        local animator = humanoid and humanoid:WaitForChild("Animator", 10)
        if not animator or watched[model] ~= entry then
            return
        end
        table.insert(entry.connections, animator.AnimationPlayed:Connect(function(track)
            wire(model, entry, track)
        end))
        for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
            wire(model, entry, track)
        end
    end)
    table.insert(entry.connections, model.AncestryChanged:Connect(function(_, parent)
        if not (parent and FOLDERS[parent.Name]) then
            unwatch(model)
        end
    end))
end

local function watchFolder(folder)
    if not (folder:IsA("Folder") and FOLDERS[folder.Name]) then
        return
    end
    folder.ChildAdded:Connect(watch)
    for _, m in ipairs(folder:GetChildren()) do
        watch(m)
    end
end
Workspace.ChildAdded:Connect(watchFolder)
for _, c in ipairs(Workspace:GetChildren()) do
    watchFolder(c)
end
