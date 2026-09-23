--// VfxModule.lua
-- Physical consequences: Dust, Vapor Cones, Shockwaves, Trails
--
-- HOW TO EDIT:
--   * Element COLORS / TEXTURES  -> QuinCore > ElementVfx (one entry per element)
--   * Each EFFECT's shape/speed/size/lifetime -> the functions below (one per effect type)
--
-- Effect type  ->  function
--   Dash (ground trail)        -> createVaporCone
--   Mid-air dash / jump trail  -> createRocketTrail
--   Launch shockwave           -> createLaunchShockwave
--   Shockwave ring             -> createShockwave
--   Debris / dust              -> createDust
--   Knockback trail            -> createKnockbackTrail
--   Impact (hit burst)         -> createStylizedHit

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local VfxModule = {}

local shakeEvent = ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Events"):WaitForChild("CameraShakeEvent")

local QuinCore = ReplicatedStorage:WaitForChild("QuinCore")
local ElementVfx = require(QuinCore:WaitForChild("ElementVfx"))

-- Resolve an element name from a string, a BasePart, or a Model (defaults to "Fire")
local function resolveElement(source, explicit)
	if explicit then return explicit end
	if typeof(source) == "string" then return source end
	if typeof(source) == "Instance" then
		local model = source:IsA("Model") and source or source:FindFirstAncestorOfClass("Model")
		if model then
			local e = model:GetAttribute("Element")
			if e then return e end
		end
	end
	return "Fire"
end

-- Resolve a world position from a Vector3 or a BasePart
local function resolvePosition(source)
	if typeof(source) == "Vector3" then return source end
	if typeof(source) == "Instance" and source:IsA("BasePart") then return source.Position end
	return source
end

-- Helper to create a basic cylinder
local function createCylinder(color, transparency)
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.Massless = true
	part.Shape = Enum.PartType.Cylinder
	part.Material = Enum.Material.Neon
	part.Color = color or Color3.new(1, 1, 1)
	part.Transparency = transparency or 0
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	return part
end

function VfxModule.shakeScreen(position, radius, intensity)
	shakeEvent:FireAllClients(position, radius, intensity)
end

-- ============================================================
-- LAUNCH SHOCKWAVE  (projectile-jump launch burst)
-- ============================================================
function VfxModule.createLaunchShockwave(source, element)
	local position = resolvePosition(source)
	local elem = ElementVfx.get(resolveElement(source, element))

	-- 1. Low-to-ground ring
	local ring = createCylinder(elem.shockwaveColor, 0.4)
	ring.Size = Vector3.new(0.3, 3, 3)
	ring.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.pi / 2)
	ring.Parent = workspace

	local tween = TweenService:Create(ring, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.1, 10, 10),
		Transparency = 1,
	})
	tween:Play()
	Debris:AddItem(ring, 0.3)

	-- 2. Vertical smoke puff
	local pillarAtt = Instance.new("Attachment")
	local pillarPart = Instance.new("Part")
	pillarPart.Anchored = true
	pillarPart.CanCollide = false
	pillarPart.Transparency = 1
	pillarPart.Position = position
	pillarPart.Parent = workspace
	pillarAtt.Parent = pillarPart

	local smoke = Instance.new("ParticleEmitter")
	smoke.Texture = elem.trailTexture
	smoke.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1.2),
		NumberSequenceKeypoint.new(1, 0.5),
	})
	smoke.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.6),
		NumberSequenceKeypoint.new(1, 1),
	})
	smoke.Lifetime = NumberRange.new(0.2, 0.35)
	smoke.Speed = NumberRange.new(15, 30)
	smoke.EmissionDirection = Enum.NormalId.Top
	smoke.SpreadAngle = Vector2.new(10, 10)
	smoke.Color = ColorSequence.new(elem.trailColor)
	smoke.Parent = pillarAtt
	smoke:Emit(6)
	Debris:AddItem(pillarPart, 0.5)

	-- 3. Core flash
	local core = Instance.new("Part")
	core.Shape = Enum.PartType.Ball
	core.Material = Enum.Material.Neon
	core.Color = elem.burstCore
	core.Size = Vector3.new(1, 1, 1)
	core.Anchored = true
	core.CanCollide = false
	core.Position = position
	core.Parent = workspace

	local coreTween = TweenService:Create(core, TweenInfo.new(0.15), {
		Size = Vector3.new(3, 3, 3),
		Transparency = 1,
	})
	coreTween:Play()
	Debris:AddItem(core, 0.2)
