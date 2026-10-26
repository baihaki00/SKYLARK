--// BattleSimulationHarness.lua
-- Server-side deterministic battle scenario harness
-- Enables reproducible AI evaluation and isolated debugging of emergent behaviors.
-- Supports all 11 canonical evaluation scenarios + aliases.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local QuinCore = ReplicatedStorage:WaitForChild("QuinCore")
local QuinInstance = require(QuinCore:WaitForChild("Modules"):WaitForChild("QuinInstance"))
local ElementData = require(QuinCore:WaitForChild("ElementData"))

local BattleSimulationHarness = {}

-- Lazy require Spawner to prevent circular dependencies
local function getSpawner()
	if _G.QuinSpawner then return _G.QuinSpawner end
	local sss = game:GetService("ServerScriptService")
	local spawner = sss:FindFirstChild("QuinSpawner")
	if spawner and spawner:IsA("ModuleScript") then
		return require(spawner)
	end
	return _G.QuinSpawner
end

-- Helper to set health percentage
local function setHealthPercent(model, percent)
	if not model then return end
	local hum = model:FindFirstChildOfClass("Humanoid")
	if hum then
		local targetHp = math.clamp(hum.MaxHealth * (percent / 100), 1, hum.MaxHealth)
		hum.Health = targetHp
	end
end

-- Helper to set energy
local function setEnergy(model, energy)
	if not model then return end
	model:SetAttribute("Energy", math.clamp(energy, 0, 100))
end

-- Clear arena of all active Quins
function BattleSimulationHarness.clearArena()
	local quinServer = Workspace:FindFirstChild("QuinServer")
	if quinServer then
		for _, ch in ipairs(quinServer:GetChildren()) do
			ch:Destroy()
		end
	end
	for _, ch in ipairs(Workspace:GetChildren()) do
		if ch:IsA("Model") and (ch:GetAttribute("CurrentState") or ch:GetAttribute("QuinId")) then
			ch:Destroy()
		end
	end
	Workspace:SetAttribute("CurrentMode", "None")
	Workspace:SetAttribute("SpectatedQuin", "")
	print("[BattleSimulationHarness] Arena cleared.")
end

-- Canonical Scenario Definitions
local scenarioHandlers = {}

-- 1. Scenario_01_OneVsOne
scenarioHandlers["OneVsOne"] = function(Spawner, options)
	local elem1 = options.Element1 or "Fire"
	local elem2 = options.Element2 or "Water"
	print(string.format("[BattleSimulationHarness] Scenario 01: OneVsOne (%s vs %s)", elem1, elem2))

	local q1Inst = QuinInstance.create({
		Type = options.Type1 or "TypeA",
		Element = elem1,
		PersonalityOverrides = { Aggression = 0.70, Persistence = 0.70 }
	})
	local q2Inst = QuinInstance.create({
		Type = options.Type2 or "TypeB",
		Element = elem2,
		PersonalityOverrides = { Aggression = 0.70, Persistence = 0.70 }
	})

	local m1 = Spawner.spawnWithInstance(q1Inst, Vector3.new(-15, 7.5, 0), "TeamAlpha")
	local m2 = Spawner.spawnWithInstance(q2Inst, Vector3.new(15, 7.5, 0), "TeamBeta")
	return { m1, m2 }
end

-- 2. Scenario_02_TwoVsOne
scenarioHandlers["TwoVsOne"] = function(Spawner, options)
	print("[BattleSimulationHarness] Scenario 02: TwoVsOne (2 Attackers vs 1 Defender)")
	local spawned = {}

	-- 2 Attackers on TeamAlpha
	local atk1Inst = QuinInstance.create({
		Type = "TypeA",
		Element = "Fire",
		PersonalityOverrides = { Aggression = 0.85, Persistence = 0.75 }
	})
	local atk2Inst = QuinInstance.create({
		Type = "TypeC",
		Element = "Lightning",
		PersonalityOverrides = { Aggression = 0.80, DashPreference = 0.80 }
	})
	table.insert(spawned, Spawner.spawnWithInstance(atk1Inst, Vector3.new(-15, 7.5, -8), "TeamAlpha"))
	table.insert(spawned, Spawner.spawnWithInstance(atk2Inst, Vector3.new(-15, 7.5, 8), "TeamAlpha"))

	-- 1 Defender on TeamBeta
	local defInst = QuinInstance.create({
		Type = "TypeB",
		Element = "Stone",
		PersonalityOverrides = { Aggression = 0.50, RetreatTendency = 0.60 }
	})
	table.insert(spawned, Spawner.spawnWithInstance(defInst, Vector3.new(15, 7.5, 0), "TeamBeta"))
	return spawned
