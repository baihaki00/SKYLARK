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
	-- Keep it active during the knockback so the GUI can read it
	RuntimeTracer.checkpoint(fighter, string.format("Enter Knockback (%s) | Stun=%.2fs", kbType, stunDuration))
	
	local isHardKnockback = (kbType == "hard_ground" or (kbType == "air" and math.random() <= 0.15))
	print("Knockback Type", kbType)
	
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
		
		-- Upright Stabilizer
		-- Do not let the physical rootPart tumble or spin violently. The animation handles the tumbling visual!
		local align = Instance.new("AlignOrientation")
		align.Name = "KB_Stabilizer"
		align.Mode = Enum.OrientationAlignmentMode.OneAttachment
		align.RigidityEnabled = false
		align.Responsiveness = 60
		align.MaxTorque = 400000
		align.MaxAngularVelocity = 25
		align.CFrame = CFrame.lookAt(Vector3.zero, flatLook)
		
		local att = Instance.new("Attachment")
		att.Name = "KB_StabilizerAttachment"
		att.Parent = rootPart
		
		align.Attachment0 = att
		align.Parent = rootPart
	else
		-- Ensure Idle is playing underneath for ground knockbacks so they don't T-pose when the flinch animation ends
		AnimationModule.play(humanoid, AnimationIds.Idle, Enum.AnimationPriority.Idle, true, 1.0, 0)
	end
	
	-- Strip down rotation entirely. No BodyGyro. Let physics tumble them naturally.
	if isHardKnockback then
		knockbackData[fighter].stunDuration = math.max(knockbackData[fighter].stunDuration, 1.5)
		AnimationModule.play(humanoid, AnimationIds.KnockbackExtreme, Enum.AnimationPriority.Action4, false, 1, 0)
	else
		if kbType == "air" then
			AnimationModule.play(humanoid, AnimationIds.FallAirKnockback, Enum.AnimationPriority.Action4, true, 1.0, 0.1)
		else
			AnimationModule.play(humanoid, AnimationIds.Knockback, Enum.AnimationPriority.Action4, false, 1.0, 0.1)
		end
	end
	
	-- Play custom knockback wind/dust trail VFX
	if rootPart then
		VfxModule.createKnockbackTrail(rootPart, stunDuration)
	end
end

function KnockbackState.exit(fighter, humanoid, rootPart)
	knockbackData[fighter] = nil
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
	local showdownRole = fighter:GetAttribute("LeaderShowdownRole")
	if showdownRole == "Duelist" then
		local LeaderShowdownSystem = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("LeaderShowdownSystem"))
		LeaderShowdownSystem.constrainToRing(rootPart)
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
			print("[KnockbackState] isGroundedNow triggered! HRP Y:", rootPart.Position.Y, "Velocity:", rootPart.AssemblyLinearVelocity.Magnitude, "Elapsed:", elapsed)
			-- Hit the ground! Instantly kill velocity and destroy any downward movers
			if rootPart:FindFirstChild("KB_LinearVelocity") then
				rootPart.KB_LinearVelocity:Destroy()
			end
			rootPart.AssemblyLinearVelocity = Vector3.zero
			rootPart.AssemblyAngularVelocity = Vector3.zero
			
			AudioModule.playSlam(rootPart.Position)
			VfxModule.createDust(rootPart, 10)
			VfxModule.shakeScreen(rootPart.Position, 350, 8)
			RuntimeTracer.checkpoint(fighter, "GroundContact → IMPACT")
			
			-- We no longer need to teleport CFrame or freeze animations here!
			-- AlignOrientation kept them upright, so RecoveryState can handle the transition seamlessly.
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
