--// Cognition.SelfAwareness
-- What is happening to the Quin itself: its body, its resources, what it is doing and whether
-- that is working.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local QuinCore = ReplicatedStorage:WaitForChild("QuinCore")
local SpatialModule = require(QuinCore:WaitForChild("Modules"):WaitForChild("SpatialModule"))

local SelfAwareness = {}

local DAMAGE_WINDOW = 2.0 -- seconds of health history kept for "recent damage"
local STALLED_SPEED = 1.5 -- studs/s below which a Quin that wants to move is not getting anywhere
local MOVING_STATES = { Chase = true, Retreat = true, ReEntry = true }

function SelfAwareness.assess(board, quinModel, rootPart, humanoid, now)
	local history = board.history
	table.insert(history, { time = now, health = humanoid.Health })
	while #history > 1 and now - history[1].time > DAMAGE_WINDOW do
		table.remove(history, 1)
	end

	local velocity = rootPart.AssemblyLinearVelocity
	local planarSpeed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
	local state = quinModel:GetAttribute("CurrentState") or "Idle"

	-- Is the current movement getting anywhere?
	if MOVING_STATES[state] and planarSpeed < STALLED_SPEED then
		board.stalledSince = board.stalledSince or now
	else
		board.stalledSince = nil
	end

	local humanoidState = humanoid:GetState()
	local airborne = humanoidState == Enum.HumanoidStateType.Freefall or humanoidState == Enum.HumanoidStateType.Jumping
		or humanoid.PlatformStand

	return {
		position = rootPart.Position,
		velocity = velocity,
		planarSpeed = planarSpeed,
		facing = rootPart.CFrame.LookVector,
		healthRatio = humanoid.Health / humanoid.MaxHealth,
		energyRatio = math.clamp((quinModel:GetAttribute("Energy") or 100) / (quinModel:GetAttribute("MaxEnergy") or 100), 0, 1),
		recentDamage = math.max(history[1].health - humanoid.Health, 0),
		state = state,
		targetName = quinModel:GetAttribute("CurrentTarget") or quinModel:GetAttribute("TargetQuin"),
		isAirborne = airborne,
		isGrounded = not airborne and SpatialModule.isGrounded(rootPart),
		stalledFor = board.stalledSince and (now - board.stalledSince) or 0,
	}
end

return SelfAwareness