end

-- 3. Scenario_03_IsolatedTarget
scenarioHandlers["IsolatedTarget"] = function(Spawner, options)
	print("[BattleSimulationHarness] Scenario 03: IsolatedTarget (1 Target encircled by 3 Attackers)")
	local spawned = {}

	-- Target Quin on TeamBeta, isolated in center
	local targetInst = QuinInstance.create({
		Type = options.TargetType or "TypeA",
		Element = options.TargetElement or "Wind",
		PersonalityOverrides = {
			Aggression = 0.35,
			RetreatTendency = 0.80,
		},
	})
	local targetModel = Spawner.spawnWithInstance(targetInst, Vector3.new(0, 7.5, 0), "TeamBeta")
	table.insert(spawned, targetModel)

	-- 3 Attackers on TeamAlpha encircling the target
	local angles = { 0, 120, 240 }
	for i, deg in ipairs(angles) do
		local rad = math.rad(deg)
		local pos = Vector3.new(math.cos(rad) * 25, 7.5, math.sin(rad) * 25)
		local atkInst = QuinInstance.create({
			Type = "TypeC",
			Element = "Lightning",
			PersonalityOverrides = {
				Aggression = 0.85,
				DashPreference = 0.90,
			},
		})
		local atkModel = Spawner.spawnWithInstance(atkInst, pos, "TeamAlpha")
		table.insert(spawned, atkModel)
	end
	return spawned
end

-- 4. Scenario_04_Rescue
scenarioHandlers["Rescue"] = function(Spawner, options)
	print("[BattleSimulationHarness] Scenario 04: Rescue (Critically wounded ally + Protector vs Attacker)")
	local spawned = {}

	-- Distressed Ally on TeamAlpha (Center, low HP)
	local allyInst = QuinInstance.create({
		Type = "TypeA",
		Element = "Wind",
		PersonalityOverrides = { RetreatTendency = 0.90, Aggression = 0.20 }
	})
	local allyModel = Spawner.spawnWithInstance(allyInst, Vector3.new(0, 7.5, 0), "TeamAlpha")
	setHealthPercent(allyModel, 20)
	table.insert(spawned, allyModel)

	-- Enemy Attacker on TeamBeta pressing the distressed ally
	local enemyInst = QuinInstance.create({
		Type = "TypeC",
		Element = "Fire",
		PersonalityOverrides = { Aggression = 0.90, Persistence = 0.85 }
	})
	local enemyModel = Spawner.spawnWithInstance(enemyInst, Vector3.new(10, 7.5, 0), "TeamBeta")
	table.insert(spawned, enemyModel)

	-- Protector Ally on TeamAlpha nearby with high protectiveness
	local protectorInst = QuinInstance.create({
		Type = "TypeB",
		Element = "Stone",
		PersonalityOverrides = {
			Protectiveness = 0.95,
			LoyaltyBias = 0.90,
			Aggression = 0.75,
		}
	})
	local protectorModel = Spawner.spawnWithInstance(protectorInst, Vector3.new(-25, 7.5, 0), "TeamAlpha")
	table.insert(spawned, protectorModel)

	return spawned
end

