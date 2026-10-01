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
local GaitModule = require(QuinCore:WaitForChild("Modules"):WaitForChild("GaitModule"))
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
local lastHeadingLook = nil
local bankLeanAngle = 0
local walkMode = false -- Z toggles walking; default pace is jog, Shift runs
local groundContractConn = nil

-- PlayerQuinController owns intent only. PlayerModule must be disabled while
-- possessed so it cannot write a second movement vector into the humanoid.
local defaultControls = nil
local function setDefaultControlsEnabled(enabled)
	if not defaultControls then
		local playerScripts = player:FindFirstChild("PlayerScripts")
		local playerModule = playerScripts and playerScripts:FindFirstChild("PlayerModule")
		if playerModule then
			local ok, module = pcall(require, playerModule)
			if ok and module and module.GetControls then
				defaultControls = module:GetControls()
			end
		end
	end
	if defaultControls then
		if enabled then
			defaultControls:Enable()
		else
			defaultControls:Disable()
		end
	end
end

-- ============================================================
-- 1. HUD BUTTON: [ ▶ Play As Quin ] / [ ⏹ Exit Quin Mode ]
-- ============================================================
local playerGui = player:WaitForChild("PlayerGui")
local playAsQuinGui = nil
local toggleBtn = nil
local stroke = nil
local toggleQuinControl = nil -- forward declaration

local function updateButtonDisplay(isPiloting)
	if not toggleBtn then return end
	if isPiloting then
		toggleBtn.Text = "⏹ Exit Quin Mode [P]"
		toggleBtn.TextColor3 = Color3.fromRGB(255, 180, 60)
		if stroke then stroke.Color = Color3.fromRGB(255, 140, 40) end
	else
		toggleBtn.Text = "▶ Play As Quin [P]"
		toggleBtn.TextColor3 = Color3.fromRGB(240, 245, 255)
		if stroke then stroke.Color = Color3.fromRGB(0, 200, 255) end
	end
end

local function ensureButtonHierarchy()
	if not playAsQuinGui or playAsQuinGui.Parent ~= playerGui then
		playAsQuinGui = playerGui:FindFirstChild("PlayAsQuinGui")
		if not playAsQuinGui then
			playAsQuinGui = Instance.new("ScreenGui")
			playAsQuinGui.Name = "PlayAsQuinGui"
			playAsQuinGui.ResetOnSpawn = false
			playAsQuinGui.DisplayOrder = 20
			playAsQuinGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
			playAsQuinGui.Parent = playerGui
		end
	end

	local existing = playAsQuinGui:FindFirstChild("PlayAsQuinBtn")
	if existing then
		toggleBtn = existing
		stroke = toggleBtn:FindFirstChildOfClass("UIStroke")
	else
		toggleBtn = Instance.new("TextButton")
		toggleBtn.Name = "PlayAsQuinBtn"
		toggleBtn.Size = UDim2.new(0, 180, 0, 36)
		toggleBtn.AnchorPoint = Vector2.new(1, 1)
		toggleBtn.Position = UDim2.new(1, -20, 1, -113)
		toggleBtn.BackgroundColor3 = Color3.fromRGB(18, 22, 30)
		toggleBtn.BackgroundTransparency = 0.15
		toggleBtn.TextColor3 = Color3.fromRGB(240, 245, 255)
		toggleBtn.Font = Enum.Font.GothamBold
		toggleBtn.TextSize = 12
		toggleBtn.Text = (activeQuin ~= nil) and "⏹ Exit Quin Mode [P]" or "▶ Play As Quin [P]"

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 18)
		corner.Parent = toggleBtn

		stroke = Instance.new("UIStroke")
		stroke.Color = (activeQuin ~= nil) and Color3.fromRGB(255, 140, 40) or Color3.fromRGB(0, 200, 255)
		stroke.Thickness = 1.5
		stroke.Transparency = 0.4
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Parent = toggleBtn

		toggleBtn.MouseEnter:Connect(function()
			TweenService:Create(toggleBtn, TweenInfo.new(0.2), { BackgroundTransparency = 0.05 }):Play()
			if stroke then TweenService:Create(stroke, TweenInfo.new(0.2), { Transparency = 0.1 }):Play() end
		end)

		toggleBtn.MouseLeave:Connect(function()
			TweenService:Create(toggleBtn, TweenInfo.new(0.2), { BackgroundTransparency = 0.15 }):Play()
			if stroke then TweenService:Create(stroke, TweenInfo.new(0.2), { Transparency = 0.4 }):Play() end
		end)

		toggleBtn.MouseButton1Click:Connect(function()
			if toggleQuinControl then
				toggleQuinControl()
			end
		end)

		toggleBtn.Parent = playAsQuinGui
	end
	updateButtonDisplay(activeQuin ~= nil)
end

