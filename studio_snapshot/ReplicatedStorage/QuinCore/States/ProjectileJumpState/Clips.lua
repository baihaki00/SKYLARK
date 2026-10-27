--// ProjectileJumpState/Clips.lua
-- What a jump looks and sounds like: its clips (the kit per style, the smack-down, the dive), the
-- dive's facing, and the launch's dust and shake.
-- (Moved out of ProjectileJumpState as it was: QuinCore audit 2026-10-27, step 7.)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local AudioModule = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("AudioModule"))
local VfxModule = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("VfxModule"))
local AnimationConfig = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("AnimationConfig"))
local AnimationModule = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("AnimationModule"))
local CombatConfig = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("CombatConfig"))

local Clips = {}

local function stopAnim(track)
	if track then track:Stop(0.2) end
end

-- Projectile jump kits (AnimationConfig.Registry.ProjectileJump): a jump picks one
local KITS = {
	{ name = "Ninja", jump = "ProjectileJump.NinjaJump", loop = "ProjectileJump.NinjaAirLoop" },
	{ name = "Standard", jump = "ProjectileJump.StandardJump", loop = "ProjectileJump.StandardAirLoop" },
}

local function playClip(humanoid, path, looped)
	local entry = AnimationConfig.get(path)
	local track = entry and AnimationModule.getTrack(humanoid, entry.id)
	if track then
		track.Priority = Enum.AnimationPriority.Action3
		track.Looped = looped == true
		track:Play(entry.fadeTime or 0.1, 1, entry.speed or 1)
	end
	return track
end

-- The arc jump's other look: one smack-down clip over the whole jump (AnimationConfig
-- Attacks.Special.ProceduralSmackDown, in place). Its markers: ProjectileJump (takeoff) 0.53 s,
-- BodyLanding 1.20 s, end 2.73 s. It starts at the takeoff; the airborne part is stretched or
-- squeezed every frame so the BodyLanding frame meets the touchdown, and the rest plays at normal
-- speed as the landing (RecoveryState carries it on instead of a landing clip).
local SMACK_PATH = "Attacks.Special.ProceduralSmackDown"
local SMACK_TAKEOFF = 0.53
local SMACK_LANDING = 1.2

local function playSmackDown(humanoid)
	local entry = AnimationConfig.get(SMACK_PATH)
	local track = entry and AnimationModule.getTrack(humanoid, entry.id)
	if track then
		track.Priority = Enum.AnimationPriority.Action3
		track.Looped = false
		track:Play(0.08, 1, 1)
		if track.Length > 0 then
			track.TimePosition = SMACK_TAKEOFF
		end
	end
	return track
end

-- The dive: the flying clip, head first along the path
local function playDiveAnim(humanoid)
	return playClip(humanoid, "ProjectileJump.DiveFly", true)
end

-- A dive only ever goes down. Re-aimed at 480+ studs/s toward a target above (one in the air, on
-- a higher platform) it went up past it, then down, then up again.
local function diveDirection(offset, fallback)
	local flat = Vector3.new(offset.X, 0, offset.Z)
	local y = math.min(offset.Y, -0.3 * math.max(flat.Magnitude, 1))
	local dir = Vector3.new(offset.X, y, offset.Z)
	return dir.Magnitude > 0.001 and dir.Unit or fallback
end

-- The launch's sound and shockwave are for a jump into the sky (owner 2026-10-27: "that sound is
-- for a Quin staying airborne for quite a while"): only when the jump tops out at least
-- ProjectileJump_LaunchFxHeight studs above the ground under it. A lower one sounds like a jump,
-- quietly, with no shockwave or shake. vy: the launch's upward speed.
local launchFxParams = RaycastParams.new()
launchFxParams.FilterType = Enum.RaycastFilterType.Exclude
local function launchFx(rootPart, vy, shake, untilT)
	local qs = workspace:FindFirstChild("QuinServer")
	launchFxParams.FilterDescendantsInstances = qs and { qs } or {}
	local hit = workspace:Raycast(rootPart.Position, Vector3.new(0, -1000, 0), launchFxParams)
	local above = hit and (rootPart.Position.Y - hit.Position.Y) or 0
	-- (the rise it really makes: a dash or dive that starts before the top cuts it short - untilT)
	local g = workspace.Gravity
	local t = math.max(vy, 0) / g
	if untilT then t = math.min(t, math.max(untilT, 0)) end
	local peak = above + math.max(vy, 0) * t - 0.5 * g * t * t
	if peak >= (CombatConfig.ProjectileJump_LaunchFxHeight or 200) then
		AudioModule.playJumpUp(rootPart.Position)
		VfxModule.createLaunchShockwave(rootPart)
		if shake then VfxModule.shakeScreen(rootPart.Position, 500, 8) end
	else
		AudioModule.playJumpSoft(rootPart.Position)
	end
end

Clips.stopAnim = stopAnim
Clips.KITS = KITS
Clips.playClip = playClip
Clips.SMACK_PATH = SMACK_PATH
Clips.SMACK_TAKEOFF = SMACK_TAKEOFF
Clips.SMACK_LANDING = SMACK_LANDING
Clips.playSmackDown = playSmackDown
Clips.playDiveAnim = playDiveAnim
Clips.diveDirection = diveDirection
Clips.launchFx = launchFx

return Clips
