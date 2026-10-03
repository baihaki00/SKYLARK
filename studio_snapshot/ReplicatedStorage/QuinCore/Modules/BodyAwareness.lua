--// BodyAwareness.lua
-- "There is someone in my way." A moving Quin looks along its path and steers round the bodies
-- it would walk into, instead of shoving through them.
--
--   adjust(fighter, rootPart, desired, speed) -> the direction to move in
--
-- Called by LocomotionModule's steer driver, so it holds in every state that moves (chasing,
-- circling, closing in a fight, retreating, the social walks).
--   - Only bodies ahead, inside the width of its path, within the look-ahead (which grows with
--     speed). A moving body is judged where it will be when the Quin gets there.
--   - Its own opponent is not in the way: that is where it is going.
--   - A body right beside it (inside its personal space) is eased away from, so two Quins going
--     for the same opponent come at it shoulder to shoulder, not through each other.
--   - A body to one side is passed on the other. One dead ahead is passed on the right, by both
--     of two Quins meeting head on, so they pass instead of mirroring each other.
--   - It bends the route (up to MaxSwerve); it never stops the Quin.
-- Publishes BodyInWay (the name of the body it is steering round) for the mind panel.
-- Switches: CombatConfig.BodyAwareness.Enabled; Workspace attributes BodyAwareness = false (all
-- of it) and BodyPersonalSpace = false (the personal-space rule only).

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CombatConfig = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("CombatConfig"))

local BodyAwareness = {}

local CFG = CombatConfig.BodyAwareness or {}
local ROSTER_REFRESH = 0.2 -- seconds between looks at who is on the field

local roster = {} -- { model, root } of the living Quins
local rosterAt = 0

local function refreshRoster()
	local now = os.clock()
	if now - rosterAt < ROSTER_REFRESH then return end
	rosterAt = now
	roster = {}
	local folder = Workspace:FindFirstChild("QuinServer")
	if not folder then return end
	for _, model in ipairs(folder:GetChildren()) do
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		local root = model:FindFirstChild("HumanoidRootPart")
		if humanoid and root and humanoid.Health > 0 then
			table.insert(roster, { model = model, root = root })
		end
	end
end

function BodyAwareness.adjust(fighter, rootPart, desired, speed)
	if CFG.Enabled == false or Workspace:GetAttribute("BodyAwareness") == false then
		return desired
	end
	refreshRoster()

	local lookAhead = math.clamp(speed * (CFG.LookTime or 0.6), CFG.MinLook or 5, CFG.MaxLook or 16)
	local width = CFG.PathWidth or 3.6 -- half the width of the path: two bodies and a little air
	local heightBand = CFG.HeightBand or 5
	local personalSpace = Workspace:GetAttribute("BodyPersonalSpace") == false and 0 or (CFG.PersonalSpace or 4)
	local opponent = fighter:GetAttribute("CurrentTarget")
	local origin = rootPart.Position
	local right = Vector3.new(-desired.Z, 0, desired.X)

	local push, heaviest, inWay = 0, 0, nil
	for _, other in ipairs(roster) do
		local model, root = other.model, other.root
		if model ~= fighter and model.Name ~= opponent and root.Parent then
			local to = root.Position - origin
			if math.abs(to.Y) < heightBand then
				local ahead = to:Dot(desired)
				local weight = 0
				-- beside it, inside its personal space
				local gap = Vector3.new(to.X, 0, to.Z).Magnitude
				if gap < personalSpace and ahead > -personalSpace * 0.5 then
					weight = (1 - gap / personalSpace) * (CFG.PersonalWeight or 0.7)
				end
				-- on its path
				if ahead > 0 and ahead < lookAhead then
					-- where it will be by the time this Quin gets there (half its lead: it may turn)
					local velocity = root.AssemblyLinearVelocity
					to += Vector3.new(velocity.X, 0, velocity.Z) * (ahead / math.max(speed, 8)) * 0.5
					ahead = to:Dot(desired)
					local lateral = to:Dot(right)
					if ahead > 0 and ahead < lookAhead and math.abs(lateral) < width then
						weight = math.max(weight, (1 - ahead / lookAhead) * (1 - math.abs(lateral) / width))
					end
				end
				if weight > 0 then
					local hand = 1 -- dead ahead: pass on the right
					if to:Dot(right) > 0.3 then hand = -1 end -- it is to the right: go left of it
					push += hand * weight
					if weight > heaviest then
						heaviest, inWay = weight, model.Name
					end
				end
			end
		end
	end

	local noticed = heaviest > (CFG.NoticeWeight or 0.25) and inWay or nil
	if fighter:GetAttribute("BodyInWay") ~= noticed then
		fighter:SetAttribute("BodyInWay", noticed)
	end
	if push == 0 then
		return desired
	end
	local swerve = math.clamp(push * (CFG.Gain or 1.6), -(CFG.MaxSwerve or 0.9), CFG.MaxSwerve or 0.9)
	return (desired + right * swerve).Unit
end

return BodyAwareness
