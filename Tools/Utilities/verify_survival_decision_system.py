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
    workspace:SetAttribute("MatchStarted", false)
    local SSS = game:GetService("ServerScriptService")
    local QuinSpawner = require(SSS.QuinSpawner)
    QuinSpawner.cleanAll()
    local p = workspace:FindFirstChild("TestVantagePlatform")
    if p then p:Destroy() end
    local w = workspace:FindFirstChild("TestDeadEndWall")
    if w then w:Destroy() end
    local o = workspace:FindFirstChild("TestObstacle")
    if o then o:Destroy() end
    local b = workspace:FindFirstChild("TestDeadEndBox")
    if b then b:Destroy() end
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
# SCENARIO 1: SOLE SURVIVOR REFUSES SUICIDAL ESCAPE -> LAST STAND
# ============================================================
def test_1_sole_survivor_last_stand(client):
    print("\n--- SCENARIO 1: SOLE SURVIVOR LAST STAND (REFUSES SUICIDAL ESCAPE) ---")
    cleanup(client)

    setup = """
    local SSS = game:GetService("ServerScriptService")
    local RS = game:GetService("ReplicatedStorage")
    local Http = game:GetService("HttpService")
    local QuinSpawner = require(SSS.QuinSpawner)
    local TacticalPerception = require(RS.QuinCore.Modules.TacticalPerception)
    local DecisionSystem = require(RS.QuinCore.Modules.DecisionSystem)

    -- Sole surviving Beta Quin, low HP (20/100)
    local survivor = QuinSpawner.spawn("TypeC", Vector3.new(0, 2.05, 0), "TeamBeta")
    survivor.Name = "SurvivorBeta"
    local hum = survivor:FindFirstChildOfClass("Humanoid")
    hum.Health = 20

    -- 3 surrounding Alpha pursuers in close range (15-20 studs)
    local a1 = QuinSpawner.spawn("TypeA", Vector3.new(-12, 2.05, -10), "TeamAlpha")
    a1.Name = "Alpha1"
    local a2 = QuinSpawner.spawn("TypeB", Vector3.new(12, 2.05, -10), "TeamAlpha")
    a2.Name = "Alpha2"
    local a3 = QuinSpawner.spawn("TypeD", Vector3.new(0, 2.05, -18), "TeamAlpha")
    a3.Name = "Alpha3"

    task.wait(0.05)

    -- Run Tactical Perception and Decision Evaluation
    local pState = TacticalPerception.evaluate(survivor)
    local dAction, _, dScores = DecisionSystem.evaluateAction(survivor, pState, 15)

    return Http:JSONEncode({
        feasibility = pState.EscapeFeasibility,
        lifeValue = pState.BattleLifeValue,
        isSoleSurvivor = pState.IsSoleSurvivor,
        lastStandMode = survivor:GetAttribute("LastStandMode"),
        desperateCounter = survivor:GetAttribute("DesperateCounter"),
        chosenAction = dAction,
        retreatScore = dScores["Retreat"] or 0,
        attackScore = dScores["Attack"] or 0,
        livingAllies = pState.TotalLivingAllies,
        livingEnemies = pState.TotalLivingEnemies,
    })
    """
    raw = client.execute_luau(setup, datamodel_type="Server")
    data = json.loads(raw.get("result", {}).get("content", [{}])[0].get("text", "{}"))

    feas = data.get("feasibility", 1.0)
    last_stand = data.get("lastStandMode", False)
    retreat_score = data.get("retreatScore", 999)
    action = data.get("chosenAction", "")
    attack_score = data.get("attackScore", 0)

    print(f"  Escape Feasibility: {feas:.2f} (Threshold: 0.20)")
    print(f"  Sole Survivor: {data.get('isSoleSurvivor')} (Allies: {data.get('livingAllies')}, Enemies: {data.get('livingEnemies')})")
    print(f"  Last Stand Mode: {last_stand} | Desperate Counter: {data.get('desperateCounter')}")
    print(f"  Chosen Action: {action} (Retreat Score: {retreat_score}, Attack Score: {attack_score:.1f})")

    # In a suicidal 1v3 situation, escape must be rejected, LastStandMode activated, and Retreat suppressed to 0
    passed = (feas < 0.20) and (last_stand == True) and (retreat_score == 0) and (action != "Retreat")
    print(f"  Result: {'PASSED' if passed else 'FAILED'}")
    return passed

