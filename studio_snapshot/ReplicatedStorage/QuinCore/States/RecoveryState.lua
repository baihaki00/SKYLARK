--// RecoveryState.lua
-- Getting back up from a stun, knockdown, or prone tumble: restores the upright orientation,
-- plays the get-up that matches the knockdown, and hands back to combat when it finishes.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local QuinCore = ReplicatedStorage:WaitForChild("QuinCore")
local AnimationModule = require(QuinCore:WaitForChild("Modules"):WaitForChild("AnimationModule"))
local AnimationIds = require(QuinCore:WaitForChild("AnimationIds"))
local CombatConfig = require(QuinCore:WaitForChild("CombatConfig"))
local RuntimeTracer = require(QuinCore:WaitForChild("Modules"):WaitForChild("RuntimeTracer"))
local LocomotionModule = require(QuinCore:WaitForChild("Modules"):WaitForChild("LocomotionModule"))
local TargetingModule = require(QuinCore:WaitForChild("Modules"):WaitForChild("TargetingModule"))
local KnockbackModule = require(QuinCore:WaitForChild("Modules"):WaitForChild("KnockbackModule"))

local RecoveryState = { name = "Recovery" }

-- Get-up clips. A heavy knockdown rises slowly from the back; everything else kips up.
local GET_UP_FAST = "Reactions.GetUpBackFast"
local GET_UP_HEAVY = "Reactions.GetUpGround"
-- The state hands over slightly before the clip's last frame so its tail blends into the next pose
local GET_UP_HANDOVER = 0.92

-- Landing a projectile jump or smash: one of these plays on reaching the ground
local SLAM_LANDINGS = { "Parkour.LandingSuperHero", "Parkour.LandingHard", "ProjectileJump.NinjaLanding", "ProjectileJump.StandardLanding" }

local UPRIGHT_ALIGN_NAME = "RecoveryUpright"
local UPRIGHT_ATT_NAME = "RecoveryUprightAtt"

local recoveryData = {}

local function removeUprightAlign(rootPart)
	local align = rootPart:FindFirstChild(UPRIGHT_ALIGN_NAME)
	if align then align:Destroy() end
	local att = rootPart:FindFirstChild(UPRIGHT_ATT_NAME)
	if att then att:Destroy() end
end

local function flatLookOf(rootPart)
	local look = rootPart.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 0.05 then
		local up = rootPart.CFrame.UpVector
		flat = Vector3.new(-up.X, 0, -up.Z)
	end
	return flat.Magnitude > 0.05 and flat.Unit or Vector3.new(0, 0, -1)
end

-- Rotate a tipped body upright over a few frames with a torque constraint (assigning the upright
-- CFrame directly flipped it to vertical in a single frame)
local function alignUpright(rootPart)
	removeUprightAlign(rootPart)
	local att = Instance.new("Attachment")
	att.Name = UPRIGHT_ATT_NAME
	att.Parent = rootPart
	local align = Instance.new("AlignOrientation")
	align.Name = UPRIGHT_ALIGN_NAME
	align.Mode = Enum.OrientationAlignmentMode.OneAttachment
	align.RigidityEnabled = false
	align.Responsiveness = 35
	align.MaxTorque = 1000000
	align.MaxAngularVelocity = 18
	align.CFrame = CFrame.lookAt(Vector3.zero, flatLookOf(rootPart))
	align.Attachment0 = att
	align.Parent = rootPart
end