ensureButtonHierarchy()
player.CharacterAdded:Connect(function()
	task.defer(ensureButtonHierarchy)
end)

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

	-- Notify camera and presentation systems
	shared.PlayerControlledQuin = quin
	_G.PlayerControlledQuin = quin
	activeQuin:SetAttribute("IsPlayerControlled", true)

	-- Prevent Roblox's default PlayerModule from competing with QuinCore.
	setDefaultControlsEnabled(false)

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
	-- Start from rest so QuinCore acceleration, braking, and animation cadence carry weight.
	activeQuin:SetAttribute("CurrentPilotSpeed", 0)
	LocomotionModule.resetGroundIntent(activeQuin)
	AnimationModule.ensureBaseIdle(activeHumanoid)

	-- This client owns the piloted Quin's animation: enforce the ground contract here
	if groundContractConn then groundContractConn:Disconnect() end
	local contractQuin = activeQuin
	groundContractConn = GaitModule.bindGroundContract(activeQuin, activeHumanoid, activeRootPart, function()
		return contractQuin:GetAttribute("IsPlayerControlled") == true
	end)

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


		-- A committed slide owns the body until it hands back to the gait
		if LocomotionModule.isSliding(activeQuin) then
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
		-- Gait intent: default jog, Z toggles walk, hold Shift to run. The animation
		-- follows the resulting ground speed through the shared GaitModule blend.
		local goalSpeed
		if isSprint then
			goalSpeed = CombatConfig.Player_RunSpeed or 42.0
		elseif walkMode or activeQuin:GetAttribute("VirtualWalk") == true then
			goalSpeed = CombatConfig.Player_WalkSpeed or 7.5
		else
			goalSpeed = CombatConfig.Player_JogSpeed or 13.0
		end

		-- Authoritative speed modulation: targetSpeed is set to goalSpeed,
		-- and LocomotionModule.modulateSpeed applies the authoritative acceleration curve
		local targetSpeed = goalSpeed
		activeQuin:SetAttribute("CurrentPilotSpeed", activeHumanoid.WalkSpeed)

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

			-- Direct, Responsive Player Drive (GTA V / Watch Dogs 2 style):
			-- We do NOT pass moveDir as resolvedDirection; LocomotionModule.steer carves the turn arc
			-- through resolveGroundIntent, eliminating instantaneous 45° crab-strafe snaps on diagonal transitions.
			local moveDir = rawMoveDir
			smoothedMoveDir = moveDir
			lastMoveDir = moveDir

			activeQuin:SetAttribute("IsMoving", true)
			activeQuin:SetAttribute("LastActivityTime", now)

			-- Sprint initiation: track start timestamp to dynamically ramp animation speed from slow to baseline
			if isSprint and not wasSprinting and not isAirborne then
				activeQuin:SetAttribute("IsSprinting", true)
				activeQuin:SetAttribute("SprintStartTime", now)
			elseif not isSprint then
				activeQuin:SetAttribute("IsSprinting", false)
				activeQuin:SetAttribute("SprintStartTime", nil)
			end

			-- Pure Speed Retention: Speed stays solid, crisp, and constant through turns (GTA V / Watch Dogs)
			local currentVel = activeRootPart.AssemblyLinearVelocity
			local flatVel = Vector3.new(currentVel.X, 0, currentVel.Z)
			local curSpeed = flatVel.Magnitude

			-- Stylized Grey Foot Smoke: Cadence-synced puffs during sprint strides
			if isSprint and curSpeed > 25.0 and not isAirborne then
				local smokeCadence = 0.28 -- matches sprint stride frequency
				if (now - lastFootstepSmokeTime) >= smokeCadence then
					lastFootstepSmokeTime = now
					local footOffset = Vector3.new(0, -activeRootPart.Size.Y * 0.5, 0)
					VfxModule.emitFootstepSmoke(activeQuin, activeRootPart.Position + footOffset)
				end
			end

			-- Authoritative QuinCore steer: resolves ground intent through continuous damped heading arc (GTA V / Watch Dogs 2)
			local rawTargetPosition = activeRootPart.Position + rawMoveDir * 15
			LocomotionModule.steer(activeQuin, activeHumanoid, activeRootPart, rawTargetPosition, targetSpeed, dt)

			-- Shared QuinCore gait: synchronized Walk/Run blend space whose cadence is
			-- derived from real ground speed, identical to the AI Quins. It self-gates:
			-- it never plays ground loops in the air or under a slide.
			if not AnimationModule.isPlaying(activeHumanoid, "Movement.StopRun") then
				GaitModule.update(activeHumanoid, activeRootPart, dt)
			end
		else
			smoothedMoveDir = Vector3.zero
			-- Retain lastRawMoveDir across brief key transitions (20-350ms) so WASD multi-taps detect chatter
			if lastRawMoveTime and (now - lastRawMoveTime) > 0.35 then
				lastRawMoveDir = nil
			end
			local isChattering = lastChatterTime and (now - lastChatterTime) < 0.40
			activeQuin:SetAttribute("DirectionalChatter", isChattering or false)

			-- Preserve weight on release: let the authoritative brake decelerate the body,
			-- while the pilot speed attribute eases toward rest instead of snapping to walk pace.
			local releaseAlpha = 1.0 - math.exp(-10.0 * dt)
			local releasedSpeed = activeQuin:GetAttribute("CurrentPilotSpeed") or 0
			activeQuin:SetAttribute("CurrentPilotSpeed", releasedSpeed + (0 - releasedSpeed) * releaseAlpha)
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
	setDefaultControlsEnabled(true)
	if groundContractConn then
		groundContractConn:Disconnect()
		groundContractConn = nil
	end
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
		LocomotionModule.resetGroundIntent(activeQuin)
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
	updateButtonDisplay(false)

	print("[PlayerQuinController] Released Quin control — returned to Freefly spectator.")
