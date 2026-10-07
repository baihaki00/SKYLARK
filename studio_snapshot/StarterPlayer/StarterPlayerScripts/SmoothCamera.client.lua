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

-- === BODY BOUNCE IN THE ORBIT CAMERA (pass 25) ===
-- First person rides the head bone, so it bounces with every step; the orbit camera tracked the
-- root part and was perfectly level. It now follows the hips bone's own up-and-down (the stride
-- of the walk / run clip), measured against a slowly-adapting rest height so posture changes
-- (crouch, landing) don't shift the camera for long.
local bodyBobScale = 0.85          -- share of the hips' vertical motion the orbit camera follows
local bodyBobMax = 1.6             -- studs either way
local bodyBobRest = nil
local bodyBobSmoothed = 0
local bodyBobModel = nil

-- === FOLLOW LAG ON THE QUIN THE PLAYER PILOTS ===
-- The orbit was locked dead-centre on the root: running sideways or cutting across, the body never
-- moved on the screen, the world slid past it ("the camera is locked to the body"), and a jump
-- left the body where it was while the floor dropped away. On the Quin the player pilots, the
-- camera now follows its focus with a lag, capped, so the body moves across the view and the view
-- catches up. Spectating an AI Quin keeps the dead-centre framing.
local pilotFollowRate = 4.0        -- 1/s: how fast the view catches up sideways and in depth
local pilotFollowRateUp = 6.0      -- 1/s: ... and up and down (a jump shows as a jump)
local pilotFollowMaxSide = 5.0     -- studs the body may be off-centre sideways
local pilotFollowMaxDepth = 3.0    -- studs it may pull ahead of / drop behind the focus
local pilotFollowMaxUp = 4.0       -- studs it may rise above / fall below the focus

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

-- Fly Spectator is the default (pass 24): the game opens in the free camera above the arena; the
-- avatar is parked, hidden and still. B walks as the avatar, R (or B again) flies.
local cameraMode = "FREEFLY"
shared.SpectatorState = { Mode = "FREEFLY" }
local playerSpawnObj = findSpawnLocation()
local cameraPos = playerSpawnObj and (playerSpawnObj.Position + Vector3.new(0, 15, 30)) or Vector3.new(161, 159, -722.5)
local yaw = 0
local pitch = -15.0

-- Orbit internals
local smoothYaw, smoothPitch = yaw, pitch
local targetDistance = 18
local currentDistance = targetDistance
local smoothedTargetPos = nil
local lastControlledQuin = nil

local isLeftMouseDown = false
local isRightMouseDown = false
local isToggleLocked = false

-- === MOUSE CONTROLS ===
-- Mouse look (pass 24): in the free camera and while spectating or playing a Quin the view follows
-- the mouse with no button held (it needed a held button or L). The middle mouse button (or L)
-- frees the cursor to click buttons and locks it again; the cursor is also free while a menu
-- window is open (Quin Manager, Arena System) or a text box has focus.
local cursorFree = false
local lastCameraMode = nil

local function menuOpen()
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	if not playerGui then return false end
	local lab = playerGui:FindFirstChild("AnimationLabUI")
	local labFrame = lab and lab.Enabled and lab:FindFirstChild("MainFrame")
	if labFrame and labFrame.Visible then return true end
	local arena = playerGui:FindFirstChild("ArenaOrchestratorUI")
	local arenaWindow = arena and arena.Enabled and arena:FindFirstChild("ArenaMainWindow", true)
	if arenaWindow and arenaWindow:IsA("GuiObject") and arenaWindow.Visible then return true end
	return false
end

local function lookActive()
	return cameraMode ~= "DEFAULT" and not cursorFree and not menuOpen() and UserInputService:GetFocusedTextBox() == nil
end

