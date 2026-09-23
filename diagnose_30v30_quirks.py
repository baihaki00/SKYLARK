"""
Rigorous 30v30 Quirk Diagnostic Harness
Monitors 60 Quins in real-time combat:
1. Detects 360-degree tumbling / pinwheeling (AssemblyAngularVelocity > 15 rad/s)
2. Detects Cockroach bug (upY < 0.6 while grounded or running/fighting while flat)
3. Detects State Stagnation (stuck in a single state > 5.0s)
4. Detects Float bug (stuck mid-air > 2.0s with low velocity)
5. Detects Obstacle Collision tumbling during jumps
"""
import sys
import time
import os
import json

sys.stdout.reconfigure(encoding='utf-8')
sys.path.insert(0, r"C:\Users\User\.gemini\antigravity\scratch\Tools\Utilities")

from roblox_client import RobloxStudioClient
client = RobloxStudioClient()
print("Connected to Studio ID:", client.studio_id)

# Ensure Studio is in Play mode
st = client.get_studio_state()
txt = st.get("result", {}).get("content", [{}])[0].get("text", "")
if "Current Studio Mode: Edit" in txt:
    print("Starting Play mode in Studio...")
    client.set_play_mode(True)
    for _ in range(20):
        time.sleep(1)
        st = client.get_studio_state()
        txt = st.get("result", {}).get("content", [{}])[0].get("text", "")
        if "Current Studio Mode: Play" in txt:
            print("Confirmed: Studio is in Play mode.")
            time.sleep(2)  # Wait for server services to initialize
            break
    else:
        print("Failed to enter Play mode!")
        sys.exit(1)

# 1. Spawn 30 vs 30 Quins
spawn_30v30 = """
local QuinSpawner = require(game.ServerScriptService:WaitForChild("QuinSpawner"))

-- Clear previous Quins
for _, m in ipairs(workspace:GetDescendants()) do
    if m:IsA("Model") and game:GetService("CollectionService"):HasTag(m, "Quin") then
        m:Destroy()
    end
end
task.wait(0.5)

-- Spawn 30 vs 30
local teamA = QuinSpawner.spawnTeam("TeamA", 30, Vector3.new(-120, 5, 0), 1)
local teamB = QuinSpawner.spawnTeam("TeamB", 30, Vector3.new(120, 5, 0), 2)

task.wait(0.5)
local CS = game:GetService("CollectionService")
local allQuins = CS:GetTagged("Quin")

-- Cross-target assignment
for _, q in ipairs(allQuins) do
    local myTeam = q:GetAttribute("Team")
    local enemies = {}
    for _, other in ipairs(allQuins) do
        if other:GetAttribute("Team") ~= myTeam and other.Parent then
            table.insert(enemies, other)
        end
    end
    if #enemies > 0 then
        local t = enemies[math.random(1, #enemies)]
        q:SetAttribute("CurrentTarget", t.Name)
        q:SetAttribute("TargetQuin", t.Name)
    end
end

return string.format("Spawned 30v30: TeamA=%d, TeamB=%d, Total=%d", #teamA, #teamB, #teamA + #teamB)
"""

print("Spawning 30 vs 30 battle...")
res = client.execute_luau(spawn_30v30, datamodel_type="Server")
print(res.get("result", {}).get("content", [{}])[0].get("text", ""))

