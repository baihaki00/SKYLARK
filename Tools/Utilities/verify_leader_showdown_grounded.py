import time
import json
import os
import sys
import base64

sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..")))
from Tools.Utilities.roblox_client import RobloxStudioClient

def main():
    client = RobloxStudioClient()
    print("Connected to Studio ID:", client.studio_id)

    # 1. Clean arena and spawn 5v1 matchup
    # Place 2 quins inside 48-stud radius (at dist ~25 studs) and 3 outside (at dist ~60 studs)
    # to explicitly verify pre-existing radius Quins rising with dais and outside quins making leisure choices
    setup_code = """
    local RS = game:GetService("ReplicatedStorage")
    local SSS = game:GetService("ServerScriptService")
    local QuinSpawner = require(SSS.QuinSpawner)
    local LSS = require(RS.QuinCore.Modules.LeaderShowdownSystem)

    LSS.reset()
    QuinSpawner.cleanAll()
    task.wait(0.5)

    -- Spawn Squad (TeamAlpha: 5 fighters, including a Stone Tanker)
    -- TypeB is Stone Tanker, TypeA is Striker, TypeC is Assassin, TypeD is Brawler
    local alphaTypes = {"TypeB", "TypeA", "TypeC", "TypeA", "TypeD"}
    local posAlpha = Vector3.new(20, 2.05, -38)  -- Inside radius! (dist = 20 studs)
    QuinSpawner.spawnTeam(alphaTypes, "TeamAlpha", 5, 1, posAlpha)

    task.wait(0.2)
    -- Spawn Lone Opponent (TeamBeta: 1 fighter) outside radius
    local betaTypes = {"TypeC"}
    local posBeta = Vector3.new(-65, 2.05, -38) -- Outside radius! (dist = 65 studs)
    QuinSpawner.spawnTeam(betaTypes, "TeamBeta", 1, 2, posBeta)

    -- Assign specific quirkies to test leisurely behavior
    local CS = game:GetService("CollectionService")
    local quins = CS:GetTagged("Quin")
    local quirkies = {"PackLeader", "Showoff", "Lazy", "Observer", "LoneWolf", "Revengeful"}
    for idx, q in ipairs(quins) do
        q:SetAttribute("Quirky", quirkies[idx] or "Observer")
        q:SetAttribute("AssignedQuirky", quirkies[idx] or "Observer")
    end

    workspace:SetAttribute("MatchStarted", true)
    return "Spawned 5v1 Quins with configured positions & quirkies"
    """

    res = client.execute_luau(setup_code, datamodel_type="Server")
    print("Spawn result:", res)
    time.sleep(1.0)

    # 2. Trigger Asymmetric Showdown
    trigger_code = """
    local RS = game:GetService("ReplicatedStorage")
    local CS = game:GetService("CollectionService")
    local LSS = require(RS.QuinCore.Modules.LeaderShowdownSystem)

    local squad = {}
    local lone = nil

    for _, q in ipairs(CS:GetTagged("Quin")) do
        local team = q:GetAttribute("Team")
        if team == "TeamAlpha" then
            table.insert(squad, q)
        elseif team == "TeamBeta" then
            lone = q
        end
    end

    if #squad >= 2 and lone then
        task.spawn(function()
            LSS.initiateAsymmetricShowdown(squad, lone)
        end)
        return "Initiated Showdown: " .. #squad .. " vs 1"
    else
        return "Error: squad=" .. #squad .. " lone=" .. tostring(lone)
    end
    """

    res = client.execute_luau(trigger_code, datamodel_type="Server")
    print("Trigger result:", res)

    # 3. Monitor progression through phases until DuelActive
    print("Waiting for Showdown choreography to complete...")
    for step in range(45):
        time.sleep(0.5)
        poll_code = """
        local RS = game:GetService("ReplicatedStorage")
        local LSS = require(RS.QuinCore.Modules.LeaderShowdownSystem)
        local CS = game:GetService("CollectionService")

        local duelists = {}
        local guards = {}
        for _, q in ipairs(CS:GetTagged("Quin")) do
            local role = q:GetAttribute("LeaderShowdownRole")
            local state = q:GetAttribute("CurrentState")
            local hum = q:FindFirstChildOfClass("Humanoid")
            local hp = hum and hum.Health or 0
            local maxHp = hum and hum.MaxHealth or 100
            local hrp = q:FindFirstChild("HumanoidRootPart")
            local pos = hrp and hrp.Position or Vector3.zero
            local distToCenter = Vector3.new(pos.X - 0, 0, pos.Z - (-38)).Magnitude
            local jumpPower = hum and hum.JumpPower or 0
            local isSitting = hum and hum.Sit or false

            -- Check foot toe bone height relative to dais (top is 6.50)
            local lowestFootY = 999
            for _, d in ipairs(q:GetDescendants()) do
                if d:IsA("Bone") or d:IsA("Attachment") then
                    if string.find(string.lower(d.Name), "toe") or string.find(string.lower(d.Name), "foot") then
                        if d.WorldPosition.Y < lowestFootY then
                            lowestFootY = d.WorldPosition.Y
                        end
                    end
                end
            end

            local info = {
                name = q.Name,
                role = role or "None",
                state = state or "None",
                hp = math.floor(hp),
                maxHp = math.floor(maxHp),
                dist = math.floor(distToCenter * 10) / 10,
                x = math.floor(pos.X * 10) / 10,
                z = math.floor(pos.Z * 10) / 10,
                y = math.floor(pos.Y * 10) / 10,
                lowestFootY = math.floor(lowestFootY * 100) / 100,
                jumpPower = jumpPower,
                quirky = q:GetAttribute("Quirky") or "None",
                platformStatus = q:GetAttribute("SpectatorPlatformStatus") or "None",
                wasRider = q:GetAttribute("LeaderShowdownPlatformRider") or false,
                isSitting = isSitting
            }

            if role == "Duelist" then
                table.insert(duelists, info)
            elseif role == "PerimeterGuard" then
                table.insert(guards, info)
            end
        end

        local dais = workspace:FindFirstChild("LeaderShowdownDais")
        local platformSize = dais and dais.PrimaryPart and tostring(dais.PrimaryPart.Size) or "none"

        local separation = 0
        if #duelists >= 2 then
            local dx = duelists[1].x - duelists[2].x
            local dz = duelists[1].z - duelists[2].z
            separation = math.floor(math.sqrt(dx*dx + dz*dz) * 10) / 10
        end

        local result = {
            active = LSS.isActive,
            phase = LSS.activePhase,
            duelists = duelists,
            guards = guards,
            platformExists = (dais ~= nil),
            platformSize = platformSize,
            separation = separation
        }
        local HttpService = game:GetService("HttpService")
        return HttpService:JSONEncode(result)
        """
        poll_res = client.execute_luau(poll_code, datamodel_type="Server")
        txt = poll_res.get("result", {}).get("content", [{}])[0].get("text", "")
        try:
            data = json.loads(txt)
            phase = data.get("phase", "")
            print(f"[{step*0.5:.1f}s] Phase: {phase} | Active: {data.get('active')} | Platform: {data.get('platformSize')} | Duelists: {len(data.get('duelists', []))} | Guards: {len(data.get('guards', []))}")
            if phase == "DuelActive":
                print(">>> SHOWDOWN DUEL IS ACTIVE! Monitoring combat integrity...")
                break
        except Exception as e:
            pass

    # 4. Monitor active duel for 8 seconds, testing ring containment, jump suppression, and foot height
    print("\n--- MONITORING ACTIVE DUEL & SPECTATOR INTEGRITY ---")
    max_duelist_dist = 0
    min_duelist_separation = 999
    any_jump_detected = False
    spectator_damage_detected = False
    feet_sinking_detected = False

    initial_guard_hps = {}

    for i in range(10):
        time.sleep(0.8)
        poll_res = client.execute_luau(poll_code, datamodel_type="Server")
        txt = poll_res.get("result", {}).get("content", [{}])[0].get("text", "")
        try:
            data = json.loads(txt)
            sep = data.get("separation", 0)
            if sep > 0 and sep < min_duelist_separation:
                min_duelist_separation = sep

            for d in data.get("duelists", []):
                dist = d.get("dist", 0)
                if dist > max_duelist_dist:
                    max_duelist_dist = dist
                if d.get("jumpPower", 0) > 0:
                    any_jump_detected = True
                
                # Check duelist foot contact (surface is at 6.50, toe bone should be >= 6.40)
                if d.get("lowestFootY", 0) < 6.40:
                    feet_sinking_detected = True

                print(f"  Duelist: {d['name']} | State: {d['state']} | HP: {d['hp']}/{d['maxHp']} | DistToCenter: {d['dist']}s | Pos: ({d.get('x')}, {d.get('y')}, {d.get('z')}) | JumpPower: {d['jumpPower']}")
            print(f"  >>> Duelist Separation: {sep} studs")

            for g in data.get("guards", []):
                if g["name"] not in initial_guard_hps:
                    initial_guard_hps[g["name"]] = g["hp"]
                elif g["hp"] < initial_guard_hps[g["name"]]:
                    spectator_damage_detected = True

                status = g.get("platformStatus", "None")
                is_sat = g.get("isSitting", False)
                rider = g.get("wasRider", False)

                # Check guard foot contact: if OnPlatform and not sitting, toe bone should be >= 6.45
                if status == "OnPlatform" and not is_sat and g.get("lowestFootY", 0) < 6.40:
                    feet_sinking_detected = True

                print(f"  Spectator: {g['name']} ({g['quirky']}) | Post: {status} (Rider: {rider}, Sit: {is_sat}) | Dist: {g['dist']}s (HRP Y={g['y']}, Toe Y={g['lowestFootY']}) | HP: {g['hp']}")
            print("-" * 50)
        except Exception as e:
            print("Poll error:", e)

    print(f"\nVerification Results:")
    print(f"Platform Dimensions: {data.get('platformSize')} (Expected: 4.5, 96, 96 for r=48)")
    print(f"Max Duelist Distance from Center: {max_duelist_dist:.1f} studs (Limit: 36.0 studs)")
    print(f"Any Jumps/JumpPower Detected: {any_jump_detected} (Expected: False)")
    print(f"Spectator Damage Detected: {spectator_damage_detected} (Expected: False)")
    print(f"Feet Sinking Detected: {feet_sinking_detected} (Expected: False)")

    # 5. Capture close-up screenshot of feet contact at platform surface level
    print("\nCapturing close-up screenshot of foot grounding at surface level...")
    # Camera placed low near the platform edge looking at the Quin feet
    cam_pos_feet = [12, 8.5, -28]
    look_pos_feet = [0, 7.0, -38]

    cap_res_feet = client.call_tool("screen_capture", {
        "studio_id": client.studio_id,
        "capture_id": "ScreenCapture_LeaderShowdown_Grounded",
        "camera_position": cam_pos_feet,
        "look_at_position": look_pos_feet
    })

    artifact_path_feet = r"C:\Users\User\.gemini\antigravity\brain\742ec506-bcb9-44da-93cc-dfae76d1bdaf\screen_capture_leader_showdown_grounded.png"
    if cap_res_feet and not cap_res_feet.get("isError", False):
        content = cap_res_feet.get("result", {}).get("content", [])
        for item in content:
            if item.get("type") == "image":
                img_data = item.get("data", "")
                with open(artifact_path_feet, "wb") as f:
                    f.write(base64.b64decode(img_data))
                print(f"[OK] Saved close-up screenshot to {artifact_path_feet} ({len(img_data)} bytes)")
                break

    # 6. Capture wide cinematic screenshot showing entire 48-stud dais and spectator distribution
    print("\nCapturing wide cinematic overview screenshot...")
    cam_pos_wide = [0, 36, 18]
    look_pos_wide = [0, 7, -38]

    cap_res_wide = client.call_tool("screen_capture", {
        "studio_id": client.studio_id,
        "capture_id": "ScreenCapture_LeaderShowdown_Organic",
        "camera_position": cam_pos_wide,
        "look_at_position": look_pos_wide
    })

    artifact_path_wide = r"C:\Users\User\.gemini\antigravity\brain\742ec506-bcb9-44da-93cc-dfae76d1bdaf\screen_capture_leader_showdown_organic.png"
    if cap_res_wide and not cap_res_wide.get("isError", False):
        content = cap_res_wide.get("result", {}).get("content", [])
        for item in content:
            if item.get("type") == "image":
                img_data = item.get("data", "")
                with open(artifact_path_wide, "wb") as f:
                    f.write(base64.b64decode(img_data))
                print(f"[OK] Saved wide screenshot to {artifact_path_wide} ({len(img_data)} bytes)")
                break

    client.close()

if __name__ == "__main__":
    main()
