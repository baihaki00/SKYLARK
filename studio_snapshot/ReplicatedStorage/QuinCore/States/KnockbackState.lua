--// KnockbackState.lua
-- Hit reaction state: stagger, wall bounce, recovery
-- Entered when a fighter takes a hit with knockback

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local AnimationModule = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("AnimationModule"))
local KnockbackModule = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("KnockbackModule"))
local AudioModule = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("AudioModule"))
local VfxModule = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("VfxModule"))
local AnimationIds = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("AnimationIds"))
local CombatConfig = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("CombatConfig"))

local SpatialModule = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("SpatialModule"))
local RuntimeTracer = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("RuntimeTracer"))

local KnockbackState = { name = "Knockback" }

local knockbackData = {}

function KnockbackState.enter(fighter, humanoid, rootPart)
	local stunDuration = CombatConfig.BaseStunDuration or 0.5
	local stunResist = fighter:GetAttribute("StunResist") or 0
	stunDuration = stunDuration * (1 - stunResist)
	
	-- Adrenaline Surge: full energy reset upon taking a hit
	fighter:SetAttribute("Energy", CombatConfig.MaxEnergy or 100)
	
	local kbType = fighter:GetAttribute("KnockbackType") or "air"
	-- Recovery reads the same attribute but defaults to "ground": publish the resolved type so a
	-- launch that never set it still gets the full get-up instead of a 0.2s pop to standing
	fighter:SetAttribute("KnockbackType", kbType)
	-- Keep it active during the knockback so the GUI can read it
	RuntimeTracer.checkpoint(fighter, string.format("Enter Knockback (%s) | Stun=%.2fs", kbType, stunDuration))
	
	local isHardKnockback = (kbType == "hard_ground" or (kbType == "air" and math.random() <= 0.15))
	
	local flatLook = Vector3.new(rootPart.CFrame.LookVector.X, 0, rootPart.CFrame.LookVector.Z)
	if flatLook.Magnitude > 0.01 then flatLook = flatLook.Unit else flatLook = Vector3.new(0,0,-1) end
	
	knockbackData[fighter] = {
		enterTime = tick(),
		stunDuration = math.max(stunDuration, 0.1),
		kbType = kbType,
		isHardKnockback = isHardKnockback,
		hitFacingDir = flatLook
	}
	
	if kbType == "air" or kbType == "hard_ground" then
		humanoid.PlatformStand = true -- Required to allow mid-air knockbacks to fly properly
		
		-- Active Muscle Ragdoll core compliance (replaces rigid 400,000 torque stick)
		local muscleStiffness = CombatConfig.Ragdoll_MuscleStiffness or 8000
		local align = Instance.new("AlignOrientation")
		align.Name = "KB_Stabilizer"
		align.Mode = Enum.OrientationAlignmentMode.OneAttachment
		align.RigidityEnabled = false
		align.Responsiveness = 12
		align.MaxTorque = muscleStiffness
		align.MaxAngularVelocity = 15
		align.CFrame = CFrame.lookAt(Vector3.zero, flatLook)
		
		local att = Instance.new("Attachment")
		att.Name = "KB_StabilizerAttachment"
		att.Parent = rootPart
		
		align.Attachment0 = att
		align.Parent = rootPart

		-- Impart dynamic angular tumble velocity on launch
		local tumbleScale = CombatConfig.Ragdoll_TumbleScale or 1.0
		rootPart.AssemblyAngularVelocity = Vector3.new(
			(math.random() - 0.5) * 8.0,
			(math.random() - 0.5) * 4.0,
			(math.random() - 0.5) * 8.0
		) * tumbleScale
	else
		-- Ensure Idle is playing underneath for ground knockbacks so they don't T-pose when the flinch animation ends
		AnimationModule.play(humanoid, AnimationIds.Idle, Enum.AnimationPriority.Idle, true, 1.0, 0)
	end
	
	-- Heavy knockdowns keep the fighter down longer and get the slow get-up in Recovery
	if isHardKnockback then
		knockbackData[fighter].stunDuration = math.max(knockbackData[fighter].stunDuration, 1.5)
	end
	fighter:SetAttribute("KnockdownHeavy", isHardKnockback)

	if kbType == "air" or kbType == "hard_ground" then
		-- The flight pose is the authored air-knockback clip. While ProceduralRagdollActive is set
		-- the presentation layer leans the whole body along its travel direction on top of it.
		AnimationModule.play(humanoid, AnimationIds.FallAirKnockback, Enum.AnimationPriority.Action4, true, 1.0, 0.1)
		fighter:SetAttribute("ProceduralRagdollActive", CombatConfig.AirKnockback_ProceduralRagdollEnabled == true)
	else
		AnimationModule.play(humanoid, AnimationIds.Knockback, Enum.AnimationPriority.Action4, false, 1.0, 0.1)
	end
	
	-- Play custom knockback wind/dust trail VFX
	if rootPart then
		VfxModule.createKnockbackTrail(rootPart, stunDuration)
	end
