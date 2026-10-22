--// ArenaCrowdClient.client.lua
-- The NPC crowd on the stands, drawn on this machine only (ArenaCrowdNpcs.server lays out the
-- stands and passes on the procedural crowd's reactions).
--
-- The crowd comes and goes like a real one (owner): a few when the arena opens, more through
-- the preparation, almost full for the anthem, full for the fight (ATTENDANCE). Five minutes into
-- the fight some start heading home, and through the arena closure the stands empty slowly; at
-- IDLE the rest go. Arrivals flicker in, holographic (the nearest with a cyan glow), some already
-- walking, cheering or chatting. Leavers either walk off along their row and flicker out on the
-- way, flicker out where they stand, or (a pair) agree on plans ("wanna grab a bite at the ATC?"
-- / "Sure! Let's go, you lead the way.") and walk off together.
--
-- Three distances, so thousands still look alive at little cost:
--   near (ANIMATE_MAX within ANIMATE_RANGE): Roblox animations and emotes, an expressive face
--     (FACE_MAX within FACE_RANGE: eyes, brows and a mouth that cheer, gasp, boo and talk), chat
--     bubbles;
--   middle (within POSE_RANGE): poses written straight to the joints a few avatars a frame (arms
--     up, clapping, pointing, hands on the head, slumping, walking legs, talking nods);
--   far: still, which at that distance reads the same.
-- Nobody stares at one point: fans look about (turning left and right, to a neighbour), walkers
-- keep their distance (they wait, or turn back, rather than walk through someone), and
-- neighbours hold real conversations (CrowdChatter: one speaks, the other answers a moment later,
-- back and forth; pre-game, live and post-game lines; bubbles near the camera).
-- Every hop raises the arms. Hops and poses go through the joints' Transform (what animations
-- write); the looks are rigid Motor6D bodies, so none of it wakes physics.
-- Reactions: cheers and roars -> cheering, clapping, jumping (big moments: jumping again and again,
-- dancing); groans and disappointment -> booing (pointing, slumping); gasps -> hands on the head.
-- The anthem is loud and pumping (owner): almost the whole stadium goes off, each fan at their own
-- random pace (hopping, punching the air, waving, clapping, screaming with arms up), switching
-- every few bars; the music's kick (40-80 Hz, ArenaBassPulse: shared.ArenaBass) only adds a
-- light bounce and nod on top (owner: the on-beat stuff subtle, everything else random).
-- Mexican waves round the stands (the server starts them, so every player sees the same), and
-- chants (the chanted team's sections pump their fists).
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
local ANTHEM_FALLBACK_BEAT = 60 / 128 -- seconds per beat when the music cannot be heard
local HOP_SHARE = 0.55 -- of a hopper's own rhythm spent off the floor
local BEAT_ACCENT = 0.2 -- the kick's bounce and nod (owner: subtle; 1 = the old full strength)
local ULTRAS = 2 -- areas of the stands that hop the most in the anthem
local ULTRAS_WIDTH = 55 -- degrees round the arena
local ANTHEM_BUILD = 8 -- seconds for the stands to get going
local LIVELY_SHARE = 0.03 -- of the crowd starting something new every half second in the fight
local CHANT_BEAT = 0.5 -- seconds per fist pump
local WAVE_WIDTH = 9 -- degrees of the stands up at once
local HOP_MAX = 250 -- avatars in the air at once
local HOP_RANGE = 450
local HOP_TIME = 0.42 -- seconds per hop
local WALKER_SHARE = 0.06 -- of the crowd walking at any time
local WALK_SPEED = { 3.5, 6 } -- studs/s
local TALK_SHARE = 0.05 -- of the crowd chatting at any time
local BUBBLE_RANGE = 90
local LOOK_SHARE = 0.05 -- of the crowd turning to look somewhere new every half second
local LOOK_SPREAD = 55 -- degrees either side of the arena they may look
local TURN_TIME = 0.6 -- seconds to turn
local PERSONAL_SPACE = 2.2 -- studs a walker keeps from anyone in their way
local RESPOND_PER_FRAME = 60
local NEAR_CHANGES_PER_FRAME = 12
local ATTENDANCE = { -- of the crowd in the stands, by arena phase
    ARENA_OPEN = 0.15, ARENA_GENERATION = 0.3, PREPARATION_ROOM = 0.5, TELEPORTING_QUINS = 0.7,
    STADIUM_ANTHEM = 0.9, PRE_GAME = 0.95, IN_GAME = 1, WINNER_DETERMINATION = 1, POST_GAME = 0.85,
}
local LEAVE_AFTER = 300 -- seconds into the fight before anyone heads home
local LEAVE_PER_MINUTE = 0.03 -- of the crowd heading home each minute after that (up to 25%)
local CLOSURE_LEAVE = 0.012 -- of the crowd leaving each second of the arena closure
local ARRIVE_RATE = 0.12 -- of the gap filled each second (at least 4 a second)
local GLITCH_TIME = 0.9
local GLOW_MAX = 20 -- cyan glows at once (Roblox draws ~31 highlights)
local ARENA_CENTER = Vector3.new(0, 0, -438)

local IDS = {
    idle = "507766388", walk = "507777826", cheer = "507770677", wave = "507770239", point = "507770453",
    laugh = "507770818", dance1 = "507771019", dance2 = "507776043", dance3 = "507777268",
}
local LOOPED = { idle = true, walk = true, dance1 = true, dance2 = true, dance3 = true }

local CrowdChatter = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("CrowdChatter"))

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
local turning = {} -- avatar -> { from, to, start } (yaw in radians)
local grid = {} -- "x:z" cell (4 studs) -> avatars standing there (walkers keep it current)

