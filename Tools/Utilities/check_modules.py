import sys
import os
sys.path.append(os.path.abspath("Tools/Utilities"))
from roblox_client import RobloxStudioClient

client = RobloxStudioClient()
test_code = """
local modules = {
    {"QuinSpawner", function() return require(game:GetService("ServerScriptService"):WaitForChild("QuinSpawner")) end},
    {"LeaderShowdownSystem", function() return require(game:GetService("ReplicatedStorage"):WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("LeaderShowdownSystem")) end},
    {"LeaderShowdownState", function() return require(game:GetService("ReplicatedStorage"):WaitForChild("QuinCore"):WaitForChild("States"):WaitForChild("LeaderShowdownState")) end},
    {"TacticalPerception", function() return require(game:GetService("ReplicatedStorage"):WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("TacticalPerception")) end},
    {"DecisionSystem", function() return require(game:GetService("ReplicatedStorage"):WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("DecisionSystem")) end},
    {"RetreatState", function() return require(game:GetService("ReplicatedStorage"):WaitForChild("QuinCore"):WaitForChild("States"):WaitForChild("RetreatState")) end},
    {"ChaseState", function() return require(game:GetService("ReplicatedStorage"):WaitForChild("QuinCore"):WaitForChild("States"):WaitForChild("ChaseState")) end},
    {"FightState", function() return require(game:GetService("ReplicatedStorage"):WaitForChild("QuinCore"):WaitForChild("States"):WaitForChild("FightState")) end},
    {"BeamStruggleState", function() return require(game:GetService("ReplicatedStorage"):WaitForChild("QuinCore"):WaitForChild("States"):WaitForChild("BeamStruggleState")) end},
    {"AuraFarmState", function() return require(game:GetService("ReplicatedStorage"):WaitForChild("QuinCore"):WaitForChild("States"):WaitForChild("AuraFarmState")) end},
    {"VfxModule", function() return require(game:GetService("ReplicatedStorage"):WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("VfxModule")) end},
    {"DamageModule", function() return require(game:GetService("ReplicatedStorage"):WaitForChild("QuinCore"):WaitForChild("Modules"):WaitForChild("DamageModule")) end},
}

local out = {}
for _, m in ipairs(modules) do
    local ok, err = pcall(m[2])
    table.insert(out, m[1] .. ": " .. (ok and "OK" or ("FAIL: " .. tostring(err))))
end
return table.concat(out, "\\n")
"""

res = client.execute_luau(test_code, datamodel_type="Server")
print(res.get("result", {}).get("content", [{}])[0].get("text", ""))
