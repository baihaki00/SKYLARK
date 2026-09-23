import time
import json
import os
import sys

sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "Utilities")))
from roblox_client import RobloxStudioClient

def main():
    print("=== Live Movement & Projectile Jump Verification (16v16) ===")
    client = RobloxStudioClient()
    print(f"Connected to Studio ID: {client.studio_id}")

    # Step 1: Trigger 16v16 team battle via _G.GameModeManager
    start_code = """
    if _G.GameModeManager then
        _G.GameModeManager.startTeamBattle(16)
        return "16v16 Started via _G.GameModeManager"
    else
        return "Error: _G.GameModeManager not found"
    end
    """
    res = client.execute_luau(start_code, datamodel_type="Server")
    msg = res.get("result", {}).get("content", [{}])[0].get("text", "")
    print("Launch status:", msg)

    if "Error" in msg:
        # Fallback via Client remote
        client_code = """
        local ReplicatedStorage = game:GetService("ReplicatedStorage")
        local cmd = ReplicatedStorage:WaitForChild("GameCommand")
        cmd:FireServer("team", 16)
        return "Fired via GameCommand client remote"
        """
        res2 = client.execute_luau(client_code, datamodel_type="Client")
        print("Fallback launch status:", res2.get("result", {}).get("content", [{}])[0].get("text", ""))

    # Wait for countdown (3, 2, 1, FIGHT!)
    print("Waiting 4.5s for match countdown to finish...")
    time.sleep(4.5)

    # Step 2: Sample battlefield telemetry over 20 seconds
    print("Sampling 16v16 battlefield dynamics over 20 seconds...")
    all_snapshots = []
    
    for sec in range(1, 21):
        time.sleep(1.0)
        sample_code = """
        local HttpService = game:GetService("HttpService")
        local CollectionService = game:GetService("CollectionService")
        local quins = CollectionService:GetTagged("Quin")

        local stateCounts = {}
        local stylesUsed = {}
        local obstacleAwarenessCounts = {}
        local aliveCount = 0
        local pjCount = 0
        local dashCount = 0

        for _, q in ipairs(quins) do
            local hum = q:FindFirstChildOfClass("Humanoid")
            if hum and hum.Health > 0 then
                aliveCount = aliveCount + 1
                local st = q:GetAttribute("CurrentState") or "Unknown"
                stateCounts[st] = (stateCounts[st] or 0) + 1
                if st == "ProjectileJump" then pjCount = pjCount + 1 end
                if st == "Dash" then dashCount = dashCount + 1 end

                local style = q:GetAttribute("JumpStyle")
                if style then
                    stylesUsed["Style_" .. tostring(style)] = (stylesUsed["Style_" .. tostring(style)] or 0) + 1
                end

                local obs = q:GetAttribute("ObstacleAwareness")
                if obs and obs ~= "Clear" then
                    obstacleAwarenessCounts[obs] = (obstacleAwarenessCounts[obs] or 0) + 1
                end
            end
        end

        return HttpService:JSONEncode({
            alive = aliveCount,
            pjCount = pjCount,
            dashCount = dashCount,
            states = stateCounts,
            styles = stylesUsed,
            obstacles = obstacleAwarenessCounts,
            matchStarted = workspace:GetAttribute("MatchStarted")
        })
        """
        sample_res = client.execute_luau(sample_code, datamodel_type="Server")
        raw_text = sample_res.get("result", {}).get("content", [{}])[0].get("text", "{}")
        try:
            data = json.loads(raw_text)
            all_snapshots.append(data)
            states = data.get("states") if isinstance(data.get("states"), dict) else {}
            styles = data.get("styles") if isinstance(data.get("styles"), dict) else {}
            obs = data.get("obstacles") if isinstance(data.get("obstacles"), dict) else {}
            print(f"[T+{sec:02d}s] Alive: {data.get('alive')}, States: {states}, Styles: {styles}, Obs: {obs}")
        except Exception as e:
            print(f"[T+{sec:02d}s] Parse error: {e} raw: {raw_text[:100]}")

    client.close()

    # Step 3: Analyze results
    print("\n=== Verification Summary ===")
    total_pj_ticks = sum(s.get("pjCount", 0) for s in all_snapshots)
    total_dash_ticks = sum(s.get("dashCount", 0) for s in all_snapshots)
    
    unique_styles = set()
    for s in all_snapshots:
        st_dict = s.get("styles") if isinstance(s.get("styles"), dict) else {}
        for st in st_dict.keys():
            unique_styles.add(st)
            
    print(f"Total ProjectileJump occurrences: {total_pj_ticks}")
    print(f"Total Dash occurrences: {total_dash_ticks}")
    print(f"Unique ProjectileJump styles observed: {sorted(list(unique_styles))}")

    if total_pj_ticks > 0:
        print("[PASS] Projectile Jump is actively firing during match/chase across arena!")
    else:
        print("[FAIL] Projectile Jump was not observed during the sample window.")

    if total_dash_ticks > 0:
        print("[PASS] Athletic Dashes are actively occurring!")
    else:
        print("[FAIL] Dash was not observed during the sample window.")

if __name__ == "__main__":
    main()
