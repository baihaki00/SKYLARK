--// PlayerQuinController.client.lua
-- Allows the player to pilot a Quin directly using authentic QuinCore physics & locomotion
-- Single Source of Truth: ReplicatedStorage.QuinCore.Modules.LocomotionModule

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local QuinCore = ReplicatedStorage:WaitForChild("QuinCore")
local CombatConfig = require(QuinCore:WaitForChild("CombatConfig"))
local AnimationConfig = require(QuinCore:WaitForChild("AnimationConfig"))
local LocomotionModule = require(QuinCore:WaitForChild("Modules"):WaitForChild("LocomotionModule"))
local AnimationModule = require(QuinCore:WaitForChild("Modules"):WaitForChild("AnimationModule"))
local SpatialModule = require(QuinCore:WaitForChild("Modules"):WaitForChild("SpatialModule"))
local VfxModule = require(QuinCore:WaitForChild("Modules"):WaitForChild("VfxModule"))

local controlFunction = ReplicatedStorage:WaitForChild("PlayerQuinControlFunction", 10)

-- State tracking
local activeQuin = nil
local activeHumanoid = nil
local activeRootPart = nil
local renderConn = nil
local deathConn = nil
local lastMoveDir = Vector3.new(0, 0, -1)
local smoothedMoveDir = Vector3.zero
local lastRawMoveDir = nil
local lastRawMoveTime = 0
local lastChatterTime = 0
local lastHeadingAngle = nil
local lastFootstepSmokeTime = 0

-- ============================================================================
-- 1. HUD BUTTON: [ ▶ Play As Quin ] / [ ⏹ Exit Quin Mode ]
-- ============================================================================
local playerGui = player:WaitForChild("PlayerGui")
local screenGui = playerGui:FindFirstChild("ScreenGui")
if not screenGui then
	screenGui = Instance.new("ScreenGui")
	screenGui.Name = "ScreenGui"
	screenGui.ResetOnSpawn = false
	screenGui.Parent = playerGui
end

local toggleBtn = Instance.new("TextButton")
toggleBtn.Name = "PlayAsQuinBtn"
toggleBtn.Size = UDim2.new(0, 180, 0, 36)
toggleBtn.AnchorPoint = Vector2.new(1, 1)
toggleBtn.Position = UDim2.new(1, -20, 1, -113)
toggleBtn.BackgroundColor3 = Color3.fromRGB(18, 22, 30)
toggleBtn.BackgroundTransparency = 0.15
toggleBtn.TextColor3 = Color3.fromRGB(240, 245, 255)
toggleBtn.Font = Enum.Font.GothamBold
toggleBtn.TextSize = 12
toggleBtn.Text = "▶ Play As Quin [P]"
toggleBtn.Parent = screenGui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 18)
corner.Parent = toggleBtn

local stroke = Instance.new("UIStroke")
stroke.Color = Color3.fromRGB(0, 200, 255)
stroke.Thickness = 1.5
stroke.Transparency = 0.4
stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
stroke.Parent = toggleBtn

-- Subtle hover animation matching spectator and manager pills
toggleBtn.MouseEnter:Connect(function()
	TweenService:Create(toggleBtn, TweenInfo.new(0.2), { BackgroundTransparency = 0.05 }):Play()
	TweenService:Create(stroke, TweenInfo.new(0.2), { Transparency = 0.1 }):Play()
end)

toggleBtn.MouseLeave:Connect(function()
	TweenService:Create(toggleBtn, TweenInfo.new(0.2), { BackgroundTransparency = 0.15 }):Play()
	TweenService:Create(stroke, TweenInfo.new(0.2), { Transparency = 0.4 }):Play()
end)

-- Forward declaration
local toggleQuinControl