end

-- ============================================================
-- MID-AIR DASH / JUMP TRAIL  (rocket streak)
-- ============================================================
function VfxModule.createRocketTrail(rootPart)
	local elem = ElementVfx.get(resolveElement(rootPart))

	local att0 = Instance.new("Attachment")
	att0.Name = "RocketTrailAtt0"
	att0.Position = Vector3.new(0, 1, 0)
	att0.Parent = rootPart

	local att1 = Instance.new("Attachment")
	att1.Name = "RocketTrailAtt1"
	att1.Position = Vector3.new(0, -1, 0)
	att1.Parent = rootPart

	local trail = Instance.new("Trail")
	trail.Name = "RocketTrail"
	trail.Attachment0 = att0
	trail.Attachment1 = att1
	trail.Lifetime = 1.0
	trail.MinLength = 0.1
	trail.Color = ColorSequence.new(elem.trailCore, elem.trailColor)
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	trail.WidthScale = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(1, 0),
	})
	trail.LightEmission = elem.trailEmission
	trail.Parent = rootPart
end

-- ============================================================
-- DASH  (ground dash trail / vapor cone)
-- ============================================================
function VfxModule.createVaporCone(rootPart, duration)
	local elem = ElementVfx.get(resolveElement(rootPart))

	-- Aerodynamic ring (vapor cone)
	local ring = Instance.new("Part")
	ring.Anchored = true
	ring.CanCollide = false
	ring.Massless = true
	ring.Shape = Enum.PartType.Cylinder
	ring.Material = Enum.Material.Neon
	ring.Color = elem.trailColor
	ring.Transparency = 0.4
	ring.TopSurface = Enum.SurfaceType.Smooth
	ring.BottomSurface = Enum.SurfaceType.Smooth
	ring.Size = Vector3.new(0.3, 2.5, 2.5)
	ring.CFrame = rootPart.CFrame * CFrame.Angles(0, math.pi / 2, 0)
	ring.Parent = workspace

	local tween = TweenService:Create(ring, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.1, 8, 8),
		Transparency = 1,
	})
	tween:Play()
	Debris:AddItem(ring, 0.25)

	-- Backward trailing dust
	local att = Instance.new("Attachment")
	att.Parent = rootPart

	local smoke = Instance.new("ParticleEmitter")
	smoke.Texture = elem.trailTexture
	smoke.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1.2),
		NumberSequenceKeypoint.new(1, 0.4),
	})
	smoke.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.6),
		NumberSequenceKeypoint.new(1, 1),
	})
	smoke.Lifetime = NumberRange.new(0.15, 0.25)
	smoke.Speed = NumberRange.new(15, 25)
	smoke.SpreadAngle = Vector2.new(10, 10)
	smoke.Color = ColorSequence.new(elem.trailColor)
	smoke.LightEmission = elem.trailEmission
	smoke.EmissionDirection = Enum.NormalId.Back
	smoke.Parent = att
	smoke:Emit(6)
	Debris:AddItem(att, 0.4)
end

-- ============================================================
-- SHOCKWAVE RING
-- ============================================================
function VfxModule.createShockwave(position, size, duration, element)
	local elem = ElementVfx.get(resolveElement(position, element))
	position = resolvePosition(position)
	local ring = createCylinder(elem.shockwaveColor, 0.2)
	ring.Size = Vector3.new(0.2, 1, 1)
	ring.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.pi / 2)
	ring.Parent = workspace

	local tween = TweenService:Create(ring, TweenInfo.new(duration or 0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.1, size, size),
		Transparency = 1,
	})
	tween:Play()
	Debris:AddItem(ring, duration or 0.5)
