--// FXService.lua
-- Central presentation service for dynamic Element Appearance and Plug-and-Play Elemental FX
-- Completely decouples visual aesthetics from gameplay/AI/combat logic

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local QuinCore = ReplicatedStorage:WaitForChild("QuinCore")
local ElementData = require(QuinCore:WaitForChild("ElementData"))

local FXService = {}

-- ============================================================================
-- 1. DYNAMIC ELEMENT APPEARANCE
-- ============================================================================
-- Applies data-driven body coloration to a Quin model based on its Element
function FXService.applyElementAppearance(model, elementName)
	if not model then return end
	local elem = ElementData.getElement(elementName or model:GetAttribute("Element") or "Fire")

	-- 1. Remove any legacy TeamRing instances
	local oldRing = model:FindFirstChild("TeamRing")
	if oldRing then oldRing:Destroy() end

	-- 2. Remove any legacy element highlight
	local oldHighlight = model:FindFirstChild("ElementHighlight")
	if oldHighlight then oldHighlight:Destroy() end

	-- 3. Recolor the visible body (Alpha_Surface) to a solid element color.
	-- The skin texture (rbxassetid://85394248927456) is cleared below so the color
	-- reads clearly; to restore the skin, just remove the TextureID clearing.
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") and (part.Name == "Alpha_Surface" or part.Name:find("Mesh") or part.Name == "Body") then
			part.Color = elem.BodyTint or elem.Color
			if part:IsA("MeshPart") and part.TextureID and part.TextureID ~= "" then
				part.TextureID = ""
			end
		end
	end

	-- 4. Element Tag attributes
	model:SetAttribute("ElementColor", elem.Color)
	model:SetAttribute("ElementDisplayName", elem.DisplayName)

	return true
end

-- ============================================================================
-- 2. PLUG-AND-PLAY ELEMENTAL FX EMITTERS
-- ============================================================================
-- Central dispatch method: plays visual FX for an event based on the Quin's Element
function FXService.play(quinModel, eventType, target)
	if not quinModel or not quinModel.Parent then return end
	local elementName = quinModel:GetAttribute("Element") or "Fire"
	local elem = ElementData.getElement(elementName)

	local hrp = quinModel:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	local fxId = elem.FX and elem.FX[eventType] or (elementName .. "_" .. eventType)

	-- Route to event-specific presentation handler
	if eventType == "Attack" then
		FXService.emitAttackFX(hrp, elem, target)
	elseif eventType == "Dash" then
		FXService.emitDashFX(hrp, elem)
	elseif eventType == "Hit" then
		FXService.emitHitFX(target or hrp, elem)
	elseif eventType == "Block" then
		FXService.emitBlockFX(hrp, elem)
	elseif eventType == "Special" or eventType == "Super" then
		FXService.emitSpecialFX(hrp, elem)
	elseif eventType == "Spawn" then
		FXService.emitSpawnFX(hrp, elem)
	elseif eventType == "Death" then
		FXService.emitDeathFX(hrp, elem)
	else
		-- Generic elemental pulse
		FXService.emitPulse(hrp.Position, elem.Color, 4, 0.3)
	end
end

-- Backward compatibility alias
function FXService.playElementFX(quinModel, eventType, target)
	return FXService.play(quinModel, eventType, target)
end

-- --- Elemental Emitter Implementations (Restrained, Lightweight Presentation Layer) ---

-- Helper: Create a lightweight temporary attachment at a position
local function createTempAttachment(positionOrPart, cframeOffset)
	local att = Instance.new("Attachment")
	if typeof(positionOrPart) == "Vector3" then
		local anchor = Instance.new("Part")
		anchor.Size = Vector3.new(0.1, 0.1, 0.1)
		anchor.Transparency = 1
		anchor.Anchored = true
		anchor.CanCollide = false
		anchor.Position = positionOrPart
		anchor.Parent = workspace
		att.Parent = anchor
		Debris:AddItem(anchor, 0.5)
	elseif positionOrPart:IsA("BasePart") then
		att.CFrame = cframeOffset or CFrame.new()
		att.Parent = positionOrPart
		Debris:AddItem(att, 0.5)
	end
	return att
end

function FXService.emitAttackFX(hrp, elem, target)
	local att = createTempAttachment(hrp, CFrame.new(0, 0, -2.2))
	local emitter = Instance.new("ParticleEmitter")
	emitter.LightEmission = 0.8
	emitter.LightInfluence = 0.2
	emitter.Drag = 3.0

	local name = elem.DisplayName or "Fire"
	if name == "Fire" then
		-- Small warm embers + subtle flash
		emitter.Texture = "rbxassetid://1185246"
		emitter.Color = ColorSequence.new(elem.Color, Color3.fromRGB(255, 180, 50))
		emitter.Size = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 0)})
		emitter.Lifetime = NumberRange.new(0.18, 0.25)
		emitter.Speed = NumberRange.new(3, 7)
		emitter.SpreadAngle = Vector2.new(20, 20)
		emitter.Parent = att
		emitter:Emit(4)

	elseif name == "Water" then
		-- Small fluid droplets with gravity
		emitter.Texture = "rbxassetid://2415893330"
		emitter.Color = ColorSequence.new(elem.Color, Color3.fromRGB(150, 230, 255))
		emitter.Size = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0.1)})
		emitter.Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 0.8)})
		emitter.Lifetime = NumberRange.new(0.2, 0.3)
		emitter.Speed = NumberRange.new(4, 9)
		emitter.Acceleration = Vector3.new(0, -12, 0)
		emitter.Parent = att
		emitter:Emit(5)

	elseif name == "Stone" then
		-- Subtle dust puff and fine pebble debris
		emitter.Texture = "rbxassetid://2415893330"
		emitter.Color = ColorSequence.new(elem.Color, Color3.fromRGB(180, 160, 140))
		emitter.Size = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 0.5)})
		emitter.Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 1)})
		emitter.Lifetime = NumberRange.new(0.2, 0.3)
		emitter.Speed = NumberRange.new(2, 6)
		emitter.Parent = att
		emitter:Emit(4)

	elseif name == "Lightning" then
		-- Sharp electric sparks
		emitter.Texture = "rbxassetid://6763809313"
		emitter.Color = ColorSequence.new(elem.Color, Color3.fromRGB(255, 255, 200))
		emitter.Size = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 0)})
		emitter.Lifetime = NumberRange.new(0.1, 0.18)
		emitter.Speed = NumberRange.new(15, 30)
		emitter.Drag = 5.0
		emitter.SpreadAngle = Vector2.new(45, 45)
		emitter.Parent = att
		emitter:Emit(4)

	elseif name == "Wind" then
		-- Curved, semi-transparent wind streaks
		emitter.Texture = "rbxassetid://2415893330"
		emitter.Color = ColorSequence.new(Color3.fromRGB(220, 255, 245))
		emitter.Size = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 1.2)})
		emitter.Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.7), NumberSequenceKeypoint.new(1, 1)})
		emitter.Lifetime = NumberRange.new(0.18, 0.28)
		emitter.Speed = NumberRange.new(8, 16)
		emitter.Parent = att
		emitter:Emit(3)
	end
