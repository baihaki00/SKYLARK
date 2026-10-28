--// TeleportDebugHUD.client.lua
-- Grid Teleporter across all 625 baseplates (50k x 50k continent)
-- Teleports player 100 studs in the air at the exact center of any clicked baseplate
-- Automatically engages Fly Mode

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local TILE_SIZE = 2000
local GRID_RADIUS = 12 -- -12 to +12 (25x25 = 625 tiles)
local BASE_SURFACE_Y = 8 -- Baseplate top surface
local SPAWN_ALTITUDE = 108 -- 100 studs in the air above surface

-- Create ScreenGui
local gui = Instance.new("ScreenGui")
gui.Name = "TeleportDebugHUD"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 60
gui.Parent = playerGui

-- Toggle Button (Docked top-left)
local toggleBtn = Instance.new("TextButton")
toggleBtn.Name = "TogglePill"
toggleBtn.Position = UDim2.new(0, 20, 0, 70)
toggleBtn.Size = UDim2.new(0, 160, 0, 32)
toggleBtn.BackgroundColor3 = Color3.fromRGB(18, 22, 28)
toggleBtn.BackgroundTransparency = 0.15
toggleBtn.BorderSizePixel = 0
toggleBtn.Text = "📍 TELEPORT DEBUG"
toggleBtn.Font = Enum.Font.GothamBold
toggleBtn.TextSize = 12
toggleBtn.TextColor3 = Color3.fromRGB(0, 230, 200)
toggleBtn.AutoButtonColor = true
toggleBtn.Parent = gui

local btnCorner = Instance.new("UICorner")
btnCorner.CornerRadius = UDim.new(0, 8)
btnCorner.Parent = toggleBtn

local btnStroke = Instance.new("UIStroke")
btnStroke.Color = Color3.fromRGB(0, 230, 200)
btnStroke.Transparency = 0.5
btnStroke.Thickness = 1.2
btnStroke.Parent = toggleBtn

-- Main Panel
local mainPanel = Instance.new("Frame")
mainPanel.Name = "MainPanel"
mainPanel.Position = UDim2.new(0, 20, 0, 110)
mainPanel.Size = UDim2.new(0, 420, 0, 520)
mainPanel.BackgroundColor3 = Color3.fromRGB(15, 18, 24)
mainPanel.BackgroundTransparency = 0.15
mainPanel.BorderSizePixel = 0
mainPanel.Active = true
mainPanel.Visible = false -- (starts closed, the pill opens it: owner 2026-10-28)
mainPanel.ClipsDescendants = false
mainPanel.Parent = gui

local panelCorner = Instance.new("UICorner")
panelCorner.CornerRadius = UDim.new(0, 12)
panelCorner.Parent = mainPanel

local panelStroke = Instance.new("UIStroke")
panelStroke.Color = Color3.fromRGB(45, 55, 70)
panelStroke.Thickness = 1.5
panelStroke.Parent = mainPanel

-- Title Bar
local title = Instance.new("TextLabel")
title.Name = "Title"
title.Position = UDim2.new(0, 15, 0, 10)
title.Size = UDim2.new(1, -50, 0, 20)
title.BackgroundTransparency = 1
title.Text = "50K × 50K BASEPLATE TELEPORTER"
title.Font = Enum.Font.GothamBold
title.TextSize = 14
title.TextColor3 = Color3.fromRGB(240, 245, 255)
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = mainPanel

local subtitle = Instance.new("TextLabel")
subtitle.Name = "Subtitle"
subtitle.Position = UDim2.new(0, 15, 0, 30)
subtitle.Size = UDim2.new(1, -30, 0, 16)
subtitle.BackgroundTransparency = 1
subtitle.Text = "Click any tile to spawn 100 studs in the air (Auto-Fly ON)"
subtitle.Font = Enum.Font.Gotham
subtitle.TextSize = 11
subtitle.TextColor3 = Color3.fromRGB(130, 145, 165)
subtitle.TextXAlignment = Enum.TextXAlignment.Left
subtitle.Parent = mainPanel