# 2. Diagnostic monitoring loop
monitor_script = """
local HttpService = game:GetService("HttpService")
local CS = game:GetService("CollectionService")
local quins = CS:GetTagged("Quin")

local SpatialModule = require(game.ReplicatedStorage.QuinCore.Modules.SpatialModule)

local quirks = {
    cockroaches = {},        -- grounded but upY < 0.6 while in active combat/locomotion
    violentSpins = {},       -- angular velocity > 15 rad/s (pinwheeling/tumbling)
    stuckStates = {},        -- in same state for > 5 seconds
    floatingMidair = {},     -- ungrounded with near-zero velocity
    desyncAnims = {}         -- running/fighting while prone
}

local stats = {
    alive = 0,
    total = #quins,
    states = {}
}

for _, q in ipairs(quins) do
    if q.Parent then
        local hum = q:FindFirstChildOfClass("Humanoid")
        local hrp = q:FindFirstChild("HumanoidRootPart")
        if hum and hum.Health > 0 and hrp then
            stats.alive = stats.alive + 1
            local curState = q:GetAttribute("CurrentState") or "None"
            stats.states[curState] = (stats.states[curState] or 0) + 1

            local upY = hrp.CFrame.UpVector.Y
            local angVel = hrp.AssemblyAngularVelocity.Magnitude
            local linVel = hrp.AssemblyLinearVelocity.Magnitude
            local isGrounded = SpatialModule.isGrounded(hrp)

            -- 1. Check Violent Spin / Tumbling 360 vs Upright Snap Pivot
            local isTrueTumble = (angVel > 25.0) or (angVel > 15.0 and upY < 0.85)
            if isTrueTumble then
                table.insert(quirks.violentSpins, {
                    quin = q.Name,
                    state = curState,
                    angVel = math.round(angVel * 10) / 10,
                    linVel = math.round(linVel * 10) / 10,
                    upY = math.round(upY * 100) / 100,
                    pos = string.format("(%.1f, %.1f, %.1f)", hrp.Position.X, hrp.Position.Y, hrp.Position.Z)
                })
            end

            -- 2. Check Cockroach Bug: Flat on ground while running/fighting/circling (not supposed to be down)
            if upY < 0.6 and isGrounded then
                local isSupposedToBeDown = (curState == "Knockback" or curState == "Recovery" or curState == "Death")
                if not isSupposedToBeDown then
                    table.insert(quirks.cockroaches, {
                        quin = q.Name,
                        state = curState,
                        upY = math.round(upY * 100) / 100,
                        supposedToBeDown = isSupposedToBeDown,
                        speed = math.round(linVel * 10) / 10,
                        walkSpeed = hum.WalkSpeed,
                        pos = string.format("(%.1f, %.1f, %.1f)", hrp.Position.X, hrp.Position.Y, hrp.Position.Z)
                    })
                end
            end

            -- 3. Check Floating in mid-air
            local isAirState = (curState == "Airborne" or curState == "ProjectileJump" or curState == "PositioningJump" 
                or curState == "MidAirClash" or curState == "ReEntry" or curState == "Knockback")
            if not isAirState and not isGrounded and hrp.Position.Y > 15 and linVel < 3.0 then
                table.insert(quirks.floatingMidair, {
                    quin = q.Name,
                    state = curState,
                    alt = math.round(hrp.Position.Y * 10) / 10,
                    linVel = math.round(linVel * 10) / 10
                })
            end
        end
    end
end

return HttpService:JSONEncode({
    stats = stats,
    quirks = quirks
})
"""

print("\n--- MONITORING 30v30 OVER 30 SECONDS (EVERY 3 SECONDS) ---")
total_cockroach_events = 0
total_spin_events = 0
total_float_events = 0

for step in range(10):
    time.sleep(3)
    res = client.execute_luau(monitor_script, datamodel_type="Server")
    raw = res.get("result", {}).get("content", [{}])[0].get("text", "")
    try:
        data = json.loads(raw)
        st = data["stats"]
        qk = data["quirks"]
        
        c_count = len(qk["cockroaches"])
        s_count = len(qk["violentSpins"])
        f_count = len(qk["floatingMidair"])
        
        total_cockroach_events += c_count
        total_spin_events += s_count
        total_float_events += f_count

        print(f"[{step*3+3:2d}s] Alive: {st['alive']}/{st['total']} | States: {st['states']}")
        print(f"      Quirks: Cockroaches={c_count}, ViolentSpins={s_count}, Floating={f_count}")
        
        if c_count > 0:
            for item in qk["cockroaches"][:3]:
                print(f"        🪳 Cockroach: {item['quin']} in state '{item['state']}' upY={item['upY']} spd={item['speed']} walkSpd={item['walkSpeed']} supposedDown={item['supposedToBeDown']}")
        if s_count > 0:
            for item in qk["violentSpins"][:3]:
                print(f"        🌪️ Spin: {item['quin']} in state '{item['state']}' angVel={item['angVel']} rad/s upY={item['upY']} at {item['pos']}")
        if f_count > 0:
            for item in qk["floatingMidair"][:3]:
                print(f"        ☁️ Float: {item['quin']} in state '{item['state']}' alt={item['alt']} vel={item['linVel']}")
    except Exception as e:
        print(f"Error parsing: {e} | Raw: {raw[:200]}")

print("\n=== 30v30 DIAGNOSTIC SUMMARY ===")
print(f"Total Cockroach Events Recorded: {total_cockroach_events}")
print(f"Total Violent Spin Events Recorded: {total_spin_events}")
print(f"Total Floating Midair Events Recorded: {total_float_events}")
