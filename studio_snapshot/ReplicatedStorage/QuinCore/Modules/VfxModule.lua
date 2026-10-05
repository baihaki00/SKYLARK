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

-- ============================================================
-- STYLIZED GREY FOOT SMOKE (Turn plants, hard cuts, footwork)
-- ============================================================
function VfxModule.createArcaneFootBurst(fighter, position, direction)
	position = resolvePosition(position)
	direction = direction or Vector3.new(0, 0, -1)

	local attPart = Instance.new("Part")
	attPart.Size = Vector3.new(0.1, 0.1, 0.1)
	attPart.Anchored = true
	attPart.CanCollide = false
	attPart.Transparency = 1
	attPart.CFrame = CFrame.lookAt(position - Vector3.new(0, 0.2, 0), position - Vector3.new(0, 0.2, 0) + direction)
	attPart.Parent = workspace

	local att = Instance.new("Attachment")
	att.Parent = attPart

	local smoke = Instance.new("ParticleEmitter")
	smoke.Texture = "rbxassetid://6508826458"
	smoke.LightEmission = 0.1
	smoke.LightInfluence = 0.8
	smoke.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.4),
		NumberSequenceKeypoint.new(0.4, 0.9),
		NumberSequenceKeypoint.new(1, 0.2),
	})
	smoke.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.35),
		NumberSequenceKeypoint.new(0.6, 0.7),
		NumberSequenceKeypoint.new(1, 1),
	})
	smoke.Lifetime = NumberRange.new(0.25, 0.40)
	smoke.Speed = NumberRange.new(3, 8)
	smoke.SpreadAngle = Vector2.new(30, 30)
	smoke.EmissionDirection = Enum.NormalId.Back
	smoke.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(220, 225, 230)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(180, 185, 190)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(130, 135, 140)),
	})
	smoke.Parent = att
	smoke:Emit(5)

	Debris:AddItem(attPart, 0.50)
end

function VfxModule.emitFootstepSmoke(fighter, footPosition)
	local pos = resolvePosition(footPosition)

	local attPart = Instance.new("Part")
	attPart.Size = Vector3.new(0.1, 0.1, 0.1)
	attPart.Anchored = true
	attPart.CanCollide = false
	attPart.Transparency = 1
	attPart.Position = pos - Vector3.new(0, 0.1, 0)
	attPart.Parent = workspace

	local att = Instance.new("Attachment")
	att.Parent = attPart

	local puff = Instance.new("ParticleEmitter")
	puff.Texture = "rbxassetid://6508826458"
	puff.LightEmission = 0.1
	puff.LightInfluence = 0.8
	puff.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.25),
		NumberSequenceKeypoint.new(1, 0.55),
	})
	puff.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.45),
		NumberSequenceKeypoint.new(1, 1),
	})
	puff.Lifetime = NumberRange.new(0.15, 0.25)
	puff.Speed = NumberRange.new(1, 3)
	puff.SpreadAngle = Vector2.new(180, 0)
	puff.Color = ColorSequence.new(Color3.fromRGB(190, 195, 200))
	puff.Parent = att
	puff:Emit(2)

	Debris:AddItem(attPart, 0.30)
end

-- ============================================================
-- GROUND FEEDBACK  (landing dust, slide smoke, marks left on the turf)
-- Switches: CombatConfig.Vfx_LandingDust / Vfx_SlideSmoke / Vfx_GroundMarks
-- ============================================================
local CombatConfig = require(QuinCore:WaitForChild("CombatConfig"))

local SMOKE_TEXTURE = "rbxassetid://6508826458"
local SMOKE_COLOR = ColorSequence.new(Color3.fromRGB(205, 210, 215), Color3.fromRGB(150, 155, 160))
local MARK_COLOR = Color3.fromRGB(38, 62, 44) -- scuffed turf
local MARK_LIMIT = 60 -- marks on the field at once; further ones are skipped
local FOOTPRINT_MIN_SPEED = 25 -- studs/s: only a sprint digs into the turf
local FOOTPRINT_INTERVAL = 0.15 -- seconds between prints per Quin (several gait clips fire the same step)

local markCount = 0
local lastFootprint = setmetatable({}, { __mode = "k" })
local footprintSide = setmetatable({}, { __mode = "k" })

