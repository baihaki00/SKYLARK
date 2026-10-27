--// MidAirClashState.lua
-- Dragon Ball Z / Anime Style Mid-Air Aerial Brawling State Machine
-- Two fighters meet in the air, fly the multi-dash orbit together (Modules/ClashOrbit), then one of
-- two climaxes: Mutual Tie blast-back OR Meteor Downward Smash into ground recovery.

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
local ClashOrbit = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("ClashOrbit"))
local States = require(game:GetService("ReplicatedStorage"):WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("States")) -- (every state by name)
local StateRequest = require(game:GetService("ReplicatedStorage"):WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("StateRequest")) -- (asking a Quin to change state)

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
	-- The Quin it meets up there, named by whoever started the clash (ClashWith). TargetQuin
	-- is only the fallback: it is the Quin's general target, which can be someone standing on
	-- the ground - a follower that looked its partner up there pulled a third Quin in, and a
	-- jumper started clashes with chasing Quins on the floor.
	local targetName = fighter:GetAttribute("ClashWith") or fighter:GetAttribute("TargetQuin")
	fighter:SetAttribute("ClashWith", nil)
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

	-- A target already in a clash with another Quin is taken: no clash (update leaves at once).
	-- Overwriting its partner made three-way clashes in which both sides "won".
	local busyPartner = target and target:GetAttribute("MidAirClashPartner")
	if busyPartner and busyPartner ~= fighter.Name and target:GetAttribute("CurrentState") == "MidAirClash" then
		target = nil
	end
	-- Nor is one standing on something (unless it already leads this clash with us)
	if target and not (target:GetAttribute("MidAirClashRole") == "Leader" and busyPartner == fighter.Name) then
		local targetHumanoid = target:FindFirstChildOfClass("Humanoid")
		if not targetHumanoid or not (targetHumanoid.PlatformStand or targetHumanoid.FloorMaterial == Enum.Material.Air) then
			target = nil
		end
	end
	
	if target and target:IsA("Model") then
		local targetHRP = target:FindFirstChild("HumanoidRootPart")
		if targetHRP then
			-- If target is already Leader of a clash, become Follower
			if target:GetAttribute("MidAirClashRole") == "Leader" and target:GetAttribute("MidAirClashPartner") == fighter.Name then
				role = "Follower"
			else
				-- We are Leader: ensure target is linked and pulled into MidAirClash
				role = "Leader"
				-- A result left from a clash the other never arrived in is not this one's
				fighter:SetAttribute("ClashResult", nil)
				target:SetAttribute("ClashResult", nil)
				fighter:SetAttribute("MidAirClashRole", "Leader")
				fighter:SetAttribute("MidAirClashPartner", target.Name)
				target:SetAttribute("MidAirClashRole", "Follower")
				target:SetAttribute("MidAirClashPartner", fighter.Name)
				target:SetAttribute("ClashWith", fighter.Name)
				StateRequest.ask(target, "MidAirClash", StateRequest.CLASH, "met in the air")
				
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

				-- Sometimes there is no brawl: the one that came in faster smashes the other
				-- straight down. The result is written on both, so both act on the same one.
				-- A target that is not flying under its own power (thrown up by a hit, falling)
				-- cannot fight back up there: an interceptor usually smashes it down at once.
				local targetState = target:GetAttribute("CurrentState")
				local helpless = targetState ~= "ProjectileJump" and targetState ~= "MidAirClash"
				if helpless and math.random() < (CombatConfig.MidAirClash_HelplessSmashChance or 0.75) then
					fighter:SetAttribute("ClashResult", fighter.Name)
					target:SetAttribute("ClashResult", fighter.Name)
				elseif math.random() < (CombatConfig.MidAirClash_ImmediateSmashChance or 0.3) then
					local winner = rootPart.AssemblyLinearVelocity.Magnitude >= targetHRP.AssemblyLinearVelocity.Magnitude and fighter or target
					fighter:SetAttribute("ClashResult", winner.Name)
					target:SetAttribute("ClashResult", winner.Name)
				end
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
	if data and data.orbit and not data.orbit.done then
		data.orbit.stop()
	end
	rootPart.Anchored = false -- (the orbit anchors both bodies while it moves them)
	
	fighter:SetAttribute("MidAirClashRole", nil)
	fighter:SetAttribute("MidAirClashPartner", nil)
	fighter:SetAttribute("ClashCenterX", nil)
	fighter:SetAttribute("ClashCenterY", nil)
	fighter:SetAttribute("ClashCenterZ", nil)
	fighter:SetAttribute("ClashPhase", nil)
	fighter:SetAttribute("ClashPhaseStart", nil)
	fighter:SetAttribute("ClashRelocations", nil)
	fighter:SetAttribute("ClashWinner", nil)
	fighter:SetAttribute("ClashResult", nil)
	fighter:SetAttribute("LastClashTime", os.clock())
	
	clashData[fighter] = nil
