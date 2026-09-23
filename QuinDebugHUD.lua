--// QuinDebugHUD.client.lua
-- Canonical Left-Side HUD: Live telemetry, authoritative AnimationTrack display,
-- Runtime Execution Tracing breadcrumbs, clickable Quin spectate cards & Q/E cycling.
-- Smooth GTA camera tracking integration via shared.SpectatedQuin & Workspace SpectatedQuin attribute.

local StarterGui = game:GetService("StarterGui")
pcall(function() StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Chat, false) end)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera

-- ============================================================
-- AUTHORITATIVE ANIMATION REGISTRY LOOKUP
-- ============================================================
local animNameLookup = {
	["rbxassetid://109837817595150"] = "Idle / Block",
	["rbxassetid://109090784752055"] = "Run / Sprint",
	["rbxassetid://133182359318358"] = "Dash",
	["rbxassetid://74552125029304"]  = "WalkConfident / WalkThug",
	["rbxassetid://85622241844167"]  = "Jump",
	["rbxassetid://79340771026707"]  = "Fall",
	["rbxassetid://88475997278069"]  = "FallAirKnockback",
	["rbxassetid://113219639247452"] = "Punch1 / Uppercut",
	["rbxassetid://79937990476934"]  = "CrossLeft",
	["rbxassetid://99362983788110"]  = "CrossRight",
	["rbxassetid://135206101877204"] = "Hook",
	["rbxassetid://84162023451491"]  = "HighKick",
	["rbxassetid://71573540671127"]  = "LowKick",
	["rbxassetid://87872094663324"]  = "PowerKick / Special1",
	["rbxassetid://89487629068473"]  = "WheelDrive / Slam",
	["rbxassetid://83869147275692"]  = "HitLight / Knockback",
	["rbxassetid://82096408080514"]  = "HitHeavy",
	["rbxassetid://79207866638803"]  = "GetUpGround",
	["rbxassetid://82291519563301"]  = "StrafeRightWalk",
	["rbxassetid://71421932655009"]  = "StrafeLeftWalk",
	["rbxassetid://107962284182266"] = "StrafeRightRun",
	["rbxassetid://123318024844911"] = "StrafeLeftRun",
	["rbxassetid://110691224052109"] = "StrafeRightTired",
	["rbxassetid://91032818959845"]  = "StrafeLeftTired",
}

-- Populate dynamically from AnimationConfig registry if available
pcall(function()
	local qc = ReplicatedStorage:FindFirstChild("QuinCore")
	if qc and qc:FindFirstChild("AnimationConfig") then
		local AnimationConfig = require(qc.AnimationConfig)
		local function scanRegistry(tbl)
			if type(tbl) ~= "table" then return end
			for k, v in pairs(tbl) do
				if type(v) == "table" then
					if v.id then
						local rawId = tostring(v.id)
						local name = v.name or k
						animNameLookup[rawId] = name
						local num = rawId:match("%d+")
						if num then
							animNameLookup[num] = name
							animNameLookup["rbxassetid://" .. num] = name
						end
					else
						scanRegistry(v)
					end
				end
			end
		end
		scanRegistry(AnimationConfig.Registry)
	end
end)

-- Helper to inspect active authoritative AnimationTrack from Animator
local function getAuthoritativeAnimation(model)
	if not model then return nil end
	local tracks = {}

	-- 1. Check direct Humanoid on model
	local hum = model:FindFirstChildOfClass("Humanoid")
	local anim = hum and hum:FindFirstChildOfClass("Animator")
	if anim then
		tracks = anim:GetPlayingAnimationTracks()
	elseif hum then
		tracks = hum:GetPlayingAnimationTracks()
	end

	-- 2. Fallback check on Client Ghost in Workspace.QuinGhost
	if #tracks == 0 then
		local qGhost = Workspace:FindFirstChild("QuinGhost")
		local ghost = qGhost and qGhost:FindFirstChild(model.Name .. "_Visual")
		local gHum = ghost and ghost:FindFirstChildOfClass("Humanoid")
		local gAnim = gHum and gHum:FindFirstChildOfClass("Animator")
		if gAnim then
			tracks = gAnim:GetPlayingAnimationTracks()
		elseif gHum then
			tracks = gHum:GetPlayingAnimationTracks()
		end
	end

	if #tracks == 0 then return nil end

	-- Find highest priority track (prioritize active combat/movement over background idle)
	local bestTrack = nil
	for _, t in ipairs(tracks) do
		if t.IsPlaying and t.WeightCurrent > 0.01 then
			if not bestTrack then
				bestTrack = t
			else
				local tPrio = t.Priority.Value
				local bPrio = bestTrack.Priority.Value
				if tPrio > bPrio then
					bestTrack = t
				elseif tPrio == bPrio and t.WeightCurrent > bestTrack.WeightCurrent then
					bestTrack = t
				end
			end
		end
	end
	return bestTrack
