--// RuntimeVisualizer.lua
-- 3D Debug Visualizers for Quin combat AI, spatial reasoning, and kinematics:
-- 1. Line-of-Sight (LoS) 3D Tether: Neon Green when clear, Crimson Red when occluded + hit point
-- 2. Last Known Position (LKP): Pulsing floor ring + vertical beacon marker
-- 3. Ballistic Trajectory Curve: Real-time physics projection arc + landing impact reticle
-- 4. Platform & Ledge Intent: Visual navigation vectors for high-ground dive and climb
-- 5. Overhead Tactical HUD Billboard: State, obstacle awareness, speed, mana, and IK telemetry

local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")

local QuinCore = ReplicatedStorage:WaitForChild("QuinCore")
local CombatConfig = require(QuinCore:WaitForChild("CombatConfig"))
local SpatialModule = require(QuinCore:WaitForChild("Modules"):WaitForChild("SpatialModule"))

local RuntimeVisualizer = {}
RuntimeVisualizer.__index = RuntimeVisualizer

local GRAVITY = Vector3.new(0, -Workspace.Gravity, 0)
local VISUALIZER_FOLDER_NAME = "QuinDebugVisualizers"

local container = nil
local function getContainer()
	if not container or not container.Parent then
		container = Workspace:FindFirstChild(VISUALIZER_FOLDER_NAME)
		if not container then
			container = Instance.new("Folder")
			container.Name = VISUALIZER_FOLDER_NAME
			container.Parent = Workspace
		end
	end
	return container
end

-- Line Adornment Pool
local linePool = {}
local function getLineAdornment(index)
	if not linePool[index] then
		local line = Instance.new("LineHandleAdornment")
		line.Name = "DebugLine_" .. tostring(index)
		line.ZIndex = 5
		line.AlwaysOnTop = true
		line.Thickness = 3
		line.Adornee = Workspace.Terrain
		line.Parent = getContainer()
		linePool[index] = line
	end
	linePool[index].Visible = true
	return linePool[index]
end

local function hideUnusedLines(usedCount)
	for i = usedCount + 1, #linePool do
		if linePool[i] then
			linePool[i].Visible = false
		end
	end
end

-- Visualizer State
local isEnabled = CombatConfig.DebugVisualizers_Enabled ~= false
local activeTargetBeam = nil
local activeTargetAtt0 = nil
local activeTargetAtt1 = nil
local lkpMarker = nil
local impactReticle = nil
local overheadBillboard = nil
local platformArrow = nil

function RuntimeVisualizer.isEnabled()
	return isEnabled
end

function RuntimeVisualizer.setEnabled(val)
	isEnabled = val
	if not isEnabled then
		RuntimeVisualizer.clear()
	end
end

function RuntimeVisualizer.toggle()
	RuntimeVisualizer.setEnabled(not isEnabled)
	return isEnabled
end

-- Clear all active 3D debug visualizer instances
function RuntimeVisualizer.clear()
	hideUnusedLines(0)
	if container and container.Parent then
		container:ClearAllChildren()
	end
	activeTargetBeam = nil
	activeTargetAtt0 = nil
	activeTargetAtt1 = nil
	lkpMarker = nil
	impactReticle = nil
	overheadBillboard = nil
	platformArrow = nil
end