end

-- ============================================================
-- DEBRIS / DUST  (physical chunks on impact / landing)
-- ============================================================
function VfxModule.createDust(position, amountOrDir, count, element)
	local elem = ElementVfx.get(resolveElement(position, element))
	position = resolvePosition(position)

	local amount = 3
	if typeof(amountOrDir) == "number" then
		amount = amountOrDir
	elseif typeof(count) == "number" then
		amount = count
	end
	amount = math.clamp(amount, 2, 6)

	for i = 1, amount do
		local dust = Instance.new("Part")
		dust.Anchored = false
		dust.CanCollide = false
		dust.Massless = true
		dust.Size = Vector3.new(0.25, 0.25, 0.25)
		dust.Position = position + Vector3.new(math.random(-2, 2), 0.5, math.random(-2, 2))
		dust.Material = elem.debrisMaterial
		dust.Color = elem.debrisColor

		dust.AssemblyLinearVelocity = Vector3.new(math.random(-12, 12), math.random(6, 18), math.random(-12, 12))

		dust.Parent = workspace
		Debris:AddItem(dust, 0.35)
	end
end

-- ============================================================
-- KNOCKBACK TRAIL  (dust cloud following a knocked-back Quin)
-- ============================================================
function VfxModule.createKnockbackTrail(part, duration)
	local elem = ElementVfx.get(resolveElement(part))

	local attachment = Instance.new("Attachment")
	attachment.Name = "KnockbackTrailAttachment"
	attachment.Parent = part

	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = elem.trailTexture
	emitter.LightEmission = elem.trailEmission
	emitter.LightInfluence = 0.1
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1.5),
		NumberSequenceKeypoint.new(0.5, 4.5),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.3),
		NumberSequenceKeypoint.new(0.7, 0.7),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Lifetime = NumberRange.new(0.25, 0.5)
	emitter.Rate = 45
	emitter.Speed = NumberRange.new(5, 12)
	emitter.SpreadAngle = Vector2.new(20, 20)
	emitter.Acceleration = Vector3.new(0, 1.5, 0)
	emitter.Color = ColorSequence.new(elem.trailColor)
	emitter.Parent = attachment

	task.delay(duration, function()
		emitter.Enabled = false
		Debris:AddItem(attachment, 1.0)
	end)
end

