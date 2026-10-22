--// ArenaCrowdClient.client.lua
-- The NPC crowd on the stands, drawn on this machine only (ArenaCrowdNpcs.server lays out the
-- stands and passes on the procedural crowd's reactions). Built for thousands of avatars:
--   * no Humanoids: each avatar is the R15 rig of one of the server's looks, with an
--     AnimationController;
--   * only the avatars nearest the camera animate (ANIMATE_MAX within ANIMATE_RANGE, re-chosen
--     twice a second, switched a few a frame); the rest stand still, which at that distance reads
--     the same;
--   * a hop lifts the body through its Root joint's Transform, the property animations write. The
--     server's looks are joined with Motor6Ds (not Roblox's physics AnimationConstraints), so each
--     avatar is one rigid anchored body and a hop wakes no physics:
--     moving an avatar's root part dragged its 15 jointed parts through the engine's move path, and
--     40 hopping avatars took a 16v16 from 78 to 14 fps; at most HOP_MAX hop at once, none beyond
--     HOP_RANGE (Workspace attribute CrowdHopMode = "move" brings the old way back, to compare);
--   * a reaction starts at most RESPOND_PER_FRAME avatars a frame, so it ripples instead of spiking;
--   * reactions reach the avatars of the sections that made them: cheers and roars -> cheering,
--     waving, jumping (big moments: jumping again and again, dancing); groans and disappointment
--     -> pointing (booing), gasps -> standing still; the fight's excitement keeps a few moving.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- (live tuning: Workspace attributes CrowdAnimateMax / CrowdHopMax / CrowdReactScale override these)
local ANIMATE_MAX = 60 -- avatars animated at once (the nearest; each costs ~0.03 ms a frame)
local ANIMATE_RANGE = 200 -- studs from the camera
local HOP_MAX = 200 -- avatars in the air at once
local HOP_RANGE = 450 -- studs: further away a hop is not worth drawing
local RESPOND_PER_FRAME = 60 -- avatars starting a reaction in one frame (a roar ripples, no spike)
local NEAR_CHANGES_PER_FRAME = 12 -- avatars starting / stopping animation in one frame
local function tuned(name, default)
    return tonumber(Workspace:GetAttribute(name)) or default
end
local HOP_TIME = 0.42 -- seconds per hop
local ARENA_CENTER = Vector3.new(0, 0, -438)

local IDS = {
    idle = "507766388", cheer = "507770677", wave = "507770239", point = "507770453",
    laugh = "507770818", dance1 = "507771019", dance2 = "507776043", dance3 = "507777268",
}
local LOOPED = { idle = true, dance1 = true, dance2 = true, dance3 = true }

local net = ReplicatedStorage:WaitForChild("ArenaNetwork")
local remote = net:WaitForChild("CrowdNpcs", 60)
local layoutFunction = net:WaitForChild("CrowdNpcLayout", 60)
local templates = ReplicatedStorage:WaitForChild("CrowdNpcTemplates", 60)
if not (remote and layoutFunction and templates) then
    warn("[ArenaCrowdClient] No crowd from the server")
    return
end

local camera = Workspace.CurrentCamera
local rng = Random.new()
local animations = {}
for name, id in pairs(IDS) do
    local a = Instance.new("Animation")
    a.AnimationId = "rbxassetid://" .. id
    animations[name] = a
end

local folder = Instance.new("Folder")
folder.Name = "ArenaCrowdLocal"
folder.Parent = Workspace

local avatars = {} -- { model, root, home, section, animator, tracks, near, emote, busyUntil }
local hopping = {} -- avatar -> { start, times, height }
local hopCount = 0
local pending = {} -- { at, avatar, category, major }
local nearQueue = {} -- { a, near }: animation switches still to do
local buildToken = 0

