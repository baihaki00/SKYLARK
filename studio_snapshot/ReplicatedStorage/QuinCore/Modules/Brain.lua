--// Brain.lua
-- One reasoning tick for a Quin, in order (QuinCore audit 2026-10-27, step 6):
--   Cognition   what it knows (senses -> attention -> memory -> self / environment / situation)
--   TaskChoice  what it sets out to do (fight, rescue, hunt, carry ...)
--   Targeting   whom, given that task
--   Decision    how (attack, retreat, pursue ...), weighed against that target
-- then the orders that follow (go idle, retreat, chase: the lowest state request, so a Knockback
-- or a clash another Quin set on this one between ticks wins - Modules/StateRequest).
--   Brain.tick(quin, rootPart, stateName) -> its tactical context, or nil
-- (Before: the same steps inline in Main, and the action read target facts Cognition had made
-- for last tick's target.)

local GameClock = require(game:GetService("ReplicatedStorage"):WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("GameClock")) -- (the game's clock: a freeze stops it)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local QuinCore = ReplicatedStorage:WaitForChild("QuinCore")
local Modules = QuinCore:WaitForChild("Modules")
local CombatConfig = require(QuinCore:WaitForChild("CombatConfig"))
local Cognition = require(QuinCore:WaitForChild("Cognition"))
local TaskChoice = require(Modules:WaitForChild("TaskChoice"))
local TargetingModule = require(Modules:WaitForChild("TargetingModule"))
local DecisionSystem = require(Modules:WaitForChild("DecisionSystem"))
local BattleEventSystem = require(Modules:WaitForChild("BattleEventSystem"))
local DebugReadouts = require(Modules:WaitForChild("DebugReadouts")) -- (debug-only attributes)
local RuntimeTracer = require(Modules:WaitForChild("RuntimeTracer"))
local StateRequest = require(Modules:WaitForChild("StateRequest"))

local Brain = {}

-- States in which a Quin is not in control of itself: it does not pick a new target in them
-- (measured: 22 % of all target changes happened knocked down or in mid-jump, where it cannot act
-- on the choice and comes out of it turned to someone else)
local NO_RETARGET_STATES = { Knockback = true, Recovery = true, ProjectileJump = true, MidAirClash = true, Airborne = true, WallRun = true }

function Brain.tick(Quin, rootPart, stateName)
	local tacticalContext = Cognition.update(Quin)
	if not tacticalContext then return nil end
	local showdownRole = Quin:GetAttribute("RespectRole")
	local function order(state, why)
		StateRequest.ask(Quin, state, StateRequest.BRAIN, why or "brain")
	end

	-- 1. Utility-based target selection & switching
	local oldTargetName = Quin:GetAttribute("CurrentTarget")
	local selectedTarget, targetScore, targetReason
	if NO_RETARGET_STATES[stateName] then
		selectedTarget = TargetingModule.getCommittedTarget(Quin, rootPart) -- (the one it has)
	else
		-- what it sets out to do first (fight, rescue, hunt), then whom
		tacticalContext.Task = TaskChoice.choose(Quin, rootPart, tacticalContext)
		selectedTarget, targetScore, targetReason = TargetingModule.selectTarget(Quin, tacticalContext)
	end
	if targetReason then
		DebugReadouts.set(Quin, "TargetReason", targetReason)
	end
	if selectedTarget then
		-- If target changed while actively in Fight state and next target is distant,
		-- enter TargetTransition to breathe, survey, and reset rather than robotic snapping
		if oldTargetName and oldTargetName ~= "" and oldTargetName ~= selectedTarget.Name and stateName == "Fight" then
			local sHRP = selectedTarget:FindFirstChild("HumanoidRootPart")
			local dist = sHRP and (sHRP.Position - rootPart.Position).Magnitude or 50
			if dist > (CombatConfig.CombatRange or 8.2) * 1.5 then
				order("Idle")
			end
		end
		Quin:SetAttribute("CurrentTarget", selectedTarget.Name)
	end
	-- The action below is weighed against the enemy just chosen. Cognition described the one it
	-- had last tick: on a tick that switched, "finish it, it is nearly down" and "it is alone"
	-- were about the old target while the distance was to the new one.
	if selectedTarget and selectedTarget ~= tacticalContext.BestTarget then
		Cognition.retarget(Quin, selectedTarget)
	end

	-- A task with a place to go (Objectives: carry, guard, escort ...): IdleState walks
	-- it there, and a chase after someone far off is dropped to get back to the job
	local task = tacticalContext.Task
	if task and task.point then
		Quin:SetAttribute("ObjectiveGoTo", task.point)
		Quin:SetAttribute("ObjectiveSpeed", task.speed or 40)
		Quin:SetAttribute("ObjectiveUrgency", task.urgency or 1)
		Quin:SetAttribute("ObjectivePaceWhy", task.paceWhy)
		Quin:SetAttribute("ObjectiveFace", task.face)
		Quin:SetAttribute("ObjectiveEngage", task.engage or 16)
		Quin:SetAttribute("ObjectiveUntil", GameClock.serverNow() + 1.0)
		local sHRP = selectedTarget and selectedTarget:FindFirstChild("HumanoidRootPart")
		local tDist = sHRP and (sHRP.Position - rootPart.Position).Magnitude or math.huge
		local away = stateName == "Chase" or stateName == "Circling" or stateName == "Overwatch"
			or (stateName == "Fight" and (task.engage or 16) <= 0)
		if away and tDist > (task.engage or 16) * 1.4 then
			order("Idle")
		end
	elseif Quin:GetAttribute("ObjectiveGoTo") ~= nil then
		Quin:SetAttribute("ObjectiveGoTo", nil)
	end

	-- What it knows of its target right now, from its own contact record (Cognition:
	-- senses and memory), whatever state it is in: TargetHasLoS (it sees it) and
	-- TargetKnownBy (sight, touch, hearing, memory, report, rumour). Written here and
	-- nowhere else. (Target selection and ChaseState each wrote TargetHasLoS, and only
	-- on some paths: half the time a target was behind an obstacle it still said "seen".)
	local contact = selectedTarget and Cognition.contactFor(Quin, selectedTarget)
	local seen = contact ~= nil and contact.visible == true and contact.hasLineOfSight == true
	local knownBy = contact and (seen and "sight" or contact.channel or "memory") or nil
	if Quin:GetAttribute("TargetHasLoS") ~= seen then
		Quin:SetAttribute("TargetHasLoS", seen)
	end
	if Quin:GetAttribute("TargetKnownBy") ~= knownBy then
		Quin:SetAttribute("TargetKnownBy", knownBy)
	end
	
	-- 2. Track distressed ally for emergent rescue
	if tacticalContext.DistressedAlly then
		Quin:SetAttribute("DistressedAllyName", tacticalContext.DistressedAlly.Name)
	else
		Quin:SetAttribute("DistressedAllyName", "")
	end

	-- 3. Evaluate candidate action utilities biased by personality
	local distToTgt = (selectedTarget and selectedTarget:FindFirstChild("HumanoidRootPart"))
		and (selectedTarget.HumanoidRootPart.Position - rootPart.Position).Magnitude or 15

	local bestAction, tacticalState = DecisionSystem.evaluateAction(Quin, tacticalContext, distToTgt)
	Quin:SetAttribute("RecommendedAction", bestAction)
	Quin:SetAttribute("TacticalDecision", bestAction)

	-- 4. Decision-driven behavior override: wire the tactical decision into the FSM
	-- States a decision to retreat pulls the Quin out of: a fight, and a chase back
	-- into one (a Quin at 5% health used to flee, turn round and chase, eight times over)
	local isMeleeCommitted = (stateName == "Fight" or stateName == "Special" or stateName == "Chase")
	local nowClock = GameClock.now()

	if bestAction == "Retreat" and isMeleeCommitted and showdownRole ~= "Duelist" then
		local lastBreakoff = Quin:GetAttribute("LastRetreatBreakoff") or 0
		if (nowClock - lastBreakoff) >= (CombatConfig.RetreatBreakoffCooldown or 3.0) then
			Quin:SetAttribute("LastRetreatBreakoff", nowClock)
			order("Retreat")
			RuntimeTracer.checkpoint(Quin, "Decision: Retreat (break off melee)")
		end
	elseif bestAction == "Pursue" and stateName == "Idle" then
		-- Recovery is not interrupted: it finishes the get-up and then picks its own next
		-- state. Forcing Chase from here cut the get-up clip after ~0.1s (prone -> sprint pop).
		-- (a Quin walking to its task's spot - IdleState - is not pulled off after someone
		-- outside the job's reach)
		local onJob = task and task.point and distToTgt > (task.engage or 16) * 1.4
		if distToTgt > (CombatConfig.PursueEngageDistance or 20.0) and not onJob then
			order("Chase")
			RuntimeTracer.checkpoint(Quin, "Decision: Pursue (chase target)")
		end
	end

	-- 4. Emit emergent battle events telemetry
	BattleEventSystem.checkEvents(Quin, tacticalContext)
	return tacticalContext
end

return Brain
