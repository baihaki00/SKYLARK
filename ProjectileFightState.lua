--// ProjectileFightState.lua
-- Dedicated Cinematic State Machine for 1-Quin and 2-Quin Scenarios
-- ISOLATED: Only transitions to InterceptionState and TestEndState.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AnimationModule = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("AnimationModule"))
local AudioModule = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("AudioModule"))
local VfxModule = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("VfxModule"))
local TargetingModule = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("TargetingModule"))
local AnimationIds = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("AnimationIds"))

local ProjectileFightState = { name = "ProjectileFight" }
local projData = {}
local PROJECTILE_FIGHT_DEBUG = true

-- ============================================
-- TUNING KNOBS (adjust these to taste)
-- ============================================
local Config = {
    ARC_SPEED_XZ    = 100,   -- XZ speed during initial Launch burst
    HOMING_SPEED    = 200,   -- 3D homing cruise speed (studs/sec)
    HOMING_ACCEL    = 300,   -- 3D homing speed when within 100 studs of target
    DASH_SPEED      = 750,   -- Final approach dash speed (studs/sec)
    CLASH_RADIUS    = 25,    -- How close before X triggers (studs)
    CLASH_ALT       = 100,   -- Minimum altitude above startY for X to trigger
    LAUNCH_DURATION = 0.3,   -- How long the parabolic burst lasts before homing CAN kick in
    HOMING_TIMEOUT  = 6,     -- Max seconds in Homing before giving up
    DASH_TIMEOUT    = 2,     -- Max seconds in Dash before giving up
}

local function cleanup(fighter, rootPart)
	if rootPart:FindFirstChild("Proj_AntiGrav") then rootPart.Proj_AntiGrav:Destroy() end
	if rootPart:FindFirstChild("Proj_Gyro") then rootPart.Proj_Gyro:Destroy() end
	if rootPart:FindFirstChild("Proj_Mover") then rootPart.Proj_Mover:Destroy() end
	if rootPart:FindFirstChild("Proj_Align") then rootPart.Proj_Align:Destroy() end
	if rootPart:FindFirstChild("Proj_LinearVelocity") then rootPart.Proj_LinearVelocity:Destroy() end
	if rootPart:FindFirstChild("Proj_Att") then rootPart.Proj_Att:Destroy() end
end

local function switchPhase(data, newPhase)
	data.phase = newPhase
	data.phaseTime = tick()
end

function ProjectileFightState.enter(fighter, humanoid, rootPart)
	humanoid.PlatformStand = true
	cleanup(fighter, rootPart)

	local target, _ = TargetingModule.getNearest(rootPart, 1000)
	local sequence = fighter:GetAttribute("ProjSequence") or "Jump"

	if PROJECTILE_FIGHT_DEBUG then
		print("[ProjectileFight] " .. fighter.Name .. " entered. Seq: " .. sequence)
	end

	projData[fighter] = {
		startTime = tick(),
		target = target,
		sequence = sequence,
		phase = "Launch",
		phaseTime = tick(),
		startY = rootPart.Position.Y,
		lastDebugTime = 0
	}

	local att = Instance.new("Attachment")
	att.Name = "Proj_Att"
	att.Parent = rootPart

	local ao = Instance.new("AlignOrientation")
	ao.Name = "Proj_Align"
	ao.Mode = Enum.OrientationAlignmentMode.OneAttachment
	ao.Attachment0 = att
	ao.MaxTorque = math.huge
	ao.Responsiveness = 40
	ao.Parent = rootPart

	local lv = Instance.new("LinearVelocity")
	lv.Name = "Proj_LinearVelocity"
	lv.Attachment0 = att
	lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	lv.MaxAxesForce = Vector3.new(math.huge, math.huge, math.huge)
	lv.VectorVelocity = Vector3.zero
	lv.Parent = rootPart

	if sequence == "Jump" or sequence == "JumpDash" then
		AudioModule.playJumpUp(rootPart.Position)
		VfxModule.createLaunchShockwave(rootPart)
		AnimationModule.play(humanoid, AnimationIds.Jump, Enum.AnimationPriority.Action, false, 1.2)
		
		-- Setup Launch burst (parabolic)
		if target and target.Parent and target:FindFirstChild("HumanoidRootPart") then
			local targetHRP = target:FindFirstChild("HumanoidRootPart")
			local diff = targetHRP.Position - rootPart.Position
			local dirXZ = Vector3.new(diff.X, 0, diff.Z)
			local distHorizontal = dirXZ.Magnitude
			
			local timeToTarget = math.max(distHorizontal / Config.ARC_SPEED_XZ, 0.1)
			local gravity = workspace.Gravity
			local requiredY = (targetHRP.Position.Y - rootPart.Position.Y + 0.5 * gravity * timeToTarget^2) / timeToTarget
			
			if PROJECTILE_FIGHT_DEBUG then
				print(string.format("[ProjectileFight] %s Launch Phase! Vy=%.1f", fighter.Name, requiredY))
			end
			
			lv.MaxAxesForce = Vector3.new(math.huge, 0, math.huge)
			if distHorizontal > 0.1 then
				lv.VectorVelocity = dirXZ.Unit * Config.ARC_SPEED_XZ
			end
			rootPart.AssemblyLinearVelocity = Vector3.new(0, requiredY, 0)
			
			projData[fighter].dashExactTime = math.min(timeToTarget - 0.2, 1.5 + math.random() * 1.0)
		end
		
	elseif sequence == "Dash" then
		AudioModule.playSonicBoom(rootPart.Position)
		AnimationModule.play(humanoid, AnimationIds.Dash, Enum.AnimationPriority.Action, false, 1.5)
		switchPhase(projData[fighter], "Dashing")
	end