-- The point on the floor under a standing Quin (root part given), or the position itself
local function floorPoint(source)
	if typeof(source) == "Instance" and source:IsA("BasePart") then
		local humanoid = source.Parent and source.Parent:FindFirstChildOfClass("Humanoid")
		if humanoid then
			return source.Position - Vector3.new(0, humanoid.HipHeight + source.Size.Y / 2, 0)
		end
		return source.Position
	end
	return source
end

local function emitterAnchor(position, lifetime)
	local anchor = Instance.new("Part")
	anchor.Name = "GroundVfx"
	anchor.Size = Vector3.new(0.1, 0.1, 0.1)
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.CFrame = CFrame.new(position)
	anchor.Parent = workspace
	Debris:AddItem(anchor, lifetime)
	local attachment = Instance.new("Attachment")
	attachment.Parent = anchor
	return attachment
end

-- A low burst of smoke spreading along the ground where a body comes down.
-- source: floor position or the Quin's root part; strength 0..1 (a hop .. a slam)
function VfxModule.createLandingDust(source, strength)
	if CombatConfig.Vfx_LandingDust == false then return end
	strength = math.clamp(strength or 0.5, 0.2, 1)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = SMOKE_TEXTURE
	emitter.Color = SMOKE_COLOR
	emitter.LightEmission = 0.1
	emitter.LightInfluence = 0.8
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.5 + strength * 0.5),
		NumberSequenceKeypoint.new(1, 1.6 + strength * 1.6),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.35),
		NumberSequenceKeypoint.new(0.6, 0.7),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Lifetime = NumberRange.new(0.35, 0.6)
	emitter.Speed = NumberRange.new(7 + strength * 6, 12 + strength * 12)
	emitter.SpreadAngle = Vector2.new(86, 86) -- nearly flat: outward along the ground
	emitter.EmissionDirection = Enum.NormalId.Top
	emitter.Drag = 5
	emitter.Rate = 0
	emitter.Parent = emitterAnchor(floorPoint(source) + Vector3.new(0, 0.2, 0), 1.0)
	emitter:Emit(math.round(8 + strength * 12))
end

-- Smoke trailing from under a sliding Quin. Returns the emitter; stop it with
-- VfxModule.stopSlideSmoke when the slide ends.
function VfxModule.createSlideSmoke(rootPart)
	if CombatConfig.Vfx_SlideSmoke == false then return nil end
	local humanoid = rootPart.Parent and rootPart.Parent:FindFirstChildOfClass("Humanoid")
	local attachment = Instance.new("Attachment")
	attachment.Name = "SlideSmokeAtt"
	attachment.Position = Vector3.new(0, -((humanoid and humanoid.HipHeight or 4) + rootPart.Size.Y / 2) + 0.3, 1.2)
	attachment.Parent = rootPart

	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = SMOKE_TEXTURE
	emitter.Color = SMOKE_COLOR
	emitter.LightEmission = 0.1
	emitter.LightInfluence = 0.8
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 1.5) })
	emitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(1, 1) })
	emitter.Lifetime = NumberRange.new(0.3, 0.5)
	emitter.Speed = NumberRange.new(1, 3)
	emitter.SpreadAngle = Vector2.new(40, 40)
	emitter.EmissionDirection = Enum.NormalId.Back
	emitter.Rate = 35
	emitter.Parent = attachment
	return emitter
end

function VfxModule.stopSlideSmoke(emitter)
	if not emitter then return end
	emitter.Enabled = false
	if emitter.Parent then
		Debris:AddItem(emitter.Parent, 0.6)
	end
end

-- ============================================================
-- GROUND DECALS (footprints, slide streaks, landing cracks)
-- Drawn on the floor with a SurfaceGui on an invisible, non-colliding flat carrier: the marks
-- are flat shapes, never visible geometry (they used to be grey Part rectangles). Each kind is
-- drawn from Frames by default and can be replaced by an image: CombatConfig.Vfx_FootprintImage
-- (+ Vfx_FootprintImageLeft), Vfx_LandingCrackImage. The image is laid toe-up for footprints.
-- ============================================================
local GROUND_PPS = 64 -- SurfaceGui pixels per stud
local DECAL_COLOR = MARK_COLOR
local DECAL_DARK = Color3.fromRGB(24, 34, 27)
local IMPACT_GREY = Color3.fromRGB(46, 46, 48) -- landing cracks and scorch: grey, not turf green (owner)
local TREAD_COLOR = Color3.fromRGB(78, 104, 82)

