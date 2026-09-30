--// QuinAccessoryModule.lua
-- Authoritative Accessory & Cosmetic System for Skinned Quin Combat Entities
-- Rule 1: Physics != Visuals. All accessories are purely visual (CanCollide=false, Massless=true)
-- Attached via modern Roblox RigidConstraints directly to Mixamo bone hierarchy.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local QuinAccessoryModule = {}

-- Folder for equipped cosmetic instances inside a Quin model
local ACCESSORY_FOLDER_NAME = "QuinAccessories"

-- ============================================================================
-- 1. ACCESSORY CATALOG & REGISTRY
-- ============================================================================

local Registry = {}

-- Helper to make parts purely visual and physics-safe
local function sanitizePart(part)
	if part:IsA("BasePart") then
		part.CanCollide = false
		part.CanTouch = false
		part.CanQuery = false
		part.Massless = true
		part.CastShadow = true
	end
	for _, child in ipairs(part:GetDescendants()) do
		if child:IsA("BasePart") then
			child.CanCollide = false
			child.CanTouch = false
			child.CanQuery = false
			child.Massless = true
			child.CastShadow = true
		end
	end
end

-- Procedural model builders for starter cosmetics
local Builders = {}

-- 1. Vanguard Helm (Head Slot)
function Builders.VanguardHelm()
	local model = Instance.new("Model")
	model.Name = "VanguardHelm"

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(1.4, 1.25, 1.45)
	handle.Color = Color3.fromRGB(55, 60, 72)
	handle.Material = Enum.Material.Metal
	handle.Parent = model
	model.PrimaryPart = handle

	-- Visor slit
	local visor = Instance.new("Part")
	visor.Name = "Visor"
	visor.Size = Vector3.new(1.1, 0.22, 0.2)
	visor.Color = Color3.fromRGB(240, 180, 40)
	visor.Material = Enum.Material.Neon
	visor.Parent = model

	local visorWeld = Instance.new("WeldConstraint")
	visorWeld.Part0 = handle
	visorWeld.Part1 = visor
	visorWeld.Parent = visor
	visor.CFrame = handle.CFrame * CFrame.new(0, -0.05, -0.68)

	-- Crest / Mohawk ridge
	local crest = Instance.new("Part")
	crest.Name = "Crest"
	crest.Size = Vector3.new(0.25, 0.45, 1.3)
	crest.Color = Color3.fromRGB(190, 45, 45)
	crest.Material = Enum.Material.SmoothPlastic
	crest.Parent = model

	local crestWeld = Instance.new("WeldConstraint")
	crestWeld.Part0 = handle
	crestWeld.Part1 = crest
	crestWeld.Parent = crest
	crest.CFrame = handle.CFrame * CFrame.new(0, 0.72, 0)

	sanitizePart(model)
	return model
end

-- 2. Ronin Kasa / Straw Hat (Head Slot)
function Builders.RoninKasa()
	local model = Instance.new("Model")
	model.Name = "RoninKasa"

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Shape = Enum.PartType.Cylinder
	handle.Size = Vector3.new(0.18, 3.2, 3.2) -- Cylinder orientation: X is length/height
	handle.Color = Color3.fromRGB(175, 140, 95)
	handle.Material = Enum.Material.Wood
	handle.Parent = model
	model.PrimaryPart = handle

	-- Top cone
	local cone = Instance.new("Part")
	cone.Name = "Crown"
	cone.Shape = Enum.PartType.Cylinder
	cone.Size = Vector3.new(0.4, 1.4, 1.4)
	cone.Color = Color3.fromRGB(130, 100, 65)
	cone.Material = Enum.Material.Wood
	cone.Parent = model

	local coneWeld = Instance.new("WeldConstraint")
	coneWeld.Part0 = handle
	coneWeld.Part1 = cone
	coneWeld.Parent = cone
	cone.CFrame = handle.CFrame * CFrame.new(0.2, 0, 0)

	sanitizePart(model)
	return model
end

