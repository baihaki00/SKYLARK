--// JumpRead.lua
-- Reading a projectile jump from the ground (owner 2026-10-29: "can the one on the ground track
-- it, read whether it's about to dive at it, ignore it, or intercept it, by its own choice?").
-- A Quin that sees an enemy in a projectile jump works out where it comes down:
--   diving   along the dive line to the floor (the line it is flying now), and how soon
--   rising   near the jumper's own target (the dive lands 5-25 studs off it: Flight's scatter)
-- If that lands it inside the slam (SlamShockwaveRadius), it picks once per jump, by temperament
-- (leanings, never rules):
--   clear      get out of the landing spot, and carry on
--   punish     wait just outside the slam, and go at the jumper the moment it hits the ground
--              (it is free to act ~0.35 s after landing: from further than ~24 studs, or once it is
--              already up, nobody got there in time; at most two go at one jumper)
--   intercept  go up and meet it in the air (the intercept jump, AirInterceptModule)
--   ignore     stay on what it is doing (only when the jump is not aimed at it)
-- A jump aimed at it is not run from (the dive re-aims at it every frame until the last 10
-- studs: running changed nothing, 17% slammed either way). Clearing or punishing, it watches the
-- dive frame by frame and sidesteps across the dive line JumpRead_SidestepLead seconds before
-- touchdown, with a focus dash (Modules/Evasion), when one is ready. Switch: Workspace
-- JumpSidestepOff = true or CombatConfig.JumpRead_Sidestep = false (it runs, as before).
-- Main runs it each tick for a standing Quin on the ground (JumpRead.update): it returns a point
-- to run to while clearing, and the state holds while it does.
-- Switch: CombatConfig.JumpRead_Enabled = false, or Workspace JumpReadOff = true (off: the old
-- random block / dodge / meet in FightState.Decide).
-- Readout: attribute JumpRead ("<jumper> at me: clear, lands in 0.4 s, 9 studs off").