# ============================================================
# SCENARIO 2: VIABLE ESCAPE WITH LIVING ALLIES & HAVEN ACCESS
# ============================================================
def test_2_viable_escape_with_allies(client):
    print("\n--- SCENARIO 2: VIABLE ESCAPE WITH LIVING ALLIES ---")
    cleanup(client)

    setup = """
    local SSS = game:GetService("ServerScriptService")
    local RS = game:GetService("ReplicatedStorage")
    local Http = game:GetService("HttpService")
    local QuinSpawner = require(SSS.QuinSpawner)
    local TacticalPerception = require(RS.QuinCore.Modules.TacticalPerception)
    local DecisionSystem = require(RS.QuinCore.Modules.DecisionSystem)

    -- Beta Quin with damaged health (35/100) and high retreat tendency
    local runner = QuinSpawner.spawn("TypeC", Vector3.new(0, 2.05, 0), "TeamBeta")
    runner.Name = "ViableRunner"
    local hum = runner:FindFirstChildOfClass("Humanoid")
    hum.Health = 25
    runner:SetAttribute("Pers_RetreatTendency", 0.90)

    -- 2 healthy allies nearby (30 studs behind at +Z)
    local ally1 = QuinSpawner.spawn("TypeA", Vector3.new(-8, 2.05, 30), "TeamBeta")
    ally1.Name = "BetaAlly1"
    local ally2 = QuinSpawner.spawn("TypeB", Vector3.new(8, 2.05, 30), "TeamBeta")
    ally2.Name = "BetaAlly2"

    -- 1 solitary pursuer in front at -Z (35 studs away)
    local chaser = QuinSpawner.spawn("TypeD", Vector3.new(0, 2.05, -35), "TeamAlpha")
    chaser.Name = "LoneChaser"
    hum.Health = 25
    local pState = TacticalPerception.evaluate(runner)
    local dAction, _, dScores = DecisionSystem.evaluateAction(runner, pState, 35)

    return Http:JSONEncode({
        feasibility = pState.EscapeFeasibility,
        isSoleSurvivor = pState.IsSoleSurvivor,
        lastStandMode = runner:GetAttribute("LastStandMode") or false,
        chosenAction = dAction,
        retreatScore = dScores["Retreat"] or 0,
        livingAllies = pState.TotalLivingAllies,
        livingEnemies = pState.TotalLivingEnemies,
    })
    """
    raw = client.execute_luau(setup, datamodel_type="Server")
    data = json.loads(raw.get("result", {}).get("content", [{}])[0].get("text", "{}"))

    feas = data.get("feasibility", 0)
    last_stand = data.get("lastStandMode", False)
    retreat_score = data.get("retreatScore", 0)
    action = data.get("chosenAction", "")

    print(f"  Escape Feasibility: {feas:.2f} (Expected > 0.40)")
    print(f"  Living Allies: {data.get('livingAllies')} | Enemies: {data.get('livingEnemies')}")
    print(f"  Last Stand Active: {last_stand} | Retreat Score: {retreat_score:.1f} | Action: {action}")

    passed = (feas >= 0.40) and (not last_stand) and (action == "Retreat" or retreat_score > 30)
    print(f"  Result: {'PASSED' if passed else 'FAILED'}")
    return passed

