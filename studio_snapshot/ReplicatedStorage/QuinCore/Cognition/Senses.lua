--// Cognition.Senses
-- What reaches a Quin this tick. One percept per other living Quin, with the channel it came
-- through (nil = not noticed):
--   team     allies are always known (the team talks)
--   sight    inside the vision cone and range, with a clear line of sight. The cone is 200
--            degrees wide and VisionVerticalHalfAngle above and below where the head points
--            (gazePitch, from Cognition.Gaze)
--   hearing  close enough to hear what it makes (owner 2026-10-27: "if they hear footsteps they
--            turn around"): a walk is silent, a jog is heard at its hearing range, a sprint
--            further, a fight about twice as far, and a loud moment (a plant's or a defuse's slam,
--            LoudUntil) across much of the arena
--   touch    within arm's reach, or the Quin that just hit it
-- Neutral (layer off): every living enemy is noticed wherever it is, as before this layer existed.

local GameClock = require(game:GetService("ReplicatedStorage"):WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("GameClock")) -- (the game's clock: a freeze stops it)
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local QuinCore = ReplicatedStorage:WaitForChild("QuinCore")
local CombatConfig = require(QuinCore:WaitForChild("CombatConfig"))
local SpatialModule = require(QuinCore:WaitForChild("Modules"):WaitForChild("SpatialModule"))
local Pers = require(game:GetService("ReplicatedStorage"):WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("Pers")) -- (personality reads + defaults, one place)

local Senses = {}

local NOISY_STATES = { Fight = true, Knockback = true, ProjectileJump = true, Special = true }
local HIT_MEMORY = 2.0 -- seconds an attacker stays "felt" after its hit
local LOS_ALWAYS_WITHIN = 45 -- line of sight is always resolved inside the local combat radius

-- How far off the noise `other` makes right now can be heard by a Quin whose hearing reach is
-- `hearing` (0: it makes none)
local function noiseReach(other, otherRoot, cfg, hearing)
	if (other:GetAttribute("LoudUntil") or 0) > GameClock.serverNow() then
		return cfg.HearingLoudRange or 160
	end
	if other:GetAttribute("Attacking") == true or NOISY_STATES[other:GetAttribute("CurrentState") or ""] == true then
		return hearing * (cfg.HearingFightFactor or 2.2)
	end
	local speed = Vector3.new(otherRoot.AssemblyLinearVelocity.X, 0, otherRoot.AssemblyLinearVelocity.Z).Magnitude
	if speed > (cfg.SprintNoiseSpeed or 28) then return hearing * (cfg.HearingSprintFactor or 1.4) end
	if speed > cfg.NoiseSpeed then return hearing end
	return 0
end

-- Hearing reach for this Quin: aware Quins pick up more
function Senses.hearingRange(quinModel)
	local cfg = CombatConfig.Cognition
	local awareness = Pers.get(quinModel, "Awareness")
	return cfg.HearingRangeMin + awareness * (cfg.HearingRangeMax - cfg.HearingRangeMin)
end

function Senses.sense(quinModel, rootPart, others, enabled, gazePitch)
	gazePitch = gazePitch or 0
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
	local hitAge = GameClock.serverNow() - (quinModel:GetAttribute("ImpactTime") or 0)

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
				local elevation = math.deg(math.asin(math.clamp(offset.Y / math.max(distance, 0.01), -1, 1)))
				local inCone = distance <= cfg.VisionRange
					and (flatOffset.Magnitude < 0.01 or flatLook:Dot(flatOffset.Unit) >= coneCos)
					and math.abs(elevation - gazePitch) <= cfg.VisionVerticalHalfAngle
				local hasLoS = false
				if inCone or channel or distance <= LOS_ALWAYS_WITHIN then
					hasLoS = SpatialModule.checkLineOfSight(myEye, SpatialModule.getEyePosition(otherRoot), { quinModel, other })
				end
				if not channel and inCone and hasLoS then
					channel = "sight"
				end
				if not channel and distance <= noiseReach(other, otherRoot, cfg, hearing) then
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