-- ============================================================
-- 1. LINE-OF-SIGHT (LoS) TETHER
-- ============================================================
local function updateLoSTether(fighter, target, hasLoS, occludedPoint)
	local folder = getContainer()
	if not activeTargetBeam or not activeTargetBeam.Parent then
		local part0 = Instance.new("Part")
		part0.Name = "LoS_AttPart0"
		part0.Size = Vector3.new(0.2, 0.2, 0.2)
		part0.Transparency = 1
		part0.Anchored = true
		part0.CanCollide = false
		part0.Parent = folder

		local part1 = Instance.new("Part")
		part1.Name = "LoS_AttPart1"
		part1.Size = Vector3.new(0.2, 0.2, 0.2)
		part1.Transparency = 1
		part1.Anchored = true
		part1.CanCollide = false
		part1.Parent = folder

		local att0 = Instance.new("Attachment")
		att0.Parent = part0
		local att1 = Instance.new("Attachment")
		att1.Parent = part1

		local beam = Instance.new("Beam")
		beam.Name = "LoS_Beam"
		beam.Attachment0 = att0
		beam.Attachment1 = att1
		beam.Width0 = 0.4
		beam.Width1 = 0.4
		beam.FaceCamera = true
		beam.LightEmission = 1.0
		beam.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.1),
			NumberSequenceKeypoint.new(0.5, 0.0),
			NumberSequenceKeypoint.new(1, 0.1),
		})
		beam.Parent = folder

		activeTargetAtt0 = att0
		activeTargetAtt1 = att1
		activeTargetBeam = beam
	end

	local fHRP = fighter:FindFirstChild("HumanoidRootPart")
	local tHRP = target and target:FindFirstChild("HumanoidRootPart")
	if not fHRP or not tHRP then
		activeTargetBeam.Enabled = false
		return
	end

	local startPos = SpatialModule.getEyePosition(fHRP)
	local endPos = SpatialModule.getEyePosition(tHRP)

	activeTargetAtt0.Parent.Position = startPos
	activeTargetAtt1.Parent.Position = endPos
	activeTargetBeam.Enabled = true

	if hasLoS then
		-- Clear Line of Sight: Neon Emerald Green
		local green = Color3.fromRGB(0, 255, 128)
		activeTargetBeam.Color = ColorSequence.new(green)
		activeTargetBeam.Width0 = 0.35
		activeTargetBeam.Width1 = 0.35
	else
		-- Occluded: Neon Crimson Red
		local red = Color3.fromRGB(255, 45, 65)
		activeTargetBeam.Color = ColorSequence.new(red)
		activeTargetBeam.Width0 = 0.50
		activeTargetBeam.Width1 = 0.50
	end
end

-- ============================================================
-- 2. LAST KNOWN POSITION (LKP) MARKER
-- ============================================================
local function updateLKPMarker(fighter, target, hasLoS)
	local folder = getContainer()
	local lkpPos = fighter:GetAttribute("LastSeenTargetPosition")
	if hasLoS or not lkpPos then
		if lkpMarker and lkpMarker.Parent then
			lkpMarker.Transparency = 1
			local bb = lkpMarker:FindFirstChildOfClass("BillboardGui")
			if bb then bb.Enabled = false end
		end
		return
	end

	if not lkpMarker or not lkpMarker.Parent then
		local part = Instance.new("Part")
		part.Name = "LKP_Marker"
		part.Shape = Enum.PartType.Cylinder
		part.Size = Vector3.new(0.4, 6.0, 6.0)
		part.Orientation = Vector3.new(0, 0, 90)
		part.Material = Enum.Material.Neon
		part.Color = Color3.fromRGB(255, 170, 0)
		part.Transparency = 0.4
		part.Anchored = true
		part.CanCollide = false
		part.Parent = folder

		local bb = Instance.new("BillboardGui")
		bb.Size = UDim2.new(0, 140, 0, 30)
		bb.StudsOffset = Vector3.new(0, 2.5, 0)
		bb.AlwaysOnTop = true
		bb.Parent = part

		local txt = Instance.new("TextLabel")
		txt.Name = "LKP_Label"
		txt.Size = UDim2.new(1, 0, 1, 0)
		txt.BackgroundTransparency = 1
		txt.TextColor3 = Color3.fromRGB(255, 200, 50)
		txt.Font = Enum.Font.GothamBold
		txt.TextSize = 13
		txt.TextStrokeTransparency = 0.2
		txt.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
		txt.Parent = bb

		lkpMarker = part
	end

	local timeLastSeen = fighter:GetAttribute("TimeLastSeen") or os.clock()
	local age = math.max(0, math.round((os.clock() - timeLastSeen) * 10) / 10)

	lkpMarker.Position = lkpPos + Vector3.new(0, 0.2, 0)
	lkpMarker.Transparency = 0.35 + math.sin(os.clock() * 6) * 0.15

	local bb = lkpMarker:FindFirstChildOfClass("BillboardGui")
	if bb then
		bb.Enabled = true
		local lbl = bb:FindFirstChild("LKP_Label")
		if lbl then
			local tgtName = target and target.Name or "Target"
			lbl.Text = string.format("👁️ LKP (%s) [-%0.1fs]", tgtName, age)
		end
	end