-- ============================================================
-- IMPACT  (hit burst + per-element flavor)
-- ============================================================
function VfxModule.createStylizedHit(position, isHeavy, element)
	local elem = ElementVfx.get(resolveElement(position, element))

	local attPart = Instance.new("Part")
	attPart.Anchored = true
	attPart.CanCollide = false
	attPart.CanQuery = false
	attPart.Transparency = 1
	attPart.Size = Vector3.new(0.1, 0.1, 0.1)
	attPart.Position = position
	attPart.Parent = workspace

	local att = Instance.new("Attachment")
	att.Parent = attPart

	local hitFx = Instance.new("ParticleEmitter")
	hitFx.Texture = elem.sparkTexture
	hitFx.LightEmission = 1
	hitFx.LightInfluence = 0
	hitFx.ZOffset = 1
	hitFx.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, isHeavy and 1.8 or 1.0),
		NumberSequenceKeypoint.new(0.2, isHeavy and 2.5 or 1.5),
		NumberSequenceKeypoint.new(1, 0),
	})
	hitFx.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.5, 0.3),
		NumberSequenceKeypoint.new(1, 1),
	})
	hitFx.Lifetime = NumberRange.new(0.15, 0.25)
	hitFx.Speed = NumberRange.new(10, 20)
	hitFx.Drag = 4.0
	hitFx.SpreadAngle = Vector2.new(180, 180)
	hitFx.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, elem.impactSecondary),
		ColorSequenceKeypoint.new(0.2, elem.impactPrimary),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(30, 30, 30)),
	})
	hitFx.Parent = att
	hitFx:Emit(isHeavy and 6 or 3)

	-- Per-element flavor particles (see ElementVfx.impactStyle)
	if elem.impactStyle == "rocks" then
		-- Stone: physical rock chunks
		VfxModule.createDust(position, isHeavy and 8 or 5, nil, element)
	elseif elem.impactStyle == "splash" then
		-- Water: droplets with gravity
		local droplets = hitFx:Clone()
		droplets.Texture = elem.trailTexture
		droplets.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.4),
			NumberSequenceKeypoint.new(1, 0.1),
		})
		droplets.Speed = NumberRange.new(6, 14)
		droplets.Acceleration = Vector3.new(0, -18, 0)
		droplets.Drag = 1.0
		droplets.Parent = att
		droplets:Emit(isHeavy and 8 or 4)
	elseif elem.impactStyle == "arc" then
		-- Lightning: sharp electric sparks
		local sparks = hitFx:Clone()
		sparks.Texture = elem.sparkTexture
		sparks.Size = NumberSequence.new(0.3, 0)
		sparks.Speed = NumberRange.new(22, 40)
		sparks.Drag = 6.0
		sparks.LightEmission = 1
		sparks.Parent = att
		sparks:Emit(isHeavy and 8 or 4)
	else
		-- Fire / Wind: subtle sparks
		local sparks = hitFx:Clone()
		sparks.Texture = elem.sparkTexture
		sparks.Size = NumberSequence.new(0.3, 0)
		sparks.Speed = NumberRange.new(20, 35)
		sparks.Drag = 6.0
		sparks.LightEmission = 1
		sparks.Parent = att
		sparks:Emit(isHeavy and 4 or 2)
	end

	Debris:AddItem(attPart, 0.4)
end

-- ============================================================
-- AURA FARM VFX  (Rising elemental energy aura & pulsing glow)
-- ============================================================
function VfxModule.createAuraFarmVfx(rootPart, element, duration)
	local elem = ElementVfx.get(resolveElement(rootPart, element))

	local att = Instance.new("Attachment")
	att.Name = "AuraFarmAttachment"
	att.Position = Vector3.new(0, -1.5, 0) -- Base of the fighter
	att.Parent = rootPart

	-- 1. Rising elemental aura wisps
	local auraEmitter = Instance.new("ParticleEmitter")
	auraEmitter.Name = "AuraWisps"
	auraEmitter.Texture = elem.trailTexture
	auraEmitter.LightEmission = math.max(0.7, elem.trailEmission)
	auraEmitter.LightInfluence = 0.05
	auraEmitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1.0),
		NumberSequenceKeypoint.new(0.5, 2.5),
		NumberSequenceKeypoint.new(1, 0.2),
	})
	auraEmitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.6),
		NumberSequenceKeypoint.new(0.4, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	auraEmitter.Lifetime = NumberRange.new(0.45, 0.75)
	auraEmitter.Rate = 40
	auraEmitter.Speed = NumberRange.new(5, 11)
	auraEmitter.SpreadAngle = Vector2.new(15, 15)
	auraEmitter.EmissionDirection = Enum.NormalId.Top
	auraEmitter.Acceleration = Vector3.new(0, 12, 0)
	auraEmitter.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, elem.burstCore),
		ColorSequenceKeypoint.new(0.5, elem.trailColor),
		ColorSequenceKeypoint.new(1, elem.impactSecondary),
	})
	auraEmitter.Parent = att

	-- 2. Ambient elemental ground flare
	local light = Instance.new("PointLight")
	light.Name = "AuraLight"
	light.Color = elem.burstColor
	light.Range = 14
	light.Brightness = 2.5
	light.Parent = rootPart

	local isAlive = true
	local cleanup = function()
		if not isAlive then return end
		isAlive = false
		auraEmitter.Enabled = false
		if light and light.Parent then
			local tw = TweenService:Create(light, TweenInfo.new(0.3), { Brightness = 0, Range = 0 })
			tw:Play()
			Debris:AddItem(light, 0.35)
		end
		Debris:AddItem(att, 0.8)
	end

	if type(duration) == "number" and duration > 0 then
		task.delay(duration, cleanup)
	end

	return {
		destroy = cleanup
	}
