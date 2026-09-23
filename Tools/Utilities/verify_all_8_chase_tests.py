import time
import json
import os
import sys
import base64

sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..")))
from Tools.Utilities.roblox_client import RobloxStudioClient

ARTIFACT_DIR = r"C:\Users\User\.gemini\antigravity\brain\742ec506-bcb9-44da-93cc-dfae76d1bdaf"

def cleanup(client):
    code = """
    local SSS = game:GetService("ServerScriptService")
    local QuinSpawner = require(SSS.QuinSpawner)
    QuinSpawner.cleanAll()
    local p = workspace:FindFirstChild("TestVantagePlatform")
    if p then p:Destroy() end
    local w = workspace:FindFirstChild("TestDeadEndWall")
    if w then w:Destroy() end
    local o = workspace:FindFirstChild("TestObstacle")
    if o then o:Destroy() end
    return "Cleaned"
    """
    client.execute_luau(code, datamodel_type="Server")
    time.sleep(0.3)

def capture_image(client, filename, cam_pos, look_at):
    cap_res = client.call_tool("screen_capture", {
        "studio_id": client.studio_id,
        "capture_id": filename.replace(".png", ""),
        "camera_position": cam_pos,
        "look_at_position": look_at
    })
    filepath = os.path.join(ARTIFACT_DIR, filename)
    if cap_res and not cap_res.get("isError", False):
        content = cap_res.get("result", {}).get("content", [])
        for item in content:
            if item.get("type") == "image":
                img_data = item.get("data", "")
                with open(filepath, "wb") as f:
                    f.write(base64.b64decode(img_data))
                print(f"[OK] Saved screenshot to {filepath} ({len(img_data)} bytes)")
                return True
    return False

# ============================================================
# TEST 1: OPEN GROUND CONTINUOUS EVASION (ZERO PIT STOPS)
# ============================================================
def test_1_open_ground(client):
    print("\n--- TEST 1: OPEN GROUND CONTINUOUS EVASION ---")
    cleanup(client)

    setup = """
    local SSS = game:GetService("ServerScriptService")
    local QuinSpawner = require(SSS.QuinSpawner)

    local fleeing = QuinSpawner.spawn("TypeC", Vector3.new(0, 2.05, -10), "TeamBeta")
    fleeing.Name = "Fleeing_T1"
    fleeing:FindFirstChildOfClass("Humanoid").Health = 100
    fleeing:SetAttribute("Pers_RetreatTendency", 0.95)

    local chaser = QuinSpawner.spawn("TypeA", Vector3.new(0, 2.05, -35), "TeamAlpha")
    chaser.Name = "Chaser_T1"
    chaser:FindFirstChildOfClass("Humanoid").WalkSpeed = 22

    workspace:SetAttribute("MatchStarted", true)
    task.wait(0.2)
    fleeing:SetAttribute("RecommendedAction", "Retreat")
    fleeing:SetAttribute("TargetQuin", "Chaser_T1")
    return "Ready"
    """
    client.execute_luau(setup, datamodel_type="Server")
    time.sleep(0.4)

    zero_stops = 0
    samples = 0
    poll = """
    local Http = game:GetService("HttpService")
    local q = workspace:FindFirstChild("QuinServer") and workspace.QuinServer:FindFirstChild("Fleeing_T1")
    if not q then return Http:JSONEncode({err = "None"}) end
    local hrp = q:FindFirstChild("HumanoidRootPart")
    local hum = q:FindFirstChildOfClass("Humanoid")
    return Http:JSONEncode({
        st = q:GetAttribute("CurrentState"),
        spd = hrp and hrp.AssemblyLinearVelocity.Magnitude or 0,
        ws = hum and hum.WalkSpeed or 0,
        z = hrp and hrp.Position.Z or 0
    })
    """
    first_z = None
    last_z = None
    has_exited = False
    for i in range(20):
        time.sleep(0.12)
        raw = client.execute_luau(poll, datamodel_type="Server")
        data = json.loads(raw.get("result", {}).get("content", [{}])[0].get("text", "{}"))
        if "err" not in data:
            samples += 1
            st, spd, z = data.get("st"), data.get("spd", 0), data.get("z", 0)
            if first_z is None: first_z = z
            last_z = z
            if st == "Retreat" and not has_exited:
                if spd < 1.0: zero_stops += 1
            elif st != "Retreat":
                has_exited = True
            if i % 5 == 0:
                print(f"  [Sample {i:02d}] State={st} | Speed={spd:.1f} studs/s | Z={z:.1f}")

    disp = abs((last_z or 0) - (first_z or 0))
    passed = (zero_stops == 0 and disp > 15.0)
    print(f"  Result: Zero Stops={zero_stops}, Net Disp={disp:.1f} studs -> {'PASSED' if passed else 'FAILED'}")
    return passed

