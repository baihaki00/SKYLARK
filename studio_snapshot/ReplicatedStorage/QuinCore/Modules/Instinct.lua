--// Instinct.lua
-- Reflexes (QUIN_CREATURE_DESIGN.md 5.3: instinct first, thought on top). A strike shows itself at
-- its tell (the owner's Windup marker: StrikeTellAt on the attacker); a Quin it is aimed at sees
-- it, and after its own reaction time its body answers before its mind has a tick to think:
--   guard   raise the guard (DamageModule decides if it holds; a held guard opens a counter)
--   slip    step off the line, back and to a side; the counter window opens (CounterUntil)
--   hop     a low kick is jumped
--   nothing it takes it, or trades
-- How likely each is and how quick the reaction is come from the Quin: awareness (speed), defense
-- preference (guard), mobility (slip, hop) and how tired it is. Only AI Quins: a player's Quin
-- only does what its player presses (design doc 10.3). Runs every frame from a loop the Server
-- starts (Instinct.start), not at the states' 10 Hz.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local QuinCore = ReplicatedStorage:WaitForChild("QuinCore")
local CombatConfig = require(QuinCore:WaitForChild("CombatConfig"))

local Instinct = {}

local REACT_STATES = { Fight = true, Circling = true, Chase = true, Idle = true, Retreat = true }

local function cfg(key, default)
	local v = CombatConfig["Instinct_" .. key]
	if v == nil then return default end
	return v
end

function Instinct.enabled()
	-- (Studio: Workspace attribute Ablate_Instinct switches it off live, for A/B by eye or probe)
	if workspace:GetAttribute("Ablate_Instinct") and game:GetService("RunService"):IsStudio() then return false end
	return CombatConfig.Instinct_Enabled ~= false
end

local reacted = setmetatable({}, { __mode = "k" }) -- defender -> { [attacker] = windupUntil already answered }
local stats = { seen = 0, guard = 0, slip = 0, hop = 0, none = 0 }

-- How long this Quin takes to answer a tell
local function reactionTime(quin)
	local awareness = quin:GetAttribute("Pers_Awareness") or 0.6
	local t = cfg("ReactionBase", 0.16) * (1.3 - awareness * 0.6)
	if (quin:GetAttribute("Energy") or 100) < (CombatConfig.FatigueThreshold or 25) then
		t += cfg("TiredExtra", 0.08)
	end
	return t
end

local function answer(defender, humanoid, rootPart, attacker, attackerRoot, contactAt, now)
	local AnimationModule = require(QuinCore.Modules.AnimationModule)
	local KnockbackModule = require(QuinCore.Modules.KnockbackModule)
	local LocomotionModule = require(QuinCore.Modules.LocomotionModule)
	local timeLeft = contactAt - now
	local defense = defender:GetAttribute("Pers_DefensePreference") or 0.5
	local mobility = defender:GetAttribute("Pers_MobilityPreference") or 0.5
	local low = attacker:GetAttribute("StrikeLow") == true
	local roll = math.random()
	local hop = low and timeLeft >= cfg("HopMinTime", 0.15) and cfg("HopChance", 0.5) * (0.5 + mobility) or 0
	local slip = timeLeft >= cfg("SlipMinTime", 0.12) and cfg("SlipChance", 0.15) * (0.5 + mobility) or 0
	-- (a cautious Quin guards more readily, a furious one would rather trade: Modules/Drives)
	local guard = cfg("GuardChance", 0.3) * (0.5 + defense) * require(QuinCore.Modules.Drives).guardBias(defender)
	stats.seen += 1
	if roll < hop then
		stats.hop += 1
		LocomotionModule.jump(defender, humanoid, rootPart, cfg("HopHeight", 6), 0, "hop")
		defender:SetAttribute("InstinctAt", os.clock())
		defender:SetAttribute("Instinct", "hop")
		return
	end
	roll -= hop
	if roll < slip then
		stats.slip += 1
		local away = rootPart.Position - attackerRoot.Position
		away = Vector3.new(away.X, 0, away.Z)
		away = away.Magnitude > 0.01 and away.Unit or -rootPart.CFrame.LookVector
		local side = Vector3.new(-away.Z, 0, away.X) * (math.random() < 0.5 and -1 or 1)
		KnockbackModule.applySlide(defender, (side * 0.85 + away * 0.5).Unit, cfg("SlipSpeed", 35), 0.25)
		local soundPart = defender:FindFirstChild("Sounds")
		local swish = soundPart and soundPart:FindFirstChild("swish")
		if swish then swish.Volume = 0.3 swish:Play() end
		defender:SetAttribute("CounterUntil", tick() + (CombatConfig.Flow_CounterWindow or 0.7))
		defender:SetAttribute("InstinctAt", os.clock())
		defender:SetAttribute("Instinct", "slip")
		return
	end
	roll -= slip
	if roll < guard then
		stats.guard += 1
		defender:SetAttribute("IsGuarding", true)
		AnimationModule.playConfig(humanoid, "Reactions.Block", 1.0, Enum.AnimationPriority.Action4, false)
		task.delay(timeLeft + cfg("GuardHold", 0.2), function()
			if defender.Parent and defender:GetAttribute("IsGuarding") == true then
				defender:SetAttribute("IsGuarding", false)
			end
		end)
		defender:SetAttribute("InstinctAt", os.clock())
		defender:SetAttribute("Instinct", "guard")
		return
	end
	stats.none += 1
end

local function step()
	local folder = Workspace:FindFirstChild("QuinServer")
	if not folder or not Instinct.enabled() then return end
	local now = tick()
	local quins = folder:GetChildren()
	for _, attacker in ipairs(quins) do
		if attacker:GetAttribute("Attacking") == true then
			local tellAt = attacker:GetAttribute("StrikeTellAt")
			local contactAt = attacker:GetAttribute("AttackWindupUntil")
			local targetName = attacker:GetAttribute("CurrentTarget")
			local defender = targetName and folder:FindFirstChild(targetName)
			local attackerRoot = attacker:FindFirstChild("HumanoidRootPart")
			if tellAt and contactAt and defender and attackerRoot and now < contactAt
				and not defender:GetAttribute("PilotedBy") and REACT_STATES[defender:GetAttribute("CurrentState") or ""]
				and defender:GetAttribute("IsInert") ~= true and defender:GetAttribute("Attacking") ~= true then
				local memo = reacted[defender]
				if not memo then
					memo = setmetatable({}, { __mode = "k" })
					reacted[defender] = memo
				end
				if memo[attacker] ~= contactAt and now >= tellAt + reactionTime(defender) then
					memo[attacker] = contactAt -- (one answer per strike)
					local humanoid = defender:FindFirstChildOfClass("Humanoid")
					local rootPart = defender:FindFirstChild("HumanoidRootPart")
					if humanoid and rootPart and humanoid.Health > 0
						and (attackerRoot.Position - rootPart.Position).Magnitude <= cfg("Range", 14) then
						answer(defender, humanoid, rootPart, attacker, attackerRoot, contactAt, now)
					end
				end
			end
		end
	end
end

local started = false
function Instinct.start()
	if started then return end
	started = true
	RunService.Heartbeat:Connect(function()
		local ok, err = pcall(step)
		if not ok then warn("[Instinct] " .. tostring(err)) end
	end)
	if RunService:IsStudio() then
		task.spawn(function()
			while true do
				task.wait(5)
				Workspace:SetAttribute("InstinctStats", string.format("seen %d guard %d slip %d hop %d none %d", stats.seen, stats.guard, stats.slip, stats.hop, stats.none))
			end
		end)
	end
end

return Instinct