-- Re-asserted every frame: Roblox's own scripts reset MouseBehavior
local function updateMouseBehavior()
	if cameraMode == "DEFAULT" then return end
	if lookActive() then
		if UserInputService.MouseBehavior ~= Enum.MouseBehavior.LockCenter then
			UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
		end
		UserInputService.MouseIconEnabled = false
	else
		if UserInputService.MouseBehavior ~= Enum.MouseBehavior.Default then
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		end
		UserInputService.MouseIconEnabled = true
	end
end

local function lockMouse()
	cursorFree = false
	updateMouseBehavior()
end

local function unlockMouse()
	cursorFree = true
	isToggleLocked = false
	isLeftMouseDown = false
	isRightMouseDown = false
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	UserInputService.MouseIconEnabled = true
end

-- === AVATAR WHILE NOT WALKING (pass 24) ===
-- Outside DEFAULT the avatar is parked: hidden for this player and its controls off, so WASD flies
-- the camera instead of also walking the body. While a Quin is possessed PlayerQuinController owns
-- the controls and the costume, so this leaves them alone.
local defaultControls = nil
local function getDefaultControls()
	if defaultControls then return defaultControls end
	local playerScripts = player:FindFirstChild("PlayerScripts")
	local playerModule = playerScripts and playerScripts:FindFirstChild("PlayerModule")
	if playerModule then
		local ok, module = pcall(require, playerModule)
		if ok and module and module.GetControls then
			defaultControls = module:GetControls()
		end
	end
	return defaultControls
end

local function isPossessing()
	local quin = shared.PlayerControlledQuin or _G.PlayerControlledQuin
	return quin ~= nil and quin.Parent ~= nil
end

local avatarApplied = nil -- last applied state (true = walking avatar)
local function applyAvatarState(active)
	if isPossessing() then avatarApplied = nil return end
	local character = player.Character
	if character and character:GetAttribute("IsCostume") == true then return end
	if avatarApplied ~= active then
		avatarApplied = active
		local controls = getDefaultControls()
		if controls then
			if active then controls:Enable() else controls:Disable() end
		end
		if active and character then
			for _, d in ipairs(character:GetDescendants()) do
				if d:IsA("BasePart") or d:IsA("Decal") then d.LocalTransparencyModifier = 0 end
			end
		end
	end
	-- hidden every frame while parked: a respawned body loads its parts after CharacterAdded, and
	-- Roblox's transparency controller writes the modifier too
	if not active and character then
		for _, d in ipairs(character:GetDescendants()) do
			if (d:IsA("BasePart") or d:IsA("Decal")) and d.LocalTransparencyModifier < 1 then
				d.LocalTransparencyModifier = 1
			end
		end
	end
end
player.CharacterAdded:Connect(function()
	avatarApplied = nil -- a new body: controls applied again
end)

-- === FIRST PERSON WHEN ZOOMED IN (Play As Quin, pass 24) ===
-- Scrolling in past the closest orbit zoom puts the camera at the possessed Quin's eyes and hides
-- its body for this player (LocalTransparencyModifier); scrolling out, releasing or dying brings
-- the orbit and the body back.
local firstPerson = false
local fpEye = nil
local hiddenBody = nil -- { model = Model, parts = { BasePart | Decal } }

local function showBody()
	if not hiddenBody then return end
	for _, d in ipairs(hiddenBody.parts) do
		if d.Parent then d.LocalTransparencyModifier = 0 end
	end
	if hiddenBody.conn then hiddenBody.conn:Disconnect() end
	hiddenBody = nil
end

