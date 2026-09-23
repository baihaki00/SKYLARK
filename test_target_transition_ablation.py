import os
import sys
import time

current_dir = os.path.dirname(os.path.abspath(__file__))
tools_dir = os.path.join(current_dir, "Tools", "Utilities")
if tools_dir not in sys.path:
    sys.path.insert(0, tools_dir)

try:
    sys.stdout.reconfigure(encoding='utf-8')
except Exception:
    pass

from roblox_client import RobloxStudioClient

def test_target_transition_ablation():
    client = RobloxStudioClient()
    print("Connected to Studio ID:", client.studio_id)

    # 1. Setup deterministic test scene:
    # QuinA at (0, 3, 0)
    # QuinVictim at (0, 3, 6) with 15 HP
    # QuinDistant at (0, 3, 50)
    setup_code = """
    local sss = game:GetService("ServerScriptService")
    local QuinSpawner = require(sss:WaitForChild("QuinSpawner"))
    QuinSpawner.cleanAll()
    workspace:SetAttribute("MatchStarted", false)

    -- Spawn QuinA (TeamAlpha)
    local qA = QuinSpawner.spawn("TypeA", Vector3.new(0, 3, 0), "TeamAlpha")
    qA.Name = "QuinA_Attacker"

    -- Spawn QuinVictim (TeamBeta, 15 HP, close by)
    local qV = QuinSpawner.spawn("TypeB", Vector3.new(0, 3, 6), "TeamBeta")
    qV.Name = "QuinVictim"
    local humV = qV:FindFirstChildOfClass("Humanoid")
    if humV then
        humV.Health = 15
    end

    -- Spawn QuinDistant (TeamBeta, full HP, 50 studs away)
    local qD = QuinSpawner.spawn("TypeC", Vector3.new(0, 3, 50), "TeamBeta")
    qD.Name = "QuinDistant"

    workspace:SetAttribute("MatchStarted", true)
    return "Ablation scene initialized"
    """

    res = client.execute_luau(setup_code, datamodel_type="Server")
    print(res.get("result", {}).get("content", [{}])[0].get("text", ""))

    # Monitor attacker across 20 samples over 3 seconds
    monitor_code = """
    local qA = workspace:FindFirstChild("QuinA_Attacker") or (workspace:FindFirstChild("QuinServer") and workspace.QuinServer:FindFirstChild("QuinA_Attacker"))
    local qV = workspace:FindFirstChild("QuinVictim") or (workspace:FindFirstChild("QuinServer") and workspace.QuinServer:FindFirstChild("QuinVictim"))
    if not qA then return "QuinA not found" end

    local humA = qA:FindFirstChildOfClass("Humanoid")
    local st = qA:GetAttribute("CurrentState") or "None"
    local spd = humA and humA.WalkSpeed or 0
    local target = qA:GetAttribute("CurrentTarget") or "None"
    local hpV = (qV and qV:FindFirstChildOfClass("Humanoid")) and qV.Humanoid.Health or 0

    return string.format("State=%s | Spd=%.1f | Target=%s | VictimHP=%.0f", st, spd, target, hpV)
    """

    print("\n--- MONITORING ATTACKER STATE PROGRESSION ---")
    for i in range(15):
        time.sleep(0.2)
        res = client.execute_luau(monitor_code, datamodel_type="Server")
        txt = res.get("result", {}).get("content", [{}])[0].get("text", "")
        print(f"Sample {i+1:02d} (+{(i+1)*0.2:.1f}s): {txt}")

    client.close()

if __name__ == "__main__":
    test_target_transition_ablation()