end

-- ============================================================
-- GUI SETUP
-- ============================================================
local gui = Instance.new("ScreenGui")
gui.Name = "QuinDebugGui"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = player:WaitForChild("PlayerGui")

-- HUD Visibility flag (Visible by default; press H or click pill to toggle)
local isHudVisible = true
local showVerboseTrace = true

-- Floating Toggle Pill (Top-Left, docked opposite to Quin Manager Menu)
local togglePill = Instance.new("TextButton")
togglePill.Name = "SpectatorTogglePill"
togglePill.Size = UDim2.new(0, 180, 0, 36)
togglePill.Position = UDim2.new(0, 15, 0, 15)
togglePill.BackgroundColor3 = Color3.fromRGB(15, 20, 30)
togglePill.BackgroundTransparency = 0.15
togglePill.TextColor3 = Color3.fromRGB(0, 229, 255)
togglePill.Font = Enum.Font.GothamBold
togglePill.TextSize = 12
togglePill.Text = "👁️ Spectator HUD [H]"
togglePill.Visible = false
togglePill.Parent = gui

local pillCorner = Instance.new("UICorner")
pillCorner.CornerRadius = UDim.new(0, 18)
pillCorner.Parent = togglePill

local pillStroke = Instance.new("UIStroke")
pillStroke.Color = Color3.fromRGB(0, 229, 255)
pillStroke.Thickness = 1.5
pillStroke.Parent = togglePill

-- Outer Container Frame (Docked Left)
local outerFrame = Instance.new("Frame")
outerFrame.Size = UDim2.new(0, 360, 1, -30)
outerFrame.Position = UDim2.new(0, 15, 0, 15)
outerFrame.BackgroundTransparency = 0.20
outerFrame.BackgroundColor3 = Color3.fromRGB(10, 12, 18)
outerFrame.BorderSizePixel = 0
outerFrame.Visible = true
outerFrame.Parent = gui

local outerCorner = Instance.new("UICorner")
outerCorner.CornerRadius = UDim.new(0, 8)
outerCorner.Parent = outerFrame

local outerStroke = Instance.new("UIStroke")
outerStroke.Color = Color3.fromRGB(40, 50, 70)
outerStroke.Thickness = 1.5
outerStroke.Parent = outerFrame

-- Header Bar
local headerBar = Instance.new("Frame")
headerBar.Size = UDim2.new(1, 0, 0, 28)
headerBar.Position = UDim2.new(0, 0, 0, 0)
headerBar.BackgroundColor3 = Color3.fromRGB(18, 22, 32)
headerBar.BorderSizePixel = 0
headerBar.Parent = outerFrame

local headerCorner = Instance.new("UICorner")
headerCorner.CornerRadius = UDim.new(0, 8)
headerCorner.Parent = headerBar

local headerPadding = Instance.new("UIPadding")
headerPadding.PaddingLeft = UDim.new(0, 10)
headerPadding.PaddingRight = UDim.new(0, 8)
headerPadding.Parent = headerBar