# ============================================================
# SCENARIO 3: GEOMETRIC JUKE CUT (LATERAL OVERSHOOT VECTOR)
# ============================================================
def test_3_geometric_juke_cut(client):
    print("\n--- SCENARIO 3: GEOMETRIC JUKE CUT (LATERAL OVERSHOOT VECTOR) ---")
    cleanup(client)

    setup = """
    local SSS = game:GetService("ServerScriptService")
    local RS = game:GetService("ReplicatedStorage")
    local Http = game:GetService("HttpService")
    local QuinSpawner = require(SSS.QuinSpawner)
    local RTM = require(RS.QuinCore.Modules.RetreatTacticsModule)

    -- Fleeing Quin facing +Z
    local runner = QuinSpawner.spawn("TypeC", Vector3.new(0, 2.05, 0), "TeamBeta")
    runner.Name = "JukingRunner"
    local rHRP = runner.HumanoidRootPart

    -- Pursuer placed 10 studs directly behind (-Z)
    local chaser = QuinSpawner.spawn("TypeA", Vector3.new(0, 2.05, -10), "TeamAlpha")
    chaser.Name = "RapidChaser"
    local cHRP = chaser.HumanoidRootPart

    task.wait(0.05)

    -- Apply precise velocities right at evaluation moment
    rHRP.CFrame = CFrame.lookAt(Vector3.new(0, 2.05, 0), Vector3.new(0, 2.05, 10))
    rHRP.AssemblyLinearVelocity = Vector3.new(0, 0, 15) -- Running forward +Z
    cHRP.CFrame = CFrame.lookAt(Vector3.new(0, 2.05, -10), Vector3.new(0, 2.05, 0))
    cHRP.AssemblyLinearVelocity = Vector3.new(0, 0, 32) -- Closing speed = 32 - 15 = 17 studs/s!

    local eval = RTM.evaluate(runner, { chaser }, {})

    return Http:JSONEncode({
        isJuking = eval.isJuking,
        maneuver = eval.maneuver,
        phase = eval.distanceThreatPhase,
        closingSpeed = eval.closingSpeed,
        dist = eval.nearestEnemyDist,
        steerX = eval.steerDirection.X,
        steerZ = eval.steerDirection.Z,
        jukeType = runner:GetAttribute("JukeType"),
    })
    """
    raw = client.execute_luau(setup, datamodel_type="Server")
    data = json.loads(raw.get("result", {}).get("content", [{}])[0].get("text", "{}"))

    is_juking = data.get("isJuking", False)
    maneuver = data.get("maneuver", "")
    phase = data.get("phase", "")
    steer_x = abs(data.get("steerX", 0))
    closing_spd = data.get("closingSpeed", 0)

    print(f"  Distance: {data.get('dist', 0):.1f} studs | Closing Speed: {closing_spd:.1f} studs/s")
    print(f"  Threat Phase: {phase} | Maneuver: {maneuver}")
    print(f"  Is Juking: {is_juking} | Juke Side: {data.get('jukeType')} | Steer Lateral |X|: {steer_x:.2f}")

    # Juke must trigger when closing rapidly behind <= 14 studs, steering laterally (|X| > 0.7)
    passed = (is_juking == True) and (maneuver == "JUKE_CUT") and (steer_x > 0.70)
    print(f"  Result: {'PASSED' if passed else 'FAILED'}")
    return passed

# ============================================================
# SCENARIO 4: PREDICTIVE CHASER LEAD INTERCEPTION
# ============================================================
def test_4_predictive_interception(client):
    print("\n--- SCENARIO 4: PREDICTIVE CHASER LEAD INTERCEPTION ---")
    cleanup(client)

    setup = """
    local SSS = game:GetService("ServerScriptService")
    local RS = game:GetService("ReplicatedStorage")
    local Http = game:GetService("HttpService")
    local QuinSpawner = require(SSS.QuinSpawner)
    local ChaseState = require(RS.QuinCore.States.ChaseState)

    -- Runner translating rapidly along +X axis at 30 studs/s
    local runner = QuinSpawner.spawn("TypeC", Vector3.new(0, 2.05, 0), "TeamBeta")
    runner.Name = "CrossRunner"
    local rHRP = runner.HumanoidRootPart
    rHRP.AssemblyLinearVelocity = Vector3.new(30, 0, 0)

    -- Chaser at (0, 2.05, -30) in ChaseState chasing CrossRunner
    local chaser = QuinSpawner.spawn("TypeA", Vector3.new(0, 2.05, -30), "TeamAlpha")
    chaser.Name = "LeadChaser"
    local cHum = chaser:FindFirstChildOfClass("Humanoid")
    cHum.WalkSpeed = 26
    chaser:SetAttribute("CurrentTarget", "CrossRunner")
    chaser:SetAttribute("TargetQuin", "CrossRunner")
    ChaseState.enter(chaser, cHum, chaser.HumanoidRootPart)
    cHum.WalkSpeed = 26 -- maintain speed above 5.0 threshold
    rHRP.AssemblyLinearVelocity = Vector3.new(30, 0, 0)
    ChaseState.update(chaser, cHum, chaser.HumanoidRootPart)

    local leadTime = chaser:GetAttribute("InterceptionLeadTime") or 0

    return Http:JSONEncode({
        leadTime = leadTime,
        targetVel = { rHRP.AssemblyLinearVelocity.X, rHRP.AssemblyLinearVelocity.Y, rHRP.AssemblyLinearVelocity.Z },
    })
    """
    raw = client.execute_luau(setup, datamodel_type="Server")
    data = json.loads(raw.get("result", {}).get("content", [{}])[0].get("text", "{}"))

    lead = data.get("leadTime", 0)
    print(f"  Target Velocity: {data.get('targetVel')} | Calculated Lead Time: {lead:.2f}s")

    # Predictive interception must compute a positive lead time (> 0.2s) to cut angles
    passed = (lead >= 0.20)
    print(f"  Result: {'PASSED' if passed else 'FAILED'}")
    return passed