-- Close button
local closeBtn = Instance.new("TextButton")
closeBtn.Name = "CloseBtn"
closeBtn.AnchorPoint = Vector2.new(1, 0)
closeBtn.Position = UDim2.new(1, -12, 0, 10)
closeBtn.Size = UDim2.new(0, 24, 0, 24)
closeBtn.BackgroundColor3 = Color3.fromRGB(35, 40, 50)
closeBtn.BorderSizePixel = 0
closeBtn.Text = "✕"
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 12
closeBtn.TextColor3 = Color3.fromRGB(200, 210, 225)
closeBtn.Parent = mainPanel

local closeCorner = Instance.new("UICorner")
closeCorner.CornerRadius = UDim.new(0, 6)
closeCorner.Parent = closeBtn

closeBtn.MouseButton1Click:Connect(function()
	mainPanel.Visible = false
end)

toggleBtn.MouseButton1Click:Connect(function()
	mainPanel.Visible = not mainPanel.Visible
end)

-- Status / Hover readout bar
local statusLabel = Instance.new("TextLabel")
statusLabel.Name = "StatusLabel"
statusLabel.Position = UDim2.new(0, 15, 0, 50)
statusLabel.Size = UDim2.new(1, -30, 0, 24)
statusLabel.BackgroundColor3 = Color3.fromRGB(22, 28, 38)
statusLabel.BorderSizePixel = 0
statusLabel.Text = "Hover over grid or click a tile"
statusLabel.Font = Enum.Font.GothamMedium
statusLabel.TextSize = 11
statusLabel.TextColor3 = Color3.fromRGB(0, 230, 200)
statusLabel.Parent = mainPanel

local statusCorner = Instance.new("UICorner")
statusCorner.CornerRadius = UDim.new(0, 6)
statusCorner.Parent = statusLabel

-- Core Teleport function
local function teleportTo(targetX, targetZ, labelName)
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if hrp then
		hrp.AssemblyLinearVelocity = Vector3.zero
		hrp.CFrame = CFrame.new(targetX, SPAWN_ALTITUDE, targetZ)
		
		-- Engage fly mode automatically
		task.defer(function()
			if shared.StartFlying then
				shared.StartFlying()
			end
		end)
		
		statusLabel.Text = string.format("✓ Teleported to %s (%d, 100u air, %d)", labelName or "Baseplate", targetX, targetZ)
		statusLabel.TextColor3 = Color3.fromRGB(80, 255, 160)
	end
end

shared.TeleportToCoords = teleportTo

-- Quick Presets Row
local presetsFrame = Instance.new("Frame")
presetsFrame.Name = "Presets"
presetsFrame.Position = UDim2.new(0, 15, 0, 80)
presetsFrame.Size = UDim2.new(1, -30, 0, 26)
presetsFrame.BackgroundTransparency = 1
presetsFrame.Parent = mainPanel

local presetLayout = Instance.new("UIListLayout")
presetLayout.FillDirection = Enum.FillDirection.Horizontal
presetLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
presetLayout.Padding = UDim.new(0, 6)
presetLayout.Parent = presetsFrame

local presets = {
	{ name = "ARENA", x = 0, z = 0 },
	{ name = "NORTH", x = 0, z = -24000 },
	{ name = "SOUTH", x = 0, z = 24000 },
	{ name = "EAST", x = 24000, z = 0 },
	{ name = "WEST", x = -24000, z = 0 },
}

for _, p in ipairs(presets) do
	local pBtn = Instance.new("TextButton")
	pBtn.Size = UDim2.new(0, 72, 1, 0)
	pBtn.BackgroundColor3 = Color3.fromRGB(28, 35, 48)
	pBtn.BorderSizePixel = 0
	pBtn.Text = p.name
	pBtn.Font = Enum.Font.GothamBold
	pBtn.TextSize = 10
	pBtn.TextColor3 = Color3.fromRGB(180, 205, 235)
	pBtn.Parent = presetsFrame
	
	local pCorner = Instance.new("UICorner")
	pCorner.CornerRadius = UDim.new(0, 6)
	pCorner.Parent = pBtn
	
	pBtn.MouseButton1Click:Connect(function()
		teleportTo(p.x, p.z, p.name)
	end)
end

-- 25x25 Interactive Grid Container (375x375 pixels: 25 cols * 15px = 375px)
local gridContainer = Instance.new("Frame")
gridContainer.Name = "GridContainer"
gridContainer.Position = UDim2.new(0, 22, 0, 114)
gridContainer.Size = UDim2.new(0, 376, 0, 376)
gridContainer.BackgroundColor3 = Color3.fromRGB(10, 12, 16)
gridContainer.BorderSizePixel = 0
gridContainer.Parent = mainPanel

