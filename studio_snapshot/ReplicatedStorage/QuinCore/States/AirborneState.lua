--// AirborneState.lua
-- Handles aerial combat: air pursuit, air combos, meteor slam
-- Entered after launching an enemy or being launched

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")

local TargetingModule = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("TargetingModule"))
local AnimationModule = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("AnimationModule"))
local HitboxModule = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("HitboxModule"))
local KnockbackModule = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("KnockbackModule"))
local ComboModule = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("ComboModule"))
local DamageModule = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("DamageModule"))
local AudioModule = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("AudioModule"))
local VfxModule = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("VfxModule"))
local AnimationIds = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("AnimationIds"))
local CombatConfig = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("CombatConfig"))

local AirborneState = { name = "Airborne" }

local airborneData = {} -- per-fighter tracking

function AirborneState.enter(fighter, humanoid, rootPart)
	if not airborneData[fighter] then
		airborneData[fighter] = {
			enterTime = tick(),
			airComboStep = 0,
			hasJumped = false,
			lastAirAttack = 0,
		}
	end
	local data = airborneData[fighter]
	data.enterTime = tick()
	data.airComboStep = 0
	data.hasJumped = false
	data.lastAirAttack = 0
	
	-- Jump up to pursue
	local jumpPower = fighter:GetAttribute("JumpPower") or 50
	
	-- The pursuit launch only fires from the ground. This state is also entered already in the
	-- air (after a mid-air clash); launching again there shot the Quin straight up a second time.
	if humanoid.FloorMaterial ~= Enum.Material.Air then
		local attachment = Instance.new("Attachment")
		attachment.Name = "AirborneAttachment"
		attachment.Parent = rootPart
		Debris:AddItem(attachment, 0.3)
		
		local lv = Instance.new("LinearVelocity")
		lv.Attachment0 = attachment
		lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
		lv.VectorVelocity = Vector3.new(0, CombatConfig.AirPursuitJumpForce or 150, 0)
		lv.MaxForce = 150000
		lv.Parent = rootPart
		Debris:AddItem(lv, 0.25)
		
		AnimationModule.play(humanoid, AnimationIds.Jump, Enum.AnimationPriority.Action, false, 1.2)
	end
	data.hasJumped = true
end

function AirborneState.exit(fighter, humanoid, rootPart)
	airborneData[fighter] = nil
	if rootPart then
		local trackLV = rootPart:FindFirstChild("AirborneTrackLV")
		if trackLV then trackLV:Destroy() end
		local trackAtt = rootPart:FindFirstChild("AirborneTrackAtt")
		if trackAtt then trackAtt:Destroy() end
	end
	AnimationModule.stop(humanoid, AnimationIds.Jump)
	AnimationModule.stop(humanoid, AnimationIds.Fall)
	AnimationModule.stop(humanoid, AnimationIds.Attack)
end

