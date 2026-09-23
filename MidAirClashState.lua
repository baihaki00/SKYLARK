--// MidAirClashState.lua
-- Dragon Ball Z / Anime Style Mid-Air Aerial Brawling State Machine
-- Features: Anti-gravity suspension, rapid strike flurries, dynamic XYZ mid-air flash-step relocations,
-- and two dramatic climax resolutions: Mutual Tie blast-back OR Meteor Downward Smash into ground recovery.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")

local AnimationModule = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("AnimationModule"))
local AudioModule = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("AudioModule"))
local VfxModule = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("VfxModule"))
local KnockbackModule = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("KnockbackModule"))
local DamageModule = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("DamageModule"))
local TargetingModule = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("TargetingModule"))
local AnimationIds = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("AnimationIds"))
local CombatConfig = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("CombatConfig"))
local SpatialModule = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("SpatialModule"))

local MidAirClashState = { name = "MidAirClash" }

local clashData = {}

local function cleanupMovers(rootPart)
	for _, child in ipairs(rootPart:GetChildren()) do
		if child.Name == "MidAir_AntiGrav" or child.Name == "MidAir_Att" or child.Name == "MidAir_Gyro" or child.Name == "MidAir_Align" or child.Name == "MidAir_Pos" then
			child:Destroy()
		end
	end
end

function MidAirClashState.enter(fighter, humanoid, rootPart)
	humanoid.PlatformStand = true
	cleanupMovers(rootPart)
	
	-- 1. Anti-gravity: suspend fighter in mid-air
	local att = Instance.new("Attachment")
	att.Name = "MidAir_Att"
	att.Parent = rootPart
	
	local antiGrav = Instance.new("LinearVelocity")
	antiGrav.Name = "MidAir_AntiGrav"
	antiGrav.Attachment0 = att
	antiGrav.VelocityConstraintMode = Enum.VelocityConstraintMode.Line
	antiGrav.LineDirection = Vector3.new(0, 1, 0)
	antiGrav.LineVelocity = 0
	antiGrav.MaxForce = 1e7
	antiGrav.Parent = rootPart
	
	local ao = Instance.new("AlignOrientation")
	ao.Name = "MidAir_Align"
	ao.Mode = Enum.OrientationAlignmentMode.OneAttachment
	ao.Attachment0 = att
	ao.MaxTorque = 1e7
	ao.Responsiveness = 40
	ao.Parent = rootPart
	
	-- 2. Identify partner and establish Leader/Follower role
	local targetName = fighter:GetAttribute("TargetQuin")
	local target = nil
	if targetName then
		local serverFolder = Workspace:FindFirstChild("QuinServer") or Workspace
		target = serverFolder:FindFirstChild(targetName)
	end
	if not target then
		target, _ = TargetingModule.getNearest(rootPart, 100)
	end
	
	local role = "Leader"
	local partnerFighter = target
	
	if target and target:IsA("Model") then
		local targetHRP = target:FindFirstChild("HumanoidRootPart")
		if targetHRP then
			-- If target is already Leader of a clash, become Follower
			if target:GetAttribute("MidAirClashRole") == "Leader" and target:GetAttribute("MidAirClashPartner") == fighter.Name then
				role = "Follower"
			else
				-- We are Leader: ensure target is linked and pulled into MidAirClash
				role = "Leader"
				fighter:SetAttribute("MidAirClashRole", "Leader")
				fighter:SetAttribute("MidAirClashPartner", target.Name)
				target:SetAttribute("MidAirClashRole", "Follower")
				target:SetAttribute("MidAirClashPartner", fighter.Name)
				target:SetAttribute("ForceState", "MidAirClash")
				
				-- Set initial mid-air center point (ensure elevated at least Y=30)
				local midY = math.max(30, (rootPart.Position.Y + targetHRP.Position.Y) / 2)
				local midX = (rootPart.Position.X + targetHRP.Position.X) / 2
				local midZ = (rootPart.Position.Z + targetHRP.Position.Z) / 2
				local center = Vector3.new(midX, midY, midZ)
				
				fighter:SetAttribute("ClashCenterX", center.X)
				fighter:SetAttribute("ClashCenterY", center.Y)
				fighter:SetAttribute("ClashCenterZ", center.Z)
				fighter:SetAttribute("ClashPhase", "Init")
				fighter:SetAttribute("ClashPhaseStart", tick())
				fighter:SetAttribute("ClashRelocations", 0)
			end
		end
	end
	
	fighter:SetAttribute("CurrentState", "MidAirClash")
	
	clashData[fighter] = {
		startTime = tick(),
		target = target,
		role = role,
		phase = "Init",
		phaseStart = tick(),
		strikesDelivered = 0,
		relocationsDone = 0,
		maxRelocations = 2, -- 2 dynamic XYZ jumps during brawl
		nextStrikeTime = tick() + 0.15,
		winnerName = nil,
		animTrack = nil
	}
	
	rootPart.AssemblyLinearVelocity = Vector3.zero
	rootPart.AssemblyAngularVelocity = Vector3.zero
