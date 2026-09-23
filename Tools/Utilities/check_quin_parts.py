import sys
import json
import os
sys.path.insert(0, r"C:\Users\User\.gemini\antigravity\scratch\Tools\Utilities")
from roblox_client import RobloxStudioClient

client = RobloxStudioClient()
code = """
local SSS = game:GetService("ServerScriptService")
local QuinSpawner = require(SSS.QuinSpawner)
local q = QuinSpawner.spawn("TypeA", Vector3.new(0, 2.05, 0), "TeamAlpha")
local parts = {}
for _, d in ipairs(q:GetDescendants()) do
    if d:IsA("BasePart") or d:IsA("MeshPart") then
        table.insert(parts, d.ClassName .. ": " .. d.Name .. " (Trans=" .. d.Transparency .. ")")
    end
end
return game:GetService("HttpService"):JSONEncode(parts)
"""
res = client.execute_luau(code, datamodel_type="Server")
raw_text = res.get("result", {}).get("content", [{}])[0].get("text", "")
print("Quin Parts:", raw_text)
client.close()
