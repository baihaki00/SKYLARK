--// Drives.lua
-- Combat feelings (QUIN_CREATURE_DESIGN.md 5.5): animal intensity, not human drama. Each Quin
-- carries five, 0..1, that rise with what happens to it and fall back on their own:
--   confidence   landing hits, winning exchanges (taking hits lowers it)
--   fury         a heavy hit or a knockdown taken, an ally falling close by
--   caution      hurt (low health), and a run of hits taken
--   thrill       a close, even exchange: both landing on each other
--   exhaustion   the body's mana running low
-- They colour the mind, never replace it: Drives.aggression(quin) scales how pressing a fighter is
-- (FightState: the cooldown between strikes), Drives.guardBias(quin) how readily its reflexes
-- guard (Instinct). The strongest feeling is published as the Quin's Drive attribute (mind panel,
-- probes); later phases show them on the body (owner: later). A player's Quin has them too, but
-- they only shape AI choices.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local CombatConfig = require(ReplicatedStorage:WaitForChild("QuinCore"):WaitForChild("CombatConfig"))

local Drives = {}

local feelings = setmetatable({}, { __mode = "k" }) -- quin -> { confidence, fury, caution, thrill, exhaustion, lastLanded, lastTaken, at }

local function cfg(key, default)
	local v = CombatConfig["Drives_" .. key]
	if v == nil then return default end
	return v
end

function Drives.enabled()
	-- (Studio: Workspace attribute Ablate_Drives switches it off live, for A/B by eye or probe)
	if workspace:GetAttribute("Ablate_Drives") and game:GetService("RunService"):IsStudio() then return false end
	return CombatConfig.Drives_Enabled ~= false
end

local function of(quin)
	local f = feelings[quin]
	if not f then
		f = { confidence = 0.5, fury = 0, caution = 0, thrill = 0, exhaustion = 0, lastLanded = 0, lastTaken = 0, at = os.clock() }
		feelings[quin] = f
	end
	return f
end

local function clamp01(x) return math.clamp(x, 0, 1) end

-- Damage dealt and taken (DamageModule.apply). status: "Hit" | "Blocked" | "Dodged" | ...
function Drives.onExchange(attacker, target, damage, status, heavy)
	if not Drives.enabled() or not attacker or not target then return end
	local a, t = of(attacker), of(target)
	local now = os.clock()
	if status == "Hit" then
		a.confidence = clamp01(a.confidence + cfg("ConfidencePerHit", 0.08))
		t.confidence = clamp01(t.confidence - cfg("ConfidenceLossPerHit", 0.1))
		t.caution = clamp01(t.caution + cfg("CautionPerHit", 0.06))
		if heavy then
			t.fury = clamp01(t.fury + cfg("FuryPerHeavy", 0.3))
		end
		-- both landing on each other within a few seconds: a close fight, the thrill of it
		if now - t.lastLanded < cfg("ThrillWindow", 3) then
			a.thrill = clamp01(a.thrill + cfg("ThrillPerTrade", 0.05))
			t.thrill = clamp01(t.thrill + cfg("ThrillPerTrade", 0.05))
		end
		a.lastLanded = now
		t.lastTaken = now
	elseif status == "Blocked" or status == "Dodged" then
		t.confidence = clamp01(t.confidence + cfg("ConfidencePerStop", 0.05))
	end
end

-- Knocked down (KnockbackState) or an ally falls close by (DeathState)
function Drives.onKnockdown(quin)
	if not Drives.enabled() then return end
	local f = of(quin)
	f.fury = clamp01(f.fury + cfg("FuryPerKnockdown", 0.25))
end

function Drives.onAllyDown(fallen)
	if not Drives.enabled() then return end
	local folder = Workspace:FindFirstChild("QuinServer")
	local root = fallen:FindFirstChild("HumanoidRootPart")
	if not folder or not root then return end
	local team = fallen:GetAttribute("Team")
	for _, ally in ipairs(folder:GetChildren()) do
		local allyRoot = ally:FindFirstChild("HumanoidRootPart")
		if ally ~= fallen and team and ally:GetAttribute("Team") == team and allyRoot
			and (allyRoot.Position - root.Position).Magnitude <= cfg("AllyDownRange", 60) then
			local f = of(ally)
			f.fury = clamp01(f.fury + cfg("FuryPerAllyDown", 0.4))
		end
	end
end

-- Once per tick (Main): feelings drift back, the body's state feeds caution and exhaustion, and the
-- strongest is published
function Drives.update(quin, humanoid)
	if not Drives.enabled() then return end
	local f = of(quin)
	local now = os.clock()
	local dt = math.min(now - f.at, 0.5)
	f.at = now
	local relax = cfg("Relax", 0.06) * dt -- per second back toward rest
	f.confidence += (0.5 - f.confidence) * math.min(relax * 2, 1)
	f.fury = math.max(0, f.fury - cfg("FuryDecay", 0.07) * dt)
	f.thrill = math.max(0, f.thrill - cfg("ThrillDecay", 0.15) * dt)
	local healthShare = humanoid.MaxHealth > 0 and humanoid.Health / humanoid.MaxHealth or 1
	local hurt = (1 - healthShare) ^ 1.5
	local recentlyHit = now - f.lastTaken < 2 and 0.15 or 0
	f.caution = clamp01(math.max(f.caution - cfg("CautionDecay", 0.05) * dt, hurt + recentlyHit))
	f.exhaustion = clamp01(1 - (quin:GetAttribute("Energy") or 100) / (CombatConfig.MaxEnergy or 100))
	-- the strongest feeling that stands out
	local best, bestValue = nil, cfg("PublishThreshold", 0.45)
	for _, name in ipairs({ "fury", "caution", "thrill", "exhaustion" }) do
		if f[name] > bestValue then best, bestValue = name, f[name] end
	end
	if not best and f.confidence > 0.75 then best = "confidence" end
	if quin:GetAttribute("Drive") ~= best then
		quin:SetAttribute("Drive", best)
	end
end

-- How pressing this Quin is right now: a multiplier around 1 (FightState divides its cooldown by it)
function Drives.aggression(quin)
	if not Drives.enabled() then return 1 end
	local f = feelings[quin]
	if not f then return 1 end
	local m = 1 + cfg("ConfidencePress", 0.5) * (f.confidence - 0.5) + cfg("FuryPress", 0.6) * f.fury
		+ cfg("ThrillPress", 0.3) * f.thrill - cfg("CautionHold", 0.35) * f.caution - cfg("ExhaustionHold", 0.3) * f.exhaustion
	return math.clamp(m, cfg("MinAggression", 0.6), cfg("MaxAggression", 1.6))
end

-- How readily its reflexes guard rather than trade: a multiplier around 1 (Instinct)
function Drives.guardBias(quin)
	if not Drives.enabled() then return 1 end
	local f = feelings[quin]
	if not f then return 1 end
	return math.clamp(1 + cfg("CautionGuard", 0.8) * f.caution - cfg("FuryGuard", 0.5) * f.fury, 0.4, 1.8)
end

function Drives.get(quin)
	return feelings[quin]
end

return Drives
