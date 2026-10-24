--// QuinPreview.lua
-- A Quin shown in a ViewportFrame (the player menu's MY QUINS cards), built on the player's own
-- machine from the body templates (ReplicatedStorage.QuinType, as QuinSpawner does), standing in
-- its idle. One place builds the look, so accessories and colours added to Quins later show here
-- too: extend QuinPreview.build.
--
--   QuinPreview.build(info)           -> Model (info: { Gender = "Male" | "Female", ... })
--   QuinPreview.mount(viewport, info) -> handle { model, setYaw(degrees), destroy() }

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local QuinCore = ReplicatedStorage:WaitForChild("QuinCore")
local AnimationConfig = require(QuinCore:WaitForChild("AnimationConfig"))

local QuinPreview = {}

local FOV = 30
local DISTANCE = 17 -- studs from the body, looking at its middle
local LOOK_HEIGHT = -0.9 -- (the root stands at hip height: the body's middle is a little lower)
local YAW = 200 -- degrees: turned a little, not square to the camera

local function idleId()
    local reg = AnimationConfig.Registry
    local idle = reg and reg.Idles and reg.Idles.DefaultIdle
    return idle and idle.id
end

-- The Quin's body as it would look in the arena (today: the template of its gender)
function QuinPreview.build(info)
    info = info or {}
    local folder = ReplicatedStorage:WaitForChild("QuinType")
    local template = folder:FindFirstChild(info.Gender == "Female" and "QuinFemale" or "QuinMale")
    if not template then
        return nil
    end
    local model = template:Clone()
    for _, d in ipairs(model:GetDescendants()) do
        if d:IsA("LuaSourceContainer") or d:IsA("Sound") then
            d:Destroy()
        elseif d:IsA("BasePart") then
            d.Anchored = d.Name == "HumanoidRootPart"
            d.CanCollide = false
            d.CastShadow = false
            if d.Name == "HumanoidRootPart" or d.Name == "Sounds" then
                d.Transparency = 1
            end
        end
    end
    local hrp = model:FindFirstChild("HumanoidRootPart")
    if hrp then
        model.PrimaryPart = hrp
    end
    -- (accessories, paint and team bands go here once Quins carry them)
    return model
end

function QuinPreview.mount(viewport, info)
    local world = Instance.new("WorldModel")
    world.Parent = viewport
    local camera = Instance.new("Camera")
    camera.FieldOfView = FOV
    camera.CFrame = CFrame.lookAt(Vector3.new(0, LOOK_HEIGHT + 0.6, DISTANCE), Vector3.new(0, LOOK_HEIGHT, 0))
    camera.Parent = viewport
    viewport.CurrentCamera = camera
    viewport.LightDirection = Vector3.new(-0.6, -1, -0.8)
    viewport.Ambient = Color3.fromRGB(150, 155, 170)
    viewport.LightColor = Color3.fromRGB(255, 250, 240)

    local handle = { model = nil }
    local model = QuinPreview.build(info)
    if model then
        model:PivotTo(CFrame.Angles(0, math.rad(YAW), 0))
        model.Parent = world
        handle.model = model
        local id = idleId()
        local humanoid = model:FindFirstChildOfClass("Humanoid")
        local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
        if id and animator then
            local anim = Instance.new("Animation")
            anim.AnimationId = id
            local ok, track = pcall(function()
                return animator:LoadAnimation(anim)
            end)
            if ok and track then
                track.Looped = true
                track:Play(0)
                handle.track = track
            end
        end
    end

    function handle.setYaw(degrees)
        if handle.model then
            handle.model:PivotTo(CFrame.Angles(0, math.rad(degrees), 0))
        end
    end

    function handle.destroy()
        if handle.track then
            handle.track:Stop(0)
        end
        world:Destroy()
        camera:Destroy()
    end

    return handle
end

return QuinPreview