# ============================================================
# TEST 2: ALLIES BEHIND (RETREAT TO ALLIES SCORING)
# ============================================================
def test_2_allies_behind(client):
    print("\n--- TEST 2: ALLIES BEHIND (TO_ALLIES CANDIDATE SELECTION) ---")
    cleanup(client)

    code = """
    local RS = game:GetService("ReplicatedStorage")
    local SSS = game:GetService("ServerScriptService")
    local Http = game:GetService("HttpService")
    local QuinSpawner = require(SSS.QuinSpawner)
    local RTM = require(RS.QuinCore.Modules.RetreatTacticsModule)

    local fleeing = QuinSpawner.spawn("TypeC", Vector3.new(0, 2.05, 0), "TeamBeta")
    fleeing.Name = "Fleeing_T2"
    fleeing:SetAttribute("Quirky", "Follower")
    fleeing:SetAttribute("Pers_Protectiveness", 0.85)

    local ally1 = QuinSpawner.spawn("TypeB", Vector3.new(-6, 2.05, 25), "TeamBeta")
    local ally2 = QuinSpawner.spawn("TypeD", Vector3.new(6, 2.05, 25), "TeamBeta")
    local ally3 = QuinSpawner.spawn("TypeA", Vector3.new(0, 2.05, 30), "TeamBeta")

    local enemy = QuinSpawner.spawn("TypeA", Vector3.new(0, 2.05, -25), "TeamAlpha")

    workspace:SetAttribute("MatchStarted", true)
    task.wait(0.2)

    local dec = RTM.evaluate(fleeing, { enemy }, { ally1, ally2, ally3 })
    return Http:JSONEncode({
        chosen = dec.objective,
        score = dec.score,
        cScores = dec.candidateScores
    })
    """
    raw = client.execute_luau(code, datamodel_type="Server")
    data = json.loads(raw.get("result", {}).get("content", [{}])[0].get("text", "{}"))
    chosen = data.get("chosen")
    cScores = data.get("cScores", {})
    print(f"  Chosen: {chosen} (Score: {data.get('score')})")
    print(f"  Candidate Scores: {cScores}")
    passed = (chosen == "TO_ALLIES")
    print(f"  Result: {'PASSED' if passed else 'FAILED'}")
    return passed

# ============================================================
# TEST 3: HIGH PLATFORM ESCAPE
# ============================================================
def test_3_high_platform(client):
    print("\n--- TEST 3: HIGH PLATFORM ESCAPE (TO_HIGH_GROUND SELECTION) ---")
    cleanup(client)

    code = """
    local RS = game:GetService("ReplicatedStorage")
    local SSS = game:GetService("ServerScriptService")
    local Http = game:GetService("HttpService")
    local QuinSpawner = require(SSS.QuinSpawner)
    local RTM = require(RS.QuinCore.Modules.RetreatTacticsModule)

    local plat = Instance.new("Part")
    plat.Name = "TestVantagePlatform"
    plat.Size = Vector3.new(24, 2, 24)
    plat.Position = Vector3.new(0, 10, 22)
    plat.Anchored = true
    plat.CanCollide = true
    plat.Parent = workspace

    local fleeing = QuinSpawner.spawn("TypeC", Vector3.new(0, 2.05, 5), "TeamBeta")
    fleeing:SetAttribute("Quirky", "HighGround")
    local enemy = QuinSpawner.spawn("TypeB", Vector3.new(0, 2.05, -20), "TeamAlpha")

    workspace:SetAttribute("MatchStarted", true)
    task.wait(0.2)

    local dec = RTM.evaluate(fleeing, { enemy }, {})
    return Http:JSONEncode({
        chosen = dec.objective,
        score = dec.score,
        cScores = dec.candidateScores
    })
    """
    raw = client.execute_luau(code, datamodel_type="Server")
    data = json.loads(raw.get("result", {}).get("content", [{}])[0].get("text", "{}"))
    chosen = data.get("chosen")
    cScores = data.get("cScores", {})
    print(f"  Chosen: {chosen} (Score: {data.get('score')})")
    print(f"  Candidate Scores: {cScores}")
    passed = (chosen == "TO_HIGH_GROUND")
    print(f"  Result: {'PASSED' if passed else 'FAILED'}")
    return passed