local headerTitle = Instance.new("TextLabel")
headerTitle.Size = UDim2.new(1, -125, 1, 0)
headerTitle.Position = UDim2.new(0, 0, 0, 0)
headerTitle.BackgroundTransparency = 1
headerTitle.TextColor3 = Color3.fromRGB(255, 215, 0)
headerTitle.Font = Enum.Font.GothamBold
headerTitle.TextSize = 11
headerTitle.TextXAlignment = Enum.TextXAlignment.Left
headerTitle.Text = "QUIN SPECTATOR HUD [H]"
headerTitle.Parent = headerBar

local resetCamBtn = Instance.new("TextButton")
resetCamBtn.Size = UDim2.new(0, 85, 0, 22)
resetCamBtn.Position = UDim2.new(1, -118, 0, 3)
resetCamBtn.BackgroundColor3 = Color3.fromRGB(45, 55, 75)
resetCamBtn.TextColor3 = Color3.fromRGB(220, 235, 255)
resetCamBtn.Font = Enum.Font.GothamBold
resetCamBtn.TextSize = 10
resetCamBtn.Text = "📷 Reset (R)"
resetCamBtn.Parent = headerBar

local resetCorner = Instance.new("UICorner")
resetCorner.CornerRadius = UDim.new(0, 4)
resetCorner.Parent = resetCamBtn

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.new(0, 24, 0, 22)
closeBtn.Position = UDim2.new(1, -27, 0, 3)
closeBtn.BackgroundColor3 = Color3.fromRGB(45, 55, 75)
closeBtn.TextColor3 = Color3.fromRGB(220, 235, 255)
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 12
closeBtn.Text = "—"
closeBtn.Parent = headerBar

local closeCorner = Instance.new("UICorner")
closeCorner.CornerRadius = UDim.new(0, 4)
closeCorner.Parent = closeBtn

-- Main Scrollable Card List Frame
local scrollFrame = Instance.new("ScrollingFrame")
scrollFrame.Size = UDim2.new(1, 0, 1, -34)
scrollFrame.Position = UDim2.new(0, 0, 0, 34)
scrollFrame.BackgroundTransparency = 0.35
scrollFrame.BackgroundColor3 = Color3.fromRGB(15, 18, 26)
scrollFrame.BorderSizePixel = 0
scrollFrame.ScrollBarThickness = 5
scrollFrame.ScrollBarImageColor3 = Color3.fromRGB(80, 120, 180)
scrollFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
scrollFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
scrollFrame.Parent = outerFrame

local scrollCorner = Instance.new("UICorner")
scrollCorner.CornerRadius = UDim.new(0, 6)
scrollCorner.Parent = scrollFrame

local listLayout = Instance.new("UIListLayout")
listLayout.Padding = UDim.new(0, 6)
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Parent = scrollFrame

local padding = Instance.new("UIPadding")
padding.PaddingLeft = UDim.new(0, 6)
padding.PaddingRight = UDim.new(0, 6)
padding.PaddingTop = UDim.new(0, 6)
padding.PaddingBottom = UDim.new(0, 6)
padding.Parent = scrollFrame

-- ============================================================
-- SPECTATOR LOGIC
-- ============================================================
local cardInstances = {}

local function getAllAliveQuins()
	local quins = {}
	-- STRICT FILTER: Only query QuinServer folder (where arena combatants reside).
	-- Never scan raw Workspace to avoid picking up static rigs/world dummies (QuinTest, QuinTypeA).
	local serverFolder = Workspace:FindFirstChild("QuinServer")
	if not serverFolder then return quins end

	for _, model in ipairs(serverFolder:GetChildren()) do
		if model:IsA("Model") and not model.Name:find("_Visual") and model.Parent then
			-- Exclude player characters
			if model ~= player.Character and not Players:GetPlayerFromCharacter(model) then
				-- Arena Quin verification: Must be an arena combatant
				local isArenaQuin = model:GetAttribute("QuinId") ~= nil
					or CollectionService:HasTag(model, "Quin")
					or CollectionService:HasTag(model, "AI_Fighter")
					or string.match(model.Name, "^Quin_")

				if isArenaQuin and model.Name ~= "QuinTest" and model.Name ~= "QuinTypeA" then
					local hum = model:FindFirstChildOfClass("Humanoid")
					local hrp = model:FindFirstChild("HumanoidRootPart")
					if hum and hum.Health > 0 and hrp then
						table.insert(quins, model)
					end
				end
			end
		end
	end
	table.sort(quins, function(a, b) return a.Name < b.Name end)
	return quins
