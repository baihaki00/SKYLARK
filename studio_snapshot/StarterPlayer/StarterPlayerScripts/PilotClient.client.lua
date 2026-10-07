--// PilotClient.client.lua
-- The player's side of the Player Quin match mode: reads the keys and sends them to the server
-- (ReplicatedStorage.PilotInput -> Modules/PilotInput -> States/PilotedState). The server owns
-- and moves the Quin with the same locomotion, strikes and states as an AI Quin; this script only
-- sends what the player asks for. The camera follows the Quin through SmoothCamera (the same
-- orbit as Play As Quin: shared.PlayerControlledQuin).
--
-- Keys: WASD move (camera-relative), hold Shift run, Z walk on/off, left click strike,
-- hold right click guard, Space jump (let go early: a short hop), C slide, Q / E dash,
-- V projectile jump at what the crosshair is on: tap = style 1 (an arc onto it), hold and let go =
-- style 2 (a high launch); in the air, V again dives onto what the crosshair is on then.
-- T lock on to the nearest threat (again: let go), G move the lock to the next one. A locked
-- enemy carries a small marker. A HUD at the bottom middle shows health, mana and the jump and
-- projectile-jump gauges; a dot marks the middle of the view while in the air or aiming.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local remote = ReplicatedStorage:WaitForChild("PilotInput")

local SEND_INTERVAL = 0.25 -- seconds between repeats of an unchanged move (the server stops a silent Quin after 1 s)
local PJ_HOLD = 0.3 -- seconds V is held for a style 2 (high launch) instead of a style 1 (arc)
local AIM_RANGE = 600

