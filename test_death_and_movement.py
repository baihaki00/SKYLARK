from Tools.Utilities.roblox_client import RobloxStudioClient
import time

client = RobloxStudioClient()

# Test 1: Verify death animation and DeathType classification live
code_death_test = """
local CollectionService = game:GetService("CollectionService")
local DamageModule = require(game:GetService("ReplicatedStorage").QuinCore.Modules.DamageModule)

local quins = CollectionService:GetTagged("Quin")
if #quins < 2 then
    return "Error: Need at least 2 Quins for death test, found " .. #quins
end

local victim = quins[1]
local attacker = quins[2]
local victimHum = victim:FindFirstChildOfClass("Humanoid")

if not victimHum or victimHum.Health <= 0 then
    victim = quins[2]
    attacker = quins[1]
    victimHum = victim:FindFirstChildOfClass("Humanoid")
end

-- Set victim health low and execute decisive blow
victimHum.Health = 15
local success, isKill, hitType = DamageModule.apply(attacker, victim, {
    damage = 30,
    isFinisher = true,
    knockbackForce = 50,
})

local deathType = victim:GetAttribute("DeathType")
local currentState = victim:GetAttribute("CurrentState")

-- Check playing animations on victim
local victimAnims = {}
for _, t in ipairs(victimHum:GetPlayingAnimationTracks()) do
    if t.WeightCurrent > 0.05 then
        table.insert(victimAnims, t.Animation and t.Animation.AnimationId or "unknown")
    end
end

return string.format("Victim: %s | isKill: %s | DeathType: %s | State: %s | Anims: %s", 
    victim.Name, tostring(isKill), tostring(deathType), tostring(currentState), table.concat(victimAnims, ", "))
"""

res = client.execute_luau(code_death_test, "Server")
out1 = res.get("result", {}).get("content", [{}])[0].get("text", "")
print("TEST 1 - Lethal Blow & Death Classification:")
print(out1)

# Wait 1.3s for impact delay and check DeathFadeAlpha
time.sleep(1.4)

code_fade_check = """
local CollectionService = game:GetService("CollectionService")
local results = {}
for _, q in ipairs(workspace:GetDescendants()) do
    if q:IsA("Model") and q:GetAttribute("DeathFadeAlpha") ~= nil then
        table.insert(results, string.format("Model: %s | FadeAlpha: %.2f | State: %s", 
            q.Name, q:GetAttribute("DeathFadeAlpha") or 0, tostring(q:GetAttribute("CurrentState"))))
    end
end
return #results > 0 and table.concat(results, "\\n") or "No dying models with DeathFadeAlpha found yet"
"""

res = client.execute_luau(code_fade_check, "Server")
out2 = res.get("result", {}).get("content", [{}])[0].get("text", "")
print("\nTEST 2 - DeathFadeAlpha Ramp Check:")
print(out2)

client.close()