end

local function setSpectatedQuin(model)
	shared.SpectatedQuin = model
	_G.SpectatedQuin = model
	Workspace:SetAttribute("SpectatedQuin", model and model.Name or "")
	if not model then
		if player.Character and player.Character:FindFirstChildOfClass("Humanoid") then
			camera.CameraSubject = player.Character:FindFirstChildOfClass("Humanoid")
		end
	else
		local hum = model:FindFirstChildOfClass("Humanoid")
		if hum then
			camera.CameraSubject = hum
		end
	end
end

local function cycleSpectatedQuin(delta)
	local quins = getAllAliveQuins()
	if #quins == 0 then
		setSpectatedQuin(nil)
		return
	end

	local curQuin = shared.SpectatedQuin or _G.SpectatedQuin
	if not curQuin then
		local curName = Workspace:GetAttribute("SpectatedQuin")
		if curName and curName ~= "" then
			curQuin = Workspace:FindFirstChild(curName) or (Workspace:FindFirstChild("QuinServer") and Workspace.QuinServer:FindFirstChild(curName))
		end
	end

	local curIdx = 1
	for idx, q in ipairs(quins) do
		if q == curQuin then
			curIdx = idx
			break
		end
	end

	curIdx = ((curIdx - 1 + delta) % #quins) + 1
	setSpectatedQuin(quins[curIdx])
end

local function setHudVisibility(visible)
	isHudVisible = visible
	local hideOverride = (Workspace:GetAttribute("HideSpectatorHUD") == true)
	if hideOverride then
		outerFrame.Visible = false
		togglePill.Visible = false
	else
		outerFrame.Visible = visible
		togglePill.Visible = not visible
	end
end

togglePill.MouseButton1Click:Connect(function()
	setHudVisibility(not isHudVisible)
end)

closeBtn.MouseButton1Click:Connect(function()
	setHudVisibility(false)
end)

resetCamBtn.MouseButton1Click:Connect(function()
	setSpectatedQuin(nil)
end)

-- Keybinds: Q/E cycle, R reset, H toggle HUD, T toggle verbose trace
UserInputService.InputBegan:Connect(function(input, gp)
	if gp or UserInputService:GetFocusedTextBox() then return end
	if input.KeyCode == Enum.KeyCode.Q then
		cycleSpectatedQuin(-1)
	elseif input.KeyCode == Enum.KeyCode.E then
		cycleSpectatedQuin(1)
	elseif input.KeyCode == Enum.KeyCode.R then
		setSpectatedQuin(nil)
	elseif input.KeyCode == Enum.KeyCode.H then
		setHudVisibility(not isHudVisible)
	elseif input.KeyCode == Enum.KeyCode.T then
		showVerboseTrace = not showVerboseTrace
	end
end)

-- ============================================================
-- CARD FACTORY
-- ============================================================
local function getOrCreateCard(quinModel)
	local name = quinModel.Name
	if cardInstances[name] then
		return cardInstances[name]
	end

	local cardBtn = Instance.new("TextButton")
	cardBtn.Name = name
	cardBtn.Size = UDim2.new(1, 0, 0, 0)
	cardBtn.AutomaticSize = Enum.AutomaticSize.Y
	cardBtn.BackgroundColor3 = Color3.fromRGB(22, 26, 36)
	cardBtn.BackgroundTransparency = 0.2
	cardBtn.Text = ""
	cardBtn.AutoButtonColor = true
	cardBtn.Parent = scrollFrame

	local cardCorner = Instance.new("UICorner")
	cardCorner.CornerRadius = UDim.new(0, 6)
	cardCorner.Parent = cardBtn

	local cardPad = Instance.new("UIPadding")
	cardPad.PaddingLeft = UDim.new(0, 8)
	cardPad.PaddingRight = UDim.new(0, 8)
	cardPad.PaddingTop = UDim.new(0, 6)
	cardPad.PaddingBottom = UDim.new(0, 8)
	cardPad.Parent = cardBtn

	local cardStroke = Instance.new("UIStroke")
	cardStroke.Color = Color3.fromRGB(0, 200, 255)
	cardStroke.Thickness = 0
	cardStroke.Parent = cardBtn

	local textLabel = Instance.new("TextLabel")
	textLabel.Size = UDim2.new(1, 0, 0, 0)
	textLabel.Position = UDim2.new(0, 0, 0, 0)
	textLabel.AutomaticSize = Enum.AutomaticSize.Y
	textLabel.TextWrapped = true
	textLabel.BackgroundTransparency = 1
	textLabel.TextColor3 = Color3.fromRGB(200, 255, 200)
	textLabel.Font = Enum.Font.RobotoMono
	textLabel.TextSize = 11
	textLabel.TextXAlignment = Enum.TextXAlignment.Left
	textLabel.TextYAlignment = Enum.TextYAlignment.Top
	textLabel.RichText = true
	textLabel.Parent = cardBtn

	cardBtn.MouseButton1Click:Connect(function()
		setSpectatedQuin(quinModel)
	end)

	local cardObj = {
		btn = cardBtn,
		stroke = cardStroke,
		label = textLabel,
		model = quinModel,
	}
	cardInstances[name] = cardObj
	return cardObj
end

-- ============================================================
-- MAIN UPDATE LOOP
-- ============================================================
RunService.Heartbeat:Connect(function()
	local activeQuins = {}
	local count = 0

	local quins = getAllAliveQuins()
	local curSpectated = shared.SpectatedQuin or _G.SpectatedQuin
	if not curSpectated then
		local curName = Workspace:GetAttribute("SpectatedQuin")
		if curName and curName ~= "" then
			local qServer = Workspace:FindFirstChild("QuinServer")
			curSpectated = qServer and qServer:FindFirstChild(curName)
		end
	end

	-- Auto-cycle if currently spectated Quin dies or despawns or is not in QuinServer
	if curSpectated then
		local hum = curSpectated:FindFirstChildOfClass("Humanoid")
		local isAliveArena = curSpectated.Parent and curSpectated.Parent.Name == "QuinServer" and hum and hum.Health > 0
		if not isAliveArena then
			cycleSpectatedQuin(1)
			curSpectated = shared.SpectatedQuin or _G.SpectatedQuin
		end
	end

	for _, model in ipairs(quins) do
		activeQuins[model.Name] = true
		count = count + 1

		local card = getOrCreateCard(model)
		local isSpectatingThis = (model == curSpectated)

		card.stroke.Thickness = isSpectatingThis and 2.0 or 0
		card.stroke.Color = isSpectatingThis and Color3.fromRGB(255, 215, 0) or Color3.fromRGB(0, 200, 255)
		card.btn.BackgroundColor3 = isSpectatingThis and Color3.fromRGB(30, 36, 52) or Color3.fromRGB(22, 26, 36)

		local state = model:GetAttribute("CurrentState") or "None"
		local startY = model:GetAttribute("StartY") or 0
		local targetName = model:GetAttribute("TargetQuin") or "None"

		local hrp = model:FindFirstChild("HumanoidRootPart")
		local targetQuin = Workspace:FindFirstChild(targetName)
		local quinServer = Workspace:FindFirstChild("QuinServer")
		if not targetQuin and quinServer then
			targetQuin = quinServer:FindFirstChild(targetName)
		end
		local targetHrp = targetQuin and targetQuin:FindFirstChild("HumanoidRootPart")

		local alt = hrp and (hrp.Position.Y - startY) or 0
		local dist = (hrp and targetHrp) and (targetHrp.Position - hrp.Position).Magnitude or 0
		local speed = hrp and hrp.AssemblyLinearVelocity.Magnitude or 0
		local vy = hrp and hrp.AssemblyLinearVelocity.Y or 0

		local dashArmed = model:GetAttribute("DashArmed") or false

		local qType = model:GetAttribute("QuinType") or "TypeA"
		local qElem = model:GetAttribute("Element") or "Fire"
		local elemColor = model:GetAttribute("ElementColor") or Color3.fromRGB(255, 140, 40)
		local hexColor = string.format("#%02X%02X%02X", math.floor(elemColor.R * 255), math.floor(elemColor.G * 255), math.floor(elemColor.B * 255))

		local tactical = model:GetAttribute("TacticalState") or "ENGAGING"
		local conf = model:GetAttribute("CurrentConfidence") or 0.5
		local awareness = model:GetAttribute("AwarenessLevel") or model:GetAttribute("Pers_Awareness") or 0.65
		local threatZone = model:GetAttribute("ThreatZone") or "Front"
		local pacingVel = model:GetAttribute("PacingVelocity") or 0
		local decision = model:GetAttribute("RecommendedAction") or "—"
		local targetReason = model:GetAttribute("TargetReason") or ""
		local teamRole = model:GetAttribute("TeamRole") or "Solo"
		local quirky = model:GetAttribute("Quirky") or "Balanced"
		local curSpecial = model:GetAttribute("CurrentSpecial")

		-- 1. Authoritative Animation Information
		local activeAnim = getAuthoritativeAnimation(model)
		local animName = "None"
		local animId = "N/A"
		local animPrio = "None"
		local animLoop = "false"
		local animTime = "0.00s / 0.00s"
		local animSpeed = "1.0x"

		if activeAnim then
			local rawId = activeAnim.Animation and activeAnim.Animation.AnimationId or ""
			local num = rawId:match("%d+")
			animId = rawId ~= "" and rawId or "N/A"
			animName = animNameLookup[rawId] or (num and animNameLookup[num]) or activeAnim.Name
			if animName == "Animation" and activeAnim.Name == "Animation" then
				animName = num and ("Anim_" .. num) or "Active"
			end
			animPrio = activeAnim.Priority.Name
			animLoop = tostring(activeAnim.Looped)
			animTime = string.format("%.2fs / %.2fs", activeAnim.TimePosition, activeAnim.Length)
			animSpeed = string.format("%.1fx", activeAnim.Speed)
		end

		-- 2. Execution Context Tracing
		local breadcrumb = model:GetAttribute("TraceBreadcrumb") or "Main.lua:72 (Init)"
		local traceLog = model:GetAttribute("TraceLog") or ""

		local nameHeader = isSpectatingThis 
			and string.format("<font color='#FFD700'><b>[%s] 📷 SPECTATING</b></font>", model.Name)
			or string.format("<b>[%s]</b>", model.Name)

		local hasTrace = (traceLog ~= "")
		local traceDisplay = ""
		if hasTrace then
			traceDisplay = string.format(
				"\n<font color='#80D0FF'><b>▶ Trace:</b> %s</font>\n<font color='#A8B4C4'>%s</font>",
				breadcrumb, traceLog
			)
		else
			traceDisplay = string.format("\n<font color='#80D0FF'><b>▶ Trace:</b> %s</font>", breadcrumb)
		end

		local retreatScore = model:GetAttribute("RetreatScore")
		local isCornered = model:GetAttribute("IsCornered")
		local retreatObj = model:GetAttribute("RetreatObjective")
		local chaseCommit = model:GetAttribute("ChaseCommitment")
		local retreatTag = ""
		if isCornered then
			retreatTag = " <font color='#FF3333'><b>[CORNERED]</b></font>"
		elseif retreatObj then
			local scoreStr = retreatScore and string.format(" (%.1f)", retreatScore) or ""
			retreatTag = string.format(" <font color='#66FF66'><b>[%s%s]</b></font>", retreatObj, scoreStr)
		elseif retreatScore then
			retreatTag = string.format(" <font color='#66FF66'>[Safe:%.2f]</font>", retreatScore)
		end

		local chaseTag = ""
		if state == "Chase" and chaseCommit then
			chaseTag = string.format(" <font color='#FFAA00'>[Commit:%.0f%%]</font>", chaseCommit * 100)
		end

		local specialTag = curSpecial and string.format(" <font color='#FF44AA'><b>[%s]</b></font>", curSpecial) or ""

		local obsAware = model:GetAttribute("ObstacleAwareness")
		local wallSide = model:GetAttribute("WallRunSide")
		local travTag = ""
		if state == "Slide" then
			travTag = " <font color='#00FFCC'><b>[SLIDING]</b></font>"
		elseif state == "WallRun" then
			travTag = string.format(" <font color='#FFCC00'><b>[WALL RUN %s]</b></font>", wallSide or "")
		elseif obsAware and obsAware:find("Sliding") then
			travTag = " <font color='#00FFCC'><b>[SLIDE GAP]</b></font>"
		elseif obsAware and obsAware:find("Wall-Running") then
			travTag = " <font color='#FFCC00'><b>[WALL RUN]</b></font>"
		end

		local equippedTitle = model:GetAttribute("EquippedTitle") or "Rookie"
		local primaryRival = model:GetAttribute("PrimaryRivalId")
		local rivalScore = model:GetAttribute("PrimaryRivalScore") or ""
		local winStreak = model:GetAttribute("WinStreak") or 0

		local historyLine = string.format("Title: <font color='#FFDF70'><b>«%s»</b></font>", equippedTitle)
		if winStreak > 1 then
			historyLine = historyLine .. string.format(" <font color='#FF5555'><b>[%dW Streak]</b></font>", winStreak)
		end
		if primaryRival then
			historyLine = historyLine .. string.format(" | Rival: <font color='#FF6666'><b>%s</b></font> (%s)", primaryRival, rivalScore)
		end

		card.label.Text = string.format(
			"%s  <font color='%s'><b>[%s • %s]</b></font>\n" ..
			"%s\n" ..
			"State: <font color='#FFAA50'><b>%s</b></font>%s%s%s | Tact: <font color='#00E5FF'><b>%s</b></font> | Conf: %.2f\n" ..
			"Role: <font color='#FFD700'><b>%s</b></font> | Quirky: <font color='#E080FF'><b>%s</b></font>\n" ..
			"Alt: %.1f | Dist: %.1f | Spd: %.1f | Vy: %.1f | Dash: %s\n" ..
			"<font color='#FFB000'>Aware: %.2f</font> | <font color='#00FFAA'>Zone: %s</font> | <font color='#FF8080'>Pace: %.0f</font>\n" ..
			"<font color='#FFC0FF'><b>Decision:</b> <font color='#FFFFFF'>%s</font></font>%s <font color='#99AABB'>%s</font>\n" ..
			"<font color='#FF80DF'><b>Anim:</b></font> <font color='#FFFFFF'><b>%s</b></font> [<font color='#FFD700'>%s</font>] (Loop=%s)\n" ..
			"<font color='#888888'>Id: %s | Time: %s (%s)</font>%s",
			nameHeader, hexColor, qType, qElem,
			historyLine,
			state, specialTag, travTag, chaseTag, tactical, conf,
			teamRole, quirky,
			alt, dist, speed, vy, tostring(dashArmed),
			awareness, threatZone, pacingVel,
			decision, retreatTag, targetReason,
			animName, animPrio, animLoop,
			animId, animTime, animSpeed, traceDisplay
		)
	end

	local hideOverride = (Workspace:GetAttribute("HideSpectatorHUD") == true)
	if hideOverride then
		outerFrame.Visible = false
		togglePill.Visible = false
	else
		local showHUD = isHudVisible and (count > 0)
		outerFrame.Visible = showHUD
		togglePill.Visible = not showHUD
	end

	-- Prune stale cards
	for name, card in pairs(cardInstances) do
		if not activeQuins[name] then
			card.btn:Destroy()
			cardInstances[name] = nil
		end
	end
end)

print("[QuinDebugHUD] Loaded: Authoritative AnimationTrack inspector & RuntimeTracer breadcrumbs active.")