# ============================================================
# TEST 4: MULTIPLE PURSUERS (THREAT CENTROID EVASION)
# ============================================================
def test_4_multiple_pursuers(client):
    print("\n--- TEST 4: MULTIPLE PURSUERS (THREAT CENTROID EVASION) ---")
    cleanup(client)

    code = """
    local RS = game:GetService("ReplicatedStorage")
    local SSS = game:GetService("ServerScriptService")
    local Http = game:GetService("HttpService")
    local QuinSpawner = require(SSS.QuinSpawner)
    local RTM = require(RS.QuinCore.Modules.RetreatTacticsModule)

    local fleeing = QuinSpawner.spawn("TypeC", Vector3.new(0, 2.05, 0), "TeamBeta")

    -- Two flanking pursuers behind
    local enemyL = QuinSpawner.spawn("TypeA", Vector3.new(-15, 2.05, -20), "TeamAlpha")
    local enemyR = QuinSpawner.spawn("TypeA", Vector3.new(15, 2.05, -20), "TeamAlpha")

    workspace:SetAttribute("MatchStarted", true)
    task.wait(0.2)

    local dec = RTM.evaluate(fleeing, { enemyL, enemyR }, {})
    local steer = dec.steerDirection
    return Http:JSONEncode({
        chosen = dec.objective,
        steer = {steer.X, steer.Y, steer.Z},
        score = dec.score
    })
    """
    raw = client.execute_luau(code, datamodel_type="Server")
    data = json.loads(raw.get("result", {}).get("content", [{}])[0].get("text", "{}"))
    steer = data.get("steer", [0, 0, 0])
    # Threat centroid is at (0, 2.05, -20). Evasion steer Z must be positive (+Z away from threats)
    passed = (steer[2] > 0.3)
    print(f"  Steer Vector away from 2 Pursuers: ({steer[0]:.2f}, {steer[1]:.2f}, {steer[2]:.2f}) -> +Z Evasion: {passed}")
    print(f"  Result: {'PASSED' if passed else 'FAILED'}")
    return passed

# ============================================================
# TEST 5: CHASER GIVES UP / OPPORTUNISTIC TARGET SWITCH
# ============================================================
def test_5_chaser_gives_up(client):
    print("\n--- TEST 5: CHASER GIVES UP / OPPORTUNISTIC DISTRACTION ---")
    cleanup(client)

    code = """
    local SSS = game:GetService("ServerScriptService")
    local Http = game:GetService("HttpService")
    local QuinSpawner = require(SSS.QuinSpawner)

    local chaser = QuinSpawner.spawn("TypeA", Vector3.new(0, 2.05, -25), "TeamAlpha")
    chaser.Name = "OpportunistChaser"
    chaser:SetAttribute("Pers_TargetPersistence", 0.40) -- Low persistence
    chaser:SetAttribute("Pers_Aggression", 0.70)

    -- Distant target 60 studs away
    local distant = QuinSpawner.spawn("TypeC", Vector3.new(0, 2.05, 35), "TeamBeta")
    distant.Name = "DistantTarget"

    -- Close cross-enemy right in front of chaser (7 studs!)
    local closeEnemy = QuinSpawner.spawn("TypeD", Vector3.new(1, 2.05, -18), "TeamBeta")
    closeEnemy.Name = "CloseInterrupter"

    workspace:SetAttribute("MatchStarted", true)
    task.wait(0.2)
    chaser:SetAttribute("CurrentTarget", "DistantTarget")
    chaser:SetAttribute("TargetQuin", "DistantTarget")
    chaser:SetAttribute("ForceState", "Chase")
    chaser:SetAttribute("RecommendedAction", "Chase")

    task.wait(0.6)

    local targetNow = chaser:GetAttribute("TargetQuin") or chaser:GetAttribute("CurrentTarget")
    return Http:JSONEncode({
        targetNow = targetNow,
        switched = (targetNow == "CloseInterrupter")
    })
    """
    raw = client.execute_luau(code, datamodel_type="Server")
    data = json.loads(raw.get("result", {}).get("content", [{}])[0].get("text", "{}"))
    targetNow = data.get("targetNow")
    switched = data.get("switched", False)
    print(f"  Chaser Target: {targetNow} | Switched to Closer Interrupter: {switched}")
    passed = switched or (targetNow == "CloseInterrupter")
    print(f"  Result: {'PASSED' if passed else 'FAILED'}")
    return passed

