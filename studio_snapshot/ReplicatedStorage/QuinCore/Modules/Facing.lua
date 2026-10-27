--// Facing.lua
-- The one turner a state holds to keep a Quin's body facing something while it stands, strafes or
-- fights (body claim, step 1: QUINCORE_AUDIT_20261027.md). One AlignOrientation per Quin, named
-- "Facing", tagged with its holder; each holder turns at its own pace (TUNE below, in one place).
--   Facing.hold(rootPart, "Fight") -> the AlignOrientation (taken over from another holder: made
--                                     fresh from where the body faces now, with this one's pace)
--   Facing.get(rootPart [, holder...]) -> it, if held (by one of these holders)
--   Facing.drop(rootPart [, holder...]) -> let go (only if one of these holds it; any if none given)
-- Main drops it on every state change, so no state can leave a turner behind on the body.
-- Holding it is owning the body's facing: the humanoid's AutoRotate goes off and the locomotion's
-- steering facing stops at once (measured 2026-10-27 in the 16v16: in Fight, AutoRotate was still
-- turning the body toward where it walked 70% of the time the fight held it toward its target, and
-- the steering facing was on with it 6% of the time). Dropping it gives AutoRotate back.
-- (Before: IdleGyro, CirclingGyro and FightGyro, each made and destroyed by its own state, and
-- IdleGyro shared by three users at whichever pace the first one made it with.)
-- Moves keep their own short-lived aligns (a jump, a skid, a tackle, a clash): the locomotion's
-- steering facing still gives way to any of them (LocomotionModule.otherAlignActive).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CombatConfig = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("CombatConfig"))

local Facing = {}

local NAME = "Facing"
local SOCIAL = CombatConfig.Social or {}
local TURN_CAP = CombatConfig.Combat_FacingMaxTurnRate or 14 -- (uncapped, a body whipped round at 18-26 rad/s)

-- holder -> responsiveness, max torque, max turn rate (rad/s)
local TUNE = {
	Fight = { 22, 60000, TURN_CAP },                                                -- squared up to its target
	Circling = { CombatConfig.Circling_GyroResponsiveness or 35, 100000, TURN_CAP }, -- strafing round it
	Idle = { 15, 100000, TURN_CAP },                                                 -- standing, turned to the nearest enemy
	IdlePost = { 8, 100000, 4 },                                                     -- on a post, looking out (slow)
	Watch = { SOCIAL.WatchTurnResponsiveness or 6, 100000, SOCIAL.WatchTurnRate or 3 }, -- stepped back, watching
}

local function holds(align, holders)
	if #holders == 0 then return true end
	local who = align:GetAttribute("Holder")
	for _, h in ipairs(holders) do
		if h == who then return true end
	end
	return false
end

function Facing.get(rootPart, ...)
	local align = rootPart and rootPart:FindFirstChild(NAME)
	if align and holds(align, { ... }) then
		return align
	end
	return nil
end

local function humanoidOf(rootPart)
	return rootPart.Parent and rootPart.Parent:FindFirstChildOfClass("Humanoid")
end

function Facing.drop(rootPart, ...)
	local align = Facing.get(rootPart, ...)
	if align then
		align:Destroy()
		local humanoid = humanoidOf(rootPart)
		if humanoid then humanoid.AutoRotate = true end
	end
end

-- The body's facing is taken: nothing else turns it while this is held
local function own(rootPart)
	local humanoid = humanoidOf(rootPart)
	if humanoid and humanoid.AutoRotate then humanoid.AutoRotate = false end
	local steer = rootPart:FindFirstChild("SteerFacing") -- (LocomotionModule: it lets go on its next frame)
	if steer and steer.Enabled then steer.Enabled = false end
end

function Facing.hold(rootPart, holder)
	local align = rootPart:FindFirstChild(NAME)
	if align and align:GetAttribute("Holder") == holder then
		own(rootPart)
		return align
	end
	if align then
		align:Destroy()
	end
	local tune = TUNE[holder] or TUNE.Idle
	local att = rootPart:FindFirstChild("RootAttachment") or Instance.new("Attachment", rootPart)
	att.Name = "RootAttachment"
	align = Instance.new("AlignOrientation")
	align.Name = NAME
	align.Mode = Enum.OrientationAlignmentMode.OneAttachment
	align.Attachment0 = att
	align.RigidityEnabled = false
	align.Responsiveness = tune[1]
	align.MaxTorque = tune[2]
	align.MaxAngularVelocity = tune[3]
	align.CFrame = rootPart.CFrame
	align:SetAttribute("Holder", holder)
	align:SetAttribute("BaseResponsiveness", tune[1])
	align.Parent = rootPart
	own(rootPart)
	return align
end

return Facing
