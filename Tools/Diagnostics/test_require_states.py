import sys
import os
import json

sys.stdout.reconfigure(encoding='utf-8')
sys.path.append(r'C:\Users\User\.gemini\antigravity\scratch\Tools\Utilities')
from roblox_client import RobloxStudioClient

client = RobloxStudioClient()

test_luau = """
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local QuinCore = ReplicatedStorage:WaitForChild("QuinCore")
local statesFolder = QuinCore:WaitForChild("States")

local results = {}
for _, ch in ipairs(statesFolder:GetChildren()) do
    if ch:IsA("ModuleScript") then
        local success, err = pcall(function()
            require(ch)
        end)
        results[ch.Name] = {
            success = success,
            err = err and tostring(err) or nil
        }
    end
end

-- Also test modules in Modules
local modulesFolder = QuinCore:WaitForChild("Modules")
local modResults = {}
for _, ch in ipairs(modulesFolder:GetChildren()) do
    if ch:IsA("ModuleScript") then
        local success, err = pcall(function()
            require(ch)
        end)
        modResults[ch.Name] = {
            success = success,
            err = err and tostring(err) or nil
        }
    end
end

-- Also test Main script line by line
local mainScript = QuinCore:FindFirstChild("Main")

return {
    states = results,
    modules = modResults,
    hasMain = (mainScript ~= nil)
}
"""

res = client.execute_luau(test_luau, datamodel_type="Server")
content = res.get("result", {}).get("content", [{}])[0].get("text", "")
data = json.loads(content)

print("=== STATES ===")
for name, r in data.get("states", {}).items():
    if not r["success"]:
        print(f"[FAIL] {name} -> {r['err']}")
    else:
        print(f"[OK] {name}")

print("\n=== MODULES ===")
for name, r in data.get("modules", {}).items():
    if not r["success"]:
        print(f"[FAIL] {name} -> {r['err']}")
    else:
        print(f"[OK] {name}")