end

function FXService.emitDashFX(hrp, elem)
	local att = createTempAttachment(hrp, CFrame.new(0, -0.5, 1))
	local emitter = Instance.new("ParticleEmitter")
	emitter.LightEmission = 0.6
	emitter.Drag = 4.0

	local name = elem.DisplayName or "Fire"
	emitter.Color = ColorSequence.new(elem.Color)
	emitter.Size = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 0)})
	emitter.Lifetime = NumberRange.new(0.15, 0.25)
	emitter.Speed = NumberRange.new(3, 8)
	emitter.EmissionDirection = Enum.NormalId.Back

	if name == "Lightning" then
		emitter.Texture = "rbxassetid://6763809313"
		emitter.Speed = NumberRange.new(12, 22)
		emitter.Drag = 6.0
	else
		emitter.Texture = "rbxassetid://2415893330"
	end

	emitter.Parent = att
	emitter:Emit(5)
end

function FXService.emitHitFX(targetPart, elem)
	local pos = (typeof(targetPart) == "Vector3") and targetPart or (targetPart:IsA("BasePart") and targetPart.Position or Vector3.zero)
	local att = createTempAttachment(pos)
	local emitter = Instance.new("ParticleEmitter")
	emitter.LightEmission = 0.8
	emitter.Drag = 4.0

	local name = elem.DisplayName or "Fire"
	emitter.Color = ColorSequence.new(elem.ParticleColor or elem.Color)
	emitter.Size = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0)})
	emitter.Lifetime = NumberRange.new(0.12, 0.22)
	emitter.Speed = NumberRange.new(6, 14)
	emitter.SpreadAngle = Vector2.new(180, 180)

	if name == "Lightning" then
		emitter.Texture = "rbxassetid://6763809313"
	else
		emitter.Texture = "rbxassetid://2415893330"
	end

	emitter.Parent = att
	emitter:Emit(5)
end

function FXService.emitBlockFX(hrp, elem)
	local shield = Instance.new("Part")
	shield.Shape = Enum.PartType.Ball
	shield.Material = Enum.Material.ForceField
	shield.Color = elem.Color
	shield.Size = Vector3.new(4, 4, 4)
	shield.Anchored = true
	shield.CanCollide = false
	shield.CFrame = hrp.CFrame
	shield.Parent = workspace

	local tw = TweenService:Create(shield, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(5, 5, 5),
		Transparency = 1,
	})
	tw:Play()
	Debris:AddItem(shield, 0.3)
end

function FXService.emitSpecialFX(hrp, elem)
	-- Controlled 6-8 particle radial burst
	local att = createTempAttachment(hrp, CFrame.new(0, 0, 0))
	local emitter = Instance.new("ParticleEmitter")
	emitter.LightEmission = 0.8
	emitter.Color = ColorSequence.new(elem.Color)
	emitter.Size = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0.1)})
	emitter.Lifetime = NumberRange.new(0.2, 0.35)
	emitter.Speed = NumberRange.new(8, 16)
	emitter.Drag = 3.5
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Texture = "rbxassetid://2415893330"
	emitter.Parent = att
	emitter:Emit(7)
end

function FXService.emitSpawnFX(hrp, elem)
	FXService.emitSpecialFX(hrp, elem)
end

function FXService.emitDeathFX(hrp, elem)
	FXService.emitSpecialFX(hrp, elem)
end

function FXService.emitPulse(position, color, finalSize, duration)
	local p = Instance.new("Part")
	p.Shape = Enum.PartType.Ball
	p.Material = Enum.Material.Neon
	p.Color = color
	p.Size = Vector3.new(0.8, 0.8, 0.8)
	p.Anchored = true
	p.CanCollide = false
	p.Position = position
	p.Parent = workspace

	local tw = TweenService:Create(p, TweenInfo.new(duration or 0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(finalSize or 3, finalSize or 3, finalSize or 3),
		Transparency = 1,
	})
	tw:Play()
	Debris:AddItem(p, (duration or 0.25) + 0.05)
end

return FXService