function RecoveryState.enter(fighter, humanoid, rootPart)
	local kbType = fighter:GetAttribute("KnockbackType") or "ground"
	local isHeavy = kbType == "hard_ground" or fighter:GetAttribute("KnockdownHeavy") == true

	-- Stop driving the body. Its remaining speed here is knockback carry, not a run, so the
	-- locomotion brake (run cycle, stop-run plant) does not apply.
	LocomotionModule.cancelSteer(fighter)
	humanoid:Move(Vector3.zero, false)
	humanoid.WalkSpeed = 0
	humanoid.PlatformStand = false
	fighter:SetAttribute("GetUpProtection", true)

	local upY = rootPart.CFrame.UpVector.Y
	if upY < 0.85 then
		alignUpright(rootPart)
	end

	-- A landing skid carries its own deceleration; cutting the velocity here only made
	-- it drop and then get pulled straight back up to the skid speed.
	if not KnockbackModule.isSliding(fighter) then
		rootPart.AssemblyLinearVelocity = rootPart.AssemblyLinearVelocity * 0.15
	end
	rootPart.AssemblyAngularVelocity = Vector3.zero
	humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)

	local clipPath = nil
	local duration
	if kbType == "ground" and upY >= 0.85 then
		-- Light ground flinch, still on its feet
		duration = 0.2
	elseif kbType == "traversal_landing" then
		-- A hop onto a spot (a stepping stone): a soft landing and straight on
		clipPath = "Parkour.LandingSoft"
		AnimationModule.playConfig(humanoid, clipPath, 1.3, Enum.AnimationPriority.Action3, false)
		duration = 0.3
	elseif kbType == "slam_landing" and fighter:GetAttribute("LandingClipPath") then
		-- The jump's own clip goes on as the landing (the arc smack-down): no second clip on top
		clipPath = fighter:GetAttribute("LandingClipPath")
		duration = (fighter:GetAttribute("LandingClipRemaining") or 1.0) * GET_UP_HANDOVER
		fighter:SetAttribute("LandingClipPath", nil)
		fighter:SetAttribute("LandingClipRemaining", nil)
	elseif kbType == "slam_landing" then
		clipPath = SLAM_LANDINGS[math.random(1, #SLAM_LANDINGS)]
		local track = AnimationModule.playConfig(humanoid, clipPath, 1.0, Enum.AnimationPriority.Action4, false)
		if not track or track.Length <= 0 then
			-- The asset has not loaded (or cannot): use the other landing rather than no pose at all
			clipPath = SLAM_LANDINGS[1]
			AnimationModule.playConfig(humanoid, clipPath, 1.0, Enum.AnimationPriority.Action4, false)
		end
		duration = AnimationModule.getEffectiveDuration(humanoid, clipPath, 1.0) * GET_UP_HANDOVER
	else
		clipPath = isHeavy and GET_UP_HEAVY or GET_UP_FAST
		AnimationModule.playConfig(humanoid, clipPath, 1.0, Enum.AnimationPriority.Action4, false)
		-- The state lasts as long as the clip: a fixed 1.2s cut the get-up off mid-rise
		duration = AnimationModule.getEffectiveDuration(humanoid, clipPath, 1.0) * GET_UP_HANDOVER
	end

	recoveryData[fighter] = {
		enterTime = tick(),
		clipPath = clipPath,
		duration = duration,
	}

	RuntimeTracer.checkpoint(fighter, string.format("Enter Recovery (Type=%s, Heavy=%s, UpY=%.2f, %.2fs)", kbType, tostring(isHeavy), upY, duration))
end

function RecoveryState.exit(fighter, humanoid, rootPart)
	RuntimeTracer.checkpoint(fighter, "Recovery Complete → Return to Combat")
	local data = recoveryData[fighter]
	if data and data.clipPath then
		AnimationModule.stopConfig(humanoid, data.clipPath, 0.2)
	end

	-- Purge residual reaction tracks
	AnimationModule.stop(humanoid, AnimationIds.FallAirKnockback, 0.1)
	AnimationModule.stop(humanoid, AnimationIds.Knockback, 0.1)

	humanoid.PlatformStand = false
	rootPart.AssemblyAngularVelocity = Vector3.zero

	removeUprightAlign(rootPart)
	-- Last resort only: still tipped after the whole get-up
	if rootPart.CFrame.UpVector.Y < 0.7 then
		rootPart.CFrame = CFrame.lookAt(rootPart.Position, rootPart.Position + flatLookOf(rootPart))
	end

	fighter:SetAttribute("KnockbackType", nil)
	fighter:SetAttribute("KnockdownHeavy", nil)
	-- Clear GetUpProtection after a brief 0.3s poise buffer so character is not instantly re-knocked
	task.delay(0.30, function()
		if fighter and fighter.Parent then
			fighter:SetAttribute("GetUpProtection", nil)
		end
	end)
	recoveryData[fighter] = nil
end

function RecoveryState.update(fighter, humanoid, rootPart, DEBUG)
	local showdownRole = fighter:GetAttribute("LeaderShowdownRole")
	if showdownRole == "Duelist" then
		local LeaderShowdownSystem = require(QuinCore:WaitForChild("Modules"):WaitForChild("LeaderShowdownSystem"))
		LeaderShowdownSystem.constrainToRing(rootPart)
	end

	local data = recoveryData[fighter]
	if not data then return require(script.Parent:WaitForChild("IdleState")) end

	if tick() - data.enterTime >= data.duration then
		local chaseRange = CombatConfig.ChaseRange or 60
		local target, distance = TargetingModule.getCommittedTarget(fighter, rootPart, chaseRange)
		if not target then
			target, distance = TargetingModule.getNearest(rootPart, chaseRange)
		end

		if target then
			local combatRange = CombatConfig.CombatRange or 8
			if distance <= combatRange * 1.2 then
				-- Opponent in melee proximity: defend or fight
				return require(script.Parent:WaitForChild("FightState"))
			elseif distance <= combatRange * 3.5 then
				-- Standoff range: circular pacing
				return require(script.Parent:WaitForChild("CirclingState"))
			end
		end
		-- Nobody within reach. On a high platform that is a place worth holding.
		local OverwatchState = require(script.Parent:WaitForChild("OverwatchState"))
		if OverwatchState.canHold(fighter, rootPart) then
			return OverwatchState
		end
		if target then
			-- Distant opponent: pursue
			return require(script.Parent:WaitForChild("ChaseState"))
		end
		return require(script.Parent:WaitForChild("IdleState"))
	end

	-- Keep them grounded, upright, and still during get-up
	humanoid.WalkSpeed = 0
	humanoid:MoveTo(rootPart.Position)

	return RecoveryState
end

return RecoveryState
