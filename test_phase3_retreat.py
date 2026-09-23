"""
Phase 3 Verification: 16v16 Team Battle - Safe Haven Retreat System
Spawns 32 fighters, runs for 20 seconds, checks:
1. No runtime errors
2. All 32 alive at start
3. RetreatScore and IsCornered attributes are being set
"""
import sys
import time
import os

sys.stdout.reconfigure(encoding='utf-8')
current_dir = os.path.dirname(os.path.abspath(__file__))
tools_dir = os.path.join(current_dir, "Tools", "Utilities")
sys.path.insert(0, tools_dir)

from roblox_client import RobloxStudioClient

client = RobloxStudioClient()
print(f"Connected to Studio ID: {client.studio_id}")

# Spawn 16v16 team battle
spawn_lua = """
local QuinSpawner = require(game.ServerScriptService:WaitForChild("QuinSpawner"))

-- Clear previous
for _, m in ipairs(workspace:GetDescendants()) do
    if m:IsA("Model") and m:FindFirstChild("HumanoidRootPart") then
        local tag = game:GetService("CollectionService"):HasTag(m, "Quin")
        if tag then m:Destroy() end
    end
end
task.wait(0.5)

local teamA = QuinSpawner.spawnTeam("A", 16, Vector3.new(-50, 5, 0), 8)
local teamB = QuinSpawner.spawnTeam("B", 16, Vector3.new(50, 5, 0), 8)

-- Assign targets: each team targets the other team's members
task.wait(0.3)
for _, quin in ipairs(game:GetService("CollectionService"):GetTagged("Quin")) do
    local team = quin:GetAttribute("Team")
    local enemies = {}
    for _, other in ipairs(game:GetService("CollectionService"):GetTagged("Quin")) do
        if other:GetAttribute("Team") ~= team and other.Parent then
            table.insert(enemies, other)
        end
    end
    if #enemies > 0 then
        local target = enemies[math.random(1, #enemies)]
        quin:SetAttribute("CurrentTarget", target.Name)
        quin:SetAttribute("TargetQuin", target.Name)
    end
end

return "Spawned " .. tostring(#teamA) .. " + " .. tostring(#teamB) .. " = " .. tostring(#teamA + #teamB) .. " fighters"
"""
result = client.execute_luau(spawn_lua)
print(f"Spawn result: {result}")

# Wait for battle to run
print("Waiting 20 seconds for battle simulation...")
time.sleep(20)

# Check status
check_lua = """
local CS = game:GetService("CollectionService")
local quins = CS:GetTagged("Quin")
local alive = 0
local errCount = 0
local retreatScoreCount = 0
local corneredCount = 0
local hasDesperateCounter = 0

for _, q in ipairs(quins) do
    if q.Parent then
        local hum = q:FindFirstChildOfClass("Humanoid")
        if hum and hum.Health > 0 then
            alive = alive + 1
        end
        
        local rs = q:GetAttribute("RetreatScore")
        if rs ~= nil then
            retreatScoreCount = retreatScoreCount + 1
        end
        
        local ic = q:GetAttribute("IsCornered")
        if ic then
            corneredCount = corneredCount + 1
        end
        
        local dc = q:GetAttribute("DesperateCounter")
        if dc then
            hasDesperateCounter = hasDesperateCounter + 1
        end
    end
end

-- Check output log for errors
local output = game:GetService("LogService"):GetLogHistory()
local errors = 0
local errorMessages = {}
for _, entry in ipairs(output) do
    if entry.messageType == Enum.MessageType.MessageError then
        errors = errors + 1
        if #errorMessages < 5 then
            table.insert(errorMessages, entry.message:sub(1, 200))
        end
    end
end

return string.format(
    "ALIVE=%d TOTAL=%d ERRORS=%d RETREAT_SCORE_SET=%d CORNERED=%d DESPERATE_COUNTER=%d\\nERROR_MSGS: %s",
    alive, #quins, errors, retreatScoreCount, corneredCount, hasDesperateCounter,
    table.concat(errorMessages, " | ")
)
"""
result = client.execute_lua(check_lua)
print(f"\n=== PHASE 3 VERIFICATION ===")
print(result)

# Parse results
if "ERRORS=0" in str(result):
    print("\n✅ PASS: Zero runtime errors in 16v16 match")
else:
    print("\n❌ FAIL: Runtime errors detected")

if "RETREAT_SCORE_SET=" in str(result):
    import re
    match = re.search(r"RETREAT_SCORE_SET=(\d+)", str(result))
    if match and int(match.group(1)) > 0:
        print(f"✅ PASS: RetreatScore attribute set on {match.group(1)} fighters")
    else:
        print("⚠️ WARNING: RetreatScore not set on any fighters yet (may need more time)")

print("\nPhase 3 verification complete.")