-- 3. Solar Cape (Back Slot)
function Builders.SolarCape()
	local model = Instance.new("Model")
	model.Name = "SolarCape"

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(2.6, 3.8, 0.15)
	handle.Color = Color3.fromRGB(180, 35, 35)
	handle.Material = Enum.Material.Fabric
	handle.Parent = model
	model.PrimaryPart = handle

	-- Golden clasp brooches at the shoulders
	local leftClasp = Instance.new("Part")
	leftClasp.Name = "Clasp_L"
	leftClasp.Size = Vector3.new(0.35, 0.35, 0.35)
	leftClasp.Color = Color3.fromRGB(255, 215, 0)
	leftClasp.Material = Enum.Material.Metal
	leftClasp.Parent = model

	local lWeld = Instance.new("WeldConstraint")
	lWeld.Part0 = handle
	lWeld.Part1 = leftClasp
	lWeld.Parent = leftClasp
	leftClasp.CFrame = handle.CFrame * CFrame.new(-1.1, 1.75, -0.15)

	local rightClasp = Instance.new("Part")
	rightClasp.Name = "Clasp_R"
	rightClasp.Size = Vector3.new(0.35, 0.35, 0.35)
	rightClasp.Color = Color3.fromRGB(255, 215, 0)
	rightClasp.Material = Enum.Material.Metal
	rightClasp.Parent = model

	local rWeld = Instance.new("WeldConstraint")
	rWeld.Part0 = handle
	rWeld.Part1 = rightClasp
	rWeld.Parent = rightClasp
	rightClasp.CFrame = handle.CFrame * CFrame.new(1.1, 1.75, -0.15)

	sanitizePart(model)
	return model
end

-- 4. Windstrider Boots (Feet Slot - Bilateral)
function Builders.WindstriderBoots()
	local model = Instance.new("Model")
	model.Name = "WindstriderBoots"

	local function createSingleBoot(sideName)
		local boot = Instance.new("Part")
		boot.Name = "Boot_" .. sideName
		boot.Size = Vector3.new(0.9, 0.85, 1.5)
		boot.Color = Color3.fromRGB(35, 40, 50)
		boot.Material = Enum.Material.Metal
		boot.Parent = model

		-- Glowing elemental sole
		local sole = Instance.new("Part")
		sole.Name = "Sole_" .. sideName
		sole.Size = Vector3.new(0.85, 0.15, 1.45)
		sole.Color = Color3.fromRGB(60, 220, 255)
		sole.Material = Enum.Material.Neon
		sole.Parent = model

		local sWeld = Instance.new("WeldConstraint")
		sWeld.Part0 = boot
		sWeld.Part1 = sole
		sWeld.Parent = sole
		sole.CFrame = boot.CFrame * CFrame.new(0, -0.42, 0)

		-- Ankle Wing Accent
		local wing = Instance.new("Part")
		wing.Name = "Wing_" .. sideName
		wing.Size = Vector3.new(0.12, 0.5, 0.6)
		wing.Color = Color3.fromRGB(255, 255, 255)
		wing.Material = Enum.Material.SmoothPlastic
		wing.Parent = model

		local wWeld = Instance.new("WeldConstraint")
		wWeld.Part0 = boot
		wWeld.Part1 = wing
		wWeld.Parent = wing
		local xOffset = (sideName == "L") and -0.52 or 0.52
		wing.CFrame = boot.CFrame * CFrame.new(xOffset, 0.25, -0.3) * CFrame.Angles(math.rad(20), 0, (sideName == "L") and math.rad(-15) or math.rad(15))

		return boot
	end

	local leftBoot = createSingleBoot("L")
	local rightBoot = createSingleBoot("R")
	model.PrimaryPart = leftBoot

	sanitizePart(model)
	return model
end

-- 5. Shadow Pauldrons (Shoulders Slot - Bilateral)
function Builders.ShadowPauldrons()
	local model = Instance.new("Model")
	model.Name = "ShadowPauldrons"

	local function createShoulder(sideName)
		local p = Instance.new("Part")
		p.Name = "Pauldron_" .. sideName
		p.Size = Vector3.new(1.1, 0.6, 1.1)
		p.Color = Color3.fromRGB(40, 35, 50)
		p.Material = Enum.Material.Metal
		p.Parent = model

		local spike = Instance.new("Part")
		spike.Name = "Spike_" .. sideName
		spike.Size = Vector3.new(0.3, 0.6, 0.3)
		spike.Color = Color3.fromRGB(160, 60, 240)
		spike.Material = Enum.Material.Neon
		spike.Parent = model

		local sWeld = Instance.new("WeldConstraint")
		sWeld.Part0 = p
		sWeld.Part1 = spike
		sWeld.Parent = spike
		spike.CFrame = p.CFrame * CFrame.new(0, 0.45, 0)

		return p
	end

	local leftP = createShoulder("L")
	local rightP = createShoulder("R")
	model.PrimaryPart = leftP

	sanitizePart(model)
	return model
