--// LeaderShowdownSystem.lua
-- Phase 12: Leader Showdown Protocol & Arena Staging Engine
-- Implements Master Project Plan Section 46 & Section 73
-- Authoritative server choreography for Asymmetric (4v1, 5v1, 6v1) and Symmetrical (1v1) Showdowns

local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local CombatConfig = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("CombatConfig"))
local AudioModule = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("AudioModule"))
local VfxModule = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("VfxModule"))
local AnimationModule = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("AnimationModule"))

local LeaderShowdownSystem = {
	isActive = false,
	activePhase = "None",
	currentPlatform = nil,
	refereeModels = {},
	barrierBeams = {},
	duelists = {},
	spectators = {},
}

-- Central Arena Anchor (top of ArenaGround is Y = 2.0)
local ARENA_CENTER = Vector3.new(0, 2.0, -38.0)
local PLATFORM_RADIUS = 48.0      -- Enlarged to 48 studs radius to comfortably seat 6+ Quins & spacious duel
local PLATFORM_HEIGHT = 4.5      -- Elevated slab height
local INNER_RING_RADIUS = 36.0    -- Inner sacred dueling perimeter boundary

-- Precise Vertical Geometry (Zero Sinking Feet)
local DAIS_TOP_Y = ARENA_CENTER.Y + PLATFORM_HEIGHT        -- 2.0 + 4.5 = 6.50
local STAND_OFFSET = 5.33                                  -- Exact measured sole-to-HRP height
local PLATFORM_STAND_Y = DAIS_TOP_Y + STAND_OFFSET         -- 6.50 + 5.33 = 11.83
local GROUND_STAND_Y = ARENA_CENTER.Y + STAND_OFFSET       -- 2.0 + 5.33 = 7.33
local GROUND_SIT_Y = ARENA_CENTER.Y + 2.40                 -- Natural seated HRP height (4.40)

-- 4 Wall Cardinal Perch Coordinates for 1v1 Referees (Y = 147 atop ArenaWalls)
local REFEREE_WALL_PERCHES = {
	North = Vector3.new(34.5, 147.0, -370.0),
	South = Vector3.new(28.5, 147.0, 295.0),
	East  = Vector3.new(330.0, 147.0, -37.0),
	West  = Vector3.new(-335.0, 147.0, -37.0),
}

-- Pacing Delays (Deliberate cinematic cadence, unhurried and dramatic)
local PACING = {
	CeasefireDelay       = 0.8,
	TankerStrideTime     = 2.2,
	GroundSmashWindup    = 0.7,
	PlatformElevation    = 1.6,
	PerimeterUnfurlTime  = 0.6,
	SquadStagingDuration = 3.2,
	ChampionStrideTime   = 1.8,
	FairnessSurgePause   = 1.0,
	PreDuelStandoffGaze  = 1.2,
	RefereeDiveDuration  = 1.6,
}

-- Walk Speed Presets (studs/s) — deliberate, unhurried, cinematic strides
local WALK_SPEED = {
	TankerApproach   = 12,   -- Heavy, powerful, at-ease stride
	SpectatorStaging = 16,   -- Casual walk to perimeter marks
	ChampionStride   = 14,   -- Confident volunteer stepping forward
	OpponentStride   = 14,   -- Lone warrior walking to their mark
}

-- Helper: Walk a Quin to a position using Humanoid:MoveTo (NO teleporting)
-- Plays confident walk animation, dynamically paces based on arena distance, waits for arrival
local function walkToPosition(model, targetPos, walkSpeed, lookAtPos, animOverride)
	local hrp = model:FindFirstChild("HumanoidRootPart")
	local hum = model:FindFirstChildOfClass("Humanoid")
	if not hrp or not hum then return end

	local dist = (Vector2.new(hrp.Position.X - targetPos.X, hrp.Position.Z - targetPos.Z)).Magnitude
	local baseSpeed = walkSpeed or 14

	-- Dynamic distance-scaled pace: if starting 100+ studs away across the arena,
	-- walk at a brisk stride so arrival is timely, then settle to deliberate stride near center
	local effectiveSpeed = baseSpeed
	if dist > 80 then
		effectiveSpeed = math.clamp(dist / 4.5, baseSpeed, 32)
	end
	hum.WalkSpeed = effectiveSpeed

	local anim = animOverride or "Locomotion.ConfidentWalk"
	AnimationModule.playConfig(hum, anim, 1.0, Enum.AnimationPriority.Movement)

	hum:MoveTo(Vector3.new(targetPos.X, hrp.Position.Y, targetPos.Z))

	local arrived = false
	local conn
	conn = hum.MoveToFinished:Connect(function(reached)
		arrived = true
		if conn then conn:Disconnect() end
	end)

	local startTime = tick()
	local maxWait = math.max(3.0, (dist / effectiveSpeed) * 1.8)
	maxWait = math.min(maxWait, 16.0)

	while not arrived and (tick() - startTime) < maxWait do
		local curDist = (Vector2.new(hrp.Position.X - targetPos.X, hrp.Position.Z - targetPos.Z)).Magnitude
		if curDist <= 2.5 then
			arrived = true
			break
		end
		-- Decelerate to majestic stride within 30 studs of destination
		if curDist <= 30 and hum.WalkSpeed > baseSpeed then
			hum.WalkSpeed = baseSpeed
		end
		task.wait(0.1)
	end
	if conn then conn:Disconnect() end

	hum.WalkSpeed = 0
	hum:MoveTo(hrp.Position)
	AnimationModule.playConfig(hum, "Movement.Idle", 1.0, Enum.AnimationPriority.Idle, true)

	if lookAtPos then
		local lookCF = CFrame.lookAt(hrp.Position, Vector3.new(lookAtPos.X, hrp.Position.Y, lookAtPos.Z))
		hrp.CFrame = lookCF
	end
end

