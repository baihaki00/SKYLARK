--// KnockbackModule.lua
-- Knockback, launch, slam, lunge and slide
-- Respects Weight and KnockbackResist from QuinData
--
-- Pushes along the ground go through ImpulseModule (one force channel per Quin); launches into
-- the air are ballistic (a velocity set once, then gravity).

local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local QuinCore = ReplicatedStorage:WaitForChild("QuinCore")
local CombatConfig = require(QuinCore:WaitForChild("CombatConfig"))
local ImpulseModule = require(QuinCore:WaitForChild("Modules"):WaitForChild("ImpulseModule"))

local Priority = ImpulseModule.Priority
local SLIDE_FORCE = 150000 -- slides and knockbacks have full authority over the body's walking
local FLINCH_TIME = 0.3
local LUNGE_FORCE = 60000 -- enough to carry the step-in over the Humanoid's own braking

-- A launch owns the body: drop every ground push and any vertical slam mover
local function cleanupMovers(targetModel, hrp)
	ImpulseModule.cancel(targetModel)
	for _, child in ipairs(hrp:GetChildren()) do
		if child.Name:find("^KB_Slam") then
			child:Destroy()
		end
	end
end

-- Push strength after the victim's weight and knockback resistance
local function resisted(targetModel, amount)
	local weight = targetModel:GetAttribute("Weight") or 1.0
	local resist = targetModel:GetAttribute("KnockbackResist") or 0.0
	return amount * (1 - resist) / weight
end

local KnockbackModule = {}

-- Ground knockback: the victim skids away on its feet like on ice (speed in studs/s at the start)
function KnockbackModule.applyGroundKnockback(targetModel, direction, speed, duration)
	local effectiveSpeed = resisted(targetModel, speed)
	if effectiveSpeed <= 0 then return end
	ImpulseModule.push(targetModel, "knockback", direction, effectiveSpeed, duration or 0.5, {
		profile = "friction", endRatio = 0.05, priority = Priority.Knockback, maxForce = SLIDE_FORCE, rampIn = 0.03,
	})
end

-- Apply horizontal knockback (punches, combos)
function KnockbackModule.applyKnockback(targetModel, direction, force, duration)
	local targetHRP = targetModel:FindFirstChild("HumanoidRootPart")
	local humanoid = targetModel:FindFirstChildOfClass("Humanoid")
	if not targetHRP or not humanoid then return end
	
	cleanupMovers(targetModel, targetHRP)
	
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
	
	cleanupMovers(targetModel, targetHRP)
	
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

-- Ground knockback given as the distance the victim should skid on a free floor
function KnockbackModule.applyGroundSkid(targetModel, direction, studs, duration)
	duration = duration or 0.6
	KnockbackModule.applyGroundKnockback(targetModel, direction, ImpulseModule.speedForDistance(studs, duration, "friction", 0.05), duration)
end

-- Meteor slam (air to ground)
function KnockbackModule.applySlam(targetModel, downForce)
	local targetHRP = targetModel:FindFirstChild("HumanoidRootPart")
	if not targetHRP then return end

	cleanupMovers(targetModel, targetHRP)

	downForce = downForce or 200

	local att = Instance.new("Attachment")
	att.Name = "KB_SlamAtt"
	att.Parent = targetHRP

	local lv = Instance.new("LinearVelocity")
	lv.Name = "KB_SlamVelocity"
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

-- Attacker's step into a strike: a short burst that eases out.
-- maxTravel (optional) caps the distance covered, so a strike thrown at arm's length does not
-- carry the attacker into (and through) its target.
function KnockbackModule.applyLunge(model, direction, speed, duration, maxTravel)
	speed = speed or 25
	duration = duration or 0.25
	if maxTravel then
		speed = math.min(speed, ImpulseModule.speedForDistance(maxTravel, duration, "lunge"))
	end
	ImpulseModule.push(model, "lunge", direction, speed, duration, {
		profile = "lunge", priority = Priority.SelfMotion, maxForce = LUNGE_FORCE,
	})
end

-- Dash / dodge / skid for the body itself.
-- opts (optional): { friction = true } decays from full speed over the whole duration (a body
-- skidding to rest); { endRatio = n } sets the fraction of speed left at the end.
function KnockbackModule.applySlide(model, direction, speed, duration, opts)
	local hrp = model:FindFirstChild("HumanoidRootPart")
	if not hrp then return end
	opts = opts or {}

	local flatDir = Vector3.new(direction.X, 0, direction.Z)
	if flatDir.Magnitude < 0.001 then
		flatDir = hrp.CFrame.LookVector
	end

	local speedMult = workspace:GetAttribute("GameSpeedMultiplier") or 1.0
	local friction = opts.friction == true
	ImpulseModule.push(model, "slide", flatDir, (speed or 95) * speedMult, (duration or 0.3) / speedMult, {
		profile = friction and "friction" or "hold",
		endRatio = opts.endRatio or 0.12,
		priority = Priority.SelfMotion,
		maxForce = SLIDE_FORCE,
		rampIn = friction and 0 or nil,
	})
end

-- True while a slide / skid started through applySlide is still carrying the body
function KnockbackModule.isSliding(model)
	return ImpulseModule.isActive(model, "slide")
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

-- Flinch: the victim gives ground without leaving its feet, sliding `studs` back and bleeding off
function KnockbackModule.applyMicroKnockback(targetModel, direction, studs)
	local distance = resisted(targetModel, studs)
	if distance <= 0 then return end
	ImpulseModule.push(targetModel, "flinch", direction, ImpulseModule.speedForDistance(distance, FLINCH_TIME, "friction", 0), FLINCH_TIME, {
		profile = "friction", endRatio = 0, priority = Priority.Reaction, rampIn = 0.03,
	})
end

return KnockbackModule
