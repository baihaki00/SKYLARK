local DamageModule = require(game:GetService("ReplicatedStorage"):FindFirstChild("QuinCore"):FindFirstChild("Modules"):FindFirstChild("DamageModule"))

-- Setup dummy defender
local defender = Instance.new("Model")
defender.Name = "DefenderQuin"
local defHRP = Instance.new("Part", defender)
defHRP.Name = "HumanoidRootPart"
defHRP.CFrame = CFrame.new(0, 5, 0) -- faces (0, 0, -1)
local defHum = Instance.new("Humanoid", defender)
defHum.MaxHealth = 100
defHum.Health = 100
defender:SetAttribute("CurrentState", "Fight")
defender:SetAttribute("BlockChance", 1.0) -- Force 100% block chance for test determinism

-- Setup dummy attacker
local attacker = Instance.new("Model")
attacker.Name = "AttackerQuin"
local attHRP = Instance.new("Part", attacker)
attHRP.Name = "HumanoidRootPart"
local attHum = Instance.new("Humanoid", attacker)
attHum.MaxHealth = 100
attHum.Health = 100

local results = {}

-- TEST 1: REAR ATTACK (Defender at (0,5,0) facing (0,0,-1); Attacker at (0, 5, 10), so localPos.Z = 10 > 0.5)
attHRP.CFrame = CFrame.new(0, 5, 10)
defender:SetAttribute("IsGuarding", true)
defender:SetAttribute("Posture", 100)
defHum.Health = 100

local dmgInfo = { damage = 10, comboStep = 1 }
local applied, _, status = DamageModule.apply(attacker, defender, dmgInfo)

if status ~= "Blocked" and dmgInfo.isBackAttack == true then
    table.insert(results, "PASS: Rear attack bypassed guard completely (isBackAttack = true, status != Blocked).")
else
    table.insert(results, string.format("FAIL: Rear attack was blocked! status=%s, isBackAttack=%s", tostring(status), tostring(dmgInfo.isBackAttack)))
end

-- Verify 1.5x posture damage (base light attack posture damage is 8, 8 * 1.5 = 12)
local remainingPosture = defender:GetAttribute("Posture")
local postureDamageDealt = 100 - remainingPosture
if postureDamageDealt == 12 then
    table.insert(results, string.format("PASS: Rear attack inflicted 1.5x posture damage (12 posture damage vs 8 base)."))
else
    table.insert(results, string.format("FAIL: Rear posture damage was %s (expected 12).", tostring(postureDamageDealt)))
end

-- TEST 2: FRONT ATTACK (Attacker at (0, 5, -10), so localPos.Z = -10 <= 0.5)
attHRP.CFrame = CFrame.new(0, 5, -10)
defender:SetAttribute("IsGuarding", true)
defender:SetAttribute("Posture", 100)
defHum.Health = 100

local frontDmgInfo = { damage = 10, comboStep = 1 }
local frontApplied, _, frontStatus = DamageModule.apply(attacker, defender, frontDmgInfo)

if frontStatus == "Blocked" then
    table.insert(results, "PASS: Front attack was cleanly blocked by active guard.")
else
    table.insert(results, string.format("FAIL: Front attack was not blocked! status=%s", tostring(frontStatus)))
end

-- Cleanup dummies
defender:Destroy()
attacker:Destroy()

return table.concat(results, "\n")