local function cellOf(pos)
    return math.floor(pos.X / 4) .. ":" .. math.floor(pos.Z / 4)
end

local function yawTo(from, to)
    local d = to - from
    return math.atan2(-d.X, -d.Z)
end

-- Turn to face a yaw (radians) over TURN_TIME
local function turnTo(a, yaw)
    local current = a.yaw or yawTo(a.pos, ARENA_CENTER)
    local diff = (yaw - current + math.pi) % (2 * math.pi) - math.pi
    turning[a] = { from = current, to = current + diff, start = os.clock() }
end
local posing = {} -- avatars holding a moving pose
local posingCount = 0
local pending = {}
local nearQueue = {}
local buildToken = 0
local present = false -- the crowd is in the stands
local shownCount = 0 -- in the stands and not on their way out
local vanish = nil -- (attendance: flicker out and gone)
local lastPhaseForChat = nil -- (the arena phase, for what the crowd talks about)
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

-- The anthem's beat, from its drum stem's loudness (a hit: well over the running average)
local beat = { last = 0, interval = ANTHEM_FALLBACK_BEAT, count = 0, avg = 0, drum = nil, scanAt = 0, u = 0, signalAt = 0 }

local function findDrum()
    -- (the anthem's stems play on the ArenaGlobe and the stands' emitters, inside ArenaOne)
    local arena = Workspace:FindFirstChild("argoniaonion") and Workspace.argoniaonion:FindFirstChild("ArenaOne")
    for _, d in ipairs(arena and arena:GetDescendants() or {}) do
        if d:IsA("Sound") and d.IsPlaying and d.Name:upper():find("DRUM") then
            return d
        end
    end
    return nil
end

