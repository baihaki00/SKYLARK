--// SmoothCamera.client.lua
-- Default Freefly Spectator Camera + Smooth Quin Focus Support
-- Starts by default elevated above the arena for optimal tactical battlefield observation

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local CollectionService = game:GetService("CollectionService")
local Camera = workspace.CurrentCamera

local player = Players.LocalPlayer

-- === SETTINGS (HIGH SPEED TACTICAL FREECAM) ===
local baseFlySpeed = 300 -- Boosted ~5x (was 65) for fast agile arena freefly
local sprintMultiplier = 3.5 -- Holding Shift reaches 1,050 studs/s hyper-fly
local flySensitivity = 0.32
local minAltitude = 5.0
local maxAltitude = 1200.0

-- Orbit mode settings (used when spectating a Quin)
local orbitSmoothness = 10
local posSmoothness = 14
local zoomSpeed = 3.0
local minZoom, maxZoom = 4.0, 45.0

-- === 2ND-ORDER SUSPENSION & GYRO DYNAMICS ===
local suspensionEnabled = false       -- DISABLED for rock-solid GTA / Watch Dogs 3rd-person camera
local suspStiffness = 175.0        -- Spring stiffness k (rad/s)^2 for vertical bob & landing shock
local suspDamping = 19.5          -- Damping coefficient d for smooth, cushioned bounce
local landingImpulseScale = 0.045  -- Converts landing downward velocity to vertical shock compression
local strideBobScale = 0.0         -- Pelvic/hips bone vertical animation tracking weight

-- === LOCOMOTION STRIDE SUSPENSION (WALK/RUN TINY BOUNCES) ===
local walkBounceAmp = 0.0          -- Vertical bounce amplitude when walking (studs)
local runBounceAmp = 0.0           -- Vertical bounce amplitude when sprinting (studs)
local walkPitchBob = 0.0           -- Camera pitch nod when walking (deg)
local runPitchBob = 0.0            -- Camera pitch nod when sprinting (deg)
local walkSwayAmp = 0.0            -- Lateral hip sway when walking (studs)
local runSwayAmp = 0.0             -- Lateral hip sway when sprinting (studs)
local stridePhase = 0              -- Continuous stride phase accumulator

local gyroEnabled = false          -- DISABLED: No Dutch tilt / airplane banking roll
local gyroStiffness = 160.0       -- Roll spring stiffness
local gyroDamping = 21.0          -- Roll spring damping (critically damped for zero roll overshoot)
local maxGyroRollDeg = 0.0        -- Max Dutch tilt / roll banking angle during high-speed carving turns
local gyroBankWeight = 0.0        -- Weight of Quin's BankRoll attribute in camera roll

local pitchLagStiffness = 130.0   -- Inertial pitch lag spring stiffness
local pitchLagDamping = 17.0      -- Inertial pitch lag spring damping
local maxPitchLagDeg = 0.0        -- Max pitch lag during rapid acceleration / braking

local lateralSwayStiffness = 140.0 -- Centripetal sway spring stiffness
local lateralSwayDamping = 18.0    -- Centripetal sway spring damping
local maxLateralSwayStuds = 0.0   -- Max lateral displacement from centripetal G-force

local fovSpeedMin = 15.0          -- Speed threshold where dynamic FOV starts expanding
local fovSpeedMax = 55.0          -- Speed threshold where max FOV is reached
local fovExpansionMax = 6.5       -- Max FOV expansion in degrees (e.g. 70 -> 76.5)
local baseFOV = 70.0              -- Resting FOV

-- Suspension & Gyro physical states
local suspDispY = 0
local suspVelY = 0

local gyroRoll = 0
local gyroRollVel = 0

local inertPitch = 0
local inertPitchVel = 0

local swayDispX = 0
local swayVelX = 0

local lastTrackedHRP = nil
local lastVerticalVel = 0
local lastHorizSpeed = 0
local currentCamFov = baseFOV

-- Bone caching
local currentQuinModel = nil
local cachedHipsBone = nil
local restHipsRelY = nil

