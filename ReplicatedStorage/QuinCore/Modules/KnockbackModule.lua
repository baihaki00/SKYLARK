--// KnockbackModule.lua
-- Physics-based knockback, launch, slam, and slide
-- Respects Weight and KnockbackResist from QuinData

local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")

local function cleanupMovers(hrp)
	for _, child in ipairs(hrp:GetChildren()) do
		if child.Name:find("^KB_") or child.Name:find("^Slide") then
			child:Destroy()
		end
		-- Also clean up old unnamed ones just in case
		if child:IsA("AlignPosition") and child.MaxAxesForce == Vector3.new(0, 100000, 0) then
			child:Destroy()
		end
	end
end

local KnockbackModule = {}

-- Apply ground knockback (ice gliding)
function KnockbackModule.applyGroundKnockback(targetModel, direction, force, duration)
	local targetHRP = targetModel:FindFirstChild("HumanoidRootPart")
	if not targetHRP then return end
	
	cleanupMovers(targetHRP)
	
	local weight = targetModel:GetAttribute("Weight") or 1.0
	local resist = targetModel:GetAttribute("KnockbackResist") or 0.0
	
	local effectiveForce = force * (1 - resist) / weight
	if effectiveForce <= 0 then return end
	
	local flatDirection = Vector3.new(direction.X, 0, direction.Z).Unit
	
	local lv = Instance.new("LinearVelocity")
	lv.Name = "KB_LinearVelocity"
	lv.ForceLimitMode = Enum.ForceLimitMode.PerAxis
	lv.MaxAxesForce = Vector3.new(100000, 0, 100000) -- Never counteract vertical gravity
	lv.VectorVelocity = flatDirection * effectiveForce
	
	local att = Instance.new("Attachment")
	att.Name = "KB_Att"
	att.Parent = targetHRP
	lv.Attachment0 = att
	lv.Parent = targetHRP
	
	-- No AlignPosition to lock X and Z, just let the LinearVelocity push them horizontally!
	
	-- Decelerate over time
	local steps = 10
	local stepTime = (duration or 0.5) / steps
	task.spawn(function()
		for i = 1, steps do
			task.wait(stepTime)
			if lv.Parent then
				lv.VectorVelocity = lv.VectorVelocity * 0.7 -- friction decay
			end
		end
		lv:Destroy()
		att:Destroy()
	end)
end

-- Apply horizontal knockback (punches, combos)
function KnockbackModule.applyKnockback(targetModel, direction, force, duration)
	local targetHRP = targetModel:FindFirstChild("HumanoidRootPart")
	local humanoid = targetModel:FindFirstChildOfClass("Humanoid")
	if not targetHRP or not humanoid then return end
	
	cleanupMovers(targetHRP)
	
	local weight = targetModel:GetAttribute("Weight") or 1.0
	local resist = targetModel:GetAttribute("KnockbackResist") or 0.0
	
	local effectiveForce = force * (1 - resist) / weight
	if effectiveForce <= 0 then return end
	
	targetModel:SetAttribute("LaunchedAt", tick())
	humanoid.PlatformStand = true
	
	-- Flatten direction to ensure consistent horizontal push even if the hit came from above
	local flatDirection = Vector3.new(direction.X, 0, direction.Z)
	if flatDirection.Magnitude > 0.001 then
		flatDirection = flatDirection.Unit
	else
		-- Fallback: knock them backward relative to themselves
		flatDirection = -targetHRP.CFrame.LookVector
	end
	
	-- Parabolic throw using instant velocity
	local isShowdown = (workspace:GetAttribute("LeaderShowdownActive") == true) or (targetModel:GetAttribute("LeaderShowdownRole") ~= nil)
	if isShowdown then
		-- Grounded sacred duel: tight martial-arts stagger recoil, strictly contained
		local clampedForce = math.min(effectiveForce, 24)
		targetHRP.AssemblyLinearVelocity = flatDirection * clampedForce + Vector3.new(0, 6, 0)
	else
		targetHRP.AssemblyLinearVelocity = flatDirection * (effectiveForce * 1.5) + Vector3.new(0, effectiveForce * 1.5, 0)
	end

	-- Procedural Combat Reaction Telemetry
	targetModel:SetAttribute("ImpactTime", tick())
	targetModel:SetAttribute("ImpactDir", flatDirection)
	targetModel:SetAttribute("ImpactMag", math.clamp(effectiveForce / 100, 0.5, 1.0))
	targetModel:SetAttribute("ImpactType", "KNOCKBACK")