end

-- ============================================================
-- CHARGE POWER-UP VFX (Gathering elemental aura + ground tremor)
-- ============================================================
function VfxModule.createChargePowerUpVfx(rootPart, duration, element)
	local vfx = ElementVfx.get(resolveElement(rootPart, element))
	duration = duration or 0.65

	local att = Instance.new("Attachment")
	att.Name = "ChargeAtt"
	att.Position = Vector3.new(0, 0.4, -0.6)
	att.Parent = rootPart

	-- Inward gathering sparks
	local gatherEmitter = Instance.new("ParticleEmitter")
	gatherEmitter.Name = "GatherEmitter"
	gatherEmitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	gatherEmitter.LightEmission = 1.0
	gatherEmitter.LightInfluence = 0
	gatherEmitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.5),
		NumberSequenceKeypoint.new(0.6, 0.25),
		NumberSequenceKeypoint.new(1, 0),
	})
	gatherEmitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(0.8, 0.3),
		NumberSequenceKeypoint.new(1, 1),
	})
	gatherEmitter.Lifetime = NumberRange.new(0.20, 0.40)
	gatherEmitter.Rate = 75
	gatherEmitter.Speed = NumberRange.new(-6, -2) -- inward acceleration towards center
	gatherEmitter.SpreadAngle = Vector2.new(180, 180)
	gatherEmitter.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, vfx.burstCore),
		ColorSequenceKeypoint.new(0.5, vfx.burstColor),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 255, 255)),
	})
	gatherEmitter.Parent = att

	-- Charge point light
	local light = Instance.new("PointLight")
	light.Color = vfx.burstCore
	light.Range = 10
	light.Brightness = 2.0
	light.Parent = att

	-- Ground dust burst
	VfxModule.createDust(rootPart.Position - Vector3.new(0, 2.0, 0), 3, nil, element)

	local cleaned = false
	local function cleanup()
		if cleaned then return end
		cleaned = true
		gatherEmitter.Enabled = false
		task.delay(0.4, function()
			if att and att.Parent then att:Destroy() end
		end)
	end

	task.delay(duration, cleanup)
	return { destroy = cleanup }
end

