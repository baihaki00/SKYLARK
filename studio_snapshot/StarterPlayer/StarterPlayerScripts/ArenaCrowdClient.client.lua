--// ArenaCrowdClient.client.lua
-- The NPC crowd on the stands, drawn on this machine only (ArenaCrowdNpcs.server lays out the
-- stands and passes on the procedural crowd's reactions).
--
-- The crowd arrives when the arena opens (a match leaves IDLE): avatars flicker in over a few
-- seconds, holographic (the nearest with a cyan glow), some already walking along their bench row,
-- cheering or chatting with a neighbour; at the end of the match they flicker out again.
--
-- Three distances, so thousands still look alive at little cost:
--   near (ANIMATE_MAX within ANIMATE_RANGE): Roblox animations and emotes, an expressive face
--     (FACE_MAX within FACE_RANGE: eyes, brows and a mouth that cheer, gasp, boo and talk), chat
--     bubbles;
--   middle (within POSE_RANGE): poses written straight to the joints a few avatars a frame (arms
--     up, clapping, pointing, hands on the head, slumping, walking legs, talking nods);
--   far: still, which at that distance reads the same.
-- Every hop raises the arms. Hops and poses go through the joints' Transform (what animations
-- write); the looks are rigid Motor6D bodies, so none of it wakes physics.
-- Reactions: cheers and roars -> cheering, clapping, jumping (big moments: jumping again and again,
-- dancing); groans and disappointment -> booing (pointing, slumping); gasps -> hands on the head.
-- Together, in time (server time, so every player sees the same): the anthem (the whole stadium
-- sways side to side, arms up, singing), Mexican waves round the stands (the server starts them),
-- and chants (the chanted team's sections pump their fists on the beat).
-- Live knobs (Workspace attributes): CrowdAnimateMax, CrowdHopMax, CrowdReactScale,
-- CrowdAlwaysOn (true: the crowd stays between matches too).

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")

local ANIMATE_MAX = 60 -- avatars with real animations (the nearest)
local ANIMATE_RANGE = 200 -- studs from the camera
local FACE_MAX = 40 -- expressive faces (the nearest)
local FACE_RANGE = 70
local POSE_RANGE = 380 -- beyond this the crowd stands still
local POSE_UPDATES_PER_FRAME = 160 -- posed avatars re-posed per frame
local POSE_UPDATES_ANTHEM = 360 -- (during the anthem every avatar sways: more a frame)
local ANTHEM_PERIOD = 2.6 -- seconds per sway, left and right
local CHANT_BEAT = 0.5 -- seconds per fist pump
local WAVE_WIDTH = 9 -- degrees of the stands up at once
local HOP_MAX = 250 -- avatars in the air at once
local HOP_RANGE = 450
local HOP_TIME = 0.42 -- seconds per hop
local WALKER_SHARE = 0.06 -- of the crowd walking at any time
local WALK_SPEED = { 3.5, 6 } -- studs/s
local TALK_SHARE = 0.05 -- of the crowd chatting at any time
local BUBBLE_RANGE = 90
local RESPOND_PER_FRAME = 60
local NEAR_CHANGES_PER_FRAME = 12
local ARRIVE_TIME = 8 -- seconds for the stands to fill
local LEAVE_TIME = 4
local GLITCH_TIME = 0.9
local GLOW_MAX = 20 -- cyan glows at once (Roblox draws ~31 highlights)
local ARENA_CENTER = Vector3.new(0, 0, -438)

local IDS = {
    idle = "507766388", walk = "507777826", cheer = "507770677", wave = "507770239", point = "507770453",
    laugh = "507770818", dance1 = "507771019", dance2 = "507776043", dance3 = "507777268",
}
local LOOPED = { idle = true, walk = true, dance1 = true, dance2 = true, dance3 = true }

local LINES = {
    "LET'S GO!", "Did you see that?!", "No way...", "Get up, get up!", "That was clean",
    "Ooooh!", "He's done for", "Finish it!", "Who's that one?", "This round is wild",
    "Ref!!", "I told you", "Again! Again!", "So close", "MVP right there", "Look at the left side",
}

local net = ReplicatedStorage:WaitForChild("ArenaNetwork")
local remote = net:WaitForChild("CrowdNpcs", 60)
local layoutFunction = net:WaitForChild("CrowdNpcLayout", 60)
local stateRemote = net:WaitForChild("StateReplication", 60)
local templates = ReplicatedStorage:WaitForChild("CrowdNpcTemplates", 120)
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

local avatars = {}
local hopping, hopCount = {}, 0
local walkers, walkerCount = {}, 0
local posing = {} -- avatars holding a moving pose
local posingCount = 0
local pending = {}
local nearQueue = {}
local buildToken = 0
local present = false -- the crowd is in the stands
local anthemOn = false -- the stadium anthem: everyone sways together
local wave = nil -- a Mexican wave going round: { start, angle, speed, id }
local arriveNow = false -- (a rebuild while the stands were full: fill them again next frame)
local glowCount = 0

local function pick(list)
    return list[rng:NextInteger(1, #list)]
end

local function tuned(name, default)
    return tonumber(Workspace:GetAttribute(name)) or default
end

local function eyeDistance(a)
    return (a.pos - camera.CFrame.Position).Magnitude
end

local function facing(pos, target)
    return CFrame.lookAt(pos, Vector3.new(target.X, pos.Y, target.Z))
end

-- ============================================================================
-- FACES (the nearest only)
-- ============================================================================

local function faceGui(head)
    local gui = Instance.new("SurfaceGui")
    gui.Name = "CrowdFace"
    gui.Face = Enum.NormalId.Front
    gui.CanvasSize = Vector2.new(100, 100)
    gui.LightInfluence = 1
    local skin = head.Color
    local function blob(name, pos, size, color, round)
        local f = Instance.new("Frame")
        f.Name = name
        f.AnchorPoint = Vector2.new(0.5, 0.5)
        f.Position = UDim2.fromScale(pos.X, pos.Y)
        f.Size = UDim2.fromScale(size.X, size.Y)
        f.BackgroundColor3 = color or Color3.new(0.08, 0.08, 0.1)
        f.BorderSizePixel = 0
        if round then
            local c = Instance.new("UICorner")
            c.CornerRadius = UDim.new(1, 0)
            c.Parent = f
        end
        f.Parent = gui
        return f
    end
    local parts = {
        eyeL = blob("EyeL", Vector2.new(0.36, 0.42), Vector2.new(0.09, 0.13), nil, true),
        eyeR = blob("EyeR", Vector2.new(0.64, 0.42), Vector2.new(0.09, 0.13), nil, true),
        browL = blob("BrowL", Vector2.new(0.36, 0.29), Vector2.new(0.14, 0.03)),
        browR = blob("BrowR", Vector2.new(0.64, 0.29), Vector2.new(0.14, 0.03)),
        mouth = blob("Mouth", Vector2.new(0.5, 0.68), Vector2.new(0.3, 0.16), nil, true),
    }
    parts.lid = blob("MouthCover", Vector2.new(0.5, 0.63), Vector2.new(0.34, 0.1), skin) -- (makes the mouth a smile)
    parts.lid.ZIndex = 2
    return gui, parts
end

local EXPRESSIONS = {
    neutral = { eye = 0.13, brow = 0, mouth = Vector2.new(0.24, 0.04), mouthY = 0.68, lid = false },
    happy = { eye = 0.13, brow = 0, mouth = Vector2.new(0.3, 0.16), mouthY = 0.66, lid = true },
    cheer = { eye = 0.04, brow = -8, mouth = Vector2.new(0.28, 0.26), mouthY = 0.7, lid = false },
    shocked = { eye = 0.17, brow = 0, mouth = Vector2.new(0.12, 0.16), mouthY = 0.72, lid = false, browY = 0.25 },
    angry = { eye = 0.09, brow = 18, mouth = Vector2.new(0.26, 0.05), mouthY = 0.72, lid = false },
    talk = { eye = 0.13, brow = 0, mouth = Vector2.new(0.22, 0.12), mouthY = 0.68, lid = false },
}

local function setExpression(a, name)
    a.expression = name
    local f = a.face
    if not f then
        return
    end
    local e = EXPRESSIONS[name] or EXPRESSIONS.neutral
    f.parts.eyeL.Size = UDim2.fromScale(0.09, e.eye)
    f.parts.eyeR.Size = UDim2.fromScale(0.09, e.eye)
    f.parts.browL.Rotation = e.brow
    f.parts.browR.Rotation = -e.brow
    f.parts.browL.Position = UDim2.fromScale(0.36, e.browY or 0.29)
    f.parts.browR.Position = UDim2.fromScale(0.64, e.browY or 0.29)
    f.parts.mouth.Size = UDim2.fromScale(e.mouth.X, e.mouth.Y)
    f.parts.mouth.Position = UDim2.fromScale(0.5, e.mouthY)
    f.parts.lid.Visible = e.lid
end

-- The face drawn over the head's own: a classic head's face decal is hidden, a mesh head's
-- texture (the face painted into it) is swapped for its plain skin until the camera moves away
local function setFace(a, on)
    if on and not a.face and a.head then
        local gui, parts = faceGui(a.head)
        gui.Parent = a.head
        a.face = { gui = gui, parts = parts }
        if a.decal then
            a.decal.Transparency = 1
        elseif a.head:IsA("MeshPart") then
            a.headTexture = a.head.TextureID
            a.head.TextureID = ""
        end
        setExpression(a, a.expression or "neutral")
    elseif not on and a.face then
        a.face.gui:Destroy()
        a.face = nil
        if a.decal then
            a.decal.Transparency = 0
        elseif a.headTexture then
            a.head.TextureID = a.headTexture
        end
    end
end

-- ============================================================================
-- JOINTS: poses and hops
-- ============================================================================

local function joint(model, partName, jointName)
    local p = model:FindFirstChild(partName)
    local j = p and p:FindFirstChild(jointName)
    return j and j:IsA("Motor6D") and j or nil
end

local rad = math.rad

local function syncTime()
    return Workspace:GetServerTimeNow() -- (the same moment on every player's machine)
end

-- pose -> function(t, phase) returning { joint key = CFrame }; t is server time, so the poses
-- that ignore `phase` (anthem, pump) move in unison across the stadium
local POSES = {
    anthem = function(t)
        local sway = math.sin(t * math.pi * 2 / ANTHEM_PERIOD)
        return {
            Waist = CFrame.Angles(0, 0, rad(7 * sway)),
            LS = CFrame.Angles(rad(150), 0, rad(-12 + 16 * sway)), RS = CFrame.Angles(rad(150), 0, rad(12 + 16 * sway)),
            LE = CFrame.Angles(rad(20), 0, 0), RE = CFrame.Angles(rad(20), 0, 0),
            Neck = CFrame.Angles(rad(12), 0, rad(-5 * sway)),
        }
    end,
    pump = function(t)
        local beat = (t / CHANT_BEAT) % 1
        local lift = math.sin(math.pi * math.min(1, beat * 1.6))
        return {
            RS = CFrame.Angles(rad(120 + 50 * lift), 0, rad(8)), RE = CFrame.Angles(rad(70 - 60 * lift), 0, 0),
            Neck = CFrame.Angles(rad(6 + 6 * lift), 0, 0),
        }
    end,
    cheer = function(t, p)
        local sway = math.sin(t * 7 + p) * 18
        return { LS = CFrame.Angles(rad(165), 0, rad(-sway)), RS = CFrame.Angles(rad(165), 0, rad(sway)) }
    end,
    clap = function(t, p)
        local c = math.abs(math.sin(t * 9 + p)) * 30
        return {
            LS = CFrame.Angles(rad(70), rad(-20 + c), 0), RS = CFrame.Angles(rad(70), rad(20 - c), 0),
            LE = CFrame.Angles(rad(40), 0, 0), RE = CFrame.Angles(rad(40), 0, 0),
        }
    end,
    point = function(t, p)
        return { RS = CFrame.Angles(rad(100 + math.sin(t * 5 + p) * 8), 0, 0), Neck = CFrame.Angles(rad(5), 0, 0) }
    end,
    head = function() -- hands on the head
        return {
            LS = CFrame.Angles(rad(150), 0, rad(-40)), RS = CFrame.Angles(rad(150), 0, rad(40)),
            LE = CFrame.Angles(rad(110), 0, 0), RE = CFrame.Angles(rad(110), 0, 0),
        }
    end,
    slump = function()
        return { Waist = CFrame.Angles(rad(-14), 0, 0), Neck = CFrame.Angles(rad(-22), 0, 0) }
    end,
    talk = function(t, p)
        return {
            Neck = CFrame.Angles(rad(math.sin(t * 5 + p) * 6), rad(math.sin(t * 1.3 + p) * 8), 0),
            RS = CFrame.Angles(rad(28 + math.sin(t * 3 + p) * 14), 0, rad(-10)),
            RE = CFrame.Angles(rad(50), 0, 0),
        }
    end,
    walk = function(t, p)
        local s = math.sin(t * 8 + p)
        return {
            LH = CFrame.Angles(rad(s * 28), 0, 0), RH = CFrame.Angles(rad(-s * 28), 0, 0),
            LS = CFrame.Angles(rad(-s * 22), 0, 0), RS = CFrame.Angles(rad(s * 22), 0, 0),
        }
    end,
}
local JOINT_KEYS = { "LS", "RS", "LE", "RE", "LH", "RH", "Waist", "Neck" }

local function clearJoints(a)
    for _, k in ipairs(JOINT_KEYS) do
        local j = a.joints[k]
        if j then
            j.Transform = CFrame.identity
        end
    end
end

local function applyPose(a)
    local fn = POSES[a.pose]
    if not fn then
        return
    end
    local set = fn(syncTime(), a.phase)
    for _, k in ipairs(JOINT_KEYS) do
        local j = a.joints[k]
        if j then
            j.Transform = set[k] or CFrame.identity
        end
    end
end

-- A pose for `seconds` (nil: until changed). The nearest animate instead.
local function setPose(a, name, seconds)
    a.poseUntil = seconds and (os.clock() + seconds) or nil
    if a.pose == name then
        return
    end
    a.pose = name
    if name == "idle" then
        if posing[a] then
            posing[a] = nil
            posingCount -= 1
        end
        if not a.emote then
            clearJoints(a)
        end
    elseif a.shown then
        if not posing[a] then
            posing[a] = true
            posingCount += 1
        end
        if not a.emote then
            applyPose(a)
        end
    end
end

-- ============================================================================
-- ANIMATION (the nearest only)
-- ============================================================================

local function track(a, name)
    local t = a.tracks[name]
    if not t and a.animator then
        t = a.animator:LoadAnimation(animations[name])
        t.Looped = LOOPED[name] == true
        t.Priority = (name == "idle" or name == "walk") and Enum.AnimationPriority.Core or Enum.AnimationPriority.Action
        a.tracks[name] = t
    end
    return t
end

-- (no idle animation: on these rigs Roblox's default idle bends the knees ~30 degrees into a
-- crouch; standing still reads better, and only emotes and the walk animate)
local function setNear(a, near)
    if a.near == near then
        return
    end
    a.near = near
    if near then
        clearJoints(a)
        if a.walking then
            local w = track(a, "walk")
            if w then
                w:Play(0.3)
            end
        end
    else
        for _, t in pairs(a.tracks) do
            t:Stop(0.3)
        end
        a.emote = nil
        if a.pose ~= "idle" then
            applyPose(a)
        end
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

local EMOTE_FOR = { cheer = "cheer", clap = "wave", point = "point" }
local FACE_FOR = { cheer = "cheer", clap = "happy", point = "angry", head = "shocked", slump = "angry", talk = "talk", dance = "cheer" }

-- An avatar's answer: an emote for the nearest, a pose for the rest, and a face
local function express(a, kind, seconds)
    setExpression(a, FACE_FOR[kind] or "happy")
    a.faceUntil = os.clock() + (seconds or 2)
    if kind == "dance" then
        if a.near then
            emote(a, pick({ "dance1", "dance2", "dance3" }), seconds)
        end
        setPose(a, "cheer", seconds)
    else
        if a.near and EMOTE_FOR[kind] then
            emote(a, EMOTE_FOR[kind], seconds)
        end
        setPose(a, kind, seconds)
    end
end

-- ============================================================================
-- HOPS, WALKS, TALKS
-- ============================================================================

local function hop(a, times, height)
    if hopping[a] or hopCount >= tuned("CrowdHopMax", HOP_MAX) or not a.rootJoint or not a.shown then
        return
    end
    if eyeDistance(a) > HOP_RANGE then
        return
    end
    hopping[a] = { start = os.clock(), times = times, height = (height or 2.2) * rng:NextNumber(0.75, 1.25) }
    hopCount += 1
    express(a, "cheer", times * HOP_TIME + 0.3) -- (arms up while jumping)
end

local function startWalk(a)
    if a.walking or not a.shown or hopping[a] then
        return
    end
    if a.to - a.from < 6 then
        return
    end
    local here = a.axis == 1 and a.pos.X or a.pos.Z
    local goal = math.clamp(here + (rng:NextNumber() < 0.5 and -1 or 1) * rng:NextNumber(10, 45), a.from, a.to)
    if math.abs(goal - here) < 4 then
        return
    end
    walkers[a] = { goal = goal, speed = rng:NextNumber(WALK_SPEED[1], WALK_SPEED[2]) }
    walkerCount += 1
    a.walking = true
    if a.near then
        local w = track(a, "walk")
        if w then
            w:Play(0.25)
        end
    end
    setPose(a, "walk")
end

local function stopWalk(a)
    if not a.walking then
        return
    end
    walkers[a] = nil
    walkerCount -= 1
    a.walking = false
    a.home = facing(a.pos, ARENA_CENTER)
    if a.near and a.tracks.walk then
        a.tracks.walk:Stop(0.25)
    end
    setPose(a, "idle")
end

local lastBubble = 0
local function talk(a)
    local b = a and a.neighbor
    if not b or not a.shown or not b.shown or a.walking or b.walking or a.talking or b.talking then
        return
    end
    local seconds = rng:NextNumber(4, 9)
    for _, x in ipairs({ a, b }) do
        x.talking = os.clock() + seconds
        x.root.CFrame = facing(x.pos, (x == a and b or a).pos)
        express(x, "talk", seconds)
    end
    if os.clock() - lastBubble > 1.2 and eyeDistance(a) < BUBBLE_RANGE and a.head then
        lastBubble = os.clock()
        pcall(function()
            TextChatService:DisplayBubble(a.head, pick(LINES))
        end)
    end
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
    if now < a.busyUntil or not a.shown or a.walking then
        return
    end
    if category:find("Celebration") then
        a.busyUntil = now + 7
        hop(a, rng:NextInteger(3, 6), 2.6)
        express(a, rng:NextNumber() < 0.5 and "dance" or "cheer", 7)
    elseif isPositive(category) then
        a.busyUntil = now + (major and 3.5 or 2)
        if category:find("Applause") then
            express(a, "clap", 2.5)
        else
            express(a, pick({ "cheer", "cheer", "clap", "point" }), major and 3 or 2)
            if major or rng:NextNumber() < 0.45 then
                hop(a, major and rng:NextInteger(1, 3) or 1, major and 2.4 or 1.6)
            end
        end
    elseif isNegative(category) then
        a.busyUntil = now + 2.5
        if category:find("Gasp") or category:find("Shock") then
            express(a, "head", 2.5)
        elseif rng:NextNumber() < 0.45 then
            express(a, "point", 2) -- (booing)
        else
            express(a, "slump", 3)
        end
    end
end

-- ============================================================================
-- BUILD, ARRIVE, LEAVE
-- ============================================================================

local function clear()
    avatars, hopping, hopCount, walkers, walkerCount, posing, pending = {}, {}, 0, {}, 0, {}, {}
    posingCount = 0
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
    local wasPresent = present
    present = false
    clear()
    local looks = templates:GetChildren()
    table.sort(looks, function(x, y)
        return (tonumber(x.Name:match("%d+")) or 0) < (tonumber(y.Name:match("%d+")) or 0)
    end)
    local grid = {}
    for i, entry in ipairs(layout or {}) do
        local look = looks[entry[4]] or looks[1]
        if look then
            local pos = Vector3.new(entry[1], entry[2], entry[3])
            local model = look:Clone()
            model:PivotTo(facing(pos, ARENA_CENTER))
            local head = model:FindFirstChild("Head")
            local controller = model:FindFirstChildOfClass("AnimationController")
            local a = {
                model = model,
                root = model.PrimaryPart or model:FindFirstChild("HumanoidRootPart"),
                pos = pos,
                section = entry[5],
                axis = entry[6] or 1,
                from = entry[7] or pos.X,
                to = entry[8] or pos.X,
                animator = controller and controller:FindFirstChildOfClass("Animator"),
                head = head,
                decal = head and head:FindFirstChild("face"),
                rootJoint = joint(model, "LowerTorso", "Root"),
                joints = {
                    LS = joint(model, "LeftUpperArm", "LeftShoulder"), RS = joint(model, "RightUpperArm", "RightShoulder"),
                    LE = joint(model, "LeftLowerArm", "LeftElbow"), RE = joint(model, "RightLowerArm", "RightElbow"),
                    LH = joint(model, "LeftUpperLeg", "LeftHip"), RH = joint(model, "RightUpperLeg", "RightHip"),
                    Waist = joint(model, "UpperTorso", "Waist"), Neck = joint(model, "Head", "Neck"),
                },
                phase = rng:NextNumber(0, 6.28),
                angle = math.deg(math.atan2(pos.Z - ARENA_CENTER.Z, pos.X - ARENA_CENTER.X)) % 360,
                tracks = {},
                near = false,
                shown = false,
                pose = "idle",
                busyUntil = 0,
            }
            table.insert(avatars, a)
            local key = math.floor(pos.X / 4) .. ":" .. math.floor(pos.Z / 4)
            grid[key] = grid[key] or {}
            table.insert(grid[key], a)
        end
        if i % 80 == 0 then
            RunService.Heartbeat:Wait()
            if token ~= buildToken then
                return
            end
        end
    end
    -- each avatar's nearest neighbour on the same bench (someone to talk to)
    for _, a in ipairs(avatars) do
        local cx, cz = math.floor(a.pos.X / 4), math.floor(a.pos.Z / 4)
        local best, bestD = nil, 5.5
        for dx = -1, 1 do
            for dz = -1, 1 do
                for _, b in ipairs(grid[(cx + dx) .. ":" .. (cz + dz)] or {}) do
                    local d = (b.pos - a.pos).Magnitude
                    if b ~= a and d < bestD and math.abs(b.pos.Y - a.pos.Y) < 1 then
                        best, bestD = b, d
                    end
                end
            end
        end
        a.neighbor = best
    end
    print(string.format("[ArenaCrowdClient] %d crowd avatars ready (layout v%d)", #avatars, version or 0))
    if wasPresent or Workspace:GetAttribute("CrowdAlwaysOn") == true then
        task.defer(function()
            arriveNow = true
        end)
    end
end

-- Flicker in (or out) like the Quins' teleport; the nearest also glow cyan
local function glitch(a, arriving)
    local parts = {}
    for _, d in ipairs(a.model:GetDescendants()) do
        if d:IsA("BasePart") or d:IsA("Decal") then
            table.insert(parts, d)
        end
    end
    local glow = nil
    if glowCount < GLOW_MAX and eyeDistance(a) < 160 then
        glowCount += 1
        glow = Instance.new("Highlight")
        glow.FillColor = Color3.fromRGB(0, 200, 255)
        glow.OutlineTransparency = 1
        glow.DepthMode = Enum.HighlightDepthMode.Occluded
        glow.Parent = a.model
    end
    task.spawn(function()
        local started = os.clock()
        while a.model.Parent do
            local progress = math.clamp((os.clock() - started) / GLITCH_TIME, 0, 1)
            local solid = arriving and progress or 1 - progress
            local shown = (progress < 1 and rng:NextNumber() < 0.2) and 0 or math.clamp(solid + rng:NextNumber(-0.3, 0.3), 0, 1)
            if progress >= 1 then
                shown = arriving and 1 or 0
            end
            for _, d in ipairs(parts) do
                d.LocalTransparencyModifier = 1 - shown
            end
            if glow then
                glow.FillTransparency = rng:NextNumber(0.25, 0.85)
            end
            if progress >= 1 then
                break
            end
            task.wait(rng:NextNumber(0.04, 0.09))
        end
        if glow then
            glow:Destroy()
            glowCount -= 1
        end
        if not arriving then
            a.model.Parent = nil
        end
    end)
end

local function arrive(instant)
    if present then
        return
    end
    present = true
    local order = table.clone(avatars)
    for i = #order, 2, -1 do
        local j = rng:NextInteger(1, i)
        order[i], order[j] = order[j], order[i]
    end
    task.spawn(function()
        local started = os.clock()
        for i, a in ipairs(order) do
            if not present then
                return
            end
            local at = instant and 0 or (i / #order) * ARRIVE_TIME
            while os.clock() - started < at do
                RunService.Heartbeat:Wait()
            end
            a.model.Parent = folder
            a.shown = true
            if not instant and eyeDistance(a) < POSE_RANGE then
                glitch(a, true)
            end
            -- some come in already busy
            local roll = rng:NextNumber()
            if roll < 0.08 then
                startWalk(a)
            elseif roll < 0.18 then
                express(a, pick({ "cheer", "clap" }), rng:NextNumber(2, 4))
            elseif roll < 0.26 then
                talk(a)
            end
            if instant and i % 100 == 0 then
                RunService.Heartbeat:Wait()
            end
        end
    end)
end

local function leave()
    if not present then
        return
    end
    present = false
    local list = table.clone(avatars)
    task.spawn(function()
        local started = os.clock()
        for i, a in ipairs(list) do
            if present then
                return
            end
            local at = (i / #list) * LEAVE_TIME
            while os.clock() - started < at do
                RunService.Heartbeat:Wait()
            end
            a.shown = false
            stopWalk(a)
            setPose(a, "idle")
            if a.model.Parent and eyeDistance(a) < POSE_RANGE then
                glitch(a, false)
            else
                a.model.Parent = nil
            end
        end
    end)
end

local function setAnthem(on)
    if anthemOn == on then
        return
    end
    anthemOn = on
    for _, a in ipairs(avatars) do
        if a.shown then
            if on then
                stopWalk(a)
                if a.emote and a.tracks[a.emote] then
                    a.tracks[a.emote]:Stop(0.3)
                    a.emote = nil
                end
                setPose(a, "anthem")
                setExpression(a, "talk") -- (singing)
                a.faceUntil = nil
            else
                setPose(a, "idle")
                setExpression(a, "happy")
                a.faceUntil = os.clock() + 3
            end
        end
    end
end

local lastPhase = nil
local function onPhase(phase)
    setAnthem(phase == "STADIUM_ANTHEM")
    if Workspace:GetAttribute("CrowdAlwaysOn") == true then
        arrive(true)
    elseif phase == "IDLE" then
        leave()
    elseif phase then
        arrive(false)
    end
end

if stateRemote then
    stateRemote.OnClientEvent:Connect(function(snap)
        local phase = type(snap) == "table" and snap.Phase or nil
        if phase ~= lastPhase then
            local joined = lastPhase == nil
            lastPhase = phase
            if joined and phase ~= "IDLE" then
                arrive(true) -- (joined mid-match: already seated)
            else
                onPhase(phase)
            end
        end
    end)
end
Workspace:GetAttributeChangedSignal("CrowdAlwaysOn"):Connect(function()
    if Workspace:GetAttribute("CrowdAlwaysOn") == true then
        arrive(true)
    elseif lastPhase == "IDLE" or lastPhase == nil then
        leave()
    end
end)

remote.OnClientEvent:Connect(function(kind, a1, a2, a3, a4)
    if kind == "layout" then
        task.spawn(build)
    elseif kind == "react" and present then
        local team, category, major, teams = a1, a2, a3, a4 or {}
        if type(category) ~= "string" then
            return
        end
        local chance = (category:find("Celebration") and 1 or major and 0.95 or (isPositive(category) and 0.5 or 0.35)) * tuned("CrowdReactScale", 1)
        local now = os.clock()
        for _, a in ipairs(avatars) do
            if (team == nil or teams[a.section] == team) and rng:NextNumber() < chance then
                table.insert(pending, { at = now + rng:NextNumber(0, major and 0.5 or 0.8), avatar = a, category = category, major = major })
            end
        end
    elseif kind == "wave" and present then
        wave = { start = a1, angle = a2, speed = a3, id = (wave and wave.id or 0) + 1 }
    elseif kind == "mood" and present and not anthemOn then
        local excitement, teams, chant = a1 or {}, a2 or {}, a3
        if chant then
            -- the chanted team's sections pump their fists together, on the beat
            for _, a in ipairs(avatars) do
                if a.shown and not a.walking and teams[a.section] == chant and rng:NextNumber() < 0.35 then
                    setPose(a, "pump", 1.3)
                    setExpression(a, "cheer")
                    a.faceUntil = os.clock() + 1.3
                end
            end
        end
        for _ = 1, math.max(1, math.floor(#avatars * 0.07)) do
            local a = avatars[rng:NextInteger(1, math.max(1, #avatars))]
            if a and os.clock() >= a.busyUntil and not a.walking then
                local level = excitement[teams[a.section] or "Neutral"] or excitement.Neutral or 0.2
                if rng:NextNumber() < 0.4 + level then
                    a.busyUntil = os.clock() + 2.5
                    express(a, pick({ "cheer", "cheer", "clap", "point" }), 2)
                    if level > 0.45 and rng:NextNumber() < 0.55 then
                        hop(a, level > 0.75 and 2 or 1, 1.8)
                    end
                end
            end
        end
    end
end)

-- ============================================================================
-- PER FRAME
-- ============================================================================

local lastLod, lastLife = 0, 0
local walkParts, walkFrames = {}, {}

RunService.RenderStepped:Connect(function(dt)
    if arriveNow then
        arriveNow = false
        arrive(true)
    end
    local now = os.clock()
    if #avatars == 0 then
        return
    end

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

    -- animation on / off, a few a frame
    for _ = 1, NEAR_CHANGES_PER_FRAME do
        local change = table.remove(nearQueue)
        if not change then
            break
        end
        setNear(change.a, change.near)
    end

    -- the Mexican wave: the stands rise as it passes
    if wave and present then
        local elapsed = syncTime() - wave.start
        if elapsed > 360 / wave.speed + 1 then
            wave = nil
        elseif elapsed >= 0 then
            local at = (wave.angle + elapsed * wave.speed) % 360
            for _, a in ipairs(avatars) do
                if a.shown and a.waveId ~= wave.id then
                    local d = (a.angle - at + 540) % 360 - 180
                    if d > -WAVE_WIDTH and d <= 0 then
                        a.waveId = wave.id
                        if not a.walking then
                            express(a, "cheer", 1.1)
                            hop(a, 1, 2.2)
                        end
                    end
                end
            end
        end
    end

    -- hops: the Root joint lifts the body
    if hopCount > 0 then
        for a, h in pairs(hopping) do
            local elapsed = now - h.start
            local n = math.floor(elapsed / HOP_TIME)
            if n >= h.times or not a.model.Parent then
                hopping[a] = nil
                hopCount -= 1
                a.rootJoint.Transform = CFrame.identity
            else
                local u = (elapsed - n * HOP_TIME) / HOP_TIME
                a.rootJoint.Transform = CFrame.new(0, h.height * math.sin(math.pi * u), 0)
            end
        end
    end

    -- walkers: along their bench row, one batched move
    if walkerCount > 0 then
        table.clear(walkParts)
        table.clear(walkFrames)
        local done = {}
        for a, w in pairs(walkers) do
            local here = a.axis == 1 and a.pos.X or a.pos.Z
            local step = math.sign(w.goal - here) * w.speed * dt
            local arrived = math.abs(w.goal - here) <= math.abs(step) + 0.01
            local value = arrived and w.goal or here + step
            local dir = a.axis == 1 and Vector3.new(math.sign(step), 0, 0) or Vector3.new(0, 0, math.sign(step))
            a.pos = a.axis == 1 and Vector3.new(value, a.pos.Y, a.pos.Z) or Vector3.new(a.pos.X, a.pos.Y, value)
            table.insert(walkParts, a.root)
            table.insert(walkFrames, (arrived or dir.Magnitude < 0.5) and facing(a.pos, ARENA_CENTER) or CFrame.lookAt(a.pos, a.pos + dir))
            if arrived then
                table.insert(done, a)
            end
        end
        if #walkParts > 0 then
            Workspace:BulkMoveTo(walkParts, walkFrames, Enum.BulkMoveMode.FireCFrameChanged)
        end
        for _, a in ipairs(done) do
            stopWalk(a)
        end
    end

    -- poses, a slice a frame: an avatar posed less than its turn ago is passed over, so every
    -- posed avatar gets its turn (about budget / count of them a frame)
    local budget = anthemOn and POSE_UPDATES_ANTHEM or POSE_UPDATES_PER_FRAME
    local range = anthemOn and math.huge or POSE_RANGE
    local turn = math.max(0, (posingCount / budget) * dt * 0.9)
    for a in pairs(posing) do
        if budget <= 0 then
            break
        end
        if a.poseUntil and now > a.poseUntil then
            setPose(a, anthemOn and "anthem" or (a.walking and "walk" or "idle"))
        elseif not a.emote and (a.posedAt or 0) <= now - turn and eyeDistance(a) < range then
            a.posedAt = now
            applyPose(a)
            budget -= 1
        end
    end

    -- the life of the stands: walks, chats; faces calm down, talkers turn back (not in the anthem:
    -- then everyone is singing together)
    if now - lastLife > 0.5 and present and not anthemOn then
        lastLife = now
        local n = #avatars
        for _ = 1, 3 do
            if walkerCount < math.floor(n * WALKER_SHARE) then
                local a = avatars[rng:NextInteger(1, n)]
                if now >= a.busyUntil and not a.talking then
                    startWalk(a)
                end
            end
        end
        for _ = 1, math.max(1, math.floor(n * TALK_SHARE / 12)) do
            talk(avatars[rng:NextInteger(1, n)])
        end
        for _, a in ipairs(avatars) do
            if a.talking and now > a.talking then
                a.talking = nil
                if not a.walking then
                    a.root.CFrame = facing(a.pos, ARENA_CENTER)
                end
            end
            if a.faceUntil and now > a.faceUntil then
                a.faceUntil = nil
                setExpression(a, "neutral")
            end
        end
    end

    -- level of detail
    if now - lastLod > 0.5 then
        lastLod = now
        local eye = camera.CFrame.Position
        local inRange = {}
        for _, a in ipairs(avatars) do
            if a.shown then
                local d = (a.pos - eye).Magnitude
                if d < ANIMATE_RANGE then
                    table.insert(inRange, { a = a, d = d })
                end
            end
        end
        table.sort(inRange, function(x, y)
            return x.d < y.d
        end)
        local animateMax = tuned("CrowdAnimateMax", ANIMATE_MAX)
        local chosen, faced = {}, {}
        for i, item in ipairs(inRange) do
            if i <= animateMax then
                chosen[item.a] = true
            end
            if i <= FACE_MAX and item.d < FACE_RANGE then
                faced[item.a] = true
            end
        end
        table.clear(nearQueue)
        for _, a in ipairs(avatars) do
            local want = chosen[a] == true
            if a.near ~= want then
                table.insert(nearQueue, { a = a, near = want })
            end
            local wantFace = faced[a] == true
            if (a.face ~= nil) ~= wantFace then
                setFace(a, wantFace)
            end
        end
    end

    -- talking mouths (the faces near the camera)
    for _, a in ipairs(avatars) do
        if a.face and a.expression == "talk" then
            a.face.parts.mouth.Size = UDim2.fromScale(0.2, math.sin(now * 14 + a.phase) > 0 and 0.13 or 0.04)
        end
    end
end)

task.spawn(build)