end

-- Launch enemy into the air (uppercut)
function KnockbackModule.applyLaunch(targetModel, verticalForce, horizontalForce)
	local targetHRP = targetModel:FindFirstChild("HumanoidRootPart")
	local humanoid = targetModel:FindFirstChildOfClass("Humanoid")
	if not targetHRP or not humanoid then return end
	
	cleanupMovers(targetHRP)
	
	local weight = targetModel:GetAttribute("Weight") or 1.0
	local launchPower = targetModel:GetAttribute("LaunchPower") or 1.0
	
	verticalForce = (verticalForce or 120) / weight
	horizontalForce = (horizontalForce or 20) / weight

	local isShowdown = (workspace:GetAttribute("LeaderShowdownActive") == true) or (targetModel:GetAttribute("LeaderShowdownRole") ~= nil)
	if isShowdown then
		verticalForce = math.min(verticalForce, 14)
		horizontalForce = math.min(horizontalForce, 12)
	end
	
	targetModel:SetAttribute("LaunchedAt", tick())
	humanoid.PlatformStand = true
	
	targetHRP.AssemblyLinearVelocity = Vector3.new(0, verticalForce * 1.2, 0) + targetHRP.CFrame.LookVector * (-horizontalForce * 1.2)

	-- Procedural Combat Reaction Telemetry
	targetModel:SetAttribute("ImpactTime", tick())
	targetModel:SetAttribute("ImpactDir", Vector3.new(0, 1, 0) - targetHRP.CFrame.LookVector * 0.4)
	targetModel:SetAttribute("ImpactMag", 0.9)
	targetModel:SetAttribute("ImpactType", "LAUNCH")
end

-- Meteor slam (air to ground)
function KnockbackModule.applySlam(targetModel, downForce)
	local targetHRP = targetModel:FindFirstChild("HumanoidRootPart")
	if not targetHRP then return end
	
	cleanupMovers(targetHRP)
	
	downForce = downForce or 200
	
	local att = Instance.new("Attachment")
	att.Name = "KB_Att"
	att.Parent = targetHRP
	
	local lv = Instance.new("LinearVelocity")
	lv.Name = "KB_LinearVelocity"
	lv.ForceLimitMode = Enum.ForceLimitMode.PerAxis
	lv.MaxAxesForce = Vector3.new(0, 250000, 0)
	lv.VectorVelocity = Vector3.new(0, -downForce, 0)
	lv.Attachment0 = att
	lv.Parent = targetHRP
	
	Debris:AddItem(lv, 0.35)
	Debris:AddItem(att, 0.35)

	-- Procedural Combat Reaction Telemetry
	targetModel:SetAttribute("ImpactTime", tick())
	targetModel:SetAttribute("ImpactDir", Vector3.new(0, -1, 0))
	targetModel:SetAttribute("ImpactMag", 1.0)
	targetModel:SetAttribute("ImpactType", "SLAM")
end