-- 5. Scenario_05_LocalNumericalAdvantage
scenarioHandlers["LocalNumericalAdvantage"] = function(Spawner, options)
	print("[BattleSimulationHarness] Scenario 05: LocalNumericalAdvantage (3 vs 1 Emergent Convergence)")
	local spawned = {}

	-- 3 Allied Fighters on TeamAlpha
	local offsets = { Vector3.new(-20, 7.5, -10), Vector3.new(-20, 7.5, 0), Vector3.new(-20, 7.5, 10) }
	for i, pos in ipairs(offsets) do
		local inst = QuinInstance.create({
			Type = "TypeA",
			Element = (i == 1 and "Fire") or (i == 2 and "Lightning") or "Wind",
			PersonalityOverrides = { Aggression = 0.80, Persistence = 0.70 }
		})
		table.insert(spawned, Spawner.spawnWithInstance(inst, pos, "TeamAlpha"))
	end

	-- 1 Lone Opponent on TeamBeta
	local oppInst = QuinInstance.create({
		Type = "TypeB",
		Element = "Stone",
		PersonalityOverrides = { Aggression = 0.50, RetreatTendency = 0.50 }
	})
	table.insert(spawned, Spawner.spawnWithInstance(oppInst, Vector3.new(15, 7.5, 0), "TeamBeta"))
	return spawned
end

-- 6. Scenario_06_OutnumberedRetreat
scenarioHandlers["OutnumberedRetreat"] = function(Spawner, options)
	print("[BattleSimulationHarness] Scenario 06: OutnumberedRetreat (1 Cautious Quin vs 3 Aggressors)")
	local spawned = {}

	-- 1 Cautious Quin on TeamBeta
	local cautiousInst = QuinInstance.create({
		Type = "TypeA",
		Element = "Water",
		PersonalityOverrides = {
			RetreatTendency = 0.95,
			Aggression = 0.15,
			Confidence = 0.30,
		}
	})
	local cautiousModel = Spawner.spawnWithInstance(cautiousInst, Vector3.new(0, 7.5, 0), "TeamBeta")
	table.insert(spawned, cautiousModel)

	-- 3 Aggressive Opponents on TeamAlpha
	local offsets = { Vector3.new(-18, 7.5, -10), Vector3.new(-18, 7.5, 0), Vector3.new(-18, 7.5, 10) }
	for i, pos in ipairs(offsets) do
		local atkInst = QuinInstance.create({
			Type = "TypeC",
			Element = "Fire",
			PersonalityOverrides = { Aggression = 0.85, Persistence = 0.80 }
		})
		table.insert(spawned, Spawner.spawnWithInstance(atkInst, pos, "TeamAlpha"))
	end
	return spawned
end

-- 7. Scenario_07_Pursuit
scenarioHandlers["Pursuit"] = function(Spawner, options)
	print("[BattleSimulationHarness] Scenario 07: Pursuit (Chaser vs Retreating Opponent)")
	local spawned = {}

	-- 1 Chaser on TeamAlpha
	local chaserInst = QuinInstance.create({
		Type = "TypeC",
		Element = "Lightning",
		PersonalityOverrides = {
			Aggression = 0.95,
			Persistence = 0.95,
			DashPreference = 0.85,
		}
	})
	local chaserModel = Spawner.spawnWithInstance(chaserInst, Vector3.new(-10, 7.5, 0), "TeamAlpha")
	table.insert(spawned, chaserModel)

	-- 1 Retreating Opponent on TeamBeta
	local fleeingInst = QuinInstance.create({
		Type = "TypeA",
		Element = "Wind",
		PersonalityOverrides = {
			RetreatTendency = 0.95,
			Aggression = 0.10,
		}
	})
	local fleeingModel = Spawner.spawnWithInstance(fleeingInst, Vector3.new(20, 7.5, 0), "TeamBeta")
	table.insert(spawned, fleeingModel)
	return spawned
end