end

-- Populate built-in definitions
Registry["VanguardHelm"] = {
	Id = "VanguardHelm",
	DisplayName = "Iron Vanguard Helmet",
	Slot = "Head",
	TargetBone = "mixamorig:Head",
	Offset = CFrame.new(0, -0.22, 0.1),
	Builder = Builders.VanguardHelm,
}

Registry["RoninKasa"] = {
	Id = "RoninKasa",
	DisplayName = "Wanderer's Kasa",
	Slot = "Head",
	TargetBone = "mixamorig:Head",
	Offset = CFrame.new(0, -0.45, 0.05) * CFrame.Angles(0, 0, math.rad(90)), -- Rotate cylinder flat
	Builder = Builders.RoninKasa,
}

Registry["SolarCape"] = {
	Id = "SolarCape",
	DisplayName = "Solar Vanguard Cape",
	Slot = "Back",
	TargetBone = "mixamorig:Spine2",
	Offset = CFrame.new(0, 1.65, -0.45) * CFrame.Angles(math.rad(12), 0, 0),
	Builder = Builders.SolarCape,
}

Registry["WindstriderBoots"] = {
	Id = "WindstriderBoots",
	DisplayName = "Windstrider Boots",
	Slot = "Feet",
	IsBilateral = true,
	Bones = {
		L = "mixamorig:LeftFoot",
		R = "mixamorig:RightFoot",
	},
	Offsets = {
		L = CFrame.new(0, 0.22, -0.2),
		R = CFrame.new(0, 0.22, -0.2),
	},
	Parts = {
		L = "Boot_L",
		R = "Boot_R",
	},
	Builder = Builders.WindstriderBoots,
}

Registry["ShadowPauldrons"] = {
	Id = "ShadowPauldrons",
	DisplayName = "Shadow Pauldrons",
	Slot = "Shoulders",
	IsBilateral = true,
	Bones = {
		L = "mixamorig:LeftShoulder",
		R = "mixamorig:RightShoulder",
	},
	Offsets = {
		L = CFrame.new(0, 0.35, 0),
		R = CFrame.new(0, 0.35, 0),
	},
	Parts = {
		L = "Pauldron_L",
		R = "Pauldron_R",
	},
	Builder = Builders.ShadowPauldrons,
}

-- ============================================================================
-- 2. CORE EQUIPPING PIPELINE
-- ============================================================================

local function getOrCreateAccessoryFolder(quinModel)
	local folder = quinModel:FindFirstChild(ACCESSORY_FOLDER_NAME)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = ACCESSORY_FOLDER_NAME
		folder.Parent = quinModel
	end
	return folder
end

local function findBone(quinModel, boneName)
	local surface = quinModel:FindFirstChild("Alpha_Surface")
	if not surface then return nil end
	return surface:FindFirstChild(boneName, true)
end

