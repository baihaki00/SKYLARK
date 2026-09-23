--// AnimationIds.lua
-- Dynamic, backward-compatible bridge to the AnimationConfig registry
-- Ensures any script accessing AnimationIds reads live, hot-swappable animation IDs and metadata

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local AnimationConfig = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("AnimationConfig"))

local AnimationIds = {}

-- Dynamic proxies for nested array lookups (e.g. Punches[1], Kicks[2], Hits[1])
local dynamicPunches = setmetatable({}, {
	__index = function(_, idx)
		local p = AnimationConfig.Registry.Attacks and AnimationConfig.Registry.Attacks.Punches
		if not p then return nil end
		local punchKeys = {"Punch1", "CrossLeft", "CrossRight", "Hook"}
		local key = punchKeys[idx] or ("Punch" .. tostring(idx))
		return p[key] and p[key].id or nil
	end,
	__len = function(_)
		return 4
	end
})

local dynamicKicks = setmetatable({}, {
	__index = function(_, idx)
		local k = AnimationConfig.Registry.Attacks and AnimationConfig.Registry.Attacks.Kicks
		if not k then return nil end
		local kickKeys = {"HighKick", "LowKick", "PowerKick", "WheelDrive"}
		local key = kickKeys[idx] or ("Kick" .. tostring(idx))
		return k[key] and k[key].id or nil
	end,
	__len = function(_)
		return 4
	end
})

local dynamicHits = setmetatable({}, {
	__index = function(_, idx)
		local r = AnimationConfig.Registry.Reactions
		if not r then return nil end
		if idx == 1 then return r.HitLight and r.HitLight.id end
		if idx == 2 then return r.HitHeavy and r.HitHeavy.id end
		return nil
	end,
	__len = function(_)
		return 2
	end
})