local function hideBody(model)
	if hiddenBody and hiddenBody.model ~= model then showBody() end
	if not hiddenBody then
		hiddenBody = { model = model, parts = {} }
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") or d:IsA("Decal") then table.insert(hiddenBody.parts, d) end
		end
		hiddenBody.conn = model.DescendantAdded:Connect(function(d)
			if d:IsA("BasePart") or d:IsA("Decal") then table.insert(hiddenBody.parts, d) end
		end)
	end
	-- (every frame: Roblox's transparency controller also writes these)
	for _, d in ipairs(hiddenBody.parts) do
		if d.Parent then d.LocalTransparencyModifier = 1 end
	end
end

local function leaveFirstPerson()
	if firstPerson then
		firstPerson = false
		fpEye = nil
		targetDistance = minZoom + 1.5
		currentDistance = minZoom
	end
	showBody()
end

-- === STREAMING AROUND THE CAMERA (pass 24) ===
-- StreamingEnabled streams the world around the character, which the free camera leaves behind
-- (and after a release there is no character at all): the camera position is sent to the server
-- (CameraFocusServer), which moves this player's ReplicationFocus with it.
local lastFocusSend = 0
local focusSent = false
local function sendStreamFocus(position)
	local event = game:GetService("ReplicatedStorage"):FindFirstChild("CameraFocus")
	if not event then return end
	event:FireServer(position)
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
			-- Any recognized menu or HUD ScreenGui
			local screen = obj:FindFirstAncestorWhichIsA("ScreenGui")
			if screen then
				local sName = screen.Name
				if sName == "ArenaOrchestratorUI" or sName == "AnimationLabUI" 
					or sName == "QuinMenuUI" or sName == "QuinDebugGui" 
					or sName == "PlayAsQuinGui" or sName == "JumpDebugUI" then
					return true
				end
			end
			-- Explicit name / ancestor checks
			if obj:FindFirstAncestor("ArenaOrchestratorUI") or obj.Name == "ArenaOrchestratorUI" or obj.Name == "ArenaMainWindow" then
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
			-- Play As Quin UI
			if obj:FindFirstAncestor("PlayAsQuinGui") or obj.Name == "PlayAsQuinGui" then
				return true
			end
			-- QuinMenuUI
			if obj:FindFirstAncestor("QuinMenuUI") or obj.Name == "QuinMenuUI" then
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

-- (the look lock is re-asserted every frame in the render loop: updateMouseBehavior)

-- Check active spectated Quin (ONLY returns AI Quin or explicitly possessed Quin, NEVER player avatar)
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

	-- Hotkey B toggles the free camera from any state (F flies the body: TheArchitectCode)
	if input.KeyCode == Enum.KeyCode.B and not gp then
		if cameraMode == "FREEFLY" then
			cameraMode = "DEFAULT"
			shared.SpectatorState.Mode = cameraMode
			unlockMouse()
			print("[SmoothCamera] Freefly disabled -> Returned to default player avatar.")
		else
			cameraMode = "FREEFLY"
			shared.SpectatorState.Mode = cameraMode
			cameraPos = Camera.CFrame.Position
			local look = Camera.CFrame.LookVector
			yaw = math.deg(math.atan2(-look.X, -look.Z))
			pitch = math.deg(math.asin(math.clamp(look.Y, -1, 1)))
			smoothYaw = yaw
			smoothPitch = pitch
			shared.SpectatedQuin = nil
			workspace:SetAttribute("SpectatedQuin", "")
			lockMouse()
			print("[SmoothCamera] Entered Freefly mode.")
		end
		return
	end

	-- Hotkey R: back to the free camera (Fly Spectator) from anything
	if input.KeyCode == Enum.KeyCode.R and not gp then
		if cameraMode ~= "FREEFLY" then
			cameraMode = "FREEFLY"
			shared.SpectatorState.Mode = cameraMode
			cameraPos = Camera.CFrame.Position
			local look = Camera.CFrame.LookVector
			yaw = math.deg(math.atan2(-look.X, -look.Z))
			pitch = math.deg(math.asin(math.clamp(look.Y, -1, 1)))
			smoothYaw = yaw
			smoothPitch = pitch
		end
		shared.SpectatedQuin = nil
		_G.SpectatedQuin = nil
		workspace:SetAttribute("SpectatedQuin", "")
		lockMouse()
		print("[SmoothCamera] Fly Spectator.")
		return
	end

	-- In DEFAULT avatar mode, let Roblox handle default mouse/input
	if cameraMode == "DEFAULT" then
		return
	end

	-- Middle mouse (or L): free the cursor to click buttons / lock it again for mouse look
	if input.UserInputType == Enum.UserInputType.MouseButton3 or (input.KeyCode == Enum.KeyCode.L and not gp) then
		if cursorFree then
			lockMouse()
		else
			unlockMouse()
		end

	-- Mouse Unlock keys
	elseif input.KeyCode == Enum.KeyCode.Tab or input.KeyCode == Enum.KeyCode.Escape then
		unlockMouse()
	end
end)