# ============================================================
# SCENARIO 5: DYNAMIC COUNTERATTACK ON PURSUER WHIFF / OVEREXTENSION
# ============================================================
def test_5_counterattack_on_whiff(client):
    print("\n--- SCENARIO 5: COUNTERATTACK ON PURSUER WHIFF / OVEREXTENSION ---")
    cleanup(client)

    setup = """
    local SSS = game:GetService("ServerScriptService")
    local RS = game:GetService("ReplicatedStorage")
    local Http = game:GetService("HttpService")
    local QuinSpawner = require(SSS.QuinSpawner)
    local RetreatState = require(RS.QuinCore.States.RetreatState)

    -- Runner in RetreatState
    local runner = QuinSpawner.spawn("TypeC", Vector3.new(0, 2.05, 0), "TeamBeta")
    runner.Name = "WhiffCounterRunner"
    RetreatState.enter(runner, runner.Humanoid, runner.HumanoidRootPart)

    -- Pursuer in close range (7 studs away) with whiffed attack (Attacking=true, windup expired)
    local pursuer = QuinSpawner.spawn("TypeA", Vector3.new(0, 2.05, -7), "TeamAlpha")
    pursuer.Name = "WhiffingPursuer"
    pursuer:SetAttribute("Attacking", true)
    pursuer:SetAttribute("AttackWindupUntil", tick() - 0.1) -- Expired / whiffed

    task.wait(0.35)

    local nextState = RetreatState.update(runner, runner.Humanoid, runner.HumanoidRootPart)

    return Http:JSONEncode({
        nextStateName = nextState and nextState.name or "None",
        counterattacked = runner:GetAttribute("RetreatCounterattacked") or false,
        currentTarget = runner:GetAttribute("CurrentTarget") or "",
    })
    """
    raw = client.execute_luau(setup, datamodel_type="Server")
    data = json.loads(raw.get("result", {}).get("content", [{}])[0].get("text", "{}"))

    state = data.get("nextStateName", "")
    countered = data.get("counterattacked", False)
    target = data.get("currentTarget", "")

    print(f"  Next State: {state} | Counterattack Flag: {countered} | Target: {target}")

    # Runner must immediately seize the whiffed attack and transition into FightState
    passed = (state == "Fight") and (countered == True) and (target == "WhiffingPursuer")
    print(f"  Result: {'PASSED' if passed else 'FAILED'}")
    return passed

# ============================================================
# SCENARIO 6: DEFEND & DELAY FOR APPROACHING REINFORCING ALLY
# ============================================================
def test_6_defend_and_delay_reinforcement(client):
    print("\n--- SCENARIO 6: DEFEND & DELAY FOR APPROACHING ALLY ---")
    cleanup(client)

    setup = """
    local SSS = game:GetService("ServerScriptService")
    local RS = game:GetService("ReplicatedStorage")
    local Http = game:GetService("HttpService")
    local QuinSpawner = require(SSS.QuinSpawner)
    local RetreatState = require(RS.QuinCore.States.RetreatState)
    local TacticalPerception = require(RS.QuinCore.Modules.TacticalPerception)

    local runner = QuinSpawner.spawn("TypeC", Vector3.new(0, 2.05, 0), "TeamBeta")
    runner.Name = "DelayRunner"
    RetreatState.enter(runner, runner.Humanoid, runner.HumanoidRootPart)

    -- Approaching ally closing in (22 studs away, moving toward runner at 25 studs/s)
    local ally = QuinSpawner.spawn("TypeB", Vector3.new(0, 2.05, 22), "TeamBeta")
    ally.Name = "ReinforcingAlly"

    -- Solitary pursuer 18 studs behind runner
    local pursuer = QuinSpawner.spawn("TypeA", Vector3.new(0, 2.05, -18), "TeamAlpha")
    pursuer.Name = "ThreatAlpha"

    task.wait(0.25)

    -- Set ally velocity toward runner right at evaluation moment
    ally.HumanoidRootPart.AssemblyLinearVelocity = Vector3.new(0, 0, -25)

    -- Tactical Perception detects approaching reinforcement
    local pState = TacticalPerception.evaluate(runner)
    local nextState = RetreatState.update(runner, runner.Humanoid, runner.HumanoidRootPart)

    return Http:JSONEncode({
        reinforcing = runner:GetAttribute("ReinforcingAllyApproaching") or false,
        isGuarding = runner:GetAttribute("IsGuarding") or false,
        nextStateName = nextState and nextState.name or "None",
    })
    """
    raw = client.execute_luau(setup, datamodel_type="Server")
    data = json.loads(raw.get("result", {}).get("content", [{}])[0].get("text", "{}"))

    reinf = data.get("reinforcing", False)
    guard = data.get("isGuarding", False)
    state = data.get("nextStateName", "")

    print(f"  Reinforcing Ally Detected: {reinf} | Guard Raised: {guard} | State: {state}")

    passed = (reinf == True) and (guard == True) and (state == "Circling")
    print(f"  Result: {'PASSED' if passed else 'FAILED'}")
    return passed

