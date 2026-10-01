--// KnockbackModule.lua
-- Physics-based knockback, launch, slam, and slide
-- Respects Weight and KnockbackResist from QuinData

local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CombatConfig = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("CombatConfig"))

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
		-- Capped launch: finisher-tier forces otherwise reach 220+ studs/s on both axes, which
		-- reads as a teleport and carries the victim out of the arena
		local launchH = math.min(effectiveForce * 1.5, CombatConfig.Knockback_MaxLaunchHorizontal or 110)
		local launchV = math.min(effectiveForce * 1.5, CombatConfig.Knockback_MaxLaunchVertical or 75)
		targetHRP.AssemblyLinearVelocity = flatDirection * launchH + Vector3.new(0, launchV, 0)
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
	local dir = direction.Unit
	local peak = speed or 25
	lv.VectorVelocity = dir * (peak * 0.3)
	lv.Attachment0 = att
	lv.Parent = hrp
	
	-- Per-frame envelope: short ramp in, then a continuous ease-out to rest (the old
	-- 6-step staircase changed speed in visible jumps)
	local total = duration or 0.25
	local rampIn = math.min(0.06, total * 0.25)
	local startClock = os.clock()
	local conn
	conn = RunService.Heartbeat:Connect(function()
		local t = os.clock() - startClock
		if t >= total or not lv.Parent then
			conn:Disconnect()
			if lv.Parent then lv:Destroy() end
			if att.Parent then att:Destroy() end
			return
		end
		local k
		if t < rampIn then
			k = 0.3 + 0.7 * (t / rampIn)
		else
			local p = (t - rampIn) / math.max(total - rampIn, 0.01)
			k = (1 - p) * (1 - p)
		end
		lv.VectorVelocity = dir * (peak * k)
	end)
end

-- Dash/slide movement for the attacker (modern LinearVelocity with full authority)
-- opts (optional): { friction = true } decays from full speed over the whole duration (a body
-- skidding to rest); { endRatio = n } sets the fraction of speed left at the end.
function KnockbackModule.applySlide(model, direction, speed, duration, opts)
	local hrp = model:FindFirstChild("HumanoidRootPart")
	if not hrp then return end
	opts = opts or {}
	
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
	local full = (speed or 95) * speedMult
	local total = (duration or 0.3) / speedMult
	local frictionMode = opts.friction == true
	local endRatio = opts.endRatio or 0.12
	-- Blend in from the body's current velocity along the slide direction (negative when it is
	-- moving the other way) over a few frames, instead of replacing the velocity in one. A
	-- slide that only continues the current motion (refresh, landing skid) has no ramp.
	local alongNow = hrp.AssemblyLinearVelocity:Dot(flatDir)
	local startK = math.clamp(alongNow / math.max(full, 0.01), -1, 1)
	local rampIn = 0
	if not frictionMode and startK < 0.9 then
		rampIn = math.min(0.05 + 0.05 * (1 - startK), total * 0.4)
	end
	lv.VectorVelocity = flatDir * (full * (rampIn > 0 and startK or 1))

	-- Each call owns the mover through a token: a slide that is refreshed before it ends is
	-- not cut off by the previous call's expiry (that produced an on/off pulse), and the
	-- last 40% eases down instead of dropping from full speed to nothing in one frame.
	local token = os.clock()
	lv:SetAttribute("SlideToken", token)
	local easeStart = total * 0.6
	local conn
	conn = RunService.Heartbeat:Connect(function()
		if not lv.Parent or lv:GetAttribute("SlideToken") ~= token then
			conn:Disconnect()
			return
		end
		local t = os.clock() - token
		if t >= total then
			conn:Disconnect()
			lv:Destroy()
			if att.Parent then att:Destroy() end
			return
		end
		local k = 1
		if t < rampIn then
			k = startK + (1 - startK) * (t / rampIn)
		elseif frictionMode then
			local p = 1 - t / total
			k = endRatio + (1 - endRatio) * p * p
		elseif t > easeStart then
			local p = (t - easeStart) / math.max(total - easeStart, 0.01)
			k = 1 - (1 - endRatio) * p * p
		end
		lv.VectorVelocity = flatDir * (full * k)
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
	local dir = direction.Unit
	local peak = pushPower * 6
	lv.VectorVelocity = dir * peak
	lv.Attachment0 = att
	lv.Parent = targetHRP
	
	-- Same travel as the old 0.15s constant push, but it bleeds off instead of cutting out
	local total = 0.28
	local startClock = os.clock()
	local conn
	conn = RunService.Heartbeat:Connect(function()
		local t = os.clock() - startClock
		if t >= total or not lv.Parent then
			conn:Disconnect()
			if lv.Parent then lv:Destroy() end
			if att.Parent then att:Destroy() end
			return
		end
		lv.VectorVelocity = dir * (peak * (1 - t / total))
	end)
end

return KnockbackModule
