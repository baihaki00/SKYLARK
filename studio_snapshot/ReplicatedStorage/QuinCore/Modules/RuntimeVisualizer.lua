--// RuntimeVisualizer.lua
-- 3D debug overlay for the Quins, drawn on the spectator's client.
--
-- The overlay is a set of layers, each switched on or off from the Spectator HUD
-- (DebugDraw.Layers lists them). Two kinds of layer:
--   * client layers  - computed here from replicated state (attributes, velocity): overhead
--     label, target / line of sight, last seen position, velocity + facing, flight prediction;
--   * server layers  - submitted by the Quins' own reasoning code through DebugDraw (raycasts,
--     steering, pursuit, jump plans, retreat options, decision scores) and only drawn here.
-- Everything is drawn immediate-mode from pools: each frame the active layers ask for lines,
-- spheres, rings and text; whatever was not asked for is hidden.

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local QuinCore = ReplicatedStorage:WaitForChild("QuinCore")
local CombatConfig = require(QuinCore:WaitForChild("CombatConfig"))
local SpatialModule = require(QuinCore:WaitForChild("Modules"):WaitForChild("SpatialModule"))
local DebugDraw = require(QuinCore:WaitForChild("Modules"):WaitForChild("DebugDraw"))

local RuntimeVisualizer = {}

local GRAVITY = Vector3.new(0, -Workspace.Gravity, 0)
local VISUALIZER_FOLDER_NAME = "QuinDebugVisualizers"

local COLOR = {
	clear = Color3.fromRGB(0, 255, 128),
	blocked = Color3.fromRGB(255, 45, 65),
	memory = Color3.fromRGB(255, 170, 0),
	velocity = Color3.fromRGB(0, 220, 255),
	facing = Color3.fromRGB(245, 245, 255),
	rise = Color3.fromRGB(0, 220, 255),
	apex = Color3.fromRGB(255, 230, 80),
	fall = Color3.fromRGB(255, 120, 30),
	impact = Color3.fromRGB(0, 255, 220),
	label = Color3.fromRGB(240, 245, 255),
}

-- ============================================================
-- State: master switch, layers, scope
-- ============================================================
local isEnabled = CombatConfig.DebugVisualizers_Enabled ~= false
local layerEnabled = {} -- [layerId] = true; every layer starts off
local watchAll = false -- false: only the spectated Quin; true: every Quin

function RuntimeVisualizer.isEnabled()
	return isEnabled
end

function RuntimeVisualizer.setEnabled(value)
	isEnabled = value
	if not isEnabled then
		RuntimeVisualizer.clear()
	end
end

function RuntimeVisualizer.toggle()
	RuntimeVisualizer.setEnabled(not isEnabled)
	return isEnabled
end

function RuntimeVisualizer.getLayers()
	return DebugDraw.Layers
end

function RuntimeVisualizer.isLayerEnabled(layerId)
	return layerEnabled[layerId] == true
end

function RuntimeVisualizer.setLayerEnabled(layerId, value)
	layerEnabled[layerId] = value and true or nil
end

function RuntimeVisualizer.isWatchingAll()
	return watchAll
end

function RuntimeVisualizer.setWatchAll(value)
	watchAll = value == true
end

-- ============================================================
-- Pools (immediate-mode drawing)
-- ============================================================
local container = nil
local function getContainer()
	if not container or not container.Parent then
		container = Workspace:FindFirstChild(VISUALIZER_FOLDER_NAME)
		if not container then
			container = Instance.new("Folder")
			container.Name = VISUALIZER_FOLDER_NAME
			container.Parent = Workspace
		end
	end
	return container
end

-- Anchor for the pools: an invisible part kept just in front of the camera. Adornments are
-- culled with the part they adorn, so one left at the world origin (or Terrain) draws nothing
-- from across the arena. Everything is positioned relative to it (anchorOrigin).
local anchorPart = nil
local anchorOrigin = Vector3.zero
local function getAnchor()
	if not anchorPart or not anchorPart.Parent then
		anchorPart = Instance.new("Part")
		anchorPart.Name = "DebugDrawAnchor"
		anchorPart.Size = Vector3.new(1, 1, 1)
		anchorPart.CFrame = CFrame.identity
		anchorPart.Anchored = true
		anchorPart.Transparency = 1
		anchorPart.CanCollide = false
		anchorPart.CanQuery = false
		anchorPart.CanTouch = false
		anchorPart.Parent = getContainer()
	end
	return anchorPart
end

local function newPool(create, hide)
	return { items = {}, used = 0, create = create, hide = hide }
end

local function take(pool)
	pool.used += 1
	local item = pool.items[pool.used]
	if not item or not item.Parent then
		item = pool.create()
		pool.items[pool.used] = item
	end
	return item
end

