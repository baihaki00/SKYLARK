import os
import sys

sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..")))
from Tools.Utilities.roblox_client import RobloxStudioClient

client = RobloxStudioClient()
code = """
local SSS = game:GetService("ServerScriptService")
local RS = game:GetService("ReplicatedStorage")
local QuinSpawner = require(SSS.QuinSpawner)
local TP = require(RS.QuinCore.Modules.TacticalPerception)
local DS = require(RS.QuinCore.Modules.DecisionSystem)
local CC = require(RS.QuinCore.CombatConfig)

local q = QuinSpawner.spawn("TypeC", Vector3.new(0, 2, 0), "TeamBeta")
local h = q:FindFirstChildOfClass("Humanoid")
h.Health = 25
q:SetAttribute("Pers_RetreatTendency", 0.90)

local ally1 = QuinSpawner.spawn("TypeA", Vector3.new(-8, 2, 30), "TeamBeta")
local ally2 = QuinSpawner.spawn("TypeB", Vector3.new(8, 2, 30), "TeamBeta")
local enemy = QuinSpawner.spawn("TypeD", Vector3.new(0, 2, -35), "TeamAlpha")

local pState = TP.evaluate(q)
local bestAction, tacticalState, scores = DS.evaluateAction(q, pState, 35)

q:Destroy()
ally1:Destroy()
ally2:Destroy()
enemy:Destroy()

return game:GetService("HttpService"):JSONEncode({
    bestAction = bestAction,
    scores = scores,
    hpRatio = pState.ownHealthRatio,
    conf = pState.currentConfidence,
    escapeFeas = pState.EscapeFeasibility,
    isLastStand = q:GetAttribute("LastStandMode"),
    critHealth = CC.RetreatCriticalHealth,
    confThresh = CC.RetreatConfidenceThreshold
})
"""
res = client.execute_luau(code, datamodel_type="Server")
print(res.get("result", {}).get("content", [{}])[0].get("text", "{}"))
