--// SlideTackle.lua
-- The slide as a tackle (combination moves): a Quin sliding in on its target takes the legs of
-- whoever is standing in its lane, unless they see it coming and hop over it.
--
--   the sweep   during the glide (the low part of the slide clip), an enemy whose body is in
--               front of the slider's feet and whose own feet are still on the ground has its legs
--               taken: damage through DamageModule (guards, protections and the duel rules apply),
--               a small launch along the slide, and it falls the way its legs went: swept from
--               behind it goes down on its back, from the front on its face (the fall clip from
--               the first frame, the body's root kept upright like every other knockdown;
--               KnockbackState, SweptAt / SweepFallSide). (A 180-degree spin of the root ended
--               it on its head, and Recovery then turned it upright under a get-up clip that
--               starts lying down: it got up twice.)
--   the hurdle  each enemy in the lane gets one reflex as the slide closes in: one that is facing
--               it, not busy striking and on its feet may hop (chance from its mobility); a hop in
--               time lifts the feet over the slide and it passes underneath
--
-- LocomotionModule.slide runs the slide itself and calls back here every glide frame (onGlide).
-- Publishes: SweptAt / SweepFallSide on the victim, SlideHurdledAt on a hurdler, Workspace TackleStats.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local QuinCore = ReplicatedStorage:WaitForChild("QuinCore")
local Modules = QuinCore:WaitForChild("Modules")
local CombatConfig = require(QuinCore:WaitForChild("CombatConfig"))

local SlideTackle = {}

local isStudio = game:GetService("RunService"):IsStudio()

local stats = { slides = 0, sweeps = 0, hurdles = 0, guarded = 0 }

local function cfg(key, default)
	local v = CombatConfig["SlideTackle_" .. key]
	if v == nil then return default end
	return v
end

local function publish()
	Workspace:SetAttribute("TackleStats", string.format("slides %d sweeps %d hurdles %d guarded %d", stats.slides, stats.sweeps, stats.hurdles, stats.guarded))
end

local DOWN_STATES = { Knockback = true, Recovery = true, Death = true, ProjectileJump = true, Airborne = true, MidAirClash = true, WallRun = true }

-- Feet height above the ground under them
local function feetClearance(model, rootPart, humanoid)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { Workspace:FindFirstChild("QuinServer") or model }
	local hit = Workspace:Raycast(rootPart.Position, Vector3.new(0, -40, 0), params)
	if not hit then return math.huge end
	local feetY = rootPart.Position.Y - (humanoid.HipHeight + rootPart.Size.Y / 2)
	return feetY - hit.Position.Y
end

-- It sees the slide coming and hops over it
local function hurdle(victim, humanoid, rootPart)
	local g = Workspace.Gravity
	local v = rootPart.AssemblyLinearVelocity
	rootPart.AssemblyLinearVelocity = Vector3.new(v.X * 0.5, math.sqrt(2 * g * cfg("HurdleHeight", 6)), v.Z * 0.5)
	humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
	local AnimationModule = require(Modules:WaitForChild("AnimationModule"))
	AnimationModule.playConfig(humanoid, "Parkour.SlideHurdle", 1.2, Enum.AnimationPriority.Action3, false)
	victim:SetAttribute("SlideHurdledAt", os.clock())
	victim:SetAttribute("ObstacleAwareness", "Hopped over a slide tackle")
	stats.hurdles += 1
	publish()
end

-- The flip: the body turns over once, the way it is falling, in the air. The first half under
-- the flailing clip (KnockbackState), then the fall pose for its side takes over and it comes
-- round upright for the landing (Recovery: a landing on its feet, or down and up from that side).
-- It is turned by a constraint whose target is stepped every frame (an angular velocity alone
-- was damped to ~90 degrees). Not by writing the root's CFrame: a CFrame written every frame
-- reaches the clients outside the physics stream, and when the writes stopped the body hung
-- where it was, about 4 studs up, for ~0.17 s on every client before it came down.
local FLIP_ALIGN, FLIP_ATT = "SweepFlip", "SweepFlipAtt"