-- ============================================================================
-- 2. LOCOMOTION INPUT ENGINE (Calls QuinCore.LocomotionModule Directly)
-- ============================================================================
local function startControlSession(quin)
	activeQuin = quin
	activeHumanoid = quin:FindFirstChildOfClass("Humanoid")
	activeRootPart = quin:FindFirstChild("HumanoidRootPart")

	if not activeHumanoid or not activeRootPart then
		warn("[PlayerQuinController] Quin missing Humanoid or HumanoidRootPart")
		return false
	end

	-- Notify camera and ghost systems
	shared.PlayerControlledQuin = quin
	_G.PlayerControlledQuin = quin
	activeQuin:SetAttribute("IsPlayerControlled", true)

	-- Stop any stale tracks so IdleReady_Stance has a clean slate
	local animator = activeHumanoid:FindFirstChildOfClass("Animator")
	if animator then
		for _, t in ipairs(animator:GetPlayingAnimationTracks()) do
			t:Stop(0)
		end
	end

	-- Immediately engage default idle posture (IDLE_DEFAULT)
	activeQuin:SetAttribute("CurrentIdleStance", "Default")
	activeQuin:SetAttribute("LastActivityTime", os.clock())
	activeQuin:SetAttribute("IsMoving", false)
	activeQuin:SetAttribute("IsSprinting", false)
	AnimationModule.ensureBaseIdle(activeHumanoid)

	-- Update button UI
	toggleBtn.Text = "⏹ Exit Quin Mode [P]"
	toggleBtn.TextColor3 = Color3.fromRGB(255, 180, 60)
	stroke.Color = Color3.fromRGB(255, 140, 40)

	-- Auto-exit if Quin dies
	if deathConn then deathConn:Disconnect() end
	deathConn = activeHumanoid.Died:Connect(function()
		print("[PlayerQuinController] Player Quin died — exiting control mode.")
		toggleQuinControl(false)
	end)

	-- Frame-by-frame locomotion loop
	if renderConn then renderConn:Disconnect() end
	renderConn = RunService.RenderStepped:Connect(function(dt)
		if not activeQuin or not activeQuin.Parent or not activeRootPart or not activeHumanoid then
			toggleQuinControl(false)
			return
		end

		if activeHumanoid.Health <= 0 then
			return
		end

		-- Skip movement inputs if focused on TextBox
		if UserInputService:GetFocusedTextBox() then
			LocomotionModule.brake(activeQuin, activeHumanoid, activeRootPart, dt)
			return
		end

		-- Read movement keys
		local moveZ = 0
		local moveX = 0
		if UserInputService:IsKeyDown(Enum.KeyCode.W) or UserInputService:IsKeyDown(Enum.KeyCode.Up) then moveZ = moveZ - 1 end
		if UserInputService:IsKeyDown(Enum.KeyCode.S) or UserInputService:IsKeyDown(Enum.KeyCode.Down) then moveZ = moveZ + 1 end
		if UserInputService:IsKeyDown(Enum.KeyCode.A) or UserInputService:IsKeyDown(Enum.KeyCode.Left) then moveX = moveX - 1 end
		if UserInputService:IsKeyDown(Enum.KeyCode.D) or UserInputService:IsKeyDown(Enum.KeyCode.Right) then moveX = moveX + 1 end

		-- Virtual Input support for diagnostics and automated testing suites
		local virtZ = activeQuin:GetAttribute("VirtualMoveZ")
		local virtX = activeQuin:GetAttribute("VirtualMoveX")
		if virtZ ~= nil then moveZ = virtZ end
		if virtX ~= nil then moveX = virtX end

		local camCF = workspace.CurrentCamera.CFrame
		local fwd = Vector3.new(camCF.LookVector.X, 0, camCF.LookVector.Z)
		local right = Vector3.new(camCF.RightVector.X, 0, camCF.RightVector.Z)
		fwd = fwd.Magnitude > 0.01 and fwd.Unit or Vector3.new(0, 0, -1)
		right = right.Magnitude > 0.01 and right.Unit or Vector3.new(1, 0, 0)

		local rawMoveDir = (fwd * (-moveZ) + right * moveX)
		local now = os.clock()

		-- Sprint toggle (LeftShift, RightShift, or VirtualSprint)
		local isSprint = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
			or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
			or (activeQuin:GetAttribute("VirtualSprint") == true)
		local maxPacing = CombatConfig.Locomotion_PacingSpeedMax or 50.0
		local minPacing = CombatConfig.Locomotion_PacingSpeedMin or 18.5
		local goalSpeed = isSprint and maxPacing or minPacing

		-- Smooth kinetic acceleration curve: emulates natural inertia and weight on keyboard
		local curPilotSpeed = activeQuin:GetAttribute("CurrentPilotSpeed") or minPacing
		local accelRate = isSprint and 85.0 or 60.0
		if curPilotSpeed < goalSpeed then
			curPilotSpeed = math.min(curPilotSpeed + accelRate * dt, goalSpeed)
		else
			curPilotSpeed = math.max(curPilotSpeed - accelRate * 1.5 * dt, goalSpeed)
		end
		activeQuin:SetAttribute("CurrentPilotSpeed", curPilotSpeed)
		local targetSpeed = curPilotSpeed

		local isAirborne = (activeHumanoid:GetState() == Enum.HumanoidStateType.Jumping)
			or (activeHumanoid:GetState() == Enum.HumanoidStateType.Freefall)
			or (activeHumanoid.FloorMaterial == Enum.Material.Air and not SpatialModule.isGrounded(activeRootPart))

		local wasMoving = activeQuin:GetAttribute("IsMoving") == true
		local wasSprinting = activeQuin:GetAttribute("IsSprinting") == true

		if rawMoveDir.Magnitude > 0.1 then
			rawMoveDir = rawMoveDir.Unit

			-- Directional Chatter Detection:
			-- Check dot product between successive raw input vectors and time interval
			if lastRawMoveDir then
				local dotRaw = lastRawMoveDir:Dot(rawMoveDir)
				local timeSinceLastRaw = now - lastRawMoveTime
				-- Angle reversal (< 0.5, i.e. > 60° cut) within 350ms implies rapid WASD chatter
				-- Exclude sharp reversals (dotRaw < -0.42) so intentional 180° turnarounds execute cleanly
				if dotRaw < 0.5 and dotRaw >= -0.42 and timeSinceLastRaw < 0.35 then
					lastChatterTime = now
				end
			end
			lastRawMoveDir = rawMoveDir
			lastRawMoveTime = now

			local isChattering = lastChatterTime and (now - lastChatterTime) < 0.40
			activeQuin:SetAttribute("DirectionalChatter", isChattering or false)

			-- 2D Heading Slerp Directional Spring:
			-- Interpolates heading angle along the unit circle rather than cutting through (0,0,0)
			-- Eliminates vector collapse and 1-frame sideways snapping on 180° reversals
			local targetAngle = math.atan2(rawMoveDir.X, rawMoveDir.Z)
			if smoothedMoveDir.Magnitude < 0.1 then
				if lastHeadingAngle and (now - lastRawMoveTime) < 0.25 then
					local diff = (targetAngle - lastHeadingAngle + math.pi) % (2 * math.pi) - math.pi
					local springAlpha = 1.0 - math.exp(-28.0 * dt)
					local newAngle = lastHeadingAngle + diff * springAlpha
					smoothedMoveDir = Vector3.new(math.sin(newAngle), 0, math.cos(newAngle))
					lastHeadingAngle = newAngle
				else
					smoothedMoveDir = rawMoveDir
					lastHeadingAngle = targetAngle
				end
			else
				local currentAngle = math.atan2(smoothedMoveDir.X, smoothedMoveDir.Z)
				local diff = (targetAngle - currentAngle + math.pi) % (2 * math.pi) - math.pi
				local springAlpha = 1.0 - math.exp(-28.0 * dt)
				local newAngle = currentAngle + diff * springAlpha
				smoothedMoveDir = Vector3.new(math.sin(newAngle), 0, math.cos(newAngle))
				lastHeadingAngle = newAngle
			end

			local moveDir = smoothedMoveDir
			lastMoveDir = moveDir

			local targetPosition = activeRootPart.Position + moveDir * 15

			activeQuin:SetAttribute("IsMoving", true)
			activeQuin:SetAttribute("LastActivityTime", now)

			-- Sprint initiation: track start timestamp to dynamically ramp animation speed from slow to baseline
			if isSprint and not wasSprinting and not isAirborne then
				activeQuin:SetAttribute("IsSprinting", true)
				activeQuin:SetAttribute("SprintStartTime", now)
				AnimationModule.stop(activeHumanoid, "Movement.WalkConfident", 0.10)
			elseif not isSprint then
				activeQuin:SetAttribute("IsSprinting", false)
				activeQuin:SetAttribute("SprintStartTime", nil)
			end

			-- Dynamic Apex Deceleration Dip & Physical Weight:
			-- When carving a sharp cut or tight circle at high speed, momentarily dip speed by 15-25%
			-- to emulate planting mass/friction into the turf, then burst forward with momentum!
			local currentVel = activeRootPart.AssemblyLinearVelocity
			local flatVel = Vector3.new(currentVel.X, 0, currentVel.Z)
			local curSpeed = flatVel.Magnitude
			if curSpeed > 20.0 and flatVel.Magnitude > 0.1 then
				local alignment = flatVel.Unit:Dot(smoothedMoveDir)
				if alignment < 0.85 then
					local apexFactor = math.clamp(0.75 + 0.25 * math.max(0, alignment), 0.75, 1.0)
					targetSpeed = targetSpeed * apexFactor
				end
			end

			-- Stylized Grey Foot Smoke: Cadence-synced puffs during sprint strides
			if isSprint and curSpeed > 25.0 and not isAirborne then
				local smokeCadence = 0.28 -- matches sprint stride frequency
				if (now - lastFootstepSmokeTime) >= smokeCadence then
					lastFootstepSmokeTime = now
					local footOffset = Vector3.new(0, -activeRootPart.Size.Y * 0.5, 0)
					VfxModule.emitFootstepSmoke(activeQuin, activeRootPart.Position + footOffset)
				end
			end

			-- Authoritative QuinCore steer: checks 180° skids against RAW player intent vector, modulates speed
			local rawTargetPosition = activeRootPart.Position + rawMoveDir * 15
			LocomotionModule.steer(activeQuin, activeHumanoid, activeRootPart, rawTargetPosition, targetSpeed, dt)

			activeHumanoid:Move(smoothedMoveDir, false)

			-- Only drive ground locomotion animations when grounded (do not overwrite jump in mid-air)
			if not isAirborne then
				-- Protect stop plants from being crushed by base locomotion
				local isStopPlaying = AnimationModule.isPlaying(activeHumanoid, "Movement.StopRun")

				if not isStopPlaying then
					local desiredAnim = isSprint and "Movement.Run" or "Movement.WalkConfident"
					local oppositeAnim = isSprint and "Movement.WalkConfident" or "Movement.Run"

					if AnimationModule.isPlaying(activeHumanoid, oppositeAnim) then
						AnimationModule.stop(activeHumanoid, oppositeAnim, 0.15)
					end

					if not AnimationModule.isPlaying(activeHumanoid, desiredAnim) then
						AnimationModule.stop(activeHumanoid, "Movement.Idle", 0.15)
						AnimationModule.stop(activeHumanoid, "Idles.ReadyStance", 0.15)
						AnimationModule.stop(activeHumanoid, "Idles.FightIdle", 0.15)
						AnimationModule.stop(activeHumanoid, "Idles.CombatIdle", 0.15)
						AnimationModule.playConfig(activeHumanoid, desiredAnim)
					end

					-- Athletic Stride Turnover (Eliminates slow-motion shuffling):
					-- At min running speed (18.5 studs/s), turnover is a crisp, natural 0.75x cadence.
					-- At max sprint (50.0 studs/s), turnover reaches full 1.00x athletic power.
					if desiredAnim == "Movement.Run" and AnimationModule.isPlaying(activeHumanoid, "Movement.Run") then
						local currentSpeed = activeRootPart.AssemblyLinearVelocity.Magnitude
						local minPacing = CombatConfig.Locomotion_PacingSpeedMin or 18.5
						local maxPacing = CombatConfig.Locomotion_PacingSpeedMax or 50.0
						local baseCfgSpeed = AnimationConfig.get("Movement.Run") and AnimationConfig.get("Movement.Run").speed or 1.00

						local speedFraction = math.clamp((currentSpeed - minPacing) / math.max(1, maxPacing - minPacing), 0.0, 1.0)
						local dynamicCadence = 0.75 + (0.25 * speedFraction)
						local dynamicSpeed = math.clamp(baseCfgSpeed * dynamicCadence, 0.70, 1.05)
						AnimationModule.adjustSpeed(activeHumanoid, "Movement.Run", dynamicSpeed)
					elseif desiredAnim == "Movement.WalkConfident" and AnimationModule.isPlaying(activeHumanoid, "Movement.WalkConfident") then
						local currentSpeed = activeRootPart.AssemblyLinearVelocity.Magnitude
						local strideBase = CombatConfig.WalkStrideBase or 18.5
						local velRatio = math.clamp(currentSpeed / strideBase, 0.50, 1.10)
						local baseCfgSpeed = AnimationConfig.get("Movement.WalkConfident") and AnimationConfig.get("Movement.WalkConfident").speed or 1.00
						AnimationModule.adjustSpeed(activeHumanoid, "Movement.WalkConfident", baseCfgSpeed * velRatio)
					end
				end
			end
		else
			smoothedMoveDir = Vector3.zero
			-- Retain lastRawMoveDir across brief key transitions (20-350ms) so WASD multi-taps detect chatter
			if lastRawMoveTime and (now - lastRawMoveTime) > 0.35 then
				lastRawMoveDir = nil
			end
			local isChattering = lastChatterTime and (now - lastChatterTime) < 0.40
			activeQuin:SetAttribute("DirectionalChatter", isChattering or false)

			-- Reset pilot speed towards min pacing when keys are released
			activeQuin:SetAttribute("CurrentPilotSpeed", minPacing)
			activeQuin:SetAttribute("IsMoving", false)
			activeQuin:SetAttribute("IsSprinting", false)
			activeQuin:SetAttribute("SprintStartTime", nil)

			if not isAirborne then
				-- Authoritative QuinCore brake: smooth deceleration, slide follow-through, stops run, ensures idle
				LocomotionModule.brake(activeQuin, activeHumanoid, activeRootPart, dt)
			end
		end
	end)

	print(string.format("[PlayerQuinController] Successfully piloting %s via QuinCore locomotion!", quin.Name))
	return true
