import os
import sys
import json

sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..")))
from Tools.Utilities.roblox_client import RobloxStudioClient

client = RobloxStudioClient()
code = """
local SSS = game:GetService("ServerScriptService")
local RS = game:GetService("ReplicatedStorage")
local QuinSpawner = require(SSS.QuinSpawner)
local TP = require(RS.QuinCore.Modules.TacticalPerception)
local DS = require(RS.QuinCore.Modules.DecisionSystem)

local q = QuinSpawner.spawn("TypeC", Vector3.new(0, 2, 0), "TeamBeta")
local h = q:FindFirstChildOfClass("Humanoid")
h.Health = 25
task.wait(0.25)
local hAfterWait = h.Health

local ally = QuinSpawner.spawn("TypeA", Vector3.new(0, 2, 30), "TeamBeta")
local enemy = QuinSpawner.spawn("TypeD", Vector3.new(0, 2, -35), "TeamAlpha")

local pState1 = TP.evaluate(q)
local act1, _, sc1 = DS.evaluateAction(q, pState1, 35)

h.Health = 25
local pState2 = TP.evaluate(q)
local act2, _, sc2 = DS.evaluateAction(q, pState2, 35)

q:Destroy()
ally:Destroy()
enemy:Destroy()

return game:GetService("HttpService"):JSONEncode({
    hAfterWait = hAfterWait,
    maxH = h.MaxHealth,
    pState1_hp = pState1.SelfHealthPercent,
    sc1_retreat = sc1["Retreat"],
    act1 = act1,
    pState2_hp = pState2.SelfHealthPercent,
    sc2_retreat = sc2["Retreat"],
    act2 = act2,
    all_sc2 = sc2
})
"""
res = client.execute_luau(code, datamodel_type="Server")
print(res.get("result", {}).get("content", [{}])[0].get("text", "{}"))