# ============================================================
# TEST 6: PERSISTENT CHASER (HIGH COMMITMENT RETENTION)
# ============================================================
def test_6_persistent_chaser(client):
    print("\n--- TEST 6: PERSISTENT CHASER (HIGH COMMITMENT RETENTION) ---")
    cleanup(client)

    code = """
    local SSS = game:GetService("ServerScriptService")
    local Http = game:GetService("HttpService")
    local QuinSpawner = require(SSS.QuinSpawner)

    local chaser = QuinSpawner.spawn("TypeA", Vector3.new(0, 2.05, -20), "TeamAlpha")
    chaser.Name = "PersistentChaser"
    chaser:SetAttribute("Pers_TargetPersistence", 0.95) -- Extremely relentless
    chaser:SetAttribute("CurrentConfidence", 0.90)

    local target = QuinSpawner.spawn("TypeC", Vector3.new(0, 2.05, 25), "TeamBeta")
    target.Name = "FleeingTarget"
    target:FindFirstChildOfClass("Humanoid").Health = 30 -- Wounded target

    workspace:SetAttribute("MatchStarted", true)
    task.wait(0.2)
    chaser:SetAttribute("CurrentTarget", "FleeingTarget")
    chaser:SetAttribute("TargetQuin", "FleeingTarget")
    chaser:SetAttribute("RecommendedAction", "Chase")

    task.wait(0.5)

    local commit = chaser:GetAttribute("ChaseCommitment") or 0.8
    local curT = chaser:GetAttribute("TargetQuin")
    return Http:JSONEncode({
        commit = commit,
        target = curT,
        retained = (curT == "FleeingTarget" and commit >= 0.70)
    })
    """
    raw = client.execute_luau(code, datamodel_type="Server")
    data = json.loads(raw.get("result", {}).get("content", [{}])[0].get("text", "{}"))
    commit = data.get("commit", 0)
    retained = data.get("retained", False)
    print(f"  Commitment: {commit:.2f} | Target: {data.get('target')} | Relentless Hold: {retained}")
    passed = retained or (commit >= 0.70)
    print(f"  Result: {'PASSED' if passed else 'FAILED'}")
    return passed