local function pick(list)
    return list[rng:NextInteger(1, #list)]
end

-- ============================================================================
-- BUILD
-- ============================================================================

local function clear()
    avatars, hopping, pending, hopCount = {}, {}, {}, 0
    table.clear(nearQueue)
    folder:ClearAllChildren()
end

local function build()
    buildToken += 1
    local token = buildToken
    local ok, version, layout = pcall(function()
        return layoutFunction:InvokeServer()
    end)
    if not ok or token ~= buildToken then
        return
    end
    clear()
    local looks = templates:GetChildren()
    table.sort(looks, function(a, b)
        return (tonumber(a.Name:match("%d+")) or 0) < (tonumber(b.Name:match("%d+")) or 0)
    end)
    local started = os.clock()
    for i, entry in ipairs(layout or {}) do
        local look = looks[entry[4]] or looks[1]
        if look then
            local pos = Vector3.new(entry[1], entry[2], entry[3])
            local home = CFrame.lookAt(pos, Vector3.new(ARENA_CENTER.X, pos.Y, ARENA_CENTER.Z))
            local model = look:Clone()
            model:PivotTo(home)
            model.Parent = folder
            local controller = model:FindFirstChildOfClass("AnimationController")
            table.insert(avatars, {
                model = model,
                root = model.PrimaryPart or model:FindFirstChild("HumanoidRootPart"),
                home = home,
                section = entry[5],
                animator = controller and controller:FindFirstChildOfClass("Animator"),
                tracks = {},
                rootJoint = model:FindFirstChild("LowerTorso") and model.LowerTorso:FindFirstChild("Root"),
                near = false,
                busyUntil = 0,
            })
        end
        if i % 60 == 0 then
            RunService.Heartbeat:Wait()
            if token ~= buildToken then
                return
            end
        end
    end
    print(string.format("[ArenaCrowdClient] %d crowd avatars (layout v%d) in %.1f s", #avatars, version or 0, os.clock() - started))
end

-- ============================================================================
-- ANIMATION (the nearest only)
-- ============================================================================

local function track(a, name)
    local t = a.tracks[name]
    if not t and a.animator then
        t = a.animator:LoadAnimation(animations[name])
        t.Looped = LOOPED[name] == true
        t.Priority = name == "idle" and Enum.AnimationPriority.Core or Enum.AnimationPriority.Action
        a.tracks[name] = t
    end
    return t
end

-- (tracks stay loaded when an avatar goes still, so coming back near loads nothing)
local function setNear(a, near)
    if a.near == near then
        return
    end
    a.near = near
    if near then
        local idle = track(a, "idle")
        if idle then
            idle:Play(0.3)
            idle.TimePosition = rng:NextNumber(0, math.max(0.1, idle.Length))
        end
    else
        for _, t in pairs(a.tracks) do
            t:Stop(0.3)
        end
        a.emote = nil
    end
end

local function emote(a, name, seconds)
    if not a.near then
        return
    end
    if a.emote and a.emote ~= name and a.tracks[a.emote] then
        a.tracks[a.emote]:Stop(0.2)
    end
    local t = track(a, name)
    if t then
        a.emote = name
        t:Play(0.15)
        local mine = t
        task.delay(seconds or 2, function()
            if a.emote == name and a.tracks[name] == mine then
                mine:Stop(0.3)
                a.emote = nil
            end
        end)
    end
end

local function stopEmote(a)
    if a.emote and a.tracks[a.emote] then
        a.tracks[a.emote]:Stop(0.25)
    end
    a.emote = nil
end

-- The lift for a hop: a function setting the body's height above its stand
local function lifter(a)
    local joint = a.rootJoint
    if not joint or not (joint:IsA("AnimationConstraint") or joint:IsA("Motor6D")) then
        return nil
    end
    local mode = Workspace:GetAttribute("CrowdHopMode")
    if mode == "attach" and joint:IsA("AnimationConstraint") and joint.Attachment0 then
        local attach, base = joint.Attachment0, joint.Attachment0.Position
        return function(lift)
            attach.Position = base + Vector3.new(0, lift, 0)
        end
    end
    return function(lift)
        joint.Transform = CFrame.new(0, lift, 0)
    end
end

local function hop(a, times, height)
    if a.lift == nil then
        a.lift = lifter(a) or false
    end
    if hopping[a] or hopCount >= tuned("CrowdHopMax", HOP_MAX) then
        return
    end
    if (a.home.Position - camera.CFrame.Position).Magnitude > HOP_RANGE then
        return -- (too far to see a hop)
    end
    hopping[a] = { start = os.clock(), times = times, height = (height or 2.2) * rng:NextNumber(0.75, 1.25) }
    hopCount += 1
end

-- ============================================================================
-- REACTIONS
-- ============================================================================

local function isPositive(category)
    return category:find("Cheer") or category:find("Roar") or category:find("Applause") or category:find("Celebration")
end

local function isNegative(category)
    return category:find("Groan") or category:find("Gasp") or category:find("Disappointment") or category:find("Boo") or category:find("Shock")
end

local function respond(a, category, major)
    local now = os.clock()
    if now < a.busyUntil then
        return
    end
    if category:find("Celebration") then
        a.busyUntil = now + 7
        hop(a, rng:NextInteger(3, 6), 2.6)
        emote(a, pick({ "cheer", "dance1", "dance2", "dance3", "cheer" }), 7)
    elseif isPositive(category) then
        a.busyUntil = now + (major and 3.5 or 2)
        if category:find("Applause") then
            emote(a, pick({ "wave", "cheer" }), 2.5)
        else
            emote(a, pick({ "cheer", "cheer", "wave", "point" }), major and 3 or 2)
            if major or rng:NextNumber() < 0.45 then
                hop(a, major and rng:NextInteger(1, 3) or 1, major and 2.4 or 1.6)
            end
        end
    elseif isNegative(category) then
        a.busyUntil = now + 2.5
        if (category:find("Disappointment") or category:find("Groan")) and rng:NextNumber() < 0.4 then
            emote(a, "point", 2) -- (booing the call)
        else
            stopEmote(a) -- (stunned still)
        end
    end
end

remote.OnClientEvent:Connect(function(kind, a1, a2, a3, a4)
    if kind == "layout" then
        task.spawn(build)
    elseif kind == "react" then
        local team, category, major, teams = a1, a2, a3, a4 or {}
        if type(category) ~= "string" then
            return
        end
        local chance = (major and 0.85 or (isPositive(category) and 0.35 or 0.25)) * tuned("CrowdReactScale", 1)
        local now = os.clock()
        for _, a in ipairs(avatars) do
            if (team == nil or teams[a.section] == team) and rng:NextNumber() < chance then
                table.insert(pending, { at = now + rng:NextNumber(0, major and 0.5 or 0.8), avatar = a, category = category, major = major })
            end
        end
    elseif kind == "mood" then
        local excitement, teams = a1 or {}, a2 or {}
        local tries = math.max(1, math.floor(#avatars * 0.04))
        for _ = 1, tries do
            local a = avatars[rng:NextInteger(1, math.max(1, #avatars))]
            if a and os.clock() >= a.busyUntil then
                local level = excitement[teams[a.section] or "Neutral"] or excitement.Neutral or 0.2
                if rng:NextNumber() < 0.3 + level then
                    a.busyUntil = os.clock() + 2.5
                    emote(a, pick({ "cheer", "point", "wave" }), 2)
                    if level > 0.6 and rng:NextNumber() < 0.5 then
                        hop(a, 1, 1.6)
                    end
                end
            end
        end
    end
end)

-- ============================================================================
-- PER FRAME: due reactions, hops (one batched move), and twice a second, who animates
-- ============================================================================

local lastLod, lastAmbient = 0, 0
local parts, cframes = {}, {}

RunService.RenderStepped:Connect(function()
    local now = os.clock()

    -- reactions whose small random delay is up
    if #pending > 0 then
        local keep, started = {}, 0
        for _, p in ipairs(pending) do
            if now >= p.at and started < RESPOND_PER_FRAME then
                started += 1
                respond(p.avatar, p.category, p.major)
            else
                table.insert(keep, p)
            end
        end
        pending = keep
    end

    -- animation on / off, a few avatars a frame
    for _ = 1, NEAR_CHANGES_PER_FRAME do
        local change = table.remove(nearQueue)
        if not change then
            break
        end
        setNear(change.a, change.near)
    end

    -- hops: through the Root joint (or, CrowdHopMode "move", the old batched part move)
    if hopCount > 0 then
        local byJoint = Workspace:GetAttribute("CrowdHopMode") ~= "move"
        table.clear(parts)
        table.clear(cframes)
        for a, h in pairs(hopping) do
            local elapsed = now - h.start
            local n = math.floor(elapsed / HOP_TIME)
            local lift = 0
            local done = n >= h.times or not a.root.Parent
            if done then
                hopping[a] = nil
                hopCount -= 1
            else
                local u = (elapsed - n * HOP_TIME) / HOP_TIME
                lift = h.height * math.sin(math.pi * u)
            end
            if byJoint and a.lift then
                a.lift(lift)
            else
                table.insert(parts, a.root)
                table.insert(cframes, a.home + Vector3.new(0, lift, 0))
            end
        end
        if #parts > 0 then
            Workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
        end
    end

    -- level of detail: the nearest animate
    if now - lastLod > 0.5 and #avatars > 0 then
        lastLod = now
        local eye = camera.CFrame.Position
        local inRange = {}
        for _, a in ipairs(avatars) do
            local d = (a.home.Position - eye).Magnitude
            if d < ANIMATE_RANGE then
                table.insert(inRange, { a = a, d = d })
            end
        end
        local animateMax = tuned("CrowdAnimateMax", ANIMATE_MAX)
        if #inRange > animateMax then
            table.sort(inRange, function(x, y)
                return x.d < y.d
            end)
        end
        local chosen = {}
        for i = 1, math.min(animateMax, #inRange) do
            chosen[inRange[i].a] = true
        end
        table.clear(nearQueue)
        for _, a in ipairs(avatars) do
            local want = chosen[a] == true
            if a.near ~= want then
                table.insert(nearQueue, { a = a, near = want })
            end
        end
    end

    -- between fights the stands are not quite still either
    if now - lastAmbient > 2 and #avatars > 0 and Workspace:GetAttribute("CrowdPhase") ~= "IN_GAME" then
        lastAmbient = now
        for _ = 1, math.max(1, math.floor(#avatars * 0.01)) do
            local a = avatars[rng:NextInteger(1, #avatars)]
            if a.near and now >= a.busyUntil then
                a.busyUntil = now + 2.5
                emote(a, pick({ "wave", "laugh", "point" }), 2.5)
            end
        end
    end
end)

task.spawn(build)