local function getHipsBone(quinModel)
	if quinModel ~= currentQuinModel then
		currentQuinModel = quinModel
		cachedHipsBone = quinModel and (
			quinModel:FindFirstChild("mixamorig:Hips", true)
			or quinModel:FindFirstChild("Hips", true)
			or quinModel:FindFirstChild("UpperTorso", true)
			or quinModel:FindFirstChild("Torso", true)
		)
		restHipsRelY = nil
	end
	return cachedHipsBone
end

-- === INITIAL STATE: FREEFLY ABOVE ARENA ===
local function findSpawnLocation()
	local arenaOne = workspace:FindFirstChild("argoniaonion") and workspace.argoniaonion:FindFirstChild("ArenaOne")
	if arenaOne and arenaOne:FindFirstChild("SpawnLocation") then
		return arenaOne.SpawnLocation
	end
	return workspace:FindFirstChild("SpawnLocation", true) or workspace:FindFirstChildOfClass("SpawnLocation")
end

local cameraMode = "FREEFLY" -- "FREEFLY" or "QUIN_SPECTATE"
shared.SpectatorState = { Mode = "FREEFLY" }
local playerSpawnObj = findSpawnLocation()
local cameraPos = playerSpawnObj and (playerSpawnObj.Position + Vector3.new(0, 15, 30)) or Vector3.new(161, 159, -722.5)
local yaw = 0
local pitch = playerSpawnObj and -18.0 or -25.0 -- Angled toward the course

-- Orbit internals
local smoothYaw, smoothPitch = yaw, pitch
local targetDistance = 18
local currentDistance = targetDistance
local smoothedTargetPos = nil
local lastControlledQuin = nil

local isLeftMouseDown = false
local isRightMouseDown = false
local isToggleLocked = false

