--// Spacing.lua
-- Fighting bodies keep their room (FIGHT_PROGRAMME.md step 1). Measured 2026-10-29: roots were
-- under 3 studs apart for ~9% of engaged time, torsos drawn inside each other in 4-9% of close
-- frames, and half of that time no push was moving the body at all: it walked in (the Humanoid's
-- own walk carrying on after a step-in) until the collision boxes stopped it.
-- Every frame, for every two Quins on the same ground level:
--   * neither walks or is pushed closer than Spacing_BodyGap to the other;
--   * a Quin that is striking its target stops at the strike's own gap (StrikeStopGap, set by
--     FightState.Strike from the clip's reach), so the limb lands in the body, not the bodies;
--   * two bodies already inside each other are eased apart.
-- Only the closing part of the motion is taken away: sideways motion goes on. It is a short
-- request on ImpulseModule (tag "space"), refreshed while the body still closes, so it never
-- fights a knockback and lets go the frame the body stops closing.
-- Left alone: bodies in the air, clashing, knocked back, dead, on walls, a player's own Quin, and
-- any Quin with the SpacingExempt attribute (a grab, later). Runs from a loop the Server starts.

local GameClock = require(game:GetService("ReplicatedStorage"):WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("GameClock")) -- (the game's clock: a freeze stops it)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local QuinCore = ReplicatedStorage:WaitForChild("QuinCore")
local CombatConfig = require(QuinCore:WaitForChild("CombatConfig"))
local ImpulseModule = require(QuinCore:WaitForChild("Modules"):WaitForChild("ImpulseModule"))

local Spacing = {}

local EXEMPT_STATES = {
	MidAirClash = true, Knockback = true, Airborne = true, ProjectileJump = true, Recovery = true,
	Death = true, WallRun = true, ReEntry = true, Special = true, Piloted = true,
}
local LOOK_RANGE = 7       -- pairs further apart than this are not looked at
local CLOSING_MIN = 0.5    -- studs/s toward the other that counts as closing
local TAG = "space"

local function cfg(key, default)
	local v = CombatConfig["Spacing_" .. key]
	if v == nil then return default end
	return v
end

function Spacing.enabled()
	-- (Studio: Workspace attribute Ablate_Spacing switches it off live, for A/B by eye or probe)
	if workspace:GetAttribute("Ablate_Spacing") and game:GetService("RunService"):IsStudio() then return false end
	return CombatConfig.Spacing_Enabled ~= false
end

-- Root distance at which a strike's limb is in the target's body by Spacing_ContactDepth
-- (reach: how far ahead of the root the clip's limb gets, AnimationConfig.Attacks .reach)
function Spacing.strikeStopGap(reach)
	if not reach then return CombatConfig.Combat_LungeStopDistance or 4.8 end
	return reach + cfg("TargetRadius", 0.72) - cfg("ContactDepth", 0.25)
end

-- May this body be held? (the others in a pair still count as obstacles)
local function holdable(model, root)
	if model:GetAttribute("SpacingExempt") or model:GetAttribute("PilotClientMoves") or model:GetAttribute("IsPlayerControlled") then return false end
	if EXEMPT_STATES[model:GetAttribute("CurrentState")] then return false end
	local mover = root:FindFirstChild("ImpulseLV")
	if mover and (mover:GetAttribute("Priority") or 0) >= ImpulseModule.Priority.Knockback then return false end
	return true
end

local function consider(self, other, dir, gap)
	if not self.holdable then return end
	-- (where it will be a moment from now, while it closes: the hold reaches the client that moves
	-- the body a frame or two late, and two bodies closing at once ate the gap in that time)
	local v = self.root.AssemblyLinearVelocity
	local closing = Vector3.new(v.X, 0, v.Z):Dot(dir)
	-- (capped: at a strike's 60 studs/s lunge 0.1 s is 6 studs, and the hold stopped the step-in
	-- that far short of reach)
	if closing > 0 then gap -= math.min(closing * cfg("LookAhead", 0.1), cfg("LookAheadMax", 0.75)) end
	local bodyGap = cfg("BodyGap", 3.0)
	local minGap = bodyGap
	local model = self.model
	if model:GetAttribute("Attacking") == true and model:GetAttribute("CurrentTarget") == other.model.Name then
		minGap = math.max(minGap, model:GetAttribute("StrikeStopGap") or Spacing.strikeStopGap(nil))
	end
	if gap >= minGap then return end
	self.limits = self.limits or {}
	local depth = bodyGap - cfg("ApartSlack", 0.5) - gap
	table.insert(self.limits, { dir = dir, apart = depth > 0 and depth or nil })
end

local function hold(entry)
	local root = entry.root
	local v = root.AssemblyLinearVelocity
	local velocity = Vector3.new(v.X, 0, v.Z)
	local act = false
	for _, limit in ipairs(entry.limits) do
		if limit.apart or velocity:Dot(limit.dir) > CLOSING_MIN then act = true break end
	end
	if not act then return end

	local away = Vector3.zero
	for _, limit in ipairs(entry.limits) do
		ImpulseModule.cancelToward(entry.model, limit.dir, 0.3, TAG)
		local along = velocity:Dot(limit.dir)
		if along > 0 then velocity -= limit.dir * along end
		away -= limit.dir
		if limit.apart then
			velocity -= limit.dir * math.min(limit.apart * cfg("ApartRate", 10), cfg("ApartMaxSpeed", 10))
		end
	end
	if velocity.Magnitude < 0.3 then
		if away.Magnitude < 0.01 then return end
		velocity = away.Unit * 0.3
	end
	ImpulseModule.push(entry.model, TAG, velocity, velocity.Magnitude, cfg("HoldTime", 0.06), {
		profile = "hold", endRatio = 1, rampIn = 0,
		priority = ImpulseModule.Priority.Reaction, maxForce = cfg("MaxForce", 40000),
	})
end

local function step()
	if not Spacing.enabled() or GameClock.frozen() then return end
	local folder = Workspace:FindFirstChild("QuinServer")
	if not folder then return end
	local list = {}
	for _, model in ipairs(folder:GetChildren()) do
		local root = model:FindFirstChild("HumanoidRootPart")
		local hum = model:FindFirstChildOfClass("Humanoid")
		if root and hum and hum.Health > 0 then
			table.insert(list, { model = model, root = root, pos = root.Position, holdable = holdable(model, root) })
		end
	end
	local vertical = cfg("VerticalRange", 3.5)
	for i = 1, #list do
		local a = list[i]
		for j = i + 1, #list do
			local b = list[j]
			if math.abs(b.pos.Y - a.pos.Y) < vertical then
				local flat = Vector3.new(b.pos.X - a.pos.X, 0, b.pos.Z - a.pos.Z)
				local gap = flat.Magnitude
				if gap < LOOK_RANGE and gap > 0.01 then
					local dir = flat / gap
					consider(a, b, dir, gap)
					consider(b, a, -dir, gap)
				end
			end
		end
	end
	for _, entry in ipairs(list) do
		if entry.limits then hold(entry) end
	end
end

local connection = nil
-- Run the loop from a script that lives all session (Server). Call once at start-up.
function Spacing.start()
	if connection then connection:Disconnect() end
	connection = RunService.Heartbeat:Connect(step)
end

return Spacing
