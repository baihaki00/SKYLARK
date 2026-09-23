import os
import sys
import time
import json

current_dir = os.path.dirname(os.path.abspath(__file__))
tools_dir = os.path.join(current_dir, "Tools", "Utilities")
if tools_dir not in sys.path:
    sys.path.insert(0, tools_dir)

try:
    sys.stdout.reconfigure(encoding='utf-8')
except Exception:
    pass

from roblox_client import RobloxStudioClient

def run_directional_awareness_tests():
    client = RobloxStudioClient()
    print("=== PHASE 2: DIRECTIONAL AWARENESS & 360 THREAT PERCEPTION ABLATION ===")
    print("Connected to Studio ID:", client.studio_id)

    # -------------------------------------------------------------
    # TEST 1: Directional Dot-Product & 4-Quadrant Classification
    # -------------------------------------------------------------
    print("\n--- TEST 1: Directional Dot-Product & Quadrant Classification ---")
    test1_code = """
    local sss = game:GetService("ServerScriptService")
    local rs = game:GetService("ReplicatedStorage")
    local QuinSpawner = require(sss:WaitForChild("QuinSpawner"))
    local TacticalPerception = require(rs.QuinCore.Modules.TacticalPerception)
    
    QuinSpawner.cleanAll()
    workspace:SetAttribute("MatchStarted", false)

    -- Spawn Observer facing -Z (LookVector = (0, 0, -1))
    local observer = QuinSpawner.spawn("TypeA", Vector3.new(0, 3, 0), "TeamAlpha")
    observer.Name = "Quin_Observer"
    observer.HumanoidRootPart.CFrame = CFrame.lookAt(Vector3.new(0, 3, 0), Vector3.new(0, 3, -10))

    -- Spawn Front enemy (0, 3, -14)
    local qFront = QuinSpawner.spawn("TypeB", Vector3.new(0, 3, -14), "TeamBeta")
    qFront.Name = "Enemy_Front"

    -- Spawn Right flank enemy (14, 3, 0)
    local qRight = QuinSpawner.spawn("TypeB", Vector3.new(14, 3, 0), "TeamBeta")
    qRight.Name = "Enemy_Right"

    -- Spawn Left flank enemy (-14, 3, 0)
    local qLeft = QuinSpawner.spawn("TypeB", Vector3.new(-14, 3, 0), "TeamBeta")
    qLeft.Name = "Enemy_Left"

    -- Spawn Rear enemy (0, 3, 14)
    local qRear = QuinSpawner.spawn("TypeB", Vector3.new(0, 3, 14), "TeamBeta")
    qRear.Name = "Enemy_Rear"

    task.wait(0.1)
    local ctx = TacticalPerception.evaluate(observer)
    
    local results = {
        frontCount = #ctx.FrontEnemies,
        flankRightCount = #ctx.FlankRightEnemies,
        flankLeftCount = #ctx.FlankLeftEnemies,
        rearCount = #ctx.RearEnemies,
        occupiedQuadrants = ctx.OccupiedQuadrants,
        surrounded = ctx.Surrounded,
        totalEnemies = ctx.EnemyCount,
    }
    
    local HttpService = game:GetService("HttpService")
    return HttpService:JSONEncode(results)
    """
    res1 = client.execute_luau(test1_code, datamodel_type="Server")
    t1_json = res1.get("result", {}).get("content", [{}])[0].get("text", "{}")
    print("Test 1 Result:", t1_json)
    data1 = json.loads(t1_json)
    assert data1["frontCount"] == 1, f"Expected 1 Front, got {data1['frontCount']}"
    assert data1["flankRightCount"] == 1, f"Expected 1 FlankRight, got {data1['flankRightCount']}"
    assert data1["flankLeftCount"] == 1, f"Expected 1 FlankLeft, got {data1['flankLeftCount']}"
    assert data1["rearCount"] == 1, f"Expected 1 Rear, got {data1['rearCount']}"
    assert data1["occupiedQuadrants"] == 4, f"Expected 4 quadrants, got {data1['occupiedQuadrants']}"
    assert data1["surrounded"] == True, f"Expected surrounded=True"
    print("✓ TEST 1 PASSED: 4 quadrants cleanly classified; surround invariant confirmed.")

    # -------------------------------------------------------------
    # TEST 2: Personality-Scaled Rear Threat Detection Monotonicity
    # -------------------------------------------------------------
    print("\n--- TEST 2: Personality-Scaled Rear Threat Detection Monotonicity ---")
    test2_code = """
    local sss = game:GetService("ServerScriptService")
    local rs = game:GetService("ReplicatedStorage")
    local QuinSpawner = require(sss:WaitForChild("QuinSpawner"))
    local TacticalPerception = require(rs.QuinCore.Modules.TacticalPerception)
    
    QuinSpawner.cleanAll()
    workspace:SetAttribute("MatchStarted", false)

    local observer = QuinSpawner.spawn("TypeC", Vector3.new(0, 3, 0), "TeamAlpha")
    observer.Name = "Quin_Observer"
    observer.HumanoidRootPart.CFrame = CFrame.lookAt(Vector3.new(0, 3, 0), Vector3.new(0, 3, -10))

    -- Place rear enemy at 18 studs behind (0, 3, 18)
    local qRear = QuinSpawner.spawn("TypeD", Vector3.new(0, 3, 18), "TeamBeta")
    qRear.Name = "Enemy_Rear"

    task.wait(0.1)

    -- Case A: High awareness (0.95) -> radius = 8 + 0.95*(22-8) = 21.3 studs -> SHOULD DETECT
    observer:SetAttribute("Pers_Awareness", 0.95)
    local ctxHigh = TacticalPerception.evaluate(observer)
    local highDetects = ctxHigh.IsUnderRearThreat

    -- Case B: Low awareness (0.35) -> radius = 8 + 0.35*(22-8) = 12.9 studs -> SHOULD NOT DETECT at 18 studs
    observer:SetAttribute("Pers_Awareness", 0.35)
    local ctxLowDistant = TacticalPerception.evaluate(observer)
    local lowDistantDetects = ctxLowDistant.IsUnderRearThreat

    -- Case C: Move rear enemy to 11 studs -> Low awareness SHOULD NOW DETECT
    qRear.HumanoidRootPart.CFrame = CFrame.new(0, 3, 11)
    task.wait(0.05)
    local ctxLowClose = TacticalPerception.evaluate(observer)
    local lowCloseDetects = ctxLowClose.IsUnderRearThreat

    local results = {
        highAt18Studs = highDetects,
        lowAt18Studs = lowDistantDetects,
        lowAt11Studs = lowCloseDetects,
        closestRearName = ctxLowClose.ClosestRearThreat and ctxLowClose.ClosestRearThreat.Name or "None"
    }

    local HttpService = game:GetService("HttpService")
    return HttpService:JSONEncode(results)
    """
    res2 = client.execute_luau(test2_code, datamodel_type="Server")
    t2_json = res2.get("result", {}).get("content", [{}])[0].get("text", "{}")
    print("Test 2 Result:", t2_json)
    data2 = json.loads(t2_json)
    assert data2["highAt18Studs"] == True, "High awareness should detect rear threat at 18 studs"
    assert data2["lowAt18Studs"] == False, "Low awareness should not detect rear threat at 18 studs"
    assert data2["lowAt11Studs"] == True, "Low awareness should detect rear threat at 11 studs"
    assert data2["closestRearName"] == "Enemy_Rear", "Closest rear threat should identify Enemy_Rear"
    print("✓ TEST 2 PASSED: Awareness monotonicity empirically confirmed.")

    # -------------------------------------------------------------
    # TEST 3: Multi-Opponent Focus & Bullying Detection
    # -------------------------------------------------------------
    print("\n--- TEST 3: Multi-Opponent Focus & Bullying Detection ---")
    test3_code = """
    local sss = game:GetService("ServerScriptService")
    local rs = game:GetService("ReplicatedStorage")
    local QuinSpawner = require(sss:WaitForChild("QuinSpawner"))
    local TacticalPerception = require(rs.QuinCore.Modules.TacticalPerception)
    
    QuinSpawner.cleanAll()
    workspace:SetAttribute("MatchStarted", false)

    local victim = QuinSpawner.spawn("TypeA", Vector3.new(0, 3, 0), "TeamAlpha")
    victim.Name = "Quin_Victim"

    local bully1 = QuinSpawner.spawn("TypeB", Vector3.new(10, 3, 0), "TeamBeta")
    bully1.Name = "Bully_1"
    bully1:SetAttribute("CurrentTarget", "Quin_Victim")

    local bully2 = QuinSpawner.spawn("TypeD", Vector3.new(-10, 3, 0), "TeamBeta")
    bully2.Name = "Bully_2"
    bully2:SetAttribute("CurrentTarget", "Quin_Victim")

    task.wait(0.1)
    local ctxBullied = TacticalPerception.evaluate(victim)
    local focusCount = ctxBullied.FocusCount
    local isBullied = ctxBullied.BeingBullied

    -- Move bully 2 out of focus range (> 40 studs)
    bully2.HumanoidRootPart.CFrame = CFrame.new(80, 3, 0)
    task.wait(0.05)
    local ctxSingle = TacticalPerception.evaluate(victim)

    local results = {
        focusCountWhen2 = focusCount,
        isBulliedWhen2 = isBullied,
        focusCountWhen1 = ctxSingle.FocusCount,
        isBulliedWhen1 = ctxSingle.BeingBullied
    }

    local HttpService = game:GetService("HttpService")
    return HttpService:JSONEncode(results)
    """
    res3 = client.execute_luau(test3_code, datamodel_type="Server")
    t3_json = res3.get("result", {}).get("content", [{}])[0].get("text", "{}")
    print("Test 3 Result:", t3_json)
    data3 = json.loads(t3_json)
    assert data3["focusCountWhen2"] == 2, f"Expected focusCount=2, got {data3['focusCountWhen2']}"
    assert data3["isBulliedWhen2"] == True, "Expected isBullied=True with 2 focusers"
    assert data3["focusCountWhen1"] == 1, f"Expected focusCount=1, got {data3['focusCountWhen1']}"
    assert data3["isBulliedWhen1"] == False, "Expected isBullied=False with 1 focuser"
    print("✓ TEST 3 PASSED: Bullying and focus detection confirmed.")

    # -------------------------------------------------------------
    # TEST 4: Combat Ambush Reaction (180 Turn Pivot & Counter)
    # -------------------------------------------------------------
    print("\n--- TEST 4: Combat Ambush Reaction (180 Turn Pivot & Counter) ---")
    test4_code = """
    local sss = game:GetService("ServerScriptService")
    local rs = game:GetService("ReplicatedStorage")
    local QuinSpawner = require(sss:WaitForChild("QuinSpawner"))
    local FightState = require(rs.QuinCore.States.FightState)
    local TacticalPerception = require(rs.QuinCore.Modules.TacticalPerception)
    
    QuinSpawner.cleanAll()
    workspace:SetAttribute("MatchStarted", false)

    -- Fighter facing -Z (0, 3, 0)
    local fighter = QuinSpawner.spawn("TypeA", Vector3.new(0, 3, 0), "TeamAlpha")
    fighter.Name = "Fighter_Quin"
    fighter.HumanoidRootPart.CFrame = CFrame.lookAt(Vector3.new(0, 3, 0), Vector3.new(0, 3, -10))
    fighter:SetAttribute("Pers_Awareness", 0.95)
    fighter:SetAttribute("Pers_DefensePreference", 0.3)

    -- Target in front (0, 3, -7)
    local targetFront = QuinSpawner.spawn("TypeB", Vector3.new(0, 3, -7), "TeamBeta")
    targetFront.Name = "Target_Front"
    fighter:SetAttribute("CurrentTarget", "Target_Front")
    fighter:SetAttribute("TargetQuin", "Target_Front")

    -- Ambusher sneaks up behind (0, 3, 8)
    local ambusher = QuinSpawner.spawn("TypeC", Vector3.new(0, 3, 8), "TeamBeta")
    ambusher.Name = "Ambusher_Rear"

    task.wait(0.1)
    TacticalPerception.evaluate(fighter)

    -- Run FightState update cycle
    local hum = fighter:FindFirstChildOfClass("Humanoid")
    local root = fighter:FindFirstChild("HumanoidRootPart")
    local nextState = FightState.update(fighter, hum, root, false)

    local finalTarget = fighter:GetAttribute("CurrentTarget")
    local newLook = root.CFrame.LookVector
    -- LookVector should now point toward +Z (toward Ambusher_Rear)
    local dotAmbusher = newLook:Dot(Vector3.new(0, 0, 1))

    local results = {
        isUnderRear = fighter:GetAttribute("IsUnderRearThreat"),
        closestRear = fighter:GetAttribute("ClosestRearThreat"),
        finalTarget = finalTarget,
        dotTowardAmbusher = dotAmbusher,
        isGuarding = fighter:GetAttribute("IsGuarding") or false
    }

    local HttpService = game:GetService("HttpService")
    return HttpService:JSONEncode(results)
    """
    res4 = client.execute_luau(test4_code, datamodel_type="Server")
    t4_json = res4.get("result", {}).get("content", [{}])[0].get("text", "{}")
    print("Test 4 Result:", t4_json)
    data4 = json.loads(t4_json)
    assert data4["isUnderRear"] == True, "Expected IsUnderRearThreat=True"
    assert data4["closestRear"] == "Ambusher_Rear", "Expected ClosestRearThreat=Ambusher_Rear"
    assert data4["finalTarget"] == "Ambusher_Rear", f"Expected target switched to Ambusher_Rear, got {data4['finalTarget']}"
    assert data4["dotTowardAmbusher"] > 0.85, f"Expected Quin to turn 180° toward ambusher, dot={data4['dotTowardAmbusher']}"
    print("✓ TEST 4 PASSED: 180° snap pivot, target retargeting, and counter reaction verified.")

    # -------------------------------------------------------------
    # TEST 5: Chase State Rear Threat Intercept
    # -------------------------------------------------------------
    print("\n--- TEST 5: Chase State Rear Threat Intercept ---")
    test5_code = """
    local sss = game:GetService("ServerScriptService")
    local rs = game:GetService("ReplicatedStorage")
    local QuinSpawner = require(sss:WaitForChild("QuinSpawner"))
    local ChaseState = require(rs.QuinCore.States.ChaseState)
    local TacticalPerception = require(rs.QuinCore.Modules.TacticalPerception)
    
    QuinSpawner.cleanAll()
    workspace:SetAttribute("MatchStarted", false)

    -- Chaser running toward distant target at -Z
    local chaser = QuinSpawner.spawn("TypeA", Vector3.new(0, 3, 0), "TeamAlpha")
    chaser.Name = "Chaser_Quin"
    chaser.HumanoidRootPart.CFrame = CFrame.lookAt(Vector3.new(0, 3, 0), Vector3.new(0, 3, -10))
    chaser:SetAttribute("Pers_Awareness", 0.90)

    local distantTarget = QuinSpawner.spawn("TypeB", Vector3.new(0, 3, -60), "TeamBeta")
    distantTarget.Name = "Target_Distant"
    chaser:SetAttribute("CurrentTarget", "Target_Distant")

    -- Pursuer closing in right behind at 7 studs (0, 3, 7)
    local rearPursuer = QuinSpawner.spawn("TypeC", Vector3.new(0, 3, 7), "TeamBeta")
    rearPursuer.Name = "Rear_Pursuer"

    task.wait(0.1)
    TacticalPerception.evaluate(chaser)

    local hum = chaser:FindFirstChildOfClass("Humanoid")
    local root = chaser:FindFirstChild("HumanoidRootPart")
    ChaseState.enter(chaser, hum, root)
    local nextState = ChaseState.update(chaser, hum, root, false)

    local finalTarget = chaser:GetAttribute("CurrentTarget")
    local dotPursuer = root.CFrame.LookVector:Dot(Vector3.new(0, 0, 1))

    local results = {
        returnedState = nextState and nextState.name or "None",
        finalTarget = finalTarget,
        dotTowardPursuer = dotPursuer
    }

    local HttpService = game:GetService("HttpService")
    return HttpService:JSONEncode(results)
    """
    res5 = client.execute_luau(test5_code, datamodel_type="Server")
    t5_json = res5.get("result", {}).get("content", [{}])[0].get("text", "{}")
    print("Test 5 Result:", t5_json)
    data5 = json.loads(t5_json)
    assert data5["returnedState"] == "Fight", f"Expected transition to Fight state, got {data5['returnedState']}"
    assert data5["finalTarget"] == "Rear_Pursuer", f"Expected retarget to Rear_Pursuer, got {data5['finalTarget']}"
    assert data5["dotTowardPursuer"] > 0.85, f"Expected 180 snap toward pursuer, dot={data5['dotTowardPursuer']}"
    print("✓ TEST 5 PASSED: ChaseState rear intercept transition and 180° snap verified.")

    # -------------------------------------------------------------
    # TEST 6: 16v16 Match Stability & Studio Log Health
    # -------------------------------------------------------------
    print("\n--- TEST 6: Live 16v16 Match Stability & Log Service Check ---")
    test6_code = """
    local LogService = game:GetService("LogService")
    LogService:ClearOutput()
    
    local sss = game:GetService("ServerScriptService")
    local QuinSpawner = require(sss:WaitForChild("QuinSpawner"))
    QuinSpawner.cleanAll()
    workspace:SetAttribute("MatchStarted", false)

    local alphaTypes = {}
    for i = 1, 16 do
        table.insert(alphaTypes, i % 2 == 0 and "TypeA" or "TypeC")
    end
    local betaTypes = {}
    for i = 1, 16 do
        table.insert(betaTypes, i % 2 == 0 and "TypeB" or "TypeD")
    end

    local positions = QuinSpawner.getSpawnPositions()
    local pos1 = positions[1] or Vector3.new(158, 2.05, -167)
    local pos2 = positions[2] or Vector3.new(-137, 2.05, 205)

    QuinSpawner.spawnTeam(alphaTypes, "TeamAlpha", 16, 1, pos2)
    task.wait(0.2)
    QuinSpawner.spawnTeam(betaTypes, "TeamBeta", 16, 2, pos1)
    workspace:SetAttribute("MatchStarted", true)
    
    return "16v16 match spawned successfully"
    """
    res6 = client.execute_luau(test6_code, datamodel_type="Server")
    print(res6.get("result", {}).get("content", [{}])[0].get("text", ""))

    print("Running 16v16 simulation for 10 seconds...")
    time.sleep(10)

    log_check_code = """
    local LogService = game:GetService("LogService")
    local logs = LogService:GetLogHistory()
    local errorCount = 0
    local errorList = {}
    for _, item in ipairs(logs) do
        if item.messageType == Enum.MessageType.MessageError then
            errorCount = errorCount + 1
            table.insert(errorList, item.message)
        end
    end
    
    local QuinSpawner = require(game:GetService("ServerScriptService"):WaitForChild("QuinSpawner"))
    local aliveAlpha = 0
    local aliveBeta = 0
    for _, quin in ipairs(game:GetService("CollectionService"):GetTagged("Quin")) do
        local hum = quin:FindFirstChildOfClass("Humanoid")
        if hum and hum.Health > 0 then
            local team = quin:GetAttribute("Team")
            if team == "TeamAlpha" then aliveAlpha = aliveAlpha + 1 end
            if team == "TeamBeta" then aliveBeta = aliveBeta + 1 end
        end
    end

    local HttpService = game:GetService("HttpService")
    return HttpService:JSONEncode({
        errorCount = errorCount,
        errorList = errorList,
        aliveAlpha = aliveAlpha,
        aliveBeta = aliveBeta,
        totalAlive = aliveAlpha + aliveBeta
    })
    """
    res_logs = client.execute_luau(log_check_code, datamodel_type="Server")
    log_json = res_logs.get("result", {}).get("content", [{}])[0].get("text", "{}")
    print("Log Service Result:", log_json)
    log_data = json.loads(log_json)
    assert log_data["errorCount"] == 0, f"Observed errors during 16v16 match: {log_data['errorList']}"
    print(f"✓ TEST 6 PASSED: 16v16 match healthy, active fighters={log_data['totalAlive']}, 0 runtime errors.")

    print("\n=================================================================")
    print("ALL 6 PHASE 2 ABLATION AND REGRESSION TESTS PASSED EMPIRICALLY!")
    print("=================================================================")
    client.close()

if __name__ == "__main__":
    run_directional_awareness_tests()