setmetatable(AnimationIds, {
	__index = function(_, key)
		if key == "Punches" then return dynamicPunches end
		if key == "Kicks" then return dynamicKicks end
		if key == "Hits" then return dynamicHits end

		local reg = AnimationConfig.Registry
		if not reg then return nil end

		if key == "Idle" then 
			return (reg.Idles and reg.Idles.CombatIdle and reg.Idles.CombatIdle.id)
				or (reg.Movement and reg.Movement.Idle and reg.Movement.Idle.id)
		end
		if key == "Run" then return reg.Movement and reg.Movement.Run and reg.Movement.Run.id end
		if key == "Jump" then return reg.Movement and reg.Movement.Jump and reg.Movement.Jump.id end
		if key == "Fall" then return reg.Movement and reg.Movement.Fall and reg.Movement.Fall.id end
		if key == "FallAirKnockback" then 
			return (reg.Reactions and reg.Reactions.FallAirKnockback and reg.Reactions.FallAirKnockback.id)
				or (reg.Reactions and reg.Reactions.KnockbackAir and reg.Reactions.KnockbackAir.id)
				or (reg.Movement and reg.Movement.FallAirKnockback and reg.Movement.FallAirKnockback.id)
		end
		if key == "WalkConfident" then return reg.Movement and reg.Movement.WalkConfident and reg.Movement.WalkConfident.id end
		if key == "WalkThug" then return reg.Movement and reg.Movement.WalkThug and reg.Movement.WalkThug.id end
		if key == "Knockback" then 
			return (reg.Reactions and reg.Reactions.Knockback and reg.Reactions.Knockback.id)
				or (reg.Reactions and reg.Reactions.HitHeavy and reg.Reactions.HitHeavy.id)
		end
		if key == "KnockbackExtreme" then return reg.Reactions and reg.Reactions.KnockbackAir and reg.Reactions.KnockbackAir.id end
		if key == "GetUpGround" or key == "GetUpAir" then return reg.Reactions and reg.Reactions.GetUpGround and reg.Reactions.GetUpGround.id end
		if key == "Block" or key == "BlockFront" then return reg.Reactions and reg.Reactions.BlockFront and reg.Reactions.BlockFront.id end
		if key == "BlockLeft" then return reg.Reactions and reg.Reactions.BlockLeft and reg.Reactions.BlockLeft.id end
		if key == "BlockRight" then return reg.Reactions and reg.Reactions.BlockRight and reg.Reactions.BlockRight.id end
		if key == "Uppercut" then return reg.Attacks and reg.Attacks.Specials and reg.Attacks.Specials.Uppercut and reg.Attacks.Specials.Uppercut.id end
		if key == "Slam" then return reg.Attacks and reg.Attacks.Specials and reg.Attacks.Specials.Slam and reg.Attacks.Specials.Slam.id end
		if key == "RivalFinisher" then return reg.Attacks and reg.Attacks.Specials and reg.Attacks.Specials.RivalFinisher and reg.Attacks.Specials.RivalFinisher.id end
		if key == "BeamStruggle" then return reg.Attacks and reg.Attacks.Specials and reg.Attacks.Specials.BeamStruggle and reg.Attacks.Specials.BeamStruggle.id end
		if key == "Death" then return (reg.Reactions and reg.Reactions.Death and reg.Reactions.Death.id) or (reg.Reactions and reg.Reactions.DeathCollapse and reg.Reactions.DeathCollapse.id) end
		if key == "DeathOnTheSpot" or key == "OnTheSpotDeath" then return reg.Reactions and reg.Reactions.DeathOnTheSpot and reg.Reactions.DeathOnTheSpot.id end
		if key == "Dash" then 
			return (reg.Movement and reg.Movement.Dash and reg.Movement.Dash.id)
				or (reg.Movement and reg.Movement.Run and reg.Movement.Run.id)
		end

		-- Movement Improvements & Reversals
		if key == "RunTurn180" then return reg.Movement and reg.Movement.RunTurn180 and reg.Movement.RunTurn180.id end
		if key == "RunTurn180Left" then return reg.Movement and reg.Movement.RunTurn180Left and reg.Movement.RunTurn180Left.id end
		if key == "RunTurn180Right" then return reg.Movement and reg.Movement.RunTurn180Right and reg.Movement.RunTurn180Right.id end
		if key == "IdleToRun1" then return reg.Movement and reg.Movement.IdleToRun1 and reg.Movement.IdleToRun1.id end
		if key == "IdleToRun2" then return reg.Movement and reg.Movement.IdleToRun2 and reg.Movement.IdleToRun2.id end
		if key == "ArcRun30Rear" then return reg.Movement and reg.Movement.ArcRun30Rear and reg.Movement.ArcRun30Rear.id end
		if key == "ArcRun30RearLeft" then return reg.Movement and reg.Movement.ArcRun30RearLeft and reg.Movement.ArcRun30RearLeft.id end
		if key == "ArcRun30RearRight" then return reg.Movement and reg.Movement.ArcRun30RearRight and reg.Movement.ArcRun30RearRight.id end
		if key == "FallStraight" then return reg.Movement and reg.Movement.FallStraight and reg.Movement.FallStraight.id end

		-- Strafe aliases are used by CirclingState and TestState.
		if key == "StrafeLeftRun" then return reg.Strafe and reg.Strafe.StrafeLeftRun and reg.Strafe.StrafeLeftRun.id end
		if key == "StrafeLeftWalk" then return reg.Strafe and reg.Strafe.StrafeLeftWalk and reg.Strafe.StrafeLeftWalk.id end
		if key == "StrafeLeftTired" then return reg.Strafe and reg.Strafe.StrafeLeftTired and reg.Strafe.StrafeLeftTired.id end
		if key == "StrafeRightRun" then return reg.Strafe and reg.Strafe.StrafeRightRun and reg.Strafe.StrafeRightRun.id end
		if key == "StrafeRightWalk" then return reg.Strafe and reg.Strafe.StrafeRightWalk and reg.Strafe.StrafeRightWalk.id end
		if key == "StrafeRightTired" then return reg.Strafe and reg.Strafe.StrafeRightTired and reg.Strafe.StrafeRightTired.id end

		-- Recovery & GetUp Aliases
		if key == "GetUpBackFast" then return reg.Reactions and reg.Reactions.GetUpBackFast and reg.Reactions.GetUpBackFast.id end
		if key == "GetUpBackSlow" then return reg.Reactions and reg.Reactions.GetUpBackSlow and reg.Reactions.GetUpBackSlow.id end
		if key == "GetUpFromCrouch" then return reg.Reactions and reg.Reactions.GetUpFromCrouch and reg.Reactions.GetUpFromCrouch.id end
		if key == "KnockdownBehind" then return reg.Reactions and reg.Reactions.KnockdownBehind and reg.Reactions.KnockdownBehind.id end

		-- Hero Landings
		if key == "LandingSoft" then return reg.Parkour and reg.Parkour.LandingSoft and reg.Parkour.LandingSoft.id end
		if key == "LandingHard" then return reg.Parkour and reg.Parkour.LandingHard and reg.Parkour.LandingHard.id end
		if key == "LandingSuperHero" then return reg.Parkour and reg.Parkour.LandingSuperHero and reg.Parkour.LandingSuperHero.id end

		-- Procedural Specials, Parkour & Awareness
		if key == "SkidOverOB" then return reg.Parkour and reg.Parkour.SkidOverOB and reg.Parkour.SkidOverOB.id end
		if key == "ProceduralJump1" then return reg.Parkour and reg.Parkour.ProceduralJump1 and reg.Parkour.ProceduralJump1.id end
		if key == "ProceduralSlide1" then return reg.Parkour and reg.Parkour.ProceduralSlide1 and reg.Parkour.ProceduralSlide1.id end
		if key == "ProceduralSlide2" then return reg.Parkour and reg.Parkour.ProceduralSlide2 and reg.Parkour.ProceduralSlide2.id end
		if key == "ProceduralEvade1" then return reg.Tactics and reg.Tactics.ProceduralEvade1 and reg.Tactics.ProceduralEvade1.id end
		if key == "ProceduralEvade2" then return reg.Tactics and reg.Tactics.ProceduralEvade2 and reg.Tactics.ProceduralEvade2.id end
		if key == "ProceduralSmackDown" then return reg.Attacks and reg.Attacks.Specials and reg.Attacks.Specials.ProceduralSmackDown and reg.Attacks.Specials.ProceduralSmackDown.id end
		if key == "LookingBehind" then return reg.Awareness and reg.Awareness.LookingBehind and reg.Awareness.LookingBehind.id end

		-- Behavioral Polish Aliases (Phase 1 - 6)
		if key == "StartSprint" then return reg.Movement and reg.Movement.StartSprint and reg.Movement.StartSprint.id end
		if key == "BrakingStop" then return reg.Movement and reg.Movement.BrakingStop and reg.Movement.BrakingStop.id end
		if key == "AssessTarget" then return reg.Transition and reg.Transition.AssessTarget and reg.Transition.AssessTarget.id end
		if key == "RearThreatGlance" then return reg.Awareness and reg.Awareness.RearThreatGlance and reg.Awareness.RearThreatGlance.id end
		if key == "Turn180Pivot" then return reg.Awareness and reg.Awareness.Turn180Pivot and reg.Awareness.Turn180Pivot.id end
		if key == "RetreatBackstep" then return reg.Tactics and reg.Tactics.RetreatBackstep and reg.Tactics.RetreatBackstep.id end
		if key == "DesperateCounter" then return reg.Tactics and reg.Tactics.DesperateCounter and reg.Tactics.DesperateCounter.id end
		if key == "VaultObstacle" then return reg.Parkour and reg.Parkour.VaultObstacle and reg.Parkour.VaultObstacle.id end
		if key == "LedgeDropLanding" then return reg.Parkour and reg.Parkour.LedgeDropLanding and reg.Parkour.LedgeDropLanding.id end
		if key == "SlamImpact" then return reg.Attacks and reg.Attacks.Specials and reg.Attacks.Specials.SlamImpact and reg.Attacks.Specials.SlamImpact.id end
		if key == "SlamRecovery" then return reg.Attacks and reg.Attacks.Specials and reg.Attacks.Specials.SlamRecovery and reg.Attacks.Specials.SlamRecovery.id end
		if key == "SlammedDown" then return reg.Reactions and reg.Reactions.SlammedDown and reg.Reactions.SlammedDown.id end
		if key == "DeathCollapse" then return reg.Reactions and reg.Reactions.DeathCollapse and reg.Reactions.DeathCollapse.id end

		-- Fallback to AnimationConfig.get
		local direct = AnimationConfig.get(key)
		if direct and direct.id then
			return direct.id
		end
		return nil
	end
})

return AnimationIds