local function flip(victim, root, humanoid, axis, side, airtime)
	local RunService = game:GetService("RunService")
	local AnimationModule = require(Modules:WaitForChild("AnimationModule"))
	local start = root.CFrame - root.Position
	local total = math.rad(cfg("FlipDegrees", 360))
	local flipTime = airtime * cfg("FlipShare", 0.85)
	local t0 = os.clock()
	local switched = false

	local att = Instance.new("Attachment")
	att.Name = FLIP_ATT
	att.Parent = root
	local align = Instance.new("AlignOrientation")
	align.Name = FLIP_ALIGN
	align.Mode = Enum.OrientationAlignmentMode.OneAttachment
	align.RigidityEnabled = true
	align.Attachment0 = att
	align.CFrame = start
	align.Parent = root

	local conn
	local function finish()
		conn:Disconnect()
		align:Destroy()
		att:Destroy()
	end
	conn = RunService.Heartbeat:Connect(function()
		if not root.Parent or humanoid.Health <= 0 or victim:GetAttribute("CurrentState") == "Recovery" then
			finish()
			return
		end
		local p = math.min((os.clock() - t0) / flipTime, 1)
		local eased = p * p * (3 - 2 * p)
		align.CFrame = CFrame.fromAxisAngle(axis, total * eased) * start
		if not switched and eased >= 0.5 then
			switched = true
			AnimationModule.stopConfig(humanoid, "Movement.FallAirKnockback", 0.15)
			AnimationModule.playConfig(humanoid, side == "Front" and "Movement.FallFront" or "Movement.FallBack", 1.0, Enum.AnimationPriority.Action4, true)
		end
		if p >= 1 then finish() end
	end)
end

-- Its legs are taken
local function sweep(slider, victim, dir, speed)
	local DamageModule = require(Modules:WaitForChild("DamageModule"))
	local info = DamageModule.calculate(slider, victim, 1, cfg("DamageMultiplier", 0.8))
	local applied, _, status = DamageModule.apply(slider, victim, info)
	if not applied then
		if status == "Blocked" then stats.guarded += 1 publish() end
		return false
	end
	local root = victim:FindFirstChild("HumanoidRootPart")
	local humanoid = victim:FindFirstChildOfClass("Humanoid")
	if not (root and humanoid) or humanoid.Health <= 0 then return true end
	-- Which way it goes down: the legs are knocked along the slide, so the trunk topples the
	-- other way, and its own momentum carries the trunk on. A Quin standing with its back to the
	-- slide falls on its back, one facing it on its face, and one running at it goes down forward.
	local look = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
	local v = root.AssemblyLinearVelocity
	local topple = -dir * cfg("Topple", 1) + Vector3.new(v.X, 0, v.Z) / cfg("MomentumSpeed", 30)
	local side = (look.Magnitude > 0.01 and look.Unit:Dot(topple) >= 0) and "Front" or "Back"
	victim:SetAttribute("KnockbackType", "air")
	victim:SetAttribute("LaunchedAt", tick())
	victim:SetAttribute("SweptAt", os.clock())
	victim:SetAttribute("SweepFallSide", side)
	victim:SetAttribute("LastAttackerName", slider.Name)
	humanoid.PlatformStand = true
	local launch = cfg("Launch", 55)
	root.AssemblyLinearVelocity = dir * math.min(speed * cfg("Carry", 0.35), 20) + Vector3.new(0, launch, 0)
	root.AssemblyAngularVelocity = Vector3.zero
	victim:SetAttribute("ForceState", "Knockback")
	-- over the way it is falling: the head turns toward the topple
	local toppleFlat = Vector3.new(topple.X, 0, topple.Z)
	toppleFlat = toppleFlat.Magnitude > 0.01 and toppleFlat.Unit or -dir
	flip(victim, root, humanoid, Vector3.yAxis:Cross(toppleFlat).Unit, side, 2 * launch / workspace.Gravity)
	local AudioModule = require(Modules:WaitForChild("AudioModule"))
	AudioModule.playImpact(root.Position, true)
	stats.sweeps += 1
	publish()
	return true
end