end

local function switchPhase(data, newPhase)
	data.phase = newPhase
	data.phaseStart = tick()
end

function MidAirClashState.update(fighter, humanoid, rootPart, DEBUG)
	local data = clashData[fighter]
	if not data then return States.Airborne end
	
	local target = data.target
	if not target or not target.Parent then
		return States.Airborne
	end
	-- The partner left the clash (or is clashing with someone else): nobody to fight up here.
	-- Not once a result is written (the leader leaves first and clears its own partner).
	if not fighter:GetAttribute("ClashResult") and tick() - data.startTime > 0.3
		and target:GetAttribute("MidAirClashPartner") ~= fighter.Name then
		return States.Airborne
	end
	
	local targetHum = target:FindFirstChildOfClass("Humanoid")
	local targetHRP = target:FindFirstChild("HumanoidRootPart")
	if not targetHum or targetHum.Health <= 0 or not targetHRP then
		return States.Airborne
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
	-- (not in the orbit: ClashOrbit turns them, toward where they fly)
	local ao = rootPart:FindFirstChild("MidAir_Align")
	if ao and data.phase ~= "Orbit" then
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
			if fighter:GetAttribute("ClashResult") then
				switchPhase(data, "Climax") -- decided on contact: no brawl
			else
				-- the multi-dash orbit (Modules/ClashOrbit): the leader drives both bodies
				switchPhase(data, "Orbit")
				if data.role == "Leader" then
					data.orbit = ClashOrbit.run(fighter, target, clashCenter)
				end
			end
		end
		
	-- ============================================================
	-- PHASE 2: ORBIT (multi-dash passes, Modules/ClashOrbit)
	-- ============================================================
	elseif data.phase == "Orbit" then
		if data.role == "Leader" then
			if not data.orbit or data.orbit.done then
				fighter:SetAttribute("ClashPhase", "Climax")
				switchPhase(data, "Climax")
			end
		elseif fighter:GetAttribute("ClashResult") or target:GetAttribute("ClashPhase") == "Climax" then
			switchPhase(data, "Climax")
		end

	-- ============================================================
	-- PHASE 3: CLIMAX (Tie Blast-back OR Meteor Downward Smash)
	-- ============================================================
	elseif data.phase == "Climax" then
		-- The leader decides and writes the result on both fighters. (The follower used to read
		-- it from the leader, which had usually left the state and cleared it by then: the
		-- follower saw a tie while the leader played a smash.)
		data.winnerName = data.winnerName or fighter:GetAttribute("ClashResult")
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
			fighter:SetAttribute("ClashResult", data.winnerName)
			target:SetAttribute("ClashResult", data.winnerName)
		elseif not data.winnerName then
			return MidAirClashState -- the leader has not decided yet
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
			StateRequest.ask(fighter, "Knockback", StateRequest.HIT, "struck")
			KnockbackModule.applyKnockback(fighter, flatAway, 110, 0.5)
			return States.Knockback
			
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
				
				return States.Airborne
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
				local smashSpeed = CombatConfig.MidAirClash_SmashSpeed or 260
				lv.VectorVelocity = Vector3.new(0, -smashSpeed, 0)
				lv.ForceLimitMode = Enum.ForceLimitMode.PerAxis -- MaxAxesForce is ignored otherwise
				lv.MaxAxesForce = Vector3.new(20000, 1e7, 20000)
				lv.Parent = rootPart
				Debris:AddItem(loserAtt, 0.6)
				Debris:AddItem(lv, 0.6)
				
				rootPart.AssemblyLinearVelocity = Vector3.new(0, -smashSpeed, 0)
				
				fighter:SetAttribute("KnockbackType", "hard_ground")
				StateRequest.ask(fighter, "Knockback", StateRequest.HIT, "struck")
				fighter:SetAttribute("LaunchedAt", tick() + 0.1)
				
				DamageModule.chip(target, fighter, 20) -- the one smashed down takes it (this used to hit the winner)
				
				return States.Knockback
			end
		end
	end
	
	-- Global safety timeout: max 4.5s in air clash (the orbit's own limit, plus a beat)
	if totalElapsed > math.max(4.5, math.max(CombatConfig.MidAirClash_OrbitMaxTime or 2, CombatConfig.MidAirClash_OrbitLeapMaxTime or 2) + 1.5) then
		return States.Airborne
	end
	
	return MidAirClashState
end

return MidAirClashState