-- ============================================================
-- BEAM STRUGGLE VFX  (Dual sleek energy beams + dynamic clash node)
-- ============================================================
function VfxModule.createBeamStruggleVfx(rootPartA, rootPartB, clashNode, elemA, elemB)
	local vfxA = ElementVfx.get(resolveElement(rootPartA, elemA))
	local vfxB = ElementVfx.get(resolveElement(rootPartB, elemB))

	-- Attachments on Quin roots (hands/chest level)
	local attA = Instance.new("Attachment")
	attA.Name = "BeamStruggleAttA"
	attA.Position = Vector3.new(0, 0.6, -1.0)
	attA.Parent = rootPartA

	local attB = Instance.new("Attachment")
	attB.Name = "BeamStruggleAttB"
	attB.Position = Vector3.new(0, 0.6, -1.0)
	attB.Parent = rootPartB

	-- Attachments on Clash Node
	local attClashA = Instance.new("Attachment")
	attClashA.Name = "ClashAttA"
	attClashA.Parent = clashNode

	local attClashB = Instance.new("Attachment")
	attClashB.Name = "ClashAttB"
	attClashB.Parent = clashNode

	-- 1. Outer Elemental Energy Stream (vibrant anime beam)
	local outerBeamA = Instance.new("Beam")
	outerBeamA.Name = "OuterBeamA"
	outerBeamA.Attachment0 = attA
	outerBeamA.Attachment1 = attClashA
	outerBeamA.FaceCamera = true
	outerBeamA.Segments = 10
	outerBeamA.Width0 = 1.20
	outerBeamA.Width1 = 1.80
	outerBeamA.Color = ColorSequence.new(vfxA.burstColor, vfxA.trailColor)
	outerBeamA.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.15),
		NumberSequenceKeypoint.new(0.5, 0.35),
		NumberSequenceKeypoint.new(1, 0.55),
	})
	outerBeamA.LightEmission = 0.80
	outerBeamA.LightInfluence = 0
	outerBeamA.Texture = ""
	outerBeamA.TextureSpeed = 4.0
	outerBeamA.TextureLength = 3.0
	outerBeamA.Parent = clashNode

	local outerBeamB = Instance.new("Beam")
	outerBeamB.Name = "OuterBeamB"
	outerBeamB.Attachment0 = attB
	outerBeamB.Attachment1 = attClashB
	outerBeamB.FaceCamera = true
	outerBeamB.Segments = 10
	outerBeamB.Width0 = 1.20
	outerBeamB.Width1 = 1.80
	outerBeamB.Color = ColorSequence.new(vfxB.burstColor, vfxB.trailColor)
	outerBeamB.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.15),
		NumberSequenceKeypoint.new(0.5, 0.35),
		NumberSequenceKeypoint.new(1, 0.55),
	})
	outerBeamB.LightEmission = 0.80
	outerBeamB.LightInfluence = 0
	outerBeamB.Texture = ""
	outerBeamB.TextureSpeed = 4.0
	outerBeamB.TextureLength = 3.0
	outerBeamB.Parent = clashNode

	-- 2. Inner Concentrated Core Laser (piercing solid white laser core)
	local coreBeamA = Instance.new("Beam")
	coreBeamA.Name = "CoreBeamA"
	coreBeamA.Attachment0 = attA
	coreBeamA.Attachment1 = attClashA
	coreBeamA.FaceCamera = true
	coreBeamA.Segments = 10
	coreBeamA.Width0 = 0.50
	coreBeamA.Width1 = 0.75
	coreBeamA.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(255, 255, 255))
	coreBeamA.LightEmission = 1.0
	coreBeamA.LightInfluence = 0
	coreBeamA.Transparency = NumberSequence.new(0.0)
	coreBeamA.Texture = ""
	coreBeamA.TextureSpeed = 6.0
	coreBeamA.TextureLength = 2.0
	coreBeamA.Parent = clashNode

	local coreBeamB = Instance.new("Beam")
	coreBeamB.Name = "CoreBeamB"
	coreBeamB.Attachment0 = attB
	coreBeamB.Attachment1 = attClashB
	coreBeamB.FaceCamera = true
	coreBeamB.Segments = 10
	coreBeamB.Width0 = 0.50
	coreBeamB.Width1 = 0.75
	coreBeamB.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(255, 255, 255))
	coreBeamB.LightEmission = 1.0
	coreBeamB.LightInfluence = 0
	coreBeamB.Transparency = NumberSequence.new(0.0)
	coreBeamB.Texture = ""
	coreBeamB.TextureSpeed = 6.0
	coreBeamB.TextureLength = 2.0
	coreBeamB.Parent = clashNode

	-- 3. Central Clash Friction Sparks (crisp, small, high-velocity sparks)
	local clashEmitter = Instance.new("ParticleEmitter")
	clashEmitter.Name = "ClashFrictionSparks"
	clashEmitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	clashEmitter.LightEmission = 1.0
	clashEmitter.LightInfluence = 0
	clashEmitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.35),
		NumberSequenceKeypoint.new(0.5, 0.70),
		NumberSequenceKeypoint.new(1, 0),
	})
	clashEmitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.6, 0.15),
		NumberSequenceKeypoint.new(1, 1),
	})
	clashEmitter.Lifetime = NumberRange.new(0.20, 0.45)
	clashEmitter.Rate = 160
	clashEmitter.Speed = NumberRange.new(12, 28)
	clashEmitter.SpreadAngle = Vector2.new(180, 180)
	clashEmitter.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
		ColorSequenceKeypoint.new(0.4, vfxA.burstColor),
		ColorSequenceKeypoint.new(0.8, vfxB.burstColor),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(40, 40, 40)),
	})
	clashEmitter.Parent = attClashA

	-- 4. Central Clash PointLight (Dynamic Radiant Clash Glow)
	local clashLight = Instance.new("PointLight")
	clashLight.Color = Color3.fromRGB(255, 255, 255)
	clashLight.Range = 26
	clashLight.Brightness = 4.5
	clashLight.Parent = clashNode

	-- Clash node appearance
	clashNode.Size = Vector3.new(2.0, 2.0, 2.0)
	clashNode.Transparency = 0.1

	local destroyed = false
	local function destroy()
		if destroyed then return end
		destroyed = true
		clashEmitter.Enabled = false
		if attA and attA.Parent then attA:Destroy() end
		if attB and attB.Parent then attB:Destroy() end
		if clashNode and clashNode.Parent then clashNode:Destroy() end
	end

	local function setBeamEnabled(isLeader, enabled)
		if destroyed then return end
		if isLeader then
			outerBeamA.Enabled = enabled
			coreBeamA.Enabled = enabled
		else
			outerBeamB.Enabled = enabled
			coreBeamB.Enabled = enabled
		end
	end

	local function triggerSurge(isLeader, surgeDuration)
		if destroyed then return end
		surgeDuration = surgeDuration or 0.30
		local ob = isLeader and outerBeamA or outerBeamB
		local cb = isLeader and coreBeamA or coreBeamB
		local rp = isLeader and rootPartA or rootPartB
		local elem = isLeader and elemA or elemB

		ob.Width0 = 1.60
		ob.Width1 = 2.40
		cb.Width0 = 0.70
		cb.Width1 = 1.10

		-- Kinetic shockwave ring at feet
		VfxModule.createShockwave(rp.Position - Vector3.new(0, 2.0, 0), 10, 0.25, elem)

		task.delay(surgeDuration, function()
			if not destroyed and ob and ob.Parent then
				ob.Width0 = 1.20
				ob.Width1 = 1.80
				cb.Width0 = 0.50
				cb.Width1 = 0.75
			end
		end)
	end

	local function triggerBreach(winnerIsLeader, loserRootPart)
		if destroyed then return end
		local loserOb = winnerIsLeader and outerBeamB or outerBeamA
		local loserCb = winnerIsLeader and coreBeamB or coreBeamA
		local winnerOb = winnerIsLeader and outerBeamA or outerBeamB
		local winnerCb = winnerIsLeader and coreBeamA or coreBeamB
		local winElem = winnerIsLeader and elemA or elemB

		-- 1. Loser's counter-beam collapses immediately
		loserOb.Enabled = false
		loserCb.Enabled = false

		-- 2. Winner's beam flares up with piercing power
		winnerOb.Width0 = 1.80
		winnerOb.Width1 = 2.80
		winnerCb.Width0 = 0.80
		winnerCb.Width1 = 1.30

		-- 3. The white clash node actively surges / drives straight into the loser's chest!
		local startPos = clashNode.Position
		local travelDuration = 0.16 -- 160ms rapid surge across remaining gap
		local impactTime = tick() + travelDuration
		local reachedImpact = false

		-- Enlarge clash node into an expanding piercing white core
		clashNode.Size = Vector3.new(3.5, 3.5, 3.5)
		if clashLight then
			clashLight.Brightness = 8.5
			clashLight.Range = 36
		end

		task.spawn(function()
			while not destroyed and tick() < (impactTime + 0.35) do
				local now = tick()
				local targetPos = loserRootPart.Position + Vector3.new(0, 0.6, 0)
				if now < impactTime then
					-- Flying rapidly toward loser's chest
					local alpha = math.clamp(1.0 - ((impactTime - now) / travelDuration), 0, 1)
					local easeAlpha = alpha * alpha -- Quad ease-in
					clashNode.Position = startPos:Lerp(targetPos, easeAlpha)
				else
					-- Reached loser! Detonate impact on arrival
					if not reachedImpact then
						reachedImpact = true
						AudioModule.playSlam(targetPos)
						-- High-visibility elemental impact shockwave directly on loser's body (NO screen shake!)
						VfxModule.createShockwave(targetPos, 28, 0.45, winElem)
						-- Flash burst on impact point
						local burstLight = Instance.new("PointLight")
						burstLight.Color = Color3.fromRGB(255, 255, 255)
						burstLight.Brightness = 12.0
						burstLight.Range = 40
						burstLight.Parent = clashNode
						Debris:AddItem(burstLight, 0.25)
					end
					-- Pin to loser as they get launched backwards in knockback!
					clashNode.Position = targetPos
				end
				task.wait(0.015)
			end

			-- Smooth fade-out of winner beam after sustained impact blast
			if not destroyed then
				for fade = 1, 5 do
					task.wait(0.02)
					if winnerOb and winnerOb.Parent then
						winnerOb.Transparency = NumberSequence.new(fade * 0.2)
					end
					if coreBeamA and coreBeamA.Parent then
						coreBeamA.Transparency = NumberSequence.new(fade * 0.2)
					end
					if coreBeamB and coreBeamB.Parent then
						coreBeamB.Transparency = NumberSequence.new(fade * 0.2)
					end
				end
			end
		end)
	end

	return {
		clashNode = clashNode,
		clashEmitter = clashEmitter,
		clashLight = clashLight,
		outerBeamA = outerBeamA,
		outerBeamB = outerBeamB,
		coreBeamA = coreBeamA,
		coreBeamB = coreBeamB,
		setBeamEnabled = setBeamEnabled,
		triggerSurge = triggerSurge,
		triggerBreach = triggerBreach,
		destroy = destroy,
	}
