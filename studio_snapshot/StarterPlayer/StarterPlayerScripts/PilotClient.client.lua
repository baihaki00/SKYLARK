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
		send("action", "Jump")
	elseif input.KeyCode == Enum.KeyCode.C then
		send("action", "Slide")
	elseif input.KeyCode == Enum.KeyCode.Q or input.KeyCode == Enum.KeyCode.E then
		send("action", "Dash")
	elseif input.KeyCode == Enum.KeyCode.Z then
		walkMode = not walkMode
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
		send("action", "JumpRelease")
	elseif input.KeyCode == Enum.KeyCode.V and vDownAt then
		local style = (os.clock() - vDownAt >= PJ_HOLD) and 2 or 1
		vDownAt = nil
		local point, name = aim()
		send("pj", style, point, name)
	end
end)