-- Helper: Stage a Quin to their designated position during Ring Formation
-- Handles both platform hop (for Quins moving from ground up onto the elevated dais)
-- and ground walking (for leisurely Quins like Lazy or LoneWolf staying on floor)
local function stageQuinToSpot(q, targetPos, walkSpeed, lookAtPos, choosePlatform, isSeated)
	task.spawn(function()
		local hrp = q:FindFirstChild("HumanoidRootPart")
		local hum = q:FindFirstChildOfClass("Humanoid")
		if not hrp or not hum then return end

		q:SetAttribute("ShowdownStaged", false)

		local totalDist = (Vector2.new(hrp.Position.X - targetPos.X, hrp.Position.Z - targetPos.Z)).Magnitude
		local baseSpeed = walkSpeed or WALK_SPEED.SpectatorStaging
		local effectiveSpeed = (totalDist > 80) and math.clamp(totalDist / 4.5, baseSpeed, 32) or baseSpeed
		hum.WalkSpeed = effectiveSpeed

		local currentY = hrp.Position.Y
		local isOnGroundNow = (currentY < DAIS_TOP_Y)

		if choosePlatform and isOnGroundNow then
			-- Case 1: On arena ground, wants to hop onto the dais
			-- Walk smoothly to the dais base edge first
			local dirToCenter = Vector3.new(ARENA_CENTER.X - hrp.Position.X, 0, ARENA_CENTER.Z - hrp.Position.Z)
			local edgeSpot = ARENA_CENTER - (dirToCenter.Unit * (PLATFORM_RADIUS + 1.5))
			edgeSpot = Vector3.new(edgeSpot.X, GROUND_STAND_Y, edgeSpot.Z)

			AnimationModule.playConfig(hum, "Locomotion.ConfidentWalk", 1.1, Enum.AnimationPriority.Movement)
			hum:MoveTo(edgeSpot)

			local startT = tick()
			local edgeWait = math.max(3.0, (hrp.Position - edgeSpot).Magnitude / effectiveSpeed * 1.5)
			edgeWait = math.min(edgeWait, 14.0)
			while (tick() - startT) < edgeWait do
				local d = (Vector2.new(hrp.Position.X - edgeSpot.X, hrp.Position.Z - edgeSpot.Z)).Magnitude
				if d <= 3.5 then break end
				task.wait(0.1)
			end

			-- Perform athletic vault / hop onto dais
			AnimationModule.playConfig(hum, "Parkour.VaultObstacle", 1.2, Enum.AnimationPriority.Action)
			hum.Jump = true
			
			local att = Instance.new("Attachment")
			att.Name = "ShowdownHopAtt"
			att.Parent = hrp

			local lv = Instance.new("LinearVelocity")
			lv.Name = "ShowdownHop"
			local hopDir = (Vector3.new(targetPos.X - hrp.Position.X, 0, targetPos.Z - hrp.Position.Z)).Unit
			lv.VectorVelocity = hopDir * 16 + Vector3.new(0, 26, 0)
			lv.MaxForce = 250000
			lv.Attachment0 = att
			lv.Parent = hrp
			Debris:AddItem(lv, 0.35)
			Debris:AddItem(att, 0.35)
			task.wait(0.35)

			-- Now on platform: continue walking to the final spectator position
			AnimationModule.stopConfig(hum, "Parkour.VaultObstacle", 0.1)
			AnimationModule.playConfig(hum, "Movement.WalkConfident", 1.0, Enum.AnimationPriority.Movement)
			hum.WalkSpeed = baseSpeed
			hum:MoveTo(Vector3.new(targetPos.X, PLATFORM_STAND_Y, targetPos.Z))
			local arriveT = tick()
			while (tick() - arriveT) < 5.0 do
				local d = (Vector2.new(hrp.Position.X - targetPos.X, hrp.Position.Z - targetPos.Z)).Magnitude
				if d <= 2.5 then break end
				task.wait(0.1)
			end
		else
			-- Case 2: Already on platform (rode rising dais), or staying on ground
			AnimationModule.playConfig(hum, "Locomotion.ConfidentWalk", 1.0, Enum.AnimationPriority.Movement)
			hum:MoveTo(Vector3.new(targetPos.X, hrp.Position.Y, targetPos.Z))

			local startT = tick()
			local maxW = math.max(3.0, (totalDist / effectiveSpeed) * 1.8)
			maxW = math.min(maxW, 16.0)
			while (tick() - startT) < maxW do
				local d = (Vector2.new(hrp.Position.X - targetPos.X, hrp.Position.Z - targetPos.Z)).Magnitude
				if d <= 2.5 then break end
				if d <= 30 and hum.WalkSpeed > baseSpeed then
					hum.WalkSpeed = baseSpeed
				end
				task.wait(0.1)
			end
		end

		-- Arrived at mark: stop walking, idle
		hum.WalkSpeed = 0
		hum:MoveTo(hrp.Position)
		AnimationModule.playConfig(hum, "Movement.Idle", 1.0, Enum.AnimationPriority.Idle, true)
		q:SetAttribute("ShowdownStaged", true)

		if lookAtPos then
			local lookCF = CFrame.lookAt(hrp.Position, Vector3.new(lookAtPos.X, hrp.Position.Y, lookAtPos.Z))
			hrp.CFrame = lookCF
		end

		if isSeated then
			pcall(function() hum.Sit = true end)
		end
	end)
end

-- ============================================================
-- UTILITY & FAIRNESS CALCULATION ENGINE
-- ============================================================

-- Compute combat rating based on HP, Class advantage, and Element
local function getCombatRating(quin, opponentQuin)
	if not quin or not quin.Parent then return 0 end
	local hum = quin:FindFirstChildOfClass("Humanoid")
	local currentHp = hum and hum.Health or 100
	local maxHp = hum and hum.MaxHealth or 100
	local hpRatio = currentHp / math.max(1, maxHp)

	local qClass = quin:GetAttribute("QuinClass") or "Striker"
	local oppClass = opponentQuin and opponentQuin:GetAttribute("QuinClass") or "Striker"

	-- Class matchup weighting
	local classMultiplier = 1.0
	if qClass == "Tanker" and oppClass == "Assassin" then classMultiplier = 1.2 end
	if qClass == "Assassin" and oppClass == "Striker" then classMultiplier = 1.2 end
	if qClass == "Striker" and oppClass == "Brawler" then classMultiplier = 1.15 end
	if qClass == "Brawler" and oppClass == "Tanker" then classMultiplier = 1.15 end

	-- Element affinity weighting (Water is primary; Earth/Stone, Fire, Wind, Electric)
	local qElement = quin:GetAttribute("Element") or "Water"
	local oppElement = opponentQuin and opponentQuin:GetAttribute("Element") or "Fire"
	local elementMultiplier = 1.0
	if qElement == "Water" and oppElement == "Fire" then elementMultiplier = 1.25 end
	if qElement == "Fire" and oppElement == "Wind" then elementMultiplier = 1.25 end
	if qElement == "Wind" and oppElement == "Stone" then elementMultiplier = 1.2 end
	if qElement == "Stone" and oppElement == "Lightning" then elementMultiplier = 1.2 end
	if qElement == "Lightning" and oppElement == "Water" then elementMultiplier = 1.25 end

	local streak = quin:GetAttribute("CurrentStreak") or 0
	local streakBonus = 1.0 + math.clamp(streak * 0.05, 0, 0.3)

	return currentHp * classMultiplier * elementMultiplier * streakBonus