end

local function stopControlSession()
	if renderConn then
		renderConn:Disconnect()
		renderConn = nil
	end
	if deathConn then
		deathConn:Disconnect()
		deathConn = nil
	end

	if activeQuin then
		activeQuin:SetAttribute("IsPlayerControlled", false)
		if activeHumanoid and activeRootPart then
			LocomotionModule.brake(activeQuin, activeHumanoid, activeRootPart, 0.1)
		end
	end

	shared.PlayerControlledQuin = nil
	_G.PlayerControlledQuin = nil
	smoothedMoveDir = Vector3.zero
	lastRawMoveDir = nil
	lastRawMoveTime = 0
	lastChatterTime = 0
	activeQuin = nil
	activeHumanoid = nil
	activeRootPart = nil

	-- Update button UI
	toggleBtn.Text = "▶ Play As Quin [P]"
	toggleBtn.TextColor3 = Color3.fromRGB(240, 245, 255)
	stroke.Color = Color3.fromRGB(0, 200, 255)

	print("[PlayerQuinController] Released Quin control — returned to Freefly spectator.")
end

toggleQuinControl = function(desiredState)
	if desiredState == nil then
		desiredState = (activeQuin == nil)
	end

	if desiredState then
		if not controlFunction then
			controlFunction = ReplicatedStorage:FindFirstChild("PlayerQuinControlFunction")
		end
		if not controlFunction then
			warn("[PlayerQuinController] PlayerQuinControlFunction not found in ReplicatedStorage")
			return
		end

		toggleBtn.Text = "⏳ Summoning..."
		local possessedQuin = controlFunction:InvokeServer("Possess")
		if possessedQuin then
			startControlSession(possessedQuin)
		else
			warn("[PlayerQuinController] Server failed to possess or spawn Quin")
			toggleBtn.Text = "▶ Play As Quin [P]"
		end
	else
		if controlFunction then
			controlFunction:InvokeServer("Release")
		end
		stopControlSession()
	end
