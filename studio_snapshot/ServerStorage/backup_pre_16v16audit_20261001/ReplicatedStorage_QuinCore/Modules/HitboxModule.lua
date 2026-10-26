--// HitboxModule.lua
-- Server-authoritative hitbox creation and detection
-- Uses OverlapParams for precise hit detection with directional cone filtering

local Workspace = game:GetService("Workspace")

local HitboxModule = {}

-- Create a hitbox at a position and return all hit models
function HitboxModule.cast(cframe, size, ignoreModel)
	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude
	overlapParams.FilterDescendantsInstances = ignoreModel and {ignoreModel} or {}
	
	local hitParts = Workspace:GetPartBoundsInBox(cframe, size, overlapParams)
	
	-- Deduplicate by model
	local hitModels = {}
	local seen = {}
	
	for _, part in ipairs(hitParts) do
		local model = part.Parent
		if model and not seen[model] then
			local hum = model:FindFirstChildOfClass("Humanoid")
			if hum and hum.Health > 0 then
				seen[model] = true
				table.insert(hitModels, model)
			end
		end
	end
	
	return hitModels
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
				if dot >= 0.25 then
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
	return HitboxModule.cast(cframe, size, ignoreModel)
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