end

-- Calculate expected win probability between candidate and lone opponent
function LeaderShowdownSystem.calculateWinProbability(candidate, loneOpponent)
	local ratingA = getCombatRating(candidate, loneOpponent)
	local ratingB = getCombatRating(loneOpponent, candidate)
	if (ratingA + ratingB) <= 0 then return 0.5 end
	return ratingA / (ratingA + ratingB)
end

-- Select the most fair volunteer from the squad (closest to 50/50 win-rate)
-- Or PackLeader if one explicitly claims the duel
function LeaderShowdownSystem.selectChampionVolunteer(squadMembers, loneOpponent)
	local bestCandidate = nil
	local bestDifference = math.huge
	local bestWinRate = 0.5

	-- Priority 1: Check for PackLeader Quirky with sufficient vitality (> 40% HP)
	for _, q in ipairs(squadMembers) do
		local hum = q:FindFirstChildOfClass("Humanoid")
		if hum and hum.Health > (hum.MaxHealth * 0.4) then
			local quirky = q:GetAttribute("Quirky") or q:GetAttribute("AssignedQuirky")
			if quirky == "PackLeader" then
				local winRate = LeaderShowdownSystem.calculateWinProbability(q, loneOpponent)
				return q, winRate, "PackLeader claiming duel"
			end
		end
	end

	-- Priority 2: Fairness-optimized selection (minimizing |WinRate - 0.50|)
	for _, q in ipairs(squadMembers) do
		local hum = q:FindFirstChildOfClass("Humanoid")
		if hum and hum.Health > 15 then
			local winRate = LeaderShowdownSystem.calculateWinProbability(q, loneOpponent)
			local diff = math.abs(winRate - 0.50)
			if diff < bestDifference then
				bestDifference = diff
				bestCandidate = q
				bestWinRate = winRate
			end
		end
	end

	-- Fallback to first alive squad member
	if not bestCandidate and #squadMembers > 0 then
		bestCandidate = squadMembers[1]
		bestWinRate = LeaderShowdownSystem.calculateWinProbability(bestCandidate, loneOpponent)
	end

	return bestCandidate, bestWinRate, string.format("Fairness-calibrated volunteer (Expected WinRate: %.0f%%)", bestWinRate * 100)
end

-- Apply "Second Wind / Gladiator Honor Surge" to ensure duel fairness
function LeaderShowdownSystem.applyDuelFairnessSurge(champion, loneOpponent)
	if not champion or not loneOpponent then return end
	local champHum = champion:FindFirstChildOfClass("Humanoid")
	local loneHum = loneOpponent:FindFirstChildOfClass("Humanoid")
	if not champHum or not loneHum then return end

	-- If the lone opponent survived against overwhelming odds and has low HP (< 60%):
	-- The sacred platform bestows an Elemental Second Wind restoring health to match challenger baseline
	local loneHpRatio = loneHum.Health / math.max(1, loneHum.MaxHealth)
	local champHpRatio = champHum.Health / math.max(1, champHum.MaxHealth)

	if loneHpRatio < 0.60 or loneHum.Health < (champHum.Health * 0.70) then
		local targetHealth = math.clamp(champHum.Health * 0.85, loneHum.MaxHealth * 0.65, loneHum.MaxHealth)
		local healAmount = targetHealth - loneHum.Health
		if healAmount > 0 then
			loneHum.Health = targetHealth
			print(string.format("[LeaderShowdown] Gladiator Second Wind granted to %s! (+%.0f HP)", loneOpponent.Name, healAmount))

			-- Visual Second Wind burst
			local root = loneOpponent:FindFirstChild("HumanoidRootPart")
			if root then
				VfxModule.createShockwave(root, 14, 0.8)
				AudioModule.playDodge(root.Position)

				local hl = Instance.new("Highlight")
				hl.Name = "SecondWindGlow"
				hl.FillColor = Color3.fromRGB(255, 220, 80)
				hl.OutlineColor = Color3.fromRGB(255, 255, 255)
				hl.FillTransparency = 0.4
				hl.Parent = loneOpponent
				Debris:AddItem(hl, 1.8)
			end
		end
	end

	-- Equalize/replenish energy for both duelists
	champion:SetAttribute("CurrentEnergy", 100)
	loneOpponent:SetAttribute("CurrentEnergy", 100)
	champion:SetAttribute("CurrentConfidence", 0.95)
	loneOpponent:SetAttribute("CurrentConfidence", 0.90)
end

-- ============================================================
-- DYNAMIC SHOWDOWN PLATFORM CREATION
-- ============================================================

