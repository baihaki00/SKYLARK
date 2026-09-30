--// ProjectileJumpState.lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")
local CollectionService = game:GetService("CollectionService")

local AudioModule = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("AudioModule"))
local VfxModule = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("VfxModule"))
local TargetingModule = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("TargetingModule"))
local AnimationIds = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("AnimationIds"))
local AnimationModule = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("AnimationModule"))
local KnockbackModule = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("KnockbackModule"))

local ProjectileJumpState = { name = "ProjectileJump" }

local Config = {
	JumpPowerMin = 350,
	JumpPowerMax = 400,
	DashExecuteTimeMin = 2.0,
	DashExecuteTimeMax = 2.5,

	MultiJumpPowerMin = 200,
	MultiJumpPowerMax = 250,
	MultiJumpGapTimeMin = 0.75,
	MultiJumpGapTimeMax = 1.25,
	MultiJumpDashTimeMin = 0.75,
	MultiJumpDashTimeMax = 1.25,

	SlamSpeed = 150,     
	StrafeDistanceMin = 150,
	StrafeDistanceMax = 300,
	CurveAggressiveness = 1,
	ArcSpeedXZ = 100,

	MultiJumpForwardSpeedMin = 100,
	MultiJumpForwardSpeedMax = 200,
	MultiJumpSideSpeedMin = -200,
	MultiJumpSideSpeedMax = 200,

	ComboGapTimeMin = 0.3,
	ComboGapTimeMax = 0.6,

	-- New Bezier Settings
	BezierArcHeightBase = 50,
	BezierLateralBendBase = 40,
	BezierDashDuration = 0.5,
	BezierSpeedFloor = 0.25,
	SlamSpeedMultiplier = 1.15
}

local function getFloat(min, max)
	return min + math.random() * (max - min)
end

-- Math Helpers for Style 5
local function fluidEaseOutIn(t, sMin)
	return ((0.5 + 4 * (t - 0.5)^3) * (1 - sMin)) + (t * sMin)
end

local function calculateLowestY(Y0, Y2, ArcHeight)
	if ArcHeight == 0 then return math.min(Y0, Y2) end
	local tLowest = 0.5 - (Y0 - Y2) / (4 * ArcHeight)
	if tLowest >= 0.0 and tLowest <= 1.0 then
		local midY = (Y0 + Y2) / 2
		local P1Y = midY + ArcHeight
		return ((1 - tLowest)^2 * Y0) + (2 * (1 - tLowest) * tLowest * P1Y) + (tLowest^2 * Y2)
	else
		return math.min(Y0, Y2)
	end
end

local function isCurveSafe(P0, P1, P2, fighter, target)
	local segments = 10
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = {fighter, target}

	local prevPoint = P0
	for i = 1, segments do
		local t = i / segments
		local nextPoint = ((1 - t)^2 * P0) + (2 * (1 - t) * t * P1) + (t^2 * P2)
		local dir = nextPoint - prevPoint
		local dist = dir.Magnitude
		if dist > 0.01 then
			local hit = workspace:Spherecast(prevPoint, 2, dir.Unit * dist, params)
			if hit then return false end
		end
		prevPoint = nextPoint
	end
	return true
end

local function calculateCombatAimPoint(rootPart, targetHRP, dashSpeed, humanoid)
	local targetPos = targetHRP.Position
	local targetVel = targetHRP.AssemblyLinearVelocity
	local flatTargetVel = Vector3.new(targetVel.X, 0, targetVel.Z)

	-- Dynamic arrival time for lead interception
	local currentDist = (targetPos - rootPart.Position).Magnitude
	local speed = dashSpeed or Config.SlamSpeed or 500
	local tArrival = math.clamp(currentDist / speed, 0.04, 0.40)

	-- First-order lead position (where the moving target will be upon dive arrival)
	local leadPos = targetPos + (flatTargetVel * tArrival)

	-- Approach vector on XZ plane
	local toLeadFlat = Vector3.new(leadPos.X - rootPart.Position.X, 0, leadPos.Z - rootPart.Position.Z)
	local approachDir = toLeadFlat.Magnitude > 0.01 and toLeadFlat.Unit or rootPart.CFrame.LookVector

	-- Arena floor altitude at the landing point
	local groundY = targetPos.Y
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = {rootPart.Parent, targetHRP.Parent}
	local floorRay = workspace:Raycast(leadPos + Vector3.new(0, 10, 0), Vector3.new(0, -35, 0), rayParams)
	if floorRay then
		groundY = floorRay.Position.Y + (humanoid and humanoid.HipHeight or 2.0) + (rootPart.Size.Y / 2)
	end

	-- Striking landing spot with organic clamped trajectory scatter (Sections 42 & 43)
	-- smashes are not 100% laser-guided; landing has a 5 to 25 studs scatter (clamped strictly <= 30)
	local jumpDist = (leadPos - rootPart.Position).Magnitude
	local scatterDist = math.clamp(jumpDist * 0.12, 5.0, 25.0)
	local randAngle = math.random() * math.pi * 2
	local scatterOffset = Vector3.new(math.cos(randAngle), 0, math.sin(randAngle)) * scatterDist

	local landingSpot = leadPos - (approachDir * 4.5) + scatterOffset
	landingSpot = Vector3.new(landingSpot.X, groundY, landingSpot.Z)

	return landingSpot, approachDir, groundY