end

function MidAirClashState.exit(fighter, humanoid, rootPart)
	humanoid.PlatformStand = false
	cleanupMovers(rootPart)
	
	local data = clashData[fighter]
	if data and data.animTrack then
		data.animTrack:Stop(0.1)
	end
	
	fighter:SetAttribute("MidAirClashRole", nil)
	fighter:SetAttribute("MidAirClashPartner", nil)
	fighter:SetAttribute("ClashCenterX", nil)
	fighter:SetAttribute("ClashCenterY", nil)
	fighter:SetAttribute("ClashCenterZ", nil)
	fighter:SetAttribute("ClashPhase", nil)
	fighter:SetAttribute("ClashPhaseStart", nil)
	fighter:SetAttribute("ClashRelocations", nil)
	fighter:SetAttribute("ClashWinner", nil)
	
	clashData[fighter] = nil
end

local function switchPhase(data, newPhase)
	data.phase = newPhase
	data.phaseStart = tick()
end

function MidAirClashState.update(fighter, humanoid, rootPart, DEBUG)
	local data = clashData[fighter]
	if not data then return require(script.Parent:WaitForChild("AirborneState")) end
	
	local target = data.target
	if not target or not target.Parent then
		return require(script.Parent:WaitForChild("AirborneState"))
	end
	
	local targetHum = target:FindFirstChildOfClass("Humanoid")
	local targetHRP = target:FindFirstChild("HumanoidRootPart")
	if not targetHum or targetHum.Health <= 0 or not targetHRP then
		return require(script.Parent:WaitForChild("AirborneState"))
	end
	
	local now = tick()
	local timeInPhase = now - data.phaseStart
	local totalElapsed = now - data.startTime
	
	-- Sync Follower state from Leader attributes
	local leaderModel = (data.role == "Leader") and fighter or target
	local centerX = leaderModel:GetAttribute("ClashCenterX") or rootPart.Position.X
	local centerY = leaderModel:GetAttribute("ClashCenterY") or rootPart.Position.Y
	local centerZ = leaderModel:GetAttribute("ClashCenterZ") or rootPart.Position.Z
	local clashCenter = Vector3.new(centerX, centerY, centerZ)
	
	-- Continuous Face-off rotation
	local ao = rootPart:FindFirstChild("MidAir_Align")
	if ao then
		ao.CFrame = CFrame.lookAt(rootPart.Position, Vector3.new(targetHRP.Position.X, rootPart.Position.Y, targetHRP.Position.Z))
	end
	
	-- ============================================================
	-- PHASE 1: INIT (Position fighters 3.8 studs apart at anchor)
	-- ============================================================
	if data.phase == "Init" then
		local lookDir = (targetHRP.Position - rootPart.Position)
		local flatDir = Vector3.new(lookDir.X, 0, lookDir.Z)
		if flatDir.Magnitude < 0.1 then flatDir = Vector3.new(1, 0, 0) else flatDir = flatDir.Unit end
		
		-- Leader sits on one side, Follower on the other
		local offsetDir = (data.role == "Leader") and -flatDir or flatDir
		local targetPos = clashCenter + (offsetDir * 1.9)
		rootPart.CFrame = CFrame.lookAt(targetPos, clashCenter)
		rootPart.AssemblyLinearVelocity = Vector3.zero
		
		if timeInPhase > 0.2 then
			switchPhase(data, "Flurry")
			data.strikesDelivered = 0
			data.nextStrikeTime = now + 0.05
		end
		
	-- ============================================================
	-- PHASE 2: FLURRY (Rapid strike exchanges at current anchor)
	-- ============================================================
	elseif data.phase == "Flurry" then
		-- Keep anchored at combat spacing
		local dist = (rootPart.Position - targetHRP.Position).Magnitude
		if dist > 5.0 or dist < 2.5 then
			local toTarget = (targetHRP.Position - rootPart.Position)
			local flatToTarget = Vector3.new(toTarget.X, 0, toTarget.Z)
			if flatToTarget.Magnitude > 0.01 then
				local desiredPos = targetHRP.Position - (flatToTarget.Unit * 3.8)
				rootPart.CFrame = CFrame.lookAt(Vector3.new(desiredPos.X, clashCenter.Y, desiredPos.Z), targetHRP.Position)
			end
		end
		
		-- Strike delivery loop
		if now >= data.nextStrikeTime then
			data.nextStrikeTime = now + math.random(18, 26) / 100 -- every 0.18 - 0.26s
			data.strikesDelivered = data.strikesDelivered + 1
			
			-- Alternate punches and kicks
			local punchList = AnimationIds.Punches or {}
			local kickList = AnimationIds.Kicks or {}
			local animId = (data.strikesDelivered % 2 == 1 and #punchList > 0)
				and punchList[math.random(1, #punchList)]
				or kickList[math.random(1, math.max(1, #kickList))]
			
			if animId then
				AnimationModule.play(humanoid, animId, Enum.AnimationPriority.Action4, false, 1.4)
			end
			
			-- Sound & micro impact
			local midPoint = (rootPart.Position + targetHRP.Position) / 2
			AudioModule.playSlam(midPoint)
			VfxModule.createShockwave(midPoint, 5, 0.15)
			VfxModule.shakeScreen(rootPart.Position, 200, 4)
			
			-- Chip damage
			if data.role == "Leader" and targetHum then
				targetHum:TakeDamage(4)
			elseif data.role == "Follower" and humanoid then
				humanoid:TakeDamage(4)
			end
		end
		
		-- After 4-5 rapid strikes at this anchor point:
		if data.strikesDelivered >= 4 then
			if data.relocationsDone < data.maxRelocations then
				switchPhase(data, "Relocate")
			else
				switchPhase(data, "Climax")
			end
		end
		
	-- ============================================================
	-- PHASE 3: RELOCATE (Anime Flash-Step / Z-Burst to new XYZ)
	-- ============================================================
	elseif data.phase == "Relocate" then
		if data.role == "Leader" then
			-- Calculate dynamic 3D offset: jumps 15 to 25 studs in mid-air
			local angle = math.random() * math.pi * 2
			local horizDist = math.random(16, 26)
			local newX = math.clamp(clashCenter.X + math.cos(angle) * horizDist, -180, 180)
			local newZ = math.clamp(clashCenter.Z + math.sin(angle) * horizDist, -180, 180)
			local newY = math.clamp(clashCenter.Y + math.random(-6, 14), 28, 70)
			local newCenter = Vector3.new(newX, newY, newZ)
			
			fighter:SetAttribute("ClashCenterX", newCenter.X)
			fighter:SetAttribute("ClashCenterY", newCenter.Y)
			fighter:SetAttribute("ClashCenterZ", newCenter.Z)
		end
		
		-- Audio & VFX for the mid-air flash-step
		AudioModule.playSonicBoom(rootPart.Position)
		AudioModule.playMidairSwoosh(rootPart.Position)
		VfxModule.createVaporCone(rootPart, 0.25)
		
		-- Reposition to new anchor
		local updatedCenter = Vector3.new(
			leaderModel:GetAttribute("ClashCenterX") or clashCenter.X,
			leaderModel:GetAttribute("ClashCenterY") or clashCenter.Y,
			leaderModel:GetAttribute("ClashCenterZ") or clashCenter.Z
		)
		
		local flatDir = Vector3.new(math.random() - 0.5, 0, math.random() - 0.5).Unit
		local offsetDir = (data.role == "Leader") and -flatDir or flatDir
		local newPos = updatedCenter + (offsetDir * 1.9)
		rootPart.CFrame = CFrame.lookAt(newPos, updatedCenter)
		rootPart.AssemblyLinearVelocity = Vector3.zero
		
		data.relocationsDone = data.relocationsDone + 1
		data.strikesDelivered = 0
		data.nextStrikeTime = now + 0.1
		switchPhase(data, "Flurry")
		
	-- ============================================================
	-- PHASE 4: CLIMAX (Tie Blast-back OR Meteor Downward Smash)
	-- ============================================================
	elseif data.phase == "Climax" then
		if data.role == "Leader" and not data.winnerName then
			-- 40% Tie, 60% Meteor Slam
			local roll = math.random()
			if roll < 0.40 then
				data.winnerName = "Tie"
			else
				-- Pick winner (higher HP or 50/50)
				local myHp = humanoid.Health
				local oppHp = targetHum.Health
				if myHp > oppHp then
					data.winnerName = fighter.Name
				elseif oppHp > myHp then
					data.winnerName = target.Name
				else
					data.winnerName = (math.random() > 0.5) and fighter.Name or target.Name
				end
			end
			fighter:SetAttribute("ClashWinner", data.winnerName)
		else
			data.winnerName = leaderModel:GetAttribute("ClashWinner") or "Tie"
		end
		
		local midPoint = (rootPart.Position + targetHRP.Position) / 2
		
		-- RESOLUTION 1: MUTUAL TIE BLAST-BACK
		if data.winnerName == "Tie" then
			AudioModule.playSonicBoom(midPoint)
			VfxModule.createLaunchShockwave(midPoint)
			VfxModule.shakeScreen(midPoint, 600, 12)
			
			local awayDir = (rootPart.Position - targetHRP.Position)
			local flatAway = Vector3.new(awayDir.X, 0.2, awayDir.Z).Unit
			
			cleanupMovers(rootPart)
			fighter:SetAttribute("KnockbackType", "air")
			fighter:SetAttribute("ForceState", "Knockback")
			KnockbackModule.applyKnockback(fighter, flatAway, 110, 0.5)
			return require(script.Parent:WaitForChild("KnockbackState"))
			
		-- RESOLUTION 2: METEOR DOWNWARD SMASH
		else
			local isWinner = (fighter.Name == data.winnerName)
			
			if isWinner then
				-- WINNER: Heavy downward axe kick / slam
				cleanupMovers(rootPart)
				local kickAnim = AnimationIds.Kicks and AnimationIds.Kicks[3] or AnimationIds.Attack
				if kickAnim then
					AnimationModule.play(humanoid, kickAnim, Enum.AnimationPriority.Action4, false, 1.3)
				end
				AudioModule.playSlam(rootPart.Position)
				VfxModule.createShockwave(midPoint, 10, 0.3)
				VfxModule.shakeScreen(rootPart.Position, 500, 10)
				
				-- Hover in air momentarily then drop to re-engage
				task.delay(0.45, function()
					if humanoid and humanoid.Health > 0 then
						humanoid.PlatformStand = false
					end
				end)
				
				return require(script.Parent:WaitForChild("AirborneState"))
			else
				-- LOSER: Smashed straight down to the ground!
				cleanupMovers(rootPart)
				
				-- Play FallAirKnockback (the wailing animation Bai specified)
				AnimationModule.play(humanoid, AnimationIds.FallAirKnockback, Enum.AnimationPriority.Action4, true, 1.1)
				
				-- High downward velocity toward the floor
				local loserAtt = Instance.new("Attachment")
				loserAtt.Name = "KB_Att"
				loserAtt.Parent = rootPart

				local lv = Instance.new("LinearVelocity")
				lv.Name = "KB_LinearVelocity"
				lv.Attachment0 = loserAtt
				lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
				lv.VectorVelocity = Vector3.new(0, -125, 0)
				lv.MaxAxesForce = Vector3.new(20000, 1e7, 20000)
				lv.Parent = rootPart
				Debris:AddItem(loserAtt, 0.6)
				Debris:AddItem(lv, 0.6)
				
				rootPart.AssemblyLinearVelocity = Vector3.new(0, -125, 0)
				
				fighter:SetAttribute("KnockbackType", "hard_ground")
				fighter:SetAttribute("ForceState", "Knockback")
				fighter:SetAttribute("LaunchedAt", tick() + 0.1)
				
				targetHum:TakeDamage(20)
				
				return require(script.Parent:WaitForChild("KnockbackState"))
			end
		end
	end
	
	-- Global safety timeout: max 4.5s in air clash
	if totalElapsed > 4.5 then
		return require(script.Parent:WaitForChild("AirborneState"))
	end
	
	return MidAirClashState
end

return MidAirClashState