-- 8. Scenario_08_TargetSwitch
scenarioHandlers["TargetSwitch"] = function(Spawner, options)
	print("[BattleSimulationHarness] Scenario 08: TargetSwitch (Evaluates high HP defended vs low HP isolated target)")
	local spawned = {}

	-- 1 Attacker on TeamAlpha
	local atkInst = QuinInstance.create({
		Type = "TypeA",
		Element = "Fire",
		PersonalityOverrides = { Aggression = 0.80, Persistence = 0.50 }
	})
	local atkModel = Spawner.spawnWithInstance(atkInst, Vector3.new(0, 7.5, 0), "TeamAlpha")
	table.insert(spawned, atkModel)

	-- 1 Healthy Defended Target on TeamBeta (Full HP)
	local healthyInst = QuinInstance.create({
		Type = "TypeB",
		Element = "Stone",
		PersonalityOverrides = { Aggression = 0.60 }
	})
	local healthyModel = Spawner.spawnWithInstance(healthyInst, Vector3.new(-15, 7.5, 0), "TeamBeta")
	table.insert(spawned, healthyModel)

	-- 1 Low-HP Isolated Target on TeamBeta (15% HP)
	local lowHpInst = QuinInstance.create({
		Type = "TypeA",
		Element = "Wind",
		PersonalityOverrides = { RetreatTendency = 0.80 }
	})
	local lowHpModel = Spawner.spawnWithInstance(lowHpInst, Vector3.new(15, 7.5, 10), "TeamBeta")
	setHealthPercent(lowHpModel, 15)
	table.insert(spawned, lowHpModel)

	return spawned
end

-- 9. Scenario_09_ResourceExhaustion
scenarioHandlers["ResourceExhaustion"] = function(Spawner, options)
	print("[BattleSimulationHarness] Scenario 09: ResourceExhaustion (Critically Low Energy Combat)")
	local spawned = {}

	local q1Inst = QuinInstance.create({ Type = "TypeD", Element = "Fire" })
	local q2Inst = QuinInstance.create({ Type = "TypeD", Element = "Water" })

	local m1 = Spawner.spawnWithInstance(q1Inst, Vector3.new(-10, 7.5, 0), "TeamAlpha")
	local m2 = Spawner.spawnWithInstance(q2Inst, Vector3.new(10, 7.5, 0), "TeamBeta")

	setEnergy(m1, 10)
	setEnergy(m2, 10)
	table.insert(spawned, m1)
	table.insert(spawned, m2)
	return spawned
end

-- 10. Scenario_10_LastStand
scenarioHandlers["LastStand"] = function(Spawner, options)
	print("[BattleSimulationHarness] Scenario 10: LastStand (Critical 12% HP Defender vs 2 Attackers)")
	local spawned = {}

	-- Critical Defender on TeamBeta
	local defInst = QuinInstance.create({
		Type = "TypeB",
		Element = "Stone",
		PersonalityOverrides = {
			Aggression = 0.50,
			RetreatTendency = 0.85,
			Confidence = 0.25,
		}
	})
	local defModel = Spawner.spawnWithInstance(defInst, Vector3.new(0, 7.5, 0), "TeamBeta")
	setHealthPercent(defModel, 12)
	table.insert(spawned, defModel)

	-- 2 Attackers on TeamAlpha
	local atk1Inst = QuinInstance.create({ Type = "TypeA", Element = "Fire" })
	local atk2Inst = QuinInstance.create({ Type = "TypeC", Element = "Lightning" })
	local m1 = Spawner.spawnWithInstance(atk1Inst, Vector3.new(-15, 7.5, 0), "TeamAlpha")
	local m2 = Spawner.spawnWithInstance(atk2Inst, Vector3.new(15, 7.5, 0), "TeamAlpha")
	table.insert(spawned, m1)
	table.insert(spawned, m2)
	return spawned
end