end

local stateData = {}

local function cleanupMovers(hrp)
	for _, child in ipairs(hrp:GetChildren()) do
		if child.Name == "PJ_Velocity" or child.Name == "PJ_Gyro" or child.Name == "PJ_Align" or child.Name == "PJ_Att" or child.Name == "PJ_LinearVelocity" then
			child:Destroy()
		elseif child.Name == "RocketTrail" then
			child.Enabled = false
			Debris:AddItem(child, child.Lifetime)
		elseif child.Name == "RocketTrailAtt0" or child.Name == "RocketTrailAtt1" then
			Debris:AddItem(child, 2)
		end
	end
end

local function spawnVisualizerNode(position)
	if not workspace:GetAttribute("ProjectileVisualizerEnabled") then return end
	local part = Instance.new("Part")
	part.Size = Vector3.new(1, 1, 1)
	part.Anchored = true
	part.CanCollide = false
	part.Material = Enum.Material.Neon
	part.Color = Color3.new(0, 1, 1)
	part.Position = position
	part.Parent = Workspace
	Debris:AddItem(part, 5)
end

local function playAnim(humanoid, id)
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator or not id then return nil end
	local anim = Instance.new("Animation")
	anim.AnimationId = id
	local track = animator:LoadAnimation(anim)
	track:Play(0.1)
	return track
end

local function stopAnim(track)
	if track then track:Stop(0.2) end
end

function ProjectileJumpState.enter(fighter, humanoid, rootPart)
	humanoid.PlatformStand = true
	cleanupMovers(rootPart)

	-- Select across all 7 projectile jump styles (Style 1 Parabolic, Style 5 Bezier, etc.)
	local style = fighter:GetAttribute("JumpStyle")
	if not style then
		local styles = { 1, 1, 2, 3, 4, 5, 5, 6, 7 }
		style = styles[math.random(1, #styles)]
		fighter:SetAttribute("JumpStyle", style)
	end

	local targetVal = fighter:FindFirstChild("ProjectileTarget")
	local target = targetVal and targetVal.Value
	if not target then
		local currentTgt = fighter:GetAttribute("CurrentTarget") or fighter:GetAttribute("TargetQuin")
		if currentTgt then
			target = workspace:FindFirstChild(currentTgt) or (workspace:FindFirstChild("QuinServer") and workspace.QuinServer:FindFirstChild(currentTgt))
		end
	end
	if not target then
		local CombatConfig = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("CombatConfig"))
		target, _ = TargetingModule.getNearest(rootPart, CombatConfig.ChaseRange or 1000)
	end

	local CombatConfig = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("CombatConfig"))
	local energy = fighter:GetAttribute("Energy") or 100
	local drain = CombatConfig.EnergyDrain_ProjectileJump or 40
	fighter:SetAttribute("EnergyAtActionStart", energy)
	fighter:SetAttribute("Energy", math.max(0, energy - drain))

	stateData[fighter] = {
		phase = "Init",
		style = style,
		target = target,
		startTime = tick(),
		phaseTime = tick(),
		jumpCount = 1,
		startPos = rootPart.Position,
		apexPos = nil,
		curveVelocity = nil,
		animTrack = playAnim(humanoid, AnimationIds.Jump)
	}

	AudioModule.playJumpUp(rootPart.Position)

	local att = Instance.new("Attachment")
	att.Name = "PJ_Att"
	att.Parent = rootPart

	local lv = Instance.new("LinearVelocity")
	lv.Name = "PJ_LinearVelocity"
	lv.Attachment0 = att
	lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	lv.MaxAxesForce = Vector3.new(math.huge, math.huge, math.huge)
	lv.VectorVelocity = Vector3.zero
	lv.Parent = rootPart

	local ao = Instance.new("AlignOrientation")
	ao.Name = "PJ_Align"
	ao.Mode = Enum.OrientationAlignmentMode.OneAttachment
	ao.Attachment0 = att
	ao.MaxTorque = 1e7
	ao.Responsiveness = 40
	ao.CFrame = rootPart.CFrame
	ao.Parent = rootPart