-- Equip an accessory onto a Quin model
function QuinAccessoryModule.equip(quinModel, accessoryId)
	if not quinModel or not quinModel.Parent then return false, "Invalid Quin model" end
	local def = Registry[accessoryId]
	if not def then
		return false, string.format("Accessory '%s' not found in registry", tostring(accessoryId))
	end

	-- 1. Unequip any existing item in this slot first
	QuinAccessoryModule.unequip(quinModel, def.Slot)

	-- 2. Build or clone the accessory model
	local accModel = def.Builder and def.Builder()
	if not accModel then
		return false, "Failed to instantiate accessory model"
	end
	accModel.Name = def.Slot .. "_" .. accessoryId

	local accFolder = getOrCreateAccessoryFolder(quinModel)

	if def.IsBilateral then
		-- Bilateral items attach separate parts to Left and Right bones (e.g. Boots, Pauldrons)
		local leftBone = findBone(quinModel, def.Bones.L)
		local rightBone = findBone(quinModel, def.Bones.R)
		if not leftBone or not rightBone then
			accModel:Destroy()
			return false, string.format("Missing skeleton bones (%s, %s)", def.Bones.L, def.Bones.R)
		end

		local leftPart = accModel:FindFirstChild(def.Parts.L)
		local rightPart = accModel:FindFirstChild(def.Parts.R)
		if not leftPart or not rightPart then
			accModel:Destroy()
			return false, "Bilateral handles missing from accessory model"
		end

		-- Left constraint
		local lAtt = Instance.new("Attachment")
		lAtt.Name = "RigidAtt"
		lAtt.CFrame = def.Offsets.L
		lAtt.Parent = leftPart

		local lRC = Instance.new("RigidConstraint")
		lRC.Name = "BoneRigidConstraint"
		lRC.Attachment0 = lAtt
		lRC.Attachment1 = leftBone
		lRC.Parent = leftPart

		-- Right constraint
		local rAtt = Instance.new("Attachment")
		rAtt.Name = "RigidAtt"
		rAtt.CFrame = def.Offsets.R
		rAtt.Parent = rightPart

		local rRC = Instance.new("RigidConstraint")
		rRC.Name = "BoneRigidConstraint"
		rRC.Attachment0 = rAtt
		rRC.Attachment1 = rightBone
		rRC.Parent = rightPart
	else
		-- Single-bone items (Helmet, Cape, Mask)
		local targetBone = findBone(quinModel, def.TargetBone)
		if not targetBone then
			accModel:Destroy()
			return false, string.format("Missing skeleton bone: %s", tostring(def.TargetBone))
		end

		local handle = accModel.PrimaryPart or accModel:FindFirstChild("Handle") or accModel:FindFirstChildWhichIsA("BasePart")
		if not handle then
			accModel:Destroy()
			return false, "Accessory model has no BasePart handle"
		end

		local att = Instance.new("Attachment")
		att.Name = "RigidAtt"
		att.CFrame = def.Offset
		att.Parent = handle

		local rc = Instance.new("RigidConstraint")
		rRC = rc
		rc.Name = "BoneRigidConstraint"
		rc.Attachment0 = att
		rc.Attachment1 = targetBone
		rc.Parent = handle
	end

	-- Parent into character folder and stamp attribute
	accModel.Parent = accFolder
	quinModel:SetAttribute("Equipped_" .. def.Slot, accessoryId)

	return true, accModel
end

-- Unequip an accessory slot from a Quin model
function QuinAccessoryModule.unequip(quinModel, slot)
	if not quinModel then return end
	local folder = quinModel:FindFirstChild(ACCESSORY_FOLDER_NAME)
	if folder then
		for _, child in ipairs(folder:GetChildren()) do
			if child.Name:sub(1, #slot + 1) == (slot .. "_") then
				child:Destroy()
			end
		end
	end
	quinModel:SetAttribute("Equipped_" .. slot, nil)
end

-- Unequip all accessories from a Quin model
function QuinAccessoryModule.unequipAll(quinModel)
	if not quinModel then return end
	local folder = quinModel:FindFirstChild(ACCESSORY_FOLDER_NAME)
	if folder then
		folder:ClearAllChildren()
	end
	local slots = { "Head", "Back", "Feet", "Shoulders", "Chest", "Waist" }
	for _, slot in ipairs(slots) do
		quinModel:SetAttribute("Equipped_" .. slot, nil)
	end
end

-- Get table of all equipped accessories on a Quin model
function QuinAccessoryModule.getEquipped(quinModel)
	if not quinModel then return {} end
	local equipped = {}
	local slots = { "Head", "Back", "Feet", "Shoulders", "Chest", "Waist" }
	for _, slot in ipairs(slots) do
		local id = quinModel:GetAttribute("Equipped_" .. slot)
		if id and id ~= "" then
			equipped[slot] = id
		end
	end
	return equipped
end

function QuinAccessoryModule.getRegistry()
	return Registry
end

function QuinAccessoryModule.register(id, def)
	Registry[id] = def
end

return QuinAccessoryModule