-- A slide that can tackle. Returns the slide's duration (0 when it could not start).
function SlideTackle.slide(fighter, humanoid, rootPart, target)
	local LocomotionModule = require(Modules:WaitForChild("LocomotionModule"))
	if CombatConfig.SlideTackle_Enabled == false then
		return LocomotionModule.slide(fighter, humanoid, rootPart)
	end
	-- Aimed at where the target will be when it gets there; one too far off its run is no tackle
	local aim = nil
	local targetRoot = target and target:FindFirstChild("HumanoidRootPart")
	if targetRoot then
		local v = rootPart.AssemblyLinearVelocity
		local run = Vector3.new(v.X, 0, v.Z)
		local gap = Vector3.new(targetRoot.Position.X - rootPart.Position.X, 0, targetRoot.Position.Z - rootPart.Position.Z)
		local lead = math.clamp(gap.Magnitude / math.max(run.Magnitude, 20), 0, cfg("MaxLead", 0.8))
		local tv = targetRoot.AssemblyLinearVelocity
		aim = gap + Vector3.new(tv.X, 0, tv.Z) * lead
		if run.Magnitude < 1 or aim.Magnitude < 1 or aim.Unit:Dot(run.Unit) < math.cos(math.rad(cfg("MaxAimAngle", 40))) then
			fighter:SetAttribute("TackleSkip", string.format("aim off the run (run %.0f studs/s)", run.Magnitude))
			return 0
		end
	end
	local team = fighter:GetAttribute("Team")
	local rolled = {} -- enemies that had their reflex
	local done = {}   -- enemies already swept or passed
	local reach = cfg("Reach", 4.5)
	local width = cfg("Width", 2.5)
	local duration = LocomotionModule.slide(fighter, humanoid, rootPart, nil, nil, {
		aim = aim,
		maxTurn = cfg("MaxAimAngle", 40),
		onGlide = function(_, speed, dir)
			local folder = Workspace:FindFirstChild("QuinServer")
			if not folder then return end
			local feet = rootPart.Position
			for _, enemy in ipairs(folder:GetChildren()) do
				local eRoot = enemy:FindFirstChild("HumanoidRootPart")
				local eHum = enemy:FindFirstChildOfClass("Humanoid")
				if eRoot and eHum and eHum.Health > 0 and not done[enemy] and enemy:GetAttribute("Team") ~= team
					and not DOWN_STATES[enemy:GetAttribute("CurrentState") or ""] then
					local rel = eRoot.Position - feet
					local ahead = rel:Dot(dir)
					local side = (rel - dir * ahead)
					side = Vector3.new(side.X, 0, side.Z).Magnitude
					if enemy == target then -- (debug HUD, probes)
						fighter:SetAttribute("TackleView", string.format("ahead %.1f side %.1f clear %.1f", ahead, side, feetClearance(enemy, eRoot, eHum)))
					end
					if side <= width + 1 and ahead > -1 then
						-- its reflex as the slide closes in
						-- (time to contact from the closing speed: one running at the slide meets it sooner)
						local closing = speed - eRoot.AssemblyLinearVelocity:Dot(dir)
						if not rolled[enemy] and ahead / math.max(closing, 1) <= cfg("ReflexLead", 0.32) then
							rolled[enemy] = true
							local look = eRoot.CFrame.LookVector
							local facing = Vector3.new(look.X, 0, look.Z).Unit:Dot(-dir) > 0.3
							local busy = enemy:GetAttribute("Attacking") == true
							local mobility = enemy:GetAttribute("Pers_MobilityPreference") or 0.6
							local roll = math.random() < cfg("HurdleChance", 0.35) * (0.5 + mobility)
							-- (Studio demo switch: Workspace TackleOutcome = "hurdle" | "sweep" decides the reflex)
							local forced = isStudio and Workspace:GetAttribute("TackleOutcome")
							if forced == "hurdle" then roll = true elseif forced == "sweep" then roll = false end
							if (facing or forced == "hurdle") and not busy and feetClearance(enemy, eRoot, eHum) < 1.5 and roll then
								hurdle(enemy, eHum, eRoot)
							end
						end
						-- contact: legs still low and in reach
						if ahead <= reach and side <= width and feetClearance(enemy, eRoot, eHum) < cfg("ClearHeight", 2.5) then
							done[enemy] = true
							sweep(fighter, enemy, dir, speed)
						end
					end
				end
			end
		end,
	})
	if duration > 0 then
		stats.slides += 1
		publish()
	end
	return duration
end

return SlideTackle