-- (no hold-to-look: nothing to release on InputEnded)

-- Scroll wheel
UserInputService.InputChanged:Connect(function(input, gp)
	if gp then return end
	if cameraMode == "DEFAULT" then return end
	if input.UserInputType == Enum.UserInputType.MouseWheel then
		if cameraMode == "QUIN_SPECTATE" then
			local zoomingIn = input.Position.Z > 0
			if firstPerson then
				if not zoomingIn then
					leaveFirstPerson()
				end
			elseif zoomingIn and targetDistance <= minZoom + 0.01 and isPossessing() then
				firstPerson = true
				fpEye = nil
			else
				targetDistance = math.clamp(targetDistance - input.Position.Z * zoomSpeed, minZoom, maxZoom)
			end
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

	-- Check if a Quin is selected from the HUD or player possessed
	local targetHRP, quinModel = getActiveSpectatedQuin()

	-- First person only on the Quin this player is playing
	if firstPerson and (not quinModel or quinModel ~= (shared.PlayerControlledQuin or _G.PlayerControlledQuin)) then
		leaveFirstPerson()
	end
	applyAvatarState(cameraMode == "DEFAULT" and not targetHRP)
	local nowClock = os.clock()
	if cameraMode ~= "DEFAULT" and not isPossessing() then
		if nowClock - lastFocusSend > 0.5 then
			lastFocusSend = nowClock
			focusSent = true
			sendStreamFocus(Camera.CFrame.Position)
		end
	elseif focusSent and not isPossessing() then
		focusSent = false
		sendStreamFocus(nil)
	end
	if targetHRP then
		if cameraMode ~= "QUIN_SPECTATE" then
			cameraMode = "QUIN_SPECTATE"
			shared.SpectatorState.Mode = cameraMode
			if (shared.PlayerControlledQuin or quinModel == player.Character) and lastControlledQuin ~= quinModel then
				lastControlledQuin = quinModel
				targetDistance = 14
				pitch = -12
				local look = targetHRP.CFrame.LookVector
				yaw = math.deg(math.atan2(-look.X, -look.Z))
				smoothYaw = yaw
				smoothPitch = pitch
			end
		end
	elseif cameraMode == "QUIN_SPECTATE" then
		-- the spectated Quin is gone (died, released): back to the free camera where the view is
		cameraMode = "FREEFLY"
		shared.SpectatorState.Mode = cameraMode
		cameraPos = Camera.CFrame.Position
		local look = Camera.CFrame.LookVector
		yaw = math.deg(math.atan2(-look.X, -look.Z))
		pitch = math.deg(math.asin(math.clamp(look.Y, -1, 1)))
		smoothYaw = yaw
		smoothPitch = pitch
	end
	-- entering any flying / spectating mode starts with mouse look on
	if cameraMode ~= lastCameraMode then
		if cameraMode ~= "DEFAULT" and lastCameraMode ~= nil then
			cursorFree = false
		end
		lastCameraMode = cameraMode
		Camera:SetAttribute("SpectatorMode", cameraMode) -- (for tests and other scripts)
	end
	Camera:SetAttribute("FirstPerson", firstPerson or nil)

	-- If in DEFAULT avatar mode, restore Roblox Custom camera and let player control character freely
	if cameraMode == "DEFAULT" then
		if Camera.CameraType ~= Enum.CameraType.Custom then
			Camera.CameraType = Enum.CameraType.Custom
		end
		if player.Character then
			local hum = player.Character:FindFirstChildOfClass("Humanoid")
			if hum and Camera.CameraSubject ~= hum then
				Camera.CameraSubject = hum
			end
		end
		if math.abs(currentCamFov - baseFOV) > 0.05 then
			currentCamFov = currentCamFov + (baseFOV - currentCamFov) * (1 - math.exp(-8.0 * dt))
			Camera.FieldOfView = currentCamFov
		end
		return
	end

	Camera.CameraType = Enum.CameraType.Scriptable

	-- Mouse rotation (Continuous, unconstrained 360-degree rotation): follows the mouse whenever
	-- the cursor is not freed (pass 24)
	updateMouseBehavior()
	local isHoldingLook = lookActive()
	if isHoldingLook then
		local delta = UserInputService:GetMouseDelta()
		yaw = yaw - delta.X * flySensitivity
		pitch = math.clamp(pitch - delta.Y * flySensitivity, -85, 85)
	elseif cameraMode == "QUIN_SPECTATE" and targetHRP then
		-- GTA V / Watch Dogs 2 Dynamic Auto-Follow Yaw:
		-- Only gently track behind character travel direction when moving forward relative to the camera.
		-- During pure strafes (A/D) or reverse, freeze auto-follow yaw so the camera never spirals or drifts off-center.
		local curVel = targetHRP.AssemblyLinearVelocity
		local flatVel = Vector3.new(curVel.X, 0, curVel.Z)
		local camLook = Camera.CFrame.LookVector
		local fwdCam = Vector3.new(camLook.X, 0, camLook.Z)
		if fwdCam.Magnitude > 0.01 and flatVel.Magnitude > 6.0 then
			local forwardDot = flatVel.Unit:Dot(fwdCam.Unit)
			if forwardDot > 0.65 then
				local moveHeading = math.deg(math.atan2(-flatVel.X, -flatVel.Z))
				local diff = (moveHeading - yaw) % 360
				if diff > 180 then diff = diff - 360 end
				yaw = yaw + diff * (1 - math.exp(-3.5 * dt))
			end
		end
	end
	-- Where the mouse has turned the view to, before the view's own easing: a piloted Quin is
	-- steered by it (PilotClient). Steered by the eased view, every mouse turn reached the Quin
	-- ~0.1 s late.
	shared.CameraTargetYaw = cameraMode ~= "FREEFLY" and yaw or nil

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

	elseif firstPerson and quinModel and targetHRP then
		-- === FIRST PERSON (possessed Quin, zoomed all the way in) ===
		-- Eyes at the head bone, a little forward; the view turns with the mouse, not with the
		-- head's animation (head bob and snaps would be sickening)
		local head = quinModel:FindFirstChild("mixamorig:Head", true)
		-- the same smooth turning as the orbit camera (it turned 1:1 with the mouse)
		local rotAlpha = 1 - math.exp(-orbitSmoothness * dt)
		-- (straight at the mouse's yaw, not the shortest way round: a fast flick put the mouse more
		-- than 180 degrees ahead of the eased view, the shortest way flipped, and the view stalled
		-- or swung back. Every place that sets yaw outright sets smoothYaw with it.)
		smoothYaw = smoothYaw + (yaw - smoothYaw) * rotAlpha
		smoothPitch = smoothPitch + (pitch - smoothPitch) * rotAlpha
		local rotCF = CFrame.Angles(0, math.rad(smoothYaw), 0) * CFrame.Angles(math.rad(smoothPitch), 0, 0)
		local flatLook = Vector3.new(rotCF.LookVector.X, 0, rotCF.LookVector.Z)
		local eye
		if head and head:IsA("Bone") then
			eye = head.TransformedWorldCFrame.Position
		elseif head and head:IsA("BasePart") then
			eye = head.Position
		else
			eye = targetHRP.Position + Vector3.new(0, 2.6, 0)
		end
		eye += Vector3.new(0, 0.15, 0) + (flatLook.Magnitude > 0.01 and flatLook.Unit * 0.3 or Vector3.zero)
		-- (the head's bounce is kept, eased a little like the orbit's position)
		fpEye = fpEye and fpEye:Lerp(eye, 1 - math.exp(-posSmoothness * dt)) or eye
		currentDistance = minZoom
		if math.abs(currentCamFov - baseFOV) > 0.05 then
			currentCamFov = currentCamFov + (baseFOV - currentCamFov) * (1 - math.exp(-8.0 * dt))
			Camera.FieldOfView = currentCamFov
		end
		hideBody(quinModel)
		Camera.CFrame = CFrame.new(fpEye) * rotCF
		cameraPos = fpEye

	else
		-- === QUIN SPECTATE (ORBIT WITH SUSPENSION & DYNAMIC GYRO) ===
		local rotAlpha = 1 - math.exp(-orbitSmoothness * dt)
		local zoomAlpha = 1 - math.exp(-10 * dt)
		local posAlpha = 1 - math.exp(-posSmoothness * dt)

		-- Shortest-path circular angular lerp: ZERO degree boundaries, ZERO snap-backs
		-- (straight at the mouse's yaw, not the shortest way round: a fast flick put the mouse more
		-- than 180 degrees ahead of the eased view, the shortest way flipped, and the view stalled
		-- or swung back. Every place that sets yaw outright sets smoothYaw with it.)
		smoothYaw = smoothYaw + (yaw - smoothYaw) * rotAlpha
		smoothPitch = smoothPitch + (pitch - smoothPitch) * rotAlpha
		currentDistance += (targetDistance - currentDistance) * zoomAlpha

		local bobY = 0
		if bodyBobScale > 0 and quinModel then
			if quinModel ~= bodyBobModel then
				bodyBobModel = quinModel
				bodyBobRest = nil
				bodyBobSmoothed = 0
			end
			local hips = getHipsBone(quinModel)
			local hipsY = hips and (hips:IsA("Bone") and hips.TransformedWorldCFrame.Position.Y or (hips:IsA("BasePart") and hips.Position.Y))
			if hipsY then
				local rel = hipsY - targetHRP.Position.Y
				bodyBobRest = bodyBobRest and (bodyBobRest + (rel - bodyBobRest) * (1 - math.exp(-0.8 * dt))) or rel
				local want = math.clamp(rel - bodyBobRest, -bodyBobMax, bodyBobMax) * bodyBobScale
				bodyBobSmoothed = bodyBobSmoothed + (want - bodyBobSmoothed) * (1 - math.exp(-18 * dt))
				bobY = bodyBobSmoothed
			end
		end
		local rawTargetPos = targetHRP.Position + Vector3.new(0, 2.5 + bobY, 0)
		-- Spectating: the focus stays dead-centre on the root (no drift to the screen edge on
		-- diagonal runs). Piloting: it follows with a capped lag (pilotFollow*, above).
		if isPossessing() and smoothedTargetPos and lastTrackedHRP == targetHRP and pilotFollowRate > 0 then
			local a = 1 - math.exp(-pilotFollowRate * dt)
			local aUp = 1 - math.exp(-pilotFollowRateUp * dt)
			local p = smoothedTargetPos:Lerp(rawTargetPos, a)
			p = Vector3.new(p.X, smoothedTargetPos.Y + (rawTargetPos.Y - smoothedTargetPos.Y) * aUp, p.Z)
			local turn = CFrame.Angles(0, math.rad(smoothYaw), 0)
			local side, ahead = turn.RightVector, turn.LookVector
			local off = p - rawTargetPos
			smoothedTargetPos = rawTargetPos
				+ side * math.clamp(off:Dot(side), -pilotFollowMaxSide, pilotFollowMaxSide)
				+ ahead * math.clamp(off:Dot(ahead), -pilotFollowMaxDepth, pilotFollowMaxDepth)
				+ Vector3.new(0, math.clamp(off.Y, -pilotFollowMaxUp, pilotFollowMaxUp), 0)
		else
			smoothedTargetPos = rawTargetPos
		end
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