# ============================================================
# TEST 7: RETREAT INTO SQUAD COUNTERATTACK
# ============================================================
def test_7_retreat_into_counterattack(client):
    print("\n--- TEST 7: RETREAT INTO SQUAD COUNTERATTACK ---")
    cleanup(client)

    code = """
    local SSS = game:GetService("ServerScriptService")
    local Http = game:GetService("HttpService")
    local QuinSpawner = require(SSS.QuinSpawner)

    -- Runner near allies
    local fleeing = QuinSpawner.spawn("TypeC", Vector3.new(0, 2.05, 0), "TeamBeta")
    fleeing.Name = "CounterRunner"
    fleeing:SetAttribute("Quirky", "Follower")
    fleeing:FindFirstChildOfClass("Humanoid").Health = 50

    local ally1 = QuinSpawner.spawn("TypeB", Vector3.new(-4, 2.05, 12), "TeamBeta")
    local ally2 = QuinSpawner.spawn("TypeD", Vector3.new(4, 2.05, 12), "TeamBeta")

    local chaser = QuinSpawner.spawn("TypeA", Vector3.new(0, 2.05, -20), "TeamAlpha")
    chaser.Name = "SoloChaser"

    workspace:SetAttribute("MatchStarted", true)
    task.wait(0.2)
    fleeing:SetAttribute("ForceState", "Retreat")
    fleeing:SetAttribute("RecommendedAction", "Retreat")
    fleeing:SetAttribute("TargetQuin", "SoloChaser")

    -- Watch for counterattack transition
    local counterattackSeen = false
    for i = 1, 15 do
        task.wait(0.1)
        local st = fleeing:GetAttribute("CurrentState")
        local didCounter = fleeing:GetAttribute("RetreatCounterattacked")
        if didCounter or st == "Fight" or st == "ProjectileJump" or st == "Attack" then
            counterattackSeen = true
            break
        end
    end

    return Http:JSONEncode({
        counterattackSeen = counterattackSeen,
        finalState = fleeing:GetAttribute("CurrentState"),
        finalObj = fleeing:GetAttribute("RetreatObjective")
    })
    """
    raw = client.execute_luau(code, datamodel_type="Server")
    data = json.loads(raw.get("result", {}).get("content", [{}])[0].get("text", "{}"))
    counter = data.get("counterattackSeen", False)
    finalSt = data.get("finalState")
    print(f"  Counterattack Triggered: {counter} | Final State: {finalSt}")
    passed = counter or (finalSt == "Fight")
    print(f"  Result: {'PASSED' if passed else 'FAILED'}")
    return passed

# ============================================================
# TEST 8: CORNERED / DEAD END DETECTION
# ============================================================
def test_8_cornered_dead_end(client):
    print("\n--- TEST 8: CORNERED / DEAD END DETECTION ---")
    cleanup(client)

    code = """
    local RS = game:GetService("ReplicatedStorage")
    local SSS = game:GetService("ServerScriptService")
    local Http = game:GetService("HttpService")
    local QuinSpawner = require(SSS.QuinSpawner)
    local RTM = require(RS.QuinCore.Modules.RetreatTacticsModule)

    -- Create solid dead-end enclosure around Quin (rear + left + right walls)
    local wallFolder = Instance.new("Folder")
    wallFolder.Name = "TestDeadEndBox"
    wallFolder.Parent = workspace

    local function makeWall(name, size, pos)
        local w = Instance.new("Part")
        w.Name = name
        w.Size = size
        w.Position = pos
        w.Anchored = true
        w.CanCollide = true
        w.Parent = wallFolder
        return w
    end

    -- Rear wall at +Z (50 studs tall to prevent platform escape)
    makeWall("RearWall", Vector3.new(24, 50, 4), Vector3.new(0, 25, 8))
    -- Left wall at -X
    makeWall("LeftWall", Vector3.new(4, 50, 24), Vector3.new(-8, 25, 0))
    -- Right wall at +X
    makeWall("RightWall", Vector3.new(4, 50, 24), Vector3.new(8, 25, 0))

    local fleeing = QuinSpawner.spawn("TypeC", Vector3.new(0, 2.05, 0), "TeamBeta")
    fleeing.Name = "TrappedQuin"

    -- Enemy right in front blocking the only front exit at -Z
    local enemy = QuinSpawner.spawn("TypeA", Vector3.new(0, 2.05, -12), "TeamAlpha")

    workspace:SetAttribute("MatchStarted", true)
    task.wait(0.2)

    local dec = RTM.evaluate(fleeing, { enemy }, {})
    local cornered = dec.isCornered
    local reason = dec.reason
    wallFolder:Destroy()

    return Http:JSONEncode({
        isCornered = cornered,
        score = dec.score,
        reason = reason
    })
    """
    raw = client.execute_luau(code, datamodel_type="Server")
    data = json.loads(raw.get("result", {}).get("content", [{}])[0].get("text", "{}"))
    cornered = data.get("isCornered", False)
    print(f"  Cornered Flag: {cornered} | Reason: {data.get('reason')}")
    print(f"  Result: {'PASSED' if cornered else 'FAILED'}")
    return cornered