end

-- ============================================================
-- RIVAL FINISHER IMPACT  (Crisp, weighted decisive strike cue)
-- ============================================================
function VfxModule.createFinisherImpact(position, element)
	local elem = ElementVfx.get(resolveElement(position, element))
	position = resolvePosition(position)

	-- 1. Sharp shockwave ring
	VfxModule.createShockwave(position, 18, 0.45, element)

	-- 2. Physical impact debris
	VfxModule.createDust(position, 7, nil, element)

	-- 3. Concentrated radial spark flash
	local attPart = Instance.new("Part")
	attPart.Anchored = true
	attPart.CanCollide = false
	attPart.Transparency = 1
	attPart.Position = position
	attPart.Parent = workspace

	local att = Instance.new("Attachment")
	att.Parent = attPart

	local sparkEmitter = Instance.new("ParticleEmitter")
	sparkEmitter.Texture = elem.sparkTexture
	sparkEmitter.LightEmission = 1.0
	sparkEmitter.LightInfluence = 0
	sparkEmitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1.5),
		NumberSequenceKeypoint.new(0.3, 2.5),
		NumberSequenceKeypoint.new(1, 0),
	})
	sparkEmitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.6, 0.3),
		NumberSequenceKeypoint.new(1, 1),
	})
	sparkEmitter.Lifetime = NumberRange.new(0.2, 0.4)
	sparkEmitter.Speed = NumberRange.new(20, 38)
	sparkEmitter.SpreadAngle = Vector2.new(180, 180)
	sparkEmitter.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
		ColorSequenceKeypoint.new(0.3, elem.burstCore),
		ColorSequenceKeypoint.new(1, elem.impactPrimary),
	})
	sparkEmitter.Parent = att
	sparkEmitter:Emit(14)

	Debris:AddItem(attPart, 0.6)
end

return VfxModule