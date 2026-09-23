import os
import sys
import json
import time

# Ensure Tools/Utilities is on python path
util_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "Utilities"))
if util_dir not in sys.path:
    sys.path.insert(0, util_dir)

from roblox_client import RobloxStudioClient

def run_combat_benchmark(mode="1v1", sample_duration_sec=6.0):
    client = RobloxStudioClient()
    print(f"Connected to Studio ID: {client.studio_id} | Mode: {mode}")

    # 1. Launch Match via Client remote event
    launch_code = f"""
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local QuinCore = ReplicatedStorage:WaitForChild("QuinCore")
    local Events = QuinCore:WaitForChild("Events")
    local labEvent = Events:WaitForChild("AnimationLabEvent")
    labEvent:FireServer("SetGameMode", {{ mode = "{mode}" }})
    return "{mode} Match Launched"
    """
    res_launch = client.execute_luau(launch_code, datamodel_type="Client")
    print("Launch Status:", res_launch.get("result", {}).get("content", [{}])[0].get("text", ""))

    # Wait for countdown (3.. 2.. 1.. FIGHT!)
    print("Waiting for match countdown...")
    time.sleep(4.5)

    # 2. Sample live combat telemetry
    sample_code = """
    local Workspace = game:GetService("Workspace")
    local quinServer = Workspace:FindFirstChild("QuinServer")
    local quinGhost = Workspace:FindFirstChild("QuinGhost")

    local report = {
        serverQuins = {},
        activeReactions = 0,
        activeGaze = 0,
    }

    if quinServer then
        for _, child in ipairs(quinServer:GetChildren()) do
            if child:IsA("Model") then
                local hum = child:FindFirstChildOfClass("Humanoid")
                table.insert(report.serverQuins, {
                    name = child.Name,
                    state = child:GetAttribute("CurrentState") or "N/A",
                    health = hum and math.round(hum.Health) or 0,
                })
            end
        end
    end

    if quinGhost then
        for _, ghost in ipairs(quinGhost:GetChildren()) do
            if ghost:IsA("Model") then
                local rx = ghost:GetAttribute("ReactionType")
                local look = ghost:GetAttribute("LookMode")
                if rx and rx ~= "NONE" then report.activeReactions = report.activeReactions + 1 end
                if look and look ~= "NONE" then report.activeGaze = report.activeGaze + 1 end
            end
        end
    end

    return report
    """

    print(f"Sampling combat activity over {sample_duration_sec}s...")
    steps = int(sample_duration_sec / 0.5)
    reactions_captured = 0
    gaze_captured = 0
    states_observed = set()
    initial_hp = None
    final_hp = None

    for i in range(steps):
        time.sleep(0.5)
        res = client.execute_luau(sample_code, datamodel_type="Client")
        txt = res.get("result", {}).get("content", [{}])[0].get("text", "")
        try:
            data = json.loads(txt)
            reactions_captured += data.get("activeReactions", 0)
            gaze_captured += data.get("activeGaze", 0)
            sq = data.get("serverQuins", [])
            server_list = list(sq.values()) if isinstance(sq, dict) else sq
            total_hp = sum(q.get("health", 0) for q in server_list if isinstance(q, dict))
            if initial_hp is None and total_hp > 0:
                initial_hp = total_hp
            if total_hp > 0:
                final_hp = total_hp
            for q in server_list:
                if isinstance(q, dict) and "state" in q:
                    states_observed.add(q.get("state"))
        except Exception as e:
            print("Telemetry sampling parse error:", e)

    # 3. Clean up arena
    clear_code = """
    local SSS = game:GetService("ServerScriptService")
    local Spawner = require(SSS:WaitForChild("QuinSpawner"))
    Spawner.cleanAll()
    workspace:SetAttribute("MatchStarted", false)
    workspace:SetAttribute("CurrentMode", "None")
    return "Arena Cleaned"
    """
    client.execute_luau(clear_code, datamodel_type="Server")

    print("\n=== COMBAT BENCHMARK REPORT ===")
    print(f"Match Mode: {mode}")
    print(f"Observed Combat States: {list(states_observed)}")
    print(f"Total Health Delta: Initial {initial_hp} -> Final {final_hp} (Damage Dealt: {initial_hp - final_hp if initial_hp and final_hp else 0})")
    print(f"Procedural Reactions Triggered: {reactions_captured}")
    print(f"Gaze Tracking Frames Active: {gaze_captured}")

    # Invariants verification
    combat_active = len(states_observed) > 1 and "Fight" in states_observed
    print(f"Invariant [Dynamic Combat Engagement]: {'PASSED' if combat_active else 'FAILED'}")
    print("===============================\n")

    client.close()

if __name__ == "__main__":
    mode_arg = sys.argv[1] if len(sys.argv) > 1 else "1v1"
    run_combat_benchmark(mode_arg)