end

-- ============================================================
-- 3. BALLISTIC TRAJECTORY PREDICTION CURVE & IMPACT RETICLE
-- ============================================================
local function updateTrajectoryCurve(fighter, rootPart)
	local folder = getContainer()
	local vel = rootPart.AssemblyLinearVelocity
	local isAirborne = false
	local state = fighter:GetAttribute("CurrentState") or ""
	if state == "Airborne" or state == "Knockback" or state == "ProjectileJump" or math.abs(vel.Y) > 10 or vel.Magnitude > 32 then
		isAirborne = true
	end

	if not isAirborne then
		hideUnusedLines(0)
		if impactReticle and impactReticle.Parent then
			impactReticle.Transparency = 1
			local bb = impactReticle:FindFirstChildOfClass("BillboardGui")
			if bb then bb.Enabled = false end
		end
		return
	end

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = { fighter, getContainer(), Workspace:FindFirstChild("QuinGhost") }

	local startPos = rootPart.Position
	local currentPos = startPos
	local currentVel = vel
	local dt = 0.05
	local maxSteps = 35

	local lineIndex = 0
	local hitPos = nil
	local impactTime = 0

	for step = 1, maxSteps do
		local nextVel = currentVel + GRAVITY * dt
		local nextPos = currentPos + currentVel * dt + 0.5 * GRAVITY * (dt * dt)

		-- Raycast segment
		local segRay = Workspace:Raycast(currentPos, nextPos - currentPos, rayParams)
		local endPos = segRay and segRay.Position or nextPos

		lineIndex = lineIndex + 1
		local line = getLineAdornment(lineIndex)
		line.Length = (endPos - currentPos).Magnitude
		line.CFrame = CFrame.lookAt(currentPos, endPos)
		
		-- Color arc: Cyan on rise, Amber on apex, Orange on descent
		if currentVel.Y > 5 then
			line.Color3 = Color3.fromRGB(0, 220, 255)
		elseif currentVel.Y > -10 then
			line.Color3 = Color3.fromRGB(255, 230, 80)
		else
			line.Color3 = Color3.fromRGB(255, 120, 30)
		end
		line.Visible = true

		if segRay then
			hitPos = segRay.Position
			impactTime = step * dt
			break
		end

		currentPos = nextPos
		currentVel = nextVel
	end

	hideUnusedLines(lineIndex)

	-- Impact Ground Reticle
	if hitPos then
		if not impactReticle or not impactReticle.Parent then
			local ring = Instance.new("Part")
			ring.Name = "ImpactReticle"
			ring.Shape = Enum.PartType.Cylinder
			ring.Size = Vector3.new(0.2, 5.0, 5.0)
			ring.Orientation = Vector3.new(0, 0, 90)
			ring.Material = Enum.Material.Neon
			ring.Color = Color3.fromRGB(0, 255, 220)
			ring.Transparency = 0.35
			ring.Anchored = true
			ring.CanCollide = false
			ring.Parent = folder

			local bb = Instance.new("BillboardGui")
			bb.Size = UDim2.new(0, 120, 0, 24)
			bb.StudsOffset = Vector3.new(0, 1.8, 0)
			bb.AlwaysOnTop = true
			bb.Parent = ring

			local lbl = Instance.new("TextLabel")
			lbl.Name = "ImpactLabel"
			lbl.Size = UDim2.new(1, 0, 1, 0)
			lbl.BackgroundTransparency = 1
			lbl.TextColor3 = Color3.fromRGB(0, 255, 220)
			lbl.Font = Enum.Font.GothamBold
			lbl.TextSize = 12
			lbl.TextStrokeTransparency = 0.2
			lbl.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
			lbl.Parent = bb

			impactReticle = ring
		end

		impactReticle.Position = hitPos + Vector3.new(0, 0.1, 0)
		impactReticle.Transparency = 0.35 + math.sin(os.clock() * 10) * 0.15

		local bb = impactReticle:FindFirstChildOfClass("BillboardGui")
		if bb then
			bb.Enabled = true
			local lbl = bb:FindFirstChild("ImpactLabel")
			if lbl then
				lbl.Text = string.format("🎯 Impact: %0.2fs", impactTime)
			end
		end
	end