local quin = nil
local walkMode = false
local vDownAt = nil
local spaceDownAt = nil -- (the HUD's jump gauge)
local lastLookYaw, lastLookPitch, lastLookAt = nil, nil, 0
local lastDir, lastPace, lastSentAt = Vector3.zero, "jog", 0

-- Roblox's default controls must not walk the parked avatar while the keys drive the Quin
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
		if enabled then defaultControls:Enable() else defaultControls:Disable() end
	end
end

local function myQuin()
	local folder = Workspace:FindFirstChild("QuinServer")
	if not folder then return nil end
	for _, q in ipairs(folder:GetChildren()) do
		if q:GetAttribute("PilotedBy") == player.UserId then
			local hum = q:FindFirstChildOfClass("Humanoid")
			if hum and hum.Health > 0 and q:FindFirstChild("HumanoidRootPart") then
				return q
			end
		end
	end
	return nil
end

local function attach(q)
	quin = q
	shared.PilotedQuin = q
	shared.PlayerControlledQuin = q -- (SmoothCamera follows it)
	_G.PlayerControlledQuin = q
	setDefaultControlsEnabled(false)
	walkMode = false
	print("[PilotClient] Piloting " .. q.Name .. " (WASD, Shift run, click strike, hold right click guard, Space, C, Q/E)")
end

local function detach()
	if shared.PlayerControlledQuin == quin then shared.PlayerControlledQuin = nil end
	if _G.PlayerControlledQuin == quin then _G.PlayerControlledQuin = nil end
	if shared.PilotedQuin == quin then shared.PilotedQuin = nil end
	quin = nil
	setDefaultControlsEnabled(true)
end

local function send(kind, a, b, c)
	pcall(function() remote:FireServer(kind, a, b, c) end)
end

-- What the crosshair (the middle of the view) is on: a point, and the Quin there if it is one
local function aim()
	local cam = Workspace.CurrentCamera.CFrame
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { quin, player.Character, Workspace:FindFirstChild("PlayerCostumes") }
	local hit = Workspace:Raycast(cam.Position, cam.LookVector * AIM_RANGE, params)
	if not hit then
		return cam.Position + cam.LookVector * AIM_RANGE, nil
	end
	local folder = Workspace:FindFirstChild("QuinServer")
	local model = hit.Instance:FindFirstAncestorOfClass("Model")
	while model and model.Parent ~= folder do
		model = model.Parent and model.Parent:FindFirstAncestorOfClass("Model")
	end
	return hit.Position, model and model.Name or nil
end

-- The lock marker: a small diamond over the locked enemy (only while locked)
local marker = Instance.new("BillboardGui")
marker.Name = "PilotLockMarker"
marker.Size = UDim2.fromOffset(18, 18)
marker.StudsOffsetWorldSpace = Vector3.new(0, 4.2, 0)
marker.AlwaysOnTop = true
marker.Enabled = false
local diamond = Instance.new("Frame")
diamond.Size = UDim2.fromScale(0.7, 0.7)
diamond.Position = UDim2.fromScale(0.15, 0.15)
diamond.Rotation = 45
diamond.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
diamond.BackgroundTransparency = 0.15
diamond.BorderSizePixel = 0
diamond.Parent = marker
marker.Parent = player:WaitForChild("PlayerGui")
RunService.Heartbeat:Connect(function()
	local locked = quin and quin:GetAttribute("PilotLocked") == true
	local name = locked and quin:GetAttribute("PilotFocus")
	local folder = Workspace:FindFirstChild("QuinServer")
	local target = name and folder and folder:FindFirstChild(name)
	local root = target and target:FindFirstChild("HumanoidRootPart")
	marker.Adornee = root or nil -- (unlocked, `root` is false, not nil)
	marker.Enabled = root ~= nil and root ~= false
end)

-- Which Quin is mine (a match spawns it, a death or the match end takes it away)
task.spawn(function()
	while true do
		local current = myQuin()
		if current ~= quin then
			if quin then detach() end
			if current then attach(current) end
		end
		task.wait(0.3)
	end
end)

-- Movement, every frame; sent when it changes and repeated while it lasts
RunService.RenderStepped:Connect(function()
	if not quin then return end
	local x, z = 0, 0
	if not UserInputService:GetFocusedTextBox() then
		if UserInputService:IsKeyDown(Enum.KeyCode.W) or UserInputService:IsKeyDown(Enum.KeyCode.Up) then z -= 1 end
		if UserInputService:IsKeyDown(Enum.KeyCode.S) or UserInputService:IsKeyDown(Enum.KeyCode.Down) then z += 1 end
		if UserInputService:IsKeyDown(Enum.KeyCode.A) or UserInputService:IsKeyDown(Enum.KeyCode.Left) then x -= 1 end
		if UserInputService:IsKeyDown(Enum.KeyCode.D) or UserInputService:IsKeyDown(Enum.KeyCode.Right) then x += 1 end
	end
	local cam = Workspace.CurrentCamera.CFrame
	local fwd = Vector3.new(cam.LookVector.X, 0, cam.LookVector.Z)
	local right = Vector3.new(cam.RightVector.X, 0, cam.RightVector.Z)
	-- (where the mouse has turned the view to, not the eased view: SmoothCamera's target yaw.
	-- Steered by the eased view, every mouse turn reached the Quin ~0.1 s late.)
	local targetYaw = shared.CameraTargetYaw
	if type(targetYaw) == "number" then
		local r = math.rad(targetYaw)
		fwd = Vector3.new(-math.sin(r), 0, -math.cos(r))
		right = Vector3.new(math.cos(r), 0, -math.sin(r))
	end
	fwd = fwd.Magnitude > 0.01 and fwd.Unit or Vector3.new(0, 0, -1)
	right = right.Magnitude > 0.01 and right.Unit or Vector3.new(1, 0, 0)
	local dir = fwd * -z + right * x
	dir = dir.Magnitude > 0.1 and dir.Unit or Vector3.zero

	local pace = "jog"
	if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) or UserInputService:IsKeyDown(Enum.KeyCode.RightShift) then
		pace = "run"
	elseif walkMode then
		pace = "walk"
	end

	local now = os.clock()
	if (dir - lastDir).Magnitude > 0.05 or pace ~= lastPace or now - lastSentAt > SEND_INTERVAL then
		lastDir, lastPace, lastSentAt = dir, pace, now
		send("move", dir, pace)
	end
	-- where the view points (the Quin's head, for everyone else), at most 5 times a second
	local lookYaw = math.deg(math.atan2(cam.LookVector.X, cam.LookVector.Z))
	local lookPitch = math.deg(math.asin(math.clamp(cam.LookVector.Y, -1, 1)))
	if now - lastLookAt > 0.2 and (not lastLookYaw or math.abs((lookYaw - lastLookYaw + 180) % 360 - 180) > 4 or math.abs(lookPitch - lastLookPitch) > 4) then
		lastLookYaw, lastLookPitch, lastLookAt = lookYaw, lookPitch, now
		send("look", lookYaw, lookPitch)
	end
end)

UserInputService.InputBegan:Connect(function(input, gp)
	if not quin or UserInputService:GetFocusedTextBox() then return end
	-- (Space comes in marked as handled: Roblox's own controls keep a jump action bound to it even
	-- while they are disabled, so a jump was never sent)
	if gp and input.KeyCode ~= Enum.KeyCode.Space then return end
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		send("action", "Strike")
	elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
		send("guard", true)
	elseif input.KeyCode == Enum.KeyCode.Space then
		spaceDownAt = os.clock()
		send("action", "Jump")
	elseif input.KeyCode == Enum.KeyCode.C then
		send("action", "Slide")
	elseif input.KeyCode == Enum.KeyCode.Q or input.KeyCode == Enum.KeyCode.E then
		send("action", "Dash")
	elseif input.KeyCode == Enum.KeyCode.Z then
		walkMode = not walkMode
	elseif input.KeyCode == Enum.KeyCode.T then
		send("action", "Lock")
	elseif input.KeyCode == Enum.KeyCode.G then
		send("action", "LockNext")
	elseif input.KeyCode == Enum.KeyCode.V then
		-- in a high launch: dive now; otherwise start timing the press
		if quin:GetAttribute("CurrentState") == "ProjectileJump" and quin:GetAttribute("PJPhase") == "AirborneTimer" then
			local point, name = aim()
			send("dive", point, name)
		else
			vDownAt = os.clock()
		end
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if not quin then return end
	if input.UserInputType == Enum.UserInputType.MouseButton2 then
		send("guard", false)
	elseif input.KeyCode == Enum.KeyCode.Space then
		spaceDownAt = nil
		send("action", "JumpRelease")
	elseif input.KeyCode == Enum.KeyCode.V and vDownAt then
		local style = (os.clock() - vDownAt >= PJ_HOLD) and 2 or 1
		vDownAt = nil
		local point, name = aim()
		send("pj", style, point, name)
	end
end)

-- The HUD (bottom middle): health, mana (with the mark a projectile jump needs), the jump gauge
-- (Space held: a hop fills to a full jump), the projectile-jump gauge (V held: arc, then arc and
-- dive) and the server's note when something asked for is refused (PilotNote). A dot at the middle
-- of the view while in the air or aiming a projectile jump: what the aim is on.
local CombatConfig = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("CombatConfig"))
local PJ_MANA = CombatConfig.ProjectileJumpMinEnergy or 40
local JUMP_FULL = CombatConfig.Locomotion_JumpCutWindow or 0.3 -- held this long a jump is not cut

