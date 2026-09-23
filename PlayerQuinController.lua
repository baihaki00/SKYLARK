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
local LocomotionModule = require(QuinCore:WaitForChild("Modules"):WaitForChild("LocomotionModule"))
local AnimationModule = require(QuinCore:WaitForChild("Modules"):WaitForChild("AnimationModule"))
local SpatialModule = require(QuinCore:WaitForChild("Modules"):WaitForChild("SpatialModule"))

local controlFunction = ReplicatedStorage:WaitForChild("PlayerQuinControlFunction", 10)

-- State tracking
local activeQuin = nil
local activeHumanoid = nil
local activeRootPart = nil
local renderConn = nil
local deathConn = nil
local lastMoveDir = Vector3.new(0, 0, -1)

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

local btnFrame = Instance.new("Frame")
btnFrame.Name = "PlayAsQuinContainer"
btnFrame.Size = UDim2.new(0, 180, 0, 36)
btnFrame.AnchorPoint = Vector2.new(1, 1)
btnFrame.Position = UDim2.new(1, -20, 1, -113)
btnFrame.BackgroundColor3 = Color3.fromRGB(20, 22, 28)
btnFrame.BackgroundTransparency = 0.2
btnFrame.BorderSizePixel = 0
btnFrame.Parent = screenGui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 18)
corner.Parent = btnFrame

local stroke = Instance.new("UIStroke")
stroke.Color = Color3.fromRGB(0, 200, 255)
stroke.Thickness = 1.5
stroke.Transparency = 0.4
stroke.Parent = btnFrame

local toggleBtn = Instance.new("TextButton")
toggleBtn.Name = "PlayAsQuinBtn"
toggleBtn.Size = UDim2.new(1, 0, 1, 0)
toggleBtn.BackgroundTransparency = 1
toggleBtn.Font = Enum.Font.GothamBold
toggleBtn.TextSize = 13
toggleBtn.TextColor3 = Color3.fromRGB(240, 245, 255)
toggleBtn.Text = "▶ Play As Quin (P)"
toggleBtn.Parent = btnFrame

-- Subtle hover animation
toggleBtn.MouseEnter:Connect(function()
	TweenService:Create(btnFrame, TweenInfo.new(0.2), { BackgroundTransparency = 0.05 }):Play()
	TweenService:Create(stroke, TweenInfo.new(0.2), { Transparency = 0.1 }):Play()
end)

toggleBtn.MouseLeave:Connect(function()
	TweenService:Create(btnFrame, TweenInfo.new(0.2), { BackgroundTransparency = 0.2 }):Play()
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

	-- Notify camera
	shared.PlayerControlledQuin = quin
	_G.PlayerControlledQuin = quin

	-- Update button UI
	toggleBtn.Text = "⏹ Exit Quin Mode (P)"
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

		local camCF = workspace.CurrentCamera.CFrame
		local fwd = Vector3.new(camCF.LookVector.X, 0, camCF.LookVector.Z)
		local right = Vector3.new(camCF.RightVector.X, 0, camCF.RightVector.Z)
		fwd = fwd.Magnitude > 0.01 and fwd.Unit or Vector3.new(0, 0, -1)
		right = right.Magnitude > 0.01 and right.Unit or Vector3.new(1, 0, 0)

		local moveDir = (fwd * (-moveZ) + right * moveX)

		-- Sprint toggle (LeftShift or RightShift)
		local isSprint = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
		local maxPacing = CombatConfig.Locomotion_PacingSpeedMax or 50.0
		local minPacing = CombatConfig.Locomotion_PacingSpeedMin or 18.5
		local targetSpeed = isSprint and maxPacing or minPacing

		if moveDir.Magnitude > 0.1 then
			moveDir = moveDir.Unit
			lastMoveDir = moveDir

			local targetPosition = activeRootPart.Position + moveDir * 15

			-- Authoritative QuinCore steer: modulates speed, checks 180° skids, turns with AutoRotate
			LocomotionModule.steer(activeQuin, activeHumanoid, activeRootPart, targetPosition, targetSpeed, dt)

			-- Ensure locomotion animation is playing
			local desiredAnim = isSprint and "Movement.Run" or "Movement.WalkConfident"
			if not AnimationModule.isPlaying(activeHumanoid, desiredAnim) then
				AnimationModule.stop(activeHumanoid, "Movement.Idle", 0.15)
				AnimationModule.playConfig(activeHumanoid, desiredAnim)
			end
		else
			-- Authoritative QuinCore brake: smooth deceleration, slide follow-through, stops run, ensures idle
			LocomotionModule.brake(activeQuin, activeHumanoid, activeRootPart, dt)
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

	if activeQuin and activeHumanoid and activeRootPart then
		LocomotionModule.brake(activeQuin, activeHumanoid, activeRootPart, 0.1)
	end

	shared.PlayerControlledQuin = nil
	_G.PlayerControlledQuin = nil
	activeQuin = nil
	activeHumanoid = nil
	activeRootPart = nil

	-- Update button UI
	toggleBtn.Text = "▶ Play As Quin (P)"
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
			toggleBtn.Text = "▶ Play As Quin (P)"
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

	-- Space: Ballistic Jump (Rule 6: single impulse, 88% landing retention)
	if input.KeyCode == Enum.KeyCode.Space and not gp then
		local currentVel = activeRootPart.AssemblyLinearVelocity
		local fwdSpeed = math.max(Vector3.new(currentVel.X, 0, currentVel.Z).Magnitude, 38.0)
		LocomotionModule.jump(activeQuin, activeHumanoid, activeRootPart, 8.0, fwdSpeed, "jump")

	-- C: Athletic Ground Slide
	elseif input.KeyCode == Enum.KeyCode.C and not gp then
		LocomotionModule.slide(activeQuin, activeHumanoid, activeRootPart, lastMoveDir, 0.42)

	-- Q or E: Dash burst
	elseif (input.KeyCode == Enum.KeyCode.Q or input.KeyCode == Enum.KeyCode.E) and not gp then
		local dashTarget = activeRootPart.Position + lastMoveDir * 35
		LocomotionModule.dash(activeQuin, activeHumanoid, activeRootPart, dashTarget, 35)
	end
end)

print("[PlayerQuinController] Initialized. Press 'P' or click 'Play As Quin' to hop in.")