-- 11. Scenario_11_BenchmarkQuin
scenarioHandlers["BenchmarkQuin"] = function(Spawner, options)
	local count = options.OpponentCount or 4
	print(string.format("[BattleSimulationHarness] Scenario 11: BenchmarkQuin (1 Admin Benchmark vs %d Opponents)", count))
	local spawned = {}

	-- Admin Benchmark Quin
	local benchInst = QuinInstance.create({
		QuinId = "ADMIN_BENCHMARK_01",
		OwnerId = "ADMIN",
		Type = "TypeB",
		Element = "Stone",
		QuinClass = "Admin",
		Archetype = "Benchmark",
		PersonalityOverrides = {
			Aggression = 0.50,
			RiskTolerance = 1.00,
			Protectiveness = 0.80,
			Confidence = 1.00,
			RetreatTendency = 0.00,
		},
	})
	benchInst.Titles = { "Admin Benchmark", "Indomitable" }

	local benchModel = Spawner.spawnWithInstance(benchInst, Vector3.new(0, 7.5, 0), "TeamAdmin")
	if benchModel and benchModel.Parent then
		benchModel:SetAttribute("BenchmarkActive", true)
		local hum = benchModel:FindFirstChildOfClass("Humanoid")
		if hum then
			local totalDmg = 0
			local hits = 0
			local startTime = os.clock()
			local lastHp = hum.Health
			hum.HealthChanged:Connect(function(health)
				local delta = lastHp - health
				if delta > 0 then
					totalDmg = totalDmg + delta
					hits = hits + 1
					benchModel:SetAttribute("BenchmarkTotalDamage", totalDmg)
					benchModel:SetAttribute("BenchmarkHitsReceived", hits)
				end
				lastHp = health
			end)
			hum.Died:Connect(function()
				benchModel:SetAttribute("BenchmarkSurvivalTime", os.clock() - startTime)
			end)
		end
	end
	table.insert(spawned, benchModel)

	-- Normal Opponents surrounding Admin
	for i = 1, count do
		local angle = (i - 1) * (2 * math.pi / count)
		local pos = Vector3.new(math.cos(angle) * 25, 7.5, math.sin(angle) * 25)
		local oppInst = QuinInstance.create({
			Type = (i % 2 == 0) and "TypeA" or "TypeC",
			Element = ElementData.getRandomElement(),
		})
		local oppModel = Spawner.spawnWithInstance(oppInst, pos, "TeamChallenger")
		table.insert(spawned, oppModel)
	end
	return spawned
end

-- Extra: ElementMatchup
scenarioHandlers["ElementMatchup"] = function(Spawner, options)
	local elem1 = options.Element1 or "Fire"
	local elem2 = options.Element2 or "Water"
	print(string.format("[BattleSimulationHarness] Running Scenario: ElementMatchup (%s vs %s)", elem1, elem2))

	local q1Inst = QuinInstance.create({ Type = options.Type1 or "TypeA", Element = elem1 })
	local q2Inst = QuinInstance.create({ Type = options.Type2 or "TypeB", Element = elem2 })

	local m1 = Spawner.spawnWithInstance(q1Inst, Vector3.new(-12, 7.5, 0), "TeamAlpha")
	local m2 = Spawner.spawnWithInstance(q2Inst, Vector3.new(12, 7.5, 0), "TeamBeta")
	return { m1, m2 }
end

