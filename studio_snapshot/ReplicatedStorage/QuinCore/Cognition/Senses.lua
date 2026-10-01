--// Cognition.Senses
-- What reaches a Quin this tick. One percept per other living Quin, with the channel it came
-- through (nil = not noticed):
--   team     allies are always known (the team talks)
--   sight    inside the vision cone and range, with a clear line of sight
--   hearing  close enough to hear, and making noise (running, attacking, being thrown)
--   touch    within arm's reach, or the Quin that just hit it
-- Neutral (layer off): every living enemy is noticed wherever it is, as before this layer existed.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local QuinCore = ReplicatedStorage:WaitForChild("QuinCore")
local CombatConfig = require(QuinCore:WaitForChild("CombatConfig"))
local SpatialModule = require(QuinCore:WaitForChild("Modules"):WaitForChild("SpatialModule"))

local Senses = {}

local NOISY_STATES = { Fight = true, Knockback = true, ProjectileJump = true, Special = true, BeamStruggle = true }
local HIT_MEMORY = 2.0 -- seconds an attacker stays "felt" after its hit
local LOS_ALWAYS_WITHIN = 45 -- line of sight is always resolved inside the local combat radius

local function isNoisy(other, otherRoot, cfg)
	return otherRoot.AssemblyLinearVelocity.Magnitude > cfg.NoiseSpeed
		or other:GetAttribute("Attacking") == true
		or NOISY_STATES[other:GetAttribute("CurrentState") or ""] == true
end

-- Hearing reach for this Quin: aware Quins pick up more
function Senses.hearingRange(quinModel)
	local cfg = CombatConfig.Cognition
	local awareness = quinModel:GetAttribute("Pers_Awareness") or 0.65
	return cfg.HearingRangeMin + awareness * (cfg.HearingRangeMax - cfg.HearingRangeMin)
end

function Senses.sense(quinModel, rootPart, others, enabled)
	local cfg = CombatConfig.Cognition
	local myPos = rootPart.Position
	local myEye = SpatialModule.getEyePosition(rootPart)
	local myTeam = quinModel:GetAttribute("Team") or "None"

	local look = rootPart.CFrame.LookVector
	local flatLook = Vector3.new(look.X, 0, look.Z)
	flatLook = flatLook.Magnitude > 0.01 and flatLook.Unit or Vector3.new(0, 0, -1)
	local coneCos = math.cos(math.rad(cfg.VisionHalfAngle))
	local hearing = Senses.hearingRange(quinModel)

	local attackerName = quinModel:GetAttribute("LastAttackerName")
	local hitAge = workspace:GetServerTimeNow() - (quinModel:GetAttribute("ImpactTime") or 0)

	local percepts = {}
	for _, other in ipairs(others) do
		local otherRoot = other:FindFirstChild("HumanoidRootPart")
		local otherHum = other:FindFirstChildOfClass("Humanoid")
		if otherRoot and otherHum then
			local offset = otherRoot.Position - myPos
			local distance = offset.Magnitude
			local otherTeam = other:GetAttribute("Team") or "None"
			local percept = {
				model = other,
				isAlly = myTeam ~= "None" and myTeam == otherTeam,
				distance = distance,
				position = otherRoot.Position,
				velocity = otherRoot.AssemblyLinearVelocity,
				healthRatio = otherHum.Health / otherHum.MaxHealth,
				energyRatio = math.clamp((other:GetAttribute("Energy") or 100) / (other:GetAttribute("MaxEnergy") or 100), 0, 1),
			}

			if percept.isAlly then
				percept.channel = "team"
			elseif not enabled then
				percept.channel = "sight"
				percept.hasLineOfSight = SpatialModule.checkLineOfSight(myEye, SpatialModule.getEyePosition(otherRoot), { quinModel, other })
			else
				local channel = nil
				if distance <= cfg.ProximityRange or (other.Name == attackerName and hitAge < HIT_MEMORY) then
					channel = "touch"
				end
				local flatOffset = Vector3.new(offset.X, 0, offset.Z)
				local inCone = distance <= cfg.VisionRange
					and (flatOffset.Magnitude < 0.01 or flatLook:Dot(flatOffset.Unit) >= coneCos)
				local hasLoS = false
				if inCone or channel or distance <= LOS_ALWAYS_WITHIN then
					hasLoS = SpatialModule.checkLineOfSight(myEye, SpatialModule.getEyePosition(otherRoot), { quinModel, other })
				end
				if not channel and inCone and hasLoS then
					channel = "sight"
				end
				if not channel and distance <= hearing and isNoisy(other, otherRoot, cfg) then
					channel = "hearing"
				end
				percept.channel = channel
				percept.hasLineOfSight = hasLoS
			end

			table.insert(percepts, percept)
		end
	end
	return percepts
end

return Senses
