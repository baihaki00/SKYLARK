import sys, os, json, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from roblox_client import RobloxStudioClient

client = RobloxStudioClient()

# 1. Clean and spawn 4v4
setup_code = """
local SSS = game:GetService("ServerScriptService")
local QuinSpawner = require(SSS:WaitForChild("QuinSpawner"))
local QuinRosterService = require(SSS:WaitForChild("QuinRosterService"))
QuinSpawner.clearAll()
QuinRosterService.clear()
task.wait(0.5)
QuinSpawner.spawnTeam({"TypeA", "TypeB", "TypeC", "TypeD"}, "TeamAlpha", 4, 1)
QuinSpawner.spawnTeam({"TypeA", "TypeB", "TypeC", "TypeD"}, "TeamBeta", 4, 2)
return "SPAWNED"
"""
client.execute_luau(setup_code, datamodel_type="Server")
print("Spawned 4v4 team battle. Monitoring every 1.5s...")

sample_code = """
local HttpService = game:GetService("HttpService")
local qs = workspace:FindFirstChild("QuinServer") or workspace
local results = {}
for _, q in ipairs(qs:GetChildren()) do
    local hum = q:FindFirstChildOfClass("Humanoid")
    local hrp = q:FindFirstChild("HumanoidRootPart")
    if hum and hrp and hum.Health > 0 then
        table.insert(results, {
            name = q.Name,
            team = q:GetAttribute("Team") or "None",
            state = q:GetAttribute("CurrentState") or "None",
            ws = math.round(hum.WalkSpeed*10)/10,
            spd = math.round(hrp.AssemblyLinearVelocity.Magnitude*10)/10,
            moveDir = math.round(hum.MoveDirection.Magnitude*100)/100,
            pos = {math.round(hrp.Position.X*10)/10, math.round(hrp.Position.Y*10)/10, math.round(hrp.Position.Z*10)/10},
            target = q:GetAttribute("CurrentTarget") or q:GetAttribute("TargetQuin") or "None",
            obs = q:GetAttribute("ObstacleAwareness") or "None",
        })
    end
end
return HttpService:JSONEncode(results)
"""

for i in range(7):
    time.sleep(1.5)
    res = client.execute_luau(sample_code, datamodel_type="Server")
    txt = res.get("result", {}).get("content", [{}])[0].get("text", "")
    try:
        data = json.loads(txt)
        print(f"\n--- SNAPSHOT t={(i+1)*1.5:.1f}s ({len(data)} fighters) ---")
        for d in data:
            print(f"  {d['name']} ({d['team']}): state={d['state']}, ws={d['ws']}, spd={d['spd']}, moveDir={d['moveDir']}, obs={d['obs']}, pos={d['pos']}")
    except Exception as e:
        print(f"Error parsing: {e}, raw: {txt}")

client.close()