local decalRay = RaycastParams.new()
decalRay.FilterType = Enum.RaycastFilterType.Exclude
decalRay.RespectCanCollide = true

-- The floor height under a point (ignores Quins and other decals); nil without a floor
local function floorUnder(point)
	decalRay.FilterDescendantsInstances = { workspace:FindFirstChild("QuinServer"), workspace:FindFirstChild("GroundDecals") }
	local hit = workspace:Raycast(point + Vector3.new(0, 3, 0), Vector3.new(0, -12, 0), decalRay)
	return hit and hit.Position or nil
end

-- Marks on the floor, oldest first: at the limit the oldest one fades away quickly to make room
-- (new marks used to be skipped once 60 were down)
local activeDecals = {}

local function fadeDecal(entry, seconds)
	if entry.fading then return end
	entry.fading = true
	if entry.canvas.Parent then
		TweenService:Create(entry.canvas, TweenInfo.new(seconds, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { GroupTransparency = 1 }):Play()
	end
	task.delay(seconds, function()
		local index = table.find(activeDecals, entry)
		if index then table.remove(activeDecals, index) end
		markCount = #activeDecals
		entry.carrier:Destroy()
	end)
end

-- A flat carrier lying on the floor at `position`, its length (Z) along `forward`; returns the
-- canvas to draw on. The mark stays fully visible for `hold` seconds, then fades out over `fade`
-- seconds (`fade` defaults to half the hold).
local function groundDecal(position, forward, sizeX, sizeZ, hold, fade)
	if CombatConfig.Vfx_GroundMarks == false then return nil end
	local limit = CombatConfig.Vfx_GroundMarkLimit or MARK_LIMIT
	local standing = 0
	for _, old in ipairs(activeDecals) do
		if not old.fading then standing += 1 end
	end
	for _, old in ipairs(activeDecals) do
		if standing < limit then break end
		if not old.fading then
			fadeDecal(old, 0.4)
			standing -= 1
		end
	end
	local flat = Vector3.new(forward.X, 0, forward.Z)
	if flat.Magnitude < 0.01 then flat = Vector3.new(0, 0, -1) end
	local folder = workspace:FindFirstChild("GroundDecals")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "GroundDecals"
		folder.Parent = workspace
	end
	local carrier = Instance.new("Part")
	carrier.Name = "GroundDecal"
	-- (a SurfaceGui on the Top face runs its width along the part's Z and its height along X: the
	-- carrier's X axis lies along the mark, the drawing's top edge toward `forward`)
	carrier.Size = Vector3.new(sizeZ, 0.05, sizeX)
	carrier.CFrame = CFrame.fromMatrix(position + Vector3.new(0, 0.03, 0), -flat.Unit, Vector3.yAxis)
	carrier.Transparency = 1
	carrier.Anchored = true
	carrier.CanCollide = false
	carrier.CanQuery = false
	carrier.CanTouch = false
	carrier.CastShadow = false
	carrier.Massless = true
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Top
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = GROUND_PPS
	gui.LightInfluence = 1
	gui.Parent = carrier
	local canvas = Instance.new("CanvasGroup")
	canvas.Name = "Canvas"
	canvas.Size = UDim2.fromScale(1, 1)
	canvas.BackgroundTransparency = 1
	canvas.Parent = gui
	carrier.Parent = folder

	hold = hold or 3.5
	fade = fade or hold * 0.5
	local entry = { carrier = carrier, canvas = canvas }
	table.insert(activeDecals, entry)
	markCount = #activeDecals
	task.delay(hold, function()
		fadeDecal(entry, fade)
	end)
	return canvas
end

-- A filled shape on a decal canvas: centre (x, y) and size (w, h) as fractions of the canvas;
-- corner 0.5 = fully rounded ends
local function blob(parent, x, y, w, h, color, transparency, corner, rotation)
	local frame = Instance.new("Frame")
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(x, y)
	frame.Size = UDim2.fromScale(w, h)
	frame.BackgroundColor3 = color
	frame.BackgroundTransparency = transparency or 0
	frame.BorderSizePixel = 0
	frame.Rotation = rotation or 0
	if (corner or 0) > 0 then
		local round = Instance.new("UICorner")
		round.CornerRadius = UDim.new(corner, 0)
		round.Parent = frame
	end
	frame.Parent = parent
	return frame
end

local function decalImage(parent, image, transparency, rotation)
	local label = Instance.new("ImageLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Image = image
	label.ImageTransparency = transparency or 0.15
	label.Rotation = rotation or 0
	label.Parent = parent
	return label
end

-- A scuff left on the turf: a soft streak along `direction` that fades out (slides, skids).
-- source: floor position or the Quin's root part
function VfxModule.createGroundMark(source, direction, length, width, lifetime)
	local canvas = groundDecal(floorPoint(source), direction, width or 0.8, length or 1.2, lifetime or 3.5)
	if not canvas then return end
	local streak = blob(canvas, 0.5, 0.5, 1, 1, DECAL_COLOR, 0.35, 0.5)
	local fade = Instance.new("UIGradient") -- soft at both ends
	fade.Rotation = 90
	fade.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.2, 0.2),
		NumberSequenceKeypoint.new(0.8, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	fade.Parent = streak
end

-- Foot bones per Quin (ankle and ball of the foot), cached
local footCache = setmetatable({}, { __mode = "k" })
local function footBones(fighter)
	local cached = footCache[fighter]
	if cached then return cached end
	cached = {
		Left = { ankle = fighter:FindFirstChild("mixamorig:LeftFoot", true), toe = fighter:FindFirstChild("mixamorig:LeftToeBase", true) },
		Right = { ankle = fighter:FindFirstChild("mixamorig:RightFoot", true), toe = fighter:FindFirstChild("mixamorig:RightToeBase", true) },
	}
	footCache[fighter] = cached
	return cached
end

-- A boot sole drawn toe-up on a footprint canvas; `inner` = +1 when the big-toe side is to the
-- right of the canvas (left foot), -1 for the right foot
local function drawSole(canvas, inner)
	local fill, groove = 0.3, 0.45
	blob(canvas, 0.5 + inner * 0.03, 0.30, 0.94, 0.56, DECAL_COLOR, fill, 0.5) -- forefoot
	blob(canvas, 0.5 - inner * 0.14, 0.62, 0.46, 0.26, DECAL_COLOR, fill, 0.35) -- outer arch
	blob(canvas, 0.5 + inner * 0.01, 0.84, 0.76, 0.30, DECAL_COLOR, fill, 0.5) -- heel
	for _, y in ipairs({ 0.13, 0.22, 0.31, 0.40, 0.49 }) do -- tread
		blob(canvas, 0.5 + inner * 0.03, y, 0.72, 0.035, TREAD_COLOR, groove, 0.5)
	end
	for _, y in ipairs({ 0.80, 0.89 }) do
		blob(canvas, 0.5, y, 0.56, 0.035, TREAD_COLOR, groove, 0.5)
	end
end

-- A sprinting step: a boot print under the foot that just stepped, along that foot.
-- side: "Left" / "Right" (the Footstep marker's parameter) or nil = the lower foot
function VfxModule.createFootprint(fighter, side)
	if CombatConfig.Vfx_GroundMarks == false then return end
	local rootPart = fighter and fighter:FindFirstChild("HumanoidRootPart")
	if not rootPart then return end
	local velocity = rootPart.AssemblyLinearVelocity
	local flat = Vector3.new(velocity.X, 0, velocity.Z)
	local now = os.clock()
	if flat.Magnitude < FOOTPRINT_MIN_SPEED or now - (lastFootprint[fighter] or 0) < FOOTPRINT_INTERVAL then return end

	local bones = footBones(fighter)
	if side ~= "Left" and side ~= "Right" then
		local l, r = bones.Left.ankle, bones.Right.ankle
		if l and r then
			side = l.TransformedWorldCFrame.Position.Y <= r.TransformedWorldCFrame.Position.Y and "Left" or "Right"
		end
	end
	local foot = side and bones[side]
	if not (foot and foot.ankle and foot.toe) then return end
	lastFootprint[fighter] = now

	local ankle = foot.ankle.TransformedWorldCFrame.Position
	local toe = foot.toe.TransformedWorldCFrame.Position
	local along = Vector3.new(toe.X - ankle.X, 0, toe.Z - ankle.Z)
	if along.Magnitude < 0.05 then along = flat end
	along = along.Unit
	-- the sole runs from just behind the ankle (heel) to past the ball of the foot (toes)
	local centre = Vector3.new(ankle.X, 0, ankle.Z) + along * (CombatConfig.Vfx_FootprintCentreOffset or 0.42)
	local floor = floorUnder(Vector3.new(centre.X, ankle.Y, centre.Z))
	if not floor then return end
	local length = CombatConfig.Vfx_FootprintLength or 1.2
	local width = CombatConfig.Vfx_FootprintWidth or 0.48
	local canvas = groundDecal(Vector3.new(centre.X, floor.Y, centre.Z), along, width, length,
		CombatConfig.Vfx_FootprintHold or 6, CombatConfig.Vfx_FootprintFade or 3)
	if not canvas then return end
	local image = CombatConfig.Vfx_FootprintImage
	local mirror = false
	if side == "Left" then
		if (CombatConfig.Vfx_FootprintImageLeft or "") ~= "" then
			image = CombatConfig.Vfx_FootprintImageLeft
		else
			mirror = true -- one right-foot image serves both feet, flipped for the left
		end
	end
	canvas.Parent.Parent:SetAttribute("Foot", side) -- (which foot made it: debug and tests)
	if (image or "") ~= "" then
		local label = decalImage(canvas, image, CombatConfig.Vfx_FootprintImageTransparency or 0.25)
		label.ScaleType = Enum.ScaleType.Fit -- keep the drawing's proportions
		local size = CombatConfig.Vfx_FootprintImageSize
		if mirror and typeof(size) == "Vector2" then
			-- a negative rect width draws the image flipped left to right
			label.ImageRectOffset = Vector2.new(size.X, 0)
			label.ImageRectSize = Vector2.new(-size.X, size.Y)
		end
	else
		drawSole(canvas, side == "Left" and 1 or -1)
	end
end

-- Landing impact on the ground: a crack and scorch decal where the body came down, dust spreading
-- along the floor and clods of earth thrown up (particles; no debris parts, no shockwave ring).
-- source: floor position or the Quin's root part; strength 0..1 (a hop .. a slam)
function VfxModule.createLandingImpact(source, strength, element)
	if CombatConfig.Vfx_LandingImpact == false then
		VfxModule.createLandingDust(source, strength)
		return
	end
	strength = math.clamp(strength or 0.6, 0.2, 1)
	local base = floorPoint(source)
	local floor = floorUnder(base) or base
	VfxModule.createLandingDust(floor, strength)

	-- crack (only a real impact cracks the ground)
	if strength >= 0.45 then
		local size = 3 + strength * 5
		local canvas = groundDecal(floor, Vector3.new(math.random() - 0.5, 0, math.random() - 0.5), size, size,
			CombatConfig.Vfx_LandingCrackHold or 6, CombatConfig.Vfx_LandingCrackFade or 3)
		if canvas then
			if (CombatConfig.Vfx_LandingCrackImage or "") ~= "" then
				decalImage(canvas, CombatConfig.Vfx_LandingCrackImage, 0.1, math.random(0, 359))
			else
				local crackColor = CombatConfig.Vfx_LandingCrackColor or IMPACT_GREY
				-- (opaque enough to read grey on green turf: see-through grey just tinted the grass)
				blob(canvas, 0.5, 0.5, 0.62, 0.62, Color3.fromRGB(128, 128, 130), 0.55, 0.5) -- dust ring
				blob(canvas, 0.5, 0.5, 0.32, 0.32, Color3.fromRGB(84, 84, 86), 0.2, 0.5) -- crushed centre
				-- a jagged line: short segments that wander and thin out toward the tip
				local function crackLine(x, y, angle, length, thick, segments)
					local step = length / segments
					for k = 1, segments do
						angle += (math.random() - 0.5) * 0.7
						local nx, ny = x + math.cos(angle) * step, y + math.sin(angle) * step
						local w = thick * (1 - (k - 1) / (segments + 1))
						-- (a touch longer than the step so the joints close)
						blob(canvas, (x + nx) / 2, (y + ny) / 2, step * 1.15, w, CombatConfig.Vfx_LandingCrackColor or IMPACT_GREY, 0.15 + k * 0.05, 0.5, math.deg(angle))
						x, y = nx, ny
					end
					return x, y, angle
				end
				local count = 7 + math.floor(strength * 5)
				for i = 1, count do
					local angle = (i / count) * math.pi * 2 + (math.random() - 0.5) * 0.5
					local len = 0.22 + math.random() * 0.24
					local thick = 0.014 + math.random() * 0.012
					crackLine(0.5 + math.cos(angle) * 0.08, 0.5 + math.sin(angle) * 0.08, angle, len, thick, 3)
					-- a branch from part of the way out
					if math.random() < 0.7 then
						local at = 0.08 + len * (0.4 + math.random() * 0.3)
						local bAngle = angle + (math.random() < 0.5 and -1 or 1) * (0.4 + math.random() * 0.4)
						crackLine(0.5 + math.cos(angle) * at, 0.5 + math.sin(angle) * at, bAngle, len * (0.3 + math.random() * 0.25), thick * 0.65, 2)
					end
				end
			end
		end
	end

	-- clods of earth thrown up and falling back
	local clods = Instance.new("ParticleEmitter")
	clods.Texture = SMOKE_TEXTURE
	clods.Color = ColorSequence.new(Color3.fromRGB(92, 92, 95), Color3.fromRGB(58, 58, 60)) -- grey rubble
	clods.LightEmission = 0
	clods.LightInfluence = 1
	clods.Size = NumberSequence.new(0.18 + strength * 0.12, 0.08)
	clods.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.05), NumberSequenceKeypoint.new(0.8, 0.2), NumberSequenceKeypoint.new(1, 1) })
	clods.Lifetime = NumberRange.new(0.45, 0.8)
	clods.Speed = NumberRange.new(10 + strength * 8, 18 + strength * 16)
	clods.SpreadAngle = Vector2.new(55, 55)
	clods.EmissionDirection = Enum.NormalId.Top
	clods.Acceleration = Vector3.new(0, -workspace.Gravity * 0.5, 0)
	clods.Drag = 1.5
	clods.Rotation = NumberRange.new(0, 360)
	clods.RotSpeed = NumberRange.new(-300, 300)
	clods.Rate = 0
	clods.Parent = emitterAnchor(floor + Vector3.new(0, 0.3, 0), 1.2)
	clods:Emit(math.round(8 + strength * 18))