end

function ProjectileFightState.exit(fighter, humanoid, rootPart)
	humanoid.PlatformStand = false
	cleanup(fighter, rootPart)
	projData[fighter] = nil
	fighter:SetAttribute("ProjSequence", nil)
end

function ProjectileFightState.update(fighter, humanoid, rootPart, DEBUG)
	local data = projData[fighter]
	if not data then return require(script.Parent:WaitForChild("AirborneState")) end

	local target = data.target
	if not target or not target.Parent then return require(script.Parent:WaitForChild("AirborneState")) end

	local targetHRP = target:FindFirstChild("HumanoidRootPart")
	if not targetHRP then return require(script.Parent:WaitForChild("AirborneState")) end

	local now = tick()
	local timeInPhase = now - data.phaseTime
	local diff = targetHRP.Position - rootPart.Position
	local dist = diff.Magnitude
	local altitudeEarned = math.abs(rootPart.Position.Y - data.startY)
	local altReal = rootPart.Position.Y - data.startY

	local ao = rootPart:FindFirstChild("Proj_Align")
	local lv = rootPart:FindFirstChild("Proj_LinearVelocity")

	-- Periodic distance debug (every 0.5s)
	if PROJECTILE_FIGHT_DEBUG and (now - data.lastDebugTime) >= 0.5 then
		data.lastDebugTime = now
		print(string.format("[ProjectileFight] %s | Phase: %s | Dist: %.1f | Alt: %.1f | Y: %.1f",
			fighter.Name, data.phase, dist, altitudeEarned, rootPart.Position.Y))
	end

	-- LookAt: Follow velocity during arc/homing, face target otherwise
	if ao then
		local vel = rootPart.AssemblyLinearVelocity
		if vel.Magnitude > 5 then
			ao.CFrame = CFrame.lookAt(rootPart.Position, rootPart.Position + vel.Unit)
		elseif dist > 1 then
			ao.CFrame = CFrame.lookAt(rootPart.Position, targetHRP.Position)
		end
	end

	-- ==========================================
	-- COLLISION DETECTION (The X)
	-- ==========================================
	local targetState = target:GetAttribute("CurrentState")
	local bothAirborne = (targetState == "ProjectileFight" or targetState == "Interception")
	
	if bothAirborne and dist < Config.CLASH_RADIUS and altReal >= Config.CLASH_ALT then
		if PROJECTILE_FIGHT_DEBUG then
			print(string.format("[ProjectileFight] CLASH! %s dist=%.1f alt=%.1f", fighter.Name, dist, altReal))
		end
		return require(script.Parent:WaitForChild("InterceptionState"))
	end

	-- ==========================================
	-- FLIGHT PHASES
	-- ==========================================
	if data.phase == "Launch" then
		-- Wait for the cinematic upward burst to finish (0.3s)
		if timeInPhase >= Config.LAUNCH_DURATION then
			-- ONLY switch to 3D Homing if the target is also airborne
			if bothAirborne then
				if PROJECTILE_FIGHT_DEBUG then print("[ProjectileFight] " .. fighter.Name .. " target airborne! → Homing Phase") end
				switchPhase(data, "Homing")
			end
		end
		
		-- JumpDash transition during parabola (if target never jumps)
		if data.sequence == "JumpDash" and timeInPhase >= (data.dashExactTime or 2) then
			if PROJECTILE_FIGHT_DEBUG then print("[ProjectileFight] " .. fighter.Name .. " → Dash Phase!") end
			switchPhase(data, "Dashing")
			AnimationModule.play(humanoid, AnimationIds.Dash, Enum.AnimationPriority.Action, false, 1.5)
			AudioModule.playMidairSwoosh(rootPart.Position)
		end

		-- Ground impact (miss)
		if rootPart.Position.Y <= data.startY + 5 and rootPart.AssemblyLinearVelocity.Y < 0 and timeInPhase > 0.5 then
			if PROJECTILE_FIGHT_DEBUG then print("[ProjectileFight] " .. fighter.Name .. " SLAMMED GROUND (miss)!") end
			VfxModule.createLaunchShockwave(rootPart)
			AudioModule.playSlam(rootPart.Position)
			return require(script.Parent:WaitForChild("AirborneState"))
		end
		
	elseif data.phase == "Homing" then
		if lv then
			-- 3D HOMING: LinearVelocity steers toward the target in ALL 3 axes.
			local homingSpeed = Config.HOMING_SPEED
			if dist < 100 then
				homingSpeed = Config.HOMING_ACCEL
			end

			if dist > 0.5 then
				lv.MaxAxesForce = Vector3.new(math.huge, math.huge, math.huge)
				lv.VectorVelocity = diff.Unit * homingSpeed
			end
		end

		-- JumpDash transition
		if data.sequence == "JumpDash" and timeInPhase >= (data.dashExactTime or 2) then
			if PROJECTILE_FIGHT_DEBUG then print("[ProjectileFight] " .. fighter.Name .. " → Dash Phase!") end
			switchPhase(data, "Dashing")
			AnimationModule.play(humanoid, AnimationIds.Dash, Enum.AnimationPriority.Action, false, 1.5)
			AudioModule.playMidairSwoosh(rootPart.Position)
		end

		-- Ground impact
		if rootPart.Position.Y <= data.startY + 5 and rootPart.AssemblyLinearVelocity.Y < 0 then
			if PROJECTILE_FIGHT_DEBUG then print("[ProjectileFight] " .. fighter.Name .. " SLAMMED GROUND (miss)!") end
			VfxModule.createLaunchShockwave(rootPart)
			AudioModule.playSlam(rootPart.Position)
			return require(script.Parent:WaitForChild("AirborneState"))
		end

		-- Timeout
		if timeInPhase > Config.HOMING_TIMEOUT then
			if PROJECTILE_FIGHT_DEBUG then print("[ProjectileFight] " .. fighter.Name .. " HOMING TIMEOUT!") end
			return require(script.Parent:WaitForChild("AirborneState"))
		end

	elseif data.phase == "Dashing" then
		if lv then
			lv.MaxAxesForce = Vector3.new(math.huge, math.huge, math.huge)
			if dist > 0.5 then
				lv.VectorVelocity = diff.Unit * Config.DASH_SPEED
			else
				lv.VectorVelocity = rootPart.CFrame.LookVector * Config.DASH_SPEED
			end
			rootPart.AssemblyLinearVelocity = lv.VectorVelocity
		end

		-- Ground impact
		if rootPart.Position.Y <= data.startY + 5 and rootPart.AssemblyLinearVelocity.Y < 0 then
			if PROJECTILE_FIGHT_DEBUG then print("[ProjectileFight] " .. fighter.Name .. " DASH SLAMMED GROUND!") end
			VfxModule.createLaunchShockwave(rootPart)
			AudioModule.playSlam(rootPart.Position)
			return require(script.Parent:WaitForChild("AirborneState"))
		end

		-- Timeout
		if timeInPhase > Config.DASH_TIMEOUT then
			if PROJECTILE_FIGHT_DEBUG then print("[ProjectileFight] " .. fighter.Name .. " DASH TIMEOUT!") end
			return require(script.Parent:WaitForChild("AirborneState"))
		end
	end

	return ProjectileFightState
end

return ProjectileFightState