-- Ensure dummy spectator character is non-interfering (NEVER isolate a Quin)
local function isolatePlayerCharacter(char)
	if not char then return end
	if char:GetAttribute("QuinType") or char:GetAttribute("IsPlayerControlled") or CollectionService:HasTag(char, "Quin") then
		return -- Never isolate active Quin characters
	end
	local root = char:WaitForChild("HumanoidRootPart", 5)
	local hum = char:FindFirstChildOfClass("Humanoid")
	local sl = findSpawnLocation()
	local isoCF = sl and (sl.CFrame + Vector3.new(0, 15, 0)) or CFrame.new(161, 159, -752.5)
	if root then
		root.Anchored = true
		root.CFrame = isoCF
	end
	for _, part in ipairs(char:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CanCollide = false
			part.Transparency = 1
			part.CastShadow = false
		end
	end
	if hum then
		hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	end
end

if player.Character then
	isolatePlayerCharacter(player.Character)
end
player.CharacterAdded:Connect(isolatePlayerCharacter)

-- === MOUSE CONTROLS ===
local function updateMouseBehavior()
	if isLeftMouseDown or isRightMouseDown or isToggleLocked then
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
		UserInputService.MouseIconEnabled = false
	else
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		UserInputService.MouseIconEnabled = true
	end
end

local function lockMouse()
	isToggleLocked = true
	updateMouseBehavior()
end

local function unlockMouse()
	isToggleLocked = false
	isLeftMouseDown = false
	isRightMouseDown = false
	updateMouseBehavior()
end

-- Helper to verify an object and all its ancestors are truly visible
local function isTrulyVisible(obj, playerGui)
	local cur = obj
	while cur and cur ~= playerGui and not cur:IsA("ScreenGui") do
		if not cur.Visible then return false end
		cur = cur.Parent
	end
	return true
end

-- Helper to check if a mouse position is over an interactive GUI element
local function isClickOnGui(mousePos)
	if not mousePos then
		mousePos = UserInputService:GetMouseLocation()
	end
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	if not playerGui then return false end

	local guis = playerGui:GetGuiObjectsAtPosition(mousePos.X, mousePos.Y)
	for _, obj in ipairs(guis) do
		if isTrulyVisible(obj, playerGui) then
			-- Interactive controls
			if obj:IsA("GuiButton") or obj:IsA("TextBox") or (obj:IsA("ScrollingFrame") and obj.Active) then
				return true
			end
			-- Quin Manager Menu window (AnimationLabUI)
			if obj:FindFirstAncestor("AnimationLabUI") or obj.Name == "AnimationLabUI" then
				return true
			end
			-- Spectator HUD (QuinDebugGui)
			if obj:FindFirstAncestor("QuinDebugGui") or obj.Name == "QuinDebugGui" then
				return true
			end
			-- Explicitly active GUI frames
			if obj.Active then
				return true
			end
		end
	end
	return false
end

-- Keep cursor and look state synced when window focus changes or Studio resets mouse
UserInputService.WindowFocusReleased:Connect(function()
	unlockMouse()
end)

UserInputService:GetPropertyChangedSignal("MouseBehavior"):Connect(function()
	if UserInputService.MouseBehavior == Enum.MouseBehavior.Default then
		if not isLeftMouseDown and not isRightMouseDown then
			isToggleLocked = false
		end
	end
end)

-- Check active spectated Quin
local function getActiveSpectatedQuin()
	local playerQuin = shared.PlayerControlledQuin or _G.PlayerControlledQuin
	if playerQuin and playerQuin.Parent and playerQuin:FindFirstChild("HumanoidRootPart") then
		local hum = playerQuin:FindFirstChildOfClass("Humanoid")
		local hrp = playerQuin:FindFirstChild("HumanoidRootPart")
		if hum and hum.Health > 0 and hrp then
			return hrp, playerQuin
		end
	end

	local specQuin = shared.SpectatedQuin or _G.SpectatedQuin
	if not specQuin or not specQuin.Parent then
		local specName = workspace:GetAttribute("SpectatedQuin")
		if specName and specName ~= "" then
			local qServer = workspace:FindFirstChild("QuinServer")
			specQuin = qServer and qServer:FindFirstChild(specName)
		end
	end
	if specQuin and specQuin.Parent and specQuin.Parent.Name == "QuinServer" and specQuin.Name ~= "QuinTest" and specQuin.Name ~= "QuinTypeA" then
		local hum = specQuin:FindFirstChildOfClass("Humanoid")
		local hrp = specQuin:FindFirstChild("HumanoidRootPart")
		if hum and hum.Health > 0 and hrp then
			return hrp, specQuin
		end
	end
	return nil, nil
end

-- === INPUT HANDLING ===
UserInputService.InputBegan:Connect(function(input, gp)
	if UserInputService:GetFocusedTextBox() then return end

	-- Mouse Controls: Left Click or Right Click to look around
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		if gp or isClickOnGui(input.Position) then
			-- Clicked on GUI (e.g. Spectator HUD button/card)
			return
		end
		isLeftMouseDown = true
		updateMouseBehavior()

	elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
		if gp or isClickOnGui(input.Position) then return end
		isRightMouseDown = true
		updateMouseBehavior()

	-- Toggle hands-free look lock with L
	elseif input.KeyCode == Enum.KeyCode.L then
		if isToggleLocked then
			unlockMouse()
		else
			lockMouse()
		end

	-- Mouse Unlock keys
	elseif input.KeyCode == Enum.KeyCode.Tab or input.KeyCode == Enum.KeyCode.Escape then
		unlockMouse()

	elseif input.KeyCode == Enum.KeyCode.R then
		-- Return to Freefly overview
		cameraMode = "FREEFLY"
		shared.SpectatedQuin = nil
		_G.SpectatedQuin = nil
		workspace:SetAttribute("SpectatedQuin", "")
		local ps = findSpawnLocation()
		cameraPos = ps and (ps.Position + Vector3.new(0, 15, 30)) or Vector3.new(161, 159, -722.5)
		pitch = ps and -18.0 or -25.0
		yaw = 0
		print("[SmoothCamera] Returned to default Freefly Spectator overview.")

	elseif input.KeyCode == Enum.KeyCode.F then
		-- Toggle Freefly mode
		if cameraMode == "QUIN_SPECTATE" then
			cameraMode = "FREEFLY"
			cameraPos = Camera.CFrame.Position
			shared.SpectatedQuin = nil
			workspace:SetAttribute("SpectatedQuin", "")
			print("[SmoothCamera] Released Quin focus to Freefly.")
		else
			local hrp = getActiveSpectatedQuin()
			if hrp then
				cameraMode = "QUIN_SPECTATE"
				print("[SmoothCamera] Focused on spectated Quin.")
			end
		end
	end
end)

UserInputService.InputEnded:Connect(function(input, gp)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		isLeftMouseDown = false
		updateMouseBehavior()
	elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
		isRightMouseDown = false
		updateMouseBehavior()
	end
end)

-- Scroll wheel
UserInputService.InputChanged:Connect(function(input, gp)
	if gp then return end
	if input.UserInputType == Enum.UserInputType.MouseWheel then
		if cameraMode == "QUIN_SPECTATE" then
			targetDistance = math.clamp(targetDistance - input.Position.Z * zoomSpeed, minZoom, maxZoom)
		else
			-- In freefly, wheel nudges camera forward/backward along view
			local forward = Camera.CFrame.LookVector
			cameraPos = cameraPos + forward * (input.Position.Z * 50)
			cameraPos = Vector3.new(cameraPos.X, math.clamp(cameraPos.Y, minAltitude, maxAltitude), cameraPos.Z)
		end
	end
end)

-- === RENDER STEP LOOP ===
RunService:BindToRenderStep("SpectatorFreeflyCamera", Enum.RenderPriority.Camera.Value + 1, function(dt)
	local isOverride = (workspace:GetAttribute("CameraOverrideActive") == true) or (shared.CameraOverrideCFrame ~= nil)
	if isOverride then
		Camera.CameraType = Enum.CameraType.Scriptable
		if shared.CameraOverrideCFrame then
			Camera.CFrame = shared.CameraOverrideCFrame
		else
			local posX = workspace:GetAttribute("CamPosX") or 0
			local posY = workspace:GetAttribute("CamPosY") or 8.0
			local posZ = workspace:GetAttribute("CamPosZ") or -20.0
			local lookX = workspace:GetAttribute("CamLookX") or 0
			local lookY = workspace:GetAttribute("CamLookY") or 6.0
			local lookZ = workspace:GetAttribute("CamLookZ") or -38.0
			Camera.CFrame = CFrame.lookAt(Vector3.new(posX, posY, posZ), Vector3.new(lookX, lookY, lookZ))
		end
		return
	end

	Camera.CameraType = Enum.CameraType.Scriptable

	-- Check if a Quin is selected from the HUD or player possessed
	local targetHRP, quinModel = getActiveSpectatedQuin()
	if targetHRP and cameraMode ~= "QUIN_SPECTATE" then
		cameraMode = "QUIN_SPECTATE"
		shared.SpectatorState.Mode = cameraMode
		if shared.PlayerControlledQuin and lastControlledQuin ~= quinModel then
			lastControlledQuin = quinModel
			targetDistance = 14
			pitch = -12
			local look = targetHRP.CFrame.LookVector
			yaw = math.deg(math.atan2(-look.X, -look.Z))
			smoothYaw = yaw
			smoothPitch = pitch
		end
	elseif not targetHRP and cameraMode == "QUIN_SPECTATE" then
		cameraMode = "FREEFLY"
		shared.SpectatorState.Mode = cameraMode
		cameraPos = Camera.CFrame.Position
	end

	-- Mouse rotation (Continuous, unconstrained 360-degree rotation)
	local isHoldingLook = isLeftMouseDown or isRightMouseDown or isToggleLocked
	if isHoldingLook then
		local delta = UserInputService:GetMouseDelta()
		yaw = yaw - delta.X * flySensitivity
		pitch = math.clamp(pitch - delta.Y * flySensitivity, -85, 85)
	elseif cameraMode == "QUIN_SPECTATE" and targetHRP then
		-- GTA V / Watch Dogs 2 Dynamic Auto-Follow Yaw:
		-- When actively moving and not manually orbiting with mouse, gently track behind character travel direction
		local curVel = targetHRP.AssemblyLinearVelocity
		local flatVel = Vector3.new(curVel.X, 0, curVel.Z)
		if flatVel.Magnitude > 6.0 then
			local moveHeading = math.deg(math.atan2(-flatVel.X, -flatVel.Z))
			local diff = (moveHeading - yaw) % 360
			if diff > 180 then diff = diff - 360 end
			yaw = yaw + diff * (1 - math.exp(-3.5 * dt))
		end
	end

	if cameraMode == "FREEFLY" then
		-- === FREEFLY NAVIGATION ===
		-- Restore FOV and relax dynamic suspension states in freecam
		if math.abs(currentCamFov - baseFOV) > 0.05 then
			currentCamFov = currentCamFov + (baseFOV - currentCamFov) * (1 - math.exp(-8.0 * dt))
			Camera.FieldOfView = currentCamFov
		end
		suspDispY = 0
		suspVelY = 0
		stridePhase = 0
		gyroRoll = 0
		gyroRollVel = 0
		inertPitch = 0
		inertPitchVel = 0
		swayDispX = 0
		swayVelX = 0
		lastTrackedHRP = nil

		local speed = baseFlySpeed
		if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) or UserInputService:IsKeyDown(Enum.KeyCode.RightShift) then
			speed = speed * sprintMultiplier
		end

		local rotCF = CFrame.Angles(0, math.rad(yaw), 0) * CFrame.Angles(math.rad(pitch), 0, 0)
		local moveDir = Vector3.zero

		-- Keyboard Inputs
		if UserInputService:IsKeyDown(Enum.KeyCode.W) then
			moveDir += rotCF.LookVector
		end
		if UserInputService:IsKeyDown(Enum.KeyCode.S) then
			moveDir -= rotCF.LookVector
		end
		if UserInputService:IsKeyDown(Enum.KeyCode.A) then
			moveDir -= rotCF.RightVector
		end
		if UserInputService:IsKeyDown(Enum.KeyCode.D) then
			moveDir += rotCF.RightVector
		end
		if UserInputService:IsKeyDown(Enum.KeyCode.Space) or UserInputService:IsKeyDown(Enum.KeyCode.E) then
			moveDir += Vector3.new(0, 1.2, 0)
		end
		if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) or UserInputService:IsKeyDown(Enum.KeyCode.C) or UserInputService:IsKeyDown(Enum.KeyCode.Q) then
			moveDir -= Vector3.new(0, 1.2, 0)
		end

		if moveDir.Magnitude > 0.001 then
			cameraPos += moveDir.Unit * (speed * dt)
		end

		-- Altitude Clamp
		cameraPos = Vector3.new(cameraPos.X, math.clamp(cameraPos.Y, minAltitude, maxAltitude), cameraPos.Z)

		Camera.CFrame = CFrame.new(cameraPos) * rotCF

	else
		-- === QUIN SPECTATE (ORBIT WITH SUSPENSION & DYNAMIC GYRO) ===
		local rotAlpha = 1 - math.exp(-orbitSmoothness * dt)
		local zoomAlpha = 1 - math.exp(-10 * dt)
		local posAlpha = 1 - math.exp(-posSmoothness * dt)

		-- Shortest-path circular angular lerp: ZERO degree boundaries, ZERO snap-backs
		local diffYaw = (yaw - smoothYaw) % 360
		if diffYaw > 180 then diffYaw = diffYaw - 360 end
		smoothYaw = smoothYaw + diffYaw * rotAlpha
		smoothPitch = smoothPitch + (pitch - smoothPitch) * rotAlpha
		currentDistance += (targetDistance - currentDistance) * zoomAlpha

		local rawTargetPos = targetHRP.Position + Vector3.new(0, 2.5, 0)
		-- Zero Lag Character Centering (GTA V / Watch Dogs):
		-- Camera focus point stays locked 100% dead-center on character root.
		-- Completely eliminates the body drifting to the left/right edge of the screen during diagonal runs.
		smoothedTargetPos = rawTargetPos
		lastTrackedHRP = targetHRP

		-- 1. BONE & BODY DISPLACEMENT TRACKING (Stride & Vertical Cadence)
		local rawBobY = 0
		if suspensionEnabled and quinModel then
			local hips = getHipsBone(quinModel)
			if hips then
				local hipsPos
				if hips:IsA("Bone") then
					hipsPos = hips.TransformedWorldCFrame.Position
				elseif hips:IsA("BasePart") then
					hipsPos = hips.Position
				end

				if hipsPos then
					local currentRelY = hipsPos.Y - targetHRP.Position.Y
					if not restHipsRelY then
						restHipsRelY = currentRelY
					elseif targetHRP.AssemblyLinearVelocity.Magnitude < 2.0 then
						-- Auto-calibrate resting baseline when stationary
						restHipsRelY = restHipsRelY + (currentRelY - restHipsRelY) * (1 - math.exp(-2.0 * dt))
					end
					rawBobY = math.clamp(currentRelY - restHipsRelY, -1.2, 1.2)
				end
			end
		end

		-- 2. LOCOMOTION SUSPENSION STRIDE BOUNCE (Walk / Run Tiny Bounces)
		local curLinVel = targetHRP.AssemblyLinearVelocity
		local curVertVel = curLinVel.Y
		local horizVel = Vector3.new(curLinVel.X, 0, curLinVel.Z)
		local curSpeed = horizVel.Magnitude

		local locoBounceY = 0
		local locoPitchNod = 0
		local locoBounceSway = 0

		local isGrounded = math.abs(curVertVel) < 4.0
		if suspensionEnabled and curSpeed > 1.5 and isGrounded then
			-- Stride frequency scales with speed: ~2.4 Hz at walk (18 studs/s), ~4.2 Hz at sprint (50 studs/s)
			local speedNormalized = math.clamp(curSpeed / 50.0, 0, 1.2)
			local strideFreq = 2.0 + 2.2 * math.clamp(speedNormalized, 0, 1.0)
			stridePhase = (stridePhase + strideFreq * (2 * math.pi) * dt) % (2 * math.pi)

			-- Blend amplitude between walking (12 studs/s) and sprinting (50 studs/s)
			local walkRunFactor = math.clamp((curSpeed - 12.0) / 38.0, 0, 1.0)
			local curBounceAmp = walkBounceAmp + (runBounceAmp - walkBounceAmp) * walkRunFactor
			local curPitchBob = walkPitchBob + (runPitchBob - walkPitchBob) * walkRunFactor
			local curSwayAmp = walkSwayAmp + (runSwayAmp - walkSwayAmp) * walkRunFactor

			-- Downward suspension compression on foot plants + bone displacement
			locoBounceY = -math.abs(math.sin(stridePhase)) * curBounceAmp + (rawBobY * strideBobScale)
			locoPitchNod = math.cos(2 * stridePhase) * curPitchBob
			locoBounceSway = math.sin(stridePhase) * curSwayAmp
		else
			-- Smoothly damp stride phase when stopped or airborne
			stridePhase = 0
		end

		-- 3. VERTICAL SUSPENSION IMPACT SHOCK SPRING
		if suspensionEnabled then
			-- Landing Touchdown Shock: falling velocity abruptly absorbed on contact
			if lastVerticalVel < -10 and curVertVel > -2 then
				local impactSpeed = math.abs(lastVerticalVel)
				local impulse = math.clamp(impactSpeed * landingImpulseScale, 0.3, 2.2)
				suspVelY = suspVelY - impulse -- compress down into shocks
			end
			lastVerticalVel = curVertVel

			-- 2nd-order damped harmonic spring for macro shocks & elevation transitions
			local vertForce = -suspStiffness * suspDispY - suspDamping * suspVelY
			suspVelY = suspVelY + vertForce * dt
			suspDispY = math.clamp(suspDispY + suspVelY * dt, -2.5, 2.0)
		else
			suspDispY = 0
		end

		-- 4. GYRO & CENTRIPETAL BANKING (DUTCH TILT)
		local speedRatio = math.clamp(curSpeed / 50.0, 0, 1.25)
		if gyroEnabled then
			local bankAttrDeg = (quinModel and quinModel:GetAttribute("BankRoll")) or 0
			local hrpAngVelY = targetHRP.AssemblyAngularVelocity.Y
			local centripetalBank = -math.clamp(hrpAngVelY * speedRatio * 0.08, -math.rad(maxGyroRollDeg), math.rad(maxGyroRollDeg))
			local targetRoll = math.rad(bankAttrDeg) * gyroBankWeight + centripetalBank * (1 - gyroBankWeight)
			targetRoll = math.clamp(targetRoll, -math.rad(maxGyroRollDeg), math.rad(maxGyroRollDeg))

			local rollForce = -gyroStiffness * (gyroRoll - targetRoll) - gyroDamping * gyroRollVel
			gyroRollVel = gyroRollVel + rollForce * dt
			gyroRoll = gyroRoll + gyroRollVel * dt
		else
			gyroRoll = 0
		end

		-- 5. INERTIAL PITCH LAG & ACCEL SURGE
		local speedAccel = (curSpeed - lastHorizSpeed) / math.max(dt, 0.001)
		lastHorizSpeed = curSpeed

		local targetPitchLag = math.clamp(-speedAccel * 0.02, -maxPitchLagDeg, maxPitchLagDeg * 0.75)
		local pitchForce = -pitchLagStiffness * (inertPitch - targetPitchLag) - pitchLagDamping * inertPitchVel
		inertPitchVel = inertPitchVel + pitchForce * dt
		inertPitch = inertPitch + inertPitchVel * dt

		-- 6. CENTRIPETAL LATERAL SWAY (G-Force Shift)
		local targetSwayX = math.clamp((targetHRP.AssemblyAngularVelocity.Y) * speedRatio * 0.22, -maxLateralSwayStuds, maxLateralSwayStuds)
		local swayForce = -lateralSwayStiffness * (swayDispX - targetSwayX) - lateralSwayDamping * swayVelX
		swayVelX = swayVelX + swayForce * dt
		swayDispX = swayDispX + swayVelX * dt

		-- 7. DYNAMIC FOV SPEED BREATHING
		local speedFrac = math.clamp((curSpeed - fovSpeedMin) / (fovSpeedMax - fovSpeedMin), 0, 1)
		local targetFov = baseFOV + speedFrac * fovExpansionMax
		currentCamFov = currentCamFov + (targetFov - currentCamFov) * (1 - math.exp(-7.0 * dt))
		Camera.FieldOfView = currentCamFov

		-- 8. CONSTRUCT CAMERA CFRAME (Suspension Offset + Stride Bounce + Gyro Roll)
		local totalSuspY = suspDispY + locoBounceY
		local suspendedTargetPos = smoothedTargetPos + Vector3.new(0, totalSuspY, 0)
		local finalPitch = math.clamp(smoothPitch + inertPitch + locoPitchNod, -85, 85)

		local baseRotCF = CFrame.Angles(0, math.rad(smoothYaw), 0) * CFrame.Angles(math.rad(finalPitch), 0, 0)
		local camLook = baseRotCF.LookVector
		local camRight = baseRotCF.RightVector

		local totalSwayX = swayDispX + locoBounceSway
		local camPos = suspendedTargetPos - camLook * currentDistance + camRight * totalSwayX

		if camPos.Y < 2.0 then
			camPos = Vector3.new(camPos.X, 2.0, camPos.Z)
		end

		Camera.CFrame = CFrame.lookAt(camPos, suspendedTargetPos) * CFrame.Angles(0, 0, gyroRoll)
		cameraPos = camPos -- keep synced if switched to freefly
	end
end)