local function updateBeat(now)
    -- the kick heard by ArenaBassPulse (40-80 Hz), when it hears the music
    local heard = shared.ArenaBass
    if heard and heard.live then
        if heard.beatAt > beat.last then
            beat.last = heard.beatAt
            beat.interval = heard.interval
            beat.count += 1
        end
        beat.u = math.clamp((now - beat.last) / math.max(0.2, beat.interval), 0, 1)
        return
    end
    local drum = beat.drum
    if not (drum and drum.Parent and drum.IsPlaying) then
        beat.drum = nil
        if now >= beat.scanAt then
            beat.scanAt = now + 1.5
            beat.drum = findDrum()
        end
    end
    local hit = false
    local loud = beat.drum and beat.drum.PlaybackLoudness or 0
    if loud > 1 then
        beat.signalAt = now
    end
    -- (no drum, or one that gives no signal: the player's audio is off: a steady pulse instead)
    if beat.drum and now - beat.signalAt < 2 then
        beat.avg += (loud - beat.avg) * 0.08
        if loud > beat.avg * 1.3 + 8 and now - beat.last > 0.24 then
            local gap = now - beat.last
            if gap < 1.2 then
                beat.interval = beat.interval * 0.7 + gap * 0.3
            end
            hit = true
        end
    elseif now - beat.last >= beat.interval then
        hit = true
    end
    if hit then
        beat.last = now
        beat.count += 1
    end
    beat.u = math.clamp((now - beat.last) / math.max(0.2, beat.interval), 0, 1)
end

local function syncTime()
    return Workspace:GetServerTimeNow() -- (the same moment on every player's machine)
end

-- pose -> function(t, phase) returning { joint key = CFrame }; t is server time, so the poses
-- that ignore `phase` (anthem, pump) move in unison across the stadium
local POSES = {
    anthem = function(_, p, a)
        local now = os.clock()
        local rate = a.rate or 2
        local cycle = (now * rate + p) % 1 -- this fan's own rhythm
        local wobble = math.sin((now * rate + p) * math.pi * 2)
        -- the beat: a light accent for everyone (subtle)
        local tb = (now - beat.last) - (a.lag or 0)
        if tb < 0 then
            tb += beat.interval
        end
        local k = math.exp(-tb * 9) * BEAT_ACCENT
        local accent = CFrame.new(0, 0.6 * k, 0)
        local role = a.role
        local amp = a.amp or 1
        if role == "hop" then
            -- hops on their own rhythm, a real arc each time
            local x = cycle / HOP_SHARE
            local lift = x < 1 and 4 * x * (1 - x) * (a.hopH or 1.3) or 0
            return {
                Root = CFrame.new(0, lift, 0) * accent,
                LS = CFrame.Angles(rad(150 + 12 * wobble), 0, rad(-14)), RS = CFrame.Angles(rad(150 - 12 * wobble), 0, rad(14)),
                LE = CFrame.Angles(rad(20), 0, 0), RE = CFrame.Angles(rad(20), 0, 0),
                Neck = CFrame.Angles(rad(12), 0, 0),
            }
        elseif role == "pump" then
            local punch = math.max(0, math.sin(cycle * math.pi * 2)) ^ 0.6
            return {
                Root = accent,
                RS = CFrame.Angles(rad(110 + 60 * punch * amp), 0, rad(8)), RE = CFrame.Angles(rad(80 - 70 * punch), 0, 0),
                LS = CFrame.Angles(rad(35), 0, rad(-8)), LE = CFrame.Angles(rad(70), 0, 0),
                Neck = CFrame.Angles(rad(8 - 18 * punch * amp - 10 * k), 0, 0),
            }
        elseif role == "clap" then
            local c = math.abs(math.sin(cycle * math.pi))
            return {
                Root = accent,
                LS = CFrame.Angles(rad(75), rad(-30 + 24 * c), 0), RS = CFrame.Angles(rad(75), rad(30 - 24 * c), 0),
                LE = CFrame.Angles(rad(45), 0, 0), RE = CFrame.Angles(rad(45), 0, 0),
                Neck = CFrame.Angles(rad(-8 * k), 0, 0),
            }
        elseif role == "scream" then
            -- both arms up, shaking, leaning in
            return {
                Root = accent,
                LS = CFrame.Angles(rad(160 + 8 * wobble), 0, rad(-20 + 10 * wobble)), RS = CFrame.Angles(rad(160 - 8 * wobble), 0, rad(20 + 10 * wobble)),
                LE = CFrame.Angles(rad(25), 0, 0), RE = CFrame.Angles(rad(25), 0, 0),
                Waist = CFrame.Angles(rad(-6), 0, 0), Neck = CFrame.Angles(rad(18), 0, 0),
            }
        end
        -- wave: arms up, swinging side to side at their own pace
        local sway = math.sin((now * rate * 0.5 + p) * math.pi * 2) * amp
        return {
            Root = accent,
            Waist = CFrame.Angles(0, 0, rad(9 * sway)),
            LS = CFrame.Angles(rad(150), 0, rad(-10 + 26 * sway)), RS = CFrame.Angles(rad(150), 0, rad(10 + 26 * sway)),
            Neck = CFrame.Angles(rad(10 - 6 * k), 0, rad(-7 * sway)),
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
    local set = fn(syncTime(), a.phase, a)
    for _, k in ipairs(JOINT_KEYS) do
        local j = a.joints[k]
        if j then
            j.Transform = set[k] or CFrame.identity
        end
    end
    if set.Root and a.rootJoint and not hopping[a] then
        a.rootJoint.Transform = set.Root
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
    if a.walking or not a.shown or a.departing or hopping[a] then
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
    turnTo(a, yawTo(a.pos, ARENA_CENTER) + math.rad(rng:NextNumber(-25, 25)))
    if a.near and a.tracks.walk then
        a.tracks.walk:Stop(0.25)
    end
    setPose(a, "idle")
    if a.departing and vanish then
        vanish(a) -- (a leaver's walk is over: gone)
    end
end

local function chatPhase()
    if lastPhaseForChat == "IN_GAME" then
        return "live"
    elseif lastPhaseForChat == "WINNER_DETERMINATION" or lastPhaseForChat == "POST_GAME" then
        return "post"
    end
    return "pre"
end

local function bubble(a, text)
    if a.head and eyeDistance(a) < BUBBLE_RANGE then
        pcall(function()
            TextChatService:DisplayBubble(a.head, text)
        end)
    end
end

-- Two neighbours talk: they turn to each other, one says something, the other answers a moment
-- later, sometimes back and forth; the speaker's mouth moves, the listener nods along
local function talk(a)
    local b = a and a.neighbor
    if not b or not a.shown or not b.shown or a.walking or b.walking or a.talking or b.talking then
        return
    end
    local turns = CrowdChatter.conversation(chatPhase(), rng)
    local seconds = 1.5 + #turns * 2.6
    for _, x in ipairs({ a, b }) do
        x.talking = os.clock() + seconds
        turnTo(x, yawTo(x.pos, (x == a and b or a).pos))
        setPose(x, "talk", seconds)
        setExpression(x, "happy")
    end
    task.spawn(function()
        task.wait(rng:NextNumber(0.3, 0.9))
        for _, t in ipairs(turns) do
            if not (a.shown and b.shown) then
                return
            end
            local speaker, listener = t.who == 1 and a or b, t.who == 1 and b or a
            setExpression(speaker, "talk")
            setExpression(listener, rng:NextNumber() < 0.3 and "cheer" or "happy")
            bubble(speaker, t.text)
            task.wait(rng:NextNumber(1.8, 3.2)) -- (the other takes it in, then answers)
            setExpression(speaker, "happy")
        end
    end)
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
    shownCount = 0
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
    grid = {}
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
            local key = cellOf(pos)
            grid[key] = grid[key] or {}
            table.insert(grid[key], a)
            a.cell = key
            -- (not all facing one point: each a little off, their own way)
            a.yaw = yawTo(pos, ARENA_CENTER) + math.rad(rng:NextNumber(-25, 25))
            model:PivotTo(CFrame.new(pos) * CFrame.Angles(0, a.yaw, 0))
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

-- The anthem: what each fan does, by how hot their part of the stands is and how far in it is
local anthemStart, ultras = 0, {}

local function heatAt(angle)
    local h = 0.22
    for _, centre in ipairs(ultras) do
        local d = math.abs((angle - centre + 540) % 360 - 180)
        h = math.max(h, 1 - d / ULTRAS_WIDTH)
    end
    return h
end

local function chooseRole(a)
    local energy = math.clamp((os.clock() - anthemStart) / ANTHEM_BUILD, 0.6, 1)
    local h = heatAt(a.angle)
    local weights = {
        { "hop", (0.18 + 0.25 * h) * energy }, { "pump", 0.2 * energy }, { "wave", 0.24 }, { "clap", 0.12 },
        { "scream", 0.14 * energy }, { "calm", 0.05 },
    }
    local total = 0
    for _, w in ipairs(weights) do
        total += w[2]
    end
    local roll = rng:NextNumber(0, total)
    for _, w in ipairs(weights) do
        roll -= w[2]
        if roll <= 0 then
            return w[1]
        end
    end
    return "calm"
end

local function setRole(a, role)
    a.role = role
    a.rerollAt = beat.count + rng:NextInteger(4, 12)
    if role == "calm" then
        -- chatting, walking about, just watching (the life of the stands carries on)
        setPose(a, "idle")
        if a.rootJoint and not hopping[a] then
            a.rootJoint.Transform = CFrame.identity
        end
        setExpression(a, rng:NextNumber() < 0.5 and "happy" or "neutral")
    else
        stopWalk(a)
        setPose(a, "anthem")
        setExpression(a, role == "clap" and "happy" or "cheer")
    end
    a.faceUntil = nil
end

local function setAnthem(on)
    if anthemOn == on then
        return
    end
    anthemOn = on
    if on then
        anthemStart = os.clock()
        ultras = {}
        for _ = 1, ULTRAS do
            table.insert(ultras, rng:NextNumber(0, 360))
        end
    end
    for _, a in ipairs(avatars) do
        if a.shown then
            if on then
                if a.emote and a.tracks[a.emote] then
                    a.tracks[a.emote]:Stop(0.3)
                    a.emote = nil
                end
                a.lag = rng:NextNumber(-0.03, 0.1)
                a.hopH = rng:NextNumber(0.7, 1.8)
                a.rate = rng:NextNumber(1.2, 2.8) -- (their own pace: cycles a second)
                a.amp = rng:NextNumber(0.6, 1.25)
                setRole(a, chooseRole(a))
            else
                setPose(a, "idle")
                if a.rootJoint and not hopping[a] then
                    a.rootJoint.Transform = CFrame.identity
                end
                setExpression(a, "happy")
                a.faceUntil = os.clock() + 3
            end
        end
    end
end

-- ============================================================================
-- ATTENDANCE: arriving and leaving
-- ============================================================================

local phaseStarted = os.clock()
local cap = 1 -- (once people head home the stands don't fill up again)
local instantFill = false
local arriveBudget, leaveBudget = 0, 0

local function attendance(now)
    if Workspace:GetAttribute("CrowdAlwaysOn") == true then
        return 1
    end
    local phase = lastPhaseForChat
    if phase == nil or phase == "IDLE" then
        return 0
    end
    local share = ATTENDANCE[phase] or 0.5
    local t = now - phaseStarted
    local leaving = phase == "WINNER_DETERMINATION" or phase == "POST_GAME"
    if phase == "IN_GAME" and t > LEAVE_AFTER then
        share -= math.min(0.25, (t - LEAVE_AFTER) / 60 * LEAVE_PER_MINUTE)
        leaving = true
    elseif phase == "POST_GAME" then
        share = math.max(0.05, share - t * CLOSURE_LEAVE)
    end
    if leaving then
        share = math.min(share, cap)
        cap = share
    end
    return share
end

local function show(a, instant)
    a.model.Parent = folder
    a.shown = true
    a.departing = false
    shownCount += 1
    if not instant and eyeDistance(a) < POSE_RANGE then
        glitch(a, true)
    end
    if anthemOn then
        a.lag = rng:NextNumber(-0.03, 0.1)
        a.hopH = rng:NextNumber(0.7, 1.8)
        a.rate = rng:NextNumber(1.2, 2.8)
        a.amp = rng:NextNumber(0.6, 1.25)
        setRole(a, chooseRole(a))
        return
    end
    -- some come in already busy
    local roll = rng:NextNumber()
    if roll < 0.1 then
        startWalk(a)
    elseif roll < 0.2 then
        express(a, pick({ "cheer", "clap" }), rng:NextNumber(2, 4))
    elseif roll < 0.28 then
        talk(a)
    end
end

vanish = function(a)
    if not a.shown then
        return
    end
    a.departing = false
    stopWalk(a)
    a.shown = false
    a.talking = nil
    turning[a] = nil
    setPose(a, "idle")
    if a.model.Parent and eyeDistance(a) < POSE_RANGE then
        glitch(a, false)
    else
        a.model.Parent = nil
    end
end

-- Off along the row toward `goal` (a position on its axis), flickering out on the way
local function walkOut(a, goal)
    if a.to - a.from < 6 or hopping[a] then
        vanish(a)
        return
    end
    local here = a.axis == 1 and a.pos.X or a.pos.Z
    goal = math.clamp(goal or ((math.abs(here - a.from) < math.abs(here - a.to)) and a.from or a.to), a.from, a.to)
    if a.walking then
        walkers[a] = nil
        walkerCount -= 1
        a.walking = false
    end
    walkers[a] = { goal = goal, speed = rng:NextNumber(WALK_SPEED[1], WALK_SPEED[2]), leaveBy = os.clock() + rng:NextNumber(3, 9) }
    walkerCount += 1
    a.walking = true
    if a.near then
        local w = track(a, "walk")
        if w then
            w:Play(0.25)
        end
    end
    setPose(a, "walk")
    setExpression(a, "happy")
end

-- Two neighbours agree on plans for after, then walk off together
local function leaveTogether(a, b)
    local turns = CrowdChatter.leaving(rng)
    local seconds = 1 + #turns * 2.6
    for _, x in ipairs({ a, b }) do
        x.departing = true
        x.talking = os.clock() + seconds
        turnTo(x, yawTo(x.pos, (x == a and b or a).pos))
        setPose(x, "talk", seconds)
        setExpression(x, "happy")
    end
    task.spawn(function()
        task.wait(rng:NextNumber(0.3, 0.8))
        for _, t in ipairs(turns) do
            if not (a.shown and b.shown) then
                break
            end
            local speaker, listener = t.who == 1 and a or b, t.who == 1 and b or a
            setExpression(speaker, "talk")
            setExpression(listener, "happy")
            bubble(speaker, t.text)
            task.wait(rng:NextNumber(1.8, 3.2))
            setExpression(speaker, "happy")
        end
        -- the same way out, the first leading
        local here = a.axis == 1 and a.pos.X or a.pos.Z
        local towardTo = math.abs(here - a.to) < math.abs(here - a.from)
        for i, x in ipairs({ a, b }) do
            if x.shown and x.departing then
                x.talking = nil
                task.delay((i - 1) * rng:NextNumber(0.3, 0.8), function()
                    if x.shown and x.departing then
                        walkOut(x, towardTo and x.to or x.from)
                    end
                end)
            end
        end
    end)
end

-- One fan heads home: walks off, flickers out where they are, or leaves with the neighbour
local function depart(a)
    a.departing = true
    shownCount -= 1
    local idle = lastPhaseForChat == "IDLE" or lastPhaseForChat == nil
    local b = a.neighbor
    local roll = rng:NextNumber()
    if not idle and not anthemOn and roll < 0.3 and b and b.shown and not b.departing and not a.talking and not b.talking
        and not a.walking and not b.walking then
        b.departing = true
        shownCount -= 1
        leaveTogether(a, b)
    elseif roll < (idle and 0.5 or 0.7) and not anthemOn then
        if a.talking then
            a.talking = nil
        end
        walkOut(a)
    else
        vanish(a)
    end
end

local function updateAttendance(now, dt)
    local n = #avatars
    if n == 0 then
        return
    end
    -- leavers walking too long flicker out where they are
    local late = nil
    for a, w in pairs(walkers) do
        if w.leaveBy and now > w.leaveBy then
            late = late or {}
            table.insert(late, a)
        end
    end
    for _, a in ipairs(late or {}) do
        stopWalk(a)
    end
    local want = math.floor(attendance(now) * n + 0.5)
    local gap = want - shownCount
    if gap > 0 then
        if instantFill then
            arriveBudget = math.min(gap, 150) -- (a frame's worth)
        else
            arriveBudget = math.min(arriveBudget + math.max(4, gap * ARRIVE_RATE) * dt, gap)
        end
        local tries = 0
        while arriveBudget >= 1 and tries < 400 do
            tries += 1
            local a = avatars[rng:NextInteger(1, n)]
            if not a.shown then
                show(a, instantFill)
                arriveBudget -= 1
            end
        end
        if instantFill and want - shownCount <= 0 then
            instantFill = false
        end
    elseif gap < 0 then
        instantFill = false
        local idle = lastPhaseForChat == "IDLE" or lastPhaseForChat == nil
        local rate = idle and math.max(30, -gap * 0.6) or math.max(1.5, -gap * 0.08)
        leaveBudget = math.min(leaveBudget + rate * dt, -gap)
        local tries = 0
        while leaveBudget >= 1 and tries < 200 do
            tries += 1
            local a = avatars[rng:NextInteger(1, n)]
            if a.shown and not a.departing then
                depart(a)
                leaveBudget -= 1
            end
        end
    else
        arriveBudget, leaveBudget = 0, 0
        instantFill = false
    end
    if shownCount <= 0 and want == 0 then
        present = false
    end
end

-- (the old names: the stands now fill and empty by attendance)
local function arrive(instant)
    present = true
    if instant then
        instantFill = true
    end
end

local function leave()
    -- (attendance empties the stands at IDLE)
end

local lastPhase = nil
local function onPhase(phase)
    lastPhaseForChat = phase
    phaseStarted = os.clock()
    if phase == "IDLE" or ATTENDANCE[phase] and ATTENDANCE[phase] < 1 and phase ~= "POST_GAME" then
        cap = 1 -- (a new arena day)
    end
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
        lastPhaseForChat = phase
        if phase ~= lastPhase then
            local joined = lastPhase == nil
            lastPhase = phase
            if joined and phase ~= "IDLE" then
                phaseStarted = os.clock()
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
    updateAttendance(now, dt)

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

    -- turning (looking about, to a neighbour, back to the arena)
    for a, t in pairs(turning) do
        local u = math.clamp((now - t.start) / TURN_TIME, 0, 1)
        u = u * u * (3 - 2 * u)
        a.yaw = t.from + (t.to - t.from) * u
        if not a.walking then
            a.root.CFrame = CFrame.new(a.pos) * CFrame.Angles(0, a.yaw, 0)
        end
        if u >= 1 then
            turning[a] = nil
        end
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
            local nextPos = a.axis == 1 and Vector3.new(value, a.pos.Y, a.pos.Z) or Vector3.new(a.pos.X, a.pos.Y, value)
            -- someone in the way: wait a moment, then turn back rather than walk through them
            local blocked = false
            local cx, cz = math.floor(nextPos.X / 4), math.floor(nextPos.Z / 4)
            for dx = -1, 1 do
                for dz = -1, 1 do
                    for _, other in ipairs(grid[(cx + dx) .. ":" .. (cz + dz)] or {}) do
                        if other ~= a and other.shown and math.abs(other.pos.Y - a.pos.Y) < 2 then
                            local ahead = (other.pos - a.pos):Dot(dir)
                            if ahead > 0 and (other.pos - nextPos).Magnitude < PERSONAL_SPACE then
                                blocked = true
                            end
                        end
                    end
                end
            end
            if blocked then
                w.waited = (w.waited or 0) + dt
                if w.waited > rng:NextNumber(0.8, 1.6) then
                    table.insert(done, a) -- (gives up: stops here)
                end
            else
                w.waited = 0
                a.pos = nextPos
                local key = cellOf(a.pos)
                if key ~= a.cell then
                    local list = grid[a.cell]
                    local i = list and table.find(list, a)
                    if i then
                        table.remove(list, i)
                    end
                    grid[key] = grid[key] or {}
                    table.insert(grid[key], a)
                    a.cell = key
                end
                a.yaw = math.atan2(-dir.X, -dir.Z)
                table.insert(walkParts, a.root)
                table.insert(walkFrames, CFrame.new(a.pos) * CFrame.Angles(0, a.yaw, 0))
                if arrived then
                    table.insert(done, a)
                end
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
    if anthemOn then
        local before = beat.count
        updateBeat(now)
        if beat.count ~= before then
            -- a new beat: a few fans change what they are doing
            for _ = 1, math.max(1, math.floor(#avatars / 40)) do
                local a = avatars[rng:NextInteger(1, #avatars)]
                if a.shown and a.rerollAt and beat.count >= a.rerollAt and not a.talking then
                    setRole(a, chooseRole(a))
                end
            end
        end
    end
    for a in pairs(posing) do
        if budget <= 0 then
            break
        end
        if a.poseUntil and now > a.poseUntil then
            setPose(a, (anthemOn and a.role and a.role ~= "calm") and "anthem" or (a.walking and "walk" or "idle"))
        elseif anthemOn and a.near and not a.emote then
            applyPose(a) -- (the nearest, every frame: the jumps and headbangs read crisp up close)
        elseif not a.emote and (a.posedAt or 0) <= now - turn and eyeDistance(a) < range then
            a.posedAt = now
            applyPose(a)
            budget -= 1
        end
    end

    -- the life of the stands: walks, chats; faces calm down, talkers turn back (not in the anthem:
    -- then everyone is singing together)
    if now - lastLife > 0.5 and present then
        lastLife = now
        local n = #avatars
        -- (in the anthem only the calm ones walk and chat: the rest are moving to the music)
        local function free(a)
            return not anthemOn or a.role == "calm"
        end
        for _ = 1, 3 do
            if walkerCount < math.floor(n * WALKER_SHARE * (anthemOn and 0.5 or 1)) then
                local a = avatars[rng:NextInteger(1, n)]
                if now >= a.busyUntil and not a.talking and free(a) then
                    startWalk(a)
                end
            end
        end
        for _ = 1, math.max(1, math.floor(n * TALK_SHARE / 12)) do
            local a = avatars[rng:NextInteger(1, n)]
            if free(a) and (not a.neighbor or free(a.neighbor)) then
                talk(a)
            end
        end
        -- looking about: a few fans turn to look somewhere new (along the stands, at a neighbour,
        -- back to the fight)
        for _ = 1, math.max(1, math.floor(n * LOOK_SHARE)) do
            local a = avatars[rng:NextInteger(1, n)]
            if a.shown and not a.walking and not a.talking and not turning[a] then
                local toArena = yawTo(a.pos, ARENA_CENTER)
                if a.neighbor and rng:NextNumber() < 0.2 then
                    turnTo(a, yawTo(a.pos, a.neighbor.pos))
                else
                    turnTo(a, toArena + math.rad(rng:NextNumber(-LOOK_SPREAD, LOOK_SPREAD)))
                end
            end
        end
        -- never just standing and staring: in the fight a slice of the crowd keeps starting
        -- something (cheering, clapping, pointing, a hop), each for its own few seconds
        if not anthemOn and Workspace:GetAttribute("CrowdPhase") == "IN_GAME" then
            for _ = 1, math.max(1, math.floor(n * LIVELY_SHARE)) do
                local a = avatars[rng:NextInteger(1, n)]
                if a.shown and not a.walking and not a.talking and now >= a.busyUntil then
                    local seconds = rng:NextNumber(1.5, 5)
                    a.busyUntil = now + seconds
                    express(a, pick({ "cheer", "cheer", "clap", "clap", "point", "pump" }), seconds)
                    if rng:NextNumber() < 0.15 then
                        hop(a, rng:NextInteger(1, 2), rng:NextNumber(1, 1.8))
                    end
                end
            end
        end
        for _, a in ipairs(avatars) do
            if a.talking and now > a.talking then
                a.talking = nil
                if not a.walking then
                    turnTo(a, yawTo(a.pos, ARENA_CENTER) + math.rad(rng:NextNumber(-20, 20)))
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
