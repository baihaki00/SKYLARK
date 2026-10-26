--// QuinPreview.lua
-- A Quin shown in a ViewportFrame (the player menu's MY QUINS cards), built on the player's own
-- machine from the body templates (ReplicatedStorage.QuinType, as QuinSpawner does), standing in
-- its idle. One place builds the look, so accessories and colours added to Quins later show here
-- too: extend QuinPreview.build.
--
--   QuinPreview.build(info)           -> Model (info: { Gender = "Male" | "Female", Outfit = {...}, ... })
--   (Outfit: a QuinWardrobe outfit, worn as in the arena; handle.dress(outfit) changes it)
--   QuinPreview.mount(viewport, info) -> handle { model, setYaw(degrees), dress(outfit), destroy() }

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local QuinCore = ReplicatedStorage:WaitForChild("QuinCore")
local AnimationConfig = require(QuinCore:WaitForChild("AnimationConfig"))
local QuinWardrobe = require(QuinCore:WaitForChild("Modules"):WaitForChild("QuinWardrobe"))

local QuinPreview = {}

local FOV = 30
local DISTANCE = 18.5 -- studs from the body, looking at its middle (17 cut off the shoes)
local LOOK_HEIGHT = -1.4 -- (the root stands at hip height: the body's middle is a little lower)
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
    model:SetAttribute("Gender", info.Gender == "Female" and "Female" or "Male")
    if type(info.Outfit) == "table" then
        QuinWardrobe.dress(model, info.Outfit, true) -- (layered here: the owner's choice for previews)
    end
    -- (paint and team bands go here once the menu shows them)
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
    -- soft studio light: a warm key from the front left and above, a cool, bright ambient so the
    -- shadow side isn't muddy
    viewport.LightDirection = Vector3.new(0.45, -0.9, -0.75)
    viewport.LightColor = Color3.fromRGB(255, 246, 232)
    viewport.Ambient = Color3.fromRGB(168, 174, 190)

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

    function handle.dress(outfit)
        if handle.model then
            QuinWardrobe.dress(handle.model, outfit or {}, true)
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