end

-- Holographic glitch over a whole Quin: it flickers, tears (gone for a beat) and glows through in
-- cyan while it dissolves (direction "out": a defeated Quin) or takes shape ("in": a Quin
-- teleported onto the field). Runs on the server; every client sees the same flicker.
-- "in" expects the model as it should end up and returns it to that; "out" leaves it invisible.
local HOLO_FLICKER_MIN, HOLO_FLICKER_MAX = 0.016, 0.04 -- seconds between flickers (was 0.04 - 0.09: it read as a slow blink)

function VfxModule.holoGlitch(model, duration, direction)
	if not model or not model.Parent then return end
	duration = duration or 1.0
	local arriving = direction == "in"

	local parts = {}
	for _, item in ipairs(model:GetDescendants()) do
		if (item:IsA("BasePart") and item.Name ~= "HumanoidRootPart" and item.Transparency < 1)
			or item:IsA("Decal") or item:IsA("Texture") then
			table.insert(parts, { item = item, base = item.Transparency })
		end
	end
	local glow = Instance.new("Highlight")
	glow.Name = "HoloGlitch"
	glow.FillColor = Color3.fromRGB(0, 200, 255)
	glow.OutlineTransparency = 1 -- (no outline: the white rim read as a selection box)
	glow.DepthMode = Enum.HighlightDepthMode.Occluded
	glow.Adornee = model
	glow.Parent = model

	task.spawn(function()
		local rng = Random.new()
		local started = os.clock()
		while model.Parent do
			local progress = math.clamp((os.clock() - started) / duration, 0, 1)
			local solid = arriving and progress or (1 - progress) -- how much of it is there
			local tear = progress < 1 and rng:NextNumber() < 0.18
			local shown = tear and 0 or math.clamp(solid + rng:NextNumber(-0.3, 0.3), 0, 1)
			if progress >= 1 then
				shown = arriving and 1 or 0
			end
			for _, entry in ipairs(parts) do
				if entry.item.Parent then
					entry.item.Transparency = entry.base + (1 - entry.base) * (1 - shown)
				end
			end
			glow.FillTransparency = rng:NextNumber(0.25, 0.85)
			if progress >= 1 then break end
			task.wait(rng:NextNumber(HOLO_FLICKER_MIN, HOLO_FLICKER_MAX))
		end
		glow:Destroy()
	end)
end

return VfxModule