# ============================================================
# SCENARIO 7: CONTINUOUS 600-STUD ARENA EVASION (ZERO STOP-AND-GO)
# ============================================================
def test_7_continuous_arena_evasion(client):
    print("\n--- SCENARIO 7: CONTINUOUS 600-STUD ARENA EVASION ---")
    cleanup(client)

    setup = """
    local SSS = game:GetService("ServerScriptService")
    local RS = game:GetService("ReplicatedStorage")
    local QuinSpawner = require(SSS.QuinSpawner)
    local RetreatState = require(RS.QuinCore.States.RetreatState)

    local runner = QuinSpawner.spawn("TypeC", Vector3.new(0, 2.05, -10), "TeamBeta")
    runner.Name = "ContinuousRunner"
    runner:FindFirstChildOfClass("Humanoid").Health = 35
    runner:SetAttribute("Pers_RetreatTendency", 0.95)

    local chaser = QuinSpawner.spawn("TypeA", Vector3.new(0, 2.05, -35), "TeamAlpha")
    chaser.Name = "PacingChaser"
    chaser:FindFirstChildOfClass("Humanoid").WalkSpeed = 22

    workspace:SetAttribute("MatchStarted", true)
    task.wait(0.2)
    runner:SetAttribute("ForceState", "Retreat")
    runner:SetAttribute("RecommendedAction", "Retreat")
    runner:SetAttribute("TargetQuin", "PacingChaser")
    return "Ready"
    """
    client.execute_luau(setup, datamodel_type="Server")
    time.sleep(0.4)

    zero_stops = 0
    samples = 0
    poll = """
    local Http = game:GetService("HttpService")
    local q = workspace:FindFirstChild("QuinServer") and workspace.QuinServer:FindFirstChild("ContinuousRunner")
    if not q then return Http:JSONEncode({err = "None"}) end
    local hrp = q:FindFirstChild("HumanoidRootPart")
    local hum = q:FindFirstChildOfClass("Humanoid")
    return Http:JSONEncode({
        st = q:GetAttribute("CurrentState"),
        spd = hrp and hrp.AssemblyLinearVelocity.Magnitude or 0,
        z = hrp and hrp.Position.Z or 0
    })
    """
    speeds = []
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
            speeds.append(spd)
            if st == "Retreat" and not has_exited:
                if spd < 1.0: zero_stops += 1
            elif st != "Retreat":
                has_exited = True
            if i % 5 == 0:
                print(f"  [Sample {i:02d}] State={st} | Speed={spd:.1f} studs/s | Z={z:.1f}")

    avg_spd = sum(speeds) / max(len(speeds), 1)
    net_disp = abs((last_z or 0) - (first_z or 0))
    print(f"  Samples: {samples} | Zero Stops: {zero_stops} | Avg Speed: {avg_spd:.1f} studs/s | Net Disp: {net_disp:.1f} studs")

    passed = (zero_stops == 0) and (net_disp > 20.0)
    print(f"  Result: {'PASSED' if passed else 'FAILED'}")
    return passed