function AirborneState.update(fighter, humanoid, rootPart, DEBUG)
	local data = airborneData[fighter]
	if not data then
		return require(script.Parent:WaitForChild("IdleState"))
	end
	
	local elapsed = tick() - data.enterTime
	local maxAirTime = 4.0
	
	-- Timeout: fall back to ground
	if elapsed > maxAirTime then
		if DEBUG then print("[Airborne] Timeout → ground") end
		return require(script.Parent:WaitForChild("ChaseState"))
	end
	
	-- Check if we landed
	local state = humanoid:GetState()
	if elapsed > 0.5 and (state == Enum.HumanoidStateType.Running or state == Enum.HumanoidStateType.Landed) then
		if DEBUG then print("[Airborne] Landed → Chase") end
		return require(script.Parent:WaitForChild("ChaseState"))
	end
	
	-- Find target
	-- (a read-only look: getNearest assigns targets and cleared this Quin's own in mid-air whenever
	-- nobody was within 30 studs)
	local nearest = TargetingModule.getEnemiesInRange(rootPart, 30)[1]
	local target, distance = nearest and nearest.model, nearest and nearest.distance
	if not TargetingModule.isValid(target) then
		return AirborneState
	end
	
	local targetHRP = target:FindFirstChild("HumanoidRootPart")
	if not targetHRP then return AirborneState end
	
	-- Aerial Encounter Trigger: If opponent is airborne within 35 studs, enter MidAirClash!
	-- Not right after a clash (the winner fell into this state and clashed again with the
	-- Quin it had just smashed, every 0.4s), and not with a Quin being thrown (Knockback):
	-- "in the air" is the humanoid off the floor, not a fixed height (platform tops are higher).
	local targetState = target:GetAttribute("CurrentState")
	local targetHumanoid = target:FindFirstChildOfClass("Humanoid")
	local targetOffGround = targetHumanoid ~= nil and (targetHumanoid.PlatformStand or targetHumanoid.FloorMaterial == Enum.Material.Air)
	local clashCooldown = CombatConfig.MidAirClash_Cooldown or 3.0
	local clashedRecently = os.clock() - (fighter:GetAttribute("LastClashTime") or 0) < clashCooldown
		or os.clock() - (target:GetAttribute("LastClashTime") or 0) < clashCooldown
	-- (a clash between two others is not joined: that made three-way clashes)
	if not clashedRecently and targetState ~= "Knockback" and targetState ~= "MidAirClash"
		and (targetState == "Airborne" or targetState == "ProjectileJump" or targetState == "MidAirClash" or targetOffGround) and distance < 35 then
		fighter:SetAttribute("ClashWith", target.Name)
		return require(script.Parent:WaitForChild("MidAirClashState"))
	end
	
	-- Move toward target in air
	local dir = (targetHRP.Position - rootPart.Position)
	if dir.Magnitude > 3 then
		local trackAtt = rootPart:FindFirstChild("AirborneTrackAtt")
		if not trackAtt then
			trackAtt = Instance.new("Attachment")
			trackAtt.Name = "AirborneTrackAtt"
			trackAtt.Parent = rootPart
		end
		
		local trackLV = rootPart:FindFirstChild("AirborneTrackLV")
		if not trackLV then
			trackLV = Instance.new("LinearVelocity")
			trackLV.Name = "AirborneTrackLV"
			trackLV.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
			-- Horizontal authority only: gravity keeps acting, so the pursuit is an arc rather
			-- than a constant-speed straight-line glide
			trackLV.ForceLimitMode = Enum.ForceLimitMode.PerAxis
			trackLV.MaxAxesForce = Vector3.new(60000, 0, 60000)
			trackLV.Attachment0 = trackAtt
			trackLV.Parent = rootPart
		end
		
		local flatDir = Vector3.new(dir.X, 0, dir.Z)
		trackLV.VectorVelocity = (flatDir.Magnitude > 0.1 and flatDir.Unit or Vector3.zero) * 40
	else
		local trackLV = rootPart:FindFirstChild("AirborneTrackLV")
		if trackLV then trackLV:Destroy() end
	end
	
	-- Face target
	-- Yaw only: aiming at the target's height pitched the whole body over
	local flatTargetPos = Vector3.new(targetHRP.Position.X, rootPart.Position.Y, targetHRP.Position.Z)
	if (flatTargetPos - rootPart.Position).Magnitude > 0.5 then
		local lookCF = CFrame.lookAt(rootPart.Position, flatTargetPos)
		rootPart.CFrame = rootPart.CFrame:Lerp(lookCF, 0.3)
	end
	
	-- Air combo attack
	local attackCooldown = 0.4
	if distance <= 8 and (tick() - data.lastAirAttack) > attackCooldown then
		data.lastAirAttack = tick()
		data.airComboStep = data.airComboStep + 1
		
		local moveData = ComboModule.nextAttack(fighter, "Aerial")
		if moveData then
			AnimationModule.play(humanoid, AnimationIds.Attack, Enum.AnimationPriority.Action4, false, 1.3)
			
			task.delay(moveData.duration * 0.3, function()
				local hitModels = HitboxModule.castInFront(rootPart, moveData.hitboxSize, Vector3.new(0, 0, -3), fighter)
				for _, hitModel in ipairs(hitModels) do
					local damageInfo = DamageModule.calculate(fighter, hitModel, data.airComboStep, moveData.damageMultiplier)
					-- Aerial damage bonus
					local aerialBonus = fighter:GetAttribute("AerialDamageBonus") or 0.15
					damageInfo.damage = math.floor(damageInfo.damage * (1 + aerialBonus))
					DamageModule.apply(fighter, hitModel, damageInfo)
					
					if moveData.isSlam then
						-- METEOR SLAM
						KnockbackModule.applySlam(hitModel, CombatConfig.SlamDownForce or 200)
						
						-- VFX & Audio Hook
						local hitHRP = hitModel:FindFirstChild("HumanoidRootPart")
						if hitHRP then
							AudioModule.playSlam(hitHRP.Position)
							VfxModule.createShockwave(hitHRP, 20, 0.6)
							VfxModule.createDust(hitHRP, 8)
						end
						
						if DEBUG then print("[Airborne] METEOR SLAM!") end
					else
						-- Keep them in the air
						local hitHRP = hitModel:FindFirstChild("HumanoidRootPart")
						if hitHRP then
							local att = hitHRP:FindFirstChild("AirborneAttachment")
							if not att then
								att = Instance.new("Attachment")
								att.Name = "AirborneAttachment"
								att.Parent = hitHRP
								Debris:AddItem(att, 0.3)
							end
							
							local keepUp = Instance.new("LinearVelocity")
							keepUp.Attachment0 = att
							keepUp.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
							keepUp.VectorVelocity = Vector3.new(0, 15, 0)
							keepUp.MaxForce = 50000
							keepUp.Parent = hitHRP
							Debris:AddItem(keepUp, 0.2)
						end
					end
				end
			end)
			
			-- After meteor slam, return to ground
			if moveData.isSlam then
				task.delay(moveData.duration, function()
					KnockbackModule.applySlam(fighter, 150)
					
					-- Self impact VFX
					task.delay(0.2, function()
						AudioModule.playSlam(rootPart.Position)
						VfxModule.createShockwave(rootPart, 15, 0.5)
						VfxModule.createDust(rootPart, 5)
					end)
				end)
			end
		end
	end
	
	-- Fall animation
	if rootPart.AssemblyLinearVelocity.Y < -5 then
		if not AnimationModule.isPlaying(humanoid, AnimationIds.Fall) then
			AnimationModule.play(humanoid, AnimationIds.Fall, Enum.AnimationPriority.Movement, true, 1)
		end
	end
	
	return AirborneState
end

return AirborneState