function LeaderShowdownSystem.createShowdownPlatform(tankerElement)
	tankerElement = tankerElement or "Stone"
	local isStone = (tankerElement == "Stone" or tankerElement == "Earth")
	local isWater = (tankerElement == "Water" or tankerElement == "Ice")

	local model = Instance.new("Model")
	model.Name = "LeaderShowdownDais"

	-- Base cylinder slab (starts submerged beneath arena ground)
	local dais = Instance.new("Part")
	dais.Name = "ShowdownPlatform"
	dais.Shape = Enum.PartType.Cylinder
	dais.Size = Vector3.new(PLATFORM_HEIGHT, PLATFORM_RADIUS * 2, PLATFORM_RADIUS * 2)
	dais.CFrame = CFrame.new(ARENA_CENTER - Vector3.new(0, PLATFORM_HEIGHT + 3, 0)) * CFrame.Angles(0, 0, math.rad(90))
	dais.Anchored = true
	dais.CanCollide = true
	dais.TopSurface = Enum.SurfaceType.Smooth
	dais.BottomSurface = Enum.SurfaceType.Smooth

	if isStone then
		dais.Material = Enum.Material.Slate
		dais.Color = Color3.fromRGB(100, 95, 90)
	elseif isWater then
		dais.Material = Enum.Material.Ice
		dais.Color = Color3.fromRGB(160, 220, 250)
		dais.Transparency = 0.12
	else
		dais.Material = Enum.Material.Cobblestone
		dais.Color = Color3.fromRGB(90, 85, 95)
	end
	dais.Parent = model

	-- Outer Rim Neon Ring Segments (Hollow boundary, preserving visible dais texture)
	local rimSegments = Instance.new("Model")
	rimSegments.Name = "PlatformRimSegments"
	rimSegments.Parent = model

	local ringColor = isWater and Color3.fromRGB(100, 220, 255) or Color3.fromRGB(255, 195, 60)
	local numRimSegments = 32
	for i = 1, numRimSegments do
		local a1 = (i - 1) / numRimSegments * (2 * math.pi)
		local a2 = i / numRimSegments * (2 * math.pi)
		local subY = -PLATFORM_HEIGHT - 3
		local p1 = ARENA_CENTER + Vector3.new(math.cos(a1) * (PLATFORM_RADIUS - 0.4), subY, math.sin(a1) * (PLATFORM_RADIUS - 0.4))
		local p2 = ARENA_CENTER + Vector3.new(math.cos(a2) * (PLATFORM_RADIUS - 0.4), subY, math.sin(a2) * (PLATFORM_RADIUS - 0.4))
		local seg = Instance.new("Part")
		seg.Name = "RimSeg_" .. i
		seg.Size = Vector3.new(0.6, 0.15, (p2 - p1).Magnitude + 0.15)
		seg.CFrame = CFrame.lookAt((p1 + p2) / 2, p2)
		seg.Anchored = true
		seg.CanCollide = false
		seg.Material = Enum.Material.Neon
		seg.Color = ringColor
		seg.Transparency = 0.75
		seg.Parent = rimSegments
	end

	-- Inner Sacred Dueling Ring Segments (Hollow boundary at r = INNER_RING_RADIUS)
	local innerSegments = Instance.new("Model")
	innerSegments.Name = "InnerRingSegments"
	innerSegments.Parent = model

	local numInnerSegments = 28
	local innerColor = isWater and Color3.fromRGB(180, 245, 255) or Color3.fromRGB(255, 225, 100)
	for i = 1, numInnerSegments do
		local a1 = (i - 1) / numInnerSegments * (2 * math.pi)
		local a2 = i / numInnerSegments * (2 * math.pi)
		local subY = -PLATFORM_HEIGHT - 3
		local p1 = ARENA_CENTER + Vector3.new(math.cos(a1) * INNER_RING_RADIUS, subY, math.sin(a1) * INNER_RING_RADIUS)
		local p2 = ARENA_CENTER + Vector3.new(math.cos(a2) * INNER_RING_RADIUS, subY, math.sin(a2) * INNER_RING_RADIUS)
		local seg = Instance.new("Part")
		seg.Name = "InnerSeg_" .. i
		seg.Size = Vector3.new(0.45, 0.12, (p2 - p1).Magnitude + 0.12)
		seg.CFrame = CFrame.lookAt((p1 + p2) / 2, p2)
		seg.Anchored = true
		seg.CanCollide = false
		seg.Material = Enum.Material.Neon
		seg.Color = innerColor
		seg.Transparency = 0.75
		seg.Parent = innerSegments
	end

	model.PrimaryPart = dais
	model.Parent = Workspace

	return model, dais, rimSegments, innerSegments
end

-- ============================================================
-- ASYMMETRIC SHOWDOWN PROTOCOL (4v1, 5v1, 6v1)
-- ============================================================