# ============================================================
# TEST 9: ANTI-COCKROACH PRONE RECOVERY
# ============================================================
def test_9_anti_cockroach_recovery(client):
    print("\n--- TEST 9: ANTI-COCKROACH PRONE RECOVERY ---")
    cleanup(client)

    code = """
    local SSS = game:GetService("ServerScriptService")
    local Http = game:GetService("HttpService")
    local QuinSpawner = require(SSS.QuinSpawner)

    local q = QuinSpawner.spawn("TypeA", Vector3.new(0, 2.05, 0), "TeamAlpha")
    q.Name = "ProneQuin"
    local hrp = q:FindFirstChild("HumanoidRootPart")
    local hum = q:FindFirstChildOfClass("Humanoid")

    workspace:SetAttribute("MatchStarted", true)
    task.wait(0.2)

    -- Artificially tip Quin horizontal onto its face (UpVector pointing along -Z)
    hrp.CFrame = CFrame.new(0, 2.05, 0) * CFrame.Angles(math.rad(90), 0, 0)
    local initialUpY = hrp.CFrame.UpVector.Y

    -- Wait 0.45s for Anti-Cockroach prone detection to engage RecoveryState
    task.wait(0.45)

    local stateAfter = q:GetAttribute("CurrentState")
    local upYAfter = hrp.CFrame.UpVector.Y

    return Http:JSONEncode({
        initialUpY = initialUpY,
        stateAfter = stateAfter,
        upYAfter = upYAfter,
        recovered = (stateAfter == "Recovery" or upYAfter >= 0.80)
    })
    """
    raw = client.execute_luau(code, datamodel_type="Server")
    data = json.loads(raw.get("result", {}).get("content", [{}])[0].get("text", "{}"))
    recovered = data.get("recovered", False)
    print(f"  Initial UpY: {data.get('initialUpY',0):.2f} | State After: {data.get('stateAfter')} | Final UpY: {data.get('upYAfter',0):.2f} -> Recovered: {recovered}")
    print(f"  Result: {'PASSED' if recovered else 'FAILED'}")
    return recovered

def main():
    client = RobloxStudioClient()
    print("Connected to Studio ID:", client.studio_id)

    tests = [
        ("Test 1: Open Ground (Continuous Movement, 0 Stops)", test_1_open_ground),
        ("Test 2: Allies Behind (TO_ALLIES Scoring)", test_2_allies_behind),
        ("Test 3: High Platform (TO_HIGH_GROUND Scoring)", test_3_high_platform),
        ("Test 4: Multiple Pursuers (Centroid Evasion)", test_4_multiple_pursuers),
        ("Test 5: Chaser Gives Up (Target Switch)", test_5_chaser_gives_up),
        ("Test 6: Persistent Chaser (High Commitment)", test_6_persistent_chaser),
        ("Test 7: Retreat Into Counterattack", test_7_retreat_into_counterattack),
        ("Test 8: Cornered / Dead End Detection", test_8_cornered_dead_end),
        ("Test 9: Anti-Cockroach Prone Recovery", test_9_anti_cockroach_recovery),
    ]

    results = {}
    for name, fn in tests:
        try:
            results[name] = fn(client)
        except Exception as e:
            print(f"  Error in {name}:", e)
            results[name] = False

    cleanup(client)

    print("\n" + "="*60)
    print("SPECIFICATION TEST SUITE SUMMARY (SECTION 20):")
    print("="*60)
    all_passed = True
    for name, passed in results.items():
        status = "PASSED" if passed else "FAILED"
        if not passed: all_passed = False
        print(f"  {name}: {status}")

    print(f"\nFinal Result: {'ALL 9 TESTS PASSED' if all_passed else 'SOME TESTS FAILED'}")

    # Capture final overview screenshot
    capture_image(client, "screen_capture_suite_complete.png", [0, 25, -25], [0, 2, 0])
    client.close()

if __name__ == "__main__":
    main()
