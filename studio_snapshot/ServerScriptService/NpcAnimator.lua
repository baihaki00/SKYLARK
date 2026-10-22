--// NpcAnimator.lua
-- Animations for server-run Roblox avatars (NPC owners, the crowd). Their Animate script is a
-- LocalScript and never runs on an NPC, so without this they stand frozen.
--
--   NpcAnimator.attach(model, { moving = true })  -- follows the Humanoid: idle / walk / run /
--                                                  -- jump / fall / sit, from its state and speed
--   NpcAnimator.attach(model)                      -- still (the crowd): idle, plus emotes
--   NpcAnimator.emote(model, name, seconds)        -- cheer, wave, point, laugh, dance1-3
--                                                  -- (a moving NPC that starts walking stops it)
-- Roblox's default R15 animations; one Heartbeat drives every moving NPC.

local RunService = game:GetService("RunService")

local NpcAnimator = {}

local IDS = {
    idle = { "507766388", "507766666", "507766951" },
    walk = { "507777826" },
    run = { "507767714" },
    jump = { "507765000" },
    fall = { "507767968" },
    sit = { "2506281703" },
    cheer = { "507770677" },
    wave = { "507770239" },
    point = { "507770453" },
    laugh = { "507770818" },
    dance1 = { "507771019" },
    dance2 = { "507776043" },
    dance3 = { "507777268" },
}
local LOOPED = { idle = true, walk = true, run = true, fall = true, sit = true, dance1 = true, dance2 = true, dance3 = true }
local RUN_SPEED = 17 -- studs/s above which an NPC runs...
local WALK_SPEED_BACK = 14 -- ...and below which a running NPC walks again (no flicker between them)

local animations = {} -- id -> Animation (shared)
local rigs = {} -- model -> { animator, humanoid, root, tracks = {}, base, emote, emoteUntil, moving }

local function animation(id)
    local a = animations[id]
    if not a then
        a = Instance.new("Animation")
        a.AnimationId = "rbxassetid://" .. id
        animations[id] = a
    end
    return a
end

local function track(rig, name)
    local t = rig.tracks[name]
    if not t then
        local ids = IDS[name]
        local ok, loaded = pcall(function()
            return rig.animator:LoadAnimation(animation(ids[math.random(1, #ids)]))
        end)
        if not ok then
            return nil
        end
        loaded.Looped = LOOPED[name] == true
        loaded.Priority = (name == "idle" or name == "walk" or name == "run" or name == "sit" or name == "fall")
            and Enum.AnimationPriority.Core or Enum.AnimationPriority.Action
        rig.tracks[name] = loaded
        t = loaded
    end
    return t
end

local function setBase(rig, name, speed)
    if rig.base ~= name then
        local old = rig.base and rig.tracks[rig.base]
        if old then
            old:Stop(0.25)
        end
        rig.base = name
        local t = track(rig, name)
        if t then
            t:Play(0.25)
        end
    end
    local t = rig.tracks[name]
    if t and speed then
        t:AdjustSpeed(speed)
    end
end

function NpcAnimator.attach(model, options)
    local humanoid = model:FindFirstChildOfClass("Humanoid")
    if not humanoid then
        return nil
    end
    local animate = model:FindFirstChild("Animate")
    if animate then
        animate:Destroy() -- (a LocalScript: it never runs here)
    end
    local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator", humanoid)
    local rig = {
        animator = animator,
        humanoid = humanoid,
        root = model:FindFirstChild("HumanoidRootPart"),
        tracks = {},
        moving = options and options.moving == true,
    }
    rigs[model] = rig
    setBase(rig, "idle")
    -- idle variants now and then
    task.spawn(function()
        while rigs[model] == rig and model.Parent do
            task.wait(math.random(8, 20))
            if rig.base == "idle" and rigs[model] == rig then
                local old = rig.tracks.idle
                rig.tracks.idle = nil
                rig.base = nil
                setBase(rig, "idle")
                if old then
                    old:Stop(0.4)
                    task.delay(0.6, old.Destroy, old)
                end
            end
        end
    end)
    model.AncestryChanged:Connect(function()
        if not model.Parent then
            rigs[model] = nil
        end
    end)
    return rig
end

function NpcAnimator.emote(model, name, seconds)
    local rig = rigs[model]
    if not rig or not IDS[name] then
        return
    end
    if rig.emote and rig.emote ~= name and rig.tracks[rig.emote] then
        rig.tracks[rig.emote]:Stop(0.2)
    end
    local t = track(rig, name)
    if t then
        rig.emote = name
        rig.emoteUntil = os.clock() + (seconds or t.Length)
        t:Play(0.15)
        if seconds then
            task.delay(seconds, function()
                if rig.emote == name and os.clock() >= rig.emoteUntil - 0.05 then
                    t:Stop(0.3)
                    rig.emote = nil
                end
            end)
        end
    end
end

function NpcAnimator.stopEmote(model)
    local rig = rigs[model]
    if rig and rig.emote and rig.tracks[rig.emote] then
        rig.tracks[rig.emote]:Stop(0.25)
        rig.emote = nil
    end
end

-- Moving NPCs: the base animation follows the Humanoid
RunService.Heartbeat:Connect(function()
    for model, rig in pairs(rigs) do
        if rig.moving and rig.root then
            local hum = rig.humanoid
            local state = hum:GetState()
            local v = rig.root.AssemblyLinearVelocity
            local speed = Vector3.new(v.X, 0, v.Z).Magnitude
            if hum.SeatPart then -- (the seat itself: Sit / the Seated state can stay set after standing up)
                setBase(rig, "sit")
            elseif state == Enum.HumanoidStateType.Jumping then
                if rig.base ~= "jump" then
                    setBase(rig, "jump")
                end
            elseif state == Enum.HumanoidStateType.Freefall then
                setBase(rig, "fall")
            elseif speed > RUN_SPEED or (rig.base == "run" and speed > WALK_SPEED_BACK) then
                setBase(rig, "run", speed / 16)
            elseif speed > 0.8 then
                setBase(rig, "walk", speed / 9)
            else
                setBase(rig, "idle")
            end
            if rig.emote and speed > 0.8 then
                NpcAnimator.stopEmote(model)
            end
        end
    end
end)

return NpcAnimator
