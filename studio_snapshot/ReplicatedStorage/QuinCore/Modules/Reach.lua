--// Reach.lua
-- A Quin's sense of distance as time (QUIN_CREATURE_DESIGN.md 5.2: range is time, not studs).
-- For a Quin and a target, from where both are and how both are moving: how soon it can be in
-- striking contact, and with what.
--
--   contact   inside strike reach now (Combat_StrikeRange), on about the same level
--   beat      one burst away (a lunge, dash or slide: Reach_BurstSpeed) within Reach_BeatTime
--   closing   a run away: the gap at its own top speed plus the closing (or opening) speed
--   sighted   further than Reach_ClosingTime of running
--   aerial    the target is up in the air out of jump reach (a projectile jump or an intercept)
--
-- A target running away at the Quin's own speed is never "closing": its time is unbounded and it
-- reads as sighted, whatever the studs. A target running in is reached sooner than its distance
-- says. Weapons and new verbs add their own reach here later (design doc: additions, not rewrites).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CombatConfig = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("CombatConfig"))

local Reach = {}

local function cfg(key, default)
	local v = CombatConfig["Reach_" .. key]
	if v == nil then return default end
	return v
end

function Reach.enabled()
	-- (Studio: Workspace attribute Ablate_Reach switches it off live, for A/B by eye or probe)
	if workspace:GetAttribute("Ablate_Reach") and game:GetService("RunService"):IsStudio() then return false end
	return CombatConfig.Reach_Enabled ~= false
end

local function airborne(model)
	local hum = model:FindFirstChildOfClass("Humanoid")
	local state = model:GetAttribute("CurrentState")
	return (hum and (hum.FloorMaterial == Enum.Material.Air or hum.PlatformStand))
		or state == "ProjectileJump" or state == "Airborne" or state == "MidAirClash"
end

-- { time, band, distance, rise, closing } for fighter -> target, or nil
function Reach.measure(fighter, rootPart, target)
	local targetRoot = target and target:FindFirstChild("HumanoidRootPart")
	if not rootPart or not targetRoot then return nil end
	local offset = targetRoot.Position - rootPart.Position
	local flat = Vector3.new(offset.X, 0, offset.Z)
	local distance = flat.Magnitude
	local rise = offset.Y
	local strikeReach = CombatConfig.Combat_StrikeRange or 9
	local ownTop = fighter:GetAttribute("Speed") or 40

	-- how fast the gap is shrinking (positive) or growing (negative) from the target's side
	local towardMe = distance > 0.01 and -flat.Unit or Vector3.zero
	local tv = targetRoot.AssemblyLinearVelocity
	local targetIn = Vector3.new(tv.X, 0, tv.Z):Dot(towardMe)

	local result = { distance = distance, rise = rise, closing = targetIn }
	if rise > (CombatConfig.Jump_MaxReach or 25) and airborne(target) then
		result.band, result.time = "aerial", distance / cfg("AerialSpeed", 150)
		return result
	end
	if distance <= strikeReach and math.abs(rise) < 6 then
		result.band, result.time = "contact", 0
		return result
	end
	local gap = math.max(distance - strikeReach, 0)
	local burstTime = gap / math.max(cfg("BurstSpeed", 100) + targetIn, 1)
	if gap <= cfg("BurstReach", 30) and burstTime <= cfg("BeatTime", 0.4) then
		result.band, result.time = "beat", burstTime
		return result
	end
	local approach = ownTop + targetIn
	if approach <= 1 then
		result.band, result.time = "sighted", math.huge
		return result
	end
	result.time = gap / approach
	result.band = result.time <= cfg("ClosingTime", 3) and "closing" or "sighted"
	return result
end

-- Publish a Quin's band to its target (HUD, probes, the mind panel), only when it changes
function Reach.publish(fighter, result)
	local band = result and result.band or nil
	if fighter:GetAttribute("ReachBand") ~= band then
		fighter:SetAttribute("ReachBand", band)
	end
end

return Reach