local function finishPool(pool)
	for i = pool.used + 1, #pool.items do
		pool.hide(pool.items[i])
	end
	pool.used = 0
end

local function newAdornment(className)
	local adornment = Instance.new(className)
	-- ZIndex is left at its default: with any other value an AlwaysOnTop adornment is not drawn
	adornment.AlwaysOnTop = true
	adornment.Adornee = getAnchor()
	adornment.Parent = getAnchor()
	return adornment
end

local function hideAdornment(adornment)
	adornment.Visible = false
end

local linePool = newPool(function()
	local line = newAdornment("LineHandleAdornment")
	line.Thickness = 3
	return line
end, hideAdornment)

local spherePool = newPool(function()
	return newAdornment("SphereHandleAdornment")
end, hideAdornment)

local ringPool = newPool(function()
	local ring = newAdornment("CylinderHandleAdornment")
	ring.Height = 0.15
	ring.Transparency = 0.45
	return ring
end, hideAdornment)

local textPool = newPool(function()
	local anchor = Instance.new("Attachment")
	anchor.Name = "DebugTextAnchor"
	anchor.Parent = getAnchor()

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "DebugText"
	billboard.Size = UDim2.new(0, 340, 0, 110)
	billboard.AlwaysOnTop = true
	billboard.Adornee = anchor
	billboard.Parent = getAnchor()

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextSize = 11
	label.TextYAlignment = Enum.TextYAlignment.Bottom
	label.TextStrokeTransparency = 0.2
	label.TextStrokeColor3 = Color3.new(0, 0, 0)
	label.Parent = billboard
	return billboard
end, function(billboard)
	billboard.Enabled = false
end)

local draw = {}

function draw.line(from, to, color, thickness)
	local delta = to - from
	if delta.Magnitude < 0.01 then return end
	local line = take(linePool)
	line.CFrame = CFrame.lookAt(from - anchorOrigin, to - anchorOrigin)
	line.Length = delta.Magnitude
	line.Color3 = color
	line.Thickness = thickness or 3
	line.Visible = true
end

function draw.sphere(position, radius, color)
	local sphere = take(spherePool)
	sphere.CFrame = CFrame.new(position - anchorOrigin)
	sphere.Radius = radius
	sphere.Color3 = color
	sphere.Visible = true
end

-- Flat ring on the ground
function draw.ring(position, radius, color)
	local ring = take(ringPool)
	ring.CFrame = CFrame.new(position - anchorOrigin) * CFrame.Angles(math.rad(90), 0, 0)
	ring.Radius = radius
	ring.InnerRadius = radius * 0.8
	ring.Color3 = color
	ring.Visible = true
end

function draw.text(position, text, color)
	local billboard = take(textPool)
	billboard.Adornee.WorldPosition = position
	billboard.Label.Text = text
	billboard.Label.TextColor3 = color
	billboard.Enabled = true
end

local function finishFrame()
	finishPool(linePool)
	finishPool(spherePool)
	finishPool(ringPool)
	finishPool(textPool)
end

-- Remove everything the overlay has drawn
function RuntimeVisualizer.clear()
	finishFrame()
	DebugDraw.clearLive()
end

-- ============================================================
-- Client layers
-- ============================================================
local function findTarget(fighter)
	local targetName = fighter:GetAttribute("CurrentTarget") or fighter:GetAttribute("TargetQuin")
	if not targetName or targetName == "" then return nil end
	local quinServer = Workspace:FindFirstChild("QuinServer") or Workspace
	return quinServer:FindFirstChild(targetName) or Workspace:FindFirstChild(targetName)
end

local clientLayers = {}

-- State, health, energy, speed and what the Quin reports about obstacles
function clientLayers.Label(fighter, rootPart)
	local humanoid = fighter:FindFirstChildOfClass("Humanoid")
	draw.text(rootPart.Position + Vector3.new(0, 5.2, 0), string.format("%s | %s\nHP %d | Mana %d | %.1f studs/s\n%s | %s\nknows %d enemies (notices %d) | target via %s",
		fighter.Name,
		string.upper(fighter:GetAttribute("CurrentState") or "None"),
		humanoid and math.round(humanoid.Health) or 0,
		fighter:GetAttribute("Energy") or 100,
		rootPart.AssemblyLinearVelocity.Magnitude,
		fighter:GetAttribute("TacticalState") or "-",
		fighter:GetAttribute("ObstacleAwareness") or "Clear",
		fighter:GetAttribute("KnownEnemies") or 0,
		fighter:GetAttribute("NoticedEnemies") or 0,
		fighter:GetAttribute("TargetContact") or "-"), COLOR.label)
end

