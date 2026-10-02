--// CameraMotionBlur
-- Camera motion blur. Roblox has no per-pixel motion blur, so this is the usual stand-in: a
-- BlurEffect on the camera whose size follows how fast the view turns and travels. Quick pans,
-- whip turns and fast flights smear; a still or slowly drifting view stays sharp.
-- Tuning: CombatConfig.MotionBlur_*. Live switch: Workspace attribute MotionBlur (false = off)
-- and MotionBlurScale (multiplies the strength).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local CombatConfig = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("CombatConfig"))

local CUT_DISTANCE = 40 -- studs in one frame: a camera cut (spectate switch, teleport), not motion
local CUT_ANGLE = math.rad(60) -- likewise for rotation

local blur = Instance.new("BlurEffect")
blur.Name = "CameraMotionBlur"
blur.Size = 0
blur.Enabled = false

local lastCFrame = nil
local current = 0

local function ramp(value, startAt, fullAt)
	return math.clamp((value - startAt) / math.max(fullAt - startAt, 1e-3), 0, 1)
end

RunService:BindToRenderStep("CameraMotionBlur", Enum.RenderPriority.Last.Value, function(dt)
	local camera = workspace.CurrentCamera
	if not camera then return end
	if blur.Parent ~= camera then
		blur.Parent = camera
	end

	local liveSwitch = workspace:GetAttribute("MotionBlur")
	local enabled = liveSwitch ~= false and (liveSwitch == true or CombatConfig.MotionBlur_Enabled ~= false)
	local cf = camera.CFrame
	local target = 0
	if enabled and lastCFrame and dt > 0 then
		local moved = (cf.Position - lastCFrame.Position).Magnitude
		local _, angle = (lastCFrame.Rotation:Inverse() * cf.Rotation):ToAxisAngle()
		angle = math.abs(angle)
		if moved < CUT_DISTANCE and angle < CUT_ANGLE then
			local turnRate = math.deg(angle) / dt
			local speed = moved / dt
			local amount = math.max(
				ramp(turnRate, CombatConfig.MotionBlur_TurnStart or 90, CombatConfig.MotionBlur_TurnFull or 540),
				ramp(speed, CombatConfig.MotionBlur_SpeedStart or 60, CombatConfig.MotionBlur_SpeedFull or 200)
			)
			local scale = workspace:GetAttribute("MotionBlurScale")
			target = amount * (CombatConfig.MotionBlur_MaxSize or 8) * (type(scale) == "number" and scale or 1)
		end
	end
	lastCFrame = cf

	-- quick to smear, slower to clear (an exposure that trails off)
	local rate = target > current and (CombatConfig.MotionBlur_Attack or 20) or (CombatConfig.MotionBlur_Release or 8)
	current += (target - current) * (1 - math.exp(-rate * dt))
	if current < 0.3 then
		blur.Enabled = false
	else
		blur.Enabled = true
		blur.Size = current
	end
end)