end

function ProjectileJumpState.exit(fighter, humanoid, rootPart)
	rootPart.AssemblyLinearVelocity = Vector3.zero
	rootPart.AssemblyAngularVelocity = Vector3.zero
	humanoid.PlatformStand = false
	cleanupMovers(rootPart)
	if stateData[fighter] and stateData[fighter].animTrack then
		stopAnim(stateData[fighter].animTrack)
	end
	fighter:SetAttribute("LastProjectileJumpTime", tick())
	fighter:SetAttribute("JumpStyle", nil)
	stateData[fighter] = nil
end

local function switchPhase(data, newPhase)
	data.phase = newPhase
	data.phaseTime = tick()
end

function ProjectileJumpState.update(fighter, humanoid, rootPart, DEBUG)
	local data = stateData[fighter]
	if not data then return require(script.Parent:WaitForChild("IdleState")) end

	local target = data.target
	if not target then
		return require(script.Parent:WaitForChild("FightState"))
	end
	local targetPosPart = target:FindFirstChild("HumanoidRootPart") or target.PrimaryPart or target:FindFirstChildWhichIsA("BasePart")
	if not targetPosPart then
		return require(script.Parent:WaitForChild("FightState"))
	end

	local targetPos = targetPosPart.Position
	local now = tick()
	local timeInPhase = now - data.phaseTime

	local lv = rootPart:FindFirstChild("PJ_LinearVelocity") or rootPart:FindFirstChild("PJ_Velocity")
	local ao = rootPart:FindFirstChild("PJ_Align") or rootPart:FindFirstChild("PJ_Gyro")
	if not lv or not ao then return require(script.Parent:WaitForChild("FightState")) end

	if not data.lastNodePos or (rootPart.Position - data.lastNodePos).Magnitude > 5 then
		spawnVisualizerNode(rootPart.Position)
		data.lastNodePos = rootPart.Position
	end

	local distToTarget = (targetPos - rootPart.Position).Magnitude
	local gravity = workspace.Gravity

	local function triggerComboNext()
		local action = data.comboSequence[data.comboIndex]
		if action == "Jump" then
			lv.MaxAxesForce = Vector3.zero
			local jumpPower = math.random(Config.MultiJumpPowerMin, Config.MultiJumpPowerMax)
			local forwardVec = rootPart.CFrame.LookVector
			local rightVec = rootPart.CFrame.RightVector
			local forwardSpeed = math.random(Config.MultiJumpForwardSpeedMin, Config.MultiJumpForwardSpeedMax)
			local sideSpeed = math.random(Config.MultiJumpSideSpeedMin, Config.MultiJumpSideSpeedMax)
			local driftVelocity = (forwardVec * forwardSpeed) + (rightVec * sideSpeed)

			rootPart.AssemblyLinearVelocity = Vector3.new(driftVelocity.X, jumpPower, driftVelocity.Z)

			AudioModule.playJumpUp(rootPart.Position)
			VfxModule.createLaunchShockwave(rootPart)
			if data.comboIndex == 1 then
				VfxModule.createRocketTrail(rootPart)
				VfxModule.shakeScreen(rootPart.Position, 500, 8) 
			end

			data.comboGapTime = getFloat(Config.ComboGapTimeMin, Config.ComboGapTimeMax)
			switchPhase(data, "ComboWait")

		elseif action == "Strafe" then
			switchPhase(data, "ComboStrafe")
			AudioModule.playMidairSwoosh(rootPart.Position)
			data.strafeDir = rootPart.CFrame.RightVector * (math.random() > 0.5 and 1 or -1)
			data.strafeDuration = (math.random() > 0.5) and 0.2 or 0.5
			local dist = getFloat(Config.StrafeDistanceMin, Config.StrafeDistanceMax)
			data.strafeInitialVelocity = data.strafeDir * (data.strafeDuration == 0.2 and (dist / 0.2) or (dist * 4))

		elseif action == "Dash" then
			switchPhase(data, "Dash")
			lv.MaxAxesForce = Vector3.new(math.huge, math.huge, math.huge)
			local dashSpeed = Config.SlamSpeed * Config.SlamSpeedMultiplier
			local aimPoint, approachDir, groundY = calculateCombatAimPoint(rootPart, targetPosPart, dashSpeed, humanoid)
			local offset = aimPoint - rootPart.Position
			local dashDir = offset.Magnitude > 0.001 and offset.Unit or rootPart.CFrame.LookVector
			lv.VectorVelocity = dashDir * dashSpeed
			rootPart.AssemblyLinearVelocity = lv.VectorVelocity
			ao.CFrame = CFrame.lookAt(rootPart.Position, Vector3.new(aimPoint.X, rootPart.Position.Y, aimPoint.Z))

			stopAnim(data.animTrack)
			data.animTrack = playAnim(humanoid, AnimationIds.Dash)
			AudioModule.playSonicBoom(rootPart.Position)
			VfxModule.createVaporCone(rootPart, 0.5)
		end
	end

	local speedMult = workspace:GetAttribute("GameSpeedMultiplier") or 1.0

	if data.phase == "Init" then
		if data.style == 1 or data.style == 7 then
			local dir = (targetPos - rootPart.Position)
			dir = Vector3.new(dir.X, 0, dir.Z)
			local dist = dir.Magnitude

			if data.style == 1 then
				local arcSpeed = math.clamp(dist / 1.8, 120, 260) * speedMult
				local timeToTarget = math.max(0.05, dist / arcSpeed)
				local requiredY = (targetPos.Y - rootPart.Position.Y + 0.5 * gravity * timeToTarget^2) / timeToTarget
				lv.MaxAxesForce = Vector3.new(math.huge, 0, math.huge)
				local safeDir = dist > 0.001 and dir.Unit or Vector3.new(1,0,0) -- PREVENT NAN
				lv.VectorVelocity = safeDir * arcSpeed
				rootPart.AssemblyLinearVelocity = Vector3.new(0, requiredY, 0)

				VfxModule.createRocketTrail(rootPart)
				VfxModule.createLaunchShockwave(rootPart)
				VfxModule.shakeScreen(rootPart.Position, 500, 8)
			else
				local jumpPower = math.random(Config.JumpPowerMin, Config.JumpPowerMax) * math.clamp(speedMult, 1, 2)
				lv.MaxAxesForce = Vector3.zero
				local forwardVec = rootPart.CFrame.LookVector
				local rightVec = rootPart.CFrame.RightVector
				local forwardSpeed = math.random(30, 60) * speedMult
				local sideSpeed = math.random(-40, 40) * speedMult
				local driftVelocity = (forwardVec * forwardSpeed) + (rightVec * sideSpeed)
				rootPart.AssemblyLinearVelocity = Vector3.new(driftVelocity.X, jumpPower, driftVelocity.Z)
			end

			VfxModule.createRocketTrail(rootPart)
			VfxModule.createLaunchShockwave(rootPart)
			VfxModule.shakeScreen(rootPart.Position, 500, 8)

			switchPhase(data, "Arcing")

		elseif data.style == 6 then
			local combos
			if math.random() > 0.5 then
				combos = {"Jump", "Jump", "Strafe", "Strafe", "Dash"}
			else
				combos = {"Jump", "Strafe", "Jump", "Strafe", "Dash"}
			end
			data.comboSequence = combos
			data.comboIndex = 1

			triggerComboNext()

		else
			local jumpPower
			if data.style == 3 then
				jumpPower = math.random(Config.MultiJumpPowerMin, Config.MultiJumpPowerMax)
				data.multiJumpGapTime = getFloat(Config.MultiJumpGapTimeMin, Config.MultiJumpGapTimeMax)
				data.multiJumpDashTime = getFloat(Config.MultiJumpDashTimeMin, Config.MultiJumpDashTimeMax)
			else
				jumpPower = math.random(Config.JumpPowerMin, Config.JumpPowerMax)
			end

			local yDiff = targetPos.Y - rootPart.Position.Y
			local discriminant = jumpPower^2 - 2 * gravity * yDiff
			local timeOfFlight = 1
			if discriminant > 0 then
				timeOfFlight = (jumpPower + math.sqrt(discriminant)) / gravity
			end

			data.jumpTime = timeOfFlight

			if data.style == 3 then
				data.dashExactTime = data.multiJumpGapTime + data.multiJumpDashTime
			else
				local dashExec = getFloat(Config.DashExecuteTimeMin, Config.DashExecuteTimeMax)
				data.dashExactTime = math.min(dashExec, timeOfFlight - 0.2)
			end

			lv.MaxAxesForce = Vector3.zero
			local forwardVec = rootPart.CFrame.LookVector
			local rightVec = rootPart.CFrame.RightVector
			local forwardSpeed, sideSpeed
			if data.style == 3 then
				forwardSpeed = math.random(Config.MultiJumpForwardSpeedMin, Config.MultiJumpForwardSpeedMax)
				sideSpeed = math.random(Config.MultiJumpSideSpeedMin, Config.MultiJumpSideSpeedMax)
			else
				forwardSpeed = math.random(30, 60)
				sideSpeed = math.random(-40, 40)
			end
			local driftVelocity = (forwardVec * forwardSpeed) + (rightVec * sideSpeed)
			rootPart.AssemblyLinearVelocity = Vector3.new(driftVelocity.X, jumpPower, driftVelocity.Z)

			VfxModule.createRocketTrail(rootPart)
			VfxModule.createLaunchShockwave(rootPart)
			VfxModule.shakeScreen(rootPart.Position, 500, 8) 
			switchPhase(data, "AirborneTimer")
		end

	elseif data.phase == "Arcing" then
		if rootPart.AssemblyLinearVelocity.Magnitude > 1 then
			local lookDir = rootPart.AssemblyLinearVelocity
			local flatLook = Vector3.new(lookDir.X, 0, lookDir.Z)
			if flatLook.Magnitude > 0.5 then
				ao.CFrame = CFrame.lookAt(rootPart.Position, rootPart.Position + flatLook)
			end
		end

		local isFalling = rootPart.AssemblyLinearVelocity.Y <= 0
		local isNearGround = rootPart.Position.Y <= targetPos.Y + 2
		local reachedTarget = distToTarget < 15
		if reachedTarget or (timeInPhase > 0.25 and isFalling and isNearGround) then
			switchPhase(data, "Impact")
		end

	elseif data.phase == "ComboWait" then
		if timeInPhase >= data.comboGapTime then
			data.comboIndex = data.comboIndex + 1
			triggerComboNext()
		end

		if distToTarget < 15 or (rootPart.Position.Y <= targetPos.Y + 2 and rootPart.AssemblyLinearVelocity.Y < 0) then
			switchPhase(data, "Impact")
		end

	elseif data.phase == "ComboStrafe" then
		lv.MaxAxesForce = Vector3.new(math.huge, math.huge, math.huge)
		if data.strafeDuration == 0.5 then
			local percentComplete = math.min(1, timeInPhase / data.strafeDuration)
			lv.VectorVelocity = data.strafeInitialVelocity:Lerp(Vector3.zero, percentComplete)
		else
			lv.VectorVelocity = data.strafeInitialVelocity
		end

		if timeInPhase >= data.strafeDuration then
			lv.MaxAxesForce = Vector3.zero
			data.comboGapTime = getFloat(Config.ComboGapTimeMin, Config.ComboGapTimeMax)
			switchPhase(data, "ComboWait")
		end

	elseif data.phase == "AirborneTimer" then
		local timeSinceJump = now - data.startTime
		local heightAboveTarget = rootPart.Position.Y - targetPos.Y
		local isFalling = rootPart.AssemblyLinearVelocity.Y < 0

		if data.style == 3 and data.jumpCount < 2 and timeSinceJump >= data.multiJumpGapTime then
			data.jumpCount = 2
			local midAirJumpPower = math.random(Config.MultiJumpPowerMin, Config.MultiJumpPowerMax)

			local forwardVec = rootPart.CFrame.LookVector
			local rightVec = rootPart.CFrame.RightVector
			local forwardSpeed = math.random(Config.MultiJumpForwardSpeedMin, Config.MultiJumpForwardSpeedMax)
			local sideSpeed = math.random(Config.MultiJumpSideSpeedMin, Config.MultiJumpSideSpeedMax)
			local driftVelocity = (forwardVec * forwardSpeed) + (rightVec * sideSpeed)

			rootPart.AssemblyLinearVelocity = Vector3.new(driftVelocity.X, midAirJumpPower, driftVelocity.Z)
			AudioModule.playJumpUp(rootPart.Position)
			VfxModule.createLaunchShockwave(rootPart)
		end

		if timeSinceJump >= data.dashExactTime or (isFalling and heightAboveTarget <= 60) then
			if data.style == 4 then
				switchPhase(data, "Strafe")
				AudioModule.playMidairSwoosh(rootPart.Position)
				data.strafeDir = rootPart.CFrame.RightVector * (math.random() > 0.5 and 1 or -1)
				data.strafeDuration = (math.random() > 0.5) and 0.2 or 0.5

				local dist = getFloat(Config.StrafeDistanceMin, Config.StrafeDistanceMax)
				data.strafeInitialVelocity = data.strafeDir * (data.strafeDuration == 0.2 and (dist / 0.2) or (dist * 4))
			elseif data.style == 5 then
				switchPhase(data, "Dash")
				data.dashStartTime = tick()

				-- Pre-calculate Bezier with combat offset landing point
				data.P0 = rootPart.Position
				data.P2 = calculateCombatAimPoint(rootPart, targetPosPart, Config.SlamSpeed * speedMult, humanoid)
				local p0p2Dist = (data.P2 - data.P0).Magnitude
				data.dashDuration = math.clamp(p0p2Dist / 200, Config.BezierDashDuration or 0.5, 1.8) / speedMult

				local arcHeight = Config.BezierArcHeightBase
				local lowestY = calculateLowestY(data.P0.Y, data.P2.Y, arcHeight)
				if lowestY < 0 then
					arcHeight = math.max(0, arcHeight - math.abs(lowestY))
				end

				local midPoint = (data.P0 + data.P2) / 2
				local dirXZ = Vector3.new(data.P2.X - data.P0.X, 0, data.P2.Z - data.P0.Z).Unit
				if dirXZ.Magnitude == 0 then dirXZ = Vector3.new(1,0,0) end
				local rightDir = Vector3.new(dirXZ.Z, 0, -dirXZ.X) -- Perpendicular

				local latBend = Config.BezierLateralBendBase * (math.random() > 0.5 and 1 or -1)
				data.P1 = midPoint + Vector3.new(0, arcHeight, 0) + (rightDir * latBend)

				if not isCurveSafe(data.P0, data.P1, data.P2, fighter, target) then
					latBend = latBend * -1
					data.P1 = midPoint + Vector3.new(0, arcHeight, 0) + (rightDir * latBend)
					if not isCurveSafe(data.P0, data.P1, data.P2, fighter, target) then
						data.P1 = midPoint + Vector3.new(0, arcHeight, 0)
					end
				end

				lv.MaxAxesForce = Vector3.zero
				rootPart.AssemblyLinearVelocity = Vector3.zero

				stopAnim(data.animTrack)
				data.animTrack = playAnim(humanoid, AnimationIds.Dash)
				AudioModule.playSonicBoom(rootPart.Position)
				VfxModule.createVaporCone(rootPart, Config.BezierDashDuration / speedMult)
			else
				switchPhase(data, "Dash")

				lv.MaxAxesForce = Vector3.new(math.huge, math.huge, math.huge)
				local dashSpeed = ((data.style == 3 or data.style == 7) and (Config.SlamSpeed * Config.SlamSpeedMultiplier) or Config.SlamSpeed) * speedMult
				local aimPoint, approachDir, groundY = calculateCombatAimPoint(rootPart, targetPosPart, dashSpeed, humanoid)
				local offset = aimPoint - rootPart.Position
				local dashDir = offset.Magnitude > 0.001 and offset.Unit or rootPart.CFrame.LookVector
				lv.VectorVelocity = dashDir * dashSpeed
				ao.CFrame = CFrame.lookAt(rootPart.Position, Vector3.new(aimPoint.X, rootPart.Position.Y, aimPoint.Z))

				if offset.Magnitude < 10 or rootPart.Position.Y <= groundY + 2.5 then
					switchPhase(data, "Impact")
				end
			end
			return ProjectileJumpState
		end

		if distToTarget < 15 or (rootPart.Position.Y <= targetPos.Y + 2 and rootPart.AssemblyLinearVelocity.Y < 0) then
			switchPhase(data, "Impact")
		end

	elseif data.phase == "Strafe" then
		lv.MaxAxesForce = Vector3.new(math.huge, math.huge, math.huge)
		if data.strafeDuration == 0.5 then
			local percentComplete = math.min(1, timeInPhase / data.strafeDuration)
			lv.VectorVelocity = data.strafeInitialVelocity:Lerp(Vector3.zero, percentComplete)
		else
			lv.VectorVelocity = data.strafeInitialVelocity
		end

		if timeInPhase >= data.strafeDuration then
			switchPhase(data, "Dash")

			local dashSpeed = Config.SlamSpeed
			local aimPoint, approachDir, groundY = calculateCombatAimPoint(rootPart, targetPosPart, dashSpeed, humanoid)
			local offset = aimPoint - rootPart.Position
			local dashDir = offset.Magnitude > 0.001 and offset.Unit or rootPart.CFrame.LookVector
			lv.VectorVelocity = dashDir * dashSpeed
			rootPart.AssemblyLinearVelocity = lv.VectorVelocity
			ao.CFrame = CFrame.lookAt(rootPart.Position, Vector3.new(aimPoint.X, rootPart.Position.Y, aimPoint.Z))

			stopAnim(data.animTrack)
			data.animTrack = playAnim(humanoid, AnimationIds.Dash)
			AudioModule.playSonicBoom(rootPart.Position)
			VfxModule.createVaporCone(rootPart, 0.5)
		end

	elseif data.phase == "Dash" then
		if data.style == 5 then
			local rawT = math.min(1, (now - data.dashStartTime) / data.dashDuration)
			local t = fluidEaseOutIn(rawT, Config.BezierSpeedFloor)

			local currentPos = ((1 - t)^2 * data.P0) + (2 * (1 - t) * t * data.P1) + (t^2 * data.P2)

			-- MId-Dash failsafe raycast
			local rayParams = RaycastParams.new()
			rayParams.FilterType = Enum.RaycastFilterType.Exclude
			rayParams.FilterDescendantsInstances = {fighter, target}
			local rayDir = currentPos - rootPart.Position
			local rayDist = rayDir.Magnitude

			if rayDist > 0.01 then
				local hit = workspace:Raycast(rootPart.Position, rayDir.Unit * rayDist, rayParams)
				if hit then
					rootPart.CFrame = CFrame.new(hit.Position)
					switchPhase(data, "Impact")
					return ProjectileJumpState
				end
			end

			-- Dynamic LinearVelocity steering to eliminate jitter
			local lookAheadTime = 0.1
			local futureRawT = math.min(1, rawT + (lookAheadTime / data.dashDuration))
			local futureT = fluidEaseOutIn(futureRawT, Config.BezierSpeedFloor)
			local futurePos = ((1 - futureT)^2 * data.P0) + (2 * (1 - futureT) * futureT * data.P1) + (futureT^2 * data.P2)

			local targetVelocity = (futurePos - rootPart.Position) / lookAheadTime
			lv.MaxAxesForce = Vector3.new(math.huge, math.huge, math.huge)
			lv.VectorVelocity = targetVelocity

			local flatVel = Vector3.new(targetVelocity.X, 0, targetVelocity.Z)
			if flatVel.Magnitude > 0.5 then
				ao.CFrame = CFrame.lookAt(rootPart.Position, rootPart.Position + flatVel)
			end

			if rawT >= 1 or distToTarget < 15 or (rawT > 0.4 and rootPart.Position.Y <= targetPos.Y + 2) then
				switchPhase(data, "Impact")
			end

		else
			lv.MaxAxesForce = Vector3.new(math.huge, math.huge, math.huge)
			local dashSpeed = (data.style == 3 or data.style == 6) and (Config.SlamSpeed * Config.SlamSpeedMultiplier) or Config.SlamSpeed
			local aimPoint, approachDir, groundY = calculateCombatAimPoint(rootPart, targetPosPart, dashSpeed, humanoid)
			local offset = aimPoint - rootPart.Position
			local dir = offset.Magnitude > 0.001 and offset.Unit or rootPart.CFrame.LookVector
			lv.VectorVelocity = dir * dashSpeed
			ao.CFrame = CFrame.lookAt(rootPart.Position, Vector3.new(aimPoint.X, rootPart.Position.Y, aimPoint.Z))

			local isFalling = rootPart.AssemblyLinearVelocity.Y <= 0
			local isNearGround = rootPart.Position.Y <= groundY + 2.5
			local reachedAim = offset.Magnitude < 10
			if reachedAim or (timeInPhase > 0.12 and isFalling and isNearGround) then
				switchPhase(data, "Impact")
			end
		end

	elseif data.phase == "Impact" then

		-- STOP all mover forces immediately
		cleanupMovers(rootPart)
		rootPart.AssemblyLinearVelocity = Vector3.zero
		rootPart.AssemblyAngularVelocity = Vector3.zero

		-- Detect MidAir Clash
		local targetState = target:GetAttribute("CurrentState")
		if (targetState == "ProjectileJump" or targetState == "MidAirClash" or targetState == "Airborne" or (targetPosPart and targetPosPart.Position.Y > 20)) and distToTarget <= 35 then
			return require(script.Parent:WaitForChild("MidAirClashState"))
		end

		-- 1. Firmly plant feet on the arena floor (never floating, never skull stacking)
		local rayParams = RaycastParams.new()
		rayParams.FilterType = Enum.RaycastFilterType.Exclude
		rayParams.FilterDescendantsInstances = {fighter, target}
		local floorRay = workspace:Raycast(rootPart.Position + Vector3.new(0, 5, 0), Vector3.new(0, -25, 0), rayParams)
		local finalY = rootPart.Position.Y
		if floorRay then
			finalY = floorRay.Position.Y + (humanoid.HipHeight or 2.0) + (rootPart.Size.Y / 2)
		elseif targetPosPart then
			finalY = targetPosPart.Position.Y
		end

		-- 2. Spatial de-penetration: ensure clean 4.5 studs combat separation
		local targetHRP = target:FindFirstChild("HumanoidRootPart")
		local jumperPos = Vector3.new(rootPart.Position.X, finalY, rootPart.Position.Z)
		if targetHRP then
			local flatDiff = Vector3.new(jumperPos.X - targetHRP.Position.X, 0, jumperPos.Z - targetHRP.Position.Z)
			local flatDist = flatDiff.Magnitude
			
			if flatDist < 4.0 then
				-- Jumper is too close / overlapping: resolve along approach angle to 4.5 studs
				local pushDir = flatDist > 0.01 and flatDiff.Unit or -targetHRP.CFrame.LookVector
				jumperPos = Vector3.new(targetHRP.Position.X + pushDir.X * 4.5, finalY, targetHRP.Position.Z + pushDir.Z * 4.5)
				-- Apply light arrival wind-pressure micro-push on target (4 studs)
				KnockbackModule.applyMicroKnockback(target, -pushDir, 4.0)
			end
			
			-- 3. Eye-to-eye alignment: both face each other horizontally
			rootPart.CFrame = CFrame.lookAt(jumperPos, Vector3.new(targetHRP.Position.X, finalY, targetHRP.Position.Z))
			targetHRP.CFrame = CFrame.lookAt(targetHRP.Position, Vector3.new(jumperPos.X, targetHRP.Position.Y, jumperPos.Z))
		else
			rootPart.CFrame = CFrame.new(jumperPos)
		end

		-- 4. Clean foot-strike audio and subtle ground dust (no generic explosions)
		AudioModule.playFallOnGround(rootPart.Position)
		AudioModule.playSlam(rootPart.Position)
		VfxModule.createDust(rootPart, 8)
		local elem = fighter:GetAttribute("Element") or "Fire"
		VfxModule.createShockwave(jumperPos, 22, 0.40, elem)
		VfxModule.shakeScreen(rootPart.Position, 400, 8)

		-- 5. Slam Shockwave & Target Stumble (Phase 5.2)
		local CombatConfig = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("CombatConfig"))
		local shockRadius = CombatConfig.SlamShockwaveRadius or CombatConfig.SlamImpactRadius or 14
		local stumbleForce = CombatConfig.SlamStumbleForce or 90
		local stumbleDuration = CombatConfig.SlamStumbleDuration or 0.35
		for _, other in ipairs(CollectionService:GetTagged("Quin")) do
			if other ~= fighter and other.Parent then
				local oHRP = other:FindFirstChild("HumanoidRootPart")
				local oHum = other:FindFirstChildOfClass("Humanoid")
				if oHRP and oHum and oHum.Health > 0 then
					local oDist = (oHRP.Position - jumperPos).Magnitude
					if oDist <= shockRadius then
						local awayDir = oHRP.Position - jumperPos
						if awayDir.Magnitude < 0.01 then
							awayDir = -rootPart.CFrame.LookVector
						else
							awayDir = awayDir.Unit
						end
						local falloff = 1 - (oDist / shockRadius)
						KnockbackModule.applyGroundKnockback(other, awayDir, stumbleForce * (0.5 + 0.5 * falloff), stumbleDuration)
						other:SetAttribute("ImpactTime", workspace:GetServerTimeNow())
						other:SetAttribute("ImpactDir", awayDir)
						other:SetAttribute("ImpactMag", math.clamp(0.4 + 0.6 * falloff, 0.3, 1.0))
						other:SetAttribute("ImpactType", "SLAM")
						local oState = other:GetAttribute("CurrentState")
						if oState ~= "Knockback" and oState ~= "Death" and oState ~= "Airborne" then
							other:SetAttribute("ForceState", "Knockback")
							other:SetAttribute("KnockbackType", "ground")
						end
					end
				end
			end
		end

		-- 6. Route into dedicated slam recovery pipeline (Phase 5.1)
		stopAnim(data.animTrack)
		AnimationModule.stop(humanoid, AnimationIds.Dash, 0.05)
		fighter:SetAttribute("KnockbackType", "slam_landing")

		return require(script.Parent:WaitForChild("RecoveryState"))
	end

	return ProjectileJumpState
end

return ProjectileJumpState