-- Eye-to-eye line to the current target: green with line of sight, red without
function clientLayers.Target(fighter, rootPart, target)
	local targetRoot = target and target:FindFirstChild("HumanoidRootPart")
	if not targetRoot then return end
	local hasLoS = fighter:GetAttribute("TargetHasLoS") == true
	draw.line(SpatialModule.getEyePosition(rootPart), SpatialModule.getEyePosition(targetRoot), hasLoS and COLOR.clear or COLOR.blocked, hasLoS and 3 or 5)
end

-- Where the Quin last saw its target, while it cannot see it
function clientLayers.Memory(fighter, rootPart, target)
	local lastSeen = fighter:GetAttribute("LastSeenTargetPosition")
	if not lastSeen or fighter:GetAttribute("TargetHasLoS") == true then return end
	draw.ring(lastSeen + Vector3.new(0, 0.2, 0), 3, COLOR.memory)
	draw.line(rootPart.Position, lastSeen, COLOR.memory, 2)
	draw.text(lastSeen + Vector3.new(0, 2.5, 0), "last seen: " .. (target and target.Name or "target"), COLOR.memory)
end

-- Velocity (half a second of travel) and facing
function clientLayers.Velocity(fighter, rootPart)
	local origin = rootPart.Position
	draw.line(origin, origin + rootPart.AssemblyLinearVelocity * 0.5, COLOR.velocity, 4)
	draw.line(origin, origin + rootPart.CFrame.LookVector * 5, COLOR.facing, 2)
end

-- Ballistic prediction of a body in flight, with the landing point
function clientLayers.Trajectory(fighter, rootPart)
	local velocity = rootPart.AssemblyLinearVelocity
	local state = fighter:GetAttribute("CurrentState") or ""
	local inFlight = state == "Airborne" or state == "Knockback" or state == "ProjectileJump"
		or math.abs(velocity.Y) > 10
	if not inFlight then return end

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = { fighter, getContainer(), Workspace:FindFirstChild("QuinServer") }

	local position = rootPart.Position
	local step = 0.05
	for i = 1, 35 do
		local nextPosition = position + velocity * step + 0.5 * GRAVITY * (step * step)
		local hit = Workspace:Raycast(position, nextPosition - position, rayParams)
		local color = velocity.Y > 5 and COLOR.rise or (velocity.Y > -10 and COLOR.apex or COLOR.fall)
		draw.line(position, hit and hit.Position or nextPosition, color)
		if hit then
			draw.ring(hit.Position + Vector3.new(0, 0.1, 0), 2.5, COLOR.impact)
			draw.text(hit.Position + Vector3.new(0, 1.8, 0), string.format("lands in %.2fs", i * step), COLOR.impact)
			return
		end
		position = nextPosition
		velocity += GRAVITY * step
	end
end

local function drawClientLayers(fighter)
	local rootPart = fighter:FindFirstChild("HumanoidRootPart")
	if not rootPart then return end
	local target = findTarget(fighter)
	for _, layer in ipairs(DebugDraw.Layers) do
		if layer.source == "client" and layerEnabled[layer.id] then
			clientLayers[layer.id](fighter, rootPart, target)
		end
	end
end

-- ============================================================
-- Server layers: draw what the Quins submitted
-- ============================================================
local function drawServerPrimitive(primitive)
	if not layerEnabled[DebugDraw.Layers[primitive[2]].id] then return end
	local kind = primitive[1]
	if kind == DebugDraw.Kind.Line then
		draw.line(primitive[3], primitive[4], primitive[5], 2)
	elseif kind == DebugDraw.Kind.Sphere then
		draw.sphere(primitive[3], primitive[4], primitive[5])
	else
		draw.text(primitive[3], primitive[7], primitive[5])
	end
end

-- ============================================================
-- Frame update (called by the Spectator HUD while it is open)
-- ============================================================
function RuntimeVisualizer.update(spectatedFighter, allFighters)
	if not isEnabled then
		DebugDraw.configure({}, false, nil)
		return
	end

	local spectatedName = spectatedFighter and spectatedFighter.Parent and spectatedFighter.Name or nil
	DebugDraw.configure(layerEnabled, watchAll, spectatedName)

	local cameraFrame = Workspace.CurrentCamera.CFrame
	anchorOrigin = cameraFrame.Position + cameraFrame.LookVector * 12
	getAnchor().CFrame = CFrame.new(anchorOrigin)

	if watchAll and allFighters then
		for _, fighter in ipairs(allFighters) do
			if fighter.Parent then drawClientLayers(fighter) end
		end
	elseif spectatedName then
		drawClientLayers(spectatedFighter)
	end

	DebugDraw.forEachLive(drawServerPrimitive)
	finishFrame()
end

-- The HUD closed: stop the server sending and take everything off screen
function RuntimeVisualizer.stop()
	DebugDraw.configure({}, false, nil)
	RuntimeVisualizer.clear()
end

return RuntimeVisualizer
