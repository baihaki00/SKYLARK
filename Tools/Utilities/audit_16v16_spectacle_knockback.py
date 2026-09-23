#// audit_16v16_spectacle_knockback.py
# Full 16 vs 16 Arena Battle Audit for Step 4 Spectacle Knockback & Active Muscle Ragdoll

import time
import json
import math
import os
from roblox_client import RobloxStudioClient
from PIL import Image

def main():
    client = RobloxStudioClient()
    print("Connected to Studio ID:", client.studio_id)

    # 1. Start 16 vs 16 Team Battle (32 Quins)
    print("\n--- INITIATING 16 VS 16 TEAM BATTLE (32 QUINS) ---")
    start_battle_code = """
    local QuinSpawner = require(game:GetService("ServerScriptService"):WaitForChild("QuinSpawner"))

    QuinSpawner.cleanAll()
    local quinGhost = workspace:FindFirstChild("QuinGhost")
    if quinGhost then
        for _, g in ipairs(quinGhost:GetChildren()) do
            g:Destroy()
        end
    end
    task.wait(0.2)

    -- Ensure AIGhostHandler runner is active for visual ghosts
    local sp = game:GetService("StarterPlayer"):FindFirstChild("StarterPlayerScripts")
    local ghostScript = sp and sp:FindFirstChild("AIGhostHandler")
    if ghostScript then
        task.spawn(loadstring(ghostScript.Source))
    end

    -- Spawn 16 TeamAlpha and 16 TeamBeta
    local positions = QuinSpawner.getSpawnPositions()
    local pos1 = positions[1] or Vector3.new(120, 8.5, -120)
    local pos2 = positions[2] or Vector3.new(-120, 8.5, 120)

    local alpha = QuinSpawner.spawnTeam({ "TypeA", "TypeC" }, "TeamAlpha", 16, 1, pos1, pos2)
    local beta = QuinSpawner.spawnTeam({ "TypeB", "TypeD" }, "TeamBeta", 16, 2, pos2, pos1)

    workspace:SetAttribute("MatchStarted", true)
    return string.format("Spawned %d Alpha vs %d Beta Quins", #alpha, #beta)
    """

    res = client.execute_luau(start_battle_code, "Edit")
    print("Battle launch result:", res)

    # Wait for Quins to spawn and spread into combat
    print("Waiting 4 seconds for Quins to engage in combat...")
    time.sleep(4)

    # 2. Monitor 32 Quins across rounds
    print("\n--- MONITORING 32 QUINS COMBAT & KNOCKBACK TELEMETRY ---")
    total_launches = 0
    total_skids = 0
    total_recoveries = 0
    total_prone = 0
    total_supine = 0

    shots = [
        {"name": "shot1_arena_wide", "cam": [0, 95, -180], "look": [0, 15, 0]},
        {"name": "shot2_midfield_clash", "cam": [-40, 25, -60], "look": [0, 8, 0]},
        {"name": "shot3_ground_skids", "cam": [35, 12, -20], "look": [0, 6, 10]},
        {"name": "shot4_aerial_spectacle", "cam": [-20, 35, 40], "look": [0, 15, 0]},
    ]
    captured_images = []

    for round_idx in range(6):
        time.sleep(2.0)
        telemetry_code = """
        local quinServer = workspace:FindFirstChild("QuinServer")
        local quins = quinServer and quinServer:GetChildren() or {}
        local quinGhost = workspace:FindFirstChild("QuinGhost")

        local data = {
            totalQuins = #quins,
            inKnockback = 0,
            inSkid = 0,
            inRecovery = 0,
            proneGetups = 0,
            supineGetups = 0,
            maxTilt = 0,
            activeRoosterTails = 0,
            sampleQuins = {}
        }

        for _, q in ipairs(quins) do
            if q:IsA("Model") and q:FindFirstChild("HumanoidRootPart") then
                local hrp = q.HumanoidRootPart
                local state = q:GetAttribute("CurrentState") or "None"
                local tilt = q:GetAttribute("KnockbackFlightTiltDeg") or 0
                if tilt > data.maxTilt then data.maxTilt = tilt end

                local hasSkid = hrp:FindFirstChild("KB_SkidVelocity") ~= nil
                local hasRooster = hrp:FindFirstChild("GroundSkidAttachment") ~= nil
                local hasAlign = hrp:FindFirstChild("Recovery_UprightAlign") ~= nil

                if state == "Knockback" then
                    data.inKnockback = data.inKnockback + 1
                    if hasSkid then
                        data.inSkid = data.inSkid + 1
                    end
                elseif state == "Recovery" or hasAlign then
                    data.inRecovery = data.inRecovery + 1
                    local lookY = hrp.CFrame.LookVector.Y
                    if lookY < -0.20 then
                        data.proneGetups = data.proneGetups + 1
                    else
                        data.supineGetups = data.supineGetups + 1
                    end
                end

                if hasRooster then
                    data.activeRoosterTails = data.activeRoosterTails + 1
                end

                if #data.sampleQuins < 5 and (state == "Knockback" or state == "Recovery" or state == "Chase") then
                    local g = quinGhost and quinGhost:FindFirstChild(q.Name .. "_Visual")
                    local gPitch = g and g:GetAttribute("ReactionPitch") or 0
                    table.insert(data.sampleQuins, {
                        name = q.Name,
                        state = state,
                        speed = math.round(Vector3.new(hrp.AssemblyLinearVelocity.X, 0, hrp.AssemblyLinearVelocity.Z).Magnitude),
                        velY = math.round(hrp.AssemblyLinearVelocity.Y),
                        isSkid = hasSkid,
                        tilt = math.round(tilt),
                        ghostPitch = gPitch
                    })
                end
            end
        end

        return data
        """

        t_res = client.execute_luau(telemetry_code, "Edit")
        try:
            t_data = json.loads(t_res.get("result", {}).get("content", [{}])[0].get("text", "{}"))
            total_launches += t_data.get("inKnockback", 0)
            total_skids += t_data.get("inSkid", 0)
            total_recoveries += t_data.get("inRecovery", 0)
            total_prone += t_data.get("proneGetups", 0)
            total_supine += t_data.get("supineGetups", 0)

            print(f"[Round {round_idx+1}] Active Quins: {t_data.get('totalQuins')} | In Knockback: {t_data.get('inKnockback')} (Skidding: {t_data.get('inSkid')}) | In Recovery: {t_data.get('inRecovery')} | Rooster Tails: {t_data.get('activeRoosterTails')} | Max Flight Tilt: {t_data.get('maxTilt'):.1f}°")
            sample_quins = t_data.get("sampleQuins", {})
            if isinstance(sample_quins, dict):
                sample_quins = list(sample_quins.values())
            for sq in sample_quins:
                if isinstance(sq, dict):
                    print(f"   -> {sq.get('name')}: State={sq.get('state')} Speed={sq.get('speed')} studs/s VelY={sq.get('velY')} Skid={sq.get('isSkid')} FlightTilt={sq.get('tilt')}° GhostSpine={sq.get('ghostPitch')}°")
        except Exception as e:
            print("Telemetry err:", e)

        # Screen capture during battle
        if round_idx < len(shots):
            shot = shots[round_idx]
            cap_id = f"Battle16v16_{shot['name']}"
            cap_res = client.call_tool("screen_capture", {
                "studio_id": client.studio_id,
                "capture_id": cap_id,
                "camera_position": shot["cam"],
                "look_at_position": shot["look"]
            })
            text_cap = cap_res.get("result", {}).get("content", [{}])[0].get("text", "")
            if "file:///" in text_cap:
                path = text_cap.split("file:///")[1].strip()
                if os.path.exists(path):
                    captured_images.append((shot["name"], path))
                    print(f"Captured {shot['name']} -> {path}")

    client.close()

    # 3. Create Composite Filmstrip
    if captured_images:
        print(f"\nCompiling {len(captured_images)} captures into step4_knockback_filmstrip.png...")
        imgs = [Image.open(p) for _, p in captured_images]
        w, h = imgs[0].size
        # 2x2 grid
        grid = Image.new("RGB", (w * 2, h * 2))
        grid.paste(imgs[0], (0, 0))
        if len(imgs) > 1: grid.paste(imgs[1], (w, 0))
        if len(imgs) > 2: grid.paste(imgs[2], (0, h))
        if len(imgs) > 3: grid.paste(imgs[3], (w, h))

        out_path = r"C:\Users\User\.gemini\antigravity\brain\742ec506-bcb9-44da-93cc-dfae76d1bdaf\step4_knockback_filmstrip.png"
        grid.save(out_path)
        print(f"Saved filmstrip: {out_path}")

    print("\n=== 16 VS 16 BATTLE AUDIT SUMMARY ===")
    print(f"Total Knockback Launches Sampled: {total_launches}")
    print(f"Total Kinetic Ground Skids Sampled: {total_skids}")
    print(f"Total Recoveries Sampled: {total_recoveries} (Prone: {total_prone}, Supine: {total_supine})")
    print("Step 4 verification complete.")

if __name__ == "__main__":
    main()