end

-- ============================================================
-- 4. PLATFORM INTENT & LEDGE NAVIGATION ARROWS
-- ============================================================
local function updatePlatformIntent(fighter, rootPart)
	local folder = getContainer()
	local obsAware = fighter:GetAttribute("ObstacleAwareness") or ""
	local isPerched = (obsAware:find("Ledge") ~= nil or obsAware:find("Platform") ~= nil)

	if not isPerched then
		if platformArrow and platformArrow.Parent then
			platformArrow.Transparency = 1
			local bb = platformArrow:FindFirstChildOfClass("BillboardGui")
			if bb then bb.Enabled = false end
		end
		return
	end

	if not platformArrow or not platformArrow.Parent then
		local arrow = Instance.new("Part")
		arrow.Name = "PlatformIntentArrow"
		arrow.Size = Vector3.new(1.2, 0.2, 6.0)
		arrow.Material = Enum.Material.Neon
		arrow.Color = Color3.fromRGB(255, 90, 200)
		arrow.Transparency = 0.3
		arrow.Anchored = true
		arrow.CanCollide = false
		arrow.Parent = folder

		local bb = Instance.new("BillboardGui")
		bb.Size = UDim2.new(0, 150, 0, 24)
		bb.StudsOffset = Vector3.new(0, 2.0, 0)
		bb.AlwaysOnTop = true
		bb.Parent = arrow

		local lbl = Instance.new("TextLabel")
		lbl.Name = "IntentLabel"
		lbl.Size = UDim2.new(1, 0, 1, 0)
		lbl.BackgroundTransparency = 1
		lbl.TextColor3 = Color3.fromRGB(255, 120, 220)
		lbl.Font = Enum.Font.GothamBold
		lbl.TextSize = 12
		lbl.TextStrokeTransparency = 0.2
		lbl.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
		lbl.Parent = bb

		platformArrow = arrow
	end

	local fwd = rootPart.CFrame.LookVector
	local flatFwd = Vector3.new(fwd.X, 0, fwd.Z)
	flatFwd = flatFwd.Magnitude > 0.01 and flatFwd.Unit or Vector3.new(0, 0, -1)

	platformArrow.CFrame = CFrame.lookAt(rootPart.Position + flatFwd * 4.0 - Vector3.new(0, 2.5, 0), rootPart.Position + flatFwd * 8.0 - Vector3.new(0, 2.5, 0))
	platformArrow.Transparency = 0.25 + math.sin(os.clock() * 8) * 0.15

	local bb = platformArrow:FindFirstChildOfClass("BillboardGui")
	if bb then
		bb.Enabled = true
		local lbl = bb:FindFirstChild("IntentLabel")
		if lbl then
			lbl.Text = string.format("⚡ %s", obsAware)
		end
	end
end