local gridCorner = Instance.new("UICorner")
gridCorner.CornerRadius = UDim.new(0, 8)
gridCorner.Parent = gridContainer

local gridLayout = Instance.new("UIGridLayout")
gridLayout.CellSize = UDim2.new(0, 14, 0, 14)
gridLayout.CellPadding = UDim2.new(0, 1, 0, 1)
gridLayout.FillDirectionMaxCells = 25
gridLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
gridLayout.VerticalAlignment = Enum.VerticalAlignment.Center
gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
gridLayout.Parent = gridContainer

-- Player position indicator dot (parented to mainPanel so it overlays without disrupting UIGridLayout)
local playerDot = Instance.new("Frame")
playerDot.Name = "PlayerMarker"
playerDot.Size = UDim2.new(0, 8, 0, 8)
playerDot.AnchorPoint = Vector2.new(0.5, 0.5)
playerDot.BackgroundColor3 = Color3.fromRGB(255, 230, 0)
playerDot.ZIndex = 25
playerDot.BorderSizePixel = 0
playerDot.Parent = mainPanel

local dotCorner = Instance.new("UICorner")
dotCorner.CornerRadius = UDim.new(1, 0)
dotCorner.Parent = playerDot

-- Populate 25x25 Grid
local cellIndex = 0

for gz = -GRID_RADIUS, GRID_RADIUS do
	for gx = -GRID_RADIUS, GRID_RADIUS do
		cellIndex = cellIndex + 1
		local tileX = gx * TILE_SIZE
		local tileZ = gz * TILE_SIZE
		local isCenter = (gx == 0 and gz == 0)
		
		local cell = Instance.new("TextButton")
		cell.Name = string.format("Cell_%d_%d", gx, gz)
		cell.LayoutOrder = cellIndex
		cell.BorderSizePixel = 0
		cell.Text = ""
		cell.AutoButtonColor = false
		
		if isCenter then
			cell.BackgroundColor3 = Color3.fromRGB(0, 230, 180) -- Emerald for Arena Center
		else
			cell.BackgroundColor3 = Color3.fromRGB(30, 36, 46)
		end
		
		local cCorner = Instance.new("UICorner")
		cCorner.CornerRadius = UDim.new(0, 2)
		cCorner.Parent = cell
		
		cell.MouseEnter:Connect(function()
			if not isCenter then
				cell.BackgroundColor3 = Color3.fromRGB(70, 140, 240)
			end
			local labelDesc = isCenter and "★ ARENA CENTER [0, 0]" or string.format("Tile [%d, %d]", gx, gz)
			statusLabel.Text = string.format("%s | Center: (%d, %d)", labelDesc, tileX, tileZ)
			statusLabel.TextColor3 = Color3.fromRGB(0, 230, 200)
		end)
		
		cell.MouseLeave:Connect(function()
			if not isCenter then
				cell.BackgroundColor3 = Color3.fromRGB(30, 36, 46)
			end
		end)
		
		cell.MouseButton1Click:Connect(function()
			local labelDesc = isCenter and "Arena Center" or string.format("Tile [%d, %d]", gx, gz)
			teleportTo(tileX, tileZ, labelDesc)
		end)
		
		cell.Parent = gridContainer
	end
end

-- Update player marker on the grid
RunService.Heartbeat:Connect(function()
	if not mainPanel.Visible then return end
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if hrp then
		local posX = hrp.Position.X
		local posZ = hrp.Position.Z
		
		-- Map from [-25000, 25000] to gridContainer bounds
		local alphaX = math.clamp((posX + 25000) / 50000, 0, 1)
		local alphaZ = math.clamp((posZ + 25000) / 50000, 0, 1)
		
		local gPos = gridContainer.Position
		local gSize = gridContainer.Size
		playerDot.Position = UDim2.new(
			gPos.X.Scale, gPos.X.Offset + (alphaX * gSize.X.Offset),
			gPos.Y.Scale, gPos.Y.Offset + (alphaZ * gSize.Y.Offset)
		)
	end
end)
