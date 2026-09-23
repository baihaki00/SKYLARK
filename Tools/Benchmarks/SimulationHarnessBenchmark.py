import os
import sys
import json
import time

# Ensure Tools/Utilities is on python path
util_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "Utilities"))
if util_dir not in sys.path:
    sys.path.insert(0, util_dir)

from roblox_client import RobloxStudioClient

def run_simulation_harness():
    client = RobloxStudioClient()
    print("Connected to Studio ID:", client.studio_id)

    code = """
    local ServerScriptService = game:GetService("ServerScriptService")
    local Harness = require(ServerScriptService:WaitForChild("BattleSimulationHarness"))

    local scenarios = Harness.getAvailableScenarios()
    local results = {}

    for _, scName in ipairs(scenarios) do
        local success, err = pcall(function()
            local spawned = Harness.runScenario(scName)
            task.wait(0.3)
            local count = #spawned
            local mode = workspace:GetAttribute("CurrentMode")
            
            -- Invariant checks per scenario
            local invariantsPassed = true
            local failureReason = nil
            
            if scName == "Scenario_01_OneVsOne" then
                invariantsPassed = (count == 2)
                if not invariantsPassed then failureReason = "Expected 2 fighters, found " .. count end
            elseif scName == "Scenario_02_TwoVsOne" then
                invariantsPassed = (count == 3)
                if not invariantsPassed then failureReason = "Expected 3 fighters, found " .. count end
            elseif scName == "Scenario_03_IsolatedTarget" then
                invariantsPassed = (count == 4)
                if not invariantsPassed then failureReason = "Expected 4 fighters, found " .. count end
            elseif scName == "Scenario_04_Rescue" then
                invariantsPassed = (count == 3)
                local distressedHp = nil
                for _, m in ipairs(spawned) do
                    local h = m:FindFirstChildOfClass("Humanoid")
                    if h and h.Health < 300 then distressedHp = h.Health end
                end
                if not distressedHp then
                    invariantsPassed = false
                    failureReason = "No distressed ally found (< 300 HP)"
                end
            elseif scName == "Scenario_05_LocalNumericalAdvantage" then
                invariantsPassed = (count == 4)
                if not invariantsPassed then failureReason = "Expected 4 fighters, found " .. count end
            elseif scName == "Scenario_06_OutnumberedRetreat" then
                invariantsPassed = (count == 4)
                if not invariantsPassed then failureReason = "Expected 4 fighters, found " .. count end
            elseif scName == "Scenario_07_Pursuit" then
                invariantsPassed = (count == 2)
                if not invariantsPassed then failureReason = "Expected 2 fighters, found " .. count end
            elseif scName == "Scenario_08_TargetSwitch" then
                invariantsPassed = (count == 3)
                local woundedFound = false
                for _, m in ipairs(spawned) do
                    local h = m:FindFirstChildOfClass("Humanoid")
                    if h and h.Health < 200 then woundedFound = true end
                end
                if not woundedFound then
                    invariantsPassed = false
                    failureReason = "No vulnerable target (< 200 HP) present"
                end
            elseif scName == "Scenario_09_ResourceExhaustion" then
                invariantsPassed = (count == 2)
                local lowEnergy = true
                for _, m in ipairs(spawned) do
                    if (m:GetAttribute("Energy") or 100) > 30 then lowEnergy = false end
                end
                if not lowEnergy then
                    invariantsPassed = false
                    failureReason = "Fighters did not have critical energy (<= 30)"
                end
            elseif scName == "Scenario_10_LastStand" then
                invariantsPassed = (count == 3)
                local criticalHpFound = false
                for _, m in ipairs(spawned) do
                    local h = m:FindFirstChildOfClass("Humanoid")
                    if h and h.Health <= (h.MaxHealth * 0.20) then criticalHpFound = true end
                end
                if not criticalHpFound then
                    invariantsPassed = false
                    failureReason = "No critical defender (<= 20% HP) present"
                end
            elseif scName == "Scenario_11_BenchmarkQuin" then
                invariantsPassed = (count == 5)
                local adminFound = false
                for _, m in ipairs(spawned) do
                    if m:GetAttribute("IsBenchmark") == true then adminFound = true end
                end
                if not adminFound then
                    invariantsPassed = false
                    failureReason = "Benchmark recorder not attached"
                end
            end
            
            results[scName] = {
                success = true,
                fighterCount = count,
                mode = mode,
                invariantsPassed = invariantsPassed,
                failureReason = failureReason,
            }
        end)
        
        if not success then
            results[scName] = {
                success = false,
                error = tostring(err),
                invariantsPassed = false,
                failureReason = "Lua runtime exception: " .. tostring(err),
            }
        end
    end

    -- Clean arena after run
    Harness.clearArena()

    return results
    """

    res = client.execute_luau(code, datamodel_type="Server")
    txt = res.get("result", {}).get("content", [{}])[0].get("text", "")
    print("\n=== DETERMINISTIC SIMULATION HARNESS BENCHMARK RESULTS ===")
    passed = 0
    failed = 0
    try:
        data = json.loads(txt)
        for scName, res_data in data.items():
            ok = res_data.get("invariantsPassed", False)
            if ok:
                passed += 1
                print(f"[PASS] {scName}: {res_data.get('fighterCount')} fighters, mode={res_data.get('mode')}")
            else:
                failed += 1
                print(f"[FAIL] {scName}: Reason -> {res_data.get('failureReason')}")
        print("----------------------------------------------------------")
        print(f"Summary: {passed} PASSED | {failed} FAILED (Total: {passed + failed})")
    except Exception:
        print("Raw Output:", txt)
    print("==========================================================\n")
    client.close()
    return failed == 0

if __name__ == "__main__":
    run_simulation_harness()