-- Dash/slide movement for the attacker (Lunge / Overshoot)
function KnockbackModule.applyLunge(model, direction, speed, duration)
	local hrp = model:FindFirstChild("HumanoidRootPart")
	if not hrp then return end
	
	local att = Instance.new("Attachment")
	att.Name = "KB_LungeAtt"
	att.Parent = hrp
	
	local lv = Instance.new("LinearVelocity")
	lv.Name = "KB_LungeVelocity"
	lv.ForceLimitMode = Enum.ForceLimitMode.PerAxis
	lv.MaxAxesForce = Vector3.new(18000, 0, 18000)
	lv.VectorVelocity = direction.Unit * (speed or 25)
	lv.Attachment0 = att
	lv.Parent = hrp
	
	-- Decay to simulate stopping inertia
	local steps = 6
	local stepTime = (duration or 0.25) / steps
	task.spawn(function()
		for i = 1, steps do
			task.wait(stepTime)
			if lv.Parent then
				lv.VectorVelocity = lv.VectorVelocity * 0.6
			end
		end
		if lv and lv.Parent then lv:Destroy() end
		if att and att.Parent then att:Destroy() end
	end)
end

-- Dash/slide movement for the attacker (modern LinearVelocity with full authority)
function KnockbackModule.applySlide(model, direction, speed, duration)
	local hrp = model:FindFirstChild("HumanoidRootPart")
	if not hrp then return end
	
	local att = hrp:FindFirstChild("SlideAtt")
	if not att then
		att = Instance.new("Attachment")
		att.Name = "SlideAtt"
		att.Parent = hrp
	end
	
	local lv = hrp:FindFirstChild("SlideLV")
	if not lv then
		lv = Instance.new("LinearVelocity")
		lv.Name = "SlideLV"
		lv.ForceLimitMode = Enum.ForceLimitMode.PerAxis
		lv.MaxAxesForce = Vector3.new(150000, 0, 150000)
		lv.Attachment0 = att
		lv.Parent = hrp
	end
	
	local flatDir = Vector3.new(direction.X, 0, direction.Z)
	if flatDir.Magnitude > 0.001 then
		flatDir = flatDir.Unit
	else
		flatDir = hrp.CFrame.LookVector
	end
	
	local speedMult = workspace:GetAttribute("GameSpeedMultiplier") or 1.0
	lv.VectorVelocity = flatDir * ((speed or 95) * speedMult)
	
	task.delay((duration or 0.3) / speedMult, function()
		if lv and lv.Parent then lv:Destroy() end
		if att and att.Parent then att:Destroy() end
	end)
end

-- Wall bounce detection
function KnockbackModule.checkWallBounce(rootPart, direction, bounceDistance)
	bounceDistance = bounceDistance or 15
	local params = RaycastParams.new()
	params.FilterDescendantsInstances = {rootPart.Parent}
	params.FilterType = Enum.RaycastFilterType.Exclude
	
	local result = Workspace:Raycast(rootPart.Position, direction.Unit * bounceDistance, params)
	if result then
		return true, result.Position, result.Normal
	end
	return false
end

-- Apply tiny knockback without lifting them (flinch push)
function KnockbackModule.applyMicroKnockback(targetModel, direction, studs)
	local targetHRP = targetModel:FindFirstChild("HumanoidRootPart")
	if not targetHRP then return end
	
	local weight = targetModel:GetAttribute("Weight") or 1.0
	local resist = targetModel:GetAttribute("KnockbackResist") or 0.0
	local pushPower = (studs / weight) * (1 - resist)
	if pushPower <= 0 then return end
	
	local att = Instance.new("Attachment")
	att.Name = "KB_MicroAtt"
	att.Parent = targetHRP
	
	local lv = Instance.new("LinearVelocity")
	lv.Name = "KB_MicroVelocity"
	lv.ForceLimitMode = Enum.ForceLimitMode.PerAxis
	lv.MaxAxesForce = Vector3.new(18000, 0, 18000)
	lv.VectorVelocity = direction.Unit * (pushPower * 6)
	lv.Attachment0 = att
	lv.Parent = targetHRP
	
	Debris:AddItem(lv, 0.15)
	Debris:AddItem(att, 0.15)
end

return KnockbackModule
