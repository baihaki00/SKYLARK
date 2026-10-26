--// QuinHoloBands.client.lua
-- The team bands: a hologram ring round the RIGHT wrist of every Quin on a team (TeamAlpha / TeamBeta),
-- in its team colour (CombatConfig.TeamColors). Drawn on this machine only, as hollow
-- CylinderHandleAdornments on the Quin's body, moved onto the wrist bones every frame: always
-- on the arm, readable over any sleeve (a hologram may clip - owner, 2026-10-25), and nothing to
-- build. (They replace the layered SYS band items: those never wrapped onto the arms, and were
-- seen floating beside the Quins.)
-- Same rule as the pack leader band (LeaderWristbands): right wrist only, just above the wrist
-- joint; while a Quin is pack leader (SocialRole = "Leader") its leader band shows instead.
-- Quins farther than DRAW_DIST from the camera are not drawn. Workspace attribute
-- HoloBandsOff = true hides them all.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local CombatConfig = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("CombatConfig"))

local DRAW_DIST = 400
local RADIUS = 0.2 -- studs (the wrist is ~0.36 across)
local INNER = 0.16
local HEIGHT = 0.22
local ALONG = 0.9 -- where on the forearm (0 elbow .. 1 wrist; the leader band sits here too)
local TRANSPARENCY = 0.2
local SIDES = { "Right" }

local bands = {} -- [model] = { surf, rings = { {ring, glow, arm, hand} ... }, team }

local function teamColor(team)
    return CombatConfig.TeamColors and CombatConfig.TeamColors[team]
end

local function drop(m)
    local b = bands[m]
    if b then
        for _, r in ipairs(b.rings) do
            r.ring:Destroy()
            r.glow:Destroy()
        end
        bands[m] = nil
    end
end

local function make(m, surf, color)
    local b = { surf = surf, rings = {}, team = m:GetAttribute("Team") }
    for _, side in ipairs(SIDES) do
        local arm = surf:FindFirstChild("mixamorig:" .. side .. "ForeArm", true)
        local hand = surf:FindFirstChild("mixamorig:" .. side .. "Hand", true)
        if arm and hand then
            local ring = Instance.new("CylinderHandleAdornment")
            ring.Name = "HoloBand" .. side
            ring.Radius, ring.InnerRadius, ring.Height = RADIUS, INNER, HEIGHT
            ring.Color3, ring.Transparency = color, TRANSPARENCY
            ring.Adornee = surf
            ring.Parent = surf
            local glow = Instance.new("CylinderHandleAdornment") -- (a faint halo round it)
            glow.Name = "HoloBandGlow" .. side
            glow.Radius, glow.InnerRadius, glow.Height = RADIUS + 0.06, RADIUS, HEIGHT * 0.6
            glow.Color3, glow.Transparency = color:Lerp(Color3.new(1, 1, 1), 0.35), 0.65
            glow.Adornee = surf
            glow.Parent = surf
            table.insert(b.rings, { ring = ring, glow = glow, arm = arm, hand = hand })
        end
    end
    bands[m] = b
    return b
end

local function quins()
    local list = {}
    for _, name in ipairs({ "QuinServer", "PlayerCostumes" }) do
        local folder = Workspace:FindFirstChild(name)
        if folder then
            for _, m in ipairs(folder:GetChildren()) do
                if m:IsA("Model") then
                    table.insert(list, m)
                end
            end
        end
    end
    return list
end

-- which Quins get bands (every 0.25 s)
local function refresh()
    local camera = Workspace.CurrentCamera
    local eye = camera and camera.CFrame.Position or Vector3.zero
    local off = Workspace:GetAttribute("HoloBandsOff")
    local seen = {}
    for _, m in ipairs(quins()) do
        local team = m:GetAttribute("Team")
        local color = teamColor(team)
        local surf = m:FindFirstChild("Alpha_Surface") or m:FindFirstChild("Beta_Surface")
        local root = m:FindFirstChild("HumanoidRootPart")
        local near = root and (root.Position - eye).Magnitude <= DRAW_DIST
        local leader = m:GetAttribute("SocialRole") == "Leader"
        if color and surf and near and not off and not leader then
            seen[m] = true
            local b = bands[m]
            if b and b.team ~= team then
                drop(m)
                b = nil
            end
            if not b then
                make(m, surf, color)
            end
        end
    end
    for m in pairs(bands) do
        if not seen[m] then
            drop(m)
        end
    end
end

RunService.RenderStepped:Connect(function()
    for m, b in pairs(bands) do
        if not m.Parent then
            drop(m)
        else
            local inv = b.surf.CFrame:Inverse()
            -- (a body the game makes invisible - a teleport, a dash effect - takes its bands with it)
            local shown = b.surf.Transparency < 0.5 and b.surf.LocalTransparencyModifier < 0.5
            for _, r in ipairs(b.rings) do
                r.ring.Visible, r.glow.Visible = shown, shown
                local a = r.arm.TransformedWorldCFrame.Position
                local h = r.hand.TransformedWorldCFrame.Position
                local at = a:Lerp(h, ALONG)
                local cf = inv * CFrame.lookAt(at, h) -- (a cylinder adornment runs along its Z)
                r.ring.CFrame = cf
                r.glow.CFrame = cf
            end
        end
    end
end)

while true do
    local ok, err = pcall(refresh)
    if not ok then
        warn("[QuinHoloBands] " .. tostring(err))
    end
    task.wait(0.25)
end