end

-- ============================================================
-- COMBAT ATTACK ENGINE (Punches & Light Combos)
-- ============================================================
local comboStep = 1
local lastAttackTime = 0
local PUNCH_TRACKS = {
	"rbxassetid://113219639247452", -- Lead Jab
	"rbxassetid://99362983788110",  -- Cross Right
	"rbxassetid://135206101877204", -- Hook Punch
}

local function executePlayerAttack()
	if not activeQuin or not activeHumanoid or not activeRootPart then return end
	if activeHumanoid.Health <= 0 then return end
	local now = os.clock()
	if now - lastAttackTime < 0.28 then return end

	if now - lastAttackTime > 1.2 then
		comboStep = 1
	else
		comboStep = (comboStep % #PUNCH_TRACKS) + 1
	end
	lastAttackTime = now

	-- Refresh activity & set Ready stance
	activeQuin:SetAttribute("LastActivityTime", now)
	activeQuin:SetAttribute("CurrentIdleStance", "Ready")

	-- Play attack animation track
	local animId = PUNCH_TRACKS[comboStep]
	AnimationModule.play(activeHumanoid, animId, {
		speed = 1.35,
		priority = Enum.AnimationPriority.Action4,
		fadeTime = 0.05
	})

	-- Invoke server-authoritative damage & hitbox
	if controlFunction then
		task.spawn(function()
			controlFunction:InvokeServer("Attack", comboStep)
		end)
	end
end

toggleQuinControl = function(desiredState, explicitTarget)
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

		if toggleBtn then
			toggleBtn.Text = "⏳ Possessing..."
		end

		-- Target: explicit target > spectated quin > default arena quin
		local targetName = explicitTarget
		if not targetName or targetName == "" then
			local spec = shared.SpectatedQuin or _G.SpectatedQuin
			if spec and spec:IsA("Model") and spec ~= player.Character then
				targetName = spec.Name
			end
		end

		local possessedQuin = controlFunction:InvokeServer("Possess", targetName)
		if possessedQuin then
			startControlSession(possessedQuin)
		else
			warn("[PlayerQuinController] Server failed to possess Quin")
			updateButtonDisplay(false)
		end
	else
		if controlFunction then
			controlFunction:InvokeServer("Release")
		end
		stopControlSession()
	end
end

-- Export to shared environment for QuinDebugHUD & other UI integration
shared.ToggleQuinControl = toggleQuinControl
_G.ToggleQuinControl = toggleQuinControl

player.CharacterAdded:Connect(function(char)
	task.defer(ensureButtonHierarchy)
end)

-- ============================================================================
-- 3. KEYBIND LISTENERS (Jump, Slide, Dash, Attack, Toggle)
-- ============================================================================
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

	-- Mouse Click Attack (Left Click when not clicking UI)
	if input.UserInputType == Enum.UserInputType.MouseButton1 and not gp then
		executePlayerAttack()
		return
	end

	-- F Key: Light Attack / Punch Combo
	if input.KeyCode == Enum.KeyCode.F and not gp then
		executePlayerAttack()
		return
	end

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
		LocomotionModule.slide(activeQuin, activeHumanoid, activeRootPart, lastMoveDir)

	-- Z: toggle walking pace (default pace is jog)
	elseif input.KeyCode == Enum.KeyCode.Z then
		walkMode = not walkMode
		activeQuin:SetAttribute("WalkMode", walkMode)

	-- Q or E: Dash burst
	elseif input.KeyCode == Enum.KeyCode.Q or input.KeyCode == Enum.KeyCode.E then
		local dashTarget = activeRootPart.Position + lastMoveDir * 35
		LocomotionModule.dash(activeQuin, activeHumanoid, activeRootPart, dashTarget, 35)
	end
end)

print("[PlayerQuinController] Initialized in Spectator Mode. Press 'P' or click 'Play As Quin' to possess a fighter.")
