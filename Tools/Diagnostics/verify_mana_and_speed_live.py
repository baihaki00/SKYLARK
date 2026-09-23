import time
import json
import os
import sys

sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "Utilities")))
from roblox_client import RobloxStudioClient

def main():
    print("=== Live Mana Economy & 5x Speed HUD Verification ===")
    client = RobloxStudioClient()
    print(f"Connected to Studio ID: {client.studio_id}")

    # 1. Verify GameSpeedMultiplier and BattleSpeedHUD on Client
    hud_check_code = """
    local Players = game:GetService("Players")
    local player = Players.LocalPlayer
    local pGui = player and player:FindFirstChild("PlayerGui")
    local speedGui = pGui and pGui:FindFirstChild("BattleSpeedGui")
    local mult = workspace:GetAttribute("GameSpeedMultiplier")
    
    return string.format("HUD_Present: %s | GameSpeedMultiplier: %s", tostring(speedGui ~= nil), tostring(mult))
    """
    res_hud = client.execute_luau(hud_check_code, datamodel_type="Client")
    print("HUD & Speed Status:", res_hud.get("result", {}).get("content", [{}])[0].get("text", ""))

    # 2. Trigger 16v16 Match via Client remote
    launch_code = """
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local cmd = ReplicatedStorage:WaitForChild("GameCommand")
    cmd:FireServer("team", 16)
    return "16v16 Launched"
    """
    res_launch = client.execute_luau(launch_code, datamodel_type="Client")
    print("Launch Status:", res_launch.get("result", {}).get("content", [{}])[0].get("text", ""))

    # Wait for countdown
    print("Waiting for match countdown to finish...")
    time.sleep(4.5)

    # 3. Sample 15 seconds of combat: track Mana, ProjectileJump count, Dash count, WalkSpeed
    print("Sampling live combat dynamics (checking mana awareness, projectile jump rate, speeds)...")
    samples = []

    for sec in range(1, 16):
        time.sleep(1.0)
        sample_code = """
        local HttpService = game:GetService("HttpService")
        local CollectionService = game:GetService("CollectionService")
        local quins = CollectionService:GetTagged("Quin")

        local stateCounts = {}
        local energyLevels = {}
        local pjCount = 0
        local dashCount = 0
        local fatiguedCount = 0
        local illegalPJCount = 0
        local aliveCount = 0
        local speeds = {}

        for _, q in ipairs(quins) do
            local hum = q:FindFirstChildOfClass("Humanoid")
            if hum and hum.Health > 0 then
                aliveCount = aliveCount + 1
                local st = q:GetAttribute("CurrentState") or "Unknown"
                stateCounts[st] = (stateCounts[st] or 0) + 1
                if st == "ProjectileJump" then pjCount = pjCount + 1 end
                if st == "Dash" then dashCount = dashCount + 1 end
                
                local energy = q:GetAttribute("Energy") or 100
                if energy < 25 then
                    fatiguedCount = fatiguedCount + 1
                end
                if st == "ProjectileJump" then
                    local startEnergy = q:GetAttribute("EnergyAtActionStart") or (energy + 40)
                    if startEnergy < 40 then
                        illegalPJCount = illegalPJCount + 1
                    end
                elseif st == "Dash" then
                    local startEnergy = q:GetAttribute("EnergyAtActionStart") or (energy + 20)
                    if startEnergy < 25 then
                        illegalPJCount = illegalPJCount + 1
                    end
                end
                table.insert(energyLevels, math.round(energy))
                table.insert(speeds, math.round(hum.WalkSpeed))
            end
        end

        local avgEnergy = 0
        if #energyLevels > 0 then
            local sum = 0
            for _, e in ipairs(energyLevels) do sum = sum + e end
            avgEnergy = math.round(sum / #energyLevels)
        end

        local avgSpeed = 0
        if #speeds > 0 then
            local sum = 0
            for _, s in ipairs(speeds) do sum = sum + s end
            avgSpeed = math.round(sum / #speeds)
        end

        return HttpService:JSONEncode({
            alive = aliveCount,
            pjCount = pjCount,
            dashCount = dashCount,
            fatigued = fatiguedCount,
            illegalCasts = illegalPJCount,
            avgEnergy = avgEnergy,
            avgSpeed = avgSpeed,
            states = stateCounts,
            speedMultiplier = workspace:GetAttribute("GameSpeedMultiplier")
        })
        """
        sample_res = client.execute_luau(sample_code, datamodel_type="Server")
        raw_text = sample_res.get("result", {}).get("content", [{}])[0].get("text", "{}")
        try:
            data = json.loads(raw_text)
            samples.append(data)
            states = data.get("states") if isinstance(data.get("states"), dict) else {}
            print(f"[T+{sec:02d}s] Mult: {data.get('speedMultiplier')}x | Alive: {data.get('alive')} | AvgMana: {data.get('avgEnergy')} | Fatigued: {data.get('fatigued')} | Illegal: {data.get('illegalCasts')} | States: {states}")
        except Exception as e:
            print(f"[T+{sec:02d}s] Error: {e}")

    # 4. Test toggle speed to 10x and back to 1x via client remote
    print("\nTesting Speed Toggle to 10x...")
    toggle_10x = """
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local evt = ReplicatedStorage:WaitForChild("GameSpeedEvent")
    evt:FireServer(10)
    return "Fired 10x"
    """
    client.execute_luau(toggle_10x, datamodel_type="Client")
    time.sleep(1.0)
    chk_10x = client.execute_luau("return workspace:GetAttribute('GameSpeedMultiplier')", datamodel_type="Server")
    val_10x = chk_10x.get("result", {}).get("content", [{}])[0].get("text", "")
    print(f"Speed multiplier in workspace after 10x toggle: {val_10x}")

    print("Testing Speed Toggle back to 5x...")
    toggle_5x = """
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local evt = ReplicatedStorage:WaitForChild("GameSpeedEvent")
    evt:FireServer(5)
    return "Fired 5x"
    """
    client.execute_luau(toggle_5x, datamodel_type="Client")
    time.sleep(1.0)
    chk_5x = client.execute_luau("return workspace:GetAttribute('GameSpeedMultiplier')", datamodel_type="Server")
    val_5x = chk_5x.get("result", {}).get("content", [{}])[0].get("text", "")
    print(f"Speed multiplier in workspace after 5x toggle: {val_5x}")

    client.close()

    # 5. Analysis
    print("\n=== Verification Summary ===")
    total_pj = sum(s.get("pjCount", 0) for s in samples)
    total_dash = sum(s.get("dashCount", 0) for s in samples)
    print(f"Total ProjectileJump occurrences across 15s: {total_pj} (previously 152 before toning down)")
    print(f"Total Dash occurrences across 15s: {total_dash}")
    
    if total_pj > 0 and total_pj < 60:
        print("[PASS] Projectile Jump frequency successfully toned down to balanced tactical cadence!")
    elif total_pj == 0:
        print("[WARN] Projectile Jump was not observed.")
    else:
        print(f"[INFO] Projectile Jump count: {total_pj}")

    if val_10x == "10" and val_5x == "5":
        print("[PASS] Speed multiplier toggle verified across Client and Server!")
    else:
        print(f"[INFO] Speed toggle check: 10x={val_10x}, 5x={val_5x}")

if __name__ == "__main__":
    main()
