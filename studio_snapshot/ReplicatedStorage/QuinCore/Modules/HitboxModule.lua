--// HitboxModule.lua
-- Server-authoritative hitbox creation and detection
-- Uses OverlapParams for precise hit detection with directional cone filtering

local Workspace = game:GetService("Workspace")

local HitboxModule = {}

-- Every Quin is hit as the same upright body around its root, whatever its mesh. (The parts
-- themselves are no measure: the skinned mesh part is a T-pose bounding box 8 studs wide and
-- 1.4-1.6 deep that differs per rig, so reach used to depend on the target's build and angle.)
local BODY_RADIUS = 1.5
local BODY_HALF_HEIGHT = 3.5

-- Create a hitbox at a position and return all hit models
function HitboxModule.cast(cframe, size, ignoreModel)
	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude
	overlapParams.FilterDescendantsInstances = ignoreModel and {ignoreModel} or {}
	
	local reach = Vector3.new(BODY_RADIUS, BODY_HALF_HEIGHT, BODY_RADIUS)
	local hitParts = Workspace:GetPartBoundsInBox(cframe, size + reach * 2, overlapParams)

	-- Player costumes live outside the tournament: a hit only connects within the same
	-- world (fighter -> fighter, costume -> costume). An attacker-less cast is a fighter cast.
	local attackerIsCostume = ignoreModel ~= nil and ignoreModel:GetAttribute("IsCostume") == true
	
	-- Deduplicate by model
	local hitModels = {}
	local seen = {}
	
	for _, part in ipairs(hitParts) do
		local model = part.Parent
		if model and not seen[model] and (model:GetAttribute("IsCostume") == true) == attackerIsCostume then
			seen[model] = true
			local hum = model:FindFirstChildOfClass("Humanoid")
			local root = model:FindFirstChild("HumanoidRootPart")
			if hum and hum.Health > 0 and root then
				local offset = cframe:PointToObjectSpace(root.Position)
				if math.abs(offset.X) <= size.X / 2 + reach.X and math.abs(offset.Y) <= size.Y / 2 + reach.Y and math.abs(offset.Z) <= size.Z / 2 + reach.Z then
					table.insert(hitModels, model)
				end
			end
		end
	end
	
	return hitModels
end

-- Solid geometry between two bodies blocks a blow: it lands if the line from the attacker's chest
-- or its head to the target's is clear (a fist goes over waist-high cover, not through a wall).
-- Measured 2026-10-27: with a wall put between four fighting pairs, 4 hits went through it.
local wallParams = RaycastParams.new()
wallParams.FilterType = Enum.RaycastFilterType.Exclude
wallParams.RespectCanCollide = true
function HitboxModule.clearBetween(fromRoot, toRoot)
	wallParams.FilterDescendantsInstances = { fromRoot.Parent, toRoot.Parent, Workspace:FindFirstChild("QuinServer") }
	for _, up in ipairs({ 1.5, 3 }) do
		local a = fromRoot.Position + Vector3.new(0, up, 0)
		local b = toRoot.Position + Vector3.new(0, up, 0)
		if not Workspace:Raycast(a, b - a, wallParams) then
			return true
		end
	end
	return false
end

-- Cast a hitbox in front of a fighter with forward angle filtering
function HitboxModule.castInFront(rootPart, size, offset, ignoreModel)
	size = size or Vector3.new(5, 5, 5)
	offset = offset or Vector3.new(0, 0, -3)
	
	local hitboxCFrame = rootPart.CFrame * CFrame.new(offset)
	local candidates = HitboxModule.cast(hitboxCFrame, size, ignoreModel or rootPart.Parent)
	
	-- Directional verification: target must be in front of the attacker (forward ~75 degrees)
	local hitModels = {}
	local lookVec = rootPart.CFrame.LookVector
	for _, m in ipairs(candidates) do
		local mHRP = m:FindFirstChild("HumanoidRootPart")
		if mHRP then
			local toTarget = (mHRP.Position - rootPart.Position)
			local flatDir = Vector3.new(toTarget.X, 0, toTarget.Z)
			if flatDir.Magnitude > 0.01 then
				local dot = lookVec:Dot(flatDir.Unit)
				if dot >= 0.25 and HitboxModule.clearBetween(rootPart, mHRP) then
					table.insert(hitModels, m)
				end
			else
				table.insert(hitModels, m)
			end
		else
			table.insert(hitModels, m)
		end
	end
	
	return hitModels
end

-- Cast an AoE hitbox (for slams, specials)
function HitboxModule.castAoE(position, radius, ignoreModel)
	local size = Vector3.new(radius * 2, radius, radius * 2)
	local cframe = CFrame.new(position)
	local hits = HitboxModule.cast(cframe, size, ignoreModel)
	-- (a blast does not go through a wall either: kept only where the caster's body has a clear line)
	local casterRoot = ignoreModel and ignoreModel:FindFirstChild("HumanoidRootPart")
	if not casterRoot then return hits end
	local kept = {}
	for _, m in ipairs(hits) do
		local root = m:FindFirstChild("HumanoidRootPart")
		if not root or HitboxModule.clearBetween(casterRoot, root) then
			table.insert(kept, m)
		end
	end
	return kept
end

-- Visual debug hitbox (optional)
function HitboxModule.debugVisualize(cframe, size, duration)
	local part = Instance.new("Part")
	part.Size = size
	part.CFrame = cframe
	part.Anchored = true
	part.CanCollide = false
	part.Transparency = 0.7
	part.Color = Color3.fromRGB(255, 0, 0)
	part.Material = Enum.Material.Neon
	part.Parent = Workspace
	game:GetService("Debris"):AddItem(part, duration or 0.2)
end

return HitboxModule