function LeaderShowdownSystem.initiateAsymmetricShowdown(squadMembers, loneOpponent)
	if LeaderShowdownSystem.isActive then return end
	LeaderShowdownSystem.isActive = true
	LeaderShowdownSystem.activePhase = "Ceasefire"

	print(string.format("[LeaderShowdown] INITIATING SHOWDOWN PROTOCOL: %d vs 1 (%s)", 
		#squadMembers, loneOpponent.Name))

	-- 1. CEASEFIRE: Disengage all combatants
	for _, q in ipairs(squadMembers) do
		q:SetAttribute("LeaderShowdownRole", "Transition")
		q:SetAttribute("CurrentState", "LeaderShowdown")
	end
	loneOpponent:SetAttribute("LeaderShowdownRole", "Transition")
	loneOpponent:SetAttribute("CurrentState", "LeaderShowdown")

	task.wait(PACING.CeasefireDelay)

	-- 2. IDENTIFY TANKER (Stone or Water Tanker preferred)
	local groundSmashTanker = nil
	for _, q in ipairs(squadMembers) do
		local qClass = q:GetAttribute("QuinClass")
		local qElem = q:GetAttribute("Element")
		if qClass == "Tanker" and (qElem == "Stone" or qElem == "Water" or qElem == "Earth" or qElem == "Ice") then
			groundSmashTanker = q
			break
		end
	end
	if not groundSmashTanker then
		for _, q in ipairs(squadMembers) do
			if q:GetAttribute("QuinClass") == "Tanker" then
				groundSmashTanker = q
				break
			end
		end
	end
	if not groundSmashTanker and #squadMembers > 0 then
		groundSmashTanker = squadMembers[1] -- Fallback leader
	end

	local tankerElement = groundSmashTanker and groundSmashTanker:GetAttribute("Element") or "Stone"
	print(string.format("[LeaderShowdown] Platform Creation led by Tanker %s (%s)", groundSmashTanker.Name, tankerElement))

	-- 3. TANKER STRIDE TO ARENA CENTER (Deliberate physical walk, slow and at ease)
	LeaderShowdownSystem.activePhase = "TankerApproach"
	local tankerHRP = groundSmashTanker:FindFirstChild("HumanoidRootPart")
	local tankerHum = groundSmashTanker:FindFirstChildOfClass("Humanoid")
	if tankerHRP and tankerHum then
		local targetPos = Vector3.new(ARENA_CENTER.X, GROUND_STAND_Y, ARENA_CENTER.Z)
		walkToPosition(groundSmashTanker, targetPos, WALK_SPEED.TankerApproach, targetPos + Vector3.new(0, 0, -1), "Locomotion.ConfidentWalk")
		task.wait(0.35) -- Brief breath of calm before the ground smash
	end

	-- 4. GROUND SMASH & ELEMENTAL SHOCKWAVE
	LeaderShowdownSystem.activePhase = "GroundSmash"
	if tankerHRP then
		if tankerHum then
			AnimationModule.playConfig(tankerHum, "Attacks.Kicks.HeavyKick", 1.2, Enum.AnimationPriority.Action)
		end
		task.wait(0.2)
		AudioModule.playSlam(tankerHRP.Position)
		VfxModule.createShockwave(tankerHRP, PLATFORM_RADIUS * 2, 0.85)
		task.wait(PACING.GroundSmashWindup - 0.2)
	end

	-- 5. DYNAMIC PLATFORM ELEVATION & PRE-EXISTING QUINS RISING
	LeaderShowdownSystem.activePhase = "PlatformRise"
	local platformModel, daisPart, rimSegments, innerSegments = LeaderShowdownSystem.createShowdownPlatform(tankerElement)
	LeaderShowdownSystem.currentPlatform = platformModel

	-- Identify ALL Quins currently located inside the dais radius (they ride the platform up!)
	local raisedQuins = {}
	for _, q in ipairs(CollectionService:GetTagged("Quin")) do
		local qHRP = q:FindFirstChild("HumanoidRootPart")
		if qHRP then
			local dist2D = Vector2.new(qHRP.Position.X - ARENA_CENTER.X, qHRP.Position.Z - ARENA_CENTER.Z).Magnitude
			if dist2D <= (PLATFORM_RADIUS - 1.5) then
				table.insert(raisedQuins, q)
				q:SetAttribute("LeaderShowdownPlatformRider", true)
				print(string.format("[LeaderShowdown] Pre-existing Quin riding rising dais: %s (dist: %.1f studs)", q.Name, dist2D))
			end
		end
	end

	-- Target CFrame for elevated dais (top surface sits at DAIS_TOP_Y = 6.50)
	local targetPlatformCFrame = CFrame.new(ARENA_CENTER + Vector3.new(0, PLATFORM_HEIGHT / 2, 0)) * CFrame.Angles(0, 0, math.rad(90))
	local riseTween = TweenService:Create(daisPart, TweenInfo.new(PACING.PlatformElevation, Enum.EasingStyle.Cubic, Enum.EasingDirection.Out), {
		CFrame = targetPlatformCFrame
	})
	riseTween:Play()

	-- Elevate ring segments to rest cleanly on top of dais surface
	local elevationDelta = PLATFORM_HEIGHT + 3 + (PLATFORM_HEIGHT / 2) + 0.05
	for _, seg in ipairs(rimSegments:GetChildren()) do
		if seg:IsA("BasePart") then
			local t = TweenService:Create(seg, TweenInfo.new(PACING.PlatformElevation, Enum.EasingStyle.Cubic, Enum.EasingDirection.Out), {
				CFrame = seg.CFrame + Vector3.new(0, elevationDelta, 0)
			})
			t:Play()
		end
	end
	for _, seg in ipairs(innerSegments:GetChildren()) do
		if seg:IsA("BasePart") then
			local t = TweenService:Create(seg, TweenInfo.new(PACING.PlatformElevation, Enum.EasingStyle.Cubic, Enum.EasingDirection.Out), {
				CFrame = seg.CFrame + Vector3.new(0, elevationDelta, 0)
			})
			t:Play()
		end
	end

	-- Concurrently elevate all Quins who were already inside the radius
	for _, q in ipairs(raisedQuins) do
		local qHRP = q:FindFirstChild("HumanoidRootPart")
		if qHRP then
			local currentPos = qHRP.Position
			local elevatedTarget = Vector3.new(currentPos.X, currentPos.Y + PLATFORM_HEIGHT, currentPos.Z)
			local qRiseTween = TweenService:Create(qHRP, TweenInfo.new(PACING.PlatformElevation, Enum.EasingStyle.Cubic, Enum.EasingDirection.Out), {
				CFrame = CFrame.new(elevatedTarget) * (qHRP.CFrame - qHRP.Position)
			})
			qRiseTween:Play()
		end
	end

	task.wait(PACING.PlatformElevation)

	-- 6. TANKER UNFURLS PERIMETER RING
	LeaderShowdownSystem.activePhase = "PerimeterUnfurl"
	if tankerHRP and tankerHum then
		AudioModule.playClash(ARENA_CENTER)
		for _, seg in ipairs(rimSegments:GetChildren()) do
			if seg:IsA("BasePart") then
				local t = TweenService:Create(seg, TweenInfo.new(PACING.PerimeterUnfurlTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
					Transparency = 0.20
				})
				t:Play()
			end
		end
		for _, seg in ipairs(innerSegments:GetChildren()) do
			if seg:IsA("BasePart") then
				local t = TweenService:Create(seg, TweenInfo.new(PACING.PerimeterUnfurlTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
					Transparency = 0.15
				})
				t:Play()
			end
		end
		task.wait(PACING.PerimeterUnfurlTime)
	end

	-- 7. VOLUNTEER SELECTION VIA FAIRNESS ENGINE
	local championVolunteer, winRate, selectionReason = LeaderShowdownSystem.selectChampionVolunteer(squadMembers, loneOpponent)
	print(string.format("[LeaderShowdown] Champion Volunteer: %s (%s)", championVolunteer.Name, selectionReason))

	-- 8. ORGANIC QUIRKY-DRIVEN SPECTATOR STAGING & DUELIST POSITIONING
	LeaderShowdownSystem.activePhase = "RingFormation"
	local perimeterQuins = {}
	for _, q in ipairs(squadMembers) do
		if q ~= championVolunteer then
			table.insert(perimeterQuins, q)
		end
	end

	local numPerimeter = #perimeterQuins
	for idx, q in ipairs(perimeterQuins) do
		local qHRP = q:FindFirstChild("HumanoidRootPart")
		local qHum = q:FindFirstChildOfClass("Humanoid")
		local quirky = q:GetAttribute("Quirky") or q:GetAttribute("AssignedQuirky") or "Observer"
		local wasOnPlatform = (q:GetAttribute("LeaderShowdownPlatformRider") == true)

		-- Quirky Leisure Choice: Hop on platform vs stay on ground vs sit
		local choosePlatform = false
		local isSeated = false

		if wasOnPlatform then
			-- Already elevated on the dais: stay on dais rim
			choosePlatform = true
		else
			-- On the ground: Quirky drives the leisure decision
			if quirky == "Lazy" then
				-- Lazy: stays on ground, relaxes near the dais base
				choosePlatform = false
				isSeated = true
			elseif quirky == "LoneWolf" then
				-- LoneWolf: detached solitary spectator on the ground
				choosePlatform = false
			elseif quirky == "Showoff" or quirky == "Follower" then
				-- Energetic Quins hop onto the platform rim to cheer/flex
				choosePlatform = true
			elseif quirky == "Observer" then
				-- 50% chance to hop onto dais or observe from floor
				choosePlatform = (idx % 2 == 1)
			else
				choosePlatform = true
			end
		end

		-- Organic angular distribution with jitter and natural clustering
		local baseAngle = ((idx - 1) / math.max(1, numPerimeter)) * (2 * math.pi)
		local jitter = ((idx % 2 == 0) and 0.22 or -0.20) + (math.sin(idx * 1.7) * 0.12)
		local finalAngle = baseAngle + jitter

		-- Varied radial distance (not rigid compass rose)
		local targetRadius = 0
		local targetY = 0

		if choosePlatform then
			-- On the elevated platform rim (r in [40.5, 44.5] within 48-stud dais)
			targetRadius = 41.5 + ((idx % 3) * 1.5)
			targetY = PLATFORM_STAND_Y
			q:SetAttribute("SpectatorPlatformStatus", "OnPlatform")
		else
			-- Down on the arena ground
			if isSeated then
				targetRadius = 52.0  -- Near dais base
				targetY = GROUND_SIT_Y
				q:SetAttribute("SpectatorPlatformStatus", "OnGround")
			else
				targetRadius = 54.0 + ((idx % 2) * 5.0)  -- 54 to 59 studs on ground
				targetY = GROUND_STAND_Y
				q:SetAttribute("SpectatorPlatformStatus", "OnGround")
			end
		end

		local targetPos = ARENA_CENTER + Vector3.new(math.cos(finalAngle) * targetRadius, targetY - ARENA_CENTER.Y, math.sin(finalAngle) * targetRadius)
		local lookAtCenter = CFrame.lookAt(targetPos, Vector3.new(ARENA_CENTER.X, targetPos.Y, ARENA_CENTER.Z))

		if qHRP then
			q:SetAttribute("LeaderShowdownRole", "PerimeterGuard")
			q:SetAttribute("PerimeterAngle", finalAngle)
			q:SetAttribute("SpectatorRadius", targetRadius)

			-- Physical concurrent walk/hop to designated spectator spot
			stageQuinToSpot(q, targetPos, WALK_SPEED.SpectatorStaging, Vector3.new(ARENA_CENTER.X, targetPos.Y, ARENA_CENTER.Z), choosePlatform, isSeated)
		end
	end

	-- Position Lone Opponent at South dueling mark inside inner ring (r = 15 studs)
	local loneHRP = loneOpponent:FindFirstChild("HumanoidRootPart")
	if loneHRP then
		local lonePos = ARENA_CENTER + Vector3.new(0, PLATFORM_STAND_Y - ARENA_CENTER.Y, 15.0)
		-- Physical concurrent walk/hop onto platform to dueling spot
		stageQuinToSpot(loneOpponent, lonePos, WALK_SPEED.OpponentStride, ARENA_CENTER, true, false)
	end

	-- Dynamic unhurried staging wait: wait until duelists and spectators arrive at their marks
	local stageStart = tick()
	local maxStageWait = math.max(PACING.SquadStagingDuration, 8.0)
	while (tick() - stageStart) < maxStageWait do
		local allDone = (loneOpponent:GetAttribute("ShowdownStaged") == true)
		if allDone then
			for _, q in ipairs(perimeterQuins) do
				if q:GetAttribute("ShowdownStaged") ~= true then
					allDone = false
					break
				end
			end
		end
		if allDone then break end
		task.wait(0.2)
	end

	-- 9. CHAMPION STEPS FORWARD TO VOLUNTEER (North dueling mark inside inner ring)
	LeaderShowdownSystem.activePhase = "ChampionVolunteer"
	local champHRP = championVolunteer:FindFirstChild("HumanoidRootPart")
	local champHum = championVolunteer:FindFirstChildOfClass("Humanoid")
	if champHRP then
		championVolunteer:SetAttribute("LeaderShowdownRole", "Duelist")
		local champDuelPos = ARENA_CENTER + Vector3.new(0, PLATFORM_STAND_Y - ARENA_CENTER.Y, -15.0)
		local loneLookPos = loneHRP and loneHRP.Position or ARENA_CENTER

		-- Deliberate, confident walk forward to the dueling line
		walkToPosition(championVolunteer, champDuelPos, WALK_SPEED.ChampionStride, loneLookPos, "Locomotion.ConfidentWalk")
		task.wait(0.3)
	end

	-- 10. FAIRNESS ENGINE: GLADIATOR SECOND WIND / HP EQUALIZATION
	LeaderShowdownSystem.activePhase = "FairnessSurge"
	LeaderShowdownSystem.applyDuelFairnessSurge(championVolunteer, loneOpponent)
	task.wait(PACING.FairnessSurgePause)

	-- 11. PRE-DUEL STANDOFF GAZE & AURA FLARE
	LeaderShowdownSystem.activePhase = "DuelStandoff"
	championVolunteer:SetAttribute("CurrentTarget", loneOpponent.Name)
	championVolunteer:SetAttribute("TargetQuin", loneOpponent.Name)
	loneOpponent:SetAttribute("CurrentTarget", championVolunteer.Name)
	loneOpponent:SetAttribute("TargetQuin", championVolunteer.Name)
	loneOpponent:SetAttribute("LeaderShowdownRole", "Duelist")

	AudioModule.playClash(ARENA_CENTER)
	task.wait(PACING.PreDuelStandoffGaze)

	-- 12. COMBAT RESUME: 1v1 DUEL ACTIVE
	LeaderShowdownSystem.activePhase = "DuelActive"
	workspace:SetAttribute("LeaderShowdownActive", true)
	championVolunteer:SetAttribute("LeaderShowdownRole", "Duelist")
	loneOpponent:SetAttribute("LeaderShowdownRole", "Duelist")

	-- Strict jump suppression: forbid all jumps for showdown duelists
	local cHum = championVolunteer:FindFirstChildOfClass("Humanoid")
	local lHum = loneOpponent:FindFirstChildOfClass("Humanoid")
	if cHum then
		cHum.UseJumpPower = true
		cHum.JumpPower = 0
		cHum.JumpHeight = 0
	end
	if lHum then
		lHum.UseJumpPower = true
		lHum.JumpPower = 0
		lHum.JumpHeight = 0
	end
	championVolunteer:SetAttribute("EnableProjectileJump", false)
	loneOpponent:SetAttribute("EnableProjectileJump", false)

	championVolunteer:SetAttribute("ForceState", "Fight")
	loneOpponent:SetAttribute("ForceState", "Fight")
	championVolunteer:SetAttribute("CurrentState", "Fight")
	loneOpponent:SetAttribute("CurrentState", "Fight")

	print(string.format("[LeaderShowdown] 1v1 SHOWDOWN COMMENCED: %s vs %s! (Platform R = %.0f, Inner Dueling Ring = %.0f)", 
		championVolunteer.Name, loneOpponent.Name, PLATFORM_RADIUS, INNER_RING_RADIUS))
end

-- ============================================================
-- SYMMETRICAL 1v1 SACRED REFEREE DESCENT PROTOCOL
-- ============================================================

function LeaderShowdownSystem.initiate1v1RefereeProtocol(quinA, quinB)
	if LeaderShowdownSystem.isActive then return end
	LeaderShowdownSystem.isActive = true
	LeaderShowdownSystem.activePhase = "1v1RefereeDescent"

	print(string.format("[LeaderShowdown] SACRED 1v1 PROTOCOL: %s vs %s! Referees descending from 4 walls!",
		quinA.Name, quinB.Name))

	-- Freeze duelists in standoff
	quinA:SetAttribute("LeaderShowdownRole", "Duelist")
	quinA:SetAttribute("CurrentState", "LeaderShowdown")
	quinB:SetAttribute("LeaderShowdownRole", "Duelist")
	quinB:SetAttribute("CurrentState", "LeaderShowdown")

	local hrpA = quinA:FindFirstChild("HumanoidRootPart")
	local hrpB = quinB:FindFirstChild("HumanoidRootPart")
	if hrpA and hrpB then
		hrpA.CFrame = CFrame.lookAt(ARENA_CENTER + Vector3.new(0, GROUND_STAND_Y - ARENA_CENTER.Y, -16), ARENA_CENTER)
		hrpB.CFrame = CFrame.lookAt(ARENA_CENTER + Vector3.new(0, GROUND_STAND_Y - ARENA_CENTER.Y, 16), ARENA_CENTER)
	end

	-- Spawn 4 Referees atop the 4 walls
	local cardinals = { "North", "South", "East", "West" }
	local landingOffsets = {
		North = Vector3.new(0, GROUND_STAND_Y - ARENA_CENTER.Y, -PLATFORM_RADIUS),
		South = Vector3.new(0, GROUND_STAND_Y - ARENA_CENTER.Y, PLATFORM_RADIUS),
		East  = Vector3.new(PLATFORM_RADIUS, GROUND_STAND_Y - ARENA_CENTER.Y, 0),
		West  = Vector3.new(-PLATFORM_RADIUS, GROUND_STAND_Y - ARENA_CENTER.Y, 0),
	}

	local refereeParts = {}
	local refFolder = Instance.new("Folder")
	refFolder.Name = "ShowdownReferees"
	refFolder.Parent = Workspace

	for _, card in ipairs(cardinals) do
		local refPart = Instance.new("Part")
		refPart.Name = "Referee_" .. card
		refPart.Size = Vector3.new(3, 6, 3)
		refPart.CFrame = CFrame.new(REFEREE_WALL_PERCHES[card])
		refPart.Anchored = true
		refPart.CanCollide = false
		refPart.Material = Enum.Material.Neon
		refPart.Color = Color3.fromRGB(255, 215, 0) -- Sacred Gold
		refPart.Parent = refFolder

		local trail = Instance.new("Trail")
		local a0 = Instance.new("Attachment", refPart)
		local a1 = Instance.new("Attachment", refPart)
		a0.Position = Vector3.new(0, 2.5, 0)
		a1.Position = Vector3.new(0, -2.5, 0)
		trail.Attachment0 = a0
		trail.Attachment1 = a1
		trail.Color = ColorSequence.new(Color3.fromRGB(255, 230, 100), Color3.fromRGB(255, 255, 255))
		trail.Lifetime = 0.6
		trail.Parent = refPart

		table.insert(refereeParts, { part = refPart, target = ARENA_CENTER + landingOffsets[card] })
	end

	task.wait(PACING.CeasefireDelay)

	-- Synchronized high-altitude dive
	for _, ref in ipairs(refereeParts) do
		local diveTween = TweenService:Create(ref.part, TweenInfo.new(PACING.RefereeDiveDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			CFrame = CFrame.lookAt(ref.target, ARENA_CENTER)
		})
		diveTween:Play()
	end
	task.wait(PACING.RefereeDiveDuration)

	-- 3-point superhero landing impact
	for _, ref in ipairs(refereeParts) do
		VfxModule.createShockwave(ref.part, 14, 0.6)
		AudioModule.playSlam(ref.part.Position)
	end

	-- Channel luminous boundary ring connecting the 4 Referees
	local ring = Instance.new("Part")
	ring.Name = "RefereeSacredRing"
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(0.6, PLATFORM_RADIUS * 2, PLATFORM_RADIUS * 2)
	ring.CFrame = CFrame.new(ARENA_CENTER + Vector3.new(0, 0.5, 0)) * CFrame.Angles(0, 0, math.rad(90))
	ring.Anchored = true
	ring.CanCollide = false
	ring.Material = Enum.Material.Neon
	ring.Color = Color3.fromRGB(255, 220, 50)
	ring.Transparency = 0.5
	ring.Parent = refFolder

	-- Standoff & Duel start
	task.wait(PACING.PreDuelStandoffGaze)
	LeaderShowdownSystem.applyDuelFairnessSurge(quinA, quinB)

	workspace:SetAttribute("LeaderShowdownActive", true)
	quinA:SetAttribute("LeaderShowdownRole", "Duelist")
	quinB:SetAttribute("LeaderShowdownRole", "Duelist")

	local humA = quinA:FindFirstChildOfClass("Humanoid")
	local humB = quinB:FindFirstChildOfClass("Humanoid")
	if humA then
		humA.UseJumpPower = true
		humA.JumpPower = 0
		humA.JumpHeight = 0
	end
	if humB then
		humB.UseJumpPower = true
		humB.JumpPower = 0
		humB.JumpHeight = 0
	end
	quinA:SetAttribute("EnableProjectileJump", false)
	quinB:SetAttribute("EnableProjectileJump", false)

	quinA:SetAttribute("CurrentTarget", quinB.Name)
	quinA:SetAttribute("TargetQuin", quinB.Name)
	quinB:SetAttribute("CurrentTarget", quinA.Name)
	quinA:SetAttribute("ForceState", "Fight")
	quinB:SetAttribute("ForceState", "Fight")
	quinA:SetAttribute("CurrentState", "Fight")
	quinB:SetAttribute("CurrentState", "Fight")

	LeaderShowdownSystem.activePhase = "DuelActive"
	print("[LeaderShowdown] SACRED 1v1 REFEREE DUEL COMMENCED!")
end

-- ============================================================
-- SACRED RING CONTAINMENT ENGINE (Pure Grounded Duel, Zero Out-Of-Ring)
-- ============================================================

function LeaderShowdownSystem.constrainToRing(rootPart)
	if not rootPart then return false end
	local pos = rootPart.Position
	local offset = Vector3.new(pos.X - ARENA_CENTER.X, 0, pos.Z - ARENA_CENTER.Z)
	local dist = offset.Magnitude
	local clamped = false

	-- 1. Horizontal Ring Containment (Strict boundary at INNER_RING_RADIUS = 36.0 studs within 48-stud dais)
	if dist > INNER_RING_RADIUS then
		local normal = offset.Unit
		local clampedX = ARENA_CENTER.X + normal.X * INNER_RING_RADIUS
		local clampedZ = ARENA_CENTER.Z + normal.Z * INNER_RING_RADIUS
		
		-- Reposition smoothly back inside perimeter line
		rootPart.CFrame = CFrame.new(clampedX, pos.Y, clampedZ) * (rootPart.CFrame - rootPart.CFrame.Position)
		
		-- Inward deflection impulse: cancel outward momentum and bounce firmly inward
		local vel = rootPart.AssemblyLinearVelocity
		local outwardDot = vel.X * normal.X + vel.Z * normal.Z
		if outwardDot > 0 then
			local inwardVel = Vector3.new(vel.X - normal.X * outwardDot * 1.8, vel.Y, vel.Z - normal.Z * outwardDot * 1.8)
			rootPart.AssemblyLinearVelocity = inwardVel
		end
		clamped = true
	end

	-- 2. Vertical Floor Safety & Ceiling Clamp: keep duel grounded on top of the elevated dais
	-- Ceiling clamp: prevent duelist from rocketing into orbit during knockback
	if pos.Y > (DAIS_TOP_Y + 14.0) then
		rootPart.CFrame = CFrame.new(rootPart.Position.X, DAIS_TOP_Y + 12.0, rootPart.Position.Z) * (rootPart.CFrame - rootPart.CFrame.Position)
		local vel = rootPart.AssemblyLinearVelocity
		if vel.Y > 0 then
			rootPart.AssemblyLinearVelocity = Vector3.new(vel.X, -15, vel.Z)
		end
		clamped = true
	end

	-- Floor clamp: ensure duelist stays grounded on top of elevated dais (no clipping beneath surface)
	if pos.Y < (DAIS_TOP_Y + 3.0) then
		rootPart.CFrame = CFrame.new(rootPart.Position.X, PLATFORM_STAND_Y, rootPart.Position.Z) * (rootPart.CFrame - rootPart.CFrame.Position)
		local vel = rootPart.AssemblyLinearVelocity
		if vel.Y < 0 then
			rootPart.AssemblyLinearVelocity = Vector3.new(vel.X, 0, vel.Z)
		end
		clamped = true
	end

	return clamped
end

-- ============================================================
-- CLEANUP / RESET
-- ============================================================

function LeaderShowdownSystem.reset()
	LeaderShowdownSystem.isActive = false
	LeaderShowdownSystem.activePhase = "None"
	workspace:SetAttribute("LeaderShowdownActive", false)

	if LeaderShowdownSystem.currentPlatform then
		LeaderShowdownSystem.currentPlatform:Destroy()
		LeaderShowdownSystem.currentPlatform = nil
	end
	local refFolder = Workspace:FindFirstChild("ShowdownReferees")
	if refFolder then refFolder:Destroy() end

	for _, quin in ipairs(CollectionService:GetTagged("Quin")) do
		quin:SetAttribute("LeaderShowdownRole", nil)
		quin:SetAttribute("PerimeterAngle", nil)
		quin:SetAttribute("SpectatorPlatformStatus", nil)
		quin:SetAttribute("SpectatorRadius", nil)
		quin:SetAttribute("LeaderShowdownPlatformRider", nil)
		quin:SetAttribute("EnableProjectileJump", true)

		local hum = quin:FindFirstChildOfClass("Humanoid")
		if hum then
			pcall(function() hum.Sit = false end)
			hum.JumpPower = 50
			hum.JumpHeight = 7.2
		end
	end
end

_G.LeaderShowdownSystem = LeaderShowdownSystem
shared.LeaderShowdownSystem = LeaderShowdownSystem

return LeaderShowdownSystem
