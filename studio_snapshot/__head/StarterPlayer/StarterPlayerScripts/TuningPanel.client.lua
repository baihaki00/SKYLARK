--// TuningPanel.client.lua
-- Studio only. F3 opens a panel to tune the body's movement live while piloting a Quin: each row
-- sets a Workspace attribute Tune_<CombatConfig key>, which LocomotionModule.tune reads before the
-- config. The player's machine moves its own Quin (PlayerQuin.ClientMovement), so a change here is
-- felt on it at once. The AI Quins run on the server and keep the config's values. "Print" writes
-- the current values to the Output (to send back and make them the defaults); "Reset" clears them.
-- While the panel is open the cursor is free (SmoothCamera: menuOpen); WASD still drives the Quin.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

if not RunService:IsStudio() then return end

local player = Players.LocalPlayer
local CombatConfig = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("CombatConfig"))

-- key, label, what it does, step, min, max
local ROWS = {
	{ section = "Sharp turns (reversals: W to S, A to D...)" },
	{ "Locomotion_ReversalFlipSpeed", "Flip speed", "studs/s the plant brakes down to before heading straight back the other way", 1, 0, 20 },
	{ "Locomotion_ReversalTurnRate", "Turn-round rate", "rad/s the body turns round on the spot (22 = a half turn in 0.15 s)", 1, 4, 40 },
	{ "Locomotion_ReversalBrake", "Plant brake", "studs/s^2 braking before the pivot (higher: less sliding on)", 20, 40, 800 },
	{ "Locomotion_ReversalMinSpeed", "Reversal from speed", "studs/s above which a reversal plants and pivots", 1, 0, 20 },
	{ "Locomotion_ReversalDriveOutAccel", "Drive-out accel", "studs/s^2 out of the pivot, for a moment", 10, 40, 500 },
	{ "Locomotion_ReversalTurnClipRate", "Turn clip rate", "playback rate of the 180 turn animation (lower: slower)", 0.1, 0.5, 3 },
	{ "Locomotion_ReversalTurnClipMinSpeedShare", "Turn clip from speed", "share of top speed a turnaround needs for the turn animation", 0.05, 0, 1 },
	{ "Locomotion_FacingMaxTurnRate", "Body facing max turn", "rad/s the body may turn to face its run", 2, 6, 60 },
	{ section = "Cornering (curves, mouse turns)" },
	{ "Locomotion_LateralGrip", "Lateral grip", "studs/s^2 sideways: how tight a run can curve", 20, 40, 800 },
	{ "Locomotion_TurnRateFast", "Turn rate at a sprint", "rad/s cap at full speed", 0.5, 1, 20 },
	{ "Locomotion_TurnRateSlow", "Turn rate when slow", "rad/s cap at walking pace", 1, 2, 30 },
	{ "Locomotion_GroundTurnResponse", "Turn response", "how quickly the heading chases the input", 1, 2, 40 },
	{ section = "Speed up / slow down" },
	{ "Locomotion_Acceleration", "Acceleration", "studs/s^2 getting up to speed", 10, 20, 400 },
	{ "Locomotion_BrakingDeceleration", "Braking", "studs/s^2 slowing down", 10, 20, 600 },
	{ section = "In the air" },
	{ "Locomotion_AirAcceleration", "Air control", "studs/s^2 the body can change its flight", 10, 0, 300 },
	{ "Locomotion_AirDriftSpeed", "Air drift speed", "studs/s it may drift to from a standing jump", 2, 0, 40 },
}

-- What the body uses when nothing is set here (the agile value when the agile body is on)
local function default(key)
	if CombatConfig.Body_Agile ~= false and CombatConfig[key .. "_Agile"] ~= nil then
		return CombatConfig[key .. "_Agile"]
	end
	return CombatConfig[key]
end
local function current(key)
	local live = Workspace:GetAttribute("Tune_" .. key)
	if live ~= nil then return live end
	return default(key)
end
local function fmt(v)
	if v == nil then return "-" end
	if math.abs(v - math.round(v)) < 1e-6 then return tostring(math.round(v)) end
	return (string.format("%.2f", v):gsub("0$", "")) -- (0.85 shows as 0.85, 7.5 as 7.5)
end

-- === UI ===
local gui = Instance.new("ScreenGui")
gui.Name = "TuningPanel"
gui.ResetOnSpawn = false
gui.DisplayOrder = 50
gui.Enabled = false
gui.Parent = player:WaitForChild("PlayerGui")

local frame = Instance.new("Frame")
frame.Name = "Window"
frame.AnchorPoint = Vector2.new(0, 0.5)
frame.Position = UDim2.new(0, 16, 0.5, 20) -- (left: the right edge has the arena buttons)
frame.Size = UDim2.new(0, 460, 0, 600)
frame.BackgroundColor3 = Color3.fromRGB(16, 20, 28)
frame.BackgroundTransparency = 0.08
frame.BorderSizePixel = 0
frame.Parent = gui
Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 10)

local function text(parent, str, size, bold, color)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = bold and Enum.Font.GothamBold or Enum.Font.Gotham
	l.TextSize = size
	l.TextColor3 = color or Color3.fromRGB(230, 236, 242)
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextWrapped = true
	l.Text = str
	l.Parent = parent
	return l