local GameClock = require(game:GetService("ReplicatedStorage"):WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("GameClock")) -- (the game's clock: a freeze stops it)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local QuinCore = ReplicatedStorage:WaitForChild("QuinCore")
local Modules = QuinCore:WaitForChild("Modules")
local CombatConfig = require(QuinCore:WaitForChild("CombatConfig"))
local Cognition = require(QuinCore:WaitForChild("Cognition"))
local Pers = require(Modules:WaitForChild("Pers"))

local JumpRead = {}

local DIVE_PHASES = { Dash = true, Strafe = true, ComboStrafe = true, Impact = true }

local reads = setmetatable({}, { __mode = "k" }) -- fighter -> the jump it is reading
local punishers = setmetatable({}, { __mode = "k" }) -- jumper -> { [fighter] = true } waiting to punish it
local stats = { reads = 0, clear = 0, punish = 0, intercept = 0, ignore = 0, punishGo = 0, sidestep = 0, sidestepFailed = 0 }
local watching = setmetatable({}, { __mode = "k" }) -- fighter -> the jumper whose dive it is timing
local sidestepping = setmetatable({}, { __mode = "k" }) -- fighter -> true while its sidestep dash runs
JumpRead.stats = stats

local function cfg(key, default)
	local v = CombatConfig[key]
	if v == nil then return default end
	return v
end

function JumpRead.enabled()
	return cfg("JumpRead_Enabled", true) ~= false and Workspace:GetAttribute("JumpReadOff") ~= true
end

local function flat(v) return Vector3.new(v.X, 0, v.Z) end

local floorParams
local function floorBelowAlong(from, dir, length)
	if not floorParams then
		floorParams = RaycastParams.new()
		floorParams.FilterType = Enum.RaycastFilterType.Exclude
		floorParams.RespectCanCollide = true
	end
	floorParams.FilterDescendantsInstances = { Workspace:FindFirstChild("QuinServer") }
	return Workspace:Raycast(from, dir * length, floorParams)
end

-- Where and when the jumper comes down, as this Quin can tell from what it sees.
-- Returns landing (Vector3), eta (seconds, or nil while it is still going up), spread (studs)
function JumpRead.predict(jumper)
	local root = jumper:FindFirstChild("HumanoidRootPart")
	if not root then return nil end
	local v = root.AssemblyLinearVelocity
	local phase = jumper:GetAttribute("PJPhase")
	if DIVE_PHASES[phase] and v.Y < -5 and v.Magnitude > 20 then
		local hit = floorBelowAlong(root.Position, v.Unit, 1500)
		if hit then
			return hit.Position, (hit.Position - root.Position).Magnitude / v.Magnitude, 6
		end
	end
	-- still up: it comes down near its own target
	local target = Workspace:FindFirstChild("QuinServer") and Workspace.QuinServer:FindFirstChild(jumper:GetAttribute("CurrentTarget") or "")
	local tRoot = target and target:FindFirstChild("HumanoidRootPart")
	if not tRoot then return nil end
	local spread = math.clamp((tRoot.Position - root.Position).Magnitude * 0.12, 5, 25)
	return tRoot.Position, nil, spread
end

local function canJump(fighter)
	return CombatConfig.EnableProjectileJump ~= false and fighter:GetAttribute("EnableProjectileJump") ~= false
		and (fighter:GetAttribute("Energy") or 100) >= (CombatConfig.ProjectileJumpMinEnergy or 40)
		and (GameClock.tick() - (fighter:GetAttribute("LastProjectileJumpTime") or 0)) >= (CombatConfig.ProjectileJump_Cooldown or 14.0)
end

-- The choice, once per jump
local function choose(fighter, rootPart, jumper, aimed, rising)
	local aggression = Pers.get(fighter, "Aggression")
	local defense = Pers.get(fighter, "DefensePreference")
	local jRoot = jumper:FindFirstChild("HumanoidRootPart")
	local weights = {
		clear = 0.5 + defense,
		punish = 0.2 + aggression, -- (whether it is close enough is checked as the jump comes down)
		intercept = 0,
		ignore = aimed and 0 or cfg("JumpRead_IgnoreWeight", 0.35) * aggression,
	}
	if rising and canJump(fighter) and jRoot and jRoot.Position.Y - rootPart.Position.Y >= (CombatConfig.Intercept_MinHeight or 40)
		and GameClock.now() - (jumper:GetAttribute("InterceptedAt") or 0) >= (CombatConfig.Intercept_ClaimTime or 3.0) then
		weights.intercept = cfg("JumpRead_InterceptWeight", 0.6) * aggression
	end
	local total = 0
	for _, w in pairs(weights) do total += w end
	local roll = math.random() * total
	for _, name in ipairs({ "clear", "punish", "intercept", "ignore" }) do
		roll -= weights[name]
		if roll <= 0 then return name end
	end
	return "clear"
end

-- The enemy jump that matters most to this Quin now (aimed at it first, then the nearest landing)
local function findThreat(fighter, rootPart)
	local best, bestScore
	for _, contact in ipairs(Cognition.knownEnemies(fighter) or {}) do
		local m = contact.model
		if contact.visible and m and m.Parent and m:GetAttribute("CurrentState") == "ProjectileJump" then
			local landing, eta, spread = JumpRead.predict(m)
			if landing then
				local aimed = m:GetAttribute("CurrentTarget") == fighter.Name
				local off = flat(landing - rootPart.Position).Magnitude
				local radius = (CombatConfig.SlamShockwaveRadius or CombatConfig.SlamImpactRadius or 14) + spread
				if aimed or off <= radius then
					local score = (aimed and 0 or 100) + off
					if not bestScore or score < bestScore then
						best, bestScore = { jumper = m, landing = landing, eta = eta, spread = spread, aimed = aimed, off = off, radius = radius }, score
					end
				end
			end
		end
	end
	return best
end

local function sidestepOn()
	return cfg("JumpRead_Sidestep", true) ~= false and Workspace:GetAttribute("JumpSidestepOff") ~= true
end

-- Time the dive frame by frame (Main ticks ten times a second; the dive is down in ~0.6 s) and
-- dash across its line just before it lands
local function watchDive(fighter, humanoid, rootPart, jumper)
	if watching[fighter] then return end
	watching[fighter] = jumper
	local Evasion = require(Modules:WaitForChild("Evasion"))
	local started = GameClock.now()
	local conn
	conn = RunService.Heartbeat:Connect(function()
		if GameClock.frozen() then return end
		local done = not fighter.Parent or not jumper.Parent or humanoid.Health <= 0 or not sidestepOn()
			or jumper:GetAttribute("CurrentState") ~= "ProjectileJump" or GameClock.now() - started > 3
		local jRoot = not done and jumper:FindFirstChild("HumanoidRootPart")
		if jRoot then
			local landing, eta = JumpRead.predict(jumper)
			if landing and eta and eta <= cfg("JumpRead_SidestepLead", 0.2) then
				-- across the dive line, to the side away from where it comes down
				local dive = flat(jRoot.AssemblyLinearVelocity)
				local away = flat(rootPart.Position - landing)
				local side
				if dive.Magnitude > 1 then
					local perp = Vector3.new(-dive.Z, 0, dive.X).Unit
					side = away:Dot(perp) >= 0 and perp or -perp
				else
					side = away.Magnitude > 0.5 and away.Unit or Vector3.new(1, 0, 0)
				end
				local kind = Evasion.focusDash(fighter, humanoid, rootPart, jRoot, side, { anyState = true, curve = 0 })
				if kind then
					sidestepping[fighter] = true
					stats.sidestep += 1
					fighter:SetAttribute("JumpSidestep", kind)
					fighter:SetAttribute("JumpSidestepAt", GameClock.now())
				else
					stats.sidestepFailed += 1
				end
				done = true
			end
		end
		if done then
			conn:Disconnect()
			if watching[fighter] == jumper then watching[fighter] = nil end
		end
	end)
end

-- Each tick, for a standing Quin on the ground. Returns a point to run to (clearing the landing),
-- or nil. May ask for a state (intercept; punish once the jumper is down).
function JumpRead.update(fighter, rootPart, humanoid)
	local now = GameClock.now()
	-- its sidestep has the body: the state holds (second result)
	if sidestepping[fighter] then
		if require(Modules:WaitForChild("Evasion")).busy(fighter) then return nil, true end
		sidestepping[fighter] = nil
	end
	local read = reads[fighter]
	-- punish: the jumper hits the ground, go at it
	local jState = read and read.jumper.Parent and read.jumper:GetAttribute("CurrentState")
	if read and read.choice == "punish" and jState and (jState ~= "ProjectileJump" or read.jumper:GetAttribute("PJPhase") == "Impact") then
		reads[fighter] = nil
		local list = punishers[read.jumper]
		if list then list[fighter] = nil end
		local jRoot = read.jumper:FindFirstChild("HumanoidRootPart")
		if jRoot and jState ~= "MidAirClash" and jState ~= "Knockback" and GameClock.now() - read.since < 8
			and flat(jRoot.Position - rootPart.Position).Magnitude <= cfg("JumpRead_PunishRange", 24) then
			local TargetingModule = require(Modules:WaitForChild("TargetingModule"))
			local StateRequest = require(Modules:WaitForChild("StateRequest"))
			TargetingModule.setTarget(fighter, read.jumper, "PunishLanding")
			-- (held through the window: the brain's next pick turned 4 of 7 punishers to someone
			-- else within 0.1 s. TargetOverride wins over the utility choice; it is taken off
			-- again only if it is still this jumper)
			local jumperName = read.jumper.Name
			if (fighter:GetAttribute("TargetOverride") or "") == "" then
				fighter:SetAttribute("TargetOverride", jumperName)
				GameClock.delay(cfg("JumpRead_PunishCommit", 1.5), function()
					if fighter.Parent and fighter:GetAttribute("TargetOverride") == jumperName then
						fighter:SetAttribute("TargetOverride", nil)
					end
				end)
			end
			local inReach = flat(jRoot.Position - rootPart.Position).Magnitude <= (CombatConfig.CombatRange or 8.2) * 1.5
			StateRequest.ask(fighter, inReach and "Fight" or "Chase", StateRequest.FOLLOW, "punish the landing")
			fighter:SetAttribute("JumpRead", read.jumper.Name .. " landed: going at it")
			stats.punishGo += 1
			GameClock.delay(1.5, function()
				if fighter.Parent and reads[fighter] == nil then fighter:SetAttribute("JumpRead", nil) end
			end)
		else
			fighter:SetAttribute("JumpRead", nil)
		end
		return nil
	end
	if read and (not read.jumper.Parent or read.jumper:GetAttribute("CurrentState") ~= "ProjectileJump") then
		reads[fighter] = nil
		read = nil
		fighter:SetAttribute("JumpRead", nil)
	end

	local threat = findThreat(fighter, rootPart)
	if not threat then
		if read and read.choice ~= "punish" then reads[fighter] = nil end
		if not reads[fighter] and fighter:GetAttribute("JumpRead") and not fighter:GetAttribute("JumpRead"):find("going at it", 1, true) then
			fighter:SetAttribute("JumpRead", nil)
		end
		return nil
	end
	if not read or read.jumper ~= threat.jumper then
		read = { jumper = threat.jumper, since = now }
		read.choice = choose(fighter, rootPart, threat.jumper, threat.aimed, threat.eta == nil)
		if read.choice == "punish" then
			-- (two at most wait for one jumper: the rest clear and carry on)
			local list = punishers[threat.jumper] or {}
			punishers[threat.jumper] = list
			local count = 0
			for f in pairs(list) do if f.Parent and reads[f] and reads[f].jumper == threat.jumper then count += 1 else list[f] = nil end end
			if count >= cfg("JumpRead_PunishMax", 2) then
				read.choice = "clear"
			else
				list[fighter] = true
			end
		end
		reads[fighter] = read
		stats.reads += 1
		stats[read.choice] += 1
		fighter:SetAttribute("JumpReadChoice", read.choice)
		fighter:SetAttribute("JumpReadAt", now)
	end
	fighter:SetAttribute("JumpRead", string.format("%s%s: %s, lands %s, %d studs off", threat.jumper.Name,
		threat.aimed and " at me" or "", read.choice, threat.eta and string.format("in %.1f s", threat.eta) or "later", math.floor(threat.off)))

	if read.choice == "ignore" then return nil end
	if read.choice == "intercept" then
		if threat.eta == nil and canJump(fighter) then
			local AirInterceptModule = require(Modules:WaitForChild("AirInterceptModule"))
			local StateRequest = require(Modules:WaitForChild("StateRequest"))
			AirInterceptModule.commit(fighter, threat.jumper)
			fighter:SetAttribute("JumpWhy", "read a jump: going up to meet it")
			StateRequest.ask(fighter, "ProjectileJump", StateRequest.FOLLOW, "meet the jump")
			reads[fighter] = nil
			return nil
		end
		read.choice = "clear" -- too late to go up: get out instead
	end
	-- clear / punish: out of the landing, to just past the slam's edge
	-- (a jump aimed at it is cleared once the dive has committed: the dive steers onto it until then)
	if threat.aimed and threat.eta == nil then return nil end
	-- the dive has committed to it: sidestep at the last moment instead of running
	if threat.aimed and sidestepOn() and (watching[fighter] == threat.jumper
		or require(Modules:WaitForChild("Evasion")).dashReady(fighter)) then
		watchDive(fighter, humanoid, rootPart, threat.jumper)
		return nil
	end
	-- (a punisher waits right at the slam's edge, close enough to be on it as it lands)
	local slam = CombatConfig.SlamShockwaveRadius or CombatConfig.SlamImpactRadius or 14
	local radius = (read.choice == "punish" and slam + math.min(threat.spread, 6) or threat.radius) + cfg("JumpRead_ClearMargin", 4)
	if threat.off >= radius then return nil end
	local away = flat(rootPart.Position - threat.landing)
	if away.Magnitude < 0.5 then
		local j = flat(threat.jumper.HumanoidRootPart.Position - rootPart.Position)
		away = j.Magnitude > 0.5 and Vector3.new(-j.Z, 0, j.X) or Vector3.new(1, 0, 0)
	end
	fighter:SetAttribute("ObstacleAwareness", "Clearing out: a jump lands here")
	return threat.landing + away.Unit * radius + Vector3.new(0, rootPart.Position.Y - threat.landing.Y, 0)
end

return JumpRead
