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
	local target, distance = TargetingModule.getNearest(rootPart, 30)
	if not TargetingModule.isValid(target) then
		return AirborneState
	end
	
	local targetHRP = target:FindFirstChild("HumanoidRootPart")
	if not targetHRP then return AirborneState end
	
	-- Aerial Encounter Trigger: If opponent is airborne within 35 studs, enter MidAirClash!
	local targetState = target:GetAttribute("CurrentState")
	if (targetState == "Airborne" or targetState == "ProjectileJump" or targetState == "MidAirClash" or targetHRP.Position.Y > 20) and distance < 35 then
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
			trackLV.MaxForce = 60000
			trackLV.Attachment0 = trackAtt
			trackLV.Parent = rootPart
		end
		
		trackLV.VectorVelocity = dir.Unit * 40
	else
		local trackLV = rootPart:FindFirstChild("AirborneTrackLV")
		if trackLV then trackLV:Destroy() end
	end
	
	-- Face target
	local lookCF = CFrame.lookAt(rootPart.Position, targetHRP.Position)
	rootPart.CFrame = rootPart.CFrame:Lerp(lookCF, 0.3)
	
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