end
local function button(parent, str, w)
	local b = Instance.new("TextButton")
	b.Size = UDim2.new(0, w, 0, 26)
	b.BackgroundColor3 = Color3.fromRGB(40, 48, 64)
	b.TextColor3 = Color3.fromRGB(235, 240, 245)
	b.Font = Enum.Font.GothamBold
	b.TextSize = 14
	b.Text = str
	b.AutoButtonColor = true
	b.Parent = parent
	Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
	return b
end

local title = text(frame, "MOVEMENT TUNING  (F3)", 15, true, Color3.fromRGB(0, 210, 255))
title.Position = UDim2.new(0, 14, 0, 10)
title.Size = UDim2.new(1, -28, 0, 20)
local sub = text(frame, "Your Quin only, live. Changed values are orange. Print sends them to the Output.", 11, false, Color3.fromRGB(150, 160, 175))
sub.Position = UDim2.new(0, 14, 0, 30)
sub.Size = UDim2.new(1, -28, 0, 16)

local list = Instance.new("ScrollingFrame")
list.Position = UDim2.new(0, 8, 0, 52)
list.Size = UDim2.new(1, -16, 1, -96)
list.BackgroundTransparency = 1
list.BorderSizePixel = 0
list.ScrollBarThickness = 6
list.AutomaticCanvasSize = Enum.AutomaticSize.Y
list.CanvasSize = UDim2.new(0, 0, 0, 0)
list.Parent = frame
local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 4)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = list

local valueLabels = {}
local function refresh()
	for key, label in pairs(valueLabels) do
		local live = Workspace:GetAttribute("Tune_" .. key)
		label.Text = fmt(current(key))
		label.TextColor3 = live ~= nil and Color3.fromRGB(255, 170, 60) or Color3.fromRGB(230, 236, 242)
	end
end

for order, row in ipairs(ROWS) do
	if row.section then
		local s = text(list, row.section, 12, true, Color3.fromRGB(0, 210, 255))
		s.Size = UDim2.new(1, -10, 0, 22)
		s.LayoutOrder = order
	else
		local key, label, hint, step, lo, hi = row[1], row[2], row[3], row[4], row[5], row[6]
		local r = Instance.new("Frame")
		r.Size = UDim2.new(1, -10, 0, 48)
		r.BackgroundColor3 = Color3.fromRGB(24, 30, 42)
		r.BorderSizePixel = 0
		r.LayoutOrder = order
		r.Parent = list
		Instance.new("UICorner", r).CornerRadius = UDim.new(0, 6)
		local name = text(r, label, 13, true)
		name.Position = UDim2.new(0, 8, 0, 3)
		name.Size = UDim2.new(1, -150, 0, 16)
		local h = text(r, hint .. "  (default " .. fmt(default(key)) .. ")", 10, false, Color3.fromRGB(140, 150, 165))
		h.Position = UDim2.new(0, 8, 0, 20)
		h.Size = UDim2.new(1, -150, 0, 26)
		h.TextYAlignment = Enum.TextYAlignment.Top
		local minus = button(r, "-", 30)
		minus.Position = UDim2.new(1, -138, 0, 11)
		local value = text(r, "", 14, true)
		value.TextXAlignment = Enum.TextXAlignment.Center
		value.Position = UDim2.new(1, -104, 0, 11)
		value.Size = UDim2.new(0, 60, 0, 26)
		local plus = button(r, "+", 30)
		plus.Position = UDim2.new(1, -40, 0, 11)
		valueLabels[key] = value
		local function nudge(dir)
			local v = math.clamp((current(key) or 0) + dir * step, lo, hi)
			v = math.round(v / step) * step
			Workspace:SetAttribute("Tune_" .. key, v)
			refresh()
		end
		minus.MouseButton1Click:Connect(function() nudge(-1) end)
		plus.MouseButton1Click:Connect(function() nudge(1) end)
	end
end

local bar = Instance.new("Frame")
bar.Position = UDim2.new(0, 8, 1, -38)
bar.Size = UDim2.new(1, -16, 0, 30)
bar.BackgroundTransparency = 1
bar.Parent = frame
local barLayout = Instance.new("UIListLayout")
barLayout.FillDirection = Enum.FillDirection.Horizontal
barLayout.Padding = UDim.new(0, 8)
barLayout.Parent = bar
local printBtn = button(bar, "Print values", 130)
local resetBtn = button(bar, "Reset all", 110)
local closeBtn = button(bar, "Close (F3)", 110)

printBtn.MouseButton1Click:Connect(function()
	local lines = { "[TuningPanel] current values (changed ones marked *):" }
	for _, row in ipairs(ROWS) do
		if not row.section then
			local key = row[1]
			local live = Workspace:GetAttribute("Tune_" .. key)
			table.insert(lines, string.format("  %s%s = %s  (default %s)", live ~= nil and "*" or " ", key, fmt(current(key)), fmt(default(key))))
		end
	end
	print(table.concat(lines, "\n"))
end)
resetBtn.MouseButton1Click:Connect(function()
	for _, row in ipairs(ROWS) do
		if not row.section then Workspace:SetAttribute("Tune_" .. row[1], nil) end
	end
	refresh()
end)
closeBtn.MouseButton1Click:Connect(function() gui.Enabled = false end)

UserInputService.InputBegan:Connect(function(input, gp)
	if input.KeyCode == Enum.KeyCode.F3 and not UserInputService:GetFocusedTextBox() then
		gui.Enabled = not gui.Enabled
		if gui.Enabled then refresh() end
	end
end)
refresh()
print("[TuningPanel] F3 opens the movement tuning panel (Studio only)")