# ============================================================
# SCENARIO 8: PERSONALITY BRANCHING (FOLLOWER VS EGOIST)
# ============================================================
def test_8_personality_branching(client):
    print("\n--- SCENARIO 8: PERSONALITY BRANCHING (FOLLOWER VS EGOIST) ---")
    cleanup(client)

    setup = """
    local SSS = game:GetService("ServerScriptService")
    local RS = game:GetService("ReplicatedStorage")
    local Http = game:GetService("HttpService")
    local QuinSpawner = require(SSS.QuinSpawner)
    local RTM = require(RS.QuinCore.Modules.RetreatTacticsModule)

    local follower = QuinSpawner.spawn("TypeC", Vector3.new(0, 2.05, 0), "TeamBeta")
    follower.Name = "FollowerQuin"
    follower:SetAttribute("Quirky", "Follower")

    local egoist = QuinSpawner.spawn("TypeC", Vector3.new(0, 2.05, 0), "TeamBeta")
    egoist.Name = "EgoistQuin"
    egoist:SetAttribute("Quirky", "Egoist")

    local ally = QuinSpawner.spawn("TypeA", Vector3.new(0, 2.05, 30), "TeamBeta")
    ally.Name = "SquadMate"

    local enemy = QuinSpawner.spawn("TypeB", Vector3.new(0, 2.05, -25), "TeamAlpha")
    enemy.Name = "Attacker"

    workspace:SetAttribute("MatchStarted", true)
    task.wait(0.2)

    local fEval = RTM.evaluate(follower, { enemy }, { ally })
    local eEval = RTM.evaluate(egoist, { enemy }, { ally })

    return Http:JSONEncode({
        followerAllyScore = fEval.candidateScores["TO_ALLIES"] or 0,
        egoistAllyScore = eEval.candidateScores["TO_ALLIES"] or 0,
        followerObj = fEval.objective,
        egoistObj = eEval.objective,
    })
    """
    raw = client.execute_luau(setup, datamodel_type="Server")
    data = json.loads(raw.get("result", {}).get("content", [{}])[0].get("text", "{}"))

    f_score = data.get("followerAllyScore", 0)
    e_score = data.get("egoistAllyScore", 0)
    diff = f_score - e_score

    print(f"  Follower TO_ALLIES Score: {f_score:.1f} (Objective: {data.get('followerObj')})")
    print(f"  Egoist TO_ALLIES Score: {e_score:.1f} (Objective: {data.get('egoistObj')})")
    print(f"  Score Difference: {diff:.1f} points")

    passed = (diff >= 40.0)
    print(f"  Result: {'PASSED' if passed else 'FAILED'}")
    return passed

# ============================================================
# MAIN SUITE RUNNER
# ============================================================
def main():
    client = RobloxStudioClient()
    print("Connected to Studio ID:", client.studio_id)

    results = {}
    results["Scenario 1: Sole Survivor Last Stand"] = test_1_sole_survivor_last_stand(client)
    results["Scenario 2: Viable Escape with Allies"] = test_2_viable_escape_with_allies(client)
    results["Scenario 3: Geometric Juke Cut"] = test_3_geometric_juke_cut(client)
    results["Scenario 4: Predictive Lead Interception"] = test_4_predictive_interception(client)
    results["Scenario 5: Dynamic Counterattack on Whiff"] = test_5_counterattack_on_whiff(client)
    results["Scenario 6: Defend & Delay for Ally"] = test_6_defend_and_delay_reinforcement(client)
    results["Scenario 7: Continuous Arena Evasion"] = test_7_continuous_arena_evasion(client)
    results["Scenario 8: Personality Branching"] = test_8_personality_branching(client)

    print("\n" + "=" * 60)
    print("TACTICAL SURVIVAL & EVALUATED ESCAPE SUITE SUMMARY:")
    print("=" * 60)
    all_passed = True
    for name, passed in results.items():
        status = "PASSED" if passed else "FAILED"
        print(f"  {name}: {status}")
        if not passed: all_passed = False

    print(f"\nFinal Result: {'ALL 8 SCENARIOS PASSED' if all_passed else 'SOME SCENARIOS FAILED'}")

    # Capture visual proof for artifacts
    capture_image(client, "screen_capture_survival_decision_verified.png",
                  [20, 18, -25],
                  [0, 2, 0])

    cleanup(client)
    return all_passed

if __name__ == "__main__":
    success = main()
    sys.exit(0 if success else 1)
