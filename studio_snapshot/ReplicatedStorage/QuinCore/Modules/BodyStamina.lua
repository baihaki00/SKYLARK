--// BodyStamina.lua
-- Mana as the body's effort (QUIN_CREATURE_DESIGN.md phase 1: costs belong to the body). Called
-- by Main for every Quin, AI and player alike, whatever state it is in:
--   running hard (at least Body_RunEffortShare of its own top speed)   EnergyDrain_Sprint per second
--   moving at less than that                                           EnergyRecovery_Walk per second
--   standing (under 2 studs/s)                                         EnergyRecovery_Idle per second
--   in the air, knocked down, or mid-strike                            nothing either way
-- Strikes, dashes and jumps keep their own costs where they happen. With Body_StaminaByEffort off,
-- the states do it as before (Chase drains and recovers; Idle, Circling and Overwatch recover).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CombatConfig = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("CombatConfig"))

local BodyStamina = {}

local pending = setmetatable({}, { __mode = "k" }) -- Quin -> change not yet written

function BodyStamina.enabled()
	return CombatConfig.Body_StaminaByEffort ~= false
end

function BodyStamina.update(quin, humanoid, rootPart, dt)
	if not BodyStamina.enabled() or not rootPart or humanoid.Health <= 0 then return end
	if humanoid.PlatformStand or humanoid.FloorMaterial == Enum.Material.Air then return end
	if quin:GetAttribute("Attacking") == true then return end
	local v = rootPart.AssemblyLinearVelocity
	local speed = Vector3.new(v.X, 0, v.Z).Magnitude
	local top = quin:GetAttribute("Speed") or 40
	local rate
	if speed >= top * (CombatConfig.Body_RunEffortShare or 0.8) then
		rate = -(CombatConfig.EnergyDrain_Sprint or 2)
	elseif speed < 2 then
		rate = CombatConfig.EnergyRecovery_Idle or 16
	else
		rate = CombatConfig.EnergyRecovery_Walk or 10
	end
	local speedMult = workspace:GetAttribute("GameSpeedMultiplier") or 1.0
	-- (gathered and written in steps of at least a tenth: every write of a Quin's attribute
	-- replicates, and a fast-ticking Quin's change per tick can be smaller than that)
	local delta = (pending[quin] or 0) + rate * dt * speedMult
	if math.abs(delta) < 0.1 then
		pending[quin] = delta
		return
	end
	pending[quin] = 0
	local maxEnergy = CombatConfig.MaxEnergy or 100
	local energy = quin:GetAttribute("Energy") or maxEnergy
	local nextEnergy = math.clamp(energy + delta, 0, maxEnergy)
	if nextEnergy ~= energy then
		quin:SetAttribute("Energy", math.floor(nextEnergy * 10 + 0.5) / 10)
	end
end

return BodyStamina