-- Normalization mapping for scenario keys
local scenarioAliases = {
	["1"] = "OneVsOne",
	["01"] = "OneVsOne",
	["scenario_01"] = "OneVsOne",
	["scenario_01_onevsone"] = "OneVsOne",
	["onevsone"] = "OneVsOne",
	["1v1"] = "OneVsOne",

	["2"] = "TwoVsOne",
	["02"] = "TwoVsOne",
	["scenario_02"] = "TwoVsOne",
	["scenario_02_twovsone"] = "TwoVsOne",
	["twovsone"] = "TwoVsOne",
	["2v1"] = "TwoVsOne",

	["3"] = "IsolatedTarget",
	["03"] = "IsolatedTarget",
	["scenario_03"] = "IsolatedTarget",
	["scenario_03_isolatedtarget"] = "IsolatedTarget",
	["isolatedtarget"] = "IsolatedTarget",

	["4"] = "Rescue",
	["04"] = "Rescue",
	["scenario_04"] = "Rescue",
	["scenario_04_rescue"] = "Rescue",
	["rescue"] = "Rescue",

	["5"] = "LocalNumericalAdvantage",
	["05"] = "LocalNumericalAdvantage",
	["scenario_05"] = "LocalNumericalAdvantage",
	["scenario_05_localnumericaladvantage"] = "LocalNumericalAdvantage",
	["localnumericaladvantage"] = "LocalNumericalAdvantage",
	["advantage"] = "LocalNumericalAdvantage",

	["6"] = "OutnumberedRetreat",
	["06"] = "OutnumberedRetreat",
	["scenario_06"] = "OutnumberedRetreat",
	["scenario_06_outnumberedretreat"] = "OutnumberedRetreat",
	["outnumberedretreat"] = "OutnumberedRetreat",
	["retreat"] = "OutnumberedRetreat",

	["7"] = "Pursuit",
	["07"] = "Pursuit",
	["scenario_07"] = "Pursuit",
	["scenario_07_pursuit"] = "Pursuit",
	["pursuit"] = "Pursuit",

	["8"] = "TargetSwitch",
	["08"] = "TargetSwitch",
	["scenario_08"] = "TargetSwitch",
	["scenario_08_targetswitch"] = "TargetSwitch",
	["targetswitch"] = "TargetSwitch",

	["9"] = "ResourceExhaustion",
	["09"] = "ResourceExhaustion",
	["scenario_09"] = "ResourceExhaustion",
	["scenario_09_resourceexhaustion"] = "ResourceExhaustion",
	["resourceexhaustion"] = "ResourceExhaustion",
	["exhaustion"] = "ResourceExhaustion",

	["10"] = "LastStand",
	["scenario_10"] = "LastStand",
	["scenario_10_laststand"] = "LastStand",
	["laststand"] = "LastStand",

	["11"] = "BenchmarkQuin",
	["scenario_11"] = "BenchmarkQuin",
	["scenario_11_benchmarkquin"] = "BenchmarkQuin",
	["benchmarkquin"] = "BenchmarkQuin",
	["benchmark"] = "BenchmarkQuin",

	["elementmatchup"] = "ElementMatchup",
	["elements"] = "ElementMatchup",
}

-- Launch a specific reproducible scenario
function BattleSimulationHarness.runScenario(scenarioName, options)
	options = options or {}
	BattleSimulationHarness.clearArena()
	task.wait(0.2)

	local Spawner = getSpawner()
	if not Spawner then
		warn("[BattleSimulationHarness] Spawner could not be resolved.")
		return {}
	end

	local cleanKey = string.lower(string.gsub(tostring(scenarioName), "%s+", ""))
	local canonicalName = scenarioAliases[cleanKey] or scenarioName
	local handler = scenarioHandlers[canonicalName]

	if not handler then
		warn(string.format("[BattleSimulationHarness] Unknown scenario: %s (cleanKey: %s)", tostring(scenarioName), cleanKey))
		return {}
	end

	local spawned = handler(Spawner, options)
	Workspace:SetAttribute("CurrentMode", "SimulationScenario_" .. canonicalName)
	print(string.format("[BattleSimulationHarness] Scenario %s started with %d fighters.", canonicalName, #spawned))
	return spawned
end

-- Return list of all supported canonical scenario names
function BattleSimulationHarness.getAvailableScenarios()
	return {
		"Scenario_01_OneVsOne",
		"Scenario_02_TwoVsOne",
		"Scenario_03_IsolatedTarget",
		"Scenario_04_Rescue",
		"Scenario_05_LocalNumericalAdvantage",
		"Scenario_06_OutnumberedRetreat",
		"Scenario_07_Pursuit",
		"Scenario_08_TargetSwitch",
		"Scenario_09_ResourceExhaustion",
		"Scenario_10_LastStand",
		"Scenario_11_BenchmarkQuin",
	}
end

_G.BattleSimulationHarness = BattleSimulationHarness
shared.BattleSimulationHarness = BattleSimulationHarness

return BattleSimulationHarness