-- ============================================================
-- 5. OVERHEAD TACTICAL HUD BILLBOARD
-- ============================================================
local function updateOverheadBillboard(fighter, rootPart)
	local folder = getContainer()
	if not overheadBillboard or not overheadBillboard.Parent then
		local bb = Instance.new("BillboardGui")
		bb.Name = "FighterDebugBillboard"
		bb.Size = UDim2.new(0, 220, 0, 60)
		bb.StudsOffset = Vector3.new(0, 5.2, 0)
		bb.AlwaysOnTop = true
		bb.Parent = folder

		local bg = Instance.new("Frame")
		bg.Name = "Bg"
		bg.Size = UDim2.new(1, 0, 1, 0)
		bg.BackgroundColor3 = Color3.fromRGB(12, 16, 24)
		bg.BackgroundTransparency = 0.25
		bg.Parent = bb

		local uic = Instance.new("UICorner")
		uic.CornerRadius = UDim.new(0, 6)
		uic.Parent = bg

		local uis = Instance.new("UIStroke")
		uis.Color = Color3.fromRGB(0, 200, 255)
		uis.Thickness = 1.2
		uis.Parent = bg

		local line1 = Instance.new("TextLabel")
		line1.Name = "Line1"
		line1.Size = UDim2.new(1, -8, 0, 18)
		line1.Position = UDim2.new(0, 4, 0, 3)
		line1.BackgroundTransparency = 1
		line1.TextColor3 = Color3.fromRGB(240, 245, 255)
		line1.Font = Enum.Font.GothamBold
		line1.TextSize = 11
		line1.TextXAlignment = Enum.TextXAlignment.Left
		line1.Parent = bg

		local line2 = Instance.new("TextLabel")
		line2.Name = "Line2"
		line2.Size = UDim2.new(1, -8, 0, 16)
		line2.Position = UDim2.new(0, 4, 0, 22)
		line2.BackgroundTransparency = 1
		line2.TextColor3 = Color3.fromRGB(0, 230, 255)
		line2.Font = Enum.Font.Gotham
		line2.TextSize = 10
		line2.TextXAlignment = Enum.TextXAlignment.Left
		line2.Parent = bg

		local line3 = Instance.new("TextLabel")
		line3.Name = "Line3"
		line3.Size = UDim2.new(1, -8, 0, 16)
		line3.Position = UDim2.new(0, 4, 0, 39)
		line3.BackgroundTransparency = 1
		line3.TextColor3 = Color3.fromRGB(180, 200, 225)
		line3.Font = Enum.Font.Gotham
		line3.TextSize = 9
		line3.TextXAlignment = Enum.TextXAlignment.Left
		line3.Parent = bg

		overheadBillboard = bb
	end

	overheadBillboard.Adornee = rootPart
	overheadBillboard.Enabled = true

	local bg = overheadBillboard:FindFirstChild("Bg")
	if bg then
		local state = fighter:GetAttribute("CurrentState") or "None"
		local obsAware = fighter:GetAttribute("ObstacleAwareness") or "Clear"
		local speed = math.round(rootPart.AssemblyLinearVelocity.Magnitude * 10) / 10
		local energy = fighter:GetAttribute("Energy") or 100
		local hum = fighter:FindFirstChildOfClass("Humanoid")
		local hp = hum and math.round(hum.Health) or 100

		local l1 = bg:FindFirstChild("Line1")
		if l1 then
			l1.Text = string.format("%s | %s", fighter.Name, state:upper())
		end

		local l2 = bg:FindFirstChild("Line2")
		if l2 then
			l2.Text = string.format("HP: %d | Mana: %d | Spd: %0.1f s/s", hp, energy, speed)
		end

		local l3 = bg:FindFirstChild("Line3")
		if l3 then
			l3.Text = string.format("Intent: %s", obsAware)
		end
	end
end

-- ============================================================
-- MAIN UPDATE TICK (Invoked from QuinDebugHUD or RenderStepped)
-- ============================================================
function RuntimeVisualizer.update(spectatedFighter)
	if not isEnabled then return end
	if not spectatedFighter or not spectatedFighter.Parent then
		RuntimeVisualizer.clear()
		return
	end

	local rootPart = spectatedFighter:FindFirstChild("HumanoidRootPart")
	if not rootPart then return end

	-- Find active target
	local targetName = spectatedFighter:GetAttribute("CurrentTarget") or spectatedFighter:GetAttribute("TargetQuin")
	local target = nil
	if targetName and targetName ~= "" then
		local quinServer = Workspace:FindFirstChild("QuinServer") or Workspace
		target = quinServer:FindFirstChild(targetName) or Workspace:FindFirstChild(targetName)
	end

	-- 1. LoS Tether
	local hasLoS = spectatedFighter:GetAttribute("TargetHasLoS") == true
	updateLoSTether(spectatedFighter, target, hasLoS)

	-- 2. LKP Marker
	updateLKPMarker(spectatedFighter, target, hasLoS)

	-- 3. Trajectory Curve & Impact Reticle
	updateTrajectoryCurve(spectatedFighter, rootPart)

	-- 4. Platform Intent Navigation Vector
	updatePlatformIntent(spectatedFighter, rootPart)

	-- 5. Overhead Tactical HUD Billboard
	updateOverheadBillboard(spectatedFighter, rootPart)
end

return RuntimeVisualizer