end

-- ============================================================================
-- 3. KEYBIND LISTENERS (Jump, Slide, Dash, Toggle)
-- ============================================================================
toggleBtn.MouseButton1Click:Connect(function()
	toggleQuinControl()
end)

UserInputService.InputBegan:Connect(function(input, gp)
	if UserInputService:GetFocusedTextBox() then return end

	-- Hotkey P toggles Quin mode
	if input.KeyCode == Enum.KeyCode.P and not gp then
		toggleQuinControl()
		return
	end

	-- Controls when actively piloting
	if not activeQuin or not activeRootPart or not activeHumanoid then return end
	if activeHumanoid.Health <= 0 then return end

	-- Pilot action touches activity timestamp & keeps Quin alert in Ready stance
	activeQuin:SetAttribute("LastActivityTime", os.clock())
	activeQuin:SetAttribute("CurrentIdleStance", "Ready")

	-- Space: Ballistic Jump (Rule 6: single impulse, 88% landing retention)
	if input.KeyCode == Enum.KeyCode.Space then
		local currentVel = activeRootPart.AssemblyLinearVelocity
		local hSpeed = Vector3.new(currentVel.X, 0, currentVel.Z).Magnitude
		local fwdSpeed = (hSpeed > 2.0) and hSpeed or 0.0
		LocomotionModule.jump(activeQuin, activeHumanoid, activeRootPart, 8.0, fwdSpeed, "jump")

	-- C: Athletic Ground Slide
	elseif input.KeyCode == Enum.KeyCode.C then
		LocomotionModule.slide(activeQuin, activeHumanoid, activeRootPart, lastMoveDir, 0.42)

	-- Q or E: Dash burst
	elseif input.KeyCode == Enum.KeyCode.Q or input.KeyCode == Enum.KeyCode.E then
		local dashTarget = activeRootPart.Position + lastMoveDir * 35
		LocomotionModule.dash(activeQuin, activeHumanoid, activeRootPart, dashTarget, 35)
	end
end)

print("[PlayerQuinController] Initialized. Press 'P' or click 'Play As Quin' to hop in.")

-- Auto-spawn into Quin mode at SpawnLocation on startup
task.spawn(function()
	task.wait(0.5)
	if not activeQuin then
		print("[PlayerQuinController] Auto-spawning player at SpawnLocation...")
		toggleQuinControl(true)
	end
end)