local hud = Instance.new("ScreenGui")
hud.Name = "PilotHUD"
hud.ResetOnSpawn = false
hud.IgnoreGuiInset = true -- (the dot sits on the camera's centre, where the aim is taken)
hud.DisplayOrder = 5
hud.Enabled = false
hud.Parent = player:WaitForChild("PlayerGui")

local function corner(parent, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end
local function label(parent, text, size, xAlign)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.GothamBold
	l.TextSize = size
	l.TextColor3 = Color3.fromRGB(235, 240, 245)
	l.TextStrokeTransparency = 0.6
	l.TextXAlignment = xAlign or Enum.TextXAlignment.Left
	l.Text = text
	l.Parent = parent
	return l
end
-- A bar: returns its fill frame and its text
local function bar(parent, y, height, color, name)
	local back = Instance.new("Frame")
	back.Name = name
	back.Position = UDim2.new(0, 0, 0, y)
	back.Size = UDim2.new(1, 0, 0, height)
	back.BackgroundColor3 = Color3.fromRGB(14, 18, 26)
	back.BackgroundTransparency = 0.25
	back.BorderSizePixel = 0
	back.Parent = parent
	corner(back, 4)
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.new(1, 0, 1, 0)
	fill.BackgroundColor3 = color
	fill.BorderSizePixel = 0
	fill.Parent = back
	corner(fill, 4)
	local text = label(back, name, 11)
	text.Size = UDim2.new(1, -12, 1, 0)
	text.Position = UDim2.new(0, 6, 0, 0)
	text.ZIndex = 3
	return fill, text, back
end

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.AnchorPoint = Vector2.new(0.5, 1)
panel.Position = UDim2.new(0.5, 0, 1, -22)
panel.Size = UDim2.new(0, 360, 0, 74)
panel.BackgroundTransparency = 1
panel.Parent = hud

local hpFill, hpText = bar(panel, 0, 16, Color3.fromRGB(90, 210, 120), "HP")
local manaFill, manaText, manaBack = bar(panel, 20, 12, Color3.fromRGB(70, 170, 255), "MANA")
manaText.TextSize = 10
-- the mark a projectile jump needs
local manaMark = Instance.new("Frame")
manaMark.Size = UDim2.new(0, 2, 1, 4)
manaMark.Position = UDim2.new(PJ_MANA / (CombatConfig.MaxEnergy or 100), -1, 0, -2)
manaMark.BackgroundColor3 = Color3.fromRGB(255, 200, 80)
manaMark.BorderSizePixel = 0
manaMark.ZIndex = 4
manaMark.Parent = manaBack

local gauges = Instance.new("Frame")
gauges.Position = UDim2.new(0, 0, 0, 38)
gauges.Size = UDim2.new(1, 0, 0, 14)
gauges.BackgroundTransparency = 1
gauges.Parent = panel
local jumpHalf = Instance.new("Frame")
jumpHalf.Size = UDim2.new(0.5, -4, 1, 0)
jumpHalf.BackgroundTransparency = 1
jumpHalf.Parent = gauges
local pjHalf = Instance.new("Frame")
pjHalf.Position = UDim2.new(0.5, 4, 0, 0)
pjHalf.Size = UDim2.new(0.5, -4, 1, 0)
pjHalf.BackgroundTransparency = 1
pjHalf.Parent = gauges
local jumpFill, jumpText = bar(jumpHalf, 0, 14, Color3.fromRGB(235, 240, 245), "JUMP")
local pjFill, pjText = bar(pjHalf, 0, 14, Color3.fromRGB(255, 170, 60), "PJ")
jumpText.TextSize, pjText.TextSize = 10, 10

local note = label(panel, "", 13, Enum.TextXAlignment.Center)
note.Size = UDim2.new(1, 0, 0, 16)
note.Position = UDim2.new(0, 0, 0, 56)
note.TextColor3 = Color3.fromRGB(255, 205, 120)

local dot = Instance.new("Frame")
dot.Name = "AimDot"
dot.AnchorPoint = Vector2.new(0.5, 0.5)
dot.Position = UDim2.fromScale(0.5, 0.5)
dot.Size = UDim2.fromOffset(6, 6)
dot.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
dot.BorderSizePixel = 0
dot.Visible = false
dot.Parent = hud
corner(dot, 3)
local dotStroke = Instance.new("UIStroke")
dotStroke.Color = Color3.fromRGB(0, 0, 0)
dotStroke.Transparency = 0.4
dotStroke.Thickness = 1
dotStroke.Parent = dot

local lastNote, noteAt = nil, 0
local function textColor(dark)
	return dark and Color3.fromRGB(20, 24, 30) or Color3.fromRGB(235, 240, 245)
end
RunService.RenderStepped:Connect(function()
	hud.Enabled = quin ~= nil and quin.Parent ~= nil
	if not hud.Enabled then return end
	local hum = quin:FindFirstChildOfClass("Humanoid")
	if not hum then return end
	local now = os.clock()

	local hp = math.clamp(hum.Health / math.max(hum.MaxHealth, 1), 0, 1)
	hpFill.Size = UDim2.new(hp, 0, 1, 0)
	hpFill.BackgroundColor3 = Color3.fromRGB(230, 70, 60):Lerp(Color3.fromRGB(90, 210, 120), hp)
	hpText.Text = string.format("HP  %d / %d", math.ceil(hum.Health), hum.MaxHealth)

	local energy = quin:GetAttribute("Energy") or 0
	local maxEnergy = CombatConfig.MaxEnergy or 100
	manaFill.Size = UDim2.new(math.clamp(energy / maxEnergy, 0, 1), 0, 1, 0)
	manaText.Text = string.format("MANA  %d", math.floor(energy))

	-- jump: held, a hop fills to a full jump
	local state = hum:GetState()
	local airborne = state == Enum.HumanoidStateType.Freefall or state == Enum.HumanoidStateType.Jumping
	if spaceDownAt then
		local f = math.clamp((now - spaceDownAt) / JUMP_FULL, 0, 1)
		jumpFill.Size = UDim2.new(f, 0, 1, 0)
		jumpText.Text = f >= 1 and "JUMP  FULL" or "JUMP  HOP"
	else
		jumpFill.Size = UDim2.new(0, 0, 1, 0)
		jumpText.Text = airborne and "JUMP  (in the air)" or "JUMP"
	end
	jumpText.TextColor3 = textColor(spaceDownAt ~= nil and (now - spaceDownAt) / JUMP_FULL > 0.5)

	-- projectile jump: held, an arc fills to an arc and dive
	local inPJ = quin:GetAttribute("CurrentState") == "ProjectileJump"
	if vDownAt then
		local f = math.clamp((now - vDownAt) / PJ_HOLD, 0, 1)
		pjFill.Size = UDim2.new(f, 0, 1, 0)
		pjFill.BackgroundColor3 = f >= 1 and Color3.fromRGB(255, 110, 60) or Color3.fromRGB(255, 170, 60)
		pjText.Text = f >= 1 and "PJ  ARC + DIVE" or "PJ  ARC"
	elseif inPJ and quin:GetAttribute("PJPhase") == "AirborneTimer" then
		pjFill.Size = UDim2.new(1, 0, 1, 0)
		pjFill.BackgroundColor3 = Color3.fromRGB(255, 110, 60)
		pjText.Text = "V: DIVE NOW"
	else
		local ready = energy >= PJ_MANA
		pjFill.Size = UDim2.new(ready and 1 or math.clamp(energy / PJ_MANA, 0, 1), 0, 1, 0)
		pjFill.BackgroundColor3 = ready and Color3.fromRGB(110, 90, 60) or Color3.fromRGB(70, 60, 60)
		pjText.Text = inPJ and "PJ  (flying)" or (ready and "PJ  READY" or "PJ  NEEDS MANA")
	end
	pjText.TextColor3 = textColor(false)

	-- the server's note (a refused projectile jump: no mana, nowhere to land, not from the air)
	local text = quin:GetAttribute("PilotNote")
	if text ~= lastNote then
		lastNote, noteAt = text, now
	end
	note.Text = (text and now - noteAt < 2.5) and text or ""

	dot.Visible = airborne or inPJ or vDownAt ~= nil
end)