end

function KnockbackState.exit(fighter, humanoid, rootPart)
	knockbackData[fighter] = nil
	fighter:SetAttribute("ProceduralRagdollActive", false)
	local speed = fighter:GetAttribute("Speed") or 40
	humanoid.WalkSpeed = speed
	humanoid.PlatformStand = false
	rootPart.AssemblyAngularVelocity = Vector3.zero
	
	if rootPart:FindFirstChild("KB_Stabilizer") then
		rootPart.KB_Stabilizer:Destroy()
	end
	if rootPart:FindFirstChild("KB_StabilizerAttachment") then
		rootPart.KB_StabilizerAttachment:Destroy()
	end
	
	AnimationModule.stop(humanoid, AnimationIds.Knockback, 0.3)
	AnimationModule.stop(humanoid, AnimationIds.FallAirKnockback, 0.15)
	AnimationModule.stop(humanoid, AnimationIds.KnockbackExtreme, 0.15)
	-- No more GetUp stop here, handled by RecoveryState
end

local DEBUG_KB = true
function KnockbackState.update(fighter, humanoid, rootPart, DEBUG)
	local showdownRole = fighter:GetAttribute("RespectRole")
	if showdownRole == "Duelist" then
		require(game:GetService("ReplicatedStorage").QuinCore.Modules.SocialSystem).constrainToCeremony(rootPart)
	end

	local data = knockbackData[fighter]
	if not data then return require(script.Parent:WaitForChild("IdleState")) end
	
	local elapsed = tick() - data.enterTime
	
	-- Debug: Print timing of the recovery countdown
	local remainingStun = data.stunDuration - elapsed
	local secs = math.ceil(math.max(remainingStun, 0))
	if secs ~= data.lastPrintedSec then
		-- Muted by Test Scenario
		data.lastPrintedSec = secs
	end
	
	-- Anti-Clipping: The moment they hit the ground, turn off PlatformStand.
	if humanoid.PlatformStand and (data.kbType == "air" or data.kbType == "hard_ground") then
		local launchTime = fighter:GetAttribute("LaunchedAt") or 0
		local isImmune = (tick() - launchTime) < 0.35
		
		local isBeingLaunched = rootPart:FindFirstChild("KB_LinearVelocity") ~= nil or isImmune
		
		local velY = rootPart.AssemblyLinearVelocity.Y
		local isDescending = velY <= 2.0 -- Must be descending or at apex, not actively rocketing up
		local isGroundedNow = SpatialModule.isGrounded(rootPart)
		
		if isDescending and isGroundedNow and (not isBeingLaunched or velY < -30) then
			-- Hit the ground: destroy launch velocity and retain dynamic turf slide friction
			local flatVel = Vector3.new(rootPart.AssemblyLinearVelocity.X, 0, rootPart.AssemblyLinearVelocity.Z)
			local groundSlideSpeed = flatVel.Magnitude * (CombatConfig.Ragdoll_GroundFriction or 0.55)
			local slideDir = (flatVel.Magnitude > 0.1) and flatVel.Unit or -rootPart.CFrame.LookVector

			if rootPart:FindFirstChild("KB_LinearVelocity") then
				rootPart.KB_LinearVelocity:Destroy()
			end
			rootPart.AssemblyAngularVelocity = Vector3.zero
			
			if groundSlideSpeed > 10 then
				-- Skid to rest from the actual touchdown speed. The old slide jumped to 55% of
				-- that speed on contact, held it for 0.35s and then stopped dead.
				KnockbackModule.applySlide(fighter, slideDir, flatVel.Magnitude, 0.45, { friction = true, endRatio = 0.1 })
			else
				rootPart.AssemblyLinearVelocity = Vector3.zero
			end
			
			AudioModule.playSlam(rootPart.Position)
			-- body slammed into the ground: crack, dust and earth clods (no debris parts)
			VfxModule.createLandingImpact(rootPart, math.clamp(flatVel.Magnitude / 80, 0.4, 1), fighter:GetAttribute("Element"))
			if groundSlideSpeed > 10 then
				VfxModule.createGroundMark(rootPart, slideDir, math.clamp(flatVel.Magnitude * 0.15, 2, 8), 1.6, 4)
			end
			VfxModule.shakeScreen(rootPart.Position, 350, 8)
			RuntimeTracer.checkpoint(fighter, "GroundContact → IMPACT & SLIDE")
			
			return require(script.Parent:WaitForChild("RecoveryState"))
		end
	end
	
	-- Update air arc (Temporarily disabled)
	if data.kbType == "air" and rootPart:FindFirstChild("KB_UprightGyro") then
		-- local vel = rootPart.AssemblyLinearVelocity
		-- if vel.Magnitude > 5 then
		-- 	local lookAt = CFrame.lookAt(Vector3.zero, -vel)
		-- 	rootPart.KB_UprightGyro.CFrame = lookAt * CFrame.Angles(math.rad(90), 0, 0)
		-- end
	end
	
	-- Wall bounce check
	if not data.wallChecked then
		data.wallChecked = true
		local vel = rootPart.AssemblyLinearVelocity
		if vel.Magnitude > 10 then
			local isWall, wallPos, wallNormal = KnockbackModule.checkWallBounce(rootPart, vel.Unit)
			if isWall then
				data.stunDuration = data.stunDuration + 0.5
				AudioModule.playSlam(wallPos)
				VfxModule.createDust(wallPos, 6)
				VfxModule.createShockwave(wallPos, 12, 0.4)
				if DEBUG then print("[Knockback] WALL BOUNCE! Extra stun") end
			end
		end
	end
	
	-- Recovery Transition
	if elapsed >= data.stunDuration then
		-- If it's an air knockback, they shouldn't reach here unless they never hit the floor
		if data.kbType == "air" then
			-- Fallback: If 3.0 seconds have passed and they still haven't hit the ground, force recovery
			if elapsed > 3.0 then
				print("[KnockbackState] Fallback Recovery triggered! elapsed:", elapsed)
				return require(script.Parent:WaitForChild("RecoveryState"))
			end
		else
			-- For ground knockbacks, immediately go to recovery when stun is up
			return require(script.Parent:WaitForChild("RecoveryState"))
		end
	end
	
	-- Stay stunned
	humanoid:MoveTo(rootPart.Position)
	return KnockbackState
end

-- Set stun parameters from outside (called by FightState when applying knockback)
function KnockbackState.setStunParams(fighter, duration, isHeavy)
	local data = knockbackData[fighter]
	if data then
		if isHeavy then
			data.stunDuration = (CombatConfig.HeavyStunDuration or 1.5) * (1 - (fighter:GetAttribute("StunResist") or 0))
		end
	end
end

return KnockbackState
